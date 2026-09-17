class_name RigMapping
extends RefCounted

## ============================================================
## RIG MAPPING — memetakan 25 sendi keluaran Locomotion.sample_pose()
## ke tulang karakter yang dipakai project ini.
## (Port dari RigMapping.cs — PURE, tanpa scene.)
##
## Rig sumber lama (Hornet) sudah dibuang. Model penggantinya punya
## tulang bernama lain dan TIDAK punya padanan untuk 3 pasang sendi.
## Keputusan "melipat ke mana" adalah keputusan desain yang harus
## bisa dites, bukan dikira-kira di dalam script node.
##
## Hasil pengukuran atas model (lihat art/characters/LISENSI.md):
##   - 49 bone humanoid VRM lengkap, termasuk seluruh jari
##   - TIDAK ada clavicle/bahu  -> SHOULDER tidak punya tujuan
##   - ada tulang twist .001/.002 -> LOWLEG punya tujuan
##   - ada *FingerPalm_*         -> KNUCLE bisa dilipat ke pergelangan
##
## Semua angka dalam RADIAN, relatif terhadap bind pose.
## ============================================================

## Slot tulang nyata yang digerakkan (padanan enum Joint di C#,
## sebagai konstanta string untuk kunci Dictionary).
const J_HIPS := "Hips"
const J_SPINE := "Spine"
const J_CHEST := "Chest"
const J_NECK := "Neck"
const J_HEAD := "Head"

const J_LEFT_UPPER_LEG := "LeftUpperLeg"
const J_LEFT_LOWER_LEG := "LeftLowerLeg"
const J_LEFT_SHIN_TWIST_A := "LeftShinTwistA"
const J_LEFT_SHIN_TWIST_B := "LeftShinTwistB"
const J_LEFT_FOOT := "LeftFoot"
const J_LEFT_TOES := "LeftToes"
const J_RIGHT_UPPER_LEG := "RightUpperLeg"
const J_RIGHT_LOWER_LEG := "RightLowerLeg"
const J_RIGHT_SHIN_TWIST_A := "RightShinTwistA"
const J_RIGHT_SHIN_TWIST_B := "RightShinTwistB"
const J_RIGHT_FOOT := "RightFoot"
const J_RIGHT_TOES := "RightToes"

const J_LEFT_UPPER_ARM := "LeftUpperArm"
const J_LEFT_LOWER_ARM := "LeftLowerArm"
const J_LEFT_HAND := "LeftHand"
const J_RIGHT_UPPER_ARM := "RightUpperArm"
const J_RIGHT_LOWER_ARM := "RightLowerArm"
const J_RIGHT_HAND := "RightHand"

const ALL_JOINTS: Array[String] = [
	J_HIPS, J_SPINE, J_CHEST, J_NECK, J_HEAD,
	J_LEFT_UPPER_LEG, J_LEFT_LOWER_LEG, J_LEFT_SHIN_TWIST_A, J_LEFT_SHIN_TWIST_B,
	J_LEFT_FOOT, J_LEFT_TOES,
	J_RIGHT_UPPER_LEG, J_RIGHT_LOWER_LEG, J_RIGHT_SHIN_TWIST_A, J_RIGHT_SHIN_TWIST_B,
	J_RIGHT_FOOT, J_RIGHT_TOES,
	J_LEFT_UPPER_ARM, J_LEFT_LOWER_ARM, J_LEFT_HAND,
	J_RIGHT_UPPER_ARM, J_RIGHT_LOWER_ARM, J_RIGHT_HAND,
]

