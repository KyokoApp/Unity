extends Node3D
## World: mengorkestrasi pulau — chunk terrain streaming + LOD + collision,
## air toon dengan peta pantai, langit + siklus siang-malam ringan, dan
## pemasangan pack props. Semua query tinggi lewat `island` (thread-safe).

signal gen_progress(pct, text)

const IslandScript := preload("res://packs/world_terrain/island.gd")
const ChunkScript := preload("res://packs/world_terrain/terrain_chunk.gd")
const Materials := preload("res://packs/shaders_materials/materials.gd")
const WATER_SHADER := preload("res://packs/shaders_materials/water.gdshader")
const SKY_SHADER := preload("res://packs/shaders_materials/sky.gdshader")
const FOREST_SCENE := "res://packs/world_props_forest/forest.tscn"
const BEACH_SCENE := "res://packs/world_props_beach/beach.tscn"
const CHUNK_SIZE := 67.0
const GRID := 4
const WORLD_SEED := 20260919
const WORLD_SIZE := 268.0  # diperkecil 3x laggi (keluhan: masih kebesaran)
const EDITS_PATH := "user://terrain_edits.dat"

var island
var terr_mat: Material
var chunks := {}          # key "cx,cz" -> Chunk
var building := {}        # key -> lod yang sedang dibangun
var results := []         # antrian hasil worker
var _rm := Mutex.new()
var _stream_timer := 0.0
var _progress_done := 0
var _progress_total := 1
var _initial_center := Vector2i.ZERO
var player: Node3D
var sun: DirectionalLight3D
var world_env: WorldEnvironment
var sky_mat: ShaderMaterial
var water: MeshInstance3D
var time_of_day := 16.4   # jam (mulai sore yang adem — sesuai permintaan)
const DAY_LENGTH := 420.0 # detik untuk 24 jam penuh
var chunk_rings := 6
var forest_pack: Node
var beach_pack: Node
var interactables := []
var quality_ref
var _seeded := false
var faceted := false   # gaya low-poly "segi datar" (Mode Edit / pengaturan)

## Ganti gaya render terrain (halus ↔ segi datar) + bangun ulang semua chunk.
func set_faceted(on: bool) -> void:
	if on == faceted:
		return
	faceted = on
	for k in chunks.keys():
		var parts: PackedStringArray = k.split(",")
		var c := Vector2i(int(parts[0]), int(parts[1]))
		_rebuild_chunk_now(c.x, c.y)
	_wtrace("gaya terrain: " + ("segi datar (low-poly)" if on else "halus"))

func _ready() -> void:
	name = "World"

# ---------------- boot ----------------

var _root_ref: Node
var _stat_chunks := 0
var _stat_verts := 0
var _stat_nan := 0
var _stat_hmin := 1e9
var _stat_hmax := -1e9

func _wtrace(msg: String) -> void:
	if _root_ref and _root_ref.has_method("_trace"):
		_root_ref._trace(msg)

# ---------------- mode WORLD STATIS (Gravity Falls) ----------------
const STATIC_WORLD_PATH := "res://packs/world_terrain/gravity_falls.glb"
var static_mode := false
var _static_ready := false
var _gcell := 4.0                      # meter per sel grid akselerasi
var _gbuckets := {}                    # "cx,cz" -> PackedInt32Array indeks segitiga
var _gtris := PackedFloat32Array()     # 9 float per segitiga (x,y,z)*3

func generate_async(_root: Node) -> void:
	_root_ref = _root
	_report(0.0, "Membangun pulau…")
	island = IslandScript.new(WORLD_SEED, WORLD_SIZE)
	_load_edits(island)
	_wtrace("pulau: h(0,0)=%.1f h(120,60)=%.1f" % [island.height_at(0, 0), island.height_at(120, 60)])
	_progress_done = 0
	_progress_total = 1 + 1 + 25 + 2  # shore map + laut + chunk awal + 2 pack props
	terr_mat = Materials.toon_vertex_color(false, 0.012, true)
	_setup_environment()
	await _gen_shore_map_async()
	_report_step("Menyiapkan lautan…")
	_setup_water()
	await _initial_chunks()
	_wtrace("terrain: %d chunk, %dv, NaN=%d, h=[%.1f..%.1f]" % [
		_stat_chunks, _stat_verts, _stat_nan, _stat_hmin, _stat_hmax])
	await _load_prop_packs()
	_report(1.0, "Dunia siap")
	# Gravity Falls dimuat ASINKRON di latar — never non-blocking boot →
	# kalau apa pun gagal di tahap ini, pemain tetap di pulau (anti blue screen)
	if ResourceLoader.exists(STATIC_WORLD_PATH):
		var err := ResourceLoader.load_threaded_request(STATIC_WORLD_PATH, "", false)
		if err == OK:
			_static_queue = true
			_wtrace("gravity falls dimuat di latar belakang…")
		else:
			_wtrace("gravity falls: request gagal (%d) — pakai pulau" % int(err))

