extends Node3D
## Beach: palem/kelapa, kerang, dan struktur landmark (mercusuar, dermaga,
## gubuk, perahu, lingkaran batu) + titik interaksi kelapa.
## Semua sampling posisi dihitung di worker thread (satu task besar).

const Materials := preload("res://packs/shaders_materials/materials.gd")
const MeshLib := preload("res://packs/world_terrain/meshlib.gd")

var island
var world
var player: Node3D
var tree_density := 1.0
var palm_mm: MultiMesh
var boat: Node3D
var lighthouse_light: OmniLight3D
var _t := 0.0
var _data := {}
var _built := false

func configure(p_island, p_world) -> void:
	island = p_island
	world = p_world
	WorkerThreadPool.add_task(Callable(self, "_task_layout"), false, "beach_layout")
	while _data.is_empty():
		await get_tree().process_frame
	_build_all()
	_built = true

func set_player(p: Node3D) -> void:
	player = p

func apply_density(t: float, _g: float) -> void:
	tree_density = t
	if palm_mm:
		palm_mm.visible_instance_count = maxi(1, int(round(palm_mm.instance_count * tree_density)))

# ---------------- worker: hitung semua posisi ----------------

func _task_layout() -> void:
	var d := {}
	var spawn: Vector3 = island.find_spawn_point()
	d["spawn"] = spawn
	# --- palem ---
	var rng := RandomNumberGenerator.new()
	rng.seed = 808
	var palms := []
	var tries := 0
	while palms.size() < 170 and tries < 4000:
		tries += 1
		var x := rng.randf_range(-780, 780)
		var z := rng.randf_range(-780, 780)
		var h: float = island.height_at(x, z)
		if h < 0.35 or h > 2.6:
			continue
		if island.slope_at(x, z) > 0.25:
			continue
		if island.is_river_near(x, z, 7.0) and h < 1.2:
			continue
		var near_sea := false
		for a in range(4):
			var off := Vector2(cos(a * PI / 2.0), sin(a * PI / 2.0)) * 55.0
			if island.height_at(x + off.x, z + off.y) < -0.5:
				near_sea = true
				break
		if not near_sea:
			continue
		palms.append({"p": Vector3(x, h, z), "s": rng.randf_range(0.85, 1.25), "rot": rng.randf() * TAU})
	d["palms"] = palms
	# --- kerang ---
	rng.seed = 606
	var shells := []
	tries = 0
	while shells.size() < 140 and tries < 2800:
		tries += 1
		var x := rng.randf_range(-780, 780)
		var z := rng.randf_range(-780, 780)
		var h: float = island.height_at(x, z)
		if h < 0.15 or h > 0.8 or island.slope_at(x, z) > 0.2:
			continue
		shells.append({"p": Vector3(x, h + 0.03, z), "ci": rng.randi() % 4, "s": rng.randf_range(0.6, 1.4)})
	d["shells"] = shells
	# --- mercusuar: titik tinggi pada cincin 150..500 m ---
	var best := [Vector3(0, -10, 0)]
	for j in range(21):
		for i in range(21):
			var x := -800.0 + i * 80.0
			var z := -800.0 + j * 80.0
			var r := Vector2(x, z).length()
			if r < 150.0 or r > 500.0:
				continue
			var h: float = island.height_at(x, z)
			if h > best[0].y:
				best[0] = Vector3(x, h, z)
	d["lighthouse"] = best[0]
	# --- lingkaran batu: titik tinggi dekat pusat ---
	best = [Vector3(0, -10, 0)]
	for j in range(13):
		for i in range(13):
			var x := -600.0 + i * 100.0
			var z := -600.0 + j * 100.0
			if Vector2(x, z).length() > 320.0:
				continue
			var h: float = island.height_at(x, z)
			if h > best[0].y:
				best[0] = Vector3(x, h, z)
	d["stone"] = best[0]
	# --- gubuk ---
	rng.seed = 4242
	var huts := []
	tries = 0
	while huts.size() < 3 and tries < 300:
		tries += 1
		var x := spawn.x + rng.randf_range(-110, 110)
		var z := spawn.z + rng.randf_range(-110, 110)
		var h: float = island.height_at(x, z)
		if h < 1.2 or h > 8.0 or island.moisture_at(x, z) > 0.48:
			continue
		if island.slope_at(x, z) > 0.18:
			continue
		huts.append({"p": Vector3(x, h, z), "rot": rng.randf() * TAU})
	d["huts"] = huts
	# --- dermaga: arah laut dari spawn ---
	var g := Vector2(
		island.height_at(spawn.x + 6.0, spawn.z) - island.height_at(spawn.x - 6.0, spawn.z),
		island.height_at(spawn.x, spawn.z + 6.0) - island.height_at(spawn.x, spawn.z - 6.0))
	var sea := -g
	if sea.length() < 0.001:
		sea = Vector2(spawn.x, spawn.z).normalized()
	sea = sea.normalized()
	var start := Vector2(spawn.x, spawn.z) + sea * 18.0
	d["dock"] = {"pos": Vector3(start.x, 0, start.y), "rot": -atan2(sea.y, sea.x)}
	# --- kelapa: 8 palem terdekat spawn (<=160 m) ---
	var near := palms.duplicate()
	near.sort_custom(func(a, b): return a["p"].distance_squared_to(spawn) < b["p"].distance_squared_to(spawn))
	var cocos := []
	rng.seed = 909
	for i in range(near.size()):
		if cocos.size() >= 8:
			break
		if near[i]["p"].distance_to(spawn) > 160.0:
			break
		cocos.append(near[i]["p"] + Vector3(rng.randf_range(-0.4, 0.4), rng.randf_range(3.0, 4.0), rng.randf_range(-0.4, 0.4)))
	d["coconuts"] = cocos
	call_deferred("_recv_layout", d)

