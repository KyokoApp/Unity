# Audit Menyeluruh Proyek — `Unity` (Godot 4.5 / C#)

Tanggal: 2026-09-19 · Basis: `main` @ `4cfcc1d` ("chore(cleanup): pembersihan menyeluruh file sampah & aset usang")
Cakupan: 59 file `.cs` (≈12.700 baris) di `_script/`, semua `.tscn`/`.tres`/`.gdshader`, `project.godot`, `*.csproj`/`*.sln`, `export_presets.cfg`, `.github/workflows/android-build.yml`, `tools/update_pipeline/*.py`, `docs/`.

> Metode: audit statis (baca + grep + pencocokan referensi aset) dan kros-check ke source/engine API Godot 4.5.
> Di sandbox ini **tidak ada** .NET SDK/Godot, jadi tidak ada satu pun temuan yang "dikompilasi/diverifikasi runtime".
> Bagian **H** berisi hal-hal yang perlu Anda cek sendiri di mesin Anda.

---

## A. RINGKASAN EKSEKUSI

| Aspek | Nilai | Catatan singkat |
|---|---|---|
| Arsitektur & streaming dunia | **4/10** | Konsepnya benar (chunk + LOD + generator di thread), tapi ada 1 bug fatal yang membekukan streaming selamanya |
| Gameplay loop (karakter, musuh, menang/kalah) | **2/10** | Tidak ada damage, tidak ada kalah, musuh hampir tidak pernah spawn, gravitasi mob salah |
| UI/UX mobile | **6/10** | Touch button & HUD bagus; beberapa jalur (underwater, minimap, debug label) mati senyap |
| Sistem update (patch/PCK/APK) | **8/10** | Yang paling matang di proyek ini; ada 3 catatan |
| Performa & optimasi | **5/10** | Banyak keputusan hemat yang benar, tapi juga alokasi per-frame & `SetPixel` massal |
| Kebersihan kode/repo | **4/10** | ±2.500 baris dead code, komentar Unity-ism, aset rusak sisa "cleanup", keystore ikut commit |
| **Sebagai demo tech procedural** | **7/10** | layak dipamerkan |
| **Sebagai game yang dirilis & dimainkan** | **3/10** | belum: ada bug yang menghentikan dunia + belum ada loop game |

