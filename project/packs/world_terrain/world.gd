extends Node3D
## World: PULAU DATAR ~12km bergaya sihir open-world (ronde-46, pivot balik
## dari game tank ke tema penyihir anime). Visual tanah TETAP satu bidang
## datar (PlaneMesh 1400m) yg mengikuti pemain scr visual (collider bidang
## WorldBoundaryShape3D tetap tak berujung scr FISIK — POLA SEDERHANA, bukan
## trimesh ⇒ is_on_floor() engine selalu benar) — TAPI skrg dunia scr LOGIS
## dibatasi jadi pulau (lihat island_shape.gd: garis pantai "alami" dari
## harmonik sinus, BUKAN lingkaran/kotak) dgn laut mengelilinginya, dirender
## oleh shader tanah yg SAMA (_make_ground_material, blend darat->pasir->air
## berdasar posisi dunia absolut) & pemain didorong lembut balik kalau
## melewati garis pantai (player.gd _clamp_to_island). Tiang/reruntuhan batu
## (wall_system.gd) SUDAH DIHAPUS dr spawn (permintaan user, dianggap tak
## cocok tema) — skrip lama tetap ada di repo, tak lagi dipanggil.
##
## Bag. C (permintaan pengguna): tanah rumput lebat (tekstur + tumpuk rumput
## 3D MultiMesh dekat pemain, lihat _build_grass, TAK tumbuh di laut/pasir),
## kabut "batas pandang" HANYA di kejauhan (FOG_MODE_DEPTH, lihat
## _setup_environment — dekat pemain SELALU jernih), dan dunia dikunci
## MALAM PERMANEN dgn langit berbintang + bulan (siklus siang-malam lama,
## SKY_PRESETS, & slider debug "Mode Edit" tetap dipertahankan kodenya, cuma
## tak lagi auto-berjalan — lihat _tick_daynight). Mantra andalan yang
## dipoles (bag. B) menyusul. API platform tetap lengkap agar HUD/pemain/
## game_root tidak perlu berubah.

signal gen_progress(p: float, t: String)

const Materials := preload("res://packs/shaders_materials/materials.gd")
const SKY_SHADER := preload("res://packs/shaders_materials/sky.gdshader")
const GRASS_SHADER := preload("res://packs/shaders_materials/grass_blade.gdshader")
# Build Mode (permintaan user butir 1-7): manager modular di packs/build_mode
const BUILD_MODE := preload("res://packs/build_mode/build_mode_manager.gd")
const WALL_SYSTEM := preload("res://packs/world_terrain/wall_system.gd")
const IslandShape := preload("res://packs/world_terrain/island_shape.gd")

var player: Node3D
var quality_ref
var faceted := false          # stub: tak ada world lagi untuk di-facet
var world_env: WorldEnvironment
var sun: DirectionalLight3D
var sky_mat: ShaderMaterial
# Ronde-46 bag. C dulu: dunia dikunci MALAM. RONDE INI (permintaan user:
# "ubah jadi sore hari dengan suasana santai") — dikunci SORE (~17:12,
# golden hour hangat): satu-satunya waktu yg aktif di _apply_daylight adalah
# cabang SIANG (dayf≈0.21>0.15) yg warnanya kini diset utk sore keemasan
# (matahari rendah hangat, langit krim-emas, bintang mati), siklus jalan
# waktu tetap DIMATIKAN (lihat _tick_daynight). Masih pakai kurva
# sin((t-6)/12*PI) yg sama, jd kalau besok mau balik malam/siang tinggal
# ganti nilai angka ini saja.
var time_of_day := 17.2

var _root: Node
var _ground: MeshInstance3D   # bidang raksasa yang menyentak mengikuti pemain
var _ground_mat: ShaderMaterial  # material tanah+air (dipakai set param refleksi/matahari-air)
# --- REFLEKSI PLANAR DI AIR: kode RIG masih ADA di bawah (_setup/_tick)
# tapi DIMATIKAN lewat toggle ini. Alasan (laporan user ronde ini, hasil
# test di HP: "air keliatan nya gk ada perubahan malah kek jadi berat") —
# dua kekurangan sekaligus: (1) pantulannya nyaris tak terlihat (campuran
# fresnel sudut pandang atas terlalu halus), (2) tapi biayanya NYATA:
# bidang tanah+air raksasa + environment di-render DUA KALI tiap 3 frame
# ke SubViewport (perf drop terasa di HP mid-range; user minta balik ke
# jalur 60fps smooth). Penggantinya: air stylized mobile (buih pantai
# bergerak, fresnel arah langit, serapan Beer-ish, riak gelombang pemain,
# kaustik diperkuat) di shader tanah — NOL pass render tambahan. Kalau
# besok mau dicoba lagi tinggal ubah const ini = true; shader sudah siap
# pasang (reflect_strength/refl_tex diparametrikan dari _setup di bawah).
const WATER_REFLECTION := false
# RUMPUT PROSEDURAL (dibalikin ke awal — permintaan user ronde ini:
# "buat rumput nya balikin lagi ke awal"): petak chunk-streaming GrassChunk_*
# + blade tuft wind FBM hidup lagi persis versi matang sebelumnya (lihat
# blok _build_grass dkk di bawah). Pernah sempat OFF satu ronde (user minta
# rumput manual via katalog); KEDUA jalur kini tersedia permanen: rumput
# prosedural MENYALA di sini, & rumput manual tetap bisa ditanam tambahan
# lewat katalog Build Mode kapan saja. Flag ini juga versi-aman: CI fase
# 1e membaca `grass_enabled` & menolak flip diam-diam.
const PROC_GRASS := true
## Bendera runtime dibaca probe CI (const tak bisa di-get() dari instance).
var grass_enabled: bool = PROC_GRASS
var _refl_vp: SubViewport
var _refl_cam: Camera3D
var _refl_ground: MeshInstance3D
var _refl_tick := 0
var wall_system: Node3D       # reruntuhan/dinding batu destructible — rintangan & pemandangan dunia
const GROUND_SIZE := 1400.0   # ~1km pulau + tepi laut (ronde ini: perkecil dunia)
var interactables := []       # kosong; dipertahankan utk kompatibilitas API

