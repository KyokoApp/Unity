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

### EKSEKUSI: satu baris itu (2026-09-16)

`GfxApplier.cs(83)` ditulis ulang menjadi `UnityEngine.ShadowQuality.All / .Disable`,
dan stubnya diberi decoy `UnityEngine.Rendering.Universal.ShadowQuality` supaya
CS0104 kelas ini SELALU terlihat di `verify.yml` (60 detik) dan tidak pernah lagi
butuh 7 build Unity untuk ketemu. Build `v0.2.0-cel-fix11` = verifikasi pertama
dengan rantai bukti lengkap: kran log Unity -> `Logs/AureliaUnity.log` -> anotasi.

## 2026-09-16 — HIJAU: APK release terverifikasi bertanda tangan CN=yuki (v0.2.0-cel-fix17)

Rantai penyebab, dari gejala "harus uninstall dulu" sampai build yang lulus:

1. **fix7–fix10**: .yml$ rusak dirinya sendiri (stub dobel) -> tidak ada satu pun
   pemeriksaan kompilasi C# yang jalan. .cs(83)$ CS0104 ($
   ambigu) dan $ CS0122 ($
   tidak bisa diakses bertipe di URP 17) lolos ke build Unity dan membakarnya 20 menit
   tiap percobaan. Kedua-duanya sekarang diperbaiki, dan harness dikompilasi
   per-.asmdef supaya kesalahan lintas-assembly tidak bisa sembunyi lagi.
2. **fix11–fix12**: : latest$ mati di API GitHub (403) -> dipin .1.65$.
3. **fix13–fix14**: $: Can not sign the application$. Penyebab:
   $ diberikan ABSOLUT; Unity menaruh current directory di
   depannya -> /github/workspace/github/workspace/keystore/... -> "keystore file not
   found". Bukti bahwa keystore sehat: keytool baca OK + jarsigner menandatangani OK
   di JDK runner yang sama.
4. **fix15**: path direlatifkan -> error berubah menjadi "please provide
   passwords!". Jadi isinya benar, jalurnya yang bocor: password dikirim sebagai
   argumen baris perintah ke skrip build game-ci dan hilang diam-diam.
5. **fix16**: CI menulis /ci-signing.txt$ (relatif, tidak di-commit) dan
   .ApplyAndroidSigningFromCi()$ memasang
   PlayerSettings.Android.{useCustomKeystore,keystoreName,keystorePass,keyaliasName,
   keyaliasPass} sendiri di OnPreprocessBuild (callbackOrder -100), BEBERAPA DETIK
   sebelum Unity menandatangani, lalu membaca balik nilainya sebagai bukti. Build
   Android LULUS untuk pertama kalinya. Yang gagal tinggal verifier-ku sendiri.
6. **fix17**: verifier sebelumnya menghakimi dari META-INF/*.RSA — salah, karena
   skema v2/v3 tidak menulis META-INF; dan  -c 4096$ tidak pernah mencapai APK
   Signing Block (central directory APK ini ratusan KB). Diganti  verify
   --print-certs$ (build-tools disisakan dari pembersihan disk) + pemindai struktur
   APK yang dites terhadap APK sintetik; kalau unsigned, CI menandatanganinya sendiri.
   Bug lain yang ditebas di langkah yang sama:  | sed$ di dalam function
   mengembalikan kode $ (0), jadi APK unsigned akan dinyatakan lolos.

Hasil (run 35048608918, semua 20 langkah success):

- Release: .2.0-cel-fix17$ -> -0.2.0-cel-fix17-arm64.apk$ (50.641.822 byte;
  ambang "scene tidak kosong" 30 MB, karakter VRM ikut).
- Bukti penandatangan, dari apksigner (bukan dugaan): =yuki$ dan
  =ADA$ (APK Signing Block hadir, jadi skema v2/v3 aktif) -> install
  menimpa build berikut tanpa uninstall, selama kunci tetap dan versionCode naik
  (versionCode = run_number + 1000).
- Unity TIDAK perlu ditambal CI untuk signing: jalur Unity sendiri yang menandatangani.
- Kosmetik yang ditinggalkan: =?$ di anotasi (walker pair tidak memetakan ID
  milik Unity; $ sudah menjawab resmi), dan dua baris
  "Addressable Asset Settings does not exist" (paket di-referensi .Runtime.asmdef$
  tapi tidak dipakai kode mana pun -> bisa dilepas untuk memangkas waktu impor).

Kebocoran lisensi Personal: tiap run diakhiri "Failed to return the Personal license
seat after 4 attempts". -ci/unity-return-license@v2$ TIDAK menolong (entrypoint-nya
hanya jalan kalau $ ada; Personal tidak punya serial). Kalau nanti kena
"no available seats": lepas aktivasi di https://id.unity.com -> My Account -> My Seats
-> "Remove selected activations" (bukan halaman Security; di situ tidak ada apa-apa).
