extends Node3D
## Semua monster ronde ini sengaja hanya berupa kubus kecil.
## Mereka berjalan di y=0, mengejar pemain tanpa terbang/lompat, dan memiliki
## dua mata merah agar terbaca jelas sebagai musuh dari kamera third-person.

var kind := "cube"
var variant := 0
var max_health := 100.0
var health := 100.0
var move_speed := 1.4
var attack_damage := 5.0
var cube_size := 0.56
var player: Node3D

var _body_material: StandardMaterial3D
var _eye_material: StandardMaterial3D
var _body: MeshInstance3D
var _t := 0.0
var _attack_cd := 0.0
var _hurt_flash := 0.0

func setup(spec: Dictionary, target: Node3D) -> void:
	kind = "cube"
	variant = int(spec.get("variant", 0))
	max_health = float(spec.get("health", 100.0))
	health = max_health
	move_speed = float(spec.get("speed", 1.4))
	attack_damage = float(spec.get("damage", 5.0))
	cube_size = float(spec.get("size", 0.56))
	player = target

func _ready() -> void:
	add_to_group("enemies")
	_build_cube()

func _process(delta: float) -> void:
	_t += minf(delta, 0.1)
	_attack_cd = maxf(0.0, _attack_cd - delta)
	_hurt_flash = maxf(0.0, _hurt_flash - delta * 5.0)
	if is_instance_valid(player):
		var to_player := player.global_position - global_position
		to_player.y = 0.0
		var distance := to_player.length()
		if distance > 2.8 and distance < 30.0:
			var direction := to_player / maxf(distance, 0.001)
			global_position += direction * move_speed * delta
			global_position.y = 0.0
			rotation.y = lerp_angle(rotation.y, atan2(-direction.x, -direction.z), 1.0 - exp(-7.0 * delta))
		elif distance <= 2.8 and _attack_cd <= 0.0:
			_attack_cd = 1.25 + fmod(float(variant) * 0.13, 0.3)
			if player.has_method("take_damage"):
				player.take_damage(attack_damage)
	if _body_material:
		_body_material.albedo_color = Color(0.84, 0.12, 0.12) if _hurt_flash > 0.0 else _cube_color()

func take_damage(amount: float) -> void:
	health = maxf(0.0, health - maxf(0.0, amount))
	_hurt_flash = 1.0
	if health <= 0.0:
		_die()

func _die() -> void:
	set_process(false)
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_property(self, "scale", Vector3(0.1, 0.1, 0.1), 0.22)
	tween.tween_callback(queue_free)

func _build_cube() -> void:
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3.ONE * cube_size
	_body = MeshInstance3D.new()
	_body.name = "SmallCubeBody"
	_body.mesh = body_mesh
	_body.position.y = cube_size * 0.5
	_body_material = StandardMaterial3D.new()
	_body_material.albedo_color = _cube_color()
	_body_material.roughness = 0.84
	_body.material_override = _body_material
	add_child(_body)

	# Mata berupa dua kubus pipih merah, menghadap sisi -Z seperti pemain.
	_eye_material = StandardMaterial3D.new()
	_eye_material.albedo_color = Color(1.0, 0.015, 0.01)
	_eye_material.emission_enabled = true
	_eye_material.emission = Color(1.0, 0.0, 0.0)
	_eye_material.emission_energy_multiplier = 3.0
	for side in [-1.0, 1.0]:
		var eye_mesh := BoxMesh.new()
		eye_mesh.size = Vector3(0.10, 0.095, 0.035)
		var eye := MeshInstance3D.new()
		eye.name = "RedEye"
		eye.mesh = eye_mesh
		eye.position = Vector3(side * 0.14, cube_size * 0.62, -cube_size * 0.515)
		eye.material_override = _eye_material
		add_child(eye)

	var hitbox := Area3D.new()
	hitbox.name = "CubeMonsterHitbox"
	hitbox.collision_layer = 1
	hitbox.collision_mask = 0
	hitbox.monitoring = false
	hitbox.set_meta("monster", self)
	var hit_shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = cube_size * 0.82
	hit_shape.shape = sphere
	hit_shape.position = Vector3(0.0, cube_size * 0.5, 0.0)
	hitbox.add_child(hit_shape)
	add_child(hitbox)

func _cube_color() -> Color:
	var colors := [
		Color(0.20, 0.24, 0.29), Color(0.25, 0.27, 0.32),
		Color(0.30, 0.22, 0.25), Color(0.22, 0.30, 0.31),
	]
	return colors[variant % colors.size()]
