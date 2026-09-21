extends Node3D
## World: satu-satunya dunia = Gravity Falls (gravity_falls.glb), mode STATIS.
## World procedural lama (pulau/chunk/desa/hutan/pantai) DIHAPUS TOTAL.
## API platform tetap lengkap agar HUD/pemain/game_root tidak perlu berubah
## (sculpt/edit = no-op, interactable = kosong, faceted = stub).

signal gen_progress(p: float, t: String)

const Materials := preload("res://packs/shaders_materials/materials.gd")
const SKY_SHADER := preload("res://packs/shaders_materials/sky.gdshader")
const STATIC_WORLD_PATH := "res://packs/world_terrain/gravity_falls.glb"
# node yang tidak dapat collision/outline (langit, bayangan tempel, logo)
const SKIP_PARTS := ["skybox", "shadow", "logo"]

var player: Node3D
var quality_ref
var faceted := false          # stub (tak ada world_terrain lagi)
var world_env: WorldEnvironment
var sun: DirectionalLight3D
var sky_mat: ShaderMaterial
var time_of_day := 16.4       # sore adem

var _root: Node
var _static_ready := false
var _hit_top := 60.0          # batas atas ray cari-lantai (diset dari AABB world)
var _hit_bottom := -60.0      # batas bawah ray (fallback bidang datar)
var _fallback_flat := false   # mode darurat: semua titik y=0
var _mesh_done := 0           # counter mesh di _static_walk (progres + yield)
var interactables := []       # kosong; dipertahankan utk kompatibilitas API

func _ready() -> void:
	name = "World"

func _wtrace(msg: String) -> void:
	if _root and _root.has_method("_trace"):
		_root._trace(msg)

func _report(p: float, t: String) -> void:
	print("[gen] %d%% %s" % [int(p * 100), t])
	gen_progress.emit(clampf(p, 0.0, 1.0), t)

# ---------------- boot ----------------

func generate_async(p_root: Node) -> void:
	_root = p_root
	_report(0.0, "Menyiapkan langit…")
	_setup_environment()
	_report(0.35, "Memuat Gravity Falls…")
	var res = load(STATIC_WORLD_PATH)
	if res == null:
		_wtrace("GAGAL: load() gravity_falls.glb mengembalikan null")
		_fallback_ground("load null")
		_report(1.0, "Dunia darurat (polos) siap")
		return
	if not (res is PackedScene):
		_wtrace("GAGAL: resource bukan PackedScene: %s" % str(res))
		_fallback_ground("bukan scene")
		_report(1.0, "Dunia darurat (polos) siap")
		return
	_report(0.6, "Membangun world…")
	if await _build_static(res):
		_report(1.0, "Dunia siap (Gravity Falls)")
	else:
		_fallback_ground("build gagal")
		_report(1.0, "Dunia darurat (polos) siap")

func _fallback_ground(why: String) -> void:
	# bidang datar darurat 400m: pemain tetap bisa berjalan & membaca jejak
	_wtrace("world darurat aktif (%s)" % why)
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(400, 400)
	mi.mesh = pm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.32, 0.42, 0.30)
	mi.material_override = mat
	add_child(mi)
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(400, 1.0, 400)
	col.position = Vector3(0, -0.5, 0)
	col.shape = sh
	body.add_child(col)
	add_child(body)
	_fallback_flat = true
	_hit_top = 40.0
	_hit_bottom = -40.0
	_static_ready = true

# ---------------- pembangun world statis ----------------

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


## RANTAI KUBAH: mesh dominan di 2 sumbu (>60% horizontal, >45% vertikal) = langit/latar.
func _mark_dome_meshes(node: Node, xf: Transform3D, total: AABB) -> void:
	if node is MeshInstance3D and node.mesh != null:
		var lb: AABB = xf * node.mesh.get_aabb()
		var horiz: float = maxf(lb.size.x, lb.size.z)
		var kd: float = horiz / maxf(maxf(total.size.x, total.size.z), 0.001)
		var kh: float = lb.size.y / maxf(total.size.y, 0.001)
		# kubah: dominan horizontal & cukup tinggi, tapi BUKAN backdrop gua sangat tinggi
		if kd > 0.6 and kh > 0.42 and kh < 0.90:
			node.set_meta("gf_dome", true)
	for c in node.get_children():
		var nxf: Transform3D = xf * (c.transform if c is Node3D else Transform3D.IDENTITY)
		_mark_dome_meshes(c, nxf, total)

## Pilih kandidat TANAH: mesh besar, agak datar (size.y relatif tipis), dekat bagian bawah scene.
## Dipakai sebagai dasar lantai (y=0) — menggantikan min.y global yang terseret kubah/lampiran ekstrem.
func _pick_ground_mesh(node: Node, xf: Transform3D, total: AABB) -> Dictionary:
	var best := {}
	_pick_ground_walk(node, xf, total, best)
	return best

