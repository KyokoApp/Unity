extends Node3D
## Proyektil bola api berbalistik, dengan ekor persisten dan ledakan prosedural.

const FX := preload("res://packs/character_player/fire_fx.gd")
const EXPLOSION := preload("res://packs/character_player/fire_explosion.gd")
const CORE_SHADER := preload("res://packs/character_player/fireball_core.gdshader")
const SHELL_SHADER := preload("res://packs/character_player/fireball_shell.gdshader")

var vel := Vector3.ZERO
var fx := 1.0
var exclude_rids: Array[RID] = []
var shake_target: Node

var _age := 0.0
var _dead := false
var _visual: Node3D
var _shell_mat: ShaderMaterial
var _light: OmniLight3D
var _flow := Vector3.ZERO
var _trail := Vector3.ZERO

func _ready() -> void:
	fx = clampf(fx, 0.2, 1.0)
	_build_visual()

func _process(delta: float) -> void:
	if _dead:
		return
	delta = minf(delta, 0.1)
	_age += delta
	var from := global_position
	vel.y -= 5.0 * delta
	var to := from + vel * delta
	var hit := get_world_3d().direct_space_state.intersect_ray(_ray(from, to))
	if not hit.is_empty():
		_explode(hit.get("position", to), "impact")
		return
	if to.y <= 0.0:
		var fraction := from.y / maxf(from.y - to.y, 0.0001)
		_explode(from.lerp(to, clampf(fraction, 0.0, 1.0)), "impact")
		return
	global_position = to
	_flow += vel * delta * 0.5
	_trail = _trail.lerp((-vel * 0.05).limit_length(0.9), 1.0 - exp(-13.0 * delta))
	_shell_mat.set_shader_parameter("trail", _trail)
	_shell_mat.set_shader_parameter("flow_offset", _flow)
	_light.light_energy = 2.2 * (0.9 + 0.08 * sin(_age * 31.0) + 0.05 * sin(_age * 53.0))
	if _age >= 3.0:
		_explode(global_position, "air")

func _ray(from: Vector3, to: Vector3) -> PhysicsRayQueryParameters3D:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = exclude_rids
	q.collide_with_areas = true
	q.collide_with_bodies = true
	return q

func _build_visual() -> void:
	_visual = Node3D.new()
	_visual.name = "BoltVisual"
	add_child(_visual)

	var core := MeshInstance3D.new()
	var core_mesh := SphereMesh.new()
	core_mesh.radius = 0.16
	core_mesh.height = 0.32
	core_mesh.radial_segments = 20
	core_mesh.rings = 10
	core.mesh = core_mesh
	var core_key := "bolt_core_mat"
	var core_mat: ShaderMaterial
	if FX.has(core_key):
		core_mat = FX.get_res(core_key)
	else:
		core_mat = ShaderMaterial.new()
		core_mat.shader = CORE_SHADER
		core_mat.set_shader_parameter("intensity", 3.4)
		core_mat.set_shader_parameter("turbulence", 1.6)
		FX.put(core_key, core_mat)
	core.material_override = core_mat
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_visual.add_child(core)

	var shell := MeshInstance3D.new()
	var shell_mesh := SphereMesh.new()
	shell_mesh.radius = 0.27
	shell_mesh.height = 0.54
	shell_mesh.radial_segments = 24
	shell_mesh.rings = 12
	shell.mesh = shell_mesh
	_shell_mat = ShaderMaterial.new()
	_shell_mat.shader = SHELL_SHADER
	_shell_mat.set_shader_parameter("intensity", 2.0)
	_shell_mat.set_shader_parameter("rise", 0.12)
	shell.material_override = _shell_mat
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shell.extra_cull_margin = 2.0
	_visual.add_child(shell)

	var halo := MeshInstance3D.new()
	halo.mesh = FX.quad(Vector2(1.3, 1.3), FX.fx_mat(FX.soft_tex(0.12), true, Color(1, 0.35, 0.04, 0.55), BaseMaterial3D.BILLBOARD_ENABLED))
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_visual.add_child(halo)

	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.48, 0.14)
	_light.light_energy = 2.2
	_light.omni_range = 6.0
	_light.shadow_enabled = false
	_visual.add_child(_light)

	_build_tail("FlameTongues", 60, 0.38, "flame")
	_build_tail("Sparks", 20, 0.8, "spark")
	_build_tail("ThinSmoke", 14, 1.25, "smoke")