var _static_queue := false

# sektor poligon yang dianggap non-kolisi/outline (langit, bayangan tempel, logo)
const STATIC_SKIP := ["skybox", "shadow", "logo"]

func _scene_aabb(node: Node) -> AABB:
	var boxes := []
	_scene_aabb_walk(node, Transform3D.IDENTITY, boxes)
	var out := AABB()
	for i in range(boxes.size()):
		out = boxes[i] if i == 0 else out.merge(boxes[i])
	return out

static func _scene_aabb_walk(node: Node, xf: Transform3D, boxes: Array) -> void:
	if node is MeshInstance3D and node.mesh != null:
		boxes.append(xf * node.mesh.get_aabb())
	for c in node.get_children():
		var nxf: Transform3D = xf * (c.transform if c is Node3D else Transform3D.IDENTITY)
		_scene_aabb_walk(c, nxf, boxes)

func _build_static_world(res: Resource) -> bool:
	_report_step("Memuat Gravity Falls…")
	if not (res is PackedScene):
		return false
	var scene_root: Node3D = (res as PackedScene).instantiate()
	if scene_root == null:
		return false
	var aabb := _scene_aabb(scene_root)
	if aabb.size.x <= 0.001:
		scene_root.free()
		return false
	# normalisasi: pertahankan skala asli bila sudah wajar (60..480 m), selain itu paksa ~160 m
	var span := maxf(aabb.size.x, aabb.size.z)
	var k := 1.0
	if span < 60.0 or span > 480.0:
		k = 160.0 / span
	var cont := Node3D.new()
	cont.name = "GravityFallsWorld"
	add_child(cont)
	cont.add_child(scene_root)
	cont.scale = Vector3.ONE * k
	cont.position = Vector3(-(aabb.position.x + aabb.size.x * 0.5) * k,
		-aabb.position.y * k,
		-(aabb.position.z + aabb.size.z * 0.5) * k)
	# collision + outline tipis + grid akselerasi tinggi permukaan
	var out_mat = Materials.make_outline(0.008)
	if out_mat == null:
		_wtrace("PERINGATAN: material outline gagal — lanjut tanpa outline")
	var base_xf := cont.transform
	var stats := [0, 0]  # tris_kolisi, tris_walkable
	_static_walk(scene_root, base_xf, out_mat, stats)
	# verifikasi hasil: tanpa permukaan pijakan, world tak bisa dimainkan → fallback
	if int(stats[1]) <= 0 or _gbuckets.is_empty():
		_wtrace("PERINGATAN: tak ada permukaan pijakan di gravity_falls.glb — fallback")
		cont.queue_free()
		return false
	_static_ready = true
	_wtrace("gravity falls: span %dx%dm skala %.2f | kolisi %d segi | jalan %d segi | sel %d" % [
		int(span), int(aabb.size.y), k, int(stats[0]), int(stats[1]), _gbuckets.size()])
	return true

