extends Node3D
## Tembakan besar "Zoltraak" yang dilepaskan setelah menahan serang penuh.
## Visualnya untaian segmen yang meliuk seperti gelombang air mengalir,
## putih di kepala bercampur biru tipis di buntut, dan bisa menembus
## beberapa musuh sekaligus di jalur lintasannya (bukan meledak sekali kena).

const FX := preload("res://packs/character_player/fire_fx.gd")
const SHOCK_SHADER := preload("res://packs/character_player/shockwave.gdshader")

const SEGMENT_COUNT := 7
const SEGMENT_SPACING := 0.30
const WAVE_FREQ := 11.0
const WAVE_AMPLITUDE := 0.30
const MAX_LIFETIME := 1.7
const MAX_RANGE := 34.0
const BASE_DAMAGE := 40.0
const MAX_DAMAGE := 95.0
const BASE_SPEED := 17.0
const MAX_SPEED := 25.0

var fx := 1.0
var exclude_rids: Array[RID] = []
var shake_target: Node3D

var _dir := Vector3.FORWARD
var _right := Vector3.RIGHT
var _up := Vector3.UP
var _speed := 20.0
var _damage := 40.0
var _wave_scale := 0.8
var _age := 0.0
var _distance := 0.0
var _dead := false
var _hit_monsters := {}
var _segments: Array[MeshInstance3D] = []
var _segment_mats: Array[StandardMaterial3D] = []
var _light: OmniLight3D
var _trail_particles: GPUParticles3D

func setup(direction: Vector3, charge_fraction: float) -> void:
	var charge := clampf(charge_fraction, 0.0, 1.0)
	_dir = direction.normalized() if direction.length_squared() > 0.001 else Vector3.FORWARD
	_right = _dir.cross(Vector3.UP)
	if _right.length_squared() < 0.001:
		_right = Vector3.RIGHT
	_right = _right.normalized()
	_up = _right.cross(_dir).normalized()
	_speed = lerpf(BASE_SPEED, MAX_SPEED, charge)
	_damage = lerpf(BASE_DAMAGE, MAX_DAMAGE, charge)
	_wave_scale = lerpf(0.55, 1.25, charge)

func _ready() -> void:
	fx = clampf(fx, 0.2, 1.0)
	_build_visual()

func _process(delta: float) -> void:
	if _dead:
		return
	delta = minf(delta, 0.1)
	_age += delta
	var step := _speed * delta
	var from := global_position
	var to := from + _dir * step
	var hit := get_world_3d().direct_space_state.intersect_ray(_ray(from, to))
	if not hit.is_empty():
		var collider = hit.get("collider")
		if collider and collider.has_meta("monster"):
			var target = collider.get_meta("monster")
			if is_instance_valid(target) and target.has_method("take_damage"):
				var id := target.get_instance_id()
				if not _hit_monsters.has(id):
					_hit_monsters[id] = true
					target.take_damage(_damage)
					_spawn_hit_spark(hit.get("position", to))
			# sengaja TIDAK berhenti: Zoltraak menembus musuh, bukan meledak sekali kena.
		else:
			_dissolve(hit.get("position", to), true)
			return
	global_position = to
	_distance += step
	_update_wave_shape()
	_light.light_energy = 3.4 * _wave_scale * (0.92 + 0.08 * sin(_age * 40.0))
	if _age >= MAX_LIFETIME or _distance >= MAX_RANGE or to.y < -2.0:
		_dissolve(global_position, false)

func _ray(from: Vector3, to: Vector3) -> PhysicsRayQueryParameters3D:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = exclude_rids
	q.collide_with_areas = true
	q.collide_with_bodies = true
	return q

