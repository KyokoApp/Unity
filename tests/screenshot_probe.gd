extends SceneTree

## ============================================================
## SCREENSHOT PROBE — memanggang 4 jepretan NYATA dari game ini.
##
## Jalan di RUNNER bawah Xvfb (lihat .github/workflows/screenshot.yml)
## dengan rendering software — viewport asli, bukan dummy headless.
## Empat sudut pandang jepretan: siaga, hadap kamera, berlari,
## tengah serangan. Keluar ke /tmp/shots/*.png.
##
## Bila models/ ada (cache aset CI) → karakter pengguna yang
## terscreenshot; kalau tidak → fallback mannequin.
## ============================================================

var _saved := 0

func _init() -> void:
	print("== SCREENSHOT PROBE ==")
	DisplayServer.window_set_size(Vector2i(1280, 720))

	var w = load("res://scenes/world.tscn").instantiate()
	root.add_child(w)

	var guard := 0
	while not w.boot_done and guard < 3000:
		guard += 1
		await process_frame
	print("boot selesai frame=", guard)

	# Ekstra buffer: tekstur & chunk terrain selesai menuntaskan
	# frame pertama pada renderer software.
	for i in 90:
		await process_frame

	# Bukti faktual ke log: nama klip PERSIS seperti yang Godot lihat
	# + peta peran + laporan bind (model/kalibrasi/tekstur).
	print("REPORTB %s" % w.rig.last_bind_report)
	if w.rig.anim != null:
		print("REPORTA %s" % w.rig.anim.last_report)
		print("REPORTM mapping=%s" % str(w.rig.anim.mapping))
	print("REPORTT tex=%d/%d" % [ToonCharacterSetup.last_tex,
		ToonCharacterSetup.last_hadir])

	await _shoot("shot1_idle.png")

	## Balik karakter menghadap kamera (motor hanya memutar rig saat
	## ada input/serangan — saat siaga rotasi bebas kita set).
	w.rig.rotation.y = PI
	for i in 45:
		await process_frame
	await _shoot("shot2_face.png")
	w.rig.rotation.y = 0.0

	## Berlari: jalur GUI stik asli (persis touch_probe) — kanan-atas.
	var hud = w.hud
	var stick = hud.stick
	var vs: Vector2 = root.get_visible_rect().size
	var stick_pos := Vector2(vs.x * 0.22, vs.y - 100.0)
	stick._gui_input(stick.make_input_local(_touch(0, stick_pos, true)))
	await process_frame
	stick._gui_input(stick.make_input_local(
		_drag(0, stick_pos + Vector2(160, -110), Vector2(160, -110))))
	for i in 55:
		await process_frame
	await _shoot("shot3_run.png")
	stick._gui_input(stick.make_input_local(
		_touch(0, stick_pos + Vector2(160, -110), false)))
	for i in 30:
		await process_frame

	## Serang: sinyal HUD asli -> motor -> combo + klip Sword_Regular_A.
	hud.pressed_attack.emit()
	for i in 13:
		await process_frame
	await _shoot("shot4_attack.png")

	## Varian siaga ke-2 (pilih nanti): paksa mapping idle ke
	## Idle_Lantern lalu tenangkan 45 frame — membantu memilih
	## kandidat siaga final paket UAL2 tanpa menebak.
	if w.rig.anim != null and w.rig.anim.mapping.has("idle"):
		var cadangan: String = w.rig.anim.mapping["idle"]
		for varian in [["Idle_Lantern", "shot5_idle2.png"],
				["Idle_Rail", "shot6_idle3.png"],
				["A_TPose", "shot7_tpose.png"]]:
			w.rig.anim.mapping["idle"] = varian[0]
			w.rig.anim.current_role = ""
			for i in 50:
				await process_frame
			await _shoot(varian[1])
		w.rig.anim.mapping["idle"] = cadangan
		w.rig.anim.current_role = ""

	print("== jepretan tersimpan: %d ==" % _saved)
	quit(0 if _saved >= 4 else 1)

func _shoot(nama: String) -> void:
	# frame_post_draw = kandungan viewport sudah final di renderer.
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	var path := "/tmp/shots/" + nama
	var err := img.save_png(path)
	print("JEPRET %s err=%d" % [path, err])
	if err == OK:
		_saved += 1
	await process_frame

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
