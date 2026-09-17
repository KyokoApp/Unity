class_name GfxResolver
extends RefCounted

## ============================================================
## GFX RESOLVER — port dari resolveGfx() di game/quality.mjs
## (lewat GfxResolver.cs).
##
## Menerjemahkan TINGKAT (0..3) menjadi ANGKA KONKRET untuk engine.
## is_touch menurunkan plafon karena GPU ponsel jauh lebih sempit.
##
## Angka keluarannya target ANGKA; yang menerapkannya ke engine Godot
## adalah runtime/quality_applier.gd (viewport scaling_3d_scale,
## fog uniforms, directional shadow, dsb).
## ============================================================

const _RAMP4 := [0.0, 0.25, 0.55, 1.0]        ## faktor jumlah populasi
const _RAMP_VIEW := [0.45, 0.7, 1.0, 1.35]    ## faktor jarak pandang

static func _at(arr: Array, i: int, fallback):
	return arr[i] if (i >= 0 and i < arr.size()) else fallback

static func resolve(settings: Dictionary, is_touch: bool = false) -> Dictionary:
	var g: Dictionary = settings.get("gfx", QualityPresets.PRESETS["balanced"]["gfx"])
	var dpr_cap := 2.0 if is_touch else 2.5

	var grass_base := 9000.0 if is_touch else 28000.0
	var dust_base := 90.0 if is_touch else 190.0
	var bfly_base := 26.0 if is_touch else 55.0
	var bird_base := 18.0 if is_touch else 34.0

	var shadow_size: int = _at([0, 1024, 1536, 2048], g["shadows"], 0)
	var view_f: float = _at(_RAMP_VIEW, g["view"], 1.0)

	return {
		# --- resolusi ---
		"dpr_cap": dpr_cap,
		"render_scale": 1.0 if g["render_scale"] == 0 else g["render_scale"],
		"adaptive": g["adaptive"],

		# --- bayangan ---
		"shadows_enabled": shadow_size > 0 and settings["shadows"],
		"shadow_map_size": 512 if shadow_size == 0 else shadow_size,
		# diperbarui tiap N frame: hemat besar, nyaris tak terlihat
		"shadow_refresh_frames": 1 if g["shadows"] >= 2 else 2,

		# --- vegetasi & partikel ---
		"grass_count": JsMath.round_to_int(grass_base * _at(_RAMP4, g["grass"], 0.0)),
		"grass_enabled": g["grass"] > 0,
		"dust_count": JsMath.round_to_int(dust_base * _at(_RAMP4, g["particles"], 0.0)),
		"butterfly_count": JsMath.round_to_int(bfly_base * _at(_RAMP4, g["particles"], 0.0)),
		"bird_count": JsMath.round_to_int(bird_base * _at(_RAMP4, g["particles"], 0.0)),
		"particles_enabled": g["particles"] > 0,

		# --- air ---
		"water_segments": _at([24, 44, 68, 96], g["water"], 68),
		"water_waves": g["water"] >= 2,
		"water_opacity": 0.55 if g["water"] == 0 else 0.86,

		# --- jarak pandang / streaming dunia ---
		"fog_near": JsMath.round_to_int((260.0 if is_touch else 450.0) * view_f),
		"fog_far": JsMath.round_to_int((700.0 if is_touch else 950.0) * view_f),
		"orb_cull_distance": JsMath.round_to_int(650 * view_f),
		"stream_radius": clampi(
			(3 if is_touch else 4) + (1 if g["view"] >= 3 else (-1 if g["view"] == 0 else 0)),
			2, 5),

		# --- kedetailan dunia ---
		"terrain_segments_near": _at([28, 44, 64, 84], g["detail"], 64),
		"props_near": _at([10, 24, 40, 56], g["detail"], 40),
		"props_far": _at([3, 5, 8, 12], g["detail"], 8),
		"road_props": g["detail"] >= 1,
		"road_prop_spacing": 90 if g["detail"] >= 3 else (130 if g["detail"] == 2 else 190),

		# --- tekstur ---
		"texture_size": _at([128, 256, 512], g["texture"], 256),
		"anisotropy": _at([1, 4, 8], g["texture"], 4),

		# --- post-processing ---
		"bloom_level": g["bloom"],
		"motion_blur_level": g["motion_blur"],
		"volumetric_level": g["volumetric"],
		"post_enabled": g["bloom"] > 0 or g["motion_blur"] > 0 or g["volumetric"] > 0,
	}

## ============================================================
## ADAPTIVE RESOLUTION — port dari createAdaptiveResolution().
## Naik-turunkan skala render mengikuti waktu frame terukur.
## Histeresis lebar (turun cepat, naik pelan) supaya tidak berosilasi.
## ============================================================
class AdaptiveResolution:
	extends RefCounted
	var _min: float
	var _max: float
	var _start: float
	var _scale: float
	var _bad_frames: int = 0
	var _good_frames: int = 0

	func _init(min_s: float = 0.55, max_s: float = 1.0, start: float = 1.0) -> void:
		_min = min_s
		_max = max_s
		_start = start
		_scale = start

	func scale() -> float:
		return _scale

	func reset(next: float = -1.0) -> void:
		_scale = next if next >= 0.0 else _start
		_bad_frames = 0
		_good_frames = 0

	## target_ms = budget frame (mis. 1000/45). Mengembalikan skala baru.
	func update(frame_ms: float, target_ms: float) -> float:
		if not (target_ms > 0.0) or is_nan(frame_ms) or is_inf(frame_ms):
			return _scale

		if frame_ms > target_ms * 1.22:
			_bad_frames += 1
			_good_frames = 0
		elif frame_ms < target_ms * 0.82:
			_good_frames += 1
			_bad_frames = 0
		else:
			_bad_frames = 0
			_good_frames = 0

		if _bad_frames >= 20:
			_scale = maxf(_min, _scale - 0.1)
			_bad_frames = 0
		elif _good_frames >= 150:
			_scale = minf(_max, _scale + 0.05)
			_good_frames = 0
		return _scale
