extends SceneTree
## Uji asap SERANGAN headless (tanpa GPU) — penjaga insiden Ronde-38, terus
## dipertahankan lewat pivot ronde-45 (mage -> tank) dan ronde-46 (tank ->
## kembali ke penyihir anime).
##
## Kronologi insiden asli: fire_bolt.gd memakai `var distance := shake_target…`
## dengan shake_target bertipe Node -> analyzer Godot 4.5 melempar parse error
## keras -> fire_bolt.gd gagal compile -> player.gd (preload-nya) ikut gagal ->
## pack character_player TERBIT dengan pemain mati: tombol serang ditekan di
## perangkat, TIDAK ADA tembakan. Godot --export-pack exit 0 walau ada SCRIPT
## ERROR, jadi jalur export saja tidak cukup — probe inilah yang gagal keras
## sebelum konten sempat diterbitkan.
##
## RONDE-46: pivot balik dari TANK ke penyihir anime prosedural. Semantik
## serangan tap tetap sederhana: TAP tombol serang = SATU peluru sihir kecil
## (arcane_bolt.gd, sebelumnya bernama tank_shell.gd di ronde-45), lalu
## reload singkat (FIRE_COOLDOWN di player.gd) sebelum bisa menembak lagi.
## Mantra andalan yang lebih megah (bag. B ronde-46) belum ada di probe ini —
## akan ditambah probe terpisah jika mantra itu jadi node/kelas sendiri.
##
## Jalankan (CI & lokal):
##   godot --headless --path project --script dev_probe/fire_attack_check.gd
## Exit 0 = LULUS; exit != 0 = build konten WAJIB berhenti.
##
## Fase 1 : semua .gd di packs/ + semua scene inti WAJIB termuat & valid.
## Fase 2 : TAP cepat via set_attack_held → satu arcane_bolt.gd HARUS muncul.
## Fase 3 : HUD ditanam, handler tombol serang (_on_attack) TAP cepat →
##          arcane_bolt.gd HARUS muncul (jalur persis tombol tembak di layar).
##
## Catatan urutan engine (diverifikasi dari source Godot 4.5.2):
## _initialize() dipanggil SEBELUM root masuk tree — node yang ditambahkan di
## sini menerima ENTER_TREE/READY saat initialize() selesai, dan await
## process_frame hanya dilanjutkan pada iterasi pertama, jadi saat badan uji
## berjalan, _ready pemain/HUD dijamin sudah tereksekusi.

const PLAYER_SCENE := "res://packs/character_player/player.tscn"
const HUD_SCENE := "res://packs/ui/hud.tscn"
const SCENES := [
	"res://packs/core_scripts/game_root.tscn",
	"res://packs/world_terrain/world.tscn",
	PLAYER_SCENE,
	HUD_SCENE,
	"res://packs/ui/loading_screen.tscn",
	"res://packs/ui/pause_menu.tscn",
]
# WAJIB lebih besar dari DUA hal sekaligus, bukan cuma reload:
#   1) FIRE_COOLDOWN (0.3) di player.gd — supaya fase berikutnya tak
#      tertelan reload.
#   2) siklus hidup PENUH arcane_bolt.gd di dunia uji TANPA lantai (tak ada
#      collider sama sekali di "TestWorld") — peluru jatuh bebas sampai
#      y<=0 (~0.8 dtk dgn gravitasi & BOLT_LIFT saat ini) lalu meledak, dan
#      BARU benar-benar queue_free() 1 dtk KEMUDIAN (lihat arcane_bolt.gd
#      _explode()). Insiden ronde-45: nilai lama (1.3) lebih pendek dari
#      siklus itu (~1.7-1.9 dtk) -> peluru fase sebelumnya kadang ke-free()
#      TEPAT saat hitungan "after" fase berikutnya diambil, menyamarkan
#      peluru baru yang sebenarnya berhasil ditembak (before==after palsu,
#      "tombol serang HUD tidak menghasilkan tembakan"). Beri margin besar
#      supaya sisa peluru fase sebelumnya SUDAH BENAR-BENAR lenyap sebelum
#      hitungan "before" fase berikutnya diambil.
const COOLDOWN_WAIT_SEC := 3.0
# TAP_HOLD_SEC/RELEASE_SETTLE_SEC dipakai (bukan `await process_frame` tunggal)
# supaya waktu-nyata yang berlalu dijamin cukup untuk beberapa siklus
# _process() node pemain benar-benar berjalan sebelum/di antara aksi tekan-
# lepas. Satu `await process_frame` saja pernah terbukti rentan race 1-frame
# (insiden ronde-43).
const TAP_HOLD_SEC := 0.05
const RELEASE_SETTLE_SEC := 0.15

