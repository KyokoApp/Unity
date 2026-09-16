# TAHAP 5 — Tampilan ala Genshin: toon, HUD, loading, VFX

> Urutan baca: paling dasar (karakter) → paling kompleks (rumput LOD + angin).
> Semua skrip di bawah ditulis tangan (HLSL/C#), tapi tiap bagian ada padanan
> Shader Graph-nya supaya bisa dipelajari/dimodifikasi secara visual.

## 0. Cara memakai (3 langkah)

1. Buka proyek di Unity 6000.0.32f1, pastikan paket URP + UniVRM terinstal.
2. Menu **Tools > Aurelia > 4. Bangun scene Tahap 3** (scene ini sekarang
   sudah termasuk semua sistem Tahap 5: toon, volume, HUD, loading, VFX).
3. Tekan Play: loading krem → dunia → HUD ala Genshin. Tombol `=` (kiri atas)
   membuka panel PENGATURAN (kualitas, fps, bloom, bayangan, ...).

Material permanen (properti/NPC/senjata): pilih material di Project →
menu **Aurelia > Toon > Bake Selected Materials To Toon**.

## 1. Karakter: cel shading 3-tingkat + outline (DASAR)

- Shader: `Assets/_Project/Shaders/AureliaToon.shader` (+ `AureliaToonLite`
  tanpa outline untuk rambut transparan/alis/bulu mata).
- 3 tingkat warna (terang → mid → bayangan) + 1 warna bayangan yang bisa
  disetel; transisi dilembutkan (`_ToonSoftness`) supaya tidak bergerigi.
- Ramp opsional: `Assets/_Project/Textures/ToonRamp_Default.png`
  (dibuat oleh `tools/bake_toon_textures.py`, deterministik, ikut di-commit).
  Kalau ramp tidak dipasang, shader jatuh ke fungsi prosedural — tetap toon.
- Outline: teknik *inverted hull* (pass kedua, normal didorong keluar,
  muka-depan di-cull) — 1 draw call tambahan per material, tebal per-material.
- Specular anime (kilau rambut/mata): Blinn-Phong yang dipadatkan
  (`_SpecPower` 60–90) + *rim light* lembut di tepi siluet.
- Konversi otomatis: `ToonCharacterSetup` (dipasang builder di root karakter)
  menukar SEMUA material VRM saat runtime — opaque → Toon, transparan/cutout
  → ToonLite, `_MainTex` → `_BaseMap`, emission + cull ikut disalin. Prefab
  dan file .vrm tidak diubah. Di preset Rendah, outline dimatikan otomatis
  (hemat 1 draw call + 1x vertex per material).

**Padanan Shader Graph** (kalau mau versi visual): Unlit Graph +
`Main Light Direction` → Dot dengan `Normal (World)` → `Smoothstep` 2x untuk
3 tingkat → `Lerp` 3 warna → tambah `Fresnel` untuk rim → tambah `Specular`
node untuk kilau. Outline = Graph kedua dengan node `Position (Object)` +
`Normal (Object)` × tebal, material *double-sided-flipped* (di Graph:
Cull = Front). Hasilnya sama; versi HLSL di repo dipilih supaya bisa
diperiksa CI tanpa membuka Unity.

## 2. Pencahayaan & post: volume stylized (DASAR-MENENGAH)

- `StylizedVolume` membangun URP Volume **saat runtime** (bukan aset .profile):
  bloom HALUS (threshold 0.9 — hanya langit/VFX yang memendar), color grading
  (saturasi +6, kontras +4), vignette tipis. Tanpa motion blur & volumetrik
  (mahal di GPU HP, bukan tampilan Genshin).
- Intensitas bloom 0–3 mengikuti preset kualitas; preset Rendah mematikan
  post sepenuhnya.
- **GI**: tidak ada SDFGI/HDDAGI — keduanya tidak tersedia/cocok untuk URP
  stylized di HP. Penggantinya yang dipakai di sini: ambient flat + fog
  berwarna + bayangan toon + color grading. Kombinasi ini justru yang membuat
  tampilan "anime", bukan GI realistis.
- `QualityApplier` (baru, ini perbaikan bug besar): sebelum Tahap 5, preset
  kualitas **tidak diterapkan ke apa pun**. Sekarang menerapkan render scale,
  shadow distance + cascade, fog, resolusi terrain, radius rumput, bloom,
  bayangan matahari, outline, target fps, dan adaptive resolution yang
  naik-turun mengikuti frame.

## 3. Animasi: prosedural + jalur animasi jadi (MENENGAH)

- Default tetap pose prosedural (`CharacterRig`) — diperhalus (smoothing 14,
  lean, pulse jongkok) dan digerakkan `CombatState` (kombo 3x, stamina,
  dash) yang murni-logika dan dites (`CombatTests`).
- `AnimatorBridge` (mati secara default): pasang AnimatorController dengan
  parameter Speed/Move/Grounded/Dash/Attack/Combo, centang komponennya, dan
  animasi jadi (Mixamo/Quaternius/VRM) mengambil alih. Matikan lagi untuk
  kembali ke prosedural.
- Aset gratis: **Mixamo** (gratis, puluhan animasi combat/locomotion —
  retarget ke rig VRM via Humanoid), **Quaternius** (CC0, gaya chibi),
  animasi bawaan file VRM sendiri.

## 4. VFX anime: 1 draw call (MENENGAH)

- `AnimeVFX`: pool 256 sparkle yang digambar **satu draw call** (instancing +
  `MaterialPropertyBlock`), shader `Aurelia/Sparkle` (billboard + gradasi
  radial + twinkle): `Burst/Slash/Dash/Land/Skill/Ult/SetAura`.
- Tombol E memicu skill + shake kamera; Q (energi 100%) memicu ultimate.
- Pengganti VFX Graph: di HP, VFX Graph berat; sistem pool ini tampilannya
  setara untuk sparkle/slash/ledakan kecil dengan biaya tetap.

## 5. HUD + loading ala Genshin (MENENGAH)

- `GenshinHud` (dibangun dari kode saat runtime — scene dibangun ulang
  builder, jadi prefab manual tidak bertahan): potret party + HP, kompas
  8-arah yang hidup, pelacak region (nama + subtitle dari `WorldData`),
  minimap + fps, bar stamina (muncul hanya saat terkuras), klaster aksi
  ATK/E/Q/JMP/DSH dengan cooldown radial + cincin energi ultimate, stik
  virtual kiri-bawah, dan panel PENGATURAN lengkap.
- `LoadingScreen` + `WorldBoot` (Tahap 5d): splash krem + spinner + progress
  + tips. **Tidak menunggu 25–49 chunk.** Satu chunk dekat + 0,55 dtk splash
  = masuk (`BootPolicy`). Streaming beranggaran 8 ms/frame supaya main thread
  tidak membeku. Overlay punya failsafe sendiri 4,5 dtk + "ketuk untuk masuk".
  `HideImmediate` mematikan canvas, bukan fade yang bisa nempel selamanya.
- Kamera orang ketiga (Tahap 5d): `CameraFraming` memetakan zoom menu 3..8
  (paritas JS, default 5) ke **2,35..4,40 m** (default ~3,2 m) di belakang
  bahu, FOV 50°, pitch positif = dari atas. Screenshot CI memakai framing
  yang sama — bukan offset 8 m yang membuat karakter sebesar semut.
- Semua memakai sprite prosedural (`UiKit`: lingkaran/cincin/panel) + font
  bawaan — tanpa aset luar. Kalau mau ikon beneran: ganti `UiKit.Font` dengan
  font berlisensi bebas (mis. **Nunito** — OFL, mirip font Genshin) dan
  `UiKit.Circle/Ring` dengan sprite impor; tidak ada kode lain yang berubah.

## 6. Rumput LOD + angin (KOMPLEKS)

- `GrassField`: cache sel PERSISTEN (tidak dibangun ulang tiap frame),
  2 tingkat LOD (dekat = 3 bilah, jauh = 1 bilah), instancing, mati total di
  preset Rendah.
- Angin: goyangan vertex di shader (`AureliaGrass`) — akar diam, ujung
  bergoyang mengikuti noise `WindNoise.png` + gelombang sinus; kekuatan angin
  bisa disetel per-material.
- **Padanan Shader Graph**: Graph PBR/Lit + node `Simple Noise` (UV digeser
  `Time`) → `Multiply` dengan maskapai `UV.y` (0 di akar, 1 di ujung) →
  tambah ke `Position (Object)` sebelum `Vertex Position`. Maskapai UV.y
  adalah "akar diam"-nya.

## 7. Android & draw call (ringkasan biaya)

| Fitur | Biaya | Catatan hemat |
|---|---|---|
| Toon | +1 draw call/outline | outline mati di preset Rendah |
| Bloom halus | 1 efek murah | mati total di preset Rendah |
| Rumput | 2 draw call (near+far) | radius 23–33 m, mati di Rendah |
| VFX | 1 draw call total | pool tetap 256, tanpa alokasi |
| Bayangan | 80 m, 1–2 cascade | mati total di malam hari & Rendah |
| Adaptive | render scale 0.55–1.25 | target fps dari pengaturan |

## 8. Aset gratis yang disarankan

- Animasi: **Mixamo** (adobe.com, gratis), **Quaternius** (CC0).
- Font: **Nunito / Quicksand** (OFL) — ganti satu baris di `UiKit.Font`.
- Ikon/elemen UI: **Kenney UI Pack** (CC0), **Game-icons.net** (CC-BY).
- Tekstur noise: sudah dibangkitkan (`tools/bake_toon_textures.py`).

## 9. Tahap 5e — dunia terlihat di HP, HUD tidak menumpuk

Screenshot HP 2026-09-16: game **masuk**, 49 chunk, lampu ada, kamera di
atas tanah — tapi dunia **hitam pekat**, HUD tertutup PerfHud + tombol
Pagi/Siang, dan loading 5c macet di "menabur rumput 92%" karena
`DrawMeshInstanced` tanpa `material.enableInstancing`.

Perbaikan:

1. **Tidak hitam.** Shader terrain/toon/rumput/air punya lantai
   pencahayaan (`WorldLookPolicy` / `AureliaLitFill.hlsl`): shadow
   attenuation ≥ 0,45, fill light, SH fallback, MixFog tidak menelan
   albedo. HP memakai `CameraClearFlags.SolidColor` (warna horizon),
   bukan skybox custom yang URP GLES sering skip. HDR URP dimatikan.
2. **Tidak macet di rumput.** `GrassMaterial.enableInstancing = true`,
   `LateUpdate` tidak menggambar saat loading, exception instancing
   ditelan (bukan kotak merah). `BootLog` mengabaikan log noisy itu.
3. **HUD bersih.** PerfHud default mati (F1 / ketuk sudut 3×), tombol
   suasana default mati (F2), TouchJoystick IMGUI mundur kalau
   `GenshinHud` sudah ada (stik + ATK/JMP canvas yang dipakai).

Kamera Genshin ~3,2 m dan boot 5d tetap. **Tahap 6 (golem) belum.**
