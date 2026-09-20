extends RefCounted
## Helper material: membuat ShaderMaterial toon + outline inverted-hull.
## Dipakai lintas pack lewat preload().

const TOON_SHADER := preload("res://packs/shaders_materials/toon.gdshader")
const TOON_COLOR_SHADER := preload("res://packs/shaders_materials/toon_color.gdshader")
const OUTLINE_SHADER := preload("res://packs/shaders_materials/outline.gdshader")

static var _cache := {}

static func toon(color: Color, outline := false, outline_thickness := 0.012, rim := 0.5) -> ShaderMaterial:
	var key := "t_%s_%d_%.3f_%.2f" % [color.to_html(), int(outline), outline_thickness, rim]
	if _cache.has(key):
		return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = TOON_SHADER
	m.set_shader_parameter("albedo", color)
	m.set_shader_parameter("rim_amount", rim)
	if outline:
		m.next_pass = make_outline(outline_thickness, color.darkened(0.82))
	_cache[key] = m
	return m

static func toon_vertex_color(outline := false, outline_thickness := 0.012) -> ShaderMaterial:
	var key := "vc_%d_%.3f" % [int(outline), outline_thickness]
	if _cache.has(key):
		return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = TOON_COLOR_SHADER
	if outline:
		m.next_pass = make_outline(outline_thickness)
	_cache[key] = m
	return m

<<<<<<< HEAD
static func make_outline(thickness := 0.012, color := Color(0.07, 0.05, 0.10)) -> ShaderMaterial:
=======
static func make_outline(thickness := 0.012, color := Color(0.24, 0.15, 0.14)) -> ShaderMaterial:
>>>>>>> a7dedaa (style: palet turquoise pastel seluruh game + pratinjau eksposur CPU (siang/senja/malam))
	var key := "ol_%.3f_%s" % [thickness, color.to_html()]
	if _cache.has(key):
		return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = OUTLINE_SHADER
	m.set_shader_parameter("thickness", thickness)
	m.set_shader_parameter("outline_color", color)
	_cache[key] = m
	return m
