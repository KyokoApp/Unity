extends Node3D
## GameRoot: dirakit dari resource pack setelah launcher memuat semuanya.
## Alur boot: pengaturan -> loading screen -> generate dunia async -> spawn
## pemain di pantai -> HUD -> mulai. Juga mengurus pause, auto-pause saat
## aplikasi ke background, dan tombol back Android.

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

func _ready() -> void:
	# info dari launcher (offline/server/versi)
	var cfg := ConfigFile.new()
	if cfg.load("user://boot.cfg") == OK:
		_boot = {"offline": cfg.get_value("boot", "offline", false),
				"game_version": cfg.get_value("boot", "game_version", "?")}
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
	_start_loading()

func _start_loading() -> void:
	var lp = load(LOADING_SCENE)
	if lp == null:
		push_error("[game] loading screen tidak ditemukan")
		_finish_boot_fail()
		return
	loading = lp.instantiate()
	add_child(loading)
	var snapped: Callable = Callable(self, "_boot_world")
	loading.call("begin", snapped)

func _boot_world(progress_cb: Callable) -> void:
	# dipanggil dari loading screen; generate dunia bertahap
	var wp = load(WORLD_SCENE)
	world = wp.instantiate()
	add_child(world)
	if world.has_signal("gen_progress"):
		world.gen_progress.connect(progress_cb)
	await world.generate_async(self)
	progress_cb.call(1.0, "Menempatkan pemain…")
	player = load(PLAYER_SCENE).instantiate()
	add_child(player)
	var spawn = world.call("find_spawn_point")
	player.global_position = spawn + Vector3(0, 0.6, 0)
	player.call("set_world", world)
	player.call("set_settings", settings)
	quality.apply_all()  # shadow sudah terdaftar
	await get_tree().process_frame
	var hp = load(HUD_SCENE)
	hud = hp.instantiate()
	add_child(hud)
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
