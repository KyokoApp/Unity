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
var _gcell := 4.0             # meter per sel grid akselerasi ketinggian
var _gbuckets := {}           # "cx,cz" -> PackedInt32Array indeks segitiga
var _gtris := PackedFloat32Array()
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
	if _build_static(res):
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
	# grid tinggi menganggap semua titik di y=0
	_register_flat_grid()
	_static_ready = true

func _register_flat_grid() -> void:
	# dua segitiga besar menutupi [-200,200]^2 di y=0
	_gtris.append_array([-200.0, 0.0, -200.0, 200.0, 0.0, -200.0, 200.0, 0.0, 200.0])
	_gtris.append_array([-200.0, 0.0, -200.0, 200.0, 0.0, 200.0, -200.0, 0.0, 200.0])
	for cz in range(-50, 51):
		for cx in range(-50, 51):
			var key := "%d,%d" % [cx, cz]
			_gbuckets[key] = PackedInt32Array([0, 1])

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
	var out_mat = Materials.make_outline(0.008)
	var stats := [0, 0]  # [mesh_kolisi, segi_jalan]
	_static_walk(scene_root, cont.transform, out_mat, stats)
	if int(stats[1]) <= 0 or _gbuckets.is_empty():
		_wtrace("GAGAL: tak ada segitiga pijakan (kolisi %d)" % int(stats[0]))
		cont.queue_free()
		return false
	_static_ready = true
	_wtrace("gravity falls ✓ span %dm tinggi %dm skala %.2f | mesh kolisi %d | segi jalan %d" % [
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
			var sh := mi.mesh.create_trimesh_shape()
			if sh != null:
				var body := StaticBody3D.new()
				body.name = mi.name + "_col"
				var col := CollisionShape3D.new()
				col.shape = sh
				body.add_child(col)
				mi.add_child(body)
				stats[0] += 1
			if out_mat != null:
				var o := MeshInstance3D.new()
				o.mesh = mi.mesh
				o.material_override = out_mat
				o.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				o.name = mi.name + "_outline"
				mi.add_child(o)
			for si in range(mi.mesh.get_surface_count()):
				var arrs := mi.mesh.surface_get_arrays(si)
				var verts: PackedVector3Array = arrs[Mesh.ARRAY_VERTEX]
				if verts.is_empty():
					continue
				var idx: PackedInt32Array = arrs[Mesh.ARRAY_INDEX]
				if idx.is_empty():
					idx = PackedInt32Array(range(verts.size()))
				for t in range(0, idx.size() - 2, 3):
					var a: Vector3 = xf * verts[idx[t]]
					var b: Vector3 = xf * verts[idx[t + 1]]
					var c: Vector3 = xf * verts[idx[t + 2]]
					var n := (b - a).cross(c - a)
					if n.length() < 0.0001 or n.normalized().y < 0.35:
						continue
					_grid_add_tri(a, b, c)
					stats[1] += 1
	for c2 in node.get_children():
		var nxf2: Transform3D = xf * (c2.transform if c2 is Node3D else Transform3D.IDENTITY)
		_static_walk(c2, nxf2, out_mat, stats)

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

# ---------------- query permukaan ----------------

func _static_floor_at(x: float, z: float) -> float:
	var best := -999.0
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
				# barycentric via dot-product (dua vektor sisi) — AKURAT, terverifikasi 20.000 titik acak
				var v0x: float = bx - ax
				var v0z: float = bz - az
				var v1x: float = cx2 - ax
				var v1z: float = cz2 - az
				var v2x: float = x - ax
				var v2z: float = z - az
				var d00: float = v0x * v0x + v0z * v0z
				var d01: float = v0x * v1x + v0z * v1z
				var d11: float = v1x * v1x + v1z * v1z
				var d20: float = v2x * v0x + v2z * v0z
				var d21: float = v2x * v1x + v2z * v1z
				var den: float = d00 * d11 - d01 * d01
				if absf(den) < 0.0000001:
					continue
				var wb: float = (d11 * d20 - d01 * d21) / den
				var wc: float = (d00 * d21 - d01 * d20) / den
				var wa: float = 1.0 - wb - wc
				if wa < -0.0001 or wb < -0.0001 or wc < -0.0001:
					continue
				var y := wa * ay + wb * by + wc * cy
				if y > best:
					best = y
	return best

func find_spawn_point() -> Vector3:
	for cand in [Vector2(0, 0), Vector2(4, 0), Vector2(-4, 0), Vector2(0, 4), Vector2(0, -4),
			Vector2(8, 8), Vector2(-8, -8), Vector2(8, -8), Vector2(-8, 8)]:
		var fy := _static_floor_at(cand.x, cand.y)
		if fy > -999.0:
			return Vector3(cand.x, fy + 0.25, cand.y)
	return Vector3(0, 0.3, 0)

func height_at(x: float, z: float) -> float:
	return _static_floor_at(x, z)

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
		sky_mat.set_shader_parameter("ground_color", Color(0.30, 0.38, 0.37))
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
		sky_mat.set_shader_parameter("sun_color", Color(1.0, 0.60, 0.30))
	else:
		sun.light_color = Color(0.55, 0.65, 0.90)
		sun.light_energy = 0.34
		env.ambient_light_color = Color(0.30, 0.38, 0.46)
		env.ambient_light_energy = 0.62
		env.fog_light_color = Color(0.14, 0.19, 0.26)
		sky_mat.set_shader_parameter("zenith_color", Color(0.05, 0.09, 0.16))
		sky_mat.set_shader_parameter("horizon_color", Color(0.10, 0.15, 0.22))
		sky_mat.set_shader_parameter("sun_color", Color(0.62, 0.70, 0.85))
	env.fog_density = 0.0026 * float(_lo.fog)
	sun.light_energy *= float(_lo.sun)
	env.ambient_light_energy *= float(_lo.ambient)
	if int(_lo.sky) >= 0 and int(_lo.sky) < SKY_PRESETS.size():
		var pr: Array = SKY_PRESETS[int(_lo.sky)]
		sky_mat.set_shader_parameter("zenith_color", pr[0])
		sky_mat.set_shader_parameter("horizon_color", pr[1])
