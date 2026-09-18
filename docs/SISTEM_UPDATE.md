# Sistem Download, Ukuran APK & Update — Dokumentasi

Dokumen ini menjelaskan tiga perbaikan besar yang dikerjakan:

1. **Bug download "stuck di 80MB"** — akar masalah & solusi.
2. **APK di bawah 100MB** — apa yang diubah agar APK tetap ramping.
3. **Update tanpa download ulang semua data** — cara kerja & prosedur rilis.

---

## 1. Bug Download Stuck di ~80MB (FIXED)

### Akar masalah

Di `bootstrapper.tscn` lama, node `DownloadRequest` (HTTPRequest) diset `timeout = 180`.
Menurut source code Godot 4.5 (`scene/main/http_request.cpp`):

- `timeout` diimplementasikan sebagai `Timer` *one-shot* yang dimulai **sekali** saat
  `request()` dipanggil (`timer->start(timeout)`).
- Timer ini **tidak pernah di-reset** walaupun data terus mengalir.
- Saat timer habis → request dibatalkan paksa (`RESULT_TIMEOUT`).

Artinya: **setiap unduhan yang berlangsung lebih dari 180 detik pasti mati**, berapa pun
ukurannya. `assets_v1.pck` berukuran ±97MB; pada koneksi HP ±450–550 KB/s, unduhan
mencapai lebih kurang **80MB tepat saat 180 detik habis** → gagal → tombol "Coba Lagi"
mengulang **dari byte 0** → pengguna terjebak selamanya di ~80MB.

### Solusi yang diterapkan (`_script/ui/Bootstrapper.cs`)

Downloader lama berbasis `HTTPRequest` diganti **downloader kustom berbasis `HTTPClient`**
yang di-*pump* per frame, dengan fitur:

| Masalah lama | Solusi baru |
|---|---|
| Batas total 180 detik | **Tidak ada batas total**. Yang ada hanya *stall detection*: bila tidak ada byte masuk selama `StallTimeoutSec` (default 15s), koneksi dianggap macet → diputus → **dilanjutkan otomatis** |
| Gagal = ulang dari 0 | **Resume byte-range** (`Range: bytes=N-`) ke file `*.part`; retry melanjutkan dari posisi terakhir |
| Redirect GitHub 302 | Ditangani manual (maks 5 lompatan), termasuk redirect relatif |
| Tanpa verifikasi integritas | **Verifikasi ukuran + SHA256** dari manifest; file korup dibuang & diunduh bersih sekali |
| Timeout koneksi tidak jelas | `ConnectTimeoutSec` (default 20s) khusus fase connect/header |
| Tidak ada backoff | Jeda retry linear (1.5s × percobaan), maks `MaxAttempts` (default 6) |

Semua parameter bisa diubah lewat Inspector (grup **Downloader**) pada node `Bootstrapper`.

### Perilaku saat koneksi putus di tengah

- Koneksi terputus/macet → UI menampilkan *"Koneksi bermasalah, mencoba lagi dalam N dtk
  (percobaan k/6)..."* → unduhan dilanjutkan dari byte terakhir.
- File hasil unduhan disimpan sebagai `nama.pck.part` dan hanya dipindah ke `nama.pck`
  setelah lolos verifikasi → file final **tidak pernah setengah jadi/korup**.
- Tombol "Coba Lagi" kini melanjutkan antrean (resume), bukan mengulang dari nol.

---

## 2. Menjaga APK di Bawah 100MB

Sebelum: `InfiniteRunner-Lite.apk` ≈ **113MB**. Penyebab utama & perbaikannya:

| Item | Sebelum | Sesudah | Hemat |
|---|---|---|---|
| Arsip statis `lib/**.a` sisa template Godot Mono (`libmonosgen-2.0.a` 44MB dkk.) | Ikut ter-pack di APK | **Dibuang di CI** (zip trim) lalu APK di-zipalign & **re-sign** dengan keystore release — `.a` adalah arsip link-time yang tidak pernah bisa dimuat runtime Android | ~60MB |
| `videos/loading.mp4` (27MB) ikut ter-export ke APK | Ya (filter tidak mengecualikan) | **Dihapus dari repo** (duplikat persis `Amv/*.mp4`) + `videos/*.mp4` masuk `exclude_filter` | ~27MB |
| Video loading di dalam APK | mp4 27MB + ogv ~12MB (ganda) | Hanya `loading.ogv` hasil re-encode **854px, q4, tanpa audio, 24fps** | ~36MB (tersisa ±3MB) |
| Debug symbols .NET di APK | `dotnet/include_debug_symbols=true` | `false` | ~2–5MB |
| Ikon launcher `icon_192.png`/`icon_432.png` ikut ter-pack | Ya | Masuk `exclude_filter` | ~0.3MB |
| Format tekstur di paket aset | s3tc/bptc (desktop, berat & lambat di HP) | **etc2_astc=true** untuk preset `AssetPack` & `PatchPack` | load & VRAM lebih ringan |

