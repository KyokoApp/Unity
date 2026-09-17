# Aurelia — Godot 4

RPG open-world anime bergaya Genshin: dunia prosedural 3 km × 3 km dengan
7 region, terrain streaming, karakter anime beranimasi prosedural
(25 sendi dari port three.js), HUD ala Genshin, siklus siang/malam,
dan target utama **Android**.

Repo ini adalah hasil **migrasi penuh dari Unity 6** — tidak ada
Asset/Packages/ProjectSettings lagi; yang tersisa murni proyek Godot 4.
Lihat **[MIGRASI-GODOT.md](MIGRASI-GODOT.md)** untuk peta yang diporting
sistem-per-sistem, dan **[DESAIN.md](DESAIN.md)** untuk dokumen desain
(yang tidak berubah — dunia & gameplay-nya sama, enginenya saja yang ganti).

## Struktur

```
project.godot        # konfigurasi Godot 4.5+ (renderer Mobile, stretch 1920x1080)
scenes/world.tscn    # akar dunia (semua dibangun dari kode di runtime/world.gd)
core/                # logika MURNI tanpa engine (bisa dites headless):
                     #   js_math, world_data, terrain_surface, terrain_mesh,
                     #   locomotion, combat_state, rig_mapping, world_scatter,
                     #   quality_presets, game_settings, gfx_resolver
shaders/             # 8 shader GLSL: sky, terrain, water, grass, sparkle,
                     #   toon, toon_lite, toon_outline, prop
runtime/             # lapisan engine: motor karakter, rig, kamera orbit,
                     #   streamer chunk (thread latar), rumput MultiMesh, air,
                     #   siklus siang/malam, VFX, orbs, quality applier, dll.
ui/                  # HUD Genshin (dibangun dari kode), stik virtual, loading
tests/               # runner uji headless (godot --headless)
models/              # tempat karakter GLB/VRM hasil konversi (lihat LISENSI)
tools/               # skrip pipeline karakter (bawaan dari era Unity)
site/                # game three.js ASLI (acuan numerik & visual, bukan runtime)
DESIGN               # -> DESAIN.md
```

## Menjalankan

1. Pasang **Godot 4.5+** (versi paling mudah: unduh binary resmi `Godot_*_linux` /
   `Godot_*_windows` / macOS dari godotengine.org — bukan Steam.NET).
2. Buka folder repo ini lewat **Import** di Project Manager → jalan.

   ```bash
   # CLI
   godot --path .
   ```

3. Di HP: ekspor dengan template export Android resmi
   (`editor/install_android_build_template` + preset `export_presets.cfg`
   belum dibuat — buat lewat **Project → Export...** di editor).

## Karakter 3D

`models/` **sengaja kosong** — file karakter ORI punya lisensi
`Redistribution_Prohibited` dan tidak boleh di-commit (lihat
`models/LISENSI.md`, warisan dari proyek Unity). Cara mengisinya:

1. Konversi `AureliaChar.vrm` menjadi `AureliaChar.glb`
   (Blender: import VRM → export glTF, atau pakai addon VRM di Blender).
2. Letakkan di `models/AureliaChar.glb` (ter-`.gitignore`).
3. Jalankan game — `CharacterRig` menemukannya otomatis lewat
   `model_paths`. Kalau file belum ada, dipakai **mannequin cadangan**
   (manusia low-poly kapsul) supaya game tetap bisa dimainkan penuh.

## Uji headless

```bash
godot --headless --path . --script tests/run_tests.gd
```

Runner menjalankan belasan uji determinisme-numerik atas `core/`
(terrain, mesh, lokomosi, combat, mapping tulang, scatter, pengaturan,
resolver kualitas) — kode keluar `0` = semua lulus.

## Kontrol

| Aksi  | Keyboard/Touch                          |
|-------|-----------------------------------------|
| Jalan | WASD / panah / stik kiri-bawah virtual  |
| Lari  | Shift (atau stik didorong penuh)        |
| Lompat| Space (tombol JMP)                      |
| Dash  | Ctrl atau X (tombol DSH)                |
| Serang| Klik kiri (tombol ATK) — kombo 3x       |
| Skill | tombol E · Ultimate tombol Q (HUD)      |
| Kamera| seret sisi kanan layar / tombol kanan   |
| Menu  | tombol "=" kiri atas → pengaturan       |

## Status CI

`godot-tests` (GitHub Actions) berjalan headless di setiap push ke
`arena/01a0ac44-unity`: mengunduh Godot 4.5.1, mengimpor proyek, lalu
menjalankan `tests/run_tests.gd`. Status terkini: **157/157 lulus**.
