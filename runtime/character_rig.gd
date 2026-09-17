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

@export_group("Animasi (klip GLB dari file lain)")
## File berisi klip animasi ketika GLB karakter sendiri tidak
## membawanya. Skeleton sama = retarget prafiks saja.
@export var anim_paths: Array[String] = [
	"res://models/AureliaAnim.glb",
	"res://models/AureliaChar_anim.glb",
]
## Offset arah hadap model (derajat) kalau GLB menghadap bukan +Z.
@export_range(-180.0, 180.0, 1.0) var model_yaw_deg := 0.0
## Tinggi target karakter (meter); model melenceng jauh di-rescale.
@export var model_target_height := 1.6

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
@export var skin: Color = QualityPresets.PALETTE_SKIN
@export var hair: Color = QualityPresets.PALETTE_HAIR

## is_bound: TRUE begitu ada skeleton yang terikat ATAU driver animasi
## aktif. (Versi lama murni menunggu _poses terisi — padahal _poses hanya
## diisi apply_pose yang sendirinya digate is_bound di motor: POSE TIDAK
## PERNAH DIPANGGIL. Laten, tersembunyi, baru ketahuan era AnimDriver.)
var is_bound: bool:
	get: return _bound_ok or not _poses.is_empty()
var bound_count: int:
	get: return _poses.size()
var last_bind_report := ""
## Pose terakhir yang ter-resolve (dibaca locomotion_utama kalau
## kepentingan belajar).
var poses: Dictionary:
	get: return _poses

## Jalur animasi GLB (non-prosedural). aktif = anim_active.
var anim: CharacterAnimDriver
var anim_active := false
## Baris diagnostik ringkas untuk strip debug (versi panjang = last_bind_report).
var debug_bind_line := ""
var _calib_h := 0.0

var _skel: MannequinSkeleton
var _poses: Dictionary = {}         ## joint(String) -> Vector3 ter-smooth
var _smoothed: Dictionary = {}
var _bound_ok := false
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
	if anim != null:
		anim.queue_free()
		anim = null
	anim_active = false
	_bound_ok = false
	_bind_report_parts.clear()

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

	_calibrate_model(model)

	_skel = MannequinSkeleton.new()
	_skel.setup(model)
	_bound_ok = _skel.skel != null
	_bind_report_parts.append("bind=%s" % _skel.report())

	## Apply toon setup (outline + rim) ke semua mesh.
	ToonCharacterSetup.apply(_root_node, {
		"shader_body": preload("res://shaders/aurelia_toon.gdshader"),
		"shader_face": preload("res://shaders/aurelia_toon_lite.gdshader"),
		"outline_shader": preload("res://shaders/aurelia_toon_outline.gdshader"),
		"skin_color": skin,
		"hair_color": hair,
	})

	## Jalur animasi GLB bila ada klip yang termapping; prosedural
	## tetap menjadi fallback (lihat _bind_anim).
	_bind_anim(model)

	last_bind_report = " & ".join(_bind_report_parts) \
		+ " | tekstur %d/%d surface bertuan" % [ToonCharacterSetup.last_tex,
			maxi(1, ToonCharacterSetup.last_hadir)]
	var model_short := "?"
	for prt in _bind_report_parts:
		if prt.begins_with("model="):
			model_short = prt.trim_prefix("model=").get_file()
	var jml_peran := anim.mapping.size() if anim != null else 0
	debug_bind_line = "%s h=%.2f | tex=%d/%d | anim=%d" % [
		model_short, _calib_h,
		ToonCharacterSetup.last_tex,
		maxi(1, ToonCharacterSetup.last_hadir), jml_peran]
	BootLog.add(last_bind_report)
	BootLog.add(anim.last_report if anim != null else "anim: nonaktif")

## ------------------------------------------------------------
## Kalibrasi model GLB nyata: ukur AABB seluruh mesh (bind pose),
## rescale ke tinggi target bila melenceng jauh (model sumber
## sering 0,01x/100x), turunkan kaki ke tanah, putar yaw bila
## tidak menghadap +Z. Mannequin (~1,68 m) masuk toleransi.
func _calibrate_model(model: Node3D) -> void:
	var r := _measure_aabb(model, Transform3D(), AABB(), false)
	if not r[1]:
		return
	var bb: AABB = r[0]
	var h: float = bb.size.y
	if h <= 0.001:
		return
	var s := 1.0
	if absf(h - model_target_height) > 0.45:
		s = clampf(model_target_height / h, 0.02, 30.0)
		model.scale = Vector3.ONE * s
	# kaki (dasar AABB) tepat di y=0
	model.position.y = -bb.position.y * s
	if model_yaw_deg != 0.0:
		model.rotation_degrees.y = model_yaw_deg
	_calib_h = h
	if s != 1.0 or model_yaw_deg != 0.0:
		_bind_report_parts.append("kalibr h=%.2f s=%.2f yaw=%.0f" % [h, s, model_yaw_deg])
	else:
		_bind_report_parts.append("kalibr h=%.2f ok" % h)

