extends CanvasLayer
## HUD: joystick virtual kiri, area geser kamera kanan, tombol aksi,
## prompt interaksi, statistik pickup, jam dalam game, FPS opsional, toast.
## Semua elemen dibangun via kode agar pack mandiri; multi-touch via index event.

var player: Node
var root_node: Node
var settings

var joy_base: Control
var joy_knob: Control
var joy_vec := Vector2.ZERO
var _joy_touch := -1
var _look_touch := -1
var _look_last := Vector2.ZERO
const JOY_RADIUS := 110.0
const DEADZONE := 0.14

var _buttons := {}   # nama -> Control(Button-like)
var _btn_colors := {}
var label_prompt: Label
var label_stats: Label
var label_fps: Label
var label_clock: Label
var toast_label: Label
var _toast_timer := 0.0
var _fps_acc := 0.0
var _fps_frames := 0
var _world: Node

func bind_player(p: Node) -> void:
	player = p
	if player and player.has_signal("nearest_interactable_changed"):
		player.nearest_interactable_changed.connect(_on_near_changed)
	if player and player.has_signal("stats_changed"):
		player.stats_changed.connect(_on_stats)

func bind_root(r: Node) -> void:
	root_node = r
	if root_node and root_node.get("world") != null:
		_world = root_node.world

func set_settings(s) -> void:
	settings = s
	_apply_scale()
	if settings.has_signal("changed"):
		settings.changed.connect(_on_setting_changed)

func _ready() -> void:
	layer = 1
	_build_layout()
	_apply_scale()
	set_physics_process(true)

func _on_setting_changed(key: String) -> void:
	if key in ["button_scale"]:
		_apply_scale()
	if key in ["show_fps"]:
		label_fps.visible = settings.show_fps

# ---------- konstruksi UI ----------

func _make_panel_col(color: Color, radius := 28) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.corner_radius_top_left = radius
	sb.corner_radius_top_right = radius
	sb.corner_radius_bottom_left = radius
	sb.corner_radius_bottom_right = radius
	sb.border_width_left = 3
	sb.border_width_right = 3
	sb.border_width_top = 3
	sb.border_width_bottom = 3
	sb.border_color = Color(1, 1, 1, 0.30)
	sb.anti_aliasing = true
	return sb

func _button_style(base: Color, edge: Color) -> Dictionary:
	var normal := StyleBoxFlat.new()
	normal.bg_color = base
	for m in ["corner_radius_top_left", "corner_radius_top_right", "corner_radius_bottom_left", "corner_radius_bottom_right"]:
		normal.set(m, 20)
	normal.border_width_bottom = 5
	normal.border_width_top = 5
	normal.border_width_left = 5
	normal.border_width_right = 5
	normal.border_color = edge
	normal.shadow_color = Color(0, 0, 0, 0.25)
	normal.shadow_size = 5
	normal.anti_aliasing = true
	var pressed: StyleBoxFlat = normal.duplicate()
	pressed.bg_color = base.darkened(0.28)
	pressed.border_color = edge.lightened(0.2)
	return {"normal": normal, "pressed": pressed}

func _make_action_button(name: String, txt: String, emoji_color: Color, edge: Color) -> Button:
	var b := Button.new()
	b.name = name
	b.text = txt
	var styles := _button_style(emoji_color, edge)
	b.add_theme_stylebox_override("normal", styles["normal"])
	b.add_theme_stylebox_override("pressed", styles["pressed"])
	b.add_theme_stylebox_override("hover", styles["normal"])
	b.add_theme_stylebox_override("focus", styles["normal"])
	b.add_theme_font_size_override("font_size", 30)
	b.add_theme_color_override("font", Color(1, 1, 1))
	b.add_theme_color_override("font_color_pressed", Color(0.9, 0.9, 0.9))
	b.add_theme_color_override("font_hover", Color(1, 1, 1))
	b.add_theme_color_override("font_focus", Color(1, 1, 1))
	b.custom_minimum_size = Vector2(128, 128)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_buttons[name] = b
	_btn_colors[name] = emoji_color
	return b

