extends Control
## Launcher A-SEKAI (RonUX 2026-09-27 — permintaan user):
##   * LOADING SCREEN full-bleed foto hitam-putih Gargantua-style
##     (ui_assets/loading_bg.jpg, KEEP_ASPECT_COVERED — TIDAK DIRENGKANGKAN
##     spt keluhan "jangan di regangkan biar gk burik potonya"), progres
##     BAR TIPIS 5px di garis bawah, tanpa panel besar ("burik").
##   * HOME MENU baru sebelum masuk world (home_menu.gd): monokrom
##     geometris slanted ala reff UI racing wireframe (logo besar, kolom
##     tombol miring vertikal, strip NEWS FEED bawah) dgn isi: profil,
##     pilihan mode Creative/Open World, setting grafik, info versi, keluar.
## Tugas: hubungi server manifest, unduh pack yang berubah (resume+verifikasi),
## lalu muat pack dengan ProjectSettings.load_resource_pack() dan mulai game.
## Tugas: hubungi server manifest, unduh pack yang berubah (resume+verifikasi),
## lalu muat pack dengan ProjectSettings.load_resource_pack() dan mulai game.
## UI dibangun lewat kode agar launcher mandiri tanpa resource lain.

const UpdaterScript := preload("res://launcher/updater.gd")
const CONFIG_PATH := "user://launcher_config.cfg"
const BOOT_PATH := "user://boot.cfg"
const GAME_SCENE := "res://packs/core_scripts/game_root.tscn"
const HOME_MENU := preload("res://launcher/home_menu.gd")
# Latar loading: seni hitam-putih accretion-disk style yg diminta user.
const LOADING_BG := preload("res://launcher/ui_assets/loading_bg.jpg")
## URL server default (ubah sesuai hosting Anda, lihat README).
const DEFAULT_SERVER := "https://raw.githubusercontent.com/KyokoApp/Unity/content"
const LEGACY_SERVER := "http://127.0.0.1:8787"

var _updater
var _server_url := DEFAULT_SERVER
var _stage_label: Label
var _pack_label: Label
var _bar_overall: ProgressBar
var _bar_pack: ProgressBar
var _log: RichTextLabel
var _btn_retry: Button
var _btn_offline: Button
var _btn_server: Button
var _busy := false
var _current_manifest := {}
var _menu = null            # instance home_menu saat tampil
var _bg_tex: TextureRect # latar foto loading (dihilang saat menu/game)
var _strip: Control      # pita gelap termuat (transparan-hitam garis)

func _ready() -> void:
	_build_ui()
	_load_config()
	_apply_cli_args()
	_log_line("Server: " + _server_url)
	_start_update()

func _load_config() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) == OK:
		_server_url = str(cfg.get_value("net", "server", DEFAULT_SERVER))
		# migrasi: alamat dev lokal -> server konten publik default
		if _server_url == LEGACY_SERVER:
			_server_url = DEFAULT_SERVER
			_save_config()

func _save_config() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("net", "server", _server_url)
	cfg.save(CONFIG_PATH)

func _apply_cli_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--server="):
			_server_url = a.substr(9)

