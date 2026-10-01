# Cara Setup Auto-Build APK (sekali saja)

Beda dengan Godot, build Unity di GitHub Actions **butuh lisensi Unity** (yang
Personal gratis). Kabar baiknya: sekarang **cukup 2 secrets** — email + password
akun Unity — dan CI mengaktivasi lisensi Personal **otomatis** setiap build.

> **Catatan penting**: jalur lama lewat file `.alf` + https://license.unity3d.com/manual
> **sudah ditutup Unity** untuk lisensi Personal, jadi workflow `unity-activation`
> di repo ini sudah dihapus. Tidak perlu (dan tidak bisa lagi) menukar `.alf`
> menjadi `.ulf` secara manual lewat situs itu.

## Langkah 1 — Siapkan akun Unity

1. Buat akun gratis di https://unity.com (atau pakai akun yang sudah ada).
2. **Nonaktifkan 2FA** di akun tersebut — aktivasi otomatis lewat command line
   tidak bisa menjawab prompt 2FA, jadi akun dengan 2FA aktif akan gagal.
3. Disarankan pakai akun khusus (bukan email pribadi utama), karena passwordnya
   disimpan sebagai secret repo.

## Langkah 2 — Isi secrets repo

Repo GitHub → **Settings → Secrets and variables → Actions → New repository secret**:

| Nama secret      | Isi                                      | Wajib? |
|------------------|------------------------------------------|--------|
| `UNITY_EMAIL`    | Email akun Unity                         | **Ya** |
| `UNITY_PASSWORD` | Password akun Unity                      | **Ya** |
| `UNITY_LICENSE`  | Seluruh isi teks file `.ulf` (fallback, lihat Langkah 3) | Opsional |

Cara kerja CI (workflow `apk-release`):

- Kalau `UNITY_LICENSE` **terisi** → isinya langsung dipakai sebagai lisensi
  (tanpa aktivasi apa pun).
- Kalau `UNITY_LICENSE` **kosong** → step **"Siapkan lisensi Unity"**
  menjalankan container `unityci/editor:ubuntu-2022.3.45f1-base-3` dan
  mengaktivasi **Personal otomatis** dengan `UNITY_EMAIL` + `UNITY_PASSWORD`
  lewat `Unity.Licensing.Client --activate-all --include-personal` (fallback:
  login `unity-editor`). Hasilnya (`Unity_lic.ulf` atau serial Personal)
  dimasukkan ke environment build, lalu seat dikembalikan agar tidak bocor.
  Log aktivasi disaring agar email/password/serial tidak muncul di Actions.
- Lisensi Personal zaman sekarang berupa **seat** (kursi) yang dipegang selama
  build lalu dilepas — bukan file `.ulf` permanen seperti dulu. Karena
  `game-ci/unity-builder@v4` bawaan belum tahu cara ini (ia hanya bisa
  aktivasi serial, yang sudah ditolak Unity untuk Personal), step **"Patch
  unity-builder v4"** menimpa `activate.sh`/`return_license.sh` milik action
  dengan strategi seat Personal (pola dari game-ci/cli PR #246). File
  patch-nya ada di `.github/unity-builder-steps/`.

## Langkah 3 — (Opsional) Fallback: `UNITY_LICENSE` dari .ulf Unity Hub

Kalau aktivasi otomatis bermasalah (misal tidak bisa menonaktifkan 2FA), kamu
bisa menyediakan lisensi manual dari PC:

1. Instal **Unity Hub** di PC, login dengan akun Unity-mu, instal editor
   **2022.3.45f1**, dan pastikan lisensi **Personal** aktif
   (Hub → ⚙ Preferences → **Licenses** → seharusnya ada "Personal").
2. Ambil file lisensinya (`Unity_lic.ulf`) di:
   - **Windows**: `C:\ProgramData\Unity\Unity_lic.ulf`
   - **macOS**: `~/Library/Application Support/Unity/Unity_lic.ulf`
   - **Linux**: `~/.local/share/unity3d/Unity/Unity_lic.ulf`
3. Buka file itu dengan text editor, **copy seluruh isinya**, lalu simpan sebagai
   secret `UNITY_LICENSE` di repo. Selama secret ini terisi, CI memakainya
   langsung dan tidak menjalankan aktivasi otomatis.

Catatan: `.ulf` terikat mesin/akun — bila nanti ditolak Unity (misal editor
di-update), kosongkan secret `UNITY_LICENSE` supaya CI kembali aktivasi otomatis,
atau ulangi langkah ini dengan `.ulf` yang baru.

## Langkah 4 — Jalankan build

Push apa pun yang menyentuh `Assets/`, `Packages/`, `ProjectSettings/`, atau file
workflow `apk_release.yml` (atau jalankan manual workflow **apk-release** lewat
tab Actions → Run workflow). Build pertama ±30–60 menit (download image editor);
berikutnya lebih cepat karena cache `Library`.

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
