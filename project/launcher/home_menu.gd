extends Control
## HOME MENU (ronde ini, permintaan user: "ui pas di sebelum masuk world di
## pilihan mode ambil referensi dari gambar") — gaya wireframe racing-game
## MONOKROM: latar hitam, panel diagonal putih besar di kanan, logo besar
## kiri-atas, kolom tombol miring (parallelogram) VERTIKAL, strip "NEWS
## FEED" slanted di bawah, isi menyesuaikan: ikon profil + mode permainan
## Creative/Open World + grafik-preset + info versi/server + keluar.
##
## 100% digambar dari kode (nol .tscn/aset tambahan): latar oleh _draw(),
## tombol oleh class SlantedButton (polygon miring khas reff-nya),
## PROFILE disc jg polygon. Signal mode_chosen dipanggil launcher.
## Seluruh konten bersifat monokrom putih/abu dr konstan fill (elegan,
## anti-klise, dan pembebanan minimal — bukan gambar berat).

signal mode_chosen(mode: String)
signal quality_changed(preset: int)
signal quit_requested()

const CFG_PATH := "user://launcher_menu.cfg"

const C_BG := Color(0.055, 0.055, 0.055, 1.0)        # hitam lembut
const C_PANEL := Color(0.92, 0.92, 0.90, 1.0)        # panel diagonal putih
const C_PANEL2 := Color(0.13, 0.13, 0.13, 1.0)       # segi gelap bawah
const C_TXT := Color(0.92, 0.92, 0.92, 1.0)
const C_TXT_DIM := Color(0.55, 0.55, 0.55, 1.0)
const C_SLANT := Color(0.16, 0.16, 0.16, 1.0)        # isi jajaran genjang
const C_SLANT_HI := Color(0.85, 0.85, 0.83, 1.0)     # hover = putih
const C_SLANT_TXT := Color(0.93, 0.93, 0.93, 1.0)
const C_ACCENT := Color(0.75, 0.75, 0.75, 1.0)

var chosen_mode := "creative"    # creative|open — last-chosen (persist)
var quality_preset := 1          # 0=Rendah,1=Sedang,2=Tinggi (direlay ke settings game)
var offline := false
var pack_versions := {}          # pid -> version (diisi launcher setelah manifest)

var _menu_col: VBoxContainer
var _btn_open: Control
var _btn_create: Control
var _btn_gfx: Control
var _status_line: Label
var _profile_last: Label        # "Mode terakhir: ..." kecil di profile row