func _build_visual() -> void:
	for i in SEGMENT_COUNT:
		var seg := MeshInstance3D.new()
		var mesh := CapsuleMesh.new()
		var t := float(i) / float(SEGMENT_COUNT - 1)
		mesh.radius = lerpf(0.30, 0.10, t) * _wave_scale
		mesh.height = lerpf(0.62, 0.30, t) * _wave_scale
		mesh.radial_segments = 14
		mesh.rings = 6
		seg.mesh = mesh
		seg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		seg.extra_cull_margin = 2.0
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.albedo_color = Color(1, 1, 1, 1).lerp(Color(0.45, 0.72, 1.0, 0.0), t) 
		mat.albedo_color.a = lerpf(0.95, 0.10, t)
		mat.disable_receive_shadows = true
		mat.no_depth_test = false
		seg.material_override = mat
		# capsule Godot memanjang di sumbu Y lokal -> putar agar sejajar arah gerak.
		seg.transform.basis = Basis(_right, _dir, _up)
		add_child(seg)
		_segments.append(seg)
		_segment_mats.append(mat)

	_light = OmniLight3D.new()
	_light.light_color = Color(0.65, 0.85, 1.0)
	_light.light_energy = 3.0
	_light.omni_range = 6.5
	_light.shadow_enabled = false
	add_child(_light)

	_trail_particles = FX.particles("ZoltraakMist", maxi(6, int(round(28 * fx))), 0.55)
	_trail_particles.fixed_fps = 60
	_trail_particles.interpolate = true
	_trail_particles.randomness = 0.4
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.22 * _wave_scale
	pm.direction = -_dir
	pm.spread = 22.0
	pm.initial_velocity_min = 0.6
	pm.initial_velocity_max = 2.2
	pm.gravity = Vector3(0, 0.15, 0)
	pm.damping_min = 1.2
	pm.damping_max = 2.6
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 2.2
	pm.turbulence_noise_scale = 2.6
	pm.turbulence_influence_min = 0.35
	pm.turbulence_influence_max = 0.75
	pm.scale_min = 0.5
	pm.scale_max = 1.05
	pm.scale_curve = FX.curve([Vector2(0, 0.4), Vector2(0.3, 1), Vector2(1, 0)], 1.0)
	pm.color_ramp = FX.ramp([0.0, 0.25, 0.7, 1.0], [Color(2.2, 2.4, 3.0), Color(0.6, 0.85, 1.4), Color(0.15, 0.35, 0.9, 0.35), Color(0.02, 0.08, 0.3, 0.0)])
	_trail_particles.process_material = pm
	_trail_particles.draw_pass_1 = FX.quad(Vector2(0.30, 0.30) * _wave_scale, FX.fx_mat(FX.soft_tex(0.12), true, Color.WHITE))
	add_child(_trail_particles)

func _update_wave_shape() -> void:
	for i in _segments.size():
		var seg := _segments[i]
		var back := float(i) * SEGMENT_SPACING * _wave_scale
		var phase := float(i) * 0.85
		var lateral_h := sin(_age * WAVE_FREQ - phase) * WAVE_AMPLITUDE * _wave_scale
		var lateral_v := cos(_age * WAVE_FREQ * 0.75 - phase) * WAVE_AMPLITUDE * 0.55 * _wave_scale
		seg.position = -_dir * back + _right * lateral_h + _up * lateral_v

func _spawn_hit_spark(at: Vector3) -> void:
	var spark := FX.particles("ZoltraakHit", maxi(4, int(round(10 * fx))), 0.35)
	spark.one_shot = true
	spark.explosiveness = 1.0
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = 180.0
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.initial_velocity_min = 1.5
	pm.initial_velocity_max = 4.0
	pm.gravity = Vector3(0, -3.0, 0)
	pm.scale_curve = FX.curve([Vector2(0, 1), Vector2(1, 0)], 1.0)
	pm.color_ramp = FX.ramp([0.0, 0.5, 1.0], [Color(2.2, 2.4, 3.0), Color(0.35, 0.65, 1.0), Color(0.05, 0.15, 0.5, 0)])
	spark.process_material = pm
	spark.draw_pass_1 = FX.quad(Vector2(0.10, 0.10), FX.fx_mat(FX.soft_tex(0.15), true, Color.WHITE))
	var host := get_parent()
	if host == null:
		return
	host.add_child(spark)
	spark.global_position = at
	spark.emitting = true
	get_tree().create_timer(0.6).timeout.connect(spark.queue_free)

func _dissolve(at: Vector3, splash: bool) -> void:
	if _dead:
		return
	_dead = true
	if shake_target and shake_target.has_method("add_shake"):
		var distance := shake_target.global_position.distance_to(at)
		shake_target.add_shake(0.5 * clampf(1.0 - distance / 32.0, 0.15, 1.0))
	if splash:
		_spawn_splash(at)
	_trail_particles.emitting = false
	_light.visible = false
	var tween := create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	for mat in _segment_mats:
		tween.tween_property(mat, "albedo_color:a", 0.0, 0.28)
	tween.chain().tween_callback(queue_free)

func _spawn_splash(at: Vector3) -> void:
	var host := get_parent()
	if host == null:
		return
	var ring := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE
	ring.mesh = plane
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.scale = Vector3.ONE * 6.0 * _wave_scale
	var mat := ShaderMaterial.new()
	mat.shader = SHOCK_SHADER
	mat.set_shader_parameter("progress", 0.0)
	mat.set_shader_parameter("tint", Color(0.55, 0.8, 1.0, 1.0))
	mat.set_shader_parameter("energy", 2.4)
	ring.material_override = mat
	host.add_child(ring)
	ring.global_position = at + Vector3(0, 0.03, 0)
	var tw := create_tween()
	tw.tween_property(mat, "shader_parameter/progress", 1.0, 0.5)
	tw.tween_callback(ring.queue_free)
