class_name BuildModeManager
extends Node
## BUILD MODE MANAGER (butir 1 user) — otak di balik toggle Build Mode:
## memegang sub-mode aktif ("place"/"terrain"/"road"/"delete"), merutekan
## tap layar ke subsistem (object_placer / terrain_editor / road_builder),
## mengatur save/load (build_save_load) + autosave saat keluar, dan selagi
## aktif MENGAMBIL ALIH gestur layar kosong: tap = aksi build, drag satu
## jari = putar kamera (dietapkan ke player.add_look_px), cubit 2 jari =
## zoom. HUD normal ditahan lewat flag hud.build_suspended (lihat hud.gd).
##
## Raycast tap->tanah dilakukan ANALITIS (kamera ray ∩ bidang y=0) — nol
## PhysicsRayQuery, kuat & cepat utk dunia bidang datar kita; kamera
## ditemukan lazy per-tap (get_viewport().get_camera_3d()).
##
## Dipanggil dari world.gd saat generate_async(_root). Saat probe/headless
## (root=tanpa-hud, tanpa pemain) seluruh bagian gestur jadi no-op aman.

const UI_SCENE := "res://packs/build_mode/build_mode_ui.gd"

var world: Node3D
var root_ref: Node
var ui: BuildModeUI
var catalog: BuildObjectCatalog
var placer: BuildObjectPlacer
var terrain: BuildTerrainEditor
var road: BuildRoadBuilder

var mode_active := false
var submode := "place"                # "place"|"terrain"|"road"|"delete"
var _hud: CanvasLayer = null
var _touches := {}                    # index -> {start, time_msec, moved, is_look}
var _look_index := -1
var _pinch_index := -1
var _pinch_last_dist := 0.0
var _undo: Array = []               # tumpukan Reverse/undo (LIFO)
var _grab_index := -1               # jari yg sedang MENGGESER objek calon (-1 = tidak)
var _grab_may_begin := false        # press yg startnya di atas objek (calon/teranam)

const UNDO_LIMIT := 64
const LONG_PRESS_MSEC := 480        # ambang "teken lama" (tahan-lama genggam objek)
const GRAB_START_PX := 12.0         # ambang gerak drag selama tahan-lama

const TAP_MAX_MSEC := 420             # tap = tekan&lepas cepat (bukan drag)
const TAP_MAX_DIST_PX := 18.0         # tap = jari nyaris tak bergeser
const LOOK_DRAG_START_PX := 8.0       # mulai anggap drag-look sesudah geser ini

func setup(p_world: Node3D, p_root: Node) -> void:
	world = p_world
	root_ref = p_root
	# subsistem modular (butir 7: terpisah per-file)
	catalog = BuildObjectCatalog.new()
	catalog.populate()
	placer = BuildObjectPlacer.new()
	placer.setup(world, catalog)
	terrain = BuildTerrainEditor.new()
	terrain.setup(world)
	road = BuildRoadBuilder.new()
	road.setup(world)
	_build_ui()
	_load_initial()

func _build_ui() -> void:
	ui = (load(UI_SCENE) as GDScript).new() as BuildModeUI
	add_child(ui)   # CanvasLayer; _ready-nya membangun layout
	ui.cb = {
		"toggle": Callable(self, "toggle"),
		"set_submode": Callable(self, "set_submode"),
		"select_catalog": Callable(self, "_on_select_catalog"),
		"rot_changed": Callable(self, "_on_rot_changed"),
		"scale_changed": Callable(self, "_on_scale_changed"),
		"set_tile": Callable(self, "_on_set_tile"),
		"rotate_tile": Callable(self, "_on_rotate_tile"),
		"level_delta": Callable(self, "_on_level_delta"),
		"width_changed": Callable(self, "_on_width_changed"),
		"finish_road": Callable(self, "_on_finish_road"),
		"cancel_road": Callable(self, "_on_cancel_road"),
		"clear_all": Callable(self, "_on_clear_all"),
		"save": Callable(self, "save_map"),
		"load": Callable(self, "load_map"),
		"undo": Callable(self, "undo"),
		"ok_pending": Callable(self, "_on_ok_pending"),
		"cancel_pending": Callable(self, "_on_cancel_pending"),
	}
	ui.fill_palette(catalog.entries)
	ui.highlight_palette(placer.current_id)
	ui.sync_rot_scale(placer.next_rot_y, placer.next_scale)
	ui.set_submode(submode)
	if ui.joy_control:
		ui.joy_control.set("on_change", Callable(self, "_on_build_joy"))

