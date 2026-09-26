extends SceneTree
## Uji asap SERANGAN headless (tanpa GPU) — penjaga insiden Ronde-38, terus
## dipertahankan lewat pivot ronde-45 (mage -> tank).
##
## Kronologi insiden asli: fire_bolt.gd memakai `var distance := shake_target…`
## dengan shake_target bertipe Node -> analyzer Godot 4.5 melempar parse error
## keras -> fire_bolt.gd gagal compile -> player.gd (preload-nya) ikut gagal ->
## pack character_player TERBIT dengan pemain mati: tombol serang ditekan di
## perangkat, TIDAK ADA tembakan. Godot --export-pack exit 0 walau ada SCRIPT
## ERROR, jadi jalur export saja tidak cukup — probe inilah yang gagal keras
## sebelum konten sempat diterbitkan.
##
## RONDE-45: pivot total dari mage (mana bolt + mantra Zoltraak tahan-lepas)
## ke TANK (meriam tap-tembak). Semantik serangan sekarang jauh lebih
## sederhana daripada ronde-43/44: TAP tombol serang = SATU tembakan meriam
## (tank_shell.gd), lalu reload (FIRE_COOLDOWN di player.gd) sebelum bisa
## menembak lagi. TIDAK ADA lagi mode tahan-untuk-mengisi (mantra Zoltraak
## dihapus total bersama seluruh pack mage). Probe ini disederhanakan
## mengikuti — hanya menguji jalur tap-tembak yang tersisa.
##
## Jalankan (CI & lokal):
##   godot --headless --path project --script dev_probe/fire_attack_check.gd
## Exit 0 = LULUS; exit != 0 = build konten WAJIB berhenti.
##
## Fase 1 : semua .gd di packs/ + semua scene inti WAJIB termuat & valid.
## Fase 2 : TAP cepat via set_attack_held → satu tank_shell.gd HARUS muncul.
## Fase 3 : HUD ditanam, handler tombol serang (_on_attack) TAP cepat →
##          tank_shell.gd HARUS muncul (jalur persis tombol tembak di layar).
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
const COOLDOWN_WAIT_SEC := 1.3 # > FIRE_COOLDOWN (1.1) di player.gd supaya fase berikut tak tertelan reload
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
		print("[fire-check] LULUS ✔ (serangan tank bekerja)")
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

	# ---------- Fase 2: TAP cepat → tank_shell.gd ----------
	await process_frame          # tree hidup; _ready pemain+HUD pasti sudah jalan
	if not bool(player.get("is_ready")):
		_fail("pemain tidak siap setelah 1 frame (is_ready=false)")
		_finish()
		return
	if not player.has_method("set_attack_held"):
		_fail("player.set_attack_held tidak ada (skrip pemain versi lama?)")
		_finish()
		return
	print("[fire-check] fase 2: TAP cepat…")
	var before_tap := _count_by_suffix(world, "tank_shell.gd")
	player.call("set_attack_held", true)
	await create_timer(TAP_HOLD_SEC).timeout
	player.call("set_attack_held", false)
	await create_timer(RELEASE_SETTLE_SEC).timeout
	var after_tap := _count_by_suffix(world, "tank_shell.gd")
	if after_tap > before_tap:
		print("[fire-check] fase 2 ✔ tap → ", after_tap - before_tap, " tank_shell.gd")
	else:
		_fail("fase 2: tap cepat tidak menghasilkan tank_shell.gd — tombol serang mati")

	# ---------- Fase 3: jalur tombol HUD (TAP cepat) ----------
	if not hud.has_method("_on_attack"):
		_fail("handler tombol serang HUD (_on_attack) tidak ada")
		_finish()
		return
	# jeda melewati sisa reload meriam (fase 2) supaya penekanan HUD diuji
	# jujur, bukan tertelan cooldown tembakan terakhir
	await create_timer(COOLDOWN_WAIT_SEC).timeout
	print("[fire-check] fase 3: tekan tombol serang via HUD (tap cepat)…")
	var before := _count_by_suffix(world, "tank_shell.gd")
	hud.call("_on_attack", true)
	await create_timer(TAP_HOLD_SEC).timeout
	hud.call("_on_attack", false)
	await create_timer(RELEASE_SETTLE_SEC).timeout
	var after := _count_by_suffix(world, "tank_shell.gd")
	if after > before:
		print("[fire-check] fase 3 ✔ tombol HUD → ", after - before, " peluru meriam baru")
	else:
		_fail("fase 3: tombol serang HUD tidak menghasilkan tembakan")
	_finish()

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
