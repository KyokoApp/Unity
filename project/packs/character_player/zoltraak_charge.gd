extends Node3D
## Lingkaran mantra "ZOLTRAAK" yang muncul di depan karakter saat tombol
## serang ditahan. Tumbuh dari pudar (baru mulai menahan) ke lengkap (5 detik)
## dan berputar pelan. Selalu menghadap kamera lewat look_at manual supaya
## huruf mantra tetap terbaca dari sudut kamera mana pun.

const RUNES := ["Z", "O", "L", "T", "R", "A", "A", "K"]
const RING_RADIUS := 0.62

var _spin: Node3D
var _outer_ring: MeshInstance3D
var _inner_ring: MeshInstance3D
var _glow: MeshInstance3D
var _outer_mat: StandardMaterial3D
var _inner_mat: StandardMaterial3D
var _glow_mat: StandardMaterial3D
var _labels: Array[Label3D] = []
var _t := 0.0
var _progress := 0.0

func _ready() -> void:
	_spin = Node3D.new()
	_spin.name = "RuneSpin"
	add_child(_spin)

	_glow = MeshInstance3D.new()
	var glow_mesh := QuadMesh.new()
	glow_mesh.size = Vector2(RING_RADIUS * 2.6, RING_RADIUS * 2.6)
	_glow.mesh = glow_mesh
	_glow_mat = _make_material(Color(0.55, 0.78, 1.0, 0.0))
	_glow.material_override = _glow_mat
	_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_spin.add_child(_glow)

	_outer_ring = MeshInstance3D.new()
	var outer_mesh := QuadMesh.new()
	outer_mesh.size = Vector2(RING_RADIUS * 2.2, RING_RADIUS * 2.2)
	_outer_ring.mesh = outer_mesh
	_outer_mat = _make_material(Color(0.6, 0.85, 1.0, 0.0))
	_outer_mat.albedo_texture = _ring_tex(0.72, 0.92)
	_outer_ring.material_override = _outer_mat
	_outer_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_outer_ring.position.z = 0.01
	_spin.add_child(_outer_ring)

	_inner_ring = MeshInstance3D.new()
	var inner_mesh := QuadMesh.new()
	inner_mesh.size = Vector2(RING_RADIUS * 1.4, RING_RADIUS * 1.4)
	_inner_ring.mesh = inner_mesh
	_inner_mat = _make_material(Color(0.85, 0.95, 1.0, 0.0))
	_inner_mat.albedo_texture = _ring_tex(0.58, 0.86)
	_inner_ring.material_override = _inner_mat
	_inner_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_inner_ring.position.z = 0.02
	_spin.add_child(_inner_ring)

	for i in RUNES.size():
		var label := Label3D.new()
		label.text = RUNES[i]
		label.font_size = 30
		label.pixel_size = 0.008
		label.modulate = Color(0.85, 0.95, 1.0, 0.0)
		label.outline_modulate = Color(0.05, 0.15, 0.4, 0.0)
		label.double_sided = true
		label.no_depth_test = true
		label.shaded = false
		var angle := TAU * float(i) / float(RUNES.size())
		label.position = Vector3(cos(angle) * RING_RADIUS * 0.98, sin(angle) * RING_RADIUS * 0.98, 0.03)
		_spin.add_child(label)
		_labels.append(label)

func update_progress(progress: float, delta: float) -> void:
	_t += delta
	_progress = clampf(progress, 0.0, 1.0)
	var eased := _progress * _progress * (3.0 - 2.0 * _progress)
	var scale_v := lerpf(0.30, 1.0, eased)
	_spin.scale = Vector3.ONE * scale_v
	_spin.rotation.z += delta * lerpf(0.6, 2.2, _progress)
	var alpha := lerpf(0.0, 1.0, eased)
	var pulse := 1.0
	if _progress >= 0.999:
		pulse = 1.0 + 0.12 * sin(_t * 7.0)
	_glow_mat.albedo_color.a = alpha * 0.5 * pulse
	_outer_mat.albedo_color.a = alpha * 0.95 * pulse
	_inner_mat.albedo_color.a = alpha * 0.9 * pulse
	for label in _labels:
		if is_instance_valid(label):
			label.modulate.a = alpha
			label.outline_modulate.a = alpha * 0.9

func face_camera(cam: Camera3D) -> void:
	if cam == null:
		return
	look_at(cam.global_position, Vector3.UP)

func dissolve_and_free() -> void:
	var tween := create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(_spin, "scale", Vector3.ONE * lerpf(_spin.scale.x, _spin.scale.x * 1.4, 1.0), 0.16)
	tween.tween_property(_glow_mat, "albedo_color:a", 0.0, 0.16)
	tween.tween_property(_outer_mat, "albedo_color:a", 0.0, 0.16)
	tween.tween_property(_inner_mat, "albedo_color:a", 0.0, 0.16)
	for label in _labels:
		if is_instance_valid(label):
			tween.tween_property(label, "modulate:a", 0.0, 0.16)
	tween.chain().tween_callback(queue_free)

func _make_material(tint: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_texture = _soft_disc()
	mat.albedo_color = tint
	mat.vertex_color_use_as_albedo = false
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.disable_receive_shadows = true
	mat.no_depth_test = true
	return mat

func _soft_disc() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.75, 1.0])
	gradient.colors = PackedColorArray([Color.WHITE, Color(1, 1, 1, 0.5), Color(1, 1, 1, 0)])
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.width = 64
	tex.height = 64
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	return tex

func _ring_tex(inner: float, outer: float) -> GradientTexture2D:
	var gradient := Gradient.new()
	var band := (inner + outer) * 0.5
	gradient.offsets = PackedFloat32Array([0.0, clampf(inner, 0.0, 0.98), clampf(band, 0.0, 0.99), clampf(outer, 0.0, 1.0), 1.0])
	gradient.colors = PackedColorArray([
		Color(1, 1, 1, 0), Color(1, 1, 1, 0), Color(1, 1, 1, 1.0), Color(1, 1, 1, 0), Color(1, 1, 1, 0)
	])
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.width = 128
	tex.height = 128
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	return tex