static func _pick_ground_walk(node: Node, xf: Transform3D, total: AABB, best: Dictionary) -> void:
	if node is MeshInstance3D and node.mesh != null and not (node as MeshInstance3D).get_meta("gf_dome", false):
		var lb: AABB = xf * node.mesh.get_aabb()
		var horiz: float = maxf(lb.size.x, lb.size.z)
		if lb.size.y < 0.35 * maxf(horiz, 0.001) and lb.size.x > 0.35 * total.size.x and lb.size.y < 0.25 * total.size.y:
			if best.is_empty() or lb.position.y < float(best["min_y"]):
				best["min_y"] = lb.position.y
				best["center"] = Vector3(lb.position.x + lb.size.x * 0.5, 0.0, lb.position.z + lb.size.z * 0.5)
	for c in node.get_children():
		var nxf: Transform3D = xf * (c.transform if c is Node3D else Transform3D.IDENTITY)
		_pick_ground_walk(c, nxf, total, best)

func _build_static(res: PackedScene) -> bool:
	await get_tree().process_frame  # beri napas satu frame (loading screen hidup)
	var scene_root: Node3D = res.instantiate()
	if scene_root == null:
		_wtrace("GAGAL: instantiate() null")
		return false
	var aabb := _scene_aabb(scene_root)
	if aabb.size.x <= 0.001:
		_wtrace("GAGAL: AABB kosong")
		scene_root.free()
		return false
	var span := maxf(aabb.size.x, aabb.size.z)
	var k := 1.0
	if span < 60.0 or span > 480.0:
		k = 160.0 / span
	# dua lintasan: (1) tandai KUBAH dari bentuk — mesh yang dominan di 2 sumbu
	# (nama node generik tidak bisa diandalkan); (2) dapatkan DASAR LANTAI dari
	# kandidat tanah (ukuran besar & datar, mendekati bawah scene), bukan min.y global.
	_mark_dome_meshes(scene_root, Transform3D.IDENTITY, aabb)
	var ground := _pick_ground_mesh(scene_root, Transform3D.IDENTITY, aabb)
	var cont := Node3D.new()
	cont.name = "GravityFallsWorld"
	add_child(cont)
	cont.add_child(scene_root)
	cont.scale = Vector3.ONE * k
	var base_y: float = aabb.position.y
	var cinfo := Vector3(aabb.position.x + aabb.size.x * 0.5, 0.0, aabb.position.z + aabb.size.z * 0.5)
	if not ground.is_empty():
		base_y = float(ground["min_y"])
		cinfo = ground["center"]
	cont.position = Vector3(-cinfo.x * k, -base_y * k, -cinfo.z * k)
	# rentang ray cari-lantai pada RUANG DUNIA (posisi cont terpasang);
	# atas = puncak scene di ruang dunia, bawah = dasar scene (keduanya +keleluasaan)
	_hit_top = (aabb.position.y + aabb.size.y) * k + 20.0 - base_y * k
	_hit_bottom = aabb.position.y * k - base_y * k - 20.0
	var out_mat = Materials.make_outline(0.008)
	var stats := [0, 0]  # [mesh_kolisi, mesh_diberi_outline]
	await _static_walk(scene_root, cont.transform, out_mat, stats)
	if int(stats[0]) <= 0:
		_wtrace("GAGAL: tak ada satu pun mesh solid (kubah=%d)" % 0)
		cont.queue_free()
		return false
	_static_ready = true
	_wtrace("gravity falls ✓ span %dm tinggi %dm skala %.2f | mesh kolisi %d | outline %d" % [
		int(span), int(aabb.size.y), k, int(stats[0]), int(stats[1])])
	_wtrace("kubah dikeluarkan dari hitungan (ground dasar y=%.1f)" % base_y)
	return true

