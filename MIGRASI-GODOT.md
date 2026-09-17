> **USANG (2026-09-17):** digantikan `CATATAN-SESI-BARU.md` — file ini tercatat di daftar hapus §7 dokumen itu.

# MIGRASI → GODOT 4

Dokumen ini memetakan **sistem demi sistem** dari proyek Unity 6
(`KyokoApp/Unity`, branch sebelum migrasi) ke proyek Godot 4 di repo ini.
Tujuan: membuktikan migrasi tuntas, bukan setengah-setengah — dan menjadi
acuan bila perilaku terlihat miring dibanding versi Unity.

## Prinsip yang diwariskan utuh

1. **Kontrak fidelitas numerik** (DESAIN.md): `core/` di Godot adalah port
   1:1 dari `Assets/_Project/Scripts/Core/`, yang sendiri sudah diuji
   paritas terhadap game three.js aslinya (`site/`). Urutan RNG, konstanta,
   dan matematika tidak berubah — hanya bahasanya jadi GDScript.
2. **Pure core**: tidak ada `Object`/engine di `core/`, persis pola C#.
   Semua pengujian di `tests/run_tests.gd` jalan headless.
3. **Scene dari kode**: scene Unity dibangun oleh `Stage2SceneBuilder`;
   di Godot cara setara dipakai — `scenes/world.tscn` cuma akar, seluruh
   dunia dibangun `runtime/world.gd`.
4. **Aturan angka tidak dikarang**: semua angka (kecepatan 6,5/13,5 m/s,
   dash 0,18 dtk, kuota 25 chunk awal, dsb.) disalin dari kode Unity.

## Peta sistem

| Unity (sebelum) | Godot (sekarang) | Catatan paritas |
|---|---|---|
| `JsMath.cs` | `core/js_math.gd` | helper lerp/smooth/hash ditiru |
| `WorldData.cs` (+`ChunkRng`) | `core/world_data.gd` (+`ChunkRng`) | terrain_h, road_*, region, chunk_plan |
| `TerrainSurface.cs` | `core/terrain_surface.gd` | warna verteks |
| `TerrainMesh.cs` | `core/terrain_mesh.gd` | grid chunk, indeks, normal |
| `Locomotion.cs` (25-joint SamplePose) | `core/locomotion.gd` | put-callback → Dictionary pose |
| `CombatState.cs` | `core/combat_state.gd` | kombo 3x, stamina, dash cost |
| `RigMapping.cs` | `core/rig_mapping.gd` | 25→23 slot, kandidat nama tulang |
| `WorldScatter.cs` | `core/world_scatter.gd` | pohon/batu + 12 orb + colliders |
| `Quality`+`Settings`+`GfxResolver` | `quality_presets.gd`, `game_settings.gd`, `gfx_resolver.gd` | Dictionary tetap, normalize, AdaptiveResolution |
| `SettingsStore.cs` (PlayerPrefs) | `runtime/settings_store.gd` | **ConfigFile `user://aurelia_settings.cfg`** |
| `BootLog.cs` | `runtime/boot_log.gd` | log boot → `user://aurelia-boot.log` |
| `CharacterMotor.cs` | `runtime/character_motor.gd` | gerak, coyote, buffer, dash, pose tap |
| `CharacterRig.cs` + `Mannequin*` | `runtime/character_rig.gd`, `runtime/mannequin.gd` | bind pose, ARM FIX T-pose, smoothing |
| virtual tulang VRM | `runtime/mannequin.gd` (MannequinBody fallback) | GLB via `res://models/*.glb` |
| `CameraRig.cs` | `runtime/camera_rig.gd` | orbit, shake, FOV sprint, jepit terrain |
| `TerrainChunkStreamer.cs` | `runtime/terrain_chunk_streamer.gd` | worker Thread + Mutex/Semaphore, pool ArrayMesh, props MultiMesh |
| `GrassField.cs` (DrawMeshInstanced) | `runtime/grass_field.gd` | cache sel 8 m, LOD 2 tingkat, MultiMesh |
| `WaterPlane.cs` | `runtime/water_plane.gd` | quad 1 segmen, snap-follow |
| `AnimeVFX.cs` | `runtime/anime_vfx.gd` | sparkle MultiMesh billboard-shader |
| `Orbs.cs` | `runtime/orbs.gd` | 12 orb dari WorldScatter, bob sinus |
| `DayNightCycle.cs` | `runtime/day_night_cycle.gd` | 8 keyframe → sun + fog + ambient + langit |
| `QualityApplier.cs` (URP) | `runtime/quality_applier.gd` | `viewport.scaling_3d_scale`, shadow atlas, fog globals, adaptive res |
| `GenshinHud`+`UiKit`+`VirtualJoystick`+`HudInput` | `ui/game_hud.gd`, `ui/ui_kit.gd`, `ui/virtual_joystick.gd` | HUD dari kode, stik mengambang, kompas, stamina, skill |
| `LoadingScreen.cs` | `ui/loading_screen.gd` | tips, bar kemajuan, spinner |
| `WorldBoot.cs` (+ BuildWorld) | `runtime/world.gd` | boot sinkron 25 chunk + rumput → loading → input nyala |
| `PerfHud.cs` | `runtime/perf_hud.gd` | overlay stats |

