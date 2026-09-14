# Aurelia — project Unity

Port dari game three.js `KyokoApp/rpg` ke Unity. **Target: Android (APK).**

---

## ⚠️ Baca ini dulu: apa yang ADA dan apa yang BELUM

Project ini **bukan game yang bisa langsung dimainkan**. Yang sudah jadi baru
**tahap 0–1**: scaffold + logika inti yang sudah diuji.

| Sudah ada | Belum ada |
|---|---|
| `RPG.Core` — world data, quality preset, lokomosi, sebar properti, orb | Scene apa pun |
| 7 tes NUnit, semuanya hijau | Kamera, karakter, terrain mesh |
| Pipeline build APK (GitHub Actions) | UI, audio, postfx |
| Konfigurasi URP + paket | Aset 3D (`.glb`/`.vrm`) |

Kalau kamu buka sekarang, yang terlihat cuma **scene kosong**. Itu memang
waktunya — lihat `DESAIN.md` untuk rencana tahap 2–8.

Yang sudah diverifikasi di luar Unity (Unity tidak ada di tempat project ini dibuat):

```
dotnet build atas file C# yang dikirim   0 error, 0 warning
paritas vs modul JS asli                 1.779 baris / 2.650 nilai, SETARA
                                         selisih maksimum 9,09e-13
NUnit                                    7/7 lulus
```

---

## Syarat

| | |
|---|---|
| **Unity** | `6000.0.32f1` — dipatok di `ProjectSettings/ProjectVersion.txt` |
| **Unity Hub** | untuk memasang versi itu |
| **Module** | Android Build Support (+ OpenJDK, Android SDK & NDK, kalau mau APK) |
| **Git LFS** | disarankan, untuk `.glb`/`.vrm` nanti (`.gitattributes` sudah siap) |

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

Harus **7/7 hijau**. Kalau ada yang merah, artinya port C# menyimpang dari
versi three.js — jangan perbarui angkanya, cari tahu kenapa berubah.
Angka golden di `CoreParityTests.cs` diambil dari menjalankan modul JS asli,
bukan ditulis tangan.

---

## Yang harus disetel manual (belum bisa diotomatiskan dari luar Unity)

1. **URP Asset** — buat lewat *Assets → Create → Rendering → URP Asset (with
   Universal Renderer)*, lalu pasang di:
   - *Project Settings → Graphics → Scriptable Render Pipeline Settings*
   - *Project Settings → Quality* (tiap tier)
2. **Active Input Handling** — *Project Settings → Player → Other Settings →
   Configuration* → set **Both** atau **Input System Package**
3. **Android** — *Project Settings → Player → Android*:
   - Scripting Backend: **IL2CPP**
   - Target Architectures: **ARM64**
   - Minimum API Level: 24 atau lebih tinggi

---

## Isi folder

```
Assets/_Project/Scripts/Core/      logika murni, noEngineReferences: true
    WorldData.cs       terrain, jalan, region, RNG chunk   (dunia 3 km)
    WorldScatter.cs    sebar properti + penempatan orb
    Locomotion.cs      samplePose 25 sendi, damp, joystick
    GameSettings.cs    RawSettings -> GameSettings, normalisasi
    QualityPresets.cs  preset, ApplyPreset, SetGfx, DetectPreset
    GfxResolver.cs     resolveGfx + adaptive resolution
    JsMath.cs          pembulatan setia ECMAScript — PENTING, lihat di dalamnya
Assets/_Project/Tests/EditMode/    CoreParityTests.cs (NUnit)
Packages/manifest.json             URP 17.0.3, Input System, glTFast, Addressables
ProjectSettings/ProjectVersion.txt Unity 6000.0.32f1
.github/workflows/                 android-release.yml (APK), pages.yml
site/index.html                    halaman unduh APK
DESAIN.md                          usulan desain lengkap — BACA INI
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

Detail dan angka lengkapnya di `DESAIN.md`.
