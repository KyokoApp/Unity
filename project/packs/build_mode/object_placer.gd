class_name BuildObjectPlacer
extends RefCounted
## PLACE OBJECT & DELETE-objek (butir 2 & 5 user):
##  - memegang pilihan palette + slider rotasi/scale (dipakai untuk
##    penempatan berikutnya, atau LIVE ke objek yg sedang terseleksi),
##  - tap di tanah: instance scene katalog di titik raycast (manager yg
##    men-hit raycast plane y=0 dan meneruskan world_pos ke sini),
##  - tap dekat objek yg SUDAH ditaruh -> jadi "terseleksi": slider
##    rotasi/scale kemudian mengedit objek itu langsung (sebelum/sesudah
##    ditempatkan, sesuai spec),
##  - ghost marker: cincin + panah arah hadap mengikuti titik tap terakhir
##    supaya user tahu di mana objek akan mendarat & orientasinya,
##  - daftar objek = data MURNI ({id, pos, rot_y, scale}) + node map —
##    serialisasi ke save_load sangat murah, nol penelusuran scene.
##
## Optimasi mobile: PackedScene di-cache katalog (1x load per model);
## penanda ghost immediate-mesh dibangun sekali & cuma digeser.

var world: Node3D
var container: Node3D
var catalog: BuildObjectCatalog

var current_id := ""          # id katalog yg sedang dipilih di palette
var next_rot_y := 0.0         # derajat (UI-friendly) utk penempatan berikut
var next_scale := 1.0
var objects: Array = []       # [{id, pos, rot_y, scale, node}]
var selected_idx := -1        # -1 = tak ada objek terseleksi (mode taruh)
var ghost: Node3D             # cincin penanda posisi+arah
var _radius_cache := {}       # id -> radius perkiraan (bounding sphere) utk seleksi tap

const SELECT_RADIUS := 2.2    # toleransi jarak tap -> seleksi objek (m)

func setup(p_world: Node3D, p_catalog: BuildObjectCatalog) -> void:
	world = p_world
	catalog = p_catalog
	# Satu container bernama tetap: memudahkan Delete/Hapus-semua & probe.
	container = Node3D.new()
	container.name = "BuiltObjects"
	world.add_child(container)
	_make_ghost()
	if not catalog.entries.is_empty():
		current_id = catalog.entries[0]["id"]

## ---------------- API dari UI ----------------

func select_catalog(id: String) -> void:
	if catalog.has_id(id):
		current_id = id
		# pindah ke mode-taruh: lepas seleksi supaya slider mengatur GHOST,
		# bukan mengedit objek lama (bingung-bebas utk pemula mobile).
		deselect()

func set_next_rot(deg: float) -> void:
	next_rot_y = fmod(deg + 360.0, 360.0)
	# Kalau ada objek terseleksi, slider dipahami LIVE mengeditnya (spec
	# "sebelum/sesudah ditempatkan").
	if selected_idx >= 0 and selected_idx < objects.size():
		var o: Dictionary = objects[selected_idx]
		o["rot_y"] = next_rot_y
		o["node"].rotation.y = deg_to_rad(next_rot_y)

func set_next_scale(s: float) -> void:
	next_scale = clampf(s, 0.3, 3.0)
	if selected_idx >= 0 and selected_idx < objects.size():
		var o: Dictionary = objects[selected_idx]
		o["scale"] = next_scale
		o["node"].scale = Vector3.ONE * next_scale

func deselect() -> void:
	selected_idx = -1
	if ghost:
		ghost.visible = true

## ---------------- Penempatan / seleksi ----------------

## Tap di tanah (world_pos hasil raycast manager): kalau SANGAT dekat
## suatu objek yg sudah ada -> SELEKSI objek itu utk diedit; kalau tidak
## -> TARUH objek katalog sekarang di titik itu.
func tap_place(pos: Vector3) -> int:
	var near := _find_nearest(pos, _select_threshold())
	if near >= 0:
		selected_idx = near
		# sinkronkan slider UI dgn nilai objek terseleksi (dikembalikannya
		# idx supaya UI bisa mengupdate slider posisinya)
		next_rot_y = objects[near]["rot_y"]
		next_scale = objects[near]["scale"]
		_update_marker(pos)
		return 1  # terseleksi, tidak menaruh baru
	return place(pos)