var _exit_code := 0

func _initialize() -> void:
	print("[fire-check] mulai (godot ", Engine.get_version_info().get("string", "?"), ")")
	_run()

func _fail(msg: String) -> void:
	_exit_code = 1
	push_error("[fire-check] GAGAL: " + msg)
	print("[fire-check] GAGAL: ", msg)

func _finish() -> void:
	if _exit_code == 0:
		print("[fire-check] LULUS ✔ (serangan sihir bekerja)")
	else:
		print("[fire-check] TIDAK LULUS ✘ — jangan terbitkan konten!")
	quit(_exit_code)

func _run() -> void:
	# ---------- Fase 1a: semua skrip pack wajib compile ----------
	var bad: Array = []
	for path in _list_gd("res://packs"):
		var s: GDScript = load(path)
		if s == null or not s.can_instantiate():
			bad.append(path)
	if not bad.is_empty():
		_fail("skrip pack tidak termuat/invalid (parse error?):\n  " + "\n  ".join(bad))
	else:
		print("[fire-check] fase 1a ✔ semua skrip pack ter-compile")

	# ---------- Fase 1b: semua scene inti wajib termuat ----------
	for path in SCENES:
		if load(path) == null:
			_fail("scene tidak termuat: " + path)
	if _exit_code != 0:
		_finish()
		return
	print("[fire-check] fase 1b ✔ semua scene inti termuat")

	# ---------- Fase 1e: dunia nyata (rumput/kabut/malam, bag. C) ----------
	# Ronde-46 bag. C: material tanah diganti total (rumput lebat), fog
	# dipindah ke FOG_MODE_DEPTH (properti baru bagi codebase ini — risiko
	# nyata nama enum/properti salah ketik), dan waktu dikunci malam permanen.
	# Cek ini menjalankan World.generate_async() SUNGGUHAN (headless, tanpa
	# GPU) supaya kesalahan run-time di jalur itu (bukan cuma parse error)
	# tertangkap SEBELUM konten terbit, bukan baru ketahuan di perangkat.
	await _check_world_ground_fog()
	if _exit_code != 0:
		_finish()
		return

	# ---------- Siapkan dunia uji ----------
	var world := Node3D.new()
	world.name = "TestWorld"
	root.add_child(world)
	var ps: PackedScene = load(PLAYER_SCENE)
	var player := ps.instantiate()
	world.add_child(player)
	var hs: PackedScene = load(HUD_SCENE)
	var hud := hs.instantiate()
	root.add_child(hud)
	if player.get_script() == null:
		_fail("skrip pemain tidak terpasang (player.gd gagal compile?)")
		_finish()
		return
	if hud.get_script() == null:
		_fail("skrip HUD tidak terpasang (hud.gd gagal compile?)")
		_finish()
		return
	player.call("set_world", world)
	player.call("set_settings", null)
	hud.call("bind_player", player)

	# ---------- Fase 2: TAP cepat → arcane_bolt.gd ----------
	await process_frame          # tree hidup; _ready pemain+HUD pasti sudah jalan
	if not bool(player.get("is_ready")):
		_fail("pemain tidak siap setelah 1 frame (is_ready=false)")
		_finish()
		return
	if not player.has_method("set_attack_held"):
		_fail("player.set_attack_held tidak ada (skrip pemain versi lama?)")
		_finish()
		return

	# ---------- Fase 1c: mannequin (ronde-46 bag. A4) wajib beranimasi ----------
	# Insiden yg mendasari cek ini: nama klip di const ANIM_* player.gd sempat
	# tak cocok dgn nama HASIL IMPORT Godot (importer glTF memotong akhiran
	# "_Loop" scr diam-diam) -> AnimationPlayer.play() gagal diam-diam ->
	# karakter beku total di layar walau semua fase lain LULUS. Cek ini
	# memverifikasi lewat konstanta skrip yg SAMA dipakai player.gd sendiri
	# (bukan string literal ganda di sini) supaya tak ikut basi jika suatu
	# saat nama klip berubah lagi.
	await _check_mannequin_animates(player)
	if _exit_code != 0:
		_finish()
		return

	# ---------- Fase 1d: dash "sprint burst" + jejak bayangan ----------
	# Ronde-46 bag. A4 lanjutan #2: dash diganti dari animasi Roll jadi
	# klip lari (ANIM_SPRINT) dipercepat + duplikasi MeshInstance3D "hantu"
	# yg merujuk Skeleton3D asli via NodePath relatif — pola API yg agak
	# eksotis, cek ini memastikan itu benar2 jalan tanpa error di headless.
	await _check_dash_effects(player, world)
	if _exit_code != 0:
		_finish()
		return

	# ---------- Fase 1f: ganti skin (mannequin <-> Kanna VRM) ----------
	await _check_skin_switch(player)
	if _exit_code != 0:
		_finish()
		return

	# ---------- Fase 1g: skill gerak-cepat ×5 (ronde ini) ----------
	await _check_speed_skill(player, world)
	if _exit_code != 0:
		_finish()
		return

	print("[fire-check] fase 2: TAP cepat…")
	var before_tap := _count_by_suffix(world, "arcane_bolt.gd")
	player.call("set_attack_held", true)
	await create_timer(TAP_HOLD_SEC).timeout
	player.call("set_attack_held", false)
	await create_timer(RELEASE_SETTLE_SEC).timeout
	var after_tap := _count_by_suffix(world, "arcane_bolt.gd")
	if after_tap > before_tap:
		print("[fire-check] fase 2 ✔ tap → ", after_tap - before_tap, " arcane_bolt.gd")
	else:
		_fail("fase 2: tap cepat tidak menghasilkan arcane_bolt.gd — tombol serang mati")

	# ---------- Fase 3: jalur tombol HUD (TAP cepat) ----------
	if not hud.has_method("_on_attack"):
		_fail("handler tombol serang HUD (_on_attack) tidak ada")
		_finish()
		return
	# jeda melewati sisa reload + siklus hidup peluru fase 2 supaya penekanan
	# HUD diuji jujur, bukan tertelan cooldown/peluru lama yang masih hidup
	await create_timer(COOLDOWN_WAIT_SEC).timeout
	print("[fire-check] fase 3: tekan tombol serang via HUD (tap cepat)…")
	var before := _count_by_suffix(world, "arcane_bolt.gd")
	hud.call("_on_attack", true)
	await create_timer(TAP_HOLD_SEC).timeout
	hud.call("_on_attack", false)
	await create_timer(RELEASE_SETTLE_SEC).timeout
	var after := _count_by_suffix(world, "arcane_bolt.gd")
	if after > before:
		print("[fire-check] fase 3 ✔ tombol HUD → ", after - before, " peluru sihir baru")
	else:
		_fail("fase 3: tombol serang HUD tidak menghasilkan tembakan")
	_finish()

