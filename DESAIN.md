# Usulan desain — Aurelia di Unity (tanpa mobil)

Repo target: `github.com/KyokoApp/Unity` (sudah ada, masih kosong — 0 ref)
Referensi: `KyokoApp/rpg` (three.js). Semua angka di bawah diukur dari repo itu.

---

## 1. Keputusan ukuran map — dan kenapa

Kamu serahkan ke saya, jadi ini keputusan saya beserta alasannya.

Kecepatan karakter di game aslinya (`index.html:1317`): **jalan 6,5 m/s, lari 13,5 m/s.**
Tanpa mobil, itu satu-satunya alat tempuh. Waktu menyeberang diagonal dunia:

| Ukuran dunia | Diagonal | Lari (13,5 m/s) | Jalan (6,5 m/s) | Penilaian |
|---|---|---|---|---|
| 24 km (asli) | 33,9 km | 42 menit | 87 menit | Absurd tanpa mobil — inilah kenapa mobil ada |
| 6 km | 8,5 km | 10,5 menit | 21,8 menit | Masih terlalu besar untuk jalan kaki |
| **3 km** | **4,24 km** | **5,2 menit** | **10,9 menit** | **Pas** |
| 2 km | 2,83 km | 3,5 menit | 7,2 menit | Terlalu padat, 7 kawasan jadi sempit |

**Keputusan: 3 km × 3 km = 9 km².**

Alasannya bukan cuma angka diagonal. Game ini punya **7 kawasan** dan **fast travel**.
Supaya tiap kawasan terasa seperti sebuah tempat (bukan sepetak rumput), satu kawasan
perlu ~1 km lintasannya — sekitar 2,5 menit jalan kaki. Tujuh kawasan berukuran itu
pas masuk dunia 3 km dengan sisa margin.

Konsekuensi teknis yang harus ikut (ini yang bikin "ganti satu angka" tidak cukup):

| Parameter | Asli (24 km) | Baru (3 km) | Kenapa |
|---|---|---|---|
| `WORLD_SIZE` | 24000 | **3000** | — |
| `WORLD_LIMIT` | 11968 | **1468** | turunan |
| `ROAD_SPACING` | 3000 | **1000** | Grid 3000 m cuma menyisakan lajur 0 di dunia 3 km |
| Posisi 7 region | ±6000 | **±1000** | Supaya tetap di dalam batas |
| Ramp pegunungan utara | `smooth(1000,7000)` | **`smooth(125,875)`** | Tanpa diskala, puncak anjlok dari +282 m ke ~+40 m |
| Sungai & 2 danau | x=1600 / −3700 / 5100 | diskala ⅛ | Posisi lama jauh di luar batas 1468 m |
| Radius streaming | 3 chunk (768 m) | **2 chunk (512 m)** | Dunia kecil, 49 chunk terlalu banyak untuk 9 km² |

---

## 2. Menghapus mobil — ini justru menyederhanakan banyak hal

Yang dibuang:

| Yang hilang | Ukuran |
|---|---|
| `js/car.js` (fisika, gigi, rpm, NOS, handbrake) | 1.197 baris |
| `game/car-hud.mjs` (speedometer, tombol sentuh mobil) | 430 baris |
| `car.glb` (BMW M4 GT3) | 7,2 MB |
| Sintesis audio mesin inline-6 + wastegate + ban | sebagian besar `js/audio.js` (594 baris) |
| Mode kamera mobil (near/far/cine) | — |
| `tests/car.physics.mjs`, `car.features.mjs`, `car.model.test.mjs`, `carhud.test.mjs` | 4 file tes |

**Total ~1.600 baris + 7,2 MB tidak perlu di-port.** Dari 6.175 baris kode aplikasi,
yang benar-benar perlu dipindah tinggal ~4.500.

### Tiga keuntungan yang tidak terduga

