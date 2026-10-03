# Stillwater Room (Unity · Android)

Game first-person minimalis di dalam lorong putih yang seolah tidak berujung. Pemain berjalan di jalur beton sisi kiri; di kanan ada kolam tenang yang luas, dengan air bening di tepi dangkal dan dasar batu yang terlihat. Bagian yang makin dalam berangsur gelap. Tidak ada karakter/avatar yang terlihat — kamera berada langsung pada tinggi pandang manusia.

## Dunia dan visual

- Lorong dibangun dari modul 24 m yang terus didaur ulang, jadi perjalanan tidak memiliki ujung dan presisi tetap terjaga.
- Dinding dan plafon porselen putih, sambungan panel tipis, jalur beton bertekstur halus, ambang rendah, serta lampu plafon lembut.
- Air menggunakan shader transparan ringan dengan riak halus dan pantulan lembut; dasar batu terlihat di area dangkal, lalu menyerap cahaya dan menggelap seiring kedalaman.
- Kabut putih menutup perspektif jauh agar koridor terasa tak terbatas.
- Geometri dan material dibuat saat runtime; tidak memerlukan asset world atau model karakter eksternal.

## Kontrol di HP

- **Joystick kiri** — berjalan maju/mundur dan sedikit bergeser di jalur kering.
- **Geser sisi kanan layar** — lihat sekeliling. Bisa digunakan bersamaan dengan joystick.
- Pemain dapat mendekati bibir air, tetapi tetap dibatasi di walkway.

Untuk mencoba di Editor: tekan Play, gunakan **WASD / tombol panah** untuk berjalan dan **klik-kanan + drag** untuk melihat.

## Buka dan build

1. Buka project dengan **Unity 2022.3 LTS** (versi proyek: 2022.3.45f1).
2. Buka `Assets/Scenes/Main.unity`, lalu tekan **Play**.
3. Untuk APK, pilih `File ▸ Build Settings ▸ Android ▸ Switch Platform`, lalu Build. Orientasi Android sudah disetel landscape.

GitHub Actions membangun APK Android dan menerbitkannya ke release `apk-latest`. Setup lisensi Unity Personal untuk CI dijelaskan di [`docs/CARA_SETUP_CI.md`](docs/CARA_SETUP_CI.md). Package ID lama dipertahankan supaya APK baru tetap bisa memperbarui instalasi sebelumnya.

## Struktur utama

```
Assets/
  Scenes/Main.unity                 # kamera, directional light, GameBootstrap
  Scripts/GameBootstrap.cs          # inisialisasi scene first-person
  Scripts/EndlessRoom.cs            # lorong, walkway, air, modul tanpa ujung
  Scripts/FirstPersonRoomController.cs
  Scripts/GameUI.cs                 # joystick + swipe-look
  Resources/Shaders/                # porcelain dan deep still-water
  Tests/SimTests.cs                 # tes room, gerak, batas walkway, dan kamera
```
