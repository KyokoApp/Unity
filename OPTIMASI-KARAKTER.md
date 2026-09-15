# Optimasi model karakter — apa yang diubah, apa yang tidak

Model: `Assets/Art/Characters/AureliaChar.vrm` (VRM 0.x, `specVersion 0.0`)
Skrip: `tools/vrm_optim.py` (disimpan di repo supaya bisa dijalankan ulang kalau beli model lain)

**Prinsip yang dipegang: tidak ada satu piksel pun yang berubah.**
Semua yang dibuang adalah data yang tidak pernah dibaca oleh apa pun.

---

## Hasil

| | Sebelum | Sesudah | |
|---|---|---|---|
| Ukuran file | 44,35 MB | **15,20 MB** | −66% |
| Verteks yang diimpor Unity | 1.961.488 | **124.988** | **−15,7×** |
| Morph target | 1.298 | **198** | −1.100 |
| Accessor / bufferView | 311 / 354 | 268 / 309 | − |
| Memori tekstur Android | ~301 MB | **~44,5 MB** | −85% (lewat import settings) |

Yang **tidak** berubah: 194.476 segitiga · 43 material · 216 node/tulang ·
49 humanoid bone · 92 spring bone · 13 blendshape preset · semua tekstur detail.

---

## Empat hal yang dibuang

### 1. Verteks hantu — 1.961.488 → 124.988 (ini yang paling besar)

Eksporernya (`saturday06_blender_vrm_exporter`) menulis **seluruh** vertex buffer
ke setiap primitive, bukan cuma bagian yang dipakai primitive itu:

```
Model.030      : 29 primitive -> semuanya menunjuk accessor POSITION #306 (61.790 verteks)
Body_Model_up  : 11 primitive -> semuanya menunjuk accessor POSITION #18  (10.638 verteks)
```

Di dalam file datanya cuma disimpan sekali, jadi file-nya tidak bengkak — tapi
importer Unity membangun satu vertex buffer per submesh, sehingga yang masuk
ke GPU adalah `29 × 61.790 + 11 × 10.638 + …` = **1,96 juta verteks** untuk
karakter yang geometri aslinya cuma 125 ribu.

Saya ukur dulu apakah ini aman diperbaiki:

```
Model.030      : pool 61.790 | jumlah unik per primitive 61.790 | rasio 1.00x
Body_Model_up  : pool 10.638 | jumlah unik per primitive 10.638 | rasio 1.00x
```

Rasio **1,00×** = primitive-primitive itu **mempartisi** vertex pool secara bersih,
tidak ada yang tumpang tindih. Jadi tiap primitive bisa diberi salinan verteksnya
sendiri tanpa menambah satu byte pun data geometri. Morph target ikut di-remap
bersamaan supaya delta-nya tetap melekat di verteks yang benar.

### 2. Morph target mati — 1.298 → 198

`Body_Model_up` membawa **118 morph target per primitive × 11 primitive = 1.298**.
Itu seluruh slider bentuk wajah/tubuh Koikatsu yang ikut terbawa waktu ekspor.

Yang benar-benar dirujuk `VRM.blendShapeMaster` cuma **18 indeks**:

```
a→39  i→93  u→62  e→14  o→67
blink→{19,13,20,36}  blink_l→{19,20}  blink_r→{13,36}
joy→{8,28,31}  fun→{8,28,31}  angry→{24,75,64}  sorrow→{56,5,86}
```

Sisa 100 per primitive tidak pernah diaktifkan oleh apa pun — tidak ada di
blendShapeMaster, tidak ada di material, tidak ada di animasi. Delta mereka
menempati ~24 MB. Dibuang, lalu indeks `binds` dipetakan ulang ke posisi baru.

### 3. Tekstur datar — 3 buah → 4×4

Hanya tekstur yang **terbukti** seragam yang diganti:

| Tekstur | Ukuran lama | Isi | Kenapa aman |
|---|---|---|---|
| `KK Eyeline down light.001` | 64×64 | alpha = 0 di semua piksel | sepenuhnya transparan — kontribusi render nol |
| `KK mf_m_primmaterial 3616` | 1024×1024 | 1 warna `(181,71,82,255)` | sampling di mana pun hasilnya sama |
| `KK mf_m_primmaterial 3646` | 1024×1024 | 1 warna `(181,71,82,255)` | idem |

