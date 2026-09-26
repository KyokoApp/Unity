extends CharacterBody3D
## Pemain = STICKMAN ungu prosedural (ronde-46 bag. A3). Setelah bag. A/A2
## (penyihir chibi-anime berjubah) dinilai pengguna masih "kayak stickman"
## dari sudut kamera, pengguna minta pivot EKSPLISIT: karakter dibuat betulan
## menyerupai gambar referensi stickman universal (kepala bulat + garis lurus
## untuk torso/lengan/kaki, tanpa wajah/rambut/pakaian), warna ungu, dan
## animasi jalan/lari/dash yang benar secara biomekanik.
##
## 100% PROSEDURAL (CapsuleMesh/SphereMesh tipis seragam + shader toon
## `toon.gdshader` yang sudah ada di project) — TIDAK ADA file model
## eksternal (sandbox ini tak bisa mengunduh file biner, sudah diverifikasi
## gagal berulang kali di ronde-ronde sebelumnya).
##
## RISET BIOMEKANIK (dipakai sbg dasar angka animasi, lihat CREDITS.md utk
## sumber lengkap):
## - Tekuk lutut maks saat mengayun: ~60° jalan normal, ~90° lari, ~105-110°
##   sprint/dash (rentang gerak makin besar seiring kecepatan).
## - Condong badan ke depan: ~2-3° jalan, ~5-7.5° lari, lebih besar lagi saat
##   akselerasi/dash (dilebih-lebihkan dikit di sini demi keterbacaan game).
## - Lengan BERLAWANAN FASA dengan kaki di sisi SEBERANG (kontralateral,
##   bukan searah) — lengan kanan maju saat kaki kiri maju, dst. Siku makin
##   tertekuk & ayunan makin lebar seiring kecepatan.
## - Rotasi pinggul/bahu (transverse) ada tapi KECIL pada lari efisien —
##   dipakai di sini sbg detail halus (beberapa derajat), bukan dominan.
## - Panjang & frekuensi langkah naik bersama kecepatan -> fase gait di sini
##   dimajukan sebanding JARAK TEMPUH (bukan waktu murni).
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
const STICK_COLOR := Color(0.46, 0.24, 0.88)   # ungu tunggal — seluruh tubuh 1 warna, sesuai referensi

# --- gerak (ringan, lincah — penyihir jalan kaki, bukan kendaraan) ---
const MAX_SPEED := 9.0
const ACCEL_RATE := 7.5
const DECEL_RATE := 4.5
const HOVER := 0.03          # cuma sedikit angkat dari y=0 (hindari z-fight kaki/tanah)

# --- proporsi stickman (kepala bulat + garis seragam, seperti referensi) ---
const HEAD_RADIUS := 0.20
const HIP_Y := 0.55            # titik cabang kaki
const SHOULDER_Y := 0.98       # titik cabang lengan (= ujung atas garis torso)
const LIMB_RADIUS := 0.065     # tebal SEMUA garis (torso/lengan/kaki) — seragam spt gambar
const LEG_THIGH_LEN := 0.27
const LEG_SHIN_LEN := 0.26
const ARM_UPPER_LEN := 0.19
const ARM_FORE_LEN := 0.16

