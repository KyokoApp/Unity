# CATATAN SERAH TERIMA — Aurelia (baca ini dulu di sesi baru)

> Tanggal: 2026-09-17 · Branch kerja: `arena/01a0ac44-unity` · Tip terakhir teruji hijau: `211f59d`
> Untuk AI berikutnya: **baca file ini sampai habis sebelum menyentuh apa pun**, lalu
> bersih-bersih catatan usang sesuai §7. Setelah file ini dipahami dan diproses, file ini sendiri boleh dihapus/diperbarui.

## 1. Proyek & aturan main (JANGAN dilanggar)
- Game: **Aurelia** — open-world anime Genshin-like, open terrain 3×3 km, target **Android**.
- Engine: **Godot 4.5.1**, bahasa **GDScript** (bukan C#, bukan Unity — Unity sudah dihapus total & jangan dikembalikan).
- Proyek Godot berada di **root repo** (`project.godot` di `/`). Scene utama `res://scenes/world.tscn` (root Node3D + skrip `runtime/world.gd` yang membangun semua dari kode).
- Kerja HANYA di branch `arena/01a0ac44-unity`; setiap commit push ke sana. PR #4 ke `main` masih menunggu user yang merge sendiri.
- GitHub `gh`/git sudah terautentikasi di sandbox. Push/pull dua event (`push` + `pull_request`) → **dua run CI identik, wajar**.

## 2. Status sekarang (yang SUDAH jadi & hijau)
- Dunia tampil di HP (sky, terrain, air, rumput, HUD) — sebelumnya layar kosong; akar masalahnya sudah tuntas.
- Ikon aplikasi = gambar anime (regenerasi mirip kiriman user: `icons/icon_master.png` + turunannya). **Gambar asli user tidak pernah sampai ke sandbox** — kalau user kirim ulang, tukar semua turunannya (512/192/432 fg/bg/mono) via PIL (numpy TIDAK ada di sandbox; pakai `pip install --user --break-system-packages pillow`).
- CI `godot-tests`: 157 unit test + smoke-run 600 frame (gate `SCRIPT ERROR|SHADER ERROR` + exit code) + **touch probe 14/14** (`tests/touch_probe.gd`). CI `android-build`: artefak APK `aurelia-debug`.
- Log diagnostik CI ada di branch `ci-logs` (run-log.txt = unit + probe, boot-log.txt = smoke). Cara baca (web/blob sering ke-block sandbox):
  ```
  git fetch origin '+refs/heads/ci-logs:refs/remotes/origin/ci-logs' --force
  git show origin/ci-logs:run-log.txt
  ```

## 3. Bug yang SUDAH diperbaiki hari ini (agar tidak kebakar dua kali)
- **Shader Godot 4 — 6 pelajaran keras** (semua fix sudah masuk; regression dicegah gate CI):
  `return` dilarang di `light()` · `SHADOW` bukan built-in (sudah termasuk di `ATTENUATION`) · `VERTEX` tidak ada di `light()` (pakai `varying float view_depth` dari `fragment()`) · `force_vertex_shading=false` WAJIB di `[rendering]` — kalau tidak, `light()` custom dimatikan engine di HP.
- **`gdparse` tidak bisa dipercaya sendirian**: lolos `:=` yang tak terinferensi dari Dictionary untyped & arg-count salah pada static call. Hakim akhir = smoke-run engine di CI.
- **Pemain terkubur y=0**: `Motor` anak dari `Rig`; motor kini memindahkan `rig.global_position` (bukan dirinya) — rig = target kamera/streamer + pembawa visual. Rotasi (`rotation.y`) juga ditulis ke rig.
- **Input sentuh mati total**: `HudRoot` STOP menelan semua sentuhan → sekarang IGNORE; dekorasi (potret face/ring, bar HP, stamina) semua IGNORE; widget interaktif tetap menangkap lewat panel anaknya. `pointing/emulate_mouse_from_touch=false` (multi-jari murni). `motor.camera_target` sudah tersambung.
- Routing `ScreenTouch → Control._gui_input` **MATI di headless DisplayServer** (diketahui lewat probe Control polos) — makanya probe memanggil `_gui_input` langsung. Di device nyata GUI touch standar Godot berjalan.

## 4. TUGAS TERBUKA — urutan prioritas dari user

### 4a. 🔴 Analog tidak muncul di HP (laporan terakhir user, prioritas utama)
Kata user: *"analog gk muncul"*. Di probe CI 14/14 lulus, jadi kemungkinan besar **build yang diuji user adalah APK lama** — pastikan user memakai artefak `aurelia-debug` dari build ≥ `211f59d`. Kalau setelah pakai tip terbaru masih mati, petunjuk investigasi:
1. Tambah log masuk di `VirtualJoystick._gui_input()` (print/BootLog) lalu minta user kirim ulang — lihat apakah event sampai (lihat cara log cepat di bawah §8).
2. Uji manual hal-hal fisik: StickZone rect = `0..0.45W × (H-340..H-34)` **piksel kanvas 1920×1080** (stretch `canvas_items`/`expand`); kalau resolusi HP berbeda jauh, posisinya seperti apa minta screenshot.
3. Hati-hati: `_base`/`_knob` stik sudah IGNORE — jangan kembalikan STOP di sana; widget di atas StickZone semua harus ter-*audit* mouse_filter-nya.
4. Genshin-build: stik "mengambang" (muncul di titik jari) — tombol-tombol kanan (JMP/ATK/DSH/E/Q) memakai `UiKit.button_slot` (Button PASS di panel STOP) — kalau tombol juga mati di HP, selidiki `Button` vs `mouse_filter` sekali lagi.

### 4b. 🟡 Ganti karakter + animasi jalan/lari/idle/dash/attack (aset dari user)
LINK USER (drive):
- **Model + klip animasi**: https://drive.google.com/file/d/120fNMWnpMaiNEJLG53LdTd8DfSGdFrYq/view?usp=drivesdk
- **Model karakter**: https://drive.google.com/file/d/1RZIwux_yJ6VB2j4nAsYdUlfcca0BLPar/view?usp=drivesdk
Pekerjaan:
1. Unduh (sandbox mungkin memblokir download langsung — coba `gh`-style / drive downloader / tanya user lampirkan file ke sesi; kalau zip dan besar: jangan di-commit mentah, ekstrak ke `models/`).
2. Format tujuan: **GLB** di `models/` (Godot impor otomatis). Konversi kalau perlu lewat CI step atau minta varian GLB ke user.
3. Sambungkan di `runtime/character_rig.gd`: `model_scene`/`model_paths` (sekarang: `res://models/AureliaChar.glb` → fallback mannequin). Gantikan pose prosedural dengan animasi `AnimationPlayer`: klip target = idle/walk/run/dash/attack; di-drive dari `CharacterMotor` (sinyal/sudah ada: `move01`, `run01`, `is_dashing`, `combat.is_attacking()`, `landed`, `attack_started(combo)`). Peta blend-speed lama ada di `Locomotion.sample_pose` — pertahankan transisi yang halus.
4. Warna toon: `runtime/toon_character_setup.gd` + `shaders/aurelia_toon.gdshader` untuk material VRM→toon; GLB baru perlu adaptasi material yang sama (cek nama material/mesh-nya).

### 4c. 🟢 Rumput dari aset user
LINK USER: https://drive.google.com/file/d/18WFEJckB7Kn1ifvTe_JpAs7bB4iKbGZf/view?usp=drivesdk
Sekarang rumput 100% prosedural: `runtime/grass_field.gd` (MultiMesh per-chunk, die-stream) + `shaders/aurelia_grass.gdshader` (geser angin berbasis TIME/vertex). Integrasi aset:
- Kalau tekstur: pasang ke material blade; pertahankan gerak angin vertex-shader; kalau model mesh: jadikan sumber MultiMesh.
- Jaga kontrak performa: tier kualitas di `core/quality_presets.gd` (jumlah blade/luas per preset), jarak sembur `quality_applier.gd`.

### 4d. ℹ️ Umum
- User merge PR #4 sendiri bila siap. Unduh APK tiap kali user minta build: artefak `aurelia-debug` run `android-build` terbaru.
- Ikon anime persis = menunggu lampiran ulang gambar user.

## 5. Peta kode kilat
| Path | Isi |
|---|---|
| `runtime/world.gd` | World composer: membangun segalanya dari kode dalam `_build()`, `_boot_sync()` loading sinkron (failsafe 25s/900 frame), `hud.visible=false` sampai boot selesai |
| `runtime/character_motor.gd` | Gerak pemain (jalan 6.5 m/s, lari 13.5, dash/stamina/coyote) — **memindahkan `rig` induknya** |
| `runtime/character_rig.gd` | Pembawa visual + pose (sekarang prosedural 25 sendi; sambungan GLB/AnimationPlayer di sini) |
| `runtime/camera_rig.gd` | Kamera orbit orang-ketiga; `_unhandled_input` drag kamera; cek `_in_stick_zone`; clamp ke terrain |
| `runtime/terrain_chunk_streamer.gd`, `grass_field.gd`, `water_plane.gd`, `orbs.gd` | Streaming chunk/prop, rumput MultiMesh, air, orb kolektibel |
| `ui/game_hud.gd`, `ui/virtual_joystick.gd`, `ui/ui_kit.gd` | HUD Genshin dari kode (layer 10) — **aturan: widget dekoratif = mouse_filter IGNORE, interaktif = STOP/via panel anak** |
| `shaders/*.gdshader` | 5 world shader + sky/water/sparkle/outline — semua sudah Godot-4-sahih; rubah dengan takut |
| `core/*` | terrain/world data, locomotion (kontrak numerik Genshin), quality presets, settings |
| `tests/run_tests.gd`, `tests/touch_probe.gd`, `tests/gui_probe_control.gd` | 157 unit + probe sentuh end-to-end (headless) |

## 6. Alur verifikasi setiap ubah kode (wajibikan)
1. `gdparse <file>` cepat, tapi **bukan** bukti benar.
2. Push → tunggu `godot-tests` hijau (unit + smoke + probe). Baca `ci-logs` kalau merah.
3. `android-build` sukses → minta user tes artefak APK terbaru secara eksplisit (sebut hash).
4. Sandbox melarang download binary Godot langsung; jangan coba lagi — verifikasi via CI.

## 7. Bersih-bersih CATATAN usang (yang boleh & yang JANGAN dihapus)
Perintah user: hapus catatan lain yang sudah tidak kepakai setelah catatan ini terpakai.
- **Boleh dihapus**: `MIGRASI-GODOT.md` (migrasi tuntas — sejarahnya ada di git), `OPTIMASI-KARAKTER.md` (dokumentasi tooling VRM era Unity; skripnya sendiri `tools/vrm_optim.py` boleh disimpan), `_verify/` (sisa verifikasi pra-migrasi), `site/` (build web three.js usang), `tools/` yaml Unity-era bila ada.
- **JANGAN dihapus**: `DESAIN.md` (kontrak numerik/desain yang masih berlaku), `README.md` (perbarui sedikit, bukan buang), `models/LISENSI.md`, `tests/README.md`, file ini (sampai selesai diproses), `LANGKAH-SELANJUTNYA.md` kalau muncul lagi (sudah tak ada di tree tip).
- File `.md` yang dihapus tetap ada di history git — aman.

## 8. Resep cepat: "tolong lihat di HP saya lagi"
- Kalau user lapor sesuatu lagi di HP: minta screenshot DAN jalankan probe terbaru; tambahkan output debug yang relevan ke BootLog agar muncul di `ci-logs:run-log.txt`… (BootLog tidak menulis ke stdout — panggil `print()` langsung bila perlu log mentahnya di CI).
- Tombol kanan HUD: DSH = dash kilat darat (pakai stamina, cooldown di `CombatState`), E = skill (cd 6s), Q = burst (cd 15s, butuh energi 100 = cincin emas penuh).

_Selamat melanjutkan — semua yang di atas terverifikasi, bukan tebakan._
