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
var last_deleted := {}        # rekaman objek terakhir yg di-delete_at (utk undo manager)
var _pending := {}            # objek "calon" saat ini: {node,id, origin?} — lihat blok pending
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
		# ganti palette saat ada calon = buang calonnya (bersih, sesuai rasa)
		if has_pending():
			cancel_pending()

func set_next_rot(deg: float) -> void:
	next_rot_y = fmod(deg + 360.0, 360.0)
	# Kalau ada objek terseleksi, slider dipahami LIVE mengeditnya (spec
	# "sebelum/sesudah ditempatkan").
	if selected_idx >= 0 and selected_idx < objects.size():
		var osel: Dictionary = objects[selected_idx]
		osel["rot_y"] = next_rot_y
		osel["node"].rotation.y = deg_to_rad(next_rot_y)
	_slider_to_pending()

func set_next_scale(s: float) -> void:
	next_scale = clampf(s, 0.3, 3.0)
	if selected_idx >= 0 and selected_idx < objects.size():
		var osc: Dictionary = objects[selected_idx]
		osc["scale"] = next_scale
		osc["node"].scale = Vector3.ONE * next_scale
	_slider_to_pending()

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
	_apply_perf_flags(node, use_id)
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
	last_deleted = {
		"id": String(o["id"]),
		"pos": BuildSaveLoad.pack_vec3(o["pos"]),   # format save (Array) supaya konsisten dgn restore_add
		"rot_y": float(o["rot_y"]),
		"scale": float(o["scale"]),
	}
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

## ===== PENDING OBJEK (permintaan user, ronde ini: "setiap objek yang
## mau ditaro bisa digeser pindah dulu kalo tekan lama, pas udah pas baru
## tekan OK") =====
## Alur: tap tanah kosong -> spawn calon (belum tersimpan, tampil langsung
## jernih-sama sbg objek biasa); tap lagi / drag menahan = geser calon;
## tahan-lama objek LAMA yg sdh ditaruh = "ambil" dia kembali jd calon
## (node re-USE, bukan instantiate ulang); tombol OK = commit_pending()
## (barulah masuk ke daftar objects & dapat di-undo); tombol BATAL =
## cancel_pending() (calon baru dihapus bebas; calon-yg-diangkat balik
## ke posisi asalnya persis). Slider rotasi/scale selalu LIVE ke calon.

func has_pending() -> bool:
	return not _pending.is_empty()

func _pending_origin() -> Dictionary:
	return _pending.get("origin", {})

## Tap tanah dg calon BARU (dr katalog sekarang). Return false bila ada
## calon yg belum selesai (manager harusnya panggil move_pending saja).
func spawn_pending(pos: Vector3) -> bool:
	if has_pending():
		return false
	var use_id := current_id
	if use_id.is_empty() or not catalog.has_id(use_id):
		return false
	var ps: PackedScene = catalog.get_scene(use_id)
	if ps == null:
		return false
	var node: Node3D = ps.instantiate() as Node3D
	if node == null:
		return false
	node.position = pos
	node.rotation.y = deg_to_rad(next_rot_y)
	node.scale = Vector3.ONE * next_scale
	_apply_perf_flags(node, use_id)
	container.add_child(node)
	_pending = {"node": node, "id": use_id, "origin": {}}
	deselect()
	ghost.visible = false       # ghost digantikan objek calon nyata
	return true

## Geser calon (tap ulang / drag saat tahan-lama posisinya).
func move_pending(pos: Vector3) -> void:
	if has_pending():
		_pending["node"].global_position = Vector3(pos.x, pos.y, pos.z)

## Tahan-lama objek LAMA yg sudah tertanam: angkat jd calon (dipindahkan).
## Return true bila ketemu objek dalam jangkauan & berhasil diangkat.
func pickup_at(pos: Vector3) -> bool:
	if has_pending():
		return false
	var near := _find_nearest(pos, _select_threshold())
	if near < 0:
		return false
	var o: Dictionary = objects[near]
	objects.remove_at(near)
	selected_idx = -1
	# slider UI langsung mencerminkan atribut objek yg diangkat (manager
	# memanggil ui.sync_rot_scale sesudahnya di _try_begin_grab).
	next_rot_y = float(o["rot_y"])
	next_scale = float(o["scale"])
	_pending = {"node": o["node"], "id": o["id"], "origin": o}
	ghost.visible = false
	return true

