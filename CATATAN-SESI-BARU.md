# CATATAN SERAH TERIMA — Aurelia (baca ini dulu di sesi baru)

> Tanggal: 2026-09-17 · Branch kerja: **`arena/01a0ad77-unity`** (sesi Arena baru
> memakai branch tetap `arena/01a0ad77-unity`; branch lama `arena/01a0ac44-unity`
> sudah digabung penuh ke sini — DONOT push ke sana lagi).
> Untuk AI berikutnya: **baca file ini sampai habis sebelum menyentuh apa pun**.

## 1. Proyek & aturan main (JANGAN dilanggar)
- Game: **Aurelia** — open-world anime Genshin-like, open terrain 3×3 km, target **Android**.
- Engine: **Godot 4.5.1**, bahasa **GDScript** (bukan C#, bukan Unity — Unity sudah dihapus total & jangan dikembalikan).
- Proyek Godot berada di **root repo** (`project.godot` di `/`). Scene utama `res://scenes/world.tscn` (root Node3D + skrip `runtime/world.gd` yang membangun semua dari kode).
- Kerja HANYA di branch `arena/01a0ad77-unity`; setiap commit push ke sana. PR #4 (dari branch lama) masih menunggu user yang merge sendiri — biarkan.
- GitHub `gh`/git sudah terautentikasi di sandbox. Push → dua run CI (`godot-tests` + `android-build`); event `pull_request` bisa menggandakan run — **wajar**.

## 2. Status sekarang (yang SUDAH jadi)
- Dunia tampil di HP (sky, terrain, air, rumput, HUD); ikon anime terpasang.
- CI `godot-tests`: 157 unit test + smoke-run 600 frame + touch probe (**naik dari 14 ke 24 cek** sesi ini).
- CI `android-build`: artefak APK `aurelia-debug`, sekarang **berstempel build** (`runtime/build_stamp.gd` ditulis CI sebelum ekspor).
- `version/name=0.2.0`, `version/code=2` (agar update APK bersih).
- Log diagnostik CI di branch `ci-logs` (run-log.txt = unit + probe, boot-log.txt = smoke, probe-log.txt):
  ```
  git fetch origin '+refs/heads/ci-logs:refs/remotes/origin/ci-logs' --force
  git show origin/ci-logs:run-log.txt
  ```

## 3. Prioritas #1 — "analog gk muncul di HP" (sesi ini)

### Dua bug NYATA ditemukan & diperbaiki
1. **Skala koordinat ganda** (`ui/virtual_joystick.gd`): `event.position` di
   `_gui_input` SUDAH koordinat lokal control (engine xform). Kode lama membaginya
   lagi dengan `_scale = max(vs/REF)` → di HP non-1920×1080 (mis. 2400×1080, skala
   sebenarnya 1,0) alas stik muncul **melenceng ±20% dari jari**. Fix: pakai posisi
   apa adanya; `_scale`/​`_recalc_scale` dihapus.
2. **Touch-capture tidak ada di Godot GUI**: begitu jari keluar rect zona stik,
   `_gui_input` berhenti menerima event → stik membeku di nilai terakhir DAN kamera
   ikut memutar (event jatuh ke `_unhandled_input`). Fix: `VirtualJoystick._input()`
   menangkap kelanjutan gerak/lepas untuk jari milik stik + `set_input_as_handled()`
   + `accept_event()` pada press/release GUI. Dedup per-frame (`_drag_frame`/
   `_release_frame`) mencegah proses ganda jalur GUI+_​input.

### Alat baru untuk membuktikan sisanya di HP user
- **Stempel build di layar**: loading screen kanan-bawah, PerfHud, strip debug,
  BootLog. Kalau stempel di HP user ≠ hash commit terbaru → **itu APK lama**
  (hipotesis utama sesi lalu). CI menulis stempel `<hash7>-b<run>`.
- **`ui/touch_debug.gd`** (CanvasLayer 90, semua IGNORE, auto-ON hanya di
  `OS.is_debug_build()`): strip teks kiri-atas + jejak titik sentuh + bingkai emas
  rect zona stik persis seperti dihit engine. Tiga penghitung diagnosis:
  `os` (Node._input) · `stikGUI` (VirtualJoystick._gui_input) · `kamera`.
  - `os` naik, `stikGUI` diam, `kamera` naik → **routing GUI mati di device itu**
    (jari dipastikan ADA di dalam bingkai zona). Rencana lanjutannya: jalankan
    stik/​tombol lewat `_input` semua (pekerjaan besar, tunggu data dulu).
  - `os` ikut diam → sentuhan tidak masuk aplikasi (emulasi/skin Android?).
  - Semua naik tapi stik tak terlihat → masalah visual (warna/lapisan), bukan input.
- **Cincin hantu saat siaga** di stik (alpha tipis di titik klasik) — "analog tidak
  muncul" tidak boleh lagi berarti "layar kosong polos"; stik tetap mengambang
  mengikuti jari saat disentuh.
- `VirtualJoystick._gui_input` me-`print()`+BootLog 3 touch-down pertama
  (`[stik] touch-down #N idx=.. lokal=.. rect=..`) → terbaca di ci-logs & logcat.

### Cara pakai setelah user unduh APK baru
Minta screenshot saat jari menekan kiri-bawah: baca stempel (benar build ini?),
bingkai zona (ada jari di dalam?), dan tiga penghitung (ujung diagnosis di atas).

## 4. TUGAS TERBUKA — urutan prioritas dari user

### 4a. 🟡 Konfirmasi analog di HP (menunggu user tes APK stempel-baru)
Jika stik tetap diam padahal stempel benar → kirim screenshot strip debug →
tindak lanjut sesuai tabel diagnosis §3 (routing mati / os mati / visual).

### 4b. 🟡 Ganti karakter + animasi jalan/lari/idle/dash/attack (aset dari user)
LINK USER (drive):
- **Model + klip animasi**: https://drive.google.com/file/d/120fNMWnpMaiNEJLG53LdTd8DfSGdFrYq/view?usp=drivesdk
- **Model karakter**: https://drive.google.com/file/d/1RZIwux_yJ6VB2j4nAsYdUlfcca0BLPar/view?usp=drivesdk
Pekerjaan:
1. Unduh (sandbox mungkin memblokir download langsung — coba downloader / tanya
   user lampirkan ke sesi; kalau zip besar: jangan commit mentah, ekstrak ke `models/`).
2. Format tujuan: **GLB** di `models/` (Godot impor otomatis; folder di-gitignore).
3. Sambung di `runtime/character_rig.gd` (`model_paths` → fallback mannequin);
   drive `AnimationPlayer` dari `CharacterMotor` (sinyal: `move01`, `run01`,
   `is_dashing`, `combat.is_attacking()`, `landed`, `attack_started(combo)`). Peta
   blend lama: `Locomotion.sample_pose` — jaga transisi halus.
4. Material toon: `runtime/toon_character_setup.gd` + `shaders/aurelia_toon.gdshader`.
5. Baca dulu `models/LISENSI.md` (lisensi! jangan commit/bundle aset itu).

### 4c. 🟢 Rumput dari aset user
LINK USER: https://drive.google.com/file/d/18WFEJckB7Kn1ifvTe_JpAs7bB4iKbGZf/view?usp=drivesdk
Sekarang rumput 100% prosedural: `runtime/grass_field.gd` (MultiMesh per-chunk) +
`shaders/aurelia_grass.gdshader`. Kalau tekstur → material bilah, pertahankan angin
vertex-shader; kalau mesh → sumber MultiMesh. Jaga kontrak tier di
`core/quality_presets.gd`.

### 4d. ℹ️ Umum
- User merge PR-nya sendiri bila siap. Unduh APK terbaru = artefak `aurelia-debug`
  run `android-build` terbaru (cek stempel hash!).
- Ikon anime persis = menunggu lampiran ulang gambar user (PIL ada di sandbox;
  numpy TIDAK ada — `pip install --user --break-system-packages pillow`).

## 5. Peta kode kilat
| Path | Isi |
|---|---|
| `runtime/world.gd` | World composer + urutan boot; memasang `TouchDebug.enabled = OS.is_debug_build()` |
| `runtime/build_stamp.gd` | Stempel build (DITIMPA CI; di repo = `dev-lokal`) |
| `runtime/character_motor.gd` | Gerak pemain — memindahkan `rig` induknya |
| `runtime/character_rig.gd` | Pembawa visual + pose prosedural 25 sendi (sambungan GLB di sini) |
| `runtime/camera_rig.gd` | Kamera orbit; `_unhandled_input`; melapor ke TouchDebug |
| `runtime/terrain_chunk_streamer.gd`, `grass_field.gd`, `water_plane.gd`, `orbs.gd` | Streaming chunk/prop, rumput, air, orb |
| `ui/game_hud.gd`, `ui/virtual_joystick.gd`, `ui/ui_kit.gd` | HUD dari kode (layer 10). **Aturan: dekoratif=IGNORE, interaktif=STOP/panel anak; stik=PASS+accept_event** |
| `ui/touch_debug.gd` | Strip diagnosa sentuh (layer 90, semua IGNORE) |
| `ui/loading_screen.gd` | Loading ala Genshin + stempel build |
| `shaders/*.gdshader` | Shader Godot-4-sahih; rubah dengan takut |
| `core/*` | terrain/world data, locomotion, quality presets, settings (kunci normalize TETAP) |
| `tests/run_tests.gd`, `tests/touch_probe.gd`, `tests/gui_probe_control.gd` | 157 unit + probe sentuh end-to-end 19 cek |

## 6. Alur verifikasi setiap ubah kode (wajibkan)
1. `gdparse <file>` cepat, tapi **bukan** bukti benar (sandbox sesi ini TIDAK punya
   gdparse — review manual teliti; hakim akhir = CI).
2. Push → tunggu `godot-tests` hijau (unit + smoke + probe). Baca `ci-logs` kalau merah.
3. `android-build` sukses → minta user tes artefak APK terbaru **dan sebutkan stempel
   yang harus muncul** (`<hash7>-b<run>` di layar loading). Bukti APK tanpa download:
   `git show origin/ci-logs:apk-log.txt` (stempel + sha256 + ukuran).
4. **Sandbox mem-block endpoint blob GitHub Actions** (artefak & log run tidak bisa
   diunduh dari sini — koneksi EOF ke Azure blob). Karena itu SEMUA bukti CI
   dirancang lewat branch `ci-logs` (github.com biasa bisa): `run-log.txt` /
   `probe-log.txt` / `boot-log.txt` (dari godot-tests) dan `apk-log.txt`
   (dari android-build). JANGAN buang pola ini.
5. Sandbox melarang download binary Godot langsung; jangan coba lagi — verifikasi via CI.

## 7. Bersih-bersih CATATAN usang — SUDAH SELESAI (2026-09-17)
- Dihapus: `MIGRASI-GODOT.md`, `OPTIMASI-KARAKTER.md`, `_verify/`, `site/`
  (referensi ke mereka di `DESAIN.md`, `README.md`, `core/quality_presets.gd`,
  `models/LISENSI.md` sudah disesuaikan; `tools/vrm_optim.py` disimpan).
- **JANGAN dihapus**: `DESAIN.md`, `README.md`, `models/LISENSI.md`, `tests/README.md`.

## 8. Resep cepat: "tolong lihat di HP saya lagi"
- Minta screenshot SAAT jari menyentuh zona stik (strip debug + bingkai zona +
  stempel harus terbaca SATU layar).
- BootLog tidak menulis ke stdout — panggil `print()` langsung bila perlu log mentahnya di CI.
- Tombol kanan HUD: DSH = dash (stamina), E = skill (cd 6s), Q = burst (cd 15s, energi 100).

_Selamat melanjutkan — stempel build adalah wasiat sesi ini: jangan pernah lagi menebak APK mana yang diuji user._