func _recv_layout(d: Dictionary) -> void:
	_data = d

# ---------------- main thread: bangun node ----------------

func _build_all() -> void:
	_build_palms()
	_build_shells()
	_build_dock()
	_build_lighthouse()
	_build_huts()
	_build_stone_circle()
	_build_coconuts()

func _build_palms() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 551
	var palm_mesh: ArrayMesh = MeshLib.to_mesh(MeshLib.make_palm(rng))
	var pts: Array = _data["palms"]
	palm_mm = MultiMesh.new()
	palm_mm.mesh = palm_mesh
	palm_mm.transform_format = MultiMesh.TRANSFORM_3D
	palm_mm.instance_count = pts.size()
	var outline := MultiMesh.new()
	outline.mesh = palm_mesh
	outline.transform_format = MultiMesh.TRANSFORM_3D
	outline.instance_count = pts.size()
	for i in range(pts.size()):
		var t := Transform3D(Basis(Vector3.UP, pts[i]["rot"]) * Basis.from_scale(Vector3.ONE * pts[i]["s"]), pts[i]["p"])
		palm_mm.set_instance_transform(i, t)
		outline.set_instance_transform(i, t)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = palm_mm
	mmi.material_override = Materials.toon_vertex_color(false)
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mmi)
	var ommi := MultiMeshInstance3D.new()
	ommi.multimesh = outline
	ommi.material_override = Materials.make_outline(0.035)
	ommi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ommi)

func _build_shells() -> void:
	var cols := [Color(0.92, 0.75, 0.72), Color(0.85, 0.82, 0.70), Color(0.80, 0.70, 0.82), Color(0.88, 0.86, 0.80)]
	var groups := [{}, {}, {}, {}]
	for s in _data["shells"]:
		groups[s["ci"]][s["p"]] = s["s"]
	var sm := SphereMesh.new()
	sm.radius = 0.09
	sm.height = 0.1
	sm.radial_segments = 6
	sm.rings = 4
	for ci in range(4):
		if groups[ci].is_empty():
			continue
		var mm := MultiMesh.new()
		mm.mesh = sm
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.instance_count = groups[ci].size()
		var i := 0
		for p in groups[ci]:
			mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * groups[ci][p]), p))
			i += 1
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = Materials.toon(cols[ci], false, 0.0, 0.2)
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = 130.0
		add_child(mmi)

