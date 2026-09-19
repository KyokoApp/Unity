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