1. **Masalah audio terberat hilang.** Yang paling sulit dari `js/audio.js` adalah
   mensintesis mesin inline-6 twin-turbo yang reaktif terhadap RPM — tidak ada
   padanannya di Unity. Yang tersisa cuma lapisan *ambient fantasy* (angin, pad akor,
   burung, shimmer sihir). Itu jauh lebih mudah, dan bisa diganti aset nyata.
2. **Satu liabilitas lisensi hilang.** Dari `CREDITS.md`: `car.glb` itu
   **CC-BY-NC-SA-4.0** — *NonCommercial*. Artinya selama ini game-mu **tidak boleh
   dikomersialkan** selama mobil itu ada. Menghapusnya menghapus batasan itu.
3. **Fokus gameplay jadi jelas.** Tanpa mobil, ini game jelajah kaki: eksplorasi,
   orb, fast travel. Tidak lagi setengah game balap.

### Yang jadi tanggung jawab baru

Karena karakter sekarang satu-satunya alat tempuh, **lokomosi jadi fitur inti**, bukan
pelengkap. Kabar baiknya `game/locomotion.mjs` sudah punya `samplePose` dengan
**25 sendi** (pelvis, spine, kaki, lengan, jari) termasuk state airborne/falling dan
3 varian combo serangan — dan itu **sudah saya port ke C# dan teruji paritas**.

---

## 3. ⚠️ Satu hal yang harus kamu putuskan: karakternya

`character.glb` adalah **Shaw / Hornet dari Hollow Knight: Silksong**, karya Seifert,
lisensi **CC-BY-4.0**.

Masalahnya bukan lisensinya — **CC-BY itu longgar**. Masalahnya modelnya adalah
**karya turunan dari game milik Team Cherry**. Mendistribusikan itu dalam aplikasi
yang bisa diunduh orang lain adalah risiko hukum yang nyata, terlepas dari CC-BY
di modelnya. Selama ini aman karena cuma PWA kecil; begitu jadi APK di GitHub
Releases yang bisa diunduh siapa saja, risikonya naik.

Tiga pilihan, urut dari yang saya sarankan:

| Pilihan | Untung | Rugi |
|---|---|---|
| **A. Ganti ke karakter CC0 asli** — Quaternius *Universal Base Characters* + *Universal Animation Library* (keduanya CC0, sudah saya cek halamannya ada) | Bersih total, ada rig + library animasi jalan/lari/serang, gaya low-poly cocok dengan aset Kenney | Kehilangan bentuk Hornet; `samplePose` 25-sendi harus dipetakan ulang ke rig baru |
| **B. Bikin karakter orisinal sendiri** | Paling aman & paling khas | Paling lama |
| **C. Tetap pakai Hornet** | Tidak ada kerja tambahan | Risiko hukum saat didistribusikan |

Saya sarankan **A**. Tapi ini keputusanmu, bukan keputusan teknis.

---

## 4. Aset — sudah saya verifikasi bisa diunduh, bukan cuma daftar link

### Terpilih: Kenney Nature Kit (CC0) — sudah saya unduh & periksa

```
https://kenney.nl/media/pages/assets/nature-kit/37ac38a37b-1677698939/kenney_nature-kit.zip
11 MB · 329 file .glb · glTF v2 VALID · License.txt di dalamnya: "Creative Commons Zero, CC0"
```

Isinya persis yang dunia fantasy-mu butuhkan:

| Kategori | Jumlah | Contoh |
|---|---|---|
| Pohon | **61** | `tree_cone`, `tree_blocks`, varian `_dark` & `_fall` |
| Tebing modular | **56** | `cliff_blockCave_rock`, `cliff_blockDiagonal_stone` |
| Batu | **30** + 30 `stone` | `rock_largeA`…`rock_largeF` |
| Rumput & semak | **4 + 8** | `grass_large`, `plant_bushDetailed` |
| Bunga | **9** | `flower_purpleA`, `flower_redB` |
| **Jamur** | **6** | `mushroom_redGroup`, `mushroom_tanTall` ← sangat fantasy |
| Patung/reruntuhan | **6** | `statue_columnDamaged`, `statue_obelisk` |
| Jembatan | **16** | `bridge_center_stone`, `bridge_side_wood` |
| Api unggun & tenda | **4 + 4** | `campfire_stones`, `tent_detailedOpen` |
| Tunggul & kayu | **7 + 4** | `stump_oldTall`, `log_stack` |
| Pagar & jalan | **12 + 7** | `fence_gate`, `path_stoneCircle` |
| Teratai | **2** | `lily_large` ← untuk danau |

