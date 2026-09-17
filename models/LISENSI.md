# Model karakter — status lisensi & catatan impor

> **File karakter (`.vrm` / `.glb`) di folder ini sengaja di-`.gitignore`.** Model ini menandai
> dirinya `licenseName: Redistribution_Prohibited`, jadi file-nya hanya
> hidup di disk lokal / Drive build, tidak pernah di-commit. (Repo ini
> sekarang privat, tapi aturan gitignore tetap dipertahankan.)
>
> Sudah diverifikasi (era Godot — dulu: `Assets/Art/Characters/*.vrm`):
> ```
> $ git check-ignore -v models/AureliaChar.glb
> .gitignore: models/*.vrm models/*.glb   models/AureliaChar.glb
> ```

---

## Metadata yang terbaca di dalam file

| Field | Nilai | Artinya untuk project ini |
|---|---|---|
| `author` | `Animeit` | penjualnya |
| `title` | `Test` | — |
| `licenseName` | **`Redistribution_Prohibited`** | **jangan di-commit, jangan di-bundle ke APK yang diunggah ke mana pun** |
| `commercialUssageName` | `Allow` | diklaim boleh komersial — **tapi lihat peringatan di bawah** |
| `violentUssageName` | `Allow` | — |
| `sexualUssageName` | `Allow` | — |
| `allowedUserName` | `Everyone` | — |
| `otherLicenseUrl` | *(kosong)* | tidak ada teks lisensi tertulis yang menyertai |

### ⚠️ Peringatan yang harus dicatat, bukan untuk menakut-nakuti

Model ini **bukan** hasil VRoid Studio. Generator di dalam filenya
`saturday06_blender_vrm_exporter_experimental_2.33.1`, dan nama tekstur/tulangnya
adalah nama aset internal **Koikatsu / Koikatsu Party**:

```
cf_m_body_MT_CT   KK Face light   KK Eyebrows (mayuge)   KK Eyewhites (sirome)
KK EyeL (hitomi)  KK Teeth (tooth) KK Tongue             KK Eyeline up/down
KK cf_m_shorts_01  KK cf_m_hair_f_06 / s_06 / b_07 / b_22 / b_100
KK cf_m_ahoge04    KK acs_m_flower  KK mf_m_primmaterial
DEF-Hips  DEF-Left leg  Hair_DEF-cf_J_hairSR_00_00      <- rigify/KKBP Blender
```

Artinya alur pembuatannya: Koikatsu → PMX → Blender (plugin KKBP) → VRM.
Aset Koikatsu milik Illusion, dan penjual pihak ketiga tidak berada di posisi
untuk memberikan hak komersial atasnya — persis logika yang sudah ditulis di
`DESAIN.md` §3 untuk Rem/Zero Two.

**Untuk pemakaian pribadi (build di HP sendiri, tidak dipublikasikan): praktis
nol risiko, dan itu memang rencana sekarang.** Dua hal yang tetap harus dijaga:

1. Repo tetap **tidak boleh** berisi file ini → sudah diurus `.gitignore`.
2. Jangan unggah APK yang memuat model ini ke tempat publik (GitHub
   Releases dsb.). Workflow sekarang (`.github/workflows/android-build.yml`)
   hanya menghasilkan **artifact privat** repo — itu batas amannya.

Kalau nanti mau naik ke Play Store, model ini **harus diganti** — karakter
VRoid Studio buatan sendiri, sesuai rencana `DESAIN.md`.

---

## File yang ada di sini

| File | Ukuran | Keterangan |
|---|---|---|
| `AureliaChar.vrm` | **15,20 MB** | versi teroptimasi — **pakai yang ini** |
| *(asli, disimpan di luar repo)* | 44,35 MB | master cadangan, jangan dihapus |

Keduanya **menghasilkan gambar yang identik secara bit-per-bit** untuk geometri,
material, dan semua tekstur detail. Yang dibuang hanya data yang tidak pernah
dipakai. Rincian transformasinya: skrip `tools/vrm_optim.py` di repo ini.

---

## Cara impor (era Unity — referensi sejarah; target sekarang = GLB di Godot)

1. Install **UniVRM** (`vrm-c/UniVRM` v0.131.2 — `UniVRM-0.131.2_a471.unitypackage`).
   File ini **VRM 0.x** (`specVersion: 0.0`), didukung UniVRM 0.131.2.
