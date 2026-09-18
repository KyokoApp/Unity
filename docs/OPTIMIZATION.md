# Optimasi Android — apa yang sudah ada, apa yang belum

Semua angka dan nama file di bawah hasil pembacaan repo pada commit `1363060`, bukan perkiraan.

---

## Sudah terpasang (jangan diulang)

Ini sudah benar di `project.godot`:

| Setting | Nilai | Kenapa bagus |
| --- | --- | --- |
| `renderer/rendering_method` | `mobile` | Forward+ terlalu berat untuk HP |
| `scaling_3d/mode` | `1` (FSR) | Render di 0.9x lalu upscale — hemat fillrate |
| `occlusion_culling/use_occlusion_culling` | `true` | Chunk di balik bukit tidak digambar |
| `textures/vram_compression/import_etc2_astc` | `true` | Format native Android, bukan S3TC |
| `directional_shadow/size` | `1024` | 2048/4096 akan membebani bandwidth |
| `msaa_3d` | `0` | Benar — MSAA di tiler GPU sangat mahal |
| `mesh_lod/lod_change/threshold_pixels` | `3.0` | LOD mesh terrain aktif |
| `physics_ticks_per_second` | `60` | Standar |

Plus: generasi terrain sudah jalan di thread background (`Task.Run`), dan ada `water_mobile.gdshader`
khusus mobile. Fondasinya sudah bagus.

---

## Belum terpasang — urut dari dampak terbesar

### 1. Belum ada object pooling untuk mob & crate

`_script/MobManager.cs:182` memanggil `Mob.Instantiate()` dan `:220` memanggil `mob.QueueFree()`.
`_script/MainCharacter.cs` melakukan hal yang sama untuk crate (`Cube.Instantiate()` / `crate.QueueFree()`).

Di Godot, instantiate + free sebuah scene 3D dengan collision shape itu **mahal** dan memicu GC.
Di HP kelas menengah ini penyebab stutter paling umum.

```csharp
// Simpan yang sudah mati, pakai ulang alih-alih free
private readonly Queue<CharacterMob> _pool = new();

private CharacterMob Rent()
{
    if (_pool.Count > 0)
    {
        var m = _pool.Dequeue();
        m.ProcessMode = ProcessModeEnum.Inherit;
        return m;
    }
    return Mob.Instantiate<CharacterMob>();
}

private void Return(CharacterMob m)
{
    m.ProcessMode = ProcessModeEnum.Disabled;
    _pool.Enqueue(m);
}
```

**Perkiraan dampak:** menghilangkan sebagian besar hitch saat spawn/despawn.

### 2. `UpdateHelpers()` alokasi string setiap frame

`_script/MainCharacter.cs` — `UpdateHelpers()` dipanggil dari `_Process()` dan setiap frame
membangun string baru (`CharacterName + "\n" + TerrainManager.Instance.CameraInChunk()`) lalu
memanggil `PopupInfo.SetText(text)`.

Ini 60 alokasi string per detik + redraw label, untuk teks yang isinya hampir tidak pernah berubah.

```csharp
private string _lastHelperText;

public void UpdateHelpers(float deltaFloat)
{
    string text = CharacterName + "\n" + TerrainManager.Instance.CameraInChunk();
    if (text == _lastHelperText) return;   // hanya update kalau benar-benar berubah
    _lastHelperText = text;
    ...
}
```

Lebih baik lagi: teks ini adalah **debug overlay** (nama karakter + koordinat chunk). Matikan
sepenuhnya di build release lewat `SoftwareManager.Build`.

### 3. Mipmaps belum konsisten

Cek `*.png.import`:

- `materials/textures/br/logo.png` — mipmaps **off**
- `materials/ui/compass.png` — mipmaps **off**
- `icon.png` — off (ini benar, memang 2D UI)

Untuk tekstur yang dipakai di 3D, mipmap off berarti GPU sampling dari resolusi penuh saat objek
jauh → cache miss dan shimmering. Untuk UI 2D, off memang benar.

`logo.png` dipakai di mana perlu dicek; kalau masuk material 3D, nyalakan.

### 4. Shadow map directional belum di-tune untuk jarak

