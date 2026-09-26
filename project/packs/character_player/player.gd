extends CharacterBody3D
## Pemain = penyihir bergaya ANIME (ronde-46, pivot dari tank ke sihir lagi
## dengan visual jauh lebih hidup). Seluruhnya PROSEDURAL (primitive Godot +
## shader cel-shading `toon.gdshader` yang sudah ada di project) — TIDAK ada
## file model eksternal, karena sandbox pengerjaan ini tidak bisa mengunduh
## file biner (.vrm/.glb) dari internet (sudah dicoba & terverifikasi gagal).
##
## Gaya "chibi anime": kepala besar, mata besar bulat dengan kilau, rambut
## runcing bergaya, topi penyihir, jubah — semua dirakit dari primitive
## (sphere/cone/cylinder/capsule) dan shader toon 3-band + outline
## inverted-hull (`Materials.toon(color, outline=true)`), TANPA tekstur wajah
## (menghindari risiko UV salah wrap yang tak bisa saya pratinjau visual di
## sandbox ini). Aura partikel ungu-biru melayang terus-menerus di sekitar
## karakter supaya terasa "banyak efek" bahkan saat diam.
##
## Kamera & gerak: arsitektur sama seperti ronde-ronde sebelumnya (third-
## person murni ikut swipe, gerak bebas 8-arah relatif kamera) — terbukti
## stabil lintas-ronde, sengaja TIDAK diubah.
##
## Serangan: tap tombol serang = satu peluru sihir kecil (arcane_bolt.gd).
## Mantra andalan yang jauh lebih megah menyusul di Bagian B ronde-46.

signal stats_changed(kind: String, count: int)
signal nearest_interactable_changed(meta)
signal health_changed(current: float, maximum: float)

const Materials := preload("res://packs/shaders_materials/materials.gd")
const SHOOT_SFX := "res://packs/audio_sfx/fire_shoot.wav"
const ARCANE_BOLT := preload("res://packs/character_player/arcane_bolt.gd")
const FIRE_COOLDOWN := 0.3
const BOLT_SPEED := 21.0
const BOLT_LIFT := 1.8

# --- gerak (ringan, lincah — penyihir jalan kaki, bukan kendaraan) ---
const MAX_SPEED := 9.0
const ACCEL_RATE := 7.5
const DECEL_RATE := 4.5
const HOVER := 0.03          # cuma sedikit angkat dari y=0 (hindari z-fight jubah/tanah)
const ROBE_HEIGHT := 0.72
const ROBE_TOP_R := 0.15
const ROBE_BOTTOM_R := 0.30
const HEAD_RADIUS := 0.20

# --- kamera third-person (murni ikut swipe, arsitektur tak berubah) ---
const PITCH_MIN := deg_to_rad(-72.0)
const PITCH_MAX := deg_to_rad(-10.0)
const CAM_DIST := 7.6
const CAM_FOLLOW := 7.0
const LOOK_K := 0.0036
const CAM_FOCUS_HEIGHT := 1.05

# --- dash: burst cepat lalu melambat ---
const DASH_SPEED := 22.0
const DASH_DURATION := 0.30
const DASH_COOLDOWN := 1.1

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
var _head: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _hair_group: Node3D
var _robe_mesh: MeshInstance3D
var _aura_particles: GPUParticles3D
var _aura_material: ParticleProcessMaterial
var _base_amounts := {}
var _t := 0.0
var _speed01 := 0.0
var _cam_extra := 0.0
var _cam_snapped := false
var _facing := Vector3.ZERO
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
	_build_witch()
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

## Dipanggil peluru (arcane_bolt.gd) saat meledak di dekat pemain.
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

func set_attack_held(down: bool) -> void:
	if down:
		_try_fire()

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
	_spawn_dash_shimmer()

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
	_move(delta)
	_apply_camera(delta)
	_animate_witch(delta)

func _move(delta: float) -> void:
	if _dash_left > 0.0:
		_dash_left = maxf(0.0, _dash_left - delta)
		var progress := 1.0 - _dash_left / DASH_DURATION
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
	var focus := global_position + Vector3(0.0, CAM_FOCUS_HEIGHT, 0.0)
	if not _cam_snapped:
		cam_pivot.global_position = focus
		_cam_snapped = true
	else:
		cam_pivot.global_position = cam_pivot.global_position.lerp(focus, 1.0 - exp(-CAM_FOLLOW * delta))
	cam_pivot.rotation = Vector3(pitch, yaw, 0.0)
	_cam_extra = lerpf(_cam_extra, _speed01 * 1.2, 1.0 - exp(-3.0 * delta))
	cam_arm.spring_length = maxf(2.0, CAM_DIST + _cam_extra)
	_shake = maxf(0.0, _shake - 1.6 * delta)
	var shake_power := _shake * _shake * 0.35
	var cam: Camera3D = $CameraPivot/CamArm/Cam
	cam.h_offset = (sin(_t * 43.0) * 0.72 + sin(_t * 67.0 + 0.8) * 0.28) * shake_power
	cam.v_offset = (sin(_t * 51.0 + 1.7) * 0.7 + sin(_t * 79.0) * 0.3) * shake_power