Hasil terukur (lihat aset `apk_report.txt` di setiap release): APK turun dari **±113MB**
menjadi **±45–50MB**; paket aset dasar dari **97MB → ±49MB**; patch update biasa hanya
**±1–3MB**.

### Checklist agar APK tidak bengkak lagi

- **Jangan taruh video/gambar besar di folder yang ikut APK.** Sumber mentah (psd, mp4,
  blend, fbx) taruh di `Amv/` atau folder ber-`.gdignore` — CI yang memprosesnya.
- Aset game (model, tekstur, scene dunia) wajib tetap berada di **paket aset**
  (`_models/`, `materials/textures/`, `_scenes/` non-bootstrapper) — jangan pernah
  menghapusnya dari `exclude_filter` preset **Android**.
- Bila menambah file besar baru, cek laporan ukuran di step **Verify Builds** pada CI.
- Video loading versi OGV dibuat di CI dari `Amv/Proyek Baru 28 [7EB4FCC].mp4` — ganti
  sumbernya di situ bila ingin video baru.

---

## 3. Update Tanpa Download Ulang Semua Data

### Arsitektur

```
GitHub Release "android-apk"
├── version.json          ← manifest: daftar paket + ukuran + SHA256
├── assets_v1.pck         ← paket dasar (nama STABIL, jarang berubah)
├── patch_1.0.<N>.pck     ← patch kumulatif (hanya file berubah sejak baseline)
└── InfiniteRunner-Lite.apk
```

Di sisi HP (lihat `Bootstrapper.cs`):

1. Unduh `version.json` → bandingkan tiap paket (`name`) dengan kondisi lokal.
2. Paket dilewati (skip) bila **SHA256 + ukuran cocok** dengan catatan di
   `user://update_state.json`. Pengguna lama yang belum punya catatan state diverifikasi
   hash-nya sekali saja, lalu dicatat.
3. Hanya paket yang berubah yang diunduh → `patch_1.0.<N>.pck` biasanya cuma KB–MB.
4. Paket usang yang tidak ada lagi di manifest (mis. patch versi lama) **dihapus otomatis**
   agar penyimpanan tidak menumpuk.
5. Paket dimuat berurutan (`order`): base dulu, patch menimpa file yang berubah
   (`LoadResourcePack(..., replaceFiles: true)`).
6. Tanpa internet: bila semua paket manifest terakhir lengkap → **mode offline**, game
   tetap jalan.

### Patch kumulatif & baseline

- Patch bersifat **kumulatif terhadap `assets_v1.pck`**: pemain yang ketinggalan 5 update
  tetap cukup mengunduh **1 patch terbaru**, bukan 5 patch berurutan.
- Isi patch dihitung CI dari `git diff <baseline>..HEAD` — nilai baseline tersimpan di
  **`tools/update_pipeline/baseline_commit.txt`** (digenerate oleh
  `tools/update_pipeline/gen_patch_filter.py` → masuk ke `include_filter` preset PatchPack).

### Prosedur rilis update kecil (kasus umum)

Cukup push ke `main` / jalankan workflow — CI otomatis:

1. Membangun APK versi `1.0.<run_number>` (naik, instalasi menimpa lancar).
2. Mengekspor `patch_1.0.<run_number>.pck` berisi **file yang berubah saja**.
3. Menulis ulang `version.json` dengan hash/ukuran terbaru.
4. Menghapus patch versi lama dari release.

Pemain yang sudah punya `assets_v1.pck` **hanya mengunduh patch baru** (biasanya <2MB).

### Prosedur RE-BASE (saat patch sudah besar / aset dasar berubah banyak)

Lakukan re-base bila:

- Patch melewati ±25MB (CI memberi warning), atau
- Anda mengubah banyak aset dasar (`_models/`, tekstur, scene utama) dan ingin baseline baru.

Langkah:

1. Pastikan rilis final ter-build & `assets_v1.pck` terbaru ter-upload ke release
   (ini terjadi otomatis di setiap build).
2. Update `tools/update_pipeline/baseline_commit.txt` → isi dengan hash commit rilis itu
   (`git rev-parse HEAD`), lalu commit & push.