func _static_walk(node: Node, xf: Transform3D, out_mat: Material, stats: Array) -> void:
	var lname := String(node.name).to_lower()
	# 0/300 mencegah rekursi tak berujung: node yang KITA tambahkan (outline/collision) tidak diproses lagi
	if lname.ends_with("_outline") or lname.ends_with("_col"):
		return
	var skip := false
	for s in STATIC_SKIP:
		if lname.contains(s):
			skip = true
			break
	if node is MeshInstance3D and node.mesh != null:
		var mi: MeshInstance3D = node
		if not skip:
			# trimesh collision (digabung dari semua permukaan mesh)
			var sh := mi.mesh.create_trimesh_shape()
			if sh != null:
				var body := StaticBody3D.new()
				body.name = mi.name + "_col"
				var col := CollisionShape3D.new()
				col.shape = sh
				body.add_child(col)
				mi.add_child(body)
				stats[0] += 1
			# outline tipis (hanya mesh bervolume, bukan skybox/shadow transparan)
			var o := MeshInstance3D.new()
			o.mesh = mi.mesh
			o.material_override = out_mat
			o.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			o.name = mi.name + "_outline"
			mi.add_child(o)
			# grid akselerasi: segitiga menghadap atas (bisa dipijak)
			for s in range(mi.mesh.get_surface_count()):
				var arrs := mi.mesh.surface_get_arrays(s)
				var verts: PackedVector3Array = arrs[Mesh.ARRAY_VERTEX]
				var idx: PackedInt32Array = arrs[Mesh.ARRAY_INDEX]
				if verts.is_empty():
					continue
				if idx.is_empty():
					idx = PackedInt32Array(range(verts.size()))
				for t in range(0, idx.size() - 2, 3):
					var a: Vector3 = xf * verts[idx[t]]
					var b: Vector3 = xf * verts[idx[t + 1]]
					var c: Vector3 = xf * verts[idx[t + 2]]
					var n := (b - a).cross(c - a)
					if n.length() < 0.0001 or n.normalized().y < 0.35:
						continue  # bukan permukaan pijakan
					_grid_add_tri(a, b, c)
					stats[1] += 1
	for c2 in node.get_children():
		var nxf: Transform3D = xf * (c2.transform if c2 is Node3D else Transform3D.IDENTITY)
		_static_walk(c2, nxf, out_mat, stats)

func _grid_add_tri(a: Vector3, b: Vector3, c: Vector3) -> void:
	var ti := _gtris.size() / 9
	_gtris.append_array([a.x, a.y, a.z, b.x, b.y, b.z, c.x, c.y, c.z])
	var minx := int(floor(minf(a.x, minf(b.x, c.x)) / _gcell))
	var maxx := int(floor(maxf(a.x, maxf(b.x, c.x)) / _gcell))
	var minz := int(floor(minf(a.z, minf(b.z, c.z)) / _gcell))
	var maxz := int(floor(maxf(a.z, maxf(b.z, c.z)) / _gcell))
	for cz in range(minz, maxz + 1):
		for cx in range(minx, maxx + 1):
			var key := "%d,%d" % [cx, cz]
			if not _gbuckets.has(key):
				_gbuckets[key] = PackedInt32Array()
			var arr: PackedInt32Array = _gbuckets[key]
			arr.append(ti)
			_gbuckets[key] = arr

## Tinggi permukaan pijakan di (x,z): barycentric atas segitiga di sel sekitar (-1000 jika tak ada).
func _static_floor_at(x: float, z: float) -> float:
	var best := -1000.0
	var cx := int(floor(x / _gcell))
	var cz := int(floor(z / _gcell))
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var key := "%d,%d" % [cx + dx, cz + dz]
			if not _gbuckets.has(key):
				continue
			for ti in _gbuckets[key]:
				var o := ti * 9
				var ax: float = _gtris[o]; var ay: float = _gtris[o + 1]; var az: float = _gtris[o + 2]
				var bx: float = _gtris[o + 3]; var by: float = _gtris[o + 4]; var bz: float = _gtris[o + 5]
				var cx2: float = _gtris[o + 6]; var cy: float = _gtris[o + 7]; var cz2: float = _gtris[o + 8]
				# barycentric 2D pada proyeksi xz
				var d := (bz - cz2) * (ax - cx2) + (cx2 - az) * (az - cz2)
				if absf(d) < 0.00001:
					continue
				var w1 := ((bz - cz2) * (x - cx2) + (cx2 - az) * (z - cz2)) / d
				var w2 := ((cz2 - az) * (x - cx2) + (ax - cx2) * (z - cz2)) / d
				var w3 := 1.0 - w1 - w2
				if w1 < -0.0001 or w2 < -0.0001 or w3 < -0.0001:
					continue
				var y := w1 * ay + w2 * by + w3 * cy
				if y > best:
					best = y
	return best

