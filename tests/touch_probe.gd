extends SceneTree

## ============================================================
## TOUCH PROBE — uji end-to-end input sentuh & pemain (headless).
##
## Menangkap regresi resep-bug:: HudRoot menelan sentuhan, stik/
## kamera mati, rig pemain terkubur di y=0. Semua regresi itu
## lolos sebelumnya karena boot tanpa probe ini tetap "bersih".
##
## Dijalankan di CI: Godot --headless --path . -s res://tests/touch_probe.gd
## ============================================================

var _pass := 0
var _fail := 0
var _use_parse := true   ## metode injeksi yang terbukti mengantar sentuhan

func _chk(cond: bool, note: String) -> void:
	if cond:
		_pass += 1
		print("PROBEPASS  ", note)
	else:
		_fail += 1
		print("PROBEFAIL  ", note)

func _touch(idx: int, pos: Vector2, pressed: bool) -> InputEventScreenTouch:
	var e := InputEventScreenTouch.new()
	e.index = idx
	e.position = pos
	e.pressed = pressed
	return e

func _drag(idx: int, pos: Vector2, rel: Vector2) -> InputEventScreenDrag:
	var e := InputEventScreenDrag.new()
	e.index = idx
	e.position = pos
	e.relative = rel
	return e

func _send(e: InputEvent) -> void:
	if _use_parse:
		Input.parse_input_event(e)
	else:
		root.push_input(e, false)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	print("== touch probe ==")

	# CATATAN (terbukti CI): routing ScreenTouch -> _gui_input MATI di
	# headless DisplayServer (fired=false untuk Control polos — dua metode
	# injeksi). Jadi jalur GUI diuji DETERMINISTIS dengan memanggil
	# _gui_input langsung; jalur _unhandled_input kamera diuji lewat
	# routing asli (terbukti bekerja). Di device nyata GUI touch hidup —
	# jaminannya adalah tombol/stik Godot mobile standar.
	print("[routing] GUI touch headless: MATI (diketahui) — uji _gui_input langsung")
	var vs: Vector2 = root.get_visible_rect().size

	# ---- dunia -----------------------------------------------------------
	var w = load("res://scenes/world.tscn").instantiate()
	root.add_child(w)

	# Tunggu boot selesai (batas 3000 frame).
	var guard := 0
	while not w.boot_done and guard < 3000:
		guard += 1
		await process_frame
	_chk(w.boot_done, "boot selesai dalam %d frame" % guard)

	vs = root.get_visible_rect().size
	print("viewport: ", vs)
	var hud = w.hud
	_chk(hud != null and hud.visible, "HUD terlihat setelah boot")

	# ---- 1) rig pemain menempel ke tanah (bukan terkubur di y=0) ---------
	var g_y: float = WorldData.terrain_h(w.rig.global_position.x, w.rig.global_position.z)
	var dy: float = absf(w.rig.global_position.y - g_y)
	print("rig y=", w.rig.global_position.y, " terrain=", g_y, " selisih=", dy)
	_chk(dy < 0.15, "rig pemain di atas tanah (selisih %.3f m)" % dy)
	_chk(w.rig.global_position.y > 0.01 or g_y <= 0.01,
		"rig TIDAK terkubur di y=0 (y=%.3f)" % w.rig.global_position.y)

	# ---- 2) stik merespons sentuhan di zona stik -------------------------
	var stick = hud.stick
	_chk(stick != null, "StickZone ada")
	_chk(stick._ghost.visible, "cincin hantu (petunjuk visual) terlihat saat siaga")
	print("stick global_rect=", stick.get_global_rect(),
		" visible=", stick.is_visible_in_tree(),
		" mouse_filter=", stick.mouse_filter)
	# Kanvas headless bisa persegi (1920x1920) — posisi zona stik dihitung
	# dari BAWAH layar (offset -340..-34 piksel kanvas), bukan fraksi tinggi.
	# PENTING: _gui_input menerima koordinat LOKAL control (engine sudah
	# xform) — make_input_local meniru delivery OS yang sesungguhnya.
	var stick_pos := Vector2(vs.x * 0.22, vs.y - 100.0)
	stick._gui_input(stick.make_input_local(_touch(0, stick_pos, true)))
	await process_frame
	await process_frame
	_chk(stick.is_active, "stik AKTIF setelah ScreenTouch di zona stik")
	_chk(stick._base.visible, "alas stik terlihat")
	_chk(not stick._ghost.visible, "cincin hantu sembunyi saat stik aktif")
	_chk(stick.gui_hits >= 1, "penghitung stikGUI berjalan (gui_hits=%d)" % stick.gui_hits)

	# ---- 3) seret stik maju → sumbu > 0 → motor melaju -------------------
	stick._gui_input(stick.make_input_local(
		_drag(0, stick_pos + Vector2(0, -260), Vector2(0, -260))))
	await process_frame
	await process_frame
	print("axis=", stick.axis_value)
	_chk(stick.axis_value.y > 0.9, "dorong atas -> axis tinggi >0.9 (dapat %.2f)" % stick.axis_value.y)

	var p0: Vector3 = w.rig.global_position
	var saw_speed := false
	for i in 300:
		stick._gui_input(stick.make_input_local(
			_drag(0, stick_pos + Vector2(0, -260), Vector2.ZERO)))
		await process_frame
		if w.motor.speed > 0.5:
			saw_speed = true
		if w.rig.global_position.distance_to(p0) > 1.0:
			break
	_chk(saw_speed, "motor melaju >0.5 m/s saat stik didorong")
	var moved: float = w.rig.global_position.distance_to(p0)
	print("rig berpindah=", moved)
	_chk(moved > 0.5, "rig berpindah >0.5 m (dapat %.2f m)" % moved)
	_chk(stick.drags_seen >= 2, "penghitung seret stik berjalan (drags=%d)" % stick.drags_seen)

	# ---- 4) lepas stik ---------------------------------------------------
	stick._gui_input(stick.make_input_local(
		_touch(0, stick_pos + Vector2(0, -260), false)))
	await process_frame
	await process_frame
	_chk(not stick.is_active, "stik lepas setelah up")
	_chk(stick.axis_value.length() < 0.001, "axis kembali nol")
	_chk(stick._ghost.visible, "cincin hantu tampil lagi setelah lepas")

	# ---- 5) drag di luar zona stik memutar kamera -------------------------
	var yaw0: float = w.camera_rig.yaw
	var cam_pos := Vector2(vs.x * 0.75, vs.y * 0.45)
	_send(_touch(7, cam_pos, true))
	await process_frame
	for i in 8:
		_send(_drag(7, cam_pos + Vector2(i * 20.0, 0), Vector2(20, 0)))
		await process_frame
	_send(_touch(7, cam_pos + Vector2(160, 0), false))
	await process_frame
	var dyaw: float = w.camera_rig.yaw - yaw0
	print("dyaw=", dyaw)
	_chk(absf(dyaw) > 1.0, "drag kanan memutar yaw (%.2f derajat)" % dyaw)

	# ---- 5b) TouchDebug membuktikan routing OS -> Node._input ------------
	_chk(w.touch_debug != null, "TouchDebug terpasang di world")
	_chk(TouchDebug.enabled, "TouchDebug nyala di build debug/editor")
	_chk(w.touch_debug._downs >= 1,
		"touch-down OS sampai ke Node._input (downs=%d)" % w.touch_debug._downs)
	_chk(w.touch_debug._drags >= 1,
		"seretan OS sampai ke Node._input (drags=%d)" % w.touch_debug._drags)
	_chk(w.touch_debug._cam_presses >= 1,
		"kamera melaporkan sentuhan (cam=%d)" % w.touch_debug._cam_presses)

	# ---- 6) drag DI zona stik tidak memutar kamera ------------------------
	yaw0 = w.camera_rig.yaw
	var zc: Vector2 = Vector2(vs.x * 0.25, vs.y - 80.0)
	w.camera_rig._drag_id = -2147483648
	w.camera_rig._unhandled_input(_touch(9, zc, true))
	await process_frame
	for i in 4:
		w.camera_rig._unhandled_input(_drag(9, zc + Vector2(i * 20.0, 0), Vector2(20, 0)))
		await process_frame
	w.camera_rig._unhandled_input(_touch(9, zc, false))
	await process_frame
	var dyaw2: float = absf(w.camera_rig.yaw - yaw0)
	_chk(dyaw2 < 0.5, "drag di zona stik TIDAK memutar kamera (%.2f)" % dyaw2)

	# ---- 7) AnimDriver: klip GLB menggantikan jalur prosedural ----------
	# Model animasi SINTETIS (tanpa aset user): skeleton + AnimationPlayer
	# berisi klip Idle/Walk/Run/Attack*. Membuktikan seleksi klip,
	# strip_xz anti root-motion, loop lokomosi, state machine lokomosi,
	# one-shot serangan, dan kembali ke fallback mannequin dengan selamat.
	var fake_root := Node3D.new()
	fake_root.name = "FakeChar"
	var fskel := Skeleton3D.new()
	fskel.name = "Skeleton3D"
	fake_root.add_child(fskel)
	var b0 := fskel.add_bone("Hips")
	var b1 := fskel.add_bone("Spine")
	fskel.set_bone_parent(b1, b0)
	fskel.set_bone_rest(b0, Transform3D(Basis(), Vector3(0, 1.0, 0)))
	fskel.set_bone_rest(b1, Transform3D(Basis(), Vector3(0, 0.2, 0)))
	var fmesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.6, 1.6, 0.4)
	fmesh.mesh = box
	fmesh.position = Vector3(0, 0.8, 0)
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0.8, 0.3, 0.3)
	fmesh.material_override = smat
	fake_root.add_child(fmesh)
	var fap := AnimationPlayer.new()
	fap.name = "AnimationPlayer"
	fake_root.add_child(fap)
	var lib := AnimationLibrary.new()
	lib.add_animation("Idle", _mk_clip("Skeleton3D:Hips", 1.2))
	lib.add_animation("Walk", _mk_clip("Skeleton3D:Hips", 0.8))
	lib.add_animation("Run", _mk_clip("Skeleton3D:Hips", 0.6))
	lib.add_animation("Attack1", _mk_clip("Skeleton3D:Hips", 0.5))
	lib.add_animation("Attack2", _mk_clip("Skeleton3D:Hips", 0.5))
	lib.add_animation("Attack3", _mk_clip("Skeleton3D:Hips", 0.7))
	fap.add_animation_library("", lib)
	_own_tree(fake_root, fake_root)
	var ps := PackedScene.new()
	var pack_ok := ps.pack(fake_root)
	_chk(pack_ok == OK, "model sintetis ter-pack ke PackedScene (%d)" % pack_ok)
	w.rig.model_scene = ps
	w.rig.bind()
	_chk(w.rig.anim_active, "rig mengaktifkan AnimDriver untuk klip GLB")
	_chk(w.rig.anim.mapping.get("idle", "") == "Idle",
		"idle terpetakan ke 'Idle' (dapat %s)" % w.rig.anim.mapping.get("idle", ""))
	_chk(w.rig.anim.mapping.get("run", "") == "Run",
		"run terpetakan ke 'Run' (dapat %s)" % w.rig.anim.mapping.get("run", ""))
	_chk(w.rig.anim.mapping.get("attack1", "") == "Attack2",
		"attack1 terpetakan ke 'Attack2' (dapat %s)" % w.rig.anim.mapping.get("attack1", ""))
	var aw: Animation = w.rig.anim.player.get_animation("Walk")
	_chk(aw != null, "klip walk terpasang di CharAnimPlayer")
	var kv: Vector3 = aw.track_get_key_value(0, 1)
	_chk(absf(kv.x) < 1e-6 and absf(kv.z) < 1e-6,
		"strip_xz menolkan XZ klip walk (dapat %s)" % str(kv))
	_chk(aw.loop_mode == Animation.LOOP_LINEAR, "klip lokomosi LOOP_LINEAR")
	w.rig.drive_anim({"speed": 0.0, "grounded": true, "falling": false,
		"dashing": false, "move": 0.0}, 0.016)
	_chk(w.rig.anim.current_role == "idle",
		"drive siaga -> idle (dapat %s)" % w.rig.anim.current_role)
	w.rig.drive_anim({"speed": 13.5, "grounded": true, "falling": false,
		"dashing": false, "move": 1.0}, 0.016)
	_chk(w.rig.anim.current_role == "run",
		"drive lari -> run (dapat %s)" % w.rig.anim.current_role)
	w.rig.anim_attack(1)
	_chk(w.rig.anim.current_role == "attack1",
		"serang kombo 1 -> attack1 (dapat %s)" % w.rig.anim.current_role)
	for i in 50:
		w.rig.drive_anim({"speed": 0.0, "grounded": true, "falling": false,
			"dashing": false, "move": 0.0}, 0.016)
		await process_frame
	_chk(w.rig.anim.current_role == "idle",
		"one-shot selesai -> kembali idle (dapat %s)" % w.rig.anim.current_role)
	# Kembalikan fallback mannequin: jalur lama harus tetap hidup.
	w.rig.model_scene = null
	w.rig.bind()
	_chk(not w.rig.anim_active, "bind ulang -> kembali fallback prosedural")
	_chk(w.rig.is_bound, "mannequin terikat (is_bound) setelah bind ulang")
	fake_root.queue_free()

	print("== hasil: %d lulus, %d gagal ==" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

## Klip posisi satu tulang dengan XZ TIDAK nol (uji strip_xz).
func _mk_clip(bone_path: String, dur: float) -> Animation:
	var a := Animation.new()
	a.length = dur
	var t := a.add_track(Animation.TYPE_POSITION_3D)
	a.track_set_path(t, NodePath(bone_path))
	a.track_insert_key(t, 0.0, Vector3(0, 1.0, 0))
	a.track_insert_key(t, dur, Vector3(0.4, 1.05, 0.3))
	return a

func _own_tree(n: Node, o: Node) -> void:
	for c in n.get_children():
		c.owner = o
		_own_tree(c, o)
