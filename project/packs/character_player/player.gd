extends CharacterBody3D
## Player = karakter kubus 3D yang melayang rendah di atas tanah datar.
## Bola api karakter diganti kubus ber-siluet tegas dengan visor, dua kaki,
## cahaya hangat, dan percikan api realistis ketika bergerak. Serangan tetap
## memakai fire bolt agar tombol lama tidak hilang.
##
## Kamera third-person SpringArm mengikuti arah lari saat tidak sedang diusap;
## gerak memakai lerp eksponensial agar akselerasi cepat namun tetap halus.

signal stats_changed(kind: String, count: int)
signal nearest_interactable_changed(meta)
signal health_changed(current: float, maximum: float)

const FIRE_SFX := "res://packs/audio_sfx/fire_loop.wav"
const SHOOT_SFX := "res://packs/audio_sfx/fire_shoot.wav"
const FIRE_BOLT := preload("res://packs/character_player/fire_bolt.gd")
const FIRE_EXPLOSION := preload("res://packs/character_player/fire_explosion.gd")
const FIRE_COOLDOWN := 0.26
const BOLT_SPEED := 20.0
const BOLT_LIFT := 2.0

# --- gerak ---
const MAX_SPEED := 10.5      # m/s; naik dari 7.5 agar respons analog cepat
const ACCEL_RATE := 8.5
const DECEL_RATE := 5.0
const HOVER := 1.15
const CHARACTER_SIZE := Vector3(0.92, 1.12, 0.92)

# --- kamera third-person ---
const PITCH_MIN := deg_to_rad(-72.0)
const PITCH_MAX := deg_to_rad(-10.0)
const CAM_DIST := 7.4
const CAM_FOLLOW := 9.0
const LOOK_K := 0.0036

var world: Node
var settings
var cam_pivot: Node3D
var cam_arm: SpringArm3D
var joy := Vector2.ZERO
var _look_vel := Vector2.ZERO
var yaw := 0.0
var pitch := deg_to_rad(-34.0)
var is_ready := false
var stats := {}
var max_health := 100.0
var health := 100.0

var _visual: Node3D
var _body_mat: StandardMaterial3D
var _visor_mat: StandardMaterial3D
var _halo_mat: StandardMaterial3D
var _light: OmniLight3D
var _ground_glow: MeshInstance3D
var _ground_mat: StandardMaterial3D
var _sparks: GPUParticles3D
var _feet: Array[Node3D] = []
var _sfx: AudioStreamPlayer
var _base_amounts := {}
var _t := 0.0
var _trail := Vector3.ZERO
var _speed01 := 0.0
var _cam_extra := 0.0
var _cam_snapped := false
var _facing := Vector3.ZERO
var _manual_look := 0.0
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
	_build_square_character()
	_make_sfx()
	is_ready = true
	health_changed.emit(health, max_health)

# =============== API dari HUD ===============

func set_joy(v: Vector2) -> void:
	joy = v

func add_look_px(dx: float, dy: float) -> void:
	_look_vel.x += dx * 60.0
	_look_vel.y += dy * 60.0
	_manual_look = minf(1.0, _manual_look + absf(dx) * 0.02 + absf(dy) * 0.02)

func take_damage(amount: float) -> void:
	var before := health
	health = maxf(1.0, health - maxf(0.0, amount))
	if not is_equal_approx(before, health):
		health_changed.emit(health, max_health)
		add_shake(0.18)

func heal(amount: float) -> void:
	var before := health
	health = minf(max_health, health + maxf(0.0, amount))
	if not is_equal_approx(before, health):
		health_changed.emit(health, max_health)

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
	_manual_look = maxf(0.0, _manual_look - delta * 1.8)
	_fire_cooldown = maxf(0.0, _fire_cooldown - delta)
	_recoil = maxf(0.0, _recoil - 6.0 * delta)
	if _attack_held or Input.is_key_pressed(KEY_SPACE) or Input.is_key_pressed(KEY_F):
		_try_fire()
	_move(delta)
	_apply_camera(delta)
	_animate_character(delta)

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
	_speed01 = lerpf(_speed01, clampf(hv.length() / MAX_SPEED, 0.0, 1.0), 1.0 - exp(-8.0 * delta))

