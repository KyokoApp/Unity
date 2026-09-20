extends RefCounted
## Helper material: membuat ShaderMaterial toon + outline inverted-hull.
## Dipakai lintas pack lewat preload().

const TOON_SHADER := preload("res://packs/shaders_materials/toon.gdshader")
const TOON_COLOR_SHADER := preload("res://packs/shaders_materials/toon_color.gdshader")
const OUTLINE_SHADER := preload("res://packs/shaders_materials/outline.gdshader")
const TERRAIN_DETAIL := preload("res://packs/shaders_materials/textures/terrain_detail.jpg")

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

static func toon_vertex_color(outline := false, outline_thickness := 0.012, detail := false) -> ShaderMaterial:
	var key := "vc_%d_%.3f_%d" % [int(outline), outline_thickness, int(detail)]
	if _cache.has(key):
		return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = TOON_COLOR_SHADER
	if detail:
		m.set_shader_parameter("detail_enabled", true)
		m.set_shader_parameter("detail_tex", TERRAIN_DETAIL)
	if outline:
		m.next_pass = make_outline(outline_thickness)
	_cache[key] = m
	return m

static func make_outline(thickness := 0.012, color := Color(0.24, 0.15, 0.14)) -> ShaderMaterial:
	var key := "ol_%.3f_%s" % [thickness, color.to_html()]
	if _cache.has(key):
		return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = OUTLINE_SHADER
	m.set_shader_parameter("thickness", thickness)
	m.set_shader_parameter("outline_color", color)
	_cache[key] = m
	return m
