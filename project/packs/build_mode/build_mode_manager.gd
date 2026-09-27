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

## ---------------- toggle & sub-mode ----------------

func toggle() -> void:
	mode_active = not mode_active
	if mode_active:
		_resolve_hud()
		if _hud:
			_hud.set("build_suspended", true)   # hud menahan gestur layar
		ui.show_panel(true)
		ui.set_status("Build Mode AKTIF — tap tanah sesuai sub-mode")
		placer.set_ghost_visible(submode == "place")
	else:
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
	submode = key
	ui.set_submode(key)
	placer.set_ghost_visible(key == "place")
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
		ui.set_status("Jalan dikunci ✓ (tap tap baru = jalan lain)")
	else:
		ui.set_status("Belum ada draft jalan (min 2 titik)")

func _on_cancel_road() -> void:
	road.cancel_draft()
	ui.set_status("Draft jalan dibatalkan")

func _on_clear_all() -> void:
	placer.clear_all()
	terrain.clear_all()
	road.clear_all()
	ui.set_status("Semua bangunan dihapus")

func _on_build_joy(v: Vector2) -> void:
	var p := _player()
	if p and p.has_method("set_joy"):
		p.set_joy(v)

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
		# TAP bersih = aksi build (cepat & nyaris tak bergeser)
		var was_look := e.index == _look_index
		if e.index == _look_index:
			_look_index = -1
		if e.index == _pinch_index:
			_pinch_index = -1
		if not info.is_empty():
			var quick := int(Time.get_ticks_msec()) - int(info["time"]) <= TAP_MAX_MSEC
			var still := float(info["moved_px"]) <= TAP_MAX_DIST_PX
			# TAP bersih (cepat & tak bergeser) = aksi build; drag panjang
			# otomatis dipahami sbg gestur kamera (lihat _on_drag).
			if quick and still:
				_build_tap(e.position)

func _on_drag(e: InputEventScreenDrag) -> void:
	if not _touches.has(e.index):
		return
	_touches[e.index]["moved_px"] = float(_touches[e.index]["moved_px"]) + e.relative.length()
	# cubit 2 jari -> zoom kamera
	if _pinch_index != -1:
		var d := _touch_pair_dist(e)
		if _pinch_last_dist > 0.0:
			var p := _player()
			if p and p.has_method("add_zoom"):
				p.add_zoom(-(d - _pinch_last_dist) * 0.012)
		_pinch_last_dist = d
		return
	# satu jari -> putar kamera (gestur look yg sama dgn gameplay)
	if e.index == _look_index:
		if float(_touches[e.index]["moved_px"]) > LOOK_DRAG_START_PX:
			var pl := _player()
			if pl and pl.has_method("add_look_px"):
				pl.add_look_px(-e.relative.x, -e.relative.y)

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
			var r := placer.tap_place(hit)
			if r == 1:
				# objek lama terseleksi -> sinkronkan slider UI ke nilainya
				ui.sync_rot_scale(placer.next_rot_y, placer.next_scale)
				ui.set_status("Objek terseleksi → slider mengeditnya (tap tanah kosong utk taruh baru)")
			elif r == 2:
				ui.set_status(catalog.label_of(placer.current_id) + " ditaruh")
		"terrain":
			if terrain.place_at(hit):
				ui.set_status("Tile %s dipasang" % _tile_name())
		"road":
			road.add_point(hit)
			ui.set_status("Titik jalan +1 (%d total)" % (road.active_curve.point_count if road.active_curve else 0))
		"delete":
			if placer.delete_at(hit):
				ui.set_status("Objek dihapus")
			elif terrain.delete_at(hit):
				ui.set_status("Tile dihapus")
			elif road.delete_at(hit):
				ui.set_status("Jalan dihapus")
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
