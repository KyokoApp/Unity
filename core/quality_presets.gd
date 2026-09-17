class_name QualityPresets
extends RefCounted

## ============================================================
## QUALITY PRESETS — port dari game/quality.mjs (bagian preset)
## lewat QualityPresets.cs.
##
## Prinsip yang dipertahankan dari aslinya:
## 1. PRESET dulu, CUSTOM kemudian. Begitu satu opsi diubah manual,
##    preset otomatis jadi 'custom'.
## 2. Modul ini PURE: tidak menyentuh engine. Bisa dites headless.
## 3. Tingkat 0 = benar-benar MATI. Tidak boleh ada sisa draw call.
##
## Penamaan tingkat: 0=Mati, 1=Rendah, 2=Sedang, 3=Tinggi.
##
## Bentuk data: settings & gfx adalah Dictionary dengan kunci tetap.
## (Di C#: kelas GameSettings/GfxSettings; Dictionary dipilih supaya
## normalisasi/storage/clone trivial dan tetap JSON-friendly.)
## ============================================================

## 'balanced' = nama internal "Sedang" supaya setting lama tetap kebaca.
const PRESET_IDS: Array[String] = ["low", "balanced", "high", "ultra"]

const PRESET_LABEL := {
	"low": "Rendah", "balanced": "Sedang", "high": "Tinggi",
	"ultra": "Ultra", "custom": "Custom",
}

## 60 = default; 24 untuk perangkat sangat lemah supaya simulasi
## tetap jalan mulus (bukan patah-patah).
const FPS_CHOICES := [24, 30, 45, 60]

const LEVEL_LABEL: Array[String] = ["Mati", "Rendah", "Sedang", "Tinggi"]
const TEXTURE_LEVEL_LABEL: Array[String] = ["Rendah", "Sedang", "Tinggi"]

## Opsi gfx: {key, label, hint, max, off}  (off=true: tingkat 0 mematikan fitur)
const GFX_OPTIONS: Array = [
	{"key": "shadows",    "label": "Bayangan",          "max": 3, "off": true,  "hint": "Peta bayangan matahari"},
	{"key": "grass",      "label": "Rumput",            "max": 3, "off": true,  "hint": "Jumlah bilah rumput di sekitar pemain"},
	{"key": "particles",  "label": "Partikel & satwa",  "max": 3, "off": true,  "hint": "Debu, kupu-kupu, burung"},
	{"key": "water",      "label": "Air",               "max": 3, "off": true,  "hint": "Detail gelombang permukaan air"},
	{"key": "view",       "label": "Jarak pandang",     "max": 3, "off": false, "hint": "Kabut, cakrawala, dan jarak streaming dunia"},
	{"key": "detail",     "label": "Kedetailan dunia",  "max": 3, "off": false, "hint": "Kerapatan pohon, batu, dan properti jalan"},
	{"key": "texture",    "label": "Detail tekstur",    "max": 2, "off": false, "hint": "Resolusi & anisotropi tekstur prosedural"},
	{"key": "bloom",      "label": "Bloom",             "max": 3, "off": true,  "hint": "Pendar cahaya pada orb, lampu, dan kilau"},
	{"key": "motion_blur","label": "Motion blur",       "max": 3, "off": true,  "hint": "Blur kecepatan (belum dipakai di Godot — lihat MIGRASI-GODOT.md)"},
	{"key": "volumetric", "label": "Volumetrik",        "max": 3, "off": true,  "hint": "Berkas cahaya matahari (god rays)"},
]

## Angka ini hasil penalaran biaya: bayangan & post-processing adalah
## beban GPU terbesar, jadi preset Rendah mematikannya total.
const PRESETS := {
	"low": {"fps": 30, "gfx": {
		"render_scale": 0.70, "shadows": 0, "grass": 0, "particles": 0,
		"water": 1, "view": 1, "detail": 0, "texture": 0,
		"bloom": 0, "motion_blur": 0, "volumetric": 0, "adaptive": true}},
	"balanced": {"fps": 45, "gfx": {
		"render_scale": 0.85, "shadows": 1, "grass": 1, "particles": 1,
		"water": 2, "view": 2, "detail": 1, "texture": 1,
		"bloom": 1, "motion_blur": 0, "volumetric": 0, "adaptive": true}},
	"high": {"fps": 60, "gfx": {
		"render_scale": 1.00, "shadows": 2, "grass": 2, "particles": 2,
		"water": 3, "view": 3, "detail": 2, "texture": 2,
		"bloom": 2, "motion_blur": 1, "volumetric": 1, "adaptive": true}},
	"ultra": {"fps": 60, "gfx": {
		"render_scale": 1.25, "shadows": 3, "grass": 3, "particles": 3,
		"water": 3, "view": 3, "detail": 3, "texture": 2,
		"bloom": 3, "motion_blur": 2, "volumetric": 2, "adaptive": false}},
}

