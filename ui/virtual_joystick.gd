class_name VirtualJoystick
extends Control

## ============================================================
## VIRTUAL JOYSTICK — stik "mengambang" ala Genshin mobile:
## alas muncul di titik jari menyentuh, kenop mengikuti seret.
## (Port dari VirtualJoystick.cs + zona GenshinHud.BuildStick.)
##
## Matematika sumbu SAMA dengan Locomotion.joystick_axis() (radius
## default 130, deadzone 0,14) jadi rasa geraknya identik dengan
## game asli — yang beda cuma tampilannya.
##
## Pelajaran penting (fix sesi "analog tidak muncul di HP"):
## [1] event.position di _gui_input adalah KOORDINAT LOKAL
##     control (engine sudah xform) — JANGAN dibagi skala lagi.
##     Skala ganda inilah yang membuat stik melenceng dari jari
##     di HP yang resolusinya bukan persis 1920x1080.
## [2] Godot GUI TIDAK punya touch-capture: begitu jari keluar
##     rect zona, _gui_input berhenti menerima event. _input()
##     di bawah menangkap kelanjutan gerak/lepas (dan menelannya)
##     supaya stik tidak membeku dan kamera tidak ikut memutar.
## ============================================================

## Radius stik dalam piksel referensi (1920x1080).
@export var radius_ref: float = 130.0
## Jarak maksimal kenop (dikali radius_ref).
@export var knob_scale: float = 0.6

var axis_value := Vector2.ZERO
var is_active := false

## Diagnostik: dibaca TouchDebug & probe. Jangan dijadikan logika.
var gui_hits := 0
var drags_seen := 0

var _touch_index := -1
var _origin := Vector2.ZERO
var _base: Control
var _knob: Control
var _ghost: Control
var _drag_frame := -1
var _release_frame := -1

signal stick_changed(axis: Vector2)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	_base = _visual("Base", UiKit.circle_style(Color(1, 1, 1, 0.18)), radius_ref * 2.0)
	_knob = _visual("Knob", UiKit.circle_style(Color(1, 1, 1, 0.45)), radius_ref * knob_scale * 2.0)
	_base.visible = false
	_knob.visible = false
	_ghost = _build_ghost()
	_home()

## Cincin nyaris-hantu di titik stik klasik — petunjuk visual saat
## siaga ("analog gk muncul" tidak boleh berarti "tidak ada apa pun
## di layar"). Tetap mengambang: sentuhan di mana saja dalam zona
## memunculkan alas tepat di bawah jari.
func _build_ghost() -> Control:
	var g := Control.new()
	g.name = "Ghost"
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var r: float = radius_ref * 0.62
	g.anchor_left = 0.30
	g.anchor_right = 0.30
	g.anchor_top = 0.55
	g.anchor_bottom = 0.55
	g.offset_left = -r
	g.offset_top = -r
	g.offset_right = r
	g.offset_bottom = r
	g.custom_minimum_size = Vector2(r * 2.0, r * 2.0)
	var ring := Panel.new()
	ring.add_theme_stylebox_override("panel", UiKit.ring_style(Color(1, 1, 1, 0.14)))
	ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.add_child(ring)
	var dot := Panel.new()
	dot.add_theme_stylebox_override("panel", UiKit.circle_style(Color(1, 1, 1, 0.10)))
	dot.anchor_left = 0.22
	dot.anchor_right = 0.78
	dot.anchor_top = 0.22
	dot.anchor_bottom = 0.78
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.add_child(dot)
	add_child(g)
	return g

func _visual(nama: String, style: StyleBox, diameter: float) -> Control:
	var c := Control.new()
	c.name = nama
	c.custom_minimum_size = Vector2(diameter, diameter)
	c.size = Vector2(diameter, diameter)
	# Dekoratif: JANGAN pernah menelan sentuhan — sentuhan harus tetap
	# jatuh ke _gui_input zona stik (Base/Knob tak punya logika).
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var p := Panel.new()
	p.add_theme_stylebox_override("panel", style)
	p.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(p)
	add_child(c)
	return c

func axis() -> Vector2:
	return axis_value

func _home() -> void:
	_set_axis(Vector2.ZERO)
	_center()

func _center() -> void:
	_base.position = _origin - _base.size * 0.5
	_knob.position = _base.position + (_base.size - _knob.size) * 0.5

func _set_axis(a: Vector2) -> void:
	axis_value = a
	stick_changed.emit(a)

func _press(pos_lokal: Vector2, idx: int) -> void:
	_touch_index = idx
	_origin = pos_lokal
	is_active = true
	_base.visible = true
	_knob.visible = true
	_ghost.visible = false
	_center()

func _release(idx: int) -> void:
	if idx != _touch_index:
		return
	_touch_index = -1
	is_active = false
	_base.visible = false
	_knob.visible = false
	_ghost.visible = true
	_home()

## Jalur GUI standar (position = LOKAL control, engine sudah xform).
func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			if not is_active:
				gui_hits += 1
				TouchDebug.note_gui(t.position, t.index)
				if gui_hits <= 3:
					var msg := "[stik] touch-down #%d idx=%d lokal=%s rect=%s" % [
						gui_hits, t.index, str(t.position), str(get_global_rect())]
					BootLog.add(msg)
					print(msg)
				_press(t.position, t.index)
				# Milik stik: sentuhan zona tidak boleh bocor ke
				# _unhandled_input (kamera/serangan klik-kiri).
				accept_event()
		else:
			if t.index == _touch_index:
				_release(t.index)
				_release_frame = Engine.get_process_frames()
				accept_event()
	elif event is InputEventScreenDrag and is_active:
		var d := event as InputEventScreenDrag
		if d.index == _touch_index:
			_drag_frame = Engine.get_process_frames()
			drags_seen += 1
			_drag(d.position - _origin)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and not is_active:
			_press(mb.position, -2)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed and _touch_index == -2:
			_release(-2)
			_release_frame = Engine.get_process_frames()
			accept_event()
	elif event is InputEventMouseMotion and is_active and _touch_index == -2:
		_drag_frame = Engine.get_process_frames()
		_drag((event as InputEventMouseMotion).position - _origin)

## Jalur TANGKAP (fix [2]): setelah stik aktif, jari BOLEH keluar
## rect zona tanpa stik membeku/kamera merebut. Event yang sampai ke
## sini berarti tidak ada Control yang menelannya.
func _input(event: InputEvent) -> void:
	if not is_active or not is_visible_in_tree():
		return
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if not t.pressed and t.index == _touch_index:
			if _release_frame == Engine.get_process_frames():
				return   # sudah dilepas lewat jalur GUI
			_release(t.index)
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == _touch_index:
			if _drag_frame == Engine.get_process_frames():
				return   # sudah diproses lewat jalur GUI
			drags_seen += 1
			_drag(make_input_local(d).get("position") - _origin)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and _touch_index == -2:
		var mb := event as InputEventMouseButton
		if not mb.pressed:
			if _release_frame == Engine.get_process_frames():
				return
			_release(-2)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _touch_index == -2:
		if _drag_frame == Engine.get_process_frames():
			return
		_drag(make_input_local(event).get("position") - _origin)
		get_viewport().set_input_as_handled()

func _drag(local: Vector2) -> void:
	var a := Locomotion.joystick_axis(local.x, local.y, radius_ref)
	# Layar: ke atas = arah +Y joystick (maju di permainan).
	_set_axis(Vector2(a.x, -a.y))
	var vis := a * radius_ref
	_knob.position = _base.position + (_base.size - _knob.size) * 0.5 \
		+ Vector2(vis.x, vis.y) * knob_scale * 0.8