## Verifikasi karakter (mannequin Quaternius, ronde-46 bag. A4) benar-benar
## beranimasi: AnimationPlayer ditemukan, SEMUA klip lokomosi yg dipakai
## player.gd ada persis dgn nama itu di AnimationPlayer, lalu simulasi dorong
## analog maju harus membuat klip berganti & benar-benar berjalan
## (is_playing=true). Baca nama klip dari konstanta skrip player.gd sendiri
## (get_script_constant_map) — bukan string literal terpisah di sini — supaya
## cek ini otomatis ikut benar kalau nama klip berubah lagi di masa depan.
func _check_mannequin_animates(player: Node) -> void:
	var consts: Dictionary = (player.get_script() as GDScript).get_script_constant_map()
	var clip_names := ["ANIM_IDLE", "ANIM_WALK", "ANIM_JOG", "ANIM_SPRINT"]
	var anim: AnimationPlayer = player.get("_anim")
	if anim == null:
		_fail("mannequin: AnimationPlayer tidak ditemukan (_anim null) — model beku total")
		return
	var missing: Array = []
	for key in clip_names:
		if not consts.has(key):
			missing.append(key + " (konstanta tak ada di player.gd)")
			continue
		var clip_name: String = consts[key]
		if not anim.has_animation(clip_name):
			missing.append("%s=\"%s\"" % [key, clip_name])
	if not missing.is_empty():
		_fail("mannequin: klip animasi tidak ada di AnimationPlayer hasil import: " + ", ".join(missing))
		return
	if not anim.is_playing():
		_fail("mannequin: AnimationPlayer tidak memutar apa pun saat idle (is_playing=false)")
		return
	# simulasikan analog didorong penuh ke depan sesaat, klip HARUS berganti & berjalan
	var before_clip := anim.current_animation
	player.call("set_joy", Vector2(0, 1))
	await create_timer(0.8).timeout
	player.call("set_joy", Vector2.ZERO)
	var after_clip := anim.current_animation
	var after_playing := anim.is_playing()
	if not after_playing:
		_fail("mannequin: AnimationPlayer berhenti (is_playing=false) setelah simulasi gerak maju")
		return
	if after_clip == before_clip and before_clip == String(consts.get("ANIM_IDLE", "")):
		_fail("mannequin: klip animasi tidak berganti dari Idle walau karakter disimulasikan bergerak penuh")
		return
	print("[fire-check] fase 1c ✔ mannequin beranimasi (idle→", after_clip, ", is_playing=", after_playing, ")")

