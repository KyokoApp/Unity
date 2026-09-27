extends Node3D
## Dinding batu/reruntuhan tinggi acak (ronde-44, dipertahankan lintas-ronde
## sebagai rintangan & pemandangan dunia sihir terbuka di ronde-46): solid
## (menghalangi jalan pemain & kamera lewat collision_layer yang sama dengan
## lantai) dan berkeping-keping jadi kotak yang berputar (RigidBody3D) saat
## hancur kena peluru sihir cukup kuat — cocok jadi reruntuhan kuno yang bisa
## diruntuhkan dengan mantra.

const HEALTH_PER_SEGMENT := 42.0
const DEBRIS_LIFETIME := 3.2

var segments := 5
var seg_size := 1.0
var footprint := 1.3
var color := Color(0.26, 0.28, 0.33)
var max_health := 210.0
var health := 210.0

var _body: StaticBody3D
var _mesh_root: Node3D
var _dead := false

func setup(spec: Dictionary) -> void:
	segments = maxi(2, int(spec.get("segments", 5)))
	seg_size = maxf(0.4, float(spec.get("seg_size", 1.0)))
	footprint = maxf(0.6, float(spec.get("footprint", 1.3)))
	color = spec.get("color", color)
	max_health = HEALTH_PER_SEGMENT * segments
	health = max_health

func _ready() -> void:
	_build()

func _build() -> void:
	_mesh_root = Node3D.new()
	_mesh_root.name = "WallVisual"
	add_child(_mesh_root)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.88
	for i in segments:
		var mesh := BoxMesh.new()
		mesh.size = Vector3(footprint, seg_size, footprint)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = mat
		mi.position = Vector3(0.0, seg_size * (float(i) + 0.5), 0.0)
		_mesh_root.add_child(mi)

	_body = StaticBody3D.new()
	_body.name = "WallBody"
	_body.collision_layer = 1
	_body.collision_mask = 0
	_body.set_meta("wall", self)
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(footprint, seg_size * float(segments), footprint)
	col.shape = box
	col.position = Vector3(0.0, seg_size * float(segments) * 0.5, 0.0)
	_body.add_child(col)
	add_child(_body)

func take_damage(amount: float) -> void:
	if _dead:
		return
	health = maxf(0.0, health - maxf(0.0, amount))
	if health <= 0.0:
		_collapse()

func _collapse() -> void:
	if _dead:
		return
	_dead = true
	var host := get_parent()
	var base := global_position
	if host:
		for i in segments:
			_spawn_debris(host, base + Vector3(0.0, seg_size * (float(i) + 0.5), 0.0))
	queue_free()

## Pecahan kotak yang tumbang berputar (RigidBody3D) — "kayak block pada
## umumnya kalo kelempar kan mutar logic gitu" (permintaan user).
func _spawn_debris(host: Node, at: Vector3) -> void:
	var rb := RigidBody3D.new()
	rb.mass = 5.0
	rb.collision_layer = 1
	rb.collision_mask = 1
	var mesh := BoxMesh.new()
	mesh.size = Vector3(footprint, seg_size, footprint) * 0.94
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.88
	mi.material_override = mat
	rb.add_child(mi)
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = mesh.size
	col.shape = box
	rb.add_child(col)
	host.add_child(rb)
	rb.global_position = at
	var outward := Vector3(randf_range(-1.0, 1.0), randf_range(0.5, 1.3), randf_range(-1.0, 1.0)).normalized()
	rb.linear_velocity = outward * randf_range(2.2, 5.5)
	rb.angular_velocity = Vector3(randf_range(-7.0, 7.0), randf_range(-7.0, 7.0), randf_range(-7.0, 7.0))
	var timer := get_tree().create_timer(DEBRIS_LIFETIME)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(rb):
			rb.queue_free()
	)
