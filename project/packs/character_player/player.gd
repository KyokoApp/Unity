extends CharacterBody3D
## Pemain = satu balok kotak sederhana di atas tanah.
## Balok berputar ke kiri/kanan mengikuti arah gerak, punya outline gelap,
## dan meninggalkan trail ekor tipis.
##
## Kamera tetap third-person versi awal: hanya mengikuti posisi pemain dan
## berubah karena swipe. TIDAK ada auto-aim/auto-kamera lagi — kamera murni
## mengikuti input pemain.
##
## Serangan: tap cepat = tembakan mana biru kecil. Tahan tombol serang selama
## 5 detik memunculkan mantra "ZOLTRAAK" di depan karakter (tumbuh dari pudar
## ke lengkap); melepas tombol langsung menembakkan gelombang Zoltraak besar
## searah hadap karakter saat itu.

signal stats_changed(kind: String, count: int)
signal nearest_interactable_changed(meta)
signal health_changed(current: float, maximum: float)

const SHOOT_SFX := "res://packs/audio_sfx/fire_shoot.wav"
const FIRE_BOLT := preload("res://packs/character_player/fire_bolt.gd")
const FIRE_EXPLOSION := preload("res://packs/character_player/fire_explosion.gd")
const ZOLTRAAK_BOLT := preload("res://packs/character_player/zoltraak_bolt.gd")
const ZOLTRAAK_CHARGE := preload("res://packs/character_player/zoltraak_charge.gd")
const FIRE_COOLDOWN := 0.26
const BOLT_SPEED := 20.0
const BOLT_LIFT := 2.0

# --- mantra Zoltraak: tahan tombol serang untuk mengisi, lepas untuk tembak ---
const CHARGE_START_DELAY := 0.16
const CHARGE_FULL_TIME := 5.0
const ZOLTRAAK_COOLDOWN := 0.55

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

# --- dash: burst cepat lalu melambat, satu bayangan per dash ---
const DASH_SPEED := 24.0
const DASH_DURATION := 0.32
const DASH_COOLDOWN := 1.15

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
var _outline_material: StandardMaterial3D
var _trail_particles: GPUParticles3D
var _trail_material: ParticleProcessMaterial
var _base_amounts := {}
var _t := 0.0
var _speed01 := 0.0
var _cam_extra := 0.0
var _cam_snapped := false
var _facing := Vector3.ZERO
var _attack_held := false
var _was_holding := false
var _charge_active := false
var _charge_time := 0.0
var _charge_node: Node3D
var _fire_cooldown := 0.0
var _shake := 0.0
var _fx := 1.0
var _dash_left := 0.0
var _dash_cooldown := 0.0
var _dash_dir := Vector3.ZERO

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

func press_dash() -> void:
	if not is_ready or _dash_cooldown > 0.0 or _dash_left > 0.0:
		return
	var wish := joy
	if wish == Vector2.ZERO:
		wish = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var direction := Basis(Vector3.UP, yaw) * Vector3(wish.x, 0.0, wish.y)
	if direction.length_squared() < 0.01:
		direction = _shoot_direction()
	_dash_dir = direction.normalized()
	_dash_left = DASH_DURATION
	_dash_cooldown = DASH_COOLDOWN
	_spawn_dash_shadow()

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
	_dash_cooldown = maxf(0.0, _dash_cooldown - delta)
	_update_attack_hold(delta)
	_move(delta)
	_apply_camera(delta)
	_animate_cube(delta)

func _update_attack_hold(delta: float) -> void:
	var holding_now := _attack_held or Input.is_key_pressed(KEY_SPACE) or Input.is_key_pressed(KEY_F)
	if holding_now and not _was_holding:
		_charge_time = 0.0
		_charge_active = false
	if holding_now:
		_charge_time += delta
		if not _charge_active and _charge_time >= CHARGE_START_DELAY:
			_charge_active = true
			_spawn_charge_visual()
		if _charge_active:
			_update_charge_visual(delta)
	elif _was_holding and not holding_now:
		print("[dbg-player] lepas terdeteksi charge_active=", _charge_active, " cooldown=", _fire_cooldown, " is_ready=", is_ready)
		if _charge_active:
			_release_charge()
		else:
			_try_fire()
		_charge_time = 0.0
		_charge_active = false
	_was_holding = holding_now

