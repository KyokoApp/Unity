class_name CharacterAnimDriver
extends Node

## ============================================================
## CHARACTER ANIM DRIVER — menyetir klip animasi GLB (idle /
## berjalan / berlari / dash / attack dst) dari keadaan motor.
##
## Dipakai BERSAMA model GLB nyata (bukan mannequin): rig
## mengaktifkan node ini setelah bind() bila menemukan >=1 klip
## yang termapping; kalau tidak, jalur prosedural lama berkuasa
## (game tidak pernah kehilangan gerak karakter).
##
## Pola putar: SATU AnimationPlayer milik sendiri (anak model),
## crossfade manual lewat play(nama, blend, speed) — sederhana,
## tegas, dan bisa dibuktikan headless:
##   - lokomosi: idle/walk/run dipilih dari speed & grounded,
##     speed klip diskalakan ke laju tanah (anti selip kaki)
##   - serat/dash/mendarat = one-shot yang MENGUNCI state sebentar
##   - jatuh di udara = klip fall bila ada
## ============================================================

@export var walk_speed := 6.5
@export var run_speed := 13.5
## Crossfade antar klip lokomosi (detik).
@export var fade_loco := 0.22
## Crossfade masuk/keluar one-shot.
@export var fade_oneshot := 0.09

var player: AnimationPlayer
var active := false
var mapping: Dictionary = {}          # role -> nama clip (setelah fallback)
var current_role := ""
var last_report := ""

var _lock := 0.0
var _oneshot_role := ""

## Mode LIVE retarget: paket animasi bermain nativ di skeleton
## sendiri (instans tersembunyi hidup di world), delta dunia
## disalin tiap frame ke skeleton pengguna (lihat AnimMap).
var _live := false
var _live_prep: Dictionary = {}

func _process(_dt: float) -> void:
	if _live:
		AnimMap.live_apply(_live_prep)

## Dipanggil CharacterRig setelah model terpasang.
## libs: Array berisi {"lib": AnimationLibrary, "mode": "", "...", ...};
## entri mode "humanoid" membawa payload live (live_src/live_skel/
## map/from_ctx/to_ctx/to_skel).
## skel_prefix: path relatif model_root -> node Skeleton3D.
## Mengembalikan jumlah peran yang berhasil dipeta.
func setup(model_root: Node3D, libs: Array, skel_prefix: String) -> int:
	active = false
	_live = false
	_live_prep = {}
	mapping.clear()
	player = null
	last_report = ""

	## ---- jalur LIVE (humanoid beda-nama) -------------------------
	for s in libs:
		if s.get("mode", "") != "humanoid":
			continue
		var src = s
		var p := AnimMap.find_player(src["live_src"])
		if p == null:
			continue
		var prep := AnimMap.prepare_live(src["live_skel"], src["to_skel"],
			src["from_ctx"], src["to_ctx"], src["map"])
		if prep.get("count", 0) < 6:
			continue
		player = p
		_live_prep = prep
		_live = true
		break

	if _live:
		## nama klip persis seperti yang dimiliki library paket —
		## play() native Godot, crossfade native, TIDAK ada penyalinan.
		var nama_semua: Array = []
		for lib_name in player.get_animation_library_list():
			nama_semua.append_array(player.get_animation_library(lib_name).get_animation_list())
		var m := AnimMap.resolve(nama_semua)
		m = AnimMap.fill_fallbacks(m)
		for role in AnimMap.ROLE_ORDER:
			var nm: String = m.get(role, "")
			if nm != "":
				mapping[role] = nm
		var punya_loko: bool = mapping.get("idle", "") != ""
		var punya_serang: bool = mapping.get("attack0", "") != ""
		active = punya_loko or punya_serang
		if active:
			current_role = ""
			_mainkan_peran(_peran_lokomosi(0.0, true, false, false), 0.0, true)
		last_report = "%s | live=%d map=%d" % [AnimMap.report(mapping),
			1 if _live else 0, _live_prep.get("count", 0)]
		return mapping.size()

	## ---- jalur klasik (skeleton sama / aset virtual) -------------

	# 1) kumpulkan semua clip dari semua library (bare name -> sumber)
	var semua: Array = []                # {"name": String, "src": int}
	for i in libs.size():
		var lib: AnimationLibrary = libs[i]["lib"]
		for nm in lib.get_animation_list():
			semua.append({"name": String(nm), "src": i})
	if semua.is_empty():
		last_report = "anim: tidak ada klip sama sekali"
		return 0

	# 2) peta peran -> klip (nama dari library sumber)
	var nama_semua := []
	for e in semua:
		nama_semua.append(e["name"])
	var m := AnimMap.resolve(nama_semua)
	m = AnimMap.fill_fallbacks(m)

	# 3) pasang AnimationPlayer sendiri + salin klip terpilih
	#    (duplikat: retarget/strip/loop tidak mencemarki sumber)
	var p := AnimationPlayer.new()
	p.name = "CharAnimPlayer"
	model_root.add_child(p)
	p.root_node = NodePath("..")
	var lib_out := AnimationLibrary.new()
	var terpeta := 0
	var dipakai := {}                    # nama keluar -> true (hindari tabrakan)
	for role in AnimMap.ROLE_ORDER:
		var nm: String = m.get(role, "")
		if nm == "":
			continue
		var src := -1
		for e in semua:
			if e["name"] == nm:
				src = e["src"]
				break
		if src < 0:
			continue
		var keluar := nm
		if dipakai.has(keluar):
			keluar = "%s#%s" % [nm, role]
		var mentah: Animation = (libs[src]["lib"] as AnimationLibrary).get_animation(nm)
		var anim: Animation = mentah.duplicate()
		var sumber: Dictionary = libs[src]
		if sumber.get("mode", "") == "prefix":
			anim = AnimMap.retarget_clip(anim, skel_prefix)
		if role in AnimMap.LOCO_ROLES:
			anim = AnimMap.strip_xz(anim)
		anim = AnimMap.apply_loop(anim, role)
		if lib_out.has_animation(keluar):
			continue
		lib_out.add_animation(keluar, anim)
		mapping[role] = keluar
		dipakai[keluar] = true
		terpeta += 1
	if mapping.is_empty():
		model_root.remove_child(p)
		p.queue_free()
		last_report = "anim: %d klip ada tapi tak ada yang cocok (lihat daftar)" % semua.size()
		return 0
	p.add_animation_library("", lib_out)
	player = p

	# 4) aktif hanya kalau ada lokomosi ATAU serangan
	var punya_loko: bool = mapping.get("idle", "") != ""
	var punya_serang: bool = mapping.get("attack0", "") != ""
	active = punya_loko or punya_serang
	if active:
		current_role = ""
		_mainkan_peran(_peran_lokomosi(0.0, true, false, false), 0.0, true)

	var daftar := []
	for i in mini(semua.size(), 12):
		daftar.append(semua[i]["name"])
	last_report = "%s | klip (%d): %s%s" % [AnimMap.report(mapping),
		semua.size(), ", ".join(daftar),
		" ..." if semua.size() > 12 else ""]
	return mapping.size()

