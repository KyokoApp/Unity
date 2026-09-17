class_name TerrainChunkStreamer
extends Node3D

## ============================================================
## TERRAIN CHUNK STREAMER — memuat & membuang chunk terrain
## mengikuti karakter. (Port dari TerrainChunkStreamer.cs.)
##
## Urutan pemuatan memakai WorldData.chunk_plan() yang sudah diuji
## paritas terhadap JS — jangan mengurutkan dengan cara lain.
##
## DUA PEKERJAAN, DUA THREAD (sama seperti versi Unity):
##   * Membangun chunk (sample terrain_h + pewarnaan + indeks)
##     terukur 2,0-4,6 ms di komputer pada quads=32 — di HP bisa
##     beberapa kali lipat, cukup untuk menghabiskan budget frame.
##     Di sini ia jalan di WORKER THREAD: TerrainMesh.build murni
##     (Packed*Array polos, tanpa RenderingServer, tanpa state
##     statis mutable), hasil diserahkan lewat antrean ber-mutex.
##   * Yang TETAP di main thread: ArrayMesh.add_surface_from_arrays
##     (~0,3 ms), dibatasi max_uploads_per_frame.
##
## set_quality membangun ulang semuanya pada resolusi baru.
##
## Streamer ini juga MENAYANGKAN props WorldScatter (pohon/batu
## deterministik per chunk) — tahap yang di repo Unity masih
## menunggu (Tahap 4). Penempatan persis hasil WorldScatter.build
## yang sudah diuji paritas-nya, plus collider lingkaran yang
## dibaca character_motor (dorong-keluar XZ).
## ============================================================

signal chunks_changed

@export var target: Node3D
@export_group("Streaming")
@export_range(1, 3) var stream_radius: int = 2
## Resolusi grid per chunk. 32 = 8 m per segitiga. Jangan beda-beda
## antar chunk: resolusi tidak seragam menyebabkan retakan.
@export_range(8, 64) var quads_per_chunk: int = TerrainMesh.DEFAULT_QUADS
@export_group("Threading")
@export var use_background_thread: bool = true
@export_range(1, 8) var max_uploads_per_frame: int = 2
@export_range(1, 4) var max_builds_per_frame: int = 1
@export_group("Tampilan")
## Material terrain. Kosong = dibuat dari shaders/aurelia_terrain.
@export var terrain_material: Material
@export_group("Props")
@export var props_enabled: bool = true

## Berapa banyak job boleh berada di worker sekaligus. Sengaja kecil:
## job yang sudah masuk tidak bisa ditarik kembali; dengan 2, kerja
## basi maksimal ~2 chunk.
const MAX_IN_FLIGHT := 2

## ---- statistik, dibaca perf_hud ----
var active_chunks: int = 0
var queued_chunks: int:
	get: return _pending.size() + _in_flight.size()
var pooled_meshes: int:
	get: return _pool.size()
var total_triangles: int = 0
var total_vertices: int = 0
var last_build_ms: float = 0.0
var last_upload_ms: float = 0.0
var thread_active: bool:
	get: return _worker != null and _worker.is_alive()
var discarded_builds: int = 0
var progress01: float:
	get:
		if _wanted_count <= 0:
			return 1.0
		return clampf(float(_active.size()) / _wanted_count, 0.0, 1.0)

var _active: Dictionary = {}          ## key(int) -> {node, tris, verts, cx, cz}
var _wanted: Dictionary = {}          ## key(int) -> ChunkRef(dict)
var _wanted_count: int = 0
var _pending: Array = []
var _in_flight: Dictionary = {}
var _pool: Array[ArrayMesh] = []
var _holder: Node3D
var _prop_root: Node3D
var _last_cx: int = -2147483648
var _last_cz: int = -2147483648

## ---- worker ----
var _worker: Thread
var _sem := Semaphore.new()
var _mutex := Mutex.new()
var _jobs: Array = []
var _done: Array = []
var _exit_worker := false

## ---- props ----
var _prop_mm: Dictionary = {}         ## kind(int) -> MultiMeshInstance3D
var _prop_sets: Dictionary = {}       ## key(int) -> hasil WorldScatter.build
var _colliders: Array = []            ## {x, z, r} koordinat dunia (near)
var _props_dirty := false
var _resolved: Dictionary = {}        ## cache GfxResolver (bukan per chunk)

const _KEY_STRIDE := 100000

func _key(cx: int, cz: int) -> int:
	return cx * _KEY_STRIDE + cz

func _unkey(k: int) -> Vector2i:
	var cx := int(floor(k / float(_KEY_STRIDE)))
	return Vector2i(cx, k - cx * _KEY_STRIDE)

