extends Node3D
## Forest: pohon/semak/batu/rumput/bunga via MultiMeshInstance3D per supercell
## 4x4 (400 m). Scatter dihitung di worker thread, mesh dibuat di main thread.
## Pohon & batu punya outline (MM kedua dengan material outline inverted-hull).

const Materials := preload("res://packs/shaders_materials/materials.gd")
const MeshLib := preload("res://packs/world_terrain/meshlib.gd")
const GRASS_SHADER := preload("res://packs/shaders_materials/grass.gdshader")
const SUPER := 4             # 4x4 supercell menutupi seluruh pulau
const CELL := 400.0          # meter per supercell
const BUILD_RING := 2        # ring supercell sekitar pemain yang dibangun
const KEEP_RING := 3
const MAX_CONCURRENT := 2

var island
var world
var player: Node3D
var tree_density := 1.0
var grass_density := 1.0
var meshes := {}             # nama mesh -> Array of ArrayMesh
var supercells := {}         # key -> Dictionary tipe -> MultiMeshInstance3D
var building := {}           # key -> true
var results := []            # antrian hasil worker (key -> dict tipe -> [{p,s,rot}])
var _rm := Mutex.new()
var prewarm_center := Vector2i(-1, -1)
var flowers_spawned := false
const MASTER_SEED := 7331

func configure(p_island, p_world) -> void:
	island = p_island
	world = p_world
	_build_shared_meshes()
	# prewarm 3x3 sel di sekitar titik spawn (masih di layar loading)
	if world.has_method("find_spawn_point"):
		var sp = world.find_spawn_point()
		prewarm_center = _supercell_at(sp.x, sp.z)
		await _prewarm()

func set_player(p: Node3D) -> void:
	player = p

func apply_density(t: float, g: float) -> void:
	tree_density = t
	grass_density = g
	for k in supercells:
		_apply_density_cell(supercells[k])

func _build_shared_meshes() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 911
	var variants := []
	for i in range(3):
		variants.append(MeshLib.to_mesh(MeshLib.make_broadleaf_tree(rng)))
	meshes["broadleaf"] = variants
	variants = []
	for i in range(3):
		variants.append(MeshLib.to_mesh(MeshLib.make_pine_tree(rng)))
	meshes["pine"] = variants
	variants = []
	for i in range(3):
		variants.append(MeshLib.to_mesh(MeshLib.make_rock(rng)))
	meshes["rock"] = variants
	meshes["bush"] = [MeshLib.to_mesh(MeshLib.make_bush(rng))]
	meshes["grass"] = [MeshLib.to_mesh(MeshLib.make_grass_tuft())]
	meshes["flower"] = [MeshLib.to_mesh(MeshLib.make_flower())]

func _supercell_at(x: float, z: float) -> Vector2i:
	return Vector2i(floori(x / CELL) + 2, floori(z / CELL) + 2)

func _prewarm() -> void:
	for j in range(prewarm_center.y - 1, prewarm_center.y + 2):
		for i in range(prewarm_center.x - 1, prewarm_center.x + 2):
			if i < 0 or j < 0 or i >= SUPER or j >= SUPER:
				continue
			_queue_cell(Vector2i(i, j))
	# tunggu semua selesai sambil mengintegrasi satu per satu
	while not building.is_empty() or _results_count() > 0:
		_integrate(1)
		await get_tree().process_frame

func _results_count() -> int:
	_rm.lock()
	var n := results.size()
	_rm.unlock()
	return n

func _queue_cell(c: Vector2i) -> void:
	var k := "%d,%d" % [c.x, c.y]
	if supercells.has(k) or building.has(k):
		return
	building[k] = true
	WorkerThreadPool.add_task(Callable(self, "_task_cell").bind(c), false)

