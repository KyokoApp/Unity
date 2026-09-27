class_name BuildObjectCatalog
extends RefCounted
## KATALOG objek yg bisa ditempatkan di mode Place Object (butir 2 user).
## Sumber model: paket "Stylized Nature MegaKit (Standard, FREE/CC0)"
## oleh Quaternius (user kirim link Google Drive-nya) — versi glTF
## (.gltf + .bin + png) yg diimpor native oleh Godot, sudah dikurasi 17
## model & teksturnya diperkecil ke maks 1024px demi pack mobile.
##
## Katalog BERSIHH REFLEKSI: saat _ready manager menghapus entri yg
## file scene-nya tidak ketemu (ResourceLoader.exists), jd menambah
## model baru nanti = letakkan .gltf di folder + tambah 1 baris entri
## di sini; tak ada wiring lain. Kalau suatu hari paket dihapus, entri
## "Fallback primitif" (kubus/kapsul warna-warni) TETAP tersedia supaya
## Build Mode tak pernah kosong-klik.

const OBJ_DIR := "res://packs/build_mode/objects/nature/"

## Daftar katalog penuh (kandidat). setiap entri:
##   id     : kunci unik (dipakai juga nama file save "objects")
##   label  : teks singkat di tombol palette (layar kecil: <= 8 huruf terbaca)
##   path   : res:// scene/model yg di-load() saat pertama kali dipakai
##   tint   : warna aksen tombol palette (selaras palet sore pastel)
var candidates: Array = [
	{"id": "CommonTree_1",   "label": "Pohon 1",  "path": OBJ_DIR + "CommonTree_1.gltf",   "tint": Color(0.42, 0.62, 0.38)},
	{"id": "CommonTree_2",   "label": "Pohon 2",  "path": OBJ_DIR + "CommonTree_2.gltf",   "tint": Color(0.40, 0.58, 0.36)},
	{"id": "CommonTree_3",   "label": "Pohon 3",  "path": OBJ_DIR + "CommonTree_3.gltf",   "tint": Color(0.38, 0.60, 0.34)},
	{"id": "Pine_1",         "label": "Pinus",    "path": OBJ_DIR + "Pine_1.gltf",         "tint": Color(0.33, 0.52, 0.34)},
	{"id": "TwistedTree_1",  "label": "P. Lilit", "path": OBJ_DIR + "TwistedTree_1.gltf",  "tint": Color(0.46, 0.40, 0.34)},
	{"id": "DeadTree_1",     "label": "P. Mati",  "path": OBJ_DIR + "DeadTree_1.gltf",     "tint": Color(0.52, 0.45, 0.38)},
	{"id": "Bush_Common",           "label": "Semak",   "path": OBJ_DIR + "Bush_Common.gltf",           "tint": Color(0.45, 0.62, 0.38)},
	{"id": "Bush_Common_Flowers",   "label": "Semak B.", "path": OBJ_DIR + "Bush_Common_Flowers.gltf",  "tint": Color(0.60, 0.55, 0.62)},
	{"id": "Fern_1",         "label": "Pakis",    "path": OBJ_DIR + "Fern_1.gltf",         "tint": Color(0.40, 0.60, 0.42)},
	{"id": "Plant_1_Big",    "label": "Tanaman",  "path": OBJ_DIR + "Plant_1_Big.gltf",    "tint": Color(0.42, 0.58, 0.40)},
	{"id": "Mushroom_Common", "label": "Jamur",   "path": OBJ_DIR + "Mushroom_Common.gltf", "tint": Color(0.66, 0.46, 0.38)},
	{"id": "Flower_3_Group", "label": "Bunga",    "path": OBJ_DIR + "Flower_3_Group.gltf", "tint": Color(0.72, 0.52, 0.60)},
	{"id": "Grass_Common_Tall", "label": "Alang", "path": OBJ_DIR + "Grass_Common_Tall.gltf", "tint": Color(0.55, 0.62, 0.40)},
	{"id": "Rock_Medium_1",  "label": "Batu 1",   "path": OBJ_DIR + "Rock_Medium_1.gltf",  "tint": Color(0.55, 0.56, 0.58)},
	{"id": "Rock_Medium_2",  "label": "Batu 2",   "path": OBJ_DIR + "Rock_Medium_2.gltf",  "tint": Color(0.52, 0.53, 0.56)},
	{"id": "Pebble_Round_1", "label": "Kerikil",  "path": OBJ_DIR + "Pebble_Round_1.gltf", "tint": Color(0.58, 0.57, 0.58)},
	{"id": "RockPath_Round_Wide", "label": "Pijakan", "path": OBJ_DIR + "RockPath_Round_Wide.gltf", "tint": Color(0.60, 0.58, 0.55)},
]

