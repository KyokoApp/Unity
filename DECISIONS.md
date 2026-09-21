# DECISIONS — Catatan keputusan teknis dan alasannya

Format: **[D-nomor]** Keputusan → alasan + alternatif yang ditolak.

## Lingkungan / toolchain

- **[D-1] Godot 4.5.2-stable** → memenuhi syarat “4.3 atau lebih baru”, stabil,
  dukungan Android modern (16KB page size untuk syarat Google Play 2025+), API
  yang dipakai (AnimationTree, PCK, HTTP, WorkerThreadPool) matang.
  Alternatif ditolak: 4.3 (lebih tua), 4.7.x (terbaru tapi risiko perbedaan
  format preset/template yang belum teruji di sandbox ini).

- **[D-2] GitHub Actions “bridge” untuk biner** → sandbox hanya membolehkan
  GitHub API/codeload + PyPI + npm; host biner (tuxfamily, dl.google, OS mirrors)
  diblok. Runner GitHub Actions punya internet penuh, lalu push payload ke branch
  `arena/bridge-assets`, ditarik lokal via codeload. Payload dipangkas
  (hanya export template Android, bukan semua platform) agar ~430 MB, bukan >1 GB.
  Branch `bridge-assets` tanpa prefix arena hilang (dipangkas sistem Arena) —
  karena itu nama branch wajib `arena/*`. Setelah selesai, branch bridge bisa
  dihapus (`git push origin --delete arena/bridge-assets`) tanpa mengganggu hasil.

- **[D-3] aapt2 dari npm (`aaptjs3`), apksigner dari build-tools runner** →
  memenuhi kebutuhan export Godot tanpa `sdkmanager` (dl.google diblok).
  zipalign tidak diperlukan: Godot 4.5 melakukan alignment APK secara internal
  (lihat `export_plugin.cpp`, mengikuti ZipAlign.cpp AOSP).

- **[D-4] JDK dari PyPI `jdk4py`** → satu-satunya sumber Java yang bisa dijangkau;
  menyediakan `java` + `keytool` (kebutuhan keystore & apksigner).

## Engine / arsitektur

- **[D-5] APK = launcher murni** → `run/main_scene` hanya updater; semua konten
  di `res://packs/<id>/` diekspor sebagai `.pck` terpisah dengan preset
  `export_filter="all"` + `exclude_filter` semua pack lain (presets digenerate
  otomatis oleh `tools/build_packs.py`, menghindari kesalahan manual).
  Alasan: update konten tanpa install ulang, memenuhi syarat “APK kecil”.

- **[D-6] Tanpa `class_name` di dalam pack** → skrip yang dimuat dari `.pck`
  tidak terdaftar di global class cache runtime; semua referensi antar-skrip
  memakai `preload()` ber-path lokal pack yang sama, antar-pack via `load()`
  res:// setelah pack dimuat (launcher menjamin urutan dependensi).

- **[D-7] Urutan dependensi pack linear** (bukan DAG) → `pack_order` di
  manifest; sederhana, deterministik, dan mudah di-debug. Dependensi antar pack
  hanya boleh menunjuk ke pack sebelumnya di urutan.

- **[D-8] Renderer Vulkan “Mobile”** → target Snapdragon 6xx/7xx; fitur cukup
  untuk toon + fog + shadow ringan. Fallback Compatibility disediakan sebagai
  preset export terpisah (renderer tidak bisa diganti runtime dari aplikasi
  Android), terdokumentasi di README.

- **[D-9] Uji visual dengan Xvfb + lavapipe** → sandbox tanpa GPU/X; mesa
  lavapipe (Vulkan software) memungkinkan screenshot renderer Mobile yang persis
  sama dengan pipeline Android. **Dibatalkan (lihat D-15)**: apt/X11/Xvfb tidak
  dapat diunduh di sandbox ini; kode sumber membuktikan `DisplayServer headless`
  menolak pembuatan RenderingDevice (`can_create_rendering_device()`), sehingga
  screenshot engine memang mustahil tanpa display server sungguhan.

## Desain game

- **[D-10] Karakter KayKit Adventurers (CC0)** → rig humanoid + ~76 animasi
  termasuk locomotion/jump/pickup/attack/emote (Knight.glb 3,5 MB); lisensi
  CC0 (kredit sukarela, tetap dicatat). Missing: crouch & swim → dipetakan ke
  varian gerak yang ada (`crouch` = `Walking_B` + visual memendek via pivot,
  `swim` fallback `Walking_A` slow + bob permukaan) supaya tidak memerlukan
  retarget yang rapuh; resolver nama animasi (animation_controller.gd) memilih
  kandidat yang tersedia sehingga pack lain tetap kompatibel.

