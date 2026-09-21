extends Node3D
## GameRoot: dirakit dari resource pack setelah launcher memuat semuanya.
## Alur boot: pengaturan -> loading screen -> generate dunia async -> spawn
## pemain di pantai -> HUD -> mulai. Juga mengurus pause, auto-pause saat
## aplikasi ke background, dan tombol back Android.
## Diagnostik: setiap tahap mencetak label kecil di layar; kegagalan
## memicu panel merah penuh teks (supaya pengguna bisa memfoto penyebabnya).

const SettingsScript := preload("res://packs/core_scripts/game_settings.gd")
const QualityScript := preload("res://packs/core_scripts/quality_manager.gd")
const WORLD_SCENE := "res://packs/world_terrain/world.tscn"
const PLAYER_SCENE := "res://packs/character_player/player.tscn"
const HUD_SCENE := "res://packs/ui/hud.tscn"
const LOADING_SCENE := "res://packs/ui/loading_screen.tscn"
const PAUSE_SCENE := "res://packs/ui/pause_menu.tscn"

var settings
var quality
var world: Node3D
var player: Node3D
var hud: CanvasLayer
var loading: CanvasLayer
var pause_menu: CanvasLayer
var _boot := {}
var _trail: Label
var _fatal_layer: CanvasLayer
var _boot_ok := false
var _last_trace := "(belum ada tahap)"
const BOOT_LOG_PATH := "user://boot_log.txt"
var _blog_lines: Array = []

func _blog(msg: String) -> void:
	var line := "[%s] %s" % [Time.get_time_string_from_system(false), msg]
	_blog_lines.append(line)
	if _blog_lines.size() > 400:
		_blog_lines = _blog_lines.slice(-360)
	var f := FileAccess.open(BOOT_LOG_PATH, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(_blog_lines))
		f.close()

func _trace(msg: String) -> void:
	_last_trace = msg
	_blog(msg)
	print("[boot] ", msg)
	if _trail == null:
		_trail = Label.new()
		_trail.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
		_trail.add_theme_font_size_override("font_size", 16)
		_trail.add_theme_color_override("font_color", Color(1, 0.95, 0.55, 0.9))
		_trail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var cl := CanvasLayer.new()
		cl.layer = 99
		cl.name = "BootTrail"
		cl.add_child(_trail)
		add_child(cl)
	_trail.text = msg

func _fatal(msg: String) -> void:
	push_error("[game] FATAL: " + msg)
	_fatal_layer = CanvasLayer.new()
	_fatal_layer.layer = 100
	add_child(_fatal_layer)
	var bg := ColorRect.new()
	bg.color = Color(0.35, 0.05, 0.08, 1)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fatal_layer.add_child(bg)
	# gulung dari ATAS (tengah layar dibiarkan pendek): teks panjang tak pernah
	# keluar tepi bawah — bug layar foto ronde-16: ekor log terpotong
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fatal_layer.add_child(scroll)
	var l := Label.new()
	l.text = "A-SEKAI — BOOT GAGAL\n\n" + msg + "\n\n(foto layar ini untuk laporan)"
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_font_size_override("font_size", 24)
	scroll.add_child(l)
	_fatal_layer.visible = true
	# jangan keluar — biarkan pengguna membaca pesan

func _ready() -> void:
	# info dari launcher (offline/server/versi)
	var cfg := ConfigFile.new()
	if cfg.load("user://boot.cfg") == OK:
		_boot = {"offline": cfg.get_value("boot", "offline", false),
				"game_version": cfg.get_value("boot", "game_version", "?")}
	# header diagnostik — membaca meringkas keadaan perangkat untuk identifikasi bug
	_blog("=== BOOT BARU ===")
	_blog("device: %s | OS: %s" % [OS.get_model_name(), OS.get_name()])
	_blog("renderer: %s | jagat: %s" % [
		str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "?")),
		RenderingServer.get_video_adapter_name()])
	_blog("godot %s | game v%s | %dx%d" % [
		Engine.get_version_info().get("string", "?"), _boot.get("game_version", "?"),
		DisplayServer.window_get_size().x, DisplayServer.window_get_size().y])
	# watchdog: bila boot macet, tampilkan penyebabnya — JANGAN PERNAH blue screen diam-diam
	var wd := get_tree().create_timer(40.0)
	wd.timeout.connect(_on_boot_watchdog)
	_trace("boot: pengaturan…")
	settings = SettingsScript.new()
	settings.name = "GameSettings"
	add_child(settings)
	settings.load_settings()
	quality = QualityScript.new()
	quality.name = "QualityManager"
	quality.settings = settings
	add_child(quality)
	settings.changed.connect(quality.on_settings_changed)
	quality.apply_all()
	_trace("boot: kualitas ✔, memuat UI…")
	_start_loading()

func _start_loading() -> void:
	var lp = load(LOADING_SCENE)
	if lp == null:
		_fatal("Scene loading hilang:\n" + LOADING_SCENE)
		return
	loading = lp.instantiate()
	add_child(loading)
	_trace("boot: loading screen ✔, membangun dunia…")
	var snapped: Callable = Callable(self, "_boot_world")
	loading.call("begin", snapped)

