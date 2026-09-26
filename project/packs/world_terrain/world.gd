extends Node3D
## World: DUNIA DATAR TANPA BATAS bergaya sihir open-world (ronde-46, pivot
## balik dari game tank ke tema penyihir anime). Bidang datar tak berujung
## (visual mengikuti pemain + collider bidang WorldBoundaryShape3D — POLA
## SEDERHANA, bukan trimesh ⇒ is_on_floor() engine selalu benar). Reruntuhan/
## dinding batu destructible acak (wall_system.gd) dipertahankan sebagai
## rintangan & pemandangan dunia terbuka.
##
## Bag. C (permintaan pengguna): tanah rumput lebat (tekstur + tumpuk rumput
## 3D MultiMesh dekat pemain, lihat _build_grass), kabut "batas pandang"
## HANYA di kejauhan (FOG_MODE_DEPTH, lihat _setup_environment — dekat pemain
## SELALU jernih), dan dunia dikunci MALAM PERMANEN dgn langit berbintang +
## bulan (siklus siang-malam lama, SKY_PRESETS, & slider debug "Mode Edit"
## tetap dipertahankan kodenya, cuma tak lagi auto-berjalan — lihat
## _tick_daynight). Mantra andalan yang dipoles (bag. B) menyusul. API
## platform tetap lengkap agar HUD/pemain/game_root tidak perlu berubah.

signal gen_progress(p: float, t: String)

const Materials := preload("res://packs/shaders_materials/materials.gd")
const SKY_SHADER := preload("res://packs/shaders_materials/sky.gdshader")
const GRASS_SHADER := preload("res://packs/shaders_materials/grass_blade.gdshader")
const WALL_SYSTEM := preload("res://packs/world_terrain/wall_system.gd")

var player: Node3D
var quality_ref
var faceted := false          # stub: tak ada world lagi untuk di-facet
var world_env: WorldEnvironment
var sun: DirectionalLight3D
var sky_mat: ShaderMaterial
# Ronde-46 bag. C (permintaan pengguna): dunia SELALU malam sekarang — siklus
# siang-malam otomatis DIMATIKAN (lihat _tick_daynight). time_of_day dikunci
# di jam malam tetap; nilai ini juga menentukan posisi tetap bulan di langit.
var time_of_day := 1.0

var _root: Node
var _ground: MeshInstance3D   # bidang raksasa yang menyentak mengikuti pemain
var wall_system: Node3D       # reruntuhan/dinding batu destructible — rintangan & pemandangan dunia
const GROUND_SIZE := 1600.0
var interactables := []       # kosong; dipertahankan utk kompatibilitas API

# ---------------- rumput lebat dekat pemain (ronde-46 bag. C) ----------------
# Rumput 3D penuh sejauh 1600m tak mungkin (hemat mobile) — jadi HANYA area
# dekat pemain dipenuhi tumpuk rumput (MultiMesh, satu draw call), sisanya
# memakai tekstur rumput datar di material tanah. Radius sengaja SEDIKIT
# LEBIH KECIL dari titik mulai kabut (fog_depth_begin) supaya tepi rumput
# "disamarkan" oleh kabut yang baru mulai muncul, bukan terlihat sbg batas
# tajam di udara jernih.
const GRASS_RADIUS := 42.0
const GRASS_COUNT := 9000
var _grass_mmi: MultiMeshInstance3D

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
	_build_grass()

## Lantai RUMPUT LEBAT (ronde-46 bag. C — ganti dari grid biru-putih ala
## blueprint sebelumnya). Tekstur foto rumput (`detail_grass.jpg`, sudah ada
## di aset) di-tile di ruang-dunia (bukan UV lokal mesh) supaya polanya diam
## di tempat walau bidang menyentak mengikuti pemain; ditambah noise petak
## skala-besar (2 corak hijau) biar tak terasa monoton berulang, lalu diberi
## shading toon 2-tingkat senada dgn gaya seluruh game.
func _make_ground_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode cull_back, depth_draw_opaque;
uniform sampler2D grass_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 tint_a : source_color = vec3(0.09, 0.20, 0.09);  // corak gelap
uniform vec3 tint_b : source_color = vec3(0.15, 0.32, 0.14);  // corak terang
uniform float tex_scale = 0.35;    // kerapatan ulang tekstur foto (per meter)
uniform float patch_scale = 0.02;  // skala noise petak corak besar
uniform float shadow_tint : hint_range(0.0, 1.0) = 0.50;
uniform float mid_tint : hint_range(0.0, 1.0) = 0.82;
varying vec3 wp;

