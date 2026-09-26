extends Node3D
## Spawner dinding tinggi ACAK (ronde-44) yang solid, bisa dihancurkan, dan
## jadi target rayap tali (grapple) ala Attack on Titan. Posisi slot tetap
## (deterministik, mudah diuji), tapi tinggi/lebar/warna tiap dinding acak
## lewat RNG berseed tetap supaya tata letak konsisten antar sesi permainan
## tanpa perlu menyimpan state manapun.

const WALL_SCRIPT := preload("res://packs/world_terrain/wall.gd")

var _walls: Array[Node3D] = []
var _rng := RandomNumberGenerator.new()

var _slots := [
	Vector3(6.0, 0.0, -7.0), Vector3(-11.0, 0.0, -3.0),
	Vector3(3.5, 0.0, 8.0), Vector3(-5.0, 0.0, 15.0),
	Vector3(15.0, 0.0, 3.0), Vector3(-16.0, 0.0, -13.0),
	Vector3(-3.0, 0.0, -19.0), Vector3(19.0, 0.0, -10.0),
	Vector3(10.0, 0.0, -20.0), Vector3(-20.0, 0.0, 7.0),
]

func _ready() -> void:
	_rng.seed = 4477
	_spawn_walls()

func _spawn_walls() -> void:
	var palette := [
		Color(0.24, 0.26, 0.31), Color(0.30, 0.27, 0.24),
		Color(0.22, 0.28, 0.29), Color(0.28, 0.24, 0.30),
	]
	for i in _slots.size():
		var wall: Node3D = WALL_SCRIPT.new()
		var spec := {
			"segments": _rng.randi_range(3, 8),
			"seg_size": _rng.randf_range(0.85, 1.2),
			"footprint": _rng.randf_range(1.0, 1.7),
			"color": palette[i % palette.size()],
		}
		wall.name = "TallWall_%02d" % (i + 1)
		wall.call("setup", spec)
		add_child(wall)
		wall.global_position = _slots[i]
		_walls.append(wall)

func alive_count() -> int:
	var alive := 0
	for w in _walls:
		if is_instance_valid(w):
			alive += 1
	return alive
