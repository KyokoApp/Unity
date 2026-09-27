class_name BuildModeUI
extends CanvasLayer
## UI Build Mode (butir 1, 6 & 7 user) — SELURUHNYA dibangun dari kode
## (nol .tscn): floating button "BANGUN" pojok kanan-bawah + panel bawah
## ala sheet dengan tab sub-mode (Objek / Terrain / Jalan / Hapus), plus
## baris aksi Simpan/Muat/Tutup+Simpan. Semua target sentuh >= 56px supaya
## gampang ditekan di layar HP (butir "touch-friendly").
##
## Layer=6: di atas HUD permainan (hud.gd layer=1) tapi di bawah menu
## pause (20) & loading (10) — menu pause tetap bisa menutupi build.
##
## Sinyal ke luar (manager): lewat Callable dictionary yg di-set manager
## (ui.cb["xxx"]) — UI tak perlu tahu detail manager (modular, mudah
## di-maintain sesuai butir 7).

var cb := {}                  # nama -> Callable utk aksi manager
var fab: Button               # floating action button toggle Build Mode
var panel: PanelContainer     # sheet bawah (terlihat hanya saat build aktif)
var tab_buttons := {}         # "place"/"terrain"/"road"/"delete" -> Button
var pages := {}               # key -> Control konten per tab
var status_label: Label
var rot_label: Label
var scale_label: Label
var rot_slider: HSlider
var scale_slider: HSlider
var palette_grid: GridContainer
var palette_buttons := {}     # id katalog -> Button
var tile_buttons := {}        # item -> Button
var rotate_btn: Button
var level_label: Label
var width_label: Label
var width_slider: HSlider
var pending_row: HBoxContainer  # baris OK/BATAL calon objek (ronde ini: teken-lama geser, lalu OK)
var joy_control: Control      # mini joystick khusus build (BuildJoyControl)
var _clear_armed := false     # konfirmasi 2x-tap utk "Hapus SEMUA"
var _status_t := 0.0

const MIN_TOUCH := 76         # px hit-target minimum (ronde ini: permintaan user "sempit" → tata letak dilegakan)

func _ready() -> void:
	layer = 6
	_build_layout()
	set_process(true)

## ---------- konstruksi tampilan ----------