func _build_dock() -> void:
	var cfg: Dictionary = _data["dock"]
	var root := Node3D.new()
	root.name = "Dock"
	root.position = cfg["pos"]
	root.rotation.y = cfg["rot"]
	var static_body := StaticBody3D.new()
	static_body.collision_layer = 1
	var mat := Materials.toon(Color(0.62, 0.48, 0.34), true, 0.03, 0.3)
	var mat2 := Materials.toon(Color(0.5, 0.36, 0.24), true, 0.03, 0.3)
	var plank_mesh := MeshLib.to_mesh(MeshLib.from_box(Vector3(2.4, 0.14, 1.05), Color.WHITE))
	var post_mesh := MeshLib.to_mesh(MeshLib.from_cyl(0.09, 0.11, 2.6, 6, Color.WHITE))
	for i in range(10):
		var mi := MeshInstance3D.new()
		mi.mesh = plank_mesh
		mi.material_override = mat
		mi.position = Vector3(i * 1.05 - 4.5, 1.05, 0)
		root.add_child(mi)
	for i in range(0, 10, 3):
		for s in [-1.1, 1.1]:
			var po := MeshInstance3D.new()
			po.mesh = post_mesh
			po.material_override = mat2
			po.position = Vector3(i * 1.05 - 4.5, 0.0, s)
			root.add_child(po)
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(10.4, 0.14, 1.3)
	col.shape = box
	col.position = Vector3(0.2, 1.05, 0)
	static_body.add_child(col)
	root.add_child(static_body)
	add_child(root)
	# perahu di ujung dermaga
	boat = Node3D.new()
	boat.name = "Boat"
	var gp: Vector3 = root.to_global(Vector3(6.5, 0, 2.6))
	boat.position = Vector3(gp.x, 0.10, gp.z)
	var hull: ArrayMesh = MeshLib.to_mesh(MeshLib.xform(MeshLib.from_sphere(1.0, 8, 5, Color.WHITE),
			Transform3D(Basis.from_scale(Vector3(1.6, 0.45, 0.8)), Vector3.ZERO)))
	var mi := MeshInstance3D.new()
	mi.mesh = hull
	mi.material_override = Materials.toon(Color(0.85, 0.30, 0.25), true, 0.04, 0.3)
	boat.add_child(mi)
	var rim := MeshInstance3D.new()
	rim.mesh = MeshLib.to_mesh(MeshLib.from_box(Vector3(2.9, 0.09, 0.5), Color.WHITE))
	rim.material_override = Materials.toon(Color(0.55, 0.40, 0.28), false, 0.0, 0.25)
	rim.position.y = 0.42
	boat.add_child(rim)
	add_child(boat)

func _build_lighthouse() -> void:
	var best: Vector3 = _data["lighthouse"]
	var root := Node3D.new()
	root.name = "Lighthouse"
	root.position = best
	var white := Materials.toon(Color(0.93, 0.92, 0.88), true, 0.04, 0.3)
	var red := Materials.toon(Color(0.82, 0.25, 0.22), true, 0.04, 0.3)
	var dark := Materials.toon(Color(0.25, 0.27, 0.32), true, 0.04, 0.3)
	var base := MeshInstance3D.new()
	base.mesh = MeshLib.to_mesh(MeshLib.from_cyl(2.0, 2.5, 9.0, 10, Color.WHITE))
	base.material_override = white
	base.position.y = 4.5
	root.add_child(base)
	for i in range(3):
		var band := MeshInstance3D.new()
		band.mesh = MeshLib.to_mesh(MeshLib.from_cyl(2.06, 2.55, 0.7, 10, Color.WHITE))
		band.material_override = red
		band.position.y = 2.2 + i * 2.6
		root.add_child(band)
	var top := MeshInstance3D.new()
	top.mesh = MeshLib.to_mesh(MeshLib.from_cyl(1.1, 1.3, 1.8, 8, Color.WHITE))
	top.material_override = dark
	top.position.y = 9.6
	root.add_child(top)
	var lamp := MeshInstance3D.new()
	lamp.mesh = MeshLib.to_mesh(MeshLib.from_sphere(0.7, 8, 5, Color.WHITE))
	lamp.material_override = Materials.toon(Color(1.0, 0.9, 0.55), false, 0.0, 0.6)
	lamp.position.y = 9.6
	root.add_child(lamp)
	lighthouse_light = OmniLight3D.new()
	lighthouse_light.omni_range = 14.0
	lighthouse_light.light_energy = 0.0
	lighthouse_light.light_color = Color(1.0, 0.85, 0.5)
	lighthouse_light.shadow_enabled = false
	lighthouse_light.position.y = 9.8
	root.add_child(lighthouse_light)
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 2.5
	cyl.height = 9.0
	cs.shape = cyl
	cs.position.y = 4.5
	sb.add_child(cs)
	root.add_child(sb)
	add_child(root)