# ---------------- rumput lebat di sekitar pemain (ronde-46 bag. C) ----------------
# RONDE INI: perombakan TOTAL cara rumput ditempatkan, sesudah user
# menunjukkan referensi https://github.com/IcterusGames/SimpleGrassTextured
# dan komplain "kok malah jadi ngikutin" thd pendekatan lama. VET dulu (bukan
# instal utuh — addon itu berbasis EDITOR (dilukis manual node
# SimpleGrassTextured di scene, butuh Godot editor GUI yg TAK ADA di jalur
# generate_async() prosedural kita) & interaksinya pakai SubViewport render-
# to-texture yg berat, tak relevan/tak cocok dipasang mentah2 di sini) —
# yg DIPORT cuma INTI ARSITEKTURnya: rumput ditaruh di POSISI DUNIA NYATA
# yg TETAP (bukan "dibungkus"/wrap muter2 spt versi lama), lalu di-STREAM
# per PETAK (chunk) yg dimuat/dibongkar berdasar jarak ke pemain waktu
# jalan — persis maksud user "buat setiap jalan ngerender rumput nya".
#
# Riwayat kenapa versi SEBELUMNYA (wrap around player, sudah dihapus)
# bermasalah: petak rumput lebat SELALU berukuran & berpusat PERSIS di
# pemain kemanapun dia jalan (posisi tiap helai "dibungkus" modulo relatif
# ke pemain di GPU) — scr visual ini kelihatan spt gelembung/aura rumput yg
# ikut nempel & meluncur bareng pemain, BUKAN rumput yg benar2 tumbuh diam
# di tanahnya (laporan user paling akhir: "kok malah jadi ngikutin").
#
# Pendekatan BARU (chunk streaming, lihat _build_grass_chunk/_update_grass_
# chunks): dunia dibagi petak GRASS_CHUNK_SIZE meter; petak dlm radius
# GRASS_RENDER_RADIUS_CHUNKS dari pemain dibangun (RNG di-seed dari
# KOORDINAT PETAK itu sendiri -> layout rumput di petak yg sama SELALU
# identik tiap kali dimuat ulang, tak "mengocok ulang" & tak nge-pop beda
# tiap kunjungan), petak yg sudah jauh (lewat GRASS_UNLOAD_RADIUS_CHUNKS,
# sengaja lebih besar dr radius render biar tak "kedip" bolak-balik pas
# pemain persis di tepi) dibongkar. Max GRASS_CHUNK_BUILD_PER_FRAME petak
# baru dibangun tiap frame (bukan sekaligus semua) biar jalan diagonal yg
# memasuki byk petak baru sekaligus tak bikin hentakan frame. Posisi tiap
# helai skrg BENERAN tetap di dunia (node tiap chunk ditaruh di titik
# tengah petaknya, TAK PERNAH digeser lagi) — grass_blade.gdshader jadi
# jauh lbh sederhana (tak ada lagi logika wrap/modulo), cuma nyisain fade
## jarak biasa (fadeout_envelope design user, jarak KE KAMERA) supaya batas radius-muat
# tak kelihatan nge-pop, PERSIS spt referensi (optimization_by_distance +
# smoothstep di grass.gdshaderinc mrk) walau implementasi detailnya beda.
const GRASS_CHUNK_SIZE := 22.0
# PERMINTAAN USER (ronde ini, LANJUTAN — msh dibilang "kurang tebel" stlh
# dinaikkan ke 4200/~8.7 rumpun/m² sblmnya): dinaikkan lagi ke ~11.2/m².
# Kali ini kenaikan jumlah RUMPUN sengaja tak digandakan sebesar putaran
# sblmnya krn tiap rumpun SKRG jauh lbh berisi (5 helai jd 9, lihat
# _build_grass_blade_mesh) — total SEGITIGA per petak naik ~2.3x dr putaran
# lalu (bkn cuma linear ikut jumlah instance), jd kepadatan visual naik
# banyak tanpa membebani GPU sebanyak kalau instance-count-nya sendiri yg
# digandakan sebesar itu. TETAP perlu dicek FPS di HP asli stlh ini —
# kalau turun terlalu jauh, turunkan angka ini dulu (bkn detail helai).
const GRASS_CHUNK_INSTANCES := 5400
const GRASS_RENDER_RADIUS_CHUNKS := 2   # persegi (2*r+1)^2 petak selalu berusaha dimuat
const GRASS_UNLOAD_RADIUS_CHUNKS := 3   # histeresis: dibongkar hanya kalau LEBIH jauh dr ini
# OPTIMASI (permintaan user: "optimalisasi biar smooth tapi tidak mengurangi
# visual") — GRASS_CHUNK_BUILD_PER_FRAME skrg cuma ngatur brp NODE petak
# baru boleh dibuat tiap frame (murah: cuma alokasi MultiMesh kosong, tak
# lagi ngisi ribuan instance-nya di frame yg sama). Pengisian instance
# sesungguhnya (yg MAHAL — dulu sampai 5400 pemanggilan set_instance_*
# per petak, dobel kalau 2 petak kebangun bareng = ~10800 panggilan native
# dlm 1 frame, itu biang hentakan/patah2 pas jalan masuk area baru) skrg
# DICICIL lewat GRASS_FILL_INSTANCES_PER_FRAME instance/frame LINTAS semua
# petak yg lg dibangun (lihat _grass_building/_process_grass_fill_budget) —
# jumlah TOTAL rumput yg akhirnya tampil TETAP SAMA PERSIS (tak ada rumput
# dikurangi), cuma proses ngisinya disebar bbrp frame drpd numpuk di 1
# frame. Bonus: rumpun kelihatan "tumbuh" bertahap saat petak baru
# dimuat—bukan nge-pop instan—yg jg terasa lebih halus dr sisi visual.
const GRASS_CHUNK_BUILD_PER_FRAME := 3   # brp petak baru boleh MULAI dibangun /frame
const GRASS_FILL_INSTANCES_PER_FRAME := 1800  # brp instance boleh DIISI /frame (semua petak digabung)
var _grass_mesh: ArrayMesh                # 1 mesh tuft dipakai bersama semua chunk
var _grass_mat: ShaderMaterial            # 1 material dipakai bersama semua chunk grass (tekstur digambar runtime)
var _grass_chunks := {}                   # Vector2i koordinat petak -> MultiMeshInstance3D
var _grass_pending: Array = []            # antrean koordinat petak menunggu MULAI dibangun
var _grass_building := {}                 # Vector2i -> {"rng":RandomNumberGenerator,"filled":int}: petak yg node-nya sudah ada tapi msh dicicil isi instance-nya
var _grass_last_chunk := Vector2i(9999999, 9999999)  # paksa update pertama
var _grass_density_frac := 1.0            # dari apply_quality() grass_density, diterapkan ke chunk baru & yg sudah ada


func _ready() -> void:
	name = "World"

func _wtrace(msg: String) -> void:
	if _root and _root.has_method("_trace"):
		_root._trace(msg)

func _report(p: float, t: String) -> void:
	print("[gen] %d%% %s" % [int(p * 100), t])
	gen_progress.emit(clampf(p, 0.0, 1.0), t)

# ---------------- boot ----------------

func generate_async(p_root: Node) -> void:
	_root = p_root
	_report(0.0, "Menyiapkan langit…")
	_setup_environment()
	await get_tree().process_frame
	_report(0.5, "Membentangkan tanah datar…")
	_make_flat_ground()
	await get_tree().process_frame
	_report(0.8, "Menegakkan dinding/bunker medan tempur…")
	# DIHAPUS (permintaan user, screenshot: "itu tiang hapus") — tiang/
	# reruntuhan batu kotak dr wall_system.gd dianggap tak cocok scr visual
	# dgn tema dunia sihir/alam yg sedang dibangun. Skrip wall_system.gd &
	# wall.gd SENGAJA TAK dihapus dr repo (cuma tak lagi di-spawn di sini)
	# supaya gampang dikembalikan/dipakai ulang kalau suatu saat perlu
	# rintangan destructible lagi.
	wall_system = null
	await get_tree().process_frame
	# BUILD MODE (permintaan user): dibuat di AKIR generate supaya semua
	# subsistem (catalog/placer/terrain/road + UI) siap sesudah tanah/
	# rumput ada. player/hud BELUM ada di fase ini — manager mereferensinya
	# LAZY tiap toggle (world.player di-set kemudian lewat set_player, hud
	# lewat root.hud), seluruh gestur no-op aman di probe tanpa pemain.
	_setup_build_mode()
	await get_tree().process_frame
	_report(1.0, "Medan tempur siap")

## Instantiate BuildModeManager (packs/build_mode/) sebagai anak world.
## DUCK-TYPED (Node): class_name BuildModeManager ada di pack LAIN —
## export per-pack bisa compile terpisah, jadi jangan bergantung pd kelas
## globalnya saat parse; cukup cek has_method saat dipakai.
var build_mode: Node = null

func _setup_build_mode() -> void:
	if build_mode != null:
		return
	var bm = BUILD_MODE.new()
	bm.name = "BuildMode"
	add_child(bm)
	if bm.has_method("setup"):
		bm.setup(self, _root)
	build_mode = bm

## Bidang datar tak berbatas: SATU collider WorldBoundary (bidang y=0, normal
## atas) — tak ada tepi, tak ada trimesh, is_on_floor() engine selalu konstan.
## Visual: PlaneMesh 1400m yang menyentak digeser bersama pemain; pola tanah
## memakai UV RUANG-DUNIA sehingga gerakan tampak mulus.
func _make_flat_ground() -> void:
	_ground = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(GROUND_SIZE, GROUND_SIZE)
	pm.material = _make_ground_material()
	_ground_mat = pm.material  # disimpan: _apply_daylight & refleksi nanti
	# arah MENUJU matahari utk kilaun air (bukan default guess uniform);
	# rotation sun sdh final-rkunci sore di sini (_apply_daylight sdh jalan)
	if sun:
		_ground_mat.set_shader_parameter("water_sun_dir", sun.global_transform.basis.z.normalized())
	_ground.mesh = pm
	add_child(_ground)
	_setup_water_reflection()
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	col.shape = WorldBoundaryShape3D.new()  # bidang tak terbatas y=0, normal +Y
	body.add_child(col)
	add_child(body)
	if PROC_GRASS:
		_build_grass()   # rumput prosedural balik ke awal (permintaan user)

## Rig refleksi planar (dipanggil sekali dari _make_flat_ground). Bidang
## air DUNIA sama dgn darat (bidang y=0), jd cermin yg tepat = bidang y=0
## itu sendiri: kamera utama dicerminkan (pos.y->-y, basis M·B·M) & meng-
## gambar BIDANG TIRUAN yg sama (mesh PlaneMesh dibagi, -0.02 di bawah spy
## kamera utama tak render-ganda/z-fighting) ke SubViewport 384x216 lalu
## disampel shader air via SCREEN_UV terbalik (ronde ini, tier-menengah).
func _setup_water_reflection() -> void:
	if not WATER_REFLECTION or _refl_vp != null or _ground == null:
		return
	_refl_vp = SubViewport.new()
	_refl_vp.size = Vector2i(384, 216)
	_refl_vp.msaa_3d = Viewport.MSAA_DISABLED
	# world_3d default DIBAGI dgn scene utama (own_3d=false) -> matahari,
	# langit & bidang tanah yg sama tampak dr kamera cermin tanpa duplikasi.
	_refl_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_refl_cam = Camera3D.new()
	# Kamera cermin HANYA menggambar layer-2 (bidang tiruan) — pohon/rumput/
	# pemain ada di layer-1 & sengaja TIDAK dipantulkan (biaya mobile; toh
	# yg tampak dominan di pantulan air = tanah/langit yg mana hamparan).
	# Tanpa layer-2 geometri di viewport mungil ini, ruangan kosong (sky
	# environment tetap ikut dirender -> pantulan LANGIT tetap ada! bagus).
	_refl_cam.cull_mask = 2
	_refl_cam.far = 240.0   # cukup utk tanah+langit dekat kejauhan
	_refl_vp.add_child(_refl_cam)
	add_child(_refl_vp)
	_refl_ground = MeshInstance3D.new()
	_refl_ground.mesh = _ground.mesh
	_refl_ground.position.y = -0.02
	_refl_ground.layers = 2
	add_child(_refl_ground)
	if _ground_mat:
		_ground_mat.set_shader_parameter("reflect_tex", _refl_vp.get_texture())
		_ground_mat.set_shader_parameter("reflect_strength", 0.38)

