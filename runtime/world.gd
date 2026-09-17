class_name World
extends Node3D

## ============================================================
## WORLD — komposer seluruh scene + urutan boot.
## (Padanan Stage2SceneBuilder/BuildWorld + WorldBoot di Unity.)
##
## Scene world.tscn adalah root kosong satu node ini: seluruh dunia
## dibangun dari kode (persis pendekatan Unity — scene dibangun
## ulang dari kode setiap build), jadi tidak ada data scene yang
## bisa kehilangan kabel.
##
## BOOT (ala Genshin): loading terlihat -> 25 chunk awal & rumput
## dibangun sinkron beberapa frame (progress bar) -> loading
## hilang -> input nyala. Selama itu motor & kamera tidak jalan.
## ============================================================

## Titik lahir pemain (lihat alasan di _build).
const SPAWN_X := 24.0
const SPAWN_Z := 30.0

@export var skips_loading_screen: bool = false

var environment_node: WorldEnvironment
var sun: DirectionalLight3D
var day_night: DayNightCycle
var streamer: TerrainChunkStreamer
var grass: GrassField
var water: WaterPlane
var vfx: AnimeVfx
var orbs: Orbs
var rig: CharacterRig
var motor: CharacterMotor
var camera_rig: CameraRig
var quality: QualityApplier
var hud: GameHud
var perf: PerfHud
var loading: LoadingScreen

var boot_done := false

func _ready() -> void:
	BootLog.install()
	_setup_input_map()
	_build()
	_disable_gameplay_input(true)

	BootLog.add("boot mulai.")
	if skips_loading_screen:
		await _boot_sync()
	else:
		_show_loading()
		_status(0.0, "menyiapkan")
		await _boot_sync()
		_hide_loading_sync()
	boot_done = true
	BootLog.add("boot selesai.")

# ============================================================ bangun
func _build() -> void:
	# ---- environment + langit ----
	environment_node = WorldEnvironment.new()
	environment_node.name = "WorldEnvironment"
	var env := Environment.new()
	var sky := Sky.new()
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = preload("res://shaders/aurelia_sky.gdshader")
	sky.sky_material = sky_mat
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.sky_rotation.y = deg_to_rad(90.0)
	environment_node.environment = env
	add_child(environment_node)
	environment_node.add_to_group("environment")

	# ---- matahari ----
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 80.0
	sun.directional_shadow_blend_splits = true
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 1.0
	add_child(sun)
	sun.add_to_group("sun")

	day_night = DayNightCycle.new()
	day_night.name = "DayNightCycle"
	day_night.sun = sun
	day_night.sky_material = sky_mat
	day_night.environment = environment_node
	add_child(day_night)

	# ---- pemain ----
	rig = CharacterRig.new()
	rig.name = "Player"
	# Spawn SENGAJA di (24, 30), bukan (0,0): titik itu persimpangan
	# dua jalur jalan (WorldData.intersection(0,0)), jadi kesan pertama
	# pemain jadi "padang pasir". Geser ke padang rumput heartlands
	# (keputusan sama seperti Stage2SceneBuilder.cs).
	rig.position = Vector3(SPAWN_X, 0.0, SPAWN_Z)
	add_child(rig)
	rig.add_to_group("player")

	motor = CharacterMotor.new()
	motor.name = "Motor"
	rig.add_child(motor)

	# ---- kamera ----
	camera_rig = CameraRig.new()
	camera_rig.name = "CameraRig"
	camera_rig.target = rig
	camera_rig.motor = motor
	add_child(camera_rig)
	motor.camera_target = camera_rig   ## yaw relatif-kamera (dash/attack/ilook)

	# ---- dunia streaming ----
	streamer = TerrainChunkStreamer.new()
	streamer.name = "Streamer"
	streamer.target = rig
	add_child(streamer)
	streamer.add_to_group("streamer")

	grass = GrassField.new()
	grass.name = "GrassField"
	grass.target = rig
	add_child(grass)
	grass.add_to_group("grass")

	water = WaterPlane.new()
	water.name = "WaterPlane"
	water.target = rig
	add_child(water)
	water.add_to_group("water")

	vfx = AnimeVfx.new()
	vfx.name = "Vfx"
	add_child(vfx)
	motor.vfx = vfx

	orbs = Orbs.new()
	orbs.name = "Orbs"
	orbs.target = rig
	add_child(orbs)
	orbs.orb_taken.connect(_on_orb_taken)

	# ---- sistem kualitas (terakhir supaya membaca node di atas) ----
	quality = QualityApplier.new()
	quality.name = "QualityApplier"
	quality.streamer = streamer
	quality.grass = grass
	quality.water = water
	quality.day_night = day_night
	quality.environment = environment_node
	quality.rig = rig
	add_child(quality)
	quality.add_to_group("quality")

	# ---- UI ----
	hud = GameHud.new()
	hud.name = "GameHud"
	hud.motor = motor
	hud.vfx = vfx
	hud.camera_rig = camera_rig
	add_child(hud)
	motor.stick = hud.stick
	hud.pressed_jump.connect(func(): motor.hud_press("jump"))
	hud.pressed_attack.connect(func(): motor.hud_press("attack"))
	hud.pressed_dash.connect(func(): motor.hud_press("dash"))

	perf = PerfHud.new()
	perf.name = "PerfHud"
	perf.streamer = streamer
	perf.grass = grass
	perf.vfx = vfx
	perf.motor = motor
	add_child(perf)

	# HUD sementara disembunyikan sampai boot selesai.
	hud.visible = false

	BootLog.add("scene dibangun.")

