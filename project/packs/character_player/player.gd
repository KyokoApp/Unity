extends CharacterBody3D
## Player = BOLA API yang melayang di atas tanah datar, digerakkan analog.
##
## Mannequin, animasi (UAL), skin, lompat, renang, emote, SFX langkah: DIHAPUS.
## Yang tersisa: gerak halus relatif kamera + visual api prosedural:
##   1. Inti plasma (fireball_core.gdshader)  -> putih-kuning panas, bergolak
##   2. Selubung api aditif (fireball_shell.gdshader) -> jilatan ke atas + EKOR
##      yang memanjang ke belakang saat bergerak
##   3. Partikel: lidah api, asap tipis, bara/percikan (turbulen)
##   4. Halo cahaya + OmniLight berkedip + pantulan cahaya di tanah
##   5. Suara api berderak (fire_loop.wav) yang makin keras saat melaju
##
## KEHALUSAN: gerak & kamera dihitung di _process (per frame render, bukan per
## tick fisika) memakai lerp eksponensial yang tak tergantung FPS:
## percepatan/perlambatan, ekor, bob, dan ikut-kamera semuanya meluncur mulus.
##
## API untuk skrip lain TETAP sama (HUD, game_root, QualityManager):
## set_world, set_settings, set_joy, add_look_px, apply_quality, press_* (no-op).

signal stats_changed(kind: String, count: int)     # kompat HUD (tidak dipakai)
signal nearest_interactable_changed(meta)          # kompat HUD (tidak dipakai)

const CORE_SHADER := preload("res://packs/character_player/fireball_core.gdshader")
const SHELL_SHADER := preload("res://packs/character_player/fireball_shell.gdshader")
const FIRE_SFX := "res://packs/audio_sfx/fire_loop.wav"
const SHOOT_SFX := "res://packs/audio_sfx/fire_shoot.wav"
const FIRE_BOLT := preload("res://packs/character_player/fire_bolt.gd")
const FIRE_EXPLOSION := preload("res://packs/character_player/fire_explosion.gd")
const FIRE_COOLDOWN := 0.26
const BOLT_SPEED := 20.0
const BOLT_LIFT := 2.0

# --- gerak ---
const MAX_SPEED := 7.5       # m/s saat analog didorong penuh
const ACCEL_RATE := 5.0      # makin besar = makin cepat mencapai kecepatan target
const DECEL_RATE := 3.0      # berhenti meluncur pelan, tidak mendadak
const HOVER := 1.15          # tinggi pusat bola dari tanah
const BALL_R := 0.42         # jari-jari inti

# --- kamera ---
const PITCH_MIN := deg_to_rad(-72.0)
const PITCH_MAX := deg_to_rad(-10.0)
const CAM_DIST := 8.5
const CAM_FOLLOW := 7.0      # kekakuan kamera mengikuti bola (lebih kecil = lebih "melayang")
const LOOK_K := 0.0036

var world: Node
var settings
var cam_pivot: Node3D
var cam_arm: SpringArm3D
var joy := Vector2.ZERO       # -1..1 dari HUD (y negatif = dorong ke atas = maju)
var _look_vel := Vector2.ZERO
var yaw := 0.0
var pitch := deg_to_rad(-34.0)
var is_ready := false
var stats := {}               # kompat HUD (_refresh_stats membaca ini)

var _visual: Node3D
var _core_mat: ShaderMaterial
var _shell_mat: ShaderMaterial
var _halo_mat: StandardMaterial3D
var _light: OmniLight3D
var _ground_glow: MeshInstance3D
var _ground_mat: StandardMaterial3D
var _flames: GPUParticles3D
var _smoke: GPUParticles3D
var _embers: GPUParticles3D
var _sfx: AudioStreamPlayer
var _base_amounts := {}       # GPUParticles3D -> amount penuh (diskalakan preset kualitas)
var _t := 0.0
var _flow := Vector3.ZERO     # offset noise (pola api mengalir ke belakang saat bergerak)
var _trail := Vector3.ZERO    # vektor ekor yang diperhalus
var _speed01 := 0.0           # 0..1 kecepatan (diperhalus) untuk intensitas/suara
var _cam_extra := 0.0
var _cam_snapped := false
var _facing := Vector3.ZERO
var _attack_held := false
var _fire_cooldown := 0.0
var _recoil := 0.0
var _shake := 0.0
var _fx := 1.0

