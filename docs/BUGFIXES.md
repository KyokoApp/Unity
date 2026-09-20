# Catatan Perbaikan Bug — A-Sekai

> Tujuan file ini: bila bug lama muncul lagi, AI/developer lain bisa langsung
> mengenali gejalanya, tahu akar masalah historisnya, dan tahu cara memperbaikinya
> TANPA menebak ulang dari nol. Diperbarui setiap fix penting.

---

## 1) BLUE SCREEN (layar penuh biru/teal, tanpa dunia)

### Gejala
Game boot → loading selesai → layar hanya warna biru/teal polos (langit),
tanpa terrain/objek/pemain terlihat. HUD bisa tetap muncul di atasnya.

### Prinsip utama
**Blue screen = langit render normal tapi TIDAK ADA world yang berhasil dibangun.**
Artinya `generate_async` di `project/packs/world_terrain/world.gd` mati/menyerah
di tengah jalan SETELAH `_setup_environment()` (langit jalan) tapi SEBELUM selesai
membuat chunk world. Godot tidak hard-crash — error GDScript hanya membunuh
fungsi itu diam-diam, loading screen tertutup, sisanya langit.

### Riwayat akar masalah

| Ver | Akar penyebab | Perbaikan |
|-----|---------------|-----------|
| awal | `pow(ridged_noise, 1.4)` dengan noise ridged bisa < 0 → `pow(neg,1.4) = NaN` → segitiga NaN membunuh seluruh buffer chunk GPU → pulau "tak terlihat" di perangkat (editor lolos) | `clampf(noise,0,1)` sebelum `pow`; isi `color_at`/`height_at` dengan guard NaN (`is_nan` → fallback) |
| 1.0.11 | `world._chunk_of` masih pakai offset `+8` dari grid 1600m, sementara `terrain_chunk.GRID_HALF = 4` (grid 800m) → setengah dunia tak pernah terbangun → pemain jatuh tembus tak terbatas sesaat setelah spawn | offset harus SELALU `GRID/2`, sinkron dengan `GRID_HALF`; komentar besar ditinggalkan di lokasi |
| 1.0.15 | Mode world statis (Gravity Falls GLB) — loader bisa gagal di perangkat (load/import/date) → abort → fallback tidak jalan → hanya langit | Loader dibuat defensif: setiap tahap dicek; bila hasil tak valid (`stats[1]<=0` atau grid kosong) → `queue_free()` kontainer dan **fallback otomatis** ke pulau procedural |

### Cara investigasi (urutan)
1. **Load GLB tidak mengembalikan null?** `load(STATIC_WORLD_PATH)` gagal →
   `res` bukan `PackedScene` → `return false` (aman). Tapi `instantiate()` pun
   bisa gagal — dicek terpisah.
2. **AABB degenerate** (ukuran ~0) → model korup/impor gagal → `free()` + false.
3. **Null-access membunuh coroutine**: tiap akses `mi.mesh.surface_get_arrays`
   dijaga `mesh != null`, `verts.is_empty()`, index kosong → bangun index manual
   (`PackedInt32Array(range(verts.size()))`).
4. **GDScript tidak punya try/catch.** Satu runtime error mematikan fungsi.
   Jangan biarkan blok rawan hidup dalam coroutine boot tanpa guard per-tahap +
   nilai "sukses/verifikasi" di akhir.
5. **Jangan paksa `%d` untuk float** di string format trace (bisa beda perilaku
   antar build) — cast `int(...)` eksplisit.
6. **Bukti di perangkat**: `_wtrace` menulis ke loading screen via
   `game_root._trace` — minta screenshot layar loading; baris terakhir =
   titik kematian.
7. **Wajib ada jalur fallback.** Apa pun world kustom (GLB/dsb) — kalau_loader
   gagal, build pulau procedural minimal agar game SELALU playable. Jangan
   jadikan aset pihak ketiga single point of failure.

