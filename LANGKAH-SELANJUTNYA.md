# Langkah Selanjutnya (handoff sesi 2026-09-16, Tahap 5d)

> Sesi ini = `arena/01a0aa20-unity`, bercabang dari `arena/01a0a964-unity`
> (Tahap 5c). Jangan pindah branch.

## 1. Posisi sekarang

- Branch kerja: `arena/01a0aa20-unity`
- Isi **Tahap 5d** (yang dikerjakan sesi ini, sebelum APK):
  1. **Loading tidak boleh macet.** `BootPolicy`: masuk setelah 1 chunk
     dekat + 0,55 dtk, atau 1,15 dtk walau 0 chunk, dinding 4 dtk.
     Overlay punya failsafe sendiri 4,5 dtk + "ketuk untuk masuk".
     `HideImmediate` mematikan canvas. Streaming beranggaran 8 ms/frame
     (bukan 4 chunk tanpa yield yang membekukan main thread).
  2. **Kamera Genshin, rapat di belakang karakter.** Default ~3,2 m
     (bukan 5–8 m). Screenshot CI memakai `CameraRig.PlaceBehind` yang
     sama. Pitch positif = dari atas.
  3. Pose idle di screenshot: `ApplyPose` dengan dt=0 sekarang SNAP
     (dulu k=0 → T-pose salib).
  4. Stik HUD Genshin dicari malas di `CharacterMotor` (dulu null
     permanen karena HUD dibangun setelah Awake motor).

- Build **v0.3.1-tahap5c** (run `35090571180`) SUKSES, tapi loading 5c
  masih menunggu semua chunk — itulah alasan 5d.

## 2. Yang harus dilakukan setelah push (berurutan)

1. Push branch ini, lalu **tag** `v0.3.2-tahap5d` di komit 5d → workflow
   Android APK jalan (~40 menit).
2. Cek run: `gh run list -R KyokoApp/Unity --limit 5`.
3. Kalau APK sukses: Release
   `https://github.com/KyokoApp/Unity/releases/tag/v0.3.2-tahap5d`
4. User install + main:
   - Loading harus hilang ≤ ~2 detik, atau setelah ketuk.
   - Kamera harus di belakang bahu, karakter besar di sepertiga bawah.
   - Kalau kotak merah muncul: screenshot isinya.
5. **Baru setelah user oke di HP**: mulai Tahap 6
   (`RENCANA-TAHAP-6.md` — rumput lebat + golem raksasa).

## 3. Konsolidasi branch

- PR #2 (`arena/01a0a964-unity` → `main`) masih OPEN berisi 5c.
- Sesi ini **tidak** boleh push ke `main`. Merge PR #2 tetap lewat
  user/HP, atau sesi yang terikat `main`.
- Kerja 5d ada di `arena/01a0aa20-unity`. Jangan squash ke 5c.

## 4. Pengetahuan sandbox (jangan diulang)

- Blob Azure DIBLOKIR → `gh run download` gagal; pakai `attach-shots.yml`
  atau `gh api .../jobs/.../logs` + `fetch_page`.
- Tidak ada .NET SDK di sandbox → tes NUnit/unitystub tidak bisa dijalankan
  di sini. Review manual + API Unity yang dipakai harus API lama.
- `.gitignore` memblokir `*.png`; `.gitattributes` memaksa LFS.
- Jangan tulis + komit paralel dalam satu batch.
- Build APK ±40 menit. Seat lisensi: kalau "no available seats", tunggu
  ±30 menit.

## 5. File kunci 5d

| File | Isi |
|---|---|
| `Assets/_Project/Scripts/Core/BootPolicy.cs` | Kapan loading WAJIB melepas pemain |
| `Assets/_Project/Scripts/Core/CameraFraming.cs` | Zoom 3..8 → meter Genshin + orbit |
| `Assets/_Project/Tests/EditMode/BootAndCameraTests.cs` | Tes murni (tanpa Unity) |
| `Assets/_Project/Scripts/Runtime/WorldBoot.cs` | EnterWorld idempoten + anggaran waktu |
| `Assets/_Project/Scripts/Runtime/LoadingScreen.cs` | Failsafe overlay + HideImmediate |
| `Assets/_Project/Scripts/Runtime/CameraRig.cs` | Framing ~3,2 m di belakang bahu |
| `RENCANA-TAHAP-6.md` | Rumput lebat + golem (belum jalan) |