func set_world(w: Node) -> void:
	world = w

func set_settings(s) -> void:
	settings = s

func _ready() -> void:
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	cam_pivot = $CameraPivot
	cam_arm = $CameraPivot/CamArm
	cam_pivot.top_level = true           # kamera mengikuti dengan lerp sendiri (bukan kaku)
	cam_arm.add_excluded_object(get_rid())
	_build_fireball()
	_make_sfx()
	is_ready = true

# =============== API dari HUD ===============

func set_joy(v: Vector2) -> void:
	joy = v

func add_look_px(dx: float, dy: float) -> void:
	_look_vel.x += dx * 60.0
	_look_vel.y += dy * 60.0

# Tombol aksi sudah tidak ada; stub dipertahankan supaya pemanggil lama aman.
func press_jump() -> void:
	pass

func press_sprint(_down: bool) -> void:
	pass

func press_interact() -> void:
	pass

func press_attack() -> void:
	_try_fire()

func set_attack_held(down: bool) -> void:
	_attack_held = down
	if down:
		_try_fire()

func press_emote() -> void:
	pass

## Dipanggil QualityManager: kurangi jumlah partikel di HP lemah.
func apply_quality(p: Dictionary) -> void:
	_fx = clampf(float(p.get("fx", 1.0)), 0.2, 1.0)
	var k := _fx
	for n in _base_amounts:
		if is_instance_valid(n):
			n.amount = maxi(4, int(round(float(_base_amounts[n]) * k)))

# =============== Loop ===============

func _process(delta: float) -> void:
	if not is_ready:
		return
	delta = minf(delta, 0.1)             # cegah lompatan setelah jeda/hitch
	_t += delta
	_fire_cooldown = maxf(0.0, _fire_cooldown - delta)
	_recoil = maxf(0.0, _recoil - 6.0 * delta)
	if _attack_held or Input.is_key_pressed(KEY_SPACE) or Input.is_key_pressed(KEY_F):
		_try_fire()
	_move(delta)
	_apply_camera(delta)
	_animate_fire(delta)

func _move(delta: float) -> void:
	var wish := joy
	if wish == Vector2.ZERO:
		# FAIL-SAFE desktop keyboard (uji di PC)
		wish = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if wish.length() > 1.0:
		wish = wish.normalized()
	# relatif kamera: dorong analog ke atas = menjauh dari kamera (-Z kamera)
	var dir := Basis(Vector3.UP, yaw) * Vector3(wish.x, 0.0, wish.y)
	var target := dir * MAX_SPEED        # panjang wish = kekuatan analog (analog penuh/setengah)
	var hv := Vector3(velocity.x, 0.0, velocity.z)
	var rate := ACCEL_RATE if target.length_squared() > 0.0001 else DECEL_RATE
	hv = hv.lerp(target, 1.0 - exp(-rate * delta))
	if hv.length_squared() < 0.0004 and target == Vector3.ZERO:
		hv = Vector3.ZERO
	# kunci badan di y=0 (bola melayang; tidak ada gravitasi/lompat)
	velocity = Vector3(hv.x, -global_position.y / maxf(delta, 0.001), hv.z)
	move_and_slide()
	if hv.length() > 1.0:
		_facing = hv.normalized()
	_speed01 = lerpf(_speed01, clampf(hv.length() / MAX_SPEED, 0.0, 1.0), 1.0 - exp(-6.0 * delta))