## Auto-LOAD saat scene map dibuka (butir 6): map yg pernah dibangun
## persist antar sesi — file save dipulihkan tanpa menunggu aksi user.
func _load_initial() -> void:
	var data := BuildSaveLoad.load_from()
	if data.is_empty():
		return
	_apply_data(data)
	if ui:
		ui.set_status("Map bangunan dipulihkan dari save")

## FAB build adalah milik WORLD CREATIVE saja — mode Open World (ronde ini,
## "kampung hutan") diminta user utk MENIKMATI hutan, jd FAB disembunkurkan
## oleh world.set_open_world_mode. Menutup build aktif terlebih dulu jika
## kebetulan sedang terbuka (bekerja dengan invoker).
func set_fab_visible(v: bool) -> void:
	if ui and ui.fab:
		ui.fab.visible = v
	if not v and mode_active:
		toggle()   # hiraukan aktif jadi off sebelum disembunyikan

## ---------------- toggle & sub-mode ----------------

func toggle() -> void:
	mode_active = not mode_active
	if mode_active:
		_resolve_hud()
		if _hud:
			_hud.set("build_suspended", true)   # hud menahan gestur layar
		# kamera langsung pindah TOP-DOWN SMOOTH + karakter disembunyikan
		# (permintaan user, ronde ini) supaya editing dari atas full-layar.
		var p_in := _player()
		if p_in and p_in.has_method("enter_build_cam"):
			p_in.enter_build_cam()
		ui.show_panel(true)
		ui.set_status("Build Mode AKTIF — kamera atas; geser layar untuk pan peta")
		placer.set_ghost_visible(submode == "place")
	else:
		# calon objek yg tertinggal dianggap BATAL (sesuai draft jalan)
		placer.cancel_pending()
		ui.set_pending_visible(false)
		var p_out := _player()
		if p_out and p_out.has_method("exit_build_cam"):
			p_out.exit_build_cam()
		# AUTOSAVE saat keluar Build Mode (butir 6: "autosave saat keluar")
		# Draft jalan ikut dituntaskan: >=2 titik -> dikunci; <2 -> batal.
		if road.active_curve != null and road.active_curve.point_count >= 2:
			road.finish()
		else:
			road.cancel_draft()
		save_map()
		if _hud:
			_hud.set("build_suspended", false)
		ui.show_panel(false)
		placer.set_ghost_visible(false)
		placer.deselect()
		# bersihkan status gerak pemain supaya tak "nyangkut" jalan sendiri
		_on_build_joy(Vector2.ZERO)
	ui.set_submode(submode)

func set_submode(key: String) -> void:
	if submode == "place" and key != "place":
		placer.cancel_pending()          # tab pindah = calon objek dibatalkan bersih
		ui.set_pending_visible(false)
	submode = key
	ui.set_submode(key)
	placer.set_ghost_visible(key == "place" and not placer.has_pending())
	placer.deselect()
	var hints := {
		"place": "Mode OBJEK: tap tanah = pasang / pilih objek",
		"terrain": "Mode TERRAIN: tap grid = pasang tile (%s, %d°)" % [_tile_name(), terrain.rot_idx * 90],
		"road": "Mode JALAN: tap = titik curve; 'Selesai' utk kunci",
		"delete": "Mode HAPUS: tap objek/tile/jalan = hapus",
	}
	ui.set_status(hints.get(key, ""))

func _tile_name() -> String:
	match terrain.current_item:
		1: return "Miring"
		2: return "Sudut"
	return "Datar"

