class_name SettingsStore
extends RefCounted

## ============================================================
## SETTINGS STORE — adapter penyimpanan untuk settings.
## (Port dari SettingsStore.cs — PlayerPrefs -> Godot ConfigFile.)
##
## core/ sengaja pure (lihat core/game_settings.gd). Ini adapter-nya.
##
## Disimpan sebagai ConfigFile di user://aurelia_settings.cfg —
## setara PlayerPrefs (datar, tahan baca-tulis di semua platform
## termasuk Android). Bagian [gfx] memakai kunci yang SAMA dengan
## SettingsStore.cs supaya bentuk datanya sama.
##
## Yang penting dijaga: setiap nilai yang dibaca TETAP dilewatkan
## ke GameSettings.normalize(), jadi batas yang sudah diuji paritas
## (sensitivity 0,4..2, camera_distance 3..8, dst) berlaku di sini
## juga. Storage yang rusak/asing tidak bisa menghasilkan setelan
## di luar batas.
## ============================================================

const PATH := "user://aurelia_settings.cfg"

## Cache load(): HUD membacanya PER FRAME (kompas, fps, stamina) dan
## ConfigFile.load() = I/O file — tanpa cache itu statistiknya 2-3 kali
## baca disk tiap frame. Di-invalidate oleh save()/delete_all().
## Yang dikembalikan adalah DUPLIKAT DALAM — penyetelan di GameHud
## memutasi hasil load() lalu save() lagi; tanpa duplikat cache ikut
## termutasi di luar jalur normalisasi.
static var _cache: Dictionary = {}

static func load() -> Dictionary:
	if _cache.is_empty():
		_cache = _read_disk()
	return _cache.duplicate(true)

static func _read_disk() -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return QualityPresets.default_settings()

	var raw := {
		"sensitivity": cfg.get_value("main", "sensitivity", null),
		"camera_distance": cfg.get_value("main", "camera_distance", null),
		"quality": cfg.get_value("main", "quality", null),
		"shadows": _bget(cfg, "main", "shadows"),
		"sound": _bget(cfg, "main", "sound"),
		"fps": cfg.get_value("main", "fps", null),
		"show_fps": _bget(cfg, "main", "show_fps"),
		"stick_shape": cfg.get_value("main", "stick_shape", null),
		"button_theme": cfg.get_value("main", "button_theme", null),
		"button_scale": cfg.get_value("main", "button_scale", null),
		"gfx": _load_gfx(cfg),
	}
	return GameSettings.normalize(raw)

static func save(s: Dictionary) -> void:
	_cache = GameSettings.normalize(s)
	var cfg := ConfigFile.new()
	# Baca lagi yang ada supaya kunci asing tidak hilang.
	cfg.load(PATH)
	cfg.set_value("main", "quality", s.get("quality", "balanced"))
	cfg.set_value("main", "sensitivity", s["sensitivity"])
	cfg.set_value("main", "camera_distance", s["camera_distance"])
	cfg.set_value("main", "shadows", s["shadows"])
	cfg.set_value("main", "sound", s["sound"])
	cfg.set_value("main", "fps", s["fps"])
	cfg.set_value("main", "show_fps", s["show_fps"])
	cfg.set_value("main", "stick_shape", s.get("stick_shape", "circle"))
	cfg.set_value("main", "button_theme", s.get("button_theme", "mono"))
	cfg.set_value("main", "button_scale", s["button_scale"])
	_save_gfx(cfg, s["gfx"])
	cfg.save(PATH)

## Setelan diturunkan secara fungsional: ambil yang sekarang, ubah
## satu nilai, normalisasi ulang supaya tetap di dalam batas.
static func with_camera_distance(s: Dictionary, meters: float) -> Dictionary:
	return GameSettings.normalize({"camera_distance": meters, "gfx": s["gfx"],
		"quality": s["quality"], "sensitivity": s["sensitivity"], "fps": s["fps"],
		"shadows": s["shadows"], "sound": s["sound"], "custom": s["custom"],
		"show_fps": s["show_fps"], "stick_shape": s["stick_shape"],
		"button_theme": s["button_theme"], "button_scale": s["button_scale"],
		"layout": s["layout"]})

static func with_sensitivity(s: Dictionary, value: float) -> Dictionary:
	return GameSettings.normalize({"sensitivity": value, "gfx": s["gfx"],
		"quality": s["quality"], "camera_distance": s["camera_distance"],
		"fps": s["fps"], "shadows": s["shadows"], "sound": s["sound"],
		"custom": s["custom"], "show_fps": s["show_fps"],
		"stick_shape": s["stick_shape"], "button_theme": s["button_theme"],
		"button_scale": s["button_scale"], "layout": s["layout"]})

static func delete_all() -> void:
	_cache.clear()
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(PATH)

# ------------------------------------------------------------------
static func _load_gfx(cfg: ConfigFile) -> Dictionary:
	if not cfg.has_section_key("gfx", "render_scale"):
		return {}   # biarkan normalize mengisi default
	return {
		"render_scale": cfg.get_value("gfx", "render_scale", null),
		"shadows": cfg.get_value("gfx", "shadows", null),
		"grass": cfg.get_value("gfx", "grass", null),
		"particles": cfg.get_value("gfx", "particles", null),
		"water": cfg.get_value("gfx", "water", null),
		"view": cfg.get_value("gfx", "view", null),
		"detail": cfg.get_value("gfx", "detail", null),
		"texture": cfg.get_value("gfx", "texture", null),
		"bloom": cfg.get_value("gfx", "bloom", null),
		"motion_blur": cfg.get_value("gfx", "motion_blur", null),
		"volumetric": cfg.get_value("gfx", "volumetric", null),
		"adaptive": _bget(cfg, "gfx", "adaptive"),
	}

static func _save_gfx(cfg: ConfigFile, g: Dictionary) -> void:
	for k in ["render_scale", "shadows", "grass", "particles", "water", "view",
			  "detail", "texture", "bloom", "motion_blur", "volumetric"]:
		cfg.set_value("gfx", k, g[k])
	cfg.set_value("gfx", "adaptive", g["adaptive"])

## Baca nilai yang mungkin bool/int (ConfigFile membaca 1/0 balik).
static func _bget(cfg: ConfigFile, section: String, key: String):
	if not cfg.has_section_key(section, key):
		return null
	var v = cfg.get_value(section, key, null)
	if v is bool:
		return v
	if v is int or v is float:
		return v != 0
	return null