3. Rilis berikutnya: patch dihitung dari baseline baru (kembali kecil).
4. Client lama yang `assets_v1.pck`-nya berbeda hash akan mengunduh ulang base **sekali**
   — ini disengaja dan aman (resume + verifikasi aktif).

> **Catatan penting tentang C#:** perubahan file `.cs` tidak ikut paket aset (script
> dikompilasi ke dalam APK). Update yang mengubah kode C# selalu membutuhkan APK baru
> (versionCode naik otomatis di CI). Update konten murni (scene/tekstur/model) cukup via
> patch tanpa APK baru.

### 3.1 Semantik "update data game" ala Mobile Legends

`version.json` kini membawa tiga flag (diisi otomatis oleh `make_manifest.py`
berdasarkan `git diff` baseline→HEAD):

| Flag | Terpicu saat | Perilaku client |
|---|---|---|
| `requires_restart` | `project.godot` / `export_presets.cfg` berubah | Setelah paket terunduh & termuat, Bootstrapper menampilkan layar "Pembaruan diterapkan" lalu **menutup aplikasi otomatis (8 dtk)** atau lewat tombol "Tutup Sekarang". Saat dibuka lagi, patch langsung aktif — **tanpa instal ulang APK**, seperti update data game. |
| `needs_new_apk` | file `_script/*.cs` / `.csproj` / `.sln` berubah | Client menampilkan pemberitahuan bahwa fitur kode terbaru baru aktif lewat APK baru (`apk_url` di manifest menunjuk lokasi). Game **tetap berjalan normal** dengan kode lama — tidak dipaksa. |
| — (tanpa flag) | hanya scene/aset/shader | Full hot-apply: `LoadResourcePack(..., replaceFiles:true)` langsung mengganti resource; pemain tidak perlu melakukan apa pun. |

---

## 4. Struktur File Sistem Ini

| Path | Fungsi |
|---|---|
| `_script/ui/Bootstrapper.cs` | Downloader resume+verify, perencana update, loader paket |
| `tools/update_pipeline/baseline_commit.txt` | Titik acuan diff untuk patch kumulatif |
| `tools/update_pipeline/gen_patch_filter.py` | Generate `include_filter` PatchPack dari git diff |
| `tools/update_pipeline/make_manifest.py` | Generate `version.json` (sha256+size tiap paket) |
| `.github/workflows/android-build.yml` | Build APK+packs+manifest, unggah ke release, bersihkan aset usang |
| `export_presets.cfg` | Preset `Android` (lite), `AssetPack`, `PatchPack` dengan filter baru |

> **Bugfix (penting):** `exclude_filter` PatchPack sebelumnya berisi glob luas
> (`_models/*`, `materials/textures/*`). Di exporter Godot, *exclude glob menang
> atas include_filter*, sehingga aset model baru tidak pernah masuk patch (ukuran
> patch terlihat konstan). `gen_patch_filter.py` kini menulis ulang
> `exclude_filter` PatchPack menjadi daftar slim (konten berat-statis saja).

## 5. Troubleshooting

- **Unduhan macet lagi?** Lihat logcat tag `Godot`: baris `[Downloader] Attempt k/n ...`
  menunjukkan resume sedang bekerja. Bila server mengabaikan `Range` (HTTP 200 saat resume),
  downloader otomatis mengulang bersih dari 0 — progres tetap akurat.
- **"Hash tidak cocok" terus-menerus** → aset di release korup/tidak sinkron dengan
  manifest; rebuild & periksa step *Generate version.json Manifest*.
- **Patch tidak berisi perubahan** → pastikan perubahan ada di folder konten
  (`_scenes/`, `_models/`, `materials/`) dan baseline bukan HEAD terbaru.
- **Ukuran APK naik tiba-tiba** → cek step *Verify Builds*; kemungkinan ada file besar baru
  di folder yang ikut APK (lihat checklist bagian 2).

## Patch tidak boleh berisi project.godot
Ekspor `project.godot` otomatis menyeret `project.binary` + main scene +
seluruh autoload sebagai deps-closure (autoload bootstrapper mereferensikan
`res://_scenes/main.tscn`, jadi seluruh game ikut). Itulah penyebab patch
v1.0.142–v1.0.152 membengkak ±50 MB (sama penuhnya dengan assets penuh).
Solusinya: `ALWAYS_INCLUDE` dikosongkan dan `project.godot`/`project.binary`
masuk `NEVER_INCLUDE_FILES` di `tools/update_pipeline/gen_patch_filter.py`.
Nomor versi update tetap dapat diketahui klien dari `version.json`.
