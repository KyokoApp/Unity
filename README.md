# PoolRooms Mobile (Unity · Android)

Game first-person mandiri untuk HP, terinspirasi dari suasana interior kolam renang liminal **PoolRooms**. Ini bukan mod Lethal Company dan tidak membutuhkan game Lethal Company, BepInEx, DunGen, atau mod PC lain. Lingkungan dibuat ulang sebagai geometri runtime yang ringan untuk Android; repo referensi tidak disalin mentah ke APK.

## Lingkungan

- Ruang utama kolam renang, locker room, shower room, dan atrium dengan planter/palm, tersambung sebagai rangkaian ruang yang terus didaur ulang.
- Keramik biru-abu, lantai basah, pintu antarruang, bangku, locker, shower, pilar, ladder kolam, serta panel lampu langit-langit.
- Air kolam tenang dengan riak dan pantulan halus; bagian dangkal memperlihatkan ubin dasar, sedangkan bagian terdalam menyerap cahaya.
- Kamera first-person tanpa model tubuh/avatar; kontrol joystick dan swipe multi-touch.
- Material dan mesh utama dibuat prosedural, sehingga tidak perlu mengunduh paket asset 772 MB dari proyek mod PC.

Referensi visual/konsep: [rfsheffer/PoolRooms](https://github.com/rfsheffer/PoolRooms), sebuah interior mod Lethal Company. Aplikasi ini tidak menyertakan kode runtime, bundle, atau asset pihak ketiga dari mod tersebut.

## Kontrol HP

- **Joystick kiri** — berjalan maju/mundur dan bergerak ke samping.
- **Geser sisi kanan layar** — melihat sekeliling; bisa dipakai bersamaan dengan joystick.

## Buka dan build

1. Buka project dengan **Unity 2022.3 LTS** (versi proyek: 2022.3.45f1).
2. Buka `Assets/Scenes/Main.unity`, lalu tekan **Play**.
3. Untuk APK, pilih `File ▸ Build Settings ▸ Android ▸ Switch Platform`, lalu Build. Orientasi Android sudah landscape.

[Unduh PoolRooms.apk](https://github.com/KyokoApp/Unity/releases/download/apk-latest/PoolRooms.apk) dari release terbaru. GitHub Actions membangun APK Android tersebut otomatis; setup lisensi Unity Personal untuk CI dijelaskan di [`docs/CARA_SETUP_CI.md`](docs/CARA_SETUP_CI.md). Package ID lama dipertahankan sebagai aplikasi Android yang sama; build baru dimaksudkan untuk menggantikan versi sebelumnya.

## Struktur utama

```
Assets/
  Scenes/Main.unity                 # bootstrap kamera dan lingkungan
  Scripts/GameBootstrap.cs          # konfigurasi mobile dan bootstrap
  Scripts/PoolRoomsEnvironment.cs   # pool, locker, shower, atrium, daur ulang ruang
  Scripts/FirstPersonRoomController.cs
  Scripts/GameUI.cs                 # joystick + swipe-look
  Resources/Shaders/                # tile, air kolam, dan ubin dasar kolam
  Tests/SimTests.cs                 # smoke tests lingkungan dan kontrol
```