func _apply_camera(delta: float) -> void:
	var sens := 1.0
	if settings:
		sens = clampf(settings.camera_sens, 0.3, 2.5)
	yaw -= _look_vel.x * LOOK_K * sens * delta * 60.0 * 0.016
	var invert := -1.0 if (settings and settings.invert_y) else 1.0
	pitch = clampf(pitch + _look_vel.y * LOOK_K * sens * delta * 60.0 * 0.016 * invert, PITCH_MIN, PITCH_MAX)
	_look_vel = _look_vel.lerp(Vector2.ZERO, 1.0 - exp(-12.0 * delta))
	var focus := global_position + Vector3(0.0, HOVER, 0.0)
	if not _cam_snapped:
		cam_pivot.global_position = focus
		_cam_snapped = true
	else:
		cam_pivot.global_position = cam_pivot.global_position.lerp(focus, 1.0 - exp(-CAM_FOLLOW * delta))
	cam_pivot.rotation = Vector3(pitch, yaw, 0.0)
	# sedikit mundur saat melaju -> terasa cepat tanpa kehilangan bola
	_cam_extra = lerpf(_cam_extra, _speed01 * 1.3, 1.0 - exp(-3.0 * delta))
	cam_arm.spring_length = CAM_DIST + _cam_extra
	_shake = maxf(0.0, _shake - 1.6 * delta)
	var shake_power := _shake * _shake * 0.35
	var cam: Camera3D = $CameraPivot/CamArm/Cam
	cam.h_offset = (sin(_t * 43.0) * 0.72 + sin(_t * 67.0 + 0.8) * 0.28) * shake_power
	cam.v_offset = (sin(_t * 51.0 + 1.7) * 0.7 + sin(_t * 79.0) * 0.3) * shake_power

func _animate_fire(delta: float) -> void:
	var hv := Vector3(velocity.x, 0.0, velocity.z)
	# bob melayang (lebih tenang saat melaju)
	var bob := sin(_t * 2.1) * 0.07 + sin(_t * 3.7 + 1.1) * 0.025
	var recoil_dir := _shoot_direction()
	_visual.position = Vector3(0.0, HOVER + bob * (1.0 - 0.6 * _speed01), 0.0) - recoil_dir * (0.22 * _recoil * _recoil)
	# ekor: berlawanan arah gerak, diperhalus (tidak patah saat belok/berhenti)
	var want_trail := (-hv * 0.12).limit_length(1.2)
	_trail = _trail.lerp(want_trail, 1.0 - exp(-5.0 * delta))
	_flow += hv * delta * 0.45
	if absf(_flow.x) > 2048.0 or absf(_flow.z) > 2048.0:
		_flow = Vector3(fposmod(_flow.x, 64.0), 0.0, fposmod(_flow.z, 64.0))
	_core_mat.set_shader_parameter("flow_offset", _flow)
	_core_mat.set_shader_parameter("intensity", 2.6 + 0.7 * _speed01 + 1.4 * _recoil)
	_core_mat.set_shader_parameter("turbulence", 1.0 + 0.6 * _speed01)
	_shell_mat.set_shader_parameter("flow_offset", _flow)
	_shell_mat.set_shader_parameter("trail", _trail)
	_shell_mat.set_shader_parameter("rise", 0.55 * (1.0 - 0.45 * _speed01))
	# kedip cahaya (campuran beberapa sinus = tidak terlihat berpola)
	var fl := 0.84 + 0.09 * sin(_t * 13.0) + 0.05 * sin(_t * 27.3 + 1.3) + 0.03 * sin(_t * 41.7 + 0.4)
	_light.light_energy = 2.6 * fl * (1.0 + 0.2 * _speed01)
	_halo_mat.albedo_color = Color(1.0, 0.42, 0.1, 0.32 * fl)
	# cahaya di tanah mengikuti bola (lebih terang/menyempit saat bola turun)
	var gp := global_position
	_ground_glow.global_position = Vector3(gp.x, 0.02, gp.z) + _trail * 0.35
	var gs := 1.0 + bob * 0.8
	_ground_glow.scale = Vector3(gs, 1.0, gs)
	_ground_mat.albedo_color = Color(1.0, 0.38, 0.08, 0.5 * fl)
	# suara makin keras & sedikit lebih tinggi saat melaju
	if _sfx:
		_sfx.volume_db = lerpf(-15.0, -6.0, _speed01)
		_sfx.pitch_scale = 0.95 + 0.15 * _speed01

