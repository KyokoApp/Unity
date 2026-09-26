extends CharacterBody3D
## Pemain = penyihir ungu berbadan manusia (ronde-46 bag. A4). Bagian A/A2/A3
## sebelumnya 100% prosedural (CapsuleMesh) — dinilai pengguna masih "kayak
## stickman" dari sudut kamera manapun, walau gait-nya sudah biomekanik.
## Pengguna lalu mengirim aset nyata (bukan cuma tautan/screenshot): paket
## animasi mocap Quaternius "Universal Animation Library" (CC0), diunggah
## LANGSUNG ke commit branch lewat uploader web GitHub (bukan lampiran
## chat) — jalur ini terbukti berhasil membawa file biner utuh ke sandbox,
## setelah semua jalur unduh URL/lampiran-chat gagal di ronde-ronde
## sebelumnya (lihat CREDITS.md).
##
## Model: project/packs/character_player/mannequin/UAL1_Standard.glb
##   - 1 mesh berskin "Mannequin" (2 material, tanpa tekstur) + 43 klip
##     animasi full-body siap pakai (mocap asli, bukan buatan tangan).
##   - Tinggi bind-pose asli ~1.83 m; skala 1:1 (meter), tak perlu koreksi.
##   - CC0 1.0 Universal oleh Quaternius — lihat CREDITS.md utk atribusi.
##
## Bagian A4 ini FOKUS pada lokomosi (diam/jalan/jog/sprint) + dash, sesuai
## permintaan eksplisit pengguna ("fokus ke animasi lari & jalan dulu").
## Klip serang (`Spell_Simple_Shoot`/`Spell_Simple_Idle_Loop`) SENGAJA belum
## dipasang di bagian ini — kandidat kuat utk lapisan animasi serang nanti.
##
## Node internal model (AnimationPlayer/MeshInstance3D) DICARI SECARA
## REKURSIF via find_child()/find_children() — path node persis hasil
## import glTF Godot tak bisa dipastikan tanpa editor lokal, jadi TIDAK ADA
## path node yang di-hardcode di sini.
##
## Warna: mesh asli (M_Main oranye, M_Joints sudah ungu) di-override total
## dgn shader toon.gdshader ungu (2 corak: badan utama + aksen sendi) supaya
## tetap sesuai mandat "karakter warna ungu". Kedua material asli TANPA
## tekstur -> override surface aman, tak ada UV/tekstur yg hilang.
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
const MANNEQUIN_SCENE := preload("res://packs/character_player/mannequin/UAL1_Standard.glb")
const FIRE_COOLDOWN := 0.3
const BOLT_SPEED := 21.0
const BOLT_LIFT := 1.8

# Dua corak ungu: badan utama (permukaan besar) + aksen sendi (kontras
# lebih gelap, mempertahankan "color-blocking" asli model sumber).
const BODY_COLOR := Color(0.50, 0.26, 0.92)
const JOINT_COLOR := Color(0.22, 0.10, 0.44)

# --- gerak (ringan, lincah — penyihir jalan kaki, bukan kendaraan) ---
const MAX_SPEED := 9.0
const ACCEL_RATE := 7.5
const DECEL_RATE := 4.5
const HOVER := 0.0           # model sudah berakar tepat di telapak kaki (Y=0 bind-pose)

# --- proporsi model nyata (Quaternius mannequin, ~1.83 m bind-pose) ---
const MODEL_HEIGHT := 1.83
const CAST_HEIGHT := 1.32     # perkiraan tinggi tangan/dada utk titik lontar peluru
## Dikonfirmasi pengguna lgsg di device (ronde-46 bag. A4 lanjutan): model
## menghadap 180° TERBALIK dari arah gerak (mukanya ke belakang saat jalan
## maju) — makanya PI di sini, bukan 0.0 lagi. Rig sumber (Quaternius/UE4
## mannequin) menghadap -Z di bind-pose sama seperti konvensi Godot, tapi
## root bone punya koreksi rotasi -90° sumbu X (Blender Z-up->Y-up) yang
## rupanya membalik sumbu depan juga -> kompensasi di sini, di level visual,
## bukan di rig (lebih aman & mudah diubah lagi kalau ternyata masih meleset).
const MODEL_YAW_OFFSET := PI

# --- nama klip animasi SETELAH import Godot (BUKAN nama asli di glTF!) ---
# Dikonfirmasi via probe CI (dev_probe/fire_attack_check.gd _diag_mannequin):
# importer glTF Godot MEMOTONG akhiran "_Loop" dari nama klip lalu memakainya
# utk set loop_mode animasi itu sendiri secara native (mis. "Idle_Loop" (glTF)
# -> "Idle" (AnimationPlayer, sudah loop_mode=LINEAR otomatis). Nama asli
# ("Idle_Loop" dkk, lihat CREDITS.md) TIDAK ADA di AnimationPlayer — pakai
# nama hasil import di bawah ini, bukan nama sumber.
const ANIM_IDLE := "Idle"
const ANIM_WALK := "Walk"
const ANIM_JOG := "Jog_Fwd"
const ANIM_SPRINT := "Sprint"

