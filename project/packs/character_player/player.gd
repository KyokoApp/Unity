extends CharacterBody3D
## Pemain = penyihir bergaya ANIME (ronde-46), 100% PROSEDURAL (primitive
## Godot + shader cel-shading `toon.gdshader` yang sudah ada di project) —
## TIDAK ada file model eksternal, karena sandbox pengerjaan ini tidak bisa
## mengunduh file biner (.vrm/.glb) dari internet (sudah dicoba & terverifikasi
## gagal).
##
## Ronde-46 bag. A2: siluet & animasi dirombak supaya TIDAK terlihat seperti
## "stickman" (masukan pengguna setelah bag. A). Perubahan inti:
## - Kaki & sepatu bot kini TERLIHAT (2 segmen: paha + betis, bukan disembunyikan
##   jubah panjang sampai tanah) dengan tekuk lutut prosedural.
## - Jubah dipendekkan jadi tunik ber-flare (bahu lebih sempit -> pinggul lebih
##   lebar) supaya ada bentuk badan, bukan kerucut polos.
##   Bahu diberi bantalan bulat + lengan lebih tebal + manset di pergelangan.
## - Cape kecil 3-segmen di punggung yang berkibar mengikuti gerak/kecepatan.
## - Siklus jalan/lari (gait) kini berbasis JARAK TEMPUH (bukan waktu murni)
##   supaya frekuensi langkah menyesuaikan kecepatan asli: kaki berlawanan
##   fasa dengan lengan seberang (gaya jalan manusia alami), badan condong ke
##   depan saat berlari, dan ada DEBU JEJAK KAKI setiap kali kaki mendarat.
##
## Gaya "chibi anime": kepala besar, mata besar bulat dengan kilau, rambut
## runcing bergaya, topi penyihir — semua dirakit dari primitive
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
const HOVER := 0.03          # cuma sedikit angkat dari y=0 (hindari z-fight kaki/tanah)

# --- proporsi tubuh (chibi-anime: kepala besar, kaki & sepatu bot terlihat) ---
const HEAD_RADIUS := 0.20
const HIP_Y := 0.55           # sendi pinggul (kaki menggantung dari sini ke tanah)
const SHOULDER_Y := 0.98       # sendi bahu (tunik & lengan menggantung dari sini)
const TUNIC_TOP_R := 0.185     # radius tunik di bahu (sempit)
const TUNIC_BOTTOM_R := 0.29   # radius tunik di pinggul (melebar -> siluet "A-line")
const LEG_THIGH_LEN := 0.27
const LEG_SHIN_LEN := 0.26
const ARM_UPPER_LEN := 0.19
const ARM_FORE_LEN := 0.16

# --- animasi gait (berbasis jarak tempuh, bukan waktu murni) ---
const STRIDE_FREQ := 1.9       # radian fase per meter tempuh
const LEG_SWING_MAX := deg_to_rad(36.0)
const KNEE_BEND_MAX := deg_to_rad(58.0)
const ARM_SWING_MAX := deg_to_rad(42.0)
const ELBOW_BEND_BASE := deg_to_rad(10.0)
const ELBOW_BEND_MAX := deg_to_rad(24.0)
const TORSO_LEAN_MAX := deg_to_rad(9.0)

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
var _upper: Node3D            # torso+kepala+lengan+cape — bisa condong (lean)
var _head: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _fore_l: Node3D
var _fore_r: Node3D
var _hip_l: Node3D
var _hip_r: Node3D
var _shin_l: Node3D
var _shin_r: Node3D
var _hair_group: Node3D
var _cape_segs: Array[Node3D] = []
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
var _gait_phase := 0.0
var _prev_leg_l_sin := 0.0
var _prev_leg_r_sin := 0.0

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
		_advance_gait(DASH_SPEED * dash_factor, delta)
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
	_advance_gait(hv.length(), delta)