func _build_ui() -> void:
	# --- LATAR FOTO HITAM-PUTIH PENUH (penuh-sampul: tanpa regangan gambar,
	# persis teknik reff/permintaan user "jangan di regangkan") ---
	_bg_tex = TextureRect.new()
	_bg_tex.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_bg_tex.texture = LOADING_BG
	_bg_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg_tex)

	# --- pita gradient gelap DI BAWAH garis tipis (membingkai konten progres
	# tanpa menutupi foto: "loading bar tipis ada dibawah garis loading
	# tipis") — 110u transparan-hitam -->
	_strip = Control.new()
	_strip.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_strip.custom_minimum_size = Vector2(0, 128)
	_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_strip)
	_strip.draw.connect(func():
		var w := _strip.size.x; var h := _strip.size.y
		for i in range(int(h)):
			var a := 0.62 * (float(i) / h)
			_strip.draw_line(Vector2(0, i), Vector2(w, i), Color(0, 0, 0, a), 1.0, true)
	)

	# --- Judul kecil pojok kiri atas (tanpa panel) ---
	var title := Label.new()
	title.text = "A-SEKAI"
	title.add_theme_font_size_override("font_size", 42)
	title.add_theme_color_override("font_color", Color(0.93, 0.93, 0.93, 1.0))
	title.add_theme_color_override("font_shadow", Color(0, 0, 0, 0.8))
	title.set_anchors_preset(Control.PRESET_TOP_LEFT)
	title.position = Vector2(28, 22)
	add_child(title)
	var sub := Label.new()
	sub.text = "OPEN-WORLD SANDBOX"
	sub.add_theme_font_size_override("font_size", 15)
	sub.add_theme_color_override("font_color", Color(0.65, 0.65, 0.65, 0.9))
	sub.set_anchors_preset(Control.PRESET_TOP_LEFT)
	sub.position = Vector2(30, 78)
	add_child(sub)

	# --- Status & BAR TIPIS di dasar (gaya monokrom) ---
	_stage_label = Label.new()
	_stage_label.text = "Memulai..."
	_stage_label.add_theme_font_size_override("font_size", 18)
	_stage_label.add_theme_color_override("font_color", Color(0.92, 0.92, 0.92, 1.0))
	_stage_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_stage_label.position = Vector2(28, -58)
	add_child(_stage_label)

	_bar_overall = ProgressBar.new()
	_bar_overall.min_value = 0
	_bar_overall.max_value = 1000
	_bar_overall.show_percentage = false
	_bar_overall.custom_minimum_size = Vector2(0, 5)   # BAR TIPIS (permintaan user)
	_bar_overall.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_bar_overall.offset_left = 28
	_bar_overall.offset_right = -28
	_bar_overall.offset_top = -34
	_bar_overall.offset_bottom = -24
	# style: track hitam 60%, fill PUTIH solid (monokrom)
	var trk := StyleBoxFlat.new()
	trk.bg_color = Color(0,0,0,0.6); trk.corner_radius_bottom_left = 2
	trk.corner_radius_bottom_right = 2; trk.corner_radius_top_left = 2; trk.corner_radius_top_right = 2
	var fll := StyleBoxFlat.new()
	fll.bg_color = Color(0.94,0.94,0.92,1); fll.corner_radius_bottom_left = 2
	fll.corner_radius_bottom_right = 2; fll.corner_radius_top_left = 2; fll.corner_radius_top_right = 2
	_bar_overall.add_theme_stylebox_override("background", trk)
	_bar_overall.add_theme_stylebox_override("fill", fll)
	add_child(_bar_overall)

	_pack_label = Label.new()
	_pack_label.add_theme_font_size_override("font_size", 14)
	_pack_label.add_theme_color_override("font_color", Color(0.60, 0.60, 0.60, 1.0))
	_pack_label.position = Vector2(28, -86)
	_pack_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	add_child(_pack_label)
	_bar_pack = ProgressBar.new()          # proses hu pack tdk di-back baru; tetap diverifikasi signals
	_bar_pack.min_value = 0
	_bar_pack.max_value = 1000
	_bar_pack.visible = false
	add_child(_bar_pack)

	# log tersembunyi bawaan (loading bersih-murni); signals tetap mengisi.
	var scroll := ScrollContainer.new()
	scroll.visible = false
	add_child(scroll)
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.fit_content = true
	scroll.add_child(_log)

	# --- tombol minimal (muncul hanya saat gagal/konfig) ---
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	row.position = Vector2(28, -128)
	row.add_theme_constant_override("separation", 10)
	add_child(row)
	_btn_retry = _make_button("Coba Lagi", Callable(self, "_on_retry"))
	_btn_retry.visible = false
	row.add_child(_btn_retry)
	_btn_offline = _make_button("Main Offline", Callable(self, "_on_offline"))
	_btn_offline.visible = false
	row.add_child(_btn_offline)
	_btn_server = _make_button("Server…", Callable(self, "_on_server"))
	row.add_child(_btn_server)

