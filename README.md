# Infinite Runner — Procedural World Generation (Godot 4.5 / C#)

Third-person infinite runner built on a chunk-streamed procedural terrain system. The world is
generated at runtime from layered simplex passes, populated with obstacles and pickups, and
streamed in and out around the player so memory stays flat no matter how far you run.

> **The repository is named `Unity`, but this is a Godot project.** Nothing here uses Unity.
> The Unity folder that used to sit under `Universal Animation Library 2[Standard]/` has been
> removed — those `.fbx` files were 48 MB of dead weight for a Godot build.

| | |
| --- | --- |
| Engine | Godot **4.5.1** (Mono / .NET **9.0**) |
| Platform target | **Android** (arm64 + armv7) |
| Renderer | Mobile, with FSR upscaling |
| Language | C# (~11k lines across 56 files) |
| CI | GitHub Actions → signed APK + asset packs → GitHub Release |

---

## Getting started

1. Install [Godot 4.5.1 **Mono**](https://godotengine.org/download) and the [.NET 9 SDK](https://dotnet.microsoft.com/download).
2. Open `project.godot` in the Godot editor and let it finish the import pass.
3. Press **F5**. The main scene is `_scenes/bootstrapper.tscn`, which runs the update check
   and then loads `_scenes/main.tscn`.

For a local build without going through CI:

```bash
dotnet build "Procedural Infinite Runner.csproj" -c ExportDebug
godot --headless --export-debug "Android" build/android/InfiniteRunner.apk
```

---

## How the world is generated

```
TerrainManager        decides which chunks exist, and which get destroyed
  └── TerrainChunk    one 50x50 tile: holds a heightmap + its decor
        ├── MapGenerator   blends the noise passes, places world items
        │     ├── Noise.cs           simplex wrapper
        │     ├── PoissonDisc.cs     evenly-spaced object placement
        │     └── delaunayvoronoi/   biome/path boundaries
        └── MeshGenerator  heightmap -> ArrayMesh, with LOD skipping
```

Generation runs on background threads (`Task.Run` in `MeshGenerator` and `MapGenerator`) so the
main thread never stalls while a chunk is built. Chunk saves are optional
(`TerrainManager.SaveTerrainToLocalDisk`) and written as compact `.isl` binary files.

## Character rig and animation

The player model is a VRM anime character driven by the
[Universal Animation Library 2](https://quaternius.com/) clips (CC0).

The two rigs share **no** bone names — the anime model uses VRM `J_Bip_*` naming, the UAL clips
use Unreal-style names (`pelvis`, `spine_01`, `upperarm_l`). `_script/character/AnimeCharacterRig.cs`
retargets between them using two `BoneMap` resources that both resolve onto Godot's
`SkeletonProfileHumanoid`:

```
_models/retarget/bonemap_ual_mannequin.tres   UAL bone names  -> humanoid profile
_models/retarget/bonemap_vrm_anime.tres       VRM bone names  -> humanoid profile
```

That profile round-trip is what lets Godot correct for the two rigs having different rest
orientations. `AnimeCharacterRig` rewrites each clip's track paths through it and installs the
result into the existing `AnimationPlayer`, so the state machine in `_scenes/main_character.tscn`
works unchanged.

Set **`Enabled = false`** on the `AnimeCharacterRig` node to fall back to the original rig.
The clip mapping is an exported `Dictionary` on that node — swap clips in the inspector, no code
changes needed.

**Known gap:** UAL2 *Standard* has no clean walk/run/sprint loop, so `Run` and `Sprint` currently
map to `Walk_Carry_Loop` and `Zombie_Walk_Fwd_Loop` as the closest available clips. Replace them
if you have the Pro pack or author your own.

## Controls (touch)

| Input | Action |
| --- | --- |
| Left half of screen | Floating analog joystick — magnitude controls speed, not just direction |
| Right half of screen | Drag to orbit the camera |
| Push the stick past the outer ring | Sprint |
| On-screen buttons | Jump, attack, jetpack, sit, torch |

Movement is camera-relative: pushing the stick up always walks away from the camera, exactly like
Genshin. See `_script/TouchInputManager.cs`.

## Android signing

The keystore is **not** in this repository. See [`.keystore/README.md`](.keystore/README.md) for
how to add it as a GitHub secret. CI fails loudly rather than generating a throwaway key, because
a new signing key breaks in-place updates for everyone who already has the app.

## Asset delivery

The APK ships small. Heavy assets go out as separate packs published to the GitHub Release:

| Pack | Contents |
| --- | --- |
| `assets_v1.pck` | models, textures, scenes |
| `patch_v1.pck` | scripts and configs only (~1–2 MB) |

`_script/ui/Bootstrapper.cs` reads `version.json`, downloads what is missing, and verifies each
pack against its **sha256** before loading it. A pack whose hash already matches the local copy is
not re-downloaded.

## Project layout

```
_scenes/       .tscn scenes
_script/       C# — gameplay, terrain, UI, core utilities
_models/       GLB models and the retarget bone maps
materials/     shaders (19) and textures
.github/       the Android build workflow
```

## License

The original procedural-terrain code is © Adrien Pierret, MIT (see `_script/SoftwareManager.cs`).
Models and animations from the Universal Animation Library are CC0.
