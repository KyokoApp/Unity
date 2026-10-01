# Setup CI Arpg (sekali saja)

Workflow `.github/workflows/apk_release.yml` membuat APK Android dan paket
AssetBundle untuk release GitHub. APK tetap memakai application ID lama
`com.kyokoapp.ual2playground`; nama yang terlihat di Android adalah **Arpg**.

## 1. Lisensi Unity untuk GitHub Actions

Unity Personal gratis. Workflow memakai aktivasi seat Personal otomatis melalui
`Unity.Licensing.Client`; siapkan repository secrets berikut:

| Secret | Isi | Wajib |
| --- | --- | --- |
| `UNITY_EMAIL` | Email akun Unity | Ya |
| `UNITY_PASSWORD` | Password akun Unity | Ya, kecuali memakai `.ulf` |
| `UNITY_LICENSE` | Seluruh isi file `.ulf` dari Unity Hub | Opsional; fallback tanpa login |

Untuk jalur otomatis, akun Unity tidak boleh meminta langkah 2FA interaktif.
Jangan tulis password atau isi license ke file yang di-commit. Detail proses
aktivasi ada di `.github/workflows/apk_release.yml` dan helper
`.github/unity-builder-steps/`.

## 2. Signing key Android yang stabil — WAJIB sebelum menerbitkan APK

Android hanya mengizinkan APK mengganti instalasi lama jika **application ID dan
sertifikat signing sama**. Karena itu, siapkan **satu keystore release**, simpan
backup aman, dan gunakan key yang sama untuk semua build. Jangan membuat key baru
setiap rilis dan jangan commit file keystore ke Git.

Jika sudah ada keystore yang menandatangani APK Arpg sebelumnya, gunakan file dan
password yang sama. Jika belum pernah ada keystore rilis, buat sekali di komputer
tepercaya dengan JDK:

```sh
keytool -genkeypair -v \
  -keystore arpg-release.keystore -storetype JKS \
  -alias arpg -keyalg RSA -keysize 2048 -validity 10000
```

Simpan file tersebut beserta password keystore, nama alias (`arpg` pada contoh),
dan password alias di tempat aman/offline. **Kehilangan keystore berarti APK
selanjutnya tidak bisa memperbarui instalasi yang ditandatangani dengannya.**

Tambahkan empat repository secrets pada **GitHub → Settings → Secrets and
variables → Actions**:

| Secret | Isi |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | File keystore yang sama, dikodekan Base64 tanpa line break |
| `ANDROID_KEYSTORE_PASS` | Password keystore |
| `ANDROID_KEYALIAS_NAME` | Nama alias, misalnya `arpg` |
| `ANDROID_KEYALIAS_PASS` | Password alias |

Encoding Base64:

```sh
# Linux
base64 -w0 arpg-release.keystore

# macOS
base64 < arpg-release.keystore | tr -d '\n'
```

Di Windows PowerShell:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes('arpg-release.keystore'))
```

Salin hasilnya hanya ke secret `ANDROID_KEYSTORE_BASE64`. Workflow akan berhenti
lebih awal bila salah satu secret signing kosong, agar tidak menerbitkan APK
ber-tanda tangan debug secara tidak sengaja. Karena build memakai metode kustom
`CiBuild.BuildAll`, metode itu juga menerapkan sendiri argumen signing GameCI ke
`PlayerSettings` dan memeriksa file keystore; build gagal tertutup jika nilai
atau file tidak tersedia.

> **Catatan migrasi instalasi lama:** konfigurasi proyek sebelumnya tidak
> mengaktifkan custom keystore, sehingga tanda tangan APK lama belum dapat
> diverifikasi dari checkout ini. Jika APK lama ditandatangani dengan sertifikat
> yang berbeda dari keystore yang sekarang disiapkan, Android akan menolak
> pembaruan langsung. Gunakan kembali keystore lama bila tersedia; bila tidak,
> perangkat mungkin perlu memasang ulang APK sekali. ID aplikasi tetap sama,
> tetapi tanda tangan lama tidak dapat dipulihkan dari APK.

## 3. Build dan release

Push ke `main` atau `arena/01a0f7e5-unity`, atau jalankan workflow
**apk-release** melalui tab **Actions → Run workflow**. Build menggunakan Unity
2022.3, IL2CPP, ikon anime CC0 dari `Assets/Branding/ArpgIcon.png`, serta nama
produk `Arpg`.

Workflow mengunggah APK lebih dahulu, lalu paket konten ber-hash, dan manifest
konten paling akhir. Dengan demikian manifest lama tetap menunjuk aset lama yang
masih tersedia sampai semua aset baru terbit:

- **`apk-latest`** — `Arpg.apk` (alias terbaru) dan APK bernama versi, misalnya `Arpg-1.0.42.apk`. Manifest in-game menunjuk ke file versi yang tidak berubah.
- **`content-latest`** — `manifest.json`, file tuning ber-hash, serta AssetBundle
  ber-hash untuk ID `arpg-character` dan `arpg-world`. Nama aset mengikuti
  `{id}-{sha256}.bundle`; konten lama tidak ditimpa, sehingga cache/link tetap
  valid saat rilis berlangsung. Release konten ditandai pre-release agar APK
  tetap menjadi release utama.

`arpg-character` membawa model mannequin dan animasi UAL2; `arpg-world` membawa
prefab/tekstur dunia. Bundle dibangun untuk Android oleh `CiBuild.BuildAll`.
Assets bawaan `Resources` tetap berada di APK sebagai fallback offline. Cache
bundle yang terverifikasi dipakai sejak game mulai; konten yang baru selesai
diunduh aktif saat Arpg dibuka lagi.

## 4. Pembaruan dari dalam game

Saat berjalan, Arpg mengecek `content-latest/manifest.json` melalui HTTPS.
Perubahan animasi/visual diunduh ke penyimpanan aplikasi dan diverifikasi dengan
SHA-256; game tidak perlu memasang APK baru untuk paket tersebut. Jika manifest
menawarkan versi aplikasi yang lebih baru, tombol **Unduh & Pasang Update**
akan muncul di UI. Game mengunduh APK, memeriksa ukuran dan SHA-256, lalu membuka
installer Android.

Pemasangan APK **tidak senyap**: Android dapat meminta izin “install unknown
apps” untuk Arpg dan tetap meminta persetujuan pengguna pada layar pemasangan.
Perubahan kode C# atau Player tetap memerlukan APK baru; paket remote ditujukan
untuk aset visual, model, tekstur, dan animasi.

Jika internet tidak tersedia, game tetap berjalan memakai APK dan konten cache.
