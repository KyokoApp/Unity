# BACA INI — Ronde-38: SERANG dengan bola api

## Yang berubah
- Tombol **🔥 SERANG** tampil di kanan layar. Ketuk untuk satu tembakan atau
  tahan untuk menembakkan bola api beruntun setiap 0,26 detik.
- Proyektil memiliki inti plasma, selubung/ekor api, halo, cahaya dan partikel.
  Saat mengenai tanah/objek, proyektil menghasilkan ledakan, shockwave, bekas
  gosong, kilat, asap, bara, percikan, camera shake, dan suara prosedural.
- Arah tembakan mengikuti arah gerak terakhir; sebelum bergerak, arah kamera.
  SPASI atau F dapat dipakai untuk menembak saat pengujian desktop.
- Pengaturan “Ukuran analog” kini mengatur **analog & tombol**. Bug sentuhan
  tombol yang sekaligus memulai usap kamera juga telah diperbaiki.

## File efek baru
- `project/packs/character_player/fire_bolt.gd`
- `project/packs/character_player/fire_explosion.gd`
- `project/packs/character_player/fire_fx.gd`
- `project/packs/character_player/shockwave.gdshader`
- `project/packs/audio_sfx/fire_shoot.wav`
- `project/packs/audio_sfx/fire_explode.wav`

Semua visual dan audio baru dibuat prosedural tanpa aset eksternal. Audio dapat
regenerasi dengan `python3 tools/synth_fire.py`; hasil `fire_loop.wav` lama tetap
identik byte-per-byte karena setiap suara memakai seed terpisah.

## Supaya masuk ke HP
Merge ke `main` memicu workflow **apk-release**, membangun pack baru, lalu
menerbitkannya ke branch `content`. Tutup game sampai benar-benar mati, lalu
buka lagi agar update pack terunduh.

**BELUM DIUJI DI PERANGKAT.** Sandbox tidak dapat menjalankan Godot; pemeriksaan
yang dilakukan adalah parse GDScript, cek semantik ringan, dan review API 4.5.