# =============================== TOMBOL MIRING ===============================
## Parallelogram tombol polos (serba kode): polygon dasar = jajaran genjang
## (+ shear 26px dr tinggi 72↑ spt reff); update letakan slot saat press;
## segitiga tipis aksen di tepi kiri; teks digeser ke kiri rata (spt reff).
class SlantedButton:
	extends Control
	signal pressed
	signal entered
	var text := ""
	var sub := ""
	var hover := false
	var downed := false
	var active := false  # ditandai ceklis kecil di kiri (mode yg sedang terpilih)
	const H := 76.0
	const SHEAR := 26.0
	# konstanta warna inner (HARUS dideklarasikan di sini: inner class GDScript
	# TIDAK mewarisi konstanta class luar — bug compile-lint pernah terbukti).
	const C_SLANT := Color(0.16, 0.16, 0.16, 1.0)
	const C_SLANT_HI := Color(0.85, 0.85, 0.83, 1.0)
	const C_SLANT_TXT := Color(0.93, 0.93, 0.93, 1.0)
	const C_ACCENT := Color(0.75, 0.75, 0.75, 1.0)

	func _init(t := "", s := "") -> void:
		text = t; sub = s
		custom_minimum_size = Vector2(400.0, H)
		mouse_filter = Control.MOUSE_FILTER_STOP
		size_flags_horizontal = Control.SIZE_EXPAND_FILL

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseMotion:
			hover = true; queue_redraw(); entered.emit()
		elif e is InputEventScreenTouch and e.pressed:
			downed = true; queue_redraw()
		elif e is InputEventScreenTouch and not e.pressed and downed:
			downed = false; pressed.emit(); queue_redraw()
		elif e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed:
				downed = true; queue_redraw()
			elif downed:
				downed = false; pressed.emit(); queue_redraw()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_MOUSE_EXIT:
			hover = false; queue_redraw()

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var fill := C_SLANT_HI if (hover or downed) else C_SLANT
		var txt := Color(0.10, 0.10, 0.10, 1.0) if (hover or downed) else C_SLANT_TXT
		# jajaran genjang utama (miring ke kanan)
		draw_colored_polygon(PackedVector2Array([
			Vector2(0, 0), Vector2(w - SHEAR, 0), Vector2(w, h), Vector2(SHEAR, h)]), fill)
		# tepi bawah-tebal (sense tebal spt reff)
		var shade := Color(0.04, 0.04, 0.04, 0.65) if (hover or downed) else Color(0.0, 0.0, 0.0, 0.5)
		draw_colored_polygon(PackedVector2Array([
			Vector2(SHEAR, h), Vector2(w, h), Vector2(w - 5, h - 6), Vector2(SHEAR + 5, h - 6)]), shade)
		# ticker vertikal kiri (ceklis = mode aktif)
		var tcol := Color(0.10, 0.10, 0.10, 1.0) if (hover or downed) else C_ACCENT
		if active:
			draw_line(Vector2(14, 14), Vector2(22, 14), tcol, 3.0, true)
			draw_line(Vector2(18, 20), Vector2(8, 40), tcol, 3.0, true)   # batang tegak kecil
			draw_line(Vector2(8, 40), Vector2(30, 52), tcol, 3.0, true)
		# teks utama (atas, besar)
		draw_string(get_theme_default_font(), Vector2(34.0, 31.0), text,
			HORIZONTAL_ALIGNMENT_LEFT, w - 60.0, 26, txt)
		if sub != "":
			draw_string(get_theme_default_font(), Vector2(34.0, 55.0), sub,
				HORIZONTAL_ALIGNMENT_LEFT, w - 60.0, 15, Color(txt) * Color(1, 1, 1, 0.62))

func _ready() -> void:
	_load_cfg()
	_build()
	queue_redraw()

func _load_cfg() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CFG_PATH) == OK:
		chosen_mode = str(cfg.get_value("menu", "mode", chosen_mode))
		quality_preset = clampi(int(cfg.get_value("menu", "quality", quality_preset)), 0, 2)

func save_cfg() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("menu", "mode", chosen_mode)
	cfg.set_value("menu", "quality", quality_preset)
	cfg.save(CFG_PATH)