## Daftar kandidat nama tulang per sendi, untuk mengikat model apa pun:
##   1. nama terukur dari model Koikatsu/VRM ini ("DEF-..."),
##   2. nama node humanoid VRM/glTF standar ("Hips", "LeftUpperLeg"),
##   3. varian snake/lower yang umum dari exporter lain.
## character_rig.gd memakai ini; BoneMatcher menormalkan spasi,
## strip, dan kapitalisasi supaya "DEF-Left leg" == "defleftleg".
const BONE_CANDIDATES: Dictionary = {
	J_HIPS:            ["DEF-Hips", "Hips", "hips"],
	J_SPINE:           ["DEF-Spine", "Spine", "spine"],
	J_CHEST:           ["DEF-Chest", "Chest", "UpperChest", "chest", "upperChest"],
	J_NECK:            ["DEF-Neck", "Neck", "neck"],
	J_HEAD:            ["DEF-Head", "Head", "head"],

	J_LEFT_UPPER_LEG:  ["DEF-Left leg", "LeftUpperLeg", "leftUpperLeg", "Left_UpperLeg", "UpperLeg_L"],
	J_LEFT_LOWER_LEG:  ["DEF-Left knee", "LeftLowerLeg", "leftLowerLeg", "Left_LowerLeg", "LowerLeg_L"],
	J_LEFT_SHIN_TWIST_A: ["DEF-Left knee.001", "LeftShinTwistA"],
	J_LEFT_SHIN_TWIST_B: ["DEF-Left knee.002", "LeftShinTwistB"],
	J_LEFT_FOOT:       ["DEF-Left ankle", "LeftFoot", "leftFoot", "Foot_L"],
	J_LEFT_TOES:       ["DEF-Left toe", "LeftToes", "leftToes", "Toes_L"],
	J_RIGHT_UPPER_LEG: ["DEF-Right leg", "RightUpperLeg", "rightUpperLeg", "UpperLeg_R"],
	J_RIGHT_LOWER_LEG: ["DEF-Right knee", "RightLowerLeg", "rightLowerLeg", "LowerLeg_R"],
	J_RIGHT_SHIN_TWIST_A: ["DEF-Right knee.001", "RightShinTwistA"],
	J_RIGHT_SHIN_TWIST_B: ["DEF-Right knee.002", "RightShinTwistB"],
	J_RIGHT_FOOT:      ["DEF-Right ankle", "RightFoot", "rightFoot", "Foot_R"],
	J_RIGHT_TOES:      ["DEF-Right toe", "RightToes", "rightToes", "Toes_R"],

	J_LEFT_UPPER_ARM:  ["DEF-Left arm", "LeftUpperArm", "leftUpperArm", "UpperArm_L"],
	J_LEFT_LOWER_ARM:  ["DEF-Left elbow", "LeftLowerArm", "leftLowerArm", "LowerArm_L"],
	J_LEFT_HAND:       ["DEF-Left wrist", "LeftHand", "leftHand", "Hand_L"],
	J_RIGHT_UPPER_ARM: ["DEF-Right arm", "RightUpperArm", "rightUpperArm", "UpperArm_R"],
	J_RIGHT_LOWER_ARM: ["DEF-Right elbow", "RightLowerArm", "rightLowerArm", "LowerArm_R"],
	J_RIGHT_HAND:      ["DEF-Right wrist", "RightHand", "rightHand", "Hand_R"],
}

## Berapa bagian dari LOWLEG yang masuk ke masing-masing tulang twist
## betis. 0.5/0.5 membagi putaran merata sehingga kulit tidak melintir.
const SHIN_TWIST_SPLIT := 0.5

## KNUCLE bernilai konstan (.48 kanan, .12 kiri) dan tidak punya tulang
## tujuan — dilipat ke sumbu X pergelangan. Kalau tangan terlihat
## terpuntir aneh, ini angka pertama yang dinolkan.
const KNUCKLE_WEIGHT := 1.0

## SHOULDER tidak punya clavicle tujuan; kontribusinya kecil
## (-swing*.09 dan sign*.035) jadi dilipat penuh ke lengan atas.
const SHOULDER_WEIGHT := 1.0

static func at_pose(pose: Dictionary, key: String) -> Vector3:
	return pose.get(key, Vector3.ZERO)