## Dipanggil dari _process tiap frame: cerminkan kamera aktif & minta
## viewport update 1-dr-3 frame (hemat; air beriak tak perlu 60fps).
func _tick_water_reflection() -> void:
	if not WATER_REFLECTION or _refl_cam == null:
		return
	var mc := get_viewport().get_camera_3d()
	if mc == null:
		return
	_refl_tick += 1
	if _refl_tick % 3 != 0:
		return
	var mt := mc.global_transform
	# cermin thd bidang y=0: basis M·B·M (M=skala(1,-1,1); determinan ttp
	# +1 dgn konjugasi ini, jd tetap rotasi murni — winding OK, & dgn
	# cull_disabled di shader tanah sisi bawah jg tergambar benar), pos
	# y negatifkan.
	var p := mt.origin
	var m := Basis.from_scale(Vector3(1.0, -1.0, 1.0))
	var nb : Basis = m * mt.basis * m
	_refl_cam.global_transform = Transform3D(nb.orthonormalized(), Vector3(p.x, -p.y, p.z))
	_refl_cam.fov = mc.fov
	_refl_cam.near = mc.near
	if _refl_ground and _ground:
		_refl_ground.position.x = _ground.position.x
		_refl_ground.position.z = _ground.position.z
	_refl_vp.render_target_update_mode = SubViewport.UPDATE_ONCE

## Lantai tanah (ronde-46 bag. C — ganti dari grid biru-putih ala blueprint
## sebelumnya). PERMINTAAN USER (ronde ini): warna diganti HIJAU TUA POLOS
## (dulu tekstur foto rumput + noise petak dua-corak, dianggap "ramai"/
## bersaing visual dgn tuft 3D di atasnya skrg yg sudah jauh lebih tebal) —
## cuma warna solid senada, diberi shading toon 2-tingkat spt gaya seluruh
## game, rumput 3D chunk streaming yg kasih semua detail/tekstur visualnya.
##
## BAG. C LANJUTAN (permintaan user: "pulau 12km, bukan bulat bukan kotak,
## dikelilingi laut"): shader yg SAMA ini (mesh tanah tetap SATU bidang
## datar 1600m yg ikut pemain, TAK PERLU mesh laut terpisah!) sekarang JUGA
## menggambar laut — berdasar water_factor(world_x,world_z) dari
## island_shape.gd (rumus disalin manual ke GLSL di sini, lihat komentar
## "IslandShape" di island_shape.gd kalau perlu ubah radius/garis pantai).
## Krn baik darat maupun laut sama2 rata (y=0), satu bidang yg sama cukup
## utk keduanya, tinggal warnanya yg beda tergantung posisi dunia absolut.
##
## FIX BUG (laporan user: "tanah warna hitam bukan hijau"): ground_color
## sblmnya (0.05,0.16,0.06) HAMPIR SAMA GELAP dgn warna akar di
## grass_blade.gdshader, ditumpuk shadow_tint + ambient malam -> di bawah
## ambang persepsi warna (kelihatan nyaris hitam polos, bukan salah render).
## Sudah dinaikkan (lihat nilai uniform ground_color di bawah).
##
## SELARAS SATU WARNA (permintaan user ronde ini: "buat rumput dan tanah
## satu warna hijau smooth"): ground_color kini SAMA-keluarga dgn warna
## akar helai rumput di grass_blade.gdshader (base_color) & gradasi ujung
## rumput dipendekkan jadi halus (lihat komentar di shader rumput) — tanah
## polos + helai 3D melebur jadi satu hamparan hijau mulus (bukan lagi
## helai kuning-terang di atas tanah gelap), senada suasana sore hangat.
##
## DANAU+SUNGAI DIHAPUS (ronde ini, permintaan user): air HANYA di tepi
## pulau; any_water_factor() kini identik water_factor() (pantai laut),
## salinan rumusnya tetap wajib disamakan manual dgn island_shape.gd.
func _make_ground_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	var sh := Shader.new()

	sh.code = """
shader_type spatial;
// RONDE INI: cull_disabled — HARUS, supaya bidang ini tetap KELIHATAN dari
// kamera cermin refleksi air yg berada DI BAWAH bidang (permintaan user:
// pasang planar-reflection di air, saran tier-menengah). Tanah dilihat
// kamera utama dari atas saja, jd double-sided tak menambah beban nyata.
render_mode cull_disabled, depth_draw_opaque;
// PERMINTAAN USER (ronde ini): "buat tanah jadi hijau lagi" + "tanah &
// rumput satu warna, kayak cuma liat ujung2 rumput doang" → ground_color
// kini HIJAU PASTEL yg SAMA PERSIS dgn base_color akar di grass_blade
// (dasar rumput = tanah; yg terbaca cuma ujung2 helai lbh terang di atas).
// Lantai shading jg dinaikkan (keluhan "pencahayaannya biar lebih terlihat
// rerumputannya"): shadow 0.50 -> 0.66, mid 0.82 -> 0.90, krn dgn sore
// elevasi rendah (sun 10-13°, dot(N,L) kecil) floor lama bikin ladang
// terbaca gelap-mossman sekarang harus tetap cerah hangat.
// RONDE INI (style Malidos penuh — permintaan user): diringankan mendekati
// bottom_color rumput merk (0.416,0.616,0.224) biar peleburan pangkal
// rumput->darat tetap halus (dl ground ini diset 0.285/0.450/0.260 "satu
// keluarga" dgn palet gelap ASekai lama).
uniform vec3 ground_color : source_color = vec3(0.345, 0.530, 0.245);
uniform float shadow_tint : hint_range(0.0, 1.0) = 0.66;
uniform float mid_tint : hint_range(0.0, 1.0) = 0.90;
// --- Pulau/laut (IslandShape, disalin manual dr island_shape.gd) ---
uniform vec3 sand_color : source_color = vec3(0.62, 0.56, 0.38);
uniform vec3 water_shallow : source_color = vec3(0.10, 0.28, 0.34);
uniform vec3 water_deep : source_color = vec3(0.03, 0.10, 0.16);
// --- TIER-MENENGAH (disetujui user ronde ini): refleksi planar air ---
// Viewport kamera cermin (world.gd _setup_water_reflection) di-pass ke
// sampler ini; reflect_strength 0 -> shader SKIP sampling (aman saat
// viewport belum siap / fitur dimatikan lewat WATER_REFLECTION=false).
uniform sampler2D reflect_tex : filter_linear, repeat_disable;
uniform float reflect_strength : hint_range(0.0, 1.0) = 0.0;
// --- TIER-MENENGAH: kilaun matahari di air (fake sun-glare) + pasir basah
// + kilau kaustik dangkal --- arah MENUJU matahari di-set ulang tiap
// _apply_daylight (sun.global_basis.z), default = sore 13deg di barat.
uniform vec3 water_sun_dir = vec3(-0.628, 0.225, -0.362);
uniform float sun_glint : hint_range(0.0, 2.0) = 0.85;
// --- adaptasi shader air reff user (ronde ini): warna pantulan LANGIT
// sore krim utk freshnel (wajah air menawan tanpa pass render ke-2), plus
// posisi pemain utk riak gelombang (player waves) — diset tiap frame dr
// world.gd _process spt player_pos rumput. ---
uniform vec3 sky_reflect_color : source_color = vec3(0.88, 0.82, 0.68);
uniform vec2 player_water_pos = vec2(0.0, 0.0);
varying vec3 wp;

float gh(vec2 p) { return fract(sin(dot(p, vec2(41.3, 289.1))) * 43758.5453); }
float gnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float a = gh(i);
	float b = gh(i + vec2(1.0, 0.0));
	float c = gh(i + vec2(0.0, 1.0));
	float d = gh(i + vec2(1.0, 1.0));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// island_shape.gd IslandShape.radius_at() -- HARUS SAMA PERSIS (lihat
// komentar di island_shape.gd kalau ubah salah satu, ubah keduanya).
const float ISLAND_RADIUS = 460.0;
const float BEACH_WIDTH = 55.0;
float island_radius_at(float theta) {
	return ISLAND_RADIUS * (1.0
		+ 0.20 * sin(theta * 3.0 + 1.3)
		+ 0.11 * sin(theta * 7.0 + 0.7)
		+ 0.06 * sin(theta * 11.0 + 2.4));
}
// 0=darat, 1=laut penuh (dipita BEACH_WIDTH), spt IslandShape.water_factor()
float water_factor(vec2 p) {
	float theta = atan(p.y, p.x);
	float r = length(p);
	float coast = island_radius_at(theta);
	return clamp((r - (coast - BEACH_WIDTH)) / BEACH_WIDTH, 0.0, 1.0);
}

// RONDE INI (permintaan user: "hilangin juga danau nya biar bagian air
// hanya ada disisi pulau"): DANAU & SUNGAI DIHILANGKAN — dirumuskan di
// sini tdk ada kode lain selain garis pantai laut; any_water_factor()
// kini identik water_factor() (dipakai menyatu nama tuignya).
float any_water_factor(vec2 p) {
	return water_factor(p);
}

void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }

void fragment() {
	vec3 land_col = ground_color;

	float wf = any_water_factor(wp.xz);

	// darat -> pasir -> air, transisi mulus di pita BEACH_WIDTH
	vec3 col = mix(land_col, sand_color, smoothstep(0.0, 0.5, wf));

	// --- PASIR BASAH (tier-menengah): pita gelap+dingin tipis persis di
	// garis air (sebelum benang air penuh) — ciri pantai sungguhan ---
	float wet = smoothstep(0.02, 0.14, wf) * (1.0 - smoothstep(0.24, 0.44, wf));
	float ripple = 0.0;

	// ================= AIR STYLIZED MOBILE =================
	// RONDE INI: adaptasi shader air "realistic/stylized water" yg dikirim
	// user (SSR + caustics + player waves + Beer absorption) — TAPI BUKAN
	// dipasang mentah: versi aslinya punya loop SSR ~100x sample tekstur
	// per piksel air + screen/depth texture fullscreen copy (JAUH terlalu
	// berat utk HP mid-range; user sendiri minta balik 60fps smooth).
	// Yang DIAMBIL semangatnya: buih tepi bergerak, fresnel langit,
	// serapan kedalaman, gelombang dari pemain. Semua noise tetap 2-oktaf
	// murah & SELURUH blok dibungkus cabang (wf>0.26) supaya piksel darat
	// (mayoritas layar saat main) TAK bayar ongkos airnya sama sekali.
	if (wf > 0.26) {
		// riak air: 2 lapis noise digeser TIME (reff pake normal-map tekstur;
		// di sini cukup noise procedural — NOL memory tekstur)
		ripple = gnoise(wp.xz * 0.05 + vec2(TIME * 0.06, TIME * 0.04))
			+ gnoise(wp.xz * 0.13 - vec2(TIME * 0.03, TIME * 0.05)) * 0.5;
		float rx = gnoise(wp.xz * 0.09 + vec2(TIME * 0.10, 0.0)) - 0.5;
		float rz = gnoise(wp.xz * 0.09 + vec2(0.0, TIME * 0.11)) - 0.5;
		vec3 vdir = normalize(CAMERA_POSITION_WORLD - wp);
		float wm = smoothstep(0.50, 0.90, wf);

		// warna air dgn serapan gaya Beer (reff: absorption_color/Beer's
		// law dgn depth-texture; di dunia datar ini proxy kedalaman = wf —
		// makin jauh dari bibir air makin dalam; dangkal tembus pasir)
		float depthish = smoothstep(0.40, 1.0, wf);
		vec3 water_col = mix(mix(sand_color * 0.78, water_shallow * 1.30, 0.45),
			mix(water_shallow * 1.30, water_deep, depthish),
			smoothstep(0.34, 0.52, wf));
		water_col += ripple * 0.035;
		col = mix(col, water_col, smoothstep(0.35, 1.0, wf));

		// --- BUIH TEPi bergerak (reff: edge ripples via depth-texture; di
		// sini pita wf + garis sinus maju ke darat + putus-putus noise) ---
		float foam_band = smoothstep(0.30, 0.40, wf) * (1.0 - smoothstep(0.44, 0.62, wf));
		float fw = sin(wf * 42.0 - TIME * 2.1) * 0.5 + 0.5;
		float foam = smoothstep(0.45, 0.85, gnoise(wp.xz * 0.42 + vec2(TIME * 0.13, -TIME * 0.10)) * 0.75 + fw * 0.35);
		col = mix(col, vec3(0.94, 0.97, 0.95), clamp(foam_band * foam * 0.85, 0.0, 1.0));

		// --- FRESNEL: mendatar -> memantulkan langit sore krim (pengganti
		// pantulan planar yg kemarin tak kentara & berat, plus SSR reff yg
		// terlalu mahal — rasa "air cermin" tetap tercapai lewat tint ini
		// + kilau matahari di bawah) ---
		float fres = pow(1.0 - clamp(dot(vdir, vec3(0.0, 1.0, 0.0)), 0.0, 1.0), 3.0);
		col = mix(col, sky_reflect_color, clamp(fres * wm * 0.65, 0.0, 1.0));

		// --- KAUSTIK DANGKAL murah (diperkuat 0.50 -> 0.85: reff punya
		// noise opensimplex2 turunan, kita tetap gnoise 2 lapis tapi sengaja
		// dibikin lebih cerah supaya TERLIHAT di layar kecil HP) ---
		float c1 = gnoise(wp.xz * 0.30 + vec2(TIME * 0.11, -TIME * 0.08));
		float c2 = gnoise(wp.xz * 0.30 - vec2(TIME * 0.09,  TIME * 0.10));
		float caust = pow(clamp(c1 * c2 * 3.2 - 1.05, 0.0, 1.0), 4.0);
		float shall = smoothstep(0.40, 0.55, wf) * (1.0 - smoothstep(0.60, 0.90, wf));
		col += vec3(0.82, 0.92, 0.82) * caust * shall * 0.85;

		// --- KILAUN MATAHARI di permukaan air (fake spec streak; ikut
		// diperkuat krn keluhan "air keliatan nya gk ada perubahan") ---
		vec3 Rj = normalize(reflect(-vdir, vec3(0.0, 1.0, 0.0)) + vec3(rx, 0.0, rz) * 2.4);
		float glint = pow(clamp(dot(Rj, normalize(water_sun_dir)), 0.0, 1.0), 64.0)
			* (0.55 + 0.45 * gnoise(wp.xz * 0.9 + vec2(TIME * 0.35, -TIME * 0.28)));
		col += vec3(1.0, 0.85, 0.60) * glint * wm * sun_glint;

		// --- GELOMBANG PEMAIN (reff: PLAYER_WAVES) — cincin riak melebar
		// dari posisi pemain saat masuk air (laut dangkal tepi pulau);
		// posisi diset tiap frame dr world.gd _process (uniform biasa, bukan
		// global shader param spy tak perlu edit ProjectSettings) ---
		if (wm > 0.001) {
			float pd = length(wp.xz - player_water_pos);
			if (pd < 4.5) {
				float pring = pow(0.5 + 0.5 * sin(pd * 9.0 - TIME * 6.5), 5.0)
					* (1.0 - smoothstep(1.2, 4.0, pd)) * smoothstep(0.20, 0.75, pd);
				col += vec3(0.88, 0.95, 0.96) * pring * wm * 0.7;
			}
		}

		// --- REFLEKSI PLANAR (NONAKTIF: rigs dimatikan demi 60fps, lihat
		// komentar WATER_REFLECTION di world.gd; blok dipertahankan supaya
		// togglenya bisa dihidupkan lagi tanpa sentuh shader) ---
		if (reflect_strength > 0.001 && wm > 0.001) {
			vec2 suv = clamp(vec2(SCREEN_UV.x + rx * 0.06 * wm,
				(1.0 - SCREEN_UV.y) + (rx + rz) * 0.05 * wm), 0.0, 1.0);
			vec3 refl = texture(reflect_tex, suv).rgb;
			col = mix(col, refl, wm * clamp(fres * 0.75 + 0.25, 0.0, 1.0) * reflect_strength);
		}
	}

	col = mix(col, col * vec3(0.60, 0.66, 0.70), wet);

	ALBEDO = col;
	// pasir basah jg mengkilap (specular lembut), air tetap paling licin
	ROUGHNESS = mix(mix(0.95, 0.45, wet), 0.18, smoothstep(0.6, 1.0, wf));
	SPECULAR = mix(max(0.0, wet * 0.25), 0.5, smoothstep(0.6, 1.0, wf));
}

void light() {
	float l = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	float b = shadow_tint
		+ (mid_tint - shadow_tint) * smoothstep(0.15, 0.45, l)
		+ (1.0 - mid_tint) * smoothstep(0.55, 0.85, l);
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * b * ATTENUATION;
}
"""
	mat.shader = sh
	return mat

