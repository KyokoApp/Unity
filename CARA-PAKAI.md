# Aurelia — project Unity

Port dari game three.js `KyokoApp/rpg` ke Unity. **Target: Android (APK).**

---

## ⚠️ Baca ini dulu: apa yang ADA dan apa yang BELUM

Project ini **bukan game yang bisa langsung dimainkan**. Yang sudah jadi baru
**tahap 0–3**: scaffold + logika inti teruji + karakter yang bisa berjalan +
dunia yang sudah terlihat (bukit, jalan, danau).

| Sudah ada | Belum ada |
|---|---|
| `RPG.Core` — world data, quality preset, lokomosi, sebar properti, orb | Aset Kenney (pohon/batu/jamur) |
| `RPG.Core` — permukaan & mesh terrain (pure, teruji) | Orb, HUD, audio, postfx |
| `RPG.Runtime` — character rig, motor, kamera orbit, stik sentuh, settings store | Kolisi terrain (motor masih menempel lewat `TerrainH`) |
| `RPG.Runtime` — chunk streamer + bidang air | LOD per jarak (sekarang satu resolusi seragam) |
| Shader URP terrain & air | Attack/combo (rumusnya sudah ada, pemicunya belum) |
| `RPG.Editor` — pembangun scene + kalibrasi pose + setelan impor VRM | Migrasi penuh ke Input System baru |
| 46 tes NUnit, semuanya hijau | — |
| Pipeline build APK (GitHub Actions), konfigurasi URP + paket | — |

Scene **tidak ikut di repo** — dibangun lewat menu
`Tools > Aurelia > 2` (karakter saja) atau `Tools > Aurelia > 4` (dunia
terlihat). Alasannya: scene yang memuat instance prefab VRM akan menyeret model
berlisensi `Redistribution_Prohibited` itu ke dalam git. Lihat
`Assets/Art/Characters/LISENSI.md`.

Dokumen per tahap: `DESAIN.md` (rencana) · `OPTIMASI-KARAKTER.md` (model) ·
`TAHAP-2.md` (controller & kamera) · `TAHAP-3.md` (terrain & air) ·
`TANPA-PC.md` (**build APK tanpa komputer**).

Yang sudah diverifikasi di luar Unity (Unity tidak ada di tempat project ini dibuat):

```
dotnet build atas file C# yang dikirim   0 error, 0 warning
paritas vs modul JS asli                 1.779 baris / 2.650 nilai, SETARA
                                         selisih maksimum 9,09e-13
NUnit                                    46/46 lulus
_verify/unitystub                        skrip Unity terkompilasi melawan stub,
                                         0 error 0 warning (baca README-nya:
                                         ini BUKAN bukti API Unity-nya cocok)
_verify/terrain                          survei 90.601 sampel dunia 3 km;
                                         retakan antar chunk = 0 selisih bit;
                                         winding salah = 0 dari 512 segitiga
_verify/shaders                          Properties vs cbuffer SRP Batcher cocok
model karakter                           44,35 MB -> 15,20 MB, 13 cek lossless lolos
```

---

> **Tidak punya komputer?** Baca `TANPA-PC.md` dulu — dokumen di bawah ini
> mengasumsikan ada Unity Editor yang bisa dibuka. Jalur tanpa-PC lewat
> GitHub Actions itu mungkin, tapi langkahnya beda.

## Dari nol sampai main di HP

**Jawaban singkat: belum bisa langsung dimainkan.** Tidak ada APK yang tinggal
diunduh, dan tidak ada scene yang tinggal dibuka. Tiga hal hanya bisa terjadi
di komputermu, bukan di tempat project ini dibuat:

1. **Unity harus terpasang** — tidak ada Unity di sandbox ini, jadi tidak ada
   yang bisa saya build untukmu.
2. **Scene harus dibangun lewat menu** — sengaja tidak ikut di repo, karena
   scene yang memuat prefab VRM akan menyeret model berlisensi
   `Redistribution_Prohibited` ke dalam git.
3. **APK harus di-build** — butuh Android SDK/NDK + IL2CPP.

Perkiraan waktu jujur:

| Langkah | Waktu |
|---|---|
| Unduh Unity Hub + Unity `6000.0.32f1` + modul Android | 1–2 jam (±10–15 GB, tergantung koneksi) |
| Buka project pertama kali (resolve paket + impor aset) | 10–30 menit |
| Menu 1 → menu 4 → tekan Play → **dunia terlihat** | 2 menit |
| Build APK pertama | 10–25 menit |

Jadi **sore ini juga bisa**, asal komputernya punya ruang ~20 GB dan koneksi
yang cukup. Yang lama cuma unduhan; langkah mainnya sendiri 4 klik.

