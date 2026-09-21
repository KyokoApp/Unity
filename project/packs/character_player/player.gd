extends CharacterBody3D
## Player: kontroler third-person dengan dukungan touch (di-set dari HUD),
## jalan/lari/sprint/jongkok/renang, interaksi dunia, SFX langkah, dan
## blob shadow (untuk preset rendah). Model = GLB KayKit (Knight).

signal stats_changed(kind: String, count: int)
signal nearest_interactable_changed(meta)

const AnimControllerScript := preload("res://packs/animations/animation_controller.gd")
const Materials := preload("res://packs/shaders_materials/materials.gd")

# PENYIHIR PROSEDURAL: model 100% dibangun dari mesh primitif oleh kode
# (jubah kerucut + topi runcing + tongkat orb) — khusus genre top-down.
# Bukan sekadar pengganti sementara knight: nol berkas GLB, nol risiko lisensi,
# nol T-pose, dan ``anim'' sengaja null (gerak lucu digerakkan kode: bob/condong/
# putar). Skin GLB lama (knight/polygirl/UAL) DIHAPUS beserta berkasnya.
const SKINS := {
	"wizard": {"path": "", "height": 1.5, "states": {}},
}
var char_skin := "wizard"   # penyihir prosedural (tanpa GLB) — skin lama dihapus

# ------- gerak -------
const SPEED_WALK := 2.4
const SPEED_RUN := 4.8
const SPEED_SPRINT := 7.2
const SPEED_CROUCH := 1.5
const SPEED_SWIM := 2.6
const DASH_IMPULSE := 9.0
const DASH_CD := 0.9
const ACCEL := 16.0
const AIR_ACCEL := 5.0
const GRAVITY := 24.0
const JUMP_VEL := 7.4
const COYOTE := 0.12
const JUMP_BUFFER := 0.15

# kamera
const PITCH_MIN := deg_to_rad(-58.0)
const PITCH_MAX := deg_to_rad(34.0)
const CAM_DIST := 11.0      # top-down agak miring (permintaan "lihat dari atas")
const LOOK_K := 0.0036

var world: Node
var settings
var anim: AnimControllerScript
var model_root: Node3D
var model_pivot: Node3D
var cam_pivot: Node3D
var cam_arm: SpringArm3D
var col_shape: CollisionShape3D
var blob: MeshInstance3D

# input terakhir dari HUD
var joy := Vector2.ZERO       # -1..1 (y positif = maju)
var _look_vel := Vector2.ZERO # px yang diubah per detik
var yaw := 0.0
var pitch := deg_to_rad(-52.0)  # awal top-down; usapan tetap bisa memutar

var sprint := false
var crouch := false
var _jump_buffer := 0.0
var _coyote := 0.0
var _was_on_floor := false
var _swimming := false
var _last_fall_speed := 0.0
var is_ready := false

var step_timer := 0.0
var sfx := {}                 # nama -> AudioStreamPlayer3D
var _near := {}
var _near_timer := 0.0
var stats := {"flower": 0, "coconut": 0}
var head_offset_y := 0.0      # untuk efek visual renang
var _action_lock := 0.0
var _attack_alt := false
var _anim_probe := 0.0        # timer jejak anim on-device (diagnostik)
var _wiz_t := 0.0             # fase animasi kode penyihir (bob)
var _spin_t := 0.0            # sisa waktu putar saat emote
var _orb_node: MeshInstance3D # (warisan: tak dipakai — tongkat sudah dihapus)
var _hover_ring: MeshInstance3D # lingkaran sihir terbang (di bawah penyihir)
var _orbs := []               # proyektil sihir terbang: {n=node, v=vel, t=ttl}      # selang-seling attack/attack2 (pakai 2 animasi pukulan, bukan 1 terus)

func set_world(w: Node) -> void:
	world = w

func set_settings(s) -> void:
	settings = s

func _ready() -> void:
	col_shape = $Col
	model_pivot = $ModelPivot
	cam_pivot = $CameraPivot
	cam_arm = $CameraPivot/CamArm
	_load_skin()
	_make_blob_shadow()
	_make_sfx_players()
	# yaw awal menghadap laut? biarkan default; kamera mengikuti
	is_ready = true