func _apply_camera(delta: float) -> void:
	var sens := 1.0
	if settings:
		sens = clampf(settings.camera_sens, 0.3, 2.5)
	yaw -= _look_vel.x * LOOK_K * sens * delta * 60.0 * 0.016
	var invert := -1.0 if (settings and settings.invert_y) else 1.0
	pitch = clampf(pitch + _look_vel.y * LOOK_K * sens * delta * 60.0 * 0.016 * invert, PITCH_MIN, PITCH_MAX)
	_look_vel = _look_vel.lerp(Vector2.ZERO, 1.0 - exp(-12.0 * delta))
	if _manual_look < 0.08 and _facing.length_squared() > 0.25:
		var direction_yaw := atan2(-_facing.x, -_facing.z)
		yaw = lerp_angle(yaw, direction_yaw, 1.0 - exp(-2.6 * delta))
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

func _animate_character(delta: float) -> void:
	var hv := Vector3(velocity.x, 0.0, velocity.z)
	var bob := sin(_t * 4.0) * 0.045 + sin(_t * 7.1 + 1.1) * 0.018
	_visual.position = Vector3(0.0, HOVER + bob * (1.0 - 0.45 * _speed01), 0.0)
	if _facing.length_squared() > 0.01:
		var face_yaw := atan2(-_facing.x, -_facing.z)
		_visual.rotation.y = lerp_angle(_visual.rotation.y, face_yaw, 1.0 - exp(-10.0 * delta))
	for i in _feet.size():
		var stride := sin(_t * 12.0 + float(i) * PI) * _speed01
		_feet[i].position.y = -CHARACTER_SIZE.y * 0.5 + 0.10 + absf(stride) * 0.05
		_feet[i].rotation.x = stride * 0.16
	# Percikan muncul hanya saat kubus benar-benar berjalan; lifetime pendek,
	# gravitasi dan variasi kecepatan membuatnya jatuh alami, bukan garis statis.
	_sparks.emitting = _speed01 > 0.035
	_sparks.position = Vector3(0.0, -CHARACTER_SIZE.y * 0.36, 0.0) - _facing * 0.24
	var flicker := 0.78 + 0.12 * sin(_t * 19.0) + 0.08 * sin(_t * 31.0 + 0.7)
	_light.light_energy = 1.0 + 1.25 * flicker * _speed01
	_halo_mat.albedo_color = Color(1.0, 0.48, 0.12, 0.12 + 0.18 * _speed01)
	var gp := global_position
	_ground_glow.global_position = Vector3(gp.x, 0.02, gp.z)
	_ground_glow.scale = Vector3(0.9 + _speed01 * 0.4, 1.0, 0.9 + _speed01 * 0.4)
	_ground_mat.albedo_color = Color(1.0, 0.34, 0.06, 0.16 + 0.22 * _speed01)
	if _sfx:
		_sfx.volume_db = lerpf(-28.0, -18.0, _speed01)
		_sfx.pitch_scale = 0.88 + 0.08 * _speed01

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
	var origin := _visual.global_position + direction * (0.46 + 0.2)
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

