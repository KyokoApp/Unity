extends CanvasLayer
## HUD: joystick melayang (muncul saat disentuh), kamera geser kanan, tombol
## aksi bulat gaya RPG (digambar via canvas), prompt, statistik, jam, FPS, toast,
## dan Mode Edit in-game (sculpt terrain + jalur + pencahayaan).

## Tombol bulat transparan putih ber-icon canvas (pedang/lompat/sepatu/dll).
class RpgButton:
	extends Control
	signal pressed
	signal released
	var icon := "sword"
	var emoji := ""
	var radius := 44.0
	var active := false
	var _down := false
	var _label: Label

	func _init(ic: String, r: float, emj := "") -> void:
		icon = ic
		radius = r
		emoji = emj
		custom_minimum_size = Vector2(r * 2, r * 2)
		size = custom_minimum_size
		mouse_filter = Control.MOUSE_FILTER_STOP
		if emoji != "":
			_label = Label.new()
			_label.text = emoji
			_label.add_theme_font_size_override("font_size", int(r * 0.92))
			_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
			_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			_label.set_anchors_preset(Control.PRESET_FULL_RECT)
			_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(_label)

	func set_active(a: bool) -> void:
		active = a
		queue_redraw()

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventScreenTouch:
			if e.pressed:
				_down = true
				pressed.emit()
			elif _down:
				_down = false
				released.emit()
			queue_redraw()
		elif e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed:
				_down = true
				pressed.emit()
			elif _down:
				_down = false
				released.emit()
			queue_redraw()

	func _draw() -> void:
		var c := Vector2(radius, radius)
		# gaya referensi (Genshin-like): lingkaran gelap translusen + glyph putih
		draw_circle(c, radius - 1.0, Color(0.10, 0.12, 0.15, 0.62 if _down else 0.42))
		draw_arc(c, radius - 2.5, 0.0, TAU, 48, Color(1, 1, 1, 0.30), 2.0, true)
		if active:
			draw_arc(c, radius - 7.0, 0.0, TAU, 48, Color(1, 1, 1, 0.55), 2.5, true)
		if emoji != "":
			return
		var w := Color(1, 1, 1, 0.94)
		var r := radius * 0.62
		match icon:
			"sword":
				var a := c + Vector2(-0.42, 0.42) * r      # pangkal gagang
				var b := c + Vector2(0.52, -0.52) * r      # ujung pedang
				var dir := (b - a).normalized()
				var perp := Vector2(-dir.y, dir.x)
				draw_line(a, b, w, 6.0, true)
				draw_line(a + perp * r * 0.16 - dir * r * 0.18,
					a - perp * r * 0.16 - dir * r * 0.18, w, 5.0, true)  # guard
				draw_line(a, a - dir * r * 0.3, w, 5.0, true)              # gagang
			"jump":
				draw_arc(c + Vector2(0, -0.5) * r, r * 0.15, 0.0, TAU, 16, w, 3.0, true)
				draw_line(c + Vector2(0, -0.34) * r, c + Vector2(0, 0.06) * r, w, 3.5, true)
				draw_line(c + Vector2(-0.26, -0.2) * r, c + Vector2(0.26, -0.2) * r, w, 3.0, true)
				draw_line(c + Vector2(0, 0.06) * r, c + Vector2(-0.24, 0.34) * r, w, 3.0, true)
				draw_line(c + Vector2(0, 0.06) * r, c + Vector2(0.24, 0.34) * r, w, 3.0, true)
				draw_line(c + Vector2(-0.42, 0.62) * r, c + Vector2(0, 0.42) * r, w, 3.5, true)
				draw_line(c + Vector2(0, 0.42) * r, c + Vector2(0.42, 0.62) * r, w, 3.5, true)
			"dash":  # sepatu + garis kecepatan
				var pts := PackedVector2Array([
					c + Vector2(-0.5, 0.14) * r, c + Vector2(-0.1, 0.14) * r,
					c + Vector2(0.12, 0.3) * r, c + Vector2(0.5, 0.3) * r,
					c + Vector2(0.5, 0.46) * r, c + Vector2(-0.5, 0.46) * r,
					c + Vector2(-0.5, 0.14) * r])
				draw_polyline(pts, w, 3.5, true)
				draw_polyline(PackedVector2Array([
					c + Vector2(-0.5, 0.14) * r, c + Vector2(-0.5, -0.12) * r,
					c + Vector2(-0.2, -0.12) * r, c + Vector2(0.0, 0.06) * r]), w, 3.0, true)
				draw_line(c + Vector2(-0.78, 0.1) * r, c + Vector2(-0.6, 0.1) * r, w, 3.0, true)
				draw_line(c + Vector2(-0.78, 0.34) * r, c + Vector2(-0.64, 0.34) * r, w, 3.0, true)
			"pause":
				draw_line(c + Vector2(-0.2, -0.42) * r, c + Vector2(-0.2, 0.42) * r, w, 7.0, true)
				draw_line(c + Vector2(0.2, -0.42) * r, c + Vector2(0.2, 0.42) * r, w, 7.0, true)

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

	# --- joystick melayang: tersembunyi, muncul di titik sentuh kiri ---
	joy_base = Panel.new()
	joy_base.name = "JoyBase"
	joy_base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	joy_base.add_theme_stylebox_override("panel", _make_panel_col(Color(0.0, 0.0, 0.0, 0.25), 100))
	joy_base.custom_minimum_size = Vector2(JOY_RADIUS * 2, JOY_RADIUS * 2)
	joy_base.size = Vector2(JOY_RADIUS * 2, JOY_RADIUS * 2)
	joy_base.position = Vector2(ml + 10, vsz.y - mb - JOY_RADIUS * 2 - 16)
	joy_base.visible = false
	root.add_child(joy_base)
	joy_knob = Panel.new()
	joy_knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	joy_knob.add_theme_stylebox_override("panel", _make_panel_col(Color(1.0, 1.0, 1.0, 0.50), 50))
	joy_knob.custom_minimum_size = Vector2(96, 96)
	joy_knob.size = Vector2(96, 96)
	joy_knob.position = Vector2(JOY_RADIUS - 48, JOY_RADIUS - 48)
	joy_base.add_child(joy_knob)

	# --- tombol aksi bulat gaya RPG (klaster kanan ala referensi) ---
	# attack besar kanan-tengah-bawah; dash di bawah-kanannya; lompat pojok kanan bawah
	var att_c := Vector2(vsz.x - mr - 148, vsz.y - mb - 230)
	_add_rpg(root, "BtnAtk", "sword", 60.0, att_c - Vector2(60.0, 60.0))
	_add_rpg(root, "BtnDash", "dash", 40.0, att_c + Vector2(86.0, 100.0) - Vector2(40.0, 40.0))
	_add_rpg(root, "BtnJump", "jump", 46.0, Vector2(vsz.x - mr - 96.0, vsz.y - mb - 96.0) - Vector2(46.0, 46.0))
	_add_rpg(root, "BtnAction", "", 36.0, att_c + Vector2(-112.0, -8.0) - Vector2(36.0, 36.0), "✋")
	_add_rpg(root, "BtnSprint", "", 30.0, Vector2(vsz.x - mr - 60, vsz.y * 0.34), "»")
	_add_rpg(root, "BtnCrouch", "", 30.0, Vector2(vsz.x - mr - 60, vsz.y * 0.34 + 72.0), "▼")
	_add_rpg(root, "BtnEmote", "", 30.0, Vector2(vsz.x - mr - 60, vsz.y * 0.34 + 144.0), "🙂")
	_connect_rpg("BtnJump", Callable(self, "_on_jump"), false)
	_connect_rpg("BtnSprint", Callable(self, "_on_sprint"), true)
	_connect_rpg("BtnCrouch", Callable(self, "_on_crouch"), true)
	_connect_rpg("BtnAction", Callable(self, "_on_action"), false)
	_connect_rpg("BtnAtk", Callable(self, "_on_attack"), false)
	_connect_rpg("BtnDash", Callable(self, "_on_dash"), false)
	_connect_rpg("BtnEmote", Callable(self, "_on_emote"), false)
	_buttons["BtnAction"].visible = false

	# --- pause: bulat kecil pojok kiri atas ---
	var bpause := RpgButton.new("pause", 32.0)
	bpause.name = "BtnPause"
	bpause.position = Vector2(ml, mt)
	root.add_child(bpause)
	_buttons["BtnPause"] = bpause
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