## Fase gait maju sebanding JARAK TEMPUH (bukan cuma delta*konstan) supaya
## panjang langkah terasa konsisten di berbagai kecepatan — lebih "detail"
## & alami dibanding sinus berbasis waktu murni.
func _advance_gait(speed: float, delta: float) -> void:
	if speed > 0.05:
		_gait_phase = fmod(_gait_phase + speed * delta * STRIDE_FREQ, TAU)
	# saat diam, fase gait dibekukan (idle punya animasi terpisah di _animate_witch)

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

	var amt := clampf(_speed01 * 1.3, 0.0, 1.0)
	var leg_l_sin := sin(_gait_phase)
	var leg_r_sin := sin(_gait_phase + PI)

	if moving:
		# ---------- kaki: paha berayun, betis menekuk saat mengayun maju ----------
		_hip_l.rotation.x = leg_l_sin * LEG_SWING_MAX * amt
		_hip_r.rotation.x = leg_r_sin * LEG_SWING_MAX * amt
		_shin_l.rotation.x = maxf(0.0, leg_l_sin) * KNEE_BEND_MAX * amt
		_shin_r.rotation.x = maxf(0.0, leg_r_sin) * KNEE_BEND_MAX * amt
		# ---------- lengan: berlawanan fasa dgn kaki seberang (gaya jalan alami) ----------
		_arm_l.rotation.x = leg_r_sin * ARM_SWING_MAX * amt * 0.85
		_arm_r.rotation.x = leg_l_sin * ARM_SWING_MAX * amt * 0.85
		_fore_l.rotation.x = ELBOW_BEND_BASE + maxf(0.0, -leg_r_sin) * ELBOW_BEND_MAX * amt
		_fore_r.rotation.x = ELBOW_BEND_BASE + maxf(0.0, -leg_l_sin) * ELBOW_BEND_MAX * amt
		# ---------- badan condong ke depan saat berlari + bob per langkah ----------
		_upper.rotation.x = lerp_angle(_upper.rotation.x, -TORSO_LEAN_MAX * amt, 1.0 - exp(-8.0 * delta))
		var bob := absf(sin(_gait_phase)) * 0.05 * amt
		_upper.position.y = HIP_Y + bob
		_hair_group.rotation.z = -_facing.x * 0.14 * amt if is_instance_valid(_hair_group) else 0.0
		# ---------- debu jejak kaki: picu saat kaki mendarat (sin lewat 0 turun) ----------
		if _prev_leg_l_sin > 0.0 and leg_l_sin <= 0.0 and amt > 0.2:
			_spawn_footstep_dust(-1.0)
		if _prev_leg_r_sin > 0.0 and leg_r_sin <= 0.0 and amt > 0.2:
			_spawn_footstep_dust(1.0)
	else:
		# ---------- idle: napas halus + ayun ringan ----------
		var idle_sway := sin(_t * 1.4) * 0.04
		_hip_l.rotation.x = lerp_angle(_hip_l.rotation.x, 0.0, 1.0 - exp(-6.0 * delta))
		_hip_r.rotation.x = lerp_angle(_hip_r.rotation.x, 0.0, 1.0 - exp(-6.0 * delta))
		_shin_l.rotation.x = lerp_angle(_shin_l.rotation.x, 0.0, 1.0 - exp(-6.0 * delta))
		_shin_r.rotation.x = lerp_angle(_shin_r.rotation.x, 0.0, 1.0 - exp(-6.0 * delta))
		_arm_l.rotation.x = lerp_angle(_arm_l.rotation.x, idle_sway, 1.0 - exp(-6.0 * delta))
		_arm_r.rotation.x = lerp_angle(_arm_r.rotation.x, -idle_sway, 1.0 - exp(-6.0 * delta))
		_fore_l.rotation.x = lerp_angle(_fore_l.rotation.x, ELBOW_BEND_BASE, 1.0 - exp(-6.0 * delta))
		_fore_r.rotation.x = lerp_angle(_fore_r.rotation.x, ELBOW_BEND_BASE, 1.0 - exp(-6.0 * delta))
		_upper.rotation.x = lerp_angle(_upper.rotation.x, 0.0, 1.0 - exp(-6.0 * delta))
		_upper.position.y = HIP_Y + sin(_t * 1.7) * 0.012
		_hair_group.rotation.z = sin(_t * 2.6) * 0.05
	_prev_leg_l_sin = leg_l_sin
	_prev_leg_r_sin = leg_r_sin

	var head_bob := sin(_t * (7.5 if moving else 2.2)) * (0.018 if moving else 0.010)
	_head.position.y = (SHOULDER_Y - HIP_Y) + HEAD_RADIUS * 0.95 + head_bob

	# ---------- cape: 3 segmen berkibar, makin melebar saat lari ----------
	var blow := clampf(_speed01, 0.0, 1.0)
	for i in _cape_segs.size():
		var seg := _cape_segs[i]
		var phase := _t * 3.2 - float(i) * 0.9
		var target_x := deg_to_rad(18.0 + 34.0 * blow) + sin(phase) * deg_to_rad(6.0 + 10.0 * (1.0 - blow))
		seg.rotation.x = lerp_angle(seg.rotation.x, target_x, 1.0 - exp(-(5.0 - float(i) * 0.8) * delta))
		seg.rotation.z = lerp_angle(seg.rotation.z, sin(phase * 0.7) * deg_to_rad(8.0), 1.0 - exp(-4.0 * delta))

	_aura_particles.position = Vector3(0.0, HIP_Y + (SHOULDER_Y - HIP_Y) * 0.5, 0.0)