func _ready() -> void:
	if terrain_material == null:
		var mat := ShaderMaterial.new()
		mat.shader = preload("res://shaders/aurelia_terrain.gdshader") as Shader
		terrain_material = mat

	_holder = Node3D.new()
	_holder.name = "TerrainChunks"
	add_child(_holder)

	refresh_settings()

	if props_enabled:
		_prop_root = Node3D.new()
		_prop_root.name = "WorldProps"
		add_child(_prop_root)
		_build_prop_multimeshes()
	_start_worker()

func _exit_tree() -> void:
	_stop_worker()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_stop_worker()

## Dipanggil quality_applier saat preset berubah; memuat ulang cache
## angka resolve supaya tidak dibaca dari disk per chunk.
func refresh_settings() -> void:
	_resolved = GfxResolver.resolve(SettingsStore.load(), _is_touch())

# ============================================================ worker
func _start_worker() -> void:
	if _worker != null or not use_background_thread:
		return
	_worker = Thread.new()
	_worker.start(_worker_loop)

func _stop_worker() -> void:
	if _worker == null:
		return
	_mutex.lock()
	_exit_worker = true
	_mutex.unlock()
	_sem.post()
	_worker.wait_to_finish()
	_worker = null
	_mutex.lock()
	_exit_worker = false
	_jobs.clear()
	_mutex.unlock()

func _worker_loop() -> void:
	while true:
		_sem.wait()
		_mutex.lock()
		if _exit_worker:
			_mutex.unlock()
			return
		var job = _jobs.pop_front()
		_mutex.unlock()

		if job == null:
			continue
		var t0 := Time.get_ticks_usec()
		var data: Dictionary = TerrainMesh.build(job["cx"], job["cz"], job["quads"])
		var ms := float(Time.get_ticks_usec() - t0) / 1000.0

		_mutex.lock()
		data["key"] = job["key"]
		data["build_ms"] = ms
		_done.append(data)
		_mutex.unlock()

# ============================================================ frame loop
func _process(_delta: float) -> void:
	if target == null:
		return
	var p := target.global_position
	var cx := TerrainMesh.chunk_index(p.x)
	var cz := TerrainMesh.chunk_index(p.z)
	if cx != _last_cx or cz != _last_cz:
		_last_cx = cx
		_last_cz = cz
		_refresh_plan(cx, cz)

	if use_background_thread:
		_feed_worker()
		_drain_results()
	else:
		_build_budgeted_sync()

	_process_props_lazy()

## Jalur sinkron untuk WorldBoot: chunk awal harus ada sebelum loading
## selesai. Dipakai ulang, supaya hasilnya identik dengan permainan.
func stream_now(max_builds: int) -> void:
	if target == null:
		return
	var prev := use_background_thread
	use_background_thread = false
	for i in max_builds:
		var p := target.global_position
		var cx := TerrainMesh.chunk_index(p.x)
		var cz := TerrainMesh.chunk_index(p.z)
		if cx != _last_cx or cz != _last_cz or _active.is_empty():
			_last_cx = cx
			_last_cz = cz
			_refresh_plan(cx, cz)
		_build_budgeted_sync()
		active_chunks = _active.size()
		if _pending.is_empty() and _in_flight.is_empty():
			break
	use_background_thread = prev

func _refresh_plan(cx: int, cz: int) -> void:
	var plan := WorldData.chunk_plan(cx * WorldData.CHUNK_SIZE + WorldData.CHUNK_SIZE * 0.5,
									 cz * WorldData.CHUNK_SIZE + WorldData.CHUNK_SIZE * 0.5,
									 stream_radius)

	_wanted.clear()
	for c in plan:
		if TerrainMesh.chunk_in_world(c["cx"], c["cz"]):
			_wanted[_key(c["cx"], c["cz"])] = c
	_wanted_count = _wanted.size()

	# buang yang sudah tidak diminta
	var stale := []
	for k in _active.keys():
		if not _wanted.has(k):
			stale.append(k)
	for k in stale:
		_release(k)

	# Antrekan yang baru, mengikuti urutan chunk_plan (terdekat dulu).
	_pending.clear()
	for k in _wanted.keys():
		if not _active.has(k) and not _in_flight.has(k):
			_pending.append(k)

func _feed_worker() -> void:
	while _in_flight.size() < MAX_IN_FLIGHT and not _pending.is_empty():
		var k: int = _pending.pop_front()
		var cc := _unkey(k)
		_in_flight[k] = true
		_mutex.lock()
		_jobs.append({"key": k, "cx": cc.x, "cz": cc.y, "quads": quads_per_chunk})
		_mutex.unlock()
		_sem.post()

