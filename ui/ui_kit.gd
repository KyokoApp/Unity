class_name UiKit
extends RefCounted

## ============================================================
## UI KIT — pembangun HUD Genshin dari kode. (Port dari UiKit.cs.)
##
## Kenapa UI dibangun dari KODE, bukan scene .tscn:
## scene game ini punggungnya adalah kode (world.tscn hanya root) —
## HUD tidak tercatat dalam scene, selalu identik di semua build,
## sama seperti pertimbangan UiKit.cs (prefab akan hilang saat
## scene dibangun ulang).
##
## Semua "gambar" (lingkaran, cincin, panel membulat) dibuat
## prosedural sebagai StyleBoxFlat/TextureRect — tanpa aset gambar,
## tanpa font kustom (font Godot bawaan dipakai; ganti di FONT
## kalau nanti punya font OFL).
##
## Referensi piksel: 1920x1080 (RefW/RefH) — HUD diletakkan dalam
## koordinat referensi dan otomatis diskala oleh stretch mode
## project ("canvas_items").
## ============================================================

## ---- palet Genshin-ish ----
static var PANEL: Color:
	get: return Color(0.06, 0.09, 0.16, 0.78)
static var PANEL_SOFT: Color:
	get: return Color(1.0, 1.0, 1.0, 0.14)
static var GOLD: Color:
	get: return Color(0.84, 0.70, 0.42, 1.0)
static var CREAM: Color:
	get: return Color(0.96, 0.95, 0.91, 1.0)
static var INK: Color:
	get: return Color(0.17, 0.16, 0.19, 1.0)
static var TEAL: Color:
	get: return Color(0.45, 0.77, 0.71, 1.0)
static var HP_GREEN: Color:
	get: return Color(0.49, 0.78, 0.43, 1.0)
static var STAMINA: Color:
	get: return Color(0.95, 0.82, 0.35, 1.0)
static var DIM: Color:
	get: return Color(1.0, 1.0, 1.0, 0.45)
static var COOLDOWN: Color:
	get: return Color(0.02, 0.03, 0.05, 0.72)

const REF_W := 1920.0
const REF_H := 1080.0

## ---- token tampilan ----
static func panel_style(color: Color, radius: int = 14, border: Color = Color(1, 1, 1, 0.10), bw: int = 2) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(radius)
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 8
	sb.shadow_offset = Vector2(0, 3)
	return sb

static func circle_style(color: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(9999)
	return sb

static func soft_style(color: Color = PANEL_SOFT) -> StyleBoxFlat:
	return circle_style(color)

## ---- Control penempat ----
## Semua koordinat dalam piksel REFERENSI (1920x1080). Rect baru dijangkar
## seperti Unity RectTransform: anchor_min..max 0..1.
static func rect(nama: String, parent: Control, am00: Vector2, am11: Vector2, pos: Vector2, size: Vector2) -> Control:
	var r: Control = Control.new()
	r.name = nama
	r.anchor_left = am00.x
	r.anchor_top = am00.y
	r.anchor_right = am11.x
	r.anchor_bottom = am11.y
	r.offset_left = pos.x
	r.offset_top = pos.y
	r.offset_right = pos.x + size.x
	r.offset_bottom = pos.y + size.y
	parent.add_child(r)
	return r

static func label(parent: Control, text: String, size_f: int = 28, color: Color = CREAM,
				align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER,
				bold := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	# Font bawaan Godot saja: kalau nanti ada font OFL (mis. Nunito),
	# daftarkan di sini meniru UiKit.Font (lihat DESAIN.md §5).
	l.add_theme_font_size_override("font_size", size_f)
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.clip_text = true
	parent.add_child(l)
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return l

static func button_slot(parent: Control, on_press: Callable) -> Button:
	var b := Button.new()
	b.flat = true
	b.modulate = Color(1, 1, 1, 0.001)
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_filter = Control.MOUSE_FILTER_PASS
	b.pressed.connect(on_press)
	parent.add_child(b)
	b.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return b

static func bar(parent: Control, nama: String, am00: Vector2, am11: Vector2,
				pos: Vector2, size: Vector2, back: Color, fill: Color, radius := 9) -> Dictionary:
	var outer := rect(nama, parent, am00, am11, pos, size)
	outer.add_theme_stylebox_override("panel", panel_style(back, radius))
	var inner := Panel.new()
	inner.name = "Fill"
	inner.add_theme_stylebox_override("panel", panel_style(fill, radius))
	inner.anchor_left = 0.02
	inner.anchor_top = 0.18
	inner.anchor_right = 0.98
	inner.anchor_bottom = 0.82
	outer.add_child(inner)
	return {"outer": outer, "fill": inner}

## Set isi bar 0..1 (kanan ditinggalkan).
static func set_bar(parts: Dictionary, value01: float) -> void:
	var u := clampf(value01, 0.0, 1.0)
	var inner: Control = parts["fill"]
	inner.anchor_left = 0.02
	inner.anchor_top = 0.18
	inner.anchor_right = lerpf(0.02, 0.98, u)
	inner.anchor_bottom = 0.82

## Rect bounds-oriented portrait (lingkaran dalam persegi).
static func portrait(parent: Control, nama: String, am00: Vector2, am11: Vector2,
					 pos: Vector2, size: Vector2, color: Color, ring: Color,
					 size_ring := 92) -> Control:
	var p := rect(nama, parent, am00, am11, pos, size)
	var face := Panel.new()
	face.name = "Face"
	face.add_theme_stylebox_override("panel", circle_style(color))
	face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(face)
	var ring_p := Panel.new()
	ring_p.name = "Ring"
	ring_p.add_theme_stylebox_override("panel", ring_style(ring))
	var d := (size_ring - size.x) / 2.0
	ring_p.offset_left = -d
	ring_p.offset_top = -d
	ring_p.offset_right = size.x + d
	ring_p.offset_bottom = size.y + d
	ring_p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(ring_p)
	return p

static func ring_style(color: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.border_color = color
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(9999)
	return sb


