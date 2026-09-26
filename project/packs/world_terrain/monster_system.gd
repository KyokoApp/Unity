extends Node3D
## Spawner monster kubus kecil. Tidak ada slime/golem/bat lagi: seluruh roster
## memakai bentuk dan logic yang sama agar siluet gameplay konsisten.

const MONSTER_SCRIPT := preload("res://packs/world_terrain/monster.gd")

var player: Node3D
var _monsters: Array[Node3D] = []
var _roster := [
	{"size": 0.54, "health": 70.0, "speed": 1.55, "damage": 4.0},
	{"size": 0.56, "health": 80.0, "speed": 1.70, "damage": 5.0},
	{"size": 0.58, "health": 90.0, "speed": 1.35, "damage": 6.0},
	{"size": 0.55, "health": 100.0, "speed": 1.85, "damage": 7.0},
	{"size": 0.60, "health": 120.0, "speed": 1.20, "damage": 8.0},
	{"size": 0.52, "health": 76.0, "speed": 2.00, "damage": 5.0},
	{"size": 0.57, "health": 110.0, "speed": 1.45, "damage": 9.0},
	{"size": 0.53, "health": 84.0, "speed": 1.90, "damage": 6.0},
]
var _spawn_positions := [
	Vector3(-9.0, 0.0, -12.0), Vector3(7.0, 0.0, -15.0),
	Vector3(14.0, 0.0, -3.0), Vector3(-14.0, 0.0, 2.0),
	Vector3(11.0, 0.0, 10.0), Vector3(-8.0, 0.0, 13.0),
	Vector3(1.0, 0.0, 17.0), Vector3(-17.0, 0.0, -8.0),
]

func set_player(p: Node3D) -> void:
	player = p
	if _monsters.is_empty():
		_spawn_roster()
	else:
		for monster in _monsters:
			if is_instance_valid(monster):
				monster.set("player", p)

func _spawn_roster() -> void:
	for i in _roster.size():
		var monster: Node3D = MONSTER_SCRIPT.new()
		var spec: Dictionary = _roster[i].duplicate()
		spec["variant"] = i
		monster.name = "SmallCubeMonster_%02d" % (i + 1)
		monster.call("setup", spec, player)
		add_child(monster)
		monster.global_position = _spawn_positions[i]
		_monsters.append(monster)

func alive_count() -> int:
	var alive := 0
	for monster in _monsters:
		if is_instance_valid(monster):
			alive += 1
	return alive

func apply_quality(preset: Dictionary) -> void:
	# Tetap mempertahankan bentuk/logic yang sama; preset rendah hanya mengurangi
	# jumlah musuh aktif agar HP lama tidak terbebani.
	var limit := 8 if float(preset.get("fx", 1.0)) >= 0.8 else 6
	for i in _monsters.size():
		if is_instance_valid(_monsters[i]):
			_monsters[i].visible = i < limit
