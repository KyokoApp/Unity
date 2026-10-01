# Arpg (Unity, Android)

Game third-person Android dengan pulau eksplorasi dan kontrol sentuh:

- Pulau deterministik 200 × 200 m: plaza, jalan, bukit/tebing, danau, sungai,
  pantai, rumput prosedural ber-streaming, dan nature kit Kenney (CC0).
- Model dan 43 animasi **Universal Animation Library 2 [Standard]** dari
  Quaternius (CC0), ditambah tiga clip lokomosi UAL1.
- Analog kiri untuk bergerak; tombol lompat, serang, slide, sprint, ganti model,
  dan panel animasi; geser sisi kanan layar untuk memutar kamera.
- Splash `Arpg` dengan progress bar tipis di bagian bawah.

## Update konten dan APK dari dalam game

- `arpg-character` memuat model/animasi; `arpg-world` memuat visual dunia.
  Keduanya dibangun menjadi Android AssetBundle dan diterbitkan di release
  GitHub `content-latest`. Cache yang lolos pemeriksaan SHA-256 dipakai saat
  Arpg dibuka; file bawaan APK tetap jadi fallback offline.
- Jika tersedia versi APK baru, tombol dalam game mengunduh APK versi dari
  release `apk-latest`, memverifikasi hash, lalu membuka installer Android. Android tetap dapat
  meminta izin sumber instalasi dan konfirmasi pemasangan—tidak ada instalasi
  senyap.
- Application ID tetap `com.kyokoapp.ual2playground`, supaya APK bertanda
  tangan sama dapat memperbarui instalasi yang ada.

Sebelum CI dapat menerbitkan APK release, siapkan **satu signing keystore
permanen** dan empat secrets Android. Lihat
[`docs/CARA_SETUP_CI.md`](docs/CARA_SETUP_CI.md) untuk lisensi Unity, signing,
backup keystore, dan catatan kompatibilitas APK lama.

## Buka proyek di Unity

1. Instal Unity Hub + Unity **2022.3 LTS** dengan Android Build Support
   (SDK/NDK/OpenJDK).
2. Tambahkan folder repo ini melalui Unity Hub dan tunggu impor awal.
3. Untuk aset generated saat Play di Editor, jalankan menu **Assets → Impor
   World Nature (Kenney CC0)** dan **Assets → Ekstrak Clip Lokomosi UAL1**.
   Workflow CI menjalankannya otomatis; folder hasilnya di-gitignore.
4. Buka `Assets/Scenes/Main.unity` lalu tekan Play.

## CI dan release GitHub

Push ke `main` atau `arena/01a0f7e5-unity` untuk menerbitkan APK ke
`apk-latest`, lalu manifest dan AssetBundle ke `content-latest`; sesudah build,
workflow menjalankan audit PlayMode. Dari tab Actions, workflow **apk-release**
juga bisa dijalankan manual dengan mode `sim-test` untuk audit saja (tanpa
menerbitkan APK). Screenshot dan laporan tes diunggah sebagai artifact.

Application ID tidak diubah. Untuk memperbarui APK lama, sertifikat signing
harus sama; jika instalasi lama memakai sertifikat berbeda, Android tidak bisa
memasang build baru di atasnya. Jangan pernah mengganti atau kehilangan
keystore permanen yang digunakan untuk rilis.

## Sumber dan lisensi

- Ikon anime: **Red suit anime girl**, karya jsks (sumber Pixabay), CC0 1.0.
  Atribusi dan tautan ada di `Assets/Branding/ASSET_CREDITS.md`.
- Model/animasi: Quaternius, Universal Animation Library 2 [Standard], CC0 1.0.
- Nature assets: Kenney Nature Kit, CC0 1.0.
