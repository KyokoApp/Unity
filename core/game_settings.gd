class_name GameSettings
extends RefCounted

## ============================================================
## SETTINGS NORMALIZER — port dari SettingsNormalizer.cs (bagian
## data dari game/quality.mjs).
##
## Di versi JS/C#, normalizeSettings() menerima bentuk APA PUN karena
## storage bisa berisi keluaran versi lama (insiden produksi
## 2026-09-15). Di GDScript bentuk "apa pun" itu Dictionary biasa:
## kunci yang hilang jatuh ke `null`, dan normalisasi mengisi
## default yang sama persis seperti JS.
##
## PURE: tidak ada engine, tidak ada FileAccess. Adapter storage
## hidup di runtime/settings_store.gd.
##
## Bentuk settings (Dictionary, kunci tetap):
##   sensitivity, camera_distance, quality, shadows, sound, fps,
##   custom, show_fps, gfx{render_scale, shadows, grass, particles,
##   water, view, detail, texture, bloom, motion_blur, volumetric,
##   adaptive}, stick_shape, button_theme, button_scale, layout
## CarCamera sengaja TIDAK ada: game ini tanpa mobil.
## ============================================================

## ---- helper clamp, semantiknya sama dengan JS ----
## JS: Number.isFinite(v) ? ... : fallback.
## null (kunci hilang) HARUS jatuh ke default — bukan ke 0.
static func _num_ok(v) -> bool:
	return v != null and v is float or v is int

static func _clamp_num(v, a: float, b: float, d: float) -> float:
	if v == null or not _num_ok(v):
		return d
	var f := float(v)
	if is_nan(f) or is_inf(f):
		return d
	return clampf(f, a, b)

static func _clamp_int(v, a: int, b: int) -> int:
	if v == null or not _num_ok(v):
		return a
	var f := float(v)
	if is_nan(f) or is_inf(f):
		return a
	return clampi(JsMath.round_to_int(f), a, b)

## Tingkat yang hilang/rusak jatuh ke DEFAULT PRESET, bukan 0.
static func _level(v, max_v: int, d: int) -> int:
	if v == null or not _num_ok(v):
		return d
	var f := float(v)
	if is_nan(f) or is_inf(f):
		return d
	return clampi(JsMath.round_to_int(f), 0, max_v)

static func _pick(v, list: Array, d: String) -> String:
	return str(v) if (v != null and str(v) in list) else d

static func _pick_fps(v, list: Array, d: int) -> int:
	if v == null or not _num_ok(v):
		return d
	var f := float(v)
	if is_nan(f) or is_inf(f):
		return d
	var iv := JsMath.round_to_int(f)
	return iv if iv in list else d

static func normalize_gfx(gfx_raw) -> Dictionary:
	var b: Dictionary = QualityPresets.PRESETS["balanced"]["gfx"]
	var src: Dictionary = gfx_raw if gfx_raw is Dictionary else {}
	return {
		"render_scale": _clamp_num(src.get("render_scale"), 0.5, 1.5, b["render_scale"]),
		"shadows": _level(src.get("shadows"), 3, b["shadows"]),
		"grass": _level(src.get("grass"), 3, b["grass"]),
		"particles": _level(src.get("particles"), 3, b["particles"]),
		"water": _level(src.get("water"), 3, b["water"]),
		"view": _level(src.get("view"), 3, b["view"]),
		"detail": _level(src.get("detail"), 3, b["detail"]),
		"texture": _level(src.get("texture"), 2, b["texture"]),
		"bloom": _level(src.get("bloom"), 3, b["bloom"]),
		"motion_blur": _level(src.get("motion_blur"), 3, b["motion_blur"]),
		"volumetric": _level(src.get("volumetric"), 3, b["volumetric"]),
		"adaptive": src.get("adaptive") if src.get("adaptive") is bool else b["adaptive"],
	}

static func _normalize_layout(layout_raw) -> Dictionary:
	var outp := {}
	if not layout_raw is Dictionary:
		return outp
	for k in layout_raw:
		var p = layout_raw[k]
		if not p is Dictionary:
			continue
		var px = p.get("x")
		var py = p.get("y")
		if px == null or py == null or not _num_ok(px) or not _num_ok(py):
			continue
		var fx := float(px)
		var fy := float(py)
		if is_nan(fx) or is_inf(fy) or is_inf(fx) or is_nan(fy):
			continue
		outp[str(k)] = {"x": clampf(fx, 0.0, 1.0), "y": clampf(fy, 0.0, 1.0)}
	return outp

## Port persis normalizeSettings(). Input bukan Dictionary = objek kosong.
static func normalize(raw) -> Dictionary:
	var s: Dictionary = raw if raw is Dictionary else {}
	var gfx := normalize_gfx(s.get("gfx"))
	var allowed: Array = []
	allowed.append_array(QualityPresets.PRESET_IDS)
	allowed.append("custom")
	var quality := _pick(s.get("quality"), allowed, "balanced")

	return {
		"sensitivity": _clamp_num(s.get("sensitivity"), 0.4, 2.0, 1.0),
		"camera_distance": _clamp_num(s.get("camera_distance"), 3.0, 8.0, 5.0),
		"quality": quality,
		"shadows": s.get("shadows") if s.get("shadows") is bool else true,
		"sound": s.get("sound") if s.get("sound") is bool else true,
		"fps": _pick_fps(s.get("fps"), QualityPresets.FPS_CHOICES, 60),
		"custom": s.get("custom") if s.get("custom") is bool else (quality == "custom"),
		"show_fps": s.get("show_fps") if s.get("show_fps") is bool else false,
		"gfx": gfx,
		"stick_shape": _pick(s.get("stick_shape"), QualityPresets.STICK_SHAPES, "circle"),
		"button_theme": _pick(s.get("button_theme"), QualityPresets.BUTTON_THEMES, "mono"),
		"button_scale": _clamp_num(s.get("button_scale"), 0.75, 1.4, 1.0),
		"layout": _normalize_layout(s.get("layout")),
	}
