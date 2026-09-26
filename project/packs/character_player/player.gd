extends CharacterBody3D
## Pemain = TANK kotak-kotak (ronde-45, pivot total dari mage ke game tank).
## Badan/hull tank berputar mengikuti arah GERAK (seperti track tank yang
## berbelok), sedangkan TURRET (menara + laras meriam) berputar independen
## mengikuti arah KAMERA/incar (swipe layar) — persis seperti tank sungguhan:
## badan jalan ke satu arah, menara tetap mengincar arah lain.
##
## Kamera: third-person, murni mengikuti swipe pemain (yaw/pitch), sama
## seperti sebelumnya — TIDAK ada auto-aim, tapi kini kamera search otomatis
## searah moncong meriam karena turret & kamera berbagi sudut `yaw` yang sama.
##
## Serangan: tap tombol serang = SATU tembakan meriam (tank_shell.gd), lalu
## reload (FIRE_COOLDOWN) sebelum bisa menembak lagi — tidak ada mode tahan
## untuk mengisi mantra lagi (sistem Zoltraak/mage DIHAPUS TOTAL saat pivot).

signal stats_changed(kind: String, count: int)
signal nearest_interactable_changed(meta)
signal health_changed(current: float, maximum: float)

const SHOOT_SFX := "res://packs/audio_sfx/fire_shoot.wav"
const TANK_SHELL := preload("res://packs/character_player/tank_shell.gd")
const FIRE_EXPLOSION := preload("res://packs/character_player/fire_explosion.gd")
const FIRE_COOLDOWN := 1.1     # jeda "reload" meriam antar tembakan
const SHELL_SPEED := 30.0
const SHELL_LIFT := 1.3

# --- gerak (tank lebih berat/lambat dari mage lama) ---
const MAX_SPEED := 7.2
const ACCEL_RATE := 4.6
const DECEL_RATE := 3.2
const TURN_RATE := 3.4          # kecepatan hull menoleh ke arah gerak baru
const HOVER := 0.42
const HULL_SIZE := Vector3(1.7, 0.56, 2.5)
const TURRET_SIZE := Vector3(0.92, 0.46, 1.05)
const BARREL_SIZE := Vector3(0.15, 0.15, 1.35)
const TRACK_SIZE := Vector3(0.28, 0.5, 2.5)

# --- kamera third-person (murni ikut swipe, tak berubah dari sebelumnya) ---
const PITCH_MIN := deg_to_rad(-72.0)
const PITCH_MAX := deg_to_rad(-10.0)
const CAM_DIST := 9.5
const CAM_FOLLOW := 7.0
const LOOK_K := 0.0036

# --- boost: burst kecepatan singkat lalu melambat, cooldown panjang ---
const BOOST_SPEED := 15.5
const BOOST_DURATION := 0.5
const BOOST_COOLDOWN := 3.0

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
var max_health := 150.0
var health := 150.0

var _hull: Node3D
var _turret: Node3D
var _hull_material: StandardMaterial3D
var _turret_material: StandardMaterial3D
var _outline_material: StandardMaterial3D
var _trail_particles: GPUParticles3D
var _trail_material: ParticleProcessMaterial
var _base_amounts := {}
var _t := 0.0
var _speed01 := 0.0
var _cam_extra := 0.0
var _cam_snapped := false
var _facing := Vector3.ZERO
var _fire_cooldown := 0.0
var _shake := 0.0
var _fx := 1.0
var _boost_left := 0.0
var _boost_cooldown := 0.0
var _boost_dir := Vector3.ZERO
var _recoil := 0.0

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
	_build_tank()
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

## Dipanggil peluru (tank_shell.gd) saat meledak di dekat pemain: getaran
## kamera kecil supaya dentuman terasa, walau bukan pemain yang ditembak.
func add_shake(amount: float) -> void:
	_shake = minf(_shake + maxf(0.0, amount), 0.9)

func press_jump() -> void:
	pass

func press_sprint(_down: bool) -> void:
	pass

func press_interact() -> void:
	pass

func press_attack() -> void:
	_try_fire()