func _build_layout() -> void:
	var sa := DisplayServer.get_display_safe_area()
	var root := Control.new()
	root.name = "HudRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var ml := 28.0
	var mr := 28.0
	var mt := 20.0
	var mb := 20.0
	var vsz := get_viewport().get_visible_rect().size
	if sa.size.x > 0:
		ml += sa.position.x
		mt += sa.position.y
		mr += maxf(0, vsz.x - sa.end.x)
		mb += maxf(0, vsz.y - sa.end.y)

	# --- joystick ---
	joy_base = Panel.new()
	joy_base.name = "JoyBase"
	joy_base.mouse_filter = Control.MOUSE_FILTER_STOP
	joy_base.add_theme_stylebox_override("panel", _make_panel_col(Color(0.05, 0.06, 0.08, 0.30), 100))
	joy_base.custom_minimum_size = Vector2(JOY_RADIUS * 2, JOY_RADIUS * 2)
	joy_base.size = Vector2(JOY_RADIUS * 2, JOY_RADIUS * 2)
	joy_base.position = Vector2(ml + 10, vsz.y - mb - JOY_RADIUS * 2 - 16)
	root.add_child(joy_base)
	joy_knob = Panel.new()
	joy_knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	joy_knob.add_theme_stylebox_override("panel", _make_panel_col(Color(0.95, 0.86, 0.55, 0.9), 50))
	joy_knob.custom_minimum_size = Vector2(96, 96)
	joy_knob.size = Vector2(96, 96)
	joy_knob.position = Vector2(JOY_RADIUS - 48, JOY_RADIUS - 48)
	joy_base.add_child(joy_knob)

	# --- tombol aksi kanan bawah ---
	var pad := 16.0
	var positions := {
		"BtnJump": Vector2(vsz.x - mr - 128 - pad, vsz.y - mb - 148),
		"BtnAtk": Vector2(vsz.x - mr - 128 * 2 - pad * 2, vsz.y - mb - 148),
		"BtnSprint": Vector2(vsz.x - mr - 128 - pad, vsz.y - mb - 148 * 2 - pad),
		"BtnCrouch": Vector2(vsz.x - mr - 128 * 2 - pad * 2, vsz.y - mb - 148 * 2 - pad),
		"BtnAction": Vector2(vsz.x - mr - 128 * 3 - pad * 3, vsz.y - mb - 148),
		"BtnEmote": Vector2(vsz.x - mr - 128 * 3 - pad * 3, vsz.y - mb - 148 * 2 - pad),
	}
	_add_button_to(root, "BtnJump", "▲", Color(0.28, 0.66, 0.34), Color(0.18, 0.45, 0.24), positions["BtnJump"])
	_add_button_to(root, "BtnAtk", "⚔", Color(0.74, 0.30, 0.28), Color(0.48, 0.19, 0.18), positions["BtnAtk"])
	_add_button_to(root, "BtnSprint", "»", Color(0.27, 0.54, 0.72), Color(0.18, 0.36, 0.50), positions["BtnSprint"])
	_add_button_to(root, "BtnCrouch", "▼", Color(0.55, 0.46, 0.66), Color(0.36, 0.30, 0.44), positions["BtnCrouch"])
	_add_button_to(root, "BtnAction", "✋", Color(0.86, 0.64, 0.24), Color(0.56, 0.42, 0.16), positions["BtnAction"])
	_add_button_to(root, "BtnEmote", "😀", Color(0.90, 0.51, 0.29), Color(0.60, 0.34, 0.19), positions["BtnEmote"])
	# koneksi tombol
	_connect_button("BtnJump", Callable(self, "_on_jump"), true)
	_connect_button("BtnSprint", Callable(self, "_on_sprint"), true)
	_connect_button("BtnCrouch", Callable(self, "_on_crouch"), true)
	_connect_button("BtnAction", Callable(self, "_on_action"), true)
	_connect_button("BtnAtk", Callable(self, "_on_attack"), true)
	_connect_button("BtnEmote", Callable(self, "_on_emote"), false)
	_buttons["BtnAction"].visible = false

	# --- pause ---
	var bpause := _make_action_button("BtnPause", "II", Color(0.30, 0.31, 0.36), Color(0.20, 0.20, 0.24))
	bpause.position = Vector2(ml, mt)
	bpause.custom_minimum_size = Vector2(88, 88)
	bpause.text = "Ⅱ"
	bpause.add_theme_font_size_override("font_size", 26)
	root.add_child(bpause)
	bpause.pressed.connect(func():
		if root_node and root_node.has_method("toggle_pause"):
			root_node.toggle_pause())

	# --- indikator atas: jam + fps ---
	label_clock = Label.new()
	label_clock.position = Vector2(ml + 100, mt + 6)
	label_clock.text = "☀ 09:36"
	label_clock.add_theme_font_size_override("font_size", 30)
	label_clock.add_theme_color_override("font_color", Color(1, 1, 1, 0.92))
	label_clock.add_theme_color_override("font_shadow", Color(0, 0, 0, 0.55))
	label_clock.add_theme_constant_override("shadow_offset_x", 2)
	label_clock.add_theme_constant_override("shadow_offset_y", 2)
	root.add_child(label_clock)
	label_fps = Label.new()
	label_fps.position = Vector2(ml + 100, mt + 44)
	label_fps.text = ""
	label_fps.add_theme_font_size_override("font_size", 24)
	label_fps.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
	label_fps.visible = settings.show_fps if settings else false
	root.add_child(label_fps)

	# --- prompt interaksi (tengah bawah) ---
	label_prompt = Label.new()
	label_prompt.add_theme_font_size_override("font_size", 30)
	label_prompt.add_theme_color_override("font_color", Color(1, 0.95, 0.7))
	label_prompt.add_theme_color_override("font_shadow", Color(0, 0, 0, 0.6))
	label_prompt.add_theme_constant_override("shadow_offset_x", 2)
	label_prompt.add_theme_constant_override("shadow_offset_y", 2)
	label_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	label_prompt.position = Vector2(vsz.x * 0.5 - 260, vsz.y - mb - 260)
	label_prompt.size = Vector2(520, 50)
	label_prompt.text = ""
	root.add_child(label_prompt)

	# --- statistik pickup (atas kanan) ---
	label_stats = Label.new()
	label_stats.position = Vector2(vsz.x - mr - 300, mt + 6)
	label_stats.size = Vector2(300, 40)
	label_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label_stats.add_theme_font_size_override("font_size", 28)
	label_stats.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	label_stats.add_theme_color_override("font_shadow", Color(0, 0, 0, 0.55))
	label_stats.add_theme_constant_override("shadow_offset_x", 2)
	label_stats.add_theme_constant_override("shadow_offset_y", 2)
	root.add_child(label_stats)

	# --- toast tengah atas ---
	toast_label = Label.new()
	toast_label.add_theme_font_size_override("font_size", 30)
	toast_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	toast_label.add_theme_color_override("font_shadow", Color(0, 0, 0, 0.6))
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toast_label.position = Vector2(vsz.x * 0.5 - 400, mt + 90)
	toast_label.size = Vector2(800, 46)
	toast_label.modulate.a = 0.0
	root.add_child(toast_label)