## Entri katalog yg SUDAH lolos cek ketersediaan file (dipakai UI/Placer).
var entries: Array = []
## Cache PackedScene per-id: load() mahal hanya sekali per model, sesudah
## itu instantiate() murah (POOLING ringan byte-butir 7 user: tanpa
## instancing berlebihan per load).
var _scene_cache := {}

## Dipanggil SEKALI oleh manager saat setup: saring kandidat ke entries.
func populate() -> void:
	entries.clear()
	for c in candidates:
		if ResourceLoader.exists(c["path"]):
			entries.append(c)
	# Fallback primitif: kalau paket model tak ter-import (mis. dev tanpa
	# zip), Build Mode tetap bisa dipakai dg objek kubik sederhana.
	if entries.is_empty():
		entries.append({"id": "Prim_Tree", "label": "Pohon*", "path": "", "tint": Color(0.42, 0.62, 0.38)})
		entries.append({"id": "Prim_Rock", "label": "Batu*", "path": "", "tint": Color(0.55, 0.56, 0.58)})

## Ambil PackedScene utk id (cache). Model primitif dibuat prosedural.
func get_scene(id: String) -> PackedScene:
	if _scene_cache.has(id):
		return _scene_cache[id]
	var ps: PackedScene = null
	for e in entries:
		if e["id"] == id and not String(e["path"]).is_empty():
			ps = load(e["path"]) as PackedScene
			break
	if ps == null:
		ps = _make_primitive_scene(id)
	_scene_cache[id] = ps
	return ps

func has_id(id: String) -> bool:
	for e in entries:
		if e["id"] == id:
			return true
	return false

func tint_of(id: String) -> Color:
	for e in entries:
		if e["id"] == id:
			return e["tint"]
	return Color(0.6, 0.6, 0.6)

func label_of(id: String) -> String:
	for e in entries:
		if e["id"] == id:
			return e["label"]
	return id

## Scene primitif darurat (pohon = silinder+bola, batu = bola gepeng):
## dibuat SEKALI lalu di-cache spt model lain.
func _make_primitive_scene(id: String) -> PackedScene:
	var root := Node3D.new()
	var is_tree := id.find("Tree") >= 0 or id.find("Pohon") >= 0
	if is_tree:
		var trunk := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.18; cm.bottom_radius = 0.26; cm.height = 1.7
		trunk.mesh = cm
		trunk.position.y = 0.85
		trunk.material_override = _prim_mat(Color(0.45, 0.32, 0.22))
		root.add_child(trunk)
		trunk.owner = root
		var crown := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 1.15; sm.height = 2.0
		crown.mesh = sm
		crown.position.y = 2.4
		crown.scale = Vector3(1.0, 0.85, 1.0)
		crown.material_override = _prim_mat(Color(0.36, 0.52, 0.30))
		root.add_child(crown)
		crown.owner = root
	else:
		var rock := MeshInstance3D.new()
		var sm2 := SphereMesh.new()
		sm2.radius = 0.8; sm2.height = 1.3
		rock.mesh = sm2
		rock.position.y = 0.45
		rock.scale = Vector3(1.15, 0.75, 0.9)
		rock.material_override = _prim_mat(Color(0.52, 0.53, 0.56))
		root.add_child(rock)
		rock.owner = root
	var ps := PackedScene.new()
	ps.pack(root)
	root.queue_free()
	return ps

func _prim_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	return m
