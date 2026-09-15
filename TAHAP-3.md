# Tahap 3 — dunia terlihat

Status: **kode selesai & terverifikasi sejauh yang bisa dilakukan tanpa Unity.**
Yang tersisa adalah 2 langkah di Editor (lihat "Cara menjalankan").

Rujukan rencana: `DESAIN.md` §5. Target tahap ini menurut rencana itu:
> *"Streaming chunk terrain + tekstur prosedural → **Dunia terlihat** — bukit,
> jalan, danau."*

---

## Prinsip yang dipakai di tahap ini

**Angka tidak ditebak, diukur dulu.**

Sebelum satu baris pun kode mesh ditulis, `WorldData.cs` yang sudah lolos tes
paritas terhadap JS dijalankan lewat `_verify/terrain/` untuk memetakan dunia
3 km-nya: seberapa tinggi, seberapa terjal, berapa persen yang terendam.
Semua ambang di `TerrainSurface.cs` — di mana pasir berakhir, di mana batu
mulai, di ketinggian berapa salju muncul — berasal dari persentil hasil
pengukuran itu, bukan dari angka yang terdengar wajar.

Alasannya praktis: ambang yang salah tidak memunculkan error apa pun. Dunia
hanya akan terlihat aneh, dan mencari tahu kenapa bukit jadi putih semua jauh
lebih mahal daripada mengukur sekali di awal.

**Sisi murni dipisah dari sisi Unity.**

`TerrainMesh.Build()` mengembalikan array `float[]` dan `int[]` polos, bukan
`UnityEngine.Mesh`. Jadi seluruh logika terrain bisa dites di NUnit tanpa
Unity, dan bisa diukur kecepatannya langsung. `TerrainChunkStreamer` tinggal
menyalin array itu ke `Mesh` sungguhan — pekerjaan yang tidak mengandung
keputusan apa pun.

---

## Hasil pengukuran

### Survei dunia (grid 301×301, langkah 10 m = 90.601 sampel)

```
tinggi   : min -10,0   maks 249,3   rata-rata 40,6 m
persentil: p1=-5,0  p5=-5,0  p25=17,5  p50=33,3  p75=48,0  p95=132,3  p99=215,0
terendam : 7,38% dari dunia  (sungai + 2 danau)
|gradien|: p50=0,113  p75=0,193  p90=0,431 (23°)  p95=0,985 (45°)  p99=4,083 (76°)
```

`p1 = p5 = -5,0` menjelaskan bentuk dasar air: datar, bukan landai. Dan
`p99` gradien 4,08 (76°) berarti dunia ini punya tebing yang benar-benar
vertikal — mesh harus sanggup mewakilinya tanpa jadi bubur.

### Ambang yang dipilih dari angka di atas

| Ambang | Nilai | Kenapa angka itu |
|---|---|---|
| `ShoreBottom / ShoreTop` | −3,0 / 3,5 m | dasar air datar di −5, jadi pantai harus mulai di atasnya |
| `RockStart / RockFull` | 0,35 / 0,95 | 0,35 ≈ 19° (antara p75 dan p90); 0,95 = **p95 terukur** |
| `SnowStart / SnowFull` | 150 / 200 m | antara p95 (132) dan p99 (215) — hanya puncak tertinggi |
| `SnowSlopeOff / On` | 1,10 / 0,45 | tebing terjal tidak menahan salju |
| `RoadCoreEdge / FadeEdge` | 0 / 24 | **lebih sempit** dari perataan jalan (4..42) supaya warna jalan selalu jatuh di area yang sudah datar |

### Tinggi per region (sampel radius 400 m)

```
heartlands  -5,0 ..  56,7      forest  -8,5 .. 40,7
frost       12,0 ..  84,9      bloom   12,6 .. 52,0
highlands   -5,0 ..  85,3      coast   -5,0 .. 73,6
amber       -5,0 .. 192,1
```

Hanya `amber` yang menembus 150 m. Artinya `SnowStart = 150` menempatkan
salju nyaris eksklusif di Amber Wastes — dan memang di sanalah puncak
tertinggi (249 m) berada.