# --- animasi gait, angka dikalibrasi dari riset biomekanik jalan/lari/sprint ---
const STRIDE_FREQ := 1.9       # radian fase per meter tempuh (independen dari framerate)
const LEG_SWING_WALK := deg_to_rad(24.0)
const LEG_SWING_RUN := deg_to_rad(42.0)
const LEG_SWING_DASH := deg_to_rad(50.0)
const KNEE_BEND_WALK := deg_to_rad(55.0)   # riset: ~60° jalan normal
const KNEE_BEND_RUN := deg_to_rad(90.0)    # riset: ~90° lari
const KNEE_BEND_DASH := deg_to_rad(106.0)  # riset: ~105-110° sprint terlatih
const ARM_SWING_WALK := deg_to_rad(20.0)
const ARM_SWING_RUN := deg_to_rad(38.0)
const ARM_SWING_DASH := deg_to_rad(48.0)
const ELBOW_BEND_BASE := deg_to_rad(8.0)
const ELBOW_BEND_RUN_EXTRA := deg_to_rad(34.0)
const ELBOW_BEND_DASH_EXTRA := deg_to_rad(54.0)
const TORSO_LEAN_WALK := deg_to_rad(2.5)   # riset: ~2-3°
const TORSO_LEAN_RUN := deg_to_rad(7.0)    # riset: ~5-7.5°
const TORSO_LEAN_DASH := deg_to_rad(17.0)  # dilebihkan dikit demi rasa "meledak maju" saat dash
const HIP_TWIST_MAX := deg_to_rad(4.0)     # rotasi pinggul halus (riset: harus kecil, bukan dominan)
const SHOULDER_TWIST_MAX := deg_to_rad(5.0)

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
var _hips: Node3D             # kelompok kaki — bisa berotasi Y independen (twist pinggul)
var _upper: Node3D            # torso+kepala+lengan — bisa condong (lean) & counter-twist
var _torso_mesh: MeshInstance3D
var _head: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _fore_l: Node3D
var _fore_r: Node3D
var _hip_l: Node3D
var _hip_r: Node3D
var _shin_l: Node3D
var _shin_r: Node3D
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
var _dash_anim := 0.0
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
	_build_stickman()
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
	_animate_stickman(delta)

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
		_dash_anim = lerpf(_dash_anim, 1.0, 1.0 - exp(-10.0 * delta))
		_advance_gait(DASH_SPEED * dash_factor, delta)
		return
	_dash_anim = lerpf(_dash_anim, 0.0, 1.0 - exp(-6.0 * delta))

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
## panjang & frekuensi langkah otomatis mengikuti kecepatan asli — sesuai
## riset ("stride length & stride rate naik bersama kecepatan").
func _advance_gait(speed: float, delta: float) -> void:
	if speed > 0.05:
		_gait_phase = fmod(_gait_phase + speed * delta * STRIDE_FREQ, TAU)

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