const STICK_SHAPES: Array[String] = ["circle", "square"]
const BUTTON_THEMES: Array[String] = ["mono", "color"]
## CarCameraModes dibuang — tidak ada mobil.

## Duplikat dalam (padanan Clone() di C#).
static func clone_gfx(g: Dictionary) -> Dictionary:
	return g.duplicate()

static func clone_settings(s: Dictionary) -> Dictionary:
	var c: Dictionary = s.duplicate()
	c["gfx"] = clone_gfx(s["gfx"])
	c["layout"] = s["layout"].duplicate()
	return c

## Kesetaraan nilai gfx — JS membandingkan per kunci di detectPreset().
static func gfx_same_values(a: Dictionary, b: Dictionary) -> bool:
	for k in ["render_scale", "shadows", "grass", "particles", "water", "view",
			  "detail", "texture", "bloom", "motion_blur", "volumetric", "adaptive"]:
		if a[k] != b[k]:
			return false
	return true

## Bentuk default = preset 'balanced'.
static func default_settings() -> Dictionary:
	return {
		"sensitivity": 1.0,
		"camera_distance": 5.0,
		"quality": "balanced",
		"shadows": true,
		"sound": true,
		"fps": 60,
		"custom": false,
		"show_fps": false,
		"gfx": clone_gfx(PRESETS["balanced"]["gfx"]),
		"stick_shape": "circle",
		"button_theme": "mono",
		"button_scale": 1.0,
		"layout": {},
	}

## Mengembalikan settings BARU (immutable style, sama seperti JS yang
## selalu menyebar {...settings}).
static func apply_preset(settings: Dictionary, id: String) -> Dictionary:
	if not PRESETS.has(id):
		return settings
	var p: Dictionary = PRESETS[id]
	var next := clone_settings(settings)
	next["quality"] = id
	next["custom"] = false
	next["fps"] = p["fps"]
	next["gfx"] = clone_gfx(p["gfx"])
	# preset ikut menyetel saklar bayangan lama supaya konsisten
	next["shadows"] = p["gfx"]["shadows"] > 0
	return next

static func _clamp_int(v: float, a: int, b: int) -> int:
	if is_nan(v) or is_inf(v):
		return a
	return clampi(JsMath.round_to_int(v), a, b)

static func _clamp_num(v: float, a: float, b: float, d: float) -> float:
	if is_nan(v) or is_inf(v):
		return d
	return clampf(v, a, b)

## Mengubah satu opsi: preset langsung turun jadi 'custom'.
static func set_gfx_num(settings: Dictionary, key: String, value: float) -> Dictionary:
	var opt := {}
	for o in GFX_OPTIONS:
		if o["key"] == key:
			opt = o
	var gfx := clone_gfx(settings["gfx"])
	if not opt.is_empty():
		gfx[key] = _clamp_int(value, 0, opt["max"])
	elif key == "render_scale":
		gfx["render_scale"] = _clamp_num(value, 0.5, 1.5, gfx["render_scale"])
	else:
		return settings   # kunci tak dikenal: kembalikan apa adanya
	var next := clone_settings(settings)
	next["gfx"] = gfx
	next["quality"] = "custom"
	next["custom"] = true
	return next

static func set_gfx_bool(settings: Dictionary, key: String, value: bool) -> Dictionary:
	if key != "adaptive":
		return settings
	var next := clone_settings(settings)
	next["gfx"] = clone_gfx(settings["gfx"])
	next["gfx"]["adaptive"] = value
	next["quality"] = "custom"
	next["custom"] = true
	return next

## Apakah isi gfx persis sama dengan sebuah preset?
static func detect_preset(gfx: Dictionary) -> String:
	for id in PRESET_IDS:
		if gfx_same_values(PRESETS[id]["gfx"], gfx):
			return id
	return "custom"

## Interval frame dalam ms untuk FPS cap. 0 = tanpa batas.
static func frame_interval(fps: int) -> float:
	return 1000.0 / fps if (fps in FPS_CHOICES and fps > 0) else 0.0

## Palet warna bawaan karakter (dipakai character_rig untuk
## mewarnai material toon saat VRM tidak punya tekstur warna).
const PALETTE_SKIN := Color(0.956, 0.760, 0.674)
const PALETTE_HAIR := Color(0.200, 0.164, 0.449)