## Verifikasi dash "sprint burst": animasi berpindah ke ANIM_SPRINT dgn
## speed_scale dipercepat, DAN minimal satu node jejak bayangan
## ("DashAfterimage") benar-benar muncul di dunia (bukti duplikasi
## MeshInstance3D + penautan Skeleton3D via NodePath relatif tidak error).
## Fase 1f: ganti skin (Kanna VRM, permintaan user "pake 2 karakter... ada
## icon ganti karakter") — memanggil cycle_skin() SUNGGUHAN (headless) &
## pastikan skeleton/model baru benar2 terbentuk (bukan cuma "tak crash"),
## lalu ganti balik ke mannequin & pastikan itu jg pulih normal. WAJIB ada
## krn rig Kanna (custom Rigify 209 tulang) SANGAT beda dr mannequin (65
## tulang) — risiko nyata gagal total (skeleton null/bone count aneh) kalau
## KANNA_BONE_MAP salah, jauh lebih murah ketahuan di sini drpd di HP user.
## CATATAN: cek ini memverifikasi STRUKTUR (skeleton/mesh/animasi terbentuk),
## BUKAN kebenaran visual pose retarget (bengkok/tidaknya sendi) — itu tetap
## perlu dicek langsung di perangkat, di luar jangkauan probe headless ini.
func _check_skin_switch(player: Node) -> void:
	if not player.has_method("cycle_skin"):
		_fail("player.cycle_skin tidak ada (fitur ganti skin belum terpasang?)")
		return
	player.call("cycle_skin")
	await create_timer(1.0).timeout
	if String(player.get("_skin_id")) != "kanna":
		_fail("ganti skin ke kanna gagal (_skin_id masih \"%s\")" % String(player.get("_skin_id")))
		return
	# perbaikan ronde ini ("karakter vrm malah tidur ditanah"): Kanna BUKAN
	# lagi menukar skeleton mannequin (nama tulang di-rename) — mannequin
	# tetap penuh sbg "puppeteer" tersembunyi (AnimationPlayer tetap menganimasi
	# _skeleton/_anim aslinya), node _kanna terpisah dgn skeleton asli VRM
	# yg pose-nya dicopy per-frame oleh driver _retarget. Verifikasi KONTRAK
	# BARU ini persis (bukan kontrak lama rename yg sudah dibuang).
	var kskel: Skeleton3D = player.get("_kanna_skeleton")
	if kskel == null or not is_instance_valid(kskel):
		_fail("skin kanna: _kanna_skeleton null setelah cycle_skin (puppeteer/mannequin _skeleton tidak lagi ditukar!)")
		return
	if player.get("_retarget") == null:
		_fail("skin kanna: node _retarget (SkinRetarget) tidak ada — pose kanna tak lagi tersambung ke mannequin")
		return
	if kskel.get_bone_count() < 200:
		_fail("skin kanna: skeleton jumlah tulang mencurigakan (%d, seharusnya >200, rig Kanna asli)" % kskel.get_bone_count())
		return
	# nama tulang DITAHAN ASLI (tak lagi di-rename): pasangan dst utk
	# SkinRetarget adalah nama VRM Rigify ("root"/"DEF-Head"/...).
	for essential in ["root", "DEF-Spine", "DEF-Head", "DEF-Left leg", "DEF-Right leg", "DEF-Left wrist", "DEF-Right wrist"]:
		if kskel.find_bone(essential) < 0:
			_fail("skin kanna: tulang asli \"%s\" tak ditemukan (KANNA_RETARGET_PAIRS salah?)" % essential)
			return
	var mdl: Node = player.get("_model")
	if mdl == null or not is_instance_valid(mdl):
		_fail("skin kanna: _model null setelah cycle_skin")
		return
	var mannequin_mesh_hidden := false
	for mi in mdl.find_children("*", "MeshInstance3D", true, false):
		if not (mi as MeshInstance3D).visible:
			mannequin_mesh_hidden = true
			break
	if not mannequin_mesh_hidden:
		_fail("skin kanna: mesh mannequin seharusnya DISEMBUNYIKAN (puppeteer tak terlihat), malah masih tampak")
		return
	var kanna_node: Node = player.get("_kanna")
	if kanna_node == null or not is_instance_valid(kanna_node):
		_fail("skin kanna: node _kanna hilang")
		return
	var kanna_meshes := kanna_node.find_children("*", "MeshInstance3D", true, false)
	if kanna_meshes.is_empty():
		_fail("skin kanna: tak ada MeshInstance3D di node _kanna")
		return
	# math post retarget (verifikasi strike kasus "tidur ditanah"): pose
	# pelvis Kanna setelah driver jalan HARUS berdiri (bukan di tanah /
	# bukan tertelungkup) — jalankan 0.5 detik spy SkinRetarget & klip
	# idle sudah menyetir pose, baru ukur.
	await create_timer(0.5).timeout
	var kp: Transform3D = kskel.get_bone_global_pose(kskel.find_bone("root"))
	var kh: Transform3D = kskel.get_bone_global_pose(kskel.find_bone("DEF-Head"))
	if kp.origin.y < 0.45 or kh.origin.y < 0.85:
		_fail("skin kanna: pose pasca-retarget TAKIK DI TANAH/TENGGELAM (pelvis y=%.2f, head y=%.2f) — kemungkinan besar math SkinRetarget salah (kasus 'tidur ditanah' yg diperbaiki ronde ini berulang)" % [kp.origin.y, kh.origin.y])
		return
	if kh.origin.y <= kp.origin.y + 0.25:
		_fail("skin kanna: kepala tak berada jelas DI ATAS pelvis (head=%.2f pelvis=%.2f) — pose bukan berdiri tegak" % [kh.origin.y, kp.origin.y])
		return
	print("[fire-check] fase 1f ✔ ganti ke skin kanna OK (tulang=", kskel.get_bone_count(), ", mesh=", kanna_meshes.size(), ", pelvis y=", snappedf(kp.origin.y, 0.01), ")")

	# ganti balik ke mannequin — pastikan jalur baliknya jg tak rusak
	player.call("cycle_skin")
	await create_timer(1.0).timeout
	if String(player.get("_skin_id")) != "mannequin":
		_fail("ganti skin balik ke mannequin gagal (_skin_id masih \"%s\")" % String(player.get("_skin_id")))
		return
	var anim: AnimationPlayer = player.get("_anim")
	if anim == null or not anim.has_animation("Idle"):
		_fail("skin mannequin (setelah ganti balik): AnimationPlayer/Idle hilang")
		return
	var mannequin_mesh_visible := false
	var mdl2: Node = player.get("_model")
	if mdl2 != null:
		for mi in mdl2.find_children("*", "MeshInstance3D", true, false):
			if (mi as MeshInstance3D).visible:
				mannequin_mesh_visible = true
				break
	if not mannequin_mesh_visible:
		_fail("skin mannequin (setelah ganti balik): mesh seharusnya KEMBALI TAMPAK, malah masih tersembunyi")
		return
	print("[fire-check] fase 1f ✔ ganti balik ke mannequin OK")