func _animate_witch(delta: float) -> void:
	_visual.position = Vector3(0.0, HOVER, 0.0)
	var moving := _speed01 > 0.035 and _facing.length_squared() > 0.01
	if _facing.length_squared() > 0.01:
		var facing_yaw := atan2(-_facing.x, -_facing.z)
		_visual.rotation.y = lerp_angle(_visual.rotation.y, facing_yaw, 1.0 - exp(-14.0 * delta))
	# Idle bob + ayunan lengan/rambut prosedural (tanpa skeleton/AnimationPlayer).
	var bob := sin(_t * (7.5 if moving else 2.2)) * (0.028 if moving else 0.014) * (0.4 + 0.6 * _speed01 if moving else 1.0)
	_head.position.y = ROBE_HEIGHT + HEAD_RADIUS * 0.95 + bob
	var swing := sin(_t * 9.5) * (0.55 * clampf(_speed01, 0.15, 1.0)) if moving else sin(_t * 1.6) * 0.05
	_arm_l.rotation.x = swing
	_arm_r.rotation.x = -swing
	_hair_group.rotation.z = sin(_t * 2.6) * 0.05 + (-_facing.x * 0.12 if moving else 0.0)
	if _robe_mesh:
		_robe_mesh.scale = Vector3(1.0, 1.0 + sin(_t * 6.0) * 0.008 * (1.0 if moving else 0.4), 1.0)
	_aura_particles.position = Vector3(0.0, ROBE_HEIGHT * 0.55, 0.0)

# =============== Serangan ===============

func _shoot_direction() -> Vector3:
	if _facing.length_squared() > 0.01:
		return _facing.normalized()
	return (Basis(Vector3.UP, yaw) * Vector3(0, 0, -1)).normalized()

func _hand_position(direction: Vector3) -> Vector3:
	return _visual.global_position + Vector3.UP * (ROBE_HEIGHT * 0.72) + direction * 0.5

func _try_fire() -> void:
	if not is_ready or _fire_cooldown > 0.0:
		return
	_fire_cooldown = FIRE_COOLDOWN
	var direction := _shoot_direction()
	var origin := _hand_position(direction)
	var host: Node = world if is_instance_valid(world) and world.is_inside_tree() else get_parent()
	if host == null:
		return
	var bolt := ARCANE_BOLT.new()
	bolt.vel = direction * BOLT_SPEED + Vector3(velocity.x, 0, velocity.z) * 0.5 + Vector3.UP * BOLT_LIFT
	bolt.fx = _fx
	bolt.exclude_rids.append(get_rid())
	bolt.shake_target = self
	host.add_child(bolt)
	bolt.global_position = origin
	_shake = minf(_shake + 0.14, 0.8)
	_play_shoot_sound()

func _play_shoot_sound() -> void:
	if not ResourceLoader.exists(SHOOT_SFX):
		return
	var sound := AudioStreamPlayer.new()
	sound.stream = load(SHOOT_SFX)
	sound.bus = "SFX"
	sound.pitch_scale = randf_range(1.05, 1.25)
	sound.finished.connect(sound.queue_free)
	add_child(sound)
	sound.play()

# =============== Rakitan visual penyihir anime ===============

func _build_witch() -> void:
	_visual = Node3D.new()
	_visual.name = "WitchCharacter"
	_visual.position = Vector3(0.0, HOVER, 0.0)
	add_child(_visual)

	_build_robe()
	_build_arms()
	_build_head_group()
	_build_aura()