func _add_rpg(root: Control, name: String, icon: String, r: float, pos: Vector2, emj := "") -> void:
	var b := RpgButton.new(icon, r, emj)
	b.name = name
	b.position = pos
	root.add_child(b)
	_buttons[name] = b

func _connect_rpg(name: String, cb: Callable, holdable: bool) -> void:
	var b: RpgButton = _buttons[name]
	b.pressed.connect(func(): cb.call(true))
	if holdable:
		b.released.connect(func(): cb.call(false))

# ---------- handlers tombol ----------

func _on_jump(down: bool) -> void:
	if down and player:
		player.press_jump()

func _on_sprint(down: bool) -> void:
	if player:
		player.press_sprint(down)
	_buttons["BtnSprint"].set_active(down)

func _on_crouch(down: bool) -> void:
	if player:
		player.press_crouch(down)
	_buttons["BtnCrouch"].set_active(down)

func _on_action(down: bool) -> void:
	if down and player:
		player.press_interact()

func _on_attack(down: bool) -> void:
	if down and player:
		player.press_attack()

func _on_dash(down: bool) -> void:
	if down and player and player.has_method("press_dash"):
		player.press_dash()

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
	if edit_mode:
		if _over_edit_bar(e.position):
			return  # biarkan kontrol bar yang menangani
		if e.pressed:
			_edit_paint = e.index
			_apply_edit_at(e.position)
		elif e.index == _edit_paint:
			_edit_paint = -1
		return
	if e.pressed:
		var vsz := get_viewport().get_visible_rect().size
		# joystick melayang: sentuh area kiri-tengah → joystick muncul di titik itu
		if _joy_touch == -1 and e.position.x < vsz.x * 0.58 and e.position.y > vsz.y * 0.22:
			joy_base.position = e.position - Vector2(JOY_RADIUS, JOY_RADIUS)
			joy_base.visible = true
			_joy_touch = e.index
			_update_joy(e.position)
			return
		if _look_touch == -1:
			_look_touch = e.index
			_look_last = e.position
	else:
		if e.index == _joy_touch:
			_joy_touch = -1
			joy_base.visible = false
			_set_joy(Vector2.ZERO)
		elif e.index == _look_touch:
			_look_touch = -1