## Fase 1g: skill gerak-cepat ×5 (permintaan user ronde ini: "tambahkan
## skill movement speed kalo kita pencet nambah 5 kali kecepatan speed lari
## dengan efek trail yang smooth"). Dipanggil via press_speed_skill untuk
## memverifikasi: (a) kecepatan fisiknya beneran naik jadi ~5× dari baseline,
## (b) efek "bush" FOV-kick/arm-pull camera ikut terpanggang (var
## _cam_boost_* berubah), (c) trail _speed_skill semula memunculkan node
## SpeedTrail.
func _check_speed_skill(player: Node, world: Node) -> void:
	if not player.has_method("press_speed_skill"):
		_fail("player.press_speed_skill tidak ada (skill kecepatan belum terpasang?)")
		return
	var consts: Dictionary = (player.get_script() as GDScript).get_script_constant_map()
	var max_speed: float = consts.get("MAX_SPEED", 0.0)
	var spd_mult: float = consts.get("SPEED_SKILL_MULT", 0.0)
	if max_speed <= 1.0 or spd_mult < 2.0:
		_fail("skill: konstanta kecepatan aneh (MAX_SPEED=%s, SPEED_SKILL_MULT=%s)" % [max_speed, spd_mult])
		return
	# ukur kecepatan jalan tanpa skill utk baseline
	player.call("press_speed_skill", false)
	player.call("set_joy", Vector2(0, 1))
	await create_timer(0.6).timeout
	var v_off: Vector3 = player.get("velocity")
	var spd_off := Vector2(v_off.x, v_off.z).length()
	# nyalakan skill & ukur lagi (toggle modern 202x — down-check saja,
	# skill_toogle sendiri tetap sama spt layar user: ada tombol tap-TAP di
	# HUD per iterator).
	player.call("press_speed_skill", true)
	await create_timer(0.9).timeout
	var spawn_fx_found := false
	for c in world.get_children():
		if String(c.name).begins_with("SpeedBoostRing") or String(c.name).begins_with("SpeedTrail"):
			spawn_fx_found = true
	var v_on: Vector3 = player.get("velocity")
	var spd_on := Vector2(v_on.x, v_on.z).length()
	player.call("set_joy", Vector2.ZERO)
	player.call("press_speed_skill", false)
	if spd_off <= 0.1 or spd_on <= 0.1:
		_fail("skill: kecepatan OFF/ON tidak masuk akal (off=%.2f on=%.2f)" % [spd_off, spd_on])
		return
	var ratio := spd_on / maxf(spd_off, 0.01)
	if ratio < 2.5 or ratio > 8.5:
		_fail("skill: rasio kecepatan ON/OFF=%.2f jauh dr ~5 (off=%.2f on=%.2f) — multiplier rusak di _move?" % [ratio, spd_off, spd_on])
		return
	if abs(spd_on - max_speed * spd_mult) > max_speed * spd_mult * 0.25:
		_fail("skill: kecepatan ON=%.2f tak mendekati MAX_SPEED*MULT=%.2f — akselerasi boostnya salah?" % [spd_on, max_speed * spd_mult])
		return
	if not spawn_fx_found:
		_fail("skill: tak ada SpeedBoostRing/SpeedTrail di dunia setelah skill diaktifkan (efek boost gagal spawn)")
		return
	print("[fire-check] fase 1g ✔ skill gerak-cepat ×%d (kecepatan %.2f->%.2f, rasio %.1f) + efek boost OK" % [int(spd_mult), spd_off, spd_on, ratio])