# =============== Serangan ===============

func _shoot_direction() -> Vector3:
	if _facing.length_squared() > 0.01:
		return _facing.normalized()
	return (Basis(Vector3.UP, yaw) * Vector3(0, 0, -1)).normalized()

func _try_fire() -> void:
	if not is_ready or _fire_cooldown > 0.0:
		return
	_fire_cooldown = FIRE_COOLDOWN
	var direction := _shoot_direction()
	var origin := _visual.global_position + direction * (BALL_R + 0.2)
	var host: Node = world if is_instance_valid(world) and world.is_inside_tree() else get_parent()
	if host == null:
		return
	var bolt := FIRE_BOLT.new()
	bolt.vel = direction * BOLT_SPEED + Vector3(velocity.x, 0, velocity.z) * 0.6 + Vector3.UP * BOLT_LIFT
	bolt.fx = _fx
	bolt.exclude_rids.append(get_rid())
	bolt.shake_target = self
	host.add_child(bolt)
	bolt.global_position = origin
	var muzzle := FIRE_EXPLOSION.new()
	muzzle.kind = "muzzle"
	muzzle.fx = _fx
	muzzle.dir = direction
	host.add_child(muzzle)
	muzzle.global_position = origin
	_recoil = 1.0
	add_shake(0.12)
	_play_shoot_sound()

func add_shake(amount: float) -> void:
	_shake = minf(_shake + amount, 0.8)

func _play_shoot_sound() -> void:
	if not ResourceLoader.exists(SHOOT_SFX):
		return
	var sound := AudioStreamPlayer.new()
	sound.stream = load(SHOOT_SFX)
	sound.bus = "SFX"
	sound.pitch_scale = randf_range(0.94, 1.08)
	sound.finished.connect(sound.queue_free)
	add_child(sound)
	sound.play()

# =============== Bangun visual ===============