## ---------------- callbacks UI ----------------

func _on_select_catalog(id: String) -> void:
	placer.select_catalog(id)
	if not placer.has_pending():
		ui.set_pending_visible(false)
	ui.highlight_palette(id)
	ui.set_status("Dipilih: " + catalog.label_of(id))

func _on_rot_changed(v: float) -> void:
	placer.set_next_rot(v)
	ui.rot_label.text = "Putar: %d°" % int(v)

func _on_scale_changed(v: float) -> void:
	placer.set_next_scale(v)
	ui.scale_label.text = "Skala: %.2fx" % v

func _on_set_tile(item: int) -> void:
	terrain.set_item(item)
	for k in ui.tile_buttons.keys():
		ui.tile_buttons[k].modulate = Color(1.35, 1.25, 1.05) if k == item else Color(1, 1, 1)
	ui.set_status("Tile: " + _tile_name())

func _on_rotate_tile() -> void:
	var r := terrain.rotate_item()
	ui.set_rotate_text(r)
	ui.set_status("Rotasi tile: %d°" % (r * 90))

func _on_level_delta(d: int) -> void:
	var lv := terrain.set_level(terrain.build_level + d)
	ui.set_level_text(lv)

func _on_width_changed(v: float) -> void:
	road.set_width(v)
	ui.set_width_text(v)

func _on_finish_road() -> void:
	if road.finish():
		# Permintaan user: "kalo buat jalan itu harus nya rumput yang ada
		# ilang" — jalan BARU membersihkan rumput/pakis/bunga/jamur (entri
		# "cover" katalog) di sekeliling jalurnya (radius = setengah lebar
		# jalan + sedikit tumpukan bahu).
		var new_road_id: Node3D = road.roads.back()["path"]
		var half_path := float(road.roads.back()["width"]) * 0.5 + 1.2
		var cut_records := placer.clear_near_path(road.last_baked, half_path)
		_push_undo({"type": "road_finish", "node": new_road_id, "grass": cut_records})
		var extra := ""
		if cut_records.size() > 0:
			extra = " (%d rumput ikut bersih)" % cut_records.size()
		ui.set_status("Jalan dikunci ✓ (mulus)" + extra + " — tap tap baru = jalan lain")
	else:
		ui.set_status("Belum ada draft jalan (min 2 titik)")

func _on_cancel_road() -> void:
	road.cancel_draft()
	ui.set_status("Draft jalan dibatalkan")

func _on_clear_all() -> void:
	placer.clear_all()
	terrain.clear_all()
	road.clear_all()
	_undo.clear()
	ui.set_status("Semua bangunan dihapus (tumpukan undo ikut dikosongkan)")

## Tombol OK (saat ada calon objek): penempatan DISAHKAN + masuk undo.
func _on_ok_pending() -> void:
	var rec := placer.commit_pending()
	if rec.is_empty():
		ui.set_status("Belum ada calon objek — tap tanah utk membuatnya")
		return
	_push_undo({"type": "obj_place", "idx": placer.objects.size() - 1})
	ui.set_pending_visible(false)
	ui.set_status(catalog.label_of(placer.current_id) + " TERSIMPAN di posisi itu ✓")

## Tombol BATAL (saat ada calon objek): buang/pulangkan calon.
func _on_cancel_pending() -> void:
	placer.cancel_pending()
	ui.set_pending_visible(false)
	ui.set_status("Calon objek dibatalkan")

