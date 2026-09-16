# RENCANA TAHAP 6 — rumput lebat + golem raksasa (SETELAH instal & cek bug)

> Status: RENCANA. Dikerjakan setelah APK Tahap 5 terinstal dan bug-nya
> terkonfirmasi. Fokus sampai saat itu: visual & grafik (lihat TAHAP-5.md).

## 1. Rumput lebat (prioritas user: "berasa nginjek rumput", murni Android)

Port "diet mobile" dari ide InfiniteGrass (Youssef Afella, MIT):
potret heightmap dari atas + culling GPU, tapi versi kecil —
tekstur 512–1024 (bukan 5× 2048 float), 1–2 tekstur saja, buffer
permanen (bukan alokasi per frame), jarak ±60 m, blade shader
stylized. Target: lebat di sekitar kaki, tetap jalan di HP kentang.

## 2. Golem raksasa: NPC jalan yang bisa dihajar

- **Peran**: NPC berjalan (bukan dimainkan), bisa diserang → butuh
  HP + reaksi kena-hit (sistem combat kecil, bagian dari Tahap 6).
- **Skala**: ~15–20× karakter pemain (pemain = sebesar kelingking
  golem, ±25–30 m). Terlihat dari jauh: fog 1150 m + far plane
  1200 m sudah cukup; outline toon ikut membesar otomatis.
- **Model** (semua CC0, bebas komersial, boleh masuk repo):
  1. **Stan - The Golem** (Shyr, itch.io) — golem batu low-poly,
     rigged + animated, FBX 2,1 MB.
     https://shyr-games.itch.io/stan-the-golem
  2. **Quaternius Ultimate Monsters** — 50 monster animasi (FBX/glTF),
     CC0, sekaligus stok musuh lain.
     https://quaternius.com/packs/ultimatemonsters.html
  3. Cadangan: cari "golem" di Poly Pizza (filter CC0).
- **Alur tanpa PC**: saya yang mengunduh FBX-nya dan commit ke
  `Assets/Art/Creatures/` (LFS sudah dikonfigurasi untuk `*.fbx`),
  builder menaruh + membesarkan + meng-toon-kan otomatis.
- **Catatan teknik**: FBX golem bukan VRM — tidak butuh prefab VRM;
  `ToonCharacterSetup` bekerja untuk material apa pun. Animasi: pakai
  klip bawaan model (walk/attack/death) via `AnimatorBridge`.