func _report(p: float, t: String) -> void:
	print("[gen] %d%% %s" % [int(p * 100), t])
	gen_progress.emit(clampf(p, 0.0, 1.0), t)

func _report_step(t: String) -> void:
	_progress_done += 1
	print("[gen] %d%% %s" % [int(100.0 * _progress_done / float(_progress_total)), t])
	gen_progress.emit(clampf(_progress_done / float(_progress_total), 0.0, 1.0), t)

# ---------------- lingkungan ----------------

func _setup_environment() -> void:
	world_env = WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sk := Sky.new()
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = SKY_SHADER
	sk.sky_material = sky_mat
	env.sky = sk
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.52, 0.58, 0.58)
	env.ambient_light_energy = 0.60
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.95
	env.fog_enabled = true
	env.fog_light_color = Color(0.56, 0.76, 0.68)
	env.fog_density = 0.0026
	env.fog_sky_affect = 0.3
	world_env.environment = env
	add_child(world_env)

	sun = DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.90, 0.72)
	sun.light_energy = 0.68
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 70.0
	sun.shadow_opacity = 0.32
	sun.directional_shadow_blend_splits = false
	sun.shadow_bias = 0.08
	sun.rotation_degrees = Vector3(-42, -120, 0)
	add_child(sun)
	_apply_daylight()
	if quality_ref:
		quality_ref.sun = sun

func _setup_water() -> void:
	var pm := PlaneMesh.new()
	pm.size = Vector2(WORLD_SIZE * 4.0, WORLD_SIZE * 4.0)
	pm.subdivide_width = 96
	pm.subdivide_depth = 96
	water = MeshInstance3D.new()
	water.mesh = pm
	water.position = Vector3(0, -0.06, 0)
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := ShaderMaterial.new()
	m.shader = WATER_SHADER
	m.set_shader_parameter("world_half", WORLD_SIZE * 0.5)
	if _shore_tex != null:
		m.set_shader_parameter("shore_map", _shore_tex)
	water.material_override = m
	add_child(water)

var _shore_tex: ImageTexture
var _shore_img: Image

func _gen_shore_map_async() -> void:
	_shore_img = Image.create_empty(256, 256, false, Image.FORMAT_R8)
	WorkerThreadPool.add_task(Callable(self, "_task_shore_map"), false, "shore_map")
	while not _shore_ready:
		await get_tree().process_frame
	_report_step("Memetakan garis pantai…")

var _shore_ready := false
var results_mtx := Mutex.new()

func _task_shore_map() -> void:
	var img := _shore_img
	var h := WORLD_SIZE * 0.5
	for j in range(256):
		for i in range(256):
			var x := (i / 255.0) * WORLD_SIZE - h
			var z := (j / 255.0) * WORLD_SIZE - h
			var v: float = clampf((island.height_at(x, z) + 20.0) / 255.0, 0.0, 1.0)
			img.set_pixel(i, j, Color(v, 0, 0))
	call_deferred("_shore_done", img)

func _shore_done(img: Image) -> void:
	_shore_tex = ImageTexture.create_from_image(img)
	_shore_ready = true
	if water and water.material_override:
		water.material_override.set_shader_parameter("shore_map", _shore_tex)

# ---------------- chunk streaming ----------------

func _initial_chunks() -> void:
	var sp = island.find_spawn_point()
	var sc := _chunk_of(sp.x, sp.z)
	_initial_center = sc
	var keys := []
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			var c := Vector2i(sc.x + dx, sc.y + dz)
			if _inside(c):
				keys.append(c)
	keys.sort_custom(func(a, b): return (a - sc).length_squared() < (b - sc).length_squared())
	for c in keys:
		_queue_chunk(c.x, c.y, _lod_for_ring(maxi(abs(c.x - sc.x), abs(c.y - sc.y))), true)
	while true:
		_integrate_results(3)
		if _results_count() == 0 and building.is_empty():
			break
		await get_tree().process_frame
	# collision dekat spawn
	_update_collision_ring(sc, true)

func _results_count() -> int:
	results_mtx.lock()
	var n := results.size()
	results_mtx.unlock()
	return n