func _handle_drag(e: InputEventScreenDrag) -> void:
	if edit_mode:
		if e.index == _edit_paint and not _over_edit_bar(e.position):
			_apply_edit_at(e.position)
		return
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
	var show := meta and meta.size() > 0 and not edit_mode
	if meta and meta.size() > 0:
		var t := str(meta.get("type", ""))
		label_prompt.text = "Ambil: " + ("🥥 Kelapa" if t == "coconut" else "🌼 Bunga")
	else:
		label_prompt.text = ""
	_buttons["BtnAction"].visible = show

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

# ==================== MODE EDIT (sculpt dunia + pencahayaan) ====================

var edit_mode := false
var edit_tool := "raise"   # "raise" | "lower" | "road"
var edit_radius := 12.0
var edit_strength := 1.4
var _edit_paint := -1
var _edit_bar: Control
var _edit_tool_btns := {}
const EDIT_ACTION_NAMES := ["BtnJump", "BtnAtk", "BtnDash", "BtnSprint", "BtnCrouch", "BtnAction", "BtnEmote"]

func set_edit_mode(on: bool) -> void:
	edit_mode = on
	if player:
		player.set_joy(Vector2.ZERO)
	joy_base.visible = false
	if _edit_bar == null:
		_build_edit_bar()
	_edit_bar.visible = on
	for n in EDIT_ACTION_NAMES:
		if on:
			_buttons[n].visible = false
		else:
			_buttons[n].visible = true
			_buttons["BtnAction"].visible = label_prompt.text != ""
	toast("Mode Edit — sentuh & geser tanah untuk membentuknya" if on else "Kembali bermain")