func _build_layout() -> void:
	# FAB kanan-bawah (selalu tampak, juga di luar build mode)
	fab = _make_button("BANGUN", Color(0.95, 0.72, 0.32), Color(0.28, 0.20, 0.08))
	fab.custom_minimum_size = Vector2(112, 64)
	fab.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	fab.position = Vector2(-128, -84)
	fab.pressed.connect(func(): _call("toggle"))
	add_child(fab)

	# Panel sheet di bawah: tersembunyi sampai build di-toggle
	panel = PanelContainer.new()
	panel.visible = false
	panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_bottom = 0
	panel.offset_top = -500   # mode bangun = kanvas kerja: sheet dilegakan biar tak sempit (permintaan user)
	var pstyle := StyleBoxFlat.new()
	pstyle.bg_color = Color(0.09, 0.085, 0.12, 0.93)
	pstyle.corner_radius_top_left = 22
	pstyle.corner_radius_top_right = 22
	pstyle.content_margin_left = 14
	pstyle.content_margin_right = 14
	pstyle.content_margin_top = 10
	pstyle.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", pstyle)
	add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)

	# --- STATUS dipindah ke ATAS tabs: dl di bawah bar paling buncit
	# (sering kena potong layar kecil; sempit ala screenshot user) ---
	status_label = Label.new()
	status_label.text = ""
	status_label.add_theme_font_size_override("font_size", 17)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.custom_minimum_size = Vector2(0, 30)
	vb.add_child(status_label)

	# --- bar tab sub-mode ---
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 10)
	vb.add_child(tabs)
	for spec in [["place", "Objek"], ["terrain", "Terrain"], ["road", "Jalan"], ["delete", "Hapus"]]:
		var tb := _make_button(spec[1], Color(0.22, 0.20, 0.28), Color(0.10, 0.09, 0.14))
		tb.custom_minimum_size = Vector2(0, MIN_TOUCH)
		tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var key: String = spec[0]
		tb.pressed.connect(func(): _call("set_submode", key))
		tabs.add_child(tb)
		tab_buttons[key] = tb

	# --- container konten tab (visible = hanya satu halaman) ---
	var pages_root := Control.new()
	pages_root.custom_minimum_size = Vector2(0, 240)
	vb.add_child(pages_root)
	pages["place"] = _build_page_place(pages_root)
	pages["terrain"] = _build_page_terrain(pages_root)
	pages["road"] = _build_page_road(pages_root)
	pages["delete"] = _build_page_delete(pages_root)

	# --- baris aksi bawah: Reverse / Simpan / Muat / Tutup ---
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	vb.add_child(bar)
	# Tombol REVERSE (permintaan user): mengambil kembali aksi terakhir —
	# objek yang sdh ditaruh bisa diambil lagi lewat ini (utuh 1 tumpukan
	# LIFO utk semua aksi bangun: taruh objs, tile, jalan, hapus, dsb).
	var bundo := _make_button("↶ Reverse", Color(0.46, 0.38, 0.26), Color(0.16, 0.13, 0.07))
	bundo.custom_minimum_size = Vector2(0, MIN_TOUCH)
	bundo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bundo.pressed.connect(func(): _call("undo"))
	bar.add_child(bundo)
	var bsave := _make_button("Simpan", Color(0.30, 0.42, 0.30), Color(0.10, 0.14, 0.10))
	bsave.custom_minimum_size = Vector2(0, MIN_TOUCH)
	bsave.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bsave.pressed.connect(func(): _call("save"))
	bar.add_child(bsave)
	var bload := _make_button("Muat", Color(0.28, 0.36, 0.46), Color(0.09, 0.11, 0.15))
	bload.custom_minimum_size = Vector2(0, MIN_TOUCH)
	bload.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bload.pressed.connect(func(): _call("load"))
	bar.add_child(bload)
	var bclose := _make_button("Tutup ✓", Color(0.42, 0.30, 0.26), Color(0.14, 0.10, 0.09))
	bclose.custom_minimum_size = Vector2(0, MIN_TOUCH)
	bclose.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bclose.pressed.connect(func(): _call("toggle"))
	bar.add_child(bclose)

	# Mini joystick kiri-bawah (hanya saat build aktif; hud normal
	# ditahan manager). Di-extend di build_joy_control.gd — modular.
	var joy_script := load("res://packs/build_mode/build_joy_control.gd")
	joy_control = joy_script.new() as Control
	joy_control.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	joy_control.position = Vector2(24, -470 - 150)   # tepat di atas sheet
	joy_control.visible = false
	add_child(joy_control)

