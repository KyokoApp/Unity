extends CharacterBody3D
## Pemain = satu kubus kotak sederhana yang berjalan tepat di atas tanah.
## Percikan hanya muncul dari titik gesek bawah kubus saat bergerak: kecil,
## pendek, dipengaruhi arah gerak dan gravitasi, bukan aura atau api yang
## mengambang di sekitar karakter.
##
## Kamera tetap third-person SpringArm seperti versi awal: mengikuti posisi
## pemain dengan smoothing, tetapi TIDAK otomatis memutar yaw ke arah lari.

signal stats_changed(kind: String, count: int)
signal nearest_interactable_changed(meta)
signal health_changed(current: float, maximum: float)

const SHOOT_SFX := "res://packs/audio_sfx/fire_shoot.wav"
const FIRE_BOLT := preload("res://packs/character_player/fire_bolt.gd")
const FIRE_EXPLOSION := preload("res://packs/character_player/fire_explosion.gd")
const FIRE_COOLDOWN := 0.26
const BOLT_SPEED := 20.0
const BOLT_LIFT := 2.0

# --- gerak ---
const MAX_SPEED := 10.5
const ACCEL_RATE := 8.5
const DECEL_RATE := 5.0
const HOVER := 0.50
const CHARACTER_SIZE := Vector3(0.92, 0.92, 0.92)

# --- kamera third-person versi awal ---
const PITCH_MIN := deg_to_rad(-72.0)
const PITCH_MAX := deg_to_rad(-10.0)
const CAM_DIST := 8.5
const CAM_FOLLOW := 7.0
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
var _body_material: StandardMaterial3D
var _sparks: GPUParticles3D
var _spark_material: ParticleProcessMaterial
var _base_amounts := {}
var _t := 0.0
var _speed01 := 0.0
var _cam_extra := 0.0
var _cam_snapped := false
var _facing := Vector3.ZERO
var _attack_held := false
var _fire_cooldown := 0.0
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
	cam_pivot.top_level = true
	cam_arm.add_excluded_object(get_rid())
	_build_cube()
	is_ready = true
	health_changed.emit(health, max_health)

# =============== API dari HUD ===============

func set_joy(v: Vector2) -> void:
	joy = v

func add_look_px(dx: float, dy: float) -> void:
	_look_vel.x += dx * 60.0
	_look_vel.y += dy * 60.0

func take_damage(amount: float) -> void:
	var before := health
	health = maxf(1.0, health - maxf(0.0, amount))
	if not is_equal_approx(before, health):
		health_changed.emit(health, max_health)
		_shake = minf(_shake + 0.18, 0.8)

func heal(amount: float) -> void:
	var before := health
	health = minf(max_health, health + maxf(0.0, amount))
	if not is_equal_approx(before, health):
		health_changed.emit(health, max_health)

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

func apply_quality(p: Dictionary) -> void:
	_fx = clampf(float(p.get("fx", 1.0)), 0.2, 1.0)
	for n in _base_amounts:
		if is_instance_valid(n):
			n.amount = maxi(6, int(round(float(_base_amounts[n]) * _fx)))

# =============== Loop ===============

func _process(delta: float) -> void:
	if not is_ready:
		return
	delta = minf(delta, 0.1)
	_t += delta
	_fire_cooldown = maxf(0.0, _fire_cooldown - delta)
	if _attack_held or Input.is_key_pressed(KEY_SPACE) or Input.is_key_pressed(KEY_F):
		_try_fire()
	_move(delta)
	_apply_camera(delta)
	_animate_cube()

func _move(delta: float) -> void:
	var wish := joy
	if wish == Vector2.ZERO:
		wish = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if wish.length() > 1.0:
		wish = wish.normalized()
	var dir := Basis(Vector3.UP, yaw) * Vector3(wish.x, 0.0, wish.y)
	var target := dir * MAX_SPEED
	var hv := Vector3(velocity.x, 0.0, velocity.z)
	var rate := ACCEL_RATE if target.length_squared() > 0.0001 else DECEL_RATE
	hv = hv.lerp(target, 1.0 - exp(-rate * delta))
	if hv.length_squared() < 0.0004 and target == Vector3.ZERO:
		hv = Vector3.ZERO
	# Origin pemain tetap di y=0; kubus diletakkan setengah tinggi di atasnya.
	velocity = Vector3(hv.x, -global_position.y / maxf(delta, 0.001), hv.z)
	move_and_slide()
	if hv.length() > 0.1:
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
	var focus := global_position + Vector3(0.0, HOVER, 0.0)
	if not _cam_snapped:
		cam_pivot.global_position = focus
		_cam_snapped = true
	else:
		cam_pivot.global_position = cam_pivot.global_position.lerp(focus, 1.0 - exp(-CAM_FOLLOW * delta))
	cam_pivot.rotation = Vector3(pitch, yaw, 0.0)
	_cam_extra = lerpf(_cam_extra, _speed01 * 1.3, 1.0 - exp(-3.0 * delta))
	cam_arm.spring_length = CAM_DIST + _cam_extra
	_shake = maxf(0.0, _shake - 1.6 * delta)
	var shake_power := _shake * _shake * 0.35
	var cam: Camera3D = $CameraPivot/CamArm/Cam
	cam.h_offset = (sin(_t * 43.0) * 0.72 + sin(_t * 67.0 + 0.8) * 0.28) * shake_power
	cam.v_offset = (sin(_t * 51.0 + 1.7) * 0.7 + sin(_t * 79.0) * 0.3) * shake_power