## Tumpuk rumput 3D dekat pemain (MultiMesh, 1 draw call) — bag. "lebat" dari
## permintaan user: tekstur datar saja terasa rata, tumpuk rumput kecil ini
## memberi kedalaman/volume. Setiap instance = tuft 5 helai bersilang, dgn
## goyangan angin & varian warna per-instance di grass_blade.gdshader.
## Inisialisasi sistem CHUNK STREAMING (lihat catatan arsitektur di atas):
## mesh & material dibuat SEKALI (dipakai bersama semua petak), lalu node
## petak ASAL (0,0) dibuat SEKARANG JUGA (spawn pemain persis di situ,
## (0,0,0)) tanpa perlu referensi `player` (blm tentu ada saat
## generate_async, lihat jg dev_probe/fire_attack_check.gd yg menguji world
## sendirian tanpa pemain) — isi instance-nya sendiri dicicil lewat
## _process_grass_fill_budget (lihat komentar GRASS_FILL_INSTANCES_PER_FRAME)
## shg full-terisi dlm hitungan beberapa frame pertama (bukan langsung
## sekaligus, demi smoothness — tapi tetap terasa "sudah ada dr detik
## pertama"). Petak lain menyusul otomatis begitu set_player() dipanggil &
## pemain mulai jalan.
func _build_grass() -> void:
	_grass_mesh = _build_grass_blade_mesh()
	_grass_mat = _grass_material()
	_grass_chunks.clear()
	_grass_pending.clear()
	_grass_last_chunk = Vector2i(9999999, 9999999)
	_build_grass_chunk(Vector2i.ZERO)