func _load_prop_packs() -> void:
	var fp = load(FOREST_SCENE)
	if fp:
		forest_pack = fp.instantiate()
		add_child(forest_pack)
		forest_pack.call("configure", island, self)
	_report_step("Menanam hutan…")
	var bp = load(BEACH_SCENE)
	if bp:
		beach_pack = bp.instantiate()
		add_child(beach_pack)
		beach_pack.call("configure", island, self)
	_report_step("Menata pantai…")
	_seeded = true

func _chunk_of(x: float, z: float) -> Vector2i:
	# offset = GRID/2 (dunia 800m → +4; saat +8 terrain timur tak pernah terbangun
	# → pemain jatuh tembus tanah). WAJIB sinkron dengan GRID_HALF di terrain_chunk.
	return Vector2i(floori(x / CHUNK_SIZE) + GRID / 2, floori(z / CHUNK_SIZE) + GRID / 2)

func _inside(c: Vector2i) -> bool:
	return c.x >= 0 and c.x < GRID and c.y >= 0 and c.y < GRID

func _lod_for_ring(ring: int) -> int:
	if ring <= 1: return 0
	if ring <= 3: return 1
	if ring <= 5: return 2
	return 3

func _key(cx: int, cy: int) -> String:
	return "%d,%d" % [cx, cy]

func _queue_chunk(cx: int, cy: int, lod: int, hi_prio := false) -> void:
	var k := _key(cx, cy)
	if chunks.has(k) and chunks[k].lod == lod:
		return
	if building.has(k) and building[k] == lod:
		return
	building[k] = lod
	WorkerThreadPool.add_task(Callable(self, "_task_build").bind(cx, cy, lod), hi_prio)

func _task_build(cx: int, cy: int, lod: int) -> void:
	var data := ChunkScript.build_mesh_data(island, cx, cy, lod, faceted)
	results_mtx.lock()
	results.append([cx, cy, lod, data])
	results_mtx.unlock()

func _integrate_results(budget: int) -> void:
	results_mtx.lock()
	var n = mini(results.size(), budget)
	var batch := results.slice(0, n)
	results = results.slice(n)
	results_mtx.unlock()
	for r in batch:
		_integrate_chunk(r[0], r[1], r[2], r[3])

func _integrate_chunk(cx: int, cy: int, lod: int, data: Dictionary) -> void:
	var k := _key(cx, cy)
	building.erase(k)
	var chunk: Node3D = chunks.get(k)
	if chunk == null:
		chunk = ChunkScript.new()
		chunk.cx = cx
		chunk.cz = cy
		chunks[k] = chunk
		add_child(chunk)
	chunk.lod = lod
	var mesh := ChunkScript.make_mesh(data)
	chunk.apply_mesh(mesh, terr_mat, data["heights"])
	# statistik diagnostik (terlihat di jejak boot layar HP)
	_stat_chunks += 1
	_stat_verts += int(data.get("stats_v", 0))
	_stat_nan += int(data.get("stats_nan", 0))
	_stat_hmin = minf(_stat_hmin, float(data.get("stats_hmin", 1e9)))
	_stat_hmax = maxf(_stat_hmax, float(data.get("stats_hmax", -1e9)))
	if _initial_pending:
		_report_step("Bangun chunk %d,%d" % [cx, cy])

var _initial_pending := true
var _initial_done := false

func _update_streaming_player_chunk() -> void:
	if player == null or island == null:
		return
	var pc := _chunk_of(player.global_position.x, player.global_position.z)
	var desired := {}
	for dz in range(-chunk_rings, chunk_rings + 1):
		for dx in range(-chunk_rings, chunk_rings + 1):
			var c := Vector2i(pc.x + dx, pc.y + dz)
			if not _inside(c):
				continue
			var ring := maxi(abs(dx), abs(dz))
			desired[_key(c.x, c.y)] = _lod_for_ring(ring)
	# buang chunk di luar ring (+1 margin)
	var to_remove := []
	for k in chunks:
		if not desired.has(k):
			var parts: PackedStringArray = k.split(",")
			var c := Vector2i(int(parts[0]), int(parts[1]))
			if maxi(abs(c.x - pc.x), abs(c.y - pc.y)) > chunk_rings + 1:
				to_remove.append(k)
	for k in to_remove:
		chunks[k].queue_free()
		chunks.erase(k)
	# bangun yang kurang / LOD berubah (urut dari dekat)
	var want := []
	for k in desired:
		var lod: int = desired[k]
		if chunks.has(k) and chunks[k].lod == lod:
			continue
		var parts: PackedStringArray = k.split(",")
		var c := Vector2i(int(parts[0]), int(parts[1]))
		if building.has(k) and building[k] == lod:
			continue
		want.append(c)
	want.sort_custom(func(a, b): return (a - pc).length_squared() < (b - pc).length_squared())
	var queued := 0
	for c in want:
		var lod := _lod_for_ring(maxi(abs(c.x - pc.x), abs(c.y - pc.y)))
		_queue_chunk(c.x, c.y, lod, queued < 4)
		queued += 1
		if queued >= 4:
			break
	_update_collision_ring(pc, false)