func _build_robe() -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = ROBE_TOP_R
	mesh.bottom_radius = ROBE_BOTTOM_R
	mesh.height = ROBE_HEIGHT
	mesh.radial_segments = 14
	_robe_mesh = MeshInstance3D.new()
	_robe_mesh.name = "Robe"
	_robe_mesh.mesh = mesh
	_robe_mesh.position = Vector3(0.0, ROBE_HEIGHT * 0.5, 0.0)
	_robe_mesh.material_override = Materials.toon(Color(0.30, 0.16, 0.52), true, 0.014)
	_visual.add_child(_robe_mesh)

	# Aksen sabuk supaya siluet jubah tak polos.
	var belt := MeshInstance3D.new()
	var belt_mesh := TorusMesh.new()
	belt_mesh.inner_radius = ROBE_TOP_R * 0.55
	belt_mesh.outer_radius = ROBE_TOP_R * 1.05
	belt.mesh = belt_mesh
	belt.position = Vector3(0.0, ROBE_HEIGHT * 0.86, 0.0)
	belt.material_override = Materials.toon(Color(0.86, 0.72, 0.20), false)
	_visual.add_child(belt)

func _build_arms() -> void:
	var mat := Materials.toon(Color(0.30, 0.16, 0.52), true, 0.012)
	var shoulder_y := ROBE_HEIGHT * 0.92
	_arm_l = _make_arm(mat, -1.0, shoulder_y)
	_arm_r = _make_arm(mat, 1.0, shoulder_y)

func _make_arm(mat: Material, side: float, shoulder_y: float) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = "ArmPivot" + ("L" if side < 0 else "R")
	pivot.position = Vector3(side * ROBE_TOP_R * 1.15, shoulder_y, 0.0)
	_visual.add_child(pivot)
	var arm := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.05
	cap.height = 0.34
	arm.mesh = cap
	arm.position = Vector3(0.0, -0.17, 0.0)
	arm.material_override = mat
	pivot.add_child(arm)
	# tangan bulat kecil di ujung, sedikit warna kulit
	var hand := MeshInstance3D.new()
	var hand_mesh := SphereMesh.new()
	hand_mesh.radius = 0.06
	hand_mesh.height = 0.12
	hand.mesh = hand_mesh
	hand.position = Vector3(0.0, -0.34, 0.0)
	hand.material_override = Materials.toon(Color(0.96, 0.82, 0.70), false)
	pivot.add_child(hand)
	return pivot

func _build_head_group() -> void:
	_head = Node3D.new()
	_head.name = "Head"
	_head.position = Vector3(0.0, ROBE_HEIGHT + HEAD_RADIUS * 0.95, 0.0)
	_visual.add_child(_head)

	var skin := Materials.toon(Color(0.97, 0.84, 0.73), true, 0.013)
	var face := MeshInstance3D.new()
	var face_mesh := SphereMesh.new()
	face_mesh.radius = HEAD_RADIUS
	face_mesh.height = HEAD_RADIUS * 2.0
	face_mesh.radial_segments = 20
	face_mesh.rings = 12
	face.mesh = face_mesh
	face.material_override = skin
	_head.add_child(face)

	_build_eyes()
	_build_hair()
	_build_hat()

func _build_eyes() -> void:
	var white := Materials.toon(Color(1.0, 1.0, 1.0), false)
	var iris := Materials.toon(Color(0.30, 0.55, 0.95), false)
	for side in [-1.0, 1.0]:
		var eye_root := Node3D.new()
		eye_root.position = Vector3(side * HEAD_RADIUS * 0.42, HEAD_RADIUS * 0.02, -HEAD_RADIUS * 0.86)
		_head.add_child(eye_root)
		var sclera := MeshInstance3D.new()
		var sclera_mesh := SphereMesh.new()
		sclera_mesh.radius = HEAD_RADIUS * 0.30
		sclera_mesh.height = HEAD_RADIUS * 0.30
		sclera.mesh = sclera_mesh
		sclera.scale = Vector3(1.0, 1.15, 0.55)
		sclera.material_override = white
		eye_root.add_child(sclera)
		var pupil := MeshInstance3D.new()
		var pupil_mesh := SphereMesh.new()
		pupil_mesh.radius = HEAD_RADIUS * 0.17
		pupil_mesh.height = HEAD_RADIUS * 0.17
		pupil.mesh = pupil_mesh
		pupil.scale = Vector3(1.0, 1.2, 0.5)
		pupil.position = Vector3(0.0, -HEAD_RADIUS * 0.02, -HEAD_RADIUS * 0.10)
		pupil.material_override = iris
		eye_root.add_child(pupil)
		# kilau mata — bulatan kecil unshaded, ciri khas mata anime berbinar
		var sparkle := MeshInstance3D.new()
		var sparkle_mesh := SphereMesh.new()
		sparkle_mesh.radius = HEAD_RADIUS * 0.055
		sparkle_mesh.height = HEAD_RADIUS * 0.055
		sparkle.mesh = sparkle_mesh
		sparkle.position = Vector3(HEAD_RADIUS * 0.08, HEAD_RADIUS * 0.10, -HEAD_RADIUS * 0.18)
		var sparkle_mat := StandardMaterial3D.new()
		sparkle_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sparkle_mat.albedo_color = Color(1.0, 1.0, 1.0)
		sparkle.material_override = sparkle_mat
		eye_root.add_child(sparkle)
	# pipi merona — dua quad lembut tipis di bawah mata
	var blush_tex := _soft_tex(0.15)
	for side in [-1.0, 1.0]:
		var blush := MeshInstance3D.new()
		blush.mesh = _quad(Vector2(0.10, 0.07), _fx_mat(blush_tex, false, Color(1.0, 0.55, 0.60, 0.55)))
		blush.position = Vector3(side * HEAD_RADIUS * 0.62, -HEAD_RADIUS * 0.20, -HEAD_RADIUS * 0.72)
		blush.rotation.y = side * -0.5
		blush.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_head.add_child(blush)

