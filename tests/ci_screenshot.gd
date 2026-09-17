extends SceneTree

## ============================================================
## CI SCREENSHOT — menjalankan game sungguhan di runner GitHub
## (renderer perangkat-lunak llvmpipe di bawah xvfb), menunggu
## loading selesai, lalu menyimpan tangkapan layar ke /tmp:
##   shot_a.png — tampilan standar (kamera default, jam emas)
##   shot_b.png — CLOSE-UP karakter dari depan (jarak 3,1 m,
##                kamera diputar ~170° supaya wajah terlihat)
##   shot_c.png — kamera balik lagi (acuan bermain)
## Hasil di-upload workflow ci-screenshot ke branch ci-logs
## (folder shots/), supaya kita bisa MEMBANDINGKAN visual game
## dengan gambar referensi pengguna langsung di chat.
## Strip debug disertakan — barang bukti (stempel/anim/tekstur)
## tetap tampak pada screenshot.
## ============================================================

var _w: Node

func _init() -> void:
	_run()

func _run() -> void:
	# Ukuran jendela konsisten supaya layout HUD bisa dibandingkan.
	root.size = Vector2i(1280, 720)
	root.mode = Window.MODE_WINDOWED
	await process_frame

	var packed: PackedScene = load("res://scenes/world.tscn")
	_w = packed.instantiate()
	root.add_child(_w)

	# Tunggu loading + impor chunk + settle render (240 frame ≈ 4 dtk
	# virtual; di llvmpipe bisa lebih lambat fisiknya, tidak apa).
	for i in 240:
		await process_frame
	_ambil("shot_a")

	# Close-up karakter dari depan.
	var rig: Node = _w.get("camera_rig")
	if rig != null:
		rig.call("set_distance", 3.1)
		rig.set("yaw", float(rig.get("yaw")) + 170.0)
	for i in 45:
		await process_frame
	_ambil("shot_b")

	# Kembali ke sudut bermain.
	if rig != null:
		rig.call("set_distance", 5.0)
		rig.set("yaw", float(rig.get("yaw")) - 170.0)
	for i in 45:
		await process_frame
	_ambil("shot_c")
	quit(0)

func _ambil(nama: String) -> void:
	var img := root.get_texture().get_image()
	var path := "/tmp/%s.png" % nama
	var err := img.save_png(path)
	print("CSI %s -> %s err=%d (%dx%d)" % [nama, path, err,
		img.get_width(), img.get_height()])
