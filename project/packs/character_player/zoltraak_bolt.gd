extends Node3D
## Laser besar "Zoltraak" (ala Frieren) yang dilepaskan setelah menahan
## serang penuh: bukan lagi proyektil yang terbang pelan, melainkan berkas
## instan sepanjang lintasannya (berhenti di dinding/tanah, tembus musuh)
## yang tampil selama BEAM_LIFETIME lalu lenyap. Visual: tabung inti putih->
## biru pudar + aura biru polos di sekelilingnya, sama-sama meliuk pelan lalu
## "glitch" digital (offset tersentak-sentak) di sepanjang lintasan.

const FX := preload("res://packs/character_player/fire_fx.gd")
const SHOCK_SHADER := preload("res://packs/character_player/shockwave.gdshader")
const CORE_SHADER := preload("res://packs/character_player/zoltraak_core.gdshader")
const AURA_SHADER := preload("res://packs/character_player/zoltraak_aura.gdshader")

const BEAM_LIFETIME := 2.0     # detik tampil penuh sebelum lenyap (permintaan user)
const FADE_OUT_TIME := 0.22
const MAX_RANGE := 30.0
const PIERCE_ITERATIONS := 14  # batas loop "tembus musuh" saat mencari titik henti dinding
const PIERCE_NUDGE := 0.55     # maju sedikit lewat musuh supaya tidak nyangkut di collider yang sama
const BASE_DAMAGE := 40.0
const MAX_DAMAGE := 95.0
const BASE_HIT_RADIUS := 0.55
const MAX_HIT_RADIUS := 0.85

var fx := 1.0
var exclude_rids: Array[RID] = []
var shake_target: Node3D

var _dir := Vector3.FORWARD
var _right := Vector3.RIGHT
var _up := Vector3.UP
var _damage := 40.0
var _hit_radius := 0.6
var _wave_scale := 0.8
var _seed := 0.0
var _beam_length := 6.0
var _age := 0.0
var _dead := false
var _hit_monsters := {}
var _core: MeshInstance3D
var _aura: MeshInstance3D
var _core_mat: ShaderMaterial
var _aura_mat: ShaderMaterial
var _light: OmniLight3D
var _light_tip: OmniLight3D
var _mist_particles: GPUParticles3D

func setup(direction: Vector3, charge_fraction: float) -> void:
	var charge := clampf(charge_fraction, 0.0, 1.0)
	_dir = direction.normalized() if direction.length_squared() > 0.001 else Vector3.FORWARD
	_right = _dir.cross(Vector3.UP)
	if _right.length_squared() < 0.001:
		_right = Vector3.RIGHT
	_right = _right.normalized()
	_up = _right.cross(_dir).normalized()
	_damage = lerpf(BASE_DAMAGE, MAX_DAMAGE, charge)
	_hit_radius = lerpf(BASE_HIT_RADIUS, MAX_HIT_RADIUS, charge)
	_wave_scale = lerpf(0.7, 1.35, charge)

func _ready() -> void:
	fx = clampf(fx, 0.2, 1.0)

## WAJIB dipanggil oleh pemanggil (player.gd) SETELAH `global_position`
## di-set dan node sudah masuk scene tree, BUKAN dari `_ready()` sendiri.
## `_ready()` jalan SINKRON di tengah `add_child()`, yaitu SEBELUM baris
## `bolt.global_position = ...` yang menyusul di player.gd -- kalau raycast/
## damage/bentuk visual dihitung di `_ready()` langsung, semuanya memakai
## posisi lama (0,0,0) karena posisi asli belum sempat di-set (insiden
## ronde-44: laser instan sekali-hitung ini beda dari fire_bolt.gd yang aman
## karena bergerak bertahap per-frame, bukan menghitung semuanya di awal).
func activate() -> void:
	_seed = randf() * 100.0
	_resolve_beam_and_damage()
	_build_visual()
	if shake_target and shake_target.has_method("add_shake"):
		shake_target.add_shake(0.35 + 0.35 * (_wave_scale - 0.7) / 0.65)

func _process(delta: float) -> void:
	if _dead:
		return
	delta = minf(delta, 0.1)
	_age += delta
	var flicker := 0.9 + 0.1 * sin(_age * 33.0)
	if is_instance_valid(_light):
		_light.light_energy = 3.4 * _wave_scale * flicker
	if is_instance_valid(_light_tip):
		_light_tip.light_energy = 2.2 * _wave_scale * flicker
	if _age >= BEAM_LIFETIME:
		_dissolve()

