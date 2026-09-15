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

## Hasil akhir (build ke-17, run 34947616844, head c840201)

- Screenshot CI membuktikan: siang = padang rumput hijau cerah, senja =
  cahaya oranye hangat, malam = biru gelap dengan siluet rumput.
- Rumput: rumpun 4 bilah, instanced, densitas jatuh menurut jarak
  (padat di dekat pemain, menipis ke tepi radius 30 m) sehingga anggaran
  instance ~2 ribu tetap terbaca sebagai hamparan, bukan titik-titik.
- Spawn karakter DIPINDAH dari (0,0) — titik itu persimpangan dua jalur
  jalan dunia, jadi tanah di sekitarnya berwarna badan jalan (kesan
  pertama = padang pasir). Spawn baru (24, 30) di padang heartlands.
- Perbaikan bug yang ditemukan lewat screenshot CI:
  1. `Awake()` tidak dijamin jalan di edit mode → `EnsureInit()` idempoten.
  2. `Mesh.colors` yang tak diisi = array kosong (bukan null) → crash telan
     di try/catch, screenshot diam-diam kosong.
  3. `in` adalah keyword HLSL terlarang sebagai nama parameter shader →
     rumput magenta di semua platform.
  4. Pass ShadowCaster terrain: bug Unity terdokumentasi, Shadows.hlsl
     butuh Lighting.hlsl diinclude lebih dulu (LerpWhiteTo).
  5. CommandBuffer kamera diam-diam diabaikan URP → screenshot memakai
     mesh bake world-space (GrassField.BakeInto), play mode tetap
     DrawMeshInstanced.

## CI APK: kenapa enam build mati tanpa sebab, dan apa yang diubah (2026-09-16)

Rantai `v0.2.0-cel-fix` .. `fix9` gagal semua dengan satu-satunya pesan
`Build failed with exit code 1`. Dari anotasi check-run + sumber resmi game-ci
ditemukan empat sebab, dan keempatnya SENYAP:

1. **Harness verifikasinya sendiri rusak.** `EditorStubs.cs` mendefinisikan
   ulang namespace yang sudah ada di `Stubs.cs` (10x CS0101) sejak commit
   8517741, jadi `verify.yml` merah karena dirinya sendiri dan **tidak ada**
   build CI yang memeriksa kompilasi C# lagi.error kompilasi lolos bebas ke
   Unity, yang baru bicara setelah 6-12 menit dan satu seat lisensi termakan.
2. **Keystore tidak pernah dipakai.** `ANDROID_KEYSTORE_*` dilempar sebagai
   `env:`, padahal unity-builder@v6 memetakannya dari INPUT
   (cli `image-environment-factory.ts`). Akibatnya tiap build ditandatangani
   debug key acak -> Android menolak timpa-install -> "harus uninstall dulu".
   Sekarang lewat `androidKeystoreName/Pass` + `androidKeyaliasName/Pass`,
   dengan path absolut di container (`/github/workspace/...`) dan validasi dini
   (file kecil / byte pertama bukan 0x30 = LFS pointer -> gagal sebelum
   12 menit terbuang). `keystore/release.keystore` dibuat ulang sebagai PKCS12
   PBES2+AES-256 (yang lama PBE-SHA1-3DES, algoritma legacy yang JDK 17 curigai).
3. **`androidBuildAppBundle` bukan input v6** -> APK dipilih lewat
   `androidExportType: androidPackage`; versionCode lewat `androidVersionCode`.
4. **Log Unity tidak pernah ada di disk.** game-ci menjalankan
   `unity-editor -logfile /dev/stdout`, jadi tidak ada Editor.log; mencoba
   menimpanya lewat `customParameters` juga tidak mempan (yang pertama menang).
   Karena itu ditambahkan **`AureliaCILogTap.cs`**: `[InitializeOnLoad]`
   menempel ke `Application.logMessageReceivedThreaded` dan menulis seluruh
   konsol Unity ke `Logs/AureliaUnity.log` — file itu ada di dalam mount
   container, jadi sampai ke host. Langkah "Kumpulkan bukti kegagalan"
   memecah isinya menjadi anotasi `file(baris,kolom): error CSxxxx: ...`,
   dan jaring keduanya memindai `Library/Bee/tundra.log.json`.
   Dari jaring itulah akhirnya terbaca: `Csc ... RPG.Runtime.dll -> exitcode 1`.

Pelajaran prosesnya, dan itu yang ditambahkan ke repo:
`_verify/asmdef/check_asmdef_refs.py` (menolak `using` yang assembly-nya tidak
terdaftar di `.asmdef`) dan `_verify/asmdef/split_asmdefs.py` (menyusun ulang
project **per-assembly** seperti Unity, lalu `dotnet build` tiap assembly —
60 detik, tanpa lisensi). Harness satu-gundukan tidak akan pernah melihat
kesalahan lintas-assembly; koreksi kecil di `UnityStubCheck.csproj`
(`UNITY_EDITOR` tidak didefinisikan!) juga membuat blok `#if UNITY_EDITOR` di
skrip Runtime tadinya tidak ikut diperiksa sama sekali.
