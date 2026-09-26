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

## NAMA SEBENARNYA setelah import Godot 4.5 (diverifikasi dari .scn hasil CI,
## pack character_player-1.0.24): importer glTF OTOMATIS memberi LOOP_LINEAR
## pada klip berakhiran "_Loop" DAN MEMBUANG suffix itu dari namanya
## (resource_importer_scene.cpp::_pre_fix_node → library.rename_animation).
## Jadi "Idle_Loop" di file GLB = "Idle" di AnimationPlayer, "Dance_Loop" =
## "Dance" (dan ter-loop!). Library ual1 = host → namespace kosong (""),
## hanya ual2 yang digabung dengan awalan "ual2/".
## Dulu alias memakai "ual1/Idle_Loop" dkk. — tak ada yang cocok persis, dan
## hanya kebetulan ketemu lewat pencarian substring; "swim_idle" malah
## nyasar ke "Idle" darat. Resolver di bawah tetap dipertahankan sebagai
## jaring pengaman bila nama berubah lagi.
const ALIASES := {
	"idle": "Idle",
	"walk": "Walk",
	"run": "Jog_Fwd",
	"sprint": "Sprint",
	"crouch_idle": "Crouch_Idle",
	"crouch_walk": "Crouch_Fwd",
	"swim_idle": "Swim_Idle",
	"swim_fwd": "Swim_Fwd",
	"roll": "Roll",
	"pickup": "Interact",
	"jump_start": "Jump_Start",
	"jump_fall": "Jump",
	"jump_land": "Jump_Land",
	"emote": "Dance",
	"attack": "ual2/Sword_Regular_Combo",
}

# Whitelist eksplisit klip yang WAJIB loop (dipakai via set_move/set_air/
# set_swim). Sengaja tidak "tebak dari nama" — lihat catatan header.
# (Importer biasanya sudah me-loop-kan ini; di sini hanya penegasan.)
const LOOP_STATES := [
	"Idle", "Walk", "Jog_Fwd", "Sprint", "Crouch_Idle", "Crouch_Fwd",
	"Jump", "Swim_Idle", "Swim_Fwd",
]

## Batas waktu kunci untuk klip action() yang ternyata LOOP (mis. "Dance"):
## klip loop TIDAK PERNAH memancarkan animation_finished, sehingga dulu
## _busy tak pernah turun → karakter joget selamanya, jalan/lompat mati.
var _busy_until_ms := 0
var _busy_is_loop := false

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
	# dipanggil tiap frame fisika dari set_move(): jangan play() ulang klip
	# yang sedang main — tiap panggilan menambah entri blend baru di
	# AnimationPlayer (boros CPU, terutama di HP).
	if real == current and player.is_playing() and player.current_animation == real:
		return true
	current = real
	player.play(real, blend_ms / 1000.0)
	return true

func _is_busy() -> bool:
	if _busy and _busy_is_loop and Time.get_ticks_msec() >= _busy_until_ms:
		_busy = false
		_busy_is_loop = false
	return _busy

## Klip one-shot (serang/roll/pickup/emote/...): mengunci state sampai
## selesai lewat animation_finished, supaya lokomosi tak menyela di tengah.
func action(name: String, blend_ms: float = 150.0) -> void:
	var real := _resolve(name)
	if real == "":
		return
	# one-shot: selalu mulai dari awal walau klip yang sama baru saja main
	current = real
	player.play(real, blend_ms / 1000.0)
	player.seek(0.0, true)
	_busy = true
	_busy_is_loop = false
	var a := player.get_animation(real)
	if a and a.loop_mode != Animation.LOOP_NONE:
		# klip loop: lepas kunci setelah SATU siklus (0,6–6 dtk)
		_busy_is_loop = true
		_busy_until_ms = Time.get_ticks_msec() + int(clampf(a.length, 0.6, 6.0) * 1000.0)

func _on_finished(_anim_name: StringName) -> void:
	_busy = false
	_busy_is_loop = false

func set_air(state: String) -> void:
	if _is_busy():
		return
	if state == "jump_start":
		_play("jump_start", 100.0)
	elif state == "jump_fall":
		_play("jump_fall", 220.0)

func set_swim(_on: bool, speed01: float) -> void:
	if _is_busy():
		return
	_play("swim_fwd" if speed01 > 0.15 else "swim_idle", 220.0)

## Dipanggil player.gd HANYA saat grounded & tak sedang berenang/di-udara —
## jadi aman jadi satu-satunya tempat mereset makna "kembali ke darat".
func set_move(speed01: float, sprinting: bool, crouching: bool) -> void:
	# emote/klip loop lain dibatalkan begitu pemain mulai bergerak
	if _busy and _busy_is_loop and speed01 > 0.06:
		_busy = false
		_busy_is_loop = false
	if _is_busy():
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