## Instance langsung (juga dipakai restore saat LOAD).
func place(pos: Vector3, id: String = "", rot_y: float = -999.0, scale: float = -1.0) -> int:
	var use_id := id if not id.is_empty() else current_id
	if use_id.is_empty() or not catalog.has_id(use_id):
		return 0
	var ps: PackedScene = catalog.get_scene(use_id)
	if ps == null:
		return 0
	var node: Node3D = ps.instantiate() as Node3D
	if node == null:
		return 0
	var use_rot := next_rot_y if rot_y < -900.0 else rot_y
	var use_scale := next_scale if scale < 0.0 else scale
	node.position = pos
	node.rotation.y = deg_to_rad(use_rot)
	node.scale = Vector3.ONE * use_scale
	container.add_child(node)
	objects.append({"id": use_id, "pos": pos, "rot_y": use_rot, "scale": use_scale, "node": node})
	# objek baru = penanda ghost pindah ke situ (indra visual "mendarat")
	_update_marker(pos)
	return 2  # tertanam baru

## Delete mode: tap -> cari objek terdekat dalam radius toleransi, hapus.
## Mengembalikan true bila ada yg terhapus (buat umpan-balik toast).
func delete_at(pos: Vector3) -> bool:
	var near := _find_nearest(pos, _select_threshold() * 1.6)
	if near < 0:
		return false
	var o: Dictionary = objects[near]
	if is_instance_valid(o["node"]):
		o["node"].queue_free()
	objects.remove_at(near)
	if selected_idx == near:
		selected_idx = -1
	elif selected_idx > near:
		selected_idx -= 1
	return true

## Cari objek terdekat dari pos (3D abaikan Y — user menyentuh tanah).
func _find_nearest(pos: Vector3, max_dist: float) -> int:
	var best := -1
	var bd := INF
	for i in objects.size():
		var op: Vector3 = objects[i]["pos"]
		var d := (op - pos).length()
		# toleransi tambahan sebanding scale objek (pohon besar gampang disentuh)
		var tol := max_dist + float(objects[i]["scale"]) * 0.8
		if d <= tol and d < bd:
			bd = d
			best = i
	return best

func _select_threshold() -> float:
	return SELECT_RADIUS

## ---------------- Data utk Save/Load ----------------

func collect_data() -> Array:
	var out: Array = []
	for o in objects:
		out.append({
			"id": o["id"],
			"pos": BuildSaveLoad.pack_vec3(o["pos"]),
			"rot_y": snappedf(float(o["rot_y"]), 0.1),
			"scale": snappedf(float(o["scale"]), 0.01),
		})
	return out

func clear_all() -> void:
	for o in objects:
		if is_instance_valid(o["node"]):
			o["node"].queue_free()
	objects.clear()
	selected_idx = -1

func restore(objects_data: Array) -> void:
	clear_all()
	for d in objects_data:
		place(BuildSaveLoad.unpack_vec3(d.get("pos", [])),
			String(d.get("id", "")),
			float(d.get("rot_y", 0.0)),
			float(d.get("scale", 1.0)))
	selected_idx = -1

func estimate_total() -> int:
	return objects.size()

## ---------------- ghost marker ----------------

## Cincin datar + panah arah hadap: selalu tampil saat Place Object
## aktif (marker tempat & orientasi objek berikutnya), disembunyikan
## saat objek lama terseleksi (panah objek itu sendiri cukup).
func _make_ghost() -> void:
	ghost = Node3D.new()
	ghost.name = "BuildGhost"
	var ring := MeshInstance3D.new()
	var imm := ImmediateMesh.new()
	imm.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	var segs := 28
	for i in segs + 1:
		var a := TAU * float(i) / float(segs)
		imm.surface_add_vertex(Vector3(cos(a) * 0.65, 0.0, sin(a) * 0.65))
	imm.surface_end()
	# panah arah hadap (ke +posisi rot_y=0)
	imm.surface_begin(Mesh.PRIMITIVE_LINES)
	imm.surface_add_vertex(Vector3.ZERO)
	imm.surface_add_vertex(Vector3(0.0, 0.0, -1.0))
	imm.surface_add_vertex(Vector3(-0.18, 0.0, -0.78))
	imm.surface_add_vertex(Vector3(0.18, 0.0, -0.78))
	imm.surface_end()
	ring.mesh = imm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.95, 0.80, 0.35)
	m.no_depth_test = true            # kelihatan di atas tanah, tak tertutup
	ring.material_override = m
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ghost.add_child(ring)
	ghost.visible = false
	world.add_child(ghost)

func _update_marker(pos: Vector3) -> void:
	if ghost == null:
		return
	ghost.global_position = pos + Vector3(0.0, 0.05, 0.0)
	ghost.rotation.y = deg_to_rad(next_rot_y)
	ghost.scale = Vector3.ONE * next_scale

## Dipanggil manager saat drag memindahkan titik bidik (ghost mengikuti
## supaya perasaan "menaruh di mana" terasa hidup sebelum jari dilepas).
func update_aim(pos: Vector3) -> void:
	_update_marker(pos)

func set_ghost_visible(v: bool) -> void:
	if ghost:
		ghost.visible = v