### Rencana chunk

```
radius 1 :  9 chunk, jangkauan  768 m,  9 Near
radius 2 : 25 chunk, jangkauan 1.280 m, 9 Near   <- dipakai sebagai default
radius 3 : 49 chunk, jangkauan 1.792 m, 9 Near

indeks chunk valid: [-6..5] = 12 nilai per sumbu -> 144 chunk total
```

Rentangnya **asimetris**, dan ini sempat menjebak: `ChunkPlan` membuang chunk
dengan `tx * 256 >= 1500`, jadi chunk 6 (mulai di 1536) tidak valid, tapi
chunk −6 (berakhir di −1280) valid. Totalnya 144, bukan 121 seperti dugaan
awal. Tesnya sudah dikoreksi ke angka terukur.

### Biaya mesh (komputer, .NET Release)

| quads | segitiga/chunk | total @ 25 chunk | ms/chunk (4 run) |
|---|---|---|---|
| 16 | 512 | 12.800 | 0,54 – 1,44 |
| 32 | 2.048 | 51.200 | 2,01 – 4,56 |
| 64 | 8.192 | 204.800 | 7,12 – 9,94 |

**Varians antar-run besar** (sandbox ini mesin berbagi), jadi jangan baca
angka ini sebagai perkiraan untuk HP-mu. Yang bisa dipakai adalah
**rasionya**: quads 16 ≈ 3,7× lebih murah dari 32, quads 64 ≈ 3,5× lebih
mahal. Angka perangkat yang sebenarnya dilaporkan oleh menu
`Tools > Aurelia > 5` saat Play Mode (`LastBuildMs`).

### Dua hal yang diuji eksplisit karena gagal-nya diam-diam

**Retakan antar chunk — 0 selisih bit.** Chunk (0,0), (1,0), dan (0,1)
dibangun lalu verteks di perbatasannya dibandingkan komponen demi komponen:

```
quads=  8: komponen beda = 0, selisih maks = 0
quads= 16: komponen beda = 0, selisih maks = 0
quads= 32: komponen beda = 0, selisih maks = 0
```

Bukan "selisih kecil", tapi benar-benar bit yang sama. Ini terjadi karena
chunk bertetangga menyampel `TerrainH` murni pada koordinat dunia yang sama —
tidak ada akumulasi error lokal. Kalau perbandingannya memakai epsilon, tes
ini tidak akan membuktikan apa-apa.

**Winding — 0 dari 512 segitiga menghadap bawah**, `min(ny) = 0,896`. Kalau
urutannya terbalik, terrain akan terlihat normal dari atas tapi tembus
pandang dari sisi mana pun, dan bayangannya salah. Gagal-nya juga diam-diam.

---

## Yang ditambahkan

### `RPG.Core` — pure, bisa dites tanpa Unity

| Berkas | Isi |
|---|---|
| `TerrainSurface.cs` | Komposisi permukaan: gradien, jumlah batu/salju/jalan, dan warna akhir per titik. Semua ambang dari tabel di atas. |
| `TerrainMesh.cs` | `Build(cx, cz, quads)` → `ChunkMesh` berisi `float[] Vertices/Normals/Colors/UVs` + `int[] Triangles`. Juga `ChunkInWorld`, `ChunkIndex`, `HeightAt`, `DefaultQuads = 32`, `MaxQuads = 64`. |

`DefaultQuads = 32` → 8 m per segitiga. Cukup rapat untuk tebing 76° di p99,
cukup ringan untuk 25 chunk sekaligus.

### `RPG.Runtime` — sisi Unity

| Berkas | Isi |
|---|---|
| `TerrainChunkStreamer.cs` | Mengikuti karakter, minta rencana chunk dari `WorldData.ChunkPlan`, bangun **maks 1 chunk per frame**, buang yang di luar radius. Mesh bekas tidak dihancurkan — masuk pool (maks 64) dan dipakai ulang. `SetQuality(quads, radius)` disiapkan untuk Tahap 7. |
| `WaterPlane.cs` | Satu quad 1.400 m di `y = WorldData.WaterLevel`, mengikuti karakter dan **di-snap ke kelipatan ukurannya**. Semua gerakan air dikerjakan di shader. |