# Ambang speed01 (0..1) utk pindah state, dgn histeresis (naik/turun beda
# ambang) supaya tak "flicker" bolak-balik dekat batas.
const WALK_ON := 0.06
const WALK_OFF := 0.03
const JOG_ON := 0.40
const JOG_OFF := 0.30
const SPRINT_ON := 0.82
const SPRINT_OFF := 0.70
const ANIM_BLEND := 0.18

# --- dash: "sprint burst" ala pengguna (bag. A4 lanjutan #2) — BUKAN lagi
# animasi roll/berguling. Badan tetap main klip lari (ANIM_SPRINT) yang
# sama seperti lari biasa, tapi kaki dipercepat drastis (speed_scale) demi
# kesan "meledak ngebut", ditambah jejak bayangan (afterimage) transparan
# yg mengikuti pose animasi berjalan saat itu.
const DASH_ANIM_SPEED_SCALE := 1.8
const AFTERIMAGE_INTERVAL := 0.05    # jarak waktu antar-ghost yg di-spawn saat dash
const AFTERIMAGE_FADE := 0.32        # durasi tiap ghost memudar
const AFTERIMAGE_COLOR := Color(0.62, 0.34, 1.0, 0.4)


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
var _model: Node3D
var _anim: AnimationPlayer
var _skeleton: Skeleton3D
var _anim_state := ""
var _afterimage_timer := 0.0
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
var _dust_dist_accum := 0.0
var _dust_side := 1.0

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
	_build_character()
	_build_aura()
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
	_animate_character(delta)

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
		_advance_footsteps(DASH_SPEED * dash_factor, delta)
		_afterimage_timer -= delta
		if _afterimage_timer <= 0.0:
			_afterimage_timer = AFTERIMAGE_INTERVAL
			_spawn_afterimage()
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
	_advance_footsteps(hv.length(), delta)

## Debu jejak kaki disederhanakan jadi berbasis JARAK TEMPUH (bukan lagi
## fase gait per-tulang manual — animasi kaki kini datang dari mocap asli,
## bukan dihitung tangan), tetap "banyak efek" saat bergerak cepat.
func _advance_footsteps(speed: float, delta: float) -> void:
	if speed <= 0.15:
		_dust_dist_accum = 0.0
		return
	_dust_dist_accum += speed * delta
	var stride := 0.75 if speed < MAX_SPEED * 0.45 else 0.55
	if _dust_dist_accum >= stride:
		_dust_dist_accum = fmod(_dust_dist_accum, stride)
		_dust_side = -_dust_side
		_spawn_footstep_dust(_dust_side)

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

## Putar model menghadap arah gerak, lalu pilih & mainkan klip mocap yang
## cocok dgn kecepatan/dash saat ini via AnimationPlayer (bukan lagi rotasi
## tulang manual per-frame).
func _animate_character(delta: float) -> void:
	if _facing.length_squared() > 0.01:
		var facing_yaw := atan2(-_facing.x, -_facing.z) + MODEL_YAW_OFFSET
		_visual.rotation.y = lerp_angle(_visual.rotation.y, facing_yaw, 1.0 - exp(-14.0 * delta))

	if _anim == null:
		return

	# Dash = "sprint burst": klip lari yang SAMA (ANIM_SPRINT), bukan
	# animasi khusus — cuma kakinya dipercepat drastis via speed_scale, plus
	# jejak bayangan (lihat _spawn_afterimage, dipanggil dari _move()).
	if _dash_left > 0.0:
		if _anim_state != ANIM_SPRINT or not _anim.is_playing():
			_anim.play(ANIM_SPRINT, 0.06)
			_anim_state = ANIM_SPRINT
		_anim.speed_scale = DASH_ANIM_SPEED_SCALE
		return
	if not is_equal_approx(_anim.speed_scale, 1.0):
		_anim.speed_scale = 1.0

	# Histeresis: state saat ini menentukan ambang MASUK vs KELUAR, supaya
	# tak lompat-lompat pas speed01 pas di garis batas.
	var target := _anim_state
	match _anim_state:
		ANIM_SPRINT:
			if _speed01 < SPRINT_OFF:
				target = ANIM_JOG
		ANIM_JOG:
			if _speed01 >= SPRINT_ON:
				target = ANIM_SPRINT
			elif _speed01 < JOG_OFF:
				target = ANIM_WALK
		ANIM_WALK:
			if _speed01 >= JOG_ON:
				target = ANIM_JOG
			elif _speed01 < WALK_OFF:
				target = ANIM_IDLE
		_:
			target = ANIM_IDLE
			if _speed01 >= WALK_ON:
				target = ANIM_WALK
			if _speed01 >= JOG_ON:
				target = ANIM_JOG
			if _speed01 >= SPRINT_ON:
				target = ANIM_SPRINT

	if target != _anim_state or not _anim.is_playing():
		_anim.play(target, ANIM_BLEND)
		_anim_state = target

# =============== Serangan ===============

func _shoot_direction() -> Vector3:
	if _facing.length_squared() > 0.01:
		return _facing.normalized()
	return (Basis(Vector3.UP, yaw) * Vector3(0, 0, -1)).normalized()