## Peta shader (7 HLSL → 8 Godot)

| URP ShaderGraph/HLSL | Godot `.gdshader` | Strategi |
|---|---|---|
| `AureliaSky.shader` | `aurelia_sky.gdshader` | `shader_type sky`, gradien EYEDIR + disc matahari |
| `AureliaTerrain.shader` | `aurelia_terrain.gdshader` | vertex color × noise 2 oktaf, half-Lambert posterize, `light()` custom |
| `AureliaWater.shader` | `aurelia_water.gdshader` | unshaded, gelombang fragment, fresnel + spec band + glitter |
| `AureliaGrass.shader` | `aurelia_grass.gdshader` | angin di vertex 2 gelombang, dist-sink exact ruang model |
| `AureliaSparkle.shader` | `aurelia_sparkle.gdshader` | additive, billboard via INV_VIEW_MATRIX, warna instance |
| `AureliaToon.shader` | `aurelia_toon.gdshader` | diffuse bertingkat + bayangan berwarna + rim + spec anime |
| `AureliaToon.shader` (Lite) | `aurelia_toon_lite.gdshader` | varian wajah transparan, tanpa rim/spec/outline |
| `AureliaToon.shader` (Pass "Outline") | `aurelia_toon_outline.gdshader` | inverted-hull `cull_front`, next_pass |
| *(materi prop generik)* | `aurelia_prop.gdshader` | tint per jenis + warna foliage per instance (Tahap 4) |

Uniform global semua shader (`aurelia_fog_color/near/far`,
`aurelia_sun_color/direction`, `aurelia_ambient_color`) dideklarasikan di
`project.godot [shader_globals]` dan diputakhirkan `DayNightCycle.apply()`
+ `QualityApplier` per frame.

## Perbedaan sadar (dan alasannya)

- **Model VRM masih os eksternal**: lisensinya tidak berubah; Godot di sini
  membaca GLB hasil konversi di `models/` (`.gitignore`-d), sama seperti
  Unity membaca prefab UniVRM lokal. Lihat `models/LISENSI.md`.
- **Tidak ada Unity → semua workflow editor hilang**: skrip Editor/
  (`Stage2SceneBuilder`, `AureliaBuildPreprocessor`, dsb.) tidak diport.
  Fungsinya digantikan pembangunan kode dari `runtime/world.gd`.
- **Post process URP Volume → Environment.glow** (bloom), tanpa motion
  blur (renderer Mobile tidak punya; opsinya tetap ada di panel).
- **`_verify/` C# dihapus**: statusnya verifikasi era Unity;
  uji sekarang di `tests/run_tests.gd` + referensi JS di `_verify/world-*.mjs`
  (kept, tidak engine-terikat).

## Lisensi & pihak ketiga

- Font & aset gambar tidak dipakai (HUD 100% prosedural), sama seperti
  proyek Unity.
- Karakter `AureliaChar`: tidak di-commit — lihat `models/LISENSI.md`.
- Godot Engine sendiri berlisensi MIT.
