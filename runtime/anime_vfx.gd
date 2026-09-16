class_name AnimeVfx
extends Node3D

## ============================================================
## ANIME VFX — percikan anime ringan untuk serangan/pendaratan.
## (Port dari AnimeVfx.cs — billboard dengan squish khas anime.)
##
## Implementasi: satu MultiMesh quad (maks 12 partikel) yang
## di-billboard penuh di shader (aurelia_sparkle), warna per
## "kunci" serangan (putih/kuning/oranye/biru) — padanan
## window.AureliaVfx.burst() di versi three.js.
##
## Squish: quad memanjang tegak saat alpha tinggi lalu "melebar" saat
## memudar — trik klasik toon supaya percikan terasa cepat.
## ============================================================

@export var max_instances: int = 12

## ---- statistik, dibaca perf_hud ----
var active_instances: int:
	get: return Count(_particles)

enum K {
	PUTIH,
	KUNING,
	ORANYE,
	BIRU,
}

var _mmi: MultiMeshInstance3D
var _particles: Array[Dictionary] = []
var _seed := 12345

func _ready() -> void:
	_build()

func _build() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(0.30, 0.30)

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = quad

	_mmi = MultiMeshInstance3D.new()
	_mmi.name = "Sparkles"
	_mmi.multimesh = mm
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/aurelia_sparkle.gdshader") as Shader
	_mmi.material_override = mat
	_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(_mmi)

## Panggil percikan anime: n partikel di sekitar "pusat".
func combo_burst(pusat: Vector3, kunci: int, n: int = 3) -> void:
	if _mmi == null:
		_build()
	var col := _color_for(kunci)
	col.a = 1.0

	_seed = (_seed * 1664525 + 1013904223) & 0x7fffffff
	for i in n:
		_seed = (_seed * 1664525 + 1013904223) & 0x7fffffff
		var a := (_seed / float(0x7fffffff)) * TAU
		_seed = (_seed * 1664525 + 1013904223) & 0x7fffffff
		var r := (_seed / float(0x7fffffff)) * 0.15
		var dir := Vector3(cos(a) * r, 1.2 + _seed / float(0x7fffffff) * 0.7, sin(a) * r)
		_particles.append({
			"p": pusat + Vector3(cos(a), 0, sin(a)) * 0.1,
			"v": dir * (2.4 + _seed / float(0x7fffffff)),
			"life": 0.42, "t": 0.0, "c": col,
		})

func _color_for(kunci: int) -> Color:
	match kunci:
		K.KUNING: return Color(1.00, 0.92, 0.64)
		K.ORANYE: return Color(1.00, 0.78, 0.46)
		K.BIRU: return Color(0.72, 0.90, 1.00)
		_: return Color(1.00, 1.00, 1.00)

func spawn_dash(pos: Vector3) -> void:
	combo_burst(pos, K.BIRU, 2)

func spawn_land(pos: Vector3) -> void:
	combo_burst(pos + Vector3.UP * 0.05, K.PUTIH, 4)

func spawn_attack(pos: Vector3, combo: int) -> void:
	combo_burst(pos + Vector3.UP * 1.1, mini(3, combo % 4), 1 + mini(2, combo))

func spawn_hit(pos: Vector3) -> void:
	combo_burst(pos + Vector3.UP * 1.0, K.KUNING, 2)

static func Count(listui: Array) -> int:
	var c := 0
	for p in listui:
		if p["t"] < p["life"]:
			c += 1
	return c

func _process(delta: float) -> void:
	if _partikles_empty():
		if _mmi != null:
			_mmi.multimesh.instance_count = 0
		return

	var mm := _mmi.multimesh
	var i := 0
	var keep: Array[Dictionary] = []
	for p in _particles:
		p["t"] += delta
		if p["t"] >= p["life"]:
			continue
		p["v"] = p["v"] + Vector3(0, -3.2, 0) * delta * 0.8
		p["p"] = p["p"] + p["v"] * delta
		if i >= max_instances:
			# overflow: jangan jatuhkan partikel — lepaskan (count caps)
			continue
		var alpha := 1.0 - (p["t"] / p["life"])
		var s := 0.9 + (p["t"] / p["life"]) * 1.6
		var xf := Transform3D(
			Basis.from_scale(Vector3(s, s * (1.0 + alpha), s)),
			p["p"])
		mm.set_instance_transform(i, xf)
		var c: Color = p["c"]
		c.a = alpha
		mm.set_instance_color(i, c)
		keep.append(p)
		i += 1
	_particles = keep
	mm.instance_count = i

func _partikles_empty() -> bool:
	for p in _particles:
		if p["t"] < p["life"]:
			return false
	return true