## Resolve: 25 sendi abstrak -> 23 slot tulang konkret.
##
## Tiga aturan lipat:
##   ARM    += SHOULDER * SHOULDER_WEIGHT   (tidak ada clavicle)
##   HAND   += KNUCLE   * KNUCKLE_WEIGHT    (tidak ada tulang knuckle)
##   LOWLEG ->  ShinTwistA/B dibagi SHIN_TWIST_SPLIT
static func resolve(pose: Dictionary) -> Dictionary:
	var o := {}
	o[J_HIPS] = at_pose(pose, "PELVIS")
	o[J_SPINE] = at_pose(pose, "BELLY")
	o[J_CHEST] = at_pose(pose, "CHEST")
	o[J_NECK] = at_pose(pose, "NECK")
	o[J_HEAD] = at_pose(pose, "HEAD")
	_apply_side(o, _left_slots(), "L", pose)
	_apply_side(o, _right_slots(), "R", pose)
	return o

static func _left_slots() -> Dictionary:
	return {"upper_leg": J_LEFT_UPPER_LEG, "lower_leg": J_LEFT_LOWER_LEG,
			"twist_a": J_LEFT_SHIN_TWIST_A, "twist_b": J_LEFT_SHIN_TWIST_B,
			"foot": J_LEFT_FOOT, "toes": J_LEFT_TOES,
			"upper_arm": J_LEFT_UPPER_ARM, "lower_arm": J_LEFT_LOWER_ARM,
			"hand": J_LEFT_HAND}

static func _right_slots() -> Dictionary:
	return {"upper_leg": J_RIGHT_UPPER_LEG, "lower_leg": J_RIGHT_LOWER_LEG,
			"twist_a": J_RIGHT_SHIN_TWIST_A, "twist_b": J_RIGHT_SHIN_TWIST_B,
			"foot": J_RIGHT_FOOT, "toes": J_RIGHT_TOES,
			"upper_arm": J_RIGHT_UPPER_ARM, "lower_arm": J_RIGHT_LOWER_ARM,
			"hand": J_RIGHT_HAND}

static func _apply_side(o: Dictionary, s: Dictionary, side: String, pose: Dictionary) -> void:
	var thigh := at_pose(pose, "THIGH" + side)
	var knee := at_pose(pose, "KNEE" + side)
	var lowleg := at_pose(pose, "LOWLEG" + side)
	var foot := at_pose(pose, "FOOT" + side)
	var toe := at_pose(pose, "TOE" + side)
	var shoulder := at_pose(pose, "SHOULDER" + side)
	var arm := at_pose(pose, "ARM" + side)
	var forearm := at_pose(pose, "FOREARM" + side)
	var hand := at_pose(pose, "HAND" + side)
	var knuckle := at_pose(pose, "KNUCLE" + side)

	o[s["upper_leg"]] = thigh
	o[s["lower_leg"]] = knee
	o[s["twist_a"]] = lowleg * SHIN_TWIST_SPLIT
	o[s["twist_b"]] = lowleg * (1.0 - SHIN_TWIST_SPLIT)
	o[s["foot"]] = foot
	o[s["toes"]] = toe

	o[s["upper_arm"]] = arm + shoulder * SHOULDER_WEIGHT
	o[s["lower_arm"]] = forearm
	o[s["hand"]] = hand + knuckle * KNUCKLE_WEIGHT

## Daftar 25 kunci yang dihasilkan sample_pose. Dipakai tes untuk
## memastikan tidak ada kunci yang diam-diam tidak terpakai.
const POSE_KEYS: Array[String] = [
	"PELVIS", "BELLY", "CHEST", "NECK", "HEAD",
	"THIGHL", "KNEEL", "LOWLEGL", "FOOTL", "TOEL",
	"SHOULDERL", "ARML", "FOREARML", "HANDL", "KNUCLEL",
	"THIGHR", "KNEER", "LOWLEGR", "FOOTR", "TOER",
	"SHOULDERR", "ARMR", "FOREARMR", "HANDR", "KNUCLER",
]