func _build_fireball() -> void:
	_visual = Node3D.new()
	_visual.name = "Fireball"
	_visual.position = Vector3(0.0, HOVER, 0.0)
	add_child(_visual)

	# 1) inti plasma
	var core := MeshInstance3D.new()
	core.name = "Core"
	var sm := SphereMesh.new()
	sm.radius = BALL_R
	sm.height = BALL_R * 2.0
	sm.radial_segments = 32
	sm.rings = 16
	core.mesh = sm
	_core_mat = ShaderMaterial.new()
	_core_mat.shader = CORE_SHADER
	core.material_override = _core_mat
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_visual.add_child(core)

	# 2) selubung api aditif (ekor + jilatan)
	var shell := MeshInstance3D.new()
	shell.name = "Shell"
	var sm2 := SphereMesh.new()
	sm2.radius = BALL_R * 1.45
	sm2.height = BALL_R * 2.9
	sm2.radial_segments = 40
	sm2.rings = 20
	shell.mesh = sm2
	_shell_mat = ShaderMaterial.new()
	_shell_mat.shader = SHELL_SHADER
	shell.material_override = _shell_mat
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# ekor bisa memanjang jauh di luar bola asli -> perbesar AABB supaya tidak ter-cull
	shell.extra_cull_margin = 2.0
	_visual.add_child(shell)

	# 3) halo cahaya lembut (tetap terlihat "menyala" walau glow mati di preset Rendah)
	var halo := MeshInstance3D.new()
	halo.name = "Halo"
	var q := QuadMesh.new()
	q.size = Vector2(2.6, 2.6)
	halo.mesh = q
	_halo_mat = _fx_mat(_soft_tex(0.15), true, Color(1.0, 0.42, 0.1, 0.32))
	_halo_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_halo_mat.vertex_color_use_as_albedo = false
	halo.material_override = _halo_mat
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_visual.add_child(halo)

	# 4) cahaya berkedip (menerangi tanah sekitar)
	_light = OmniLight3D.new()
	_light.name = "FireLight"
	_light.light_color = Color(1.0, 0.55, 0.22)
	_light.light_energy = 2.6
	_light.omni_range = 9.0
	_light.omni_attenuation = 1.3
	_light.shadow_enabled = false
	_visual.add_child(_light)

	# 5) partikel
	_flames = _make_flames()
	_smoke = _make_smoke()
	_embers = _make_embers()
	for p in [_flames, _smoke, _embers]:
		_base_amounts[p] = p.amount

	# 6) pantulan cahaya di tanah (top_level: tidak ikut bob)
	_ground_glow = MeshInstance3D.new()
	_ground_glow.name = "GroundGlow"
	var pm := PlaneMesh.new()
	pm.size = Vector2(5.0, 5.0)
	_ground_glow.mesh = pm
	_ground_mat = _fx_mat(_soft_tex(0.0), true, Color(1.0, 0.38, 0.08, 0.5))
	_ground_mat.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED   # rebah di tanah
	_ground_mat.vertex_color_use_as_albedo = false
	_ground_glow.material_override = _ground_mat
	_ground_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ground_glow.top_level = true
	add_child(_ground_glow)

