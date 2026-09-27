extends Node
class_name OpenWorldMode
## OPEN WORLD MODE (permintaan user ronde ini): dunia tanpa-batas datar-tapi-
## bergelombang, padang rumput tebal-setinggi-betis dg angin sepoi + dorongan
## saat dilewati, pepohonan/batu/semak/jamur TERTERSEBAR ACAK-dan-deterministik
## dari chunk (layout sama tiap datang lagi), kabut hutan dekat, kamera bahu
## super-dekat, gerak jalan+lari saja, karakter mannequin abu-pastel, dan
## outline tipis inverted-hull di tiap objek scatter.
##
## Struktur:
##   - terrain_wave(x,z)              : gelombang landai (SATU rumus — isi
##     yg sama persis dicopy GLSL di grass_blade.gdshader `terrain_wave()`
##     & shader tanah world.gd — WAJIB disamakan kalau diubah!) supaya
##     rumput+pohon+tanah visual semua mengikuti gelombang YANG SAMA, dan
##     posisi-Y pemain (world.height_at-> terrain_wave di mode ini) TIDAK
##     pernah tembus/kemengambang dr tanah visual.
##   - streaming scatter per chunk 34m: deter. seed koordinat; simpul chunk
##     berisi (a) MultiMeshInstance per JENIS prop (bkn per-instance node,
##     junction mutlak: draw-call prop ~8/chunk, bukan ~60), (b) static-body
##     silinder HANYA utk pohon (jalan terhalang spt hutan betulan).
##   - fog+optimize dilakukan world.gd (kulit hitam).
##
## Aset dipakai dr packs/build_mode/objects/nature (Quaternius CC0; pack
## build_mode selalu rtermuat di runtime, lihat manifest server).

const CHUNK_SIZE := 34.0
const RENDER_RADIUS := 1         # 3x3 chunk — jangkauan prop (fog menyembunyikan yg lbh jauh; OPTIMASI sudah)
const UNLOAD_RADIUS := 2
const MAX_PER_FRAME := 2         # chunk baru diboleh dibuat tiap frame (hindari hentakan)

# Gelombang datar-bergelombang (SYNC RUMUS dgn 2 shader, lihat header atas).
# Amplitudo total max ~0.6m — landai, bertekstur melalui tarikan panjang.
static func terrain_wave(x: float, z: float) -> float:
	return 0.34 * sin(x * 0.031 + 1.7) + 0.30 * sin(z * 0.036 + 0.3) * cos(x * 0.023)

# Pohon pakai goros diametris skala lebih besar dr build-mode (framing akhir
# tetap terasa "hutan", tak interactive-biji-object); rumpun kecil (semak/
# pakis/jamur) skala mirip katalog.
const PROP_TYPES := [
	# clusters: 0=pohon (collider), 1=batu, 2=semak, 3=jamur, 4=bunga/pakis
	{"id": "CommonTree_1",  "path": "res://packs/build_mode/objects/nature/CommonTree_1.gltf",  "kind": 0, "n_min": 1, "n_max": 2, "s_min": 1.15, "s_max": 1.65},
	{"id": "CommonTree_2",  "path": "res://packs/build_mode/objects/nature/CommonTree_2.gltf",  "kind": 0, "n_min": 1, "n_max": 2, "s_min": 1.05, "s_max": 1.55},
	{"id": "CommonTree_3",  "path": "res://packs/build_mode/objects/nature/CommonTree_3.gltf",  "kind": 0, "n_min": 0, "n_max": 1, "s_min": 1.15, "s_max": 1.60},
	{"id": "Pine_1",        "path": "res://packs/build_mode/objects/nature/Pine_1.gltf",        "kind": 0, "n_min": 0, "n_max": 1, "s_min": 1.25, "s_max": 1.75},
	{"id": "Rock_Medium_1", "path": "res://packs/build_mode/objects/nature/Rock_Medium_1.gltf", "kind": 1, "n_min": 1, "n_max": 2, "s_min": 0.90, "s_max": 1.50},
	{"id": "Rock_Medium_2", "path": "res://packs/build_mode/objects/nature/Rock_Medium_2.gltf", "kind": 1, "n_min": 0, "n_max": 1, "s_min": 0.95, "s_max": 1.45},
	{"id": "Bush_Common",   "path": "res://packs/build_mode/objects/nature/Bush_Common.gltf",   "kind": 2, "n_min": 1, "n_max": 2, "s_min": 0.95, "s_max": 1.35},
	{"id": "Bush_Common_Flowers", "path": "res://packs/build_mode/objects/nature/Bush_Common_Flowers.gltf", "kind": 2, "n_min": 0, "n_max": 1, "s_min": 0.95, "s_max": 1.25},
	{"id": "Fern_1",        "path": "res://packs/build_mode/objects/nature/Fern_1.gltf",        "kind": 2, "n_min": 0, "n_max": 2, "s_min": 1.10, "s_max": 1.45},
	{"id": "Mushroom_Common", "path": "res://packs/build_mode/objects/nature/Mushroom_Common.gltf", "kind": 3, "n_min": 0, "n_max": 2, "s_min": 0.90, "s_max": 1.30},
	{"id": "Flower_3_Group",  "path": "res://packs/build_mode/objects/nature/Flower_3_Group.gltf",  "kind": 4, "n_min": 0, "n_max": 1, "s_min": 0.95, "s_max": 1.30},
	{"id": "Grass_Common_Tall", "path": "res://packs/build_mode/objects/nature/Grass_Common_Tall.gltf", "kind": 4, "n_min": 1, "n_max": 3, "s_min": 1.00, "s_max": 1.45},
]