## --- UNDO ("reverse" permintaan user: objek yg sdh ditaro bisa diambil
## lewat reverse; digeneralisasikan ke tile/jalan/binge) ---
func undo() -> void:
	if _undo.is_empty():
		ui.set_status("Tak ada aksi utk di-urungkan")
		return
	var act: Dictionary = _undo.pop_back()
	match String(act.get("type", "")):
		"obj_place":
			placer.remove_index(int(act.get("idx", -1)))
			ui.set_status("Reverse: objek terakhir DIAMBIL kembali")
		"obj_del":
			placer.restore_add([act["rec"]])
			ui.set_status("Reverse: objek yg terhapus dikembalikan")
		"tile_place":
			var prev: Dictionary = act.get("prev", {})
			if prev.is_empty():
				terrain.clear_cell(act["cell"])
			else:
				terrain.set_cell_explicit(act["cell"], int(prev["item"]), int(prev["rot"]))
			ui.set_status("Reverse: penempatan tile diurungkan")
		"tile_del":
			terrain.set_cell_explicit(act["cell"], int(act["item"]), int(act["rot"]))
			ui.set_status("Reverse: tile yg terhapus dikembalikan")
		"road_finish":
			road.remove_by_node(act.get("node"))
			placer.restore_add(act.get("grass", []))
			ui.set_status("Reverse: penyelesaian jalan diurungkan")
		"road_del":
			road.restore_road({"points": act["points"], "width": act["width"]})
			ui.set_status("Reverse: jalan yg terhapus dikembalikan")
		_:
			ui.set_status("Reverse tak dikenal?")

func _push_undo(act: Dictionary) -> void:
	_undo.append(act)
	while _undo.size() > UNDO_LIMIT:
		_undo.pop_front()

func _on_build_joy(v: Vector2) -> void:
	# Joystick Build = PAN peta (kamera top-down), BUKAN gerak badan —
	# permintaan user: full-layar tanpa ribet geser screen.
	var p := _player()
	if p and p.has_method("set_build_joy"):
		p.set_build_joy(v)

## ---------------- gestur layar (mode aktif) ----------------

func _unhandled_input(event: InputEvent) -> void:
	if not mode_active:
		return
	if event is InputEventScreenTouch:
		_on_touch(event as InputEventScreenTouch)
	elif event is InputEventScreenDrag:
		_on_drag(event as InputEventScreenDrag)

func _on_touch(e: InputEventScreenTouch) -> void:
	if e.pressed:
		_touches[e.index] = {
			"start": e.position,
			"time": Time.get_ticks_msec(),
			"moved_px": 0.0,
		}
		if _look_index == -1:
			_look_index = e.index
		elif _pinch_index == -1 and _look_index != -1:
			_pinch_index = e.index
			_pinch_last_dist = _touch_pair_dist()
	else:
		var info: Dictionary = _touches.get(e.index, {})
		_touches.erase(e.index)
		# selesaikan sesi genggam objek (kalau ada) — calon TETAP mengambang
		# menunggu dipindah tap/drag berikutnya atau disahkan tombol OK.
		if e.index == _grab_index:
			_grab_index = -1
		if e.index == _look_index:
			_look_index = -1
		if e.index == _pinch_index:
			_pinch_index = -1
		if not info.is_empty():
			var quick := int(Time.get_ticks_msec()) - int(info["time"]) <= TAP_MAX_MSEC
			var still := float(info["moved_px"]) <= TAP_MAX_DIST_PX
			# TAP bersih (cepat & tak bergeser) = aksi build; drag panjang
			# otomatis dipahami sbg pan peta / genggam objek (lihat _on_drag).
			if quick and still:
				_build_tap(e.position)