### A. Melihat dunia di komputer

```
1. Unity Hub -> Add -> Add project from disk -> pilih folder ini
2. Buka (tunggu sampai selesai, jangan dibatalkan)
3. Tools > Aurelia > 1. Buat URP Asset
4. Tools > Aurelia > 4. Bangun scene Tahap 3 (dunia terlihat)
5. Tekan Play
```

Karakter **tidak wajib** untuk langkah ini. Kalau `AureliaChar.vrm` atau UniVRM
belum ada, pembangun scene memasang kapsul placeholder dan kamu tetap bisa
berjalan melihat bukit, jalan, dan danau — itu cara tercepat memastikan
terrain-nya benar sebelum mengurus karakter.

### B. APK ke HP (jalur lokal — ini yang saya sarankan untuk APK pertama)

```
File > Build Profiles (atau Build Settings)
  -> platform Android -> Switch Platform     (perlu modul Android)
Project Settings > Player > Android
  -> Scripting Backend      : IL2CPP
  -> Target Architectures   : ARM64
  -> Minimum API Level      : 24
  -> Company / Product Name : isi (jadi nama aplikasi di HP)
  -> Package Name           : mis. com.kyoko.aurelia
Project Settings > Player > Other Settings
  -> Active Input Handling  : Input Manager (Old)   <- WAJIB, lihat catatan di bawah
File > Build And Run  (atau Build -> dapat file .apk)
```

Pindahkan `.apk` ke HP (kabel, Drive, atau `adb install nama.apk`), izinkan
"pasang dari sumber tidak dikenal", pasang.

**Kenapa jalur lokal, bukan GitHub Actions:** `.github/workflows/android-release.yml`
sudah ada, tapi butuh 3 secret (`UNITY_LICENSE`, `UNITY_EMAIL`, `UNITY_PASSWORD`)
yang mengharuskan kamu mengaktivasi lisensi Unity dulu dan mengunggah isi file
`.ulf` — dan alur itu **belum pernah dijalankan sama sekali**. Untuk APK pertama,
build lokal jauh lebih mudah diperbaiki kalau ada yang salah, karena errornya
kelihatan langsung.

### C. Yang akan kamu lihat di HP, dan cara membacanya

PerfHud menyala otomatis di pojok kiri-atas. Baca tiga angka ini:

| Angka | Sehat | Kalau jelek |
|---|---|---|
| `frame maks ms` | < 33 ms | ada sentakan — catat kapan terjadinya |
| `GC gen0/s` | 0 | ada alokasi per frame yang harus dicari |
| `upload ms` | < 1 ms | ini yang memotong budget frame, bukan `build ms` |

Sembunyikan HUD: ketuk sudut kanan-atas 3 kali.

**Catatan penting soal target fps.** Belum ada yang bisa menjanjikan 50 fps,
termasuk saya — yang bisa adalah mengukur, lalu memperbaiki apa yang paling
mahal. Dan berdasarkan angka yang sudah ada, risiko terbesar project ini
**bukan terrain** (51.200 segitiga, 25 draw call — itu kecil), melainkan
**karakter**: 124.988 verteks, 43 material yang tidak bisa digabung tanpa
mengubah tampilan, plus 92 spring bone yang disimulasikan di CPU tiap frame.
Kalau nanti angkanya kurang, mulailah dari sana. Rinciannya di `TAHAP-3.md`
bagian "Performa".

---

## Syarat

| | |
|---|---|
| **Unity** | `6000.0.32f1` — dipatok di `ProjectSettings/ProjectVersion.txt` |
| **Unity Hub** | untuk memasang versi itu |
| **Module** | Android Build Support (+ OpenJDK, Android SDK & NDK, kalau mau APK) |
| **Git** | **wajib** — UniVRM diambil lewat git URL di `manifest.json` |
| **Git LFS** | disarankan, untuk `.glb`/`.vrm` nanti (`.gitattributes` sudah siap) |
| **Ruang disk** | ~20 GB bebas (Unity + modul Android + Library project) |

Kalau Unity Hub menawar versi lain, **tolak** dan pasang `6000.0.32f1` dulu.
Versi beda bisa menaikkan versi paket secara diam-diam.

---

## Cara membuka

1. Unity Hub → **Add** → **Add project from disk** → pilih folder ini
2. Pastikan versinya `6000.0.32f1`
3. Buka. **Tunggu** — pertama kali Unity akan:
   - mengunduh & resolve paket dari `Packages/manifest.json` (URP, Input System,
     glTFast, Addressables) — bisa beberapa menit
   - membuat ulang file `ProjectSettings/` yang belum ada (wajar, folder itu
     sengaja hanya berisi `ProjectVersion.txt`)
   - mengimpor `Assets/` dan membuat `Library/` (juga wajar, dan sudah di-`.gitignore`)