## Halaman OBJEK: palette katalog BENTUK KISI KOTAK (grid sel persegi,
## permintaan user ronde ini: "buat kayak bentuk kisi kisi kotak gitu") —
## scroll VERTIKAL bijb kaetika kolom kurang. Slider rotasi/scale + hint.
## Palette diisi ulang oleh manager (catalog dibuat saat setup).
func _build_page_place(root: Control) -> Control:
	var page := VBoxContainer.new()
	page.set_anchors_preset(Control.PRESET_FULL_RECT)
	page.add_theme_constant_override("separation", 8)
	root.add_child(page)

	# baris konfirmasi CALON di ATAS palette: paling gampang ditekan
	# dari kanvas (dipakai dulu sebelum scroll pilih objek lain)
	pending_row = HBoxContainer.new()
	pending_row.add_theme_constant_override("separation", 8)
	pending_row.visible = false
	page.add_child(pending_row)
	var bok := _make_button("✔ OK — Simpan Posisi", Color(0.30, 0.50, 0.30), Color(0.10, 0.16, 0.10))
	bok.custom_minimum_size = Vector2(0, MIN_TOUCH)
	bok.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bok.pressed.connect(func(): _call("ok_pending"))
	pending_row.add_child(bok)
	var bno := _make_button("✖ BATAL", Color(0.48, 0.28, 0.24), Color(0.15, 0.08, 0.06))
	bno.custom_minimum_size = Vector2(140, MIN_TOUCH)
	bno.pressed.connect(func(): _call("cancel_pending"))
	pending_row.add_child(bno)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 156)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	page.add_child(scroll)
	palette_grid = GridContainer.new()
	palette_grid.add_theme_constant_override("h_separation", 8)
	palette_grid.add_theme_constant_override("v_separation", 8)
	palette_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(palette_grid)

	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 10)
	page.add_child(row1)
	rot_label = Label.new()
	rot_label.text = "Putar: 0°"
	rot_label.custom_minimum_size = Vector2(110, 0)
	rot_label.add_theme_font_size_override("font_size", 18)
	row1.add_child(rot_label)
	rot_slider = HSlider.new()
	rot_slider.min_value = 0.0
	rot_slider.max_value = 360.0
	rot_slider.step = 5.0
	rot_slider.custom_minimum_size = Vector2(0, 44)
	rot_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rot_slider.value_changed.connect(func(v): _call("rot_changed", v))
	row1.add_child(rot_slider)

	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 10)
	page.add_child(row2)
	scale_label = Label.new()
	scale_label.text = "Skala: 1.0x"
	scale_label.custom_minimum_size = Vector2(110, 0)
	scale_label.add_theme_font_size_override("font_size", 18)
	row2.add_child(scale_label)
	scale_slider = HSlider.new()
	scale_slider.min_value = 0.3
	scale_slider.max_value = 3.0
	scale_slider.step = 0.05
	scale_slider.value = 1.0
	scale_slider.custom_minimum_size = Vector2(0, 44)
	scale_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scale_slider.value_changed.connect(func(v): _call("scale_changed", v))
	row2.add_child(scale_slider)

	var hint := Label.new()
	hint.text = "Tap tanah = bikin calon • geser (tahan drag) • OK simpan • tombol ↶ Reverse: ambil aksi terakhir"
	hint.add_theme_font_size_override("font_size", 15)
	hint.modulate = Color(1, 1, 1, 0.65)
	page.add_child(hint)
	return page

## Halaman TERRAIN: jenis tile + tombol putar + level bukit +/-
func _build_page_terrain(root: Control) -> Control:
	var page := VBoxContainer.new()
	page.set_anchors_preset(Control.PRESET_FULL_RECT)
	page.add_theme_constant_override("separation", 8)
	root.add_child(page)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	page.add_child(row)
	for spec in [[0, "Datar"], [1, "Miring"], [2, "Sudut"]]:
		var b := _make_button(spec[1], Color(0.30, 0.40, 0.30), Color(0.10, 0.12, 0.10))
		b.custom_minimum_size = Vector2(0, MIN_TOUCH)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var item: int = spec[0]
		b.pressed.connect(func(): _call("set_tile", item))
		row.add_child(b)
		tile_buttons[item] = b

	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 8)
	page.add_child(row2)
	rotate_btn = _make_button("Putar: 0°", Color(0.34, 0.30, 0.42), Color(0.11, 0.10, 0.14))
	rotate_btn.custom_minimum_size = Vector2(0, MIN_TOUCH)
	rotate_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rotate_btn.pressed.connect(func(): _call("rotate_tile"))
	row2.add_child(rotate_btn)
	var bminus := _make_button("Lv -", Color(0.30, 0.34, 0.44), Color(0.10, 0.11, 0.14))
	bminus.custom_minimum_size = Vector2(88, MIN_TOUCH)
	bminus.pressed.connect(func(): _call("level_delta", -1))
	row2.add_child(bminus)
	level_label = Label.new()
	level_label.text = "Lv 0"
	level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	level_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	level_label.custom_minimum_size = Vector2(72, MIN_TOUCH)
	level_label.add_theme_font_size_override("font_size", 20)
	row2.add_child(level_label)
	var bplus := _make_button("Lv +", Color(0.30, 0.34, 0.44), Color(0.10, 0.11, 0.14))
	bplus.custom_minimum_size = Vector2(88, MIN_TOUCH)
	bplus.pressed.connect(func(): _call("level_delta", 1))
	row2.add_child(bplus)

	var hint := Label.new()
	hint.text = "Tile modular (bukan free-sculpt): tap grid tanah = pasang tile"
	hint.add_theme_font_size_override("font_size", 15)
	hint.modulate = Color(1, 1, 1, 0.65)
	page.add_child(hint)
	return page

