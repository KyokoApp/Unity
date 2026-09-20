extends Node3D
## Village: menata beberapa desa kecil pulau dari aset KayKit Medieval (CC0).
## Rumah dihadapkan ke pusat desa (sumur), props hangat di sekitar, batu collision
## sederhana (kotak AABB) supaya tidak bisa ditembus pemain.

const KIT_DIR := "res://packs/world_props_forest/kaykit/"

const BUILDINGS := [
	{"asset": "building_home_A_green", "foot": 6.5, "tall": 6.2, "w": 3},
	{"asset": "building_home_B_green", "foot": 6.0, "tall": 6.0, "w": 3},
	{"asset": "building_tavern_green", "foot": 7.5, "tall": 7.0, "w": 2},
	{"asset": "building_blacksmith_green", "foot": 7.0, "tall": 6.6, "w": 1},
	{"asset": "building_windmill_green", "foot": 7.0, "tall": 11.0, "w": 1},
	{"asset": "building_church_green", "foot": 8.0, "tall": 10.0, "w": 1},
]
const CENTER := {"asset": "building_well_green", "foot": 3.0, "tall": 3.2}
const PROPS := [
	{"asset": "barrel", "foot": 0.9},
	{"asset": "crate_A_big", "foot": 1.1},
	{"asset": "wheelbarrow", "foot": 1.6},
	{"asset": "fence_wood_straight", "foot": 2.2},
]

var island
var world
var _scenes := {}   # asset name -> PackedScene
var _built := false

func configure(p_island, p_world) -> void:
	island = p_island
	world = p_world
	_built = false
	call_deferred("_build")

func _scene_of(asset_name: String) -> PackedScene:
	if not _scenes.has(asset_name):
		var res = load(KIT_DIR + asset_name + ".gltf")
		_scenes[asset_name] = res if res is PackedScene else null
	return _scenes[asset_name]

func _measure(scene: PackedScene) -> AABB:
	# gabungan AABB semua MeshInstance3D pada adegan (ruang lokal akar)
	var root := scene.instantiate()
	var boxes := []
	_collect_mesh_aabbs(root, Transform3D.IDENTITY, boxes)
	root.free()
	var out := AABB()
	for i in range(boxes.size()):
		out = boxes[i] if i == 0 else out.merge(boxes[i])
	return out

func _collect_mesh_aabbs(node: Node, xform: Transform3D, boxes: Array) -> void:
	if node is MeshInstance3D and node.mesh != null:
		boxes.append(xform * node.mesh.get_aabb())
	for c in node.get_children():
		var xf: Transform3D = xform * (c.transform if c is Node3D else Transform3D.IDENTITY)
		_collect_mesh_aabbs(c, xf, boxes)

func _place(name: String, pos: Vector3, yaw: float, target: float, mode: String, collide_body := true) -> Node3D:
	var scene := _scene_of(name)
	if scene == null:
		return null
	var inst: Node3D = scene.instantiate()
	var aabb := _measure(scene)
	if aabb.size.y <= 0.001:
		return null
	var base: float
	if mode == "foot":  # berdasar sisi horizontal terpanjang
		base = target / maxf(aabb.size.x, aabb.size.z)
	else:               # berdasar tinggi
		base = target / aabb.size.y
	inst.scale = Vector3.ONE * base
	inst.rotation.y = yaw
	add_child(inst)
	# kaki tepat di tanah
	var bottom := aabb.position.y * base
	inst.global_position = pos - Vector3(0, bottom, 0)
	if collide_body:
		var body := StaticBody3D.new()
		var col := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(aabb.size.x * base * 0.86, aabb.size.y * base, aabb.size.z * base * 0.86)
		col.shape = box
		col.position = Vector3(0, bottom + box.size.y * 0.5, 0)
		body.add_child(col)
		body.rotation.y = yaw
		add_child(body)
		body.global_position = pos
	return inst

# maksimum 3 desa: dekat pantai berpasir, landai, saling berjauhan
func _find_sites(count: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260920
	var sp := Vector3.ZERO
	if world != null and world.has_method("find_spawn_point"):
		sp = world.find_spawn_point()
	var sites: Array = []
	var tries := 0
	while sites.size() < count and tries < 900:
		tries += 1
		var ang := rng.randf() * TAU
		var rad := rng.randf_range(150.0, 520.0)
		var x := sp.x + cos(ang) * rad
		var z := sp.z + sin(ang) * rad
		if absf(x) > 720.0 or absf(z) > 720.0:
			continue
		var h: float = island.height_at(x, z)
		if h < 1.2 or h > 7.0:
			continue
		var s: float = island.slope_at(x, z)
		if s > 0.16:
			continue
		var ok := true
		for q in sites:
			if (q - Vector2(x, z)).length() < 240.0:
				ok = false
				break
		if ok:
			sites.append(Vector2(x, z))
	return sites

func _build() -> void:
	if _built:
		return
	_built = true
	var sites := _find_sites(3)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1977
	for si in range(sites.size()):
		var c: Vector2 = sites[si]
		var center_y: float = island.height_at(c.x, c.y)
		# sumur pusat
		_place(CENTER.asset, Vector3(c.x, center_y, c.y), rng.randf() * TAU, CENTER.foot, "foot")
		# cincin rumah menghadap pusat
		var n := rng.randi_range(4, 6)
		var ring_r := rng.randf_range(17.0, 24.0)
		var picks := []
		for b in BUILDINGS:
			for k in range(int(b["w"])):
				picks.append(b)
		picks.shuffle()
		for i in range(mini(n, picks.size())):
			var ang := (float(i) / n) * TAU + rng.randf_range(-0.22, 0.22)
			var px := c.x + cos(ang) * ring_r
			var pz := c.y + sin(ang) * ring_r
			var py: float = island.height_at(px, pz)
			if island.slope_at(px, pz) > 0.24:
				continue
			var b: Dictionary = picks[i]
			# hadap pusat: yaw + PI dengan jitter
			var yaw := atan2(c.x - px, c.y - pz) + rng.randf_range(-0.2, 0.2)
			_place(b["asset"], Vector3(px, py, pz), yaw, float(b["foot"]), "foot")
			# props di samping rumah
			for pi in range(rng.randi_range(1, 3)):
				var pr: Dictionary = PROPS[rng.randi() % PROPS.size()]
				var pa := ang + rng.randf_range(-0.9, 0.9)
				var pd := rng.randf_range(6.0, 10.0)
				var gx := px + cos(pa) * pd
				var gz := pz + sin(pa) * pd
				_place(pr["asset"], Vector3(gx, island.height_at(gx, gz), gz), rng.randf() * TAU, float(pr["foot"]), "foot", false)
		# 2-4 pohon hias tepi desa
		for ti in range(rng.randi_range(2, 4)):
			var ta := rng.randf() * TAU
			var tx := c.x + cos(ta) * rng.randf_range(ring_r + 8.0, ring_r + 20.0)
			var tz := c.y + sin(ta) * rng.randf_range(ring_r + 8.0, ring_r + 20.0)
			_place("tree_single_A", Vector3(tx, island.height_at(tx, tz), tz), rng.randf() * TAU, 6.8, "tall", false)
	print("village: %d desa dibangun" % sites.size())
