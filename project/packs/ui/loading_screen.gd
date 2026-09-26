extends CanvasLayer
## Loading screen: judul, tip, progress bar besar, dan spinner.
## Dipakai saat boot awal; buguan begin(cb) akan menjalankan cb(progress_cb).

var _bar: ProgressBar
var _label: Label
var _tip: Label
var _spin: Control
var _fade_nodes: Array = []
var _bar_target := 0.0
var _done_cb: Callable
const TIPS := [
	"Tip: geser analog di kiri layar untuk menggerakkan 🔥 bola api.",
	"Tip: dorong analog setengah saja untuk melayang pelan.",
	"Tip: usap sisi kanan layar untuk memutar kamera.",
	"Tip: saat malam tiba, cahaya bola api menerangi sekitarnya.",
	"Tip: tekan tombol Kembali (Back) untuk membuka menu.",
]

func _ready() -> void:
	layer = 10
	_build()

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.10, 0.16, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var accent := ColorRect.new()
	accent.color = Color(0.11, 0.24, 0.34, 1.0)
	accent.set_anchors_preset(Control.PRESET_FULL_RECT)
	accent.modulate.a = 0.5
	add_child(accent)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 22)
	v.custom_minimum_size = Vector2(760, 0)
	center.add_child(v)

	var title := Label.new()
	title.text = "🌴 A-SEKAI"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", Color(0.95, 0.86, 0.55))
	v.add_child(title)

	var sub := Label.new()
	sub.text = "Menyiapkan petualangan..."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 26)
	sub.modulate.a = 0.8
	v.add_child(sub)

	_label = Label.new()
	_label.text = "…"
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 22)
	v.add_child(_label)

	_bar = ProgressBar.new()
	_bar.min_value = 0
	_bar.max_value = 1000
	_bar.custom_minimum_size = Vector2(0, 34)
	_bar.show_percentage = true
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.93, 0.65, 0.25)
	fill.corner_radius_top_left = 10
	fill.corner_radius_top_right = 10
	fill.corner_radius_bottom_left = 10
	fill.corner_radius_bottom_right = 10
	_bar.add_theme_stylebox_override("fill", fill)
	var bgs := StyleBoxFlat.new()
	bgs.bg_color = Color(1, 1, 1, 0.10)
	bgs.corner_radius_top_left = 10
	bgs.corner_radius_top_right = 10
	bgs.corner_radius_bottom_left = 10
	bgs.corner_radius_bottom_right = 10
	_bar.add_theme_stylebox_override("background", bgs)
	v.add_child(_bar)

	_spin = Control.new()
	_spin.custom_minimum_size = Vector2(64, 64)
	_spin.draw.connect(_draw_spin)
	v.add_child(_spin)

	_tip = Label.new()
	_tip.text = TIPS[randi() % TIPS.size()]
	_tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tip.add_theme_font_size_override("font_size", 22)
	_tip.modulate.a = 0.75
	_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_tip)
	set_process(true)

var _spin_angle := 0.0
func _process(delta: float) -> void:
	_spin_angle += delta * 2.4
	_spin.queue_redraw()
	# progress halus menuju target
	_bar.value = lerpf(_bar.value, _bar_target, delta * 3.5)

func _draw_spin() -> void:
	var cx := Vector2(32, 32)
	for i in range(8):
		var a := _spin_angle + i * TAU / 8.0
		var al := float(i) / 8.0
		var col := Color(0.95, 0.86, 0.55, 0.15 + 0.85 * al)
		_spin.draw_circle(cx + Vector2(cos(a), sin(a)) * 22.0, 5.0, col)

## Mulai loading. `boot_callable` memanggil balik progress_cb(pct, text)
## secara berkala; awaited hingga selesai, lalu fade out.
func begin(boot_callable: Callable) -> void:
	var progress_cb := func(p: float, t: String):
		_bar_target = clampf(p, 0.0, 1.0) * 1000.0
		_label.text = t
	await boot_callable.call(progress_cb)
	_bar_target = 1000.0
	_label.text = "Selesai!"
	await get_tree().create_timer(0.35).timeout
	var valid := []
	for node in _fade_nodes:
		if is_instance_valid(node):
			valid.append(node)
	if not valid.is_empty():
		var tw := create_tween()
		tw.set_parallel(true)
		for node in valid:
			tw.tween_property(node, "modulate:a", 0.0, 0.4)
		await tw.finished
	var owner := get_parent()
	if owner and owner.has_method("on_loading_done"):
		owner.on_loading_done()
	queue_free()