# =============== Serangan ===============

func _shoot_direction() -> Vector3:
	if _facing.length_squared() > 0.01:
		return _facing.normalized()
	return (Basis(Vector3.UP, yaw) * Vector3(0, 0, -1)).normalized()

func _hand_position(direction: Vector3) -> Vector3:
	return _visual.global_position + Vector3.UP * (SHOULDER_Y * 0.82) + direction * 0.5

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

	_build_legs()

	_upper = Node3D.new()
	_upper.name = "Upper"
	_upper.position = Vector3(0.0, HIP_Y, 0.0)
	_visual.add_child(_upper)

	_build_tunic()
	_build_arms()
	_build_head_group()
	_build_cape()
	_build_aura()

# ---------- kaki (2 segmen: paha + betis, dengan sepatu bot) ----------

func _build_legs() -> void:
	var boot_mat := Materials.toon(Color(0.17, 0.11, 0.24), true, 0.012)
	_hip_l = _make_leg(boot_mat, -1.0)
	_hip_r = _make_leg(boot_mat, 1.0)

func _make_leg(mat: Material, side: float) -> Node3D:
	var hip := Node3D.new()
	hip.name = "HipPivot" + ("L" if side < 0 else "R")
	hip.position = Vector3(side * 0.115, HIP_Y, 0.0)
	_visual.add_child(hip)

	var thigh := MeshInstance3D.new()
	var thigh_mesh := CapsuleMesh.new()
	thigh_mesh.radius = 0.082
	thigh_mesh.height = LEG_THIGH_LEN
	thigh.mesh = thigh_mesh
	thigh.position = Vector3(0.0, -LEG_THIGH_LEN * 0.5, 0.0)
	thigh.material_override = mat
	hip.add_child(thigh)

	var shin := Node3D.new()
	shin.name = "ShinPivot"
	shin.position = Vector3(0.0, -LEG_THIGH_LEN, 0.0)
	hip.add_child(shin)
	if side < 0.0:
		_shin_l = shin
	else:
		_shin_r = shin

	var shin_mesh_inst := MeshInstance3D.new()
	var shin_mesh := CapsuleMesh.new()
	shin_mesh.radius = 0.068
	shin_mesh.height = LEG_SHIN_LEN
	shin_mesh_inst.mesh = shin_mesh
	shin_mesh_inst.position = Vector3(0.0, -LEG_SHIN_LEN * 0.5, 0.0)
	shin_mesh_inst.material_override = mat
	shin.add_child(shin_mesh_inst)

	var boot := MeshInstance3D.new()
	var boot_mesh := BoxMesh.new()
	boot_mesh.size = Vector3(0.13, 0.09, 0.20)
	boot.mesh = boot_mesh
	boot.position = Vector3(0.0, -LEG_SHIN_LEN - 0.02, 0.035)
	boot.material_override = Materials.toon(Color(0.12, 0.08, 0.18), false)
	shin.add_child(boot)
	return hip

# ---------- tunik ber-flare (bahu sempit -> pinggul lebar) ----------

