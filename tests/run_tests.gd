extends SceneTree

## ============================================================
## TEST RUNNER — uji murni (headless) untuk seluruh core/ +
## bagian runtime yang tidak menyentuh GPU.
##
## Jalankan:
##     godot --headless --path . --script tests/run_tests.gd
##
## Keluar dengan kode 0 kalau semua lulus, 1 kalau ada yang gagal.
## ============================================================

var _passed := 0
var _failed := 0
var _failures: Array[String] = []

func assert_true(cond: bool, name: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		_failures.append(name)
		print("GAGAL: " + name)

func assert_eq(a, b, name: String) -> void:
	assert_true(a == b, "%s ([%s] != [%s])" % [name, str(a), str(b)])

func assert_aproks(a: float, b: float, eps: float, name: String) -> void:
	assert_true(abs(a - b) <= eps,
		"%s (|%f - %f| > %f)" % [name, a, b, eps])

func _init() -> void:
	print("== Aurelia test runner ==")
	_test_js_math()
	_test_world_data()
	_test_terrain_mesh()
	_test_locomotion()
	_test_combat()
	_test_rig_mapping()
	_test_scatter()
	_test_settings()
	_test_gfx()
	_test_motor_misc()
	print("selesai: %d lulus, %d gagal" % [_passed, _failed])
	for f in _failures:
		print("  - " + f)
	quit(0 if _failed == 0 else 1)

# ------------------------------------------------------------------
func _test_js_math() -> void:
	assert_aproks(Vector3(1, 2, 3).length(), sqrt(14.0), 1e-5, "jsmath sanity")

func _test_world_data() -> void:
	# determinisme: input sama -> output sama
	assert_eq(WorldData.terrain_h(123.4, -56.7), WorldData.terrain_h(123.4, -56.7),
		"terrain_h deterministik")
	var h := WorldData.terrain_h(0.0, 0.0)
	assert_true(h > -30.0 and h < 90.0, "terrain_h dalam rentang sehat")
	assert_eq(WorldData.REGIONS.size(), 7, "ada 7 region")
	assert_eq(WorldData.region_at(0, 0)["id"], "heartlands", "pusat = heartlands")
	assert_eq(WorldData.region_at(-750, -750)["id"], "frost", "NW = frost")
	assert_eq(WorldData.waypoints().size(), 7, "7 waypoint")
	# chunk plan terdekat dulu
	var plan := WorldData.chunk_plan(128.0, 128.0, 2)
	assert_true(plan.size() >= 25, "plan radius 2 penuh")
	var prev := -1.0
	for c in plan:
		var d: float = c["cx"] * c["cx"] + c["cz"] * c["cz"]
		assert_true(d >= prev - 6.0, "plan tidak bolak-balik terlalu jauh")
		prev = d

func _test_terrain_mesh() -> void:
	var d := TerrainMesh.build(0, 0, 8)
	assert_eq(d["vertices"].size(), 81, "81 verteks untuk quads 8")
	assert_eq(d["triangles"].size(), 8 * 8 * 2 * 3, "indeks = quads*2*3")
	assert_eq(d["triangle_count"], 128, "triangle_count")
	assert_eq(d["colors"].size(), 81, "warna per verteks")
	assert_true(TerrainMesh.build(0, 0, 999).is_empty(), "quads > MAX -> kosong")
	# warna alpha selalu 1
	var c: Color = d["colors"][40]
	assert_eq(c.a, 1.0, "alpha warna verteks = 1")

func _test_locomotion() -> void:
	var pose := Locomotion.sample_pose({
		"phase": 1.0, "time": 2.0, "move": 0.5, "run": 0.2,
		"dash": 0.0, "airborne": false, "falling": false,
		"attack": -1.0, "combo": 0,
	})
	for k in RigMapping.POSE_KEYS:
		assert_true(pose.has(k), "pose punya kunci " + k)
		var v: Vector3 = pose[k]
		assert_true(is_finite(v.x) and is_finite(v.y) and is_finite(v.z),
			"pose finite " + k)
	# deadzone joystick = 0
	assert_eq(Locomotion.joystick_axis(0.0, 0.0), Vector2.ZERO, "joy 0")
	assert_eq(Locomotion.joystick_axis(1.0, 1.0).length() <= 1.0, true, "joy clamp")
	# damp mengejar target
	var x := 0.0
	for i in 60:
		x = Locomotion.damp(x, 1.0, 8.0, 0.016)
	assert_true(abs(x - 1.0) < 0.01, "damp konvergen")

func _test_combat() -> void:
	var c := CombatState.new()
	assert_true(c.try_attack(0.0), "serangan pertama ok")
	assert_true(not c.try_attack(0.1), "mid-swing ditolak")
	var watch := 0.0
	while c.is_attacking() and watch < 2.0:
		watch += 0.016
		c.update(0.016, watch, 0.0)
	assert_true(not c.is_attacking(), "serangan selesai sendiri")
	assert_aproks(c.combo, 0, 1e-9, "combo pertama = 0")
	assert_true(c.spend_stamina(0.25), "dash cost ok")
	assert_aproks(c.stamina, 0.75, 1e-6, "stamina berkurang pas")
	for i in 400:
		c.update(0.05, 0.0, 0.0)
	assert_aproks(c.stamina, 1.0, 1e-6, "stamina regen penuh")

func _test_rig_mapping() -> void:
	var pose := Locomotion.sample_pose({"phase": 0.0, "time": 0.0, "move": 1.0,
		"run": 0.0, "dash": 0.0, "airborne": false, "falling": false,
		"attack": -1.0, "combo": 0})
	var o := RigMapping.resolve(pose)
	assert_true(o.size() >= 23, "resolve -> 23 slot")
	for j in RigMapping.ALL_JOINTS:
		assert_true(o.has(j), "resolve punya " + j)
	# twist split menjumlahkan kembali ke LOWLEGL
	var ll: Vector3 = pose.get("LOWLEGL", Vector3.ZERO)
	var sum: Vector3 = o[RigMapping.J_LEFT_SHIN_TWIST_A] + o[RigMapping.J_LEFT_SHIN_TWIST_B]
	assert_true(sum.is_equal_approx(ll), "twist A+B == LOWLEGL")

func _test_scatter() -> void:
	var a := WorldScatter.build(1, 1, true, 10, 3)
	var b := WorldScatter.build(1, 1, true, 10, 3)
	assert_eq(a["props"].size(), b["props"].size(), "scatter deterministik jumlah")
	if a["props"].size() > 0:
		assert_eq(a["props"][0]["x"], b["props"][0]["x"], "scatter deterministik posisi")
	assert_true(a["props"].size() <= 20, "near <= 2x count_near")
	var orbs := WorldScatter.place_orbs()
	assert_eq(orbs.size(), 12, "12 orb episode 1")
	for o in orbs:
		assert_true(o.has("x") and o.has("y") and o.has("z") and o.has("base_y"), "orb punya posisi")
	var o0: Dictionary = orbs[0]
	assert_aproks(o0["base_y"], o0["y"], 0.25, "orb[0] base_y ~= y")
	# near=false -> tidak ada collider
	var far := WorldScatter.build(2, 2, false, 10, 3)
	assert_eq(far["colliders"].size(), 0, "chunk jauh tak punya collider")

func _test_settings() -> void:
	var s := QualityPresets.default_settings()
	s["sensitivity"] = 99.0
	s["camera_distance"] = -5.0
	s["fps"] = 999
	var n := GameSettings.normalize(s)
	assert_true(n["sensitivity"] <= 2.0, "sensitivitas dijepit")
	assert_true(n["camera_distance"] >= 3.0, "jarak kamera dijepit")
	assert_true(n["fps"] in QualityPresets.FPS_CHOICES, "fps dari pilihan")
	# apply preset semua id lalu detect
	for id in QualityPresets.PRESET_IDS:
		var p := QualityPresets.apply_preset(QualityPresets.default_settings(), id)
		assert_eq(p["quality"], id, "preset %s dipasang" % id)
		assert_eq(QualityPresets.detect_preset(p["gfx"]), id, "detect %s" % id)

func _test_gfx() -> void:
	var s := QualityPresets.default_settings()
	var r := GfxResolver.resolve(s, true)
	assert_true(r["fog_far"] > r["fog_near"], "fog far > near")
	assert_true(r["props_near"] >= r["props_far"], "props near >= far")
	var ar := GfxResolver.AdaptiveResolution.new(0.55, 1.0, 1.0)
	var scale := 1.0
	for i in 100:
		scale = ar.update(60.0, 16.6)
	assert_true(scale < 1.0, "adaptive turun saat frame berat")

func _test_motor_misc() -> void:
	assert_aproks(CharacterMotor.damp_angle(180.0, -180.0, 1.0, 0.5), 180.0, 1e-4,
		"damp_angle merangkum sudut ekstrem")
