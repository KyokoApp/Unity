# CREDITS — Pulau Toon

## Aset pihak ketiga (disertakan)

### Karakter & Animasi: Mannequin — "Universal Animation Library [Standard]" (v1, Quaternius)
- **Pembuat:** Quaternius — https://quaternius.com
- **File:** `project/packs/character_player/ual_mannequin.glb` (mannequin + skin + **43 animasi**)
- **Sumber:** diunggah pengguna ke branch (`Universal Animation Library[Standard]/`,
  berisi License.txt + README.txt asli); varian yang dipakai: Standard (root motion off).
- **Lisensi:** Creative Commons Zero (CC0 1.0) — domain publik
  (teks lisensi: https://creativecommons.org/publicdomain/zero/1.0/).
- **Ringkasan lisensi:** bebas dipakai/dimodifikasi untuk apa pun, termasuk komersial.

### Karakter: Knight — "KayKit Character Pack: Adventures" (v1.0)
- **Pembuat:** Kay Lousberg — https://kaylousberg.itch.io
- **File:** `project/packs/character_player/knight.glb` (+ rig & ~76 animasi)
- **Sumber:** https://github.com/KayKit-Game-Assets/KayKit-Character-Pack-Adventures-1.0
- **Lisensi:** Creative Commons Zero (CC0) — domain publik; atribusi sukarela.
- **Ringkasan lisensi:** bebas dipakai/dimodifikasi untuk kepentingan apa pun,
  termasuk komersial, tanpa wajib kredit.

## Aset buatan sendiri (prosedural, bebas lisensi)

- **Terrain/pulau, bioma, sungai & danau** — prosedural via FastNoiseLite
  (`project/packs/world_terrain/*`).
- **Vegetasi, bangunan, kerang, kerikil** — mesh low-poly dibangun via kode
  (`project/packs/world_terrain/meshlib.gd`).
- **Shaders cel/toon, outline inverted-hull, air, langit, rumput** —
  ditulis untuk proyek ini (`project/packs/shaders_materials/*`).
- **Musik & SFX** — disintesis secara prosedural dari gelombang dasar
  (osilator sinus/square/noise) oleh `tools/synth_audio.py`:
  `day_marimba.wav`, `beach_calm.wav`, `ocean_loop.wav`, footstep/jump/land/
  pickup/splash/emote/ui_click/whoosh. Hukumnya karya orisinal proyek ini.

## Engine & tooling

- **Godot Engine** (4.5.x), MIT — https://godotengine.org
- **OpenJDK (jdk4py)** untuk keystore/signing Android — GPL w/ classpath exception.


- **Terrain detail textures** (`packs/shaders_materials/textures/detail_grass.jpg`, `detail_sand.jpg`)
  — dibuat AI (text-to-image) untuk proyek ini mengikuti referensi palet pengguna; bukan aset pihak ketiga.


- **Low Poly Girl** (karakter + 36 animasi) oleh Manoel "Manneko" da Rocha de Oliveira
  — lisensi bebas pakai (komersial diizinkan, redistribusi/penjualan aset dilarang);
  dipakai sebagai skin bawaan pemain (`packs/character_player/polygirl.glb`).

*Terakhir diperbarui: 2026-09-20*

## Ronde-8: Aset Desa & Alam — KayKit Medieval Hexagon Pack (CC0)

- **KayKit Medieval Hexagon Pack** oleh Kay Lousberg — CC0 1.0
  (https://github.com/KayKit-Game-Assets/KayKit-Medieval-Hexagon-Pack-1.0)
  Dipakai: rumah (home A/B, tavern, blacksmith, windmill, church, well), pagar,
  barrel/crate/wheelbarrow, pohon tree_single_A/B, batu rock_single_A–E.

## Ronde-10: World "Gravity Falls" (upload pengguna)

- **gravity_falls.glb** — world kartun 225m (Mystery Shack area; mesh\+tekstur penuh,
  ~62k segitiga). Sumber: file `.glb` yang diunggah pengguna langsung ke branch.
  Atribusi: tema/brand Gravity Falls © Disney; model tampak berupa ekspor gaya
  Sketchfab (fan-made). Nama pembuat model BELUM terverifikasi — diminta ke
  pengguna; entri akan dilengkapi. Catat: ini kandidat yang perlu konfirmasi
  lisensi sebelum rilis publik (di luar paket CC0/CC-BY wajib).