func _process(_delta: float) -> void:
	if island == null:
		return
	var center := prewarm_center
	if player != null:
		center = _supercell_at(player.global_position.x, player.global_position.z)
	# antrikan sel kosong dalam ring
	if building.size() < MAX_CONCURRENT:
		var want := []
		for j in range(center.y - BUILD_RING, center.y + BUILD_RING + 1):
			for i in range(center.x - BUILD_RING, center.x + BUILD_RING + 1):
				if i < 0 or j < 0 or i >= SUPER or j >= SUPER:
					continue
				var k := "%d,%d" % [i, j]
				if not supercells.has(k) and not building.has(k):
					want.append(Vector2i(i, j))
		want.sort_custom(func(a, b): return (a - center).length_squared() < (b - center).length_squared())
		for c in want:
			if building.size() >= MAX_CONCURRENT:
				break
			_queue_cell(c)
	_integrate(1)
	# hapus sel terlalu jauh
	var del := []
	for k in supercells:
		var parts: PackedStringArray = k.split(",")
		var c := Vector2i(int(parts[0]), int(parts[1]))
		if maxi(abs(c.x - center.x), abs(c.y - center.y)) > KEEP_RING:
			del.append(k)
	for k in del:
		for t in supercells[k]:
			if is_instance_valid(supercells[k][t]):
				supercells[k][t].queue_free()
		supercells.erase(k)
	if player != null and not flowers_spawned:
		_spawn_pickup_flowers()

func _integrate(budget: int) -> void:
	_rm.lock()
	var n = mini(results.size(), budget)
	var batch := results.slice(0, n)
	results = results.slice(n)
	_rm.unlock()
	for r in batch:
		_build_cell_nodes(r)

# ---------------- worker ----------------

func _task_cell(c: Vector2i) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([MASTER_SEED, c.x, c.y])
	var origin := Vector2((c.x - 2) * CELL, (c.y - 2) * CELL)
	var out := {
		"key": "%d,%d" % [c.x, c.y],
		"broadleaf": [], "pine": [], "bush": [], "rock": [], "flower": [], "grass": []
	}
	var mesh_ix := {"broadleaf": [], "pine": [], "rock": []}
	for t in mesh_ix:
		mesh_ix[t] = meshes[t][rng.randi() % meshes[t].size()]
	out["mesh_ix"] = mesh_ix
	const TRIES := 1150
	for i in range(TRIES):
		var x := origin.x + rng.randf() * CELL
		var z := origin.y + rng.randf() * CELL
		if x < -800.0 or x > 800.0 or z < -800.0 or z > 800.0:
			continue
		# sampel biom sekali untuk semua tipe (hemat query noise)
		var h: float = island.height_at(x, z)
		if h < 0.05:
			continue
		var s: float = island.slope_at(x, z)
		var b := _biome_of(h, s, island.moisture_at(x, z))
		if b == 3 and s < 0.30 and out["broadleaf"].size() < 64:
			out["broadleaf"].append({"p": Vector3(x, h, z), "s": rng.randf_range(0.85, 1.5), "rot": rng.randf() * TAU})
		if (b == 3 or b == 5) and s < 0.34 and out["pine"].size() < 30:
			out["pine"].append({"p": Vector3(x, h, z), "s": rng.randf_range(0.9, 1.6), "rot": rng.randf() * TAU})
		if (b == 3 or b == 2) and s < 0.32 and out["bush"].size() < 40:
			out["bush"].append({"p": Vector3(x, h, z), "s": rng.randf_range(0.8, 1.5), "rot": rng.randf() * TAU})
		if (b == 4 or b == 5) and out["rock"].size() < 26:
			out["rock"].append({"p": Vector3(x, h, z), "s": rng.randf_range(1.2, 2.8), "rot": rng.randf() * TAU})
		if b == 2 and island.moisture_at(x, z) > 0.42 and s < 0.25 and out["flower"].size() < 30:
			out["flower"].append({"p": Vector3(x, h, z), "s": rng.randf_range(0.9, 1.6), "rot": rng.randf() * TAU})
		if (b == 2 or b == 3) and s < 0.33 and out["grass"].size() < 300:
			out["grass"].append({"p": Vector3(x, h - 0.05, z), "s": rng.randf_range(0.9, 2.0), "rot": rng.randf() * TAU})
	_rm.lock()
	results.append(out)
	_rm.unlock()