func _exit_edit() -> void:
	set_edit_mode(false)
	if root_node and root_node.has_method("toggle_pause"):
		root_node.toggle_pause()

func _over_edit_bar(sp: Vector2) -> bool:
	return _edit_bar and _edit_bar.visible and _edit_bar.get_global_rect().has_point(sp)

func _apply_edit_at(sp: Vector2) -> void:
	if _world == null or not _world.has_method("apply_terrain_edit"):
		return
	var hit := _edit_ray_hit(sp)
	if hit.x > 1e17:
		return
	if edit_tool == "road":
		_world.apply_terrain_edit(hit, edit_radius, edit_strength * 0.14, "road")
	else:
		_world.apply_terrain_edit(hit, edit_radius, edit_strength * 0.09, edit_tool)

func _edit_ray_hit(sp: Vector2) -> Vector3:
	var cam := get_viewport().get_camera_3d()
	if cam == null or _world == null:
		return Vector3(1e18, 0, 0)
	var ro: Vector3 = cam.project_ray_origin(sp)
	var rd: Vector3 = cam.project_ray_normal(sp)
	var p := ro
	var prev := p
	for i in range(600):
		if p.y <= _world.height_at(p.x, p.z) + 0.02:
			for k in range(8):
				var mid := (prev + p) * 0.5
				if mid.y <= _world.height_at(mid.x, mid.z) + 0.02:
					p = mid
				else:
					prev = mid
			return p
		prev = p
		p += rd * 1.5
		if p.distance_to(ro) > 900.0:
			break
	return Vector3(1e18, 0, 0)

func _mk_slider(vbox: VBoxContainer, header: String, mn: float, mx: float, val: float, cb: Callable) -> HSlider:
	var l := Label.new()
	l.text = header
	l.add_theme_font_size_override("font_size", 22)
	l.modulate.a = 0.85
	vbox.add_child(l)
	var s := HSlider.new()
	s.min_value = mn
	s.max_value = mx
	s.step = 0.05
	s.value = clampf(val, mn, mx)
	s.custom_minimum_size = Vector2(0, 38)
	s.value_changed.connect(cb)
	vbox.add_child(s)
	return s

