extends RefCounted
## AnimationController: resolver nama animasi + AnimationTree (state machine)
## untuk skin karakter (GLB KayKit). Toleran terhadap nama animasi yang
## berbeda antar pack — memakai daftar kandidat per state.
## API dipakai player.gd: set_move, set_airbone, set_swim, action, dsb.

class_name AnimController

const LOOP_STATES := ["idle", "walk", "run", "sprint",
	"crouch_idle", "crouch_move", "swim_idle", "swim_move", "jump_fall"]

const STATES := {
	"idle": ["Idle", "Unarmed_Idle", "Idle_Neutral"],
	"walk": ["Walking_A", "Walking_D", "Walk_A", "Walking"],
	"run": ["Running_A", "Running", "Run_A"],
	"sprint": ["Sprinting", "Sprint", "Running_B", "Running_A"],
	"crouch_idle": ["Idle_Sitting", "Idle", "Unarmed_Idle"],
	"crouch_move": ["Walking_B", "Walking_A"],
	"jump_start": ["Jump_Start", "Jump"],
	"jump_fall": ["Jump_Idle", "Jump_Fall", "Fall"],
	"jump_land": ["Jump_Land", "Jump_Start"],
	"swim_idle": ["Swim_Idle", "Jump_Idle", "Walking_A"],
	"swim_move": ["Swim_Forward", "Swimming", "Walking_A"],
	"pickup": ["PickUp", "Pick_Up", "Interact"],
	"interact": ["Interact", "Use_Item"],
	"emote": ["Cheer", "Wave", "Dance"],
	"attack": ["1H_Melee_Attack_Chop", "1H_Melee_Attack_Slice", "Unarmed_Melee_Attack_Punch_A"],
	"sit": ["Sit_Floor_Idle", "Sit_Chair_Idle"],
}

var anim_player: AnimationPlayer
var tree: AnimationTree
var playback: AnimationNodeStateMachinePlayback
var resolved := {}       # state -> nama anim asli
var current := ""
var _action_until := 0.0
var _move_state := "idle"
var _air := false
var _swimming := false

## Resolver nama anim TAHAP 3 (tahan prefix library dari GLB impor):
##  1) exact   — "Idle_Loop"
##  2) basename — "UAL1_Standard/Idle_Loop" (library ber-prefix dari export GLB mannequin)
##  3) lowercase-substring — "idle_loop" / "idle-loop"…
## Mengembalikan nama LENGKAP seperti yang diminta get_animation()/travel, atau bila benar-benar tak ada.
func _resolve_name(names: PackedStringArray, cands: Array) -> String:
	for cand in cands:
		if names.has(cand):
			return cand
	for cand in cands:
		for n in names:
			var base: String = str(n).get_file()  # strip "LIB/…"
			if base == cand:
				return str(n)
	for cand in cands:
		for n in names:
			var base2: String = str(n).get_file().to_lower()
			if base2 == str(cand).to_lower():
				return str(n)
	for cand in cands:
		for n in names:
			if str(n).to_lower().contains(str(cand).to_lower()):
				return str(n)
	# fallback akhir: utamakan yang ada kata "idle" supaya minimal TAK T-pose
	for n in names:
		if "idle" in str(n).to_lower():
			return str(n)
	return ""

func setup(node: Node3D, skin_root: Node, custom_states: Dictionary = {}) -> bool:
	anim_player = _find_anim_player(skin_root)
	if anim_player == null:
		push_error("[anim] AnimationPlayer tidak ditemukan di skin")
		return false
	var names := anim_player.get_animation_list()
	var unresolved := []
	for st in STATES:
		var cands: Array = custom_states.get(st, STATES[st])
		var found := _resolve_name(names, cands)
		if found == "":
			unresolved.append(st)
		else:
			resolved[st] = found
	print("[anim] resolusi: ", JSON.stringify(resolved))
	# WAJIB: animasi GLB impor tidak loop secara bawaan — tanpa ini, walk
	# berhenti di frame terakhir setelah ~1 siklus ("beberapa langkah lalu kaku").
	for st in resolved:
		var a := anim_player.get_animation(resolved[st])
		if a == null:
			continue
		a.loop_mode = Animation.LOOP_LINEAR if LOOP_STATES.has(st) else Animation.LOOP_NONE
	# bangun AnimationTree bermesin state machine
	tree = AnimationTree.new()
	tree.name = "AnimTree"
	node.add_child(tree)
	# properti anim_player: path dari node tree menuju AnimationPlayer
	tree.anim_player = tree.get_path_to(anim_player)
	var sm := AnimationNodeStateMachine.new()
	for st in resolved:
		var anim_name: String = resolved[st]
		if anim_name == "":
			continue
		var an := AnimationNodeAnimation.new()
		an.animation = anim_name
		sm.add_node(st, an)
	# transisi global (tanpa kondisi — dikendalikan dari script via travel())
	_sm_setup_transitions(sm)
	tree.tree_root = sm
	tree.active = true
	playback = tree.get("parameters/playback")
	tree.advance_expression_base_node = NodePath(".")
	return true

