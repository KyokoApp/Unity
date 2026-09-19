extends Control
## Launcher Pulau Toon.
## Tugas: hubungi server manifest, unduh pack yang berubah (resume+verifikasi),
## lalu muat pack dengan ProjectSettings.load_resource_pack() dan mulai game.
## UI dibangun lewat kode agar launcher mandiri tanpa resource lain.

const UpdaterScript := preload("res://launcher/updater.gd")
const CONFIG_PATH := "user://launcher_config.cfg"
const BOOT_PATH := "user://boot.cfg"
const GAME_SCENE := "res://packs/core_scripts/game_root.tscn"
## URL server default (ubah sesuai hosting Anda, lihat README).
const DEFAULT_SERVER := "http://127.0.0.1:8787"

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

func _save_config() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("net", "server", _server_url)
	cfg.save(CONFIG_PATH)

func _apply_cli_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--server="):
			_server_url = a.substr(9)

func _build_ui() -> void:
	var sa := DisplayServer.get_display_safe_area()
	var root_margin := MarginContainer.new()
	root_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	if sa.size.x > 0:
		root_margin.add_theme_constant_override("margin_left", sa.position.x + 24)
		root_margin.add_theme_constant_override("margin_top", sa.position.y + 16)
		root_margin.add_theme_constant_override("margin_right", maxi(24, get_viewport().get_visible_rect().size.x - sa.end.x + 24))
		root_margin.add_theme_constant_override("margin_bottom", maxi(16, get_viewport().get_visible_rect().size.y - sa.end.y + 16))
	else:
		for m in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
			root_margin.add_theme_constant_override(m, 24)
	add_child(root_margin)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_margin.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(720, 0)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	panel.add_child(v)

	var title := Label.new()
	title.text = "🌴 Pulau Toon"
	title.add_theme_font_size_override("font_size", 44)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)

	var sub := Label.new()
	sub.text = "Peluncur — memeriksa & mengunduh konten game"
	sub.add_theme_font_size_override("font_size", 20)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.modulate.a = 0.75
	v.add_child(sub)

	_stage_label = Label.new()
	_stage_label.text = "Memulai..."
	_stage_label.add_theme_font_size_override("font_size", 22)
	v.add_child(_stage_label)

	_bar_overall = ProgressBar.new()
	_bar_overall.min_value = 0
	_bar_overall.max_value = 1000
	_bar_overall.custom_minimum_size = Vector2(0, 30)
	_bar_overall.show_percentage = true
	v.add_child(_bar_overall)

	_pack_label = Label.new()
	_pack_label.text = ""
	_pack_label.add_theme_font_size_override("font_size", 18)
	v.add_child(_pack_label)

	_bar_pack = ProgressBar.new()
	_bar_pack.min_value = 0
	_bar_pack.max_value = 1000
	_bar_pack.custom_minimum_size = Vector2(0, 22)
	v.add_child(_bar_pack)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 210)
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	v.add_child(scroll)
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.fit_content = true
	_log.scroll_following = true
	_log.add_theme_font_size_override("normal_font_size", 17)
	_log.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_log)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row)

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
	b.custom_minimum_size = Vector2(180, 64)
	b.add_theme_font_size_override("font_size", 22)
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
	_enter_game(false)

func _on_finished_offline(local_manifest: Dictionary) -> void:
	_log_line("Mode offline — memakai pack yang sudah ada.", "yellow")
	_current_manifest = local_manifest
	_enter_game(true)

func _on_failed(reason: String) -> void:
	_busy = false
	_stage_label.text = "Gagal"
	_log_line("GAGAL: " + reason, "tomato")
	_btn_retry.visible = true
	# tawarkan offline bila ada manifest lokal
	if FileAccess.file_exists("user://local_manifest.json"):
		_btn_offline.visible = true

func _on_retry() -> void:
	_start_update()

func _on_offline() -> void:
	if _updater == null:
		_updater = UpdaterScript.new()
		_updater.tree = get_tree()
	var local = _updater._load_local_manifest()
	if local.is_empty():
		_log_line("Tidak ada konten lokal.", "tomato")
		return
	_current_manifest = local
	_enter_game(true)

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

func _enter_game(offline: bool) -> void:
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
		if FileAccess.file_exists(path):
			_log_line("Memuat " + pid + " (terunduh)…")
			print("[launcher] load_resource_pack: ", path)
			if not ProjectSettings.load_resource_pack(path, true, 0):
				_log_line("Gagal memuat pack: " + pid, "tomato")
				_on_failed("Pack '%s' rusak atau tidak cocok dengan versi aplikasi." % pid)
				return
		elif DirAccess.dir_exists_absolute(bundled):
			# fallback dev / paket terpasang: resource pack sudah ada di res://
			_log_line("Memuat " + pid + " (lokal/bundel)…")
			print("[launcher] fallback res:// ", pid)
		else:
			_log_line("Pack hilang: " + path, "tomato")
			_on_failed("File pack tidak ditemukan; coba unduh ulang.")
			return
	# tulis konfigurasi boot untuk game
	var cfg := ConfigFile.new()
	cfg.set_value("boot", "offline", offline)
	cfg.set_value("boot", "server", _server_url)
	cfg.set_value("boot", "game_version", str(_current_manifest.get("game_version", "?")))
	cfg.save(BOOT_PATH)
	_stage_label.text = "Menjalankan game…"
	await get_tree().process_frame
	get_tree().change_scene_to_file(GAME_SCENE)
