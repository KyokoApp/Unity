extends Node3D
## Monster low-poly 3D yang ringan untuk Android.
##
## Roster dibuat dari primitive mesh native (tanpa addon/ketergantungan asset
## biner), lalu dianimasikan procedural: idle bob, jalan, sayap, dan serangan.
## Bentuk/material sengaja dipisah per bagian agar ronde berikutnya bisa
## mengganti bagian ini dengan GLB CC0 Quaternius tanpa mengubah spawner.

var kind := "slime"
var variant := 0
var max_health := 100.0
var health := 100.0
var move_speed := 1.4
var attack_damage := 5.0
var player: Node3D

var _visual: Node3D
var _legs: Array[Node3D] = []
var _wings: Array[Node3D] = []
var _parts: Array[Node3D] = []
var _t := 0.0
var _attack_cd := 0.0
var _hurt_flash := 0.0
var _body_color := Color(0.35, 0.72, 0.46)

func setup(spec: Dictionary, target: Node3D) -> void:
	kind = str(spec.get("kind", "slime"))
	variant = int(spec.get("variant", 0))
	max_health = float(spec.get("health", 100.0))
	health = max_health
	move_speed = float(spec.get("speed", 1.4))
	attack_damage = float(spec.get("damage", 5.0))
	_body_color = spec.get("color", _body_color)
	player = target

func _ready() -> void:
	_build_body()

func _process(delta: float) -> void:
	_t += minf(delta, 0.1)
	_attack_cd = maxf(0.0, _attack_cd - delta)
	_hurt_flash = maxf(0.0, _hurt_flash - delta * 5.0)
	var moving := false
	if is_instance_valid(player):
		var to_player := player.global_position - global_position
		to_player.y = 0.0
		var distance := to_player.length()
		if distance > 4.2 and distance < 30.0:
			var direction := to_player / maxf(distance, 0.001)
			global_position += direction * move_speed * delta
			global_position.y = 0.0
			rotation.y = lerp_angle(rotation.y, atan2(-direction.x, -direction.z), 1.0 - exp(-7.0 * delta))
			moving = true
		elif distance <= 4.2 and _attack_cd <= 0.0:
			_attack_cd = 1.25 + fmod(float(variant) * 0.17, 0.35)
			if player.has_method("take_damage"):
				player.take_damage(attack_damage)
			moving = false
	_animate(moving, delta)

func take_damage(amount: float) -> void:
	health = maxf(0.0, health - amount)
	_hurt_flash = 1.0
	if health <= 0.0:
		_die()

func _die() -> void:
	set_process(false)
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_property(self, "scale", Vector3(0.1, 0.1, 0.1), 0.28)
	tween.tween_callback(queue_free)

func _animate(moving: bool, delta: float) -> void:
	var phase := _t * (7.0 if moving else 2.4) + float(variant) * 0.73
	var bob := sin(phase) * (0.10 if moving else 0.045)
	_visual.position.y = 0.04 + bob
	if _hurt_flash > 0.0:
		_visual.scale = Vector3.ONE * (1.0 + sin(_hurt_flash * 26.0) * 0.035)
	else:
		_visual.scale = Vector3.ONE
	for i in _legs.size():
		var leg_phase := phase + (PI if i % 2 == 0 else 0.0)
		_legs[i].rotation.z = sin(leg_phase) * (0.32 if moving else 0.04)
		_legs[i].rotation.x = cos(leg_phase) * (0.18 if moving else 0.0)
	for i in _wings.size():
		_wings[i].rotation.z = sin(_t * 9.0 + float(i) * PI) * (0.38 if moving else 0.12)
	# material flash murah saat kena serang
	for part in _parts:
		var mesh_part := part as MeshInstance3D
		if mesh_part:
			var mat := mesh_part.material_override as StandardMaterial3D
			if mat:
				mat.emission_energy_multiplier = 1.0 + _hurt_flash * 2.0

func _build_body() -> void:
	_visual = Node3D.new()
	_visual.name = "MonsterVisual_%s_%02d" % [kind, variant]
	_visual.position.y = 0.04
	add_child(_visual)
	match kind:
		"golem":
			_build_golem()
		"bat":
			_build_bat()
		"mushroom":
			_build_mushroom()
		"crawler":
			_build_crawler()
		_:
			_build_slime()
	var hitbox := Area3D.new()
	hitbox.name = "MonsterHitbox"
	hitbox.collision_layer = 1
	hitbox.collision_mask = 0
	hitbox.monitoring = false
	hitbox.set_meta("monster", self)
	var hit_shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 1.15
	hit_shape.shape = sphere
	hit_shape.position = Vector3(0.0, 1.0, 0.0)
	hitbox.add_child(hit_shape)
	add_child(hitbox)

func _build_slime() -> void:
	_sphere(_visual, "SlimeBody", Vector3(0.95, 0.72, 0.95), Vector3(0, 0.72, 0), _body_color)
	_sphere(_visual, "EyeL", Vector3(0.13, 0.19, 0.08), Vector3(-0.22, 0.83, -0.42), Color(0.04, 0.05, 0.08))
	_sphere(_visual, "EyeR", Vector3(0.13, 0.19, 0.08), Vector3(0.22, 0.83, -0.42), Color(0.04, 0.05, 0.08))
	_box(_visual, "Mouth", Vector3(0.22, 0.045, 0.04), Vector3(0, 0.60, -0.46), Color(0.16, 0.06, 0.10))