func _check_dash_effects(player: Node, world: Node) -> void:
	var consts: Dictionary = (player.get_script() as GDScript).get_script_constant_map()
	var sprint_name: String = consts.get("ANIM_SPRINT", "")
	var anim: AnimationPlayer = player.get("_anim")
	player.call("press_dash")
	await create_timer(0.12).timeout
	if anim != null:
		if anim.current_animation != sprint_name:
			_fail("dash: animasi saat dash bukan ANIM_SPRINT (dpt: \"%s\")" % anim.current_animation)
			return
		if anim.speed_scale <= 1.01:
			_fail("dash: speed_scale animasi tidak dipercepat saat dash (burst tak terasa)")
			return
	var ghost: Node = null
	for c in world.get_children():
		if String(c.name).begins_with("DashAfterimage"):
			ghost = c
			break
	if ghost == null:
		_fail("dash: tidak ada node DashAfterimage muncul saat dash (jejak bayangan gagal spawn)")
		return
	# HOTFIX "bayangan dash ikut gerak ... jadi bayangan nya gk gerak": ghost
	# wajib membawa Skeleton3D HANTU sendiri (bukan rujukan ke skeleton hidup)
	# dan pose-nya dibekukan — nilai pose tulang harus IDENTIK antar-frame.
	var gskel: Skeleton3D = null
	for c in ghost.get_children():
		if c is Skeleton3D:
			gskel = c
			break
	if gskel == null:
		_fail("dash: ghost afterimage tak punya Skeleton3D hantu ('GhostSkeleton') — ghost masih merujuk skeleton hidup, bayangan bakal ikut gerak lagi")
		return
	var probe_bone := mini(3, gskel.get_bone_count() - 1)
	var pose_a: Transform3D = gskel.get_bone_global_pose(probe_bone)
	# RONDE INI (permintaan user: "afterimage hanya satu bayangannya aja yg
	# tertinggal"): ghost-train interval di _move dihapus — 1 dash = 1 ghost
	# abu-abu pastel + asap bergoyang (kode sama dipakai 2 skin). Ini dicek
	# dengan menghitung DashAfterimage SAMA DENGAN 1 setelah tunggu 0.25s
	# (durasi dash 0.30s masih jalan — versi lama yg spawn tiap 0.05 detik
	# pasti sdh menumpuk >5 ghost, versi baru harus TETAP 1 persis).
	await create_timer(0.25).timeout
	var ghost_count := 0
	for c in world.get_children():
		if String(c.name).begins_with("DashAfterimage"):
			ghost_count += 1
	if ghost_count != 1:
		_fail("dash: harusnya SATU ghost per dash (dpt %d — kemungkinan train interval lama balik lagi, ATAU ghost beda-skin form-fail)" % ghost_count)
		return
	# lanjutan pemeriksaan "frozen": baca pose yg sama SETELAH 0.25s berlalu
	# (animasi pemain pasti sudah berganti-ganti) — harus tetap identik.
	if not is_instance_valid(gskel):
		_fail("dash: GhostSkeleton hilang terlalu dini (belum selesai fade)")
		return
	var pose_b: Transform3D = gskel.get_bone_global_pose(probe_bone)
	if not pose_a.is_equal_approx(pose_b):
		_fail("dash: pose ghost afterimage BERUBAH antar-frame (bayangan masih ikut animasi pemain — pembekuan pose gagal)")
		return
	print("[fire-check] fase 1d ✔ dash sprint-burst (speed_scale=", anim.speed_scale if anim else "?", ") + afterimage SATU-ghost asap DIBEKUKAN OK")
	# tunggu dash+cooldown reda supaya tidak mengganggu fase 2/3 setelahnya
	await create_timer(1.3).timeout

