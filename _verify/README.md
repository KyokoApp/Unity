# _verify — arsip verifikasi (histori)

Isi folder ini hanyalah REFERENSI NUMERIK dari era migrasi
three.js → Unity, disimpan untuk memungkinkan verifikasi silang
terhadap port Godot sekarang:

- `world-3km.mjs`, `world-scatter-3km.mjs` — numerik acuan terrain
  & scatter dari game three.js asli (keputusan & konstanta di
  `core/world_data.gd` & `core/world_scatter.gd` dijaga supaya
  cocok dengan ini).
- `dump-js.mjs` — dumper acuan.
- `compare.py` — pembanding keluaran (dipakai ulang manual).
- `verify_rig.py` — pemeriksa rig (hanya referensi; rig Godot dicek
  di `tests/run_tests.gd`).

Berkas-berkas yang engine-specific (C# NUnit runner, stub Unity,
csproj) telah DIHAPUS karena Unity Cloud sudah tidak dipakai di
project ini. Jangan tambahkan file C# baru di sini — tambahan uji
baru sebaiknya merujuk `tests/run_tests.gd`.
