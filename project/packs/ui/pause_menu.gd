extends CanvasLayer
## Pause menu: Lanjutkan / Pengaturan / Keluar.
## Panel pengaturan mencakup kualitas grafis, sensitivitas, skala tombol,
## invert-Y, FPS cap & indikator, dan volume (master/musik/sfx).

var _root: Node
var _settings
var _panel: PanelContainer
var _settings_box: VBoxContainer
var _syncing := false

func bind(root: Node, settings) -> void:
	_root = root
	_settings = settings

func _ready() -> void:
	layer = 20
	_build()

func _style_button(color: Color) -> Dictionary:
	var normal := StyleBoxFlat.new()
	normal.bg_color = color
	for m in ["corner_radius_top_left", "corner_radius_top_right", "corner_radius_bottom_left", "corner_radius_bottom_right"]:
		normal.set(m, 16)
	normal.shadow_color = Color(0, 0, 0, 0.3)
	normal.shadow_size = 6
	var hov: StyleBoxFlat = normal.duplicate()
	hov.bg_color = color.lightened(0.12)
	var prs: StyleBoxFlat = normal.duplicate()
	prs.bg_color = color.darkened(0.2)
	return {"normal": normal, "hover": hov, "pressed": prs}

func _make_button(txt: String, c: Color, cb: Callable) -> Button:
	var b := Button.new()
	b.text = txt
	var st := _style_button(c)
	b.add_theme_stylebox_override("normal", st["normal"])
	b.add_theme_stylebox_override("hover", st["hover"])
	b.add_theme_stylebox_override("pressed", st["pressed"])
	b.add_theme_stylebox_override("focus", st["hover"])
	b.add_theme_font_size_override("font_size", 28)
	b.custom_minimum_size = Vector2(0, 78)
	b.pressed.connect(cb)
	return b

func _build() -> void:
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.04, 0.07, 0.45)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)

	# panel geser dari KIRI (full tinggi, berscroll)
	_panel = PanelContainer.new()
	var pstyle := StyleBoxFlat.new()
	pstyle.bg_color = Color(0.08, 0.12, 0.18, 0.97)
	pstyle.corner_radius_top_right = 26
	pstyle.corner_radius_bottom_right = 26
	pstyle.border_width_right = 2
	pstyle.border_color = Color(1, 1, 1, 0.12)
	_panel.add_theme_stylebox_override("panel", pstyle)
	_panel.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	_panel.custom_minimum_size = Vector2(560, 0)
	_panel.size = Vector2(560, get_viewport().get_visible_rect().size.y)
	add_child(_panel)
	# animasi geser masuk
	_panel.position.x = -580
	var tw := create_tween()
	tw.set_ease(Tween.EASE_OUT)
	tw.set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(_panel, "position:x", 0.0, 0.28)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 34)
	margin.add_theme_constant_override("margin_right", 34)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_bottom", 28)
	_panel.add_child(margin)
	var scroll := ScrollContainer.new()
	margin.add_child(scroll)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)

	var title := Label.new()
	title.text = "⏸  MENU"
	title.add_theme_font_size_override("font_size", 46)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(0.95, 0.86, 0.55))
	v.add_child(title)

	v.add_child(_make_button("▶  Lanjutkan", Color(0.28, 0.66, 0.34), Callable(self, "_on_resume")))
	v.add_child(_make_button("✎  Mode Edit (dunia & cahaya)", Color(0.24, 0.58, 0.62), Callable(self, "_on_edit_mode")))
	v.add_child(_make_button("↩  Keluar ke Launcher", Color(0.55, 0.42, 0.30), Callable(self, "_on_exit_launcher")))
	v.add_child(_make_button("✕  Keluar Game", Color(0.66, 0.30, 0.28), Callable(self, "_on_exit_game")))

	var sep := HSeparator.new()
	v.add_child(sep)
	_settings_box = VBoxContainer.new()
	_settings_box.add_theme_constant_override("separation", 12)
	_settings_box.visible = true  # pengaturan langsung terlihat (scrollable)
	v.add_child(_settings_box)
	_build_settings()