### Anti-pola yang menyebabkan regresi ini
- Menjalankan operasi mahal/rapuh (load GLB 10MB + build collision 60k segitiga)
  langsung di dalam coroutine boot tanpa verifikasi akhir.
- Menambahkan node anak (collision/outline) SAAT iterasi `get_children()`
  tanpa penanda nama → loop anak tak berujung memproses anak buatan sendiri.
  (Solusi: suffix `_col` / `_outline` langsung `return` di walker.)
- Menyusun ekspresi kondisional berantai (`int(a if b else c)` di dalam
  `int(...) * int(...)`) — lolos lint tapi rapuh. Tulis langkah per langkah.

---

## 2) JATUH TEMBUS DUNIA TAK TERBATAS
- Penyebab: chunk collision vs visual tidak sinkron ATAU chunk tak terbangun
  (lihat kasus offset GRID di atas). Perangkat lebih ketat: chunk kosong = jatuh.
- Aturan: **semua konstanta grid dinyatakan SEKALI** (`GRID_HALF` di
  terrain_chunk.gd) dan tempat lain HARUS menurunkannya dari situ — jangan
  hard-code angka turunan (`+8`/`+4`) di `world.gd`.

---

## 3) WORLD KUSTOM (GLB STATIS) — ANALISIS CEPAT
- File: `project/packs/world_terrain/gravity_falls.glb` (9.6MB, 62k tri, 11 mesh).
- Loader: `world.gd` → `_build_static_world()` (mode statis, section
  "mode WORLD STATIS"). Konstanta suku: `STATIC_SKIP` (skybox/shadow/logo
  tidak diberi collision/outline).
- Ketinggian pijakan: grid barycentric `_static_floor_at` (bukan physics query,
  aman dipanggil dari thread/konteks apa pun).
- Bila span GLB di luar 60–480m → dinormalisasi ke ~160m (`k`).
- Spawn statis: `find_spawn_point` mode statis menyapu titik kandidat pusat;
  semua jatuh ke `(0,1,0)` bila gagal.

---

## 4) PROSEDUR RILIS CEPAT (agar fix sampai ke HP)
1. Edit kode (jaga gdparse bersih — gerbang lint wajib).
2. `python3 tools/build_packs.py --skip-export` → manifest server diperbarui.
3. Tambah baris `# rerun-kick NN` di `.github/workflows/apk_release.yml`
   (CI hanya jalan saat file itu berubah).
4. `git add -A && git commit && git push origin arena/01a0ba2f-unity`.
   - **Hati-hati race**: user upload via web uploader secara langsung; fetch
     pakai refspec penuh `'+refs/heads/arena/...:refs/remotes/origin/arena/...'`
     (fetch biasa bisa basi → rebase "up to date" palsu → push non-ff).
5. Tunggu run Actions → pastikan anotasi `content push: "game_version": "x.y.z"`.
6. Verifikasi: `gh api 'repos/KyokoApp/Unity/contents/manifest.json?ref=content'`.

| 1.0.19 | temuan kunci: konfigurasi 1.0.12 pun kini blue screen → akar kemungkinan BUKAN kode world (delivery/state perangkat). World procedural dihapus total; dunia = Gravity Falls statis + fallback bidang datar; debug diserahkan ke user | instruksi user: pasang GF + hapus world lama tanpa sisa; jaring darurat agar game SELALU boot |
| 1.0.18 | blue screen bertahan → akar diverifikasi lewat biseksi: strip total kode statis + revert konstanta ke 1.0.12-terbukti; GLB dikeluarkan dari pack | eliminasi variabel satu per satu; hasil uji menyempitkan tersangka |
| 1.0.17 | Sinkron-load GLB di boot tetap mematikan di perangkat walau sudah defensif (path boot panjang + alokasi besar) | GLB dimuat ASINKRON setelah game playable (threaded request), swap baru setelah verifikasi; boot tak pernah menunggu world kustom |

*Terakhir diperbarui: 2026-09-20 (fix blue screen total 1.0.17 — muat async+swap)*
