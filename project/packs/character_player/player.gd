extends CharacterBody3D
## Pemain = penyihir ungu berbadan manusia (ronde-46 bag. A4). Bagian A/A2/A3
## sebelumnya 100% prosedural (CapsuleMesh) — dinilai pengguna masih "kayak
## stickman" dari sudut kamera manapun, walau gait-nya sudah biomekanik.
## Pengguna lalu mengirim aset nyata (bukan cuma tautan/screenshot): paket
## animasi mocap Quaternius "Universal Animation Library" (CC0), diunggah
## LANGSUNG ke commit branch lewat uploader web GitHub (bukan lampiran
## chat) — jalur ini terbukti berhasil membawa file biner utuh ke sandbox,
## setelah semua jalur unduh URL/lampiran-chat gagal di ronde-ronde
## sebelumnya (lihat CREDITS.md).
##
## Model: project/packs/char_assets/mannequin/UAL1_Standard.glb
##   - 1 mesh berskin "Mannequin" (2 material, tanpa tekstur) + 43 klip
##     animasi full-body siap pakai (mocap asli, bukan buatan tangan).
##   - Tinggi bind-pose asli ~1.83 m; skala 1:1 (meter), tak perlu koreksi.
##   - CC0 1.0 Universal oleh Quaternius — lihat CREDITS.md utk atribusi.
##
## Bagian A4 ini FOKUS pada lokomosi (diam/jalan/jog/sprint) + dash, sesuai
## permintaan eksplisit pengguna ("fokus ke animasi lari & jalan dulu").
## Klip serang (`Spell_Simple_Shoot`/`Spell_Simple_Idle_Loop`) SENGAJA belum
## dipasang di bagian ini — kandidat kuat utk lapisan animasi serang nanti.
##
## Node internal model (AnimationPlayer/MeshInstance3D) DICARI SECARA
## REKURSIF via find_child()/find_children() — path node persis hasil
## import glTF Godot tak bisa dipastikan tanpa editor lokal, jadi TIDAK ADA
## path node yang di-hardcode di sini.
##
## Warna: mesh asli (M_Main oranye, M_Joints sudah ungu) di-override total
## dgn shader toon.gdshader ungu (2 corak: badan utama + aksen sendi) supaya
## tetap sesuai mandat "karakter warna ungu". Kedua material asli TANPA
## tekstur -> override surface aman, tak ada UV/tekstur yg hilang.
##
## Kamera & gerak: arsitektur sama seperti ronde-ronde sebelumnya (third-
## person murni ikut swipe, gerak bebas 8-arah relatif kamera) — terbukti
## stabil lintas-ronde, sengaja TIDAK diubah.
##
## Serangan: tap tombol serang = satu peluru sihir kecil (arcane_bolt.gd).
## Mantra andalan yang jauh lebih megah menyusul di Bagian B ronde-46.

signal stats_changed(kind: String, count: int)
signal nearest_interactable_changed(meta)
signal health_changed(current: float, maximum: float)

const Materials := preload("res://packs/shaders_materials/materials.gd")
const IslandShape := preload("res://packs/world_terrain/island_shape.gd")
const SHOOT_SFX := "res://packs/audio_sfx/fire_shoot.wav"
const ARCANE_BOLT := preload("res://packs/character_player/arcane_bolt.gd")
const FIRE_SPIRIT := preload("res://packs/character_player/fire_spirit.gd")
const SPEED_THREAD := preload("res://packs/character_player/speed_thread.gd")  # benang trail smooth ala Yelan
const MANNEQUIN_SCENE := preload("res://packs/char_assets/mannequin/UAL1_Standard.glb")
const FIRE_COOLDOWN := 0.3
const BOLT_SPEED := 21.0
const BOLT_LIFT := 1.8

## Skin ke-2 (permintaan user: file OC-Kanna.vrm dikirim via Google Drive,
## "pake 2 karakter ada icon ganti karakter satu yang manequin satu karakter
## vrm"). File .vrm SECARA BINER adalah glTF/.glb biasa (VRM = glTF + data
## tambahan avatar) — disalin apa adanya jd .glb spy importer bawaan Godot
## mengenalinya sbg PackedScene normal, TANPA perlu plugin VRM apa pun.
##
## PERBAIKAN BESAR (laporan user: "karakter vrm malah tidur ditanah"):
## pendekatan RENAME-TULANG sebelumnya (komit aa919f4) SALAH BETUL secara
## matematika — klip mocap menulis pose lokal tulang secara ABSOLUT dgn
## konvensi ruang tulang Blender/UE (root mannequin punya rotasi rest
## -90°X, lokal pelvis [0,0.05,0.92]), sedang rig Kanna (VRM) pakai
## konvensi identity/Y-up — begitu pose absolut pelvis mannequin diterapkan
## mentah ke Kanna, seluruh badan terbanting 90° ke tanah ("tidur"). Klip
## TAK BISA dipakai lintas-rig dgn ganti nama; yg benar adalah RETARGET:
## mannequin dibiarkan penuh (mesh disembunyikan, jadi "puppeteer" tak
## kelihatan), AnimationPlayer memainkan skeleton-nya spt biasa, lalu TIAP
## FRAME kelas SkinRetarget (di bawah) membaca pose global tiap tulang &
## menerjemahkannya ke skeleton Kanna (delta rotasi dari rest + konjugasi
## yaw 180°, lihat komentar konvensi cermin di bawah).
const KANNA_SCENE := preload("res://packs/char_assets/mannequin/kanna.glb")
const SKIN_MANNEQUIN := "mannequin"
const SKIN_KANNA := "kanna"

## Pasangan tulang INDUK->INDUK utk retarget: [nama tulang mannequin (sumber
## pose), nama tulang asli Kanna (tujuan)]. Urutan WAJIB induk-dulu (pelvis
## sebelum kaki/lengan/kepala) krn konversi global->lokal butuh pose induk
## yg sudah ter-set di frame yg sama. Tulang yg tak dipetakan (jari, rambut,
## segmen penolong Rigify "DEF-... .001/.002", clavicle) dibiarkan di rest —
## otomatis ikut kaku mengikuti induknya yg teranimasi (cukup utk lokomosi).
## (Nama tulang Kanna diambil dr extensions.VRM.humanoid.humanBones di file
## VRM aslinya, diverifikasi silang dgn dump wrapper glTF-nya.)
const KANNA_RETARGET_PAIRS := [
	["pelvis", "root"],           # VRM "hips"
	["spine_01", "DEF-Spine"],    # VRM "spine"
	["spine_02", "DEF-Chest"],    # VRM "chest"
	["spine_03", "DEF-Upper Chest"],
	["neck_01", "DEF-Neck"],
	["Head", "DEF-Head"],
	["thigh_l", "DEF-Left leg"],
	["calf_l", "DEF-Left knee"],
	["foot_l", "DEF-Left ankle"],
	["ball_l", "DEF-Left toe"],
	["thigh_r", "DEF-Right leg"],
	["calf_r", "DEF-Right knee"],
	["foot_r", "DEF-Right ankle"],
	["ball_r", "DEF-Right toe"],
	["upperarm_l", "DEF-Left arm"],
	["lowerarm_l", "DEF-Left elbow"],
	["hand_l", "DEF-Left wrist"],
	["upperarm_r", "DEF-Right arm"],
	["lowerarm_r", "DEF-Right elbow"],
	["hand_r", "DEF-Right wrist"],
]

