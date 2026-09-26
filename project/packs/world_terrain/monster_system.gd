extends Node3D
## Spawner roster monster. Delapan bentuk berbeda langsung terlihat di dunia;
## posisi/warna/atribut deterministic agar mudah diuji dan diulang di HP.

const MONSTER_SCRIPT := preload("res://packs/world_terrain/monster.gd")

var player: Node3D
var _monsters: Array[Node3D] = []
var _roster := [
	{"kind": "slime", "color": Color(0.30, 0.78, 0.50), "health": 80.0, "speed": 1.35, "damage": 4.0},
	{"kind": "slime", "color": Color(0.22, 0.58, 0.86), "health": 95.0, "speed": 1.55, "damage": 5.0},
	{"kind": "golem", "color": Color(0.52, 0.47, 0.62), "health": 180.0, "speed": 0.75, "damage": 12.0},
	{"kind": "golem", "color": Color(0.70, 0.34, 0.25), "health": 210.0, "speed": 0.62, "damage": 14.0},
	{"kind": "bat", "color": Color(0.34, 0.22, 0.48), "health": 70.0, "speed": 2.25, "damage": 7.0},
	{"kind": "bat", "color": Color(0.16, 0.42, 0.48), "health": 76.0, "speed": 2.05, "damage": 6.0},
	{"kind": "mushroom", "color": Color(0.82, 0.26, 0.30), "health": 110.0, "speed": 1.05, "damage": 8.0},
	{"kind": "crawler", "color": Color(0.78, 0.55, 0.22), "health": 125.0, "speed": 1.70, "damage": 9.0},
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
		monster.name = "Monster_%02d_%s" % [i + 1, str(spec["kind"])]
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
	# Preset rendah tetap menampilkan roster agar gameplay tidak berubah; hanya
	# mengurangi sebagian jauh dari kamera pada perangkat lemah.
	var limit := 8 if float(preset.get("fx", 1.0)) >= 0.8 else 6
	for i in _monsters.size():
		if is_instance_valid(_monsters[i]):
			_monsters[i].visible = i < limit
