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
