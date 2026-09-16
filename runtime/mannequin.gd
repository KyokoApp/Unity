class_name MannequinSkeleton
extends RefCounted

## ============================================================
## MANNEQUIN SKELETON — pembungkus Skeleton3D model karakter.
##
## Tugas:
##   1. Menjalin 23 Joint (RigMapping) ke indeks tulang Skeleton3D,
##      dengan tabel kandidat nama (DEF-* Koikatsu, humanoid VRM,
##      atau tulang mannequin kita sendiri).
##   2. Menyimpan BIND pose (rotasi lokal tiap tulang saat terikat).
##   3. Koreksi lengan-turun (arm fix) ala CharacterRig.cs: bind
##      pose VRM = T-pose, SEMUA pose Locomotion ditulis untuk bind
##      berlengan turun — tanpa koreksi karakter idle seperti salib.
##   4. Menerapkan pose prosedural: local = bind * fix * euler(v*tanda).
## ============================================================

const J := RigMapping

var skel: Skeleton3D
var joint_to_bone: Dictionary = {}     ## Joint(String) -> int
var bind_local: Dictionary = {}        ## int -> Quaternion bind
var arm_fix: Dictionary = {}           ## int -> Quaternion koreksi
var _report := ""

func setup(root: Node3D) -> void:
	skel = _find_skeleton(root)
	joint_to_bone.clear()
	bind_local.clear()

	if skel == null:
		_report = "TIDAK ADA Skeleton3D — karakter akan diam."
		return

	_arm_fix_root(root)

	# Catat rest tiap tulang SEKALI sebagai bind pose (setara
	# _serializedBind di versi Unity).
	for b in skel.get_bone_count():
		bind_local[b] = skel.get_bone_pose_rotation(b)

	var missing := []
	for j in RigMapping.ALL_JOINTS:
		var bi := _find_bone(j)
		if bi < 0:
			missing.append(j + ":" + ",".join(RigMapping.BONE_CANDIDATES.get(j, [])))
			continue
		joint_to_bone[j] = bi

	if missing.is_empty():
		_report = "terikat %d/%d tulang (lengkap)." % [joint_to_bone.size(),
			RigMapping.ALL_JOINTS.size()]
	else:
		_report = "terikat %d/%d tulang. TIDAK KETEMU: %s" % [
			joint_to_bone.size(), RigMapping.ALL_JOINTS.size(), "; ".join(missing)]

	_compute_arm_fix()

## Koreksi lengan (FixArm di CharacterRig.cs): ukur arah lengan di
## ruang karakter, putar ke arah rileks (bawah + sedikit keluar +
## sedikit depan) lewat rotasi busur pendek, dinyatakan sebagai
## premultiply lokal-tulang. Kalau modelnya sudah A-pose, sudutnya
## ~0 dan koreksinya otomatis identitas.
const ARM_FIX_JOINTS := [
	[J.J_LEFT_UPPER_ARM, J.J_LEFT_LOWER_ARM],
	[J.J_RIGHT_UPPER_ARM, J.J_RIGHT_LOWER_ARM],
]

func _compute_arm_fix() -> void:
	arm_fix.clear()
	if skel == null:
		return
	for pair in ARM_FIX_JOINTS:
		var upper: String = pair[0]
		var lower: String = pair[1]
		if not joint_to_bone.has(upper) or not joint_to_bone.has(lower):
			continue
		var u: int = joint_to_bone[upper]
		var e: int = joint_to_bone[lower]
		var span: Vector3 = skel.get_bone_global_pose(e).origin - skel.get_bone_global_pose(u).origin
		if span.length_squared() < 1e-10:
			continue
		# Skeleton space -> ruang karakter (manual InverseTransformDirection)
		var dir_char := (_char_basis.inverse() * (span.normalized())).normalized()
		var want_char := Vector3(signf(dir_char.x) * 0.16, -1.0, 0.10).normalized()
		if rad_to_deg(dir_char.angle_to(want_char)) < 1.0:
			continue
		var q_char := Quaternion(dir_char, want_char)

		var parent := skel.get_bone_parent(u)
		var parent_q := Quaternion()
		if parent >= 0:
			parent_q = skel.get_bone_global_pose(parent).basis.get_rotation_quaternion()
		var q_parent := parent_q.inverse() * q_char * parent_q
		var bind_q: Quaternion = bind_local.get(u, Quaternion())
		# local' = bind * (bind^-1 * q * bind) — lihat komentar FixArm.
		arm_fix[u] = bind_q.inverse() * q_parent * bind_q

func report() -> String:
	return _report