## 0 laut 1 pantai 2 padang 3 hutan 4 batu 5 bukit — sama dengan island.BIOME.
func _biome_of(h: float, s: float, m: float) -> int:
	if h > 22.0 or s > 0.42:
		return 4
	if h > 9.0 and s > 0.28:
		return 5
	if h < 0.95:
		return 1
	if m > 0.48 and h < 12.0:
		return 3
	return 2

# ---------------- main thread ----------------

func _build_cell_nodes(data: Dictionary) -> void:
	var k: String = data["key"]
	building.erase(k)
	if supercells.has(k):
		return
	var nodes := {}
	for t in ["broadleaf", "pine", "bush", "rock", "flower", "grass"]:
		var pts: Array = data[t]
		if pts.is_empty():
			continue
		var mesh: ArrayMesh = data["mesh_ix"][t] if data["mesh_ix"].has(t) else meshes[t][0]
		var mmi := MultiMeshInstance3D.new()
		var mm := MultiMesh.new()
		mm.mesh = mesh
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.instance_count = pts.size()
		for i in range(pts.size()):
			var sc: float = pts[i]["s"]
			var basis := Basis(Vector3.UP, pts[i]["rot"]) * Basis.from_scale(Vector3.ONE * sc)
			mm.set_instance_transform(i, Transform3D(basis, pts[i]["p"]))
		mmi.multimesh = mm
		if t == "grass":
			var gm := ShaderMaterial.new()
			gm.shader = GRASS_SHADER
			mmi.material_override = gm
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		else:
			mmi.material_override = Materials.toon_vertex_color(false)
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		mmi.visibility_range_end = 420.0 if t in ["grass", "flower"] else 700.0
		mmi.visibility_range_end_margin = 8.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		mmi.set_meta("base_count", pts.size())
		mmi.set_meta("type", t)
		add_child(mmi)
		nodes[t] = mmi
		if t in ["broadleaf", "pine", "rock"]:
			var ommi := MultiMeshInstance3D.new()
			var omm := MultiMesh.new()
			omm.mesh = mesh
			omm.transform_format = MultiMesh.TRANSFORM_3D
			omm.instance_count = pts.size()
			for i in range(pts.size()):
				omm.set_instance_transform(i, mm.get_instance_transform(i))
			ommi.multimesh = omm
			ommi.material_override = Materials.make_outline(0.035)
			ommi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			ommi.visibility_range_end = 380.0
			ommi.set_meta("base_count", pts.size())
			ommi.set_meta("type", t)
			add_child(ommi)
			nodes[t + "_outline"] = ommi
	_apply_density_cell(nodes)
	supercells[k] = nodes
	if world.has_method("report_pack_cell_ready"):
		world.report_pack_cell_ready()

func _apply_density_cell(nodes: Dictionary) -> void:
	for t in nodes:
		if nodes[t] is MultiMeshInstance3D:
			var mmi: MultiMeshInstance3D = nodes[t]
			var base: int = mmi.get_meta("base_count")
			var ratio := grass_density if String(mmi.get_meta("type")) == "grass" else tree_density
			mmi.multimesh.visible_instance_count = maxi(1, int(round(base * ratio))) if base > 0 else 0

## Bunga petik (interaksi) — ditempatkan dekat pemain saat pertama jalan.
func _spawn_pickup_flowers() -> void:
	flowers_spawned = true
	var rng := RandomNumberGenerator.new()
	rng.seed = 3107
	var center := Vector2(player.global_position.x, player.global_position.z)
	var placed := 0
	var tries := 0
	while placed < 24 and tries < 600:
		tries += 1
		var x := center.x + rng.randf_range(-90, 90)
		var z := center.y + rng.randf_range(-90, 90)
		if island.biome_at(x, z) != 2:
			continue
		var h: float = island.height_at(x, z)
		var node := MeshInstance3D.new()
		node.mesh = meshes["flower"][0]
		node.material_override = Materials.toon_vertex_color(true, 0.02)
		node.position = Vector3(x, h, z)
		node.rotation.y = rng.randf() * TAU
		node.scale = Vector3.ONE * rng.randf_range(1.6, 2.2)
		add_child(node)
		world.register_interactable({"pos": node.position, "radius": 2.4, "type": "flower", "node": node})
		placed += 1