func _move(delta: float) -> void:
	if _dash_left > 0.0:
		_dash_left = maxf(0.0, _dash_left - delta)
		var progress := 1.0 - _dash_left / DASH_DURATION
		# Ease-out: ledakan cepat di awal, lalu melambat sebelum normal lagi.
		var dash_factor := 1.0 - progress * progress
		var dash_velocity := _dash_dir * DASH_SPEED * dash_factor
		velocity = Vector3(dash_velocity.x, -global_position.y / maxf(delta, 0.001), dash_velocity.z)
		move_and_slide()
		_facing = _dash_dir
		_speed01 = lerpf(_speed01, dash_factor, 1.0 - exp(-12.0 * delta))
		return

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

func _animate_cube(delta: float) -> void:
	_visual.position = Vector3(0.0, HOVER, 0.0)
	var moving := _speed01 > 0.035 and _facing.length_squared() > 0.01
	if _facing.length_squared() > 0.01:
		var facing_yaw := atan2(-_facing.x, -_facing.z)
		_visual.rotation.y = lerp_angle(_visual.rotation.y, facing_yaw, 1.0 - exp(-14.0 * delta))
	_trail_particles.emitting = moving
	if moving:
		_trail_particles.position = Vector3(0.0, -HOVER + 0.12, 0.0) - _facing * 0.46
		_trail_material.direction = (-_facing + Vector3.UP * 0.08).normalized()
	else:
		_trail_particles.position = Vector3(0.0, -HOVER + 0.12, 0.0)

# =============== Serangan ===============

func _shoot_direction() -> Vector3:
	if _facing.length_squared() > 0.01:
		return _facing.normalized()
	return (Basis(Vector3.UP, yaw) * Vector3(0, 0, -1)).normalized()

func _try_fire() -> void:
	if not is_ready or _fire_cooldown > 0.0:
		print("[dbg-player] _try_fire diblokir is_ready=", is_ready, " cooldown=", _fire_cooldown)
		return
	print("[dbg-player] _try_fire lanjut")
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

# =============== Mantra Zoltraak (charge + release) ===============

func _spawn_charge_visual() -> void:
	if _charge_node and is_instance_valid(_charge_node):
		_charge_node.queue_free()
	_charge_node = ZOLTRAAK_CHARGE.new()
	add_child(_charge_node)
	_position_charge_node()

func _position_charge_node() -> void:
	if _charge_node == null or not is_instance_valid(_charge_node):
		return
	var direction := _shoot_direction()
	_charge_node.global_position = _visual.global_position + Vector3.UP * 0.05 + direction * 0.95

func _update_charge_visual(delta: float) -> void:
	if _charge_node == null or not is_instance_valid(_charge_node):
		return
	_position_charge_node()
	var progress := clampf((_charge_time - CHARGE_START_DELAY) / (CHARGE_FULL_TIME - CHARGE_START_DELAY), 0.0, 1.0)
	_charge_node.update_progress(progress, delta)
	var cam: Camera3D = $CameraPivot/CamArm/Cam
	_charge_node.face_camera(cam)

func _release_charge() -> void:
	var progress := clampf((_charge_time - CHARGE_START_DELAY) / (CHARGE_FULL_TIME - CHARGE_START_DELAY), 0.0, 1.0)
	var direction := _shoot_direction()
	if _charge_node and is_instance_valid(_charge_node):
		var node := _charge_node
		_charge_node = null
		node.dissolve_and_free()
	_fire_zoltraak(direction, progress)

func _fire_zoltraak(direction: Vector3, charge_fraction: float) -> void:
	if not is_ready:
		return
	var host: Node = world if is_instance_valid(world) and world.is_inside_tree() else get_parent()
	if host == null:
		return
	var bolt := ZOLTRAAK_BOLT.new()
	bolt.fx = _fx
	bolt.exclude_rids.append(get_rid())
	bolt.shake_target = self
	bolt.setup(direction, charge_fraction)
	host.add_child(bolt)
	bolt.global_position = _visual.global_position + direction * 0.7 + Vector3.UP * 0.05
	_shake = minf(_shake + 0.30 + 0.30 * charge_fraction, 0.9)
	_fire_cooldown = maxf(_fire_cooldown, ZOLTRAAK_COOLDOWN)
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

