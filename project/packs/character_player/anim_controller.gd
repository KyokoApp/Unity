extends RefCounted
## AnimController — lapis pemutar & resolusi nama animasi di atas SATU
## AnimationPlayer yang sudah berisi gabungan library "ual1/*" (lokomosi
## dasar) + "ual2/*" (aksi/kombat), lihat player.gd::_load_skin().
##
## Pelajaran dari riwayat proyek (DECISIONS.md) yang sengaja dicegah di sini:
## - Ronde-3 : GLB impor tak loop bawaan -> semua state lokomosi dipaksa
##   LOOP_LINEAR secara eksplisit (whitelist, BUKAN tebak dari nama, supaya
##   klip aksi ber-akhiran "_Loop" seperti Dance_Loop/Slide_Loop tetap
##   one-shot saat dipakai lewat action()).
## - Ronde-20: T-pose karena nama exact tak ketemu (prefix library) ->
##   resolver 3-tahap (alias -> exact -> basename tanpa-namespace ->
##   substring) + fallback terakhir "apa pun yang mengandung idle" (TAK
##   PERNAH nyangkut T-pose).
## - Ronde-21: flag air/swim tak pernah turun -> set_move() SELALU
##   membersihkan _air/_swimming di awal (dipanggil hanya saat grounded).

var player: AnimationPlayer
var current: String = ""          # dibaca player.gd utk jejak diagnostik
var _names := {}                  # nama_lower -> nama_asli terdaftar
var _busy := false                # true selagi klip one-shot dari action() main

const ALIASES := {
	"idle": "ual1/Idle_Loop",
	"walk": "ual1/Walk_Loop",
	"run": "ual1/Jog_Fwd_Loop",
	"sprint": "ual1/Sprint_Loop",
	"crouch_idle": "ual1/Crouch_Idle_Loop",
	"crouch_walk": "ual1/Crouch_Fwd_Loop",
	"swim_idle": "ual1/Swim_Idle_Loop",
	"swim_fwd": "ual1/Swim_Fwd_Loop",
	"roll": "ual1/Roll",
	"pickup": "ual1/Interact",
	"jump_start": "ual1/Jump_Start",
	"jump_fall": "ual1/Jump_Loop",
	"jump_land": "ual1/Jump_Land",
	"emote": "ual1/Dance_Loop",
	"attack": "ual2/Sword_Regular_Combo",
}

# Whitelist eksplisit klip yang WAJIB loop (dipakai via set_move/set_air/
# set_swim). Sengaja tidak "tebak dari nama" — lihat catatan header.
const LOOP_STATES := [
	"ual1/Idle_Loop", "ual1/Walk_Loop", "ual1/Jog_Fwd_Loop", "ual1/Sprint_Loop",
	"ual1/Crouch_Idle_Loop", "ual1/Crouch_Fwd_Loop", "ual1/Jump_Loop",
	"ual1/Swim_Idle_Loop", "ual1/Swim_Fwd_Loop",
]

func setup(p_player: AnimationPlayer) -> void:
	player = p_player
	_index_names()
	_force_loop()
	if not player.animation_finished.is_connected(_on_finished):
		player.animation_finished.connect(_on_finished)

func _index_names() -> void:
	_names.clear()
	for full in player.get_animation_list():
		_names[full.to_lower()] = full

func _force_loop() -> void:
	for full in LOOP_STATES:
		if player.has_animation(full):
			var a := player.get_animation(full)
			if a:
				a.loop_mode = Animation.LOOP_LINEAR

## Resolusi 3-tahap + fallback anti-T-pose. Lihat catatan header (Ronde-20).
func _resolve(name: String) -> String:
	var target: String = ALIASES.get(name, name)
	if player.has_animation(target):
		return target
	var lower: String = target.to_lower()
	if _names.has(lower):
		return _names[lower]
	var base: String = lower.split("/")[-1]
	for k in _names:
		if k == base or k.ends_with("/" + base):
			return _names[k]
	for k in _names:
		if k.find(lower) != -1 or lower.find(k) != -1:
			return _names[k]
	for k in _names:
		if k.find("idle") != -1 and k.find("tpose") == -1:
			return _names[k]
	return ""

func has(name: String) -> bool:
	return _resolve(name) != ""

func _play(name: String, blend_ms: float) -> bool:
	var real := _resolve(name)
	if real == "":
		return false
	current = real
	player.play(real, blend_ms / 1000.0)
	return true

## Klip one-shot (serang/roll/pickup/emote/...): mengunci state sampai
## selesai lewat animation_finished, supaya lokomosi tak menyela di tengah.
func action(name: String, blend_ms: float = 150.0) -> void:
	if _play(name, blend_ms):
		_busy = true

func _on_finished(_anim_name: StringName) -> void:
	_busy = false

func set_air(state: String) -> void:
	if _busy:
		return
	if state == "jump_start":
		_play("jump_start", 100.0)
	elif state == "jump_fall":
		_play("jump_fall", 220.0)

func set_swim(_on: bool, speed01: float) -> void:
	if _busy:
		return
	_play("swim_fwd" if speed01 > 0.15 else "swim_idle", 220.0)

## Dipanggil player.gd HANYA saat grounded & tak sedang berenang/di-udara —
## jadi aman jadi satu-satunya tempat mereset makna "kembali ke darat".
func set_move(speed01: float, sprinting: bool, crouching: bool) -> void:
	if _busy:
		return
	if crouching:
		_play("crouch_walk" if speed01 > 0.12 else "crouch_idle", 150.0)
	elif sprinting and speed01 > 0.05:
		_play("sprint", 150.0)
	elif speed01 > 0.55:
		_play("run", 150.0)
	elif speed01 > 0.06:
		_play("walk", 150.0)
	else:
		_play("idle", 200.0)