func _drain_results() -> void:
	var uploads := 0
	_mutex.lock()
	var batch := _done.duplicate()
	_done.clear()
	_mutex.unlock()

	for d in batch:
		_in_flight.erase(d["key"])

		# Chunk di luar dunia -> build {} -> buang diam-diam.
		# Buang juga hasil kalau quads berubah (set_quality) atau chunk
		# sudah tidak diminta; belum ada Mesh yang perlu di-release.
		var unusable: bool = (not d.has("quads")) or int(d["quads"]) != quads_per_chunk \
			or (not _wanted.has(d["key"])) or _active.has(d["key"])
		if unusable:
			if d.has("quads") and _wanted.has(d["key"]) and not _active.has(d["key"]):
				_pending.append(d["key"])   # masih dibutuhkan: antre lagi
			elif d.has("quads"):
				discarded_builds += 1
			continue

		if uploads >= max_uploads_per_frame:
			_pending.append(d["key"])
			continue

		last_build_ms = d.get("build_ms", 0.0)
		_upload(d["key"], d)
		uploads += 1

func _build_budgeted_sync() -> void:
	var i := 0
	while i < max_builds_per_frame and not _pending.is_empty():
		var k: int = _pending.pop_front()
		if _active.has(k):
			continue
		var cc := _unkey(k)

		var t0 := Time.get_ticks_usec()
		var data := TerrainMesh.build(cc.x, cc.y, quads_per_chunk)
		if data.is_empty():
			continue
		last_build_ms = float(Time.get_ticks_usec() - t0) / 1000.0
		_upload(k, data)
		i += 1

# ============================================================ upload
func _upload(key: int, d: Dictionary) -> void:
	var cc := _unkey(key)

	var t0 := Time.get_ticks_usec()
	var mesh: ArrayMesh
	if not _pool.is_empty():
		mesh = _pool.pop_back()
		mesh.clear_surfaces()
	else:
		mesh = ArrayMesh.new()
	mesh.resource_name = "chunk_%d_%d_q%d" % [cc.x, cc.y, quads_per_chunk]
	_fill_mesh(mesh, d)
	last_upload_ms = float(Time.get_ticks_usec() - t0) / 1000.0

	var node := MeshInstance3D.new()
	node.name = mesh.resource_name
	# verteks sudah dalam koordinat dunia
	node.mesh = mesh
	node.material_override = terrain_material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_holder.add_child(node)
	active_chunks = _active.size() + 1

	_active[key] = {"node": node, "tris": d["triangle_count"], "verts": d["vertex_count"],
					"cx": cc.x, "cz": cc.y}
	total_triangles += d["triangle_count"]
	total_vertices += d["vertex_count"]
	_add_chunk_props(cc.x, cc.y, _wanted[key] != null and _wanted[key]["near"])
	chunks_changed.emit()

func _fill_mesh(mesh: ArrayMesh, d: Dictionary) -> void:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = d["vertices"]
	arrays[Mesh.ARRAY_NORMAL] = d["normals"]
	arrays[Mesh.ARRAY_COLOR] = d["colors"]
	arrays[Mesh.ARRAY_TEX_UV] = d["uvs"]
	arrays[Mesh.ARRAY_INDEX] = d["triangles"]
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	# quads maks 64 -> 65x65 = 4.225 verteks, jauh di bawah batas indeks
	# yang dipakai Godot; tidak ada format yang perlu diubah.

func _release(key: int) -> void:
	if not _active.has(key):
		return
	var live: Dictionary = _active[key]
	total_triangles -= live["tris"]
	total_vertices -= live["verts"]
	var mesh: ArrayMesh = live["node"].mesh
	if _pool.size() < 64:
		_pool.push_back(mesh)
	live["node"].queue_free()
	_active.erase(key)
	active_chunks = _active.size()
	_remove_chunk_props(live["cx"], live["cz"])
	chunks_changed.emit()

## Dipanggil quality_applier saat tier kualitas berubah.
func set_quality(quads: int, radius: int) -> void:
	quads_per_chunk = clampi(quads, 8, TerrainMesh.MAX_QUADS)
	stream_radius = clampi(radius, 1, 3)
	refresh_settings()
	for k in _active.keys():
		_release(k)
	_pending.clear()
	total_triangles = 0
	total_vertices = 0
	_last_cx = -2147483648
	_last_cz = -2147483648

# ============================================================ props (Tahap 4)
func _build_prop_multimeshes() -> void:
	var meshes := {
		WorldScatter.PROP_TRUNK: _make_trunk_mesh(),
		WorldScatter.PROP_LEAF: _make_leaf_mesh(),
		WorldScatter.PROP_PINE: _make_pine_mesh(),
		WorldScatter.PROP_ROCK: _make_rock_mesh(),
	}
	var shader := preload("res://shaders/aurelia_prop.gdshader") as Shader
	# Warna dasar per jenis (batang cokelat, batu abu); kanopi/pinus
	# putih karena warna aslinya datang dari instance (region.foliage),
	# persis scheme JS: trunk tidak diwarnai, daun memakai foliage.
	var tints := {
		WorldScatter.PROP_TRUNK: Color(0.38, 0.26, 0.16, 1.0),
		WorldScatter.PROP_LEAF: Color(1.0, 1.0, 1.0, 1.0),
		WorldScatter.PROP_PINE: Color(1.0, 1.0, 1.0, 1.0),
		WorldScatter.PROP_ROCK: Color(0.52, 0.50, 0.47, 1.0),
	}
	for kind in meshes:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = meshes[kind]
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Props_%d" % kind
		mmi.multimesh = mm
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("albedo_tint", tints[kind])
		mmi.material_override = mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		_prop_root.add_child(mmi)
		_prop_mm[kind] = mmi