## Hash spasial sederhana dr koordinat petak -> seed RNG DETERMINISTIK: petak
## yg sama SELALU menghasilkan layout rumput identik tiap kali dibangun ulang
## (pemain pulang-pergi lewat petak yg sama tak akan lihat rumput "mengocok
## ulang"/beda posisi tiap kunjungan).
func _chunk_seed(coord: Vector2i) -> int:
	var h := (int(coord.x) * 73856093) ^ (int(coord.y) * 19349663) ^ 20460301
	return absi(h)

## Bangun 1 petak rumput di koordinat chunk (bukan meter) `coord` — node
## MultiMeshInstance3D-nya ditaruh TEPAT di titik tengah petak itu di dunia
## nyata & TAK PERNAH digeser lagi (beda total dr versi lama yg diam di
## titik asal terus dibungkus GPU spy IKUT pemain — itu penyebab laporan
## "kok malah jadi ngikutin"). Dipanggil lewat antrean _grass_pending
## (lihat _process/_update_grass_chunks), maks GRASS_CHUNK_BUILD_PER_FRAME
## per frame spy tak menghentak.
func _build_grass_chunk(coord: Vector2i) -> void:
	if _grass_chunks.has(coord):
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _grass_mesh
	mm.instance_count = GRASS_CHUNK_INSTANCES
	mm.visible_instance_count = 0  # belum ada instance terisi, lihat _process_grass_fill_budget
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "GrassChunk_%d_%d" % [coord.x, coord.y]
	mmi.multimesh = mm
	mmi.material_override = _grass_mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.position = Vector3((coord.x + 0.5) * GRASS_CHUNK_SIZE, 0.0, (coord.y + 0.5) * GRASS_CHUNK_SIZE)
	add_child(mmi)
	_grass_chunks[coord] = mmi
	# Node & buffer kosong sudah ada (murah) — pengisian GRASS_CHUNK_INSTANCES
	# instance sesungguhnya (mahal) dicicil lewat _grass_building, BUKAN di
	# sini lagi, biar tak menghentak frame ini (lihat catatan di const
	# GRASS_FILL_INSTANCES_PER_FRAME di atas).
	var rng := RandomNumberGenerator.new()
	rng.seed = _chunk_seed(coord)
	_grass_building[coord] = {"rng": rng, "filled": 0}

## Dipanggil TIAP FRAME (bukan cuma saat pindah petak): isi maks
## GRASS_FILL_INSTANCES_PER_FRAME instance rumput, disebar ke SEMUA petak yg
## msh dlm proses (_grass_building), petak terlama diisi duluan. RNG per
## petak sama & DILANJUTKAN (bukan diulang dr awal) tiap panggilan -> hasil
## akhirnya identik persis dgn kalau diisi sekaligus (cuma bedanya waktu),
## jadi TOTAL & KEPADATAN rumput tak berkurang sama sekali dibanding
## sebelumnya — cuma cara ngisinya yg disebar biar smooth.
func _process_grass_fill_budget() -> void:
	var budget := GRASS_FILL_INSTANCES_PER_FRAME
	var half := GRASS_CHUNK_SIZE * 0.5
	var done: Array = []
	for coord in _grass_building.keys():
		if budget <= 0:
			break
		var mmi = _grass_chunks.get(coord)
		if not is_instance_valid(mmi):
			done.append(coord)
			continue
		var mm: MultiMesh = mmi.multimesh
		var st: Dictionary = _grass_building[coord]
		var rng: RandomNumberGenerator = st["rng"]
		var filled: int = st["filled"]
		var n: int = mini(budget, GRASS_CHUNK_INSTANCES - filled)
		for j in range(n):
			var i := filled + j
			var x := rng.randf_range(-half, half)
			var z := rng.randf_range(-half, half)
			var s := rng.randf_range(0.75, 1.35)
			var blade_basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU))
			blade_basis = blade_basis.scaled(Vector3(s, s * rng.randf_range(0.8, 1.3), s))
			mm.set_instance_transform(i, Transform3D(blade_basis, Vector3(x, 0.0, z)))
			mm.set_instance_custom_data(i, Color(rng.randf(), rng.randf(), 0.0, 0.0))
		filled += n
		budget -= n
		st["filled"] = filled
		var target_visible := int(round(GRASS_CHUNK_INSTANCES * _grass_density_frac))
		mm.visible_instance_count = mini(filled, target_visible)
		if filled >= GRASS_CHUNK_INSTANCES:
			done.append(coord)
	for coord in done:
		_grass_building.erase(coord)

## Dipanggil dari _process tiap kali pemain PINDAH PETAK (bukan tiap frame —
## murah): tentukan set petak yg SEHARUSNYA aktif (persegi radius
## GRASS_RENDER_RADIUS_CHUNKS), antre-kan yg blm ada, bongkar yg sudah lewat
## GRASS_UNLOAD_RADIUS_CHUNKS (histeresis sengaja > radius render, cegah
## bongkar-pasang bolak-balik pas pemain persis di tepi petak).
func _update_grass_chunks(center: Vector2i) -> void:
	var wanted := {}
	for dx in range(-GRASS_RENDER_RADIUS_CHUNKS, GRASS_RENDER_RADIUS_CHUNKS + 1):
		for dz in range(-GRASS_RENDER_RADIUS_CHUNKS, GRASS_RENDER_RADIUS_CHUNKS + 1):
			wanted[Vector2i(center.x + dx, center.y + dz)] = true
	for coord in wanted:
		if not _grass_chunks.has(coord) and not _grass_pending.has(coord):
			_grass_pending.append(coord)
	var to_remove: Array = []
	for coord in _grass_chunks:
		if maxi(absi(coord.x - center.x), absi(coord.y - center.y)) > GRASS_UNLOAD_RADIUS_CHUNKS:
			to_remove.append(coord)
	for coord in to_remove:
		var mmi = _grass_chunks[coord]
		if is_instance_valid(mmi):
			mmi.queue_free()
		_grass_chunks.erase(coord)
		# Kalau petak ini dibongkar SEBELUM selesai dicicil isinya (pemain
		# lari lalu balik arah cepat), hentikan pengisiannya jg — node-nya
		# sudah free, lanjut ngisi cuma buang2 budget frame percuma.
		_grass_building.erase(coord)
	var still_wanted: Array = []
	for coord in _grass_pending:
		if wanted.has(coord):
			still_wanted.append(coord)
	_grass_pending = still_wanted

## Bangun maks GRASS_CHUNK_BUILD_PER_FRAME petak dari antrean tiap frame —
## sebar biaya, cegah hentakan saat lari diagonal memasuki byk petak baru.
func _process_grass_chunk_queue() -> void:
	var budget := GRASS_CHUNK_BUILD_PER_FRAME
	while budget > 0 and not _grass_pending.is_empty():
		var coord: Vector2i = _grass_pending.pop_front()
		if not _grass_chunks.has(coord):
			_build_grass_chunk(coord)
			budget -= 1

func _apply_grass_density_all() -> void:
	var target := int(round(GRASS_CHUNK_INSTANCES * _grass_density_frac))
	for coord in _grass_chunks:
		var mmi = _grass_chunks[coord]
		if is_instance_valid(mmi) and mmi.multimesh:
			# Petak yg msh dicicil isinya (_grass_building) jangan dipaksa
			# nampilin instance yg BLM terisi (msh data default kosong) —
			# batasi ke jumlah yg sudah benar2 diisi sejauh ini.
			var cap := target
			if _grass_building.has(coord):
				cap = mini(target, int(_grass_building[coord]["filled"]))
			mmi.multimesh.visible_instance_count = cap

## Mesh 1 tuft rumput (PEROMBAKAN #2 — user: "kurang tebel dan kurang
## realistis"). Versi lama: persis 5 helai simetris bintang 72° — dari atas
## keliatan spt "bunga" kaku berulang, bukan rumpun alami. Versi baru:
## 5 helai UTAMA (tinggi) + 4 helai PENGISI (lebih pendek/tipis) diselang-
## seling, dan SEMUA sudut/tinggi/lebar/titik-tumbuh di-JITTER acak (RNG
## seed TETAP supaya mesh hasilnya sama tiap build, tapi antar-helai dlm 1
## rumpun tak lagi simetri sempurna) — kesan rumpun rimbun & organik, bukan
## pola geometris berulang. Helai pengisi jg nambah "ketebalan" visual krn
## mengisi celah siluet antar helai utama tanpa nambah instance/chunk (biaya
## GPU tetap terkendali: cuma 9 segitiga/rumpun, naik dari 5, bukan per-
## instance count yg jauh lbh mahal). Warna vertex.a dipakai grass_blade.
## gdshader sbg bobot tinggi (0=akar,1=ujung). Dipakai BERSAMA semua petak.
## Blade MURNI segitiga tipis mengikuti konvensi "Grass-Shader-Example"
## karya @_Malido (CC0, adopsi keseluruhan ronde ini): Bukan kartu
## bertekstur — warna dr gradien top/bottom_color di shader. KONVENSI
## UV MERK: pada tiap blade, v=1 di AKAR & v=0 di UJUNG (1.0-UV.y di
## shader = bobot ujung: angin & dingkusan pemain menggerakkan ujung
## paling jauh, lag ujung UV.y/2.5). 9 helai/rumpun (5 primer + 4 pengisi)
## — jumlah yg teruji di dua ronde sebelunya. Mesh deterministik (seed
## tetap), dishare SEMUA chunk; keragamaan dr yaw/scaling per-instance.
func _build_grass_blade_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 88172645  # tetap & deterministik, lihat komentar di atas
	const PRIMARY_N := 5
	const FILLER_N := 4
	var total := PRIMARY_N + FILLER_N
	for i in range(total):
		var is_primary := i < PRIMARY_N
		var base_angle: float = (TAU / float(total)) * float(i) + rng.randf_range(-0.32, 0.32)
		var h: float = rng.randf_range(0.40, 0.58) if is_primary else rng.randf_range(0.20, 0.34)
		var w: float = rng.randf_range(0.075, 0.098) if is_primary else rng.randf_range(0.045, 0.064)
		var lean := rng.randf_range(0.07, 0.18)
		var base_shift := rng.randf_range(0.0, 0.055)
		var rot := Basis(Vector3.UP, base_angle)
		var origin: Vector3 = rot * Vector3(0.0, 0.0, base_shift)
		var bl: Vector3 = origin + rot * Vector3(-w * 0.5, -0.04, 0.0)
		var br: Vector3 = origin + rot * Vector3(w * 0.5, -0.04, 0.0)
		var tip: Vector3 = origin + rot * Vector3(0.0, h, lean)
		# Malidos-convention: v=1 di akar, v=0 di ujung.
		st.set_uv(Vector2(0, 1)); st.add_vertex(bl)
		st.set_uv(Vector2(1, 1)); st.add_vertex(br)
		st.set_uv(Vector2(0.5, 0)); st.add_vertex(tip)
	st.generate_normals()
	return st.commit()

