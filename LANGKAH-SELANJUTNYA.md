# Langkah Selanjutnya (handoff sesi 2026-09-16)

> Ditulis karena limit sesi agen hampir habis. Dokumen ini = satu-satunya
> yang perlu dibaca sesi berikutnya (atau user) untuk melanjutkan.

## 1. Posisi sekarang

- Branch kerja: `arena/01a0a964-unity` (sesi Arena terikat ke branch ini).
- PR #2: `arena/01a0a964-unity` → `main`, status MERGEABLE.
  <https://github.com/KyokoApp/Unity/pull/2>
- Build **v0.3.1-tahap5c** (run `35090571180`) SEDANG JALAN saat dokumen
  ini ditulis (mulai ±11:05 UTC, build ±40 menit → cek selepas ±11:45 UTC).
- Isi v0.3.1-tahap5c (komit `92eb141`, "Tahap 5c"):
  1. `BootLog` + kotak merah error di loading + try/catch per subsistem +
     failsafe jam dinding 25 dtk → obat "macet blink di loading".
  2. Koreksi lengan-turun otomatis (T-pose "salib" → lengan rileks).
  3. Langit gradien Aurelia/Sky dipasang (sebelumnya warna datar).
  4. Shader Toon/ToonLite/Sparkle dipaksa ikut build (sebelumnya di-strip).
  5. SceneShots: karakter di-pose idle sebelum jepret (screenshot = in-game).
- Workflow `attach-shots.yml` otomatis menunggu build selesai lalu memindahkan
  PNG screenshot ke Release + folder `shots-ci/` (sebagai `.png.bin`).

## 2. Yang harus dilakukan sesi berikutnya (berurutan)

1. **Cek build**: `gh run view 35090571180 -R KyokoApp/Unity`.
   Kalau sukses → lanjut. Kalau gagal → ambil log (lihat §4) → perbaiki.
2. **Ambil screenshot**: `git pull` lalu `cp shots-ci/*.png.bin` ke luar repo
   dengan ekstensi `.png`, ATAU unduh PNG dari halaman Release (user bisa
   langsung dari browser HP).
3. **Verifikasi visual di 3 PNG** (siang/senja/malam):
   - lengan karakter TURUN (bukan salib)? Kalau masih salib/aneh → sesuaikan
     `FixArm()` di `CharacterRig.cs` (arah `wantChar`), rebuild.
   - langit GRADIEN + ada piringan matahari? Kalau masih datar → cek
     `AureliaSky.mat` + `RenderSettings.skybox` di log build.
   - karakter terlihat cel-shaded (toon)? Kalau mentah → cek log `[Toon]`.
4. **Kirim 3 PNG + link APK ke user**:
   Release: `https://github.com/KyokoApp/Unity/releases/tag/v0.3.1-tahap5c`
5. **User install + main**:
   - Kalau ada KOTAK MERAH di loading → minta screenshot-nya. Isi kotak itu
     = pesan error persis → perbaiki langsung (tidak perlu tebak-tebakan).
   - Kalau tetap macet TANPA kotak merah → minta: % terakhir, tulisan status,
     dan berapa lama ditunggu.
6. **Kalau build 5c bagus di HP** → merge PR #2 ke `main` (tombol Merge di
   browser HP), lalu mulai Tahap 6 (lihat `RENCANA-TAHAP-6.md`): rumput lebat
   + golem raksasa. Jangan mulai Tahap 6 sebelum user oke (perintah user).

## 3. Konsolidasi branch (perintah user)

- Kabar baik: **tidak ada branch sampah** — repo hanya punya `main` dan
  `arena/01a0a964-unity`. Tidak ada yang perlu dihapus.
- "Pindah ke main" = merge PR #2 (satu ketukan tombol Merge, bisa dari HP).
- Agen sesi ini DILARANG push ke `main` (aturan sesi Arena), jadi merge harus
  dilakukan user (atau sesi lain yang terikat ke `main`).
- Setelah merge: branch `arena/01a0a964-unity` boleh dihapus dari halaman
  Branches di GitHub — TAPI hanya kalau sesi Arena ini sudah selesai total,
  karena sesi ini dilacak lewat branch itu.

## 4. Pengetahuan sandbox (jangan diulang kesalahannya)

- **Blob storage Azure DIBLOKIR** dari sandbox (`*.blob.core.windows.net`,
  `release-assets.githubusercontent.com` → EOF/SSL error). Akibatnya:
  - `gh run download` (artifact) GAGAL → pakai alur `attach-shots.yml`
    (artifact → commit `.png.bin` ke branch → `git pull`).
  - `gh run view --log-failed` GAGAL → ambil log via `gh api .../jobs/.../logs`
    (dapat URL blob) lalu `fetch_page` URL itu per-chunk.
- **Tidak ada .NET SDK** dan tidak bisa diunduh (egress dibatasi) → stub gate
  `_verify/unitystub` TIDAK bisa dijalankan; gantinya review manual + pastikan
  API Unity yang dipakai adalah API lama yang pasti ada.
- `.gitignore` memblokir `*.png` (pakai `git add -f`) dan `.gitattributes`
  memaksa `*.png` lewat LFS (tanpa CLI LFS, yang ter-pull hanya pointer) →
  itulah kenapa screenshot dikirim sebagai `.png.bin`.
- Jangan menjalankan perintah tulis + baca/komit dalam SATU blok paralel
  (balapan: komit jalan sebelum tulis selesai). Sekuensikan.
- Hasil beberapa `read_file` paralel kadang tampil TERTUKAR — verifikasi dari
  isi, bukan urutan.
- Build APK ±40 menit; jangan poll tiap menit. Monitor sesi ini menulis ke
  `/home/user/apk_tahap5c_watch.log` tiap 5 menit (proses
  `pemantau-build-apk-c`, boleh dimatikan kalau sesi berakhir).
- Seat lisensi Unity: kalau build gagal dengan "no available seats", itu
  karena seat build sebelumnya tidak kembali — tunggu ±30 menit, build ulang.

## 5. File kunci

| File | Isi |
|---|---|
| `RENCANA-TAHAP-6.md` | Rencana rumput lebat + golem (belum jalan) |
| `Assets/Art/Characters/LISENSI.md` | Batasan lisensi VRM (repo PRIVATE, jangan publik) |
| `.github/workflows/attach-shots.yml` | Utilitas screenshot artifact → release + branch |
| `_verify/unitystub/README.md` | Pelajaran asmdef + strip + boot (bagian bawah) |
| `/home/user/tahap5b_shots/*.png` | Screenshot build LAMA (5b, sebelum perbaikan) |