func _load_skin() -> void:
	if model_root and is_instance_valid(model_root):
		model_root.queue_free()
	model_root = _build_wizard()
	model_pivot.add_child(model_root)
	anim = null  # sengaja: penyihir prosedural digerakkan kode (bob/condong/putar)
	var rootc = get_tree().current_scene
	if rootc and rootc.has_method("_trace"):
		rootc.call("_trace", "boot: skin = wizard prosedural ✔ (tanpa animasi GLB)")

## Bagian-bagian penyihir toon dari mesh primitif (outline tipis sesuai permintaan).
func _wiz_part(mesh: Mesh, color: Color, pos: Vector3,
			  rot_deg := Vector3.ZERO, unshaded := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	if unshaded:
		var sm := StandardMaterial3D.new()
		sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sm.albedo_color = color
		sm.emission_enabled = true
		sm.emission = color
		sm.emission_energy_multiplier = 2.2
		mi.material_override = sm
	else:
		mi.material_override = Materials.toon(color, true, 0.012)
	mi.position = pos
	mi.rotation_degrees = rot_deg
	return mi

func _wiz_part_with(mesh: Mesh, mat: Material, pos: Vector3, rot_deg := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	return mi

## JUBAH BERGELOMBANG: shader verteks bergelombang (amplitudo makin besar ke
## bawah) di atas warna toon penyihir — kain benar-benar bergerak saat terbang.
const ROBE_WAVE_GLSL := """
shader_type spatial;
render_mode cull_back, depth_draw_opaque;
uniform vec3 base : source_color = vec3(0.42, 0.30, 0.64);
uniform float wave_amp = 0.045;
uniform float wave_speed = 5.2;
uniform float wave_freq = 7.5;
void vertex() {
	float k = clamp(1.0 - (VERTEX.y) / 0.95, 0.0, 1.0);   // 0 di pundak, 1 di ujung bawah
	float a = atan(VERTEX.z, VERTEX.x);
	vec2 w = vec2(
		sin(TIME * wave_speed + a * 2.0 + VERTEX.y * wave_freq),
		cos(TIME * wave_speed * 0.83 + a * 3.0 - VERTEX.y * wave_freq * 0.7));
	VERTEX.xz += w * wave_amp * k;
}
void fragment() {
	ALBEDO = base;
	ROUGHNESS = 0.9;
	SPECULAR = 0.0;
}
"""
static var _robe_wave_shader: Shader

func _build_wizard() -> Node3D:
	var w := Node3D.new()
	w.name = "WizardRoot"
	if _robe_wave_shader == null:
		_robe_wave_shader = Shader.new()
		_robe_wave_shader.code = ROBE_WAVE_GLSL
	var robe := CylinderMesh.new()
	robe.bottom_radius = 0.36
	robe.top_radius = 0.14
	robe.height = 0.95
	robe.radial_segments = 24
	robe.rings = 20
	var robe_mat := ShaderMaterial.new()
	robe_mat.shader = _robe_wave_shader
	robe_mat.next_pass = Materials.make_outline(0.008)
	w.add_child(_wiz_part_with(robe, robe_mat, Vector3(0, 0.475, 0)))
	var belt := TorusMesh.new()
	belt.inner_radius = 0.135
	belt.outer_radius = 0.175
	w.add_child(_wiz_part(belt, Color(0.88, 0.70, 0.28), Vector3(0, 0.60, 0), Vector3(90, 0, 0)))
	var chest := SphereMesh.new()
	chest.radius = 0.17
	chest.height = 0.30
	w.add_child(_wiz_part(chest, Color(0.48, 0.35, 0.70), Vector3(0, 0.94, 0)))
	# kepala (muka SENGAJA tanpa mata — tertutup topi besar)
	var head := SphereMesh.new()
	head.radius = 0.145
	head.height = 0.26
	w.add_child(_wiz_part(head, Color(0.95, 0.83, 0.69), Vector3(0, 1.10, 0.01)))
	# TOPI DIPERBESAR menaungi muka: kerucut lebar, brim menjuntai doyong ke depan
	var hat := CylinderMesh.new()
	hat.bottom_radius = 0.21
	hat.top_radius = 0.0
	hat.height = 0.64
	hat.radial_segments = 20
	w.add_child(_wiz_part(hat, Color(0.35, 0.23, 0.54), Vector3(0, 1.40, -0.10), Vector3(-14, 0, 3)))
	var brim := TorusMesh.new()
	brim.inner_radius = 0.15
	brim.outer_radius = 0.385
	w.add_child(_wiz_part(brim, Color(0.35, 0.23, 0.54), Vector3(0, 1.17, 0.06), Vector3(80, 0, 3)))
	var star := SphereMesh.new()
	star.radius = 0.04
	star.height = 0.055
	w.add_child(_wiz_part(star, Color(1.0, 0.86, 0.35), Vector3(0.07, 1.33, 0.13), Vector3.ZERO, true))
	# [tongkat & orb DIHAPUS atas permintaan user — sihir kini dari tangan]
	# LINGKARAN SIHIR TERBANG (samar, berputar pelan, tinggal di tanah)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.42
	ring.outer_radius = 0.50
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	rm.albedo_color = Color(0.40, 0.95, 0.85, 0.34)
	rm.emission_enabled = true
	rm.emission = Color(0.40, 0.95, 0.85)
	rm.emission_energy_multiplier = 1.6
	_hover_ring = _wiz_part_with(ring, rm, Vector3(0, 0.045, 0), Vector3(90, 0, 0))
	model_pivot.add_child(_hover_ring)  # saudara model: tetap di tanah saat terbang
	return w

func _find_mesh_instances(n: Node, out: Array) -> void:
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		_find_mesh_instances(c, out)

## Ganti skin karakter saat bermain (dari pengaturan / mode edit).
func set_skin(id: String) -> void:
	if not SKINS.has(id) or id == char_skin and model_root != null:
		return
	char_skin = id
	if model_pivot:
		_load_skin()

func _make_blob_shadow() -> void:
	var img := Image.create(64, 64, false, Image.FORMAT_L8)
	for j in range(64):
		for i in range(64):
			var d := Vector2(i - 32, j - 32).length() / 30.0
			var a: int = 0 if d > 1.0 else int(150.0 * pow(1.0 - d, 1.6))
			img.set_pixel(i, j, Color(a / 255.0, a / 255.0, a / 255.0))
	var tex := ImageTexture.create_from_image(img)
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0, 0, 0, 0.55)
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.albedo_texture = tex
	bm.albedo_texture_force_srgb = true
	bm.no_depth_test = false
	var qm := QuadMesh.new()
	qm.size = Vector2(1.5, 1.5)
	blob = MeshInstance3D.new()
	blob.mesh = qm
	blob.rotation_degrees.x = -90
	blob.material_override = bm
	blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	blob.top_level = true
	blob.visible = false   # dipakai bila shadow GPU dimatikan
	add_child(blob)

func _make_sfx_players() -> void:
	for name in ["step1", "step2", "jump", "land", "splash", "pickup", "emote"]:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		p.volume_db = -6.0
		add_child(p)
		sfx[name] = p
	_load_sfx_file("step1", "res://packs/audio_sfx/footstep_1.wav")
	_load_sfx_file("step2", "res://packs/audio_sfx/footstep_2.wav")
	_load_sfx_file("jump", "res://packs/audio_sfx/jump.wav")
	_load_sfx_file("land", "res://packs/audio_sfx/land.wav")
	_load_sfx_file("splash", "res://packs/audio_sfx/splash.wav")
	_load_sfx_file("pickup", "res://packs/audio_sfx/pickup.wav")
	_load_sfx_file("emote", "res://packs/audio_sfx/emote.wav")

func _load_sfx_file(key: String, path: String) -> void:
	if ResourceLoader.exists(path):
		sfx[key].stream = load(path)

func _play(key: String) -> void:
	if sfx.has(key) and sfx[key].stream:
		sfx[key].play()

# =============== API dari HUD ===============

func set_joy(v: Vector2) -> void:
	joy = v

func add_look_px(dx: float, dy: float) -> void:
	_look_vel.x += dx * 60.0
	_look_vel.y += dy * 60.0

func press_jump() -> void:
	_jump_buffer = JUMP_BUFFER
	if _swimming:
		# keluar air: dorong ke atas permukaan
		velocity.y = maxf(velocity.y, 3.5)

func press_sprint(down: bool) -> void:
	sprint = down
	if sprint:
		crouch = false

## Dash: hentakan cepat searah gerak terakhir / arah hadap. Cooldown singkat.
var _dash_cd := 0.0
var _last_move_dir := Vector3(0, 0, -1)

func press_dash() -> void:
	if _dash_cd > 0.0 or _swimming:
		return
	_dash_cd = DASH_CD
	var dir := _last_move_dir
	if dir.length() < 0.1:
		dir = Basis(Vector3.UP, yaw) * Vector3(0, 0, -1)
	velocity.x = dir.x * DASH_IMPULSE
	velocity.z = dir.z * DASH_IMPULSE
	if anim:
		if anim.has("roll"):
			anim.action("roll", 320)
		elif anim.has("sprint"):
			anim.action("sprint", 320)

func press_crouch(down: bool) -> void:
	crouch = down
	_apply_crouch_shape()

## Toggle dari tombol HUD (satu ketuk = ubah stwsan). Versi hold dulu bisa
## nyangkut apabila jari bergeser sebelum diangkat (release tersesat).
func press_crouch_toggle() -> void:
	crouch = not crouch
	_apply_crouch_shape()

func press_interact() -> void:
	if _near and _action_lock <= 0.0:
		_do_interact(_near)

## Dipanggil QualityManager/GameRoot saat preset tanpa shadow GPU.
func set_blob_shadow(enabled: bool) -> void:
	if blob:
		blob.visible = enabled

func press_emote() -> void:
	if _action_lock > 0.0:
		return
	if anim:
		anim.action("emote", 1600)
		_action_lock = 1.2
		_play("emote")
	else:
		# penyihir prosedural: emote = putar riang + denyut orb
		_spin_t = 0.9
		_action_lock = 0.9
		_play("emote")

func press_attack() -> void:
	if _action_lock > 0.0:
		return
	if anim:
		var st := "attack2" if (_attack_alt and anim.has("attack2")) else "attack"
		_attack_alt = not _attack_alt
		anim.action(st, 600)
		_action_lock = 0.5
	else:
		# tembak orb sihir ke arah hadap karakter (versi awal: belum mengenai apa-apa)
		_cast_orb()
		_action_lock = 0.4

## Orb pijar: bola tak-terteduh + material emisi, terbang+pijar memudar saat lenyap.
# === SERANG DASAR SIHIR ===
# lapisan 1: denyut kilat di tangan, 2: inti proyektil + jejak partikel +
# lampu cyan, 3: ledakan kembang api + cincin gelombang + bekas hangus.
# Semua prosedural (lisensi bersih) — sprite glow radial dibangun di runtime.
static var _tex_glow: Texture2D
static func glow_tex() -> Texture2D:
	if _tex_glow:
		return _tex_glow
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for yy in range(64):
		for xx in range(64):
			var d: float = Vector2(xx - 31.5, yy - 31.5).length() / 31.5
			var aa: float = clampf(1.0 - d, 0.0, 1.0)
			aa = aa * aa * (3.0 - 2.0 * aa)
			img.set_pixel(xx, yy, Color(1, 1, 1, aa * aa))
	_tex_glow = ImageTexture.create_from_image(img)
	return _tex_glow

func _quad_mat(color: Color, energy := 2.2) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = glow_tex()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m

func _burst(pos: Vector3, color: Color, count: int, speed: float,
		life: float, size: float, gravity := Vector3.ZERO, spread := 1.0) -> void:
	var p := GPUParticles3D.new()
	p.amount = count
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = 0.92
	p.interpolate = true
	p.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.spread = 180.0 * spread
	pm.initial_velocity_min = speed * 0.45
	pm.initial_velocity_max = speed
	pm.angular_velocity_min = -60.0
	pm.angular_velocity_max = 60.0
	pm.gravity = gravity
	pm.scale_min = size * 0.5
	pm.scale_max = size
	pm.damping_min = 2.0
	pm.damping_max = 5.0
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 1))
	ramp.set_color(1, Color(1, 1, 1, 0))
	var ramp_tex := GradientTexture1D.new()
	ramp_tex.gradient = ramp
	pm.color_ramp = ramp_tex
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.20, 0.20)
	q.material = _quad_mat(color, 3.0)
	p.draw_pass_1 = q
	get_tree().current_scene.add_child(p)
	p.global_position = pos
	p.emitting = true
	var t := get_tree().create_timer(life + 0.15)
	t.timeout.connect(p.queue_free)

