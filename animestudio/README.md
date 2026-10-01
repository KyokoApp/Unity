# 🎮 AnimeStudio di repo ini — ekstrak asset game Unity **tanpa PC**

Folder ini memasang **[AnimeStudio](https://github.com/Escartem/AnimeStudio)** (tool ekstraksi asset
game Unity buatan Escartem, MIT) ke dalam repo ini, supaya bisa jalan di **PC Windows gratis milik
GitHub** — cukup dari browser HP.

```
📱 HP kamu                  ☁️ Repo ini (KyokoApp/Unity)         💻 Runner Windows GitHub
upload bundle     →   Releases                                      AnimeStudio.CLI.exe
buka Actions,     →   Actions → AnimeStudio → Run workflow    →     bongkar bundle
isi form                                                             ↓
unduh hasil       ←   Releases / Artifacts   ←─────────────────  zip hasil + log
```

| Isi folder | Fungsi |
| --- | --- |
| `../.github/workflows/animestudio.yml` | Workflow-nya (yang menjalankan AnimeStudio di runner Windows) |
| `tools/anime.py` | Alat bantu: `kick` (jalankan), `status` (lihat), `pull` (unduh hasil) — stdlib Python, bisa dipakai dari HP/Termux/sandbox |
| `web/` | Versi web lokal (server Node.js) + UI mobile untuk dipakai di PC/VPS kalau nanti punya |

---

## 🚀 Mulai cepat (100% dari HP)

### 1. Taruh file bundle di Releases

1. Buka repo ini → tab **Releases** → **Draft a new release**
2. **Choose a tag** → tulis `bundle-v1` → *Create new tag*
3. **Attach binaries** → pilih file bundle dari HP (`.zip`, `.7z`, `.ab`, `.bin`, …). Maks **2 GB per file**.
4. **Publish release**, lalu **salin link filenya** (tekan lama → *Copy link*). Bentuknya:

   ```
   https://github.com/KyokoApp/Unity/releases/download/bundle-v1/nama-file.zip
   ```

### 2. Jalankan ekstraksi

1. Tab **Actions** → pilih **AnimeStudio — Ekstrak Asset Unity** (kiri) → **Run workflow** (kanan)
2. Isi minimal dua kolom: **game** (mis. `GI`) dan **bundle_url** (tempel link tadi)
3. **Run workflow** → tunggu **1–5 menit**. Klik run-nya untuk lihat log hidup
   (`[12/340] Exporting Texture2D: …`)

### 3. Ambil hasilnya

- Halaman run sudah selesai → bawah halaman → bagian **Artifacts** → unduh `hasil-ekstraksi-N`
- Atau set **publish_release = yes** saat menjalankan → hasil muncul di tab **Releases** (tag `extract-N`)

> ⚠️ **Repo ini PUBLIK.** Artifact & release di repo publik bisa diunduh **siapa pun**.
> Karena itu default `publish_release = no` (hasil hanya jadi artifact, tersimpan 3 hari).
> Kalau mau dipakai rutin untuk asset game lain, **pindahkan workflow ini ke repo PRIVATE** —
> sekaligus lebih aman dari sisi hak cipta.

---

## 📝 Daftar input workflow

| Input | Isi | Default |
| --- | --- | --- |
| **game** | Kode game (tabel di bawah) | `GI` |
| **bundle_url** | Link release GitHub / link http langsung / path file di repo | – |
| **types** | Jenis asset dipisah koma; **kosong = semua jenis** | `Texture2D,Sprite,TextAsset` |
| **export_type** | `Convert` (png/wav/obj siap pakai) · `Raw` · `Dump` · `JSON` | `Convert` |
| **group_assets** | `ByType` · `ByContainer` · `BySource` · `None` | `ByType` |
| **map_op** | Bikin/pakai asset map (`None` kalau tak perlu) | `None` |
| **unity_version** | mis. `2020.3.30f1`; kosong = deteksi otomatis | – |
| **cli_build** | `net10` (terbaru) / `net9` (stabil) | `net10` |
| **publish_release** | `yes` = hasil ditempel ke Releases juga | `no` |

### Kode game yang sering dipakai

| Game | Kode |
| --- | --- |
| Genshin Impact | `GI` (+ `GI_Pack`, `GI_CB1..CB3`, `GI_CB3Pre`) |
| Honkai: Star Rail | `SR` (+ `SR_CB2`) |
| Zenless Zone Zero | `ZZZ` (+ `ZZZ_CB1`, `ZZZ_CB2`) |
| Honkai Impact 3rd | `BH3` (+ `BH3Pre`, `BH3PrePre`) |
| Tears of Themis | `TOT` |
| Game Unity biasa (tanpa enkripsi) | `Normal` |
| Header dimodifikasi / Unity CN | `FakeHeader`, `UnityCN`, `PGR_GLB_KR`, … |
| Arknights: Endfield / Reverse: 1999 / Arknights / Girls' Frontline | `ArknightsEndfield`, `Reverse1999`, `Arknights`, `GirlsFrontline` |

Daftar lengkap (74 kode): jalankan `python3 animestudio/tools/anime.py games`

---

## 🔁 Memicu tanpa tombol ("kick")

Workflow ini punya **dua pintu masuk**:

