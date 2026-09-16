class_name CharacterRig
extends Node3D

## ============================================================
## CHARACTER RIG — menulis rotasi tulang tiap frame dari hasil
## RigMapping.resolve(). (Port dari CharacterRig.cs.)
##
## Game ini tidak memakai animasi jadi — SEMUA gerak didorong
## prosedural (sample_pose -> resolve -> apply_pose), jadi node
## ini berada di grup "player" dan menjadi target kamera/streamer.
##
## Formula (sama persis dengan C#):
##     local = bind * Quaternion.from_euler(v * tanda)
## Pose dihaluskan antar-frame (tidak patah saat input berubah
## mendadak), badan LEAN saat berputar, lutut menyekuk saat
## mendarat (pulse_crouch).
## ============================================================

@export_group("Model")
## PackedScene karakter (VRM->GLB). Kosong = try_scenes dicari
## satu-per-satu; terakhir jatuh ke bodi kasar low-poly.
@export var model_scene: PackedScene
@export var model_paths: Array[String] = [
	"res://models/AureliaChar.tscn",
	"res://models/AureliaChar.glb",
]

@export_group("Kalibrasi sumbu — balik tanda kalau limb bergerak terbalik")
@export_range(-1.0, 1.0) var sign_leg_x := 1.0
@export_range(-1.0, 1.0) var sign_leg_y := 1.0
@export_range(-1.0, 1.0) var sign_leg_z := 1.0
@export_range(-1.0, 1.0) var sign_arm_x := 1.0
@export_range(-1.0, 1.0) var sign_arm_y := 1.0
@export_range(-1.0, 1.0) var sign_arm_z := -1.0
@export_range(-1.0, 1.0) var sign_spine_x := 1.0
@export_range(-1.0, 1.0) var sign_spine_y := 1.0
@export_range(-1.0, 1.0) var sign_spine_z := 1.0
@export_range(-1.0, 1.0) var sign_foot_x := 1.0

@export_group("Kehalusan")
@export var pose_smooth_rate: float = 14.0
@export var lean_strength: float = 0.7

@export_group("Coloring (VRM -> aurelia_toon)")
@export var skin: Color = QualityPresets._ZERO_SKIN
@export var hair: Color = QualityPresets._ZERO_HAIR

var is_bound: bool:
	get: return not _poses.is_empty()
var bound_count: int:
	get: return _poses.size()
var last_bind_report := ""
## Pose terakhir yang ter-resolve (dibaca locomotion_utama kalau
## kepentingan belajar).
var poses: Dictionary:
	get: return _poses

var _skel: MannequinSkeleton
var _poses: Dictionary = {}         ## joint(String) -> Vector3 ter-smooth
var _smoothed: Dictionary = {}
var _last_fall := -1.0
var _crouch := 0.0
var _lean := 0.0
var _root_node: Node3D
var _bind_report_parts: Array[String] = []

func _ready() -> void:
	## Penampung slot model: user bisa memasukkan apa pun lewat
	## model_scene atau model_paths; kalau semua gagal dipakai
	## mannequin bawaan supaya karakter TETAP tampak.
	_root_node = Node3D.new()
	_root_node.name = "CharacterModel"
	add_child(_root_node)
	bind()

func bind() -> void:
	for c in _root_node.get_children():
		c.queue_free()

	var model: Node3D = null
	var used_path := ""
	if model_scene != null:
		model = model_scene.instantiate() as Node3D
		used_path = "model_scene"
	else:
		for p in model_paths:
			if ResourceLoader.exists(p):
				var res: Resource = load(p)
				if res is PackedScene:
					model = (res as PackedScene).instantiate() as Node3D
					used_path = p
					break
				elif res != null and res.has_method("instantiate_scene"):
					model = res.instantiate_scene() as Node3D
					used_path = p
					break

	if model != null:
		model.name = "Model"
		_root_node.add_child(model)
		_bind_report_parts.append("model=%s" % used_path)
	else:
		## fallback: mannequin low-poly (manusia kapsul) — supaya game
		## tidak kosong walau model belum dikonversi.
		model = MannequinSkeleton.MannequinBody.build_default()
		model.name = "ModelFallback"
		_root_node.add_child(model)
		_bind_report_parts.append("model=fallback mannequin")

	_skel = MannequinSkeleton.new()
	_skel.setup(model)
	_bind_report_parts.append("bind=%s" % _skel.report())
	last_bind_report = " & ".join(_bind_report_parts)
	BootLog.add(last_bind_report)

	## Apply toon setup (outline + rim) ke semua mesh.
	ToonCharacterSetup.apply(_root_node, {
		"shader_body": preload("res://shaders/aurelia_toon.gdshader"),
		"shader_face": preload("res://shaders/aurelia_toon_lite.gdshader"),
		"outline_shader": preload("res://shaders/aurelia_toon_outline.gdshader"),
		"skin_color": skin,
		"hair_color": hair,
	})

