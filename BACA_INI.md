# Cara pasang paket ini ke repo (via web GitHub, HP saja)

## File BARU (upload via "Add file → Upload files", bikin folder dulu kalau belum ada)
- `project/packs/character_player/anim_controller.gd`
- `project/packs/character_player/assets/mannequin_f.glb`
- `project/packs/character_player/assets/ual1_standard.glb`
- `project/packs/character_player/assets/ual2_standard.glb`

## File yang DIGANTI ISINYA (timpa/replace file yang sudah ada di repo)
- `project/packs/character_player/player.gd`
- `project/packs/ui/pause_menu.gd`
- `project/packs/core_scripts/game_settings.gd`
- `CREDITS.md`
- `DECISIONS.md`
- `docs/CARA_UPDATE.md`

## Setelah semua ter-upload → WAJIB picu pipeline (tidak otomatis)
Buka repo → tab **Actions** → workflow **"apk-release"** → **Run workflow**
→ pilih branch → tombol hijau **Run workflow**. Tunggu ~2 menit.

## Ringkas yang berubah
- Karakter kini punya model: mesh **Mannequin** (Quaternius) + gabungan
  **86 animasi** dari 2 paket (UAL1 = lokomosi dasar, UAL2 = aksi/kombat).
  Semua CC0 (bebas pakai, termasuk komersial).
- Tersambung ke kontrol: jalan/lari/sprint/jongkok/lompat/renang, dash
  (roll), interact (pickup), landing, **emote** & **serang** (dua tombol
  ini sebelumnya mati sejak reset lama — sekarang hidup lagi, serang =
  kombo pedang 1 klip ~3 detik).
- Sisa ~80 animasi (berkebun, perisai, ninja-jump, zombie, dst) BELUM
  disambung ke tombol apa pun — tapi sudah siap dipanggil kapan saja
  lewat kode kalau mau dipakai buat fitur baru nanti.
- Perbaikan tambahan yang ketemu di jalan: menu Karakter di Pause dulu
  ada bug laten (dropdown nunjukin 3 pilihan tapi listnya cuma 1 —
  pilih opsi ke-2/3 bisa crash). Sudah dibetulkan sekaligus.

## ⚠️ Yang BELUM diverifikasi
Aku tidak punya editor Godot/GPU di sandbox ini, jadi build & tampilan
di perangkat asli BELUM pernah dicoba. Bagian paling berisiko: mesh
mannequin "ditumpangkan" ke skeleton dari file UAL1 (nama 65 joint
sudah kucek identik persis di ketiga file, jadi harusnya aman) — kalau
setelah build karakter tampak pose aneh/hancur, itu titik pertama yang
perlu di-screenshot & dikirim balik biar cepat kebetulin. Ukuran pack
`character_player` naik dari ~29KB jadi ~16,5MB (wajar, sekali unduh).
