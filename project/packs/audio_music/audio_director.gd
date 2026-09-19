extends Node
## AudioDirector: musik latar + ambien ombak, volume menyesuaikan situasi.
## Musik siang = marimba riang; malam = calm. Ombak keras di dekat pantai.

const DAY_MUSIC := "res://packs/audio_music/day_marimba.wav"
const CALM_MUSIC := "res://packs/audio_music/beach_calm.wav"
const OCEAN := "res://packs/audio_sfx/ocean_loop.wav"

var world: Node
var player: Node3D
var music_day: AudioStreamPlayer
var music_calm: AudioStreamPlayer
var ocean: AudioStreamPlayer
var _fade := 0.0

func setup(w: Node, p: Node3D) -> void:
	world = w
	player = p
	music_day = _mk_player(DAY_MUSIC, "Music", true)
	music_calm = _mk_player(CALM_MUSIC, "Music", false)
	ocean = _mk_player(OCEAN, "SFX", true)
	add_child(music_day)
	add_child(music_calm)
	add_child(ocean)

func _mk_player(path: String, bus: String, auto := true) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	if ResourceLoader.exists(path):
		p.stream = load(path)
	p.autoplay = auto
	p.volume_db = -6.0
	p.finished.connect(func(): p.play())
	return p

func _process(delta: float) -> void:
	if world == null or player == null:
		return
	var t: float = world.time_of_day
	var is_day: bool = t > 6.5 and t < 18.5
	# crossfade sederhana menuju target
	var target_day := -6.0 if is_day else -60.0
	var target_calm := -60.0 if is_day else -6.0
	if is_day and not music_day.playing:
		music_day.volume_db = -60.0
		music_day.play()
	if not is_day and not music_calm.playing:
		music_calm.volume_db = -60.0
		music_calm.play()
	music_day.volume_db = clampf(music_day.volume_db + (delta * 20.0) * (1.0 if target_day > music_day.volume_db else -1.0), -60.0, -6.0)
	music_calm.volume_db = clampf(music_calm.volume_db + (delta * 20.0) * (1.0 if target_calm > music_calm.volume_db else -1.0), -60.0, -6.0)
	if music_day.playing and music_day.volume_db <= -59.5 and not is_day:
		music_day.stop()
	if music_calm.playing and music_calm.volume_db <= -59.5 and is_day:
		music_calm.stop()
	# ombak: keras dekat air
	if ocean.playing and world.has_method("height_at"):
		var h: float = world.height_at(player.global_position.x, player.global_position.z)
		var prox := clampf(1.0 - maxf(h + 1.5, 0.0) / 14.0, 0.0, 1.0)
		ocean.volume_db = -16.0 + prox * 10.0