static func _hide_visuals(n: Node) -> void:
	if n is VisualInstance3D:
		(n as VisualInstance3D).visible = false
	for c in n.get_children():
		_hide_visuals(c)

static func _measure_aabb(n: Node, xf: Transform3D, acc: AABB, has: bool) -> Array:
	var local := xf
	var a := acc
	var h := has
	if n is Node3D:
		local = xf * (n as Node3D).transform
		if n is VisualInstance3D:
			var gi := n as VisualInstance3D
			var bb := local * gi.get_aabb()
			a = a.merge(bb) if h else bb
			h = true
	for c in n.get_children():
		var r := _measure_aabb(c, local, a, h)
		a = r[0]
		h = r[1]
	return [a, h]

## ------------------------------------------------------------
## Sambungkan jalur animasi GLB: klip dari model sendiri dan/atau
## file animasi terpisah. Dua mode retarget otomatis per sumber:
##   "prefix"    — nama tulang kebanyakan sama: ganti prafiks path.
##   "humanoid"  — nama tulang beda (mis. kemasan UE -> J_Bip VRoid):
##                 transplantasi delta rotasi dunia ke rest target.
## Instance file eksternal dipertahankan hidup selama konversi
## (konteks rest dibutuhkan), lalu dibebaskan.
func _bind_anim(model: Node3D) -> void:
	anim = CharacterAnimDriver.new()
	anim.name = "AnimDriver"
	add_child(anim)

	var to_skel := AnimMap.find_skeleton(model)
	var skel_prefix := "Skeleton3D"
	if to_skel != null:
		skel_prefix = str(model.get_path_to(to_skel))
	var to_ctx: Dictionary = AnimMap.rest_ctx(to_skel) if to_skel != null else {}

	var libs: Array = []
	# Klip yang dibawa model itu sendiri (path sudah benar).
	var mesh_player := AnimMap.find_player(model)
	if mesh_player != null:
		for lib_name in mesh_player.get_animation_library_list():
			libs.append({"lib": mesh_player.get_animation_library(lib_name)})

	var sisa: Array = []
	for p in anim_paths:
		if not ResourceLoader.exists(p):
			continue
		var res: Resource = load(p)
		var inst: Node = null
		if res is PackedScene:
			inst = (res as PackedScene).instantiate()
		elif res != null and res.has_method("instantiate_scene"):
			inst = res.instantiate_scene()
		if inst == null:
			continue
		var ap := AnimMap.find_player(inst)
		var from_skel := AnimMap.find_skeleton(inst)
		var mode := "prefix"
		var map: Dictionary = {}
		var from_ctx: Dictionary = {}
		if ap == null and from_skel == null:
			inst.queue_free()
			continue
		if from_skel != null and to_skel != null:
			var sama := 0
			for i in from_skel.get_bone_count():
				if to_skel.find_bone(from_skel.get_bone_name(i)) >= 0:
					sama += 1
			if sama < maxi(6, from_skel.get_bone_count() / 2):
				mode = "humanoid"
				from_ctx = AnimMap.rest_ctx(from_skel)
				map = AnimMap.guess_bone_map(from_skel, to_skel)
				if map.size() < 8:
					mode = "prefix"
					from_ctx = {}
					map = {}
			_bind_report_parts.append("mod=%s map=%d" % [mode, map.size()])
		if ap != null:
			for lib_name in ap.get_animation_library_list():
				libs.append({"lib": ap.get_animation_library(lib_name),
					"mode": mode, "from_ctx": from_ctx, "to_ctx": to_ctx,
					"map": map, "live_src": inst, "live_skel": from_skel,
					"to_skel": to_skel})
		if mode == "humanoid":
			## Paket animasi dibuat bermain nativ pada skeletonnya sendiri
			## (disembunyikan) — delta disalin per-frame oleh driver.
			inst.name = "AnimSrc"
			_hide_visuals(inst)
			_root_node.add_child(inst)
			continue
		sisa.append(inst)
	for st in sisa:
		st.queue_free()

	var n := anim.setup(model, libs, skel_prefix)
	anim_active = anim.active
	if anim_active:
		_bound_ok = true
		_bind_report_parts.append("anim=%d peran" % n)
	elif n > 0:
		_bind_report_parts.append("anim=tak aktif (%d klip?)" % n)

## ---- API yang dipanggil CharacterMotor / HUD -------------------
func drive_anim(st: Dictionary, dt: float) -> void:
	if anim != null and anim.active:
		anim.update_state(st, dt)

func anim_attack(combo: int) -> void:
	if anim != null and anim.active:
		anim.attack(combo)

func anim_dash() -> void:
	if anim != null and anim.active:
		anim.dash()

func anim_jump() -> void:
	if anim != null and anim.active:
		anim.jump()

func anim_land(fall_speed: float) -> void:
	if anim != null and anim.active:
		anim.land(fall_speed)

func anim_skill() -> void:
	if anim != null and anim.active:
		anim.skill()

func anim_burst() -> void:
	if anim != null and anim.active:
		anim.burst()

func anim_debug_line() -> String:
	return anim.debug_line() if anim != null else "anim:kosong"

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
