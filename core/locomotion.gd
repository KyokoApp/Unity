class_name Locomotion
extends RefCounted

## ============================================================
## LOCOMOTION — port 1:1 dari game/locomotion.mjs (lewat C#).
##
## Target pose RELATIF terhadap bind pose rig, dalam radian.
## Setiap sendi yang digerakkan diberi target SETIAP frame supaya
## attack tidak bisa meninggalkan anggota badan tersangkut.
##
## Keluaran: Dictionary { nama_sendi: Vector3 } (radian x/y/z).
## Kelas ini sengaja tidak menyentuh node/scene.
## ============================================================

## i: Dictionary { phase, time, move, run, dash, airborne, falling,
##                attack (float, -1 = tidak menyerang), combo }
## attack -1 memodelkan `attack === null` di JS.
static func sample_pose(i: Dictionary) -> Dictionary:
	var pose := {}
	var put := func(nama: String, x := 0.0, y := 0.0, z := 0.0) -> void:
		pose[nama] = Vector3(x, y, z)

	var breath := sin(i["time"] * 1.8) * .022
	var move: float = i["move"]
	var run: float = i["run"]
	var dash: float = i["dash"]
	var phase: float = i["phase"]

	put.call("PELVIS", .10 * run + .36 * dash,
		sin(phase) * .055 * move, sin(phase) * .035 * move)
	put.call("BELLY", breath - .04 * run, 0.0, -sin(phase) * .022 * move)
	put.call("CHEST", breath * .6, -sin(phase) * .13 * move, 0.0)
	put.call("NECK", -.045 * run)
	put.call("HEAD", -.025 * run, sin(i["time"] * .55) * .035 * (1.0 - move))

	# ['R',0,1] lalu ['L',PI,-1] — urutan harus sama karena cabang
	# airborne menimpa nilai yang sudah ditulis.
	var sides := [["R", 0.0, 1.0], ["L", PI, -1.0]]

	for s in sides:
		var side: String = s[0]
		var offset: float = s[1]
		var sign: float = s[2]
		var swing := sin(phase + offset)
		var lift := maxf(0.0, -swing)

		put.call("THIGH" + side, swing * (.40 + .27 * run + .15 * dash) * move, 0.0, sign * .018 * move)
		put.call("KNEE" + side, (.10 + .78 * lift * lift) * move)
		put.call("LOWLEG" + side, -.08 * lift * move)
		put.call("FOOT" + side, (-swing * .20 - lift * .15) * move)
		put.call("TOE" + side, maxf(0.0, swing) * .16 * move)
		put.call("SHOULDER" + side, -swing * .09 * move, 0.0, sign * .035 * move)
		put.call("ARM" + side, -swing * (.30 + .15 * run) * move, 0.0, sign * .06)
		put.call("FOREARM" + side, .12 + .35 * run + .10 * lift * move)
		put.call("HAND" + side, 0.0, 0.0, sign * .04)
		put.call("KNUCLE" + side, .48 if side == "R" else .12)

		if i["airborne"]:
			put.call("THIGH" + side, .14 if i["falling"] else .38 + offset * .035)
			put.call("KNEE" + side, .26 if i["falling"] else .68)
			put.call("FOOT" + side, -.18)
			put.call("TOE" + side, .05)
			put.call("ARM" + side, -.20, 0.0, sign * .20)
			put.call("FOREARM" + side, .35)

	# Bawa senjata dengan siku santai, bukan menyapu ke belakang punggung.
	# JS memutasinya in-place: pose.ARMR[0] -= .12
	var armr: Vector3 = pose["ARMR"]
	armr.x -= .12
	pose["ARMR"] = armr
	var forearmr: Vector3 = pose["FOREARMR"]
	forearmr.x += .18
	pose["FOREARMR"] = forearmr

	var attack: float = i["attack"]
	if attack >= 0.0:
		var combo: int = i["combo"]
		var t := clampf(attack, 0.0, 1.0)
		var smooth01 := func(x: float) -> float:
			x = clampf(x, 0.0, 1.0)
			return x * x * (3.0 - 2.0 * x)
		var wind: float = smooth01.call(t / .26)
		var cut: float = smooth01.call((t - .26) / .22)
		var recover: float = smooth01.call((t - .60) / .40)
		var arc := (wind - 2.0 * cut) * (1.0 - recover)
		var direction := 1.0 if combo % 2 == 0 else -1.0
		var vertical := combo == 2

		put.call("PELVIS", .07, arc * .32 * direction)
		put.call("BELLY", .04, arc * .18 * direction)
		put.call("CHEST", .10, arc * .55 * direction)
		put.call("SHOULDERR", -.18, arc * .25 * direction, -.12)
		put.call("ARMR",
			-1.25 * arc if vertical else -.35 - .65 * cut * (1.0 - recover),
			arc * .9 * direction, -.22 - arc * .55)
		put.call("FOREARMR", .4 + .55 * wind * (1.0 - cut))
		put.call("HANDR", -.12, arc * .22, 0.0)
		put.call("ARML", .10, 0.0, .18)
		put.call("FOREARML", .30)
		put.call("THIGHR", -.12 * (1.0 - recover))
		put.call("THIGHL", .16 * (1.0 - recover))
		put.call("KNEER", .18 * (1.0 - recover))
		put.call("KNEEL", .23 * (1.0 - recover))

	return pose

static func damp(current: float, target: float, rate: float, dt: float) -> float:
	return current + (target - current) * (1.0 - exp(-rate * dt))

## Sumbu joystick dengan deadzone (radius default 55 seperti game asli).
static func joystick_axis(x: float, y: float, radius: float = 55.0, deadzone: float = .14) -> Vector2:
	var length := sqrt(x * x + y * y) / radius
	if length <= deadzone:
		return Vector2.ZERO
	var amount := minf(1.0, (length - deadzone) / (1.0 - deadzone))
	return Vector2(x / (length * radius) * amount, y / (length * radius) * amount)
