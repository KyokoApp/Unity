extends Control
## Mini virtual joystick KHUSUS Build Mode (file terpisah supaya modular,
## butir 7 user). HUD normal (hud.gd) menahan diri memakai sentuhan layar
## selagi build aktif (flag build_suspended), jd pergerakan pemain saat
## membangun diambil alih joystick ini: cukup utk berjalan ke lokasi
## pembangunan tanpa keluar-masuk mode.
##
## Tampilan: lingkaran dasar + knob yg mengikuti jari dalam radius;
## nilai arah di-emit lewat on_change(Vector2) (-1..1 per sumbu) yg
## manager teruskan ke player.set_joy(). Model joystick TETAP (bukan
## melayang): posisi sudah konsisten di pojok kiri sehingga jempol
## hafal tempatnya, standar build/mobile builder.

var radius := 60.0
var value := Vector2.ZERO
var on_change := Callable()

var _touch := -1
var _knob: Panel

func _ready() -> void:
	custom_minimum_size = Vector2(150, 150)
	mouse_filter = Control.MOUSE_FILTER_STOP   # telan sentuhan zona ini
	add_child(_make_circle(Color(0.10, 0.09, 0.13, 0.55), 150, Vector2.ZERO))
	_knob = _make_circle(Color(0.95, 0.80, 0.35, 0.85), 70, Vector2(40, 40))
	add_child(_knob)

func _make_circle(col: Color, size_px: int, offset: Vector2) -> Panel:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(size_px, size_px)
	p.position = offset
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st := StyleBoxFlat.new()
	st.bg_color = col
	st.corner_radius_top_left = size_px / 2
	st.corner_radius_top_right = size_px / 2
	st.corner_radius_bottom_left = size_px / 2
	st.corner_radius_bottom_right = size_px / 2
	p.add_theme_stylebox_override("panel", st)
	return p

func _gui_input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		if e.pressed:
			_touch = e.index
			_update_knob((e as InputEventScreenTouch).position)
		elif e.index == _touch:
			_touch = -1
			_reset()
	elif e is InputEventScreenDrag and e.index == _touch:
		_update_knob((e as InputEventScreenDrag).position)

func _update_knob(pos: Vector2) -> void:
	var d := pos - size * 0.5
	if d.length() > radius:
		d = d.normalized() * radius
	value = d / radius
	_knob.position = Vector2(40, 40) + d * 0.55
	if on_change.is_valid():
		on_change.call(value)

func _reset() -> void:
	value = Vector2.ZERO
	_knob.position = Vector2(40, 40)
	if on_change.is_valid():
		on_change.call(Vector2.ZERO)