float gh(vec2 p) { return fract(sin(dot(p, vec2(41.3, 289.1))) * 43758.5453); }
float gnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float a = gh(i);
	float b = gh(i + vec2(1.0, 0.0));
	float c = gh(i + vec2(0.0, 1.0));
	float d = gh(i + vec2(1.0, 1.0));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }

void fragment() {
	vec3 tex = texture(grass_tex, wp.xz * tex_scale).rgb;
	float patch = gnoise(wp.xz * patch_scale);
	vec3 tint = mix(tint_a, tint_b, patch);
	ALBEDO = tex * tint * 2.4;
	ROUGHNESS = 0.95;
	SPECULAR = 0.0;
}

void light() {
	float l = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	float b = shadow_tint
		+ (mid_tint - shadow_tint) * smoothstep(0.15, 0.45, l)
		+ (1.0 - mid_tint) * smoothstep(0.55, 0.85, l);
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * b * ATTENUATION;
}
"""
	mat.shader = sh
	mat.set_shader_parameter("grass_tex", Materials.TERRAIN_DETAIL_G)
	return mat

## Tumpuk rumput 3D dekat pemain (MultiMesh, 1 draw call) — bag. "lebat" dari
## permintaan user: tekstur datar saja terasa rata, tumpuk rumput kecil ini
## memberi kedalaman/volume. Setiap instance = tuft 3 helai bersilang (murah,
## 9 verts/3 tri) diputar+diskalakan acak, dgn goyangan angin & varian warna
## per-instance di grass_blade.gdshader. Posisi mengikuti pemain persis
## seperti _ground (lihat _process) supaya selalu "penuh" di sekitar kaki.
func _build_grass() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _build_grass_blade_mesh()
	mm.instance_count = GRASS_COUNT
	var rng := RandomNumberGenerator.new()
	rng.seed = 20460301
	var placed := 0
	var attempts := 0
	while placed < GRASS_COUNT and attempts < GRASS_COUNT * 4:
		attempts += 1
		var x := rng.randf_range(-GRASS_RADIUS, GRASS_RADIUS)
		var z := rng.randf_range(-GRASS_RADIUS, GRASS_RADIUS)
		if Vector2(x, z).length() > GRASS_RADIUS:
			continue
		var s := rng.randf_range(0.75, 1.35)
		var basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU))
		basis = basis.scaled(Vector3(s, s * rng.randf_range(0.8, 1.3), s))
		mm.set_instance_transform(placed, Transform3D(basis, Vector3(x, 0.0, z)))
		mm.set_instance_custom_data(placed, Color(rng.randf(), rng.randf(), 0.0, 0.0))
		placed += 1
	# sisa slot (kalau ada, jarang terjadi) ditumpuk di tengah biar tak nol-skala aneh
	while placed < GRASS_COUNT:
		mm.set_instance_transform(placed, Transform3D(Basis(), Vector3.ZERO))
		placed += 1
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "GrassBlades"
	mmi.multimesh = mm
	mmi.material_override = _grass_material()
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.extra_cull_margin = GRASS_RADIUS
	add_child(mmi)
	_grass_mmi = mmi

## Mesh 1 tuft rumput: 3 helai (segitiga) tersusun bersilang membentuk bintang
## dari atas, tiap helai punya sedikit "condong" di ujung biar tak kaku lurus.
## Warna vertex.a dipakai grass_blade.gdshader sbg bobot tinggi (0=akar,1=ujung).
func _build_grass_blade_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := 0.40
	var w := 0.05
	var lean := 0.09
	for i in range(3):
		var rot := Basis(Vector3.UP, deg_to_rad(60.0 * i))
		var bl := rot * Vector3(-w * 0.5, 0.0, 0.0)
		var br := rot * Vector3(w * 0.5, 0.0, 0.0)
		var tip := rot * Vector3(0.0, h, lean)
		st.set_color(Color(1, 1, 1, 0.0))
		st.add_vertex(bl)
		st.set_color(Color(1, 1, 1, 0.0))
		st.add_vertex(br)
		st.set_color(Color(1, 1, 1, 1.0))
		st.add_vertex(tip)
	st.generate_normals()
	return st.commit()

## Material batang rumput: goyangan angin + shading toon + varian warna per-
## instance (lihat grass_blade.gdshader). cull_disabled di shader itu sendiri.
func _grass_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = GRASS_SHADER
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
	if is_instance_valid(_grass_mmi) and _grass_mmi.multimesh:
		var gd_frac := clampf(float(p.get("grass_density", 1.0)), 0.0, 1.0)
		_grass_mmi.multimesh.visible_instance_count = int(round(GRASS_COUNT * gd_frac))
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
	# Ronde-46 bag. C (permintaan pengguna): "batas pandang" berkabut HANYA
	# di kejauhan, area dekat pemain tetap jernih. Mode default Environment
	# (FOG_MODE_EXPONENTIAL) mengabur dari dekat scr bertahap — TIDAK cocok.
	# FOG_MODE_DEPTH dipakai supaya fog_depth_begin/end jadi aktif: jernih
	# total sampai fog_depth_begin meter, baru mulai menebal ke fog_depth_end.
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_depth_begin = 45.0
	env.fog_depth_end = 160.0
	env.fog_depth_curve = 1.6
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
	if player and _grass_mmi:
		_grass_mmi.position.x = player.global_position.x
		_grass_mmi.position.z = player.global_position.z

func _tick_daynight(_delta: float) -> void:
	# Ronde-46 bag. C (permintaan pengguna): dunia SELALU malam sekarang —
	# siklus siang-malam otomatis DIMATIKAN, time_of_day tak lagi berjalan.
	# _apply_daylight()/SKY_PRESETS/slider "Mode Edit" TETAP dipertahankan
	# utuh (tak dihapus) — masih bisa dipakai manual lewat apply_lighting()
	# kalau suatu saat perlu dibuka lagi; hanya auto-jalannya yang berhenti.
	pass

var _dl_last := -1.0

func _apply_daylight() -> void:
	if abs(time_of_day - _dl_last) < 0.05:
		return
	_dl_last = time_of_day
	var t := time_of_day
	var dayf := sin((t - 6.0) / 12.0 * PI)
	# Lantai elevasi dinaikkan 14->30 (bag. C: dunia SELALU malam sekarang,
	# jadi lantai ini SELALU yang dipakai) supaya bulan tergantung lebih
	# tinggi & jelas terlihat, bukan nempel rendah di cakrawala.
	var elev := maxf(dayf * 62.0, 30.0)
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
		sky_mat.set_shader_parameter("star_visibility", 0.0)
		sky_mat.set_shader_parameter("sun_size", 0.035)
		sky_mat.set_shader_parameter("halo", 0.22)
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
		sky_mat.set_shader_parameter("star_visibility", 0.0)
		sky_mat.set_shader_parameter("sun_size", 0.035)
		sky_mat.set_shader_parameter("halo", 0.22)
	else:
		# MALAM (bag. C: satu-satunya cabang yg dipakai sekarang krn dunia
		# dikunci malam permanen) — DirectionalLight jadi "cahaya bulan" pucat
		# biru, cakram sky yg sama dipakai sbg BULAN (dibesarkan+dihalo lebih
		# lembut drpd matahari), langit gelap dgn bintang bertaburan & berkelap.
		sun.light_color = Color(0.55, 0.65, 0.90)
		sun.light_energy = 0.34
		env.ambient_light_color = Color(0.30, 0.38, 0.46)
		env.ambient_light_energy = 0.62
		env.fog_light_color = Color(0.14, 0.19, 0.26)
		sky_mat.set_shader_parameter("zenith_color", Color(0.05, 0.09, 0.16))
		sky_mat.set_shader_parameter("horizon_color", Color(0.10, 0.15, 0.22))
		sky_mat.set_shader_parameter("ground_color", Color(0.07, 0.11, 0.16))
		sky_mat.set_shader_parameter("sun_color", Color(0.85, 0.88, 0.95))
		sky_mat.set_shader_parameter("star_visibility", 1.0)
		sky_mat.set_shader_parameter("sun_size", 0.07)
		sky_mat.set_shader_parameter("halo", 0.30)
	# Di FOG_MODE_DEPTH, fog_density BUKAN lagi koefisien eksponensial —
	# artinya opasitas MAKSIMUM kabut tepat di fog_depth_end (0=tak
	# kelihatan, 1=menutup total). _lo.fog/_q_fog tetap dipakai sbg pengali
	# spt sebelumnya (slider debug & preset kualitas).
	env.fog_density = clampf(0.92 * float(_lo.fog) * _q_fog, 0.0, 1.0)
	# jarak kabut menyusut sedikit di preset kualitas Rendah (_q_fog>1) —
	# selain hemat gambar jauh, juga menyamarkan pop-in objek.
	env.fog_depth_end = 160.0 / maxf(_q_fog, 0.4)
	sun.light_energy *= float(_lo.sun)
	env.ambient_light_energy *= float(_lo.ambient)
	if int(_lo.sky) >= 0 and int(_lo.sky) < SKY_PRESETS.size():
		var pr: Array = SKY_PRESETS[int(_lo.sky)]
		sky_mat.set_shader_parameter("zenith_color", pr[0])
		sky_mat.set_shader_parameter("horizon_color", pr[1])