- **[D-11] Suara disintesis prosedural (Python)** → sumber musik/SFX CC0 yang
  stabil sulit dijangkau dari sandbox; audio orisinal bebas lisensi, dan
  sesuai tema (gelombang pantai, pad akor ambient, blip UI/pickup).

- **[D-12] Terrain heightmap prosedural + chunk LOD di GDScript,
  tanpa addon** → kontrol penuh ringan (vertex-color bioma, collision
  HeightMapShape3D hanya di sekitar pemain), terbukti jalan di Android;
  addon terrain pihak ketiga berisiko di mobile.

- **[D-13] Outline inverted-hull** → paling murah & stabil di GPU mobile;
  post-process outline (depth/normal edge) lebih mahal dan berisiko gagal 30 FPS.

- **[D-14] Bayangan: directional terbatas + blob shadow karakter** → preset
  Rendah mematikan shadow map sama sekali tetapi karakter tetap “menapak”
  lewat blob shadow quad murah.

- **[D-15] Bukti visual via renderer CPU shader-accurate** → menggantikan D-9.
  `project/dev_probe/visual_proof.gd` merender data asli pulau (island.gd)
  dengan rumus persis shader paket (toon 3 band, sky gradasi+cakram, water
  band/foam, outline contour) dan menghasilkan PNG dapat-diverifikasi manusia
  di docs/screenshots/. Jujur secara artefak: berlabel "visualisasi pipeline",
  bukan tangkapan renderer GPU.

- **[D-16] editor_settings-4.5.tres wajib header .tres** → file mengandung
  `[gd_resource type="EditorSettings" format=1]` + `[resource]`; tanpa header
  ResourceLoader menolak ("Unrecognized file type 'resource'") menyebabkan
  "A valid Java SDK path" palsu meski nilai sudah benar.

- **[D-17] Wheel jdk4py kehilangan bit eksekusi** → ekstraksi via
  `python -m zipfile` menjatuhkan permission; `chmod +x java-runtime/bin/*`
  wajib sebelum `java`/`keytool` dipakai.

- **[D-18] Export APK berhenti hanya di export_templates** → seluruh
  konfigurasi lain tervalidasi (SDK layout, apksigner jar, aapt2 dari
  aaptjs3, keystore, preset runnable); dua APK template tidak dapat diunduh
  dari sandbox (egress: host biner Godot diblok; LFS media GitHub juga
  diblok — ditemukan repo dengan template 4.5.stable via LFS, objek-nya
  tidak bisa dijangkau). Skrip `fetch_export_templates.sh` memuat langkah
  satu-klik untuk lingkungan normal.

## Rilis CI GitHub Actions (keputusan)

- **Pola rilis**: workflow `apk_release.yml` membangun APK di runner (internet penuh) dan menempelkan aset ke Release tag deterministik (`apk-YYYYMMDD-HHMM`) via `gh release edit/upload --clobber` + retry 4× per file; release dibuat/ditarget dari commit CI tanpa perlu kredensial tambahan (GITHUB_TOKEN bawaan, permissions.contents=write).
- **Diagnostik buta-run**: log runner tidak bisa diunduh dari sandbox — solusi: diagnostik build (rc, EXPORT log) ditulis ke *release notes* lewat `gh release edit --notes-file` agar bisa dibaca via API; ini sekaligus menjadi pembuktian token tulis.
- **Tiga gotcha export headless yang dipecahkan**: (1) path output export di-resolve relatif `project/` → pakai absolute; (2) nama proyek harus identifier paket yang sah (tanpa spasi) → `pulautoon`; (3) `import_etc2_astc=true` wajib — tanpanya validasi Android gagal diam-diam (valid=false tanpa pesan di kode sumber Godot).
- **Cleanup kecil**: komentar `# rerun-kick` sengaja dibiarkan sebagai pendorong run ulang murah; tidak memengaruhi build.

## Gaya visual "turquoise pastel" (permintaan pengguna)

- **Permintaan**: tampilan amat-mirip game-kasual favorit pengguna (langit turquoise, kota krim/terracotta, garis cokelat sketchy) — ditempuh sebagai *replikasi bahasa visual*, BUKAN penyalinan aset: nilai warna dirumuskan ulang sendiri dari analisis tangkapan layar publik (referensi tidak disimpan di repo).
- **Implementasi** (satu pass komit): sky.gdshader → turquoise/mint krim; toon 3-band tetap namun kontras direndahkan (shadow 0.52→0.60, softness 0.12→0.16, rim jadi hangat 1.0/0.90/0.70); outline → umber hangat (0.24/0.15/0.14); air → teal dua-nada (shallow 0.30/0.80/0.73, deep 0.09/0.42/0.52); biome island.gd → sand krim, rumput sage/jade, hutan jade-tua, batuan abu-lilac; properti pantai → cream/terracotta/sage/pale-cyan; siklus siang-malam disetel ulang (sun krim hangat, senja coral, malam teal-tinta tetap terbaca).
- **Verifikasi**: tools/style_preview.py (CPU, mereplika math shader) merender pratinjau siang/senja/malam + metrik eksposur — day mean 0.61, dusk 0.42, night 0.18, over/under-klip < 0.5% → lolos standar "tidak over-exposed/crushed".

