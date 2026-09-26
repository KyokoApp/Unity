# BACA INI — Ronde-43: hapus auto-lock, tembakan mana biru kecil, mantra Zoltraak

## Alur repository

- Remote `origin` dicek sebelum ronde ini; hanya `arena/01a0dca7-unity` yang
  ditemukan, tidak ada branch sesi lain untuk di-merge.
- Branch sesi tetap `arena/01a0dca7-unity`.
- Tidak merge ke `main` dan tidak menutup PR.
- `.github/workflows/apk_release.yml` tetap mendaftarkan branch sesi pada
  `on.push.branches`.

## Perubahan ronde ini

### Auto-aim & auto-kamera DIHAPUS

- Seluruh logic `_select_auto_target()` dan `_aim_camera_at()` di
  `player.gd` dihapus total sesuai permintaan user ("auto lock nya jelek,
  hapus ajh").
- Tembakan kembali memakai arah hadap karakter (`_facing`)/arah kamera saat
  diam, seperti sebelum ronde-42.
- Kamera benar-benar tidak lagi berputar otomatis ke arah musuh; kamera hanya
  merespons swipe dan mengikuti posisi pemain (perilaku dari ronde-41).
- Grup `enemies` yang tadinya dipakai auto-aim juga dibuang dari
  `monster.gd` karena sudah tidak dipakai.

### Tembakan biasa jadi mana biru kecil

- `fireball_core.gdshader` dan `fireball_shell.gdshader` direvisi total dari
  palet oranye/merah (api) menjadi palet biru-putih (mana): biru tua → biru
  terang → putih di tengah.
- `fire_bolt.gd`: ukuran inti/selubung/halo diperkecil (radius inti
  0.16→0.09, selubung 0.27→0.15, halo 1.3→0.65), cahaya jadi biru, partikel
  ekor direcolor biru-putih dan jumlahnya dikurangi supaya kesan "kecil".
- `fire_explosion.gd`: cahaya, bola ledakan, semburan partikel (fire/sparks/
  embers/smoke), percikan muzzle, dan cincin dampak semua direcolor biru-putih
  serta diperkecil skalanya. Bekas hangus (scorch mark) coklat dihapus,
  diganti cincin cahaya biru saja supaya terasa seperti mana, bukan api.
- Nama file/skrip (`fire_bolt.gd`, `fire_explosion.gd`, `fireball_*.gdshader`)
  sengaja TIDAK diganti agar tidak merusak preload/referensi lain; hanya isi
  visualnya yang direvisi.

### Mantra Zoltraak (skill tahan-lepas baru)

- Tap cepat tombol serang (ditahan < 0,16 detik) = satu tembakan mana biru
  kecil seperti biasa (`fire_bolt.gd`), TIDAK ADA LAGI tembakan beruntun
  selama tombol ditahan (autofire lama dihapus sesuai desain baru).
- Menahan tombol serang ≥ 0,16 detik memicu mode mantra: lingkaran sihir
  "ZOLTRAAK" (`zoltraak_charge.gd`) muncul melayang di depan karakter,
  tumbuh dari pudar (alpha/skala kecil) ke lengkap selama 5 detik
  (`CHARGE_FULL_TIME`), lengkap dengan 8 huruf "Z O L T R A A K" tersusun di
  sekeliling cincin yang berputar pelan. Lingkaran selalu menghadap kamera
  (look_at manual tiap frame) supaya hurufnya tetap terbaca dari sudut
  manapun.
- Melepas tombol kapan pun setelah mode mantra aktif langsung menembakkan
  gelombang besar Zoltraak (`zoltraak_bolt.gd`) searah hadap karakter saat
  itu. Kekuatan/ukurannya sebanding progres pengisian (0,16 detik = lemah,
  5 detik penuh = maksimal); menahan lebih dari 5 detik cukup mempertahankan
  status penuh sampai dilepas.
- Visual Zoltraak: untaian 7 segmen kapsul yang meliuk mengikuti fungsi sinus
  tegak lurus arah gerak (mensimulasikan gelombang air mengalir), warna putih
  di kepala bercampur biru tipis ke buntut, ditambah partikel kabut mana yang
  mengikuti arah gerak dengan turbulensi supaya terasa "mengalir".
- Zoltraak menembus (pierce) beberapa musuh sekaligus di jalur lintasannya,
  bukan meledak sekali kena — cocok untuk tembakan besar/ultimate. Saat
  mengenai medan atau habis jangkauan/waktu hidup, ia larut dengan percikan
  cincin cahaya biru-putih lembut (bukan ledakan api).

### Uji asap CI diperbarui

- `project/dev_probe/fire_attack_check.gd` sebelumnya mengasumsikan menahan
  tombol serang = autofire berulang (≥2 `fire_bolt.gd` dalam 0,8 detik).
  Asumsi itu sudah tidak berlaku sejak mekanik charge baru ditambahkan.
- Probe kini menguji dua jalur secara eksplisit:
  - Fase 2a & 3: TAP cepat → harus menghasilkan `fire_bolt.gd`.
  - Fase 2b: TAHAN lalu LEPAS → harus menghasilkan `zoltraak_bolt.gd`.
- Jeda antar fase diperpanjang di atas `ZOLTRAAK_COOLDOWN` (0,55 detik) agar
  cooldown tidak menelan pengujian fase berikutnya.

## Verifikasi

- Semua 20 file GDScript di `project/packs` lolos `gdparse` lokal, plus
  `project/dev_probe/fire_attack_check.gd` diperiksa terpisah.
- `python3 tools/analyze_checks.py /home/user/Unity` → `BERSIH ✓`.
- `git diff --check` → bersih.
- Uji tembak-menembak penuh (fase 2a/2b/3 probe) tervalidasi lewat GitHub
  Actions setelah push karena Godot tidak tersedia secara lokal di sandbox.

## Cara test di HP

1. Tutup game sepenuhnya lalu buka lagi agar delta terbaru terunduh.
2. Gerak dan tembak sekali (tap): pastikan warna tembakan sekarang biru dan
   ukurannya kecil, bukan bola api oranye besar.
3. Arahkan kamera manual (swipe) ke musuh, lalu tahan tombol serang: lihat
   lingkaran mantra "ZOLTRAAK" tumbuh di depan karakter selama 5 detik dengan
   huruf berputar. Kamera TIDAK boleh berputar sendiri ke arah musuh.
4. Lepas tombol serang: pastikan keluar gelombang besar putih-biru yang
   meliuk seperti air mengalir, searah hadap karakter (bukan otomatis ke
   musuh manapun).
5. Coba lepas lebih awal (sebelum 5 detik penuh): Zoltraak tetap keluar tapi
   lebih kecil/lemah dibanding yang ditahan penuh.
