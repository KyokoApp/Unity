# CREDITS — Pulau Toon

## Aset pihak ketiga (disertakan)

### (Dihapus) Female Mannequin + Universal Animation Library 1 & 2 (Quaternius, CC0)
- Dipakai Ronde-36, **dihapus Ronde-37** (pemain kini bola api prosedural —
  lihat DECISIONS.md Ronde-37). File `.glb` tidak lagi disertakan.

### Karakter: Knight — "KayKit Character Pack: Adventures" (v1.0)
- **Pembuat:** Kay Lousberg — https://kaylousberg.itch.io
- **File:** `project/packs/character_player/knight.glb` (+ rig & ~76 animasi)
- **Sumber:** https://github.com/KayKit-Game-Assets/KayKit-Character-Pack-Adventures-1.0
- **Lisensi:** Creative Commons Zero (CC0) — domain publik; atribusi sukarela.
- **Ringkasan lisensi:** bebas dipakai/dimodifikasi untuk kepentingan apa pun,
  termasuk komersial, tanpa wajib kredit.

## Aset buatan sendiri (prosedural, bebas lisensi)

- **Terrain/pulau, bioma, sungai & danau** — prosedural via FastNoiseLite
  (`project/packs/world_terrain/*`).
- **Vegetasi, bangunan, kerang, kerikil** — mesh low-poly dibangun via kode
  (`project/packs/world_terrain/meshlib.gd`).
- **Shaders cel/toon, outline inverted-hull, air, langit, rumput** —
  ditulis untuk proyek ini (`project/packs/shaders_materials/*`).
- **Musik & SFX** — disintesis secara prosedural dari gelombang dasar
  (osilator sinus/square/noise) oleh `tools/synth_audio.py`:
  `day_marimba.wav`, `beach_calm.wav`, `ui_click.wav`. Hukumnya karya orisinal
  proyek ini. (ocean/footstep/jump/land/pickup/splash/emote/whoosh dihapus
  Ronde-37.)
- **Suara api `fire_loop.wav`** — disintesis prosedural oleh
  `tools/synth_fire.py` (gemuruh + desis + letupan). Karya orisinal.
- **SFX tembak/ledak `fire_shoot.wav`, `fire_explode.wav`** — disintesis
  prosedural oleh `tools/synth_fire.py` dari osilator dan noise, tanpa sampel
  eksternal. Karya orisinal.
- **Proyektil, ledakan, muzzle flash, shockwave, partikel, dan bekas gosong** —
  visual prosedural karya orisinal di `project/packs/character_player/`
  (`fire_bolt.gd`, `fire_explosion.gd`, `fire_fx.gd`, `shockwave.gdshader`).
- **Bola api (shader inti & selubung, partikel)** — ditulis untuk proyek ini
  (`project/packs/character_player/fireball_*.gdshader`, `player.gd`).

## Engine & tooling

- **Godot Engine** (4.5.x), MIT — https://godotengine.org
- **OpenJDK (jdk4py)** untuk keystore/signing Android — GPL w/ classpath exception.


- **Terrain detail textures** (`packs/shaders_materials/textures/detail_grass.jpg`, `detail_sand.jpg`)
  — dibuat AI (text-to-image) untuk proyek ini mengikuti referensi palet pengguna; bukan aset pihak ketiga.


- **Low Poly Girl** (karakter + 36 animasi) oleh Manoel "Manneko" da Rocha de Oliveira
  — lisensi bebas pakai (komersial diizinkan, redistribusi/penjualan aset dilarang);
  dipakai sebagai skin bawaan pemain (`packs/character_player/polygirl.glb`).

## Ronde-40: Monster 3D low-poly + pemain kubus

- **Quaternius LowPoly Animated Monsters** — kandidat sumber aset eksternal
  yang ditelusuri untuk ronde lanjutan; 50 monster beranimasi, CC0:
  https://quaternius.itch.io/lowpoly-animated-monsters
- **Monster roster saat ini** — delapan bentuk 3D (slime, golem, bat, mushroom,
  crawler), material, animasi bob/jalan/serang, dan percikan pemain dibuat
  procedural memakai primitive/partikel Godot; bebas lisensi dan tidak membawa
  binary eksternal sebelum arsip CC0 diverifikasi dan diintegrasikan.
- **Pemain kubus** — BoxMesh, visor, kaki, aura, ground glow, dan TravelSparks
  dirakit di `packs/character_player/player.gd`.

## Ronde-41: bentuk visual disederhanakan

- Pemain dan seluruh monster kini hanya memakai `BoxMesh` procedural buatan
  proyek ini; tidak ada aset monster eksternal yang dibundel pada ronde ini.
- Mata merah monster dan percikan gesekan tanah dibuat procedural dengan
  material/partikel Godot.

## Ronde-43: tembakan mana biru + mantra Zoltraak