func _make_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(150, 46)
	b.add_theme_font_size_override("font_size", 18)
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.08, 0.08, 0.08, 0.85)
	st.border_color = Color(0.85, 0.85, 0.85, 0.9)
	st.set_border_width_all(1)
	st.corner_radius_bottom_left = 4; st.corner_radius_bottom_right = 4
	st.corner_radius_top_left = 4; st.corner_radius_top_right = 4
	b.add_theme_stylebox_override("normal", st)
	var sth := st.duplicate() as StyleBoxFlat
	sth.bg_color = Color(0.85, 0.85, 0.85, 0.95)
	b.add_theme_stylebox_override("hover", sth)
	b.add_theme_stylebox_override("pressed", sth)
	b.add_theme_color_override("font_color", Color(0.93, 0.93, 0.93, 1.0))
	b.add_theme_color_override("font_hover_color", Color(0.08, 0.08, 0.08, 1.0))
	b.add_theme_color_override("font_pressed_color", Color(0.08, 0.08, 0.08, 1.0))
	b.pressed.connect(cb)
	return b

func _log_line(t: String, color := "") -> void:
	var line := t
	if color != "":
		line = "[color=%s]%s[/color]" % [color, t]
	_log.append_text(line + "\n")

func _start_update() -> void:
	_busy = true
	_btn_retry.visible = false
	_btn_offline.visible = false
	_updater = UpdaterScript.new()
	_updater.tree = get_tree()
	_updater.log_line.connect(_log_line)
	_updater.stage.connect(func(t): _stage_label.text = t)
	_updater.pack_progress.connect(_on_pack_progress)
	_updater.overall_progress.connect(_on_overall_progress)
	_updater.confirm_needed.connect(_on_confirm_needed)
	_updater.finished_ok.connect(_on_finished)
	_updater.finished_offline.connect(_on_finished_offline)
	_updater.failed.connect(_on_failed)
	# Seed manifest bundel (APK AIO): konten sudah ada di res://packs/*,
	# catat sebagai manifest lokal agar boot offline-total tetap jalan,
	# dan sebagai state agar versi sama di server tak diunduh ulang.
	if FileAccess.file_exists("res://packs/manifest.json"):
		var f := FileAccess.open("res://packs/manifest.json", FileAccess.READ)
		if f != null:
			var text := f.get_as_text()
			f.close()
			if not FileAccess.file_exists("user://local_manifest.json"):
				var w := FileAccess.open("user://local_manifest.json", FileAccess.WRITE)
				if w != null:
					w.store_string(text)
					w.close()
					_log_line("Konten bawaan terdeteksi — bisa langsung main offline.")
			if not FileAccess.file_exists("user://launcher_state.json"):
				var j = JSON.parse_string(text)
				if typeof(j) == TYPE_DICTIONARY:
					var st := {}
					for pid in j.get("packs", {}):
						var m: Dictionary = j["packs"][pid]
						st[pid] = {"version": str(m.get("version", "")), "sha256": str(m.get("sha256", ""))}
					var w2 := FileAccess.open("user://launcher_state.json", FileAccess.WRITE)
					if w2 != null:
						w2.store_string(JSON.stringify(st))
						w2.close()
	_updater.run(_server_url)

func _on_pack_progress(pid: String, done: int, total: int) -> void:
	if total > 0:
		_bar_pack.value = clamp(int(1000.0 * done / total), 0, 1000)
	_pack_label.text = "%s: %s / %s" % [pid, _fmt(done), _fmt(total)]

func _on_overall_progress(done: int, total: int) -> void:
	if total > 0:
		_bar_overall.value = clamp(int(1000.0 * done / total), 0, 1000)

func _fmt(b: int) -> String:
	if b >= 1048576:
		return "%.1f MB" % (b / 1048576.0)
	return "%.0f KB" % (b / 1024.0)