## Driver retarget runtime (permintaan user: skin ke-2 pakai VRM lain & TETAP
## bisa jalan/lari). Src = skeleton mannequin yg dimainkan AnimationPlayer
## (mesh-nya disembunyikan spt puppeteer tak kelihatan); dst = skeleton
## Kanna yg mesh-nya tampil. Tiap frame, utk tiap pasangan tulang:
##   delta = pose_global_q(src) * inverse(rest_global_q(src))
##   target_global_q(dst) = delta_dikonjugasi * rest_global_q(dst)
##   lokal(dst) = inverse(pose_global_q(induk dst)) * target_global_q
## Posisi hanya dipindah utk pelvis (selisih bob dari rest, diskala rasio
## tinggi badan) — panjang tulang Kanna tetap miliknya sendiri (retarget
## "non-global-pose": bentuk tubuh asli Kanna tak dirusak).
##
## KONVENSI CERMIN (diverifikasi numerik dr data GLB kedua file): tulang
## "left" mannequin ada di sisi +X dgn badan menghadap +Z, sedang "DEF-Left"
## Kanna ada di sisi -X (menghadap -Z) -> kedua rig BEDA 180° sumbu-Y. Tanpa
## koreksi ini lengan kiri Kanna ayunannya jadi terbalik & muka belakang
## arah jalan. Delta & pose pelvis dikonjugasi rotasi 180°-Y:
##   q' = Q180y * q * Q180y^-1  ==  Quaternion(-x, y, -z, w)
##   (dx,dy,dz)' = (-dx, dy, -dz)
class SkinRetarget:
	extends Node
	var src: Skeleton3D
	var dst: Skeleton3D
	var pairs: Array = []          # [src_idx, dst_idx] (indeks tulang, bukan nama)
	var src_pelvis: int = -1
	var dst_pelvis: int = -1
	var rest_src_q: Dictionary = {}    # src_idx -> Quaternion (global rest)
	var rest_dst_q: Dictionary = {}    # dst_idx -> Quaternion (global rest)
	var rest_src_pelvis_pos := Vector3.ZERO
	var rest_dst_pelvis_pos := Vector3.ZERO
	var height_ratio := 1.0

	func _init() -> void:
		# Jalan SETELAH AnimationPlayer (prioritas default 0) spy pose yg
		# dibaca = pose frame INI (bukan 1 frame telat) jd hasilnya halus.
		process_priority = 200

	var _dst_rest_local_q: Array = []   # per dst bone: quaternion rest LOKAL

	func configure(p_src: Skeleton3D, p_dst: Skeleton3D, p_pairs: Array) -> void:
		src = p_src
		dst = p_dst
		for pp in p_pairs:
			var si: int = src.find_bone(pp[0])
			var di: int = dst.find_bone(pp[1])
			if si < 0 or di < 0:
				push_warning("SkinRetarget: pasangan tulang hilang: %s -> %s (si=%d di=%d)" % [pp[0], pp[1], si, di])
				continue
			pairs.append([si, di])
			rest_src_q[si] = src.get_bone_global_rest(si).basis.get_rotation_quaternion()
			rest_dst_q[di] = dst.get_bone_global_rest(di).basis.get_rotation_quaternion()
			if pp[0] == "pelvis":
				src_pelvis = si
				dst_pelvis = di
				rest_src_pelvis_pos = src.get_bone_global_rest(si).origin
				rest_dst_pelvis_pos = dst.get_bone_global_rest(di).origin
				if rest_src_pelvis_pos.y > 0.01:
					height_ratio = rest_dst_pelvis_pos.y / rest_src_pelvis_pos.y
		_dst_rest_local_q.resize(dst.get_bone_count())
		for i in range(dst.get_bone_count()):
			_dst_rest_local_q[i] = dst.get_bone_rest(i).basis.get_rotation_quaternion()
		# langsung retarget SEKALI di sini (tdk nunggu frame) spy tak ada
		# T-pose flash sekilas saat ganti skin.
		transfer()

	func _process(_delta: float) -> void:
		transfer()

	## Global-quaternion tulang dst `idx`, dihitung MURNI berantai top-down:
	## tulang terpetakan = target global-nya; tak terpetakan = induk_global *
	## rest_lokalnya. Tak membaca get_bone_global_pose dst sama sekali —
	## sengaja, krn pose yg baru di-set belum tentu sudah terkomposisi engine
	## (dibutuhkan utk turunkan pose lokal anak dr target globalnya sendiri
	## dgn benar, tanpa _race_/stale satu frame antar-induk-anak).
	func _dst_global_q(idx: int, target_gq: Dictionary, cache: Dictionary) -> Quaternion:
		if idx < 0:
			return Quaternion.IDENTITY
		if cache.has(idx):
			return cache[idx]
		var p := dst.get_bone_parent(idx)
		var pg := _dst_global_q(p, target_gq, cache)
		var g: Quaternion
		if target_gq.has(idx):
			g = target_gq[idx]
		else:
			g = (pg * _dst_rest_local_q[idx]).normalized()
		cache[idx] = g
		return g

	func transfer() -> void:
		if src == null or dst == null or not is_instance_valid(src) or not is_instance_valid(dst):
			return
		# 1) target ROTASI global utk tiap pasangan: delta src (dr rest-nya),
		#    dikonjugasi yaw-180 (konvensi cermin antar-rig, lihat komentar kelas)
		var target_gq: Dictionary = {}   # dst_idx -> Quaternion
		for pp in pairs:
			var si: int = pp[0]
			var di: int = pp[1]
			var gq: Quaternion = src.get_bone_global_pose(si).basis.get_rotation_quaternion()
			var dq: Quaternion = gq * rest_src_q[si].inverse()
			var cdq := Quaternion(-dq.x, dq.y, -dq.z, dq.w)
			target_gq[di] = (cdq * rest_dst_q[di]).normalized()
		# 2) susun pose LOKAL Kanna: pose tulang Godot 4 adalah TRANSFORM LOKAL
		#    ABSOLUT terhadap induknya (default-nya = rest; set_bone_pose_*
		#    menimpa penuh, BUKAN delta di atas rest). Jadi rotasi lokal yg
		#    diinginkan = induk_global^-1 * target_global. (Catatan sejarah:
		#    di komit ini sempat dikali rest_lokal^-1 jg krn salah-baca spek —
		#    utk Kanna kebetulan identik (rest tulang = identity), jadi tidak
		#    mengubah perilaku; dihapus lg utk kebenaran konsep.)
		var cache: Dictionary = {}
		for pp in pairs:
			var di: int = pp[1]
			var pidx: int = dst.get_bone_parent(di)
			var pg := _dst_global_q(pidx, target_gq, cache)
			var lq: Quaternion = (pg.inverse() * target_gq[di]).normalized()
			dst.set_bone_pose_rotation(di, lq)
		# 3) posisi: hanya pelvis (bob naik-turun/condong src diikuti, diskala).
		#    Seperti rotasi di atas: pose lokal = induk_global^-1 * target_global,
		#    TANPA komposisi rest tambahan (pose Godot = lokal absolut relatif
		#    induk). Bug sebelumnya: sempat dihitung sbg komposisi rest+target
		#    shg pelvis jatuh ke y≈0 ("tenggelam") — itulah kegagalan CI
		#    terakhir (berhasil ditangkap persis oleh probe _check_skin_switch).
		if src_pelvis >= 0 and dst_pelvis >= 0:
			var sdp: Vector3 = (src.get_bone_global_pose(src_pelvis).origin - rest_src_pelvis_pos) * height_ratio
			sdp = Vector3(-sdp.x, sdp.y, -sdp.z)
			var target_pos := rest_dst_pelvis_pos + sdp
			var ppar: int = dst.get_bone_parent(dst_pelvis)
			var local_pos := target_pos
			if ppar >= 0:
				# utk Kanna: pelvis ("root") adalah bone akar (parent=-1), cabang
				# ini cuma cadangan bila suatu hari rig lain pelvis-nya nested.
				var pgt: Transform3D = dst.get_bone_global_rest(ppar)
				var pgq: Quaternion = _dst_global_q(ppar, target_gq, cache)
				pgt.basis = Basis(pgq)
				local_pos = pgt.basis.inverse() * (target_pos - pgt.origin)
			dst.set_bone_pose_position(dst_pelvis, local_pos)


## Penggerak peleburan ghost dash SCR MANUAL per-frame (deterministik —
## TAK pakai Tween properti "shader_parameter/*": pola itu menyebabkan
## ghost "tertinggal permanen"; lihat catatan di _spawn_afterimage).
## life01 dinaikkan 0->1 merata selama `fade` detik (wobble asap di shader
## makin mengembang + alpha padam), ghost juga diangkat pelan ke atas,
## lalu node ghost (induk driver ini) di-queue_free.
class DashGhost:
	extends Node
	var fade := 0.85
	var smoke_mat: ShaderMaterial
	var RISE := 0.22                  # meter terangkat selagi memudar
	var _age := 0.0
	func _process(delta: float) -> void:
		_age += delta
		var life01: float = clampf(_age / maxf(fade, 0.05), 0.0, 1.0)
		var p := get_parent() as Node3D
		if is_instance_valid(smoke_mat):
			smoke_mat.set_shader_parameter("life01", life01)
		if is_instance_valid(p):
			p.position.y += (RISE / maxf(fade, 0.05)) * delta
		if life01 >= 1.0 and is_instance_valid(p):
			# bersihkan override tulang spy lepas RS tepat waktu, baru hilang
			for n in p.find_children("*", "Skeleton3D", true, false):
				(n as Skeleton3D).clear_bones_global_pose_override()
			p.queue_free()


# Dua corak ungu: badan utama (permukaan besar) + aksen sendi (kontras
# lebih gelap, mempertahankan "color-blocking" asli model sumber).
# RONDE INI (permintaan user: "buat warna gk bentrok ama warna lain jadi
# mereka nyambung semua... ala warna pastel gitu") — dilembutkan dr ungu
# tua pekat jadi purple-PASTEL (lavender lembut, tetap jelas ungu): serasi
# dgn langit sore keemasan+hijau pucat dunia; bukan lagi ungu neon yg
# "berteriak" sendirian di tengah warna pastel lainnya.
const BODY_COLOR := Color(0.62, 0.46, 0.90)
const JOINT_COLOR := Color(0.38, 0.26, 0.66)

# --- gerak (ringan, lincah — penyihir jalan kaki, bukan kendaraan) ---
const MAX_SPEED := 9.0
const ACCEL_RATE := 7.5
const DECEL_RATE := 4.5

# SKILL "gerak-cepat" (permintaan user ronde ini: "tambahkan skill movement
# speed kalo kita pencet nambah 5 kali kecepatan speed lari") — tombol
# toggle di HUD (BtnSpeed, emoji ≪≫): kecepatan target dilipat-gandakan
# ×SPEED_SKILL_MULT saat aktif, laju akselerasi jg dibikin BRUTALCY (lihat
# _move), bodi relatif-kamera tak dicampur sama: kamera tetap third-person
# biasa, tapi homecam FOV di-"kick" sedikit (lihat _camera_boost_fx); arm
# kamera digeser keluar sedikit (CAM_BOOST_PULL) spy pemain kelihatan lbh
# kecil & cepat, lalu lari beneran; tween FOV tetap mengizinkan beda
# pitch/look, cuma fov dasarnya yg berubah.
const SPEED_SKILL_MULT := 5.0
const SPEED_SKILL_ACCEL := 14.0
const CAM_BOOST_FOV := 72.0
const CAM_BOOST_PULL := 1.6
const HOVER := 0.0           # model sudah berakar tepat di telapak kaki (Y=0 bind-pose)

# --- proporsi model nyata (Quaternius mannequin, ~1.83 m bind-pose) ---
const MODEL_HEIGHT := 1.83
const CAST_HEIGHT := 1.32     # perkiraan tinggi tangan/dada utk titik lontar peluru
## Dikonfirmasi pengguna lgsg di device (ronde-46 bag. A4 lanjutan): model
## menghadap 180° TERBALIK dari arah gerak (mukanya ke belakang saat jalan
## maju) — makanya PI di sini, bukan 0.0 lagi. Rig sumber (Quaternius/UE4
## mannequin) menghadap -Z di bind-pose sama seperti konvensi Godot, tapi
## root bone punya koreksi rotasi -90° sumbu X (Blender Z-up->Y-up) yang
## rupanya membalik sumbu depan juga -> kompensasi di sini, di level visual,
## bukan di rig (lebih aman & mudah diubah lagi kalau ternyata masih meleset).
const MODEL_YAW_OFFSET := PI
## Koreksi yaw TAMBAHAN per-skin (di atas MODEL_YAW_OFFSET di atas, yg
## dikalibrasi KHUSUS utk rig mannequin). Skin lain (VRM dll) bisa saja py
## konvensi hadap beda — Kanna: kedua rig beda 180° sumbu-Y (diverifikasi
## numerik dr GLB: tulang "left" mannequin di +X, "DEF-Left" Kanna di -X,
## lihat komentar KONVENSI CERMIN di kelas SkinRetarget) -> PI di sini.
const SKIN_YAW_EXTRA := {
	"mannequin": 0.0,
	"kanna": PI,
}

