# Tahap 2 — karakter bisa berjalan

Status: **kode selesai & terverifikasi sejauh yang bisa dilakukan tanpa Unity.**
Yang tersisa adalah 5 langkah penyetelan di Editor (lihat "Cara menjalankan").

Rujukan rencana: `DESAIN.md` §5. Target tahap ini menurut rencana itu:
> *"Character controller + kamera + `samplePose` → karakter bisa jalan di dunia
> kosong. Hasil yang terlihat: karakter anime berjalan di bidang datar."*

---

## Yang ditambahkan

### `RPG.Core` — pure, bisa dites tanpa Unity

| File | Isi |
|---|---|
| `Scripts/Core/RigMapping.cs` | 25 sendi `SamplePose` → 23 slot tulang konkret, plus tabel nama tulang yang diukur dari file model |

Ini satu-satunya bagian Tahap 2 yang memuat **keputusan desain baru**, jadi ia
ditaruh di Core supaya bisa diuji. Tiga keputusan itu:

| Sendi `SamplePose` | Masalah | Keputusan |
|---|---|---|
| `SHOULDERL/R` | Model ini **tidak punya clavicle** — sudah dicek, nol tulang bahu di 216 node | Dilipat penuh ke lengan atas. Kontribusinya kecil (`-swing*.09`, `sign*.035`) |
| `KNUCLEL/R` | Tidak ada padanan; nilainya konstan (`.48` kanan, `.12` kiri) | Dilipat ke sumbu X pergelangan, dengan bobot yang bisa dinolkan |
| `LOWLEGL/R` | Ada tulang twist betis `DEF-*knee.001` / `.002` | Dibagi 50/50 ke keduanya supaya kulit tidak melintir di satu titik |

Sisanya 19 sendi punya padanan langsung di 49 humanoid bone VRM model ini.

### `RPG.Runtime` — sisi Unity

| File | Isi |
|---|---|
| `CharacterRig.cs` | Menulis `localRotation` tulang tiap frame; merekam & **menyimpan** bind pose; pengali tanda per kelompok sumbu untuk kalibrasi |
| `CharacterMotor.cs` | Masukan → gerak → pose. Kecepatan **6,5 / 13,5 m/s** dari `DESAIN.md`, gravitasi, lompat, batas dunia, tinggi tanah dari `WorldData.TerrainH()` |
| `CameraRig.cs` | Kamera orbit orang ketiga. Jarak & sensitivitas diambil dari `GameSettings` (batas 3..8 dan 0,4..2 sudah diuji paritas) |
| `TouchJoystick.cs` | Stik virtual untuk Android. Sumbunya dihitung pakai `Locomotion.JoystickAxis()` — deadzone 0,14 asli, bukan karangan baru |
| `SettingsStore.cs` | Adapter `PlayerPrefs` → `RawSettings` → `SettingsNormalizer.Normalize()`. Inilah "adapter storage" yang dijanjikan komentar di `GameSettings.cs` |

### `RPG.Editor`

| File | Isi |
|---|---|
| `Stage2SceneBuilder.cs` | Menu pembangun scene + menu kalibrasi pose |
| `VrmCharacterImportSettings.cs` | Kompresi tekstur Android otomatis + menu laporan biaya karakter |

### Tes

| File | Isi |
|---|---|
| `Tests/EditMode/RigMappingTests.cs` | 14 tes baru |

---

## Verifikasi

```
_verify/nunit        dotnet test    21/21 lulus   (7 paritas lama + 14 RigMapping baru)
_verify/unitystub    dotnet build   0 error, 0 warning
```

`_verify/verify_rig.py` adalah port Python independen dari `SamplePose` +
`Resolve`. Ia dipakai untuk memeriksa ulang **setiap angka golden** di
`RigMappingTests.cs` sebelum tes itu dijalankan — jadi angka di tes bukan hasil
tebakan yang kebetulan lolos.

Harness `unitystub` menangkap satu bug nyata selama penulisan:
`GetComponentsInChildren<T>()` mengembalikan array, tapi kodenya memakai
`.Count`. Sudah diperbaiki jadi `.Length`.

**Yang belum terverifikasi:** semuanya yang butuh Unity sungguhan — apakah
UniVRM menghasilkan Avatar humanoid, apakah nama tulang cocok, dan **ke arah
mana sumbu lokal tiap tulang menunjuk**. Yang terakhir ini tidak bisa diketahui
dari file `.vrm` saja; itu sifat rigify saat diekspor Blender.

---

## Cara menjalankan

### 0. Prasyarat sekali saja

