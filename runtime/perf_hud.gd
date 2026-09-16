class_name PerfHud
extends CanvasLayer

## ============================================================
## PERF HUD — overlay performa ringkas (+/- FPS, ms, chunk, segitiga,
## verteks, clump rumput, partikel VFX). Dipakai saat tersush.
## (Port dari PerfHud.cs — overlay yang sama, tanpa scaler dinamis:
## penurunan resolusi sekarang ditangani quality_applier adaptive.)
## ============================================================

@export var streamer: TerrainChunkStreamer
@export var grass: GrassField
@export var vfx: AnimeVfx
@export var motor: CharacterMotor

var _label: Label
var _acc := 0.0
var _frames := 0

func _ready() -> void:
	layer = 60
	var root := Control.new()
	root.name = "PerfRoot"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_label = UiKit.label(root, "", 18, Color(1, 1, 1, 0.9), HORIZONTAL_ALIGNMENT_LEFT)
	_label.anchor_left = 0.005
	_label.anchor_top = 0.27
	_label.anchor_right = 0.40
	_label.anchor_bottom = 0.60
	_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_label.add_theme_constant_override("shadow_offset_x", 1)
	_label.add_theme_constant_override("shadow_offset_y", 1)
	visible = false

func _process(dt: float) -> void:
	_acc += dt
	_frames += 1
	visible = SettingsStore.load().get("show_fps", false)
	if not visible:
		_acc = 0.0
		_frames = 0
		return
	if _acc < 0.5:
		return
	var fps := _frames / _acc
	_acc = 0.0
	_frames = 0
	var txt := "fps %.0f  (%.1f ms)\n" % [fps, 1000.0 / maxf(1.0, fps)]
	txt += "chunk %d (antre %d)\n" % [streamer.active_chunks if streamer else 0,
		streamer.queued_chunks if streamer else 0]
	txt += "tris %dk  vert %dk\n" % [int((streamer.total_triangles if streamer else 0) / 1000),
		int((streamer.total_vertices if streamer else 0) / 1000)]
	txt += "rumput %s\n" % (grass.init_state() if grass else "-")
	txt += "vfx %d\n" % (vfx.active_instances if vfx else 0)
	if streamer != null:
		txt += "build %.2fms  upload %.2fms  thread %s\n" % [
			streamer.last_build_ms, streamer.last_upload_ms,
			"ON" if streamer.thread_active else "OFF"]
	if motor != null:
		txt += "speed %.1f m/s  stamina %.0f%%\n" % [motor.speed, motor.stamina01 * 100]
	_label.text = txt
