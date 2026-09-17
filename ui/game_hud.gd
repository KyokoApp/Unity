class_name GameHud
extends CanvasLayer

## ============================================================
## GAME HUD — antarmuka ala Genshin, dibangun dari kode.
## (Port dari GenshinHud.cs.)
##
## Isi: potret party + HP (kiri atas), kompas arah (tengah atas),
## pelacak region (bawah kompas), minimap placeholder + fps
## (kanan atas), stamina (bawah tengah), klaster aksi ATK/E/Q/
## ATK/JMP/DSH (kanan bawah), stik virtual (kiri bawah), panel
## PENGATURAN (tengah, via tombol menu).
##
## Dibangun dari kode supaya scene tetap bersih — scene world.tscn
## hanya defins node runtime; HUD muncul identik di semua build.
## ============================================================

const SKILL_CD_MAX := 6.0
const BURST_CD_MAX := 15.0

## Kompas: 8 arah (yaw kiblat: U=180 E=90 S=0 B=-90 — cocokkan
## dengan CameraRelative: yaw 0 = menghadap +Z = "selatan" peta).
const DIR_NAME := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
const DIR_YAW: Array[float] = [180, 135, 90, 45, 0, -45, -90, -135]

var motor: CharacterMotor
var stick: VirtualJoystick
var vfx: AnimeVfx
var camera_rig: CameraRig

signal pressed_jump
signal pressed_attack
signal pressed_dash
signal pressed_skill
signal pressed_burst

## ---- node bayangan yang dibangun dari kode ----
var _dir_labels: Array[Label] = []
var _dir_rects: Array[Control] = []
var _region_name: Label
var _region_sub: Label
var _region_id := ""
var _fps_text: Label
var _stam_fill: Dictionary
var _stam_group: Control
var _burst_ring_nodes: Array = []
var _skill_cd_fill: Label
var _burst_cd_fill: Label
var _edit_panel: Control = null

var _skill_cd := 0.0
var _burst_cd := 0.0
var _energy := 60.0

var _fps_acc := 0.0
var _fps_n := 0
var _hud_label_count := 0

func _ready() -> void:
	layer = 10
	_build()

func _btn_text(t: String) -> String:
	# Godot tidak memakai ikon unicode bawaan di font default; teks
	# ASCII dipakai supaya tidak jadi kotak tofu — keputusan sama
	# seperti GenshinHud.cs.
	return t

## ============================================================ bangun
func _build() -> void:
	var root := Control.new()
	root.name = "HudRoot"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# PENTING (mobile): IGNORE supaya sentuhan di area kosong menembus
	# ke _unhandled_input kamera. Interactive widget (tombol/stik) tetap
	# menangkap lewat panel anaknya sendiri (filter STOP di sana).
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_build_party(root)
	_build_compass(root)
	_build_region_tracker(root)
	_build_minimap(root)
	_build_stamina(root)
	_build_actions(root)
	_build_stick(root)
	_build_settings(root)

	motor = get_tree().get_first_node_in_group("player") as CharacterMotor
	camera_rig = get_tree().get_first_node_in_group("camera_rig") as CameraRig
	if camera_rig == null:
		camera_rig = get_tree().get_first_node_in_group("player").get_node("../CameraRig") as CameraRig