# --- nama klip animasi SETELAH import Godot (BUKAN nama asli di glTF!) ---
# Dikonfirmasi via probe CI (dev_probe/fire_attack_check.gd _diag_mannequin):
# importer glTF Godot MEMOTONG akhiran "_Loop" dari nama klip lalu memakainya
# utk set loop_mode animasi itu sendiri secara native (mis. "Idle_Loop" (glTF)
# -> "Idle" (AnimationPlayer, sudah loop_mode=LINEAR otomatis). Nama asli
# ("Idle_Loop" dkk, lihat CREDITS.md) TIDAK ADA di AnimationPlayer — pakai
# nama hasil import di bawah ini, bukan nama sumber.
const ANIM_IDLE := "Idle"
const ANIM_WALK := "Walk"
const ANIM_JOG := "Jog_Fwd"
const ANIM_SPRINT := "Sprint"

# Ambang speed01 (0..1) utk pindah state, dgn histeresis (naik/turun beda
# ambang) supaya tak "flicker" bolak-balik dekat batas.
const WALK_ON := 0.06
const WALK_OFF := 0.03
const JOG_ON := 0.40
const JOG_OFF := 0.30
const SPRINT_ON := 0.82
const SPRINT_OFF := 0.70
const ANIM_BLEND := 0.18

# --- dash: "sprint burst" ala pengguna (bag. A4 lanjutan #2) — BUKAN lagi
# animasi roll/berguling. Badan tetap main klip lari (ANIM_SPRINT) yang
# sama seperti lari biasa, tapi kaki dipercepat drastis (speed_scale) demi
# kesan "meledak ngebut", ditambah jejak bayangan (afterimage) transparan
# yg mengikuti pose animasi berjalan saat itu.
const DASH_ANIM_SPEED_SCALE := 1.8
# Sama terapan pastel ke warna-warna lain karakter FX di file ini: dash
# afterimage kini ABU-ABU pastel dgn asap bergoyang (permintaan user:
# "hanya satu bayangannya aja yg tertinggal, abu abu dengan efek asap tapi
# masih ada bentukan karakternya kayak goyangan asap"), trail speed-skill
# pastel cyan lembut, dsb. Semuanya di-set ke satu palet pastel biar
# nyambung, gak bentrok warna sen itu sendiri.
const AFTERIMAGE_FADE := 0.85        # umur ghost dash (dinaikkan — hanya 1 ghost per dash)
# Hotfix lanjutan ronde ini (permintaan user: "bayangan dash ikut gerak...
# jadi bayangan nya gk gerak"): ghost kini membawa skeleton hantu DIBEKUKAN
# di pose spawn (lihat _spawn_afterimage) dan (untuk DASH) bahannya shader
# asap abu-abu ber-wooble (afterimage_smoke.gdshader) — siluet karakter
# tetap kebaca, tapi seolah terbuat dr gumpalan asap yg bergoyang.
const AFTERIMAGE_SHADER := preload("res://packs/character_player/afterimage_smoke.gdshader")


# --- kamera third-person (murni ikut swipe, arsitektur tak berubah) ---
const PITCH_MIN := deg_to_rad(-72.0)
const PITCH_MAX := deg_to_rad(-10.0)
# CAM_DIST didekatkan (permintaan user "kameranya agak deketin ke player"):
# 7.6 -> 5.6. LALU didekatkan LAGI (permintaan lanjutan "jarak kamera ke
# player deketin lagi"): 5.6 -> 4.4. Zoom-out manual (pinch 2 jari, lihat
# hud.gd add_zoom) msh bisa menjauhkan sampai CAM_ZOOM_MAX, tapi otomatis
# balik ke CAM_DIST ini lagi scr smooth (lihat _cam_zoom di _process) begitu
# jalan lagi / diam sebentar.
const CAM_DIST := 4.4
const CAM_FOLLOW := 7.0
const LOOK_K := 0.0036
const CAM_FOCUS_HEIGHT := 1.05
const CAM_ZOOM_MAX := 6.5          # tambahan jarak maks dr pinch zoom-out
const CAM_ZOOM_RETURN_IDLE_S := 2.2 # diam brp detik (tanpa pinch baru) sblm auto-balik
const CAM_ZOOM_RETURN_RATE := 2.4   # laju easing balik (lbh besar = lbh cepat)

# --- dash: burst cepat lalu melambat ---
const DASH_SPEED := 22.0
const DASH_DURATION := 0.30
const DASH_COOLDOWN := 1.1

var world: Node
var settings
var cam_pivot: Node3D
var cam_arm: SpringArm3D
var joy := Vector2.ZERO
var _look_vel := Vector2.ZERO
var yaw := 0.0
var pitch := deg_to_rad(-34.0)
var is_ready := false
var stats := {}
var max_health := 100.0
var health := 100.0

var _visual: Node3D
var _fire_spirit: Node3D  # peliharaan elemental api di bahu, lihat _build_fire_spirit()
var _model: Node3D
var _anim: AnimationPlayer
var _skeleton: Skeleton3D
var _anim_state := ""
var _aura_particles: GPUParticles3D
var _aura_material: ParticleProcessMaterial
var _base_amounts := {}
var _t := 0.0
var _speed01 := 0.0
var _cam_extra := 0.0
# Zoom manual dr pinch 2 jari (hud.gd add_zoom) — 0=jarak default (CAM_DIST),
# makin besar = makin menjauh (max CAM_ZOOM_MAX). Auto-balik ke 0 scr smooth
# saat pemain jalan lagi ATAU diam tanpa pinch baru sekian detik (lihat
# _process — CAM_ZOOM_RETURN_IDLE_S/RATE).
var _cam_zoom := 0.0
var _cam_zoom_idle_t := 999.0
var _cam_snapped := false
var _facing := Vector3.ZERO
var _fire_cooldown := 0.0
var _shake := 0.0
var _fx := 1.0
var _dash_left := 0.0
var _dash_cooldown := 0.0
var _dash_dir := Vector3.ZERO
var _speed_skill := false          # status skill "gerak-cepat" aktif/tidak (toggle BtnSpeed)
var _speed_threads: Array = []     # benang trail ala Yelan (speed_thread.gd), anak player
var _cam_boost_fov := 0.0          # kick FOV saat skill kecepatan diaktifkan (efek "bush")
var _cam_boost_arm := 0.0          # tarikan arm kamera keluar sedikit saat boost
var _dust_dist_accum := 0.0
var _dust_side := 1.0
var _skin_id := SKIN_MANNEQUIN
var _skin_switching := false
var _kanna: Node3D            # skin Kanna aktif (null kalau lg mannequin)
var _kanna_skeleton: Skeleton3D
var _retarget: SkinRetarget   # driver pose mannequin->kanna (null kalau mannequin)

func set_world(w: Node) -> void:
	world = w

func set_settings(s) -> void:
	settings = s

func _ready() -> void:
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	cam_pivot = $CameraPivot
	cam_arm = $CameraPivot/CamArm
	cam_pivot.top_level = true
	cam_arm.add_excluded_object(get_rid())
	# _visual dibuat SEKALI di sini (bukan lagi di _build_character) — ganti
	# skin (lihat cycle_skin()) cuma menukar isi _model DI DALAM _visual yg
	# sama, spy fire_spirit/aura yg jd anak _visual tak ikut hilang/dibuat ulang.
	_visual = Node3D.new()
	_visual.name = "Visual"
	_visual.position = Vector3(0.0, HOVER, 0.0)
	add_child(_visual)
	_build_character(_skin_id)
	_build_aura()
	_build_fire_spirit()
	_build_speed_threads()
	is_ready = true
	health_changed.emit(health, max_health)

# =============== API dari HUD ===============

func set_joy(v: Vector2) -> void:
	joy = v

func add_look_px(dx: float, dy: float) -> void:
	_look_vel.x += dx * 60.0
	_look_vel.y += dy * 60.0

## Zoom kamera manual (dipanggil hud.gd saat gestur cubit 2 jari). positif =
## menjauh, negatif = mendekat. Auto-balik ke 0 (CAM_DIST) ditangani di
## _process, bukan di sini — di sini cuma menggeser target & reset idle-timer.
func add_zoom(delta_dist: float) -> void:
	# MODE BANGUN: zoom-out top-down butuh jangkau lebih jauh (BUILD_CAM_ZOOM_
	# MAX) — kapasitas normal CAM_ZOOM_MAX tetap utk gameplay (batas dinamis).
	var zmax := BUILD_CAM_ZOOM_MAX if build_cam else CAM_ZOOM_MAX
	_cam_zoom = clampf(_cam_zoom + delta_dist, 0.0, zmax)

# ===== KAMERA MODE BANGUN (permintaan user, ronde ini) =====
# Saat Build Mode aktif: kamera digerakkan ke TOP-DOWN scr SMOOTH (pitch
# hampir tegak-lurus, jarak besar — semua transisi di-lerp di _apply_camera),
# model karakter DISEMBUNYIKAN sementara (layar penuh lega utk editing),
# drag satu jari jadi PAN peta (bukan putar kamera), joystick build jadi
# pan berkelanjutan (bukan gerak badan), dan pemain dibekukan (velocity 0).
var build_cam := false                    # true selagi Build Mode terbuka
var _build_pan := Vector3.ZERO            # offset kamera XZ relatif posisi pemain
var _build_joy := Vector2.ZERO            # joystick build → pan, bukan langkah
const BUILD_CAM_PITCH := -1.40            # rad ≈ -80°, menatap hampir tegak
const BUILD_CAM_DIST := 24.0              # jarak pandang default top-down (m)
const BUILD_CAM_ZOOM_MAX := 45.0          # jangkau pinch zoom-out mode bangun
const BUILD_PAN_LIMIT := 220.0            # pan maks (bidang tanah visual ikut pemain!)
const BUILD_PAN_SPEED := 26.0             # m/dtk pan dari joystick build

## Dipanggil BuildModeManager.toggle() saat MASUK build mode.
func enter_build_cam() -> void:
	build_cam = true
	_look_vel = Vector2.ZERO
	joy = Vector2.ZERO
	velocity = Vector3.ZERO            # bekukan sisa momentum (lihat _move)
	if _visual:
		_visual.visible = false        # "karakter otomatis dihilangkan dulu"
	if is_instance_valid(_fire_spirit):
		_fire_spirit.visible = false   # pet elemen jg disembunyikan — layar bersih

## Dipanggil BuildModeManager.toggle() saat KELUAR build mode.
func exit_build_cam() -> void:
	build_cam = false
	_build_pan = Vector3.ZERO          # kamera kembali mulus ke kepala pemain
	_build_joy = Vector2.ZERO
	_cam_zoom = 0.0
	if _visual:
		_visual.visible = true
	if is_instance_valid(_fire_spirit):
		_fire_spirit.visible = true

