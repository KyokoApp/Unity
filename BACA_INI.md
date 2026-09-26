# BACA INI — Ronde-37: pemain jadi BOLA API

## Yang berubah
- Mannequin + semua animasi (UAL1/UAL2) + skin **dihapus**.
- Layar kini cuma: **tanah datar (grid)** + **analog** kiri bawah.
  (Tombol pause di layar ikut disembunyikan — menu tetap terbuka lewat tombol
  **Back** Android / ESC. Mau munculkan lagi: `SHOW_PAUSE_BUTTON = true` di
  `project/packs/ui/hud.gd`.)
- Pemain = **bola api** realistis (shader plasma + selubung api + partikel
  lidah api/asap/bara + cahaya berkedip + suara api), digerakkan analog
  dengan percepatan/perlambatan halus dan ekor api yang mengikuti arah gerak.

## File baru
- `project/packs/character_player/fireball_core.gdshader`
- `project/packs/character_player/fireball_shell.gdshader`
- `project/packs/audio_sfx/fire_loop.wav` (dibuat ulang: `python3 tools/synth_fire.py`)
- `tools/synth_fire.py`

## File dihapus
- `project/packs/character_player/anim_controller.gd`
- `project/packs/character_player/assets/*.glb` (≈16,5 MB — pack jauh lebih kecil)
- SFX lama tak terpakai: ocean_loop, footstep_1/2, jump, land, pickup, splash, emote, whoosh

## Supaya masuk ke HP
Merge branch ini ke `main` → workflow **apk-release** otomatis build & terbitkan
pack baru ke branch `content` → game di HP update sendiri saat dibuka.

**BELUM DIUJI DI PERANGKAT** (sandbox tak bisa menjalankan Godot). Yang
sudah dicek: sintaks semua skrip (gdparse) + `tools/analyze_checks.py`.