**Jawaban langsung ke pertanyaan "apakah gameku bagus?"** Fondasinya bagus dan sistem updatenya serius (itu nilai jual terbesar Anda), tapi **saat ini game-nya rusak dalam ≤30 detik pertama** (dunia berhenti streaming, **Bug #1**), dan **belum punya loop permainan** (tidak ada damage/kalah, musuh praktis tidak spawn). Perbaikan #1 + #2 + #3 mengubahnya dari "demo teknis" menjadi "game yang bisa dimainkan".

---

## B. BUG FATAL (game berhenti berfungsi)

### #1 — Streaming terrain mati permanen (`InvalidOperationException` ditelan task yang tidak di-`await`)

**Lokasi:** `_script/terrain/TerrainManager.cs`

```
327  if (updateTimer > UpdateFrequency && !updatingChunks)
329      updatingChunks = true;
330      UpdateChunks();                 // <- async Task, TIDAK di-await
...
438  foreach (Vector2 coord in chunksDictionary.Keys)      // enumerasi kunci...
452      HideChunk(coord);                                  // <- ...yang menghapus kunci:
535  void HideChunk(Vector2 coord)
544      chunksDictionary.Remove(coord);                     // MODIFIKASI saat enumerasi
455  foreach (Vector2 coord in hiddenchunksDictionary.Keys)
457      DestroyChunk(coord);   // -> 560: hiddenchunksDictionary.Remove(coord)  (sama)
481  updatingChunks = false;    // <- tidak pernah tercapai lagi setelah exception
```

**Rantai kegagalan:**
1. Begitu pemain berpindah cukup jauh sehingga ada satu chunk keluar radius (`newHalfChunk != currentHalfChunkPosition`, sekitar **½ chunk ≈ 25 m** dari titik mulai), loop di baris 438 memanggil `HideChunk` yang melakukan `Remove` pada dictionary yang sedang di-enumerasi → `InvalidOperationException: Collection was modified`.
2. `try/catch` di baris 401–432 **hanya** membungkus bagian pembuatan chunk; bagian *cleanup* (438+) tidak terlindungi → exception lolos ke state machine `async Task`.
3. Task tersebut tidak pernah di-`await`/di-`ContinueWith` → **tidak ada crash, tidak ada pesan error yang menonjol** — hanya *unobserved faulted task*.
4. `updatingChunks` (baris 481) **tidak pernah di-reset false** → kondisi di baris 327 tidak pernah benar lagi → **tidak ada chunk baru yang pernah dibuat/dihapus selama-lamanya**.
5. Efek yang terlihat: dunia berhenti memuat (tebing terpotong, chunk jauh bolong permanen), `CurrentLoadStatus` tidak pernah menjadi `Initialized` (baris 477 di-lewati) → **LoadingUI tidak pernah disembunyikan** dan teks "Loading world chunks..." membeku, dan seluruh HUD yang bergantung status ikut salah.

**Gejala khas:** "jalan 20–30 detik, lalu dunia berhenti load; restart membantu sebentar."

**Perbaikan (minimal, aman):**

```csharp
// 1) jangan pernah mutasi dictionary yang sedang di-enumerasi
var toHide = chunksDictionary.Keys.Where(k => !reviewedChunks.Contains(k)).ToArray();
foreach (Vector2 c in toHide) HideChunk(c);

var toDestroy = hiddenchunksDictionary.Keys.ToArray();
foreach (Vector2 c in toDestroy) DestroyChunk(c);

// 2) jangan pernah tinggalkan flag terkunci
async Task UpdateChunks()
{
    updatingChunks = true;
    try { /* ...isi sekarang... */ }
    catch (Exception ex) { GD.PrintErr("[TerrainManager] UpdateChunks: " + ex); }
    finally { updatingChunks = false; }   // <- JAMINAN
}
```

Tambahan yang saya sarankan: panggil dengan `UpdateChunks().SafeContinueOnError()` atau `_ = UpdateChunks();` + logging, agar kegagalan streaming **selalu** tertulis di log, tidak senyap.

**Bug kecil sejenis di file yang sama:** `HideChunk` baris 537 melakukan `chunksDictionary[coord].loading` **sebelum** cek `ContainsKey` (baris 538) → `KeyNotFoundException` bila dipanggil dengan kunci yang sudah hilang (mis. dari jalur `Destroy()`); dan `DestroyChunk` baris 559 juga tanpa guard.

---

## C. KRITIS (game berjalan, tapi tidak "bermain")

### #2 — Tidak ada sistem damage/knockback/kalah sama sekali
- `CharacterMob.DeathPunched()` **tidak pernah dipanggil** dari mana pun (grep global: 0 pemanggil).
- `_script/CharacterMob.cs:118` `velocity.Y = PunchedVelocity;` — nilainya langsung ditimpa pada tick berikutnya oleh baris 133 (lihat #4), jadi "terlempar saat dipukul" tidak akan pernah terlihat.
- `_script/CharacterMob.cs:256` → `GameManager.Instance.OnLoseGame()`, dan `_script/GameManager.cs:66` `OnLoseGame()` **hanya** mereset `StartingPoint` + `MobManager.Instance.DespawnAllMobs()`. Tidak ada game-over, tidak ada pengurangan nyawa/mojo, tidak ada restart.
- Serangan pemain (`_script/MainCharacter.cs:458 LaunchAttack()`) membuat crate fisik (`GetTree().Root.AddChild(newCube)` — 4 tempat: baris 467, 523, 867, 891) yang **tidak pernah menyentuh mob secara logis**; `crate.QueueFree()` (505) hanya membersihkan salah satu jalur.
- Konsekuensi: "infinite runner" Anda tidak punya cara kalah selain jatuh ke jurang (dan itu juga tidak membuat kalah — lihat #17), dan tidak ada cara menang/skoring yang berarti. **Ini item #1 untuk "dijadikan game".**

### #3 — Musuh praktis tidak pernah muncul
`_script/MobManager.cs:102-145`: `GetSpawnLocation()` mengumpulkan item dengan `item.ModelAddress == "wall"` dari `GetChunks(3)` dan **`return Vector3.Zero` bila tidak ada**; `SpawnMob` lalu `continue`. Concentration `wall` di `MapGenerationSettings.DefaultValues()` hanya **0.03/chunk**, jadi di sebagian besar posisi pemain tidak ada tembok → tidak ada spawn. Ditambah lagi: radius despawn upkeep **50** vs pencarian spawn **3 chunk** → mob yang berhasil muncul langsung dianggap "jauh" dan dihapus.
Perbaikan: spawn berbasis radius/altitude (bukan keberadaan "wall"), atau naikkan concentration & samakan radius.

### #4 — Fisika mob salah total (gravitasi per-tick)
`_script/CharacterMob.cs:133`
```csharp
velocity.Y -= Mathf.Max(gravity * delta, gravity);   // delta=1/60 → selalu 9.8 per tick!
```
Yang benar: `velocity.Y += gravity * delta` (gravity sudah negatif) atau `velocity.Y -= gravity * delta`. Seperti sekarang, begitu mob kehilangan kontak tanah ia "ditarik" 588 m/s² efektif → menembus tanah/terlihat bergetar dan `IsOnFloor()` tidak stabil. (Kontras: pemain di `_script/MainCharacter.cs:680` sudah benar: `velocity.Y -= gravity * deltaFloat`.)

`_script/CharacterMob.cs` juga: `GetDirection()` mengembalikan **posisi** pemain (bukan arah) — kebetulan masih "kerja" karena `mob.global == local`; `UpdateMovement()` membaca **action `run` milik pemain** untuk animasi mob; `Initialization()` mengali `_cachedDirection` yang bernilai `Zero`.

### #5 — Tidak ada satu pun method `[Callable]`: 4 panggilan tertunda gagal senyap
grep `[Callable]` di seluruh `_script/` → **0 hasil**. Padahal ada 4 pemanggilan berbasis nama:

| Panggilan | Target | Akibat |
|---|---|---|
| `_script/MainCharacter.cs:308` & `:371` `MobManager.Instance.CallDeferred("ResetSecureZone", GlobalPosition)` | `_script/MobManager.cs:53 ResetSecureZone` (tanpa `[Callable]`) | zona aman tidak pernah di-reset → `GenerationActive` tidak pernah dipersenjatai ulang → mob berhenti spawn setelah "kalah" |
| `_script/ui/DebugUI.cs:37` `CallDeferred("setText", key, text)` | `:40 void setText(...)` **private** | label debug membeku pada nilai pertama |
| `_script/ui/GlobalUIManager.cs:212` `CallDeferred("free", module)` | `GodotObject.free()` tidak menerima argumen | modul UI tidak pernah dibebaskan (kebocoran memori kecil tiap pergantian modul) |

Godot hanya menulis `Error calling deferred method: Method not found ...` ke konsol — **tidak crash**, makanya tidak terdengar. Perbaikan: ganti semua dengan `Callable.Create(...)` / `module.CallDeferred("free")` yang benar, atau tambahkan `[Callable]`.
(Catatan: `CallDeferred("add_child", …)` di tempat lain **aman** karena itu method bawaan engine.)

---

## D. TINGGI (crash/bug yang muncul tiap sesi atau di device)

### #6 — Objek Godot dibuat di luar main thread saat generate mesh
`_script/terrain/MeshGenerator.cs:326` — `new ArrayMesh()` + `arrayMesh.AddSurfaceFromArrays(...)` dijalankan **di dalam** `await Task.Run(...)`. Mencipta/mengubah resource renderer dari thread worker tidak dijamin (proyek berjalan dengan `rendering/rendering_device/driver` default + `multi_threading/render_thread_mode` = default `unsafe` pada preset mobile) → artefak acak atau crash di device tertentu. Yang benar: hitung array (`Vector3[]`, `int[]`, warna) di background, lalu `AddSurfaceFromArrays` di main thread (chunk sudah punya pola "request → apply"). `ProcessMesh`/`CalculateNormals` justru dijalankan sinkron di main thread setiap ganti LOD → stutter yang bisa dirasakan.

### #7 — Spam exception NRE saat boot (1–2 frame pertama)
`_script/ScreenSpaceMainUI.cs:79-111` dan `_script/ui/Compass.cs:32` langsung men-dereference `GameManager.Instance` / `GetMainCharacter()` / `EnvironmentManager.Instance` **tanpa guard**, padahal `main.tscn` memproses frame sebelum `world.tscn` (di-`add_sibling` secara deferred oleh `GameManager.LoadWorld()`) mendaftarkan karakter. Hasilnya: konsol merah dengan `Object reference not set…` setiap kali game dimulai. Fix kecil: `if (GameManager.Instance == null) return;` di awal `updateActionBar()`/`updateTimeOfDay()`/`UpdateCompass()`.

### #8 — Kamera bawah-air: NRE + jalur yang mati total
`_script/MainCharacterCamera.cs`
- `:82` & `:91`: `UnderwaterEffect.Material as ShaderMaterial` → `shaderMat.SetShaderParameter(...)` tanpa cek null → NRE bila ColorRect belum punya material (dan `as` gagal).
- `SetCameraUnderwater/AboveWater` mengubah `EnvironmentManager.Instance.Environment/SunLight` tanpa guard.
- Ada blok duplikat `if (waterOverlapCount == 1)` dengan variabel lokal mati.
- **Semua itu tidak akan pernah jalan**: `_script/terrain/Water.cs:62` `if (body is CollisionShape3D area)` — di `Area3D`, sinyal `body_entered` mengirim `PhysicsBody3D`, bukan `CollisionShape3D`. Artinya efek bawah-air, celup, dan "tenggelam" **tidak pernah terpicu**.
- `_script/TouchInputManager.cs`: `Debug.Start()` dan `UpdateDirectionalActions()` tidak pernah dipanggil → loop `activeActions` mati (dead code).

### #9 — Siklus siang/malam ~36 detik (bukan 60 menit)
`_script/EnvironmentManager.cs:23` `DayLengthInMinutes = 60f`, `:125` `CycleSpeed = 100`, `:161` `secondsPerHour = (DayLengthInMinutes * 60f) / 24f` = **150 s/jam** — lalu `CycleSpeed` mengali waktu 100× → 24 jam game ≈ **36 detik nyata** → matahari & warna langit berkedip cepat (dan di device ini juga memicu update gradient/clouds terus-menerus). `world.tscn` hanya meng-override `StartAtHour = 11` — tidak menyentuh panjang hari. Fix: set `CycleSpeed = 1` (atau `DayLengthInMinutes = 20` dan hapus `CycleSpeed`).
Bonus di file yang sama: awan hanya beranimasi bila `skyMaterial.SkyCover as NoiseTexture2D` berhasil (kalau tidak → `return` dan hasil di-cache permanen → awan beku); perpaduan gradient membuat `new Gradient()` + list **setiap 0,1 s** (alokasi yang tidak perlu di mobile); `GetTime()` mengembalikan float mentah (bukan `HH:MM`).

### #10 — `Bootstrapper` membebaskan scene utamanya sendiri
`_script/ui/Bootstrapper.cs:1375` `QueueFree()` di dalam `FinishLoading()`, padahal `bootstrapper.tscn` = `run/main_scene`. Digabung dengan `MoveChild(this, GetChildCount()-1)` + penugasan ulang `CurrentScene`, urutan ini rapuh: jika `QueueFree()` dieksekusi lebih dulu saat jalur video/`MoveChild` retry berjalan, node sedang bebas → error "access an freed instance". Yang lebih aman: `GetTree().CurrentScene = world;` lalu `QueueFree()`, atau pindahkan logika boot ke autoload yang bukan main scene.
(Sisi baiknya: `LoadThreadedRequest` untuk `main.tscn`, timeout spawn 20 s/60 s, dan `FileAccess.FileExists` sebelum load = jaring pengaman yang tepat.)

### #11 — Update APK di Android kemungkinan besar crash / tidak bisa memasang
`_script/ui/Bootstrapper.cs:958` `OS.ShellOpen("file://" + apkGlobal)` dengan APK berada di `user://` (direktori privat aplikasi).
- Sejak Android 7.0, `Intent.ACTION_VIEW` dengan URI `file://` → `FileUriExposedException` (StrictMode penaltyDeath) → **aplikasi mati**, bukan sekadar error yang bisa ditangkap C#.
- Android 8+ juga membutuhkan izin `REQUEST_INSTALL_PACKAGES`; `export_presets.cfg` memakai `gradle_build/use_gradle_build=false` sehingga memakai manifest template Godot → izin & FileProvider **tidak ada**.
- Walau berhasil dibuka, package installer tidak bisa membaca direktori privat aplikasi tanpa `FLAG_GRANT_READ_URI_PERMISSION`.
Fix paling murah: buat tombol "Pasang" membuka **URL rilis di browser** (`_manifest.ApkUrl`, tombol Browser yang sudah ada di `:872`) dan sembunyikan jalur `file://`. Kalau mau tetap in-app: aktifkan gradle build + template `AndroidManifest.xml` dengan `REQUEST_INSTALL_PACKAGES` dan `FileProvider`.

### #12 — Verifikasi SHA256 dilakukan di main thread (freeze beberapa detik)
`_script/ui/Bootstrapper.cs:622 ComputeSha256(path)` dipanggil dari `:509` (setelah unduh) dan `:911`/`:1117` (saat menyusun rencana), yaitu di thread UI. Untuk pack 50–100 MB itu **freeze layar boot beberapa detik** (di HP low-end bisa 5–10 s), plus file yang sama di-hash dua kali (plan + verifikasi). Pindahkan ke `Task.Run` dengan `await`, atau pakai cache "path+size+mtime → sha".
Catatan kecil lain di downloader: `GetProcessDeltaSafe()` (`:188`, `:640`) berpura-pura `1/60` karena kelasnya bukan `Node` → backoff retry 2× terlalu cepat di perangkat 120 Hz; `OnRetryPressed` tidak meng-rewind `_completedPlanBytes` → progress bar bisa **mundur**; `_redirects++` menghitung semua respons, bukan redirect; `Content-Range` tidak di-parse (bergantung pada `416` untuk memotong file).

### #13 — Tekstur tower & wall hilang (regresi dari commit "cleanup")
`materials/textures/tower/tower_material.tres` menunjuk ke:
```
res://_models/obstacles/tower/tower_Tower.001_BaseColor.png   <- tidak ada
res://_models/obstacles/tower/tower_Tower.001_Normal.png       <- tidak ada
res://_models/obstacles/tower/tower_Tower.001_Roughness.png   <- tidak ada
```
(file PNG aslinya ada di `materials/textures/tower/`). `_models/obstacles/wall.tscn` juga menunjuk `res://materials/textures/wall_DefaultMaterial_*.png` yang tidak ada. Efeknya: tower (objek gameplay!) tampil tanpa tekstur + error load. Perbaiki path `.tres`-nya. Semua `res://` lain di 35 file `.tscn/.tres` sudah saya cek: **hanya 6 referensi ini yang rusak**, dan tidak ada script yang hilang.

### #14 — `_models/kaykit/Knight.glb` tanpa `.import`
`_scenes/main_character.tscn:10` meng-instance `res://_models/kaykit/Knight.glb`, tapi **`Knight.glb.import` tidak ada di repo** — satu-satunya `.glb` dari 68 yang tidak punya sidecar. CI menyamarkan ini dengan `timeout 180 godot --headless --editor --quit || true` (baris import) — **`|| true` menelan kegagalan/timeout import**. Artinya: di clone baru (atau CI saat import > 180 s) model pemain bisa tidak ikut ter-export dan build "sukses" tanpa model. Commit file `.import`-nya (dan/atau buat step import gagal-keras: hapus `|| true`, cek `.godot/imported` berisi).

### #15 — `.keystore/permanent.keystore` + passphrase di-commit ke repo
`.keystore/permanent.keystore` ikut version control, dan `permanentpass123` tertulis telanjang di `.github/workflows/android-build.yml` (juga dipakai sebagai fallback `keytool`). Untuk repo GitHub (apalagi publik), **siapa pun bisa menandatangani APK/PCK update atas nama Anda** — dan kunci rilis tidak bisa dirotasi tanpa membuat semua instalasi lama tidak bisa di-update. Ambil keluar dari repo (gitignore + history), pindahkan ke GitHub Secrets (`base64` + `ANDROID_KEYSTORE_PASSWORD`), dan tanda tangani dengan kunci baru.
Catatan: workflow juga **menghapus semua `patch_*.pck` lama** di tiap rilis — klien yang cache-nya tertinggal akan gagal unduh sekali (lalu jatuh ke fallback offline); simpan 1–2 patch terakhir.

---

## E. SEDANG (bug nyata, dampak terbatas / mudah diperbaiki)

| # | Lokasi | Masalah |
|---|---|---|
| 16 | `_script/ui/GraphicsSettingsManager.cs:454` | Opsi **"Render Distance"** dan preset Low/Ultra yang "mengurangi jarak lihat" adalah **no-op**: `TerrainManager.ViewingDistance` (`_script/terrain/TerrainManager.cs:32`) hanya ditulis, **tidak pernah dibaca** (jumlah penggunaan = 1). Layering chunk memakai `detailLevels.Length`. `docs/OPTIMALISASI.md` mengklaim sebaliknya → perbaiki kode atau koreksi dokumen. |
| 17 | `_script/MainCharacter.cs` (`Y < -100` → teleport ke `StartingPoint`) | Jatuh ke jurang tidak membuat kalah dan tidak mengurangi skor; tidak ada "death plane" yang berarti. |
| 18 | `_script/terrain/Noise.cs` `GenerateNoiseMapSimplex` | `noise.Seed = TerrainManager.Instance.Seed;` — **`pass.seed` diabaikan**, padahal `MapGenerator.GenerateHeightMapSimplex` menghitung `seed = Seed + passID`. Semua pass memakai seed sama → korelasi antar-pass yang tidak disengaja. (`GenerateNoiseMapSimplex_deprecated` & `GenerateNoiseMapVoronoi` = kode mati; Voronoi memanggil triangulator lalu **mengembalikan map nol**.) |
| 19 | `materials/shaders/water_sea.gdshader` | (a) menulis `ALPHA` tanpa `render_mode` transparansi (mis. `blend_mix`) → **air jadi opak**, `shallow_alpha` tidak berpengaruh; (b) `heightmap_tex : source_color` padahal itu data tinggi → nilai di-gamma-linearisasi → gradien dangal/dalam salah; (c) `shallow_grad_min = 1.115 > shallow_grad_max = 0.91` → `smoothstep(edge0>edge1)` = **undefined behavior** → garis pantai bisa hilang/menjadi konstan; (d) `depth` dihitung dua kali; `is_front` tak dipakai. |
| 20 | `materials/shaders/chroma_tint.gdshader` + `_scenes/main_character.tscn:4746` | Material tidak men-set `shader_parameter/normal_map` → `texture(black)*2-1 = (-1,-1,-1)` → layar bawah-air digeser **offset konstan** `(-0.015,-0.015)` (efek miring permanen). Set texture atau beri guard `if (length(nm.xy) < 0.001)`. |
| 21 | `_script/terrain/map/Minimap.cs` | Fitur **mati total**: badan `_Process` (`:29`) dikomentari, `Control3.visible=false` di `main.tscn`; `playerLoc == chunkLoc` membandingkan koordinat-map-chunk vs koordinat-chunk (salah satuan); menggambar dengan `SetPixel` per-piksel + `GD.Print` di loop item. Putuskan: implementasi ulang (Polygon2D/AtlasTexture) atau hapus. |
| 22 | `_script/terrain/world/SeaWater.cs` | `_script/terrain/world/SeaWater.cs:218` noise per-piksel `GD.Randf()` → air **berkedip** tiap regenerasi; `:161`/`:182` ≈ 2.811 `SetPixel` per chunk (marshal C#↔engine, mahal di mobile); `SetTerrainElevation(...)` dipanggil sebelum node masuk tree → `PushError`. |
| 23 | `_script/MobManager.cs` | `DespawnMob(mob, delay)` **mengabaikan `delay`** (`CreateTimer` tidak pernah di-`await` → `:220 mob.QueueFree()` langsung); loop `ShowHelpers` `return` setelah iterasi pertama; `_Ready` me-`Load` ulang `mob.tscn` padahal scene sudah di-instance di `world.tscn`; `mob.tscn` juga membawa `CameraPivot/Camera3D` dengan `visible = false` (properti itu **tidak ada** di `Camera3D` Godot 4 — entri basi, diabaikan saat load). |
| 24 | `_script/gameplay/Tower.cs:40,66` | `charbody.FloorMaxAngle = 70/60` di-set saat masuk/keluar, **tidak pernah dikembalikan ke 50** (default) → karakter bisa menanjak dinding setelah meninggalkan tower. `EndOverride()` juga tanpa guard null. |
| 25 | `_script/gameplay/PowerUp.cs:47` | Tween menuju `QueueFree()`, tapi `TerrainChunk` masih menyimpan `WorldItem.Model` → `OnChangedLOD` berikutnya memanggil objek yang sudah dibuang → `ObjectDisposedException` (jalur ini juga tidak memakai guard). |
| 26 | `_script/terrain/TerrainChunk.cs:191` `GetInclinationAtChunkMapLocation` | `+1` di-index tanpa clamp → `IndexOutOfRangeException` di tepi map (53). Dipanggil langsung dari `MainCharacter._Input` → crash saat input di tepi chunk. `:213 GetHeightmap()` men-dereference `_map` sebelum cek null. `Bounds` memakai `Scale(1,1,1)` yang tidak melakukan apa-apa (kemungkinan maksudnya `meshWorldSize`). |
| 27 | `_script/terrain/MapGenerator.cs:539` `public struct Map` | `Map` adalah **struct** yang berisi `List<WorldItem> DecorElements` → `default(Map)` memberi list `null` → NRE di `GetTerrainElements()`, `GetItemsForChunk()`, dan `MobManager.GetSpawnLocation()` setiap kali map belum terisi (persis yang terjadi saat `#1`). Ubah jadi `class` + guard. |
| 28 | `_script/terrain/TerrainChunk.cs` `LODMesh.hasRequestedMesh` | tidak pernah di-reset → bila request mesh gagal, LOD tersebut tidak akan pernah dicoba lagi (chunk bolong permanen). |
| 29 | `_script/terrain/TerrainDetailsManager.cs` | `GetCachedScene` miss → `PushWarning` + kembalikan `null` → properti **tidak terlihat** tanpa error yang jelas; `waterScene.Instantiate()` dipakai setelah `Load` tanpa cek null. |
| 30 | Matematika item di `MapGenerator` | `new Vector2(25 - X, 25 - Y)` meng-hardcode 25 (hanya benar untuk `chunkSizeIndex 0`); `GetTileIndex` menelan error sebagai `-201`; `DetermineItemPresence` mengembalikan `WorldItem` dengan `ModelAddress` kosong saat miss (bukan `null`) → pengecekan caller salah; `itm.Scale` di-lerp **dua kali**; `PoissonDisc` dipanggil sync-over-async (saat ini tidak terjangkau, tapi siap jebol). |
| 31 | `_script/GameManager.cs` | `EvtCameraChanged(new, mainCamera)` dibangun **sebelum** assignment → field "previous" selalu salah; `OnLoseGame()` memanggil `MobManager.Instance` tanpa guard; `Record` tidak pernah ditulis dari tempat lain (skor terbaik selalu 0); referensi statis (`Instance`, character, camera) tidak pernah dibersihkan saat keluar dunia → menggantung ke node yang sudah bebas. |
| 32 | `_script/core/events/BouncerockEventManager.cs:47` | `RemoveListener` mengakses `_subbersList[eventType]` tanpa `ContainsKey` → `KeyNotFoundException` untuk event tanpa subscriber (logika `listenerFound` di bawahnya jadi mati). Ditambah: `TerrainManager` berlangganan `EvtCameraChanged` dan **tidak pernah** berhenti → listener basi yang menunjuk node yang sudah `free`. |
| 33 | `_script/MainCharacter.cs` | Stamina: regen memakai aritmetika `int` → **terpotong jadi 0** (regen tidak pernah jalan). `_Process` melakukan pencarian medan **sinkron sampai 500 iterasi spiral** + `GD.Print` → stutter saat menanjak. `MoveToward((s-Walk)/(Run-Walk))` → NaN bila `WalkSpeed == RunSpeed`. Lerp FOV di-gate pada `Direction.Z` (tidak sinkron dengan yaw) dan clamp pitch/yaw tertukar. Glide mengunci `velocity.Y = -1` selamanya (tanpa batas mendarat), fly tidak punya langit-langit. 8 `Animator.SetXXX` per frame. |
| 34 | `_script/terrain/MapGenerator.cs:27,596,624` + `SaveTerrainToLocalDisk` | Cache `.isl` memakai `Environment.GetFolderPath(SpecialFolder.MyDocuments)` → **di Android mengembalikan ""** sehingga path jadi `/Islands/...` (`File.Exists` false → selalu generate; `SaveUnibyte` akan melempar exception). Sekarang selamat karena `world.tscn` men-set `SaveTerrainToLocalDisk = false`, tapi: (a) kalau dinyalakan, tulisannya ke path ilegal; (b) `FileWriter.SerializeToBinary<List<WorldItem>>` (DataContractSerializer) akan mencoba menserialisasi `WorldItem.Model` yang bertipe **Node** → exception. Pakai `user://` dan pisahkan DTO dari runtime. |
| 35 | Sistem modul UI (`_script/ui/UIModule.cs`, `TestUI.cs`, `GlobalUIManager.cs`) | Kerangka tidak berfungsi: `OnEnable/OnDisable` adalah hook **Unity** (Godot tidak memanggilnya), `StartModules()` tidak pernah dipanggil, `AvailableUIModules` tidak pernah diisi → semua method yang menyentuhnya NRE, `TestUI` seluruhnya dikomentari. ±250 baris sebaiknya dihapus atau ditulis ulang memakai `Visible`/`ProcessMode`. |
| 36 | `_script/ui/worldspace/WorldSpaceUI.cs` | Menjadikan `!child.IsProcessing()` sebagai proxy visibilitas — rapuh (node lain bisa mematikan process untuk alasan lain). |
| 37 | `_script/core/utils/Debug.cs` & `_script/SoftwareManager.cs` | Helper path persisten dikosongkan oleh `#if`, dan `Debug.DebugStartSession` menulis ke path **relatif** (bukan `user://`) → di device tidak terprediksi. `Debug.SetStaticBug` dipanggil per chunk (baris `TerrainManager.cs:368`) tetapi `UpdateDebugData()` diawali `return;` → kerja + alokasi string terbuang. |
| 38 | `_script/TouchInputManager.cs` | `JoystickRadius *= GameSettings.JoystickScale` → **berlipat** jika `_Ready` dijalankan dua kali (mis. respawn); drag kamera menulis `CameraRotationAxis` (menimpa, bukan menumpuk) → konsisten, tapi `UpdateDirectionalActions` tidak pernah dipanggil (lihat #8). |
| 39 | `_script/ui/GameSettings.cs` + `GraphicsSettingsManager` | `DebugOverlay` default **true** dengan komentar "sementara untuk diagnosa" → panel telemetry (FPS, posisi, hash versi) tampil ke **semua pemain rilis**; dan `GameSettings.EnsureLoaded()` hanya dipanggil dari `_Ready()` `GraphicsSettingsManager` → konsumen yang jalan lebih awal (`TouchInputManager`) membaca nilai default. Gate dengan `OS.HasFeature("editor")` dan muat `GameSettings` di `_static ctor`/autoload pertama. |
| 40 | `_script/BuildInfo.cs` | `VersionCode = 0` (placeholder). CI men-stamp dengan `github.run_number` via `sed`, tapi kalau ada yang men-build tanpa CI → `versionCode=0` tidak bisa menimpa instalasi lama (`INSTALL_FAILED_VERSION_DOWNGRADE`). Tambahkan guard: `BuildInfo.VersionCode <= 0` berarti "debug build" dan larang instalasi. |

---

## F. RENDAH / KEBERSIHAN (tidak merusak, tapi membingungkan & memperlambat)

1. **±2.500 baris kode mati.** `core/utils/math/EaseCurves.cs` (1.115 baris, **68 method, 0 pemakaian**), `FileWriter.cs` (507 baru; `LoadEncryptedXML`/`WriteXML` tak dipakai, AES dengan kunci hardcoded `"1234567890123456"` + MD5), `MathExt` (fungsi berkomentar ganda, `BoundingMin3` mengembalikan `End`, bukan `Min`), `BouncerockTools` (1 helper log), `_script/ui/worldspace/LineDrawer.cs` (+`_scenes/gui/worldspace/lines_drawer.tscn`) tidak pernah dipasang, `WorldItemData` tak terpakai, `Noise.GenerateNoiseMapSimplex_deprecated` & `GenerateNoiseMapVoronoi`, `materials/shaders/world.tres` (0 referensi). Semua ini menambah ukuran assembly/APK dan waktu baca bagi siapa pun yang menolong Anda.
2. **Dua kelas `EnvironmentManager`** (`_script/EnvironmentManager.cs` global yang aktif, dan `Wawa.Islands.EnvironmentManager` yang tak pernah direferensikan) → sumber kebingungan absolut; hapus yang kedua.
3. `HeightMapSettings` dan **kedua** `WorldItemSettings` lama dikomentari; `MapGenerationSettings.DefaultValues()` = satu-satunya sumber konfigurasi → tuning dunia berarti edit kode, bukan editor. Kembalikan konfigurasi ke `.tres`/Resource agar desainer bisa mengubah tanpa compile.
4. `using System.Runtime.Intrinsics.Arm;` (Windows build → noise) dan `using System.Security.Cryptography.X509Certificates;` di `Bootstrapper.cs` → tidak perlu.
5. `mob.tscn` punya node `BRTerrain` kosong; `crate.tscn` & `common_tree_2.tscn` ber-root `Node3D` **tanpa script** → `as WorldItemModel` menghasilkan `null` (semua kode yang mengharapkan model jadi diam-diam tidak jalan); root decor adalah `RigidBody3D` dengan `freeze=true` (kenapa bukan `StaticBody3D`/`Node3D`?).
6. `_scenes/decor/{bush_berries,schroom,power_up}.tscn` memakai `[connection]` ke `_on_area_3d_body_entered` — jika method di scriptnya di-rename/private, koneksi hilang senyap (saya tidak menemukan `[Signal]`/`[Callable]` di sisi C#).
7. `project.godot`: `editor_interfaces`/`movie_writer/movie_file = "C:/Projects/Procedural Terrain Generation Godot 4.4/movie.avi"` (path Windows milik developer lama — jangan ikut dibagikan), action input `action` punya event kosong, `ui_up/ui_down/ui_attack` memetakan **unicode** 122/115/97 (Z/S/A keyboard-layout-dependent) alih-alih physical keycode, `physics/common/physics_ticks_per_second=60` + `maximum_physics_steps_per_frame=4` (ombak 240 Hz efektif; periksa `CharacterMob` yang memakai `delta` untuk gravitasi — lihat #4).
8. File `.uid` hilang untuk: `BuildInfo.cs`, `GameSettings.cs`, `GrassRoadBuilder.cs`, `AnimeActionTouchButton.cs`, `Bootstrapper.cs`, `GraphicsSettingsManager.cs`, `toon_outline.gdshader`. Bukan fatal (fallback ke path) tapi membuat UID cache tidak stabil antar mesin/CI.
9. `_scenes/main_character.tscn:12` `uid="uid://toon_outline_01"` — **UID tulisan tangan yang tidak valid** (alphabet UID Godot tidak menerima karakter `_`, dan `toon_outline.gdshader.uid` tidak ada). Godot akan mem-print error/`Invalid UID` lalu fallback ke path. Hilangkan string-nya (biarkan path saja) lalu biarkan editor men-assign UID asli.
10. **Versi editor tercampur (cek ini!).** `project.godot` mengklaim `config/features = ("4.5","C#","Mobile")` dan csproj `Godot.NET.Sdk/4.5.1`, CI memakai **4.5.1** — tetapi 4 scene (`main.tscn` ×95, `main_character.tscn` ×29, `world.tscn` ×14, `decor/tower.tscn` ×8 entri) berisi atribut `unique_id=…` pada node, yang **tidak dikenal Godot 4.5** (`Node` 4.5 tidak punya field/property `unique_id`; fitur Unique Node IDs baru ada di 4.6). Artinya file-file itu terakhir disimpan dengan editor 4.6+, sementara `mob.tscn`/`crate.tscn`/`sea_water.tscn`/`bootstrapper.tscn`/`decor/*` tidak. `format=4` sendiri **aman** (4.5 juga menulis format 4 bila ada `PackedByteArray` besar — itu sebabnya `mob.tscn` & `crate.tscn` bernomor 4). Yang harus Anda pastikan: buka proyek ini dengan **4.5.1** dan lihat apakah muncul `Invalid set index 'unique_id'` / error parse scene; kalau iya, seragamkan satu versi (re-save semua scene di 4.5, atau upgrade proyek + CI ke 4.6 dan bump `Godot.NET.Sdk`). Jangan biarkan dua editor bergantian menyimpan repo ini.
11. `docs/`: isinya bagus dan jujur (KARAKTER.md/OPTIMALISASI.md/SISTEM_UPDATE.md), tapi ada klaim yang sudah tidak benar di kode → perbaiki: (a) "preset Low memangkas jarak render" (#16), (b) "mesh dibuat di thread dengan aman penuh" (#6), (c) `README.md` tidak ada sama sekali — untuk proyek dengan pipeline se-ambisius ini,README + diagram alur boot/patch akan sangat menolong.
12. Repo menyimpan `Amv/*.mp4` (video mentah, ~27 MB+) yang hanya dipakai CI untuk konversi; `videos/` di-`.gitignore` dengan benar. Kalau tidak diperlukan untuk build lain, pindahkan ke LFS/release asset.

---

## G. YANG SUDAH BAGUS (jangan diubah — ini kekuatan proyek Anda)

1. **Sistem update/patch adalah bagian terbaik di proyek ini.** Akar masalah "stuck di 80 MB" (timeout `HTTPRequest` = batas **total**, bukan idle) benar-benar dipahami, lalu ditulis ulang sebagai pump `HttpClient` sendiri: budget 8 ms/frame, timeout berbasis *stall*, unduh ke `.part` + `Range` (resume), `416` → mulai ulang, `200` saat resume → potong, redirect (termasuk `Location` relatif), verifikasi ukuran **dan** SHA256, rename atomik, `update_state.json` tmp+rename, pembersihan `.pck` basi dengan mempertahankan `assets_v1.pck`, fallback `last_manifest.json` offline, dan alur instalasi APK yang dieksplisitkan. Pipeline CI-nya (`gen_patch_filter.py`, `stage_patch_project.py`, `make_manifest.py`, `list_pck.py`) juga matang: baseline kumulatif, flag `requires_restart`/`needs_new_apk`, reuse entri base untuk menghemat 50 MB, laporan ukuran APK, `patch_report.txt`, dan komentar yang menjelaskan *mengapa* (contoh bagus: "exclude glob luas mengalahkan include_filter di exporter Godot").
   Tinggal tiga: #11 (`file://` install), #12 (hash di main thread), dan satu lubang: kalau **tidak ada** file konten yang berubah sejak baseline, `include_filter` menjadi kosong → `selected_resources` dengan include kosong = **seukuran proyek penuh** (catatan Anda sendiri sudah menuliskan mekanismenya) → tambahkan jalur "skip patch" di `make_manifest.py`.
2. **`_script/terrain/world/GrassRoadBuilder.cs`** — jalan prosedural deterministik global (fungsi sinus per posisi dunia, jadi chunk yang bersebelahan selalu nyambung), penolakan berbasis kemiringan/ketinggian/road-masking, `ArrayMesh`+material di-cache, **1 draw call** MultiMesh, dan early-out murah. Ini contoh pattern yang harusnya ditiru modul lain (termasuk `SeaWater`).
3. **`AnimeActionTouchButton`** memakai `_Input` + `SetInputAsHandled()`, sehingga tombol kanan menang atas drag kamera (dan UI memang lebih belakangan di tree daripada `World`) — penanganan input touch yang benar dan jarang dilakukan dengan benar.
4. HUD hemat: `ScreenSpaceMainUI` (0,2 s) dan `EnvironmentManager` (0,1 s) di-throttle dan **hanya menulis `Text` saat berubah**; `RenderingServer`/FSR 0.9 + FXAA + shadow 1024 + `etc2_astc` = preset mobile yang tepat.
5. Cache `.isl` per chunk + generator deterministik (seed tunggal) + LOD berlapis (`ComputeNewChunksAddresses`) = fondasi streaming yang benar (dan murah untuk relokasi), tinggal jangan dibunuh #1.

---

## H. PERLU ANDA VERIFIKASI DI MESIN ANDA (saya tidak bisa menjalankan build di sini)

1. Buka `_scenes/main.tscn` di **Godot 4.5.1** → cari `Invalid set index 'unique_id'` / error parse (temuan F.10). Kalau muncul, itu **fatal #0** dan selesaikan dengan menyeragamkan versi editor.
2. Jalankan game dan rekam konsol 60 detik sambil berlari lurus: kalau setelah ±25 m tidak ada chunk baru yang muncul dan label "Loading world chunks..." tidak hilang → #1 terkonfirmasi (seharusnya ada `Collection was modified` + stack trace di Output).
3. Material rumput & jalan: mesh dibuat hanya dengan Vertex+Color (tanpa `ARRAY_NORMAL`) — `GrassRoadBuilder.cs:161,264`. Bila di device rumput/jalan tampak **hitam/sangat gelap**, itu sebabnya; tambahkan `ARRAY_NORMAL` (atau set `ShadingMode = Unshaded`).
4. Apakah `git log` penuh Anda memang berisi `1363060343f361cd7394899975e078739d319d87` (isi `tools/update_pipeline/baseline_commit.txt`)? Clone saya shallow (depth 1) jadi tidak bisa memastikan. Kalau history pernah di-squash/force-push, `git diff baseline..HEAD` di CI gagal → `changed_files.txt` kosong → patch kosong/nyaris kosong dan **game tidak pernah ter-update** (gejalanya: "sudah versi terbaru" terus). Perbaiki dengan menulis ulang baseline ke HEAD rilis terakhir.
5. Apakah `dotnet build -c ExportRelease` benar-benar lulus di mesin Anda (saya tidak punya SDK di sini): ada `#if GODOT_ANDROID` (valid, define itu ada), tapi ada juga banyak `using` sistemik (`System.Xml.Serialization`, `System.Runtime.Intrinsics.Arm`) yang sebaiknya disentuh sekali agar build bersih 0 warning.

---

## I. URUTAN PERBAIKAN YANG SAYA SARANKAN

**Sprint 1 — "biar jalan" (±1–2 jam, dampak terbesar)**
1. #1 snapshot key + `try/finally` di `UpdateChunks` (dan reset `updatingChunks` + `GD.PrintErr` di `catch`).
2. #7 guard null di `ScreenSpaceMainUI`/`Compass` (hapus spam merah saat boot).
3. #5 tambahkan `[Callable]` pada `MobManager.ResetSecureZone` & `DebugUI.setText`; ganti `CallDeferred("free", module)` → `module.CallDeferred("free")`.
4. #8 `Water.cs:62` → `if (body is PhysicsBody3D body3D)`; guard null `UnderwaterEffect.Material`.
5. #4 `velocity.Y -= gravity * delta` (hapus `Mathf.Max`).
6. #13 perbaiki 6 path tekstur; #14 commit `Knight.glb.import` + hapus `|| true` di step import CI.

**Sprint 2 — "biar jadi game" (±2–4 hari)**
7. #2 + #3: loop kalah-menang yang sungguh (damage di `Collision`/`Area3D` → `MainCharacter.TakeDamage` → `GameManager.OnLoseGame` → UI game over + restart), spawn mob berbasis radius, `OnLoseGame` meng-`ResetSecureZone` via `Callable` sungguhan.
8. #9 siang/malam wajar (20–60 menit nyata) + #19 koreksi shader air (tambah `render_mode blend_mix;` atau jadikan air opaque dengan `ALBEDO` saja; set `heightmap_tex` non-`source_color`; perbaiki `shallow_grad_min/max`).
9. #17 death plane → kalahkan pemain; #33 hapus pencarian sinkron 500-iterasi dari `_Process` (pakai cache + `GetChunkFromLocationAsync`).

**Sprint 3 — "biar layak dirilis"**
10. #6 pindahkan pembuatan `ArrayMesh` ke main thread (atau aktifkan `rendering/rendering_device/...` yang konsisten & uji), pindahkan `ProcessMesh` ke background.
11. #11 & #12 di Bootstrapper; pindahkan SHA256 ke `Task.Run`; skip-patch kosong.
12. #15 keystore keluar dari repo + rotasi kunci.
13. #16–#40 & bagian F: hapus kode mati (±2.500 baris), rapikan `.uid`, hapus duplikat `EnvironmentManager`, kembalikan konfigurasi ke `.tres`, tambah `README.md`.

Kalau Sprint 1 selesai, game ini sudah "hidup" dan layak dibagikan; setelah Sprint 2 barulah layak disebut **game**.

---

## J. CATATAN VERSI ENGINE (Godot 4.5.1 → sekarang)

Proyek ini: `config/features=("4.5","C#","Mobile")`, `Godot.NET.Sdk/4.5.1`, CI mengunduh **4.5.1-stable** (`.github/workflows/android-build.yml:68-69`).

| Versi | Rilis | Status | Relevansi untuk proyek ini |
|---|---|---|---|
| **4.7.2** (terbaru) | 18 Agu 2026 | stabil, didukung | HDR output, `AreaLight3D`, `DrawableTexture2D`, **`VirtualJoystick`**, perbaikan workflow Android |
| **4.7** | 18 Jun 2026 | stabil, didukung | rilis fitur; pemeliharaan 4.7.1/4.7.2 = bug fix saja, diklaim kompatibel |
| **4.6.3** | 20 Mei 2026 | stabil, didukung | **Unique Node IDs** (penyebab `unique_id` di scene Anda — audit F.10), **delta encoding untuk Patch PCK**, Jolt jadi default, `ObjectDB` snapshots, mesh→`CollisionShape3D`, SAF di Android |
| 4.5.2 | 18/19 Mar 2026 | **partial** (hanya keamanan & dukungan platform; dukungan aktif berakhir 19 Mar 2026) | upgrade tanpa risiko migrasi, tapi tidak menyelesaikan F.10 |
| 4.8 | dev (dev6 = 15 Sep 2026) | belum stabil (estimasi Q4 2026) | jangan dipakai untuk rilis |
| ~~5.0~~ | tidak ada | — | lini 4.x masih berlanjut; tidak ada lompatan mayor |

**Kesimpulan: Anda cuma tertinggal 2 rilis minor (±11 bulan), bukan "jauh".** Tapi posisi sekarang tidak enak:
- scene `main.tscn`, `main_character.tscn`, `world.tscn`, `decor/tower.tscn` **sudah disimpan editor 4.6+** (mengandung `unique_id` yang tidak dikenal 4.5) → repo ini sebenarnya sudah "terkontaminasi" versi baru;
- 4.5 tidak lagi menerima perbaikan reguler.

**Rekomendasi (urut prioritas):**
1. **Jangan upgrade sambil memburu bug #1.** Perbaiki fatal streaming di 4.5.1 dulu — kalau keduanya berubah bersamaan, Anda tidak tahu mana penyebabnya.
2. Setelah itu, **naik langsung ke 4.7.2** (bukan 4.6): lebih bersih daripada terus campur-aduk dua editor, dan Anda dapat maintenance line yang masih didukung. Kalau Anda sangat tidak ingin menyentuh apa pun hari ini: minimal `4.5.1 → 4.5.2` (3 baris, nol migrasi).
3. Yang berubah di 4.6/4.7 dan **benar-benar menyentuh kode/config Anda**:
   - **Delta encoding Patch PCK (4.6)** — ini pesaing langsung `tools/update_pipeline/stage_patch_project.py` + `gen_patch_filter.py`. Coba dulu jalur engine sebelum mempertahankan 618 baris tooling custom; bisa-bisa pipeline Anda menyusut jadi ~1 langkah. (Catatan: ini berlaku untuk `Patches` yang di-import Godot; skema Anda men-download PCK sendiri via HTTP, jadi tetap perlu downloader Anda — tapi bagian "staging proyek minimal" mungkin bisa dibuang.)
   - **Jolt sebagai default physics (4.6)** → wajib retest: `Tower.cs:40,66` (`FloorMaxAngle` 70/60), `CharacterMob.cs:133` (gravitasi, tembus tanah), `MainCharacter` (snap-to-floor, `MotionMode`), `project.godot` `maximum_physics_steps_per_frame=4`. Kalau ingin perilaku lama persis: set `physics/3d/engine="GodotPhysics"` dulu, baru migrasi ke Jolt secara sadar.
   - **`VirtualJoystick` (4.7)** — opsional; `TouchInputManager` Anda sudah benar, jangan dirombak demi ini.
   - **`DrawableTexture2D` (4.7)** — menarik untuk `SeaWater`/`Minimap` yang sekarang melakukan ribuan `SetPixel` per chunk.
   - Editor 4.6+ menandai "klik file di Output panel" & `ObjectDB snapshots` → pakai ini untuk memburu sisa leak (lihat #31: referensi statis `GameManager` yang tidak pernah dibersihkan).
4. **Checklist upgrade konkret (5 titik):**
   ```
   Procedural Infinite Runner.csproj:1   Godot.NET.Sdk/4.5.1        -> Godot.NET.Sdk/4.7.2
   project.godot:8                       PackedStringArray("4.5",…) -> ("4.7","C#","Mobile")
   .github/workflows/android-build.yml:68-69  GODOT_VERSION="4.5.1" / RELEASE_TAG="4.5.1-stable" -> 4.7.2
   .github/workflows/android-build.yml:64  platforms;android-34 / build-tools;34.0.0 -> naik (Godot 4.7 minta API lebih baru)
   (dotnet-version '9.0.x' sudah benar — tidak perlu diubah)
   ```
   Lalu: buka proyek **sekali** di 4.7.2 → biarkan re-import → **re-save semua scene** (Project ▸ Tools ▸ *Upgrade/Resave*) → commit `.import`/`.uid` yang terbentuk, termasuk `Knight.glb.import` yang sekarang hilang (temuan #14). Setelah itu semua scene konsisten satu versi → temuan F.10 beres dan `export_presets.cfg` tidak akan lagi berubah-ubah sendiri (diff besar di run pertama, abaikan — ia tidak ikut patch tapi menyalakan flag `requires_restart`).
5. **Titik API yang harus dicek tetap compile di 4.7** (saya tidak bisa mengompilasi di sandbox): `RenderingServer.DirectionalShadowAtlasSetSize(size, is_16bits)` (`GraphicsSettingsManager.cs:478`), `TlsOptions.Client()`, `Viewport.Scaling3DScale` + `scaling_3d/fsr_sharpness`, `Node.add_sibling`, `Animator.Set*`, `Area3D.body_entered`, `PhysicsServer3D` area mask di `SeaWater`/`Water`.
6. Setelah upgrade: **hapus/muncul-kan kembali `unique_id` secara konsisten** — jangan buka project ini dengan editor 4.5 lagi (set `Project Settings ▸ Features` dan CI sebagai penjaga: tambahkan langkah CI yang gagal kalau `godot --version` ≠ yang diharapkan).

---

## K. SUDAH DITERAPKAN DI REPO (Android-only + HUD baru) — 19 Sep 2026

Perubahan ini mengerjakan 4 permintaan: **(1)** buang semua yang Windows/desktop, **(2)** UI rapi tanpa teks menghalangi, **(3)** bar darah = garis tipis di bawah layar, **(4)** stamina = setengah lingkaran di samping karakter.

### K.1 Game Android-murni (kode desktop dibuang, bukan di-`#if`)
| File | Yang dibuang / diganti |
|---|---|
| `_script/MainCharacter.cs` | `Input.MouseMode = Captured` di `Initialization()` **dihapus**; blok `#if GODOT_WINDOWS` (mouse-look + tombol mouse) dan blok komentar mouse 45 baris **dihapus**; `#if GODOT_ANDROID` pada `UpdateCamera` & `PopupInfo.SetSize` **dibuat tanpa syarat** (dulu tidak aktif di editor, karena `GODOT_ANDROID` hanya didefinisikan saat ekspor → itulah sebabnya sentuh tidak pernah terasa saat dites di PC); `mouse_speed` dihapus. |
| `_script/MainCharacter.cs` | `_Input(InputEvent)` **dihapus total** → diganti `RefreshInputState()` yang dipanggil di awal `_PhysicsProcess`. Ini sekaligus menutup **race prioritas `_input`** (temuan #C/D): dulu karakter membaca `Input.IsActionPressed(...)` *sebelum* `AnimeActionTouchButton` menekan action pada event yang sama → tombol terasa mati. Status tahan (`run/jump/fly/sit/attack`) dipolling; `torch` memakai deteksi tepi (`_torchWasDown`) supaya tidak berkedip. |
| `_script/MainCharacter.cs` | Spawn `Cube` ganda di jalur attack **dihapus** (`LaunchAttack()` sudah melakukannya, dan `attackTimer` tetap jadi satu-satunya rem). |
| `_script/CharacterMob.cs` | Blok komentar `_Input` mouse desktop (46 baris) dihapus. |
| `project.godot` | `window/handheld/orientation=6` (sensor_landscape) ditambahkan; override `ui_left/ui_right/ui_up/down` (keyboard Windows) dihapus — default engine tetap ada; `[editor] movie_writer/*` yang menunjuk `C:/Projects/...` dihapus. `emulate_touch_from_mouse=true` **sengaja dipertahankan** (satu-satunya cara mengetes sentuh di editor; di Android diabaikan). |
| `export_presets.cfg` | Preset **Windows Desktop, Web, Linux, macOS dihapus**; sisa 3 → `preset.0 Android`, `preset.1 AssetPack`, `preset.2 PatchPack` (header `[preset.N]` **dan** `[preset.N.options]` ikut dibetulkan — kalau nomor tidak rata Godot membuang SEMUA preset). CI memakai nama preset + `sed version/code`, jadi tetap valid. |
| `_script/SoftwareManager.cs` | `SetPersistentPaths()` tidak lagi pakai `Environment.GetFolderPath(ApplicationData/MyDocuments)` (di Android menghasilkan `""`) → sekarang `user://Bouncerock/` + `DirAccess.MakeDirPathRecursive`. **Plus: fungsi ini dulu tidak pernah dipanggil sama sekali** → sekarang dipanggil di awal `_Ready()`, dan `gameManager.Initialize()` diberi guard null. |
| `_script/terrain/MapGenerator.cs` | 3 × `GetFolderPath(MyDocuments) + "/Islands/"` → `user://Islands/` (`SaveTerrainToLocalDisk` = **true**, jadi ini jalur tulis yang benar-benar aktif di HP). |
| `_script/ui/Bootstrapper.cs` | `OS.ShellOpen("file://" + apk)` di `InstallDownloadedApk()` diganti buka `_manifest.ApkUrl` lewat browser. `file://` di Android melempar `FileUriExposedException` di UI thread = crash; menyerahkan APK ke Package Installer butuh ContentProvider (plugin Java) yang tidak ada di proyek ini. |

### K.2 HUD Genshin-style (2 widget baru, murni `_Draw`)
- **`_script/ui/hud/HudHealthLine.cs`** — garis darah full-width di tepi bawah: tebal 5 px, margin bawah 6 px, margin sisi 24 px; track hitam α0.42 + glow + gradien vertex-color (hijau→kuning→merah) + ujung putih 2 px; easing `Mathf.MoveToward` 3 rasio/s dan flash putih 0.3 s saat darah berkurang. Tanpa node anak, tanpa material, tanpa shader.
- **`_script/ui/hud/HudStaminaArc.cs`** — busur atas (∩) radius 42 px dengan 5 garis pembilah ("roda") + knob di ujung, drain dari kanan ke kiri; kuning → merah di bawah 28%; **hilang sendiri** saat stamina penuh (delay 1.1 s + fade), muncul lagi begitu LARI/TERBANG/GLIDE ditekan. Posisi di adegan: di kanan, sejajar bagian atas karakter.
- **`_script/ScreenSpaceMainUI.cs`** ditulis ulang: hanya `[Export] Label Distance`, `HudHealthLine HealthLine`, `HudStaminaArc StaminaArc`; throttle 10 Hz; guard `gm == null || ch == null` (menutup NRE boot temuan #D.7); rekor baru ditandai sementara dengan flash "· REKOR BARU" 2 detik di label yang sama, bukan label permanen.
- Sumber data darah: field **baru** `MainCharacter.Health/MaxHealth` + `HealthRatio`, `ActionRatio` (stamina = `Action` 0..100), `IsConsumingStamina`. Catatan penting: `Mojo` **bukan** darah — itu combo meter yang direset di 100 (`MainCharacter.cs:766-781`), jadi tidak dipakai untuk HUD. `TakeDamage()/Heal()` disediakan; belum ada pemanggilnya karena proyek memang belum punya sistem damage (temuan #C.1).

### K.3 UI dirapikan (yang dihapus dari layar)
- `_scenes/main.tscn`: 4 panel HUD lama beserta seluruh turunannya **dihapus** (48 node, ±290 baris): `PanelContainer` (Distance from start), `PanelContainer3` (Record), `PanelContainer4` (MOJO/Score/Multiplier + 2 ProgressBar), `PanelContainer5` (Time), **dan** panel bantuan keyboard di loading screen (`WASD/Space/X/F/SHIFT/R-CLICK`, 21 node). Yang tertinggal di layar: angka jarak (tengah atas, 28 px + outline 8), kompas, garis darah, busur stamina, 5 tombol sentuh.
- Tombol sentuh ditata ulang jadi satu klaster kanan-bawah yang konsisten (SERANG Ø152 di sudut, LOMPAT 120 di kirinya, LARI 108 dan TERBANG 96 di atasnya, SENTER 80 di kiri-tengah), label bahasa Indonesia, radius hit-test disamakan dengan radius visual (dulu `ButtonRadius` lebih kecil dari lingkaran yang digambar → "kok tidak kena").
- `_script/GameSettings.cs`: `DebugOverlay` default **OFF** (dulu ON → tumpukan teks debug hijau menutupi layar kiri).
- `_script/ui/GraphicsSettingsManager.cs`: tombol ⚙ pindah dari `(30,200)` (menumpuk dengan HUD kiri) ke anchor kanan-atas.
- `_script/ui/Compass.cs`: guard null untuk `GameManager.Instance`/karakter (dulu NRE tiap frame selama boot).

### K.4 Cara verifikasi saya (tanpa Godot/dotnet di sandbox)
Tidak ada toolchain Godot maupun `dotnet` di lingkungan ini, jadi **tidak ada `dotnet build`** yang membuktikan compile. Yang saya lakukan: parse ulang `main.tscn` — setiap `parent=` menunjuk node yang ada, tidak ada nama sibling ganda, semua `ExtResource(...)`/`SubResource(...)` terdefinisi, semua `NodePath` pada `ScreenSpaceUI` (`Hud/DistanceLabel`, `Hud/HealthLine`, `Hud/StaminaArc`) resolve, jumlah header `[preset.N]` = jumlah `[preset.N.options]` = 3, tidak ada lagi string desktop (`WASD`, `R-CLICK`, `MOJO`, `MouseMode`, `GODOT_WINDOWS`, `GetFolderPath`) yang tersisa di kode, dan keseimbangan `{}`/`()` setiap file C# yang disentuh sama dengan versi aslinya.

### K.5 Yang MASIH menghambat terlihatnya HUD ini
1. **Temuan #B (fatal, belum saya sentuh karena butuh izin Anda):** `TerrainManager.UpdateChunks()` melempar `InvalidOperationException` (hapus item sambil iterasi `Keys`) di `async void` tanpa `await` → streaming mati dan `CurrentLoadStatus` tidak pernah `Initialized` → gerbang `Initialized` di `MainCharacter._PhysicsProcess` menahan karakter **dan sekarang juga `RefreshInputState()`**. Tanpa perbaikan ini, game tetap beku di "loading" dan HUD baru tidak akan terlihat bergerak.
2. Belum ada yang memanggil `TakeDamage()` → garis darah akan penuh terus sampai tabrakan mob/air/jatuh disambungkan (butuh keputusan desain: berapa damage, ada respawn atau tidak).

### K.6 CATATAN ORIENTASI (penting, jangan diulang salah)
`display/window/handheld/orientation` di Godot **4.5 dibaca sebagai INT**, bukan string
(`main/main.cpp:2750` dan `platform/android/export/export_plugin.cpp:1197`), dan urutan
enum-nya (`servers/display_server.h` 4.5) adalah:

| nilai | arti |
|---|---|
| 0 | LANDSCAPE (kunci satu arah) |
| 1 | PORTRAIT |
| 2 | REVERSE_LANDSCAPE |
| 3 | REVERSE_PORTRAIT |
| **4** | **SENSOR_LANDSCAPE (landscape kiri/kanan bebas) ← dipakai proyek ini** |
| 5 | SENSOR_PORTRAIT |
| 6 | SENSOR (bebas — **inilah nilai keliru yang sempat tertulis dan membuat game ikut portrait**) |

Nilai lama repo `0` sudah landscape. Menulis `"sensor_landscape"` (string) atau `6`
(salah index) membuat orientasi lepas sehingga HP bebas memotret portrait.
Format `project.godot` juga **tidak mendukung baris komentar `#`** (parser ConfigFile
menolaknya → proyek gagal dimuat, lihat riwayat commit 9760aec→cf6655d).

### K.7 Perbaikan lanjutan setelah uji APK v1.0.176 (layar biru)
1. **TerrainManager.UpdateChunks()**: `foreach (… in chunksDictionary.Keys)` lalu
   `HideChunk()` yang menghapus entri di dictionary yang sama → `InvalidOperationException`
   di Task tanpa `await` → `updatingChunks` tersangkut `true` selamanya → streaming mati.
   Sekarang: snapshot kunci (`Keys.CopyTo`), guard `ContainsKey` sebelum `DestroyChunk`,
   dan seluruh isi dibungkus `try/catch/finally` (`updatingChunks=false` di `finally`,
   error dicetak `GD.PrintErr`).
2. **MapGenerator.SaveUnibyte/SaveMapDetails**: tulis cache `.isl` sekarang dibungkus
   try/catch — kegagalan izin tulis/disk tidak boleh membatalkan `OnHeightMapReceived`,
   yang kalau dibiarkan membuat chunk tidak pernah jadi (dunia kosong).
3. **HudHealthLine & HudStaminaArc**: `Resized += QueueRedraw` — ukuran Control hasil anchor
   belum pasti benar saat `_Ready`, tanpa ini `_Draw()` pertama bekerja dengan `Size` kosong.
4. **ScreenSpaceMainUI**: kalau `GameManager`/`TerrainManager`/karakter belum siap, label atas
   menampilkan `Menunggu <bagian yang macet> (Ns)` dan **hilang sendiri** saat sehat — jadi
   gejala "layar biru kosong" bisa dibaca dari foto layar, bukan ditebak.