func _build_square_character() -> void:
	_visual = Node3D.new()
	_visual.name = "SquareCharacter"
	_visual.position = Vector3(0.0, HOVER, 0.0)
	add_child(_visual)

	# Kubus utama: bentuk persegi sengaja kontras dengan monster organik.
	var body_mesh := BoxMesh.new()
	body_mesh.size = CHARACTER_SIZE
	var body := MeshInstance3D.new()
	body.name = "SquareBody"
	body.mesh = body_mesh
	_body_mat = StandardMaterial3D.new()
	_body_mat.albedo_color = Color(0.18, 0.46, 0.62)
	_body_mat.roughness = 0.42
	_body_mat.metallic = 0.18
	body.material_override = _body_mat
	_visual.add_child(body)

	# Visor depan + garis atas supaya arah hadap terbaca dari kamera jauh.
	var visor_mesh := BoxMesh.new()
	visor_mesh.size = Vector3(0.58, 0.20, 0.055)
	var visor := MeshInstance3D.new()
	visor.name = "SquareVisor"
	visor.mesh = visor_mesh
	visor.position = Vector3(0.0, 0.12, -CHARACTER_SIZE.z * 0.51)
	_visor_mat = StandardMaterial3D.new()
	_visor_mat.albedo_color = Color(0.62, 0.94, 0.94)
	_visor_mat.emission_enabled = true
	_visor_mat.emission = Color(0.22, 0.85, 0.92)
	_visor_mat.emission_energy_multiplier = 1.6
	visor.material_override = _visor_mat
	_visual.add_child(visor)

	var top_mesh := BoxMesh.new()
	top_mesh.size = Vector3(0.56, 0.08, 0.16)
	var top := MeshInstance3D.new()
	top.name = "SquareTopStripe"
	top.mesh = top_mesh
	top.position = Vector3(0.0, CHARACTER_SIZE.y * 0.54, -0.04)
	top.material_override = _simple_mat(Color(1.0, 0.46, 0.12))
	_visual.add_child(top)

	for side in [-1.0, 1.0]:
		var foot_mesh := BoxMesh.new()
		foot_mesh.size = Vector3(0.26, 0.22, 0.34)
		var foot := MeshInstance3D.new()
		foot.name = "SquareFoot"
		foot.mesh = foot_mesh
		foot.position = Vector3(side * 0.23, -CHARACTER_SIZE.y * 0.58, 0.0)
		foot.material_override = _simple_mat(Color(0.10, 0.16, 0.20))
		_visual.add_child(foot)
		_feet.append(foot)

	# Aura lembut pengganti bola api; karakter tetap punya aksen panas tanpa
	# kembali menjadi bola. Tidak menerima shadow agar murah di GPU mobile.
	var halo := MeshInstance3D.new()
	halo.name = "SquareGlow"
	var halo_mesh := QuadMesh.new()
	halo_mesh.size = Vector2(1.9, 1.9)
	halo.mesh = halo_mesh
	_halo_mat = _fx_mat(_soft_tex(0.10), true, Color(1.0, 0.36, 0.08, 0.18))
	_halo_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	halo.material_override = _halo_mat
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_visual.add_child(halo)

	_light = OmniLight3D.new()
	_light.name = "SquareWarmLight"
	_light.light_color = Color(1.0, 0.42, 0.12)
	_light.light_energy = 0.65
	_light.omni_range = 4.2
	_light.omni_attenuation = 1.5
	_light.shadow_enabled = false
	_visual.add_child(_light)

	_sparks = _make_travel_sparks()
	_base_amounts[_sparks] = _sparks.amount
	_sparks.emitting = false

	_ground_glow = MeshInstance3D.new()
	_ground_glow.name = "SquareGroundGlow"
	var ground_mesh := PlaneMesh.new()
	ground_mesh.size = Vector2(2.1, 2.1)
	_ground_glow.mesh = ground_mesh
	_ground_mat = _fx_mat(_soft_tex(0.0), true, Color(1.0, 0.30, 0.05, 0.22))
	_ground_mat.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	_ground_mat.vertex_color_use_as_albedo = false
	_ground_glow.material_override = _ground_mat
	_ground_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ground_glow.top_level = true
	add_child(_ground_glow)

func _simple_mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.7
	return mat

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

func _make_travel_sparks() -> GPUParticles3D:
	var p := _base_particles("TravelSparks", 48, 0.52)
	p.randomness = 0.55
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = 0.30
	m.direction = Vector3(0, 1, 0)
	m.spread = 62.0
	m.initial_velocity_min = 0.65
	m.initial_velocity_max = 2.7
	m.gravity = Vector3(0, -5.2, 0)
	m.damping_min = 0.35
	m.damping_max = 1.15
	m.scale_min = 0.55
	m.scale_max = 1.20
	m.scale_curve = _curve([Vector2(0.0, 1.0), Vector2(0.32, 0.92), Vector2(1.0, 0.0)], 1.0)
	m.angle_min = -180.0
	m.angle_max = 180.0
	m.angular_velocity_min = -180.0
	m.angular_velocity_max = 180.0
	m.color_ramp = _ramp(
		[0.0, 0.12, 0.45, 1.0],
		[Color(3.0, 2.2, 0.85, 1.0), Color(2.0, 0.70, 0.10, 1.0),
			Color(1.0, 0.16, 0.015, 0.72), Color(0.28, 0.02, 0.0, 0.0)])
	m.turbulence_enabled = true
	m.turbulence_noise_strength = 0.8
	m.turbulence_noise_scale = 2.4
	m.turbulence_influence_min = 0.16
	m.turbulence_influence_max = 0.34
	p.process_material = m
	var q := QuadMesh.new()
	q.size = Vector2(0.08, 0.08)
	q.material = _fx_mat(_soft_tex(0.28), true, Color(2.6, 1.4, 0.35, 1.0))
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