func _build_hair() -> void:
	_hair_group = Node3D.new()
	_hair_group.name = "Hair"
	_head.add_child(_hair_group)
	var hair_mat := Materials.toon(Color(0.86, 0.78, 0.95), true, 0.014)
	# poni depan
	var fringe := MeshInstance3D.new()
	var fringe_mesh := SphereMesh.new()
	fringe_mesh.radius = HEAD_RADIUS * 1.06
	fringe_mesh.height = HEAD_RADIUS * 1.4
	fringe_mesh.radial_segments = 16
	fringe_mesh.rings = 8
	fringe.mesh = fringe_mesh
	fringe.position = Vector3(0.0, HEAD_RADIUS * 0.18, 0.0)
	fringe.material_override = hair_mat
	_hair_group.add_child(fringe)
	# jambul-jambul runcing khas anime, tersebar di sekeliling atas kepala
	var spike_count := 7
	for i in spike_count:
		var ang := (float(i) / float(spike_count)) * TAU
		var spike := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0
		cm.bottom_radius = HEAD_RADIUS * 0.22
		cm.height = HEAD_RADIUS * (1.1 + 0.35 * fmod(float(i) * 0.37, 1.0))
		cm.radial_segments = 8
		spike.mesh = cm
		var r := HEAD_RADIUS * 0.75
		spike.position = Vector3(cos(ang) * r, HEAD_RADIUS * 0.55, sin(ang) * r * 0.85 - HEAD_RADIUS * 0.1)
		spike.rotation = Vector3(deg_to_rad(-28.0 + 10.0 * sin(ang)), ang, deg_to_rad(14.0 * cos(ang)))
		spike.material_override = hair_mat
		_hair_group.add_child(spike)
	# kuncir panjang di belakang, dua helai
	for side in [-1.0, 1.0]:
		var tail := MeshInstance3D.new()
		var tail_mesh := CapsuleMesh.new()
		tail_mesh.radius = HEAD_RADIUS * 0.16
		tail_mesh.height = HEAD_RADIUS * 1.8
		tail.mesh = tail_mesh
		tail.position = Vector3(side * HEAD_RADIUS * 0.7, -HEAD_RADIUS * 0.3, HEAD_RADIUS * 0.55)
		tail.rotation.x = deg_to_rad(24.0)
		tail.material_override = hair_mat
		_hair_group.add_child(tail)

func _build_hat() -> void:
	var hat_mat := Materials.toon(Color(0.20, 0.10, 0.36), true, 0.014)
	var brim := MeshInstance3D.new()
	var brim_mesh := CylinderMesh.new()
	brim_mesh.top_radius = HEAD_RADIUS * 1.35
	brim_mesh.bottom_radius = HEAD_RADIUS * 1.4
	brim_mesh.height = HEAD_RADIUS * 0.08
	brim_mesh.radial_segments = 20
	brim.mesh = brim_mesh
	brim.position = Vector3(0.0, HEAD_RADIUS * 0.62, 0.0)
	brim.material_override = hat_mat
	_head.add_child(brim)
	var cone := MeshInstance3D.new()
	var cone_mesh := CylinderMesh.new()
	cone_mesh.top_radius = 0.0
	cone_mesh.bottom_radius = HEAD_RADIUS * 0.62
	cone_mesh.height = HEAD_RADIUS * 1.7
	cone_mesh.radial_segments = 16
	cone.mesh = cone_mesh
	cone.position = Vector3(HEAD_RADIUS * 0.08, HEAD_RADIUS * 0.62 + HEAD_RADIUS * 0.85, 0.0)
	cone.rotation.z = deg_to_rad(-8.0)
	cone.material_override = hat_mat
	_head.add_child(cone)
	# aksen pita/bintang kecil di dasar topi
	var band := MeshInstance3D.new()
	var band_mesh := TorusMesh.new()
	band_mesh.inner_radius = HEAD_RADIUS * 0.55
	band_mesh.outer_radius = HEAD_RADIUS * 0.66
	band.mesh = band_mesh
	band.position = Vector3(HEAD_RADIUS * 0.05, HEAD_RADIUS * 0.68, 0.0)
	band.material_override = Materials.toon(Color(0.90, 0.75, 0.25), false)
	_head.add_child(band)