## Drag satu jari di build mode (bakal album "geser peta"): konten peta
## MENGIKUTI jari (seperti geser Google Maps) → offset kamera bergerak
## berlawanan dr geseran jari, dikonversi skala meter sesuai zoom saat ini.
func add_pan_px(dx: float, dy: float) -> void:
	var px2m := (BUILD_CAM_DIST + _cam_zoom) * 0.0016
	_build_pan += Basis(Vector3.UP, yaw) * Vector3(-dx, 0.0, -dy) * px2m
	_clamp_build_pan()

## Joystick build (BuildJoyControl) → pan peta berkelanjutan per frame.
func set_build_joy(v: Vector2) -> void:
	_build_joy = v

func _clamp_build_pan() -> void:
	_build_pan.y = 0.0
	if _build_pan.length() > BUILD_PAN_LIMIT:
		_build_pan = _build_pan.normalized() * BUILD_PAN_LIMIT
	_cam_zoom_idle_t = 0.0

func take_damage(amount: float) -> void:
	var before := health
	health = maxf(1.0, health - maxf(0.0, amount))
	if not is_equal_approx(before, health):
		health_changed.emit(health, max_health)
		_shake = minf(_shake + 0.18, 0.8)

func heal(amount: float) -> void:
	var before := health
	health = minf(max_health, health + maxf(0.0, amount))
	if not is_equal_approx(before, health):
		health_changed.emit(health, max_health)

## Dipanggil peluru (arcane_bolt.gd) saat meledak di dekat pemain.
func add_shake(amount: float) -> void:
	_shake = minf(_shake + maxf(0.0, amount), 0.9)

func press_jump() -> void:
	pass

func press_sprint(_down: bool) -> void:
	pass

func press_interact() -> void:
	pass

func press_attack() -> void:
	_try_fire()

func set_attack_held(down: bool) -> void:
	if down:
		_try_fire()

func press_speed_skill(down: bool) -> void:
	if not is_ready:
		return
	_speed_skill = down
	# momentum: efek "bush" di awal aktivasi — shockwave ring + set kecepatan
	# langsung diserok (bukan ditunggu lerpa pelan) + trail kamera (fov kick)
	if down:
		_spawn_speed_boost_fx()

