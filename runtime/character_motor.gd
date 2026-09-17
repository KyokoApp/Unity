class_name CharacterMotor
extends Node3D

## ============================================================
## CHARACTER MOTOR — menggerakkan karakter di dunia dan
## menghasilkan pose melalui rig prosedural.
## (Port dari CharacterMotor.cs.)
##
## Angka kecepatan TIDAK dikarang. Dari DESAIN.md §1, diukur dari
## game aslinya (index.html:1317): jalan 6,5 m/s, lari 13,5 m/s.
##
## Tinggi tanah dari WorldData.terrain_h(), satu-satunya sumber
## kebenaran terrain (karakter menempel ke tanah dengan aturan
## coyote/jump-buffer yang sama seperti versi Unity).
##
## Input: keyboard (proyek) + virtual_joystick HUD + tombol HUD.
## Kombo 3x, dash pakai stamina, sprint menguras stamina — semua
## mirroring CharacterMotor.cs Tahap 5.
## ============================================================

signal landed
signal attack_started(combo: int)

@export_group("Kecepatan (m/s) — dari game asli")
@export var walk_speed: float = 6.5
@export var run_speed: float = 13.5

@export_group("Kehalusan gerak")
@export var acceleration: float = 26.0
@export var deceleration: float = 34.0

@export_group("Lompat & gravitasi")
@export var gravity: float = 22.0
@export var jump_speed: float = 7.0
@export var ground_offset: float = 0.0
@export var coyote_time: float = 0.12
@export var jump_buffer: float = 0.15

@export_group("Dash & stamina")
@export var dash_speed: float = 20.0
@export var dash_time: float = 0.18
@export var dash_stamina_cost: float = 0.25
@export var sprint_drain: float = 0.15

@export_group("Irama langkah (rad/s)")
@export var cadence_base: float = 5.4
@export var cadence_per_speed: float = 0.86

@export_group("Putaran badan")
@export var turn_rate: float = 14.0

@export_group("Rujukan")
@export var camera_target: CameraRig
@export var stick: VirtualJoystick
@export var rig: CharacterRig
@export var vfx: AnimeVfx

## ---- keadaan yang dibaca komponen lain ----
var velocity: Vector3 = Vector3.ZERO
var speed: float:
	get: return Vector2(velocity.x, velocity.z).length()
var grounded := true
var phase: float = 0.0
var move01: float = 0.0
var run01: float = 0.0
var stamina01: float:
	get: return combat.stamina
var is_dashing: bool:
	get: return _dash_t > 0.0
var is_attacking: bool:
	get: return combat.is_attacking()
var combat := CombatState.new()

var _vy := 0.0
var _yaw := 0.0
var _prev_yaw := 0.0
var _clock: float = 0.0
var _vel_sm := Vector3.ZERO
var _coyote := 0.0
var _jump_buf := 0.0
var _fall_speed := 0.0
var _dash_t := 0.0
var _dash_dir := Vector3.FORWARD
var _move_sm := 0.0
var _run_sm := 0.0

func _ready() -> void:
	if rig == null:
		rig = get_parent() as CharacterRig
	add_to_group("player")
	snap_to_ground()

func snap_to_ground() -> void:
	# RIG (induk) yang dipindah ke tanah, bukan motor anaknya — rig adalah
	# target kamera/streamer dan membawa visual karakter. (Di versi Unity
	# motor & visual menempati transform yang SAMA; pemisahan node di Godot
	# ini sempat membuat visual terkubur di y=0.)
	var p := rig.global_position
	p.y = ground_height(p.x, p.z) + ground_offset
	rig.global_position = p
	position = Vector3.ZERO
	_vy = 0.0
	grounded = true
	_yaw = 0.0
	_prev_yaw = 0.0

func ground_height(x: float, z: float) -> float:
	return WorldData.terrain_h(x, z)