func _static_walk(node: Node, xf: Transform3D, out_mat: Material, stats: Array) -> void:
	var lname := String(node.name).to_lower()
	if lname.ends_with("_outline") or lname.ends_with("_col"):
		return
	var skip := false
	for s2 in SKIP_PARTS:
		if lname.contains(s2):
			skip = true
			break
	if node is MeshInstance3D and (node as MeshInstance3D).get_meta("gf_dome", false):
		skip = true
	if node is MeshInstance3D and node.mesh != null:
		var mi: MeshInstance3D = node
		if not skip:
			# COLLISION hanya untuk mesh SOLID BESAR — mesh kecil/dekoratik (pohon,
			# rumah mini, dekor, dan TERUTAMA kanvas cutout raksasa milik backdrop
			# yang ratusan ribu poligon) tak pernah dapat collision: dulu jutaan
			# segitiga diproses di GDScript → ponsel macet '_' watchdog menyala.
			var lb: AABB = xf * mi.mesh.get_aabb()
			var widest: float = maxf(lb.size.x, lb.size.z)
			if widest >= 6.0 or lb.size.y >= 6.0:
				var sh := mi.mesh.create_trimesh_shape()
				if sh != null:
					var body := StaticBody3D.new()
					body.name = mi.name + "_col"
					var col := CollisionShape3D.new()
					col.shape = sh
					body.add_child(col)
					mi.add_child(body)
					stats[0] += 1
			# outline khusus mesh non-kubah (input temen: outline = garis tipis)
			if out_mat != null:
				var o := MeshInstance3D.new()
				o.mesh = mi.mesh
				o.material_override = out_mat
				o.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				o.name = mi.name + "_outline"
				mi.add_child(o)
				stats[1] += 1
			# yield per mesh agar layar tidak membeku + progres terlihat merayap
			_mesh_done += 1
			if _mesh_done % 8 == 0:
				_report(0.6 + 0.35 * minf(_mesh_done / 250.0, 1.0), "Membangun world… (mesh ke-%d)" % _mesh_done)
			await get_tree().process_frame
	for c2 in node.get_children():
		var nxf2: Transform3D = xf * (c2.transform if c2 is Node3D else Transform3D.IDENTITY)
		await _static_walk(c2, nxf2, out_mat, stats)

var _floor_q := PhysicsRayQueryParameters3D.new()

## LANTAI NATIVE: ray physics dari atas ke bawah di titik (x,z).
## Menggantikan grid-bucket manual (jutaan segi diproses di GDScript = jamur lambat).
func _static_floor_at(x: float, z: float) -> float:
	if _fallback_flat:
		return 0.0
	if not _static_ready:
		return -999.0
	if not is_inside_tree():
		return -999.0
	_floor_q.from = Vector3(x, _hit_top, z)
	_floor_q.to = Vector3(x, _hit_bottom, z)
	_floor_q.collide_with_areas = false
	_floor_q.collide_with_bodies = true
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(_floor_q)
	if hit.is_empty():
		return -999.0
	return float(hit["position"].y)

func height_at(x: float, z: float) -> float:
	return _static_floor_at(x, z)

func find_spawn_point() -> Vector3:
	# Titik spawn = DI DEPAN RUMAH, bukan di atas atap.
	# Metode: pindai 8 arah menjauhi pusat ground (0,0); "jalur landai" =
	# rangkaian titik dengan floor VALID & < 1.8m (atap 5m+ tak lolos);
	# arah dengan jalur TERPANJANG dianggap jalanan depan rumah; spawn di
	# ujung awal jamur itu. Celah (gap) tak valid ditoleransi maksimal 2 titik.
	var dirs := [Vector2(0, 1), Vector2(-0.707, 0.707), Vector2(0.707, 0.707),
			Vector2(1, 0), Vector2(-1, 0), Vector2(0.707, -0.707),
			Vector2(-0.707, -0.707), Vector2(0, -1)]
	var best_dir := Vector2.ZERO
	var best_start := -1.0
	var best_run := 0.0
	for d in dirs:
		var first_r := -1.0
		var gap := 0
		var r := 4.0
		while r <= 90.0:
			var fy := _static_floor_at(d.x * r, d.y * r)
			if fy > -900.0 and fy < 1.8:
				if first_r < 0.0:
					first_r = r
				gap = 0
			else:
				if first_r < 0.0:
					pass  # belum lepas zona atap/dinding — terus menjauh
				else:
					gap += 1
					if gap > 2:
						break  # jalurnya putus di sini (tebing/asset tinggi)
			r += 1.5
		if first_r >= 0.0:
			var run := r - 1.5 - first_r
			if run > best_run:
				best_run = run
				best_start = first_r
				best_dir = d
	if best_dir != Vector2.ZERO and best_run >= 3.0:
		var s := best_dir * (best_start + 1.5)
		var fy2 := _static_floor_at(s.x, s.y)
		if fy2 > -900.0:
			return Vector3(s.x, fy2 + 0.25, s.y)
	# jaring 9 kandidat lama — kini dgn FILTER atap juga
	for cand in [Vector2(0, 0), Vector2(4, 0), Vector2(-4, 0), Vector2(0, 4), Vector2(0, -4),
			Vector2(8, 8), Vector2(-8, -8), Vector2(8, -8), Vector2(-8, 8)]:
		var fy3 := _static_floor_at(cand.x, cand.y)
		if fy3 > -999.0 and fy3 < 1.8:
			return Vector3(cand.x, fy3 + 0.25, cand.y)
	return Vector3(0, 0.3, 0)

# ---------------- API kompatibel (no-op / kosong) ----------------