func _add_button_to(root: Control, name: String, txt: String, c: Color, e: Color, pos: Vector2) -> void:
	var b := _make_action_button(name, txt, c, e)
	b.position = pos
	root.add_child(b)

func _connect_button(name: String, cb: Callable, holdable: bool) -> void:
	var b: Button = _buttons[name]
	b.button_down.connect(func(): cb.call(true))
	if holdable:
		b.button_up.connect(func(): cb.call(false))

# ---------- handlers tombol ----------

func _on_jump(down: bool) -> void:
	if down and player:
		player.press_jump()

func _on_sprint(down: bool) -> void:
	if player:
		player.press_sprint(down)
	_buttons["BtnSprint"].modulate = Color(1.25, 1.25, 1.25) if down else Color.WHITE

func _on_crouch(down: bool) -> void:
	if player:
		player.press_crouch(down)
	_buttons["BtnCrouch"].modulate = Color(1.25, 1.25, 1.25) if down else Color.WHITE

func _on_action(down: bool) -> void:
	if down and player:
		player.press_interact()

func _on_attack(down: bool) -> void:
	if down and player:
		player.press_attack()

func _on_emote(_down: bool) -> void:
	if player:
		player.press_emote()

# ---------- input multi-touch ----------

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_handle_touch(event)
	elif event is InputEventScreenDrag:
		_handle_drag(event)