## Efek "bush"/lontaran awal skill kecepatan (permintaan user: "pas mencet
## mov speed bajal ada efek bush gitu jadi berasa naik kecepatan nya"):
##  1) ring kejut udara melingkar di tanah (shockwave.gdshader, tint pastel
##     cyan-gray biar senada dgn trail speed, tak bentrok dgn ungu sihir);
##  2) kamera di-"kick": FOV 60->melongok ke CAM_BOOST_FOV lalu lerp balik,
##     lengan digeser keluar sedikit (CAM_BOOST_PULL) — tubuh terasa meluncur
##     yang tak bisa dicapai umpama cuma menambah angka kecepatan saja.
func _spawn_speed_boost_fx() -> void:
	var parent := get_parent()
	if parent == null:
		return
	var ring := MeshInstance3D.new()
	ring.name = "SpeedBoostRing"
	var ring_mesh := PlaneMesh.new()
	ring_mesh.size = Vector2(2.6, 2.6)
	ring.mesh = ring_mesh
	var ring_shader := preload("res://packs/character_player/shockwave.gdshader")
	var ring_mat := ShaderMaterial.new()
	ring_mat.shader = ring_shader
	ring_mat.set_shader_parameter("tint", Color(0.55, 0.68, 0.90, 0.7))
	ring_mat.set_shader_parameter("energy", 1.4)
	ring.material_override = ring_mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(ring)
	ring.global_position = global_position + Vector3(0.0, 0.06, 0.0)
	var tween := create_tween()
	tween.tween_property(ring_mat, "shader_parameter/progress", 1.0, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_callback(ring.queue_free)

	_cam_boost_fov = CAM_BOOST_FOV - 60.0
	_cam_boost_arm = CAM_BOOST_PULL

func press_dash() -> void:
	if not is_ready or _dash_cooldown > 0.0 or _dash_left > 0.0:
		return
	var wish := joy
	if wish == Vector2.ZERO:
		wish = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var direction := Basis(Vector3.UP, yaw) * Vector3(wish.x, 0.0, wish.y)
	if direction.length_squared() < 0.01:
		direction = _shoot_direction()
	_dash_dir = direction.normalized()
	_dash_left = DASH_DURATION
	_dash_cooldown = DASH_COOLDOWN
	_spawn_dash_shimmer()
	# SATU-SATUNYA bayangan dash (permintaan user: "hanya satu bayangannya
	# aja yg tertinggal") — ghost pose saat tombol ditekan, lalu kena efek
	# asap bergoyang (lihat _spawn_afterimage + _spawn_ghost_smoke), warna
	# abu-abu pastel (bukan lagi ungu bertumpuk per-interval 0.05 detik spt
	# versi lama yg "berantakan banget"). Berlaku dua2 skin (lihat
	# _spawn_afterimage: sumber mesh dipilih per skin aktif).
	_spawn_afterimage()

func press_emote() -> void:
	pass

func apply_quality(p: Dictionary) -> void:
	_fx = clampf(float(p.get("fx", 1.0)), 0.2, 1.0)
	for n in _base_amounts:
		if is_instance_valid(n):
			n.amount = maxi(6, int(round(float(_base_amounts[n]) * _fx)))

# =============== Loop ===============

func _process(delta: float) -> void:
	if not is_ready:
		return
	delta = minf(delta, 0.1)
	_t += delta
	_fire_cooldown = maxf(0.0, _fire_cooldown - delta)
	_dash_cooldown = maxf(0.0, _dash_cooldown - delta)
	_move(delta)
	_apply_camera(delta)
	_animate_character(delta)
	# Benang trail skill kecepatan: mengaum hanya saat skill ON dan laju
	# fisik nyata sudah kencang (>55% MAX_SPEED). _speed01 dipakai spy tak
	# perlu hitung ulang panjang velocity di sini.
	var thread_on := 1.0 if (_speed_skill and _speed01 > 0.55) else 0.0
	for t in _speed_threads:
		if is_instance_valid(t):
			t.set_target(thread_on)
	# Peliharaan elemental (permintaan user: "lidah apinya bakal gerak kalo
	# kita jalan") -- kasih tahu kecepatan pemain skrg spy shell shadernya
	# bisa "menyeret" nyala api ke belakang arah jalan (lihat fire_spirit.gd).
	if is_instance_valid(_fire_spirit):
		_fire_spirit.external_velocity = Vector3(velocity.x, 0.0, velocity.z)

func _move(delta: float) -> void:
	if build_cam:
		return   # Mode Bangun: pemain dibekukan (enter_build_cam sdh nol-kan velocity)
	if _dash_left > 0.0:
		_dash_left = maxf(0.0, _dash_left - delta)
		var progress := 1.0 - _dash_left / DASH_DURATION
		var dash_factor := 1.0 - progress * progress
		var dash_velocity := _dash_dir * DASH_SPEED * dash_factor
		velocity = Vector3(dash_velocity.x, -global_position.y / maxf(delta, 0.001), dash_velocity.z)
		move_and_slide()
		_clamp_to_island()
		_facing = _dash_dir
		_speed01 = lerpf(_speed01, dash_factor, 1.0 - exp(-12.0 * delta))
		_advance_footsteps(DASH_SPEED * dash_factor, delta)
		# dash HANYA MENELAN HANTU SATU-SATUNYA di tekan tombol (lihat press_dash
		# -> _spawn_afterimage) — tak ada lagi ghost train interval di sini
		# (disuruh user: "afterimage itu hanya satu bayangannya aja yg tertinggal").
		return

	var wish := joy
	if wish == Vector2.ZERO:
		wish = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if wish.length() > 1.0:
		wish = wish.normalized()
	var dir := Basis(Vector3.UP, yaw) * Vector3(wish.x, 0.0, wish.y)
	# --- kecepatan skill "gerak-cepat" (toggle BtnSpeed) ---
	# Saat skill ON: kecepatan target ×5 DAN akselerasi jg dibikin jauh lbh
	# agresif (SPEED_SKILL_ACCEL) spy 45m+ benar-benar terasa dijangkau dlm
	# hitungan ratusan milidetik, bukan lari-dibersar tapi lambat merayap.
	var spd_mult := SPEED_SKILL_MULT if _speed_skill else 1.0
	var target := dir * (MAX_SPEED * spd_mult)
	var hv := Vector3(velocity.x, 0.0, velocity.z)
	var accel_now := SPEED_SKILL_ACCEL if _speed_skill else ACCEL_RATE
	var rate := accel_now if target.length_squared() > 0.0001 else DECEL_RATE
	hv = hv.lerp(target, 1.0 - exp(-rate * delta))
	if hv.length_squared() < 0.0004 and target == Vector3.ZERO:
		hv = Vector3.ZERO
	velocity = Vector3(hv.x, -global_position.y / maxf(delta, 0.001), hv.z)
	move_and_slide()
	_clamp_to_island()
	if hv.length() > 0.1:
		_facing = hv.normalized()
	_speed01 = lerpf(_speed01, clampf(hv.length() / MAX_SPEED, 0.0, 1.0), 1.0 - exp(-8.0 * delta))
	_advance_footsteps(hv.length(), delta)
	# CATATAN: trail ghost-mesh DIHAPUS total (laporan user: "trail mov speed
	# jangan pake after image ... kayak benang smooth aja ala Yelan") —
	# penggantinya pita benang speed yg digambar per-frame oleh node
	# SpeedThread (lihat _build_speed_threads/_process), jauh lebih murah &
	# tak memenuhi layar dgn patung putih.

## Batas pulau (~3km, diperkecil dari ~12km per permintaan user ronde ini —
## angka sebenarnya SELALU ikut IslandShape.RADIUS, tak di-hardcode di sini)
## (bag. C lanjutan, permintaan user): dunia dulu papan
## tak berujung yg ikut pemain (WorldBoundaryShape3D, tak ada tepi sama
## sekali) — skrg pulau BERBATAS dgn laut di sekelilingnya. Drpd bikin mesh
## collision 3D yg cocok persis dgn garis pantai berombak (rumit & berat
## utk mobile), cukup "dorong lembut" posisi pemain balik ke dalam kalau
## melewati COAST_MARGIN sblm garis air — dari sudut pandang pemain terasa
## spt nabrak air/pantai, padahal implementasinya cuma clamp radial simpel.
func _clamp_to_island() -> void:
	var x := global_position.x
	var z := global_position.z
	var theta := atan2(z, x)
	var r := sqrt(x * x + z * z)
	var max_r := IslandShape.radius_at(theta) - IslandShape.COAST_MARGIN
	if r > max_r and r > 0.001:
		var scale := max_r / r
		global_position.x = x * scale
		global_position.z = z * scale
		# redam komponen kecepatan yg mengarah keluar pulau (biar tak
		# "menekan" terus2an ke batas, terasa spt kena tahanan air/pasir)
		var out_dir := Vector3(x, 0.0, z).normalized()
		var outward := velocity.dot(out_dir)
		if outward > 0.0:
			velocity -= out_dir * outward

## Debu jejak kaki disederhanakan jadi berbasis JARAK TEMPUH (bukan lagi
## fase gait per-tulang manual — animasi kaki kini datang dari mocap asli,
## bukan dihitung tangan), tetap "banyak efek" saat bergerak cepat.
func _advance_footsteps(speed: float, delta: float) -> void:
	if speed <= 0.15:
		_dust_dist_accum = 0.0
		return
	_dust_dist_accum += speed * delta
	# RONDE INI (permintaan user: debu jejak harus "nyesuain gerakan kaki
	# pas nyentuh ke tanah tepat", bukan konstanta asal): klip lari/jog/
	# jalan mocap punya DUA kontak kaki per siklus -> laju kontak =
	# 2*speed_scale/panjang_klip, jadi stride (m per tapak) = speed/laju —
	# debu kiri/kanan muncul betul2 berimpit dgn tiap telapak menyentuh
	# tanah animasi yg TERLIHAT, termasuk saat speed_scale skill=1.4.
	var stride := _footstep_stride(speed)
	if _dust_dist_accum >= stride:
		_dust_dist_accum = fmod(_dust_dist_accum, stride)
		_dust_side = -_dust_side
		_spawn_footstep_dust(_dust_side)

var _stride_anim_len := {}   # cache panjang klip animasi per-nama state

## stride (meter per tapak) dari klip yg SEDANG diputar (lihat komentar
## _advance_footsteps). Fallback: konstanta lama bila klip tak tersedia.
func _footstep_stride(speed: float) -> float:
	if _anim == null or _anim_state.is_empty():
		return 0.55
	var clip_len: float = _stride_anim_len.get(_anim_state, -1.0)
	if clip_len < 0.0:
		var res := _anim.get_animation(_anim_state)
		clip_len = res.length if res else 0.0
		_stride_anim_len[_anim_state] = clip_len
	var ss := maxf(_anim.speed_scale, 0.001)
	if clip_len <= 0.0:
		return 0.75 if speed < MAX_SPEED * 0.45 else 0.55
	return clampf(speed * clip_len / (2.0 * ss), 0.35, 5.0)

func _apply_camera(delta: float) -> void:
	# --------- CABANG MODE BANGUN: top-down smooth (lihat blok BUILD_* di
	# atas); seluruh nilai di-lerp (permintaan "top down smooth"), pitch
	# tidak lagi di-clamp PITCH_MIN, zoom tak auto-balik (stabil utk edit).
	if build_cam:
		if _build_joy.length_squared() > 0.0004:
			_build_pan += Basis(Vector3.UP, yaw) * Vector3(_build_joy.x, 0.0, _build_joy.y) * BUILD_PAN_SPEED * delta
			_clamp_build_pan()
		pitch = lerpf(pitch, BUILD_CAM_PITCH, 1.0 - exp(-6.0 * delta))
		var bfocus := global_position + _build_pan + Vector3(0.0, CAM_FOCUS_HEIGHT, 0.0)
		cam_pivot.global_position = cam_pivot.global_position.lerp(bfocus, 1.0 - exp(-5.0 * delta))
		cam_pivot.rotation = Vector3(pitch, yaw, 0.0)
		var want_len := maxf(6.0, BUILD_CAM_DIST + _cam_zoom)
		cam_arm.spring_length = lerpf(cam_arm.spring_length, want_len, 1.0 - exp(-5.0 * delta))
		return
	var sens := 1.0
	if settings:
		sens = clampf(settings.camera_sens, 0.3, 2.5)
	yaw -= _look_vel.x * LOOK_K * sens * delta * 60.0 * 0.016
	var invert := -1.0 if (settings and settings.invert_y) else 1.0
	pitch = clampf(pitch + _look_vel.y * LOOK_K * sens * delta * 60.0 * 0.016 * invert, PITCH_MIN, PITCH_MAX)
	_look_vel = _look_vel.lerp(Vector2.ZERO, 1.0 - exp(-12.0 * delta))
	var focus := global_position + Vector3(0.0, CAM_FOCUS_HEIGHT, 0.0)
	if not _cam_snapped:
		cam_pivot.global_position = focus
		_cam_snapped = true
	else:
		cam_pivot.global_position = cam_pivot.global_position.lerp(focus, 1.0 - exp(-CAM_FOLLOW * delta))
	cam_pivot.rotation = Vector3(pitch, yaw, 0.0)
	_cam_extra = lerpf(_cam_extra, _speed01 * 1.2, 1.0 - exp(-3.0 * delta))
	# Auto-balik zoom manual (permintaan user): begitu pemain JALAN LAGI
	# (_speed01 dr gerak fisik nyata, bukan cuma input mentah) ATAU sudah
	# DIAM tanpa pinch baru selama CAM_ZOOM_RETURN_IDLE_S detik, _cam_zoom
	# di-ease balik ke 0 (= CAM_DIST) scr smooth (exponential, bukan lompat).
	_cam_zoom_idle_t += delta
	if _speed01 > 0.05 or _cam_zoom_idle_t > CAM_ZOOM_RETURN_IDLE_S:
		_cam_zoom = lerpf(_cam_zoom, 0.0, 1.0 - exp(-CAM_ZOOM_RETURN_RATE * delta))
	cam_arm.spring_length = maxf(2.0, CAM_DIST + _cam_extra + _cam_zoom + _cam_boost_arm)
	_shake = maxf(0.0, _shake - 1.6 * delta)
	var shake_power := _shake * _shake * 0.35
	var cam: Camera3D = $CameraPivot/CamArm/Cam
	cam.h_offset = (sin(_t * 43.0) * 0.72 + sin(_t * 67.0 + 0.8) * 0.28) * shake_power
	cam.v_offset = (sin(_t * 51.0 + 1.7) * 0.7 + sin(_t * 79.0) * 0.3) * shake_power
	# Kick FOV skill kecepatan (lihat press_speed_skill/_spawn_speed_boost_fx)
	_cam_boost_fov = lerpf(_cam_boost_fov, 0.0, 1.0 - exp(-3.2 * delta))
	_cam_boost_arm = lerpf(_cam_boost_arm, 0.0, 1.0 - exp(-3.2 * delta))
	cam.fov = 60.0 + _cam_boost_fov

## Putar model menghadap arah gerak, lalu pilih & mainkan klip mocap yang
## cocok dgn kecepatan/dash saat ini via AnimationPlayer (bukan lagi rotasi
## tulang manual per-frame).
func _animate_character(delta: float) -> void:
	if _facing.length_squared() > 0.01:
		var yaw_extra: float = SKIN_YAW_EXTRA.get(_skin_id, 0.0)
		var facing_yaw := atan2(-_facing.x, -_facing.z) + MODEL_YAW_OFFSET + yaw_extra
		_visual.rotation.y = lerp_angle(_visual.rotation.y, facing_yaw, 1.0 - exp(-14.0 * delta))

	if _anim == null:
		return

	# Dash = "sprint burst": klip lari yang SAMA (ANIM_SPRINT), bukan
	# animasi khusus — cuma kakinya dipercepat drastis via speed_scale, plus
	# jejak bayangan (lihat _spawn_afterimage, dipanggil dari _move()).
	if _dash_left > 0.0:
		if _anim_state != ANIM_SPRINT or not _anim.is_playing():
			_anim.play(ANIM_SPRINT, 0.06)
			_anim_state = ANIM_SPRINT
		_anim.speed_scale = DASH_ANIM_SPEED_SCALE
		return
	## speed_scale dasar state non-dash: 1.0 biasa; 1.4 selagi skill
	## gerak-cepat ×5 ON. RONDE INI (keluhan user: "animasi pas pake move
	## speed geraknya lambat aja walaupun geraknya cepat kayak yelan pas
	## pake skill; tapi nyesuain gerakan kaki pas nyentuh ke tanah tepat" —
	## versi bhs kasarnya: gerakan kaki di-2.8x terlihat PANIK/ngibrit tak
	## elegan): ala Yelan sprint = animasi mulus tenang MESKI tubuh melaju
	## super — 1.4 cukup utk kaki tak terasa "gliding", debu jejak di-
	## sinkronkan pula dgn kontak tanah animasi (lihat _advance_footsteps).
	var baseline_scale := 1.4 if _speed_skill else 1.0
	if not is_equal_approx(_anim.speed_scale, baseline_scale):
		_anim.speed_scale = baseline_scale

	# Histeresis: state saat ini menentukan ambang MASUK vs KELUAR, supaya
	# tak lompat-lompat pas speed01 pas di garis batas.
	var target := _anim_state
	match _anim_state:
		ANIM_SPRINT:
			if _speed01 < SPRINT_OFF:
				target = ANIM_JOG
		ANIM_JOG:
			if _speed01 >= SPRINT_ON:
				target = ANIM_SPRINT
			elif _speed01 < JOG_OFF:
				target = ANIM_WALK
		ANIM_WALK:
			if _speed01 >= JOG_ON:
				target = ANIM_JOG
			elif _speed01 < WALK_OFF:
				target = ANIM_IDLE
		_:
			target = ANIM_IDLE
			if _speed01 >= WALK_ON:
				target = ANIM_WALK
			if _speed01 >= JOG_ON:
				target = ANIM_JOG
			if _speed01 >= SPRINT_ON:
				target = ANIM_SPRINT

	if target != _anim_state or not _anim.is_playing():
		_anim.play(target, ANIM_BLEND)
		_anim_state = target

# =============== Serangan ===============

func _shoot_direction() -> Vector3:
	if _facing.length_squared() > 0.01:
		return _facing.normalized()
	return (Basis(Vector3.UP, yaw) * Vector3(0, 0, -1)).normalized()

func _hand_position(direction: Vector3) -> Vector3:
	# Sumber lontar sihir SKRG di peliharaan elemental api di bahu (permintaan
	# pengguna), bukan lagi di tangan/dada — fallback ke posisi lama kalau
	# entah kenapa node peliharaan belum/tak ada (harusnya selalu ada).
	if is_instance_valid(_fire_spirit):
		return _fire_spirit.global_position + direction * 0.12
	return _visual.global_position + Vector3.UP * CAST_HEIGHT + direction * 0.5

func _try_fire() -> void:
	if not is_ready or _fire_cooldown > 0.0:
		return
	_fire_cooldown = FIRE_COOLDOWN
	var direction := _shoot_direction()
	var origin := _hand_position(direction)
	var host: Node = world if is_instance_valid(world) and world.is_inside_tree() else get_parent()
	if host == null:
		return
	var bolt := ARCANE_BOLT.new()
	bolt.vel = direction * BOLT_SPEED + Vector3(velocity.x, 0, velocity.z) * 0.5 + Vector3.UP * BOLT_LIFT
	bolt.fx = _fx
	bolt.exclude_rids.append(get_rid())
	bolt.shake_target = self
	host.add_child(bolt)
	bolt.global_position = origin
	_shake = minf(_shake + 0.14, 0.8)
	if is_instance_valid(_fire_spirit):
		_fire_spirit.pulse()
	_play_shoot_sound()

func _play_shoot_sound() -> void:
	if not ResourceLoader.exists(SHOOT_SFX):
		return
	var sound := AudioStreamPlayer.new()
	sound.stream = load(SHOOT_SFX)
	sound.bus = "SFX"
	sound.pitch_scale = randf_range(1.05, 1.25)
	sound.finished.connect(sound.queue_free)
	add_child(sound)
	sound.play()

# =============== Rakitan visual: mannequin Quaternius (dicat ungu) ATAU skin Kanna ===============

## Bangun/rakit ulang badan pemain sesuai `skin_id` (SKIN_MANNEQUIN/SKIN_KANNA)
## DI DALAM _visual yg sudah ada (lihat _ready()). SELALU instance mannequin
## penuh (satu-satunya sumber Armature/AnimationPlayer/43 klip mocap valid,
## sekaligus jadi "puppeteer" tersembunyi utk retarget skin Kanna — baca
## komentar KANNA_RETARGET_PAIRS). Skin kanna = mannequin (mesh disembunyikan)
## + node Kanna terpisah yg pose-nya disalin per-frame oleh SkinRetarget.
func _build_character(skin_id: String) -> void:
	_skin_id = skin_id
	# bereskan sisa skin sebelumnya (oke jg kalau belum ada apa2)
	if is_instance_valid(_retarget):
		_retarget.queue_free()
	_retarget = null
	if is_instance_valid(_kanna):
		_kanna.queue_free()
	_kanna = null
	_kanna_skeleton = null

	_model = MANNEQUIN_SCENE.instantiate()
	_model.name = "Mannequin"
	_visual.add_child(_model)

	_anim = _model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_skeleton = _model.find_child("Skeleton3D", true, false) as Skeleton3D

	if _anim != null:
		_anim.playback_default_blend_time = ANIM_BLEND
		if _anim.has_animation(ANIM_IDLE):
			_anim.play(ANIM_IDLE)
			_anim_state = ANIM_IDLE

	if skin_id == SKIN_KANNA:
		_build_kanna_skin()
	else:
		_set_mannequin_mesh_visible(true)
		_paint_purple()

## Tampilkan/sembunyikan mesh mannequin (skeleton+animasinya TETAP aktif —
## AnimationPlayer tak peduli node terlihat/tidak, tulang tetap diupdate).
func _set_mannequin_mesh_visible(v: bool) -> void:
	for mi in _model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).visible = v