## Mencari titik henti berkas (tembok/tanah), tembus musuh di sepanjang jalur,
## dan mendamage semua musuh yang kena — dilakukan SEKALI saat spawn karena
## laser tampil instan sepanjang lintasannya (bukan proyektil bertahap).
func _resolve_beam_and_damage() -> void:
	var space_state := get_world_3d().direct_space_state
	var origin := global_position
	var stop_dist := MAX_RANGE
	var cursor := origin
	var q := PhysicsRayQueryParameters3D.create(origin, origin + _dir * MAX_RANGE)
	q.exclude = exclude_rids.duplicate()
	q.collide_with_areas = true
	q.collide_with_bodies = true
	for _i in PIERCE_ITERATIONS:
		q.from = cursor
		q.to = origin + _dir * MAX_RANGE
		var hit := space_state.intersect_ray(q)
		if hit.is_empty():
			break
		var collider = hit.get("collider")
		var pos: Vector3 = hit.get("position", q.to)
		if collider and collider.has_meta("monster"):
			_damage_monster(collider, pos)
			cursor = pos + _dir * PIERCE_NUDGE
			continue
		stop_dist = origin.distance_to(pos)
		break
	_beam_length = clampf(stop_dist, 1.2, MAX_RANGE)
	# Sapuan lebar (laser BESAR, bukan garis tipis) supaya musuh yang berdiri
	# agak menyamping dari garis tengah tetap kena.
	var box := BoxShape3D.new()
	box.size = Vector3(_hit_radius * 2.0, _hit_radius * 2.0, _beam_length)
	var xform := Transform3D(Basis(_right, _up, _dir), origin + _dir * _beam_length * 0.5)
	var sq := PhysicsShapeQueryParameters3D.new()
	sq.shape = box
	sq.transform = xform
	sq.exclude = exclude_rids.duplicate()
	sq.collide_with_areas = true
	sq.collide_with_bodies = true
	for res in space_state.intersect_shape(sq, 24):
		var collider = res.get("collider")
		if collider and collider.has_meta("monster"):
			_damage_monster(collider, collider.global_position if collider is Node3D else origin)

func _damage_monster(collider: Object, at: Vector3) -> void:
	var target = collider.get_meta("monster")
	if not is_instance_valid(target) or not target.has_method("take_damage"):
		return
	# WAJIB tipe eksplisit (bukan `:=`): `target` tidak bertipe statis (Variant
	# dari get_meta) -> analyzer Godot 4.5 gagal keras dengan "Cannot infer the
	# type of id variable" (insiden ronde-43).
	var id: int = target.get_instance_id()
	if _hit_monsters.has(id):
		return
	_hit_monsters[id] = true
	target.take_damage(_damage)
	_spawn_hit_spark(at)