## Tekstur noise Perlin-FBM runtime utk angin/warna variaasi — teknik
## @_Malido/design-1 user: gumpalan lembut besar, seamless supaya
## repeat_enable tak menampilkan sambungan.
func _make_grass_noise(freq: float, octaves: int) -> Texture2D:
	var t := NoiseTexture2D.new()
	t.width = 256
	t.height = 256
	var nl := FastNoiseLite.new()
	nl.noise_type = FastNoiseLite.TYPE_PERLIN
	nl.fractal_type = FastNoiseLite.FRACTAL_FBM
	nl.fractal_octaves = octaves
	nl.frequency = freq
	t.noise = nl
	t.seamless = true
	return t

## Material batang rumput: goyangan angin + shading toon + varian warna per-
## instance (lihat grass_blade.gdshader). cull_disabled di shader itu
## sendiri. Tak ada lagi uniform pemain — fadeout full jarak-kamera (design user).
## Material blade — parameter persis ExampleScene merk (_Malido, CC0):
## wind_direction (1,-0.7,-0.5), strength 0.23, noise_size 0.03, speed
## 0.13; konteks kolom pakai keluarga hijau tanah ASekai (ground-kawin),
## player_displacement kuat 0.94 (karakter menyibak rumput saat lari).
## Noise Perlin-FBM seamless digambar runtime (nol aset file).
func _grass_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = GRASS_SHADER
	var fade_end := (float(GRASS_RENDER_RADIUS_CHUNKS) + 0.5) * GRASS_CHUNK_SIZE
	mat.set_shader_parameter("fadeout_envelope",
		Vector2(fade_end - GRASS_CHUNK_SIZE, fade_end))
	# STYLE VISUAL MERK (permintaan user ronde ini: "pake style ini ajh") —
	# seluruh nilai dari contoh material di ExampleScene merk, termasuk
	# player_displacement_strength 0.3 (bkn 0.4 custom).
	mat.set_shader_parameter("top_color", Vector3(0.627, 0.804, 0.282))     # lime terang (~"lime grass" merk)
	mat.set_shader_parameter("bottom_color", Vector3(0.416, 0.616, 0.224))  # hijau lush rimbun
	mat.set_shader_parameter("player_displacement_strength", 0.3)
	mat.set_shader_parameter("player_displacement_size", 0.94)
	mat.set_shader_parameter("wind_direction", Vector3(1.0, -0.7, -0.5))
	mat.set_shader_parameter("wind_strength", 0.23)
	mat.set_shader_parameter("wind_noise_size", 0.03)
	mat.set_shader_parameter("wind_noise_speed", 0.13)
	mat.set_shader_parameter("wind_noise", _make_grass_noise(0.05, 3))
	return mat

## Kirim posisi pemain ke INSTANCE-UNIFORM tiap chunk yang ada (persis
## Character.gd dr ExampleScene merk: set_deferred via "instance_shader_
## parameters/player_position") — dipakai utk push-back blade ("trample")
## diskaik klase UV-ujung. Biaya: titik-titik node kecil (~max 25 chunk)
## — sangat murah dibanding per-blade trample shader lama. Dipanggil
## tiap _process oleh world (amalan murni G-ILE menurunkan gra. Merk).
func _update_grass_player_uniform() -> void:
	if not PROC_GRASS or _grass_mat == null:
		return
	var pp: Vector3 = player.global_position + Vector3(0.0, -0.1, 0.0) if player else Vector3(0.0, -5.0, 0.0)
	for c in _grass_chunks.values():
		if is_instance_valid(c):
			c.set_instance_shader_parameter("player_position", pp)

# ---------------- API kompatibel ----------------

## Tanah datar murni: lantai SELALU y=0 di mana pun (tak ketemu = tak mungkin).
func height_at(_x: float, _z: float) -> float:
	return 0.0

func find_spawn_point() -> Vector3:
	return Vector3(0, 0.25, 0)

func set_player(p: Node3D) -> void:
	player = p

func register_interactable(meta: Dictionary) -> void:
	interactables.append(meta)

func get_nearest_interactable(pos: Vector3, radius: float) -> Dictionary:
	var best := {}
	var bd := radius
	for m in interactables:
		if m.get("taken", false):
			continue
		var d: float = pos.distance_to(m["pos"])
		if d < bd:
			bd = d
			best = m
	return best

func consume_interactable(meta: Dictionary) -> void:
	meta["taken"] = true
	if meta.has("node") and is_instance_valid(meta["node"]):
		meta["node"].call_deferred("queue_free")

func apply_terrain_edit(_p: Vector3, _r: float, _a: float, _m: String) -> void:
	pass

func reset_edits() -> void:
	pass

# ---------------- pencahayaan (Slider Mode Edit tetap jalan) ----------------

const SKY_PRESETS := [
	[Color(0.30, 0.74, 0.69), Color(0.62, 0.88, 0.80)],
	[Color(0.18, 0.38, 0.52), Color(0.56, 0.86, 0.78)],
	[Color(0.18, 0.26, 0.44), Color(0.98, 0.60, 0.38)],
	[Color(0.05, 0.09, 0.16), Color(0.16, 0.20, 0.30)],
]
var _lo := {"sun": 1.0, "ambient": 1.0, "fog": 1.0, "sky": -1}

func apply_lighting(d: Dictionary) -> void:
	for kk in d:
		_lo[kk] = d[kk]
	_dl_last = -1.0
	_apply_daylight()

var _q_fog := 1.0   # pengali kabut dari preset kualitas

func apply_quality(p: Dictionary) -> void:
	_q_fog = float(p.get("fog", 1.0))
	if wall_system and wall_system.has_method("apply_quality"):
		wall_system.apply_quality(p)
	if world_env and world_env.environment:
		world_env.environment.glow_enabled = bool(p.get("glow", true))
	if sun:
		sun.shadow_enabled = bool(p.get("shadows", true))
	_grass_density_frac = clampf(float(p.get("grass_density", 1.0)), 0.0, 1.0)
	_apply_grass_density_all()
	_dl_last = -1.0
	if world_env and sun:
		_apply_daylight()

