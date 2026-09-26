# BACA INI — Ronde-45: pivot total ke game TANK (bag. A: hull+turret+meriam)

## Alur repository

- Remote `origin` dicek sebelum ronde ini; hanya `arena/01a0dca7-unity` yang
  ditemukan, tidak ada branch sesi lain untuk di-merge.
- Branch sesi tetap `arena/01a0dca7-unity`.
- Tidak merge ke `main` dan tidak menutup PR.
- `.github/workflows/apk_release.yml` tetap mendaftarkan branch sesi pada
  `on.push.branches`.

## Latar belakang pivot

Setelah ronde-44 bag. A (Zoltraak) & bag. B (dinding tinggi destructible)
selesai dan lolos CI, pengguna menyimpulkan game ini "lebih cocok jadi game
tank". Setelah dikonfirmasi eksplisit (lihat keputusan di bawah), seluruh
pack mage (kubus mantra Zoltraak, mana biru, monster) **dihapus total** dan
diganti murni game tank. Rencana grapple ala Attack on Titan (bag. C
ronde-44, belum sempat dikerjakan) ikut dibatalkan bersama pivot ini.

Keputusan eksplisit pengguna (lewat pertanyaan klarifikasi):
1. Kamera/kontrol: **orang ketiga di belakang tank** (bukan top-down/isometrik).
2. Inti permainan: **bertahan dari gelombang tank musuh** (wave survival) —
   akan dikerjakan di Bagian B ronde-45 (belum ada di commit ini).
3. Aset/kode mage-Zoltraak-monster-AoT: **dihapus total** dari project (bukan
   sekadar diarsipkan) — sudah dieksekusi di Bagian A ini.

## Perubahan Bagian A (commit ini)

### Dihapus total

- `player.gd` versi mage (kubus mantra + charge Zoltraak) — DITULIS ULANG
  PENUH jadi tank (lihat bawah), bukan dihapus filenya (nama file & scene
  `player.tscn` dipertahankan supaya `game_root.gd`/probe tidak perlu
  berubah).
- `fire_bolt.gd`, `zoltraak_bolt.gd`, `zoltraak_charge.gd`,
  `zoltraak_aura.gdshader`, `zoltraak_core.gdshader` — dihapus.
- `monster.gd`, `monster_system.gd` (roster monster tetap 8 ekor) — dihapus;
  `world.gd` tidak lagi menginstansiasi sistem monster.
- Rencana grapple ala Attack on Titan (belum ada kode-nya) dibatalkan; grup
  `grapple_target` dan fungsi `grapple_anchor()` di `wall.gd` dihapus karena
  tidak lagi relevan.

### Dipertahankan (reuse lintas-ronde)

- **Dinding/bunker destructible acak** (`wall.gd`/`wall_system.gd`, ronde-44
  bag. B) TETAP ADA — kini berperan sebagai rintangan/cover medan tempur
  tank yang bisa diratakan meriam. Tidak ada perubahan mekanik, hanya
  komentar direvisi (bukan lagi target grapple).
- `fire_fx.gd` (pustaka cache resource FX prosedural) dipakai apa adanya,
  tidak mage-spesifik.

### Player = tank (hull + turret independen + meriam)

- `player.gd` ditulis ulang total: badan/hull (`BoxMesh`) berputar mengikuti
  arah GERAK (seperti track tank berbelok, logika sama seperti kubus mage
  dulu), sedangkan TURRET (menara + laras) adalah node terpisah yang
  berputar independen mengikuti arah kamera/swipe (`yaw`) — persis seperti
  tank sungguhan: badan boleh jalan ke satu arah, moncong meriam tetap
  mengincar arah lain.
- Kamera third-person tidak berubah perilakunya (murni ikut swipe,
  tanpa auto-aim), tapi sekarang turret "menempel" pada arah kamera —
  jadi kamera terasa seperti membidik lewat teleskop tank.
- Serangan disederhanakan drastis dibanding mage: TAP tombol serang = SATU
  tembakan meriam (`tank_shell.gd`), lalu reload `FIRE_COOLDOWN` (1.1 detik)
  sebelum bisa menembak lagi. **TIDAK ADA lagi mode tahan-untuk-mengisi**
  (mantra Zoltraak dihapus total, tidak digantikan skill serupa di bag. A
  ini).
- Tombol "Dash" HUD dipertahankan APA ADANYA (`press_dash()`, tidak ada
  perubahan wiring HUD sama sekali di ronde ini) tapi kini berperan sebagai
  "Boost" tank: ledakan kecepatan singkat (0,5 detik) lalu cooldown panjang
  (3 detik) — cocok untuk manuver mendadak, bukan spam seperti dash mage.
- Gerak tank sengaja dibuat lebih berat/lambat dari mage (`MAX_SPEED` 10,5
  → 7,2; akselerasi lebih pelan) supaya terasa seperti kendaraan berat.
