# BACA INI — Ronde-46: pivot balik dari TANK ke penyihir anime (bag. A: karakter)

## Alur repository

- Remote `origin` dicek sebelum ronde ini; hanya `arena/01a0dca7-unity` yang
  ditemukan, tidak ada branch sesi lain untuk di-merge.
- Branch sesi tetap `arena/01a0dca7-unity`.
- Tidak merge ke `main` dan tidak menutup PR.
- `.github/workflows/apk_release.yml` tetap mendaftarkan branch sesi pada
  `on.push.branches`.

## Latar belakang pivot (lagi)

Ronde-45 memindahkan seluruh game dari mage ke TANK (kamera orang-ketiga di
belakang tank, meriam tap-tembak) dan berhasil terbit lewat CI. Setelah
melihat hasilnya, pengguna menilai tank "kurang/jelek" dan minta pivot
**kembali ke tema sihir**, kali ini dengan tuntutan visual jauh lebih tinggi:
karakter bergaya anime beranimasi + banyak efek + dunia yang lebih hidup.

Keputusan eksplisit pengguna (lewat serangkaian pertanyaan klarifikasi):
1. **Buang tank total**, balik ke karakter penyihir/spellcaster.
2. Karakter: **bergaya anime**, TAPI harus **100% prosedural** — TIDAK ada
   file model eksternal (.vrm/.glb/.fbx) yang diimpor. Ini bukan preferensi,
   melainkan keterbatasan teknis yang sudah dikonfirmasi lewat percobaan
   nyata: sandbox pengerjaan ini memblokir unduhan biner via `curl`/`wget`
   (SSL_ERROR_SYSCALL ke domain CDN seperti githubusercontent.com,
   arweave.net), dan `fetch_page` (yang punya jalur jaringan sendiri)
   MERUSAK byte biner karena mengonversi hasil jadi teks/markdown —
   dikonfirmasi dengan file GLB asli yang pengguna berikan via link Google
   Drive: filenya valid (header glTF terbaca), tapi byte-nya korup begitu
   lewat `fetch_page`. Pengguna juga tidak bisa melampirkan file secara
   langsung sebagai lampiran chat saat ditawarkan. Jalur satu-satunya yang
   sah untuk aset 3D eksternal (lampiran chat langsung) belum pernah
   berhasil dicoba di sesi ini.
3. Dunia: **tetap datar tak berbatas** (bukan bikin terrain baru berbukit),
   tapi tanah/rumputnya dibuat **lebat & realistis** (bukan grid biru
   blueprint yang sekarang) — direncanakan Bagian C ronde ini.
4. Efek: fokus pada **satu mantra andalan** (gaya Zoltraak lama) yang dipoles
   jauh lebih megah/detail partikelnya — BUKAN menambah variasi mantra baru.
   Direncanakan Bagian B ronde ini.

## Perubahan Bagian A (commit ini): karakter penyihir anime prosedural

### Dihapus / diganti nama

- Kode tank di `player.gd` (hull+turret+meriam) — **ditulis ulang total**
  jadi karakter penyihir (nama file & `player.tscn` dipertahankan supaya
  `game_root.gd`/probe tidak perlu berubah).
- `tank_shell.gd` → **direname** jadi `arcane_bolt.gd` (proyektil sihir kecil
  untuk tap attack biasa; arsitektur ballistic+raycast yang sama, dipoles
  ulang warnanya jadi kristal arcane ungu-biru, bukan lagi selongsong peluru
  oranye).
- `fireball_core.gdshader`, `fireball_shell.gdshader`, `shockwave.gdshader`,
  `fire_explosion.gd` — **direcolor** dari tema api-oranye (tank) jadi tema
  arcane ungu-biru-lavender. Nama file tetap "fire_*"/"fireball_*" (warisan
  generik helper FX yang sudah dipakai ulang & direcolor beberapa kali
  lintas-ronde: mana biru → api tank → arcane ungu-biru); isinya sudah
  100% bertema sihir.