func _update_collision_ring(pc: Vector2i, force: bool) -> void:
	for k in chunks:
		var parts: PackedStringArray = k.split(",")
		var c := Vector2i(int(parts[0]), int(parts[1]))
		var near := maxi(abs(c.x - pc.x), abs(c.y - pc.y)) <= 1
		var chunk = chunks[k]
		if near:
			chunk.set_collision(true, island)
		else:
			chunk.set_collision(false, island)

# ---------------- interaksi ----------------

func register_interactable(meta: Dictionary) -> void:
	interactables.append(meta)

func get_nearest_interactable(pos: Vector3, radius: float) -> Dictionary:
	var best := {}
	var bd := radius
	for m in interactables:
		if m.get("taken", false):
			continue
		var d: float = pos.distance_to(m["pos"])
		if d < bd:
			bd = d
			best = m
	return best

func consume_interactable(meta: Dictionary) -> void:
	meta["taken"] = true
	if meta.has("node") and is_instance_valid(meta["node"]):
		meta["node"].call_deferred("queue_free")

# ---------------- API umum ----------------

func set_player(p: Node3D) -> void:
	player = p
	if forest_pack:
		forest_pack.call("set_player", p)
	if beach_pack:
		beach_pack.call("set_player", p)

func find_spawn_point() -> Vector3:
	if static_mode:
		# pusat dunia; jika bukan pijakan, sapu cincin kecil mencari lantai
		for cand in [Vector2(0, 0), Vector2(4, 0), Vector2(-4, 0), Vector2(0, 4), Vector2(0, -4),
				Vector2(8, 8), Vector2(-8, -8), Vector2(8, -8), Vector2(-8, 8)]:
			var fy := _static_floor_at(cand.x, cand.y)
			if fy > -999.0:
				return Vector3(cand.x, fy + 0.25, cand.y)
		return Vector3(0, 1.0, 0)
	return island.find_spawn_point()

func height_at(x: float, z: float) -> float:
	if static_mode:
		return _static_floor_at(x, z)
	return island.height_at(x, z)

func get_island():
	return island

# memuat GLB selesai (thread) → aktivasi; gagal → tetap di pulau (tidak fatal)
func _poll_static_world() -> void:
	if not _static_queue:
		return
	var st := ResourceLoader.load_threaded_get_status(STATIC_WORLD_PATH)
	if st == ResourceLoader.THREAD_LOAD_LOADED:
		_static_queue = false
		_activate_static_world(ResourceLoader.load_threaded_get(STATIC_WORLD_PATH))
	elif st == ResourceLoader.THREAD_LOAD_FAILED or st == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		_static_queue = false
		_wtrace("gravity falls: GAGAL dimuat (status %d) — tetap di pulau" % int(st))

func _activate_static_world(res: Resource) -> void:
	if not (res is PackedScene):
		_wtrace("gravity falls: bukan PackedScene — tetap di pulau")
		return
	_wtrace("gravity falls: membangun world…")
	if _build_static_world(res):
		static_mode = true
		# matikan visual & collision pulau procedural
		for k in chunks:
			chunks[k].visible = false
			for cs in chunks[k].find_children("*", "CollisionShape3D", true, false):
				cs.disabled = true
		if is_instance_valid(water):
			water.visible = false
		if forest_pack:
			forest_pack.visible = false
			forest_pack.set_process(false)
		if beach_pack:
			beach_pack.visible = false
			beach_pack.set_process(false)
		# teleport pemain ke titik pijakan world baru
		if player != null:
			var sp := find_spawn_point()
			player.global_position = sp + Vector3(0, 0.15, 0)
		_wtrace("gravity falls: AKTIF ✓")
	else:
		_wtrace("gravity falls: pembangunan gagal — tetap di pulau")

