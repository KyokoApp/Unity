class_name Orbs
extends Node3D

## ============================================================
## ORBS — benda float emas-kuning bercahaya di dekat jalan.
## (Port dari Orbs.cs. 12 orb deterministik per Episode 1 dari
## WorldScatter.place_orbs; bob sinus; pickup radius 2,4 m;
## collect-unik — orb diambil hanya dalam sesi ini sebelun di-reset.)
## ============================================================

@export var target: Node3D
## Warna dasar + emisi sesuai episode (E1: bulan emas-kuning).
@export var light_color := Color(1.00, 0.85, 0.35, 1.0)
@export var trail_color := Color(0.78, 0.56, 1.00, 1.0)

signal orb_taken(ids: Array)

var collected_count: int:
	get: return _collected.size()

var _list: Array[Dictionary] = []
var _node_map: Dictionary = {}
var _collected: Dictionary = {}
var _t := 0.0

func _ready() -> void:
	setup_episode(1)

## Episode 1 memakai konstanta baku place_orbs (kosong = default).
func setup_episode(_episode: int) -> void:
	clear_all()
	var list := WorldScatter.place_orbs(0, 0, 0, -1)
	for o in list:
		_list.append(o)
		if _collected.has(o["id"]):
			continue
		var node := _orb_node()
		node.position = Vector3(o["x"], o["y"], o["z"])
		add_child(node)
		_node_map[o["id"]] = node

func reset_collected() -> void:
	_collected.clear()
	setup_episode(1)

func clear_all() -> void:
	for id in _node_map:
		_node_map[id].queue_free()
	_node_map.clear()
	_list.clear()

func _process(delta: float) -> void:
	if _list.is_empty():
		return
	_t += delta

	# bob sekitar: sinus membuat benda terasa "hidup"
	for o in _list:
		var node: Node3D = _node_map.get(o["id"])
		if node == null:
			continue
		var wobble := sin(_t * 1.6 + float(o["wx"]) ) * 0.22
		node.position.y = float(o["y"]) + wobble

	# pickup: pemain cukup menyentuh radius
	if target != null:
		var p := target.global_position
		for o in _list:
			if _collected.has(o["id"]):
				continue
			var dx := p.x - float(o["x"])
			var dz := p.z - float(o["z"])
			var dy := p.y + 0.9 - float(o["y"])
			var r2 := dx * dx + dz * dz + dy * dy * 0.5
			if r2 <= WorldScatter.ORB_PICKUP_RADIUS * WorldScatter.ORB_PICKUP_RADIUS:
				_collect(o["id"])

func _collect(id: int) -> void:
	_collected[id] = true
	var node: Node3D = _node_map.get(id)
	if node != null:
		_node_map.erase(id)
		node.queue_free()
	orb_taken.emit(ids_of(_collected))

static func ids_of(coll: Dictionary) -> Array:
	var a: Array = coll.keys()
	a.sort()
	return a

func taken_ids() -> Array:
	return ids_of(_collected)

func _orb_node() -> Node3D:
	var n := MeshInstance3D.new()
	n.name = "Orb"
	var sq := SphereMesh.new()
	sq.radius = 0.32
	sq.height = 0.32 * 2.0
	sq.radial_segments = 12
	sq.rings = 6
	n.mesh = sq
	var mat := StandardMaterial3D.new()
	mat.albedo_color = light_color
	mat.emission_enabled = true
	mat.emission = Color(light_color, 1.0) * 2.4
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	n.material_override = mat
	return n
