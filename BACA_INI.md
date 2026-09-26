# BACA INI — Ronde-40: kubus pemain, percikan, monster 3D, HP, kamera RPG

## Alur repository yang diminta

- Remote `origin` sudah dicek sebelum perubahan: hanya `origin/main` dan
  `origin/content` yang tersedia. Tidak ada branch remote `arena/*-unity` lain
  yang punya pekerjaan belum di-merge, jadi tidak ada merge tambahan yang perlu
  dilakukan ke branch sesi ini.
- Branch sesi tetap `arena/01a0dca7-unity`; tidak merge ke `main`, tidak menutup
  PR.
- `.github/workflows/apk_release.yml` sekarang mendaftarkan
  `arena/01a0dca7-unity` di `on.push.branches`. Push perubahan konten dari
  branch ini akan menjalankan build APK + publish delta ke branch `content`.

## Perubahan ronde ini

### 1. Pemain bukan bola api lagi

- `project/packs/character_player/player.gd` kini merakit avatar **kubus 3D**
  dari `BoxMesh`, dengan visor bercahaya, stripe atas, dua kaki, aura hangat,
  dan ground glow.
- Fire bolt untuk tombol serang tetap dipertahankan; yang diganti adalah avatar
  karakter, sehingga jalur serang ronde sebelumnya tidak hilang.
- Saat bergerak, `GPUParticles3D` `TravelSparks` memunculkan percikan pendek
  dengan variasi kecepatan, gravitasi, turbulensi, warna HDR, dan jatuh alami.
  Partikel otomatis berhenti ketika pemain diam.

### 2. Gerak dan kamera third-person RPG

- Kecepatan penuh naik dari **7,5 m/s → 10,5 m/s**; akselerasi naik dari 5 →
  8,5 sehingga kontrol joystick lebih responsif.
- SpringArm third-person mengikuti pemain dengan smoothing lebih cepat. Jika
  pemain sedang bergerak dan tidak sedang mengusap area kamera, yaw kamera
  perlahan menghadap arah lari; usapan manual tetap diprioritaskan.
- Jarak kamera disetel ke 7,4 m agar kubus dan monster tetap mudah terlihat di
  layar HP.

### 3. Roster monster 3D bervariasi + animasi

- `world_terrain/monster.gd` dan `monster_system.gd` menambahkan 8 monster
  3D low-poly: dua slime, dua golem, dua bat, mushroom, dan crawler, masing-masing
  dengan warna, HP, kecepatan, dan damage berbeda.
- Semua mesh dirakit dari primitive Godot yang ringan; animasi procedural
  mencakup bob idle/jalan, langkah kaki, sayap bat, gerak mengejar, serangan
  jarak dekat, hurt flash, dan death shrink. Ini menjadi fallback bebas lisensi
  dan murah untuk Android, sekaligus menjaga roster bisa diganti GLB tanpa
  mengubah spawner.
- Sumber aset gratis yang sudah ditelusuri untuk ronde berikutnya:
  **Quaternius LowPoly Animated Monsters**, CC0, berisi 50 monster dengan
  animasi attack/death/run/walk: https://quaternius.itch.io/lowpoly-animated-monsters
  Binary 1,3 MB belum dibundel pada ronde ini agar tidak memasukkan arsip
  eksternal yang belum terverifikasi ke APK/PCK; roster procedural sekarang
  sudah playable dan siap menjadi fallback saat GLB CC0 diintegrasikan.
- Monster mengejar pemain di area datar dan mengurangi HP saat mendekat.

### 4. Bar darah

- Player mendapat `max_health`, `health`, `take_damage`, `heal`, dan signal
  `health_changed`.
- `project/packs/ui/hud.gd` menampilkan bar HP tetap di kiri atas, di bawah
  tombol pause, dengan label angka dan warna fill yang berubah sesuai rasio HP.
  Posisi menghormati safe-area Android.

## Verifikasi

- `python3 tools/analyze_checks.py /home/user/Unity` → `BERSIH ✓` (19 file GDScript).
- `git diff --check` → bersih.
- `bash tools/run_all_tests.sh` belum dapat dijalankan penuh karena binary
  Godot tidak tersedia di checkout/sandbox ini; CI workflow di atas tetap akan
  menjalankan import, gdparse, analyzer, probe serangan, dan build pack pada
  runner GitHub.
- Setelah push pertama, CI menemukan marker parse lama yang memang sudah ada
  di ekor `ui/hud.gd` (baris `font_color", ...` terlepas dari fungsi). Marker
  itu sudah dihapus di follow-up commit ronde ini; semua 18 file `.gd` sekarang
  lolos `gdparse` lokal + analyzer.

## Cara test di HP

1. Push branch `arena/01a0dca7-unity`.
2. Tunggu workflow `apk-release` selesai dan publish branch `content`.
3. Tutup lalu buka A-Sekai agar launcher membaca manifest baru. Delta yang
   berubah terutama `world_terrain`, `character_player`, dan `ui`.
4. Pastikan kubus terlihat, percikan muncul saat joystick digerakkan, kamera
   membuntuti arah lari, delapan monster terlihat, dan HP berkurang ketika
   monster mendekat.