func _cast_orb() -> void:
	var dir := Vector3(sin(model_pivot.rotation.y), 0.0, cos(model_pivot.rotation.y))
	var hand := global_position + dir * 0.42 + Vector3(0, 1.05, 0)
	# denyut sihir saat mantera dirapalkan
	_burst(hand, Color(0.55, 0.95, 0.88), 14, 2.4, 0.30, 0.55)
	var orb := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.10
	sm.height = 0.20
	sm.radial_segments = 12
	sm.rings = 8
	orb.mesh = sm
	orb.material_override = _quad_mat(Color(0.60, 1.0, 0.92), 4.0)
	orb.position = hand
	var trail := GPUParticles3D.new()
	trail.amount = 26
	trail.lifetime = 0.34
	trail.interpolate = true
	trail.local_coords = false
	trail.emitting = true
	var tpm := ParticleProcessMaterial.new()
	tpm.spread = 30.0
	tpm.initial_velocity_min = 0.05
	tpm.initial_velocity_max = 0.35
	tpm.gravity = Vector3.ZERO
	tpm.scale_min = 0.10
	tpm.scale_max = 0.42
	tpm.damping_min = 1.0
	tpm.damping_max = 3.0
	var tramp := Gradient.new()
	tramp.set_color(0, Color(1, 1, 1, 1))
	tramp.set_color(1, Color(0.6, 1.0, 0.9, 0))
	var trt := GradientTexture1D.new()
	trt.gradient = tramp
	tpm.color_ramp = trt
	trail.process_material = tpm
	var tq := QuadMesh.new()
	tq.size = Vector2(0.16, 0.16)
	tq.material = _quad_mat(Color(0.45, 0.95, 0.83), 2.4)
	trail.draw_pass_1 = tq
	orb.add_child(trail)
	var lit := OmniLight3D.new()
	lit.light_color = Color(0.45, 0.95, 0.85)
	lit.light_energy = 1.6
	lit.omni_range = 3.6
	lit.shadow_enabled = false
	orb.add_child(lit)
	get_tree().current_scene.add_child(orb)
	_orbs.append({"n": orb, "v": dir * 13.5 + Vector3(0, 0.2, 0), "t": 1.5, "hit": false})
	_play("attack")