## Skin Kanna (VRM): mesh asli dgn warna/tekstur aslinya (TAK dicat ungu spt
## mannequin — "pasang skin karakter ini" berarti tampil sbg karakter itu
## sendiri), pose-nya digerakkan skeleton mannequin tersembunyi lewat
## SkinRetarget (lihat komentar kelasnya utk matematika konjugasi yaw-180).
func _build_kanna_skin() -> void:
	if _skeleton == null or _anim == null:
		push_warning("Kanna: skeleton/anim mannequin tak siap, batal — pakai mannequin ungu")
		_skin_id = SKIN_MANNEQUIN
		_set_mannequin_mesh_visible(true)
		_paint_purple()
		return
	_kanna = KANNA_SCENE.instantiate() as Node3D
	_kanna.name = "Kanna"
	_visual.add_child(_kanna)
	_kanna_skeleton = _kanna.find_child("Skeleton3D", true, false) as Skeleton3D
	if _kanna_skeleton == null or _kanna.find_children("*", "MeshInstance3D", true, false).is_empty():
		push_warning("Kanna: Skeleton3D/mesh tak ditemukan di kanna.glb, batal")
		_kanna.queue_free()
		_kanna = null
		_kanna_skeleton = null
		_skin_id = SKIN_MANNEQUIN
		_set_mannequin_mesh_visible(true)
		_paint_purple()
		return

	## skala keseluruhan tinggi Kanna ke tinggi mannequin (kamera/hover/
	## collider dikalibrasi utk tinggi mannequin) — diukur dr REST pose
	## (Head vs kaki), bukan angka tebakan, jd otomatis pas walau proporsi
	## badan beda jauh (chibi vs tinggi).
	var mannequin_h := _standing_height(_skeleton, "Head", "foot_l", "foot_r")
	var kanna_h := _standing_height(_kanna_skeleton, "DEF-Head", "DEF-Left ankle", "DEF-Right ankle")
	if mannequin_h > 0.01 and kanna_h > 0.01:
		var s: float = mannequin_h / kanna_h
		_kanna.scale = Vector3(s, s, s)

	_retarget = SkinRetarget.new()
	_retarget.name = "SkinRetarget"
	add_child(_retarget)
	_retarget.configure(_skeleton, _kanna_skeleton, KANNA_RETARGET_PAIRS)

	# POLE warna Kanna (laporan user: "karakter nya terlalu terang visual
	# kurang rapih") — file VRM itu pakai glTF extension KHR_materials_unlit:
	# semua meshnya dirender UNLIT (warna flat penuh, tak merespons cahaya/
	# ambient/bayangan scene sama sekali) — di dunia sore-hangat baru, karakter
	# jadi "nempel" terang sendirian & tak rapi visual. Diubah jadi LIT lembut
	# (kena lampu sore + bayangan sendiri yg rapi), tint albedo putih-hangat
	# krim pastel (bukan sepia/pudar, bukan juga jelas-acak), specular/roughness
	# dirapikan supaya kilau plastik berhenti & warna2nya jadi "nyambung" dgn
	# palet scene (lihat _polish_kanna_materials).
	_polish_kanna_materials()

	# barulah mannequin "puppeteer" disembunyikan (pose tetap jalan utk dicopy)
	_set_mannequin_mesh_visible(false)

## Pole material mesh Kanna: override material bawaan VRM (unlit penuh) jadi
## mat_lit pastel hangat yg TETAP mempertahankan TEKSTUR asli (wajah/rambut/
## baju/mata) — material StandardMaterial3D di-duplicate (bukan di-share)
## supaya tak mengubah file-nya & terpisah dari material lain — lalu shading
## diubah: UNLIT→PER_PIXEL-lit (kena cahaya sore hangat & punya bayangan
## sendiri rapi), tint albedo krim-hangat pastel (0.02-0.06 derajat tint,
## cukup utk keharmonisan warna, tidak mengubah tekstur), roughness naik
## (kilau plastik-oranye VRM berhenti, ganti sheen lembut), specular redup.
func _polish_kanna_materials() -> void:
	for mi in _kanna.find_children("*", "MeshInstance3D", true, false):
		var mesh_inst := mi as MeshInstance3D
		if mesh_inst == null or mesh_inst.mesh == null:
			continue
		for surf in range(mesh_inst.mesh.get_surface_count()):
			var m := mesh_inst.get_active_material(surf)
			var new_mat: StandardMaterial3D = null
			if m is StandardMaterial3D:
				new_mat = m.duplicate() as StandardMaterial3D
			else:
				new_mat = StandardMaterial3D.new()
				new_mat.albedo_color = Color(1.0, 1.0, 1.0)
			new_mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
			new_mat.albedo_color = Color(1.02, 0.99, 0.94)
			new_mat.roughness = 0.82
			new_mat.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
			new_mat.metallic = 0.0
			new_mat.back_light = 0.0
			new_mat.disable_receive_shadows = false
			new_mat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
			# HOTFIX "visual kurang rapih": mesh transparan VRM (rambut/alis/
			# mata anime) digambar dgn urutan serampangan kalau polos ALPHA-
			# biasa -> tampak tembus-tak-karuan. ALPHA_DEPTH_PRE_PASS menulis
			# depth dulu sebelum blend, jadi siluet transparannya rapi stabil
			# dr sudut mana pun (standar umum utk karakter anime/VRM di Godot).
			if new_mat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
				new_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
			mesh_inst.set_surface_override_material(surf, new_mat)

## Tinggi berdiri (Head - rata2 kaki) dari REST POSE sebuah skeleton, dipakai
## _build_kanna_skin() utk menyamakan skala tanpa perlu angka tebakan manual.
func _standing_height(skel: Skeleton3D, head_name: String, foot_l_name: String, foot_r_name: String) -> float:
	if skel == null:
		return 0.0
	var head_i := skel.find_bone(head_name)
	var fl_i := skel.find_bone(foot_l_name)
	var fr_i := skel.find_bone(foot_r_name)
	if head_i < 0 or (fl_i < 0 and fr_i < 0):
		return 0.0
	var head_y: float = skel.get_bone_global_rest(head_i).origin.y
	var foot_y: float
	if fl_i >= 0 and fr_i >= 0:
		foot_y = (skel.get_bone_global_rest(fl_i).origin.y + skel.get_bone_global_rest(fr_i).origin.y) * 0.5
	elif fl_i >= 0:
		foot_y = skel.get_bone_global_rest(fl_i).origin.y
	else:
		foot_y = skel.get_bone_global_rest(fr_i).origin.y
	return head_y - foot_y

