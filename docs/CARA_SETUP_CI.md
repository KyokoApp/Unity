# Cara setup auto-build APK (sekali saja)

Build Unity di GitHub Actions membutuhkan lisensi Unity. Unity Personal gratis; workflow repo ini mengaktivasi lisensi sementara selama build.

## 1. Siapkan akun Unity

1. Buat atau gunakan akun gratis di https://unity.com.
2. Workflow login non-interaktif. Jika aktivasi akun gagal karena prompt keamanan/2FA, gunakan fallback file lisensi `.ulf` pada Langkah 3.

## 2. Tambahkan repository secrets

Buka **GitHub → Settings → Secrets and variables → Actions** lalu tambahkan:

| Secret | Isi | Wajib |
|---|---|---|
| `UNITY_EMAIL` | Email akun Unity | Ya untuk aktivasi otomatis |
| `UNITY_PASSWORD` | Password akun Unity | Ya untuk aktivasi otomatis |
| `UNITY_LICENSE` | Isi lengkap file lisensi `.ulf` | Opsional, fallback |

Jika `UNITY_LICENSE` tersedia, workflow menggunakannya langsung. Jika kosong, workflow memakai `UNITY_EMAIL` + `UNITY_PASSWORD` untuk aktivasi Unity Personal sementara melalui Unity Licensing Client.

## 3. Fallback lisensi dari Unity Hub

Jika aktivasi otomatis tidak tersedia, login di Unity Hub, pastikan lisensi Personal aktif, lalu salin isi `Unity_lic.ulf` ke secret `UNITY_LICENSE`.

Lokasi umum:

- Windows: `C:\ProgramData\Unity\Unity_lic.ulf`
- macOS: `~/Library/Application Support/Unity/Unity_lic.ulf`
- Linux: `~/.local/share/unity3d/Unity/Unity_lic.ulf`

## 4. Jalankan build

Push perubahan pada `Assets/`, `Packages/`, atau `ProjectSettings/`, atau jalankan workflow **Android APK** secara manual melalui tab **Actions → Run workflow**.

Workflow membangun `build/Android/PoolRooms.apk` lalu mengunggah APK terbaru ke release `apk-latest`. Game PoolRooms ini mandiri untuk Android; tidak membutuhkan Lethal Company, BepInEx, DunGen, atau pengunduhan konten tambahan saat dijalankan.