## Jalankan World.generate_async() sungguhan (headless) lalu pastikan: kabut
## "jauh saja" aktif dgn benar (FOG_MODE_DEPTH, begin < end, begin cukup jauh
## dari pemain), dunia terkunci SORE hangat (star_visibility=0, ronde ini),
## dan tumpuk rumput
## MultiMesh benar-benar terbentuk (instance_count > 0, material terpasang).
func _check_world_ground_fog() -> void:
	var ws: PackedScene = load("res://packs/world_terrain/world.tscn")
	var world = ws.instantiate()
	root.add_child(world)
	# PENTING: ini Fase PALING AWAL yg menyentuh pohon-adegan (belum ada
	# `await` sama sekali sebelumnya di _run()) — catatan header file ini
	# sendiri: node yg ditambah selagi _initialize() masih berjalan SINKRON
	# baru menerima ENTER_TREE setelah giliran pertama `await` beres. Tanpa
	# `await` di sini, world.generate_async() akan panggil get_tree() SAAT
	# world belum punya tree (data.tree null) -> crash "Parameter data.tree
	# is null" (insiden nyata: percobaan pertama fase 1e ini, keliru dikira
	# bug MultiMesh rumput padahal akar masalahnya di sini).
	await process_frame
	if not world.has_method("generate_async"):
		_fail("world: generate_async tidak ada (world.gd versi lama?)")
		return
	await world.generate_async(null)
	await process_frame

	var world_env: WorldEnvironment = world.get("world_env")
	if world_env == null or world_env.environment == null:
		_fail("world: world_env/Environment tidak terbentuk setelah generate_async")
		world.queue_free()
		return
	var env: Environment = world_env.environment
	if env.fog_mode != Environment.FOG_MODE_DEPTH:
		_fail("world: fog_mode bukan FOG_MODE_DEPTH — kabut jarak-jauh tidak akan aktif")
		world.queue_free()
		return
	if not (env.fog_depth_begin > 15.0 and env.fog_depth_begin < env.fog_depth_end):
		_fail("world: fog_depth_begin/end tidak masuk akal (begin=%s end=%s) — cek risiko kabut nempel dekat pemain" % [env.fog_depth_begin, env.fog_depth_end])
		world.queue_free()
		return
	var sky_mat: ShaderMaterial = world.get("sky_mat")
	# RONDE INI: kunci waktu dipindah dari MALAM permanen ke SORE permanen
	# (permintaan user) -> patokan dibalik: bintang HARUS mati (bukan nyala).
	# plus OSOlakan suasana sore hangat: cahaya matahari masih energik.
	if sky_mat == null or float(sky_mat.get_shader_parameter("star_visibility")) > 0.01:
		_fail("world: star_visibility bukan 0.0 — dunia seharusnya terkunci sore hangat (bintang mati)")
		world.queue_free()
		return
	var light_sun := world.get("sun") as DirectionalLight3D
	if light_sun == null or light_sun.light_energy < 0.30:
		_fail("world: energi matahari terlalu redup (%s) — dunia sore seharusnya masih terang terik hangat" % (("null" if light_sun == null else str(light_sun.light_energy))))
		world.queue_free()
		return
	var kids: Array = []
	for c in world.get_children():
		kids.append(String(c.name))
	# RONDE INI: rumput pindah dr 1 node "GrassBlades" tunggal (wrap around
	# player, dihapus krn laporan user "kok malah jadi ngikutin") ke sistem
	# CHUNK STREAMING (world.gd _build_grass_chunk) — tiap petak jadi node
	# MultiMeshInstance3D terpisah bernama "GrassChunk_X_Z". generate_async()
	# dipanggil TANPA pemain (world.player msh null) di cek ini, tapi
	# _build_grass() sengaja membangun petak ASAL (0,0) SEKARANG JUGA (lihat
	# komentarnya) — jadi minimal SATU chunk harus ada di sini walau tanpa
	# pemain sama sekali, sama spt jaminan versi lama.
	var grass: MultiMeshInstance3D = null
	for c in world.get_children():
		if c is MultiMeshInstance3D and String(c.name).begins_with("GrassChunk_"):
			grass = c
			break
	if grass == null:
		_fail("world: tak ada node GrassChunk_* ditemukan sbg anak World (petak asal gagal dibangun?). anak World skrg: [%s]" % ", ".join(kids))
		world.queue_free()
		return
	if grass.multimesh == null:
		_fail("world: %s.multimesh null" % grass.name)
		world.queue_free()
		return
	print("[fire-check] diag rumput: chunk=", grass.name, " instance_count=", grass.multimesh.instance_count,
		" mesh_surfaces=", (grass.multimesh.mesh.get_surface_count() if grass.multimesh.mesh else -1))
	if grass.multimesh.instance_count <= 0:
		_fail("world: MultiMesh rumput (%s) instance_count<=0 (dpt %d)" % [grass.name, grass.multimesh.instance_count])
		world.queue_free()
		return
	if grass.material_override == null:
		_fail("world: rumput tidak punya material (bakal tampil putih polos)")
		world.queue_free()
		return
	print("[fire-check] fase 1e ✔ tanah rumput + kabut jauh (begin=%.0f end=%.0f) + sore hangat OK (chunk %s, %d tuft rumput)" % [env.fog_depth_begin, env.fog_depth_end, grass.name, grass.multimesh.instance_count])
	world.queue_free()
	await process_frame

func _count_by_suffix(world: Node, suffix: String) -> int:
	var n := 0
	for c in world.get_children():
		var sp := c.get_script() as GDScript
		if sp != null and sp.resource_path.ends_with(suffix):
			n += 1
	return n

func _list_gd(base: String) -> Array[String]:
	var out: Array[String] = []
	var stack: Array[String] = [base]
	while not stack.is_empty():
		var d := DirAccess.open(stack.pop_back())
		if d == null:
			continue
		d.list_dir_begin()
		var fname := d.get_next()
		while fname != "":
			var p := d.get_current_dir() + "/" + fname
			if d.current_is_dir():
				if not fname.begins_with("."):
					stack.push_back(p)
			elif fname.ends_with(".gd"):
				out.append(p)
			fname = d.get_next()
		d.list_dir_end()
	return out