`_scenes/world.tscn:209` punya `shadow_enabled = true` untuk matahari, dan
`directional_shadow/size=1024`. Yang belum diatur: **`directional_shadow/max_distance`**.

Default Godot 100 unit. Untuk infinite runner, pemain hanya perlu bayangan ~30–40 unit di
sekitarnya. Menurunkan `max_distance` ke 40 membuat texel 1024px itu mencakup area 6x lebih kecil
→ bayangan jauh lebih tajam **dengan ukuran texture yang sama**.

```
rendering/lights_and_shadows/directional_shadow/max_distance=40
```

### 5. `ViewingDistance = 3` chunk — perlu diuji per device

`_script/terrain/TerrainManager.cs:33`. Setiap chunk = 50x50 verteks mesh + decor + collision.
Viewing distance 3 berarti ~49 chunk aktif.

Saran: expose sebagai setting grafis (kamu sudah punya `GraphicsSettingsManager.cs`) dengan preset
Low=2 / Medium=3 / High=4, dan turunkan otomatis kalau FPS < 30 selama 3 detik berturut-turut.

### 6. Collision untuk terrain

Kalau setiap chunk punya `StaticBody3D` + collision shape penuh, itu berat di memory dan di
physics broadphase. Untuk infinite runner yang lintasannya terprediksi, pertimbangkan:

- collision hanya untuk chunk di `ViewingDistance <= 1`
- chunk jauh cukup visual, tanpa collision

Cek `TerrainChunk` — kalau collision dibuat untuk semua chunk, ini penghematan besar.

### 7. `GD.Print` di jalur panas

Ada 23 `GD.Print` di `TerrainChunk.cs` dan 21 di `MapGenerator.cs`. Sebagian besar sudah
dikomentari, tapi yang aktif (mis. `TerrainChunk.cs:362` di dalam loop item) tetap jalan di build
release.

Di Android, `GD.Print` menulis ke logcat lewat IPC — itu **sinkron dan lambat**. Bungkus:

```csharp
[System.Diagnostics.Conditional("DEBUG")]
public static void Log(string msg) => GD.Print(msg);
```

atau cek `SoftwareManager.Build == BuildTypes.DEVELOPER`.

### 8. Ukuran model anime 19 MB

`_models/anime_character.glb` = 19 MB, dengan 3 mesh (Face, Body, Hair) dan 129 joint.
Yang bisa dilakukan:

- **Draco / meshopt compression** saat export dari Blender — biasanya memangkas 60–70%.
- Tekstur VRM biasanya 2048px atau 4096px. Untuk HP, 1024px cukup untuk karakter yang tidak
  pernah memenuhi layar.
- 77 dari 129 joint adalah bone sekunder (`J_Sec_Hair*`, `J_Sec_*Skirt*`, `J_Sec_*Bust*`).
  Kalau physics rambut/rok tidak dipakai, hapus bone itu di Blender → skinning jauh lebih murah.

### 9. `anime_character.glb` belum di-dekode saat runtime

Model ini baru di-mount saat `_Ready()` lewat `AnimeCharacterRig`. Artinya 19 MB di-load dan
di-retarget tepat saat scene dibuka — itu jeda yang terlihat.

Saran: panggil `ResourceLoader.LoadThreadedRequest("res://_models/anime_character.glb")` dari
`Bootstrapper` (yang sudah punya loading screen), lalu `LoadThreadedGet()` saat dibutuhkan.
Loading screen-mu jadi berguna untuk sesuatu.

---

## Ringkasan prioritas

| # | Item | Effort | Dampak |
| --- | --- | --- | --- |
| 1 | Object pooling mob & crate | sedang | **tinggi** |
| 2 | Hentikan alokasi string per frame | kecil | sedang |
| 4 | `directional_shadow/max_distance=40` | **satu baris** | sedang |
| 7 | Bungkus `GD.Print` | kecil | sedang |
| 5 | Viewing distance per preset | sedang | **tinggi** |
| 6 | Collision hanya chunk dekat | sedang | **tinggi** |
| 8 | Kompresi model anime | sedang | sedang |
| 9 | Preload model di loading screen | kecil | sedang (persepsi) |
| 3 | Mipmaps konsisten | kecil | rendah |

Yang paling murah dengan hasil langsung: **#4** (satu baris di `project.godot`).