- Unity `6000.0.32f1` + module Android Build Support
- **UniVRM v0.131.2** → impor `UniVRM-0.131.2_a471.unitypackage`
- Taruh `AureliaChar.vrm` di `Assets/Art/Characters/`, tunggu impornya selesai
  sampai muncul `AureliaChar.prefab`

### 1. Active Input Handling → **Input Manager (Old)**

*Project Settings → Player → Other Settings → Configuration → Active Input
Handling = **Input Manager (Old)**.* Sudah di-commit di
`ProjectSettings/ProjectSettings.asset` (`activeInputHandler: 0`), jadi langkah
ini biasanya tidak perlu dikerjakan manual.

**Ini wajib, bukan pilihan.** `CharacterMotor` dan `CameraRig` memakai kelas
`Input` lama. Kalau disetel ke *Input System Package (New)* saja,
`Input.GetAxisRaw()` akan melempar `InvalidOperationException` saat runtime.

*(Catatan koreksi: dokumen ini sempat menyuruh setel **Both**. Itu salah. Tidak
ada skrip yang memakai API Input System baru, Unity menolak Both di Android,
dan mengubah nilainya dari dalam skrip build merusak kompilasi. Lihat
`CARA-PAKAI.md` bagian Active Input Handling.)*

Migrasi penuh ke Input System baru masuk akal dikerjakan bareng HUD di Tahap 5 —
kalau nanti jadi, setel `activeInputHandler` di file ProjectSettings (bukan dari
skrip) dan pastikan package `com.unity.inputsystem` kembali dirujuk di
`RPG.Runtime.asmdef`.

### 2. Menu pembangun

```
Tools > Aurelia > 1. Buat URP Asset (kalau belum ada)
Tools > Aurelia > 2. Bangun scene Tahap 2
```

Menu 2 membuat `Assets/_Project/Scenes/Tahap2.unity` berisi: cahaya directional,
bidang tanah datar 120×120 m pada `y = WorldData.TerrainH(0,0)`, instance prefab
karakter (+ `CharacterRig`, `CharacterMotor`, `TouchJoystick`), kamera
(+ `CameraRig`), dan EventSystem. Baca Console — ia melaporkan apa yang dipakai
dan apa yang kurang.

Kalau prefab VRM belum ada, dipasang capsule placeholder supaya motor & kamera
tetap bisa diuji lebih dulu.

### 3. Tekan Play

| Kontrol | |
|---|---|
| WASD / panah | jalan (6,5 m/s) |
| Shift | lari (13,5 m/s) |
| Spasi | lompat |
| seret mouse / jari | putar kamera |
| di HP | stik virtual muncul di kiri-bawah saat disentuh |

### 4. Kalibrasi sumbu — **langkah yang paling mungkin perlu kamu kerjakan**

Kalau karakter bergerak tapi anggota badannya berputar ke arah yang salah
(kaki mengayun ke samping, lengan memutar seperti baling-baling), itu bukan bug
logika: itu sumbu lokal tulang rigify yang belum ketahuan arahnya.

```
Tools > Aurelia > 3. Uji pose karakter > Paha +30 (X)
```

Lihat di Scene view ke arah mana paha bergerak. Ulangi untuk `(Y)` dan `(Z)`.
Sumbu yang mengayunkan kaki **maju-mundur** adalah sumbu yang harus diisi ke
`SignLegX`. Kalau arahnya terbalik, isi `-1`. Lakukan hal yang sama untuk
`SignArm*`, `SignSpine*`, `SignFootX` di Inspector `CharacterRig`.

Default saat ini: `Leg = (+1,+1,+1)`, `Arm = (+1,+1,−1)`, `Spine = (+1,+1,+1)`,
`Foot X = +1`. Itu tebakan terdidik (rigify umumnya memakai +Y sepanjang tulang
dan rotasi utama di X), **bukan hasil pengukuran**. Perbaiki lewat menu di atas,
lalu simpan angka akhirnya di sini supaya tidak perlu dikalibrasi ulang:

```
Hasil kalibrasi (isi setelah dicoba):
  SignLegX   = ____     SignArmX   = ____
  SignLegY   = ____     SignArmY   = ____
  SignLegZ   = ____     SignArmZ   = ____
  SignSpineX = ____     SignFootX  = ____
  SignSpineY = ____
  SignSpineZ = ____
```

### 5. Cek biaya

```
Tools > Aurelia > Laporkan biaya karakter
```

Mengeluarkan segitiga, verteks, draw call, dan memori tekstur yang sebenarnya
setelah impor. Pembandingnya ada di `OPTIMASI-KARAKTER.md`.

---

