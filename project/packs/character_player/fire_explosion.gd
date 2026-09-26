extends Node3D
## Ledakan prosedural mana biru untuk impact, ledakan di udara, dan muzzle flash.

const FX := preload("res://packs/character_player/fire_fx.gd")
const SHELL_SHADER := preload("res://packs/character_player/fireball_shell.gdshader")
const SHOCK_SHADER := preload("res://packs/character_player/shockwave.gdshader")
const EXPLODE_SFX := "res://packs/audio_sfx/fire_explode.wav"

var kind := "impact"
var fx := 1.0
var dir := Vector3.FORWARD

func _ready() -> void:
	fx = clampf(fx, 0.2, 1.0)
	if kind == "muzzle":
		_build_flash(3.0, 2.2, 0.12)
		_build_muzzle()
		get_tree().create_timer(1.0).timeout.connect(queue_free)
		return
	_build_flash(8.0, 6.0, 0.4)
	_build_fireball()
	_build_burst("Mana", 22, 0.9, "fire")
	_build_burst("Sparks", 26, 1.05, "sparks")
	_build_burst("Motes", 12, 1.8, "embers")
	_build_burst("Mist", 8, 2.6, "smoke")
	if kind == "impact":
		_build_impact_marks()
	_play_sound()
	get_tree().create_timer(3.6).timeout.connect(queue_free)

func _build_flash(light_range: float, energy: float, duration: float) -> void:
	var light := OmniLight3D.new()
	light.light_color = Color(0.35, 0.55, 1.0)
	light.omni_range = light_range
	light.light_energy = energy
	light.shadow_enabled = false
	add_child(light)
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(light, "light_energy", 0.0, duration)
	tw.tween_callback(light.queue_free)

func _build_fireball() -> void:
	var ball := MeshInstance3D.new()
	ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 22
	sphere.rings = 11
	ball.mesh = sphere
	var mat := ShaderMaterial.new()
	mat.shader = SHELL_SHADER
	mat.set_shader_parameter("intensity", 2.6)
	mat.set_shader_parameter("rise", 0.5)
	mat.set_shader_parameter("alpha_scale", 1.0)
	ball.material_override = mat
	ball.scale = Vector3.ONE * 0.35
	ball.extra_cull_margin = 3.0
	add_child(ball)
	var tw := create_tween().set_parallel(true)
	tw.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(ball, "scale", Vector3.ONE * 2.0, 0.32)
	tw.tween_property(ball, "position:y", 0.55, 0.45)
	tw.tween_property(mat, "shader_parameter/alpha_scale", 0.0, 0.45)
	tw.chain().tween_callback(ball.queue_free)

func _process_mat(style: String) -> ParticleProcessMaterial:
	var key := "mana_explosion_pm_" + style
	if FX.has(key):
		return FX.get_res(key)
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = 0.16
	m.angle_min = -180.0
	m.angle_max = 180.0
	m.angular_velocity_min = -110.0
	m.angular_velocity_max = 110.0
	match style:
		"fire":
			m.direction = Vector3.UP
			m.spread = 85.0
			m.initial_velocity_min = 2.2
			m.initial_velocity_max = 5.5
			m.damping_min = 5.0
			m.damping_max = 8.0
			m.scale_min = 0.5
			m.scale_max = 0.95
			m.scale_curve = FX.curve([Vector2(0, 0.35), Vector2(0.2, 1), Vector2(1, 0)], 1.0)
			m.color_ramp = FX.ramp([0.0, 0.08, 0.28, 0.65, 1.0], [Color.WHITE, Color(0.75, 0.9, 1.0), Color(0.25, 0.55, 1.0), Color(0.06, 0.16, 0.55), Color(0.0, 0.02, 0.15, 0)])
		"sparks":
			m.direction = Vector3.UP
			m.spread = 88.0
			m.initial_velocity_min = 4.5
			m.initial_velocity_max = 9.5
			m.gravity = Vector3(0, -10, 0)
			m.scale_min = 0.4
			m.scale_max = 1.05
			m.scale_curve = FX.curve([Vector2(0, 1), Vector2(1, 0)], 1.0)
			m.color_ramp = FX.ramp([0.0, 0.45, 1.0], [Color(2.0, 2.3, 3.0), Color(0.3, 0.6, 1.0), Color(0.05, 0.15, 0.5, 0)])
		"embers":
			m.direction = Vector3.UP
			m.spread = 90.0
			m.initial_velocity_min = 0.8
			m.initial_velocity_max = 3.0
			m.gravity = Vector3(0, 0.6, 0)
			m.damping_min = 0.8
			m.damping_max = 1.8
			m.turbulence_enabled = true
			m.turbulence_noise_strength = 1.6
			m.turbulence_noise_scale = 2.0
			m.turbulence_influence_min = 0.2
			m.turbulence_influence_max = 0.55
			m.scale_curve = FX.curve([Vector2(0, 1), Vector2(1, 0)], 1.0)
			m.color_ramp = FX.ramp([0.0, 0.65, 1.0], [Color(1.6, 2.0, 3.0), Color(0.25, 0.5, 1.0), Color(0.02, 0.05, 0.25, 0)])
		"smoke":
			m.direction = Vector3.UP
			m.spread = 70.0
			m.initial_velocity_min = 0.6
			m.initial_velocity_max = 2.0
			m.gravity = Vector3(0, 1.0, 0)
			m.damping_min = 0.3
			m.damping_max = 0.9
			m.scale_min = 0.6
			m.scale_max = 1.1
			m.scale_curve = FX.curve([Vector2(0, 0.25), Vector2(0.35, 1), Vector2(1, 2.0)], 2.0)
			m.color_ramp = FX.ramp([0.0, 0.18, 0.7, 1.0], [Color(0.6, 0.78, 1.0, 0), Color(0.6, 0.78, 1.0, 0.32), Color(0.7, 0.85, 1.0, 0.14), Color(0.8, 0.9, 1.0, 0)])
	return FX.put(key, m)