func set_player(p: Node3D) -> void:
	player = p

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

func apply_terrain_edit(_p: Vector3, _r: float, _a: float, _m: String) -> void:
	pass  # world statis tak bisa di-sculpt

func reset_edits() -> void:
	pass

# ---------------- pencahayaan (Slider Mode Edit tetap jalan) ----------------

const SKY_PRESETS := [
	[Color(0.30, 0.74, 0.69), Color(0.62, 0.88, 0.80)],
	[Color(0.18, 0.38, 0.52), Color(0.56, 0.86, 0.78)],
	[Color(0.18, 0.26, 0.44), Color(0.98, 0.60, 0.38)],
	[Color(0.05, 0.09, 0.16), Color(0.16, 0.20, 0.30)],
]
var _lo := {"sun": 1.0, "ambient": 1.0, "fog": 1.0, "sky": -1}

func apply_lighting(d: Dictionary) -> void:
	for kk in d:
		_lo[kk] = d[kk]
	_dl_last = -1.0
	_apply_daylight()

func apply_quality(p: Dictionary) -> void:
	if world_env:
		world_env.environment.fog_density = 0.0026 * float(p.get("fog", 1.0))

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

const DAY_LENGTH := 420.0

func _process(delta: float) -> void:
	_tick_daynight(delta)

func _tick_daynight(delta: float) -> void:
	time_of_day = fmod(time_of_day + delta * 24.0 / DAY_LENGTH, 24.0)
	_apply_daylight()

var _dl_last := -1.0

func _apply_daylight() -> void:
	if abs(time_of_day - _dl_last) < 0.05:
		return
	_dl_last = time_of_day
	var t := time_of_day
	var dayf := sin((t - 6.0) / 12.0 * PI)
	var elev := maxf(dayf * 62.0, 14.0)
	var azim := (t - 12.0) / 12.0 * 140.0
	sun.rotation_degrees = Vector3(-elev, azim - 90.0, 0)
	var env := world_env.environment
	if dayf > 0.15:
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
		sky_mat.set_shader_parameter("ground_color", Color(0.42, 0.55, 0.50))
		sky_mat.set_shader_parameter("sun_color", Color(1.0, 0.90, 0.66))
	elif dayf > -0.12:
		var k2 := smoothstep(-0.12, 0.15, dayf)
		sun.light_color = Color(1.0, 0.52, 0.32).lerp(Color(1.0, 0.90, 0.74), k2)
		sun.light_energy = 0.42 + 0.42 * k2
		env.ambient_light_color = Color(0.50, 0.46, 0.52).lerp(Color(0.50, 0.57, 0.60), k2)
		env.ambient_light_energy = 0.52 + 0.30 * k2
		env.fog_light_color = Color(0.72, 0.55, 0.48).lerp(Color(0.54, 0.74, 0.68), k2)
		sky_mat.set_shader_parameter("zenith_color", Color(0.11, 0.24, 0.38).lerp(Color(0.19, 0.42, 0.46), k2))
		sky_mat.set_shader_parameter("horizon_color", Color(0.95, 0.55, 0.34).lerp(Color(0.62, 0.80, 0.66), k2))
		# bawah cakrawala JANGAN coklat-marun berlumpur (laporan foto 17:17):
		# harmonis dgn senja — terracotta lembut, bukan abu-abu sisa siang
		sky_mat.set_shader_parameter("ground_color", Color(0.55, 0.40, 0.34).lerp(Color(0.42, 0.55, 0.50), k2))
		sky_mat.set_shader_parameter("sun_color", Color(1.0, 0.60, 0.30))
	else:
		sun.light_color = Color(0.55, 0.65, 0.90)
		sun.light_energy = 0.34
		env.ambient_light_color = Color(0.30, 0.38, 0.46)
		env.ambient_light_energy = 0.62
		env.fog_light_color = Color(0.14, 0.19, 0.26)
		sky_mat.set_shader_parameter("zenith_color", Color(0.05, 0.09, 0.16))
		sky_mat.set_shader_parameter("horizon_color", Color(0.10, 0.15, 0.22))
		sky_mat.set_shader_parameter("ground_color", Color(0.07, 0.11, 0.16))
		sky_mat.set_shader_parameter("sun_color", Color(0.62, 0.70, 0.85))
	env.fog_density = 0.0026 * float(_lo.fog)
	sun.light_energy *= float(_lo.sun)
	env.ambient_light_energy *= float(_lo.ambient)
	if int(_lo.sky) >= 0 and int(_lo.sky) < SKY_PRESETS.size():
		var pr: Array = SKY_PRESETS[int(_lo.sky)]
		sky_mat.set_shader_parameter("zenith_color", pr[0])
		sky_mat.set_shader_parameter("horizon_color", pr[1])
