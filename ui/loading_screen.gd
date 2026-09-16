class_name LoadingScreen
extends CanvasLayer

## ============================================================
## LOADING SCREEN — ala Genshin: layar terang + bar kemajuan +
## tips, tampil SEBELUM dunia dirender, hilang setelah chunk awal
## selesai di-stream (lihat world.gd boot).
## (Port dari LoadingScreen.cs.)
## ============================================================

const TIPS: Array[String] = [
	"Tips: dorong stik penuh untuk sprint otomatis.",
	"Tips: klik kiri / tombol ATK untuk kombo 3x tebasan.",
	"Tips: tombol E = skill elemental, Q = ultimate.",
	"Tips: dash (Ctrl / tombol DSH) memakai 25% stamina.",
	"Tips: stamina terisi lagi setelah 1 detik tidak dipakai.",
	"Tips: putar kamera dengan menyeret sisi kanan layar.",
	"Tips: kualitas grafis bisa diubah di menu (pojok kiri atas).",
]

var _bar_fill: Dictionary
var _bar_label: Label
var _tips_label: Label
var _error_text: Label
var _spinner: Control
var _tip_t := 0.0
var _tip_idx := 0

func _ready() -> void:
	layer = 100
	_build()

func _build() -> void:
	var root := Control.new()
	root.name = "LoadingRoot"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	# Latar krem terang (khas loading Genshin).
	var bg := ColorRect.new()
	bg.color = Color(0.93, 0.91, 0.87, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)

	# Spinner cincin emas.
	_spinner = Control.new()
	_spinner.anchor_left = 0.5
	_spinner.anchor_right = 0.5
	_spinner.anchor_top = 0.40
	_spinner.anchor_bottom = 0.40
	_spinner.custom_minimum_size = Vector2(150, 150)
	var ring := Panel.new()
	ring.add_theme_stylebox_override("panel", UiKit._ring_style(UiKit.GOLD))
	ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_spinner.add_child(ring)
	root.add_child(_spinner)
	_spinner.position = Vector2(-75, -75)

	var title := UiKit.rect("Title", root, Vector2(0.5, 0.5), Vector2(0.5, 0.5),
		Vector2(-400, -20), Vector2(800, 90))
	UiKit.label(title, "A U R E L I A", 64, UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER, true)

	var sub := UiKit.rect("Sub", root, Vector2(0.5, 0.5), Vector2(0.5, 0.5),
		Vector2(-400, -60), Vector2(800, 40))
	UiKit.label(sub, "menyiapkan dunia ...", 30, Color(0.40, 0.38, 0.35, 1))

	# Bar kemajuan bawah.
	var bar_root := UiKit.rect("BarRow", root, Vector2(0.5, 1), Vector2(0.5, 1),
		Vector2(-320, -120), Vector2(640, 26))
	_bar_fill = UiKit.bar(bar_root, "Bar", Vector2(0, 0.5), Vector2(1, 0.5),
		Vector2(0, -8), Vector2(640, 16), Color(0.75, 0.73, 0.68, 1), UiKit.GOLD)

	var bl := UiKit.rect("BarLabel", root, Vector2(0.5, 1), Vector2(0.5, 1),
		Vector2(-400, -90), Vector2(800, 36))
	_bar_label = UiKit.label(bl, "", 26, Color(0.40, 0.38, 0.35, 1))

	var tip := UiKit.rect("Tips", root, Vector2(0.5, 1), Vector2(0.5, 1),
		Vector2(-600, -50), Vector2(1200, 36))
	_tips_label = UiKit.label(tip, TIPS[0], 26, Color(0.40, 0.38, 0.35, 1))

	_error_text = UiKit.label(tip, "", 20, Color(0.80, 0.10, 0.10, 1))
	_error_text.anchor_top = 1.0
	_error_text.anchor_bottom = 1.0
	_error_text.offset_top = 40
	_error_text.offset_bottom = 200

func _process(dt: float) -> void:
	_tip_t += dt
	if _tip_t > 4.0:
		_tip_t = 0.0
		_tip_idx = (_tip_idx + 1) % TIPS.size()
		_tips_label.text = TIPS[_tip_idx]

func set_progress(progress: float, status: String) -> void:
	UiKit.set_bar(_bar_fill, clampf(progress, 0.0, 1.0))
	_bar_label.text = status

func show_errors(lines: String) -> void:
	_error_text.text = lines
