# CREDITS — Pulau Toon

## Aset pihak ketiga (disertakan)

### (Dihapus) Female Mannequin + Universal Animation Library 1 & 2 (Quaternius, CC0)
- Dipakai Ronde-36, **dihapus Ronde-37** (pemain kini bola api prosedural —
  lihat DECISIONS.md Ronde-37). File `.glb` tidak lagi disertakan.

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
  `day_marimba.wav`, `beach_calm.wav`, `ui_click.wav`. Hukumnya karya orisinal
  proyek ini. (ocean/footstep/jump/land/pickup/splash/emote/whoosh dihapus
  Ronde-37.)
- **Suara api `fire_loop.wav`** — disintesis prosedural oleh
  `tools/synth_fire.py` (gemuruh + desis + letupan). Karya orisinal.
- **SFX tembak/ledak `fire_shoot.wav`, `fire_explode.wav`** — disintesis
  prosedural oleh `tools/synth_fire.py` dari osilator dan noise, tanpa sampel
  eksternal. Karya orisinal.
- **Proyektil, ledakan, muzzle flash, shockwave, partikel, dan bekas gosong** —
  visual prosedural karya orisinal di `project/packs/character_player/`
  (`fire_bolt.gd`, `fire_explosion.gd`, `fire_fx.gd`, `shockwave.gdshader`).
- **Bola api (shader inti & selubung, partikel)** — ditulis untuk proyek ini
  (`project/packs/character_player/fireball_*.gdshader`, `player.gd`).

## Engine & tooling

- **Godot Engine** (4.5.x), MIT — https://godotengine.org
- **OpenJDK (jdk4py)** untuk keystore/signing Android — GPL w/ classpath exception.


- **Terrain detail textures** (`packs/shaders_materials/textures/detail_grass.jpg`, `detail_sand.jpg`)
  — dibuat AI (text-to-image) untuk proyek ini mengikuti referensi palet pengguna; bukan aset pihak ketiga.


- **Low Poly Girl** (karakter + 36 animasi) oleh Manoel "Manneko" da Rocha de Oliveira
  — lisensi bebas pakai (komersial diizinkan, redistribusi/penjualan aset dilarang);
  dipakai sebagai skin bawaan pemain (`packs/character_player/polygirl.glb`).

## Ronde-40: Monster 3D low-poly + pemain kubus

- **Quaternius LowPoly Animated Monsters** — kandidat sumber aset eksternal
  yang ditelusuri untuk ronde lanjutan; 50 monster beranimasi, CC0:
  https://quaternius.itch.io/lowpoly-animated-monsters
- **Monster roster saat ini** — delapan bentuk 3D (slime, golem, bat, mushroom,
  crawler), material, animasi bob/jalan/serang, dan percikan pemain dibuat
  procedural memakai primitive/partikel Godot; bebas lisensi dan tidak membawa
  binary eksternal sebelum arsip CC0 diverifikasi dan diintegrasikan.
- **Pemain kubus** — BoxMesh, visor, kaki, aura, ground glow, dan TravelSparks
  dirakit di `packs/character_player/player.gd`.

## Ronde-41: bentuk visual disederhanakan

- Pemain dan seluruh monster kini hanya memakai `BoxMesh` procedural buatan
  proyek ini; tidak ada aset monster eksternal yang dibundel pada ronde ini.
- Mata merah monster dan percikan gesekan tanah dibuat procedural dengan
  material/partikel Godot.

## Ronde-43: tembakan mana biru + mantra Zoltraak

- `fireball_core.gdshader`, `fireball_shell.gdshader`, `fire_bolt.gd`, dan
  `fire_explosion.gd` direvisi dari palet api oranye ke palet mana biru-putih
  dan diperkecil ukurannya; semua tetap prosedural karya proyek ini, tanpa
  aset/tekstur eksternal baru.
- `zoltraak_charge.gd` (lingkaran mantra) dan `zoltraak_bolt.gd` (gelombang
  besar) adalah skrip baru, seluruhnya prosedural (mesh primitive, partikel,
  dan `Label3D` bawaan Godot untuk huruf mantra) — tidak ada aset pihak
  ketiga yang ditambahkan.

## Ronde-45: pivot total ke game TANK (mage/monster/Zoltraak dihapus)

- Permintaan pengguna: seluruh pack mage (`player.gd` kubus mantra, mana biru,
  Zoltraak) dan roster monster (`monster.gd`/`monster_system.gd`) **dihapus
  total**, diganti murni game tank (hull+turret independen, meriam, dinding/
  bunker destructible ronde-44 dipertahankan sebagai rintangan medan tempur).
  Rencana grapple ala Attack on Titan (belum sempat dikerjakan di ronde-44)
  ikut dibatalkan.
- `player.gd` ditulis ulang penuh: BoxMesh hull + turret + laras, seluruhnya
  prosedural (karya proyek ini), tanpa aset pihak ketiga.
- `fire_bolt.gd` diganti nama & isi jadi `tank_shell.gd` (proyektil meriam);
  `fireball_core.gdshader`, `fireball_shell.gdshader`, dan `fire_explosion.gd`
  direvisi PALETNYA KEMBALI dari mana biru-putih (ronde-43) ke palet api
  oranye/merah (ledakan meriam) — tetap prosedural, tanpa tekstur eksternal.
- Sempat dicek ketersediaan aset tank 3D CC0 gratis (mis. paket "Tank" dari
  Quaternius, quaternius.com, lisensi CC0/Public Domain) sebagai kandidat
  peningkatan visual di masa depan; ronde ini TETAP memakai kubus prosedural
  (konsisten dengan gaya visual proyek sejauh ini) — belum ada aset biner
  eksternal yang diunduh/dibundel.

*Terakhir diperbarui: 2026-09-26*

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