func _add_chunk_props(cx: int, cz: int, near: bool) -> void:
	if not props_enabled or _resolved.is_empty():
		return
	var sc := WorldScatter.build(cx, cz, near,
			int(_resolved["props_near"]), int(_resolved["props_far"]))
	_prop_sets[_key(cx, cz)] = sc
	for c in sc["colliders"]:
		_colliders.append(c)
	_props_dirty = true

func _remove_chunk_props(cx: int, cz: int) -> void:
	if not props_enabled:
		return
	var k := _key(cx, cz)
	if not _prop_sets.has(k):
		return
	_prop_sets.erase(k)
	_rebuild_colliders()
	_props_dirty = true

func _rebuild_colliders() -> void:
	_colliders.clear()
	for k in _prop_sets:
		for c in _prop_sets[k]["colliders"]:
			_colliders.append(c)

## Lingkaran collider props untuk character_motor (dorong-keluar XZ).
func colliders() -> Array:
	return _colliders

func _process_props_lazy() -> void:
	if not _props_dirty or _prop_mm.is_empty():
		return
	_props_dirty = false
	var per_kind: Dictionary = {
		WorldScatter.PROP_TRUNK: [], WorldScatter.PROP_LEAF: [],
		WorldScatter.PROP_PINE: [], WorldScatter.PROP_ROCK: []}
	for k in _prop_sets:
		var propset: Dictionary = _prop_sets[k]
		var cc := _unkey(k)
		var ox := cc.x * WorldData.CHUNK_SIZE
		var oz := cc.y * WorldData.CHUNK_SIZE
		for p in propset["props"]:
			per_kind[p["kind"]].append(p)
			# Simpan offset dunia supaya transform final benar.
			per_kind[p["kind"]][-1]["_ox"] = ox
			per_kind[p["kind"]][-1]["_oz"] = oz
	for kind in _prop_mm:
		var list: Array = per_kind[kind]
		var mmi: MultiMeshInstance3D = _prop_mm[kind]
		var mm := mmi.multimesh
		mm.instance_count = list.size()
		for i in list.size():
			var p: Dictionary = list[i]
			var xf := Transform3D(
				Basis.from_euler(Vector3(0, p["yaw"], 0)).scaled(
					Vector3(p["sx"], p["sy"], p["sz"])),
				Vector3(p["_ox"] + p["x"], p["y"], p["_oz"] + p["z"]))
			mm.set_instance_transform(i, xf)
			var col := Color.WHITE
			if p["has_foliage"]:
				var f: int = p["foliage"]
				col = Color(float((f >> 16) & 255) / 255.0,
							float((f >> 8) & 255) / 255.0,
							float(f & 255) / 255.0)
			mm.set_instance_color(i, col)

## Dipanggil WorldBoot supaya props siap sebelum loading selesai.
func populate_props_now() -> void:
	_props_dirty = true
	_process_props_lazy()

# ============================================================ mesh props
## Semua mesh satuan; skala datang dari prop (sx, sy, sz).
func _make_trunk_mesh() -> Mesh:
	var cyl := CylinderMesh.new()   # batang pohon kekar
	cyl.top_radius = 0.45
	cyl.bottom_radius = 0.55
	cyl.height = 7.0
	cyl.radial_segments = 6
	cyl.rings = 1
	return cyl

func _make_leaf_mesh() -> Mesh:
	var sp := SphereMesh.new()      # kanopi daun (warna per region)
	sp.radius = 4.5
	sp.height = 9.0
	sp.radial_segments = 6
	sp.rings = 3
	return sp

func _make_pine_mesh() -> Mesh:
	var cone := CylinderMesh.new()  # pinus frost/highlands
	cone.top_radius = 0.0
	cone.bottom_radius = 3.6
	cone.height = 12.0
	cone.radial_segments = 6
	cone.rings = 2
	return cone

func _make_rock_mesh() -> Mesh:
	var sp := SphereMesh.new()      # batu/kristal kasar
	sp.radius = 1.0
	sp.height = 1.6
	sp.radial_segments = 5
	sp.rings = 2
	return sp

func _is_touch() -> bool:
	return DisplayServer.is_touchscreen_available()