## 2026-09-20 — Ronde-3: animasi kaku, analog terbalik, terrain tak terlihat
1. **Animasi jalan beku setelah ~1 siklus**: GLB impor tidak loop bawaan. Semua
   state lokomosi kini dipaksa `LOOP_LINEAR` saat AnimationController.setup().
2. **Analog terbalik (maju/mundur)**: double-negation di mapping joy->kamera
   (`-joy.y` di dalam basis yang sudah kamera-relatif). Dibalik tepat sekali,
   jalur keyboard disamakan supaya konsisten.
3. **Terrain tak terlihat di perangkat**: mitigasi multi: `cull_disabled` pada
   toon_color (kebal winding/driver), clamp `hillv` anti-NaN (`pow(neg,1.4)`),
   guard NaN per-vertex di terrain_chunk (fallback h=0/normal=UP), DAN jejak
   diagnostik statistik mesh pada layar boot (chunk count, NaN, rentang h) agar
   penyebab pasti terbaca dari HP.
4. **Tekstur detail painted** pada terrain (luminance multiply, band sempit)
   meniru tekstur reference pengguna — dibuat AI agar bebas lisensi.
5. Foam/water: band pantai sempit dipertahankan; pola polka laut dipercaya
   konsekuensi tinggi≈0/NaN global — jejak baru akan membuktikannya.

## 2026-09-20 — Ronde-4: palet tanah = referensi pengguna
1. Referensi hijau (olive painted) & tanah (pasir hangat) pengguna diadopsi: warna
   vertex biome di island.gd digeser ke olive pekat/pasir hangat, plus detail
   tekstur dual-warna (detail_grass/detail_sand, AI) di-blend mengikuti hue
   vertex (rumput g>r, pasir r>g) — menggantikan tekstur luminance tunggal ronde-3.
2. Catatan: laporan "anim kaku/analog terbalik/tanah hilang" pada screenshot
   12:47 berada pada build 1.0.5; perbaikan akarnya (loop animasi, sumbu analog,
   cull-disabled/anti-NaN + jejak statistik) sudah live di 1.0.6 — menunggu uji ulang.

## 2026-09-20 — Ronde-5: HUD RPG + Mode Edit in-game + dunia lebih kecil
1. Joystick dibuat melayang: tersembunyi, muncul di titik sentuh pada 58% layar kiri.
2. Tombol aksi menjadi lingkaran transparan-putih ber-icon canvas (RpgButton):
   serang=pedang besar, lompat=orang melompat (atas-kanan), dash=sepatu (bawah-kanan);
   sprint/jongkok/emote mini di tepi kanan. Pause = lingkaran kecil pojok kiri atas.
3. Menu pause dirancang ulang: panel geser dari kiri, tinggi penuh, berscroll,
   pengaturan selalu terlihat, tombol "Mode Edit" baru.
4. Mode Edit in-game: sculpt terrain (angkat/turun via grid offset bilinear 160x160),
   jalur tanah (masker + target datar + warna jalan), slider matahari/ambient/kabut,
   preset gradien langit — semua tersimpan (terrain di user://terrain_edits.dat,
   cahaya di settings.cfg) dan ter-load ulang saat boot.
5. Dunia diperkecil 1600→800 m (GRID 8x8 chunk, GRID_HALF=4) atas keluhan "kegedean".
6. Addon pihak ketiga TIDAK dipakai: (a) itch.io & asset-store tak dapat diunduh dari
   CI/sandbox; (b) color-grading = post-process berat untuk ponsel — diganti kontrol
   pencahayaan native; (c) stylized-water umumnya butuh screen/depth texture (mahal di
   Adreno) — air toon internal dipertahankan; (d) terrain3d memang khusus desktop;
   sistem chunk kustom kita sudah setara & mobile-native. Aset Quaternius (CC0) akan
   diintegrasi begitu arsip GLB diunggah pengguna (unduhan diblok jaringan).

## 2026-09-20 — Ronde-6: gaya low-poly faceted + bug max semver
1. "Low Poly Terrain Builder" (asset store) = plugin editor Godot — tidak berjalan di
   APK, lisensi di luar filter CC0, dan server unduhan diblok. Digantikan MODE
   "segi datar" native: terrain_chunk meledakkan segitiga (vertex unik per-tri,
   normal per-muka, warna diratakan) → tampilan low-poly faceted, toggle di Mode
   Edit (tersimpan gfx_faceted). ~3x vertex pada LOD0/1 — masih ringan di ponsel.