func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var s := _find_skeleton(c)
		if s != null:
			return s
	return null

func _norm(x: String) -> String:
	return x.to_lower().replace(" ", "").replace("-", "").replace("_", "").replace(".", "")

func _find_bone(joint: String) -> int:
	var candidates: Array = RigMapping.BONE_CANDIDATES.get(joint, [joint])
	for c in candidates:
		var nc := _norm(c)
		for b in skel.get_bone_count():
			if _norm(skel.get_bone_name(b)) == nc:
				return b
	return -1

## Simpan koordinat karakter supaya arm-fix bisa menghitung
## dirChar/wantChar lewat root Q tergantung orientasi model.
var _char_basis := Basis()

func _arm_fix_root(root: Node3D) -> void:
	if root != null:
		_char_basis = root.global_transform.basis

## Terapkan pose. pose: {Joint: Vector3(radian)} + callback tanda.
func apply_pose(pose: Dictionary, k: float, signs: Callable) -> void:
	if skel == null:
		return
	for j in joint_to_bone:
		if not pose.has(j):
			continue
		var b: int = joint_to_bone[j]
		var v: Vector3 = pose[j]
		var s: Vector3 = signs.call(j)
		var q := Quaternion.from_euler(Vector3(v.x * s.x, v.y * s.y, v.z * s.z))
		var fix: Quaternion = arm_fix.get(b, Quaternion())
		var target: Quaternion = bind_local.get(b, Quaternion()) * fix * q
		var cur := skel.get_bone_pose_rotation(b)
		skel.set_bone_pose_rotation(b, cur.slerp(target, clampf(k, 0.0, 1.0)))

func reset_to_bind() -> void:
	if skel == null:
		return
	for b in bind_local:
		skel.set_bone_pose_rotation(b, bind_local[b])