func _process(dt: float) -> void:
	if dt <= 0.0:
		return
	_clock += dt

	# ---- 1. masukan -------------------------------------------------
	var inp := _read_input()

	# ---- 2. arah relatif kamera --------------------------------------
	var cam_yaw := camera_target.yaw_deg() if camera_target != null \
		else rad_to_deg(rig.rotation.y)
	var wish := camera_relative(inp.x, inp.z, cam_yaw)
	var mag: float = clampf(wish.length(), 0.0, 1.0)
	if wish.length() > 1.0:
		wish = wish.normalized()

	# Stik analog didorong penuh = sprint otomatis (ala Genshin).
	var want_run: bool = inp.run or (inp.analog and mag > 0.92)
	var can_sprint: bool = combat.stamina > 0.02
	var sprinting: bool = want_run and can_sprint and mag > 0.1 \
		and not combat.is_attacking()

	combat.update(dt, _clock, sprint_drain if sprinting and grounded else 0.0)

	# ---- 3. dash ------------------------------------------------------
	if inp.dash and not is_dashing \
	and combat.spend_stamina(dash_stamina_cost):
		_dash_t = dash_time
		if mag > 0.1:
			_dash_dir = wish.normalized()
		else:
			_dash_dir = Vector3(sin(deg_to_rad(_yaw)), 0.0, cos(deg_to_rad(_yaw)))
		_yaw = rad_to_deg(atan2(_dash_dir.x, _dash_dir.z))
		if rig != null:
			rig.rotation.y = deg_to_rad(_yaw)
			rig.anim_dash()
		if vfx != null:
			vfx.spawn_dash(global_position + Vector3.UP * 0.6)
		if camera_target != null:
			camera_target.add_shake(0.25)
	if _dash_t > 0.0:
		_dash_t -= dt

	# ---- 4. serangan ---------------------------------------------------
	if inp.attack and not is_dashing and combat.try_attack(_clock):
		attack_started.emit(combat.combo)
		var face_yaw := rad_to_deg(atan2(wish.x, wish.z)) if mag > 0.05 else cam_yaw
		_yaw = face_yaw
		if rig != null:
			rig.rotation.y = deg_to_rad(_yaw)
			rig.anim_attack(combat.combo)
		var fwd := Vector3(sin(deg_to_rad(_yaw)), 0.0, cos(deg_to_rad(_yaw)))
		if vfx != null:
			vfx.spawn_attack(global_position + Vector3.UP * 1.1 + fwd * 0.9,
						 combat.combo)
		if camera_target != null:
			camera_target.add_shake(0.12)

	# ---- 5. kecepatan target + penghalusan -----------------------------
	var speed_mul := 0.25 if combat.is_attacking() else 1.0
	var target_speed := run_speed if (want_run and can_sprint) else walk_speed
	var want := wish * (target_speed * minf(1.0, mag)) * speed_mul
	if is_dashing:
		want = _dash_dir * dash_speed

	var rate := acceleration if want.length() > _vel_sm.length() else deceleration
	_vel_sm = _vel_sm.move_toward(want, rate * dt)
	velocity = Vector3(_vel_sm.x, 0.0, _vel_sm.z)

	# ---- 6. integrasi horizontal + batas dunia ---------------------------
	# Posisi dipegang RIG (target kamera + pembawa visual).
	var p := rig.global_position
	p.x += _vel_sm.x * dt
	p.z += _vel_sm.z * dt
	var limit: float = WorldData.WORLD_LIMIT
	p.x = clampf(p.x, -limit, limit)
	p.z = clampf(p.z, -limit, limit)

	# ---- 7. vertikal: coyote, buffer, tempel tanah -----------------------
	if grounded:
		_coyote = coyote_time
	else:
		_coyote -= dt
	if inp.jump:
		_jump_buf = jump_buffer
	else:
		_jump_buf -= dt
	if _jump_buf > 0.0 and _coyote > 0.0:
		_vy = jump_speed
		grounded = false
		_coyote = 0.0
		_jump_buf = 0.0
		if rig != null:
			rig.anim_jump()

	_vy -= gravity * dt
	p.y += _vy * dt
	_fall_speed = _vy

	var ground := ground_height(p.x, p.z) + ground_offset
	if p.y <= ground:
		if not grounded:
			_on_touchdown(_fall_speed)
		p.y = ground
		_vy = 0.0
		grounded = true
	else:
		grounded = false

	# RIG yang berpindah (motor lokal tetap di titik nol => global motor
	# selalu sama dengan global rig).
	rig.global_position = p
	position = Vector3.ZERO

	# ---- 8. hadap arah jalan ----------------------------------------------
	var tr := turn_rate * 0.3 if combat.is_attacking() else turn_rate
	if mag > 0.05:
		var want_yaw := rad_to_deg(atan2(wish.x, wish.z))
		_yaw = damp_angle(_yaw, want_yaw, tr, dt)
		rig.rotation.y = deg_to_rad(_yaw)
	elif combat.is_attacking():
		_yaw = damp_angle(_yaw, cam_yaw, tr, dt)
		rig.rotation.y = deg_to_rad(_yaw)

	# lean badan saat berputar tajam (dibaca character_rig)
	if rig != null and dt > 0.0:
		var yaw_rate := (_yaw_now_delta() / dt)
		rig.set_lean(clampf(yaw_rate / 220.0, -1.0, 1.0))

	# ---- 9. irama langkah + blend gerak --------------------------------------
	var sp := speed
	if grounded and sp > 0.3:
		phase += dt * (cadence_base + cadence_per_speed * sp)

	var move_t := minf(1.0, sp / maxf(0.001, walk_speed))
	var run_t := clampf((sp - walk_speed) / maxf(0.001, run_speed - walk_speed),
						0.0, 1.0)
	_move_sm = Locomotion.damp(_move_sm, move_t, 8.0, dt)
	_run_sm = Locomotion.damp(_run_sm, run_t, 8.0, dt)
	move01 = _move_sm
	run01 = _run_sm

	# ---- 10. pose/animasi: versi Unity melakukannya di LateUpdate; di
	# sini di akhir _process sehingga rig menerima posisi final. Dua
	# jalur: AnimDriver (GLB nyata) ATAU pose prosedural (fallback).
	if rig != null:
		# attack ditahan di 1 (pulih bertahap oleh smoothing rig),
		# persis pola HumanLocomotion.Unity di versi Unity.
		var attack_val := 1.0 if combat.is_attacking() else -1.0
		var st := {
			"phase": phase, "time": _clock,
			"move": move01, "run": run01,
			"dash": 1.0 if is_dashing else 0.0,
			"airborne": not grounded,
			"falling": not grounded and _vy < 0.0,
			"attack": attack_val,
			"combo": combat.combo,
		}
		if rig.anim_active:
			st["speed"] = sp
			st["grounded"] = grounded
			st["dashing"] = is_dashing
			rig.drive_anim(st, dt)
		elif rig.is_bound:
			var resolved := RigMapping.resolve(Locomotion.sample_pose(st))
			rig.apply_pose(resolved, phase, dt)

