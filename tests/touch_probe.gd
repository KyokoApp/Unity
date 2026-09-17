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

	# ---- 0) ROUTING GUI MENTAH pada Control polos ------------------------
	# Menjawab: apakah _gui_input dipanggil sama sekali untuk ScreenTouch
	# sintetis headless? Kalau kedua metode aksen, dua jalurnya jernih.
	var vs: Vector2 = root.get_visible_rect().size
	var c0 := GuiProbeControl.new()
	c0.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c0.mouse_filter = Control.MOUSE_FILTER_PASS
	root.add_child(c0)
	await process_frame
	await process_frame

	var mid := Vector2(vs.x * 0.5, vs.y * 0.5)
	Input.parse_input_event(_touch(3, mid, true))
	await process_frame
	await process_frame
	print("[routing] parse_input_event -> fired=", c0.fired, " ", c0.last_event)
	_chk(c0.fired, "parse_input_event: touch sampai ke _gui_input Control polos")

	c0.fired = false
	root.push_input(_touch(3, mid, true), false)
	await process_frame
	await process_frame
	print("[routing] push_input -> fired=", c0.fired, " ", c0.last_event)
	if not c0.fired and _pass > 0:
		print("[routing] push_input MATI di headless — seluruh probe pakai parse_input_event")
	Input.parse_input_event(_touch(3, mid, false))
	c0.queue_free()

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
	print("stick global_rect=", stick.get_global_rect(),
		" visible=", stick.is_visible_in_tree(),
		" mouse_filter=", stick.mouse_filter)
	# Kanvas headless bisa persegi (1920x1920) — posisi zona stik dihitung
	# dari BAWAH layar (offset -340..-34 piksel kanvas), bukan fraksi tinggi.
	var stick_pos := Vector2(vs.x * 0.22, vs.y - 100.0)
	_send(_touch(0, stick_pos, true))
	await process_frame
	await process_frame
	_chk(stick.is_active, "stik AKTIF setelah ScreenTouch di zona stik")
	_chk(stick._base.visible, "alas stik terlihat")

	# ---- 3) seret stik maju → sumbu > 0 → motor melaju -------------------
	_send(_drag(0, stick_pos + Vector2(0, -90), Vector2(0, -90)))
	await process_frame
	await process_frame
	print("axis=", stick.axis_value)
	_chk(stick.axis_value.y > 0.4, "dorong atas -> axis.y>0.4 (dapat %.2f)" % stick.axis_value.y)

	var p0: Vector3 = w.rig.global_position
	var saw_speed := false
	for i in 300:
		_send(_drag(0, stick_pos + Vector2(0, -90), Vector2.ZERO))
		await process_frame
		if w.motor.speed > 0.5:
			saw_speed = true
		if w.rig.global_position.distance_to(p0) > 1.0:
			break
	_chk(saw_speed, "motor melaju >0.5 m/s saat stik didorong")
	var moved: float = w.rig.global_position.distance_to(p0)
	print("rig berpindah=", moved)
	_chk(moved > 0.5, "rig berpindah >0.5 m (dapat %.2f m)" % moved)

	# ---- 4) lepas stik ---------------------------------------------------
	_send(_touch(0, stick_pos + Vector2(0, -90), false))
	await process_frame
	await process_frame
	_chk(not stick.is_active, "stik lepas setelah up")
	_chk(stick.axis_value.length() < 0.001, "axis kembali nol")

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

	# ---- 6) drag DI zona stik tidak memutar kamera ------------------------
	yaw0 = w.camera_rig.yaw
	var zc: Vector2 = Vector2(vs.x * 0.25, vs.y - 80.0)
	w.camera_rig._drag_id = -2147483648
	_send(_touch(9, zc, true))
	await process_frame
	for i in 4:
		_send(_drag(9, zc + Vector2(i * 20.0, 0), Vector2(20, 0)))
		await process_frame
	_send(_touch(9, zc, false))
	await process_frame
	var dyaw2: float = absf(w.camera_rig.yaw - yaw0)
	_chk(dyaw2 < 0.5, "drag di zona stik TIDAK memutar kamera (%.2f)" % dyaw2)

	print("== hasil: %d lulus, %d gagal ==" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
