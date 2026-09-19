# 🌴 Pulau Toon

Game **third-person eksplorasi pulau** gaya kartun (cel-shading + outline) untuk
**Android**, dibangun dengan **Godot 4.5** (GDScript murni). Dunia **prosedural
1,6 × 1,6 km** dengan bioma pantai/hutan/padang/bukit + sungai dan danau,
siklus siang-malam, dan kontrol sentuh lengkap (joystick + geser kamera +
tombol aksi multi-touch).

**Prinsip distribusi:** APK yang diinstal ke ponsel hanya berisi **launcher +
updater + UI**. Seluruh konten game dikirim sebagai **resource pack (`.pck`)
ber-versi**, diunduh sekali lalu hanya pack yang berubah yang diunduh ulang
(delta update) — cocok untuk hosting statis murah/CDN.

---

## Daftar isi

1. [Prasyarat](#1-prasyarat)
2. [Bangun pack konten](#2-bangun-pack-konten)
3. [Jalankan server konten lokal](#3-jalankan-server-konten-lokal)
4. [Jalankan game (dev/headless)](#4-jalankan-game-devheadless)
5. [Build APK launcher](#5-build-apk-launcher)
6. [Rilis update konten (delta)](#6-rilis-update-konten-delta)
7. [Hosting produksi](#7-hosting-produksi)
8. [Arsitektur pack](#8-arsitektur-pack)
9. [Preset kualitas & performa](#9-preset-kualitas--performa)
10. [Uji yang sudah dijalankan](#10-uji-yang-sudah-dijalankan)
11. [Troubleshooting](#11-troubleshooting)

---

## 1. Prasyarat

| Kebutuhan | Versi | Keterangan |
|---|---|---|
| Godot Editor (linux headless cukup) | **4.5.x** | dipakai untuk import proyek & export pack/APK |
| Python | 3.9+ | untuk `tools/*.py` (stdlib saja) |
| Android export templates | 4.5.x | hanya untuk build APK |
| Android SDK (platform + build-tools) + JDK 17+ | — | hanya untuk build APK |

Di sandbox ini Godot dibangun dari source ke
`tools/godot-src/bin/godot.linuxbsd.editor.x86_64`. Atau install Godot resmi
dan beri tahu tooling lewat `--godot` / env `GODOT_BIN`.

> Setelah Godot tersedia pertama kali, jalankan import sekali:
> `godot --headless --path project --import` — ini mengisi cache `.godot/`
> (import `.wav`, `.glb`, shader, dsb.).

## 2. Bangun pack konten

```bash
python3 tools/build_packs.py [--godot /path/ke/godot] [--force]
```

Yang dilakukan:
- Menghitung **hash isi** tiap folder `project/packs/<id>` (versi hanya
  naik bila isi berubah — ini kunci delta update).
- Men-generate `project/export_presets.cfg` (preset Android launcher +
  satu preset `.pck` per pack).
- Menjalankan `godot --export-pack` untuk pack yang berubah.
- Menulis **`server/manifest.json`** + `server/packs/<id>-<versi>.pck`
  (+ `server/versions.json` untuk pelacakan versi, + `server/build_log.json`).

Bila Godot belum tersedia, `--skip-export` tetap men-generate manifest
(dengan size/hash kosong) — berguna untuk uji tooling.

## 3. Jalankan server konten lokal

```bash
python3 tools/dev_server.py 8787 server   # mendukung HTTP Range (resume)
```

Endpoint: `http://127.0.0.1:8787/manifest.json`,
`http://127.0.0.1:8787/packs/*.pck`.

## 4. Jalankan game (dev/headless)

**Via launcher (alur penuh — persis seperti di HP):**

```bash
godot --path project -- --server http://127.0.0.1:8787
```

Launcher akan: unduh manifest → bandingkan pack lokal → unduh yang kurang
(dengan resume + verifikasi SHA-256) → `load_resource_pack()` tiap pack →
masuk scene game.

**Langsung ke scene game (lewat launcher — untuk uji gameplay cepat):**

```bash
godot --path project res://packs/core_scripts/game_root.tscn
```

(di mode ini game membaca pack langsung dari `res://`.)

**Di HP:** ketuk ikon aplikasi → launcher membuka server yang diset
(lihat tombol “Server…” di UI launcher; default `http://127.0.0.1:8787` —
ganti ke IP LAN/server produksi Anda).

## 5. Build APK launcher

Pipeline lengkap tersedia sebagai satu perintah:

```bash
# sekali saja (host dengan akses internet normal):
sh tools/fetch_export_templates.sh   # android_debug/release.apk → ~/.local/share/godot/export_templates/4.5.2.stable/

# setiap build:
sh tools/export_android.sh           # → PulauToon-debug.apk + PulauToon-aio.apk (+ export.log)
```

Dua varian aplikasi dihasilkan dari satu project (preset sudah siap dalam
`export_presets.cfg`):

| Varian | Isi | Cocok untuk |
| --- | --- | --- |
| **PulauToon-debug.apk** ("Android Launcher") | hanya launcher+updater | Model rilis delta (butuh server konten di run pertama) |
| **PulauToon-aio.apk** ("Android AIO") | launcher + semua pack ter-bundle | Main langsung tanpa server; update delta selanjutnya tetap jalan normal |

`export_android.sh` menulis editor settings (`export/android/*` —
android_sdk_path, java path, keystore debug RSA-2048 yang digenerate dengan
`keytool`), lalu menjalankan `--export-debug` untuk kedua preset (lewati AIO
dengan `EXPORT_AIO=0`). Preset menargetkan **arm64-v8a**, **INTERNET**,
**landscape**, immersive.

**Install ke HP:**

```bash
adb install -r exports/android/PulauToon-aio.apk   # langsung main
# atau launcher online:
adb install -r exports/android/PulauToon-debug.apk
# lalu isi URL server masuk di launcher (http://<IP-LAN>:8787; lihat bagian §3)
```

> **Catatan sandbox ini**: jaringan egress membatasi host biner resmi Godot
> (objects.githubusercontent.com & tuxfamily diblok), sehingga dua berkas
> template — satu-satunya aset yang tidak dapat dijangkau — tidak terpasang.
> Validasi export berjalan sampai titik itu saja (SDK ✓ apksigner ✓ aapt2 ✓
> keystore ✓ preset ✓ keystore/Java ✓); lihat `docs/BUKTI_UJI.md` §5 untuk
> log persisnya. Dua perintah di atas adalah prosedur yang sama persis dengan
> mesin dev normal → akan menghasilkan APK begitu template terpasang.

Install & uji di perangkat (bila `adb` ada):

```bash
adb install -r exports/android/PulauToon-debug.apk
```

## 6. Rilis update konten (delta)

1. Ubah isi pack (mis. tambah pohon di `world_props_forest`).
2. `python3 tools/build_packs.py` → hanya pack itu yang versinya **naik**
   dan `.pck`-nya dibangun ulang; `manifest.json` diperbarui.
3. Salin isi `server/` ke hosting.
4. Di HP, buka aplikasi → launcher otomatis mengunduh **hanya pack yang
   berubah** (bukti ada di log launcher: “Perlu mengunduh 1 pack…”).

## 7. Hosting produksi

Persyaratan server **statis** saja:
- Sajikan `/manifest.json` dan `/packs/*.pck` lewat HTTP(S).
- **Wajib mendukung Range request** (untuk resume; S3/OSS/CDN umumnya sudah).
- `Content-Type` bebas (launcher membaca byte mentah).

Ganti URL default di `project/launcher/launcher.gd` (`DEFAULT_SERVER`) atau
lewat UI “Server…” di launcher.

## 8. Arsitektur pack

```
project/
├─ launcher/            # ISI APK: launcher/updater UI (mandiri, tanpa pack)
└─ packs/
   ├─ core_scripts/     # GameRoot, GameSettings, QualityManager
   ├─ shaders_materials/# toon/outline/grass/water/sky + materials.gd
   ├─ world_terrain/    # island (model), chunk LOD+streaming, meshlib, world
   ├─ world_props_forest# pohon/semak/batu/rumput/bunga (MultiMesh)
   ├─ world_props_beach # palem, kerang, mercusuar, dermaga, gubuk, perahu
   ├─ animations/       # AnimationTree builder + resolver nama anim
   ├─ character_player/ # Knight.glb (KayKit CC0) + controller third-person
   ├─ ui/               # HUD sentuh, loading, pause + pengaturan
   ├─ audio_sfx/        # SFX synth (.wav)
   └─ audio_music/      # musik synth (.wav) + audio_director
```

Aturan: pack **tidak saling autoload**; dependensi dinyatakan di
`manifest.json` (`deps`) dan loader memuat sesuai `pack_order`.

## 9. Preset kualitas & performa

| Pengaturan | Rendah | Sedang (default) | Tinggi |
|---|---|---|---|
| Skala render 3D | 0.60 | 0.75 | 0.90 |
| Ring chunk terrain | 4 | 6 | 8 |
| Kepadatan rumput | 30% | 60% | 100% |
| Kepadatan pohon | 60% | 85% | 100% |
| Shadow directional | mati (+blob shadow) | on (2048, 70 m) | on (2048, 110 m) |
| Fog | sedikit lebih tebal | normal | lebih tipis |
| Batas FPS | 30 | 30 | 60 |

Target: **30 FPS stabil di preset Sedang** pada HP menengah (renderer
*Mobile*, ~<120 draw calls, instancing MultiMesh, chunked LOD + streaming,
shader ringan tanpa post-process).

## 10. Uji yang sudah dijalankan (ringkasan hijau)

Orkestrator `tools/run_all_tests.sh` dijalankan terakhir dengan hasil **11/11**:

```
[ OK ] manifest ada                [ OK ] Range dijawab 206 (resume)
[ OK ] manifest tersaji            [ OK ] dunia selesai digenerate
[ OK ] tanpa error runtime         [ OK ] delta: hanya 1 pack berubah
[ OK ] launcher hanya unduh 1 pack [ OK ] mode offline berfungsi
[ OK ] run offline tanpa error      [ OK ] karakter: 76 animasi, 240 transisi
[ OK ] preset efektif (Rendah<Sedang<Tinggi, Sedang=30 FPS)
```

3 skenario launcher (unduhan penuh 10 pack, delta 1 pack `ui` 35 KB, offline)
semuanya berakhir dengan **0 SCRIPT ERROR**; probe karakter (76 animasi KayKit,
semua state terpetakan, AnimationTree 240 transisi aktif) dan preset kualitas
(efektif terbaca dari objek mesin; Sedang=30 FPS) keduanya lulus. Cuplikan log & detail:
`docs/BUKTI_UJI.md`. Bukti visual toon/langit/siang-malam (renderer CPU
shader-accurate, sandbox tanpa GPU): `docs/screenshots/` — `biome_map.png`,
`view_day.png`, `view_dusk.png`, `view_night.png`.

## 11. Troubleshooting

- **“Server tidak terjangkau”** — pastikan `dev_server.py` jalan dan URL di
  launcher benar (pakai IP LAN untuk HP fisik, bukan 127.0.0.1).
- **“HASH SALAH”** saat unduh — pack di server diubah tanpa menaikkan versi;
  selalu lewat `build_packs.py`.
- **Export Android gagal** — periksa `android_sdk_path`, export templates
  4.5.x, dan keystore di Editor Settings.
- **Stutter saat awal main** — normal di detik pertama (cache shader);
  kompilasi shader akan ter-cache oleh driver.