func _yaw_now_delta() -> float:
	var d := wrapf(_yaw - _prev_yaw, -180.0, 180.0)
	_prev_yaw = _yaw
	return d

func _on_touchdown(fall_sp: float) -> void:
	landed.emit()
	if rig != null:
		rig.anim_land(fall_sp)
	if fall_sp < -7.0 and rig != null:
		rig.pulse_crouch(clampf((-fall_sp - 7.0) / 8.0, 0.25, 1.0))
	if fall_sp < -9.0:
		if vfx != null:
			vfx.spawn_land(global_position + Vector3.UP * 0.15)
		if camera_target != null:
			camera_target.add_shake(0.3)

# ------------------------------------------------------------------
## Sumbu joystick/keyboard -> arah dunia, diputar menurut yaw kamera.
## Izinkan kamera null supaya komponen tetap bisa dites sendirian.
static func camera_relative(ix: float, iz: float, cam_yaw_deg: float) -> Vector3:
	if ix == 0.0 and iz == 0.0:
		return Vector3.ZERO
	var rad := deg_to_rad(cam_yaw_deg)
	var cosv := cos(rad)
	var sinv := sin(rad)
	# iz = "maju"; di Godot maju = +Z relatif kamera (bergerak ke
	# arah pandangan kamera). Menjaga paritas dengan versi Unity.
	return Vector3(ix * cosv + iz * sinv, 0.0,
				   iz * cosv - ix * sinv).normalized() \
		   * clampf(sqrt(ix * ix + iz * iz), 0.0, 1.0)

func _read_input() -> Dictionary:
	var ix := Input.get_axis("ui_left", "ui_right")
	var iz := Input.get_axis("ui_up", "ui_down")
	var analog := false

	if stick != null and stick.is_visible_in_tree():
		var a: Vector2 = stick.axis()
		if a.length() > 0.01:
			ix = a.x
			iz = a.y
			analog = true

	return {
		"x": ix, "z": iz, "analog": analog,
		"run": Input.is_action_pressed("run"),
		"jump": Input.is_action_just_pressed("jump") or _hud_flag("jump"),
		# Serang di desktop = klik kiri (diforward world._unhandled_input
		# -> hud_press, HUD mengantanimya sendiri) ATAU tombol F
		# (aksi "attack" yang dibuat world._setup_input_map).
		"attack": Input.is_action_just_pressed("attack") or _hud_flag("attack"),
		"dash": Input.is_action_just_pressed("dash") or _hud_flag("dash"),
	}

## Tombol HUD (mobile) menulis flag satu frame di sini.
var _hud_flags := {"jump": false, "attack": false, "dash": false}

func hud_press(name_btn: String) -> void:
	if _hud_flags.has(name_btn):
		_hud_flags[name_btn] = true

func _hud_flag(name_btn: String) -> bool:
	var v: bool = _hud_flags.get(name_btn, false)
	_hud_flags[name_btn] = false
	return v

static func damp_angle(current: float, target: float, rate: float, dt: float) -> float:
	var delta := wrapf(target - current, -180.0, 180.0)
	return current + delta * (1.0 - exp(-rate * dt))