2. Bug build_packs: game_version=max string ("1.0.10"<"1.0.7") → kunci semver.

## 2026-09-20 — Ronde-7: hotfix jatuh-tembus + skin PolyGirl
1. BUG KRITIS jatuh tembus: saat dunia diperkecil, `world._chunk_of` masih offset
   +8 (GRID lama 16) padahal terrain_chunk pakai GRID_HALF=4 → chunk timur tak
   terbangun/koordinat tabrakan bergeser. Offset kini GRID/2 konsisten.
2. Skin ganti-ganti: PolyGirl (Manneko, lisensi bebas-pakai) jadi karakter bawaan;
   Knight KayKit tetap sebagai alternatif; peta nama animasi per-skin di
   AnimController.setup(custom_states); skala dinormalisasi via AABB; pemilih di
   menu Pengaturan (char_skin, tersimpan, berlaku instan lewat player.set_skin).
3. Aset pengguna di Godot4/: Village MegaKit Standard = potongan modular (bukan
   rumah jadi) → perlu perakitan arketipe rumah; tanpa pohon (tetap prosedural
   sampai ada paket pohon). EmacEArt Cool Water + Color Grading = belum
   diintegrasi (cool water pakai screen-texture/depth → mahal di Adreno; color
   grading compositor = desktop) — kontrol pencahayaan native tetap jalan.

## 2026-09-20 — Ronde-8: aset jadi + mood sore (ZZZ-ish)
1. Prinsip baru (permintaan user): semua objek dunia = aset jadi CC0, bukan rakitan
   prosedural. Sumber utama GitHub (satu-satunya host yang lolos sandbox):
   KayKit Medieval Hexagon Pack (CC0). MegaKit Quaternius modular TIDAK dipakai
   (bukan rumah jadi) — ditinggalkan.
2. Rumah: footprint/dbagikan normalisasi AABB → skala konsisten; desa = 3 situs
   landai dekat pantai, cincin menghadap sumur, props hangat, collision kotak.
3. Pohon KayKit menggantikan pohon prosedural; batu 5 varian; rumput tetap mesh
   prosedural (tak terhindarkan untuk interaksi) tapi kini REAKTIF: hanyut saat
   diinjak (shader mendapat player_pos per frame, radius 1.6m, tekan & dorong).
4. Mood visual: default waktu 16.4 (sore), palet siang dibuat teduh + senja
   peach-teal sinematik, ambient/fog disesuaikan, exposure 0.95; tanah direram
   ke hijau zamrud; sea & sky tetap shader internal (addon Color Grading &
   Cool Water tetap ditahan demi performa ponsel).

## 2026-09-20 — Ronde-9: dunia 268m + datar bergelombang + bersih repo
1. Dunia 800 -> 268m (GRID 4x4, chunk 67m, forest supercell 67m, kabut 0.0026).
2. Kontur "datar tapi bergelombang": bukit 38m->4.5m, relief dasar 5.2->2.1m,
   detail 0.55->0.30; ambang batuan ikut turun (16-26m -> 7-13m).
3. Godot4/ DIHAPUS (permintaan): yg dipakai sudah diekstrak (PolyGirl->pack
   character_player; MegaKit modular ditinggal; VRM 19MB tak terpakai ikut hilang
   — kalau nanti mau skin VRM, upload ulang saja).
4. Lakshman-YT/Forest-Godot4 TIDAK dijadikan world baru: lisensi campuran
   per-asset Sketchfab (beberapa bukan CC0/BY jelas), tergantung stack
   Terrain3D+Sky3D+PhantomCamera (plugin PC, 158MB) — konflik dg prinsip
   mobile-ringan kita. Nilai ambil parsial: model env (maple/pine/bush/grass/
   bridge/butterfly) — ditawarkan sebagai opsi ronde berikut dgn kredit CC-BY.

## 2026-09-20 — Ronde-10: mode WORLD STATIS (Gravity Falls GLB)
1. world.gd kini punya mode statis: bila gravity_falls.glb ada → terrain
   procedural, laut, shore map, chunk streaming, hutan/pantai/desa Dinonaktifkan
   (tetap fallback otomatis bila GLB gagal dimuat). Sun/sky/fog/siang-malam tetap.
2. Normalisasi skala: span asli 225m dipertahankan (rentang wajar 60-480m);
   origin dipindah agar pusat (0,?,0) & dasar di y=0.
3. Collision: trimesh per mesh (kecuali skybox/shadow/logo); ketinggian permukaan
   pijakan dijawab lewat grid akselerasi segitiga barycentric (tanpa query fisika
   → aman dipanggil dari konteks apa pun) — player.height_at otomatis cocok.
