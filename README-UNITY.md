# Port `KyokoApp/rpg` (three.js) → Unity — status & cara lanjut

## ⚠️ Baca ini dulu: dua pilihanmu saling bertentangan

Kamu memilih **HDRP** + target **Android/iOS**. Kombinasi itu tidak bisa jalan.
Dari dokumentasi resmi HDRP 17.2 (Unity 6.2), platform yang didukung HDRP hanya:

> Windows/Windows Store (DX11/DX12, SM5.0) · PS4 · PS5 · Xbox One · Xbox Series X|S ·
> macOS (Metal) · Linux & Windows dengan Vulkan
> — dan "HDRP doesn't support OpenGL or OpenGL ES devices."

**Android dan iOS tidak ada di daftar itu.** Bukan "kurang optimal" — memang tidak
didukung. Jadi salah satu dari dua pilihanmu harus berubah:

| Kalau kamu mau… | Maka… |
|---|---|
| **Tetap Android/iOS** (pilihan platformmu) | Pakai **URP**. Ini yang saya siapkan di project ini. |
| **Tetap HDRP** | Targetnya jadi **PC/konsol**. Fitur offline & input sentuh mobile jadi tidak relevan, dan game aslinya adalah PWA mobile — jadi ini mengubah produknya, bukan cuma engine-nya. |

Catatan tambahan yang perlu kamu tahu sebelum memilih HDRP: sejak awal 2026 Unity
menyatakan **tidak ada fitur baru yang direncanakan untuk HDRP** — satu-satunya
penambahan adalah dukungan Switch 2. Semua investasi Unity sekarang ke URP.
Memulai project baru dengan HDRP di 2026 adalah taruhan yang aneh.

**Yang saya bangun mengikuti pilihan platformmu (mobile) → URP.** Kalau kamu
memang mau HDRP/PC, kabari; bagian yang sudah jadi di `Scripts/Core` tidak
terpengaruh sama sekali (ia tidak tahu apa-apa soal render pipeline), yang berubah
hanya `manifest.json` dan Fase 6.

---

## Yang sudah jadi dan SUDAH diverifikasi

### Fase 0 — scaffold project Unity
```
unity-rpg/
├── Packages/manifest.json            URP 17.0.3, Input System, glTFast, Addressables, Newtonsoft
├── ProjectSettings/ProjectVersion.txt  Unity 6000.0.32f1
├── .gitignore / .gitattributes       + Git LFS untuk car.glb (7,2 MB) dkk.
└── Assets/_Project/
    ├── Scripts/Core/       RPG.Core.asmdef   (noEngineReferences: true)
    ├── Scripts/Runtime/    RPG.Runtime.asmdef (URP, Input System, glTFast)
    ├── Tests/EditMode/     RPG.Tests.EditMode.asmdef (NUnit)
    └── Scenes/  Art/Models/  Audio/
```

### Fase 1 — port logika murni ke C# (selesai, teruji)
| File C# | Dari | Isi |
|---|---|---|
| `WorldData.cs` | `world-data.mjs` (80) | terrain, jalan, region, waypoint, RNG chunk, chunk plan |
| `Locomotion.cs` | `locomotion.mjs` (58) | `SamplePose`, `Damp`, `JoystickAxis` |
| `GameSettings.cs` | `quality.mjs` (bagian data) | `RawSettings` → `GameSettings`, `Normalize` |
| `QualityPresets.cs` | `quality.mjs` (bagian preset) | preset, `ApplyPreset`, `SetGfx`, `DetectPreset` |
| `GfxResolver.cs` | `resolveGfx` + adaptive | tingkat → angka konkret engine |
| `JsMath.cs` | — | pembulatan setia ECMAScript (lihat di bawah) |

`RPG.Core` sengaja `noEngineReferences: true` — tidak menyentuh `UnityEngine`
sama sekali, jadi bisa dikompilasi dan dites di luar Unity.

---

## Verifikasi yang benar-benar dijalankan

Unity tidak terpasang di sandbox ini, jadi saya tidak bisa menjalankan editor-nya.
Tapi logika di atas bisa diuji tanpa Unity, dan itu saya lakukan sungguhan.

**1. Kompilasi.** `dotnet build` atas file C# yang *benar-benar* dikirim ke Unity
(bukan salinan): **Build succeeded, 0 warning, 0 error.**