- `player.tscn`: collision `BoxShape3D` (tank) → `CapsuleShape3D` (humanoid).

### Karakter baru: penyihir bergaya anime, 100% prosedural

Dirakit murni dari primitive Godot (sphere/cone/cylinder/capsule/torus) +
shader cel-shading yang SUDAH ADA di project (`Materials.toon()` dari
`shaders_materials/materials.gd`, memakai `toon.gdshader` 3-band + outline
inverted-hull `outline.gdshader` otomatis via `next_pass`) — TIDAK ADA
tekstur wajah atau file model eksternal:

- Proporsi chibi-anime: kepala besar, badan kecil berjubah.
- Kepala: sphere kulit + **mata besar bulat** (sclera+iris+kilau unshaded,
  ciri khas mata anime berbinar) + **pipi merona** (quad lembut) — semua
  geometri, bukan tekstur, supaya tidak berisiko salah wrap UV (tak bisa
  dipratinjau visual di sandbox ini).
- Rambut: poni sphere + 7 jambul runcing (cone) tersebar + 2 kuncir
  (capsule) di belakang, warna lavender terang.
- Topi penyihir runcing (brim + cone) dengan pita emas — siluet ikonik.
- Jubah ungu (cylinder tapered) + sabuk (torus emas).
- Lengan: 2 capsule dengan **animasi ayun prosedural** (tanpa skeleton,
  murni rotasi pivot berbasis `sin(t)`), disinkronkan ke kecepatan gerak.
- **Aura partikel ungu-biru** yang melayang terus-menerus mengelilingi
  karakter (bukan cuma saat menyerang) — permintaan "banyak efek" berlaku
  juga saat idle.
- Idle bob halus + ayunan rambut mengikuti arah gerak.

### Gerak & kamera

Arsitektur third-person murni ikut swipe + gerak bebas relatif kamera
**tidak diubah** (terbukti stabil lintas-ronde sejak mage awal). Skala
gerak dikembalikan ke penyihir jalan kaki (lebih lincah dari tank):
`MAX_SPEED=9.0`, jarak kamera `CAM_DIST=7.6` (turun dari 9.5 milik tank).
Dash (burst cepat) dipertahankan dengan efek kilau ungu saat dipakai.

### Dunia

