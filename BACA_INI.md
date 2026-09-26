# BACA INI — Ronde-39: PERBAIKAN tombol serang tidak menembak

## Gejala yang dilaporkan
Sudah pencet tombol 🔥 SERANG di layar — **tidak ada tembakannya** (dan pemain
juga tidak bisa jalan / kamera mati, karena seluruh skrip pemain yang mati).

## Akar masalah (terbukti dari log build)
`fire_bolt.gd:183` menulis:

```gdscript
var distance := shake_target.global_position.distance_to(at)
```

dengan `shake_target` bertipe `Node`. `Node` **tidak punya** `global_position`,
jadi nilai itu dianggap Variant dan analyzer Godot 4.5 **tidak bisa meng-infer
tipe** untuk `:=` → **parse error keras**:

```
SCRIPT ERROR: Parse Error: Cannot infer the type of "distance" variable
          at: GDScript::reload (res://packs/character_player/fire_bolt.gd:183)
SCRIPT ERROR: Compile Error: Failed to compile depended scripts.
ERROR: Failed to load script "res://packs/character_player/player.gd" ...
```

`player.gd` me-preload `fire_bolt.gd`, jadi ikut gagal compile → pack
`character_player` yang terbit (1.0.26, game 1.0.35) membawa pemain TANPA
logika: dunia & HUD tetap tampil, tapi serangan/gerak/kamera mati total.
Parse error ini ADA sejak Ronde-38 — fitur serangan tidak pernah sempat
menembak di perangkat.

## Perbaikan
- `fire_bolt.gd`: `var shake_target: Node` → **`Node3D`**. Pemain adalah
  `CharacterBody3D` (turunan `Node3D`), jadi `global_position` kini statis
  bertipe `Vector3` dan `:=` bisa meng-infer `float`. Satu kata, bunuh semua
  error.

## Supaya tidak terulang (3 lapis pengaman baru)
1. **Probe serangan headless** (`project/dev_probe/fire_attack_check.gd`,
   dijalankan CI sebelum build pack): memuat SEMUA skrip pack (parse error
   apa pun = gagal), menanam pemain + HUD, menahan tombol serang 0,8 dtk,
   lalu **menghitung bola api yang keluar** — jalur persis tombol di layar.
   Exit ≠ 0 = build berhenti, konten tidak diterbitkan.
2. **Gembok skrip di `tools/build_packs.py`**: output `--export-pack`
   dipindai untuk `SCRIPT ERROR` / `Failed to load script` / `Parse Error` /
   `Compile Error` → build gagal keras (exit 4) SEBELUM manifest/publish.
   (Godot export exit 0 walau skrip rusak — celah yang membuat pack 1.0.26
   lolos ke perangkat.)
3. **Cek statis baru di `tools/analyze_checks.py`**: akses properti Node3D
   (`.global_position` dll.) pada variabel bertipe `Node` — apalagi di baris
   `:=` — ditandai sebagai error sebelum sampai ke Godot. Berjalan juga di
   sandbox tanpa Godot.

## Supaya masuk ke HP
Merge ke `main` (atau push ke branch kerja yang terdaftar di workflow)
memicu **apk-release**: probe serangan → build pack → publish ke branch
`content`. Tutup game sampai benar-benar mati, lalu buka lagi — hanya pack
`character_player` yang berubah (delta, ratusan KB).

Setelah update: tombol 🔥 mengeluarkan bola api (klik = 1 tembakan, tahan =
rentetan tiap 0,26 dtk), lengkap dengan muzzle flash, ekor, ledakan,
shockwave, camera shake, dan suara.