## Kedua material sumber (M_Main oranye, M_Joints ungu) TANPA tekstur ->
## override total aman, tak kehilangan detail UV apa pun.
func _paint_purple() -> void:
	var mats := [Materials.toon(BODY_COLOR, true, 0.012, 0.55), Materials.toon(JOINT_COLOR, false, 0.0, 0.35)]
	for mi in _model.find_children("*", "MeshInstance3D", true, false):
		var mesh_inst := mi as MeshInstance3D
		if mesh_inst == null or mesh_inst.mesh == null:
			continue
		var surfaces := mesh_inst.mesh.get_surface_count()
		for i in range(surfaces):
			mesh_inst.set_surface_override_material(i, mats[i % mats.size()])

## Ganti skin (permintaan user: "pake 2 karakter ada icon ganti karakter" +
## "setiap switch karakter kek ada efek sinar glitch") — dipanggil dari HUD
## (tombol baru, lihat hud.gd BtnSkin). _visual (fire_spirit+aura) TAK
## dibongkar, cuma isi _model di dalamnya yg ditukar.
func cycle_skin() -> void:
	if _skin_switching or not is_ready:
		return
	_skin_switching = true
	var next_id := SKIN_KANNA if _skin_id == SKIN_MANNEQUIN else SKIN_MANNEQUIN
	_spawn_skin_switch_fx(global_position + Vector3(0.0, 0.9, 0.0))
	# kedip cepat (kesan "glitch") sebelum model lama disembunyikan, biar
	# proses bongkar-pasang di baliknya tak kelihatan nge-pop.
	var flicker := create_tween()
	for i in range(4):
		flicker.tween_property(_visual, "visible", false, 0.0)
		flicker.tween_interval(0.045)
		flicker.tween_property(_visual, "visible", true, 0.0)
		flicker.tween_interval(0.045)
	await flicker.finished
	_visual.visible = false
	if is_instance_valid(_model):
		_model.queue_free()
	_model = null
	_anim = null
	_skeleton = null
	await get_tree().create_timer(0.10).timeout
	_build_character(next_id)
	_visual.visible = true
	_skin_switching = false

## Ledakan partikel cahaya + kilat lampu sesaat, kesan "teleport glitch"
## pas ganti skin (permintaan user "efek sinar glitch"). Ditaruh sbg anak
## CharacterBody3D langsung (BUKAN _visual) spy tak ikut disembunyikan oleh
## flicker _visual di cycle_skin() & tetap ada meski _model lg dibongkar-pasang.
func _spawn_skin_switch_fx(at: Vector3) -> void:
	var burst := GPUParticles3D.new()
	burst.name = "SkinSwitchFX"
	burst.amount = 46
	burst.lifetime = 0.55
	burst.one_shot = true
	burst.explosiveness = 0.95
	burst.local_coords = false
	burst.fixed_fps = 60
	burst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(burst)
	burst.global_position = at
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3.UP
	mat.spread = 180.0
	mat.initial_velocity_min = 1.4
	mat.initial_velocity_max = 3.6
	mat.gravity = Vector3.ZERO
	mat.damping_min = 2.0
	mat.damping_max = 3.5
	mat.scale_min = 0.05
	mat.scale_max = 0.15
	mat.color_ramp = _ramp(
		[0.0, 0.4, 1.0],
		[Color(0.75, 0.95, 1.0, 1.0), Color(0.55, 0.75, 1.0, 0.85), Color(0.4, 0.6, 1.0, 0.0)])
	burst.process_material = mat
	var qm := QuadMesh.new()
	qm.size = Vector2(0.09, 0.09)
	qm.material = _fx_mat(_soft_tex(0.2), true, Color(0.8, 0.95, 1.0, 0.9))
	burst.draw_pass_1 = qm
	burst.emitting = true

	var flash := OmniLight3D.new()
	flash.name = "SkinSwitchFlash"
	flash.light_color = Color(0.78, 0.93, 1.0)
	flash.omni_range = 4.5
	flash.light_energy = 0.0
	add_child(flash)
	flash.global_position = at
	var tw := create_tween()
	tw.tween_property(flash, "light_energy", 3.4, 0.09)
	tw.tween_property(flash, "light_energy", 0.0, 0.4)
	tw.finished.connect(func():
		if is_instance_valid(flash):
			flash.queue_free())

	var t := get_tree().create_timer(1.0)
	t.timeout.connect(func():
		if is_instance_valid(burst):
			burst.queue_free())

## Peliharaan elemental api kecil di bahu (permintaan pengguna: "spirit
## elemental api kecil ... nembakin sihirnya dari situ, kayak peliharaan,
## goyang goyang jangan kaku") — lihat fire_spirit.gd utk gerak idle
## non-kaku (melayang+orbit+puter). Ditaruh sbg anak _visual spy ikut
## rotasi/posisi badan, tapi py animasi mengambangnya SENDIRI tak tergantung
## animasi tubuh. _hand_position() skrg mengembalikan posisi node ini —
## artinya tembakan sihir scr visual keluar dari peliharaan ini, bukan tangan.
func _build_fire_spirit() -> void:
	_fire_spirit = FIRE_SPIRIT.new()
	_fire_spirit.name = "FireSpirit"
	_visual.add_child(_fire_spirit)

## Benang-benang trail skill gerak-cepat (permintaan user: "trail mov speed
## jangan pake after image tapi kayak semacam benang smooth gitu kayak
## karakter yelan di genshin ... pas pake move speed efek benang juga dapet
## di spirit api kecil itu"): 3 pita tipis pastel-biru dari punggung pemain
## (beda tinggi/fase supaya "mengalir" natural, tak serempak kaku) + 1 pita
## ungu-pastel di spirit api (kontrak yang dijanjikan). Target on/off diatur
## per-frame dari _process (lihat bawah) — benang mengaum hanya saat skill
## speed AKTIF dan gerakan benar2 cepat.
func _build_speed_threads() -> void:
	# RONDE INI (keluhan user: "speed trailnya masih jelek ... benang itu
	# kan tipis ungu menyala"): BENANG SUNGGUHAN sekarang — lebar DIPANGKAS
	# habis (0.060->0.022 dst; benang, bukan pita) & warnanya UNGU MENYALA
	# HDR (komponen > 1.0 supaya tembus glow_hdr_threshold 1.35 -> berpendar
	# bercahaya via bloom; bukan lagi biru-pastel matte yg terasa hambar).
	var specs: Array = [
		# [anchor, offset lokal anchor, tint HDR ungu-menyala, lebar, fase]
		# (ronde ini "masih kurang" -> sedikit ditebalkan dr 0.022 dst,
		# tetap benang; menyala HDR diperkuat di speed_thread HDR_GAIN)
		[_visual, Vector3(0.00, 1.08, 0.00), Color(1.50, 0.35, 2.00), 0.030, 0.0],
		[_visual, Vector3(0.13, 1.30, 0.00), Color(1.75, 0.55, 2.10), 0.024, 2.1],
		[_visual, Vector3(-0.13, 0.84, 0.00), Color(1.35, 0.30, 2.20), 0.022, 4.2],
		[_fire_spirit, Vector3.ZERO,        Color(1.70, 0.55, 2.20), 0.022, 1.3],
	]
	for spec in specs:
		var t := SPEED_THREAD.new()
		add_child(t)
		t.setup(spec[0], spec[1], spec[2], spec[3], spec[4])
		_speed_threads.append(t)

## Aura sihir ungu-biru yang melayang terus-menerus di sekitar karakter —
## permintaan pengguna "banyak efek" berlaku juga saat idle, bukan cuma saat
## menyerang. Dipertahankan lintas-ronde walau badan kini model mannequin.
func _build_aura() -> void:
	_aura_particles = GPUParticles3D.new()
	_aura_particles.name = "ArcaneAura"
	_aura_particles.amount = 26
	_aura_particles.lifetime = 1.6
	_aura_particles.randomness = 0.4
	_aura_particles.local_coords = false
	_aura_particles.fixed_fps = 60
	_aura_particles.interpolate = true
	_aura_particles.visibility_aabb = AABB(Vector3(-8, -2, -8), Vector3(16, 8, 16))
	_aura_particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_aura_particles.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	_visual.add_child(_aura_particles)

	_aura_material = ParticleProcessMaterial.new()
	_aura_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	_aura_material.emission_ring_axis = Vector3.UP
	_aura_material.emission_ring_radius = 0.42
	_aura_material.emission_ring_inner_radius = 0.30
	_aura_material.emission_ring_height = 0.05
	_aura_material.direction = Vector3.UP
	_aura_material.spread = 12.0
	_aura_material.initial_velocity_min = 0.16
	_aura_material.initial_velocity_max = 0.42
	_aura_material.gravity = Vector3.ZERO
	_aura_material.orbit_velocity_min = 0.18
	_aura_material.orbit_velocity_max = 0.30
	_aura_material.tangential_accel_min = 0.05
	_aura_material.tangential_accel_max = 0.12
	_aura_material.scale_min = 0.4
	_aura_material.scale_max = 0.9
	_aura_material.scale_curve = _curve([Vector2(0.0, 0.2), Vector2(0.3, 1.0), Vector2(1.0, 0.0)], 1.0)
	_aura_material.color_ramp = _ramp(
		[0.0, 0.3, 0.75, 1.0],
		[Color(0.55, 0.30, 1.0, 0.0), Color(0.62, 0.40, 1.0, 0.75), Color(0.35, 0.65, 1.0, 0.45), Color(0.2, 0.4, 1.0, 0.0)])
	_aura_particles.process_material = _aura_material
	var trail_mesh := QuadMesh.new()
	trail_mesh.size = Vector2(0.10, 0.10)
	trail_mesh.material = _fx_mat(_soft_tex(0.15), true, Color(0.6, 0.4, 1.0, 0.7))
	_aura_particles.draw_pass_1 = trail_mesh
	_aura_particles.emitting = true
	_base_amounts[_aura_particles] = _aura_particles.amount

