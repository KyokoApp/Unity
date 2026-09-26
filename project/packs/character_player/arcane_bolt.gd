extends Node3D
## Peluru sihir kecil (tap attack) — proyektil balistik (gravitasi + raycast
## per-frame) yang meledak kena apa pun yang solid: tanah, atau
## dinding/reruntuhan (ronde-44, meta "wall"). Bertema kristal arcane
## ungu-biru, bukan lagi selongsong peluru tank (ronde-45, dihapus) maupun
## mana biru murni ronde awal. Mantra andalan yang jauh lebih megah (ronde-46
## bag. B) akan jadi node terpisah, bukan proyektil kecil ini.

const FX := preload("res://packs/character_player/fire_fx.gd")
const EXPLOSION := preload("res://packs/character_player/fire_explosion.gd")
const CORE_SHADER := preload("res://packs/character_player/fireball_core.gdshader")
const SHELL_SHADER := preload("res://packs/character_player/fireball_shell.gdshader")

var vel := Vector3.ZERO
var fx := 1.0
var exclude_rids: Array[RID] = []
# WAJIB Node3D (bukan Node): analizer Godot 4.5 tidak bisa meng-infer tipe
# `var distance := shake_target.global_position…` bila statis bertipe Node
# (insiden ronde-38, masih relevan lintas-ronde).
var shake_target: Node3D
var damage := 26.0

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
	vel.y -= 6.0 * delta
	var to := from + vel * delta
	var hit := get_world_3d().direct_space_state.intersect_ray(_ray(from, to))
	if not hit.is_empty():
		var collider = hit.get("collider")
		if collider and collider.has_meta("wall"):
			# Dinding/reruntuhan (ronde-44) tetap bisa dihancurkan peluru sihir.
			var wall = collider.get_meta("wall")
			if is_instance_valid(wall) and wall.has_method("take_damage"):
				wall.take_damage(damage)
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
	_light.light_energy = 1.5 * (0.9 + 0.08 * sin(_age * 31.0) + 0.05 * sin(_age * 53.0))
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
	core_mesh.radius = 0.065
	core_mesh.height = 0.13
	core_mesh.radial_segments = 14
	core_mesh.rings = 7
	core.mesh = core_mesh
	var core_key := "bolt_core_mat"
	var core_mat: ShaderMaterial
	if FX.has(core_key):
		core_mat = FX.get_res(core_key)
	else:
		core_mat = ShaderMaterial.new()
		core_mat.shader = CORE_SHADER
		core_mat.set_shader_parameter("intensity", 2.6)
		core_mat.set_shader_parameter("turbulence", 0.9)
		FX.put(core_key, core_mat)
	core.material_override = core_mat
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_visual.add_child(core)

	var shell := MeshInstance3D.new()
	var shell_mesh := SphereMesh.new()
	shell_mesh.radius = 0.11
	shell_mesh.height = 0.22
	shell_mesh.radial_segments = 18
	shell_mesh.rings = 9
	shell.mesh = shell_mesh
	_shell_mat = ShaderMaterial.new()
	_shell_mat.shader = SHELL_SHADER
	_shell_mat.set_shader_parameter("intensity", 1.5)
	_shell_mat.set_shader_parameter("rise", 0.04)
	shell.material_override = _shell_mat
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shell.extra_cull_margin = 2.0
	_visual.add_child(shell)

	var halo := MeshInstance3D.new()
	halo.mesh = FX.quad(Vector2(0.45, 0.45), FX.fx_mat(FX.soft_tex(0.12), true, Color(0.55, 0.35, 1.0, 0.55), BaseMaterial3D.BILLBOARD_ENABLED))
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_visual.add_child(halo)

	_light = OmniLight3D.new()
	_light.light_color = Color(0.55, 0.40, 1.0)
	_light.light_energy = 1.5
	_light.omni_range = 4.5
	_light.shadow_enabled = false
	_visual.add_child(_light)

	_build_tail("BoltSparks", 16, 0.32, "spark")
	_build_tail("BoltMist", 7, 0.75, "mist")

func _tail_mat(style: String) -> ParticleProcessMaterial:
	var key := "bolt_tail_pm_" + style
	if FX.has(key):
		return FX.get_res(key)
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = 0.06
	m.direction = Vector3.ZERO
	m.spread = 180.0
	m.angle_min = -180.0
	m.angle_max = 180.0
	match style:
		"spark":
			m.initial_velocity_min = 0.4
			m.initial_velocity_max = 1.5
			m.gravity = Vector3(0, -1.2, 0)
			m.scale_curve = FX.curve([Vector2(0, 1), Vector2(1, 0)], 1.0)
			m.color_ramp = FX.ramp([0.0, 0.5, 1.0], [Color(2.2, 1.6, 3.2), Color(0.6, 0.35, 1.0), Color(0.15, 0.25, 0.5, 0.0)])
		"mist":
			m.initial_velocity_min = 0.05
			m.initial_velocity_max = 0.30
			m.gravity = Vector3(0, 0.25, 0)
			m.damping_min = 0.5
			m.damping_max = 1.1
			m.scale_min = 0.3
			m.scale_max = 0.6
			m.scale_curve = FX.curve([Vector2(0, 0.3), Vector2(1, 1.2)], 1.4)
			m.color_ramp = FX.ramp([0.0, 0.25, 1.0], [Color(0.4, 0.32, 0.6, 0), Color(0.45, 0.35, 0.65, 0.28), Color(0.5, 0.4, 0.7, 0)])
	return FX.put(key, m)

func _build_tail(pname: String, amount: int, lifetime: float, style: String) -> void:
	var p := FX.particles(pname, maxi(4, int(round(amount * fx))), lifetime)
	p.fixed_fps = 60
	p.interpolate = true
	p.randomness = 0.4
	p.process_material = _tail_mat(style)
	var size := Vector2(0.14, 0.14)
	var additive := style != "mist"
	if style == "spark":
		size = Vector2(0.03, 0.09)
	elif style == "mist":
		size = Vector2(0.20, 0.20)
	p.draw_pass_1 = FX.quad(size, FX.fx_mat(FX.soft_tex(0.12), additive, Color.WHITE))
	add_child(p)

func _explode(at: Vector3, explosion_kind: String) -> void:
	if _dead:
		return
	_dead = true
	var boom := EXPLOSION.new()
	boom.kind = explosion_kind
	boom.fx = fx
	boom.dir = vel.normalized() if vel.length_squared() > 0.01 else Vector3.UP
	var host := get_parent()
	if host:
		host.add_child(boom)
		boom.global_position = at + (Vector3(0, 0.025, 0) if explosion_kind == "impact" else Vector3.ZERO)
	if shake_target and shake_target.has_method("add_shake"):
		var distance := shake_target.global_position.distance_to(at)
		shake_target.add_shake(0.3 * clampf(1.0 - distance / 30.0, 0.15, 1.0))
	_visual.visible = false
	_light.visible = false
	for child in get_children():
		if child is GPUParticles3D:
			child.emitting = false
	get_tree().create_timer(1.0).timeout.connect(queue_free)