Snap di `WaterPlane` itu penting: quad yang menempel persis ke karakter
membuat pola gelombang "berenang" mundur saat berjalan — artefak klasik yang
sangat terlihat dan sering disalahartikan sebagai bug shader.

### Shader (URP)

| Berkas | Isi |
|---|---|
| `AureliaTerrain.shader` | Vertex color + half-Lambert + Pass `ShadowCaster` + fog. Detail noise disampel dari **posisi dunia**, bukan UV — jadi tidak ada jahitan di batas chunk. |
| `AureliaWater.shader` | Transparan. Gelombang dari posisi dunia + waktu, fresnel, specular. |
| `AureliaTerrainInput.hlsl` | `CBUFFER_START(UnityPerMaterial)` terrain. |
| `AureliaWaterInput.hlsl` | `CBUFFER_START(UnityPerMaterial)` air. |

Kenapa ada dua file `.hlsl` terpisah: **SRP Batcher menuntut properti material
berada di dalam `CBUFFER UnityPerMaterial` dan isinya identik di setiap Pass.**
Terrain punya 2 Pass (forward + shadow caster). Kalau cbuffer-nya ditulis dua
kali dengan tangan, cepat atau lambat keduanya akan berbeda — dan shader akan
diam-diam ditandai "SRP Batcher: not compatible", membuat 25 chunk jadi 50
draw call terpisah. Tidak ada error, hanya lebih lambat.

### `RPG.Editor`

`Stage2SceneBuilder.cs` diperluas, bukan diduplikasi:

```
Tools > Aurelia > 2. Bangun scene Tahap 2 (karakter saja)
Tools > Aurelia > 4. Bangun scene Tahap 3 (dunia terlihat)
Tools > Aurelia > 5. Laporkan stat terrain & air (Play Mode)
```

Menu 2 dan 4 memanggil **fungsi yang sama** dengan satu flag berbeda. Jadi
karakter, kamera, dan cahaya di kedua scene dijamin identik — kalau ada yang
terlihat beda, penyebabnya pasti terrain, bukan penyetelan scene yang kebetulan
bergeser.

Menu 4 juga menyalakan fog linear 220 → 1.150 m. Angka itu dari jangkauan
streaming: radius 2 = 1.280 m, jadi fog harus mulai menutup sebelum tepi chunk
terdekat habis, supaya chunk baru tidak muncul tiba-tiba di ujung pandang.

### Tes

`TerrainMeshTests.cs` — 25 tes baru. Total suite sekarang **46** (7 paritas +
14 RigMapping + 25 TerrainMesh).

Empat tes terakhir mengunci keamanan thread (lihat bagian berikutnya): satu
memeriksa lewat refleksi bahwa `RPG.Core` tidak punya field statis mutable,
tiga membandingkan hasil build paralel dengan sekuensial dan menuntut **bit
identik**, bukan "selisih kecil". Tes refleksi itu sudah diuji dengan kontrol
negatif — satu field statis mutable sengaja disuntikkan ke `TerrainSurface`,
dan tesnya gagal sambil menyebut nama field-nya.

---

## Verifikasi

```
_verify/nunit      dotnet test                   46/46 lulus   (25 TerrainMesh baru)
_verify/unitystub  dotnet build -c Release -warnaserror   0 error, 0 warning
_verify/terrain    dotnet run -c Release         survei + pengukuran mesh
_verify/shaders    python3 check_shader.py       SEMUA CEK LULUS
```

Keempatnya juga dipasang sebagai GitHub Actions di `.github/workflows/verify.yml`
(jalan tiap push, ~1 menit, tidak butuh Unity). Langkah terakhir di alur itu
mengubah cetakan "TIDAK ADA RETAKAN" dan "menghadap bawah: 0" dari sekadar
informasi jadi **gerbang** — kalau suatu hari ada yang mengubah `TerrainMesh`
dan retakan muncul, build-nya merah, bukan cuma log-nya berbeda.