func _build_tunic() -> void:
	var tunic_h := SHOULDER_Y - HIP_Y
	var mesh := CylinderMesh.new()
	mesh.top_radius = TUNIC_TOP_R
	mesh.bottom_radius = TUNIC_BOTTOM_R
	mesh.height = tunic_h
	mesh.radial_segments = 16
	var tunic := MeshInstance3D.new()
	tunic.name = "Tunic"
	tunic.mesh = mesh
	tunic.position = Vector3(0.0, tunic_h * 0.5, 0.0)
	tunic.material_override = Materials.toon(Color(0.30, 0.16, 0.52), true, 0.014)
	_upper.add_child(tunic)

	# Sabuk di pinggang (2/3 tinggi tunik dari bawah).
	var belt := MeshInstance3D.new()
	var belt_mesh := TorusMesh.new()
	belt_mesh.inner_radius = lerpf(TUNIC_BOTTOM_R, TUNIC_TOP_R, 0.35) * 0.92
	belt_mesh.outer_radius = lerpf(TUNIC_BOTTOM_R, TUNIC_TOP_R, 0.35) * 1.08
	belt.mesh = belt_mesh
	belt.position = Vector3(0.0, tunic_h * 0.32, 0.0)
	belt.material_override = Materials.toon(Color(0.86, 0.72, 0.20), false)
	_upper.add_child(belt)

	# Kerah/kolar kecil di leher supaya transisi ke kepala tidak polos.
	var collar := MeshInstance3D.new()
	var collar_mesh := TorusMesh.new()
	collar_mesh.inner_radius = TUNIC_TOP_R * 0.7
	collar_mesh.outer_radius = TUNIC_TOP_R * 0.95
	collar.mesh = collar_mesh
	collar.position = Vector3(0.0, tunic_h + 0.01, 0.0)
	collar.material_override = Materials.toon(Color(0.20, 0.10, 0.36), false)
	_upper.add_child(collar)

# ---------- lengan (2 segmen: lengan atas + lengan bawah, manset & bantalan bahu) ----------

func _build_arms() -> void:
	var robe_mat := Materials.toon(Color(0.30, 0.16, 0.52), true, 0.012)
	var shoulder_local_y := SHOULDER_Y - HIP_Y
	_make_arm(robe_mat, -1.0, shoulder_local_y)
	_make_arm(robe_mat, 1.0, shoulder_local_y)

func _make_arm(mat: Material, side: float, shoulder_y: float) -> void:
	var shoulder_pos := Vector3(side * (TUNIC_TOP_R * 1.05 + 0.05), shoulder_y - 0.03, 0.0)
	var pivot := Node3D.new()
	pivot.name = "ArmPivot" + ("L" if side < 0 else "R")
	pivot.position = shoulder_pos
	_upper.add_child(pivot)
	if side < 0.0:
		_arm_l = pivot
	else:
		_arm_r = pivot

	# Bantalan bahu bulat — menutup sendi & melebarkan siluet bahu.
	var pad := MeshInstance3D.new()
	var pad_mesh := SphereMesh.new()
	pad_mesh.radius = 0.085
	pad_mesh.height = 0.17
	pad.mesh = pad_mesh
	pad.scale = Vector3(1.0, 0.85, 1.0)
	pad.material_override = mat
	pivot.add_child(pad)

	var upper_arm := MeshInstance3D.new()
	var upper_mesh := CapsuleMesh.new()
	upper_mesh.radius = 0.075
	upper_mesh.height = ARM_UPPER_LEN
	upper_arm.mesh = upper_mesh
	upper_arm.position = Vector3(0.0, -ARM_UPPER_LEN * 0.5, 0.0)
	upper_arm.material_override = mat
	pivot.add_child(upper_arm)

	var forearm_pivot := Node3D.new()
	forearm_pivot.name = "ForearmPivot"
	forearm_pivot.position = Vector3(0.0, -ARM_UPPER_LEN, 0.0)
	pivot.add_child(forearm_pivot)
	if side < 0.0:
		_fore_l = forearm_pivot
	else:
		_fore_r = forearm_pivot

	var forearm := MeshInstance3D.new()
	var fore_mesh := CapsuleMesh.new()
	fore_mesh.radius = 0.062
	fore_mesh.height = ARM_FORE_LEN
	forearm.mesh = fore_mesh
	forearm.position = Vector3(0.0, -ARM_FORE_LEN * 0.5, 0.0)
	forearm.material_override = mat
	forearm_pivot.add_child(forearm)

	# Manset lengan bergaya jubah, di dekat pergelangan.
	var cuff := MeshInstance3D.new()
	var cuff_mesh := CylinderMesh.new()
	cuff_mesh.top_radius = 0.065
	cuff_mesh.bottom_radius = 0.10
	cuff_mesh.height = 0.09
	cuff.mesh = cuff_mesh
	cuff.position = Vector3(0.0, -ARM_FORE_LEN * 0.72, 0.0)
	cuff.material_override = mat
	forearm_pivot.add_child(cuff)

	var hand := MeshInstance3D.new()
	var hand_mesh := SphereMesh.new()
	hand_mesh.radius = 0.058
	hand_mesh.height = 0.116
	hand.mesh = hand_mesh
	hand.position = Vector3(0.0, -ARM_FORE_LEN - 0.02, 0.0)
	hand.material_override = Materials.toon(Color(0.96, 0.82, 0.70), false)
	forearm_pivot.add_child(hand)