var _save_edits_t := 0.0

## Terapkan edit dari HUD: mode "raise"/"lower" (sculpt) atau "road" (jalur).
func apply_terrain_edit(p: Vector3, radius: float, amount: float, mode: String) -> void:
	if static_mode or island == null:
		return  # world statis tidak bisa di-sculpt
	var m := "sculpt" if mode in ["raise", "lower"] else "road"
	var amt := amount if mode != "lower" else -amount
	island.edit_apply(p.x, p.z, radius, amt, m)
	var c0 := _chunk_of(p.x - radius, p.z - radius)
	var c1 := _chunk_of(p.x + radius, p.z + radius)
	for cz in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			_rebuild_chunk_now(cx, cz)
	_save_edits_t = 2.0  # simpan pascajeda (debounce) — lihat _process

func _rebuild_chunk_now(cx: int, cz: int) -> void:
	var k := _key(cx, cz)
	if not _inside(Vector2i(cx, cz)) or not chunks.has(k):
		return
	var chunk: Node3D = chunks[k]
	var data := ChunkScript.build_mesh_data(island, cx, cz, chunk.lod, faceted)
	var mesh := ChunkScript.make_mesh(data)
	chunk.apply_mesh(mesh, terr_mat, data["heights"])
	chunk.refresh_collision(island)

func _save_edits() -> void:
	var f := FileAccess.open(EDITS_PATH, FileAccess.WRITE)
	if f:
		f.store_var(island.serialize_edits())
		f.close()

func _load_edits(isl) -> void:
	if not FileAccess.file_exists(EDITS_PATH):
		return
	var f := FileAccess.open(EDITS_PATH, FileAccess.READ)
	if f:
		var d = f.get_var()
		if d is Dictionary:
			isl.load_edits(d)
			_wtrace("edit dunia dimuat (user-edited terrain)")
		f.close()

## Menghapus semua edit dunia (dipanggil dari panel Mode Edit).
func reset_edits() -> void:
	if island == null:
		return
	island._edit_init()
	_save_edits()
	for k in chunks.keys():
		var parts: PackedStringArray = k.split(",")
		var c := Vector2i(int(parts[0]), int(parts[1]))
		_rebuild_chunk_now(c.x, c.y)
	_wtrace("edit dunia direset")

# ---------------- pencahayaan (Mode Edit) ----------------

const SKY_PRESETS := [
	[Color(0.30, 0.74, 0.69), Color(0.62, 0.88, 0.80)],  # 0 siang mint (bawaan)
	[Color(0.18, 0.38, 0.52), Color(0.56, 0.86, 0.78)],  # 1 sore teal
	[Color(0.18, 0.26, 0.44), Color(0.98, 0.60, 0.38)],  # 2 senja peach
	[Color(0.05, 0.09, 0.16), Color(0.16, 0.20, 0.30)],  # 3 malam biru
]
var _lo := {"sun": 1.0, "ambient": 1.0, "fog": 1.0, "sky": -1}

func apply_lighting(d: Dictionary) -> void:
	for kk in d:
		_lo[kk] = d[kk]
	_dl_last = -1.0
	_apply_daylight()

func apply_quality(p: Dictionary) -> void:
	chunk_rings = int(p.chunk_rings)
	if world_env:
		world_env.environment.fog_density = 0.0015 * float(p.fog)
	if forest_pack:
		forest_pack.call("apply_density", float(p.tree_density), float(p.grass_density))
	if beach_pack:
		beach_pack.call("apply_density", float(p.tree_density), float(p.grass_density))

func _process(delta: float) -> void:
	_poll_static_world()
	_integrate_results(2)
	_stream_timer -= delta
	if _stream_timer <= 0.0:
		_stream_timer = 0.4
		if _initial_pending and building.is_empty() and _results_count() == 0:
			_initial_pending = false
			_initial_done = true
		_update_streaming_player_chunk()
	if _save_edits_t > 0.0:
		_save_edits_t -= delta
		if _save_edits_t <= 0.0:
			_save_edits()
	_tick_daynight(delta)

# ---------------- siang-malam ----------------