**12 tekstur `mf_m_primmaterial` lain sengaja TIDAK disentuh.** Saya cek:
96,78% pikselnya satu warna, tapi **33.792 piksel (3,2%) beda** — itu pola nyata,
bukan noise. Meratakannya akan mengubah tampilan, jadi dibiarkan.

### 4. Accessor/bufferView yatim + dedup

354 bufferView → 309, dikemas ulang rapat dengan alignment 4 byte, dan
di-dedup berdasarkan hash isinya (beberapa accessor memang dipakai bersama).

---

## Yang TIDAK dilakukan, dan kenapa

| Usulan awal | Keputusan | Alasan |
|---|---|---|
| Decimate `Model.030` 91rb → 20rb segitiga | **tidak** | mengubah bentuk model |
| Atlas 43 material → 2–4 | **tidak** | 10 di antaranya lapisan wajah transparan yang saling bertumpuk (alis, bulu mata, mata putih, iris, gigi, lidah). Menggabungkan UV-nya merusak wajah |
| Spring bone 92 → 16 | **tidak** | mengubah gerakan rok & rambut |
| Tekstur 4096 → 1024 | **tidak di file** | ditangani di sisi Unity sebagai kompresi ASTC per-platform — sumbernya tetap utuh, build Android tetap ringan |

### Memori tekstur ditangani lewat import settings, bukan lewat file

Model ini punya 78,8 megapiksel tekstur. Kalau dibiarkan RGBA32 itu **301 MB** —
melebihi anggaran seluruh game. Solusinya bukan mengecilkan sumbernya, tapi
membiarkan Unity menyimpan versi terkompresi khusus Android:

`Assets/_Project/Scripts/Editor/VrmCharacterImportSettings.cs` memasang
**ASTC 6×6 + mipmap + mipmap streaming** untuk semua tekstur di bawah
`Assets/Art/Characters/`. Hasilnya **~44,5 MB**, dan file `.vrm`-nya tidak
disentuh sama sekali — jadi di Editor kamu tetap melihat resolusi penuh.

---

## Verifikasi

Skrip membandingkan file asli dan hasil byte-per-byte di 13 titik. Semua lolos:

```
[OK]  segitiga per material identik: 194.476 segitiga / 44 material-slot
[OK]  himpunan posisi verteks identik di 44/44 primitive
[OK]  urutan & indeks segitiga identik di 44/44 primitive (geometri bit-sama)
[OK]  216 node/tulang: nama & urutan identik
[OK]  6 skin, joints identik
[OK]  43 material identik
[OK]  parameter material (warna/alpha/doubleSided) identik
[OK]  VRM meta / lisensi tidak berubah
[OK]  49 humanoid bone identik
[OK]  92 spring bone identik
[OK]  blendshape preset identik (13)
[OK]  delta morph target tetap melekat di verteks yang benar (2.047.248 pasang)
[OK]  43/43 tekstur benar (detail bit-identik, datar -> 4x4)
```

Validasi struktural glTF/VRM atas hasilnya juga bersih: tidak ada bufferView
melampaui batas BIN, tidak ada accessor kebesaran, tidak ada alignment salah,
jumlah morph target seragam antar primitive, tidak ada `binds` yang menunjuk
indeks yang sudah dibuang.

**Yang belum bisa diverifikasi dari sini:** Unity dan UniVRM tidak ada di
sandbox. Buka di Unity, impor, dan pastikan prefab-nya muncul normal — itu satu-
satunya langkah yang tersisa. Kalau ada yang aneh, master aslinya masih ada
(44,35 MB) dan bisa dipakai kembali kapan saja.

---

## Sisa pekerjaan untuk tahap 2

Angka-angka ini sudah masuk rentang yang bisa dijalankan, tapi belum ideal:

| Metrik | Sekarang | Catatan |
|---|---|---|
| Segitiga | 194.476 | 5× target mobile. Masih bisa jalan, tapi ini batas atas |
| Material / draw call | 43 | didominasi lapisan wajah; SRP Batcher membantu |
| Spring bone | 92 | 84 di antaranya rok — kandidat pertama kalau FPS jatuh |
| Tekstur (setelah ASTC) | ~44,5 MB | aman |

Kalau nanti FPS di HP kurang, urutan yang paling murah untuk dicoba:
**(1)** turunkan ASTC ke 8×8, **(2)** throttling spring bone rok ke update tiap
2 frame, **(3)** baru decimate mesh. Nomor 3 mengubah tampilan, jadi paling akhir.