Kalau ada dialog *"Enter Safe Mode?"* karena error kompilasi, **jangan** masuk
Safe Mode — lihat dulu errornya di Console.

---

## Menjalankan tes

**Window → General → Test Runner → tab EditMode → Run All**

Harus **46/46 hijau**. Kalau ada yang merah, artinya port C# menyimpang dari
versi three.js — jangan perbarui angkanya, cari tahu kenapa berubah.
Angka golden di `CoreParityTests.cs` diambil dari menjalankan modul JS asli,
bukan ditulis tangan; angka di `TerrainMeshTests.cs` diambil dari menjalankan
`_verify/terrain/` terhadap `WorldData.cs` yang sama.

---

## Yang harus disetel manual (belum bisa diotomatiskan dari luar Unity)

1. **UniVRM** — **sudah otomatis** lewat `Packages/manifest.json` (git URL,
   versi dipatok `v0.131.2`). Syaratnya **Git harus terpasang** di komputer;
   tanpa Git, Unity tidak bisa mengambil paket dari URL dan karakter tidak
   akan muncul.
   Yang tetap manual: taruh `AureliaChar.vrm` di `Assets/Art/Characters/`.
   File `.vrm`-nya **tidak ada di repo** (di-`.gitignore`); lihat
   `Assets/Art/Characters/LISENSI.md`.

   *Kalau tidak mau pakai Git:* hapus dua baris `com.vrmc.*` dari
   `manifest.json`, lalu unduh `UniVRM-0.131.2_*.unitypackage` dari
   [github.com/vrm-c/UniVRM/releases](https://github.com/vrm-c/UniVRM/releases)
   dan seret ke Unity. Ambil yang **VRM 0.x**, bukan VRM 1.0 — file karakter
   kita `specVersion: 0.0`.
2. **URP Asset** — otomatis lewat *Tools → Aurelia → 1. Buat URP Asset*.
   Kalau menu itu error, buat manual lewat *Assets → Create → Rendering → URP
   Asset (with Universal Renderer)*, lalu pasang di:
   - *Project Settings → Graphics → Scriptable Render Pipeline Settings*
   - *Project Settings → Quality* (tiap tier)
3. **Active Input Handling** — *Project Settings → Player → Other Settings →
   Configuration* → set **Input Manager (Old)**. Nilainya sudah di-commit di
   `ProjectSettings/ProjectSettings.asset` (`activeInputHandler: 0`), jadi
   biasanya tidak perlu disentuh sama sekali.
   - **Jangan** *Input System Package (New)*: `CharacterMotor`, `TouchJoystick`,
     dan `CameraRig` memakai kelas `Input` lama dan akan melempar
     `InvalidOperationException` saat runtime.
   - **Jangan** *Both*: tidak ada satu pun skrip yang memakai API Input System
     baru, dan Unity sendiri menolaknya di Android (*"Active Input Handling is
     set to Both, this is unsupported on Android"*).
   - **Jangan** mengubah setelan ini lewat skrip *saat build sedang berjalan*.
     `OnPreprocessBuild` jalan setelah assembly Editor dikompilasi, jadi
     assembly Player akan dapat define `ENABLE_INPUT_SYSTEM` sementara Editor
     tidak → build mati dengan *"script class layout is incompatible between
     the editor and the player"*. Detailnya ada di komentar
     `Assets/_Project/Scripts/Editor/AureliaBuildPreprocessor.cs`.
4. **Suasana & rumput (Tahap 4)** — tombol Pagi/Siang/Sore/Malam/Realtime
   ada di kiri-bawah layar; secara bawaan jam berjalan sendiri (15 menit
   dunia nyata per hari game). Rumput ikut preset kualitas
   (`SettingsStore`), dan tidak tumbuh di air atau lereng curam.
   Lihat `TAHAP-4.md`.
5. **Screenshot tanpa PC** — setiap run workflow "Android APK" mengunggah
   artifact `screenshots` (siang/senja/malam) yang bisa dibuka dari halaman
   run di browser HP.
6. **Kalibrasi sumbu tulang** — lihat `TAHAP-2.md` langkah 4. Ini satu-satunya
   hal yang benar-benar butuh matamu: arah sumbu lokal tulang rigify tidak bisa
   diketahui tanpa membuka Unity.
5. **Android** — *Project Settings → Player → Android*:
   - Scripting Backend: **IL2CPP**
   - Target Architectures: **ARM64**
   - Minimum API Level: 24 atau lebih tinggi

---

## Isi folder

```
Assets/_Project/Scripts/Core/      logika murni, noEngineReferences: true
    WorldData.cs       terrain, jalan, region, RNG chunk   (dunia 3 km)
    TerrainSurface.cs  komposisi permukaan + ambang warna (dari pengukuran)
    TerrainMesh.cs     Build(cx,cz,quads) -> array verteks/normal/warna/indeks
    WorldScatter.cs    sebar properti + penempatan orb
    Locomotion.cs      samplePose 25 sendi, damp, joystick
    RigMapping.cs      25 sendi -> tulang VRM
    GameSettings.cs    RawSettings -> GameSettings, normalisasi
    QualityPresets.cs  preset, ApplyPreset, SetGfx, DetectPreset
    GfxResolver.cs     resolveGfx + adaptive resolution
    JsMath.cs          pembulatan setia ECMAScript — PENTING, lihat di dalamnya
Assets/_Project/Scripts/Runtime/   sisi Unity (rig, motor, kamera, streamer, air, PerfHud)
Assets/_Project/Shaders/           AureliaTerrain/AureliaWater + cbuffer .hlsl
Assets/_Project/Tests/EditMode/    CoreParityTests, RigMappingTests, TerrainMeshTests
_verify/                           harness di luar Unity (nunit, unitystub, terrain, shaders)
Packages/manifest.json             URP 17.0.3, Input System, glTFast, Addressables
ProjectSettings/ProjectVersion.txt Unity 6000.0.32f1
.github/workflows/                 android-release.yml (APK), pages.yml,
                                   verify.yml (4 harness di atas, tiap push)
site/index.html                    halaman unduh APK
DESAIN.md                          usulan desain lengkap — BACA INI
TANPA-PC.md                        build APK lewat GitHub Actions, tanpa PC
TAHAP-2.md / TAHAP-3.md            catatan per tahap + hasil pengukurannya
README-UNITY.md                    status & batas verifikasi
push-ke-github.sh                  skrip push ke github.com/KyokoApp/Unity
```

---

## Keputusan desain yang sudah dikunci

- **Dunia 3 km × 3 km (9 km²).** Alasannya terukur: tanpa mobil, satu-satunya
  alat tempuh adalah kaki (6,5 m/s jalan, 13,5 m/s lari). Menyeberang diagonal
  dunia 6 km butuh 10,5 menit lari; 3 km butuh 5,2 menit.
- **Tanpa mobil.** Menghapus ~1.600 baris + 7,2 MB, dan menghapus satu
  liabilitas lisensi (`car.glb` itu CC-BY-NC-SA-4.0 = NonCommercial).
- **URP, bukan HDRP.** HDRP tidak mendukung Android/iOS sama sekali.
- **Karakter: anime orisinal via VRoid Studio** (belum dibuat). Karakter anime
  yang sudah terkenal tidak bisa dipakai — itu hak cipta studio, dan Play Store
  memindai aset untuk IP pihak ketiga.
- **Aset: CC0.** Kenney Nature Kit (329 `.glb`, sudah diverifikasi bisa diunduh
  dan lisensinya CC0) untuk pohon/batu/rumput/jamur.

- **Terrain: vertex color + noise di shader, tanpa tekstur.** Referensi JS-nya
  mewarnai terrain secara prosedural; vertex color mereproduksi hasilnya dengan
  nol memori tekstur dan nol UV yang harus dijahit. Noise detail disampel dari
  **posisi dunia**, bukan UV, supaya tidak ada jahitan di batas chunk.
  Angka ambangnya diukur, bukan ditebak — lihat `TAHAP-3.md`.
- **Air: shader, bukan mesh** (sesuai `DESAIN.md` §4). Satu quad 1.400 m yang
  mengikuti karakter dan di-snap, bukan plane 3 km yang membuang fill-rate.
- **Chunk terrain dibangun di thread latar.** Aman karena `RPG.Core` tidak bisa
  menyentuh UnityEngine (`noEngineReferences: true`, dikunci compiler) dan tidak
  punya field statis mutable (dikunci tes refleksi). Yang memotong budget frame
  hanya upload mesh (~0,3 ms), bukan build-nya (2–4,6 ms di komputer).
- **Statistik tidak boleh membaca balik `Mesh`.** `Mesh.triangles` mengalokasikan
  salinan seluruh indeks setiap kali dibaca; setelah `UploadMeshData(true)`
  salinan CPU-nya memang sudah dibuang. Jumlah segitiga disimpan di dictionary,
  bukan dihitung ulang tiap frame.

Detail dan angka lengkapnya di `DESAIN.md`.