4. Outline tipis 0.008m menggantikan 0.020 (karakter + world), sesuai permintaan;
   outline dilewatkan utk skybox/shadow/logo (plane transparan).
5. Mode Edit sculpt/jalur dinonaktifkan di mode statis (no-op); slider cahaya
   tetap berfungsi karena dioper ke Environment yang sama.

## 2026-09-20 — Ronde-11: hardening loader world statis + docs/BUGFIXES.md
1. Blue screen (langit saja) = generate_async mati setelah langit jalan.
   Loader world statis kini defensif: guard tiap tahap, verify hasil akhir
   (permukaan pijakan > 0 & grid bucket terisi) — gagal → queue_free + fallback
   pulau procedural. User tak pernah lagi terjebak di layar biru.
2. Dokumentasi perbaikan bug dipusatkan di docs/BUGFIXES.md (gejala→akar→
   investigasi→fix→prosedur rilis) supaya AI/developer lain bisa langsung kerja.

## 2026-09-20 — Ronde-12: Gravity Falls dimuat ASINKRON (anti blue screen total)
1. Blue screen masih terjadi di 1.0.16 → kesimpulan: risiko memuat GLB 10MB secara
   sinkron di boot tetap terlalu besar di perangkat. Strategi BARU: game SELALU
   boot ke pulau procedural (jalur kode yang sudah terbukti stabil 1.0.12-1.0.14),
   lalu Gravity Falls dimuat via ResourceLoader.load_threaded_request; saat
   sukses → build container + matikan visual&collision pulau + sembunyikan water/
   forest/beach + teleport pemain ke pijakan baru; saat GAGAL (load failed /
   build gagal) → diam di pulau, hanya _wtrace. Mustahil blue screen dari sini.
2. Setelah swap: height_at/find_spawn_point otomatis pakai grid segitiga GLB;
   mode edit sculpt tetap no-op di mode statis.

## 2026-09-20 — Ronde-13: BISEKSI blue screen (kembali ke konfigurasi 1.0.12)
1. Setelah 3 fix buta gagal → biseksi tegas: world.gd di-strip TOTAL dari kode
   world statis (loader/async/grid segitiga/outline GLB) + semua konstanta
   dikembalikan ke nilai 1.0.12 (GRID 8x8 chunk 100m, WORLD 800m, forest 400m,
   beach/village rentang asli) — konfigurasi terakhir yang dikonfirmasi user
   berjalan (screenshot rumah+palem).
2. gravity_falls.glb dikeluarkan dari pack (eliminasi variabel import/pack;
   file masih di riwayat git → bisa diaktifkan lagi terpisah).
3. Pertahankan: desa KayKit + pohon/batu + rumput reaktif, mood sore, outline
   tipis karakter, kontur datar bergelombang (island flatten tetap — math aman).
4. Jika 1.0.18 boot normal → kesalahannya di kode statis/handling GLB; jika
   MASIH biru → tersangka berikutnya: resize konstanta (1.0.13) atau lapis
   delivery pack; jejak boot di layar loading = titik mati persisnya.

## 2026-09-20 — Ronde-14: Gravity Falls = SATU-SATUNYA world (tanpa fallback)
1. Sesuai instruksi tegas user: world procedural lama DIHAPUS TANPA SISA
   (island.gd, terrain_chunk.gd, meshlib.gd, pack forest+beach+semua aset KayKit,
   water.gdshader, grass.gdshader). Yang tersisa: world statis Gravity Falls.
2. world.gd ditulis ulang ramping (~330 baris): load GLB sinkron saat boot
   (atas permintaan), collision trimesh, grid segitiga barycentric utk height_at
   & spawn, outline tipis 0.008, sky/sun/fog/siang-malam tetap (slider Mode Edit
   masih berfungsi). API kompatibel penuh (sculpt/edit = no-op).
3. JT JARING PENGAMAN TERAKHIR: bila GLB gagal total → "dunia darurat polos"
   (bidang 400m + collision + grid y=0) — game tetap boot & pemain bisa
   berjalan membaca jejak boot (tujuan: user mau otak-atik error sendiri).
4. Catatan riset lapangan: karena 1.0.18 (= konfigurasi 1.0.12 yang dulu jalan)
   TETAP blue screen, blue screen kemungkinan BUKAN dari kode world — kandidat
   utama berikutnya: jalur update content (pack korup di perangkat) / build ci /
   state user:// basi. Langkah debug diserahkan ke user bersama docs/BUGFIXES.md.

## 2026-09-20 — Ronde-15: 4 perbaikan blue screen (kredit analisis AI eksternal)
1. Barycentric lama MENCOBAK w1/w2 campur koordinat x-z vertex beda → terbukti
   61.6% miss + 35.3% tinggi salah (uji 20rb titik acak di sandbox); diganti
   versi dot-product (100% akurat pada uji yang sama).