**2. Uji paritas JS ↔ C# — 848 baris, 1.142 nilai numerik.**
Modul JS asli (`world-data`, `locomotion`, `quality`) dijalankan, lalu port C#
dijalankan dengan masukan identik, lalu hasilnya dibandingkan numerik:

```
baris dibandingkan      : 848
nilai numerik dibanding : 1142
toleransi               : 1e-09
selisih maksimum        : 1.11022e-16  (wd.terrainColor(-3700,2100))

SETARA - port C# menghasilkan angka identik dengan JS asli
```

Selisih maksimum 1 ULP, berasal dari perbedaan implementasi `Math.Sin` V8 vs .NET.
Tidak bisa dihindari dan tidak berpengaruh. Satu kasus (`ARMR.x`) saya cek sampai
ke pola bitnya: `0000000000c8e1bf` di kedua sisi — identik bit per bit.

**3. Tes NUnit — 7/7 lulus**, termasuk tes golden-value yang memaku 45 angka
turunan dari JS asli:
```
Passed!  - Failed: 0, Passed: 7, Skipped: 0, Total: 7
```

### Dua bug nyata yang tertangkap oleh uji paritas

Ini bukan teori — keduanya bug asli di port pertama saya, dan keduanya akan
membuat game Unity berbeda diam-diam dari versi three.js:

1. **Pembulatan.** `Math.Round` bawaan .NET memakai *banker's rounding*:
   `Math.Round(22.5)` → **22**, sedangkan `Math.round(22.5)` di JS → **23**.
   Akibatnya `dustCount` preset Sedang jadi 22 alih-alih 23, `birdCount` 8
   alih-alih 9, `fogFar` 1282 alih-alih 1283. Jumlah partikel dan jarak pandang
   bergeser tanpa terlihat. Solusi: `JsMath.RoundToInt()` (= `floor(x+0.5)`,
   definisi ECMAScript) dipakai di 15 tempat; ada tesnya.
2. **Urutan chunk.** `List.Sort` .NET tidak stabil, `Array.prototype.sort` V8
   sejak 7.0 dijamin stabil. Untuk jarak sama, urutan termuatnya chunk jadi beda.
   Diganti ke LINQ `OrderBy` yang stabilitasnya dijamin.

### Batas verifikasi — jujur
Yang **belum** bisa diverifikasi di sini: apakah Unity benar-benar membuka
project-nya tanpa error, dan apakah tes NUnit jalan di dalam Test Runner Unity.
Saya memakai NUnit 3.14 di .NET 8 untuk verifikasi; Unity 6 mengirim NUnit 3.5.0.
API klasik yang dipakai (`Assert.AreEqual`, `IsTrue`, `DoesNotThrow`, …) identik
di keduanya, jadi sumbernya kompatibel — tapi eksekusi di dalam Unity tetap
harus kamu jalankan sendiri. Versi paket di `manifest.json` juga perlu kamu
cek terhadap Unity yang kamu pasang.

---

## Cara melanjutkan

1. Buka `unity-rpg/` di Unity Hub (Unity 6000.0.32f1 atau LTS 6 lain).
   Biarkan Unity meng-generate sisa `ProjectSettings/` saat pertama dibuka.
2. Buat **URP Asset** + **Universal Renderer**, set di
   *Project Settings → Graphics* dan *Quality*.
3. Jalankan *Window → General → Test Runner → EditMode*. Harus 7/7 hijau.
   Kalau `PortSetaraDenganVersiThreeJs` merah, port-nya melipat dari aslinya —
   jangan perbarui angkanya sebelum tahu kenapa berubah.
4. Lanjut Fase 2 (lihat urutan di `unity-migration/AUDIT-MIGRASI.md` §5).

### Audio
Kamu memilih **aset suara nyata**. Folder `Assets/Audio/` sudah disiapkan.
Yang dibutuhkan: mesin (idle → redline, idealnya beberapa lapis RPM), wastegate,
ban/gesekan, angin, benturan, ambient fantasy (angin, pad akor, burung, shimmer).
Semua itu sekarang disintesis di `js/audio.js` tanpa satu pun file — jadi tidak
ada aset yang bisa dipindahkan; semuanya harus dicari atau direkam.

---

## Yang belum dikerjakan (dan perkiraan bebannya)