func _hand_position(direction: Vector3) -> Vector3:
	return _visual.global_position + Vector3.UP * CAST_HEIGHT + direction * 0.5

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

# =============== Rakitan visual: mannequin Quaternius, dicat ungu ===============

func _build_character() -> void:
	_visual = Node3D.new()
	_visual.name = "Visual"
	_visual.position = Vector3(0.0, HOVER, 0.0)
	add_child(_visual)

	_model = MANNEQUIN_SCENE.instantiate()
	_model.name = "Mannequin"
	_visual.add_child(_model)

	_anim = _model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _anim != null:
		_anim.playback_default_blend_time = ANIM_BLEND
		if _anim.has_animation(ANIM_IDLE):
			_anim.play(ANIM_IDLE)
			_anim_state = ANIM_IDLE
	_skeleton = _model.find_child("Skeleton3D", true, false) as Skeleton3D

	_paint_purple()

## Kedua material sumber (M_Main oranye, M_Joints ungu) TANPA tekstur ->
## override total aman, tak kehilangan detail UV apa pun.
func _paint_purple() -> void:
	var mats := [Materials.toon(BODY_COLOR, true, 0.012, 0.55), Materials.toon(JOINT_COLOR, false, 0.0, 0.35)]
	for mi in _model.find_children("*", "MeshInstance3D", true, false):
		var mesh_inst := mi as MeshInstance3D
		if mesh_inst == null or mesh_inst.mesh == null:
			continue
		var surfaces := mesh_inst.mesh.get_surface_count()
		for i in range(surfaces):
			mesh_inst.set_surface_override_material(i, mats[i % mats.size()])

## Aura sihir ungu-biru yang melayang terus-menerus di sekitar karakter —
## permintaan pengguna "banyak efek" berlaku juga saat idle, bukan cuma saat
## menyerang. Dipertahankan lintas-ronde walau badan kini model mannequin.
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

## Jejak bayangan (afterimage) saat dash — beberapa "hantu" transparan
## menduplikasi mesh mannequin, dibekukan di posisi/rotasi saat itu, lalu
## memudar cepat. Tiap ghost tetap merujuk Skeleton3D ASLI yang sama (jadi
## posenya ikut pose lari saat itu, bukan T-pose) — cukup utk kesan "trail
## kecepatan" tanpa perlu membekukan pose tulang secara manual.
func _spawn_afterimage() -> void:
	if not is_instance_valid(_model) or not is_instance_valid(_skeleton):
		return
	var parent := get_parent()
	if parent == null:
		return
	var ghost := Node3D.new()
	ghost.name = "DashAfterimage"
	parent.add_child(ghost)
	ghost.global_transform = _visual.global_transform

	var ghost_mat := StandardMaterial3D.new()
	ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ghost_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	ghost_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	ghost_mat.albedo_color = AFTERIMAGE_COLOR
	ghost_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	ghost_mat.disable_receive_shadows = true

	var made_any := false
	for mi in _model.find_children("*", "MeshInstance3D", true, false):
		var src := mi as MeshInstance3D
		if src == null or src.mesh == null:
			continue
		var copy := MeshInstance3D.new()
		copy.mesh = src.mesh
		copy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ghost.add_child(copy)
		copy.global_transform = src.global_transform
		copy.skeleton = copy.get_path_to(_skeleton)
		for i in range(src.mesh.get_surface_count()):
			copy.set_surface_override_material(i, ghost_mat)
		made_any = true
	if not made_any:
		ghost.queue_free()
		return

	var tween := create_tween()
	tween.tween_property(ghost_mat, "albedo_color:a", 0.0, AFTERIMAGE_FADE).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_callback(ghost.queue_free)

func _spawn_dash_shimmer() -> void:
	var parent := get_parent()
	if parent == null:
		return
	var shimmer := MeshInstance3D.new()
	shimmer.name = "DashShimmer"
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.30
	mesh.bottom_radius = 0.36
	mesh.height = MODEL_HEIGHT * 0.5
	shimmer.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.55, 0.35, 1.0, 0.5)
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	shimmer.material_override = mat
	parent.add_child(shimmer)
	shimmer.global_position = global_position + Vector3.UP * (HOVER + MODEL_HEIGHT * 0.5)
	shimmer.rotation.y = _visual.global_rotation.y
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(mat, "albedo_color", Color(0.3, 0.15, 0.5, 0.0), 0.55)
	tween.parallel().tween_property(shimmer, "scale", Vector3(1.3, 0.4, 1.3), 0.55)
	tween.tween_callback(shimmer.queue_free)

## Debu jejak kaki — burst kecil sekali-pakai, dipicu berkala berdasar jarak
## tempuh (lihat _advance_footsteps). Ditaruh dekat kaki dgn offset kiri/
## kanan bergantian, cukup dekat tanah tanpa perlu lacak tulang kaki persis.
func _spawn_footstep_dust(side: float) -> void:
	var parent := get_parent()
	if parent == null:
		return
	var right := (Basis(Vector3.UP, _visual.rotation.y) * Vector3.RIGHT)
	var world_pos := global_position + right * (side * 0.10)
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