func _setup_environment() -> void:
	world_env = WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sk := Sky.new()
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = SKY_SHADER
	sk.sky_material = sky_mat
	env.sky = sk
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.52, 0.58, 0.58)
	env.ambient_light_energy = 0.60
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.95
	env.fog_enabled = true
	env.fog_light_color = Color(0.56, 0.76, 0.68)
	# Ronde-46 bag. C (permintaan pengguna): "batas pandang" berkabut HANYA
	# di kejauhan, area dekat pemain tetap jernih. Mode default Environment
	# (FOG_MODE_EXPONENTIAL) mengabur dari dekat scr bertahap — TIDAK cocok.
	# FOG_MODE_DEPTH dipakai supaya fog_depth_begin/end jadi aktif: jernih
	# total sampai fog_depth_begin meter, baru mulai menebal ke fog_depth_end.
	env.fog_mode = Environment.FOG_MODE_DEPTH
	# SORE DIADEM (ronde ini: dunia skrg terang & pulau kecil 3km+air dekat
	# spawn) — kabut dilonggarkan JAUH (dr 45/160 malam) shg pemandangan
	# garis air laut tepi pulau jelas terbaca, sisanya cuma kabut tipis kejauhan.
	env.fog_depth_begin = 70.0
	env.fog_depth_end = 340.0
	env.fog_depth_curve = 1.6
	env.fog_density = 0.0026
	env.fog_sky_affect = 0.3
	# glow lembut utk pijar sihir (permintaan user) — SETINGAN HEMAT khusus
	# mobile: radius kecil, tanpa level tinggi (post-process berat tetap no)
	# glow AKTIF lagi: bola api memakai warna HDR (>1.0) -> berpendar.
	# Preset Rendah mematikannya (QualityManager -> apply_quality "glow").
	env.glow_enabled = true
	env.glow_normalized = true
	env.glow_intensity = 0.8
	env.glow_strength = 1.0
	env.glow_bloom = 0.02
	# PERBAIKAN BUG (laporan user: rumput jadi PUTIH — screenshot): ambang
	# HDR 0.9 kelewat rendah stlh malam dibikin lbh terang (ambient/fog/sky
	# dinaikkan bbrp ronde lalu) — cakrawala yg skrg cukup terang ikut lolos
	# ambang glow & "bleed"/bocor blur ke rumput yg posisinya pas di garis
	# cakrawala layar, kelihatan spt petak putih. Dinaikkan jauh (0.9->1.35)
	# supaya HANYA yg BENAR2 HDR (bola api/ledakan, warna >1.0) yg berpendar
	# — sesuai niat awal glow ("bola api pakai warna HDR -> berpendar"),
	# bukan cahaya ambient malam yg cuma "terang", bukan "menyala".
	env.glow_hdr_threshold = 1.35
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.set("glow_levels/1", true)
	env.set("glow_levels/2", false)
	env.set("glow_levels/3", true)
	env.set("glow_levels/4", false)
	env.set("glow_levels/5", true)
	env.set("glow_levels/6", false)
	env.set("glow_levels/7", false)
	# Sedikit koreksi warna (terinspirasi rekomendasi "Instant Realistic
	# Light" — TAPI kita TIDAK pasang plugin itu apa adanya: sebagian besar
	# fiturnya, sdfgi_enabled/volumetric_fog_enabled/ssao_enabled, cuma
	# jalan di renderer Forward+, sedangkan proyek ini renderer "mobile"
	# (wajib utk export Android) — bagian2 itu diam saja alias percuma.
	# Yang diambil hanya bagian yg memang jalan+berguna di Mobile: sedikit
	# saturasi ekstra biar warna tak pucat.
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	env.adjustment_contrast = 1.03
	world_env.environment = env
	# KOREKSI (laporan user: rumput jadi PUTIH — screenshot bukti): auto-
	# exposure di atas TERNYATA TAK BERFUNGSI di renderer Mobile — dicek
	# ulang ke dokumentasi resmi Godot: "Note: Auto-exposure is only
	# supported in the Forward+ rendering method, not Mobile or
	# Compatibility." PERSIS kesalahan yg sama spt yg diperingatkan soal
	# plugin "Instant Realistic Light" (SDFGI/Volumetric Fog/SSAO), tapi
	# kali ini kejeblos sendiri. Krn tak aktif di device, ia BUKAN
	# penyebab langsung rumput putih (kemungkinan besar itu dari ambang
	# glow yg kelewat rendah, lihat glow_hdr_threshold di atas) — tapi
	# tetap dihapus krn cuma kode mati yg menyesatkan. exposure_multiplier
	# statis (bukan auto) TETAP dipakai — itu beneran jalan di Mobile.
	var cam_attr := CameraAttributesPractical.new()
	cam_attr.exposure_multiplier = 1.05
	world_env.camera_attributes = cam_attr
	add_child(world_env)

	sun = DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.90, 0.72)
	sun.light_energy = 0.68
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 70.0
	sun.shadow_opacity = 0.32
	sun.directional_shadow_blend_splits = false
	sun.shadow_bias = 0.08
	sun.rotation_degrees = Vector3(-42, -120, 0)
	add_child(sun)
	_apply_daylight()
	if quality_ref:
		quality_ref.sun = sun
	_setup_vignette()

## VIGNETE halus + layar (tier-menengah, disetujui user): tepi layar
## diredupkan perlahan konsentrasi otomatis jatuh ke tengah (pemain) —
## trik foto/animasi, murah total (1 ColorRect + tekstur gradien radial
## 256x256, nol tambahan pass post-process, di bawah layer HUD).
func _setup_vignette() -> void:
	var layer := CanvasLayer.new()
	# layer 0: di atas dunia 3D tapi tegas DI BAWAH HUD permainan (hud.gd
	# pakai layer 1) — tombol/joistik tetap tajam tak kena redup tepian.
	layer.layer = 0
	# BUG ditemukan CI probe fase-1f: ColorRect TIDAK punya properti
	# `texture` (assignment melempar SCRIPT ERROR tiap boot & vignette tak
	# pernah tampil di device). Yang punya = TextureRect.
	var cr := TextureRect.new()
	cr.set_anchors_preset(Control.PRESET_FULL_RECT)
	cr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cr.stretch_mode = TextureRect.STRETCH_SCALE
	cr.mouse_filter = Control.MOUSE_FILTER_IGNORE  # jangan sekali2 telan sentuhan
	var g := Gradient.new()
	g.set_color(0, Color(0.0, 0.0, 0.0, 0.0))
	g.set_color(1, Color(0.05, 0.03, 0.07, 0.34))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 256
	gt.height = 256
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(0.66, 0.66)   # aromanya cuma mulai jauh ke sudut
	cr.texture = gt
	layer.add_child(cr)
	add_child(layer)

const DAY_LENGTH := 420.0

func _process(delta: float) -> void:
	_tick_daynight(delta)
	_tick_water_reflection()
	# bidang visual mengikuti pemain (collider-nya sudah tak berujung)
	if player and _ground:
		_ground.position.x = player.global_position.x
		_ground.position.z = player.global_position.z
	# Rumput: chunk streaming (lihat catatan arsitektur di dekat GRASS_CHUNK_
	# SIZE) — cuma dicek ULANG petak mana yg seharusnya aktif SAAT pemain
	# betul2 PINDAH petak (bukan tiap frame, murah), tapi antrean
	# pembangunan petak baru tetap dicicil tiap frame (budget kecil) biar
	# tak menghentak. Fadeout jarak murni dr kamera (design user), tak ada lagi param tiap-frame.
	if PROC_GRASS:
		if player:
			var pcx := int(floor(player.global_position.x / GRASS_CHUNK_SIZE))
			var pcz := int(floor(player.global_position.z / GRASS_CHUNK_SIZE))
			var pchunk := Vector2i(pcx, pcz)
			if pchunk != _grass_last_chunk:
				_grass_last_chunk = pchunk
				_update_grass_chunks(pchunk)
		# instance-uniform player_position (gaya merk _Malido Character.gd):
		# disetel tiap frame utk seluruh chunk-ada supaya rumput menyibak
		# meles menginjaknya (player push-back di grass_blade.gdshader).
		_update_grass_player_uniform()
		_process_grass_chunk_queue()
		_process_grass_fill_budget()
	# Posisi pemain jg utk riak gelombang air (shader tanah, uniform
	# player_water_pos — pajangan balon gelombang kon-ver-tasi reff shader)
	if _ground_mat:
		_ground_mat.set_shader_parameter("player_water_pos", Vector2(player.global_position.x, player.global_position.z) if player else Vector2.ZERO)


func _tick_daynight(_delta: float) -> void:
	# Ronde-46 bag. C (permintaan pengguna): dunia SELALU malam sekarang —
	# siklus siang-malam otomatis DIMATIKAN, time_of_day tak lagi berjalan.
	# _apply_daylight()/SKY_PRESETS/slider "Mode Edit" TETAP dipertahankan
	# utuh (tak dihapus) — masih bisa dipakai manual lewat apply_lighting()
	# kalau suatu saat perlu dibuka lagi; hanya auto-jalannya yang berhenti.
	pass

var _dl_last := -1.0

