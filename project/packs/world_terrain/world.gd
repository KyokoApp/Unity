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
const CHUNK_SIZE := 100.0
const GRID := 16
const WORLD_SEED := 20260919
const WORLD_SIZE := 1600.0

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
var time_of_day := 9.6    # jam (mulai pagi yang cerah)
const DAY_LENGTH := 420.0 # detik untuk 24 jam penuh
var chunk_rings := 6
var forest_pack: Node
var beach_pack: Node
var interactables := []
var quality_ref
var _seeded := false

func _ready() -> void:
	name = "World"

# ---------------- boot ----------------

func generate_async(_root: Node) -> void:
	_report(0.0, "Membangun pulau…")
	island = IslandScript.new(WORLD_SEED, WORLD_SIZE)
	_progress_done = 0
	_progress_total = 1 + 1 + 25 + 2  # shore map + laut + chunk awal + 2 pack props
	terr_mat = Materials.toon_vertex_color(false)
	_setup_environment()
	await _gen_shore_map_async()
	_report_step("Menyiapkan lautan…")
	_setup_water()
	await _initial_chunks()
	await _load_prop_packs()
	_report(1.0, "Dunia siap")

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
<<<<<<< HEAD
	env.ambient_light_color = Color(0.55, 0.62, 0.72)
=======
	env.ambient_light_color = Color(0.58, 0.66, 0.66)
>>>>>>> a7dedaa (style: palet turquoise pastel seluruh game + pratinjau eksposur CPU (siang/senja/malam))
	env.ambient_light_energy = 0.95
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	env.fog_enabled = true
<<<<<<< HEAD
	env.fog_light_color = Color(0.60, 0.70, 0.82)
=======
	env.fog_light_color = Color(0.66, 0.82, 0.76)
>>>>>>> a7dedaa (style: palet turquoise pastel seluruh game + pratinjau eksposur CPU (siang/senja/malam))
	env.fog_density = 0.0009
	env.fog_sky_affect = 0.3
	world_env.environment = env
	add_child(world_env)

	sun = DirectionalLight3D.new()
<<<<<<< HEAD
	sun.light_color = Color(1.0, 0.93, 0.80)
=======
	sun.light_color = Color(1.0, 0.90, 0.72)
>>>>>>> a7dedaa (style: palet turquoise pastel seluruh game + pratinjau eksposur CPU (siang/senja/malam))
	sun.light_energy = 1.05
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
	return Vector2i(floori(x / CHUNK_SIZE) + 8, floori(z / CHUNK_SIZE) + 8)

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
	var data := ChunkScript.build_mesh_data(island, cx, cy, lod)
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
	return island.find_spawn_point()

func height_at(x: float, z: float) -> float:
	return island.height_at(x, z)

func get_island():
	return island

func apply_quality(p: Dictionary) -> void:
	chunk_rings = int(p.chunk_rings)
	if world_env:
		world_env.environment.fog_density = 0.0009 * float(p.fog)
	if forest_pack:
		forest_pack.call("apply_density", float(p.tree_density), float(p.grass_density))
	if beach_pack:
		beach_pack.call("apply_density", float(p.tree_density), float(p.grass_density))

func _process(delta: float) -> void:
	_integrate_results(2)
	_stream_timer -= delta
	if _stream_timer <= 0.0:
		_stream_timer = 0.4
		if _initial_pending and building.is_empty() and _results_count() == 0:
			_initial_pending = false
			_initial_done = true
		_update_streaming_player_chunk()
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
		# siang
		var k := smoothstep(0.15, 0.85, dayf)
<<<<<<< HEAD
		sun.light_color = Color(1.0, 0.93, 0.80).lerp(Color(1.0, 0.98, 0.92), k)
		sun.light_energy = 0.95 + 0.15 * k
		sun.shadow_enabled = quality_ref.get_preset().shadows if quality_ref else true
		env.ambient_light_color = Color(0.55, 0.62, 0.72)
		env.ambient_light_energy = 0.95
		env.fog_light_color = Color(0.60, 0.70, 0.82)
		sky_mat.set_shader_parameter("zenith_color", Color(0.22, 0.50, 0.85))
		sky_mat.set_shader_parameter("horizon_color", Color(0.75, 0.85, 0.95))
		sky_mat.set_shader_parameter("ground_color", Color(0.28, 0.32, 0.38))
		sky_mat.set_shader_parameter("sun_color", Color(1.0, 0.92, 0.72))