## Halaman JALAN: lebar jalan + Selesai (kunci curve) + batalkan draft
func _build_page_road(root: Control) -> Control:
	var page := VBoxContainer.new()
	page.set_anchors_preset(Control.PRESET_FULL_RECT)
	page.add_theme_constant_override("separation", 8)
	root.add_child(page)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	page.add_child(row)
	width_label = Label.new()
	width_label.text = "Lebar: 3.0 m"
	width_label.custom_minimum_size = Vector2(130, 0)
	width_label.add_theme_font_size_override("font_size", 18)
	row.add_child(width_label)
	width_slider = HSlider.new()
	width_slider.min_value = 1.5
	width_slider.max_value = 8.0
	width_slider.step = 0.25
	width_slider.value = 3.0
	width_slider.custom_minimum_size = Vector2(0, 44)
	width_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	width_slider.value_changed.connect(func(v): _call("width_changed", v))
	row.add_child(width_slider)

	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 8)
	page.add_child(row2)
	var bfin := _make_button("Selesai & Kunci", Color(0.32, 0.44, 0.30), Color(0.10, 0.14, 0.09))
	bfin.custom_minimum_size = Vector2(0, MIN_TOUCH)
	bfin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bfin.pressed.connect(func(): _call("finish_road"))
	row2.add_child(bfin)
	var bcancel := _make_button("Batal Draft", Color(0.44, 0.30, 0.26), Color(0.14, 0.10, 0.08))
	bcancel.custom_minimum_size = Vector2(0, MIN_TOUCH)
	bcancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bcancel.pressed.connect(func(): _call("cancel_road"))
	row2.add_child(bcancel)

	var hint := Label.new()
	hint.text = "Tiap tap tanah = titik curve baru (kelokan OTOMATIS mulus) • rumput dekat jalan ikut bersih saat dikunci"
	hint.add_theme_font_size_override("font_size", 15)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.modulate = Color(1, 1, 1, 0.65)
	page.add_child(hint)
	return page

## Halaman HAPUS: petunjuk + tombol Hapus SEMUA (2x tap konfirmasi)
func _build_page_delete(root: Control) -> Control:
	var page := VBoxContainer.new()
	page.set_anchors_preset(Control.PRESET_FULL_RECT)
	page.add_theme_constant_override("separation", 8)
	root.add_child(page)
	var hint := Label.new()
	hint.text = "Tap objek / tile / jalan di dunia untuk menghapusnya.\n(Urutan cek: objek -> tile terrain -> jalan)"
	hint.add_theme_font_size_override("font_size", 17)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(hint)
	var bclear := _make_button("Hapus SEMUA bangunan", Color(0.52, 0.24, 0.20), Color(0.18, 0.07, 0.05))
	bclear.custom_minimum_size = Vector2(0, MIN_TOUCH)
	bclear.pressed.connect(func(): _on_clear_all())
	page.add_child(bclear)
	return page

func _on_clear_all() -> void:
	if not _clear_armed:
		_clear_armed = true
		set_status("Tekan SEKALI LAGI utk hapus semua (batal bila pindah tab)")
		get_tree().create_timer(3.0).timeout.connect(func(): _clear_armed = false)
		return
	_clear_armed = false
	_call("clear_all")

## ---------- API publik yg dipakai manager ----------

func show_panel(v: bool) -> void:
	panel.visible = v
	if joy_control:
		joy_control.visible = v
	# sedikit pembeda FAB saat mode aktif
	fab.text = "TUTUP" if v else "BANGUN"