func _base_particles(pname: String, amount: int, lifetime: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = pname
	p.amount = amount
	p.lifetime = lifetime
	p.randomness = 0.35
	p.local_coords = false               # partikel tertinggal di dunia -> jejak saat bergerak
	p.fixed_fps = 60
	p.interpolate = true
	p.visibility_aabb = AABB(Vector3(-12, -4, -12), Vector3(24, 14, 24))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	_visual.add_child(p)
	return p

func _make_flames() -> GPUParticles3D:
	var p := _base_particles("Flames", 90, 0.75)
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = BALL_R * 0.8
	m.direction = Vector3(0, 1, 0)
	m.spread = 35.0
	m.initial_velocity_min = 0.2
	m.initial_velocity_max = 0.8
	m.gravity = Vector3(0, 3.0, 0)       # api naik
	m.damping_min = 1.0
	m.damping_max = 2.0
	m.scale_min = 0.55
	m.scale_max = 1.0
	m.scale_curve = _curve([Vector2(0.0, 0.5), Vector2(0.25, 1.0), Vector2(1.0, 0.15)], 1.0)
	m.angle_min = -180.0
	m.angle_max = 180.0
	m.angular_velocity_min = -90.0
	m.angular_velocity_max = 90.0
	m.color_ramp = _ramp(
		[0.0, 0.08, 0.35, 0.7, 1.0],
		[Color(1.0, 0.9, 0.6, 0.0), Color(1.0, 0.75, 0.35, 0.9), Color(1.0, 0.45, 0.1, 0.8),
			Color(0.8, 0.15, 0.03, 0.45), Color(0.2, 0.04, 0.01, 0.0)])
	m.turbulence_enabled = true
	m.turbulence_noise_strength = 0.6
	m.turbulence_noise_scale = 2.5
	m.turbulence_influence_min = 0.05
	m.turbulence_influence_max = 0.15
	p.process_material = m
	var q := QuadMesh.new()
	q.size = Vector2(0.85, 0.85)
	q.material = _fx_mat(_soft_tex(0.1), true, Color(1.9, 1.5, 1.2, 1.0))
	p.draw_pass_1 = q
	return p

func _make_smoke() -> GPUParticles3D:
	var p := _base_particles("Smoke", 22, 1.8)
	p.position = Vector3(0.0, 0.35, 0.0)
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = 0.35
	m.direction = Vector3(0, 1, 0)
	m.spread = 20.0
	m.initial_velocity_min = 0.5
	m.initial_velocity_max = 1.0
	m.gravity = Vector3(0, 1.4, 0)
	m.damping_min = 0.5
	m.damping_max = 1.0
	m.scale_min = 0.8
	m.scale_max = 1.4
	m.scale_curve = _curve([Vector2(0.0, 0.4), Vector2(1.0, 1.6)], 2.0)
	m.angle_min = -180.0
	m.angle_max = 180.0
	m.angular_velocity_min = -30.0
	m.angular_velocity_max = 30.0
	m.color_ramp = _ramp(
		[0.0, 0.2, 0.6, 1.0],
		[Color(0.2, 0.17, 0.15, 0.0), Color(0.22, 0.19, 0.17, 0.28),
			Color(0.3, 0.28, 0.26, 0.18), Color(0.35, 0.33, 0.32, 0.0)])
	p.process_material = m
	var q := QuadMesh.new()
	q.size = Vector2(1.1, 1.1)
	q.material = _fx_mat(_soft_tex(0.0), false, Color(1, 1, 1, 1))
	p.draw_pass_1 = q
	return p

func _make_embers() -> GPUParticles3D:
	var p := _base_particles("Embers", 28, 1.4)
	p.randomness = 0.5
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = 0.4
	m.direction = Vector3(0, 1, 0)
	m.spread = 70.0
	m.initial_velocity_min = 0.8
	m.initial_velocity_max = 2.6
	m.gravity = Vector3(0, 1.2, 0)
	m.damping_min = 0.8
	m.damping_max = 1.6
	m.scale_min = 0.6
	m.scale_max = 1.2
	m.scale_curve = _curve([Vector2(0.0, 1.0), Vector2(1.0, 0.0)], 1.0)
	m.color_ramp = _ramp(
		[0.0, 0.5, 1.0],
		[Color(1.0, 0.9, 0.6, 1.0), Color(1.0, 0.5, 0.1, 1.0), Color(0.8, 0.15, 0.02, 0.0)])
	m.turbulence_enabled = true
	m.turbulence_noise_strength = 1.4
	m.turbulence_noise_scale = 1.8
	m.turbulence_influence_min = 0.2
	m.turbulence_influence_max = 0.5
	p.process_material = m
	var q := QuadMesh.new()
	q.size = Vector2(0.07, 0.07)
	q.material = _fx_mat(_soft_tex(0.35), true, Color(3.5, 2.4, 1.4, 1.0))
	p.draw_pass_1 = q
	return p

# --- helper resource ---

func _fx_mat(tex: Texture2D, additive: bool, tint: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = tex
	m.albedo_color = tint
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.disable_receive_shadows = true
	return m

func _soft_tex(core: float) -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, clampf(core, 0.0, 0.9), 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.6), Color(1, 1, 1, 0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 64
	t.height = 64
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(0.5, 0.0)
	return t

func _ramp(offsets: Array, colors: Array) -> GradientTexture1D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(offsets)
	g.colors = PackedColorArray(colors)
	var t := GradientTexture1D.new()
	t.gradient = g
	return t

func _curve(points: Array, max_v: float) -> CurveTexture:
	var c := Curve.new()
	c.max_value = max_v
	for pt in points:
		c.add_point(pt)
	var t := CurveTexture.new()
	t.curve = c
	return t

func _make_sfx() -> void:
	if not ResourceLoader.exists(FIRE_SFX):
		return
	_sfx = AudioStreamPlayer.new()
	_sfx.name = "FireSfx"
	_sfx.bus = "SFX"
	_sfx.stream = load(FIRE_SFX)
	_sfx.volume_db = -15.0
	_sfx.finished.connect(func(): _sfx.play())   # WAV tanpa loop-point -> ulang manual
	add_child(_sfx)
	_sfx.play()
