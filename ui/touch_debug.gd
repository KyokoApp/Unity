class_name TouchDebug
extends CanvasLayer

## ============================================================
## TOUCH DEBUG — mata-di-dalam-build untuk soal "input HP mati".
##
## Masalah yang diselesaikan: probe headless (tests/touch_probe.gd)
## tidak bisa menguji routing sentuhan OS -> GUI (DisplayServer
## headless tidak merouting ScreenTouch ke Control). Di HP nyata,
## satu-satunya sumber kebenaran adalah apa yang dilihat user
## sendiri. Layer ini menjawab TIGA pertanyaan diagnosis dari
## SATU screenshot:
##   os=N      — sentuhan mencapai scene tree? (Node._input)
##   stikGUI=N — ScreenTouch masuk VirtualJoystick._gui_input?
##   kamera=N  — sentuhan di luar zona dipakai kamera?
## Bila os naik tapi stikGUI diam -> routing GUI mati di device itu.
## Bila os ikut diam -> sentuhan tidak masuk aplikasi sama sekali.
##
## Plus: titik sentuh digambar di layar (mirip "show taps" Android)
## dan bingkai zona stik diarsir tipis, jadi terlihat jelas apakah
## jari mendarat di dalam zona.
##
## Nyala otomatis hanya di build debug (OS.is_debug_build()); build
## release kelak bersih tanpa perlu mengubah apa pun. Semua Control
## di sini mouse_filter=IGNORE: layer ini TIDAK PERNAH menyentuh
## input, hanya mengamati.
## ============================================================

## Master switch — dipasang World._build() dari OS.is_debug_build().
static var enabled := false

static var _inst: TouchDebug = null

## Dipanggil VirtualJoystick saat ScreenTouch masuk _gui_input-nya.
static func note_gui(pos_lokal: Vector2, idx: int) -> void:
	if not enabled or _inst == null:
		return
	_inst._gui_hits += 1
	_inst._last_note = "stikGUI idx=%d lokal=%s" % [idx, str(pos_lokal)]

## Dipanggil CameraRig saat mulai memakai satu sentuhan (di luar zona).
static func note_cam(pos_screen: Vector2, idx: int) -> void:
	if not enabled or _inst == null:
		return
	_inst._cam_presses += 1
	_inst._last_note = "kamera idx=%d pos=%s" % [idx, str(pos_screen)]

## ---- state instance ----
var stick: VirtualJoystick
var camera_rig: CameraRig
var rig: CharacterRig

var _downs := 0
var _drags := 0
var _gui_hits := 0
var _cam_presses := 0
var _last_note := "-"
var _in_zone := false
var _taps: Array = []   # {p: Vector2 kanvas, t: float, down: bool}

var _strip: Label
var _dots: Control
var _zone_tag: Label
var _acc := 0.0

func _ready() -> void:
	layer = 90
	_inst = self

	var root := Control.new()
	root.name = "TouchDebugRoot"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_dots = Control.new()
	_dots.name = "Dots"
	_dots.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dots.draw.connect(_on_dots_draw)
	root.add_child(_dots)

	_strip = Label.new()
	_strip.name = "Strip"
	_strip.add_theme_color_override("font_color", Color(1, 1, 1, 0.82))
	_strip.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_strip.add_theme_constant_override("shadow_offset_x", 1)
	_strip.add_theme_constant_override("shadow_offset_y", 1)
	_strip.add_theme_font_size_override("font_size", 19)
	_strip.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.65))
	_strip.add_theme_constant_override("outline_size", 4)
	_strip.anchor_left = 0.0
	_strip.anchor_top = 0.0
	_strip.anchor_right = 0.0
	_strip.anchor_bottom = 0.0
	_strip.offset_left = 12
	_strip.offset_top = 8
	_strip.offset_right = 760
	_strip.offset_bottom = 152
	_strip.autowrap_mode = TextServer.AUTOWRAP_OFF
	_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_strip)

	# Label kecil penanda rect zona stik (posisi di-set tiap refresh).
	_zone_tag = Label.new()
	_zone_tag.name = "ZoneTag"
	_zone_tag.text = "ZONA STIK"
	_zone_tag.add_theme_font_size_override("font_size", 18)
	_zone_tag.add_theme_color_override("font_color", Color(0.84, 0.70, 0.42, 0.8))
	_zone_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_zone_tag.custom_minimum_size = Vector2(220, 24)
	_zone_tag.size = Vector2(220, 24)
	root.add_child(_zone_tag)

	_apply_enabled()
	BootLog.add("TouchDebug siap (enabled=%s, stempel %s)." % [enabled, BuildStamp.id()])

func refresh_enabled() -> void:
	_apply_enabled()

func _apply_enabled() -> void:
	visible = enabled
	set_process_input(enabled)
	set_process(enabled)