## Bayangan dash: SATU ghost abu-abu-berasap, bentuk KARAKTER PERSIS &
## pose DIBEKUKAN di momen tombol ditekan. Revisi ronde ini (laporan user
## lewat screenshot): ghost lama (klon skeleton bikinan tangan per-bone)
## tampil "ngacak kayak error" khusus di skin KANNA — struktur skeleton
## VRM rupanya tak cocok dgn rekonstruksi manual nam<->parent/index.
## Solusinya sekarang ROBUST & sederhana: ghost = src_root.duplicate()
## (seluruh subpohon model, TERMASUK skeleton & skin mesh-nya apa adanya
## — apa pun keunikan struktur bawaan importer ikut terduplikasi), lalu
## semua penggerak di dalam duplikat DIMATIKAN (AnimationPlayer dll) dan
## tiap Skeleton3D duplikat di-STAMP pose-nya satu-kali dari skeleton
## sumber yg sepadan-lewat-path (set_bone_global_pose_override persistent)
## -> hasil akhir: siluet pose-momen-dash yg TAK PERNAH ikut animasi lagi.
## Fade DIJALANKAN MANUAL per-frame oleh inner-class DashGhost (TAK lg
## lewat Tween pada "shader_parameter/*" — pola tsb menyebabkan ghost
## "tertinggal permanen" di perangkat user: callback free tak pernah
## terpanggil). Efek asap bergoyang tetap dilengkapi _spawn_ghost_smoke.
func _spawn_afterimage() -> void:
	# sumber mesh & skeleton = skin yg AKTIF (kanna: node kanna + skeletonnya;
	# mannequin: _model + _skeleton spt biasa -- jaringan mesh mannequin lg
	# disembunyikan TERTUTUP krn di sini dipilih eksplisit per skin).
	var src_root: Node3D = _model
	if _skin_id == SKIN_KANNA:
		src_root = _kanna
	if not is_instance_valid(src_root):
		return
	var parent := get_parent()
	if parent == null:
		return
	var ghost := src_root.duplicate() as Node3D
	if ghost == null:
		return
	ghost.name = "DashAfterimage"
	parent.add_child(ghost)
	ghost.global_transform = src_root.global_transform

	# 1) Matikan SEMUA animator bawaan di dalam duplikat spy duplikat tak
	#    hidup sendiri (user: "bayangan nya gk gerak").
	for n in ghost.find_children("*", "AnimationPlayer", true, false):
		var ap := n as AnimationPlayer
		if ap != null:
			ap.stop()
			ap.playback_active = false
			ap.set_process(false)
	for n in ghost.find_children("*", "AnimationTree", true, false):
		var at := n as AnimationTree
		if at != null:
			at.active = false
			at.set_process(false)

	# 2) STAMP pose beku: tiap Skeleton3D DALAM duplikat diberi override
	#    global-pose PERSISTEN dari skeleton aslinya yg sepadan-menurut-path
	#    (path relatif di dalam subpohon identik sesudah duplicate()).
	for n in ghost.find_children("*", "Skeleton3D", true, false):
		var gskel := n as Skeleton3D
		var rel := ghost.get_path_to(gskel)
		var sskel := src_root.get_node_or_null(rel) as Skeleton3D
		if sskel == null:
			continue
		var cnt := mini(gskel.get_bone_count(), sskel.get_bone_count())
		for i in cnt:
			gskel.set_bone_global_pose_override(i, sskel.get_bone_global_pose(i), 1.0, true)

	# 3) Ganti SEMUA bahan mesh duplikat jadi asap abu-abu ber-wooble
	#    (afterimage_smoke.gdshader) — siluet karakter kebaca, permukaannya
	#    "goyangan asap" (permintaan user), pakai SATU material dipakai ulang.
	var smoke_mat := ShaderMaterial.new()
	smoke_mat.shader = AFTERIMAGE_SHADER
	var made_any := false
	for mi in ghost.find_children("*", "MeshInstance3D", true, false):
		var mesh_inst := mi as MeshInstance3D
		if mesh_inst == null or mesh_inst.mesh == null:
			continue
		mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh_inst.extra_cull_margin = maxf(mesh_inst.extra_cull_margin, 1.5)
		for s in range(mesh_inst.mesh.get_surface_count()):
			mesh_inst.set_surface_override_material(s, smoke_mat)
		made_any = true
	if not made_any:
		ghost.queue_free()
		return

	# 4) Awan asap partikel di sekeliling + peleburan DETERMINISTIK manual
	#    (DashGhost._process menaikkan uniform life01 -> 1 lalu queue_free
	#    diri sendiri — tanpa Tween properti-shader sama sekali).
	_spawn_ghost_smoke(ghost)
	var driver := DashGhost.new()
	driver.fade = AFTERIMAGE_FADE
	driver.smoke_mat = smoke_mat
	ghost.add_child(driver)

## Awan asap bergoyang di sekeliling ghost dash (permintaan user: "efek asap
## tapi masih ada bentukan karakter nya cuman kayak goyangan asap gitu,
## manequin juga sama"). Partikel bola-bola abu-abu pastel lembut (blend
## NORMAL-mix dengan alpha, bukan additive-terik, spy nyambung dgn palet sore
## hangat & tetap halus pastel), goncangan orbit/tangensial kecil supaya
## bergoyang (bukan statis), mengembang & naik pelan, lalu memudar — ikut
## hilang sendiri saat ghost-nya di-queue_free (anak langsung dr ghost).
func _spawn_ghost_smoke(ghost: Node3D) -> void:
	var p := GPUParticles3D.new()
	p.name = "GhostSmoke"
	p.amount = 18
	p.lifetime = 0.85
	p.one_shot = false
	p.explosiveness = 0.85
	p.local_coords = false
	p.fixed_fps = 30
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-2, -2, -2), Vector3(4, 5, 4))
	ghost.add_child(p)
	p.position = Vector3(0.0, 0.9, 0.0)   # tinggi torso karakter

	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3.UP
	mat.spread = 100.0
	mat.initial_velocity_min = 0.05
	mat.initial_velocity_max = 0.32
	# gravitasi NEGATIF-tipis = asap mengapung naik pelan (bukan jatuh
	# turun), sesuai "asap bergoyang" yg diminta user; damping udara besar
	# spy gerakannya lembut & tak liar berhamburan.
	mat.gravity = Vector3(0.0, -0.06, 0.0)
	mat.damping_min = 0.8
	mat.damping_max = 1.4
	mat.orbit_velocity_min = 0.04
	mat.orbit_velocity_max = 0.12
	mat.tangential_accel_min = 0.04
	mat.tangential_accel_max = 0.10
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 0.34
	mat.scale_min = 0.14
	mat.scale_max = 0.26
	mat.scale_curve = _curve([Vector2(0.0, 0.5), Vector2(0.35, 1.0), Vector2(1.0, 1.35)], 1.0)
	mat.color_ramp = _ramp(
		[0.0, 0.5, 1.0],
		[Color(0.55, 0.58, 0.65, 0.0), Color(0.62, 0.66, 0.72, 0.34), Color(0.70, 0.74, 0.80, 0.0)])
	p.process_material = mat
	var puff := _quad(Vector2(0.28, 0.28), _fx_mat(_soft_tex(0.22), false, Color(0.80, 0.82, 0.86, 0.7)))
	p.draw_pass_1 = puff
	p.emitting = true

func _spawn_dash_shimmer() -> void:
	var parent := get_parent()
	if parent == null:
		return
	var shimmer := MeshInstance3D.new()
	shimmer.name = "DashShimmer"
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.30
	mesh.bottom_radius = 0.36
	mesh.height = MODEL_HEIGHT * 0.5
	shimmer.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.55, 0.35, 1.0, 0.5)
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	shimmer.material_override = mat
	parent.add_child(shimmer)
	shimmer.global_position = global_position + Vector3.UP * (HOVER + MODEL_HEIGHT * 0.5)
	shimmer.rotation.y = _visual.global_rotation.y
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(mat, "albedo_color", Color(0.3, 0.15, 0.5, 0.0), 0.55)
	tween.parallel().tween_property(shimmer, "scale", Vector3(1.3, 0.4, 1.3), 0.55)
	tween.tween_callback(shimmer.queue_free)

## Debu jejak kaki — burst kecil sekali-pakai, dipicu berkala berdasar jarak
## tempuh (lihat _advance_footsteps). Ditaruh dekat kaki dgn offset kiri/
## kanan bergantian, cukup dekat tanah tanpa perlu lacak tulang kaki persis.
func _spawn_footstep_dust(side: float) -> void:
	var parent := get_parent()
	if parent == null:
		return
	var right := (Basis(Vector3.UP, _visual.rotation.y) * Vector3.RIGHT)
	var world_pos := global_position + right * (side * 0.10)
	world_pos.y = global_position.y + 0.02

	var p := GPUParticles3D.new()
	p.name = "FootDust"
	p.amount = maxi(3, int(round(7 * _fx)))
	p.lifetime = 0.5
	p.one_shot = true
	p.explosiveness = 0.95
	p.randomness = 0.5
	p.local_coords = false
	p.fixed_fps = 60
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.05
	pm.direction = Vector3.UP
	pm.spread = 60.0
	pm.initial_velocity_min = 0.3
	pm.initial_velocity_max = 0.9
	pm.gravity = Vector3(0, 0.4, 0)
	pm.damping_min = 1.0
	pm.damping_max = 2.0
	pm.scale_min = 0.5
	pm.scale_max = 1.0
	pm.scale_curve = _curve([Vector2(0, 0.3), Vector2(0.4, 1.0), Vector2(1, 1.6)], 1.6)
	pm.color_ramp = _ramp([0.0, 0.3, 1.0], [Color(0.55, 0.48, 0.42, 0.0), Color(0.6, 0.54, 0.48, 0.35), Color(0.65, 0.6, 0.55, 0.0)])
	p.process_material = pm
	p.draw_pass_1 = _quad(Vector2(0.14, 0.14), _fx_mat(_soft_tex(0.1), false, Color.WHITE))
	parent.add_child(p)
	p.global_position = world_pos
	p.emitting = true
	get_tree().create_timer(p.lifetime + 0.3).timeout.connect(p.queue_free)

# =============== helper FX kecil (gradient/quad/material) ===============

func _fx_mat(tex: Texture2D, additive: bool, tint: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = tex
	mat.albedo_color = tint
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.disable_receive_shadows = true
	return mat

func _quad(size: Vector2, mat: Material) -> QuadMesh:
	var mesh := QuadMesh.new()
	mesh.size = size
	mesh.material = mat
	return mesh

func _soft_tex(core: float) -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, clampf(core, 0.0, 0.9), 1.0])
	gradient.colors = PackedColorArray([Color.WHITE, Color(1, 1, 1, 0.6), Color(1, 1, 1, 0)])
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.width = 32
	tex.height = 32
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	return tex

func _ramp(offsets: Array, colors: Array) -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array(offsets)
	gradient.colors = PackedColorArray(colors)
	var tex := GradientTexture1D.new()
	tex.gradient = gradient
	return tex

func _curve(points: Array, max_v: float) -> CurveTexture:
	var curve := Curve.new()
	curve.max_value = max_v
	for point in points:
		curve.add_point(point)
	var tex := CurveTexture.new()
	tex.curve = curve
	return tex