func _on_confirm_needed(total_bytes: int, count: int) -> void:
	# headless/dev: auto-accept bila tidak ada UI atau flag --auto-download
	if DisplayServer.get_name() == "headless" or OS.get_cmdline_user_args().has("--auto-download"):
		_log_line("Konfirmasi unduhan: auto-accept (headless/auto-download)")
		_updater.respond_confirm(true)
		return
	var d := ConfirmationDialog.new()
	d.title = "Unduh konten?"
	var wifi_note := "\nAnda mungkin memakai data seluler — disarankan memakai Wi-Fi." if OS.has_feature("android") else ""
	d.dialog_text = "Konten game perlu diunduh: %d pack, total %s.%s" % [count, _fmt(total_bytes), wifi_note]
	d.ok_button_text = "Unduh"
	d.cancel_button_text = "Batal"
	d.confirmed.connect(func():
		_updater.respond_confirm(true)
		d.queue_free())
	d.canceled.connect(func():
		_updater.respond_confirm(false)
		d.queue_free())
	add_child(d)
	d.popup_centered()

func _on_finished(local_manifest: Dictionary) -> void:
	_log_line("Semua konten siap.", "lightgreen")
	_current_manifest = local_manifest
	_show_home_menu(false)

func _on_finished_offline(local_manifest: Dictionary) -> void:
	_log_line("Mode offline — memakai pack yang sudah ada.", "yellow")
	_current_manifest = local_manifest
	_show_home_menu(true)

## HOME MENU monokrom (permintaan user): setelah update siap, pemain milih
## mode dulu (Creative/Open World) + bisa ganti preset grafik, baru keluar ke
## game. Headless/--auto-download langsung masuk (CI aman).
var _boot_offline := false
func _show_home_menu(offline: bool) -> void:
	_busy = false
	if DisplayServer.get_name() == "headless" or OS.get_cmdline_user_args().has("--auto-download"):
		_enter_game(offline, "")
		return
	_boot_offline = offline
	if _menu != null:
		return   # sudah tampil (double-signal guard)
	_stage_label.text = "Siap memilih dunia."
	_menu = HOME_MENU.new()
	_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu.pack_versions = _pack_version_map()
	_menu.offline = offline
	_menu.mode_chosen.connect(func(m): _enter_game(offline, m))
	_menu.quality_changed.connect(func(_qp): pass)   # persist sendiri di cfg menu
	_menu.quit_requested.connect(func(): get_tree().quit())
	add_child(_menu)
	# versi-versi diteruskan lagi via API (tampilan news-tile menegantikan)
	_menu.set_versions(_pack_version_map(), offline)

func _pack_version_map() -> Dictionary:
	var out := {}
	for pid in _current_manifest.get("packs", {}):
		out[pid] = str(_current_manifest["packs"][pid].get("version", "?"))
	out["world_terrain"] = str(_current_manifest.get("packs", {}).get("world_terrain", {}).get("version", out.get("world_terrain", "?")))
	return out

func _on_failed(reason: String) -> void:
	_busy = false
	_stage_label.text = "Gagal"
	_log_line("GAGAL: " + reason, "tomato")
	_btn_retry.visible = true
	# tawarkan offline bila ada manifest lokal ATAU konten bundel di APK
	# (fix: dulu hanya cek user://, padahal seed pertama user:// belum ada).
	if FileAccess.file_exists("user://local_manifest.json") \
			or FileAccess.file_exists("res://packs/manifest.json"):
		_btn_offline.visible = true

func _on_retry() -> void:
	_start_update()

func _on_offline() -> void:
	# FIX BUG: dulunya memanggil _updater._load_local_manifest() yang private
	# & bergantung pada _updater yang sudah diinisialisasi penuh (kalau
	# _updater null dibuat new() di sini, tree/state belum lengkap dan
	# method private bisa gagal/return kosong). Baca langsung file manifest
	# lokal — jauh lebih aman dan tak bergantung pada state updater.
	var local := _read_local_manifest_file()
	if local.is_empty():
		_log_line("Tidak ada konten lokal.", "tomato")
		return
	_current_manifest = local
	_enter_game(true)