func _spawn_impact(pos: Vector3) -> void:
	_burst(pos, Color(0.62, 1.0, 0.92), 34, 5.2, 0.5, 0.75, Vector3(0, -3.0, 0))
	_burst(pos + Vector3(0, 0.05, 0), Color(0.95, 1.0, 0.98), 10, 7.5, 0.32, 0.5)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.55
	tm.outer_radius = 0.72
	ring.mesh = tm
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	rm.albedo_color = Color(0.40, 0.95, 0.85, 0.75)
	rm.emission_enabled = true
	rm.emission = Color(0.40, 0.95, 0.85)
	rm.emission_energy_multiplier = 2.2
	ring.material_override = rm
	ring.rotation_degrees = Vector3(90, 0, 0)
	ring.position = Vector3(pos.x, 0.06, pos.z)
	ring.scale = Vector3(0.4, 0.4, 0.4)
	get_tree().current_scene.add_child(ring)
	_fx.append({"n": ring, "t": 0.38, "T": 0.38, "kind": "ring"})
	var scorch := MeshInstance3D.new()
	var sq := PlaneMesh.new()
	sq.size = Vector2(0.9, 0.9)
	scorch.mesh = sq
	var scm := StandardMaterial3D.new()
	scm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	scm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	scm.albedo_color = Color(0.05, 0.09, 0.08, 0.55)
	scorch.material_override = scm
	scorch.rotation_degrees = Vector3(0, randf() * 360.0, 0)
	scorch.position = Vector3(pos.x, 0.055, pos.z)
	get_tree().current_scene.add_child(scorch)
	_fx.append({"n": scorch, "t": 1.8, "T": 1.8, "kind": "scorch"})