## Orb T/A: sparkle emas di dekat orb sebelum lenyap.
func _on_orb_taken(_ids: Array) -> void:
	if vfx != null and motor != null:
		vfx.combo_burst(motor.global_position + Vector3.UP * 1.0, AnimeVfx.K.KUNING, 2)

## Input map keyboard desktop dibangun dari kode (lebih aman daripada
## menulis konstanta numerik keycode di project.godot).
func _setup_input_map() -> void:
	var def := {
		"run": [KEY_SHIFT, KEY_CTRL],
		"jump": [KEY_SPACE],
		"attack": [KEY_F],
		"dash": [KEY_CTRL, KEY_X],
	}
	for aksi in def:
		if not InputMap.has_action(aksi):
			InputMap.add_action(aksi)
		for k in def[aksi]:
			var e := InputEventKey.new()
			e.keycode = k
			if not InputMap.action_has_event(aksi, e):
				InputMap.action_add_event(aksi, e)

# ============================================================ boot
@export var chunk_builds_per_frame: int = 4
@export var min_show_time: float = 0.9
@export var wall_limit: float = 25.0

func _show_loading() -> void:
	loading = LoadingScreen.new()
	loading.name = "LoadingScreen"
	add_child(loading)

func _status(prog: float, txt: String) -> void:
	if loading != null:
		loading.set_progress(prog, txt)

func _hide_loading_sync() -> void:
	if loading != null:
		loading.queue_free()
		loading = null
	hud.visible = true
	_disable_gameplay_input(false)
	day_night.apply()

func _disable_gameplay_input(disabled: bool) -> void:
	motor.set_physics_process(not disabled)
	motor.set_process(not disabled)
	camera_rig.set_process(not disabled)

## Fase sinkron-berbudget: sampai 25 chunk pertama + rumput selesai.
func _boot_sync() -> void:
	var wall := Time.get_ticks_msec() / 1000.0
	var t0 := wall
	var guard := 0
	while true:
		var elapsed := Time.get_ticks_msec() / 1000.0 - t0
		streamer.stream_now(chunk_builds_per_frame)
		streamer.populate_props_now()
		var prog := minf(0.92, streamer.progress01 * 0.92)
		_status(prog, "memuat dunia (%d chunk)" % streamer.active_chunks)
		grass.ensure_init()
		grass.populate_now()
		orbs.target = rig

		var streamed: bool = streamer.progress01 > 0.999 and streamer.queued_chunks == 0
		if streamed and elapsed >= min_show_time:
			break
		if Time.get_ticks_msec() / 1000.0 - wall > wall_limit:
			BootLog.add("[World] FAILSAFE %.0fs — paksa masuk." % wall_limit)
			break
		guard += 1
		if guard > 900:
			BootLog.add("[World] guard 900 frame tercapai — lanjut paksa.")
			break
		await get_tree().process_frame

	_status(1.0, "siap")
	if BootLog.has_errors() and loading != null:
		loading.show_errors(BootLog.tail())

## Klik kiri = serang (mouseover GUI tidak memicu HUD-motif).
## HUD/ikomponen tombol menangkap event-nya sendiri, jadi di sana
## tidak sampai ke _unhandled_input.
func _unhandled_input(event: InputEvent) -> void:
	# Di HP, sentuhan diemulasikan sebagai klik kiri — jangan jadikan serangan.
	if DisplayServer.is_touchscreen_available():
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			motor.hud_press("attack")