func _build_party(root: Control) -> void:
	var menu := UiKit.rect("MenuBtn", root, Vector2(0, 1), Vector2(0, 1),
		Vector2(-56, -56), Vector2(64, 64))
	(menu as Control).add_theme_stylebox_override("panel", UiKit.panel_style(UiKit.PANEL, 14))
	UiKit.button_slot(menu, _toggle_settings)
	UiKit.label(menu, "=", 40, UiKit.CREAM)

	# 4 potret party + bar HP.
	for i in 4:
		var active := i == 0
		var px := 16.0 + i * 96.0
		var p := UiKit.portrait(root, "Portrait%d" % i,
			Vector2(0, 1), Vector2(0, 1), Vector2(px, -150), Vector2(84, 84),
			UiKit.TEAL if active else Color(0.30, 0.34, 0.42, 0.9),
			UiKit.GOLD if active else UiKit.DIM)
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		UiKit.label(p, str(i + 1), 34, UiKit.CREAM, HORIZONTAL_ALIGNMENT_CENTER, true)
		var hp := UiKit.bar(root, "Hp%d" % i, Vector2(0, 1), Vector2(0, 1),
			Vector2(px + 2, -52), Vector2(80, 10), Color(0, 0, 0, 0.55), UiKit.HP_GREEN)
		(hp["outer"] as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		(hp["fill"] as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		UiKit.set_bar(hp, 1.0)

func _build_compass(root: Control) -> void:
	var strip := UiKit.rect("Compass", root, Vector2(0.5, 0), Vector2(0.5, 0),
		Vector2(-280, 14), Vector2(560, 52))
	(strip as Control).add_theme_stylebox_override("panel", UiKit.panel_style(UiKit.PANEL, 12))
	for i in DIR_NAME.size():
		var holder := Control.new()
		holder.name = "D%d" % i
		holder.anchor_left = 0.5
		holder.anchor_right = 0.5
		holder.anchor_top = 0.5
		holder.anchor_bottom = 0.5
		holder.custom_minimum_size = Vector2(60, 52)
		strip.add_child(holder)
		var l := UiKit.label(holder, DIR_NAME[i], 24, UiKit.CREAM)
		_dir_rects.append(holder)
		_dir_labels.append(l)
	var caret := Control.new()
	caret.anchor_left = 0.5
	caret.anchor_right = 0.5
	caret.anchor_top = 0.0
	caret.anchor_bottom = 0.0
	strip.add_child(caret)
	UiKit.label(caret, "v", 22, UiKit.GOLD)

func _build_region_tracker(root: Control) -> void:
	var panel := UiKit.rect("Quest", root, Vector2(0.5, 0), Vector2(0.5, 0),
		Vector2(-260, 72), Vector2(520, 80))
	(panel as Control).add_theme_stylebox_override("panel", UiKit.panel_style(UiKit.PANEL, 12))
	_region_name = UiKit.label(panel, "...", 28, UiKit.CREAM)
	_region_name.anchor_top = 0.02
	_region_name.anchor_bottom = 0.55
	_region_name.offset_left = 10
	_region_name.offset_right = -10
	_region_name.offset_top = 2
	_region_name.offset_bottom = 36
	_region_sub = UiKit.label(panel, "", 20, UiKit.DIM)
	_region_sub.anchor_top = 0.5
	_region_sub.anchor_bottom = 0.98
	_region_sub.offset_left = 10
	_region_sub.offset_right = -10

func _build_minimap(root: Control) -> void:
	var map := UiKit.rect("Minimap", root, Vector2(1, 0), Vector2(1, 0),
		Vector2(-210, 10), Vector2(190, 190))
	(map as Control).add_theme_stylebox_override("panel",
			UiKit.panel_style(UiKit.PANEL, 999))
	UiKit.label(map, "MAP", 30, UiKit.DIM)
	var gold_ring := Panel.new()
	gold_ring.add_theme_stylebox_override("panel", UiKit.ring_style(UiKit.GOLD))
	gold_ring.offset_left = -4
	gold_ring.offset_top = -4
	gold_ring.offset_right = 194
	gold_ring.offset_bottom = 194
	map.add_child(gold_ring)
	var nord := Control.new()
	nord.anchor_left = 0.5
	nord.anchor_right = 0.5
	nord.anchor_top = 0.5
	nord.anchor_bottom = 0.5
	map.add_child(nord)
	UiKit.label(nord, "N", 24, UiKit.GOLD)
	_n_mark = nord

	var fps := UiKit.rect("Fps", root, Vector2(1, 0), Vector2(1, 0),
		Vector2(-210, 208), Vector2(190, 30))
	_fps_text = UiKit.label(fps, "", 22, UiKit.DIM)

func _build_stamina(root: Control) -> void:
	var holder := Control.new()
	holder.name = "StaminaHolder"
	holder.anchor_left = 0.5
	holder.anchor_right = 0.5
	holder.anchor_top = 1.0
	holder.anchor_bottom = 1.0
	holder.custom_minimum_size = Vector2(440, 26)
	root.add_child(holder)
	_stam_group = holder
	_stam_group.modulate.a = 0.0
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var outer := UiKit.bar(holder, "Stamina", Vector2(0.5, 0), Vector2(0.5, 0),
		Vector2(-220, -54), Vector2(440, 14), Color(0, 0, 0, 0.55), UiKit.STAMINA)
	(outer["outer"] as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	(outer["fill"] as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stam_fill = outer

func _build_actions(root: Control) -> void:
	_make_action(root, "BtnAttack", Vector2(-170, 200), 210, "ATK", 44,
		func(): pressed_attack.emit())
	_make_action(root, "BtnSkill", Vector2(-350, 270), 150, "E", 52,
		_fire_skill)
	_make_action(root, "BtnBurst", Vector2(-330, 445), 165, "Q", 56,
		_fire_burst)
	_make_action(root, "BtnJump", Vector2(-545, 180), 135, "JMP", 34,
		func(): pressed_jump.emit())
	_make_action(root, "BtnDash", Vector2(-705, 160), 135, "DSH", 34,
		func(): pressed_dash.emit())

	# Cincin energi ultimate.
	var q := root.get_node_or_null("BtnBurst") as Control
	if q != null:
		var ring_p := Panel.new()
		ring_p.name = "Energy"
		ring_p.add_theme_stylebox_override("panel", UiKit.ring_style(UiKit.GOLD))
		ring_p.offset_left = -6
		ring_p.offset_top = -6
		ring_p.offset_right = 171
		ring_p.offset_bottom = 171
		q.add_child(ring_p)
		_burst_ring_nodes.append(ring_p)

func _make_action(root: Control, nama: String, pos: Vector2, size: int,
				  label_teks: String, font_size: int, on_press: Callable) -> Control:
	var b := UiKit.rect(nama, root, Vector2(1, 0), Vector2(1, 0), pos, Vector2(size, size))
	(b as Control).add_theme_stylebox_override("panel",
		UiKit.panel_style(Color(1, 1, 1, 0.30), 9999, UiKit.GOLD, 4))
	UiKit.button_slot(b, on_press)
	UiKit.label(b, label_teks, font_size, UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER, true)
	return b

func _build_stick(root: Control) -> void:
	stick = VirtualJoystick.new()
	stick.name = "StickZone"
	stick.anchor_left = 0.0
	stick.anchor_top = 1.0
	stick.anchor_right = 0.45
	stick.anchor_bottom = 1.0
	stick.offset_left = 0
	stick.offset_top = -340
	stick.offset_right = 0
	stick.offset_bottom = -34
	root.add_child(stick)

func _build_settings(root: Control) -> void:
	var panel := UiKit.rect("Settings", root, Vector2(0.5, 0.5), Vector2(0.5, 0.5),
		Vector2(-468, -338), Vector2(936, 676))
	(panel as Control).add_theme_stylebox_override("panel",
		UiKit.panel_style(Color(0.07, 0.09, 0.15, 0.96), 18, UiKit.GOLD, 3))
	_edit_panel = panel
	_edit_panel.visible = false

	UiKit.label(panel, "PENGATURAN", 36, UiKit.GOLD, HORIZONTAL_ALIGNMENT_CENTER, true)\
		.add_theme_font_size_override("font_size", 36)

	_labels_settings.clear()
	var y := -240.0
	for row in [
		["Kualitas", "quality", _step_quality],
		["FPS", "fps", _step_fps],
		["Sensitivitas", "sensitivity", _step_sensitivity],
		["Jarak Kamera", "camera_distance", _step_fog_distance],
		["Bayangan", "shadows", _step_shadows],
		["Bloom", "bloom", _step_bloom],
		["Suara", "sound", _step_sound],
		["Skala Tombol", "button_scale", _step_button_scale],
	]:
		_settings_row(panel, row[0], y, row[1], row[2])
		y -= 62.0

	var close := UiKit.rect("Close", panel, Vector2(0.5, 1), Vector2(0.5, 1),
		Vector2(-130, -72), Vector2(260, 60))
	(close as Control).add_theme_stylebox_override("panel",
		UiKit.panel_style(UiKit.GOLD, 30))
	UiKit.button_slot(close, _toggle_settings)
	UiKit.label(close, "TUTUP", 30, UiKit.INK)
	_refresh_settings_texts()

var _labels_settings: Dictionary = {}   ## id -> Label nilai

func _settings_row(panel: Control, label: String, y: float, id: String,
				   on_step: Callable) -> void:
	var row := UiKit.rect("Row%s" % label, panel, Vector2(0, 1), Vector2(1, 1),
		Vector2(0, y), Vector2(920, 56))
	var l := UiKit.rect("L", row, Vector2(0, 0.5), Vector2(0, 0.5),
		Vector2(20, -20), Vector2(340, 40))
	UiKit.label(l, label, 28, UiKit.CREAM, HORIZONTAL_ALIGNMENT_LEFT)

	var bl := UiKit.rect("BL", row, Vector2(1, 0.5), Vector2(1, 0.5),
		Vector2(-300, -20), Vector2(64, 40))
	(bl as Control).add_theme_stylebox_override("panel", UiKit.panel_style(UiKit.PANEL_SOFT, 12))
	UiKit.button_slot(bl, func(): on_step.call(-1))
	UiKit.label(bl, "<", 28, UiKit.CREAM)

	var vv := UiKit.rect("V", row, Vector2(1, 0.5), Vector2(1, 0.5),
		Vector2(-200, -20), Vector2(200, 40))
	_labels_settings[id] = UiKit.label(vv, "", 28, UiKit.GOLD)

	var br := UiKit.rect("BR", row, Vector2(1, 0.5), Vector2(1, 0.5),
		Vector2(0, 0), Vector2(64, 40))
	(br as Control).add_theme_stylebox_override("panel", UiKit.panel_style(UiKit.PANEL_SOFT, 12))
	UiKit.button_slot(br, func(): on_step.call(1))
	UiKit.label(br, ">", 28, UiKit.CREAM)

func _toggle_settings() -> void:
	if _edit_panel == null:
		return
	_edit_panel.visible = not _edit_panel.visible
	if _edit_panel.visible:
		_refresh_settings_texts()

func _refresh_settings_texts() -> void:
	var s := SettingsStore.load()
	if not _labels_settings.has("quality"):
		return
	_labels_settings["quality"].text = \
		QualityPresets.PRESET_LABEL.get(s.get("quality", "balanced"), s.get("quality", "balanced"))
	_labels_settings["fps"].text = str(s["fps"])
	_labels_settings["sensitivity"].text = "%.1f" % s["sensitivity"]
	_labels_settings["camera_distance"].text = "%.1f" % s["camera_distance"]
	_labels_settings["shadows"].text = "ON" if s["shadows"] else "OFF"
	_labels_settings["bloom"].text = \
		QualityPresets.LEVEL_LABEL[clampi(s["gfx"]["bloom"], 0, 3)]
	_labels_settings["sound"].text = "ON" if s["sound"] else "OFF"
	_labels_settings["button_scale"].text = "%.2f" % s["button_scale"]

func _apply(s: Dictionary) -> void:
	SettingsStore.save(s)
	QualityApplier.refresh_all_scene(get_tree())
	_refresh_settings_texts()

func _step_quality(dir: int) -> void:
	var s := SettingsStore.load()
	var ids := QualityPresets.PRESET_IDS
	var i := ids.find(s.get("quality", "balanced"))
	if i < 0:
		i = 1
	i = (i + dir + ids.size()) % ids.size()
	_apply(QualityPresets.apply_preset(s, ids[i]))

func _step_fps(dir: int) -> void:
	var s := SettingsStore.load()
	var choices := QualityPresets.FPS_CHOICES
	var i := choices.find(s["fps"])
	if i < 0:
		i = 2
	s["fps"] = choices[(i + dir + choices.size()) % choices.size()]
	_apply(GameSettings.normalize(s))

func _step_sensitivity(dir: int) -> void:
	var s := SettingsStore.load()
	s["sensitivity"] = s["sensitivity"] + 0.2 * dir
	_apply(GameSettings.normalize(s))

func _step_fog_distance(dir: int) -> void:
	var s := SettingsStore.load()
	s["camera_distance"] = s["camera_distance"] + 0.5 * dir
	_apply(GameSettings.normalize(s))

func _step_shadows(_dir: int) -> void:
	var s := SettingsStore.load()
	s["shadows"] = not s["shadows"]
	_apply(GameSettings.normalize(s))

func _step_bloom(dir: int) -> void:
	var s := SettingsStore.load()
	var v := int(s["gfx"]["bloom"]) + dir
	v = ((v % 4) + 4) % 4
	s["gfx"]["bloom"] = v
	s["quality"] = "custom"       ## satu opsi diubah manual -> custom
	_apply(GameSettings.normalize(s))

func _step_sound(_dir: int) -> void:
	var s := SettingsStore.load()
	s["sound"] = not s["sound"]
	_apply(GameSettings.normalize(s))

func _step_button_scale(dir: int) -> void:
	var s := SettingsStore.load()
	s["button_scale"] = clampf(s["button_scale"] + 0.1 * dir, 0.75, 1.4)
	_apply(GameSettings.normalize(s))

# ============================================================ skill
func _fire_skill() -> void:
	if _skill_cd > 0.0 or motor == null:
		return
	_skill_cd = SKILL_CD_MAX
	_energy = minf(100.0, _energy + 10.0)
	if vfx != null:
		vfx.spawn_hit(motor.global_position + Vector3.UP * 1.0)
	if camera_rig != null:
		camera_rig.add_shake(0.35)
	pressed_skill.emit()

func _fire_burst() -> void:
	if _burst_cd > 0.0 or _energy < 100.0 or motor == null:
		return
	_burst_cd = BURST_CD_MAX
	_energy = 0.0
	if vfx != null:
		vfx.spawn_hit(motor.global_position + Vector3.UP * 1.2)
	if camera_rig != null:
		camera_rig.add_shake(0.7)
	pressed_burst.emit()

# ============================================================ frame
var _n_mark: Control

func _process(dt: float) -> void:
	if motor == null:
		motor = get_tree().get_first_node_in_group("player") as CharacterMotor
	if camera_rig == null:
		camera_rig = get_tree().get_first_node_in_group("camera_rig") as CameraRig

	# Kompas.
	if camera_rig != null and _dir_labels.size() == DIR_NAME.size():
		var yaw := camera_rig.yaw
		for i in DIR_NAME.size():
			var d := _delta_deg(yaw, DIR_YAW[i])
			_dir_rects[i].position.x = d * 4.2
			var a := clampf(1.0 - absf(d) / 62.0, 0.0, 1.0)
			_dir_labels[i].modulate.a = a

	# Pelacak region.
	if motor != null:
		var p := motor.global_position
		var region := WorldData.region_at(p.x, p.z)
		if region["id"] != _region_id:
			_region_id = region["id"]
			_region_name.text = region["name"]
			_region_sub.text = region["subtitle"]
		# Stamina.
		var st: float = motor.stamina01
		UiKit.set_bar(_stam_fill, st)
		var show = st < 0.999
		_stam_group.modulate.a += ((1.0 if show else 0.0) - _stam_group.modulate.a) \
			* minf(1.0, dt * 8.0)

	# Cooldowns.
	_skill_cd = maxf(0.0, _skill_cd - dt)
	_burst_cd = maxf(0.0, _burst_cd - dt)
	_energy = minf(100.0, _energy + 5.0 * dt)
	for n in _burst_ring_nodes:
		n.modulate.a = _energy / 100.0

	# FPS.
	var settings := SettingsStore.load()
	if settings["show_fps"] and _fps_text != null:
		_fps_acc += dt
		_fps_n += 1
		if _fps_acc >= 0.5:
			_fps_text.text = "%.0f fps" % (_fps_n / _fps_acc)
			_fps_acc = 0.0
			_fps_n = 0
	elif _fps_text != null:
		_fps_text.text = ""

func _delta_deg(a: float, b: float) -> float:
	return wrapf(a - b + 180.0, 0.0, 360.0) - 180.0