# =============== Kubus, outline, trail, bayangan dash ===============

func _build_cube() -> void:
	_visual = Node3D.new()
	_visual.name = "SquareCharacter"
	_visual.position = Vector3(0.0, HOVER, 0.0)
	add_child(_visual)
	var mesh := BoxMesh.new()
	mesh.size = CHARACTER_SIZE

	# Inverted hull sederhana: shell sedikit lebih besar dan cull front.
	var outline := MeshInstance3D.new()
	outline.name = "PlayerOutline"
	outline.mesh = mesh
	outline.scale = Vector3.ONE * 1.07
	_outline_material = StandardMaterial3D.new()
	_outline_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_outline_material.albedo_color = Color(0.015, 0.02, 0.035, 1.0)
	_outline_material.cull_mode = BaseMaterial3D.CULL_FRONT
	outline.material_override = _outline_material
	_visual.add_child(outline)

	var body := MeshInstance3D.new()
	body.name = "PlayerCube"
	body.mesh = mesh
	_body_material = StandardMaterial3D.new()
	_body_material.albedo_color = Color(0.20, 0.43, 0.62)
	_body_material.roughness = 0.78
	_body_material.metallic = 0.05
	body.material_override = _body_material
	_visual.add_child(body)

	_trail_particles = _base_particles("CubeTrail", 24, 0.48)
	_trail_material = ParticleProcessMaterial.new()
	_trail_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	_trail_material.emission_sphere_radius = 0.16
	_trail_material.direction = Vector3(0.0, 0.0, 1.0)
	_trail_material.spread = 10.0
	_trail_material.initial_velocity_min = 0.35
	_trail_material.initial_velocity_max = 1.35
	_trail_material.gravity = Vector3(0.0, 0.18, 0.0)
	_trail_material.damping_min = 0.25
	_trail_material.damping_max = 0.60
	_trail_material.scale_min = 0.50
	_trail_material.scale_max = 1.0
	_trail_material.scale_curve = _curve([Vector2(0.0, 0.72), Vector2(0.35, 0.52), Vector2(1.0, 0.0)], 1.0)
	_trail_material.color_ramp = _ramp(
		[0.0, 0.15, 0.65, 1.0],
		[Color(0.20, 0.75, 1.0, 0.36), Color(0.10, 0.55, 0.90, 0.24), Color(0.04, 0.18, 0.36, 0.08), Color(0.0, 0.0, 0.0, 0.0)])
	_trail_particles.process_material = _trail_material
	var trail_mesh := QuadMesh.new()
	trail_mesh.size = Vector2(0.20, 0.07)
	trail_mesh.material = _fx_mat(_soft_tex(0.18), true, Color(0.18, 0.72, 1.0, 0.42))
	_trail_particles.draw_pass_1 = trail_mesh
	_trail_particles.emitting = false
	_base_amounts[_trail_particles] = _trail_particles.amount

func _spawn_dash_shadow() -> void:
	var parent := get_parent()
	if parent == null:
		return
	var shadow := MeshInstance3D.new()
	shadow.name = "DashAfterimage"
	var mesh := BoxMesh.new()
	mesh.size = CHARACTER_SIZE * 1.04
	shadow.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.10, 0.36, 0.55, 0.48)
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	shadow.material_override = mat
	parent.add_child(shadow)
	shadow.global_position = global_position + Vector3.UP * HOVER
	shadow.rotation.y = _visual.global_rotation.y
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(mat, "albedo_color", Color(0.03, 0.12, 0.18, 0.0), 0.62)
	tween.parallel().tween_property(shadow, "scale", Vector3(1.10, 0.35, 1.10), 0.62)
	tween.tween_callback(shadow.queue_free)

func _base_particles(pname: String, amount: int, lifetime: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = pname
	p.amount = amount
	p.lifetime = lifetime
	p.randomness = 0.34
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