func _animate_stickman(delta: float) -> void:
	var moving := _speed01 > 0.035 and _facing.length_squared() > 0.01
	if _facing.length_squared() > 0.01:
		var facing_yaw := atan2(-_facing.x, -_facing.z)
		_visual.rotation.y = lerp_angle(_visual.rotation.y, facing_yaw, 1.0 - exp(-14.0 * delta))

	# ---------- blend kontinu jalan->lari (speed01) + overlay dash ----------
	var run_mix := clampf(_speed01, 0.0, 1.0)
	var leg_swing := lerpf(LEG_SWING_WALK, LEG_SWING_RUN, run_mix)
	var knee_bend := lerpf(KNEE_BEND_WALK, KNEE_BEND_RUN, run_mix)
	var arm_swing := lerpf(ARM_SWING_WALK, ARM_SWING_RUN, run_mix)
	var elbow_extra := lerpf(0.0, ELBOW_BEND_RUN_EXTRA, run_mix)
	var torso_lean := lerpf(TORSO_LEAN_WALK, TORSO_LEAN_RUN, run_mix)
	leg_swing = lerpf(leg_swing, LEG_SWING_DASH, _dash_anim)
	knee_bend = lerpf(knee_bend, KNEE_BEND_DASH, _dash_anim)
	arm_swing = lerpf(arm_swing, ARM_SWING_DASH, _dash_anim)
	elbow_extra = lerpf(elbow_extra, ELBOW_BEND_DASH_EXTRA, _dash_anim)
	torso_lean = lerpf(torso_lean, TORSO_LEAN_DASH, _dash_anim)

	var amt := clampf(_speed01 * 1.3 + _dash_anim, 0.0, 1.0)
	var leg_l_sin := sin(_gait_phase)
	var leg_r_sin := sin(_gait_phase + PI)
	var bob := 0.0

	if moving:
		# ---------- kaki: paha berayun, betis menekuk saat mengayun maju (riset: knee flexion swing) ----------
		_hip_l.rotation.x = leg_l_sin * leg_swing
		_hip_r.rotation.x = leg_r_sin * leg_swing
		_shin_l.rotation.x = maxf(0.0, leg_l_sin) * knee_bend
		_shin_r.rotation.x = maxf(0.0, leg_r_sin) * knee_bend
		# ---------- lengan: KONTRALATERAL — berlawanan fasa dgn kaki SEBERANG ----------
		_arm_l.rotation.x = leg_r_sin * arm_swing
		_arm_r.rotation.x = leg_l_sin * arm_swing
		_fore_l.rotation.x = ELBOW_BEND_BASE + maxf(0.0, -leg_r_sin) * elbow_extra
		_fore_r.rotation.x = ELBOW_BEND_BASE + maxf(0.0, -leg_l_sin) * elbow_extra
		# ---------- badan condong ke depan (riset: makin cepat makin condong) ----------
		_upper.rotation.x = lerp_angle(_upper.rotation.x, -torso_lean, 1.0 - exp(-8.0 * delta))
		# ---------- twist pinggul/bahu halus (riset: harus kecil, bukan dominan) ----------
		_hips.rotation.y = lerp_angle(_hips.rotation.y, leg_l_sin * HIP_TWIST_MAX * amt, 1.0 - exp(-10.0 * delta))
		_upper.rotation.y = lerp_angle(_upper.rotation.y, -leg_l_sin * SHOULDER_TWIST_MAX * amt, 1.0 - exp(-10.0 * delta))
		bob = absf(sin(_gait_phase)) * 0.05 * amt
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
		_hips.rotation.y = lerp_angle(_hips.rotation.y, 0.0, 1.0 - exp(-6.0 * delta))
		_upper.rotation.y = lerp_angle(_upper.rotation.y, 0.0, 1.0 - exp(-6.0 * delta))
		bob = sin(_t * 1.7) * 0.012
	_prev_leg_l_sin = leg_l_sin
	_prev_leg_r_sin = leg_r_sin

	var head_bob := sin(_t * (7.5 if moving else 2.2)) * (0.018 if moving else 0.010)
	_head.position.y = (SHOULDER_Y - HIP_Y) + HEAD_RADIUS * 0.95 + head_bob
	_visual.position = Vector3(0.0, HOVER + bob, 0.0)
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

# =============== Rakitan visual: stickman ungu (kepala bulat + garis) ===============

func _build_stickman() -> void:
	_visual = Node3D.new()
	_visual.name = "Stickman"
	_visual.position = Vector3(0.0, HOVER, 0.0)
	add_child(_visual)

	_hips = Node3D.new()
	_hips.name = "Hips"
	_hips.position = Vector3(0.0, HIP_Y, 0.0)
	_visual.add_child(_hips)

	_upper = Node3D.new()
	_upper.name = "Upper"
	_upper.position = Vector3(0.0, HIP_Y, 0.0)
	_visual.add_child(_upper)

	_build_legs()
	_build_torso()
	_build_arms()
	_build_head()
	_build_aura()

func _stick_mat() -> Material:
	return Materials.toon(STICK_COLOR, true, 0.014, 0.55)

# ---------- kaki: 2 segmen (paha+betis) garis tunggal, sesuai referensi ----------

func _build_legs() -> void:
	var mat := _stick_mat()
	_hip_l = _make_leg(mat, -1.0)
	_hip_r = _make_leg(mat, 1.0)