## Tap = satu tembakan (bukan tahan-isi seperti mage lama). Dipanggil HUD
## setiap kali tombol serang disentuh (down=true) — ditekan lagi sebelum
## reload selesai diabaikan oleh _fire_cooldown di _try_fire().
func set_attack_held(down: bool) -> void:
	if down:
		_try_fire()

func press_dash() -> void:
	if not is_ready or _boost_cooldown > 0.0 or _boost_left > 0.0:
		return
	var wish := joy
	if wish == Vector2.ZERO:
		wish = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var direction := Basis(Vector3.UP, yaw) * Vector3(wish.x, 0.0, wish.y)
	if direction.length_squared() < 0.01:
		direction = _shoot_direction()
	_boost_dir = direction.normalized()
	_boost_left = BOOST_DURATION
	_boost_cooldown = BOOST_COOLDOWN
	_spawn_boost_puff()

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
	_boost_cooldown = maxf(0.0, _boost_cooldown - delta)
	_move(delta)
	_apply_camera(delta)
	_animate_tank(delta)

func _move(delta: float) -> void:
	if _boost_left > 0.0:
		_boost_left = maxf(0.0, _boost_left - delta)
		var progress := 1.0 - _boost_left / BOOST_DURATION
		# Ease-out: ledakan cepat di awal, lalu melambat sebelum normal lagi.
		var boost_factor := 1.0 - progress * progress
		var boost_velocity := _boost_dir * BOOST_SPEED * boost_factor
		velocity = Vector3(boost_velocity.x, -global_position.y / maxf(delta, 0.001), boost_velocity.z)
		move_and_slide()
		_facing = _boost_dir
		_speed01 = lerpf(_speed01, boost_factor, 1.0 - exp(-12.0 * delta))
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
	var focus := global_position + Vector3(0.0, HOVER + 0.35, 0.0)
	if not _cam_snapped:
		cam_pivot.global_position = focus
		_cam_snapped = true
	else:
		cam_pivot.global_position = cam_pivot.global_position.lerp(focus, 1.0 - exp(-CAM_FOLLOW * delta))
	cam_pivot.rotation = Vector3(pitch, yaw, 0.0)
	_cam_extra = lerpf(_cam_extra, _speed01 * 1.1, 1.0 - exp(-3.0 * delta))
	cam_arm.spring_length = maxf(2.2, CAM_DIST + _cam_extra)
	_shake = maxf(0.0, _shake - 1.6 * delta)
	var shake_power := _shake * _shake * 0.35
	var cam: Camera3D = $CameraPivot/CamArm/Cam
	cam.h_offset = (sin(_t * 43.0) * 0.72 + sin(_t * 67.0 + 0.8) * 0.28) * shake_power
	cam.v_offset = (sin(_t * 51.0 + 1.7) * 0.7 + sin(_t * 79.0) * 0.3) * shake_power

func _animate_tank(delta: float) -> void:
	_hull.position = Vector3(0.0, HOVER, 0.0)
	var moving := _speed01 > 0.035 and _facing.length_squared() > 0.01
	if _facing.length_squared() > 0.01:
		var facing_yaw := atan2(-_facing.x, -_facing.z)
		_hull.rotation.y = lerp_angle(_hull.rotation.y, facing_yaw, 1.0 - exp(-TURN_RATE * 4.0 * delta))
	# Turret independen dari hull: selalu mengincar arah kamera/swipe (yaw).
	_turret.rotation.y = lerp_angle(_turret.rotation.y, yaw, 1.0 - exp(-16.0 * delta))
	_recoil = lerpf(_recoil, 0.0, 1.0 - exp(-10.0 * delta))
	_turret.position.z = _recoil * 0.18
	_trail_particles.emitting = moving
	if moving:
		_trail_particles.position = Vector3(0.0, -HOVER + 0.1, 0.0) - _facing * 1.1
		_trail_material.direction = (-_facing + Vector3.UP * 0.05).normalized()
	else:
		_trail_particles.position = Vector3(0.0, -HOVER + 0.1, 0.0)

# =============== Serangan ===============