- `fireball_core.gdshader`, `fireball_shell.gdshader`, `fire_bolt.gd`, dan
  `fire_explosion.gd` direvisi dari palet api oranye ke palet mana biru-putih
  dan diperkecil ukurannya; semua tetap prosedural karya proyek ini, tanpa
  aset/tekstur eksternal baru.
- `zoltraak_charge.gd` (lingkaran mantra) dan `zoltraak_bolt.gd` (gelombang
  besar) adalah skrip baru, seluruhnya prosedural (mesh primitive, partikel,
  dan `Label3D` bawaan Godot untuk huruf mantra) — tidak ada aset pihak
  ketiga yang ditambahkan.

## Ronde-45: pivot total ke game TANK (mage/monster/Zoltraak dihapus)

- Permintaan pengguna: seluruh pack mage (`player.gd` kubus mantra, mana biru,
  Zoltraak) dan roster monster (`monster.gd`/`monster_system.gd`) **dihapus
  total**, diganti murni game tank (hull+turret independen, meriam, dinding/
  bunker destructible ronde-44 dipertahankan sebagai rintangan medan tempur).
  Rencana grapple ala Attack on Titan (belum sempat dikerjakan di ronde-44)
  ikut dibatalkan.
- `player.gd` ditulis ulang penuh: BoxMesh hull + turret + laras, seluruhnya
  prosedural (karya proyek ini), tanpa aset pihak ketiga.
- `fire_bolt.gd` diganti nama & isi jadi `tank_shell.gd` (proyektil meriam);
  `fireball_core.gdshader`, `fireball_shell.gdshader`, dan `fire_explosion.gd`
  direvisi PALETNYA KEMBALI dari mana biru-putih (ronde-43) ke palet api
  oranye/merah (ledakan meriam) — tetap prosedural, tanpa tekstur eksternal.
- Sempat dicek ketersediaan aset tank 3D CC0 gratis (mis. paket "Tank" dari
  Quaternius, quaternius.com, lisensi CC0/Public Domain) sebagai kandidat
  peningkatan visual di masa depan; ronde ini TETAP memakai kubus prosedural
  (konsisten dengan gaya visual proyek sejauh ini) — belum ada aset biner
  eksternal yang diunduh/dibundel.

## Ronde-46 (bag. A): pivot balik dari TANK ke penyihir anime prosedural

- Permintaan pengguna: hasil visual tank dinilai "kurang/jelek"; pivot balik
  ke karakter penyihir bergaya anime dengan banyak efek, dunia lebih hidup.
- **Riset aset karakter anime eksternal (VRM/GLB) dilakukan tapi TERBUKTI
  tidak feasible di sandbox ini** — dicoba nyata, bukan asumsi:
  - `poly.pizza/m/jWS1CLA0RO` (Quaternius Tank, CC0) — dari riset ronde-45,
    tidak relevan lagi.
  - `quaternius.itch.io/universal-animation-library` (CC0, 120+ animasi
    humanoid kompatibel Godot/Mixamo) — tidak bisa diunduh (blocker di bawah).
  - `github.com/ToxSam/open-source-avatars` (registry avatar VRM CC0,
    `opensourceavatars.com`) dan `github.com/MJMoonbow/VRMavatars` (VRM CC0
    tema fantasy) — ditemukan lewat riset, tidak diunduh (blocker sama).
  - Link Google Drive milik pengguna sendiri (file glTF/GLB valid berisi
    mesh+skin+animasi, dikonfirmasi dari magic header `glTF` yang terbaca)
    — TIDAK BISA ditransfer utuh: `fetch_page` mengonversi hasil jadi
    teks/markdown yang merusak byte biner (karakter pengganti `�` muncul
    di awal file). Pengguna juga tidak bisa melampirkan file secara
    langsung sebagai lampiran chat saat ditawarkan.
  - Kesimpulan: **TIDAK ADA aset 3D biner eksternal (.vrm/.glb/.fbx) yang
    diunduh atau dibundel** di ronde ini maupun rencana ronde berikutnya
    selama keterbatasan sandbox ini berlaku. Karakter dibangun 100%
    prosedural (primitive mesh Godot + shader cel-shading yang sudah ada
    di project, `shaders_materials/toon.gdshader` + `outline.gdshader`
    lewat helper `Materials.toon()`) — karya proyek ini, bukan aset pihak
    ketiga.
- `player.gd` ditulis ulang penuh jadi karakter penyihir chibi-anime
  (kepala besar, mata besar+kilau, pipi merona, rambut runcing, topi
  penyihir, jubah, lengan beranimasi prosedural, aura partikel) — lihat
  `BACA_INI.md` untuk detail lengkap.
- `tank_shell.gd` diganti nama jadi `arcane_bolt.gd`; palet proyektil &
  ledakan (`fireball_core.gdshader`, `fireball_shell.gdshader`,
  `shockwave.gdshader`, `fire_explosion.gd`) direvisi dari api-oranye
  (tank) jadi arcane ungu-biru-lavender — tetap prosedural, tanpa tekstur
  eksternal.
