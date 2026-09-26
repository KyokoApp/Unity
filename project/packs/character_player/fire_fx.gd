extends RefCounted
## Resource factory bersama untuk efek api. Semua resource immutable yang identik
## di-cache agar rentetan tembakan tidak terus mengalokasikan material/mesh/tekstur.

static var _cache := {}

static func has(key: String) -> bool:
	return _cache.has(key)

static func get_res(key: String):
	return _cache.get(key)

static func put(key: String, value):
	_cache[key] = value
	return value

static func soft_tex(core: float) -> GradientTexture2D:
	var key := "soft_%.3f" % core
	if has(key):
		return get_res(key)
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, clampf(core, 0.0, 0.9), 1.0])
	g.colors = PackedColorArray([Color.WHITE, Color(1, 1, 1, 0.6), Color(1, 1, 1, 0)])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.width = 64
	tex.height = 64
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	return put(key, tex)

static func ramp(offsets: Array, colors: Array) -> GradientTexture1D:
	var key := "ramp_%s_%s" % [str(offsets), str(colors)]
	if has(key):
		return get_res(key)
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(offsets)
	g.colors = PackedColorArray(colors)
	var tex := GradientTexture1D.new()
	tex.gradient = g
	return put(key, tex)

static func curve(points: Array, max_v: float) -> CurveTexture:
	var key := "curve_%s_%.3f" % [str(points), max_v]
	if has(key):
		return get_res(key)
	var c := Curve.new()
	c.max_value = max_v
	for point in points:
		c.add_point(point)
	var tex := CurveTexture.new()
	tex.curve = c
	return put(key, tex)

static func fx_mat(tex: Texture2D, additive: bool, tint: Color, billboard := BaseMaterial3D.BILLBOARD_PARTICLES) -> StandardMaterial3D:
	var key := "mat_%s_%s_%s_%s" % [tex.get_instance_id(), additive, tint, billboard]
	if has(key):
		return get_res(key)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	mat.billboard_mode = billboard
	mat.vertex_color_use_as_albedo = billboard == BaseMaterial3D.BILLBOARD_PARTICLES
	mat.albedo_texture = tex
	mat.albedo_color = tint
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.disable_receive_shadows = true
	return put(key, mat)

static func quad(size: Vector2, mat: Material) -> QuadMesh:
	var key := "quad_%s_%s" % [size, mat.get_instance_id()]
	if has(key):
		return get_res(key)
	var mesh := QuadMesh.new()
	mesh.size = size
	mesh.material = mat
	return put(key, mesh)

static func particles(name: String, amount: int, lifetime: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = name
	p.amount = maxi(amount, 1)
	p.lifetime = lifetime
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-16, -8, -16), Vector3(32, 24, 32))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	return p