`_verify/shaders/check_shader.py` membandingkan isi `Properties{}` dengan isi
`CBUFFER_START(UnityPerMaterial)` **per Pass**, secara mekanis. Ia sudah diuji
dengan kontrol negatif: satu properti sengaja diganti namanya, dan pemeriksa
benar-benar gagal (`exit=1`) sebelum dipulihkan. Pemeriksa yang tidak pernah
terbukti bisa gagal tidak membuktikan apa-apa.

Stub `unitystub` ikut diperluas (Mesh lengkap, MeshFilter, LayerMask,
FogMode, ShadowCastingMode, Transform.SetParent, Mathf.Round, dan overload
`Mathf.Clamp(int,int,int)`). Overload int itu perlu: tanpa dia,
`Mathf.Clamp(quads, 8, 64)` di stub mengembalikan `float` dan justru
**menyembunyikan** perbedaan tipe yang Unity asli tolak.

Dijalankan dengan `-warnaserror`, harness ini menangkap satu sisa kode mati
nyata: `var k = 0;` di `WaterPlane.EnsureMesh()` yang tidak pernah dipakai.
Sudah dihapus. Kecil, tapi warning yang dibiarkan menumpuk adalah warning yang
berhenti dibaca.

**Yang belum terverifikasi:** semua yang butuh Unity sungguhan — apakah shader
ini lolos kompilasi HLSL di GLES3/Vulkan, apakah SRP Batcher benar-benar
melaporkan "compatible", dan bagaimana rasanya secara visual. Tiga-tiganya
hanya bisa dijawab dengan menjalankan menu 4 lalu menekan Play.

---

## Performa: satu bug nyata dan satu perubahan arsitektur

Ditambahkan setelah pertanyaan "apakah ini bisa 50 fps seperti Genshin".
Jawaban jujurnya: belum bisa diketahui tanpa mengukur di perangkat. Jadi yang
dikerjakan adalah **membuang biaya yang sudah pasti ada** dan **menyediakan
alat ukurnya**.

### Bug: `Update()` mengalokasikan 614 KB per frame

Kode statistik di `TerrainChunkStreamer` menghitung segitiga dengan cara:

```csharp
foreach (var go in _active.Values) {
    var mf = go.GetComponent<MeshFilter>();
    TotalTriangles += mf.sharedMesh.triangles.Length / 3;   // <- ini
}
```

`Mesh.triangles` adalah **properti yang mengalokasikan**: setiap kali dibaca,
Unity menyalin seluruh buffer indeks ke array managed baru. Untuk 25 chunk ×
6.144 indeks, itu 614 KB sampah **setiap frame**. Pada 50 fps = 30 MB/detik
yang harus disapu GC.

Lebih parah: mesh-mesh itu sudah melewati `UploadMeshData(true)`, jadi salinan
CPU-nya sengaja dibuang. Membaca `.triangles` setelah itu bukan cuma boros —
ia memang tidak punya data untuk dibaca.

Sekarang jumlahnya disimpan bersama `GameObject` di dictionary `_active` dan
dihitung naik/turun saat `Upload`/`Release`. Tidak ada pembacaan balik mesh
sama sekali, dan `Mesh.triangles` hanya **ditulis**, tidak pernah dibaca.

### Build chunk dipindah ke thread latar

Membangun chunk terukur 2,0–4,6 ms di komputer. Di satu core HP angkanya bisa
beberapa kali lipat — cukup untuk menghabiskan seluruh budget frame 20 ms
(= 50 fps) dalam **satu frame**, tiap kali karakter menyeberang batas chunk.
Budget `MaxBuildsPerFrame = 1` membatasi jumlahnya, tapi tidak menghilangkan
sentakannya.

Karena itu build-nya sekarang jalan di thread latar. Keamanannya bukan
asumsi, tapi tiga hal yang bisa diperiksa:

1. `RPG.Core.asmdef` punya `noEngineReferences: true` — jadi `TerrainMesh.Build`
   secara **kompilasi** tidak bisa menyentuh `UnityEngine`.