const OUTLINE_SHADER := preload("res://packs/shaders_materials/outline.gdshader")

var world: Node3D
var player: Node3D
var active := false
var _chunks := {}                # Vector2i -> Node3D (wadah satu chunk)
var _last := Vector2i(9999999, 9999999)
var _bodies_shape: Shape3D       # silinder collider pohon (dibagi semua)
var _outline_mat: ShaderMaterial # 1 material outline dibagi semua prop
var _mesh_cache := {}            # id -> {"scn": PackedScene}

func set_actors(w: Node3D, p: Node3D) -> void:
	world = w
	player = p

func _ready() -> void:
	_outline_mat = ShaderMaterial.new()
	_outline_mat.shader = OUTLINE_SHADER
	_outline_mat.set_shader_parameter("outline_color", Color(0.16, 0.14, 0.12, 1.0))
	_outline_mat.set_shader_parameter("thickness", 0.011)   # outline TIPIS (permintaan user)
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.34
	cyl.height = 5.0
	_bodies_shape = cyl

## Aktif/nonaktif penuh. Dipanggil world.set_open_world_mode().
func enable() -> void:
	if active:
		return
	active = true
	visible = true
	_last = Vector2i(9999999, 9999999)   # paksa stream ulang ratioan frame ini

func disable() -> void:
	if not active:
		return
	active = false
	visible = false
	# bongkar sekaligus (bug falsy _chunks.clear() next frame tetap lambat
	# kalau node mati-hidden dibareng-bareng); hutan hanya berfungsi kalau
	# mode-nya on, jd aman queue_free semuanya.
	for c in _chunks.values():
		if is_instance_valid(c):
			c.queue_free()
	_chunks.clear()

## Dipanggil tiap _process world (hanya saat mode aktif). Streaming chunk
## scatter berpusat petak pemain (spt sistem grass): muat dlm radius,
## bongkar di luar histeresis. Rendering fog global (world._apply_open_world
## _env) menyembunyikan yg jauh — jangkau-muat diset kecil (OPTIMASI kunci).
func tick_stream() -> void:
	if not active or player == null:
		return
	var pcx := int(floor(player.global_position.x / CHUNK_SIZE))
	var pcz := int(floor(player.global_position.z / CHUNK_SIZE))
	var pc := Vector2i(pcx, pcz)
	var built := 0
	# bongkar yg telat jauh
	for coord in _chunks.keys():
		if coord.distance_to(pc) > float(UNLOAD_RADIUS):
			var n = _chunks[coord]
			_chunks.erase(coord)
			if is_instance_valid(n):
				n.queue_free()
	# bangun yg baru (budget MAX_PER_FRAME)
	for dx in range(-RENDER_RADIUS, RENDER_RADIUS + 1):
		for dz in range(-RENDER_RADIUS, RENDER_RADIUS + 1):
			var c := Vector2i(pcx + dx, pcz + dz)
			if _chunks.has(c) or built >= MAX_PER_FRAME:
				continue
			_build_chunk(c)
			built += 1