func _animate_cube() -> void:
	# Tidak ada bob, kaki, aura, atau kamera yang menempel ke arah gerak.
	# Dasar kubus tetap menyentuh y=0.
	_visual.position = Vector3(0.0, HOVER, 0.0)
	var moving := _speed01 > 0.035 and _facing.length_squared() > 0.01
	_sparks.emitting = moving
	if moving:
		_sparks.position = Vector3(0.0, -HOVER + 0.055, 0.0) - _facing * 0.38
		_spark_material.direction = (-_facing + Vector3.UP * 0.42).normalized()
	else:
		_sparks.position = Vector3(0.0, -HOVER + 0.055, 0.0)

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
	var origin := _visual.global_position + direction * 0.58
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
	_shake = minf(_shake + 0.12, 0.8)
	_play_shoot_sound()

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

# =============== Visual kubus + percikan gesekan ===============

func _build_cube() -> void:
	_visual = Node3D.new()
	_visual.name = "SquareCharacter"
	_visual.position = Vector3(0.0, HOVER, 0.0)
	add_child(_visual)

	var mesh := BoxMesh.new()
	mesh.size = CHARACTER_SIZE
	var body := MeshInstance3D.new()
	body.name = "PlayerCube"
	body.mesh = mesh
	_body_material = StandardMaterial3D.new()
	_body_material.albedo_color = Color(0.20, 0.43, 0.62)
	_body_material.roughness = 0.78
	_body_material.metallic = 0.05
	body.material_override = _body_material
	_visual.add_child(body)

	_sparks = _base_particles("GroundFrictionSparks", 52, 0.30)
	_spark_material = ParticleProcessMaterial.new()
	_spark_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	_spark_material.emission_sphere_radius = 0.075
	_spark_material.direction = Vector3(0.0, 0.42, -1.0).normalized()
	_spark_material.spread = 16.0
	_spark_material.initial_velocity_min = 1.1
	_spark_material.initial_velocity_max = 3.3
	_spark_material.gravity = Vector3(0.0, -9.8, 0.0)
	_spark_material.damping_min = 0.15
	_spark_material.damping_max = 0.55
	_spark_material.scale_min = 0.45
	_spark_material.scale_max = 0.95
	_spark_material.scale_curve = _curve([Vector2(0.0, 1.0), Vector2(0.22, 0.88), Vector2(1.0, 0.0)], 1.0)
	_spark_material.color_ramp = _ramp(
		[0.0, 0.18, 0.55, 1.0],
		[Color(3.0, 2.4, 1.0, 1.0), Color(2.2, 0.75, 0.12, 1.0), Color(1.0, 0.16, 0.01, 0.70), Color(0.2, 0.01, 0.0, 0.0)])
	_sparks.process_material = _spark_material
	var spark_mesh := QuadMesh.new()
	spark_mesh.size = Vector2(0.035, 0.10)
	spark_mesh.material = _fx_mat(_soft_tex(0.35), true, Color(2.8, 1.5, 0.25, 1.0))
	_sparks.draw_pass_1 = spark_mesh
	_sparks.emitting = false
	_base_amounts[_sparks] = _sparks.amount

func _base_particles(pname: String, amount: int, lifetime: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = pname
	p.amount = amount
	p.lifetime = lifetime
	p.randomness = 0.28
	p.local_coords = false
	p.fixed_fps = 60
	p.interpolate = true
	p.visibility_aabb = AABB(Vector3(-8, -2, -8), Vector3(16, 8, 16))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	_visual.add_child(p)
	return p

func _fx_mat(tex: Texture2D, additive: bool, tint: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = tex
	mat.albedo_color = tint
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.disable_receive_shadows = true
	return mat

func _soft_tex(core: float) -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, clampf(core, 0.0, 0.9), 1.0])
	gradient.colors = PackedColorArray([Color.WHITE, Color(1, 1, 1, 0.6), Color(1, 1, 1, 0)])
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.width = 32
	tex.height = 32
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	return tex

func _ramp(offsets: Array, colors: Array) -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array(offsets)
	gradient.colors = PackedColorArray(colors)
	var tex := GradientTexture1D.new()
	tex.gradient = gradient
	return tex

func _curve(points: Array, max_v: float) -> CurveTexture:
	var curve := Curve.new()
	curve.max_value = max_v
	for point in points:
		curve.add_point(point)
	var tex := CurveTexture.new()
	tex.curve = curve
	return tex