- `max_health` dinaikkan 100 → 150 (kesan tank berlapis baja).
- Kolisi pemain di `player.tscn` diganti dari `SphereShape3D` ke
  `BoxShape3D` supaya lebih pas menutupi bentuk hull tank dan bertabrakan
  lebih akurat dengan dinding/bunker kotak.

### Peluru meriam (`tank_shell.gd`, ganti nama dari `fire_bolt.gd`)

- Arsitektur proyektil (balistik: gravitasi + raycast per-frame) TIDAK
  berubah dari mekanik lama — hanya nama file & tema visual/warna yang
  berubah dari mana biru ke selongsong peluru berpijar oranye.
- Damage dinaikkan 35 → 58 (sepadan dengan reload yang lebih lambat).
- Sudah mendeteksi collider bermeta `"wall"` (dinding/bunker, ronde-44) DAN
  `"enemy_tank"` (tank musuh, akan ada objeknya mulai Bagian B ronde-45 —
  deteksinya ditambahkan sekarang secara forward-compatible, tidak
  memengaruhi apa pun karena belum ada objek berlabel itu).
- Getaran kamera saat ledakan kini benar-benar berfungsi: `tank_shell.gd`
  memanggil `shake_target.add_shake(...)` dan `player.gd` sekarang punya
  method `add_shake()` yang nyata (di mage lama method ini dipanggil tapi
  TIDAK PERNAH ada di player.gd — dead code yang tidak pernah jalan).

### Ledakan & shader direcolor (mana biru → api oranye)

- `fireball_core.gdshader`, `fireball_shell.gdshader`, `fire_explosion.gd`:
  seluruh palet warna dikembalikan dari biru-putih (ronde-43) ke oranye/
  merah (ledakan meriam khas tank) — hanya konstanta warna yang berubah,
  logika shader/partikel tetap sama persis.
- `shockwave.gdshader` TIDAK perlu diubah — defaultnya sudah oranye; yang
  berubah cuma parameter `tint` yang di-override dari skrip caller.

### Uji asap CI disederhanakan

- `project/dev_probe/fire_attack_check.gd`: fase pengujian mode
  tahan-untuk-mantra (fase 2b lama, menguji `zoltraak_bolt.gd`) DIHAPUS
  karena mekaniknya sudah tidak ada. Probe kini hanya menguji jalur TAP →
  `tank_shell.gd` muncul (fase 2 & 3), sesuai semantik serangan tank yang
  baru jauh lebih sederhana dari mage.

## Belum dikerjakan (menyusul di bagian berikutnya ronde-45)

- **Bagian B**: roster tank musuh + AI dasar (gerak + tembak) + mode
  bertahan dari gelombang (wave survival) — dunia saat ini belum ada musuh
  sama sekali setelah `monster_system.gd` dihapus.
- **Bagian C (kemungkinan)**: polish HUD (ikon tombol serang, sembunyikan
  tombol yang tidak relevan untuk tank seperti jump/crouch/emote), indikator
  reload meriam, dan pertimbangan mengganti kubus prosedural dengan aset
  tank 3D CC0 gratis (mis. paket "Tank" dari Quaternius — sudah dicek
  tersedia, belum diunduh/diintegrasikan).

## Verifikasi

- Semua 18 file GDScript di `project/packs` (+ `dev_probe/fire_attack_check.gd`)
  lolos `gdparse` lokal.
- `python3 tools/analyze_checks.py /home/user/Unity` → `BERSIH ✓`.
- `git diff --check` → bersih, tidak ada marker konflik.
- Uji CI GitHub Actions: lihat commit message untuk run ID & hasil (diisi
  setelah `gh run watch` selesai).

## Cara test di HP

1. Tutup game sepenuhnya lalu buka lagi agar delta terbaru terunduh.
2. Pastikan karakter kini tampak seperti tank kotak (hull rendah + menara +
   laras), bukan lagi kubus polos.
3. Gerakkan joystick kiri: hull tank berputar mengikuti arah gerak (seperti
   track berbelok).
4. Swipe layar untuk memutar kamera: perhatikan MENARA & LARAS ikut berputar
   mengincar arah kamera, independen dari arah gerak hull.
5. Tap tombol serang: satu peluru oranye meluncur searah laras lalu meledak
   (api oranye, bukan lagi ledakan biru). Tap lagi dengan cepat: HARUS ada
   jeda reload (~1 detik) sebelum bisa menembak lagi.
6. Tembak ke arah dinding tinggi (peninggalan ronde-44): dinding harus rusak
   dan akhirnya runtuh jadi pecahan kotak berputar setelah beberapa kali
   kena tembak.
7. Tombol "Dash" sekarang jadi "Boost": tank meluncur cepat sesaat lalu
   melambat, ada cooldown sebelum bisa dipakai lagi.
8. Belum ada musuh di dunia (menyusul Bagian B) — ini BUKAN bug, memang
   belum dikerjakan di bagian ini.

*Terakhir diperbarui: 2026-09-26*
