# CARA UPDATE GAME SENDIRI (panduan pemilik)

Konsep besarnya: **APK hanya peluncur** (jangan diubah-ubah). Semua konten
(kode, dunia, karakter, UI, audio) hidup di *pack* dan diantar oleh pipeline CI
ke cabang `content`. Handphone-mu akan mengunduh hanya pack yang BERUBAH saat
aplikasi dibuka. Jadi "update" = ubah file pack → picu pipeline → buka aplikasi.

---

## 1. PETA FILE — ubah apa untuk efek apa

Semua di dalam `project/`. Yang paling sering kamu sentuh:

| Mau mengubah… | File | Catatan |
|---|---|---|
| Ganti mesh/library animasi karakter | `project/packs/character_player/player.gd` → tabel `SKINS` (path GLB per skin) | Tambah nama anim = tulis nama persis di GLB, prefiks namespace (`ual1/…`, `ual2/…`) |
| Resolusi nama & alias animasi (jalan/serang/dst → nama klip asli) | `project/packs/character_player/anim_controller.gd` (`ALIASES`) | Loop vs sekali-jalan = daftar `LOOP_STATES` (whitelist eksplisit, lihat Ronde-36) |
| Dunia (load, sky, lighting, collision, spawn) | `project/packs/world_terrain/world.gd` | File world = `gravity_falls.glb` di folder yang sama |
| Ganti dunia total | unggah GLB baru ke `project/packs/world_terrain/` + set `STATIC_WORLD_PATH` | Catat kreditnya di `CREDITS.md` (harus CC0/legal) |
| HUD/tombol aksi | `project/packs/ui/hud.gd` | Geometri lingkaran dsb di `_build()` |
| Menu pause/pengaturan | `project/packs/ui/pause_menu.gd` | |
| Layar loading | `project/packs/ui/loading_screen.gd` | |
| Pengaturan bawaan (default) | `project/packs/core_scripts/game_settings.gd` | Contoh: skin default `char_skin` |
| Logika aplikasi game (boot, pause, HUD) | `project/packs/core_scripts/game_root.gd` | Hati-hati! Salah = macet boot |
| Peluncur + logika unduh | `project/launcher/*` | HINDER ubah; itu inti update |
| Warna/material/toon/outline | `project/packs/shaders_materials/*` | Outline = inverted-hull `make_outline()` |
| Suara | `project/packs/audio_sfx/*` + `audio_music/*` | |

Perubahan apa pun **cukup lewat web GitHub** (ikon pensil/"Add file via upload")
— persis seperti yang kamu lakukan minggu ini. Tidak perlu PC + Git.

## 2. SETELAH MENGUBAH: picu pipeline (wajib, sekali klik)

Konten tidak otomatis terbit hanya karena file berubah — pipeline `apk-release`
hanya jalan bila (dipilih salah satu):

### Cara PALING MUDAH (tanpa commit kosong):
1. Buka repo → tab **Actions**.
2. Pilih workflow **"apk-release"** (sidebar kiri).
3. Klik **"Run workflow"** → biarkan branch `arena/01a0ba2f-unity` → tombol hijau **"Run workflow"**.
4. Tunggu ~2 menit. Selesai = konten terbit.

### Cara alternatif (baris "kick"):
Edit `/.github/workflows/apk_release.yml` → scroll ke baris paling bawah →
tambahkan: `# rerun-kick N (alasan pendek)` (N = nomor berikutnya) → **Commit** →
otomatis jalan. (Kenapa? Filter `paths` di workflow; ini konvensinya kita.)

## 3. Pipeline melakukan apa (otomatis) — kamu TIDAK perlu peduli

1. Kedalaman lint (`gdparse` + `tools/analyze_checks.py`) → **build diblokir** kalau ada parse/typo nyata. Ini penyelamat bug layar-birunya kemarin.
2. Import proyek Godot 4.5.2.
3. Hash tiap pack → pack yang **berubah** mendapat versi +1 otomatis; manifest game tidak naik; `server/manifest.json` + `versions.json` diregenerasi (JANGAN diedit tangan).
4. Publlikasi ke branch `content` — ini yang dibaca launcher di HP-mu.
5. Ekspor ulang APK peluncur & upload ke Release `apk-20260920-2302` (untuk calon pemain baru).

## 4. Aturan "JANGAN" (agar tak retak)

- ❌ Jangan edit file di `server/` — regenerasi CI, editmu percuma.
- ❌ Jangan membuat preset AIO (konten di dalam APK) — dilanggar satu kali, aplikasi langsung melanggar aturan №1.
- ❌ Jangan hapus/rename preset **"Android Launcher"** atau `res://launcher/*`.
- ❌ Jangan commit file konflik (`<<<<<<<`, `=======`, `>>>>>>>`) — ada penjaga CI.
- ❌ Jangan ganti versi Godot (pent: 4.5.2) tanpa mengubah `GVER` + templates.
- ⚠ Hati-hati ubah `core_scripts/game_root.gd` & `launcher/*` — salah satu jejak = tak bisa boot; kalau yakin, fotonya panel merah akan muncul dan menolong.

## 5. Resep cepat yang sering ditanya

- **Tambah animasi ke mannequin**: edit `SKINS["mannequin"].states` di `player.gd` → tambahkan nama persis dari GLB (Bandingkan daftar `A_TPose…Walk_Loop` — nama LEBIH BAIK exact atau resolver substring akan mencoba cocokkan).
- **Ubah jam/cahaya default sore**: `world.gd` `time_of_day` + preset warna di `_apply_daylight`.
- **Skin default baru**: `game_settings.gd` `char_skin` + entri SKINS di `player.gd` + opsi di `pause_menu.gd`.
- **Ganti ikon judul/logo**: `launcher/launcher.gd` (teks "🌴 A-SEKAI").

## 6. Kalau update-mu bikin aneh di HP

1. Baca teks kuning kecil kiri-bawah saat boot (ada tahapnya).
2. Kalau layar merah → itu panel FATAL — foto saja, ada tahap terakhir + tail log.
3. Log boot ada di `user://boot_log.txt` (tahap + perangkat tiap sesi).
4. Kirim fotonya — aku menambahkan temuan sebagai entri **docs/BUGFIXES.md**.

Arsip lengkap keputusan ada di `DECISIONS.md` (cari "Ronde-N"), dan gaya/visi
bisa dilihat di `PLAN.md` + `README.md`.

*Ditulis ronde-22 untuk sang pemilik game agar full-kendali tanpa agent.*