# ============================ KONSTRUKSI TAMPILAN ===========================
func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	var sa := DisplayServer.get_display_safe_area()
	if sa.size.x > 0:
		margin.add_theme_constant_override("margin_left", int(sa.position.x) + 26)
		margin.add_theme_constant_override("margin_top", int(sa.position.y) + 18)
		margin.add_theme_constant_override("margin_right", maxi(26, int(get_viewport().get_visible_rect().size.x - sa.end.x) + 26))
		margin.add_theme_constant_override("margin_bottom", maxi(18, int(get_viewport().get_visible_rect().size.y - sa.end.y) + 14))
	else:
		for m in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
			margin.add_theme_constant_override(m, 22)
	add_child(margin)
	var root_v := VBoxContainer.new()
	root_v.add_theme_constant_override("separation", 10)
	margin.add_child(root_v)

	# ---- LOGO besar kiri atas (persis ciri reff) ----
	var hb_top := HBoxContainer.new()
	hb_top.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_v.add_child(hb_top)
	var left_col := VBoxContainer.new()
	left_col.add_theme_constant_override("separation", 8)
	hb_top.add_child(left_col)
	var logo := Label.new()
	logo.text = "A-SEKAI"
	logo.add_theme_font_size_override("font_size", 96)
	logo.add_theme_color_override("font_color", C_PANEL)
	left_col.add_child(logo)
	var sub := Label.new()
	sub.text = "OPEN-WORLD ANIMATION SANDBOX · v1.0"
	sub.add_theme_font_size_override("font_size", 16)
	sub.add_theme_color_override("font_color", C_TXT_DIM)
	left_col.add_child(sub)

	# ---- PROFILE row (ikon bulat + nama + mode terakhir) ----
	var prof_row := HBoxContainer.new()
	prof_row.add_theme_constant_override("separation", 14)
	left_col.add_child(prof_row)
	var disc := Control.new()
	disc.custom_minimum_size = Vector2(64, 64)
	disc.draw.connect(func():
		var c := Vector2(32, 32)
		disc2.draw_circle(c, 30.0, Color(0.85, 0.85, 0.85, 1.0))
		disc2.draw_circle(c, 26.0, C_BG)
		disc2.draw_arc(c + Vector2(0, -8), 8.5, 0, TAU, 24, C_TXT, 3.5, true)   # kepala
		disc2.draw_arc(c + Vector2(0, 30), 13.0, PI, TAU, 24, C_TXT, 3.5, true)  # bahu
	)
	var disc2: Control = disc   # bind final-value utk lambda draw.connect
	prof_row.add_child(disc)
	var prof_txt := VBoxContainer.new()
	prof_txt.add_theme_constant_override("separation", 2)
	prof_row.add_child(prof_txt)
	var pname := Label.new()
	pname.text = "PENJELAJAH"
	pname.add_theme_font_size_override("font_size", 26)
	pname.add_theme_color_override("font_color", C_TXT)
	prof_txt.add_child(pname)
	_profile_last = Label.new()
	_profile_last.text = ""
	_profile_last.add_theme_font_size_override("font_size", 15)
	_profile_last.add_theme_color_override("font_color", C_TXT_DIM)
	prof_txt.add_child(_profile_last)
	_sync_profile_note()

	# ---- KOLOM tombol miring (kiri) ----
	_menu_col = VBoxContainer.new()
	_menu_col.add_theme_constant_override("separation", 8)
	hb_top.add_child(_menu_col)
	left_col.add_child(_menu_col)

	_btn_open = SlantedButton.new("OPEN WORLD", "hutan tanpa-batas · kabut dekat · rumput setinggi betis")
	_btn_open.active = (chosen_mode == "open")
	_btn_open.pressed.connect(func(): _pick_mode("open"))
	_menu_col.add_child(_btn_open)

	_btn_create = SlantedButton.new("CREATIVE WORLD", "pulau 1km · build mode · laut mengelilingi")
	_btn_create.active = (chosen_mode == "creative")
	_btn_create.pressed.connect(func(): _pick_mode("creative"))
	_menu_col.add_child(_btn_create)

	_btn_gfx = SlantedButton.new("SETTING GRAFIK", _gfx_label())
	_btn_gfx.pressed.connect(_cycle_gfx)
	_menu_col.add_child(_btn_gfx)

	var b_info := SlantedButton.new("INFO UPDATE", "versi & server konten — ketuk untuk rincian")
	b_info.pressed.connect(_info_cycle)
	_menu_col.add_child(b_info)

	var b_quit := SlantedButton.new("KELUAR", "tutup aplikasi")
	b_quit.pressed.connect(func(): quit_requested.emit())
	_menu_col.add_child(b_quit)

	# ---- NEWS FEED slanted strip (bawah) ----
	var news_row := HBoxContainer.new()
	news_row.add_theme_constant_override("separation", 8)
	root_v.add_child(news_row)
	# label strip mini "NEWS FEED" spt reff — panah kirinya
	_status_line = Label.new()
	_status_line.text = ""
	_status_line.add_theme_font_size_override("font_size", 15)
	_status_line.add_theme_color_override("font_color", C_TXT_DIM)
	root_v.add_child(_status_line)
	_news_tiles(news_row)

func _gfx_label() -> String:
	return ["Rendah (hemat)", "Seimbang", "Tinggi"][clampi(quality_preset, 0, 2)]

func _cycle_gfx() -> void:
	quality_preset = (quality_preset + 1) % 3
	_btn_gfx.sub = _gfx_label()
	_btn_gfx.queue_redraw()
	save_cfg()
	quality_changed.emit(quality_preset)