var _fx := []

func _update_fx(delta: float) -> void:
	for i in range(_fx.size() - 1, -1, -1):
		var o: Dictionary = _fx[i]
		var n: Node3D = o["n"]
		if not is_instance_valid(n):
			_fx.remove_at(i)
			continue
		o["t"] = o["t"] - delta
		var k: float = clampf(o["t"] / o["T"], 0.0, 1.0)
		if o["kind"] == "ring":
			var g: float = 0.4 + (1.0 - k) * 2.6
			n.scale = Vector3(g, g, g)
			(n.material_override as StandardMaterial3D).albedo_color.a = 0.75 * k
		elif o["kind"] == "scorch":
			(n.material_override as StandardMaterial3D).albedo_color.a = 0.55 * k
		if o["t"] <= 0.0:
			n.queue_free()
			_fx.remove_at(i)

func _update_orbs(delta: float) -> void:
	for i in range(_orbs.size() - 1, -1, -1):
		var o: Dictionary = _orbs[i]
		var n: Node3D = o["n"]
		if not is_instance_valid(n):
			_orbs.remove_at(i)
			continue
		o["v"] = o["v"] + Vector3(0, -2.4, 0) * delta
		n.position += o["v"] * delta
		n.scale = Vector3.ONE * (1.0 + 0.15 * sin(_wiz_t * 9.0))
		o["t"] = o["t"] - delta
		var dying: bool = o["t"] <= 0.0 or n.position.y < 0.06
		if dying and not o.get("hit", false):
			o["hit"] = true
			_spawn_impact(n.position)
			n.queue_free()
			_orbs.remove_at(i)