2. `RPG.Core` tidak punya field statis mutable — semua statiknya `const` atau
   `static readonly` yang diisi sekali oleh type initializer CLR. Ini sekarang
   **dikunci sebagai tes refleksi**, jadi kalau nanti ada yang menambah cache
   statis, build-nya merah.
3. Hasilnya array polos yang diserahkan lewat `ConcurrentQueue`, yang
   menyediakan memory barrier.

Yang tetap di main thread hanya mengunggah array ke `Mesh` (~0,3 ms, dibatasi
`MaxUploadsPerFrame`). Jalur sinkron lama tidak dihapus — `UseBackgroundThread`
bisa dimatikan untuk membandingkan angka.

`MaxInFlight = 2`, sengaja kecil: job yang sudah masuk worker tidak bisa ditarik
kembali, jadi kalau karakter berlari 13,5 m/s dan rencana chunk berubah, kerja
basi yang terbuang maksimal 2 chunk. Hasil basi dibuang di `DrainResults`
(dihitung di `DiscardedBuilds`, kelihatan di HUD).

### Scratch buffer di `FillMesh`

Konversi `float[]` → `Vector3[]/Color[]/Vector2[]` mengalokasikan ~52 KB per
chunk, atau ~1,3 MB saat 25 chunk pertama termuat. Sekarang buffer-nya dipakai
ulang dan hanya dialokasikan ulang kalau `QuadsPerChunk` berubah — Unity
menyalin isinya ke memori native saat setter dipanggil, jadi aman.

### `PerfHud`

Overlay kecil di layar HP, tanpa kabel:

```
 48,7 fps   frame  18,2/ 20,5/  61,3 ms
spike >33 ms: 1   GC gen0: 0/s
terrain: 25 chunk, antre 0, 51.200 segitiga
  build thread  3,14 ms | upload 0,31 ms | pool 4 | buang 0
air: y=0,02, 1400 m
```

Tiga angka yang penting dibaca:

| Angka | Artinya kalau jelek |
|---|---|
| **maks frame ms** | ada sentakan. Rata-rata bagus tidak berguna kalau ini jelek — itulah kenapa min/rata/maks ditampilkan bertiga. |
| **GC gen0/s** | ada alokasi per frame. Naik saat berlari = sesuatu di jalur karakter/terrain mengalokasikan. |
| **upload ms** | ini yang benar-benar memotong budget frame, bukan `build ms`. |

F1 (desktop) atau ketuk sudut kanan-atas 3× (HP) untuk menyembunyikan.
Dipasang otomatis oleh menu 4; untuk scene lama ada menu
`Tools > Aurelia > 6. Pasang Perf HUD di scene aktif`.

### Yang belum disentuh, dan kenapa

**25 chunk = 25 draw call** (×2 dengan pass bayangan = 50). Menurunkan ini
butuh penggabungan chunk atau LOD per ring, dan keduanya berisiko
memunculkan retakan — yang justru sudah terbukti nol sekarang. Ditunda ke
Tahap 7 bersama tier kualitas, di mana angkanya sudah bisa diukur di HP.

**Karakter, bukan terrain, adalah risiko performa terbesar project ini.**
Hasil optimasi: 124.988 verteks dan **43 material** yang tidak bisa digabung
tanpa mengubah tampilan (itu batasan yang kamu pasang sendiri, dan benar).
43 material pada satu karakter = 43 draw call untuk satu karakter — lebih
banyak dari seluruh terrain. Ditambah 92 spring bone yang disimulasikan di CPU
tiap frame. Ini bukan berarti tidak bisa 50 fps; artinya kalau nanti angkanya
kurang, **yang dilihat pertama adalah karakter, bukan tanah.**

---

## Cara menjalankan

Prasyarat Tahap 2 (Active Input Handling = **Input Manager (Old)**, URP Asset,
karakter VRM sudah diimpor) tetap berlaku. Lihat `TAHAP-2.md` bagian "Cara
menjalankan".

### 1. Bangun scene

```
Tools > Aurelia > 4. Bangun scene Tahap 3 (dunia terlihat)
```

