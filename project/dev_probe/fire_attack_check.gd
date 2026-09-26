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
	var ghost_found := false
	for c in world.get_children():
		if String(c.name).begins_with("DashAfterimage"):
			ghost_found = true
			break
	if not ghost_found:
		_fail("dash: tidak ada node DashAfterimage muncul saat dash (jejak bayangan gagal spawn)")
		return
	print("[fire-check] fase 1d ✔ dash sprint-burst (speed_scale=", anim.speed_scale if anim else "?", ") + afterimage OK")
	# tunggu dash+cooldown reda supaya tidak mengganggu fase 2/3 setelahnya
	await create_timer(1.3).timeout

## Jalankan World.generate_async() sungguhan (headless) lalu pastikan: kabut
## "jauh saja" aktif dgn benar (FOG_MODE_DEPTH, begin < end, begin cukup jauh
## dari pemain), dunia terkunci malam (star_visibility=1), dan tumpuk rumput
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
	if sky_mat == null or float(sky_mat.get_shader_parameter("star_visibility")) < 0.99:
		_fail("world: star_visibility bukan 1.0 — dunia seharusnya terkunci malam berbintang")
		world.queue_free()
		return
	var kids: Array = []
	for c in world.get_children():
		kids.append(String(c.name))
	var grass := world.find_child("GrassBlades", true, false) as MultiMeshInstance3D
	if grass == null:
		_fail("world: node GrassBlades tidak ditemukan sbg anak World. anak World skrg: [%s]" % ", ".join(kids))
		world.queue_free()
		return
	if grass.multimesh == null:
		_fail("world: GrassBlades.multimesh null")
		world.queue_free()
		return
	print("[fire-check] diag rumput: instance_count=", grass.multimesh.instance_count,
		" mesh_surfaces=", (grass.multimesh.mesh.get_surface_count() if grass.multimesh.mesh else -1))
	if grass.multimesh.instance_count <= 0:
		_fail("world: MultiMesh rumput (GrassBlades) instance_count<=0 (dpt %d)" % grass.multimesh.instance_count)
		world.queue_free()
		return
	if grass.material_override == null:
		_fail("world: rumput tidak punya material (bakal tampil putih polos)")
		world.queue_free()
		return
	print("[fire-check] fase 1e ✔ tanah rumput + kabut jauh (begin=%.0f end=%.0f) + malam berbintang OK (%d tuft rumput)" % [env.fog_depth_begin, env.fog_depth_end, grass.multimesh.instance_count])
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