func _apply_crouch_shape() -> void:
	var cap: CapsuleShape3D = col_shape.shape
	var h := 1.15 if crouch else 1.8
	cap.height = h
	col_shape.position.y = h * 0.5

# =============== fisika ===============

func _physics_process(delta: float) -> void:
	if not is_ready:
		return
	var water_y := -0.06
	var floor_h := -999.0
	if world:
		floor_h = world.height_at(global_position.x, global_position.z)
	if floor_h < -900.0:
		_swimming = false  # lantai tak ketemu = BUKAN air (world statis tak punya laut)
	else:
		var depth := water_y - floor_h
		_swimming = depth > 1.05 and global_position.y < water_y + 0.3
	# input arah relatif kamera (y layar positif=kebawah karena dorongan atas = maju
	# dipetakan ke -Z kamera lewat cam_basis; jangan dinegasikan dua kali)
	var wish := Vector2(joy.x, joy.y)
	if wish.length() > 1.0:
		wish = wish.normalized()
	var cam_basis := Basis(Vector3.UP, yaw)
	var move_dir := (cam_basis * Vector3(wish.x, 0, wish.y))
	if move_dir.length() > 0.05:
		_last_move_dir = move_dir.normalized()
	_dash_cd = maxf(_dash_cd - delta, 0.0)
	var speed := _target_speed()
	# FAIL-SAFE desktop keyboard (untuk uji headless/dev)
	if joy == Vector2.ZERO:
		var kb := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
		if kb != Vector2.ZERO:
			wish = kb
			move_dir = (cam_basis * Vector3(wish.x, 0, wish.y))
		if Input.is_action_just_pressed("ui_accept"):
			press_jump()
		sprint = Input.is_key_pressed(KEY_SHIFT) or sprint
	# kamera
	_apply_camera(delta)
	# gerakan vertikal & horizontal
	var on_floor := is_on_floor()
	if on_floor:
		_coyote = COYOTE
	else:
		_coyote = maxf(_coyote - delta, 0.0)
	_jump_buffer = maxf(_jump_buffer - delta, 0.0)
	if _swimming:
		_swim_move(delta, move_dir)
	else:
		_ground_move(delta, move_dir, speed, on_floor)
	# melompat
	if _jump_buffer > 0.0 and (_coyote > 0.0) and not _swimming and not crouch:
		velocity.y = JUMP_VEL
		_jump_buffer = 0.0
		_coyote = 0.0
		if anim:
			anim.set_air("jump_start")
		_play("jump")
	# sebelum move_and_slide: simpan fall speed
	_last_fall_speed = -velocity.y if velocity.y < 0 else 0.0
	move_and_slide()
	# efek pendarat
	if not _was_on_floor and is_on_floor():
		if _last_fall_speed > 8.0:
			if anim:
				anim.action("jump_land", 320)
			_play("land")
		_coyote = 0.0
	_was_on_floor = is_on_floor()
	# animasi & model
	_update_model(delta, move_dir, speed)
	_update_orbs(delta)
	_update_fx(delta)
	if _spin_t > 0.0:
		_spin_t -= delta
		if model_root:
			model_root.rotation.y += delta * TAU / 0.9
	# langkah kaki
	if is_on_floor() and Vector2(velocity.x, velocity.z).length() > 0.7:
		step_timer -= delta
		if step_timer <= 0.0:
			step_timer = 2.6 / maxf(Vector2(velocity.x, velocity.z).length(), 0.7)
			_play("step1" if randf() < 0.5 else "step2")
	# interaksi periodik
	_near_timer -= delta
	if _near_timer <= 0.0:
		_near_timer = 0.25
		_check_interactable()
	# cleanup safety: respawn bila jatuh dari dunia
	if global_position.y < -70.0 and world:
		global_position = world.find_spawn_point() + Vector3(0, 1, 0)
		velocity = Vector3.ZERO
	# blob shadow menempel di tanah (dipakai saat shadow GPU nonaktif)
	if blob and blob.visible:
		blob.global_position = Vector3(global_position.x, floor_h + 0.04, global_position.z)
	if _action_lock > 0.0:
		_action_lock -= delta

