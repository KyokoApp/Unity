extends Node3D
## World: DUNIA DATAR TANPA BATAS — medan tempur tank (ronde-45, pivot dari
## game mage/monster). Bidang datar tak berujung (visual mengikuti pemain +
## collider bidang WorldBoundaryShape3D — POLA SEDERHANA, bukan trimesh ⇒
## is_on_floor() engine selalu benar), langit kartun + siklus siang-malam
## dipertahankan utuh. Rintangan medan tempur: dinding/bunker destructible
## acak (wall_system.gd). Roster tank musuh (wave survival) menyusul di
## Bagian B ronde-45. API platform tetap lengkap agar HUD/pemain/game_root
## tidak perlu berubah.

signal gen_progress(p: float, t: String)

const Materials := preload("res://packs/shaders_materials/materials.gd")
const SKY_SHADER := preload("res://packs/shaders_materials/sky.gdshader")
const WALL_SYSTEM := preload("res://packs/world_terrain/wall_system.gd")

var player: Node3D
var quality_ref
var faceted := false          # stub: tak ada world lagi untuk di-facet
var world_env: WorldEnvironment
var sun: DirectionalLight3D
var sky_mat: ShaderMaterial
var time_of_day := 16.4       # sore adem (cicilan ini boleh jalan terus)

var _root: Node
var _ground: MeshInstance3D   # bidang raksasa yang menyentak mengikuti pemain
var wall_system: Node3D       # dinding/bunker destructible — rintangan medan tempur tank
const GROUND_SIZE := 1600.0
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
	await get_tree().process_frame
	_report(0.5, "Membentangkan tanah datar…")
	_make_flat_ground()
	await get_tree().process_frame
	_report(0.8, "Menegakkan dinding/bunker medan tempur…")
	wall_system = WALL_SYSTEM.new()
	wall_system.name = "WallSystem"
	add_child(wall_system)
	await get_tree().process_frame
	_report(1.0, "Medan tempur siap")

## Bidang datar tak berbatas: SATU collider WorldBoundary (bidang y=0, normal
## atas) — tak ada tepi, tak ada trimesh, is_on_floor() engine selalu konstan.
## Visual: PlaneMesh 1600m yang menyentak digeser bersama pemain; pola tanah
## memakai UV RUANG-DUNIA sehingga gerakan tampak mulus.
func _make_flat_ground() -> void:
	_ground = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(GROUND_SIZE, GROUND_SIZE)
	pm.material = _make_ground_material()
	_ground.mesh = pm
	add_child(_ground)
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	col.shape = WorldBoundaryShape3D.new()  # bidang tak terbatas y=0, normal +Y
	body.add_child(col)
	add_child(body)

## Lantai GRID PUTIH ala blueprint (permintaan user: "dunia datar tanpa batas
## ada garis kotak-kotak putih"). Petak 1×1 m, garis tebal 2 cm, dilicinkan
## dengan fwidth (anti-alias) supaya tenang dari kamera top-down; UV ruang-
## dunia ⇒ mulus saat bidang mengikuti pemain. Dasar slate gelap (gaya
## rancangan); ubah `base` bila mau warna latar lain.
func _make_ground_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode cull_back, depth_draw_opaque;
uniform vec3 base : source_color = vec3(0.13, 0.17, 0.21);   // slate gelap
uniform vec3 line : source_color = vec3(1.0, 1.0, 1.0);      // garis putih
uniform float cell = 1.0;    // sisi petak (meter)
uniform float lw = 0.02;     // tebal garis (meter)
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 q = wp.xz / cell;
	vec2 g = abs(fract(q) - 0.5);
	float lv = max(g.x, g.y);
	float aa = fwidth(lv);
	float l = smoothstep(0.5 - lw / cell - aa, 0.5 - lw / cell + aa, lv);
	ALBEDO = mix(base, line, l);
	ROUGHNESS = 0.95;
	SPECULAR = 0.0;
}
"""
	mat.shader = sh
	return mat

# ---------------- API kompatibel ----------------

## Tanah datar murni: lantai SELALU y=0 di mana pun (tak ketemu = tak mungkin).
func height_at(_x: float, _z: float) -> float:
	return 0.0

func find_spawn_point() -> Vector3:
	return Vector3(0, 0.25, 0)

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
	pass

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

var _q_fog := 1.0   # pengali kabut dari preset kualitas

func apply_quality(p: Dictionary) -> void:
	_q_fog = float(p.get("fog", 1.0))
	if wall_system and wall_system.has_method("apply_quality"):
		wall_system.apply_quality(p)
	if world_env and world_env.environment:
		world_env.environment.glow_enabled = bool(p.get("glow", true))
	if sun:
		sun.shadow_enabled = bool(p.get("shadows", true))
	_dl_last = -1.0
	if world_env and sun:
		_apply_daylight()

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
	# glow lembut utk pijar sihir (permintaan user) — SETINGAN HEMAT khusus
	# mobile: radius kecil, tanpa level tinggi (post-process berat tetap no)
	# glow AKTIF lagi: bola api memakai warna HDR (>1.0) -> berpendar.
	# Preset Rendah mematikannya (QualityManager -> apply_quality "glow").
	env.glow_enabled = true
	env.glow_normalized = true
	env.glow_intensity = 0.8
	env.glow_strength = 1.0
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 0.9
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.set("glow_levels/1", true)
	env.set("glow_levels/2", false)
	env.set("glow_levels/3", true)
	env.set("glow_levels/4", false)
	env.set("glow_levels/5", true)
	env.set("glow_levels/6", false)
	env.set("glow_levels/7", false)
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
	# bidang visual mengikuti pemain (collider-nya sudah tak berujung)
	if player and _ground:
		_ground.position.x = player.global_position.x
		_ground.position.z = player.global_position.z

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
	env.fog_density = 0.0026 * float(_lo.fog) * _q_fog
	sun.light_energy *= float(_lo.sun)
	env.ambient_light_energy *= float(_lo.ambient)
	if int(_lo.sky) >= 0 and int(_lo.sky) < SKY_PRESETS.size():
		var pr: Array = SKY_PRESETS[int(_lo.sky)]
		sky_mat.set_shader_parameter("zenith_color", pr[0])
		sky_mat.set_shader_parameter("horizon_color", pr[1])