func set_submode(key: String) -> void:
	for k in pages.keys():
		pages[k].visible = (k == key)
		tab_buttons[k].modulate = Color(1.35, 1.25, 1.05) if k == key else Color(1, 1, 1)
	_clear_armed = false

func set_status(txt: String) -> void:
	status_label.text = txt
	_status_t = 4.0

func _process(delta: float) -> void:
	if _status_t > 0.0:
		_status_t -= delta
		if _status_t <= 0.0:
			status_label.text = ""

## Isi palette objek dari katalog (dipanggil manager sehabis populate()).
## SEL KOTAK persegi di-GRID (permintaan user: bentuk kisi kotak): lebar
## dihitung dr lebar layar supaya sel selulu pas ~96px persegi; sisanya
## memenuhi kolom berikutnya. Tiap sel = blok accent + label pendek.
func fill_palette(entries: Array) -> void:
	for c in palette_grid.get_children():
		c.queue_free()
	palette_buttons.clear()
	# kolom responsif: sel ~104px (sel 96 + jarak8) — layar sempit: 4 kolom.
	var vsz := get_viewport().get_visible_rect().size
	palette_grid.columns = clampi(int(floor(vsz.x / 104.0)), 4, 10)
	for e in entries:
		var b := _make_button(String(e["label"]), Color(e["tint"]) * 0.55, Color(e["tint"]) * 0.3)
		b.custom_minimum_size = Vector2(96, 96)
		b.add_theme_font_size_override("font_size", 15)
		var id: String = e["id"]
		b.pressed.connect(func(): _call("select_catalog", id))
		palette_grid.add_child(b)
		palette_buttons[id] = b

func highlight_palette(id: String) -> void:
	for k in palette_buttons.keys():
		palette_buttons[k].modulate = Color(1.45, 1.35, 1.1) if k == id else Color(1, 1, 1)

func sync_rot_scale(rot_deg: float, scale: float) -> void:
	rot_slider.value = fmod(rot_deg + 360.0, 360.0)
	scale_slider.value = clampf(scale, 0.3, 3.0)
	rot_label.text = "Putar: %d°" % int(rot_slider.value)
	scale_label.text = "Skala: %.2fx" % scale_slider.value

func set_rotate_text(rot_idx: int) -> void:
	rotate_btn.text = "Putar: %d°" % (rot_idx * 90)

func set_level_text(lv: int) -> void:
	level_label.text = "Lv %d" % lv

func set_width_text(w: float) -> void:
	width_label.text = "Lebar: %.2f m" % w

## Tampilkan/sembunyikan baris OK/BATAL calon objek (dipanggil manager).
func set_pending_visible(v: bool) -> void:
	if pending_row:
		pending_row.visible = v

## ---------- util ----------

func _make_button(txt: String, bg: Color, edge: Color) -> Button:
	var b := Button.new()
	b.text = txt
	b.focus_mode = Control.FOCUS_NONE       # game mobile: tak perlu fokus keyboard
	b.add_theme_font_size_override("font_size", 19)
	var st := StyleBoxFlat.new()
	st.bg_color = Color(bg.r, bg.g, bg.b, 0.94)
	st.border_color = edge
	st.set_border_width_all(3)
	st.corner_radius_top_left = 14
	st.corner_radius_top_right = 14
	st.corner_radius_bottom_left = 14
	st.corner_radius_bottom_right = 14
	st.content_margin_left = 12
	st.content_margin_right = 12
	st.content_margin_top = 8
	st.content_margin_bottom = 8
	b.add_theme_stylebox_override("normal", st)
	var stp := (st.duplicate() as StyleBoxFlat)
	stp.bg_color = Color(bg.r * 1.25, bg.g * 1.25, bg.b * 1.25, 0.98)
	b.add_theme_stylebox_override("pressed", stp)
	return b

func _call(name: String, a = null) -> void:
	if not cb.has(name):
		return
	if a == null:
		(cb[name] as Callable).call()
	else:
		(cb[name] as Callable).call(a)