## Keputusan yang perlu dicatat

**Kenapa menulis `localRotation` langsung, bukan `Animator` / muscle.**
Komentar di `Locomotion.cs` sudah mengantisipasi dua jalur: *"Animator dengan
Playables, atau langsung menulis localRotation per Transform"*. Yang kedua
dipilih karena:

1. Nilai `SamplePose` adalah rotasi relatif terhadap bind pose dalam radian —
   persis bentuk yang dibutuhkan penulisan `localRotation`, dan tidak cocok
   dengan muscle yang sudah dinormalisasi −1..1.
2. Sistem muscle butuh Avatar humanoid yang benar. Kalau UniVRM gagal membuatnya
   (bisa terjadi pada ekspor Blender non-standar), seluruh jalur itu mati.
   Penulisan transform tetap jalan selama tulang bisa ditemukan by name.
3. `Animator` pada prefab VRM **dimatikan** oleh `CharacterRig`. Tanpa
   `RuntimeAnimatorController` pun, Animator humanoid bisa menulis ulang tulang
   dan menimpa pose kita. `VRMSpringBone` (rok & rambut) tetap jalan — ia
   `LateUpdate` dan menyentuh tulang yang berbeda.

**Kenapa bind pose diserialisasi, bukan cuma disimpan di memori.**
Menu "Uji pose karakter" memutar tulang di Edit Mode. Perubahan yang belum
di-save **ikut terbawa waktu masuk Play Mode**. Kalau bind pose direkam ulang di
`Awake()`, pose uji itu akan terekam sebagai "pose netral" dan seluruh animasi
miring permanen. Dengan bind pose tersimpan di scene, `Awake()` hanya merekam
ulang kalau daftarnya kosong atau ada tulang yang hilang.

**Kenapa stik sentuh belum pakai uGUI.** HUD yang sebenarnya baru dikerjakan di
Tahap 5. Membangun Canvas sekarang hanya untuk dibongkar lagi nanti adalah kerja
ganda. Versi ini membaca `Touch` langsung dan menggambar lewat `OnGUI` — cukup
untuk membuktikan kendali sentuh berfungsi. Yang penting sumbunya lewat
`Locomotion.JoystickAxis()`, jadi deadzone dan kurva responsnya sama dengan game
asli.

**Kenapa tanah Tahap 2 bidang datar.** Sesuai `DESAIN.md`, yang diuji di tahap
ini adalah "karakter bisa jalan", bukan "dunia terlihat" — itu Tahap 3. Tapi
tingginya tetap diambil dari `WorldData.TerrainH(0,0)`, bukan `y=0` karangan,
supaya karakter berdiri di angka yang benar dan Tahap 3 tinggal mengganti
mesh-nya.

---

## Sengaja ditunda

| | Kapan | Kenapa bukan sekarang |
|---|---|---|
| Terrain mesh streaming | Tahap 3 | butuhnya shader + chunk mesh, bukan controller |
| Tabrakan kamera vs terrain | Tahap 3 | belum ada terrain |
| Aset Kenney disebar | Tahap 4 | `WorldScatter` sudah siap & teruji, tinggal mesh |
| Orb, HUD, loop gameplay | Tahap 5 | sekalian migrasi ke Input System baru |
| Attack / combo | Tahap 5 | `SamplePose` sudah mendukung (`Attack`, `Combo`), tinggal pemicu |
| Audio ambient | Tahap 6 | — |
| Postfx + tier kualitas | Tahap 7 | `QualityPresets` & `GfxResolver` sudah teruji, tinggal dipasang |
| Spring bone tuning | kalau FPS jatuh | mengubah gerakan rok = mengubah tampilan yang dibeli |

---

## Berkas di tahap ini

```
Assets/_Project/Scripts/Core/RigMapping.cs
Assets/_Project/Scripts/Runtime/CharacterRig.cs
Assets/_Project/Scripts/Runtime/CharacterMotor.cs
Assets/_Project/Scripts/Runtime/CameraRig.cs
Assets/_Project/Scripts/Runtime/TouchJoystick.cs
Assets/_Project/Scripts/Runtime/SettingsStore.cs
Assets/_Project/Scripts/Editor/RPG.Editor.asmdef
Assets/_Project/Scripts/Editor/Stage2SceneBuilder.cs
Assets/_Project/Scripts/Editor/VrmCharacterImportSettings.cs
Assets/_Project/Tests/EditMode/RigMappingTests.cs
_verify/unitystub/          harness kompilasi di luar Unity
_verify/verify_rig.py       pemeriksa silang angka golden
TAHAP-2.md                  dokumen ini
```