- `world.gd`, `wall.gd`, `wall_system.gd`: hanya **komentar header**
  diperbarui (dari "medan tempur tank" jadi "rintangan & pemandangan dunia
  sihir terbuka") — dinding/reruntuhan destructible dari ronde-44
  **dipertahankan** sebagai reruntuhan kuno yang bisa dihancurkan mantra,
  bukan dihapus.
- Tanah masih grid-blueprint biru (belum diganti) — itu Bagian C ronde ini,
  BELUM dikerjakan di commit ini.
- **Belum ada musuh di dunia** (monster_system dihapus ronde-45, roster
  tank musuh ronde-45 bag. B tak pernah dibuat). Ini belum diminta ulang
  oleh pengguna di ronde-46 — perlu ditanyakan lagi jika kombat/musuh mau
  dikembalikan.

### Probe CI

`dev_probe/fire_attack_check.gd` diperbarui mengikuti rename
`tank_shell.gd` → `arcane_bolt.gd` (semua string suffix yang dicek). Logika
& konstanta timing (`COOLDOWN_WAIT_SEC=3.0`) dipertahankan — siklus hidup
penuh `arcane_bolt.gd` (jatuh bebas + delay `queue_free()` 1 dtk) dihitung
ulang dan masih di bawah 3 detik.

## Ronde-46 bag. A2: perbaikan siluet "stickman" + animasi lari detail

Setelah bag. A terbit, pengguna menilai karakternya "kayak stickman" (lengan
tipis + kaki tak terlihat karena tertutup jubah panjang) dan minta animasi
lari lebih detail. Perbaikan (`player.gd` saja, tidak ada file lain diubah):

- **Kaki kini terlihat**: 2 segmen per kaki (paha `HipPivot*`+ betis
  `ShinPivot*`) dengan sepatu bot gelap di ujung, bukan disembunyikan jubah
  sampai tanah.
- **Tunik dipendekkan & di-flare**: dari bahu (`SHOULDER_Y=0.98`, radius
  sempit `TUNIC_TOP_R=0.185`) melebar ke pinggul (`HIP_Y=0.55`, radius
  `TUNIC_BOTTOM_R=0.29`) — siluet "A-line", bukan kerucut polos menyentuh
  tanah. Ditambah kerah kecil di leher.
- **Lengan 2 segmen** (lengan atas + lengan bawah/siku) + bantalan bahu bulat
  + manset di pergelangan — lebih tebal & bervolume, tidak lagi seperti
  tongkat.
- **Cape 3-segmen** di punggung yang berkibar mengikuti kecepatan gerak
  (`_cape_segs`) — memecah siluet polos dari belakang (sudut kamera utama).
- **Gait berbasis jarak tempuh** (`_gait_phase` maju sebanding `speed*delta`,
  bukan `sin(waktu)` murni) supaya frekuensi langkah menyesuaikan kecepatan
  asli. Kaki kiri/kanan berlawanan fasa; lengan berlawanan fasa dengan kaki
  SEBERANG (gaya jalan kontralateral manusia asli); betis menekuk saat kaki
  mengayun maju (ilusi lutut sederhana, tanpa IK); siku menekuk dinamis;
  badan (`_upper`) condong ke depan saat berlari (`TORSO_LEAN_MAX=9°`) +
  bob per langkah.
- **Debu jejak kaki**: burst partikel kecil sekali-pakai dipicu setiap kaki
  mendarat (`_spawn_footstep_dust`, dideteksi dari perubahan tanda
  `sin(gait_phase)` positif→negatif per kaki).
- Idle tetap punya animasi terpisah (napas halus, ayun ringan) — tidak
  memakai sistem gait yang sama supaya tidak "berjalan di tempat" saat diam.

## Ronde-46 bag. A3: pivot ke stickman ungu literal + animasi biomekanik

Pengguna mengirim gambar referensi (ikon stick figure universal: kepala
bulat + garis lurus torso/lengan/kaki) dan minta karakter dibuat betulan
menyerupai itu (warna ungu dipertahankan), plus minta animasi jalan/lari/
dash yang benar berdasarkan riset, bukan tebakan. Perubahan (`player.gd` +
`player.tscn` saja):

### Bentuk tubuh — literal stickman

- SEMUA elemen "berdaging" dari bag. A/A2 dihapus: tunik/jubah, cape,
  bantalan bahu, manset lengan, sepatu bot, rambut (poni/jambul/kuncir),
  topi penyihir, mata (sclera/iris/kilau), pipi merona.
- Diganti: kepala bulat polos (`SphereMesh`, tanpa wajah) + garis tunggal
  seragam (`CapsuleMesh` radius `LIMB_RADIUS=0.065` konstan) untuk torso,
  lengan atas+bawah, paha+betis — semua 1 warna ungu (`STICK_COLOR`).
  Skeleton/pivot sendi (`HipPivot*`, `ShinPivot`, `ArmPivot*`,
  `ForearmPivot`) dari bag. A2 **dipertahankan apa adanya** supaya tetap
  bisa menekuk saat animasi — hanya "daging" di sekitarnya yang dilucuti.
- `_hips` (Node3D baru) memisahkan kelompok kaki dari `_upper` (torso+
  lengan+kepala) supaya keduanya bisa berotasi Y independen (twist
  pinggul vs counter-twist bahu, lihat di bawah).
- `player.tscn`: collision `CapsuleShape3D` diperkecil (radius 0.32→0.24)
  mengikuti badan yang jauh lebih ramping dari versi berjubah.

### Animasi — DIRISET, bukan ditebak

Dicari lewat web search (bukan asumsi): biomekanik lari/jalan manusia dari
jurnal "The biomechanics of running" (Gait and Posture 1998), artikel
"Swing phase running biomechanics", "Biomechanics of running: overview on
gait cycle" (IJPEFS), "Assessment of Gait", serta prinsip animasi walk/run
cycle (pose contact/recoil/passing/high-point, ayunan kontralateral).
Angka konkret yang diambil & dipakai persis di kode:

| Parameter | Jalan | Lari | Sprint/Dash |
|---|---|---|---|
| Tekuk lutut maks (swing) | ~60° | ~90° | ~105-110° |
| Condong badan ke depan | ~2-3° | ~5-7.5° | (dilebihkan ~17° demi kesan "meledak") |
| Amplitudo ayun lengan & tekuk siku | kecil | sedang-besar | besar |

Prinsip lain yang diimplementasikan:
- **Lengan KONTRALATERAL**: lengan kanan mengayun SAMA fasa dengan kaki
  KIRI (berlawanan dengan kaki kanan) — bukan lengan+kaki di sisi yang
  sama bergerak searah. Ini pola gerak manusia asli, sering salah ditebak.
- **Fase gait berbasis jarak tempuh** (`_advance_gait`, fase maju
  sebanding `kecepatan × delta`), bukan `sin(waktu)` murni — supaya
  panjang & frekuensi langkah otomatis mengikuti kecepatan asli (riset:
  "stride length & stride rate naik bersama kecepatan").
- **Twist pinggul/bahu** halus (beberapa derajat saja, `HIP_TWIST_MAX`/
  `SHOULDER_TWIST_MAX`) — riset menyebut rotasi ini harus KECIL pada lari
  efisien, jadi sengaja tidak dibesar-besarkan.
- **Blend kontinu jalan→lari** berdasar `_speed01` (0=jalan pelan,
  1=lari penuh), lalu **overlay dash** (`_dash_anim`, di-lerp masuk/keluar
  supaya tidak "pop") mendorong lebih jauh ke nilai sprint yang lebih
  ekstrem — dash terasa beda dari lari biasa, bukan sekadar versi cepat.
- Debu jejak kaki (bag. A2) dipertahankan, posisi disesuaikan proporsi
  kaki yang lebih ramping (offset 0.115→0.09).

### Yang TIDAK berubah

- Aura partikel ungu-biru (efek idle) dipertahankan.
- Arsitektur gerak/kamera third-person, serangan (`arcane_bolt.gd`), dan
  semua file selain `player.gd`/`player.tscn` tidak disentuh di bag. A3.

## Ronde-46 bag. A4: mannequin Quaternius asli + mocap, dicat ungu

Pengguna menilai bag. A3 (stickman kapsul prosedural) masih terlihat
"seperti stickman" dari sudut kamera manapun. Kali ini pengguna mengirim
**file aset nyata** dengan cara mengunggahnya **langsung ke commit branch**
lewat uploader web GitHub (bukan lampiran chat) — jalur baru yang terbukti
berhasil membawa file biner besar (~7.6 MB `.glb`) utuh ke sandbox ini,
setelah semua jalur unduh URL/lampiran-chat gagal di ronde-ronde
sebelumnya (`git fetch`/`git merge --ff-only` mengambil commit tsb byte-
demi-byte, git tidak diblok firewall sandbox meski unduhan HTTP biasa
diblok).

### Aset: Quaternius "Universal Animation Library" (CC0)

- File yang disertakan: `project/packs/character_player/mannequin/UAL1_Standard.glb`
  (varian `Unreal-Godot`, tanpa root motion — gerak tetap dikendalikan kode).
- 1 mesh berskin "Mannequin" (~1.83 m tinggi bind-pose, 65 tulang, 2
  material TANPA tekstur) + 43 klip animasi mocap penuh-tubuh siap pakai.
- Lisensi CC0 1.0 Universal — lihat `CREDITS.md` untuk detail & atribusi
  lengkap (file License.txt/README.txt asli dari paket tidak disertakan
  di repo, hanya `.glb`-nya sendiri, tapi ringkasan lisensinya dicatat).

### `player.gd` — dari prosedural ke mocap asli

- Seluruh rakitan `CapsuleMesh`/`SphereMesh` stickman bag. A3 dan
  `_animate_stickman()` (rotasi tulang manual tiap frame, berdasar riset
  biomekanik bag. A3) **dihapus total**.
- Diganti: instance `UAL1_Standard.glb` sbg child `_visual`; `AnimationPlayer`
  dan semua `MeshInstance3D` dicari **secara rekursif**
  (`find_child`/`find_children`) — path node hasil import glTF Godot tidak
  bisa dipastikan tanpa editor lokal, jadi sengaja tidak di-hardcode.
- Kedua material asli (`M_Main` oranye, `M_Joints` sudah ungu), sama-sama
  TANPA tekstur, di-override total dgn `Materials.toon()` — 2 corak ungu
  (badan utama + aksen sendi lebih gelap) supaya tetap sesuai mandat warna
  ungu, sekaligus mempertahankan sedikit "color-blocking" model sumber.
- Lokomosi kini murni `AnimationPlayer.play(nama_klip, blend)` dipilih
  berdasar `_speed01` dengan histeresis (naik/turun beda ambang, cegah
  flicker di batas): `Idle_Loop` → `Walk_Loop` → `Jog_Fwd_Loop` →
  `Sprint_Loop`. Dash memakai klip `Roll` (dipercepat via `custom_speed`
  spy durasi visualnya kira-kira pas dgn `DASH_DURATION` fisik 0.3 dtk).
- **Sengaja di luar cakupan bag. A4** (fokus pengguna: "animasi lari &
  jalan dulu"): klip serang (`Spell_Simple_Shoot`) belum dipasang;
  serangan tap-fire (`arcane_bolt.gd`) tidak berubah dan tidak memicu
  animasi tubuh baru di pass ini.
- `player.tscn`: collision `CapsuleShape3D` disesuaikan ke skala manusia
  nyata (radius 0.24→0.30, tinggi 1.3→1.65) mengikuti tinggi mannequin
  asli ~1.83 m.
- Debu jejak kaki disederhanakan jadi berbasis jarak tempuh (bukan lagi
  fase gait per-tulang, karena gerak kaki kini datang dari mocap asli).
  Aura partikel ungu-biru **tidak disentuh**.

### Belum bisa diverifikasi tanpa render lokal

- Arah hadap model (apakah tampak jalan maju atau justru mundur) —
  disiapkan konstanta `MODEL_YAW_OFFSET` (`player.gd`, default `0.0`,
  tinggal dibalik ke `PI` bila perlu) tapi belum bisa dipastikan tanpa
  GPU/Godot lokal atau umpan balik render sungguhan.
- Kecocokan skala collision capsule vs mesh sebenarnya (angka di atas
  perkiraan dari tinggi bind-pose glTF, belum diverifikasi visual).

## Yang BELUM dikerjakan (menyusul di bagian berikutnya)

- **Bagian B**: mantra andalan (gaya Zoltraak) dipoles jauh lebih
  megah/detail partikelnya — masih memakai sistem tap-fire kecil
  (`arcane_bolt.gd`) untuk serangan biasa; mantra besar belum ada.
- **Bagian C**: reskin tanah dari grid biru jadi rumput lebat realistis di
  `world.gd` (`_make_ground_material()`).
- Nasib musuh/kombat di dunia sihir open-world: belum dibahas ulang dengan
  pengguna di ronde ini.

## Validasi yang dijalankan (sandbox ini, tanpa GPU/Godot lokal)

- `gdparse` (gdtoolkit) pada semua `.gd` yang diubah + loop penuh
  `project/**/*.gd` → semua lolos parse.
- `python3 tools/analyze_checks.py .` → BERSIH ✓ (18 file `.gd` diperiksa).
- `git diff --cached --check` → tidak ada whitespace/marker konflik.
- **Verifikasi render/visual sesungguhnya HARUS lewat CI GitHub Actions**
  (`gh run watch`) — tidak ada Godot binary lokal di sandbox ini dan tidak
  bisa diunduh (firewall sandbox), jadi tidak ada cara preview lokal.