func _build_head_group() -> void:
	_head = Node3D.new()
	_head.name = "Head"
	_head.position = Vector3(0.0, (SHOULDER_Y - HIP_Y) + HEAD_RADIUS * 0.95, 0.0)
	_upper.add_child(_head)

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

## Cape kecil 3-segmen di punggung — berkibar mengikuti kecepatan gerak,
## sekaligus memecah siluet polos dari belakang (sudut kamera utama).
func _build_cape() -> void:
	var cape_mat := Materials.toon(Color(0.20, 0.08, 0.38), true, 0.014)
	var seg_h := 0.20
	var attach_y := (SHOULDER_Y - HIP_Y) - 0.06
	var parent: Node3D = _upper
	var width := 0.30
	for i in 3:
		var seg := Node3D.new()
		seg.name = "CapeSeg%d" % i
		seg.position = Vector3(0.0, 0.0 if i == 0 else -seg_h, 0.05 if i == 0 else 0.0)
		if i == 0:
			seg.position = Vector3(0.0, attach_y, TUNIC_TOP_R * 0.9)
		parent.add_child(seg)
		var mesh_inst := MeshInstance3D.new()
		var plane := BoxMesh.new()
		plane.size = Vector3(width, seg_h, 0.02)
		mesh_inst.mesh = plane
		mesh_inst.position = Vector3(0.0, -seg_h * 0.5, 0.0)
		mesh_inst.material_override = cape_mat
		seg.add_child(mesh_inst)
		_cape_segs.append(seg)
		parent = seg
		width *= 0.92

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
	mesh.top_radius = TUNIC_TOP_R * 1.3
	mesh.bottom_radius = TUNIC_BOTTOM_R * 1.2
	mesh.height = SHOULDER_Y - HIP_Y
	shimmer.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.55, 0.35, 1.0, 0.5)
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	shimmer.material_override = mat
	parent.add_child(shimmer)
	shimmer.global_position = global_position + Vector3.UP * (HOVER + HIP_Y + (SHOULDER_Y - HIP_Y) * 0.5)
	shimmer.rotation.y = _visual.global_rotation.y
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(mat, "albedo_color", Color(0.3, 0.15, 0.5, 0.0), 0.55)
	tween.parallel().tween_property(shimmer, "scale", Vector3(1.3, 0.4, 1.3), 0.55)
	tween.tween_callback(shimmer.queue_free)

## Debu jejak kaki — burst kecil sekali-pakai setiap kaki mendarat saat
## berjalan/berlari (permintaan "animasi lari lebih detail").
func _spawn_footstep_dust(side: float) -> void:
	var parent := get_parent()
	if parent == null:
		return
	var foot_local := Vector3(side * 0.115, 0.0, 0.0)
	var world_pos := _visual.to_global(foot_local)
	world_pos.y = global_position.y + 0.02

	var p := GPUParticles3D.new()
	p.name = "FootDust"
	p.amount = maxi(3, int(round(7 * _fx)))
	p.lifetime = 0.5
	p.one_shot = true
	p.explosiveness = 0.95
	p.randomness = 0.5
	p.local_coords = false
	p.fixed_fps = 60
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.05
	pm.direction = Vector3.UP
	pm.spread = 60.0
	pm.initial_velocity_min = 0.3
	pm.initial_velocity_max = 0.9
	pm.gravity = Vector3(0, 0.4, 0)
	pm.damping_min = 1.0
	pm.damping_max = 2.0
	pm.scale_min = 0.5
	pm.scale_max = 1.0
	pm.scale_curve = _curve([Vector2(0, 0.3), Vector2(0.4, 1.0), Vector2(1, 1.6)], 1.6)
	pm.color_ramp = _ramp([0.0, 0.3, 1.0], [Color(0.55, 0.48, 0.42, 0.0), Color(0.6, 0.54, 0.48, 0.35), Color(0.65, 0.6, 0.55, 0.0)])
	p.process_material = pm
	p.draw_pass_1 = _quad(Vector2(0.14, 0.14), _fx_mat(_soft_tex(0.1), false, Color.WHITE))
	parent.add_child(p)
	p.global_position = world_pos
	p.emitting = true
	get_tree().create_timer(p.lifetime + 0.3).timeout.connect(p.queue_free)

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