func _handle_touch(e: InputEventScreenTouch) -> void:
	if e.pressed:
		# daerah joystick?
		var jrect := Rect2(joy_base.global_position - Vector2(30, 30), joy_base.size + Vector2(60, 60))
		if _joy_touch == -1 and jrect.has_point(e.position):
			_joy_touch = e.index
			_update_joy(e.position)
			return
		if _look_touch == -1:
			_look_touch = e.index
			_look_last = e.position
	else:
		if e.index == _joy_touch:
			_joy_touch = -1
			_set_joy(Vector2.ZERO)
		elif e.index == _look_touch:
			_look_touch = -1

func _handle_drag(e: InputEventScreenDrag) -> void:
	if e.index == _joy_touch:
		_update_joy(e.position)
	elif e.index == _look_touch:
		var d := e.position - _look_last
		_look_last = e.position
		if player:
			player.add_look_px(d.x, d.y)

func _update_joy(pos: Vector2) -> void:
	var center := joy_base.global_position + Vector2(JOY_RADIUS, JOY_RADIUS)
	var v := (pos - center) / JOY_RADIUS
	if v.length() > 1.0:
		v = v.normalized()
	_set_joy(v)

func _set_joy(v: Vector2) -> void:
	if v.length() < DEADZONE:
		v = Vector2.ZERO
	joy_vec = v
	joy_knob.position = Vector2(JOY_RADIUS - 48, JOY_RADIUS - 48) + v * (JOY_RADIUS - 52)
	if player:
		player.set_joy(joy_vec)

# ---------- sinyal dari player ----------

func _on_near_changed(meta: Dictionary) -> void:
	if meta and meta.size() > 0:
		var t := str(meta.get("type", ""))
		label_prompt.text = "Ambil: " + ("🥥 Kelapa" if t == "coconut" else "🌼 Bunga")
		_buttons["BtnAction"].visible = true
	else:
		label_prompt.text = ""
		_buttons["BtnAction"].visible = false

func _on_stats(kind: String, count: int) -> void:
	var flowers := 0
	var cocos := 0
	if player and player.get("stats") != null:
		flowers = int(player.stats.get("flower", 0))
		cocos = int(player.stats.get("coconut", 0))
	label_stats.text = "🌼 %d   🥥 %d" % [flowers, cocos]
	toast("+1 " + ("Kelapa 🥥" if kind == "coconut" else "Bunga 🌼"))

func toast(msg: String) -> void:
	toast_label.text = msg
	toast_label.modulate.a = 1.0
	_toast_timer = 2.2

# ---------- loop ----------

func _physics_process(delta: float) -> void:
	if _toast_timer > 0.0:
		_toast_timer -= delta
		if _toast_timer <= 0.0:
			toast_label.modulate.a = 0.0
	if settings and settings.show_fps:
		_fps_acc += delta
		_fps_frames += 1
		if _fps_acc >= 0.5:
			label_fps.visible = true
			label_fps.text = "%d FPS" % int(round(_fps_frames / _fps_acc))
			_fps_acc = 0.0
			_fps_frames = 0
	# jam dunia → indikator atas
	if _world and _world.get("time_of_day") != null:
		var t: float = _world.time_of_day
		var hh := int(t)
		var mm := int((t - hh) * 60.0)
		var face := "☀" if t >= 6.5 and t <= 17.5 else ("🌙" if (t < 5.0 or t > 20.5) else "🌅")
		label_clock.text = "%s %02d:%02d" % [face, hh % 24, mm]

func _apply_scale() -> void:
	var sc := 1.0
	if settings:
		sc = clampf(settings.button_scale, 0.8, 1.5)
	for name in _buttons:
		if name == "BtnPause":
			continue
		_buttons[name].scale = Vector2.ONE * sc
	joy_base.scale = Vector2.ONE * sc
