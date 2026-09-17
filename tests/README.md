# tests/ — uji headless

`run_tests.gd` adalah runner uji murni atas seluruh `core/` (dan
potongan runtime yang tidak menyentuh GPU):

```bash
godot --headless --path . --script tests/run_tests.gd
```

Kode keluar `0` = semua lulus, `1` = ada kegagalan (daftar dicetak).

Cakupan (singkat):

- **WorldData**: determinisme terrain_h, 7 region, waypoint, rencana chunk.
- **TerrainMesh**: jumlah verteks/indeks/warna untuk quads=8 + tolak
  quads>MAX.
- **Locomotion**: 25 kunci pose lengkap & finite, joystick deadzone,
  damp konvergen.
- **CombatState**: kombo ditolak mid-swing, stamina dash/regen.
- **RigMapping**: resolve → 23 slot, twist A+B menjumlahkan LOWLEG.
- **WorldScatter**: determinisme, 12 orb unik, collider hanya chunk dekat.
- **Settings**: normalisasi batas, preset bolak-balik ↔ pendeteksi.
- **GfxResolver**: fog far>near, adaptive resolution turun saat berat.
- **Motor**: damp_angle menangani ekstrem sudut.

Kalau menambah aturan baru di `core/`, tambahkan ujinya di sini supaya
kontrak fidelitas (DESAIN.md) tetap terpantau headless.