func _build_edit_bar() -> void:
	var vsz := get_viewport().get_visible_rect().size
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", _make_panel_col(Color(0.06, 0.10, 0.14, 0.90), 22))
	bar.size = Vector2(300, vsz.y)
	bar.position = Vector2(vsz.x - 300, 0)
	add_child(bar)
	_edit_bar = bar
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	bar.add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(scroll)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)
	var title := Label.new()
	title.text = "✎ Mode Edit"
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color(0.95, 0.86, 0.55))
	v.add_child(title)
	# alat bentuk
	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 8)
	v.add_child(tools)
	for spec in [["raise", "⛰ Angkat"], ["lower", "⬇ Turun"], ["road", "🛤 Jalan"]]:
		var tb := Button.new()
		tb.text = spec[1]
		tb.custom_minimum_size = Vector2(0, 56)
		tb.add_theme_font_size_override("font_size", 20)
		tb.toggle_mode = true
		var m: String = spec[0]
		tb.pressed.connect(func(): _select_tool(m))
		tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tools.add_child(tb)
		_edit_tool_btns[m] = tb
	_update_tool_visual()
	_mk_slider(v, "Ukuran kuas (m)", 3.0, 40.0, edit_radius, func(x): edit_radius = x)
	_mk_slider(v, "Kekuatan", 0.2, 4.0, edit_strength, func(x): edit_strength = x)
	var sep1 := HSeparator.new()
	v.add_child(sep1)
	var lh := Label.new()
	lh.text = "Pencahayaan"
	lh.add_theme_font_size_override("font_size", 26)
	lh.add_theme_color_override("font_color", Color(0.9, 0.92, 0.96))
	v.add_child(lh)
	_mk_slider(v, "Energi matahari", 0.3, 2.0,
		float(settings.light_sun) if settings else 1.0,
		func(x):
			if _world: _world.apply_lighting({"sun": x})
			if settings: settings.set_value("light_sun", x))
	_mk_slider(v, "Cahaya ambient", 0.3, 2.0,
		float(settings.light_ambient) if settings else 1.0,
		func(x):
			if _world: _world.apply_lighting({"ambient": x})
			if settings: settings.set_value("light_ambient", x))
	_mk_slider(v, "Kabut", 0.0, 3.0,
		float(settings.light_fog) if settings else 1.0,
		func(x):
			if _world: _world.apply_lighting({"fog": x})
			if settings: settings.set_value("light_fog", x))
	var lh2 := Label.new()
	lh2.text = "Gradien langit"
	lh2.add_theme_font_size_override("font_size", 22)
	lh2.modulate.a = 0.85
	v.add_child(lh2)
	var sw := HBoxContainer.new()
	sw.add_theme_constant_override("separation", 8)
	v.add_child(sw)
	var presets := [Color(0.62, 0.88, 0.80), Color(0.56, 0.86, 0.78), Color(0.98, 0.60, 0.38), Color(0.10, 0.15, 0.24)]
	for i in range(4):
		var cbtn := ColorRect.new()
		cbtn.color = presets[i]
		cbtn.custom_minimum_size = Vector2(52, 40)
		var bee := Button.new()
		bee.flat = true
		bee.custom_minimum_size = Vector2(52, 40)
		var ix := i
		bee.pressed.connect(func(): _pick_sky(ix))
		cbtn.add_child(bee)
		sw.add_child(cbtn)
	var auto := Button.new()
	auto.text = "Otomatis"
	auto.custom_minimum_size = Vector2(110, 40)
	auto.add_theme_font_size_override("font_size", 18)
	auto.pressed.connect(func(): _pick_sky(-1))
	sw.add_child(auto)
	# gaya low-poly (segi datar) — terinspirasi low-poly terrain builder
	var chk_fac := CheckBox.new()
	chk_fac.text = "Gaya low-poly (segi datar)"
	chk_fac.button_pressed = bool(settings.gfx_faceted) if settings else false
	chk_fac.add_theme_font_size_override("font_size", 20)
	chk_fac.custom_minimum_size = Vector2(0, 52)
	chk_fac.toggled.connect(func(on):
		if _world and _world.has_method("set_faceted"):
			_world.set_faceted(on)
		if settings:
			settings.set_value("gfx_faceted", on)
		toast("Gaya " + ("low-poly segi datar" if on else "halus")))
	v.add_child(chk_fac)
	var sep2 := HSeparator.new()
	v.add_child(sep2)
	var rst := Button.new()
	rst.text = "↺ Reset bentuk dunia"
	rst.custom_minimum_size = Vector2(0, 56)
	rst.add_theme_font_size_override("font_size", 22)
	rst.pressed.connect(func():
		if _world and _world.has_method("reset_edits"):
			_world.reset_edits()
			toast("Bentuk dunia direset"))
	v.add_child(rst)
	var done := Button.new()
	done.text = "✔ Selesai — simpan semua"
	done.custom_minimum_size = Vector2(0, 64)
	done.add_theme_font_size_override("font_size", 24)
	done.add_theme_color_override("font_color", Color(0.8, 1.0, 0.85))
	done.pressed.connect(func(): _exit_edit())
	v.add_child(done)

func _pick_sky(ix: int) -> void:
	if _world:
		_world.apply_lighting({"sky": ix})
	if settings:
		settings.set_value("light_sky", ix)
	toast("Gradien langit " + (str(ix) if ix >= 0 else "otomatis"))

func _select_tool(m: String) -> void:
	edit_tool = m
	_update_tool_visual()

func _update_tool_visual() -> void:
	for m in _edit_tool_btns:
		_edit_tool_btns[m].button_pressed = m == edit_tool