func _make_leg(mat: Material, side: float) -> Node3D:
	var hip := Node3D.new()
	hip.name = "HipPivot" + ("L" if side < 0 else "R")
	hip.position = Vector3(side * 0.09, 0.0, 0.0)
	_hips.add_child(hip)

	var thigh := MeshInstance3D.new()
	var thigh_mesh := CapsuleMesh.new()
	thigh_mesh.radius = LIMB_RADIUS
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
	shin_mesh.radius = LIMB_RADIUS
	shin_mesh.height = LEG_SHIN_LEN
	shin_mesh_inst.mesh = shin_mesh
	shin_mesh_inst.position = Vector3(0.0, -LEG_SHIN_LEN * 0.5, 0.0)
	shin_mesh_inst.material_override = mat
	shin.add_child(shin_mesh_inst)
	return hip

# ---------- torso: satu garis lurus tunggal dari pinggul ke bahu ----------

func _build_torso() -> void:
	var torso_h := SHOULDER_Y - HIP_Y
	_torso_mesh = MeshInstance3D.new()
	_torso_mesh.name = "Torso"
	var mesh := CapsuleMesh.new()
	mesh.radius = LIMB_RADIUS
	mesh.height = torso_h
	_torso_mesh.mesh = mesh
	_torso_mesh.position = Vector3(0.0, torso_h * 0.5, 0.0)
	_torso_mesh.material_override = _stick_mat()
	_upper.add_child(_torso_mesh)

# ---------- lengan: 2 segmen (atas+bawah), garis tunggal dari bahu ----------

func _build_arms() -> void:
	var mat := _stick_mat()
	var shoulder_local_y := SHOULDER_Y - HIP_Y
	_make_arm(mat, -1.0, shoulder_local_y)
	_make_arm(mat, 1.0, shoulder_local_y)

func _make_arm(mat: Material, side: float, shoulder_y: float) -> void:
	var pivot := Node3D.new()
	pivot.name = "ArmPivot" + ("L" if side < 0 else "R")
	pivot.position = Vector3(side * (LIMB_RADIUS * 1.4), shoulder_y - LIMB_RADIUS * 0.5, 0.0)
	_upper.add_child(pivot)
	if side < 0.0:
		_arm_l = pivot
	else:
		_arm_r = pivot

	var upper_arm := MeshInstance3D.new()
	var upper_mesh := CapsuleMesh.new()
	upper_mesh.radius = LIMB_RADIUS
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
	fore_mesh.radius = LIMB_RADIUS
	fore_mesh.height = ARM_FORE_LEN
	forearm.mesh = fore_mesh
	forearm.position = Vector3(0.0, -ARM_FORE_LEN * 0.5, 0.0)
	forearm.material_override = mat
	forearm_pivot.add_child(forearm)

# ---------- kepala: bulat polos, tanpa wajah (sesuai gambar referensi) ----------

func _build_head() -> void:
	_head = Node3D.new()
	_head.name = "Head"
	_head.position = Vector3(0.0, (SHOULDER_Y - HIP_Y) + HEAD_RADIUS * 0.95, 0.0)
	_upper.add_child(_head)

	var face := MeshInstance3D.new()
	var face_mesh := SphereMesh.new()
	face_mesh.radius = HEAD_RADIUS
	face_mesh.height = HEAD_RADIUS * 2.0
	face_mesh.radial_segments = 20
	face_mesh.rings = 12
	face.mesh = face_mesh
	face.material_override = _stick_mat()
	_head.add_child(face)

## Aura sihir ungu-biru yang melayang terus-menerus di sekitar karakter —
## permintaan pengguna "banyak efek" berlaku juga saat idle, bukan cuma saat
## menyerang. Dipertahankan lintas-ronde walau bentuk badan kini stickman.
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
	mesh.top_radius = LIMB_RADIUS * 4.5
	mesh.bottom_radius = LIMB_RADIUS * 5.5
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
## berjalan/berlari.
func _spawn_footstep_dust(side: float) -> void:
	var parent := get_parent()
	if parent == null:
		return
	var foot_local := Vector3(side * 0.09, 0.0, 0.0)
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