## Aura sihir ungu-biru yang melayang terus-menerus di sekitar karakter —
## permintaan pengguna "banyak efek" berlaku juga saat idle, bukan cuma saat
## menyerang.
func _build_aura() -> void:
	_aura_particles = GPUParticles3D.new()
	_aura_particles.name = "ArcaneAura"
	_aura_particles.amount = 26
	_aura_particles.lifetime = 1.6
	_aura_particles.randomness = 0.4
	_aura_particles.local_coords = false
	_aura_particles.fixed_fps = 60
	_aura_particles.interpolate = true
	_aura_particles.visibility_aabb = AABB(Vector3(-8, -2, -8), Vector3(16, 8, 16))
	_aura_particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_aura_particles.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	_visual.add_child(_aura_particles)

	_aura_material = ParticleProcessMaterial.new()
	_aura_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	_aura_material.emission_ring_axis = Vector3.UP
	_aura_material.emission_ring_radius = 0.42
	_aura_material.emission_ring_inner_radius = 0.30
	_aura_material.emission_ring_height = 0.05
	_aura_material.direction = Vector3.UP
	_aura_material.spread = 12.0
	_aura_material.initial_velocity_min = 0.16
	_aura_material.initial_velocity_max = 0.42
	_aura_material.gravity = Vector3.ZERO
	_aura_material.orbit_velocity_min = 0.18
	_aura_material.orbit_velocity_max = 0.30
	_aura_material.tangential_accel_min = 0.05
	_aura_material.tangential_accel_max = 0.12
	_aura_material.scale_min = 0.4
	_aura_material.scale_max = 0.9
	_aura_material.scale_curve = _curve([Vector2(0.0, 0.2), Vector2(0.3, 1.0), Vector2(1.0, 0.0)], 1.0)
	_aura_material.color_ramp = _ramp(
		[0.0, 0.3, 0.75, 1.0],
		[Color(0.55, 0.30, 1.0, 0.0), Color(0.62, 0.40, 1.0, 0.75), Color(0.35, 0.65, 1.0, 0.45), Color(0.2, 0.4, 1.0, 0.0)])
	_aura_particles.process_material = _aura_material
	var trail_mesh := QuadMesh.new()
	trail_mesh.size = Vector2(0.10, 0.10)
	trail_mesh.material = _fx_mat(_soft_tex(0.15), true, Color(0.6, 0.4, 1.0, 0.7))
	_aura_particles.draw_pass_1 = trail_mesh
	_aura_particles.emitting = true
	_base_amounts[_aura_particles] = _aura_particles.amount

func _spawn_dash_shimmer() -> void:
	var parent := get_parent()
	if parent == null:
		return
	var shimmer := MeshInstance3D.new()
	shimmer.name = "DashShimmer"
	var mesh := CylinderMesh.new()
	mesh.top_radius = ROBE_TOP_R * 1.1
	mesh.bottom_radius = ROBE_BOTTOM_R * 1.1
	mesh.height = ROBE_HEIGHT
	shimmer.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.55, 0.35, 1.0, 0.5)
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	shimmer.material_override = mat
	parent.add_child(shimmer)
	shimmer.global_position = global_position + Vector3.UP * (HOVER + ROBE_HEIGHT * 0.5)
	shimmer.rotation.y = _visual.global_rotation.y
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(mat, "albedo_color", Color(0.3, 0.15, 0.5, 0.0), 0.55)
	tween.parallel().tween_property(shimmer, "scale", Vector3(1.3, 0.4, 1.3), 0.55)
	tween.tween_callback(shimmer.queue_free)

# =============== helper FX kecil (gradient/quad/material) ===============

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

func _quad(size: Vector2, mat: Material) -> QuadMesh:
	var mesh := QuadMesh.new()
	mesh.size = size
	mesh.material = mat
	return mesh

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