## Arah tembak meriam = arah TURRET (kamera/incar), BUKAN arah gerak hull —
## seperti tank sungguhan: badan boleh jalan ke mana saja, moncong meriam
## tetap mengincar sesuai swipe kamera. Dipakai `_turret.rotation.y` (bukan
## `yaw` mentah) supaya tembakan SELALU cocok persis dengan arah laras yang
## tampil di layar, walau turret sedang menyusul yaw baru (lerp halus).
func _shoot_direction() -> Vector3:
	return (Basis(Vector3.UP, _turret.rotation.y) * Vector3(0, 0, -1)).normalized()

func _muzzle_position(direction: Vector3) -> Vector3:
	return _turret.global_position + direction * (BARREL_SIZE.z + 0.15)

func _try_fire() -> void:
	if not is_ready or _fire_cooldown > 0.0:
		return
	_fire_cooldown = FIRE_COOLDOWN
	var direction := _shoot_direction()
	var origin := _muzzle_position(direction)
	var host: Node = world if is_instance_valid(world) and world.is_inside_tree() else get_parent()
	if host == null:
		return
	var shell := TANK_SHELL.new()
	shell.vel = direction * SHELL_SPEED + Vector3(velocity.x, 0, velocity.z) * 0.4 + Vector3.UP * SHELL_LIFT
	shell.fx = _fx
	shell.exclude_rids.append(get_rid())
	shell.shake_target = self
	host.add_child(shell)
	shell.global_position = origin
	var muzzle := FIRE_EXPLOSION.new()
	muzzle.kind = "muzzle"
	muzzle.fx = _fx
	muzzle.dir = direction
	host.add_child(muzzle)
	muzzle.global_position = origin
	_shake = minf(_shake + 0.22, 0.85)
	_recoil = 1.0
	_play_shoot_sound()

func _play_shoot_sound() -> void:
	if not ResourceLoader.exists(SHOOT_SFX):
		return
	var sound := AudioStreamPlayer.new()
	sound.stream = load(SHOOT_SFX)
	sound.bus = "SFX"
	sound.pitch_scale = randf_range(0.85, 0.98)
	sound.finished.connect(sound.queue_free)
	add_child(sound)
	sound.play()

# =============== Tank: hull, turret, laras, trek, trail, boost ===============

