# Menjalankan Aurelia tanpa komputer

Ditulis untuk kondisi nyata: **HP Android, tanpa PC.**

---

## Situasi sebenarnya (diperiksa 2026-09-15, bukan dugaan)

```
github.com/KyokoApp/Unity   ->  1 commit "Initial commit", isinya cuma README.md
                                repo status: PUBLIK
```

Seluruh project ini — 9 commit, Tahap 1–3, 46 tes, shader, optimizer karakter —
**tidak ada di GitHub dan tidak ada di mana pun selain sandbox tempat ia dibuat.**
Sandbox itu tidak permanen.

Jadi langkah pertama bukan "build APK", tapi **menyelamatkan kodenya dulu**.

Dua cadangan sudah dibuat dan bisa diunduh dari workspace:

| File | Ukuran | Isi |
|---|---|---|
| `Aurelia-Unity-2026-09-15.zip` | 187 KB | 96 file, siap dibuka di mana saja |
| `Aurelia-Unity.bundle` | 181 KB | seluruh riwayat git (9 commit) — sudah diuji, clone darinya berhasil |

Simpan keduanya di Google Drive. `.vrm` karakter tidak ikut di zip; aslinya
sudah ada di Drive-mu.

---

## Yang berubah karena Unity mencabut aktivasi manual

Dulu game-ci butuh file `.ulf` yang hanya bisa dibuat lewat **Unity Hub di
komputer**. Unity sudah menghapus aktivasi manual untuk lisensi Personal —
`license.unity3d.com/manual` sekarang mengalih ke halaman yang menyatakan
offline activation hanya untuk Enterprise/Industry.

Artinya jalur lama di `android-release.yml` (yang minta secret `UNITY_LICENSE`)
**sudah mati**. Workflow-nya sudah saya tulis ulang.

Gantinya: `game-ci/cli` sekarang punya strategi `personal` yang mengambil seat
lisensi langsung dari layanan Unity memakai **email + password**:

```
Unity.Licensing.Client --activate-all --include-personal --username ... --password ...
```

Ditambahkan di `game-ci/cli#246`, merged **2026-09-05**. `unity-builder@v6`
memakai `cliVersion: latest` jadi dapat fitur ini.

Diverifikasi dari sumbernya, bukan dari dokumentasi (dokumentasi game.ci masih
menampilkan versi lama yang menyuruh pakai `.ulf`):

```
dist/platforms/ubuntu/steps/licensing_method.sh
  rantai resolusi: file -> serial -> floating -> personal
  kalau hanya UNITY_EMAIL dan UNITY_PASSWORD yang diset -> "personal"
```

**Jadi: tidak perlu `.ulf`, tidak perlu PC.** Cukup email dan password akun Unity.

---

## Langkahnya

### 1. Privatkan repo — lakukan ini duluan

`github.com/KyokoApp/Unity` → **Settings** → paling bawah → **Danger Zone** →
**Change visibility** → Private.

Kenapa harus duluan: karakter `AureliaChar.vrm` berlisensi
`Redistribution_Prohibited`. Selama repo publik, APK yang memuat karakter itu
tidak boleh bisa diunduh publik. Workflow-nya sekarang **menolak jalan** kalau
repo publik dan VRM ikut ter-build — tapi jangan mengandalkan pengaman itu,
privatkan saja sejak awal.

Konsekuensi yang perlu kamu tahu: repo privat dapat **2.000 menit Actions/bulan**.
Satu build Unity ≈ 30–60 menit, jadi kira-kira **30–60 build per bulan**.
Cukup untuk pengembangan pribadi, tapi tidak untuk trial-and-error kasar.

### 2. Dapatkan kode ke GitHub

Ini bagian yang paling tidak enak tanpa PC. Tiga pilihan:

| Cara | Waktu | Catatan |
|---|---|---|
| **Minta agent push-kan** pakai fine-grained PAT | ~2 menit | Tercepat. Buat token khusus repo ini, izin **Contents: Read and write** saja, umur 1 hari. **Cabut token-nya segera setelah push selesai.** |
| **Termux di HP** | ~30 menit | Install Termux dari **F-Droid** (versi Play Store basi), `pkg install git unzip`, clone repo, unzip cadangan, commit, push. Paling mandiri. |
| **Upload lewat web GitHub** | berjam-jam | 96 file satu-satu. Tidak disarankan. |

### 3. Isi secrets

Repo → **Settings** → **Secrets and variables** → **Actions** → **New repository secret**:

| Nama | Isi | Wajib |
|---|---|---|
| `UNITY_EMAIL` | email akun Unity | ✅ |
| `UNITY_PASSWORD` | password akun Unity | ✅ |
| `VRM_DRIVE_ID` | ID file Drive dari `AureliaChar.vrm` | kalau mau karakter anime |

`VRM_DRIVE_ID` diambil dari URL Drive:
`https://drive.google.com/file/d/`**`1aBcDeFgHiJk...`**`/view` → bagian tebal itu ID-nya.
File-nya harus di-share **"Anyone with the link"**.

Kalau `VRM_DRIVE_ID` tidak diisi, build tetap jalan — tapi karakternya kapsul
placeholder, bukan anime.

**Belum punya akun Unity?** Daftar gratis di unity.com, pilih lisensi Personal.
Seat Personal dipakai selama build dan dikembalikan otomatis sesudahnya
(game-ci memasang EXIT trap, jadi build gagal pun seat-nya kembali).

### 4. Jalankan build

Repo → tab **Actions** → **"Android APK"** di kiri → **Run workflow** → pilih
branch `main` → biarkan `ikutVrm: true` → **Run workflow**.

Tunggu 30–60 menit (build pertama lebih lama karena harus mengunduh Unity +
mengimpor semua aset; build berikutnya jauh lebih cepat karena `Library/`
di-cache).

### 5. Unduh APK dari HP

Dua tempat:

- **Actions → run yang hijau → bagian "Artifacts" di paling bawah** → unduh `apk`.
  Ini selalu ada, dan hanya bisa diakses orang dengan akses repo.
- **Releases** (`latest-dev`) — hanya dibuat kalau repo **privat**, karena
  Release di repo publik bisa diunduh siapa saja.

Lalu: buka file `.apk` → izinkan **"Install unknown apps"** untuk browser/file
manager-mu → pasang. APK ditandatangani debug keystore (cukup untuk dipasang di
HP sendiri; tidak bisa naik ke Play Store).

---

## Yang akan kamu lihat, dan yang belum bisa dijawab dari sini

**PerfHud menyala otomatis** di pojok kiri-atas:

```
 48,7 fps   frame  18,2/ 20,5/  61,3 ms
spike >33 ms: 1   GC gen0: 0/s
terrain: 25 chunk, antre 0, 51.200 segitiga
  build thread  3,14 ms | upload 0,31 ms | pool 4 | buang 0
```

Ketuk sudut kanan-atas 3× untuk menyembunyikan.

**Yang belum bisa diverifikasi tanpa melihat layarnya:**

| Hal | Kenapa butuh mata |
|---|---|
| Shader terrain/air | sintaks HLSL hanya dikompilasi Unity; sandbox cuma bisa cek struktur + cbuffer |
| **Arah sumbu tulang VRM** | kalibrasi Tahap 2 — tidak bisa diketahui dari file `.vrm` saja |
| Apakah UniVRM menghasilkan Avatar humanoid | tergantung impor di Editor |
| SRP Batcher "compatible: Yes" | hanya terlihat di Inspector shader |

Yang kedua itu masalah nyata untuk jalur tanpa-PC: kalibrasi sumbu tulang
dirancang sebagai menu Editor (`Tools > Aurelia > 3. Uji pose karakter`).
Di APK tidak ada menu Editor. Solusinya panel uji pose di dalam APK — belum
dibuat, dan itu kerja tambahan kalau ternyata pose karakternya salah.

---

## Realita yang perlu diterima

Jalur tanpa-PC **bisa** menghasilkan APK yang bisa dimainkan. Tapi siklus
pengembangannya jadi: ubah kode → push → tunggu 30–60 menit → pasang APK →
lihat apa yang salah → ulangi. Dan kuota 2.000 menit/bulan membatasi berapa
kali itu bisa dilakukan.

Bandingkan dengan punya akses Unity di komputer: lihat hasilnya dalam 5 detik,
perbaiki, lihat lagi.

Jadi kalau ada kesempatan memakai komputer walau sebentar — warnet, teman,
sekolah — **pakai itu untuk membuka project-nya sekali saja**. Sekali lihat
Editor, banyak hal yang selama ini cuma bisa diduga jadi pasti: apakah shader
magenta, apakah tulang karakter benar, berapa fps sebenarnya. Setelah itu
kembali ke jalur CI pun jauh lebih terarah.

Sampai saat itu, semua yang bisa dikerjakan tanpa Unity sudah dikerjakan dan
terverifikasi: 46 tes, paritas terhadap modul JS asli, dan harness yang menjaga
supaya tidak mundur.