Ini menutup hampir semua kebutuhan vegetasi + properti. Gayanya low-poly flat-shaded
dengan satu atlas tekstur — konsisten, dan ringan untuk mobile.

### Untuk tahap berikutnya (sudah saya cek halamannya ada, HTTP 200)

| Pack | Untuk | Lisensi |
|---|---|---|
| Quaternius *Ultimate Stylized Nature* | Tambahan vegetasi bergaya lebih "fantasy" | CC0 |
| Quaternius *Textured Fantasy Nature* | Pohon/bunga/jamur bertema fantasy | CC0 |
| Quaternius *Medieval Village MegaKit* (300+) | Desa, bangunan kerajaan | CC0 |
| Quaternius *Universal Base Characters* | Karakter (kalau pilih opsi A) | CC0 |
| Quaternius *Universal Animation Library* | Animasi jalan/lari/serang | CC0 |
| KayKit *Forest Nature Pack* | Alternatif vegetasi (100+ gratis) | CC0 |

**Kenapa CC0 semua:** kamu mau ini bisa diunduh sebagai APK. CC0 = tanpa atribusi,
tanpa batasan komersial, tidak ada yang bisa menagih nanti.

### Yang TIDAK perlu model
- **Air** — shader, bukan mesh. Referensi sudah ada di `world-data.mjs`.
- **Terrain** — prosedural dari `terrainH()`, bukan heightmap.
- **Langit/kabut** — URP Volume + skybox.

---

## 5. Rencana bertahap

Sesuai permintaanmu: tidak saya bangun semua sekaligus.

| Tahap | Isi | Hasil yang terlihat |
|---|---|---|
| **0** | Repo + keputusan desain *(dokumen ini)* | — |
| **1** | `RPG.Core`: world data 3 km, quality preset, lokomosi — **sudah jadi, tinggal disesuaikan ke 3 km & tanpa mobil** | Tes hijau, belum ada gambar |
| **2** | Character controller + kamera + `samplePose` → **karakter bisa jalan di dunia kosong** | Kotak kapsul berjalan di bidang datar |
| **3** | Streaming chunk terrain + tekstur prosedural | **Dunia terlihat** — bukit, jalan, danau |
| **4** | Aset Kenney disebar pakai `randomForChunk` (RNG deterministik yang sudah ada) | **Hutan, batu, jamur, bunga** |
| **5** | Orb + loop gameplay + HUD | **Bisa dimainkan** |
| **6** | Audio ambient | Dunia bersuara |
| **7** | Postfx (bloom/god rays) + tier kualitas | Cantik + lancar di HP |
| **8** | Build APK → GitHub Releases | **Bisa diinstal** |

Tahap 2 adalah titik di mana kamu pertama kali melihat sesuatu bergerak. Menurut saya
itu milestone yang tepat untuk dicek sebelum lanjut — kalau rasanya salah, lebih murah
berhenti di situ daripada setelah tahap 4.

---

## 6. Yang berubah dari rencana sebelumnya

- Pipeline render: **URP** (sudah pasti — kamu pilih target Android/APK, dan HDRP
  tidak mendukung Android/iOS sama sekali).
- PWA/GitHub Pages: **tidak relevan lagi** untuk jalur APK. Halaman `site/index.html`
  yang sudah saya buat tetap berguna sebagai halaman unduh, tapi bukan cara install utama.
- `carCamera`, `stickShape` mobil, dan semua preset terkait mobil: dihapus dari
  `GameSettings`.
