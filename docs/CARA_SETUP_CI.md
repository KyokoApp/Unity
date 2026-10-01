# Cara Setup Auto-Build APK (sekali saja)

Beda dengan Godot, build Unity di GitHub Actions **butuh lisensi Unity** (yang
Personal gratis, tapi harus diaktivasi sekali). Setelah 3 secrets terisi,
semuanya otomatis selamanya: push → APK + konten terbit sendiri.

## Langkah 1 — Ambil file aktivasi (.alf)

1. Buka tab **Actions** di repo GitHub.
2. Pilih workflow **unity-activation** → **Run workflow**.
3. Setelah selesai, buka run-nya → unduh artifact **unity-activation-file**
   (isinya `Unity_v2022.3.45f1.alf`).

## Langkah 2 — Tukar .alf menjadi lisensi .ulf

1. Buka https://license.unity3d.com/manual
2. Login dengan akun Unity milikmu (buat gratis di unity.com kalau belum punya).
3. Upload file `.alf` tadi → pilih **Unity Personal Edition** → unduh file `.ulf`.

## Langkah 3 — Isi 3 secrets repo

Repo GitHub → **Settings → Secrets and variables → Actions → New repository secret**:

| Nama secret      | Isi                                      |
|------------------|------------------------------------------|
| `UNITY_LICENSE`  | **Seluruh isi teks** file `.ulf` (buka dengan text editor, copy semua) |
| `UNITY_EMAIL`    | Email akun Unity                         |
| `UNITY_PASSWORD` | Password akun Unity                      |

## Langkah 4 — Jalankan build

Push apa pun yang menyentuh `Assets/`, `Packages/`, atau `ProjectSettings/`
(atau jalankan manual workflow **apk-release**). Build pertama ±30–60 menit
(download image editor); berikutnya lebih cepat karena cache `Library`.

Hasilnya di halaman **Releases**:

- **apk-latest** → `UAL2Playground.apk` — instal **sekali saja** di HP.
- **content-latest** → `manifest.json`, `tuning.json`, asset bundle — **diunduh
  otomatis dari dalam game** saat dibuka. Update konten = push → pemain tidak
  perlu instal ulang.

## Cara kerja update in-game (sama seperti launcher Godot lama)

```
APK (peluncur, instal sekali)
  └─ saat start: GET content-latest/manifest.json  (timeout 10 dtk, offline-safe)
       ├─ contentVersion lebih baru?  → unduh tuning.json (+ pack yang SHA-nya berubah)
       │    └─ simpan di persistentDataPath/content/ → langsung diterapkan
       ├─ appVersion lebih baru?      → tampilkan info "APK baru tersedia"
       └─ gagal/offline?              → pakai cache / bawaan APK, game tetap jalan
```

Yang bisa di-update tanpa instal ulang APK:

- `Assets/Resources/Content/tuning.json` — MOTD, kecepatan jalan/lari/lompat,
  warna grid & fog. Edit → push → selesai.
- **Asset bundle** — beri asset (prefab, model, tekstur, animasi) nama bundle di
  Inspector (dropdown *AssetBundle* kiri-bawah). CI otomatis mem-build & menerbitkannya;
  bundle berisi prefab bernama `ContentBoot` akan otomatis di-spawn di world.
- Catatan: **kode C# baru tidak bisa** dikirim lewat bundle (batasan IL2CPP);
  perubahan script tetap butuh APK baru — pemain cukup diberi tahu lewat notifikasi
  "APK baru tersedia" yang muncul otomatis di game.