func _boot_world(progress_cb: Callable) -> void:
	# dipanggil dari loading screen; generate dunia bertahap
	var wp = load(WORLD_SCENE)
	if wp == null:
		_fatal("Scene dunia hilang:\n" + WORLD_SCENE)
		return
	world = wp.instantiate()
	add_child(world)
	if world.has_signal("gen_progress"):
		world.gen_progress.connect(progress_cb)
	if world.get("faceted") != null and settings.get("gfx_faceted") != null:
		world.faceted = settings.gfx_faceted  # gaya low-poly dari pengaturan (sebelum chunk awal)
	await world.generate_async(self)
	# terapkan pencahayaan hasil Mode Edit (tersimpan di pengaturan)
	if world.has_method("apply_lighting"):
		world.apply_lighting({
			"sun": settings.light_sun, "ambient": settings.light_ambient,
			"fog": settings.light_fog, "sky": settings.light_sky})
	progress_cb.call(1.0, "Menempatkan pemain…")
	_trace("boot: dunia ✔, pemain…")
	var pp = load(PLAYER_SCENE)
	if pp == null:
		_fatal("Scene pemain hilang:\n" + PLAYER_SCENE)
		return
	player = pp.instantiate()
	player.set("char_skin", settings.char_skin)  # skin dari pengaturan (dipakai _ready)
	add_child(player)
	# FAILSAFE kick-41: bila script pack gagal menempel (token tidak cocok /
	# pck rusak), instantiate() tetap mengembalikan node dan boot "sukses" —
	# padahal pemain tak bertulang. Permukaan-kan TEGAS daripada diam-diam.
	if player.get_script() == null:
		_fatal("Pack PEMAIN rusak (script tidak terpasang).\nMinta unggah ulang konten / kosongkan cache update.")
	var spawn = world.call("find_spawn_point")
	player.global_position = spawn + Vector3(0, 0.12, 0)
	player.call("set_world", world)
	player.call("set_settings", settings)
	quality.apply_all()  # shadow sudah terdaftar
	await get_tree().process_frame
	var hp = load(HUD_SCENE)
	if hp == null:
		_fatal("Scene HUD hilang:\n" + HUD_SCENE)
		return
	hud = hp.instantiate()
	add_child(hud)
	if hud.get_script() == null:
		_fatal("Pack UI rusak (script tidak terpasang).\nMinta unggah ulang konten / kosongkan cache update.")
	hud.call("bind_player", player)
	hud.call("bind_root", self)
	hud.call("set_settings", settings)
	world.call("set_player", player)
	# audio latar (opsional bila pack ada)
	if ResourceLoader.exists("res://packs/audio_music/audio_director.gd"):
		var ad = load("res://packs/audio_music/audio_director.gd").new()
		add_child(ad)
		ad.setup(world, player)
	progress_cb.call(1.0, "Selesai")
	_boot_ok = true
	_trace("boot: HUD ✔ — selamat bermain")
	# jejak boot bertahan 20 dtk (dulu 3): probe animasi on-device butuh waktu
	# sampai user mulai berjalan; setelah itu jalan playa bersihkan diri sendiri
	get_tree().create_timer(20.0).timeout.connect(func():
		if is_instance_valid(_trail):
			_trail.get_parent().queue_free()
			_trail = null
	)

func _on_boot_watchdog() -> void:
	if _boot_ok:
		return
	var tail := ""
	var n := _blog_lines.size()
	for i in range(maxi(0, n - 9), n):
		tail += str(_blog_lines[i]) + "\n"
	_fatal("Boot macet lebih dari 40 detik.\nTahap terakhir:\n%s\n\nLog ekor (%s):\n%s\n\nFoto layar ini." % [
		_last_trace, OS.get_model_name(), tail])

func on_loading_done() -> void:
	if loading:
		loading.queue_free()
		loading = null
	if _boot.get("offline", false) and hud and hud.has_method("toast"):
		hud.call("toast", "Mode offline — konten lokal dipakai")

func _finish_boot_fail() -> void:
	get_tree().quit(1)

# ---------------- pause ----------------

func toggle_pause() -> void:
	if pause_menu:
		_close_pause()
	else:
		_open_pause()

func _open_pause() -> void:
	if pause_menu:
		return
	pause_menu = load(PAUSE_SCENE).instantiate()
	add_child(pause_menu)
	pause_menu.call("bind", self, settings)
	get_tree().paused = true

func _close_pause() -> void:
	if pause_menu:
		get_tree().paused = false
		pause_menu.queue_free()
		pause_menu = null

## Dipanggil dari pause menu: tutup menu (unpause) lalu aktifkan Mode Edit HUD.
func enter_edit_mode() -> void:
	_close_pause()
	if hud and hud.has_method("set_edit_mode"):
		hud.set_edit_mode(true)

func quit_to_launcher() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://launcher/launcher.tscn")

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause_menu"):
		toggle_pause()

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			# game otomatis pause saat aplikasi ke background
			if not get_tree().paused and player != null:
				_open_pause()
		NOTIFICATION_WM_GO_BACK_REQUEST:
			toggle_pause()