| Fase | Isi | Sifat |
|---|---|---|
| 2 | Chunk streaming (Job System + `DrawMeshInstanced`), tekstur prosedural, kamera 3 mode, spawn | tulis ulang pola |
| 3 | `car.glb`/`character.glb` via glTFast, rig + Animator, ganti `samplePose` | sebagian otomatis |
| 4 | Audio dari aset nyata | baru |
| 5 | HUD + HUD mobil draggable + panel pengaturan (838 baris DOM) | **tulis ulang total** |
| 6 | Postfx (bloom/motion blur/god rays, 397 baris) → URP Renderer Feature | **tulis ulang total** |
| 7 | Build Android/iOS + ganti 126 tes Node dengan Unity Test Framework | baru |

Yang paling berisiko bukan volumenya, tapi **Fase 6**: `postfx.mjs` menulis satu
pass komposit kustom dengan `WebGLRenderTarget`. Di URP itu jadi Renderer Feature
dengan RenderGraph — konsepnya beda, bukan terjemahan.

---

## Update: dunia 6 km + pipeline APK

### Dunia sudah dikecilkan jadi 6 km (36 km²)
Diterapkan di **kedua** codebase supaya tidak menyimpang:
`rpg/game/world-data.mjs` (three.js) dan `Assets/_Project/Scripts/Core/WorldData.cs`.
Uji paritas diulang setelah perubahan: **848 baris / 1.142 nilai numerik, SETARA**,
selisih maksimum 1,4e-14. Ke-45 golden value di `CoreParityTests.cs` sudah
diregenerasi dari JS dan tes NUnit tetap **7/7 hijau**.

Yang ikut berubah, dan kenapa (semuanya terukur, bukan ditebak):

| Perubahan | Alasan |
|---|---|
| `ROAD_SPACING` 3000 → 1500 | Di dunia 6 km (batas 2968 m) grid 3000 m **hanya menyisakan lajur 0** — seluruh jaringan jalan runtuh jadi satu persimpangan |
| Region ±6000 → ±1500 | Supaya 7 waypoint tetap di dalam batas |
| Ramp utara `smooth(1000,7000)` → `smooth(500,3500)` | Tanpa ini puncak tertinggi anjlok dari **+282 m → +99 m**. Sekarang +247 m |
| Sungai/danau ditarik ke dalam + radius dikecilkan | Danau lama di x=−3700 dan x=5100 jatuh di luar batas 2968 m |

**Konsekuensi yang perlu kamu tahu:**
- Air jadi **6,8%** luas dunia (2,4 km²), dari **1,5%** (8,6 km²) sebelumnya. Secara
  absolut airnya lebih sedikit, tapi karena dunianya jauh lebih kecil, terasa lebih
  banyak danau. Bilang saja kalau mau diturunkan.
- Mobil berkecepatan puncak **72 m/s (259 km/j)** sekarang menyeberangi seluruh dunia
  dalam **~83 detik** (dulu ~333 detik). Mobilnya jadi terasa sangat cepat untuk
  dunia sekecil ini — kemungkinan `maxSpeed` perlu diturunkan atau dunianya jangan
  sekecil ini.
- `TERRAIN_GLSL` diubah identik dengan JS dan diverifikasi di 23.345 titik
  (selisih maks 5,7e-14). Kalau melenceng, rumput dan pohon melayang/tenggelam.

### Pipeline APK → GitHub Releases
- `.github/workflows/android-release.yml` — tes EditMode → build APK (ARM64, IL2CPP)
  → unggah ke Releases. Jalan manual atau saat ada tag `v*`.
- `.github/workflows/pages.yml` + `site/index.html` — halaman unduh di GitHub Pages
  yang membaca rilis terbaru dari API GitHub.
- Kedua workflow sudah divalidasi: YAML parse OK, dan ketiga blok shell di dalamnya
  lolos `bash -n`.

**Yang belum bisa diverifikasi di sini:** workflow-nya belum pernah benar-benar
dijalankan (tidak ada Unity, tidak ada kredensial GitHub di sandbox). Butuh secret
`UNITY_LICENSE`, `UNITY_EMAIL`, `UNITY_PASSWORD` dulu, lalu tekan *Run workflow*
dan baca log-nya.

**Dan yang lebih penting:** APK yang dihasilkan hari ini akan **kosong**. Project
Unity ini baru berisi Fase 0 (scaffold) + Fase 1 (logika murni) — belum ada scene,
kamera, dunia, atau karakter. Pipeline-nya siap, tapi gamenya belum ada di sana.
Fase 2–6 harus jalan dulu sebelum APK berisi sesuatu yang bisa dimainkan.
