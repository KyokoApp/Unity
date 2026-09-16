class_name VirtualJoystick
extends Control

## ============================================================
## VIRTUAL JOYSTICK — stik "mengambang" ala Genshin mobile:
## alas muncul di titik jari menyentuh, kenop mengikuti seret.
## (Port dari VirtualJoystick.cs + zona GenshinHud.BuildStick.)
##
## Matematika sumbu SAMA dengan Locomotion.joystick_axis() (radius
## default 55, deadzone 0,14) jadi rasa geraknya identik dengan
## game asli, yang beda cuma tampilannya.
## ============================================================

## Radius stik dalam piksel referensi (1920x1080).
@export var radius_ref: float = 130.0
## Jarak maksimal kenop (dikali radius_ref).
@export var knob_scale: float = 0.6

var axis_value := Vector2.ZERO
var is_active := false

var _touch_index := -1
var _origin := Vector2.ZERO
var _base: Control
var _knob: Control
var _scale := 1.0

signal stick_changed(axis: Vector2)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	_base = _visual("Base", UiKit.circle_style(Color(1, 1, 1, 0.18)), radius_ref * 2.0)
	_knob = _visual("Knob", UiKit.circle_style(Color(1, 1, 1, 0.45)), radius_ref * knob_scale * 2.0)
	_base.visible = false
	_knob.visible = false
	_recalc_scale()
	_home()

func _visual(nama: String, style: StyleBox, diameter: float) -> Control:
	var c := Control.new()
	c.name = nama
	c.custom_minimum_size = Vector2(diameter, diameter)
	c.size = Vector2(diameter, diameter)
	var p := Panel.new()
	p.add_theme_stylebox_override("panel", style)
	p.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.add_child(p)
	add_child(c)
	return c

func _recalc_scale() -> void:
	# Koordinat layar -> kanvas referensi 1920x1080.
	var vs := get_viewport().get_visible_rect().size
	_scale = maxf(vs.x / UiKit.REF_W, vs.y / UiKit.REF_H)
	if _scale <= 0.0:
		_scale = 1.0

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

func _gui_input(event: InputEvent) -> void:
	_recalc_scale()
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed and not is_active:
			_touch_index = t.index
			_origin = t.position / _scale
			is_active = true
			_base.visible = true
			_knob.visible = true
			_center()
		elif not t.pressed and t.index == _touch_index:
			_touch_index = -1
			is_active = false
			_base.visible = false
			_knob.visible = false
			_home()
	elif event is InputEventScreenDrag and is_active:
		var d := event as InputEventScreenDrag
		if d.index == _touch_index:
			_drag(d.position / _scale - _origin)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and not is_active:
			_touch_index = -2
			_origin = mb.position / _scale
			is_active = true
			_base.visible = true
			_knob.visible = true
			_center()
		elif mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed and _touch_index == -2:
			_touch_index = -1
			is_active = false
			_base.visible = false
			_knob.visible = false
			_home()
	elif event is InputEventMouseMotion and is_active and _touch_index == -2:
		var mm := event as InputEventMouseMotion
		_drag(mm.position / _scale - _origin)

func _drag(local: Vector2) -> void:
	var a := Locomotion.joystick_axis(local.x, local.y, radius_ref)
	# Layar: ke atas = arah +Y joystick (maju di permainan).
	_set_axis(Vector2(a.x, -a.y))
	var vis := a * radius_ref
	_knob.position = _base.position + (_base.size - _knob.size) * 0.5 \
		+ Vector2(vis.x, vis.y) * knob_scale * 0.8
