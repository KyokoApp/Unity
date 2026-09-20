extends Node
## GameSettings: memuat/menyimpan pengaturan pemain (grafis, kontrol, audio).
## Dibuat oleh GameRoot sebagai singleton lokal game (bukan autoload,
## supaya pack tidak bergantung pada project.godot).

signal changed(key)

const PATH := "user://settings.cfg"

# --- Grafis ---
var quality_preset: int = 1  # 0=Rendah, 1=Sedang, 2=Tinggi
var fps_cap: int = 30        # 30 atau 60
var show_fps: bool = false

# --- Pencahayaan (Mode Edit in-game) ---
var light_sun: float = 1.0     # pengali energi matahari 0.3..2.0
var light_ambient: float = 1.0 # pengali ambient 0.3..2.0
var light_fog: float = 1.0     # pengali kabut 0..3
var light_sky: int = -1        # preset gradien langit (-1 = otomatis siang/malam)
var gfx_faceted: bool = false  # gaya low-poly segi datar pada terrain

# --- Kontrol ---
var camera_sens: float = 1.0   # 0.3 .. 2.5
var button_scale: float = 1.0  # 0.8 .. 1.5
var invert_y: bool = false
var char_skin: String = "mannequin"  # "mannequin" | "polygirl" | "knight" (bawaan: UAL mannequin)
var button_offsets := {}  # nama tombol -> Vector2 (offset dari posisi default)

# --- Audio (dB) ---
var vol_master: float = 0.0
var vol_music: float = -2.0
var vol_sfx: float = 0.0

func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		quality_preset = int(cfg.get_value("graphics", "preset", quality_preset))
		fps_cap = int(cfg.get_value("graphics", "fps_cap", fps_cap))
		show_fps = bool(cfg.get_value("graphics", "show_fps", show_fps))
		camera_sens = float(cfg.get_value("controls", "camera_sens", camera_sens))
		button_scale = float(cfg.get_value("controls", "button_scale", button_scale))
		invert_y = bool(cfg.get_value("controls", "invert_y", invert_y))
		char_skin = str(cfg.get_value("controls", "char_skin", char_skin))
		vol_master = float(cfg.get_value("audio", "master", vol_master))
		vol_music = float(cfg.get_value("audio", "music", vol_music))
		vol_sfx = float(cfg.get_value("audio", "sfx", vol_sfx))
		light_sun = float(cfg.get_value("lighting", "sun", light_sun))
		light_ambient = float(cfg.get_value("lighting", "ambient", light_ambient))
		light_fog = float(cfg.get_value("lighting", "fog", light_fog))
		light_sky = int(cfg.get_value("lighting", "sky", light_sky))
		gfx_faceted = bool(cfg.get_value("graphics", "faceted", gfx_faceted))
		apply_audio()

func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("graphics", "preset", quality_preset)
	cfg.set_value("graphics", "fps_cap", fps_cap)
	cfg.set_value("graphics", "show_fps", show_fps)
	cfg.set_value("controls", "camera_sens", camera_sens)
	cfg.set_value("controls", "button_scale", button_scale)
	cfg.set_value("controls", "invert_y", invert_y)
	cfg.set_value("controls", "char_skin", char_skin)
	cfg.set_value("audio", "master", vol_master)
	cfg.set_value("audio", "music", vol_music)
	cfg.set_value("audio", "sfx", vol_sfx)
	cfg.set_value("lighting", "sun", light_sun)
	cfg.set_value("lighting", "ambient", light_ambient)
	cfg.set_value("lighting", "fog", light_fog)
	cfg.set_value("lighting", "sky", light_sky)
	cfg.set_value("graphics", "faceted", gfx_faceted)
	cfg.save(PATH)

func set_value(key: String, v) -> void:
	match key:
		"quality_preset": quality_preset = int(v)
		"fps_cap": fps_cap = int(v)
		"show_fps": show_fps = bool(v)
		"camera_sens": camera_sens = clampf(float(v), 0.3, 2.5)
		"button_scale": button_scale = clampf(float(v), 0.8, 1.5)
		"invert_y": invert_y = bool(v)
		"char_skin": char_skin = str(v)
		"vol_master": vol_master = clampf(float(v), -40.0, 6.0)
		"vol_music": vol_music = clampf(float(v), -40.0, 6.0)
		"vol_sfx": vol_sfx = clampf(float(v), -40.0, 6.0)
		"light_sun": light_sun = clampf(float(v), 0.3, 2.0)
		"light_ambient": light_ambient = clampf(float(v), 0.3, 2.0)
		"light_fog": light_fog = clampf(float(v), 0.0, 3.0)
		"light_sky": light_sky = int(v)
		"gfx_faceted": gfx_faceted = bool(v)
	save_settings()
	changed.emit(key)
	if key.begins_with("vol_"):
		apply_audio()

func apply_audio() -> void:
	_set_bus("Master", vol_master)
	_set_bus("Music", vol_music)
	_set_bus("SFX", vol_sfx)

func _set_bus(bus: String, db: float) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, db)