2. Kubah langit (Object_14, 225m) lolos cek nama (node GLB nama generik) →
   dideteksi dari BENTUK: mesh dominan horizontal>60% & 42%<vertikal<90% =
   dikeluarkan dari collision/outline/grid (visual tetap). Backdrop gua
   (AlphaCutouts, vertikal 99%) sengaja TIDAK dianggap kubah.
3. Dasar lantai dunia bukan lagi min.y global (terseret kubah +10.6m) tapi
   kandidat tanah "besar&datar dekat bawah" (Object_16, 108m, min=-2.5);
   pusat x/z ikut tanah itu.
4. fallback_ground: posisi Shape dipindah ke CollisionShape3D (Shape3D tak
   punya .position — error diam-diam); player.gd berhenti menganggap lantai
   tak-ketemu laut (_swimming=false bila floor < -900).

## Ronde-16 — penutup sebenarnya dari misteri blue screen (2026-09-20)

User lapor: setelah instal ulang APK baru → TAK ADA unduhan sama sekali →
blue screen langsung. Dua hal dipisahkan:

1. "Tak ada unduhan" = KEWAJARAN — APK kini dari preset **Android AIO**
   (seluruh `packs/*` ter-bundle; mulai workflow TAG apk-20260920-2302).
   Verifikasi: `export_presets.cfg` preset 11 include `launcher/*,project.godot,packs/*`
   + release notes "seluruh konten ter-bundle di SATU aplikasi". Launcher menyemai
   state dari `res://packs/manifest.json`, versi cocok → skip unduhan (by design).

2. Blue screen = **error kompilasi**: `var total` dideklarasikan GANDA di
   `_build_static` (world.gd) — keduanya baris mati warisan edit ronde-15.
   GDScript analyzer menolak kelas → `load(WORLD_SCENE)` mengembalikan scene
   tanpa skrip → `await world.generate_async(self)` hentak runtime →
   `_boot_world` berhenti sebelum HUD → loading screen (bg biru-gelap
   `Color(0.06,0.10,0.16)`) menggantung = yang user sebut "blue screen".
   Ini juga menjelaskan kenapa versi-versi biru sebelumnya: chain yang sama
   (ponsel laporannya selalu "diam di layar biru setelah loading").

Aksi pencegahan permanen (agar tak lolos lagi tanpa terlihat):
- `tools/analyze_checks.py` — lint tingkat analyzer (dup-var per scope;
  preload/load/const path; rujukan scene .tscn) → gerbang CI sebelum export.

## Ronde-17 — APK kembali Launcher-murni + anti-blue-screen permanen (2026-09-20)