- `player.tscn`: collision `BoxShape3D` (tank) → `CapsuleShape3D`
  (humanoid).
- Dinding/reruntuhan destructible ronde-44 (`wall.gd`/`wall_system.gd`)
  **dipertahankan** (hanya komentar diperbarui), direframe sebagai
  reruntuhan kuno dunia sihir, bukan cover medan tempur tank.

## Ronde-46 (bag. A3): stickman ungu + animasi jalan/lari/dash biomekanik

- Permintaan pengguna (dengan gambar referensi stick figure): ganti bentuk
  karakter jadi STICKMAN literal (kepala bulat + garis lurus untuk
  torso/lengan/kaki, tanpa wajah/rambut/pakaian), warna ungu dipertahankan,
  dan minta riset dulu cara kerja animasi jalan/lari/dash yang benar.
- Riset biomekanik (bukan asumsi) via web search, sumber: jurnal "The
  biomechanics of running" (Gait and Posture, 1998), "Swing phase running
  biomechanics" (auptimo.com), "Biomechanics of running: An overview on
  gait cycle" (IJPEFS), "Assessment of Gait" (musculoskeletalkey.com), serta
  prinsip animasi walk/run-cycle (contact/recoil/passing/high-point poses,
  kontralateral arm-leg swing) dari beberapa tutorial animasi karakter.
  Angka yang diambil & dipakai di `player.gd`:
  - Tekuk lutut maksimum saat mengayun: ~60° jalan normal, ~90° lari,
    ~105-110° sprint terlatih (dipakai persis: `KNEE_BEND_WALK/RUN/DASH`).
  - Condong badan ke depan: ~2-3° jalan, ~5-7.5° lari (dipakai persis;
    nilai dash dilebih-lebihkan ke ~17° demi keterbacaan visual game).
  - Lengan berayun KONTRALATERAL (berlawanan fasa dengan kaki di sisi
    SEBERANG, bukan searah) — pola gerak manusia asli, bukan asumsi.
  - Siku makin tertekuk & amplitudo ayun makin besar seiring kecepatan.
  - Rotasi pinggul/bahu (transverse plane) ada tapi harus KECIL pada lari
    efisien — dipakai sebagai detail halus (`HIP_TWIST_MAX`/
    `SHOULDER_TWIST_MAX`, beberapa derajat saja).
  - Panjang & frekuensi langkah naik bersama kecepatan — diimplementasikan
    dengan fase gait yang maju sebanding JARAK TEMPUH (`_advance_gait`),
    bukan `sin(waktu)` murni.
- `player.gd`: seluruh mesh "berdaging" dari bag. A/A2 (tunik, cape,
  bantalan bahu, manset, sepatu bot, rambut, topi, mata, pipi merona)
  **dihapus**; diganti garis seragam (`CapsuleMesh` radius `LIMB_RADIUS`
  konstan) untuk torso/lengan/kaki + `SphereMesh` polos untuk kepala, semua
  1 warna ungu (`STICK_COLOR`) — 100% prosedural, tanpa tekstur/model
  eksternal. Skeleton pivot (paha/betis, lengan-atas/siku) dari bag. A2
  dipertahankan agar tetap bisa menekuk saat animasi.
- `player.tscn`: collision `CapsuleShape3D` diperkecil (radius 0.32→0.24)
  mengikuti badan yang jauh lebih ramping.
- Aura partikel ungu-biru & debu jejak kaki (bag. A2) **dipertahankan** —
  bukan bagian bentuk tubuh, tetap relevan untuk kesan "banyak efek".

*Terakhir diperbarui: 2026-09-26*


## Ronde-8: Aset Desa & Alam — KayKit Medieval Hexagon Pack (CC0)

- **KayKit Medieval Hexagon Pack** oleh Kay Lousberg — CC0 1.0
  (https://github.com/KayKit-Game-Assets/KayKit-Medieval-Hexagon-Pack-1.0)
  Dipakai: rumah (home A/B, tavern, blacksmith, windmill, church, well), pagar,
  barrel/crate/wheelbarrow, pohon tree_single_A/B, batu rock_single_A–E.

## Ronde-10: World "Gravity Falls" (upload pengguna)

- **gravity_falls.glb** — world kartun 225m (Mystery Shack area; mesh\+tekstur penuh,
  ~62k segitiga). Sumber: file `.glb` yang diunggah pengguna langsung ke branch.
  Atribusi: tema/brand Gravity Falls © Disney; model tampak berupa ekspor gaya
  Sketchfab (fan-made). Nama pembuat model BELUM terverifikasi — diminta ke
  pengguna; entri akan dilengkapi. Catat: ini kandidat yang perlu konfirmasi
  lisensi sebelum rilis publik (di luar paket CC0/CC-BY wajib).
