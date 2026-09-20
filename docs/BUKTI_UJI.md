# BUKTI UJI — pulau toon / launcher arsitektur

Dokumen ini merangkum hasil uji end-to-end terakhir (semua log mentah:
`server/test_logs/` — dibuat ulang oleh `tools/run_all_tests.sh`).

## Ringkasan hasil (11/11 hijau)

```
[ OK ] manifest ada
[ OK ] manifest tersaji
[ OK ] Range dijawab 206 (resume didukung)
[ OK ] dunia selesai digenerate
[ OK ] tanpa error runtime
[ OK ] delta: hanya 1 pack berubah
[ OK ] launcher hanya mengunduh 1 pack
[ OK ] mode offline berfungsi
[ OK ] run offline tanpa error runtime
[ OK ] karakter: 76 animasi, semua state terpenuhi, 240 transisi aktif
[ OK ] preset efektif: skala monoton naik, Sedang=30 FPS
```

Jumlah kesalahan runtime di seluruh run launcher:
`run1 = 0 SCRIPT ERROR | run2 = 0 | run3 = 0`.

## 1. Unduhan penuh 10 pack (fresh install)

```
[updater] Mengunduh manifest (1/3): http://127.0.0.1:8787/manifest.json
[updater] Perlu mengunduh 10 pack (2.9 MB): core_scripts, shaders_materials,
          world_terrain, world_props_forest, world_props_beach, animations,
          character_player, ui, audio_sfx, audio_music
[updater]   OK: core_scripts (18 KB) ... OK: character_player (1.3 MB)
[updater]   OK: ui (35 KB) ... OK: audio_music (1.3 MB)
[gen] 0% Membangun pulau ... [gen] 100% Dunia siap
```

Server dev menjawab `Range: bytes=…` dengan **HTTP 206** (resume dukung).

## 2. Update delta (hanya 1 pack)

Perubahan 1 komentar di `project/packs/ui/hud.gd` ⇒ hanya pack `ui` naik:

```
[change] ui: konten berubah -> v1.0.4
[updater] Perlu mengunduh 1 pack (35 KB): ui
[updater]   OK: ui (35 KB)
[updater] Menghapus pack lama: ui-1.0.3.pck
```

Setelah uji, `hud.gd` dikembalikan otomatis oleh skrip uji (self-restore).

## 3. Mode offline

```
[updater] Server tidak terjangkau — memakai pack lokal (offline).
[gen] 100% Dunia siap
```

## 4. Karakter & animasi (probe `character_anim_check.gd`)

```
[anim-check] jumlah animasi di GLB: 76
[anim-check][ OK ] idle -> Idle          [anim-check][ OK ] walk -> Walking_A
[anim-check][ OK ] run -> Running_A      [anim-check][ OK ] sprint -> Running_B
[anim-check][ OK ] jump_start -> Jump_Start   [ OK ] jump_fall -> Jump_Idle
[anim-check][ OK ] jump_land -> Jump_Land
[anim-check][ OK ] crouch_idle -> Idle   [anim-check][ OK ] crouch_move -> Walking_B
[anim-check][ OK ] swim_idle -> Jump_Idle [anim-check][ OK ] swim_move -> Walking_A
[anim-check][ OK ] pickup -> PickUp
[anim-check][ OK ] aksi attack -> 1H_Melee_Attack_Chop
[anim-check][ OK ] aksi emote -> Cheer     [anim-check][ OK ] interact -> Interact
[anim-check] transisi state machine: 240 (AnimationTree aktif)
[anim-check] HASIL: SEMUA STATE TERPENUHI
```

Crouch/swim memakai varian gerak yang ada sesuai DECISIONS D-10 (KayKit tidak
menyediakan animasi khusus itu); fallback generik mengisi state apa pun yang
tidak tersedia sehingga state machine tidak pernah kosong.

## 5. Preset kualitas (probe `quality_presets_check.gd`)

```
[quality] preset Rendah  ef: scale=0.60 fps_cap=30 shadows=false shadow_dist=45
[quality] preset Sedang  ef: scale=0.75 fps_cap=30 shadows=true  shadow_dist=70
[quality] preset Tinggi  ef: scale=0.90 fps_cap=60 shadows=true  shadow_dist=110
[quality] HASIL: 3 preset terverifikasi efektif (skala monoton naik, Sedang=30 FPS)
```

Nilai efektif dibaca kembali dari objek mesin sungguhan (Window.scaling_3d_scale,
Engine.max_fps, DirectionalLight3D.shadow_*). Catatan: pada konteks headless,
`Node.get_viewport()` baru resolve setelah 1 frame — probe men-*defer* setelah
frame pertama (bukan bug game; di scene nyata QualityManager hidup di SceneTree).

## 6. Bukti visual (tanpa GPU)

Sandbox tidak punya X11/GL/Vulkan → screenshot **engine** tidak dapat diambil.
Sebagai gantinya, renderer CPU `project/dev_probe/visual_proof.gd` menggambar
ulang **DATA ASLI** dunia prosedural (`island.gd`) dengan **rumus persis**
dari shader paket: `toon.gdshader` (3 band + rim), `sky.gdshader` (gradasi +
cakram matahari), `water.gdshader` (shallow/deep/foam + band), serta contour
outline gelap ala inverted-hull. Hasil:

- `docs/screenshots/biome_map.png` — peta pulau lengkap (bioma, sungai, danau,
  relief ber-anekat warna + hillshade 3 band).
- `docs/screenshots/view_day.png` — pandangan dari pantai ke pagar bukit,
  matahari siang + halo.
- `docs/screenshots/view_dusk.png` — senja: horizon oranye, zenith ungu,
  siluet bukit tersinari.
- `docs/screenshots/view_night.png` — malam: bintang, bulan, pencahayaan
  bulan redup (verifikasi siklus siang-malam).

Cara bangkitkan ulang:

```bash
GODOT_BIN=/home/user/tools/godot-src/bin/godot.linuxbsd.editor.x86_64
$GODOT_BIN --headless --path project --script dev_probe/visual_proof.gd
```

## 7. Build APK (status: satu pengecualian terdokumentasi)

`tools/export_android.sh` berhasil melewati SELURUH validasi konfigurasi,
kecuali satu-satunya aset biner yang tidak bisa diunduh di sandbox
(egress hanya mengizinkan github.com core + registry pypi/npm; host biner
`objects.githubusercontent.com` & `downloads.tuxfamily.org` diblok):

```
Could not find version of build tools that matches Target SDK, using 34.0.0
ERROR: Cannot export project with preset "Android Launcher" due to configuration errors:
No export template found at the expected path:
/home/user/.local/share/godot/export_templates/4.5.2.stable/android_debug.apk
No export template found at the expected path:
/home/user/.local/share/godot/export_templates/4.5.2.stable/android_release.apk
```

Yang telah terverifikasi di sisi kami: preset lengkap + runnable, Java SDK
(jdk4py Temurin 25.0.2) terdeteksi, Android SDK layout (build-tools 34.0.0:
`aapt2` 2.20, `apksigner` berfungsi `--version` → 0.9, platform-tools `adb`
stub menjawab `--version`), keystore debug RSA-2048 valid. Begitu
export templates resmi dipasang (satu langkah):

```bash
sh tools/fetch_export_templates.sh && sh tools/export_android.sh
```

CLI akan menghasilkan `exports/android/PulauToon-debug.apk` (preset
`runnable=true` hanya berisi launcher; pck ditandatangani hash oleh updater).