func _build_tank() -> void:
	_hull = Node3D.new()
	_hull.name = "TankHull"
	_hull.position = Vector3(0.0, HOVER, 0.0)
	add_child(_hull)

	var hull_mesh := BoxMesh.new()
	hull_mesh.size = HULL_SIZE

	# Inverted hull sederhana: shell sedikit lebih besar dan cull front.
	var outline := MeshInstance3D.new()
	outline.name = "HullOutline"
	outline.mesh = hull_mesh
	outline.scale = Vector3.ONE * 1.05
	_outline_material = StandardMaterial3D.new()
	_outline_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_outline_material.albedo_color = Color(0.01, 0.015, 0.01, 1.0)
	_outline_material.cull_mode = BaseMaterial3D.CULL_FRONT
	outline.material_override = _outline_material
	_hull.add_child(outline)

	var body := MeshInstance3D.new()
	body.name = "HullBody"
	body.mesh = hull_mesh
	_hull_material = StandardMaterial3D.new()
	_hull_material.albedo_color = Color(0.27, 0.34, 0.20)
	_hull_material.roughness = 0.85
	_hull_material.metallic = 0.15
	body.material_override = _hull_material
	_hull.add_child(body)

	# Trek/rantai di kedua sisi — kubus gelap panjang, murni kosmetik.
	var track_mat := StandardMaterial3D.new()
	track_mat.albedo_color = Color(0.07, 0.07, 0.08)
	track_mat.roughness = 0.95
	for side in [-1.0, 1.0]:
		var track := MeshInstance3D.new()
		track.name = "Track"
		var track_mesh := BoxMesh.new()
		track_mesh.size = TRACK_SIZE
		track.mesh = track_mesh
		track.material_override = track_mat
		track.position = Vector3(side * (HULL_SIZE.x * 0.5 + TRACK_SIZE.x * 0.35), -HULL_SIZE.y * 0.12, 0.0)
		_hull.add_child(track)

	# Turret TIDAK jadi anak _hull (yang berputar ikut arah gerak) — turret
	# anak langsung dari player root supaya rotasinya independen (lihat
	# _animate_tank: _turret.rotation.y mengejar `yaw`, bukan facing hull).
	_turret = Node3D.new()
	_turret.name = "Turret"
	_turret.position = Vector3(0.0, HOVER + HULL_SIZE.y * 0.5 + TURRET_SIZE.y * 0.55, 0.0)
	add_child(_turret)

	var turret_body := MeshInstance3D.new()
	turret_body.name = "TurretBody"
	var turret_mesh := BoxMesh.new()
	turret_mesh.size = TURRET_SIZE
	turret_body.mesh = turret_mesh
	_turret_material = StandardMaterial3D.new()
	_turret_material.albedo_color = Color(0.22, 0.28, 0.17)
	_turret_material.roughness = 0.82
	_turret_material.metallic = 0.18
	turret_body.material_override = _turret_material
	_turret.add_child(turret_body)

	var barrel := MeshInstance3D.new()
	barrel.name = "Barrel"
	var barrel_mesh := BoxMesh.new()
	barrel_mesh.size = BARREL_SIZE
	barrel.mesh = barrel_mesh
	var barrel_mat := StandardMaterial3D.new()
	barrel_mat.albedo_color = Color(0.13, 0.13, 0.15)
	barrel_mat.roughness = 0.55
	barrel_mat.metallic = 0.55
	barrel.material_override = barrel_mat
	barrel.position = Vector3(0.0, 0.0, -(TURRET_SIZE.z * 0.5 + BARREL_SIZE.z * 0.5))
	_turret.add_child(barrel)

	_trail_particles = _base_particles("DustTrail", 20, 0.6)
	_trail_material = ParticleProcessMaterial.new()
	_trail_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	_trail_material.emission_sphere_radius = 0.22
	_trail_material.direction = Vector3(0.0, 0.0, 1.0)
	_trail_material.spread = 22.0
	_trail_material.initial_velocity_min = 0.3
	_trail_material.initial_velocity_max = 1.1
	_trail_material.gravity = Vector3(0.0, 0.35, 0.0)
	_trail_material.damping_min = 0.4
	_trail_material.damping_max = 0.85
	_trail_material.scale_min = 0.55
	_trail_material.scale_max = 1.15
	_trail_material.scale_curve = _curve([Vector2(0.0, 0.3), Vector2(0.3, 1.0), Vector2(1.0, 1.6)], 1.6)
	_trail_material.color_ramp = _ramp(
		[0.0, 0.2, 0.7, 1.0],
		[Color(0.55, 0.48, 0.36, 0.0), Color(0.55, 0.48, 0.36, 0.30), Color(0.5, 0.45, 0.38, 0.16), Color(0.5, 0.45, 0.38, 0.0)])
	_trail_particles.process_material = _trail_material
	var trail_mesh := QuadMesh.new()
	trail_mesh.size = Vector2(0.5, 0.5)
	trail_mesh.material = _fx_mat(_soft_tex(0.1), false, Color(0.55, 0.48, 0.36, 0.5))
	_trail_particles.draw_pass_1 = trail_mesh
	_trail_particles.emitting = false
	_base_amounts[_trail_particles] = _trail_particles.amount

func _spawn_boost_puff() -> void:
	var parent := get_parent()
	if parent == null:
		return
	var puff := MeshInstance3D.new()
	puff.name = "BoostPuff"
	var mesh := BoxMesh.new()
	mesh.size = HULL_SIZE * 1.05
	puff.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.4, 0.4, 0.36, 0.42)
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	puff.material_override = mat
	parent.add_child(puff)
	puff.global_position = global_position + Vector3.UP * HOVER
	puff.rotation.y = _hull.global_rotation.y
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(mat, "albedo_color", Color(0.3, 0.28, 0.24, 0.0), 0.55)
	tween.parallel().tween_property(puff, "scale", Vector3(1.25, 0.35, 1.25), 0.55)
	tween.tween_callback(puff.queue_free)

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
	_hull.add_child(p)
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
