# Tahap 4 — Dunia hidup: rumput, siang/malam, dan mata CI

Selesai 2026-09-15 (build CI ke-8). Tujuan tahap ini: dunia tidak lagi
terlihat seperti tempat uji — ada hamparan rumput, cuaca berubah sendiri,
dan kita akhirnya bisa MELIHAT game-nya tanpa punya PC.

## 1. Rumput (`GrassField.cs` + `AureliaGrass.shader`)

- Jumlah rumpun datang dari sistem kualitas yang sudah ada di Core
  (`GfxResolver.GrassCount`, angka yang sama dengan game three.js aslinya:
  9.000 pada tingkat tertinggi untuk perangkat sentuh, 2.250 pada
  `balanced` bawaan). Preset rendah = rumput mati.
- Satu rumpun = 3 bilah meruncing (18 vertex, 12 segitiga), digambar lewat
  `Graphics.DrawMeshInstanced` — maksimal 1023 instance per draw call,
  jadi ribuan rumpun = beberapa draw call, bukan satu mesh raksasa yang
  dibangun ulang tiap langkah.
- Penempatan deterministik per sel 8 m (hash integer), jadi rumput tidak
  "berkedip" saat sel dibangun ulang, dan sel yang tidak berubah dipakai
  ulang dari cache.
- Gaya stylized ala Genshin, sengaja TANPA tekstur: siluet bilah sudah
  meruncing di geometri, gradasi pangkal->ujung dan variasi rona per
  rumpun dikerjakan di shader. Opaque (bukan alpha-test) = tanpa sortir
  dan tanpa overdraw di HP menengah.
- Angin di vertex shader: pangkal diam, ujung bergoyang dua gelombang.
  Rumpun jauh tidak di-fade alpha tapi ditenggelamkan ke pangkalnya,
  lalu kabut menyamarkan sisanya.
- Tidak ada di air (y < WaterLevel + 0,25 m) dan tidak di lereng curam.
- Tidak melempar bayangan: bayangan rumput 3 cm tidak terbaca di layar
  6 inci, tapi biaya shadow pass-nya nyata.

## 2. Siklus siang/malam (`DayNightCycle.cs`)

- DEFAULT REALTIME: jam berjalan terus, satu hari game = 15 menit dunia
  nyata (field `DayMinutes`), mulai jam 08.00.
- Matahari, ambient, warna kabut, dan warna langit (clear color kamera)
  diinterpolasi dari tabel keyframe enam suasana: tengah malam, subuh,
  pagi keemasan, siang netral, sore, senja jingga.
- Tombol suasana Pagi / Siang / Sore / Malam / Realtime di kiri-bawah
  layar (IMGUI, sistem yang sama dengan PerfHud dan stik) — arena pribadi,
  jadi cuaca adalah mainan.
- Langit sungguhan (gradien, awan, matahari terlihat) tetap pekerjaan
  Tahap 7; sampai saat itu langit datar sewarna kabut membuat cakrawala
  menyatu.

## 3. Screenshot in-game dari CI (`SceneShots.cs`)

- Diambil di `OnPreprocessBuild`, tepat sebelum `BuildPlayer`: kamera
  dirender ke RenderTexture 1280x720, dibaca pikselnya, disimpan PNG.
  Tiga suasana: siang, senja, malam.
- Terrain dipaksa streaming sinkron (`TerrainChunkStreamer.EditorStreamNow`)
  dan rumput dipaksa populate (`GrassField.PopulateNow` + `DrawNow`) karena
  di batchmode tidak ada loop Update.
- Diunggah sebagai artifact **screenshots** pada setiap run — buka dari
  halaman run lewat browser HP (Actions -> run -> Artifacts).
- DIBUNGKUS try/catch yang menelan semua exception: screenshot adalah mata
  kita, bukan alasan build boleh gagal. Kalau GL runner bermasalah, build
  APK tetap jalan dan log hanya mendapat satu baris PERINGATAN.

## PerfHud

Dua baris baru: `rumput: N rumpun, M sel` dan `waktu H.H (suasana)`.

## Berikutnya

- **Tahap 4b**: properti scatter Kenney (batu, pohon, reruntuhan, CC0)
  memakai slot `detail`/`PropsNear`/`PropsFar` yang sudah ada di
  GfxResolver.
- **Tahap 5**: HUD setelan (preset kualitas, sensitivitas, skala tombol)
  yang membaca/menulis `SettingsStore`.
- **Tahap 7**: langit sungguhan, bayangan berkualitas, tier perangkat
  berdasarkan angka fps yang terkumpul dari PerfHud.