2. Taruh `AureliaChar.vrm` di folder ini (`Assets/Art/Characters/`).
3. Tunggu Unity selesai impor → muncul prefab `AureliaChar.prefab`.
4. `Assets/_Project/Scripts/Editor/VrmCharacterImportSettings.cs` akan otomatis
   menyetel kompresi tekstur Android (ASTC 6×6 + mipmap streaming) begitu
   tekstur-nya dihasilkan UniVRM. Cek Console untuk log hemat memorinya.
5. Jalankan menu **Tools → Aurelia → Laporkan biaya karakter** untuk melihat
   angka segitiga / draw call / memori tekstur yang sebenarnya.

---

## Pemetaan tulang `samplePose` → rig model ini

`RPG.Core.Locomotion.SamplePose()` menghasilkan **25 sendi**. Rig model ini punya
**49 bone humanoid VRM lengkap termasuk semua jari**, jadi 19 dari 25 langsung
nyambung. Sisanya perlu penanganan khusus karena rig Koikatsu tidak punya
padanannya.

| Kunci `samplePose` | Bone di model ini | Humanoid VRM | Status |
|---|---|---|---|
| `PELVIS` | `DEF-Hips` | `hips` | ✅ langsung |
| `BELLY` | `DEF-Spine` | `spine` | ✅ langsung |
| `CHEST` | `DEF-Chest` | `chest` | ✅ langsung |
| `NECK` | `DEF-Neck` | `neck` | ✅ langsung |
| `HEAD` | `DEF-Head` | `head` | ✅ langsung |
| `THIGH{L,R}` | `DEF-{Left,Right} leg` | `{left,right}UpperLeg` | ✅ langsung |
| `KNEE{L,R}` | `DEF-{Left,Right} knee` | `{left,right}LowerLeg` | ✅ langsung |
| `FOOT{L,R}` | `DEF-{Left,Right} ankle` | `{left,right}Foot` | ✅ langsung |
| `TOE{L,R}` | `DEF-{Left,Right} toe` | `{left,right}Toes` | ✅ langsung |
| `ARM{L,R}` | `DEF-{Left,Right} arm` | `{left,right}UpperArm` | ✅ langsung |
| `FOREARM{L,R}` | `DEF-{Left,Right} elbow` | `{left,right}LowerArm` | ✅ langsung |
| `HAND{L,R}` | `DEF-{Left,Right} wrist` | `{left,right}Hand` | ✅ langsung |
| `LOWLEG{L,R}` | `DEF-{Left,Right} knee.001` | *(tidak ada)* | ⚠️ cari by name — tulang twist betis |
| `SHOULDER{L,R}` | **tidak ada clavicle** | *(tidak ada)* | ⚠️ jumlahnya kecil (`-swing*.09`, `sign*.035`) → lipat ke `ARM` |
| `KNUCLE{L,R}` | `DEF-{Left,Right} arm.002` / `*FingerPalm_*` | *(tidak ada)* | ⚠️ nilai konstan (`.48` R, `.12` L) → lipat ke roll `HAND` |

Tulang non-humanoid lain yang ada di model: `DEF-Upper Chest`, `DEF-Hips`,
`DEF-{Left,Right} {leg,knee,arm,elbow}.001/.002` (twist), `DEF-*FingerPalm_*` (8),
`DEF-*_end` (ujung), plus **84 tulang `DEF-dress_*`** dan tulang rambut `Hair_DEF-*`.

### Spring bone (fisika rambut & rok)

| Grup | Jumlah bone | stiffiness | dragForce | Catatan |
|---|---|---|---|---|
| rok (`DEF-dress_*`) | **84** | 2,5 | 0,60 | bagian termahal — 12 rantai |
| rambut (`Hair_DEF-*`) | 8 | 1,5 | 0,70 | murah |

92 spring bone disimulasikan di CPU oleh UniVRM tiap frame. Kalau FPS di HP
jatuh, ini tempat pertama yang harus diturunkan (mis. update tiap 2 frame, atau
pangkas rantai rok dari 12 jadi 6) — **tapi jangan lakukan sekarang**, karena
mengubah gerakan rok = mengubah tampilan yang kamu beli.