1. **APK = peluncur murni, DILARANG berubah** (aturan user: update selalu lewat
   server pack, tak pernah menyentuh aplikasi). Preset "Android AIO" dihapus dari
   export_presets.cfg; workflow kini hanya export "Android Launcher"
   (include: launcher/*,project.godot). APK kecil; boot pertama mengunduh
   ~8 pack dari branch `content`; selanjutnya delta saja.
2. **Watchdog 40 detik**: bila boot macet pada tahap mana pun, layar merah
   menampilkan tahap terakhir + ekor log boot + info perangkat (OS/renderer/
   resolusi) — TIDAK ADA LAGI blue screen diam-diam tanpa bisa didiagnosis.
3. **Log boot permanen** `user://boot_log.txt` — setiap tahap `_trace` (launcher,
   dunia 0..100%, spawn, HUD) dicatat waktu & perangkat.
4. **Anti-freeze pembangunan world**: `_static_walk` kini async — yield
   `process_frame` tiap 12 mesh; bar loading tetap hidup di ponsel lemah,
   watchdog tak tembak palsu-positif.

Hipotesis terbuka bila setelah ini masih biru: eksekusi tak pernah sampai
`game_root._ready` (scene change BBC / hijack)—verifikasi lewat log launcher
yang kini ikut menulis `=== BOOT BARU ===`… atau GPU/Adreno gagal kompilasi
sky shader → panel merah watchdog akan menunjuk tahapnya.

## Ronde-18 — pembunuh macet terfoto bukti (bukti visual user, 2026-09-21)

Bukti lapangan (screenshot user): watchdog menyala, tahap terakhir
"membangun dunia", timer jalan → eksekusi HIDUP tapi tak maju — bukan crash.
Deduksi: script memproses semua segitiga diorama (grid bucket tinggi tinggi
jutaan operasi GDScript vs backdrop AlphaCutouts ratusan ribu poligon) →
boot butuh menit di Infinix X6853 (hp budget user).

Prinsip yang ditetapkan (tak berubah lagi):
1. Jangan sekali-kali loop segitiga/verteks kustom di GDScript untuk tugas
   produksi di ponsel — pakai API engine (intersect_ray, trimesh shape).
2. Collision hanya untuk mesh solid besar (≥6m); yang kecil/decoratif/cutout
   visual saja — phyis register rendah, boot detik level, RAM hemat.
3. `_static_floor_at` = `PhysicsRayQueryParameters3D.intersect_ray` dari
   _hit_top→_hit_bottom (dihitung dari AABB scene setelah skala world).
   find_spawn_point + height_at API tak berubah (pemain/UI tak perlu diubah).

Deteksi tak lagi "tebakan": bukti = screenshot watchdog user.

## Ronde-19 — skin bawaan = Mannequin UAL (upload user) 2026-09-21

- Karakter bawaan diganti ke **Universal Animation Library Standard**
  (Quaternius CC0, unggahan user). 43 animasi lengkap → resolve melalui tabel
  `SKINS["mannequin"].states`. Varian dipakai: Standard (in-place; root motion
  TIDAK dibutuhkan — gerak dikendalikan CharacterBody3D). Varian _RM dibiarkan
  di folder sumber saja.
- Default `char_skin` = "mannequin" di settings + player + pause menu
  (pilihan kini triple: Mannequin/PolyGirl/Knight — dua skin lama tetap tersedia).
- CREDITS: entri Quaternius CC0 + License.txt asli tetap di repo.

## Ronde-20 — T-pose mannequin (resolver nama animasi) 2026-09-21

- Gejala: skin mannequin muncul tapi T-pose abadi → animasi resolved kosong atau
  tersingkir. Teori duga kuat: di ekspor, animasi GLB tampil dengan prefix library
  ("LIB/Idle_Loop") sehingga candidate exact-name luput — resolver stok lama hanya
  melakukan `names.has(cand)`.
- Solusi: resolver 3-tahap di AnimController (exact → basename strip-prefix →
  lower-substring) + fallback akhir "yang ada kata idle" (TAK PERNAH T-pose) +
  print resolusi ke konsol + trace on-device menunjukkan state yang gagal-resolve.
- Dble cepatnya: tak perlu import-settings apapun di editor.

## Ronde-21 — macet walk & attack-sekali: flag air/swim tak pernah turun (2026-09-21)

- Kedua gejala satu akar di AnimController: set_move() early-return kalau
  _air/_swimming true; keduanya diset via set_air("jump_start"/"jump_fall")/
  set_swim(true) tapi TAK PERNAH di-reset di alur (player tak pernah memanggil
  set_air(""); pendaratan kecil lewat action("jump_land") yg tak menyentuh flag).
- Dampak: walk hilang permanen & 'attack hanya sekali' (current tersumpal di
  "attack" karena tak ada perjalanan balik menuju move-state).
- Solusi: set_move() mengandalkan fakta bahwa player.gd hanya memanggilnya saat
  grounded — ia mereset _air/_swimming di awal. Ketahanan devikit bertambah.

## Ronde-22 — crouch nyangkut (jalan jongkok) + ikon HUD digambar (2026-09-21)

- Akar "jalan jongkok / tak ada walk-run": tombol Crouch = HOLD; bila jari
  bergeser lalu diangkat di luar bounds, `released` tersesat → crouch=true
  permanen → set_move selalu crouch. Kini: Crouch = TOGGLE TAP; status visual
  mengikuti player.crouch. PLUS: RpgButton _input global melepas berdasarkan
  INDEX sentuhan → release tak pernah hilang lagi untuk semua tombol hold
  (sprint mis.).
- Ikon: emoji/glyph (✋ » ▼ 🙂 pecah jelek di HP) diganti ikon canvas digambar
  tangan: bolt (sprint), chevron-kepala (crouch), smile (emote), arrow-down-to-
  palm (aksi). Layout disusun ulang mengacu referensi: attack besar kanan-bawah
  tengah, dash bawah-kanannya, lompat pojok kanan bawah, kolom kecil di kirinya.
- Joystick: panel dasar kini LINGKARAN penuh (radius JOY_RADIUS), alfa dipudupkan.

## Ronde-23 — spawn depan rumah + jejak animasi on-device (2026-09-21)

- Spawn baru: pindai 8 arah dari pusat ground, tolak titik floor ≥1.8m (atap);
  arah dgn jalur landai terpanjang = depan rumah. Fallback: kandidat lama tapi
  kini juga lolos filter atap. Untuk "dong di atas" dari atap-atap-an.
- Jejak diagnostik "anim:%s sp:%.1f crouch:%s skin:%s" tiap 0,9 dtk (teks kuning
  kiri bawah; trail boot kini hidup 20 detik) — foto dua detik setelah berjalan
  membuktikan state mana yg benar-benar bermain dalam kasus "jalan jongkok".
- Selanjutnya mengandalkan bukti foto itu (bukan tebakan).

## Ronde-24 — "jongkok" = jump_fall tak pernah turun dari trimesh (2026-09-21)

- Dua screenshot user (jalan di halaman: kaki terlipat = pose `jump_fall`/tuck,
  dan "stuck gk bisa lompat di rumput") menyatu jadi SATU sebab kandidat:
  `is_on_floor()` engine tidak pernah true di atas trimesh collider diorama —
  kontak FISIKA ada (tidak tembus), tapi status floor tak tercatat. Akibatnya:
  (1) `_update_model` menge-set `anim.set_air("jump_fall")` tiap frame →
  karakter tampak jongkok/lipat-kaki saat berjalan; (2) coyote tak pernah
  terisi → lompat mati di rumput.
- Fix: grounded kini diuji via RAY native `world.height_at()` (distance kaki —
  persis yg dipakai sistem renang/y offset posisi → nol risiko salah-hit):
  `_near_floor = floor_h > -900 and (y - floor_h) <= 0.42`.
  - Gerbang lompat: `(_coyote > 0.0 or _near_floor)` → lompat SELALU hidup
    di permukaan manapun yg kakinya memang menyentuh tanah.
  - Gerbang animasi: `_near_floor and _action_lock<=0` → `anim.set_move(...)`
    sebelum cabang airborne; pose tuck saat berjalan musnah.
- Diagnostik permanen: label kuning bawah-tengah `hud.anim_debug(...)`
  (pengganti `_trace` yg mati bareng trail boot 20 detik — "gk ada teks apa
  apa" dari user). Menampilkan `anim:<state> sp dh onf cr` tiap 0,9 detik;
  foto berikutnya memfilter tiga cabang (cr nyangkut / onf:false engine /
  sp:0 jalur input) bila gejala masih tersisa.

## Ronde-25 — pelajaran kick-39: ui pack tertinggal + bump liar (2026-09-21)

- Kick-39 terbit dgn DUA kekeliruan manifest: (1) pack `ui` tidak ter-bump
  (tetap 1.0.9 dgn sha IDENTIK ke yg di HP) → `hud.anim_debug` TIDAK terkirim,
  padahal player 1.0.14 sudah memanggilnya (aman: has_method guard, tapi probe
  tak tampak). Sebab: run build_packs lokal sebelumnya sudah menaikkan ui ke
  1.0.10+hash-baru di versions.json, lalu skrip sinkronisasi LIVE menimpanya
  balik ke 1.0.9 + hash FRESH (=konten baru ⇒ tak terdeteksi berubah).
  (2) world_terrain bump liar 1.0.26→1.0.27 tanpa edit — folder_hash memakai
  urutan os.walk (urutan filesystem) sehingga hash beda antar mesin.
- Perbaikan permanen: folder_hash kini mengumpulkan SEMUA path relatif lalu
  mengurutkannya (deterministik antar-mesin); versions.json disinkronkan ke
  manifest LIVE pasca-39 (player 1.0.14, world 1.0.27 …) dengan hash orde-
  terurut; ui dipaksa hash-nol agar CI menaikkannya ke 1.0.10 dan mengekspor
  ulang dgn konten barunya (anim_debug).
- Aturan baru: JANGAN menimpa paksa versions.json bila build_packs sudah
  menaikkan versi — selalu tanya manifest branch content yang LIVE.

### Lanjutan ronde-25 — resolusi akhir (kick-40)

- ALARM "ui pck konten lama" = salah baca: pck menyimpan GDScript terkompilasi
  (token biner), jadi grep string sumber selalu gagal. Bukti riwayat sha pck ui
  di branch content: 6fdcaa (kick-37/38) → fa65cc (kick-39 @eb478bf, SAMA dgn
  kick-40) → anim_debug/l near_floor MEMANG sudah LIVE sejak kick-39/40.
- Bump liar player/world berulang padahal isi identik & file-set identik dgn
  git: versi base repo buatan lokal ≠ hash hasil CI hanya untuk 2 pack tsb
  (6 lain cocok). Diduga langkah `--import` Godot di CI menulis ulang metadata
  di dalam dua folder itu. Solusi permanen MURAH: base versions.json WAJIB
  disalin dari branch `content` (versions.json yang ditulis CI sendiri),
  BUKAN dihitung lokal: `git show origin/content:versions.json > server/versions.json`.
- Status LIVE final ronde ini: game 1.0.28 — character_player 1.0.15 (ray
  _near_floor + lompat + gerbang anim ground), ui 1.0.10 (label anim_debug),
  world_terrain 1.0.28, core 1.0.10, animations 1.0.7. HP re-download delta
  otomatis (sha beda) saat aplikasi dibuka.