func _tail_mat(style: String) -> ParticleProcessMaterial:
	var key := "bolt_tail_pm_" + style
	if FX.has(key):
		return FX.get_res(key)
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = 0.14
	m.direction = Vector3.ZERO
	m.spread = 180.0
	m.angle_min = -180.0
	m.angle_max = 180.0
	match style:
		"flame":
			m.initial_velocity_min = 0.1
			m.initial_velocity_max = 0.8
			m.gravity = Vector3(0, 1.8, 0)
			m.damping_min = 1.0
			m.damping_max = 2.5
			m.scale_min = 0.5
			m.scale_max = 1.0
			m.scale_curve = FX.curve([Vector2(0, 0.3), Vector2(0.25, 1), Vector2(1, 0)], 1.0)
			m.color_ramp = FX.ramp([0.0, 0.2, 0.65, 1.0], [Color(3.2, 2.3, 1.2), Color(2.3, 0.8, 0.16), Color(1, 0.12, 0.01, 0.5), Color(0.2, 0, 0, 0)])
		"spark":
			m.initial_velocity_min = 0.8
			m.initial_velocity_max = 3.2
			m.gravity = Vector3(0, -4, 0)
			m.scale_curve = FX.curve([Vector2(0, 1), Vector2(1, 0)], 1.0)
			m.color_ramp = FX.ramp([0.0, 0.6, 1.0], [Color(3, 2, 0.6), Color(1, 0.25, 0.02), Color(0.4, 0.01, 0, 0)])
		"smoke":
			m.initial_velocity_min = 0.1
			m.initial_velocity_max = 0.7
			m.gravity = Vector3(0, 0.8, 0)
			m.damping_min = 0.5
			m.damping_max = 1.2
			m.scale_min = 0.45
			m.scale_max = 0.9
			m.scale_curve = FX.curve([Vector2(0, 0.3), Vector2(1, 1.4)], 1.5)
			m.color_ramp = FX.ramp([0.0, 0.25, 1.0], [Color(0.2, 0.14, 0.1, 0), Color(0.22, 0.16, 0.12, 0.28), Color(0.3, 0.28, 0.26, 0)])
	return FX.put(key, m)

func _build_tail(pname: String, amount: int, lifetime: float, style: String) -> void:
	var p := FX.particles(pname, maxi(4, int(round(amount * fx))), lifetime)
	p.fixed_fps = 60
	p.interpolate = true
	p.randomness = 0.4
	p.process_material = _tail_mat(style)
	var size := Vector2(0.4, 0.4)
	var additive := style != "smoke"
	if style == "spark":
		size = Vector2(0.045, 0.16)
	elif style == "smoke":
		size = Vector2(0.5, 0.5)
	p.draw_pass_1 = FX.quad(size, FX.fx_mat(FX.soft_tex(0.12), additive, Color.WHITE))
	add_child(p)

func _explode(at: Vector3, explosion_kind: String) -> void:
	if _dead:
		return
	_dead = true
	var boom := EXPLOSION.new()
	boom.kind = explosion_kind
	boom.fx = fx
	var host := get_parent()
	if host:
		host.add_child(boom)
		boom.global_position = at + (Vector3(0, 0.025, 0) if explosion_kind == "impact" else Vector3.ZERO)
	if shake_target and shake_target.has_method("add_shake"):
		var distance := shake_target.global_position.distance_to(at)
		shake_target.add_shake(0.55 * clampf(1.0 - distance / 32.0, 0.15, 1.0))
	_visual.visible = false
	_light.visible = false
	for child in get_children():
		if child is GPUParticles3D:
			child.emitting = false
	get_tree().create_timer(1.0).timeout.connect(queue_free)
