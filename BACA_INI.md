# BACA INI — Ronde-41: kubus murni, percikan gesekan, monster kubus, kamera awal

## Alur repository

- Remote `origin` sudah dicek sebelum ronde ini. Tidak ada branch remote
  `arena/*-unity` lain yang punya pekerjaan untuk di-merge ke `main`; branch
  yang tersedia hanya branch sesi ini di remote.
- Branch sesi tetap `arena/01a0dca7-unity`.
- Tidak merge ke `main` dan tidak menutup PR.
- Workflow sudah mendaftarkan `arena/01a0dca7-unity` di bagian
  `on.push.branches`, sehingga push konten dari branch ini membangun dan
  menerbitkan delta ke branch `content`.

## Koreksi sesuai feedback ronde ini

### Pemain

- `player.gd` sekarang hanya membuat **satu BoxMesh kubus**. Tidak ada visor,
  kaki, stripe, aura, lampu, ground glow, atau efek api yang mengambang.
- Kubus diletakkan tepat di atas tanah: origin karakter berada di y=0 dan
  visual kubus berada di y=0,50 dengan tinggi 0,92 m.
- Collision player di `player.tscn` diturunkan ke pusat kubus agar tidak tampak
  melayang.
- Kecepatan tetap cepat di 10,5 m/s sesuai permintaan ronde sebelumnya.

### Percikan api dari gesekan

- Partikel `GroundFrictionSparks` hanya aktif saat kubus benar-benar bergerak.
- Titik emisi berada di bawah dan sedikit di belakang kubus, bukan di tengah
  badan.
- Percikan kecil, lifetime 0,30 detik, menyebar sempit mengikuti arah
  berlawanan gerak, memiliki gravitasi bumi -9,8, damping, dan variasi
  kecepatan. Hasilnya adalah percikan pendek seperti gesekan roda/kubus dengan
  tanah, bukan aura api.

### Monster

- Semua bentuk monster lama dihapus: tidak ada lagi slime, golem, bat,
  mushroom, crawler, sayap, kaki, atau bentuk organik.
- Seluruh roster sekarang adalah kubus kecil yang sama, ukuran sekitar 0,52–0,60
  m, berjalan di bidang tanah y=0, mengejar pemain tanpa terbang atau melompat.
- Setiap kubus kecil memiliki dua mata kubus merah menyala. Perbedaan hanya
  HP, damage, dan kecepatan agar gameplay tetap bervariasi tanpa mengubah
  bentuk visual.
- Hitbox dan damage tetap ada, begitu juga fire bolt dapat mengenai kubus.

### Kamera

- Auto-follow yaw yang sebelumnya memutar kamera mengikuti arah lari dihapus.
- Kamera dikembalikan ke perilaku awal third-person: SpringArm mengikuti posisi
  pemain dengan smoothing, sedangkan arah kamera hanya berubah dari swipe/look.
- Jarak kamera dikembalikan ke 8,5 m dan smoothing ke 7,0.

## Verifikasi

- Jalankan lokal:
  - `gdparse` semua 18 file GDScript: harus bersih.
  - `python3 tools/analyze_checks.py /home/user/Unity`: harus `BERSIH ✓`.
  - `git diff --check`.
- Build APK/PCK penuh dijalankan oleh GitHub Actions setelah push. `Godot` tidak
  tersedia di sandbox lokal, jadi `tools/run_all_tests.sh` lokal tidak dapat
  melakukan export.

## Cara test di HP

1. Tutup game sepenuhnya.
2. Buka lagi agar launcher mengunduh delta `character_player` dan
   `world_terrain` terbaru.
3. Gerakkan kubus: pastikan badan tetap kotak dan menapak, lalu percikan keluar
   dari bagian bawah-belakang kubus.
4. Diamkan kamera: arah kamera tidak otomatis berputar mengikuti gerakan.
5. Dekati musuh: semua musuh harus tampak sebagai kubus kecil bermata merah.
