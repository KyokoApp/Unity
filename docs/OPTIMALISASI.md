# Optimalisasi Performa & Satu Layar Loading

Catatan perubahan performa (target: gameplay mobile smooth ~60fps), penyatuan
layar loading, dan penghapusan splash Godot. Dokumen ini melengkapi
`SISTEM_UPDATE.md` (sisi unduhan/paket).

## Ringkasan perubahan

| Area | File | Perubahan | Dampak |
|---|---|---|---|
| Splash Godot | `project.godot` | `boot_splash/show_image=false`, `bg_color` gelap senada layar loading | Logo Godot tidak lagi muncul saat start |
| Satu layar loading | `_script/ui/Bootstrapper.cs` | `main.tscn` dimuat via thread di balik overlay bootstrapper, lalu overlay menunggu `TerrainManager.Initialized` sampai 60 detik maks | Loading dunia ("render world") tidak lagi tampak; dari boot sampai masuk dunia hanya ada 1 layar |
| Generasi chunk | `_script/terrain/MapGenerator.cs` | Semua hitungan noise 4-pass + Poisson dipindah ke `Task.Run` (thread pool) | Stutter/freeze beberapa puluh ms tiap chunk baru hilang — main thread bebas |
| RNG generasi | `_script/terrain/MapGenerator.cs` | Seed deterministik per-chunk (`ChunkSeed`), `System.Random` lokal | Thread-safe; dunia konsisten saat chunk dimuat ulang (sebelumnya `DateTime.Now` + RNG bersama tidak thread-safe & tidak reprodusibel) |
| Lingkungan | `_script/EnvironmentManager.cs` | Update cahaya + offset noise awan di-throttle 10 Hz; re-bake `NoiseTexture2D` hanya saat offset bergeser | Menghilangkan re-bake tekstur awan tiap frame (mahal di CPU mobile) |
| HUD utama | `_script/ScreenSpaceMainUI.cs` | Update HUD 5 Hz (bukan tiap frame), `SetText` hanya saat nilai berubah, tanpa `CallDeferred` rantai | Menghilangkan ratusan alokasi string + relayout label per detik |
| Label karakter | `_script/MainCharacter.cs` | Teks helper dihitung 4 Hz, `SetText` saat berubah, `SetSize` Android hanya sekali | Mengurangi kerja Label3D tiap frame |
| Animasi mob | `_script/CharacterMob.cs` | State animasi di-cache; `Animator.Set` hanya saat state berubah | Menghemat ~100 native string-call per frame (sebelumnya 5 param × ~20 mob × 60fps) |
| Mesh terrain | `_script/terrain/MeshGenerator.cs` | `RegenNormalMaps()` dihapus (normal hasil bake sudah dipasok) | Menghemat regenerasi normal per mesh AND mempertahankan normal ter-bake |
| Kompas | `_script/ui/Compass.cs` | Tanpa `CallDeferred` tiap frame; teks hanya berubah saat beda; rotasi dilewati bila < 0.05° | Mengurangi relayout UI tiap frame |

## Alur boot baru (satu layar loading)

1. **Bootstrapper** (`bootstrapper.tscn`) tampil dari detik pertama — splash
   Godot dinonaktifkan (`boot_splash/show_image=false`) sehingga tidak ada
   layar logo di depan.
2. Video loading + status unduhan berjalan seperti biasa (cek manifest,
   unduh hanya paket yang berubah, verifikasi SHA).
3. Setelah paket siap, `main.tscn` dimuat **dengan thread**
   (`ResourceLoader.LoadThreadedRequest`) di balik overlay.
4. Scene utama dipasang sebagai `CurrentScene`, tetapi overlay bootstrapper
   dipindah ke urutan teratas (`MoveChild`), sehingga dunia yang sedang
   dibangun `TerrainManager` tidak kelihatan.
5. Bootstrapper menunggu `TerrainManager.CurrentLoadStatus == Initialized`
   (maks 60 detik; bila timeout, overlay tetap dibuka — loading screen
   in-game lama masih ada sebagai jaring pengaman).
6. Video dihentikan, loading screen in-game dipaksa tersembunyi, overlay
   `queue_free()`. Pemain langsung melihat dunia yang sudah jadi.

## Catatan tuning lanjutan

- Pengaturan grafis in-game sudah tersedia via `GraphicsSettingsManager`
  (tombol ⚙ di HUD): preset Low mengatur render scale 0.70, shadow off,
  view distance 2 chunk — aman untuk perangkat lemah.
- Default project: renderer `mobile`, scaling 3D FSR 0.9, shadow 1024px,
  MSAA off, FXAA on.
- `SaveTerrainToLocalDisk` sudah `false` di `world.tscn` (tidak ada I/O
  disk per chunk di gameplay).
- Ide berikutnya bila perlu: tapered LOD detail saat Low preset, pool
  objek mob (sekarang instantiate/free per spawn), dan bake trimesh
  collision di thread (Godot 4 belum menyediakan API async).

## Verifikasi

Kompilasi C# diverifikasi oleh workflow `.github/workflows/android-build.yml`
(tahap "Build C# Solution"). Jalankan CI (atau `workflow_dispatch`) untuk
hasil APK terbaru; cek artefak/release `android-apk`.
