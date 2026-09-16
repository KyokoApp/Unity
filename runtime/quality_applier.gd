class_name QualityApplier
extends Node

## ============================================================
## QUALITY APPLIER — menerjemahkan GfxResolver menjadi kenyataan.
## (Port dari QualityApplier.cs.)
##
## PERBAIKAN BUG BESAR Tahap 5 versi Unity (dipertahankan di sini):
## sebelum perbaikan, GfxResolver + preset kualitas TIDAK TERPAKAI —
## pengaturan kualitas cuma pajangan. Sekarang node ini (sekali saat
## _ready + tiap pengaturan berubah + tiap frame untuk adaptive):
##   * viewport: scaling_3d_scale (render scale) + adaptive res
##   * fog near/far lewat uniform shader global
##   * terrain: quads + radius (rebuild hanya kalau berubah)
##   * rumput: radius + refresh (mati total di preset Rendah)
##   * bloom (Environment.glow) + shadow atlas size
##   * matahari: bayangan lembut/mati, refresh tiap N frame
##   * target fps engine fps tertinggi yang dipilih pengguna
##   * outline karakter: nyala/mati (preset Rendah = mati)
## ============================================================

var streamer: TerrainChunkStreamer
var grass: GrassField
var water: WaterPlane
var day_night: DayNightCycle
var environment: WorldEnvironment
var rig: CharacterRig

var _adaptive: GfxResolver.AdaptiveResolution
var _base_scale := 1.0
var _adaptive_on := false
var _fps_target := 60

func _ready() -> void:
	# Referensi dicari supaya node ini tetap hidup walaupun sebagian
	# sistem belum ada (mis. tes headless).
	streamer = get_tree().get_first_node_in_group("streamer") as TerrainChunkStreamer
	grass = get_tree().get_first_node_in_group("grass") as GrassField
	water = get_tree().get_first_node_in_group("water") as WaterPlane
	day_night = get_tree().get_first_node_in_group("day_night") as DayNightCycle
	rig = get_tree().get_first_node_in_group("player") as CharacterRig
	var envs := get_tree().get_nodes_in_group("environment")
	if not envs.is_empty():
		environment = envs[0] as WorldEnvironment
	apply_all()

func _process(_dt: float) -> void:
	if not _adaptive_on:
		return
	var vp := get_viewport()
	if vp == null:
		return
	var frame_ms := float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0
	var target_ms := 1000.0 / maxf(1.0, float(_fps_target))
	var s: float = _adaptive.update(frame_ms, target_ms)
	if absf(s - vp.scaling_3d_scale) > 0.01:
		vp.scaling_3d_scale = s

static func refresh_all_scene(scene_tree: SceneTree) -> void:
	var q := scene_tree.get_first_node_in_group("quality") as QualityApplier
	if q != null:
		q.apply_all()

func apply_all() -> void:
	var settings := SettingsStore.load()
	var r := GfxResolver.resolve(settings, _is_touch())

	_apply_viewport(r)
	_apply_fog(r)
	_apply_terrain(r)
	_apply_grass(r, settings)
	_apply_post(r)
	_apply_shadows(r)
	_apply_water(r)

	Engine.max_fps = settings["fps"]
	_fps_target = settings["fps"]

	# Adaptive resolution: mulai dari skala preset.
	_adaptive_on = r["adaptive"]
	_adaptive = GfxResolver.AdaptiveResolution.new(0.55, _base_scale, _base_scale)

	if day_night != null:
		day_night.refresh_settings()
	if grass != null:
		grass.refresh_settings()

func _apply_viewport(r: Dictionary) -> void:
	var vp := get_viewport()
	if vp == null:
		return
	_base_scale = clampf(r["render_scale"], 0.5, 1.5)
	vp.scaling_3d_scale = _base_scale
	vp.positional_shadow_atlas_size = clampi(r["shadow_map_size"], 256, 2048)

func _apply_fog(r: Dictionary) -> void:
	RenderingServer.global_shader_parameter_set("aurelia_fog_near", float(r["fog_near"]))
	RenderingServer.global_shader_parameter_set("aurelia_fog_far", float(r["fog_far"]))

func _apply_terrain(r: Dictionary) -> void:
	if streamer == null:
		return
	var segs: int = r["terrain_segments_near"]
	var quads: int = 48 if segs >= 84 else 32 if segs >= 64 else 24 if segs >= 44 else 16
	var radius: int = clampi(r["stream_radius"], 1, 3)
	if streamer.quads_per_chunk != quads or streamer.stream_radius != radius:
		streamer.set_quality(quads, radius)

func _apply_grass(r: Dictionary, _s: Dictionary) -> void:
	if grass == null:
		return
	grass.set_enabled_by_quality(r["grass_enabled"])

func _apply_post(r: Dictionary) -> void:
	if environment == null or environment.environment == null:
		return
	var env := environment.environment
	env.glow_enabled = r["bloom_level"] > 0
	env.glow_bloom = clampf(r["bloom_level"] * 0.12, 0.0, 0.5)
	env.glow_intensity = 0.8
	var sun := get_tree().get_first_node_in_group("sun") as DirectionalLight3D
	if sun != null:
		sun.shadow_enabled = r["shadows_enabled"]

func _apply_shadows(r: Dictionary) -> void:
	var sun := get_tree().get_first_node_in_group("sun") as DirectionalLight3D
	if sun != null:
		sun.shadow_enabled = r["shadows_enabled"]

func _apply_water(r: Dictionary) -> void:
	# Segmen air versi Unity tidak memengaruhi gelombang fragment;
	# gelombang dikendalikan water_waves via uniform.
	if water != null and water.water_material != null:
		water.water_material.set_shader_parameter("waves_enabled", r["water_waves"])
		water.water_material.set_shader_parameter("opacity", r["water_opacity"])

## Preset Rendah = outline mati (hemat 1 pass per material karakter),
## persis keputusan Unity: "hemat 1 draw call + 1x vertex".
func set_outline_enabled(on: bool) -> void:
	if rig != null:
		ToonCharacterSetup.set_outline_visible(rig.root_model(), on)

func _is_touch() -> bool:
	return DisplayServer.is_touchscreen_available()