func _build_settings() -> void:
	var s := _settings_box
	var t := Label.new()
	t.text = "Pengaturan"
	t.add_theme_font_size_override("font_size", 30)
	t.add_theme_color_override("font_color", Color(0.9, 0.9, 0.95))
	s.add_child(t)
	# kualitas
	s.add_child(_field_header("Kualitas grafis"))
	var opt := OptionButton.new()
	for n in ["Rendah (hemat baterai)", "Sedang (seimbang)", "Tinggi (indah)"]:
		opt.add_item(n)
	opt.custom_minimum_size = Vector2(0, 56)
	opt.add_theme_font_size_override("font_size", 24)
	opt.selected = _settings.quality_preset if _settings else 1
	opt.item_selected.connect(func(ix):
		if not _syncing and _settings:
			_settings.set_value("quality_preset", ix))
	s.add_child(opt)
	# fps cap
	s.add_child(_field_header("Batas FPS"))
	var opt_fps := OptionButton.new()
	for n in ["30 FPS", "60 FPS"]:
		opt_fps.add_item(n)
	opt_fps.custom_minimum_size = Vector2(0, 56)
	opt_fps.add_theme_font_size_override("font_size", 24)
	opt_fps.selected = 0 if (_settings and _settings.fps_cap == 30) else 1
	opt_fps.item_selected.connect(func(ix):
		if not _syncing and _settings:
			_settings.set_value("fps_cap", 30 if ix == 0 else 60))
	s.add_child(opt_fps)
	# tampilkan fps
	var chk := CheckBox.new()
	chk.text = "Tampilkan FPS"
	chk.button_pressed = _settings.show_fps if _settings else false
	chk.add_theme_font_size_override("font_size", 24)
	chk.custom_minimum_size = Vector2(0, 56)
	chk.toggled.connect(func(on):
		if not _syncing and _settings:
			_settings.set_value("show_fps", on))
	s.add_child(chk)
	# sensitivitas kamera
	s.add_child(_field_header("Sensitivitas kamera"))
	var sens := HSlider.new()
	sens.min_value = 0.3
	sens.max_value = 2.5
	sens.step = 0.05
	sens.value = _settings.camera_sens if _settings else 1.0
	sens.custom_minimum_size = Vector2(0, 40)
	sens.value_changed.connect(func(v):
		if not _syncing and _settings:
			_settings.set_value("camera_sens", v))
	s.add_child(sens)
	# invert y
	var inv := CheckBox.new()
	inv.text = "Balik sumbu Y kamera"
	inv.button_pressed = _settings.invert_y if _settings else false
	inv.add_theme_font_size_override("font_size", 24)
	inv.custom_minimum_size = Vector2(0, 56)
	inv.toggled.connect(func(on):
		if not _syncing and _settings:
			_settings.set_value("invert_y", on))
	s.add_child(inv)
	# karakter (skin)
	s.add_child(_field_header("Karakter"))
	var opt_skin := OptionButton.new()
	for n in ["PolyGirl (bawaan)", "Knight (KayKit)"]:
		opt_skin.add_item(n)
	opt_skin.custom_minimum_size = Vector2(0, 56)
	opt_skin.add_theme_font_size_override("font_size", 24)
	opt_skin.selected = 0 if (_settings and str(_settings.char_skin) == "polygirl") else 1
	opt_skin.item_selected.connect(func(ix):
		if not _syncing and _settings:
			var id := "polygirl" if ix == 0 else "knight"
			_settings.set_value("char_skin", id)
			if _root and _root.get("player") and _root.player.has_method("set_skin"):
				_root.player.set_skin(id))
	s.add_child(opt_skin)
	# skala tombol
	s.add_child(_field_header("Ukuran tombol aksi"))
	var bs := HSlider.new()
	bs.min_value = 0.8
	bs.max_value = 1.5
	bs.step = 0.05
	bs.value = _settings.button_scale if _settings else 1.0
	bs.custom_minimum_size = Vector2(0, 40)
	bs.value_changed.connect(func(v):
		if not _syncing and _settings:
			_settings.set_value("button_scale", v))
	s.add_child(bs)
	# volume
	for item in [["Volume utama", "vol_master"], ["Volume musik", "vol_music"], ["Volume SFX", "vol_sfx"]]:
		s.add_child(_field_header(item[0]))
		var sl := HSlider.new()
		sl.min_value = -40.0
		sl.max_value = 6.0
		sl.step = 0.5
		sl.value = float(_settings.get(item[1])) if _settings else 0.0
		sl.custom_minimum_size = Vector2(0, 40)
		var key: String = item[1]
		sl.value_changed.connect(func(v):
			if not _syncing and _settings:
				_settings.set_value(key, v))
		s.add_child(sl)

func _field_header(txt: String) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", 22)
	l.modulate.a = 0.85
	return l

func _on_resume() -> void:
	# geser keluar dulu, baru benar-benar ditutup
	if _panel:
		var tw := create_tween()
		tw.set_ease(Tween.EASE_IN)
		tw.set_trans(Tween.TRANS_CUBIC)
		tw.tween_property(_panel, "position:x", -580.0, 0.2)
		await tw.finished
	if _root and _root.has_method("_close_pause"):
		_root._close_pause()

func _on_edit_mode() -> void:
	if _root and _root.has_method("enter_edit_mode"):
		_root.enter_edit_mode()

func _on_settings() -> void:
	_settings_box.visible = not _settings_box.visible

func _on_exit_launcher() -> void:
	if _root and _root.has_method("quit_to_launcher"):
		_root.quit_to_launcher()

func _on_exit_game() -> void:
	get_tree().quit()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause_menu"):
		_on_resume()