func _on_drag(e: InputEventScreenDrag) -> void:
	if not _touches.has(e.index):
		return
	_touches[e.index]["moved_px"] = float(_touches[e.index]["moved_px"]) + e.relative.length()
	# cubit 2 jari -> zoom kamera (tetap; berguna juga utk zoom top-down)
	if _pinch_index != -1:
		var d := _touch_pair_dist(e)
		if _pinch_last_dist > 0.0:
			var pz := _player()
			if pz and pz.has_method("add_zoom"):
				pz.add_zoom(-(d - _pinch_last_dist) * 0.012)
		_pinch_last_dist = d
		return
	# MODE OBJEK + tekan-lama dekat objek (calon/tersimpan) + GESER ->
	# OBJEK DIGERAKKAN (permintaan user: "bisa digeser pindah dulu kalo
	# tekan lama"). Begitu teranggap genggam, jari itu menggerakkan calon.
	if submode == "place" and e.index == _look_index:
		var info2: Dictionary = _touches.get(e.index, {})
		if not info2.is_empty():
			var age := int(Time.get_ticks_msec()) - int(info2["time"])
			if _grab_index == -1 and age >= LONG_PRESS_MSEC and float(info2["moved_px"]) > GRAB_START_PX:
				var hit_start := _ray_hit_plane(info2["start"])
				if hit_start[0]:
					_try_begin_grab(hit_start[1], e.index)
			if _grab_index == e.index:
				var hit_now := _ray_hit_plane(e.position)
				if hit_now[0]:
					placer.move_pending(hit_now[1])
				return   # jari ini memegang objek — JANGAN pan kamera sekaligus
	# satu jari -> PAN PETA (kamera top-down mode bangun; permintaan user:
	# "mode bangun langsung ganti kamera top-down ... full layar gk ribet").
	if e.index == _look_index:
		if float(_touches[e.index]["moved_px"]) > LOOK_DRAG_START_PX:
			var pp := _player()
			if pp and pp.has_method("add_pan_px"):
				pp.add_pan_px(e.relative.x, e.relative.y)

## Mulai sesi genggam objek bila START drag menunjuk: calon (pending) yg
## sedang ada, atau objek tertanam terdekat (yang langsung DIANGKAT jd
## calon supaya bisa digeser; konfirmasi dilakukan lewat tombol OK).
func _try_begin_grab(world_pos: Vector3, finger: int) -> void:
	if placer.has_pending():
		var pn: Node3D = placer._pending.get("node", null)
		if pn != null and (Vector3(pn.global_position.x, 0, pn.global_position.z) - Vector3(world_pos.x, 0, world_pos.z)).length() <= 3.0:
			_grab_index = finger
		return
	if placer.pickup_at(world_pos):
		_grab_index = finger
		ui.sync_rot_scale(placer.next_rot_y, placer.next_scale)
		ui.set_pending_visible(true)
		ui.set_status("Objek diangkat — geser lalu tekan OK utk simpan posisi")

## Raycast layar->world ANALITIS (kamera ray ∩ bidang y=0) — logika yg sama
## dipakai _build_tap, dibungkus supaya drag/jejak tap pakai dan identik.
func _ray_hit_plane(screen_pos: Vector2) -> Array:
	var cam := _camera()
	if cam == null:
		return [false, Vector3.ZERO]
	var origin := cam.project_ray_origin(screen_pos)
	var normal := cam.project_ray_normal(screen_pos)
	if absf(normal.y) < 0.0001:
		return [false, Vector3.ZERO]
	var t := -origin.y / normal.y
	if t <= 0.0 or t > 4000.0:
		return [false, Vector3.ZERO]
	return [true, origin + normal * t]

## dua sentuhan untuk pinch (dr event drag atau posisi yg disimpan)
func _touch_pair_dist(current_drag: InputEventScreenDrag = null) -> float:
	if _look_index == -1 or _pinch_index == -1:
		return 0.0
	var a: Vector2 = _touches[_look_index].get("start", Vector2.ZERO)
	var b: Vector2 = _touches[_pinch_index].get("start", Vector2.ZERO)
	if current_drag != null:
		if current_drag.index == _look_index:
			a = current_drag.position
		elif current_drag.index == _pinch_index:
			b = current_drag.position
	return a.distance_to(b)

## ---------------- aksi tap kosong (per sub-mode) ----------------