func _apply_daylight() -> void:
	if abs(time_of_day - _dl_last) < 0.05:
		return
	_dl_last = time_of_day
	var t := time_of_day
	var dayf := sin((t - 6.0) / 12.0 * PI)
	# Lantai elevasi bulan (bag. C: dunia SELALU malam, jadi lantai ini
	# SELALU yg dipakai). PERBAIKAN #2 (laporan "bulan gk indah/gk
	# kliatan"): diturunkan lagi 20°->10°. Analisis kamera (player.gd):
	# FOV 60° (setengah 30°), pitch default -34° & clamp maks "menengadah"
	# cuma -10° -> tepi ATAS layar cuma capai elevasi (30 - (-pitch)):
	# di default -34° tepi atas = -4° (msh DI BAWAH cakrawala, langit blm
	# kelihatan sama sekali!), baru tembus ke elevasi +10..+20° kalau
	# pemain aktif menengadah mendekati batas -10°. Jadi bulan/bintang
	# MEMANG perlu pemain menengadah dulu (bukan tampil terus di layar
	# default) — elevasi 10° dipilih spy sudah mulai kelihatan dgn
	# tengadah SEDANG (blm perlu mentok ke batas ekstrem -10°), bukan cuma
	# nongol tipis di detik terakhir spt versi 20° sebelumnya.
	var elev := maxf(dayf * 62.0, 10.0)
	var azim := (t - 12.0) / 12.0 * 140.0
	sun.rotation_degrees = Vector3(-elev, azim - 90.0, 0)
	var env := world_env.environment
	if dayf > 0.15:
		var k := smoothstep(0.15, 0.85, dayf)
		# SORE HANGAT ("dikunci sore ~17:12", time_of_day di atas — satu2nya
		# cabang yg aktif krn siklus mati): matahari rendah keemasan hangat
		# (bukan siang putih-panas), ambient lembut hangat, langit teal-
		# kehijauan lembut dgn cakrawala emas-krim + dasar cokelat-pasir
		# hangat, matahari/bulan cakram tetap kecil wajar (0.035, lihat fix
		# ukuran bulan), bintang MATI siang. Tenang & santai, tak ada sisa
		# nuansa dingin malam tua.
		sun.light_color = Color(1.0, 0.80, 0.55).lerp(Color(1.0, 0.88, 0.68), k)
		# RONDE INI (permintaan user: "pencahayaannya biar lebih terlihat
		# rerumputannya"): matahari dinaikkan (0.58 -> ~0.72) dan ambient
		# ikut disokong: permukaan datar rumput/tanah yg normal-nya ke atas
		# memperoleh cahaya sore-rendah ganda-bantu, jadi ladang hijau
		# akhirnya KELIHATAN hijau, bukan lagi petak gelap. Gambar masih
		# hangat sore hangat.
		sun.light_energy = 0.62 + 0.10 * k
		sun.shadow_enabled = quality_ref.get_preset().shadows if quality_ref else true
		sun.shadow_opacity = 0.35
		env.ambient_light_color = Color(0.56, 0.55, 0.52)
		env.ambient_light_energy = 0.68
		env.fog_light_color = Color(0.60, 0.68, 0.64)
		sky_mat.set_shader_parameter("zenith_color", Color(0.22, 0.45, 0.50))
		sky_mat.set_shader_parameter("horizon_color", Color(0.88, 0.74, 0.52))
		sky_mat.set_shader_parameter("ground_color", Color(0.48, 0.46, 0.40))
		# ground_bottom_color: titik gradasi ke-4 (lihat sky.gdshader) —
		# diturunkan dari ground_color sendiri via darkened(), meniru cara
		# plugin "day-and-night-cycle" (maetzemax) turunkan bbrp warna dari
		# satu basis biar tetap harmonis (bukan warna acak baru).
		sky_mat.set_shader_parameter("ground_bottom_color", Color(0.48, 0.46, 0.40).darkened(0.45))
		sky_mat.set_shader_parameter("sun_color", Color(1.0, 0.88, 0.66))
		sky_mat.set_shader_parameter("star_visibility", 0.0)
		# RONDE INI (keluhan user: "mataharinya kebesaran"): disc jauh
		# lebih kecil (0.035 -> 0.0065) mendekati kesan matahari asli yg
		# sebenarnya cuma ~0.5 derajat — versi lama = kalau diukur di
		# layar jd semacam matahari "15 derajat" yg super raksasa; sekarang
		# hanya berupa bulatan terang kecil tbp.  Dan halonya dipangkas
		# supaya tak nympy GEGLEDOK putih besar di tengah langit lagi.
		sky_mat.set_shader_parameter("sun_size", 0.0065)
		sky_mat.set_shader_parameter("halo", 0.10)
	elif dayf > -0.12:
		var k2 := smoothstep(-0.12, 0.15, dayf)
		sun.light_color = Color(1.0, 0.52, 0.32).lerp(Color(1.0, 0.90, 0.74), k2)
		sun.light_energy = 0.42 + 0.42 * k2
		env.ambient_light_color = Color(0.50, 0.46, 0.52).lerp(Color(0.50, 0.57, 0.60), k2)
		env.ambient_light_energy = 0.52 + 0.30 * k2
		env.fog_light_color = Color(0.72, 0.55, 0.48).lerp(Color(0.54, 0.74, 0.68), k2)
		sky_mat.set_shader_parameter("zenith_color", Color(0.11, 0.24, 0.38).lerp(Color(0.19, 0.42, 0.46), k2))
		sky_mat.set_shader_parameter("horizon_color", Color(0.95, 0.55, 0.34).lerp(Color(0.62, 0.80, 0.66), k2))
		# bawah cakrawala JANGAN coklat-marun berlumpur (laporan foto 17:17):
		# harmonis dgn senja — terracotta lembut, bukan abu-abu sisa siang
		sky_mat.set_shader_parameter("ground_color", Color(0.55, 0.40, 0.34).lerp(Color(0.42, 0.55, 0.50), k2))
		sky_mat.set_shader_parameter("ground_bottom_color", (Color(0.55, 0.40, 0.34).lerp(Color(0.42, 0.55, 0.50), k2)).darkened(0.45))
		sky_mat.set_shader_parameter("star_visibility", 0.0)
		# senada dgn cabang sore di atas: matahari sbrk senja tak lagi
		# raksasa (0.035 -> 0.010; halo dipangkas senada)
		sky_mat.set_shader_parameter("sun_size", 0.010)
		sky_mat.set_shader_parameter("halo", 0.14)
	else:
		# MALAM — cabang ini skrg MENJADI DEAD-CODE (ronde sebelumnya
		# satu-satunya yg dipakai krn kunci malam permanen; ronde ini: kunci
		# dipindah ke sore, lihat time_of_day di atas) tapi DIJAGA UTUH, bisa
		# diaktifkan lagi dgn ganti time_of_day (lihat komentarnya). Isinya:
		# DirectionalLight jadi "cahaya bulan" pucat
		# biru, cakram sky yg sama dipakai sbg BULAN (dibesarkan+dihalo lebih
		# lembut drpd matahari), langit gelap dgn bintang bertaburan.
		#
		# PERBAIKAN (laporan user: "gelap banget gk ada pencahayaan malam
		# kayak sebelum nya"): nilai awal terlalu redup — dinaikkan cukup
		# besar di sini supaya malam terasa "menyala lembut" (moonlit),
		# bukan gelap gulita, sambil tetap bernuansa biru dingin ala malam.
		#
		# KOREKSI #2 (laporan rumput jd PUTIH — bukti screenshot): nilai
		# INI ditumpuk lagi dgn kenaikan glow/exposure/saturasi di ronde2
		# setelahnya -> total kecerahan sesekali cukup tinggi shg ACES
		# tonemap MEMUTIHKAN (hue hilang, jadi abu2/putih — ciri khas
		# filmic tonemap saat overexposed) area yg kena kombinasi ambient+
		# cahaya langsung+fog terbanyak. Angka di sini ditarik turun
		# SEDIKIT (msh JAUH lbh terang drpd nilai asli 0.34/0.62 yg
		# dikeluhkan "gelap banget") sbg bagian dari perbaikan, digabung
		# dgn glow_hdr_threshold dinaikkan & exposure_multiplier diturunkan
		# di _setup_environment (cari margin aman drpd overexposed lagi).
		sun.light_color = Color(0.62, 0.72, 0.95)
		sun.light_energy = 0.52
		env.ambient_light_color = Color(0.36, 0.44, 0.58)
		env.ambient_light_energy = 0.74
		env.fog_light_color = Color(0.22, 0.28, 0.38)
		sky_mat.set_shader_parameter("zenith_color", Color(0.08, 0.15, 0.25))
		sky_mat.set_shader_parameter("horizon_color", Color(0.17, 0.23, 0.33))
		sky_mat.set_shader_parameter("ground_color", Color(0.10, 0.15, 0.20))
		# malam: turunkan lebih dalam (0.55) drpd siang/senja (0.45) -> dasar
		# langit malam nyaris hitam-kebiruan pekat, senada dgn nuansa malam.
		sky_mat.set_shader_parameter("ground_bottom_color", Color(0.10, 0.15, 0.20).darkened(0.55))
		sky_mat.set_shader_parameter("sun_color", Color(0.96, 0.97, 1.0))
		sky_mat.set_shader_parameter("star_visibility", 1.0)
		# bulan (screenshot user: "bulannya terlalu gede banget gk realistis")
		# — nilai SEBELUMNYA (0.075/halo 0.40) ternyata di layar HP hampir
		# menutupi separuh atas frame, jauh dr kesan bulan sungguhan. Diturunkan
		# banyak (skala non-linear: sky.gdshader pakai smoothstep atas cosinus
		# sudut pandang, bukan linear piksel, jd penurunan sun_size sekecil ini
		# msh menghasilkan cakram yg JELAS kelihatan & bersinar, cuma proporsi
		# ukurannya wajar—bukan raksasa menutup layar) — halo jg diturunkan
		# senada spy corona lembutnya tak ikut2an kelihatan besar.
		sky_mat.set_shader_parameter("sun_size", 0.010)
		sky_mat.set_shader_parameter("halo", 0.22)
	# Di FOG_MODE_DEPTH, fog_density BUKAN lagi koefisien eksponensial —
	# artinya opasitas MAKSIMUM kabut tepat di fog_depth_end (0=tak
	# kelihatan, 1=menutup total). _lo.fog/_q_fog tetap dipakai sbg pengali
	# spt sebelumnya (slider debug & preset kualitas).
	env.fog_density = clampf(0.85 * float(_lo.fog) * _q_fog, 0.0, 1.0)
	# jarak kabut menyusut sedikit di preset kualitas Rendah (_q_fog>1) —
	# selain hemat gambar jauh, juga menyamarkan pop-in objek. (Nilai dasar
	# disamakan dgn inisial sore di _setup_environment: 340, bukan 160 malam.)
	env.fog_depth_end = 340.0 / maxf(_q_fog, 0.4)
	sun.light_energy *= float(_lo.sun)
	env.ambient_light_energy *= float(_lo.ambient)
	if int(_lo.sky) >= 0 and int(_lo.sky) < SKY_PRESETS.size():
		var pr: Array = SKY_PRESETS[int(_lo.sky)]
		sky_mat.set_shader_parameter("zenith_color", pr[0])
		sky_mat.set_shader_parameter("horizon_color", pr[1])