func _tick_daynight(delta: float) -> void:
	if not _initial_done:
		return
	time_of_day = fmod(time_of_day + delta * 24.0 / DAY_LENGTH, 24.0)
	_apply_daylight()

var _dl_last := -1.0

func _apply_daylight() -> void:
	# hemat: update sekali per ~0.05 jam
	if abs(time_of_day - _dl_last) < 0.05:
		return
	_dl_last = time_of_day
	var t := time_of_day
	# sudut matahari: terbit 6, terbenam 18
	var dayf := sin((t - 6.0) / 12.0 * PI)  # -1..1, >0 siang
	var elev := maxf(dayf * 62.0, 14.0)  # malam pun cahaya "bulan" tetap dari atas
	var azim := (t - 12.0) / 12.0 * 140.0
	sun.rotation_degrees = Vector3(-elev, azim - 90.0, 0)
	var env := world_env.environment
	if dayf > 0.15:
		# siang: lembut teduh (bukan terang benderang) — rasa sore yang adem
		var k := smoothstep(0.15, 0.85, dayf)
		sun.light_color = Color(1.0, 0.82, 0.62).lerp(Color(1.0, 0.90, 0.76), k)
		sun.light_energy = 0.46 + 0.07 * k
		sun.shadow_enabled = quality_ref.get_preset().shadows if quality_ref else true
		sun.shadow_opacity = 0.40
		env.ambient_light_color = Color(0.50, 0.57, 0.60)
		env.ambient_light_energy = 0.50
		env.fog_light_color = Color(0.54, 0.74, 0.68)
		sky_mat.set_shader_parameter("zenith_color", Color(0.19, 0.42, 0.46))
		sky_mat.set_shader_parameter("horizon_color", Color(0.62, 0.80, 0.66))
		sky_mat.set_shader_parameter("ground_color", Color(0.30, 0.38, 0.37))
		sky_mat.set_shader_parameter("sun_color", Color(1.0, 0.90, 0.66))
	elif dayf > -0.12:
		# senja/fajar: peach-teal sinematik (nuansa ZZZ)
		var k := smoothstep(-0.12, 0.15, dayf)
		sun.light_color = Color(1.0, 0.52, 0.32).lerp(Color(1.0, 0.90, 0.74), k)
		sun.light_energy = 0.42 + 0.42 * k
		env.ambient_light_color = Color(0.50, 0.46, 0.52).lerp(Color(0.50, 0.57, 0.60), k)
		env.ambient_light_energy = 0.52 + 0.30 * k
		env.fog_light_color = Color(0.72, 0.55, 0.48).lerp(Color(0.54, 0.74, 0.68), k)
		sky_mat.set_shader_parameter("zenith_color", Color(0.11, 0.24, 0.38).lerp(Color(0.19, 0.42, 0.46), k))
		sky_mat.set_shader_parameter("horizon_color", Color(0.95, 0.55, 0.34).lerp(Color(0.62, 0.80, 0.66), k))
		sky_mat.set_shader_parameter("sun_color", Color(1.0, 0.60, 0.30))
	else:
		# malam: tetap terbaca, tidak gelap pekat
		sun.light_color = Color(0.55, 0.65, 0.90)
		sun.light_energy = 0.34
		env.ambient_light_color = Color(0.30, 0.38, 0.46)
		env.ambient_light_energy = 0.62
		env.fog_light_color = Color(0.14, 0.19, 0.26)
		sky_mat.set_shader_parameter("zenith_color", Color(0.05, 0.09, 0.16))
		sky_mat.set_shader_parameter("horizon_color", Color(0.10, 0.15, 0.22))
		sky_mat.set_shader_parameter("sun_color", Color(0.62, 0.70, 0.85))
	env.fog_density = 0.0026 * (quality_ref.get_preset().fog if quality_ref else 1.0) * float(_lo.fog)
	# override dari Mode Edit: pengali & preset gradien langit
	sun.light_energy *= float(_lo.sun)
	env.ambient_light_energy *= float(_lo.ambient)
	if int(_lo.sky) >= 0 and int(_lo.sky) < SKY_PRESETS.size():
		var pr: Array = SKY_PRESETS[int(_lo.sky)]
		sky_mat.set_shader_parameter("zenith_color", pr[0])
		sky_mat.set_shader_parameter("horizon_color", pr[1])