func _build_huts() -> void:
	var wall := Materials.toon(Color(0.88, 0.80, 0.62), true, 0.04, 0.3)
	var roof := Materials.toon(Color(0.72, 0.36, 0.26), true, 0.04, 0.3)
	var doorc := Materials.toon(Color(0.45, 0.33, 0.22), false)
	var wall_mesh: ArrayMesh = MeshLib.to_mesh(MeshLib.from_box(Vector3(3.4, 2.3, 3.0), Color.WHITE))
	var roof_mesh: ArrayMesh = MeshLib.to_mesh(MeshLib.make_roof_prism(Vector3(4.0, 1.5, 3.6), Color.WHITE))
	var door_mesh: ArrayMesh = MeshLib.to_mesh(MeshLib.from_box(Vector3(0.8, 1.6, 0.1), Color.WHITE))
	for cfg in _data["huts"]:
		var root := Node3D.new()
		root.name = "Hut"
		root.position = cfg["p"]
		root.rotation.y = cfg["rot"]
		var body := MeshInstance3D.new()
		body.mesh = wall_mesh
		body.material_override = wall
		body.position.y = 1.15
		root.add_child(body)
		var rf := MeshInstance3D.new()
		rf.mesh = roof_mesh
		rf.material_override = roof
		rf.position.y = 2.3
		root.add_child(rf)
		var door := MeshInstance3D.new()
		door.mesh = door_mesh
		door.material_override = doorc
		door.position = Vector3(0, 0.8, 1.51)
		root.add_child(door)
		var sb := StaticBody3D.new()
		sb.collision_layer = 1
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(3.4, 2.3, 3.0)
		cs.shape = bs
		cs.position.y = 1.15
		sb.add_child(cs)
		root.add_child(sb)
		add_child(root)

func _build_stone_circle() -> void:
	var best: Vector3 = _data["stone"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 1188
	var rock_mesh: ArrayMesh = MeshLib.to_mesh(MeshLib.make_rock(rng))
	var root := Node3D.new()
	root.name = "StoneCircle"
	root.position = best
	for i in range(7):
		var a := float(i) / 7.0 * TAU
		var p := Vector3(cos(a) * 5.0, 0, sin(a) * 5.0)
		p.y = island.height_at(best.x + p.x, best.z + p.z) - best.y
		var mi := MeshInstance3D.new()
		mi.mesh = rock_mesh
		mi.material_override = Materials.toon_vertex_color(true, 0.05)
		mi.position = p
		mi.rotation.y = rng.randf() * TAU
		var sc := rng.randf_range(2.4, 3.6)
		mi.scale = Vector3(sc, sc * rng.randf_range(0.9, 1.5), sc)
		root.add_child(mi)
	add_child(root)

func _build_coconuts() -> void:
	var coco_mesh := SphereMesh.new()
	coco_mesh.radius = 0.16
	coco_mesh.height = 0.3
	coco_mesh.radial_segments = 7
	coco_mesh.rings = 5
	var brownc := Materials.toon(Color(0.42, 0.30, 0.16), false, 0.0, 0.25)
	var oc := Materials.make_outline(0.03)
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	for top in _data["coconuts"]:
		var cluster := Node3D.new()
		cluster.name = "Coconuts"
		cluster.position = top
		for i in range(3):
			var off := Vector3(rng.randf_range(-0.25, 0.25), -0.2 - i * 0.05, rng.randf_range(-0.25, 0.25))
			var base := MeshInstance3D.new()
			base.mesh = coco_mesh
			base.material_override = brownc
			base.position = off
			cluster.add_child(base)
			var oc_i := MeshInstance3D.new()
			oc_i.mesh = coco_mesh
			oc_i.material_override = oc
			oc_i.position = off
			cluster.add_child(oc_i)
		add_child(cluster)
		world.register_interactable({"pos": top, "radius": 3.6, "type": "coconut", "node": cluster})

func _process(delta: float) -> void:
	if not _built:
		return
	_t += delta
	if boat:
		boat.position.y = 0.10 + sin(_t * 0.9) * 0.07
		boat.rotation.z = sin(_t * 0.7) * 0.04
	if lighthouse_light and world:
		var dark_now: bool = world.time_of_day > 19.0 or world.time_of_day < 5.5
		lighthouse_light.light_energy = lerpf(lighthouse_light.light_energy, 1.6 if dark_now else 0.0, delta * 2.0)