Scene tersimpan di `Assets/_Project/Scenes/Tahap3.unity`, dan dua material
(`Assets/_Project/Shaders/AureliaTerrain.mat`, `AureliaWater.mat`) dibuat
otomatis dari shader. Konsol melaporkan apa yang dipasang.

Kalau terrain muncul **magenta**: shader tidak ketemu. Pastikan folder
`Assets/_Project/Shaders/` ikut tersalin — isinya 4 berkas (2 `.shader`,
2 `.hlsl`).

### 2. Tekan Play

Yang seharusnya terlihat, urut:

1. Karakter berdiri di jalan pada `(0, 0)`, tinggi 28,0 m.
2. Chunk termuat satu per satu, menjalar keluar dari karakter. Karena
   budget-nya 1 chunk/frame, 25 chunk pertama selesai dalam ~0,4 detik —
   terlihat sebagai dunia yang "tumbuh", bukan jeda.
3. Bukit, danau di kuadran barat-daya (chunk `(-4,4)`: 32% air), jalan
   berwarna tanah memudar ke rumput di tepinya.
4. Puncak Amber Wastes bersalju kalau kamu berjalan sejauh itu.

### 3. Periksa angkanya, jangan cuma dilihat

```
Tools > Aurelia > 5. Laporkan stat terrain & air (Play Mode)
```

Isi laporannya dibanding rujukan:

| Baris | Rujukan |
|---|---|
| `TerrainH(x,z)` delta | ≈ 0,000 kalau motor menempel tanah dengan benar |
| `Chunk aktif` | 25 pada radius 2 |
| `Chunk direncanakan` | 25 — harus sama dengan chunk aktif setelah streaming selesai |
| `Build terakhir` | angka perangkatmu yang sebenarnya (komputer: 2,0–4,6 ms) |
| `Gradien / batu / salju / jalan` | nilai mentah `TerrainSurface` di titik kamu berdiri |

Kalau `Chunk aktif` tidak pernah mencapai 25, atau delta `TerrainH` tidak
mendekati nol, itu bug — bukan variasi perangkat.

---

## Keputusan yang perlu dicatat

**Kenapa vertex color, bukan splatmap/texture array.** Referensi JS-nya
mewarnai terrain lewat `TerrainColor` prosedural. Vertex color mereproduksi
hasil itu persis dengan **nol tekstur** — tidak ada sampel, tidak ada memori,
tidak ada UV yang harus dijahit. Pada 8 m per segitiga, interpolasi warna antar
verteks sudah lebih halus daripada yang bisa dibedakan di layar HP. Detail
tambahan disuntik shader lewat noise dari posisi dunia.

**Kenapa noise di shader pakai posisi dunia, bukan UV.** UV chunk di-reset ke
0..1 per chunk. Kalau noise disampel dari UV, pola detailnya berulang di tiap
chunk dan ada jahitan terlihat di setiap batas. Dari posisi dunia, polanya
bersambung tanpa sadar.

**Kenapa air satu quad, bukan plane 3 km.** Plane 3 km pada y=0 menutupi
seluruh dunia dan membuang fill-rate di tempat yang tidak terlihat — termasuk
di darat, karena blending transparan tetap dieksekusi. Quad 1.400 m (≈ 2×
jangkauan pandang radius 2) sudah menutup semua yang mungkin terlihat.

**Kenapa `UploadMeshData(true)` + pool mesh.** Setelah di-upload, salinan CPU
dibuang (~76 KB/chunk → ~1,9 MB untuk 25 chunk). Mesh bekas tetap bisa dipakai
ulang sebagai wadah karena datanya ditulis ulang sepenuhnya oleh `FillMesh`.
Kalau di perangkat ternyata `Clear(true)` pada mesh yang sudah di-upload
bermasalah, jalan keluarnya: matikan `UploadMeshData(true)` (biaya ~1,9 MB) —
jangan ganti arsitektur pool-nya.