func _ground_move(delta: float, move_dir: Vector3, speed: float, on_floor: bool) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = -0.5  # jaga tetap nempel di lereng
	var target_xz := Vector3(move_dir.x, 0, move_dir.z) * speed * (joy.length() if joy.length() > 0.05 else 1.0)
	var acc := ACCEL if joy.length() > 0.05 or move_dir.length() > 0.01 else ACCEL
	var hv := Vector2(velocity.x, velocity.z)
	var tv := Vector2(target_xz.x, target_xz.z)
	hv = hv.move_toward(tv, (AIR_ACCEL if not on_floor else acc) * delta * (speed + 0.5))
	velocity.x = hv.x
	velocity.z = hv.y

func _swim_move(delta: float, move_dir: Vector3) -> void:
	# arah permukaan: bob di -0.30; gerakan lambat + sedikit melawan gravitasi
	var surf := -0.30
	var target_y := clampf((surf - global_position.y) * 6.0, -3.0, 3.0)
	velocity.y = lerpf(velocity.y, target_y, delta * 4.0)
	var hv := Vector2(velocity.x, velocity.z)
	var tv := Vector2(move_dir.x, move_dir.z) * SPEED_SWIM * maxf(joy.length(), 0.0)
	hv = hv.move_toward(tv, 3.5 * delta * SPEED_SWIM)
	velocity.x = hv.x
	velocity.z = hv.y

func _target_speed() -> float:
	if crouch:
		return SPEED_CROUCH
	if Input.is_key_pressed(KEY_SHIFT) or sprint:
		return SPEED_SPRINT
	return SPEED_RUN

func _apply_camera(delta: float) -> void:
	var sens := 1.0
	if settings:
		sens = clampf(settings.camera_sens, 0.3, 2.5)
	yaw -= _look_vel.x * LOOK_K * sens * delta * 60.0 * 0.016
	var invert := -1.0 if (settings and settings.invert_y) else 1.0
	pitch = clampf(pitch + _look_vel.y * LOOK_K * sens * delta * 60.0 * 0.016 * invert, PITCH_MIN, PITCH_MAX)
	_look_vel = _look_vel.lerp(Vector2.ZERO, delta * 12.0)
	cam_pivot.rotation = Vector3(pitch, yaw, 0)
	# gradien bobot kecil: kamera sedikit mendekat saat jongkok
	var want_len := CAM_DIST * (0.86 if crouch else 1.0)
	cam_arm.spring_length = lerpf(cam_arm.spring_length, want_len, delta * 6.0)