func _find_anim_player(root: Node) -> AnimationPlayer:
	if root is AnimationPlayer:
		return root
	for c in root.get_children():
		var found := _find_anim_player(c)
		if found:
			return found
	return null

func _sm_setup_transitions(sm: AnimationNodeStateMachine) -> void:
	# semua state bisa pindah ke semua (switch_mode synced agar halus);
	# node yang tidak ter-resolve (animasi tak ada) dilewati.
	var states: Array = resolved.keys()
	for a in states:
		if str(resolved.get(a, "")) == "":
			continue
		for b in states:
			if a == b:
				continue
			if str(resolved.get(b, "")) == "":
				continue
			if not sm.has_node(a) or not sm.has_node(b):
				continue
			var t := AnimationNodeStateMachineTransition.new()
			t.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_AT_END if b in ["jump_land", "jump_start"] else AnimationNodeStateMachineTransition.SWITCH_MODE_SYNC
			t.xfade_time = 0.22 if b in ["idle", "walk", "run", "sprint", "swim_move", "swim_idle", "crouch_idle", "crouch_move"] else 0.08
			sm.add_transition(a, b, t)

func has(state: String) -> bool:
	return resolved.has(state) and resolved[state] != ""

func travel(state: String) -> void:
	if not has(state):
		state = "idle"
	if playback and current != state:
		playback.travel(state)
		current = state

## Input gerak: speed01 (0..1), sprint, crouch.
func set_move(speed01: float, sprint: bool, crouch: bool) -> void:
	# set_move hanya dipanggil ketika kaki benar-benar MENYENTUH tanah
	# (player.gd menjaga: is_on_floor() && !_swimming). Maka flag air/swim
	# pada titik ini PASTI kedaluwarsa — mereka tak pernah di-reset sendiri
	# dulu → setelah 1x lompat/renang, set_move ter-blokir SELAMANYA:
	# walk tak pernah animasi & attack hanya bisa sekali (_current tersumpal).
	_air = false
	_swimming = false
	var prev := _move_state
	if speed01 < 0.05:
		_move_state = "crouch_idle" if crouch else "idle"
	elif crouch:
		_move_state = "crouch_move"
	elif sprint:
		_move_state = "sprint"
	elif speed01 < 0.62:
		_move_state = "walk"
	else:
		_move_state = "run"
	if _action_until > Time.get_ticks_msec():
		return
	travel(_move_state)

func set_air(state: String) -> void:
	# state: "jump_start" | "jump_fall" | "jump_land" | "" (grounded)
	if state == "":
		_air = false
		return
	_air = true
	if state == "jump_land":
		_air = false
	_action_until = Time.get_ticks_msec() + 350.0
	travel(state)

func set_swim(swimming: bool, speed01: float) -> void:
	if swimming != _swimming:
		_swimming = swimming
		if not swimming:
			travel("idle")
			return
	if _swimming:
		travel("swim_move" if speed01 > 0.15 else "swim_idle")

## Aksi sekali jalan: "pickup" | "interact" | "emote" | "attack" | "jump_land"
func action(state: String, duration_ms := 900) -> void:
	if not has(state):
		return
	travel(state)
	_action_until = Time.get_ticks_msec() + duration_ms

func set_scale_speed(state: String, scale: float) -> void:
	# perceputan animasi sprin dsb: ubah time_scale per-node tidak tersedia -> pakai speed_scale global sementara
	if anim_player and current == state:
		anim_player.speed_scale = scale