func set_lean(n: float) -> void:
	_lean = clampf(n, -1.0, 1.0)

## Root model karakter (dipakai quality_applier untuk tying outline).
func root_model() -> Node3D:
	return _root_node

func pulse_crouch(strength: float) -> void:
	_crouch = clampf(_crouch + strength, 0.0, 1.0)

func apply_pose(pose: Dictionary, _phase: float, dt: float) -> void:
	if _skel == null:
		return
	var k := 1.0 - exp(-pose_smooth_rate * maxf(0.0, dt))
	_crouch *= exp(-6.0 * maxf(0.0, dt))
	if _crouch < 0.001:
		_crouch = 0.0

	# Haluskan: pose mengejar target, bukan teleport (dari C#:
	# _prev mengejar v dengan faktor k setiap frame).
	for j in pose:
		var target: Vector3 = pose[j]

		# Lean + crouch ditambahkan di ruang abstrak (sebelum tanda
		# kalibrasi), supaya ikut arah sumbu yang benar.
		var ex := 0.0
		var ey := 0.0
		match j:
			RigMapping.J_CHEST:
				ey = _lean * 0.30 * lean_strength
			RigMapping.J_SPINE:
				ey = _lean * 0.18 * lean_strength
			RigMapping.J_LEFT_UPPER_LEG, RigMapping.J_RIGHT_UPPER_LEG:
				ex = _crouch * 0.55
			RigMapping.J_LEFT_LOWER_LEG, RigMapping.J_RIGHT_LOWER_LEG:
				ex = _crouch * 0.80
		var want := Vector3(target.x + ex, target.y + ey, target.z)
		var prev: Vector3 = _smoothed.get(j, want)
		_smoothed[j] = prev.lerp(want, k)

	_poses = _smoothed
	# Sudah dihaluskan per sendi di atas -> k=1 di penerapan.
	_skel.apply_pose(_smoothed, 1.0, _sign_callback())

func reset_to_bind() -> void:
	_poses.clear()
	_crouch = 0.0
	if _skel != null:
		_skel.reset_to_bind()

func _sign_callback() -> Callable:
	return func(joint: String) -> Vector3:
		match joint:
			RigMapping.J_HIPS, RigMapping.J_SPINE, RigMapping.J_CHEST, \
			RigMapping.J_NECK, RigMapping.J_HEAD:
				return Vector3(sign_spine_x, sign_spine_y, sign_spine_z)
			RigMapping.J_LEFT_UPPER_LEG, RigMapping.J_RIGHT_UPPER_LEG, \
			RigMapping.J_LEFT_LOWER_LEG, RigMapping.J_RIGHT_LOWER_LEG, \
			RigMapping.J_LEFT_SHIN_TWIST_A, RigMapping.J_RIGHT_SHIN_TWIST_A, \
			RigMapping.J_LEFT_SHIN_TWIST_B, RigMapping.J_RIGHT_SHIN_TWIST_B:
				return Vector3(sign_leg_x, sign_leg_y, sign_leg_z)
			RigMapping.J_LEFT_FOOT, RigMapping.J_RIGHT_FOOT, \
			RigMapping.J_LEFT_TOES, RigMapping.J_RIGHT_TOES:
				return Vector3(sign_foot_x, 1.0, 1.0)
			_:
				return Vector3(sign_arm_x, sign_arm_y, sign_arm_z)