**Kenapa `MaxBuildsPerFrame = 1`.** Bukan karena 3 ms itu berat, tapi karena
menaikkan angkanya hanya mempercepat layar pertama dan menambah risiko hitch
saat karakter berlari 13,5 m/s melintasi batas chunk. Satu chunk per frame
tidak pernah terlewat: pada kecepatan lari, karakter butuh ~19 frame untuk
menempuh satu chunk 256 m.

**Kenapa resolusi tidak boleh beda antar chunk.** Tooltip di `QuadsPerChunk`
sudah menuliskannya: beda resolusi antar chunk bertetangga = retakan. Uji
retakan di atas hanya berlaku selama semua chunk memakai `quads` yang sama.

---

## Sengaja ditunda

| Ditunda | Ke tahap | Kenapa |
|---|---|---|
| Pohon, batu, jamur, bunga | 4 | Butuh `WorldScatter` + aset Kenney; terrain harus benar dulu |
| LOD per jarak (quads beda per ring) | 7 | Butuh skema jahitan tepi; sekarang satu resolusi seragam |
| Kolisi terrain | 5 | Motor masih menempel lewat `TerrainH`, bukan `Raycast` |
| Bayangan & postfx | 7 | Pass `ShadowCaster` sudah ada, tinggal disetel |
| Pantulan/skybox di air | 7 | Fresnel sekarang pakai warna konstan |

---

## Berkas di tahap ini

```
Assets/_Project/Scripts/Core/TerrainSurface.cs         165
Assets/_Project/Scripts/Core/TerrainMesh.cs            170
Assets/_Project/Scripts/Runtime/TerrainChunkStreamer.cs 449
Assets/_Project/Scripts/Runtime/WaterPlane.cs          102
Assets/_Project/Scripts/Runtime/PerfHud.cs             180
Assets/_Project/Shaders/AureliaTerrain.shader          204
Assets/_Project/Shaders/AureliaWater.shader            139
Assets/_Project/Shaders/AureliaTerrainInput.hlsl        27
Assets/_Project/Shaders/AureliaWaterInput.hlsl          21
Assets/_Project/Tests/EditMode/TerrainMeshTests.cs     493
Assets/_Project/Scripts/Editor/Stage2SceneBuilder.cs   (+~110)
_verify/terrain/Program.cs                             (survei + ukur mesh)
_verify/shaders/check_shader.py                        131
                                                       -----
                                                       ~2.100 baris baru
```

Dijalankan ulang kapan saja:

```bash
cd _verify/terrain  && dotnet run -c Release   # survei dunia + biaya mesh
cd _verify/nunit    && dotnet test             # 42 tes
cd _verify/unitystub && dotnet build           # 0 error 0 warning
python3 _verify/shaders/check_shader.py        # Properties vs cbuffer
```

## Catatan dari perangkat (build CI ke-5, 2026-09-15)

APK pertama yang benar-benar dipasang di HP mengungkapkan dua hal yang tidak
bisa terlihat dari CI:

1. **Layar gelap seragam** — game jalan (PerfHud hidup, ~18 fps, stik
   tergambar) tapi dunia tidak kelihatan. Penyebabnya: scene dibangun dari
   `EmptyScene`, yang TIDAK punya material skybox, sementara
   `RenderSettings.ambientMode` diset `Skybox`. Ambient dari skybox yang tidak
   ada = hitam, jadi seluruh dunia hanya diterangi hampir-nol. Sekarang:
   `clearFlags = SolidColor` dengan warna sama seperti fog, dan
   `ambientMode = Flat` dengan ambient abu-abu terang. Langit sungguhan =
   pekerjaan Tahap 7.
2. **Portrait** — `defaultScreenOrientation` bawaan templat = AutoRotation, dan
   HP memilih portrait. Sekarang PlayerSettings = LandscapeLeft, plus jaring
   pengaman di `CameraRig.Awake`.

Selain itu scene Tahap 3 tidak lagi memuat bidang datar 120x120 m peninggalan
Tahap 2 (ia memotong bukit), dan PerfHud mendapat baris `DIAG` (posisi kamera,
posisi target, tinggi terrain di kamera, ada/tidaknya lampu) supaya satu
screenshot dari HP cukup untuk mendiagnosis layar gelap berikutnya tanpa
logcat.