func _update_model(delta: float, move_dir: Vector3, speed: float) -> void:
	# putar model ke arah gerak
	if move_dir.length() > 0.01:
		var target_yaw := atan2(move_dir.x, move_dir.z)
		model_pivot.rotation.y = lerp_angle(model_pivot.rotation.y, target_yaw, delta * 10.0)
	var hspeed := Vector2(velocity.x, velocity.z).length()
	if anim:
		# jejak diagnostik ON-DEVICE (foto saat keluhannya muncul):
		# menunjukkan state ANIMASI YANG BENAR-BENAR BERMAIN tiap 0,9 detik
		_anim_probe -= delta
		if _anim_probe <= 0.0:
			_anim_probe = 0.9
			var rc2 = get_tree().current_scene
			if rc2 and rc2.has_method("_trace"):
				rc2.call("_trace", "anim:%s sp:%.1f crouch:%s | %s" % [
					str(anim.current), hspeed, str(crouch), char_skin])
		if _swimming:
			anim.set_swim(true, hspeed / SPEED_SWIM)
		elif not _swimming and not is_on_floor() and velocity.y < -2.5:
			anim.set_air("jump_fall")
		elif is_on_floor() and _action_lock <= 0.0:
			anim.set_move(clampf(hspeed / SPEED_RUN, 0.0, 1.0), _target_speed() >= SPEED_SPRINT and hspeed > SPEED_RUN + 0.2, crouch)
	elif model_root != null:
		# penyihir prosedural tanpa library animasi: bob melayang + condong ke
		# arah lari dari kode; orb tongkat berdenyut; putar saat emote diatur
		# oleh _spin_t di _physics_process.
		_wiz_t += delta * (1.1 + hspeed * 0.85)
		var hover: float = 0.30 if not crouch else 0.14     # terbang melayang!
		model_root.position.y = hover + sin(_wiz_t * 2.1) * 0.045
		var lean: float = 0.26 if hspeed > SPEED_RUN + 0.2 else (0.14 if hspeed > 0.4 else 0.0)
		model_root.rotation.x = lerp_angle(model_root.rotation.x, lean, delta * 7.0)
		model_root.rotation.z = lerp_angle(model_root.rotation.z, -lean * 0.45, delta * 7.0)
		if velocity.y < -1.0 and not is_on_floor():
			model_root.rotation.x = lerp_angle(model_root.rotation.x, -0.22, delta * 6.0)
		if _hover_ring and is_instance_valid(_hover_ring):
			_hover_ring.rotation.y += delta * 0.9
			var pr: float = 1.0 + 0.10 * sin(_wiz_t * 3.3)
			_hover_ring.scale = Vector3(pr, pr, pr)
		if _orb_node and is_instance_valid(_orb_node):
			_orb_node.scale = Vector3.ONE * (1.0 + 0.18 * sin(_wiz_t * 6.3))
	# efek visual jongkok (memendek sedikit) & renang (mengambang lebih rendah)
	var want_head := -0.28 if crouch else 0.0
	head_offset_y = lerpf(head_offset_y, want_head, delta * 8.0)
	model_pivot.position.y = head_offset_y

func _check_interactable() -> void:
	if world == null:
		return
	var prev_key := str(_near.get("pos", Vector3.ZERO))
	_near = world.get_nearest_interactable(global_position + Vector3(0, 0.8, 0) - global_transform.basis.z * 0.3, 4.2)
	var new_key := str(_near.get("pos", Vector3.ZERO))
	if prev_key != new_key or (prev_key == "" and new_key != "") or (prev_key != "" and new_key == ""):
		nearest_interactable_changed.emit(_near)

func _do_interact(meta: Dictionary) -> void:
	var signature := str(meta.get("type", "?"))
	world.consume_interactable(meta)
	if anim:
		anim.action("pickup", 700)
	_action_lock = 0.55
	_play("pickup")
	if stats.has(signature):
		stats[signature] += 1
		stats_changed.emit(signature, stats[signature])
	_near = {}
	nearest_interactable_changed.emit(_near)