## RNG deterministik dr koordinat chunk (layout stabil kembali-datangi).
func _chunk_seed(coord: Vector2i, salt: int) -> int:
	var h := (int(coord.x) * 73856093) ^ (int(coord.y) * 19349663) ^ (salt * 83492791) ^ 1123495023
	return absi(h)

## Bangun satu chunk scatter: per-jenis satu MultiMeshInstance (transforms
## bergelombang terrain_wave dr header), + collider pohon.
func _build_chunk(coord: Vector2i) -> void:
	var root := Node3D.new()
	root.name = "OWChunk_%d_%d" % [coord.x, coord.y]
	add_child(root)
	_chunks[coord] = root
	var base_x := coord.x * CHUNK_SIZE
	var base_z := coord.y * CHUNK_SIZE
	for i in range(PROP_TYPES.size()):
		var t: Dictionary = PROP_TYPES[i]
		var rng := RandomNumberGenerator.new()
		rng.seed = _chunk_seed(coord, 31 + i)
		var n := rng.randi_range(int(t["n_min"]), int(t["n_max"]))
		if n <= 0:
			continue
		var scn := _get_scene(String(t["id"]))
		if scn == null:
			continue
		# MultiMeshInstance berisi n transform (mesh+material dr glb; satu
		# draw-call per jenis per chunk — OPTIMASI penarikan draw-call).
		var mmi := MultiMeshInstance3D.new()
		var mesh: Mesh
		for j in range(n):
			var px := base_x + rng.randf_range(2.0, CHUNK_SIZE - 2.0)
			var pz := base_z + rng.randf_range(2.0, CHUNK_SIZE - 2.0)
			var sc := rng.randf_range(float(t["s_min"]), float(t["s_max"]))
			var ang := rng.randf_range(0.0, TAU)
			var py := terrain_wave(px, pz)   # sims dgn tanah & rumput
			var basis := Basis(Vector3.UP, ang).scaled(Vector3(sc, sc, sc))
			if mesh == null:
				# pertamanya: extract mesh pertama dr scene (butuh sekali per jenis)
				mesh = _extract_mesh(scn)
				if mesh == null:
					break
			if j == 0:
				var mm := MultiMesh.new()
				mm.transform_format = MultiMesh.TRANSFORM_3D
				mm.mesh = mesh
				mm.instance_count = n
				mmi.multimesh = mm
				# material_overlay = outline tipis (inverted-hull tambahan;
				# material asli glb TETAP utuh — pass 2 tambahan saja).
				mmi.material_overlay = _outline_mat
				if int(t["kind"]) != 0:
					mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				root.add_child(mmi)
			mmi.multimesh.set_instance_transform(j, Transform3D(basis, Vector3(px, py, pz)))
			if int(t["kind"]) == 0:
				# Collider pohon: jalan/lari TERHALANG batang (hutan betulan),
				# semak/batu/jamur sengaja bebas dilewati.
				var body := StaticBody3D.new()
				var col := CollisionShape3D.new()
				col.shape = _bodies_shape
				col.position = Vector3(px, py + 2.2, pz)
				body.add_child(col)
				body.collision_layer = 1
				body.collision_mask = 0
				root.add_child(body)

var _extract_cache := {}
func _get_scene(id: String) -> PackedScene:
	if _mesh_cache.has(id):
		return _mesh_cache[id]
	for t in PROP_TYPES:
		if String(t["id"]) == id:
			var ps: PackedScene = null
			if ResourceLoader.exists(String(t["path"])):
				ps = load(String(t["path"])) as PackedScene
			_mesh_cache[id] = ps
			return ps
	return null

## Tarik mesh pertama dr scene glb (Quaternius: satu node glb = satu mesh
## dg multi-surface). Nilai kembalian diserahkan MultiMesh (shader material
## glb ikut melalui surface-materials mesh tsb).
func _extract_mesh(scn: PackedScene) -> Mesh:
	var inst := scn.instantiate()
	var m := _find_mesh(inst)
	inst.queue_free()   # node proxy dibuang; mesh Resource tetap hidup (shared)
	return m

func _find_mesh(n: Node) -> Mesh:
	if n is MeshInstance3D and n.mesh != null:
		return n.mesh
	for c in n.get_children():
		var m := _find_mesh(c)
		if m != null:
			return m
	return null