func _build_visual() -> void:
	_core = MeshInstance3D.new()
	var core_mesh := CylinderMesh.new()
	core_mesh.top_radius = 0.16 * _wave_scale
	core_mesh.bottom_radius = 0.16 * _wave_scale
	core_mesh.height = _beam_length
	core_mesh.radial_segments = 10
	core_mesh.rings = clampi(int(_beam_length * 3.0), 6, 48)
	_core.mesh = core_mesh
	_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_core.extra_cull_margin = 2.0
	_core_mat = ShaderMaterial.new()
	_core_mat.shader = CORE_SHADER
	_core_mat.set_shader_parameter("beam_length", _beam_length)
	_core_mat.set_shader_parameter("seed", _seed)
	_core_mat.set_shader_parameter("intensity", 3.2)
	_core.material_override = _core_mat
	_orient_along_dir(_core, _beam_length * 0.5)
	add_child(_core)

	_aura = MeshInstance3D.new()
	var aura_mesh := CylinderMesh.new()
	aura_mesh.top_radius = 0.42 * _wave_scale
	aura_mesh.bottom_radius = 0.42 * _wave_scale
	aura_mesh.height = _beam_length
	aura_mesh.radial_segments = 8
	aura_mesh.rings = core_mesh.rings
	_aura.mesh = aura_mesh
	_aura.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_aura.extra_cull_margin = 2.0
	_aura_mat = ShaderMaterial.new()
	_aura_mat.shader = AURA_SHADER
	_aura_mat.set_shader_parameter("beam_length", _beam_length)
	_aura_mat.set_shader_parameter("seed", _seed)
	_aura_mat.set_shader_parameter("intensity", 1.5)
	_aura.material_override = _aura_mat
	_orient_along_dir(_aura, _beam_length * 0.5)
	add_child(_aura)


	_light = OmniLight3D.new()
	_light.light_color = Color(0.65, 0.85, 1.0)
	_light.light_energy = 3.4
	_light.omni_range = 6.0 * _wave_scale
	_light.shadow_enabled = false
	_light.position = _dir * minf(_beam_length * 0.3, 3.0)
	add_child(_light)

	_light_tip = OmniLight3D.new()
	_light_tip.light_color = Color(0.85, 0.95, 1.0)
	_light_tip.light_energy = 2.2
	_light_tip.omni_range = 5.0 * _wave_scale
	_light_tip.shadow_enabled = false
	_light_tip.position = _dir * _beam_length
	add_child(_light_tip)

	_mist_particles = FX.particles("ZoltraakMist", maxi(8, int(round(26 * fx))), BEAM_LIFETIME + FADE_OUT_TIME)
	_mist_particles.fixed_fps = 60
	_mist_particles.interpolate = true
	_mist_particles.randomness = 0.5
	var pm := ParticleProcessMaterial.new()
	# Bola sederhana (bukan kotak diputar) di tengah berkas -- efek kabut
	# hiasan saja, tidak perlu presisi mengikuti seluruh panjang laser.
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.4 * _wave_scale
	pm.direction = Vector3.UP
	pm.spread = 60.0
	pm.initial_velocity_min = 0.4
	pm.initial_velocity_max = 1.6
	pm.gravity = Vector3(0, 0.1, 0)
	pm.damping_min = 1.0
	pm.damping_max = 2.2
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 2.0
	pm.turbulence_noise_scale = 2.4
	pm.turbulence_influence_min = 0.35
	pm.turbulence_influence_max = 0.7
	pm.scale_min = 0.45
	pm.scale_max = 1.0
	pm.scale_curve = FX.curve([Vector2(0, 0.4), Vector2(0.3, 1), Vector2(1, 0)], 1.0)
	pm.color_ramp = FX.ramp([0.0, 0.25, 0.7, 1.0], [Color(2.2, 2.4, 3.0), Color(0.6, 0.85, 1.4), Color(0.15, 0.35, 0.9, 0.35), Color(0.02, 0.08, 0.3, 0.0)])
	_mist_particles.process_material = pm
	_mist_particles.draw_pass_1 = FX.quad(Vector2(0.28, 0.28) * _wave_scale, FX.fx_mat(FX.soft_tex(0.12), true, Color.WHITE))
	_mist_particles.position = _dir * _beam_length * 0.5
	add_child(_mist_particles)

## CylinderMesh Godot memanjang di sumbu Y lokal -> putar node supaya +Y
## sejajar arah tembak, lalu geser sejauh `forward_offset` KE ARAH TEMBAK
## (posisi Transform3D selalu dalam ruang induk/dunia, TIDAK ikut terputar
## oleh basis-nya sendiri -- kalau dibiarkan Vector3(0, x, 0) mesh akan
## menjulur ke sumbu-Y DUNIA, bukan ke arah tembak). WAJIB assign Transform3D
## utuh, bukan chain "node.transform.basis = ..." (insiden Ronde-38/43:
## analyzer statis Godot 4.5 menolak beberapa pola chained-property-of-
## property pada Node).
func _orient_along_dir(node: Node3D, forward_offset: float) -> void:
	var basis := Basis(_right, _dir, _up)
	node.transform = Transform3D(basis, _dir * forward_offset)

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

func _dissolve() -> void:
	if _dead:
		return
	_dead = true
	_spawn_splash(global_position + _dir * _beam_length)
	if is_instance_valid(_mist_particles):
		_mist_particles.emitting = false
	if is_instance_valid(_light):
		_light.visible = false
	if is_instance_valid(_light_tip):
		_light_tip.visible = false
	var tween := create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if is_instance_valid(_core):
		tween.tween_property(_core, "scale", Vector3(0.15, 1.0, 0.15), FADE_OUT_TIME)
	if is_instance_valid(_aura):
		tween.tween_property(_aura, "scale", Vector3(0.15, 1.0, 0.15), FADE_OUT_TIME)
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
	ring.scale = Vector3.ONE * 5.0 * _wave_scale
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