=======
		sun.light_color = Color(1.0, 0.90, 0.72).lerp(Color(1.0, 0.96, 0.86), k)
		sun.light_energy = 0.95 + 0.15 * k
		sun.shadow_enabled = quality_ref.get_preset().shadows if quality_ref else true
		env.ambient_light_color = Color(0.58, 0.66, 0.66)
		env.ambient_light_energy = 0.95
		env.fog_light_color = Color(0.66, 0.82, 0.76)
		sky_mat.set_shader_parameter("zenith_color", Color(0.30, 0.74, 0.69))
		sky_mat.set_shader_parameter("horizon_color", Color(0.86, 0.95, 0.86))
		sky_mat.set_shader_parameter("ground_color", Color(0.36, 0.44, 0.44))
		sky_mat.set_shader_parameter("sun_color", Color(1.0, 0.94, 0.74))
>>>>>>> a7dedaa (style: palet turquoise pastel seluruh game + pratinjau eksposur CPU (siang/senja/malam))
	elif dayf > -0.12:
		# senja/fajar
		var k := smoothstep(-0.12, 0.15, dayf)
		sun.light_color = Color(1.0, 0.55, 0.34).lerp(Color(1.0, 0.93, 0.80), k)
		sun.light_energy = 0.55 + 0.5 * k
<<<<<<< HEAD
		env.ambient_light_color = Color(0.55, 0.45, 0.50).lerp(Color(0.55, 0.62, 0.72), k)
		env.ambient_light_energy = 0.62 + 0.33 * k
		env.fog_light_color = Color(0.72, 0.52, 0.42).lerp(Color(0.60, 0.70, 0.82), k)
		sky_mat.set_shader_parameter("zenith_color", Color(0.10, 0.14, 0.30).lerp(Color(0.22, 0.50, 0.85), k))
		sky_mat.set_shader_parameter("horizon_color", Color(0.90, 0.52, 0.36).lerp(Color(0.75, 0.85, 0.95), k))
		sky_mat.set_shader_parameter("sun_color", Color(1.0, 0.62, 0.30))
=======
		env.ambient_light_color = Color(0.56, 0.50, 0.52).lerp(Color(0.58, 0.66, 0.66), k)
		env.ambient_light_energy = 0.62 + 0.33 * k
		env.fog_light_color = Color(0.82, 0.64, 0.50).lerp(Color(0.66, 0.82, 0.76), k)
		sky_mat.set_shader_parameter("zenith_color", Color(0.16, 0.34, 0.44).lerp(Color(0.30, 0.74, 0.69), k))
		sky_mat.set_shader_parameter("horizon_color", Color(0.98, 0.68, 0.42).lerp(Color(0.86, 0.95, 0.86), k))
		sky_mat.set_shader_parameter("sun_color", Color(1.0, 0.66, 0.34))
>>>>>>> a7dedaa (style: palet turquoise pastel seluruh game + pratinjau eksposur CPU (siang/senja/malam))
	else:
		# malam: tetap terbaca, tidak gelap pekat
		sun.light_color = Color(0.55, 0.65, 0.90)
		sun.light_energy = 0.34
<<<<<<< HEAD
		env.ambient_light_color = Color(0.30, 0.36, 0.52)
		env.ambient_light_energy = 0.62
		env.fog_light_color = Color(0.16, 0.20, 0.30)
		sky_mat.set_shader_parameter("zenith_color", Color(0.04, 0.06, 0.14))
		sky_mat.set_shader_parameter("horizon_color", Color(0.09, 0.12, 0.20))
		sky_mat.set_shader_parameter("sun_color", Color(0.8, 0.85, 1.0))
=======
		env.ambient_light_color = Color(0.30, 0.38, 0.46)
		env.ambient_light_energy = 0.62
		env.fog_light_color = Color(0.14, 0.19, 0.26)
		sky_mat.set_shader_parameter("zenith_color", Color(0.05, 0.09, 0.16))
		sky_mat.set_shader_parameter("horizon_color", Color(0.10, 0.15, 0.22))
		sky_mat.set_shader_parameter("sun_color", Color(0.62, 0.70, 0.85))
>>>>>>> a7dedaa (style: palet turquoise pastel seluruh game + pratinjau eksposur CPU (siang/senja/malam))
	env.fog_density = 0.0009 * (quality_ref.get_preset().fog if quality_ref else 1.0)