## ============================================================
## MANNEQUIN BODY — bodi cadangan low-poly berbentuk manusia
## (bola kapsul general-purpose). Dipakai kalau model VRM/GLB
## tidak ditemukan; gerak prosedural tetap jalan, jadi game tidak
## pernah kehilangan karakternya.
## ============================================================
class MannequinBody:
	extends Node3D

	const COLORS := {
		"skin": Color(0.97, 0.85, 0.73, 1.0),
		"hair": Color(0.55, 0.35, 0.25, 1.0),
		"cloth": Color(0.25, 0.35, 0.55, 1.0),
		"cloth2": Color(0.85, 0.80, 0.70, 1.0),
		"boot": Color(0.20, 0.22, 0.28, 1.0),
	}

	## build_default: Skeleton3D + kapsul per tulang, tinggi ~1,68 m.
	static func build_default() -> MannequinBody:
		var root := MannequinBody.new()
		var skel := Skeleton3D.new()
		skel.name = "Skeleton3D"
		root.add_child(skel)

		# rangka tulang (posisi = titik "atas" setiap segmen)
		var BONES: Array = [
			# nama, parent, pos rel parent (dari bawah ke atas rantai)
			["Hips", -1, Vector3(0, 0.95, 0)],
			["Spine", 0, Vector3(0, 0.13, 0)],
			["Chest", 1, Vector3(0, 0.22, 0)],
			["Neck", 2, Vector3(0, 0.17, 0)],
			["Head", 3, Vector3(0, 0.12, 0)],
			["LeftShoulder", 2, Vector3(-0.10, 0.13, 0)],
			["LeftUpperArm", 5, Vector3(-0.10, 0.0, 0)],
			["LeftLowerArm", 6, Vector3(0, -0.26, 0)],
			["LeftHand", 7, Vector3(0, -0.24, 0)],
			["RightShoulder", 2, Vector3(0.10, 0.13, 0)],
			["RightUpperArm", 9, Vector3(0.10, 0.0, 0)],
			["RightLowerArm", 10, Vector3(0, -0.26, 0)],
			["RightHand", 11, Vector3(0, -0.24, 0)],
			["LeftUpperLeg", 0, Vector3(-0.10, -0.02, 0)],
			["LeftLowerLeg", 13, Vector3(0, -0.44, 0)],
			["LeftFoot", 14, Vector3(0, -0.42, 0)],
			["LeftToes", 15, Vector3(0, -0.05, 0.12)],
			["RightUpperLeg", 0, Vector3(0.10, -0.02, 0)],
			["RightLowerLeg", 17, Vector3(0, -0.44, 0)],
			["RightFoot", 18, Vector3(0, -0.42, 0)],
			["RightToes", 19, Vector3(0, -0.05, 0.12)],
		]
		var rest_of := {}
		for i in BONES.size():
			var b: Array = BONES[i]
			skel.add_bone(b[0])
			if b[1] >= 0:
				skel.set_bone_parent(i, b[1])
			rest_of[i] = Transform3D(Basis(), b[2])
		for i in BONES.size():
			skel.set_bone_rest(i, rest_of[i])

		# segmen body: (joint_godot_index, arah panjang, panjang, r, warna)
		var parts := [
			# kapsul tubuh
			{"bone": 0, "p0": Vector3(0, 0.10, 0), "p1": Vector3(0, -0.06, 0), "r": 0.09, "c": "cloth"},
			{"bone": 1, "p0": Vector3(0, 0.0, 0), "p1": Vector3(0, 0.12, 0), "r": 0.085, "c": "cloth"},
			{"bone": 2, "p0": Vector3(0, 0.0, 0), "p1": Vector3(0, 0.16, 0), "r": 0.095, "c": "cloth"},
			{"bone": 3, "p0": Vector3(0, 0.0, 0), "p1": Vector3(0, 0.10, 0), "r": 0.05, "c": "skin"},
			# kepala (sepasang: bola kepala + rambut)
			{"bone": 4, "p0": Vector3(0, 0.11, 0), "p1": Vector3(0, 0.11, 0), "r": 0.11, "c": "skin", "ball": true},
			{"bone": 4, "p0": Vector3(0, 0.135, -0.02), "p1": Vector3(0, 0.135, -0.02), "r": 0.115, "c": "hair", "ball": true},
			# lengan (dari pundak ke tangan)
			{"bone": 6, "p1": Vector3(0, -0.26, 0), "r": 0.035, "c": "skin"},
			{"bone": 7, "p1": Vector3(0, -0.24, 0), "r": 0.030, "c": "skin"},
			{"bone": 8, "p0": Vector3(0, 0.0, 0), "p1": Vector3(0, -0.10, 0), "r": 0.034, "c": "skin"},
			{"bone": 10, "p1": Vector3(0, -0.26, 0), "r": 0.035, "c": "skin"},
			{"bone": 11, "p1": Vector3(0, -0.24, 0), "r": 0.030, "c": "skin"},
			{"bone": 12, "p0": Vector3(0, 0.0, 0), "p1": Vector3(0, -0.10, 0), "r": 0.034, "c": "skin"},
			# kaki
			{"bone": 13, "p1": Vector3(0, -0.44, 0), "r": 0.070, "c": "cloth"},
			{"bone": 14, "p1": Vector3(0, -0.42, 0), "r": 0.055, "c": "skin"},
			{"bone": 15, "p0": Vector3(0, 0.0, 0.0), "p1": Vector3(0, -0.04, 0.13), "r": 0.05, "c": "boot"},
			{"bone": 17, "p1": Vector3(0, -0.44, 0), "r": 0.070, "c": "cloth"},
			{"bone": 18, "p1": Vector3(0, -0.42, 0), "r": 0.055, "c": "skin"},
			{"bone": 19, "p0": Vector3(0, 0.0, 0.0), "p1": Vector3(0, -0.04, 0.13), "r": 0.05, "c": "boot"},
		]

		for p in parts:
			var mesh := _capsule_mesh(p)
			var att := BoneAttachment3D.new()
			att.bone_idx = p["bone"]
			var m := MeshInstance3D.new()
			m.mesh = mesh
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			var off: Vector3 = (p["p0"] if p.has("p0") else Vector3.ZERO) \
				+ (p["p1"] if p.has("p1") else Vector3.ZERO)
			off *= 0.5
			off.x *= 0.0 if p["bone"] == 6 or p["bone"] == 10 else 1.0
			m.position = off
			var mat := StandardMaterial3D.new()
			mat.albedo_color = COLORS[p["c"]]
			mat.roughness = 0.9
			m.material_override = mat
			att.add_child(m)
			skel.add_child(att)

		return root

	static func _capsule_mesh(p: Dictionary) -> Mesh:
		var r: float = p["r"]
		if p.get("ball", false):
			var sp := SphereMesh.new()
			sp.radius = r
			sp.height = r * 2.0
			sp.radial_segments = 12
			sp.rings = 8
			return sp
		var p0: Vector3 = p.get("p0", Vector3.ZERO)
		var p1: Vector3 = p.get("p1", Vector3.ZERO)
		var h := p0.distance_to(p1) * 1.12 + r * 2.0
		var c := CapsuleMesh.new()
		c.radius = r
		c.height = h
		c.radial_segments = 8
		c.rings = 4
		return c