func _exit_tree() -> void:
	if _inst == self:
		_inst = null

## Node-level: melihat event yang TIDAK ditelan widget STOP. Sentuhan
## yang di-accept stik (di dalam zona) dilaporkan terpisah lewat
## note_gui — jadi os+stikGUI bersama = kebenaran OS lengkap.
func _input(event: InputEvent) -> void:
	var tekan := false
	var seret := false
	if event is InputEventScreenTouch:
		tekan = (event as InputEventScreenTouch).pressed
	elif event is InputEventScreenDrag:
		seret = true
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		tekan = mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT
	elif event is InputEventMouseMotion:
		seret = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if not (tekan or seret):
		return
	# .get() sengaja dipakai: event hasil make_input_local bertipe
	# InputEvent dasar; position/index milik tipe turunannya.
	var lokal = _dots.make_input_local(event)
	var p: Vector2 = lokal.get("position")
	if tekan:
		_downs += 1
	if seret:
		_drags += 1
	_in_zone = _point_in_stick_zone(p)
	_note_tap(p, tekan)
	if tekan:
		var idx_v = event.get("index")
		_last_note = "OS idx=%s px=%s kanvas=%s zona=%s" % [
			str(idx_v) if idx_v != null else "mouse",
			str(event.get("position")), str(p), "YA" if _in_zone else "tidak"]

func _note_tap(p: Vector2, down: bool) -> void:
	_taps.append({"p": p, "t": Time.get_ticks_msec() / 1000.0, "down": down})
	if _taps.size() > 40:
		_taps.remove_at(0)

func _point_in_stick_zone(canvas_p: Vector2) -> bool:
	if stick == null or not stick.is_inside_tree():
		return false
	return stick.get_global_rect().has_point(canvas_p)

func _process(_dt: float) -> void:
	if not enabled:
		return
	_acc += _dt
	_dots.queue_redraw()
	# Buang tap yang kedaluwarsa (jejak 0,8 detik).
	var now := Time.get_ticks_msec() / 1000.0
	while not _taps.is_empty() and now - (_taps[0]["t"] as float) > 0.8:
		_taps.remove_at(0)
	if _acc < 0.25:
		return
	_acc = 0.0
	_refresh_text()

func _refresh_text() -> void:
	var vs: Vector2 = get_viewport().get_visible_rect().size
	var sk: float = get_viewport().get_final_transform().get_scale().x
	var kanvas := vs / maxf(sk, 0.0001)
	var device := "%s %s" % [OS.get_name(), OS.get_model_name()]
	var stik_txt := "off"
	if stick != null:
		if stick.is_active:
			stik_txt = "AKTIF sumbu(%.2f,%.2f)" % [stick.axis_value.x, stick.axis_value.y]
		else:
			stik_txt = "siaga"
	var zona := "?"
	if stick != null:
		var r: Rect2 = stick.get_global_rect()
		zona = str(r)
		_zone_tag.position = r.position + Vector2(8, 4)
	var anim_txt := "anim:kosong"
	if rig != null:
		anim_txt = rig.anim_debug_line()
	_strip.text = "DBG %s | layar %.0fx%.0f kanvas %.0fx%.0f x%.2f\n" % [
			BuildStamp.id(), vs.x, vs.y, kanvas.x, kanvas.y, sk] \
		+ "os turun %d seret %d | stikGUI %d | kamera %d | stik:%s\n" % [
			_downs, _drags, _gui_hits, _cam_presses, stik_txt] \
		+ "zona %s | layar-sentuh=%s | %s\n" % [
			zona, "YA" if DisplayServer.is_touchscreen_available() else "tidak",
			anim_txt] \
		+ "%s | %s" % [device, _last_note]

func _on_dots_draw() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	# Bingkai zona stik — rect yang sama persis dengan yang dihit mesin.
	if stick != null and stick.is_inside_tree():
		var r: Rect2 = stick.get_global_rect()
		_dots.draw_rect(r, Color(0.84, 0.70, 0.42, 0.10), true)
		_dots.draw_rect(r, Color(0.84, 0.70, 0.42, 0.55), false, 2.0)
	# Jejak tap.
	for tap in _taps:
		var umur: float = now - (tap["t"] as float)
		var a: float = clampf(1.0 - umur / 0.8, 0.0, 1.0)
		var p: Vector2 = tap["p"]
		if tap["down"]:
			_dots.draw_arc(p, 26.0, 0.0, TAU, 24, Color(1.0, 0.9, 0.4, 0.85 * a), 3.0)
			_dots.draw_circle(p, 7.0, Color(1.0, 0.9, 0.4, 0.85 * a))
		else:
			_dots.draw_circle(p, 5.0, Color(1.0, 1.0, 1.0, 0.5 * a))