func _build_tap(screen_pos: Vector2) -> void:
	var cam := _camera()
	if cam == null:
		return
	var origin := cam.project_ray_origin(screen_pos)
	var normal := cam.project_ray_normal(screen_pos)
	# bidang tanah y=0 (analitis; dunia kita rata di plane itu)
	if absf(normal.y) < 0.0001:
		return
	var t := -origin.y / normal.y
	if t <= 0.0 or t > 4000.0:
		return
	var hit := origin + normal * t
	match submode:
		"place":
			if placer.has_pending():
				# ada calon: tap = pindahkan calon ke titik baru; OK utk simpan
				placer.move_pending(hit)
				ui.set_status("Calon dipindah — 'OK' simpan, 'BATAL' urungkan")
			else:
				var near_idx := placer.find_near_index(hit, placer._select_threshold())
				if near_idx >= 0:
					# TAP objek lama = seleksi (slider mengeditnya LIVE)
					placer.selected_idx = near_idx
					placer.next_rot_y = placer.objects[near_idx]["rot_y"]
					placer.next_scale = placer.objects[near_idx]["scale"]
					ui.sync_rot_scale(placer.next_rot_y, placer.next_scale)
					ui.set_status("Objek terseleksi → slider mengeditnya (tahan-lama utk memindahkannya)")
				elif placer.spawn_pending(hit):
					ui.set_pending_visible(true)
					ui.set_status("Calon objek mendarat — geser (tahan-drag) lalu tekan OK utk simpan")
		"terrain":
			if terrain.place_at(hit):
				_push_undo({"type": "tile_place", "cell": terrain.last_placed["cell"], "prev": terrain.last_placed["prev"]})
				ui.set_status("Tile %s dipasang" % _tile_name())
		"road":
			road.add_point(hit)
			ui.set_status("Titik jalan +1 (%d total)" % (road.active_curve.point_count if road.active_curve else 0))
		"delete":
			if placer.delete_at(hit):
				_push_undo({"type": "obj_del", "rec": placer.last_deleted})
				ui.set_status("Objek dihapus (Reverse utk mengembalikan)")
			elif terrain.delete_at(hit):
				_push_undo({"type": "tile_del", "cell": terrain.last_erased["cell"], "item": terrain.last_erased["item"], "rot": terrain.last_erased["rot"]})
				ui.set_status("Tile dihapus (Reverse utk mengembalikan)")
			elif road.delete_at(hit):
				_push_undo({"type": "road_del", "points": road.last_deleted["points"], "width": road.last_deleted["width"]})
				ui.set_status("Jalan dihapus (Reverse utk mengembalikan)")
			else:
				ui.set_status("Tak ada bangunan di titik itu")

## ---------------- save / load ----------------

func collect_data() -> Dictionary:
	return {
		"objects": placer.collect_data(),
		"terrain": {"cells": terrain.collect_data()},
		"roads": road.collect_data(),
	}

func save_map() -> void:
	var err := BuildSaveLoad.save_to(collect_data())
	if err.is_empty():
		ui.set_status("Map TERSIMPAN ✓ (%d objek, %d tile, %d jalan)" % [placer.objects.size(), terrain.cells_changed.size(), road.roads.size()])
	else:
		ui.set_status("GAGAL simpan: " + err)

func load_map() -> void:
	var data := BuildSaveLoad.load_from()
	if data.is_empty():
		ui.set_status("Belum ada file save")
		return
	_apply_data(data)
	ui.set_status("Map DIMUAT ✓")

func _apply_data(data: Dictionary) -> void:
	var terr: Dictionary = data.get("terrain", {})
	terrain.restore(terr.get("cells", []))
	placer.restore(data.get("objects", []))
	road.restore(data.get("roads", []))

## ---------------- util ----------------

func _camera() -> Camera3D:
	return get_viewport().get_camera_3d() if get_viewport() else null

func _player() -> Node:
	if world:
		var p = world.get("player")
		if p != null:
			return p
	return null

func _resolve_hud() -> void:
	if _hud:
		return
	if root_ref:
		var h = root_ref.get("hud")
		if h is CanvasLayer:
			_hud = h

## Dipakai dev_probe (fire_attack_check) — angka2 kunci tanpa menyentuh UI.
func debug_state() -> Dictionary:
	return {
		"active": mode_active,
		"submode": submode,
		"catalog_entries": catalog.entries.size(),
		"objects": placer.objects.size(),
		"tiles": terrain.cells_changed.size(),
		"roads": road.roads.size(),
		"meshlib_items": terrain.meshlib.get_item_list().size() if terrain.meshlib else 0,
	}