func _info_cycle() -> void:
	var parts: Array = []
	for pid in pack_versions:
		parts.append("%s %s" % [pid, str(pack_versions[pid])])
	if parts.is_empty():
		_status_line.text = "versi kemasan akan tampil sehabis unduhan pertama"
	else:
		_status_line.text = " · ".join(parts) + ("  ·  OFFLINE" if offline else "")

func _pick_mode(m: String) -> void:
	chosen_mode = m
	_btn_open.active = (m == "open")
	_btn_create.active = (m == "creative")
	_btn_open.queue_redraw()
	_btn_create.queue_redraw()
	_sync_profile_note()
	save_cfg()
	mode_chosen.emit(m)

func _sync_profile_note() -> void:
	if _profile_last:
		_profile_last.text = "Mode terakhir: " + ("OPEN WORLD" if chosen_mode == "open" else "CREATIVE")

## Empat tile jajaran genjang di bagian bawah (strip news spt reff).
func _news_tiles(row: HBoxContainer) -> void:
	for k in range(4):
		var k2: int = k                       # bind final-value utk lambda di bawah
		var t := Control.new()
		var t2: Control = t                   # bind final-value (draw.connect ref-capture)
		t.custom_minimum_size = Vector2(0, 56)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(t)
		var lbl := [ "VERSI", "MODE", "GRAFIK", "STATUS"][k2]
		t.draw.connect(func():
			var w := t2.size.x; var h := t2.size.y
			var sh := 18.0
			var fill := C_PANEL2 if k2 % 2 == 0 else Color(0.20, 0.20, 0.20, 1.0)
			t2.draw_colored_polygon(PackedVector2Array([
				Vector2(0, 0), Vector2(w - sh, 0), Vector2(w, h), Vector2(sh, h)]), fill)
			var val := ""
			match k2:
				0: val = str(pack_versions.get("world_terrain", "-"))
				1: val = "OPEN" if chosen_mode == "open" else "CREATIVE"
				2: val = _gfx_label().split(" ")[0]
				3: val = "OFFLINE" if offline else "ONLINE"
			t2.draw_string(t2.get_theme_default_font(), Vector2(sh + 10.0, 22.0), lbl,
				HORIZONTAL_ALIGNMENT_LEFT, 200.0, 13, C_TXT_DIM)
			t2.draw_string(t2.get_theme_default_font(), Vector2(sh + 10.0, 44.0), val,
				HORIZONTAL_ALIGNMENT_LEFT, 200.0, 19, C_TXT)
		)
		t.name = "NewsTile%d" % k2
	row.queue_redraw()

# pengantman kabar versi yg dikirim launcher sesudah unduhan/manifest.
func set_versions(versions: Dictionary, is_offline: bool) -> void:
	pack_versions = versions
	offline = is_offline
	# biar news tergambar ulang dg data baru
	for t in find_children("NewsTile*", "Control", true, false):
		t.queue_redraw()

# ============================ LATAR GEOMETRIS ============================
func _draw() -> void:
	var w := size.x; var h := size.y
	draw_rect(Rect2(Vector2.ZERO, size), C_BG)
	# PANEL DIAGONAL PUTIH besar sisi kanan (ciri utama reff — di belakang
	# tulisan; layer digambar pertama => tertampak paling belakangg).
	var diag := 0.62   # kemiringan (stor frak lebar)
	draw_colored_polygon(PackedVector2Array([
		Vector2(w * 0.52, 0), Vector2(w, 0), Vector2(w, h), Vector2(w * (0.52 - diag * h / w), h)]), C_PANEL)
	# garis-garis tipis paralel dekoratif di kiri bawah (reff punya tearap
	# strip diagonal): 5 strip miring, transparan.
	for i in range(5):
		var oy := h - 90.0 - i * 14.0
		draw_line(Vector2(0, oy), Vector2(w * 0.30, oy - w * 0.30 * 0.28), C_ACCENT * Color(1,1,1, 0.30), 2.0, true)