## Helper: baca user://local_manifest.json langsung (dipakai tombol offline
# dan di _start_update). Dipisah supaya tak perlu menyentuh internal Updater.
func _read_local_manifest_file() -> Dictionary:
	if not FileAccess.file_exists("user://local_manifest.json"):
		# fallback terakhir: manifest bawaan APK/dev di res://
		if FileAccess.file_exists("res://packs/manifest.json"):
			var f := FileAccess.open("res://packs/manifest.json", FileAccess.READ)
			if f != null:
				var t := f.get_as_text(); f.close()
				var d = JSON.parse_string(t)
				if typeof(d) == TYPE_DICTIONARY:
					return d
		return {}
	var f := FileAccess.open("user://local_manifest.json", FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	f.close()
	return d if typeof(d) == TYPE_DICTIONARY else {}

func _on_server() -> void:
	var d := ConfirmationDialog.new()
	d.title = "Alamat server paket"
	var le := LineEdit.new()
	le.text = _server_url
	le.custom_minimum_size = Vector2(640, 56)
	d.add_child(le)
	d.confirm_button_text = "Simpan"
	d.register_text_enter(le)
	d.confirmed.connect(func():
		_server_url = le.text.strip_edges()
		_save_config()
		_log_line("Server diset: " + _server_url)
		d.queue_free())
	add_child(d)
	d.popup_centered()

func _enter_game(offline: bool, mode := "") -> void:
	if mode == "" and _menu != null:
		mode = str(_menu.chosen_mode)
	_stage_label.text = "Memuat konten…"
	_btn_retry.visible = false
	_btn_offline.visible = false
	# muat pack sesuai urutan dependensi
	var order: Array = _current_manifest.get("pack_order", [])
	var packs: Dictionary = _current_manifest.get("packs", {})
	for pid in order:
		var meta: Dictionary = packs.get(pid, {})
		var path := "user://packs/%s-%s.pck" % [pid, str(meta.get("version", ""))]
		var bundled := "res://packs/%s" % pid
		var size_here: int = int(meta.get("size", 0))
		if FileAccess.file_exists(path):
			_log_line("Memuat " + pid + " (terunduh)…")
			print("[launcher] load_resource_pack: ", path)
			if not ProjectSettings.load_resource_pack(path, true, 0):
				_log_line("Gagal memuat pack: " + pid, "tomato")
				_on_failed("Pack '%s' rusak atau tidak cocok dengan versi aplikasi." % pid)
				return
		elif DirAccess.dir_exists(bundled):
			# Konten bundel: pack SUDAH ada di res:// (developer build / APK AIO
			# tanpa pack .pck terpisah). size=0 = penanda bundel (lihat updater).
			# TIDAK perlu load_resource_pack karena file-nya sudah di-res://
			# secara langsung.
			_log_line("Memuat " + pid + " (lokal/bundel, tersedia di res://)…")
			print("[launcher] bundel tersedia, skip load_resource_pack: ", pid)
		elif size_here == 0:
			# size=0 menandakan BUNDEL; kalau DirAccess gagal, coba sub-path
			# (beberapa platform Godot memerlukan garis miring akhir).
			_log_line("Memuat " + pid + " (bundel)...")
		else:
			_log_line("Pack hilang: " + path, "tomato")
			_on_failed("File pack tidak ditemukan; coba unduh ulang.")
			return
	# tulis konfigurasi boot untuk game
	var cfg := ConfigFile.new()
	cfg.set_value("boot", "offline", offline)
	cfg.set_value("boot", "server", _server_url)
	cfg.set_value("boot", "game_version", str(_current_manifest.get("game_version", "?")))
	# MODE DUNIA PILIHAN (menu monokrom): creative|open — dibaca game_root
	# diteruskan ke world.set_open_world_mode().
	if mode != "":
		cfg.set_value("boot", "world_mode", mode)
	# Preset grafik dr menu (0/1/2) → game_settings (quality_preset ter-load
	# SEPERTI abadi; jagna perubahan permanen — _enter_game menulis balik yg
	# ada saat ini agar nomor konsisten).
	if _menu != null:
		cfg.set_value("boot", "quality_preset", int(_menu.quality_preset))
	cfg.save(BOOT_PATH)
	_stage_label.text = "Menjalankan game…"
	await get_tree().process_frame
	get_tree().change_scene_to_file(GAME_SCENE)