func _build_golem() -> void:
	_box(_visual, "GolemBody", Vector3(1.15, 1.35, 0.95), Vector3(0, 0.82, 0), _body_color)
	_box(_visual, "GolemHead", Vector3(0.88, 0.64, 0.82), Vector3(0, 1.82, -0.02), _body_color.lightened(0.12))
	_box(_visual, "ArmL", Vector3(0.34, 1.02, 0.42), Vector3(-0.78, 0.82, 0), _body_color.darkened(0.12))
	_box(_visual, "ArmR", Vector3(0.34, 1.02, 0.42), Vector3(0.78, 0.82, 0), _body_color.darkened(0.12))
	_box(_visual, "EyeL", Vector3(0.16, 0.10, 0.06), Vector3(-0.20, 1.86, -0.43), Color(1.0, 0.55, 0.12))
	_box(_visual, "EyeR", Vector3(0.16, 0.10, 0.06), Vector3(0.20, 1.86, -0.43), Color(1.0, 0.55, 0.12))

func _build_bat() -> void:
	_sphere(_visual, "BatBody", Vector3(0.64, 0.88, 0.58), Vector3(0, 1.18, 0), _body_color)
	_sphere(_visual, "EyeL", Vector3(0.10, 0.13, 0.06), Vector3(-0.14, 1.32, -0.28), Color(1.0, 0.32, 0.24))
	_sphere(_visual, "EyeR", Vector3(0.10, 0.13, 0.06), Vector3(0.14, 1.32, -0.28), Color(1.0, 0.32, 0.24))
	var wing_l := _box(_visual, "WingL", Vector3(0.96, 0.08, 0.34), Vector3(-0.58, 1.20, 0.05), _body_color.darkened(0.18))
	wing_l.rotation.z = -0.18
	_wings.append(wing_l)
	var wing_r := _box(_visual, "WingR", Vector3(0.96, 0.08, 0.34), Vector3(0.58, 1.20, 0.05), _body_color.darkened(0.18))
	wing_r.rotation.z = 0.18
	_wings.append(wing_r)

func _build_mushroom() -> void:
	_cylinder(_visual, "Stem", 0.38, 0.95, Vector3(0, 0.62, 0), _body_color.lightened(0.28))
	_cylinder(_visual, "Cap", 0.82, 0.42, Vector3(0, 1.28, 0), _body_color)
	_sphere(_visual, "EyeL", Vector3(0.10, 0.15, 0.06), Vector3(-0.17, 0.72, -0.34), Color(0.08, 0.04, 0.10))
	_sphere(_visual, "EyeR", Vector3(0.10, 0.15, 0.06), Vector3(0.17, 0.72, -0.34), Color(0.08, 0.04, 0.10))

func _build_crawler() -> void:
	_box(_visual, "CrawlerBody", Vector3(0.92, 0.62, 1.25), Vector3(0, 0.66, 0), _body_color)
	_sphere(_visual, "Head", Vector3(0.58, 0.48, 0.58), Vector3(0, 0.94, -0.66), _body_color.lightened(0.1))
	_sphere(_visual, "EyeL", Vector3(0.10, 0.12, 0.06), Vector3(-0.16, 1.02, -0.94), Color(1.0, 0.78, 0.18))
	_sphere(_visual, "EyeR", Vector3(0.10, 0.12, 0.06), Vector3(0.16, 1.02, -0.94), Color(1.0, 0.78, 0.18))
	for side in [-1.0, 1.0]:
		for z in [-0.42, 0.42]:
			var leg := _box(_visual, "Leg", Vector3(0.18, 0.28, 0.58), Vector3(side * 0.56, 0.33, z), _body_color.darkened(0.16))
			_legs.append(leg)

func _material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.82
	mat.metallic = 0.0
	mat.emission_enabled = color.get_luminance() > 0.82
	mat.emission = color
	mat.emission_energy_multiplier = 0.18
	return mat

func _box(parent: Node3D, part_name: String, size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var node := MeshInstance3D.new()
	node.name = part_name
	node.mesh = mesh
	node.position = pos
	node.material_override = _material(color)
	parent.add_child(node)
	_parts.append(node)
	return node

func _sphere(parent: Node3D, part_name: String, size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 12
	mesh.rings = 8
	var node := MeshInstance3D.new()
	node.name = part_name
	node.mesh = mesh
	node.scale = size
	node.position = pos
	node.material_override = _material(color)
	parent.add_child(node)
	_parts.append(node)
	return node

func _cylinder(parent: Node3D, part_name: String, radius: float, height: float, pos: Vector3, color: Color) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius * 1.08
	mesh.height = height
	mesh.radial_segments = 12
	var node := MeshInstance3D.new()
	node.name = part_name
	node.mesh = mesh
	node.position = pos
	node.material_override = _material(color)
	parent.add_child(node)
	_parts.append(node)
	return node