func _build_burst(pname: String, amount: int, lifetime: float, style: String) -> void:
	var p := FX.particles(pname, maxi(4, int(round(amount * fx))), lifetime)
	p.one_shot = true
	p.explosiveness = 0.92
	p.randomness = 0.45
	p.process_material = _process_mat(style)
	var additive := style != "smoke"
	var size := Vector2(0.42, 0.42)
	if style == "sparks":
		size = Vector2(0.045, 0.2)
	elif style == "embers":
		size = Vector2(0.06, 0.06)
	elif style == "smoke":
		size = Vector2(0.7, 0.7)
	p.draw_pass_1 = FX.quad(size, FX.fx_mat(FX.soft_tex(0.12), additive, Color.WHITE))
	add_child(p)
	p.emitting = true

func _build_muzzle() -> void:
	var p := FX.particles("MuzzleSparks", maxi(4, int(round(8 * fx))), 0.32)
	p.one_shot = true
	p.explosiveness = 1.0
	var m := ParticleProcessMaterial.new()
	m.direction = dir.normalized()
	m.spread = 26.0
	m.initial_velocity_min = 3.0
	m.initial_velocity_max = 6.5
	m.damping_min = 5.0
	m.damping_max = 9.0
	m.scale_curve = FX.curve([Vector2(0, 1), Vector2(1, 0)], 1.0)
	m.color_ramp = FX.ramp([0.0, 0.5, 1.0], [Color(2.0, 2.3, 3.0), Color(0.3, 0.55, 1.0), Color(0.05, 0.1, 0.4, 0)])
	p.process_material = m
	p.draw_pass_1 = FX.quad(Vector2(0.05, 0.18), FX.fx_mat(FX.soft_tex(0.2), true, Color.WHITE))
	add_child(p)
	p.emitting = true

func _build_impact_marks() -> void:
	var ring := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE
	ring.mesh = plane
	ring.position.y = 0.035
	ring.scale = Vector3.ONE * 4.5
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ring_mat := ShaderMaterial.new()
	ring_mat.shader = SHOCK_SHADER
	ring_mat.set_shader_parameter("progress", 0.0)
	ring_mat.set_shader_parameter("tint", Color(0.3, 0.6, 1.0, 1.0))
	ring_mat.set_shader_parameter("energy", 2.2)
	ring.material_override = ring_mat
	add_child(ring)
	var ring_tw := create_tween()
	ring_tw.tween_property(ring_mat, "shader_parameter/progress", 1.0, 0.45)
	ring_tw.tween_callback(ring.queue_free)

	var glow := MeshInstance3D.new()
	var glow_plane := PlaneMesh.new()
	glow_plane.size = Vector2(2.2, 2.2)
	glow.mesh = glow_plane
	glow.position.y = 0.025
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glow.material_override = FX.fx_mat(FX.soft_tex(0.05), true, Color(0.3, 0.6, 1.0, 0.6), BaseMaterial3D.BILLBOARD_DISABLED)
	add_child(glow)
	var glow_tw := create_tween()
	glow_tw.tween_property(glow, "transparency", 1.0, 1.4)
	glow_tw.tween_callback(glow.queue_free)

func _play_sound() -> void:
	if not ResourceLoader.exists(EXPLODE_SFX):
		return
	var sound := AudioStreamPlayer3D.new()
	sound.stream = load(EXPLODE_SFX)
	sound.bus = "SFX"
	sound.unit_size = 9.0
	sound.pitch_scale = randf_range(1.05, 1.25)
	sound.finished.connect(sound.queue_free)
	add_child(sound)
	sound.play()
