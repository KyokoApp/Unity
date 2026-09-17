class_name HudIcons
extends RefCounted

## ============================================================
## HUD ICONS — glif vektor prosedural untuk tombol aksi HUD
## (impresi Genshin: lingkaran gelap + glif putih/emas tipis).
## Digambar via draw_* Control — tanpa aset gambar, tanpa font
## ikon (unicode tofu di HP), tajam di semua DPI.
## kind: "sword" | "jump" | "dash" | "bolt" | "burst"
## ============================================================

static var WHITE := Color(0.95, 0.97, 0.99, 1.0)
static var GOLD := Color(0.90, 0.78, 0.50, 1.0)
static var TEAL := Color(0.55, 0.82, 0.78, 1.0)

## Pasang glif berpusat di dalam tombol (area s×s penuh).
static func icon(parent: Control, kind: String, scale01: float = 0.82) -> Control:
	var g := _Glyph.new()
	g.kind = kind
	g.scale01 = scale01
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(g)
	return g

class _Glyph:
	extends Control
	var kind := "sword"
	var scale01 := 0.82

	func _draw() -> void:
		var s: float = min(size.x, size.y) * scale01
		var ox: float = (size.x - s) * 0.5
		var oy: float = (size.y - s) * 0.5
		var p := func(x: float, y: float) -> Vector2:
			return Vector2(ox + x * s, oy + y * s)
		match kind:
			"sword":
				_sword(p)
			"jump":
				_jump(p)
			"dash":
				_dash(p)
			"bolt":
				_bolt(p)
			"burst":
				_burst(p)

	## Pedang diagonal: bilah panjang, gagang emas, garis pelindung.
	func _sword(p: Callable) -> void:
		var lw := 0.07 * min(size.x, size.y) * scale01
		draw_line(p.call(0.30, 0.70), p.call(0.70, 0.30),
			HudIcons.WHITE, lw, true)
		# ujung bilah (segitiga kecil)
		draw_colored_polygon(PackedVector2Array([
			p.call(0.70, 0.30), p.call(0.60, 0.30), p.call(0.70, 0.40),
		]), HudIcons.WHITE)
		# garis pelindung (crossguard)
		draw_line(p.call(0.40, 0.72), p.call(0.28, 0.60),
			HudIcons.GOLD, 6.0, true)
		# gagang
		draw_line(p.call(0.30, 0.70), p.call(0.22, 0.78),
			HudIcons.GOLD, 7.0, true)

	## Dua chevron ke atas (loncat), seperti glif lompat Genshin.
	func _jump(p: Callable) -> void:
		var w := 7.0
		draw_line(p.call(0.28, 0.58), p.call(0.50, 0.36), HudIcons.WHITE, w, true)
		draw_line(p.call(0.72, 0.58), p.call(0.50, 0.36), HudIcons.WHITE, w, true)
		draw_line(p.call(0.28, 0.80), p.call(0.50, 0.58), HudIcons.WHITE, w, true)
		draw_line(p.call(0.72, 0.80), p.call(0.50, 0.58), HudIcons.WHITE, w, true)

	## Angin berlari: tiga garis kecepatan + kepala panah emas.
	func _dash(p: Callable) -> void:
		draw_line(p.call(0.16, 0.36), p.call(0.52, 0.36), HudIcons.WHITE, 6.0, true)
		draw_line(p.call(0.24, 0.52), p.call(0.64, 0.52), HudIcons.WHITE, 6.0, true)
		draw_line(p.call(0.16, 0.68), p.call(0.52, 0.68), HudIcons.WHITE, 6.0, true)
		draw_colored_polygon(PackedVector2Array([
			p.call(0.58, 0.40), p.call(0.82, 0.52), p.call(0.58, 0.64),
		]), HudIcons.GOLD)

	## Petir elemen (skill).
	func _bolt(p: Callable) -> void:
		draw_colored_polygon(PackedVector2Array([
			p.call(0.56, 0.10), p.call(0.30, 0.54), p.call(0.46, 0.54),
			p.call(0.40, 0.90), p.call(0.70, 0.44), p.call(0.52, 0.44),
		]), HudIcons.GOLD)

	## Bintang meledak 8 arah (burst/ultimate).
	func _burst(p: Callable) -> void:
		var c := p.call(0.5, 0.5)
		var r := 0.15 * (size.x * scale01)
		# empat pancang panjang (N/E/S/W)
		for i in 4:
			var a := PI * 0.5 * i
			var d1 := Vector2(cos(a), sin(a))
			var d2 := Vector2(-sin(a), cos(a))
			draw_colored_polygon(PackedVector2Array([
				c + d1 * (r * 2.2) + d2 * (r * 0.28),
				c + d1 * (r * 2.2) - d2 * (r * 0.28),
				c,
			]), HudIcons.WHITE)
		# empat pendek (diagonal), emas
		for i in 4:
			var a := PI * 0.5 * i + PI * 0.25
			var d1 := Vector2(cos(a), sin(a))
			var d2 := Vector2(-sin(a), cos(a))
			draw_colored_polygon(PackedVector2Array([
				c + d1 * (r * 1.5) + d2 * (r * 0.3),
				c + d1 * (r * 1.5) - d2 * (r * 0.3),
				c,
			]), HudIcons.GOLD)
		draw_circle(c, r * 0.85, HudIcons.WHITE)