## Tombol OK: sahkan calon -> objek terdaftar. Return rekaman objeknya
## (manager mendorongnya ke tumpukan undo: jenis "obj_place", idx akhir).
func commit_pending() -> Dictionary:
	if not has_pending():
		return {}
	var node: Node3D = _pending["node"]
	var rec := {
		"id": String(_pending["id"]),
		"pos": node.global_position,
		"rot_y": next_rot_y,
		"scale": next_scale,
		"node": node,
	}
	objects.append(rec)
	_pending = {}
	_update_marker(rec["pos"])
	ghost.visible = true
	return rec

## Tombol BATAL: calon baru dibuang; calon-angkat dipulangkan ke asal.
func cancel_pending() -> void:
	if not has_pending():
		return
	var origin: Dictionary = _pending_origin()
	if origin.is_empty():
		if is_instance_valid(_pending["node"]):
			_pending["node"].queue_free()
	else:
		var node: Node3D = _pending["node"]
		node.global_position = origin["pos"]
		node.rotation.y = deg_to_rad(float(origin["rot_y"]))
		node.scale = Vector3.ONE * float(origin["scale"])
		objects.append(origin)
	_pending = {}
	ghost.visible = true

## Slider rotasi/scale langsung digerakkan ke calon (LIVE, indra edit nyata).
func _slider_to_pending() -> void:
	if not has_pending():
		return
	var node: Node3D = _pending["node"]
	node.rotation.y = deg_to_rad(next_rot_y)
	node.scale = Vector3.ONE * next_scale

## ---------------- util undo / bersih-bersih (dipakai manager) ----------------

## Hapus objek pada index tertentu (undo penempatan — LIFO aman, lihat
## catatan di manager). Return true bila index valid & node dibebaskan.
func remove_index(i: int) -> bool:
	if i < 0 or i >= objects.size():
		return false
	var o: Dictionary = objects[i]
	if is_instance_valid(o["node"]):
		o["node"].queue_free()
	objects.remove_at(i)
	if selected_idx == i:
		selected_idx = -1
	elif selected_idx > i:
		selected_idx -= 1
	return true

## Tambahkan kembali objek dari rekaman save-format (TANPA clear dulu) —
## dipakai undo hapus / undo bersih-rumput-jalan. Bedakan dgn restore()
## penuh di bawah yg for-load (dia clear_all lebih dulu).
func restore_add(records: Array) -> void:
	for d in records:
		place(BuildSaveLoad.unpack_vec3(d.get("pos", [])),
			String(d.get("id", "")),
			float(d.get("rot_y", 0.0)),
			float(d.get("scale", 1.0)))

## Bersihkan objek "penutup tanah" (rumput/pakis/bunga/jamur & yg ditandai
## "cover" di katalog) yg berada dekat jalur jalan — permintaan user:
## "kalo buat jalan itu harus nya rumput yang ada ilang". Return daftar
## rekaman (format save) yg dihapus supaya bisa di-undo manager.
func clear_near_path(pts: PackedVector3Array, radius: float) -> Array:
	var removed: Array = []
	var cover := catalog.cover_ids()
	var i := 0
	while i < objects.size():
		var o: Dictionary = objects[i]
		if not cover.has(String(o["id"])):
			i += 1
			continue
		var op: Vector3 = o["pos"]
		var near_path := false
		for pt in pts:
			if (Vector3(pt.x, 0, pt.z) - Vector3(op.x, 0, op.z)).length() <= radius:
				near_path = true
				break
		if near_path:
			removed.append({
				"id": String(o["id"]),
				"pos": BuildSaveLoad.pack_vec3(op),
				"rot_y": float(o["rot_y"]),
				"scale": float(o["scale"]),
			})
			remove_index(i)
		else:
			i += 1
	return removed

## Bayangan MATI utk objek kecil berlabel "small" di katalog (rumput dkk):
## tebaran ratusan instance tanpa bayangan = FPS mid-range jauh lebih
## toilet (optimalisasi ronde ini); objek besar (pohon/batu) tetap meneduh.
func _apply_perf_flags(node: Node3D, id: String) -> void:
	if not catalog.is_small(id):
		return
	for g in node.find_children("*", "GeometryInstance3D", true, false):
		(g as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

## Cari index objek terdekat (public wrapper buat tahan-lama manager).
func find_near_index(pos: Vector3, max_dist: float) -> int:
	return _find_nearest(pos, max_dist)

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