## ---- input dari motor (satu peran satu frame) --------------------
func update_state(st: Dictionary, dt: float) -> void:
	if not active or player == null:
		return
	_lock = maxf(0.0, _lock - dt)
	var speed: float = st.get("speed", 0.0)
	var grounded: bool = st.get("grounded", true)
	var falling: bool = st.get("falling", false)
	var dashing: bool = st.get("dashing", false)
	var move: float = st.get("move", 0.0)

	if _lock > 0.0:
		return   # one-shot sedang berkuasa

	var peran := _peran_lokomosi(speed, grounded, falling, dashing, move)
	if peran != current_role:
		_mainkan_peran(peran, speed, false)

	# Skala irama klip ke laju tanah (anti selip kaki).
	if current_role == "walk" or current_role == "run":
		var desain := walk_speed if current_role == "walk" else run_speed
		player.speed_scale = clampf(speed / maxf(0.001, desain), 0.55, 2.4)
	else:
		player.speed_scale = 1.0

func _peran_lokomosi(speed: float, grounded: bool, falling: bool,
		dashing: bool, move: float = 0.0) -> String:
	if not grounded:
		if mapping.get("fall", "") != "" or mapping.get("jump", "") != "":
			return "fall" if falling else "jump"
		return current_role if current_role != "" else "idle"
	if dashing and mapping.get("dash", "") != "":
		return "dash"
	if move > 0.10:
		if speed > walk_speed * 1.08 and mapping.get("run", "") != "":
			return "run"
		if mapping.get("walk", "") != "":
			return "walk"
		return "run"
	return "idle"

func _mainkan_peran(peran: String, speed: float, paksa: bool) -> void:
	var nama: String = mapping.get(peran, "")
	if nama == "":
		return
	if not paksa and peran == current_role:
		return
	var custom_speed := 1.0
	if peran == "walk":
		custom_speed = clampf(speed / maxf(0.001, walk_speed), 0.55, 2.4)
	elif peran == "run":
		custom_speed = clampf(speed / maxf(0.001, run_speed), 0.55, 2.4)
	player.play(nama, fade_loco, custom_speed)
	current_role = peran

## ---- one-shot -----------------------------------------------------
func attack(combo: int) -> void:
	if not active:
		return
	var peran := "attack%d" % clampi(combo, 0, 2)
	var nama: String = mapping.get(peran, "")
	if nama == "":
		nama = mapping.get("attack0", "")
	if nama == "":
		return
	_mainkan_oneshot(peran, nama, 0.55)

func dash() -> void:
	_oneshot_sederhana("dash", 0.30)

func jump() -> void:
	_oneshot_sederhana("jump", 0.30)

func land(fall_speed: float = 0.0) -> void:
	if fall_speed < -7.0:
		_oneshot_sederhana("land", 0.35)

func skill() -> void:
	_oneshot_sederhana("skill", 0.6)

func burst() -> void:
	_oneshot_sederhana("burst", 0.9)

func _oneshot_sederhana(peran: String, dur: float) -> void:
	if not active:
		return
	var nama: String = mapping.get(peran, "")
	if nama == "":
		return
	_mainkan_oneshot(peran, nama, dur)

func _mainkan_oneshot(peran: String, nama: String, durasi_target: float) -> void:
	var anim: Animation = player.get_animation(nama)
	var panjang := anim.length if anim != null and anim.length > 0.05 else 0.55
	var sp := clampf(panjang / maxf(0.05, durasi_target), 0.6, 3.0)
	player.play(nama, fade_oneshot, sp)
	player.speed_scale = 1.0
	current_role = peran
	_oneshot_role = peran
	_lock = minf(panjang / sp, maxf(0.22, durasi_target * 1.2))

## Baris status kecil untuk strip debug / PerfHud.
func debug_line() -> String:
	if not active:
		return "anim:prosedural"
	var kunci := current_role
	if _lock > 0.0:
		kunci = "%s(lock %.1f)" % [_oneshot_role, _lock]
	return "anim:%s [%s]" % [kunci, mapping.get(current_role, "-")]