| Cara | Kapan dipakai | Syarat |
| --- | --- | --- |
| Tombol **Run workflow** | sehari-hari dari HP | file workflow sudah ada di `main` (tombolnya belum muncul sebelum PR-nya di-merge) |
| **Kick file** `animestudio/trigger.json` | sekarang juga, dari branch mana pun; dipakai agent/sandbox | tidak ada |

Cara pakai kick file:

1. Buka `animestudio/trigger.json` di GitHub (dari HP pun bisa: tekan ikon ✏️).
2. Isi `game`, `bundle_url`, dan `types` (contoh lengkap ada di `animestudio/trigger.example.json`).
3. **Commit changes** → workflow AnimeStudio langsung jalan.
4. Set `"dry_run": true` kalau hanya ingin menguji input tanpa ekstraksi.

Atau lewat perintah (otomatis: coba tombol dulu, kalau belum aktif pakai jalur kick):

```bash
python3 animestudio/tools/anime.py kick --game GI --url "https://.../bundle.zip" --watch
```

---

## 🤖 Jalankan dari baris perintah (untuk sesi dev / bridge)

`animestudio/tools/anime.py` bisa dipakai tanpa browser — cocok untuk sandbox yang hanya bisa
menjangkau `api.github.com` (pola *bridge* yang sudah dipakai project ini):

```bash
export GITHUB_TOKEN=ghp_xxx        # token: scope `repo` + `workflow`

# 1) jalankan ekstraksi (langsung dipantau sampai selesai)
python3 animestudio/tools/anime.py kick \
  --game GI \
  --url "https://github.com/KyokoApp/Unity/releases/download/bundle-v1/bundle.zip" \
  --types Texture2D,TextAsset \
  --watch --pull-saat-selesai --out hasil

# 2) lihat riwayat
python3 animestudio/tools/anime.py status

# 3) unduh hasil run tertentu (artifact atau release, otomatis dibuka zip-nya)
python3 animestudio/tools/anime.py pull --run 12 --out hasil
```

Catatan token: **jangan** taruh token di dalam repo. Cukup sebagai environment variable,
dan hapus/revoke kalau sudah tidak dipakai.

---

## ⚠️ Batasan (angka per 2026)

| Batas | Angka |
| --- | --- |
| Ukuran file per release GitHub | **2 GB** (hasil > 1,8 GB otomatis dipecah `.001/.002`) |
| Runner Windows | repo **publik** = 4 core / 16 GB / disk 14 GB, **menit gratis tanpa batas** |
| Lama satu job | maks 6 jam (workflow di-set 300 menit) |
| Simpan artifact | 3 hari + kuota artifact 500 MB (hasil > 450 MB otomatis lewat Releases) |
| Waktu tipikal | 1–5 menit per ekstraksi (bundle kecil), bundel GB bisa 20+ menit |

Disk 14 GB adalah batas paling nyata: bundle 3 GB + hasil 5 GB sudah ketat. Pakai filter `types`
kalau hasilnya membengkak.

---

## 🧯 Kalau ada masalah

| Gejala | Solusi |
| --- | --- |
| Tombol *Run workflow* tidak ada | workflow belum ada di branch default (`main`). Merge PR-nya dulu, atau jalankan lewat API dengan `--branch`. |
| Selesai tapi **0 file** | 90% kode game salah (coba `GI` vs `GI_CB3`) atau filter `types` terlalu sempit → kosongkan `types`. |
| Error saat ambil bundle | link mati / bukan link langsung. Link *viewer* Google Drive tidak bisa. |
| Hasil aneh, nama berantakan | isi `unity_version` lalu jalankan ulang. |
| Error `MeshRenderer/SkinnedMeshRenderer` | batasi `types` ke `Mesh,Texture2D` saja dulu. |
| Artifact sudah hilang | cuma disimpan 3 hari. Pakai `publish_release = yes`, atau unduh lebih cepat. |

---

## 🔐 Hak cipta & etika

- Hasil ekstraksi adalah **asset milik publisher game**. Pakai untuk keperluan pribadi
  (belajar, fanart, mod pribadi). **Jangan** dijual atau disebar bebas.
- Repo ini publik: berhati-hatilah menaruh asset game di Releases/Artifacts. Untuk pemakaian rutin,
  buat repo **private** khusus untuk ekstraksi.
- Yang dijalankan tetap **AnimeStudio resmi** (diunduh dari nightly build Escartem), bukan build
  modifikasi. Kredit: Escartem, Razmoth (Studio), Perfare (AssetStudio). Lisensi MIT.

---

## 💻 Alternatif: server web lokal (`web/`)

Kalau nanti ada PC/VPS Windows, isi `web/` adalah UI web (bahasa Indonesia, ramah HP) yang
membungkus `AnimeStudio.CLI` — upload bundle → pantau progress → lihat galeri hasil → download zip,
semuanya dari HP dengan pratinjau gambar/audio/teks. Cara pakai ada di `web/README.md`.

Bandingkan:

| | Workflow GitHub (folder ini) | Web lokal (`web/`) |
| --- | --- | --- |
| Butuh | akun GitHub | Node.js + Windows |
| Batas file | 2 GB / file, disk 14 GB | sebesar disk sendiri |
| Cocok untuk | sesekali, tanpa PC | rutin, file besar, pratinjau hasil |
