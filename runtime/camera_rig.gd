class_name CameraRig
extends Camera3D

## ============================================================
## CAMERA RIG — kamera orang ketiga mengorbit.
## (Port dari CameraRig.cs.)
##
## Jarak & sensitivitas TIDAK punya default sendiri: diambil dari
## SettingsStore (batas dipatok di GameSettings: camera_distance
## 3..8 default 5, sensitivity 0,4..2 default 1).
##
## Yang dipertahankan dari versi Unity Tahap 5:
## [1] MULTI-SENTUH: semua jari dipindai — kamera bisa diputar
##     sambil berjalan (jari lain tetap di stik).
## [2] Kamera dijepit di atas terrain (+ terrain_clearance) supaya
##     tidak masuk bukit.
## [3] FOV menendang saat sprint + screen-shake halus untuk
##     tebasan/dash/mendarat.
## [4] Penghalusan Lebih: posisi/FOV memakai Locomotion.damp yang
##     sama dengan karakter, bukan sistem kedua.
## ============================================================

@export_group("Target")
@export var target: Node3D
## Tinggi titik fokus di atas kaki karakter.
@export var focus_height: float = 1.35
## Dibaca untuk FOV sprint. Kosong = cari sendiri.
@export var motor: CharacterMotor

@export_group("Batas pitch (derajat)")
@export var min_pitch: float = -35.0
@export var max_pitch: float = 70.0
@export var start_pitch: float = 12.0

@export_group("Penghalusan")
@export var position_damp: float = 12.0
@export var rotation_damp: float = 18.0

@export_group("Terrain")
## Jarak minimum kamera di atas tanah (m). Mencegah kamera masuk bukit.
@export var terrain_clearance: float = 0.4

@export_group("Rasa (game feel)")
@export var base_fov: float = 60.0
## FOV saat sprint penuh.
@export var sprint_fov: float = 67.0

@export_group("Sentuh / mouse")
## Kalau true, menyeret di mana pun memutar kamera (untuk HP).
## Kalau false, hanya tombol mouse kanan.
@export var drag_anywhere: bool = true

var yaw: float = 0.0         ## derajat, dibaca motor (arah relatif kamera)
var pitch: float = 12.0

var _drag_id: int = -2147483648
var _mouse_dragging := false
var _shake := 0.0
var _settings: Dictionary

func _ready() -> void:
	add_to_group("camera_rig")
	_settings = SettingsStore.load()
	pitch = start_pitch
	current = true
	if target == null:
		target = get_tree().get_first_node_in_group("player") as Node3D
	if motor == null:
		motor = get_tree().get_first_node_in_group("player") as CharacterMotor
	fov = base_fov

func yaw_deg() -> float:
	return yaw

func set_distance(meters: float) -> void:
	_settings = SettingsStore.with_camera_distance(_settings, meters)
	SettingsStore.save(_settings)

func set_sensitivity(value: float) -> void:
	_settings = SettingsStore.with_sensitivity(_settings, value)
	SettingsStore.save(_settings)

## Dipanggil panel pengaturan setelah nilai berubah.
func refresh_settings() -> void:
	_settings = SettingsStore.load()

## Guncangan kamera 0..1 (tebasan, dash, mendarat).
func add_shake(amount: float) -> void:
	_shake = clampf(_shake + amount, 0.0, 1.0)

func _process(dt: float) -> void:
	if target == null:
		return

	var focus := target.global_position + Vector3.UP * focus_height
	var dist: float = float(_settings.get("camera_distance", 5.0))

	var pitch_rad := deg_to_rad(pitch)
	var yaw_rad := deg_to_rad(yaw)
	var offset := Vector3(
		sin(yaw_rad) * cos(pitch_rad),
		sin(pitch_rad),
		cos(yaw_rad) * cos(pitch_rad)) * -dist

	var want_pos := focus + offset

	# Jepit di atas terrain supaya tidak masuk bukit.
	var ground_y := WorldData.terrain_h(want_pos.x, want_pos.z) + terrain_clearance
	if want_pos.y < ground_y:
		want_pos.y = ground_y

	var want_rot := Basis().looking_at(focus - want_pos, Vector3.UP)

	# Damp dari Locomotion, bukan smooth-damp engine: laju penghalusan
	# harus sama dengan yang dipakai karakter.
	var p := global_position
	p.x = Locomotion.damp(p.x, want_pos.x, position_damp, dt)
	p.y = Locomotion.damp(p.y, want_pos.y, position_damp, dt)
	p.z = Locomotion.damp(p.z, want_pos.z, position_damp, dt)
	global_position = p
	if dt > 0.0:
		global_basis = global_basis.slerp(want_rot, 1.0 - exp(-rotation_damp * dt))

	# Shake: getaran sinus dua frekuensi, meluruh cepat.
	if _shake > 0.001 and dt > 0.0:
		_shake *= exp(-7.0 * dt)
		var t := Time.get_ticks_msec() / 1000.0
		global_position += Vector3(
			sin(t * 91.0) * _shake * 0.06,
			sin(t * 113.0 + 1.7) * _shake * 0.06, 0.0)
	else:
		_shake = 0.0

	# FOV menendang saat sprint/dash.
	var run: float = motor.run01 if motor != null else 0.0
	var dash_kick: float = 4.0 if (motor != null and motor.is_dashing) else 0.0
	var want_fov: float = base_fov + (sprint_fov - base_fov) * run + dash_kick
	fov = Locomotion.damp(fov, want_fov, 6.0, dt)

## Input kamera via event yang TIDAK dipakai HUD (tombol + stik sudah
## mengambil bagiannya). Setara "!IsPointerOverUi()" di versi Unity,
## plus cek zona stik kiri-bawah supaya jempol stik tidak ikut
## memutar kamera.
func _unhandled_input(event: InputEvent) -> void:
	var sens: float = float(_settings.get("sensitivity", 1.0))

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT \
		or (drag_anywhere and mb.button_index == MOUSE_BUTTON_LEFT):
			_mouse_dragging = mb.pressed
	elif event is InputEventMouseMotion:
		if _mouse_dragging or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			var mm := event as InputEventMouseMotion
			_apply_look(mm.relative.x, mm.relative.y, sens)
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			if not _in_stick_zone(st.position):
				_drag_id = st.index
				TouchDebug.note_cam(st.position, st.index)
		elif st.index == _drag_id:
			_drag_id = -2147483648
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		if sd.index == _drag_id and not _in_stick_zone(sd.position):
			_apply_look(sd.relative.x, sd.relative.y, sens)

## Zona stik kiri-bawah (koordinat layar: Y ke bawah). Sama dengan
## InStickZone Unity, Y dibalik: (y < 0.7 h dari bawah) -> (y > 0.3 h
## dari atas).
func _in_stick_zone(p: Vector2) -> bool:
	var vs := get_viewport().get_visible_rect().size
	return p.x < vs.x * 0.45 and p.y > vs.y * 0.3

func _apply_look(dx: float, dy: float, sens: float) -> void:
	yaw += dx * 0.12 * sens
	# dy dibalik: layar Godot Y-ke-bawah, Unity Y-ke-atas.
	pitch = clampf(pitch + dy * 0.10 * sens, min_pitch, max_pitch)
	yaw = fposmod(yaw + 360.0, 720.0) - 360.0
