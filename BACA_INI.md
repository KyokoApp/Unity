# BACA INI — Ronde-42: rotasi balok, outline, trail, dash, auto-aim

## Alur repository

- Remote `origin` dicek sebelum ronde ini. Tidak ada branch remote
  `arena/*-unity` lain dengan pekerjaan yang perlu di-merge.
- Branch sesi tetap `arena/01a0dca7-unity`.
- Tidak merge ke `main` dan tidak menutup PR.
- Workflow `.github/workflows/apk_release.yml` tetap mendaftarkan branch sesi
  pada `on.push.branches`, sehingga push konten menjalankan build dan publish
  delta ke branch `content`.

## Perubahan ronde ini

### Balok pemain

- Balok tetap satu kubus sederhana, sekarang berputar halus ke kiri/kanan
  mengikuti `_facing` atau arah gerak/dash.
- Ditambahkan outline inverted-hull gelap (`PlayerOutline`) di sekeliling balok
  supaya silhouette tetap terbaca di layar HP.
- Percikan `GroundFrictionSparks` dihapus total.
- Diganti `CubeTrail`: ekor partikel pendek/transparan yang tertinggal di
  belakang balok selama bergerak. Trail mengikuti arah berlawanan gerak dan
  berhenti ketika pemain diam.

### Dash

- Tombol dash sekarang terlihat di HUD dan memanggil `press_dash()`.
- Dash memiliki burst cepat lalu ease-out hingga lambat, bukan gerak beruntun
  dengan kecepatan konstan.
- Cooldown dash 1,15 detik mencegah dash dipicu tanpa jeda.
- Setiap dash meninggalkan satu `DashAfterimage` berbentuk balok di posisi awal;
  bayangan membesar sedikit lalu memudar selama 0,62 detik.

### Auto-aim tembakan

- Saat menembak, pemain mencari node group `enemies` dalam jarak 30 m.
- Target normal dipilih dari musuh yang benar-benar berada di layar, dengan
  prioritas tambahan untuk yang dekat dengan tengah layar.
- Musuh di belakang kamera tetap bisa dipilih bila jaraknya maksimal 10 m;
  target dekat seperti itu mendapat skor prioritas lebih tinggi.
- Kamera langsung diarahkan ke target terpilih.
- Fire bolt diarahkan langsung ke posisi target tanpa lift balistik tambahan;
  tembakan tanpa target tetap memakai arah balok/kamera lama.
- Semua kubus monster sekarang mendaftarkan diri ke group `enemies`.

### HUD

- Tombol serang dan dash dibuat terlihat lagi agar fitur auto-aim dan dash bisa
  dites langsung di HP. Tombol aksi lain tetap tersembunyi.

## Verifikasi

- Semua 18 file GDScript lolos `gdparse` lokal.
- `python3 tools/analyze_checks.py /home/user/Unity` → `BERSIH ✓`.
- `git diff --check` → bersih.
- Build APK/PCK final akan diverifikasi GitHub Actions setelah push karena Godot
  tidak tersedia lokal di sandbox.

## Cara test di HP

1. Tutup game sepenuhnya lalu buka lagi agar delta terbaru masuk.
2. Gerakkan balok ke kanan/kiri; rotasi balok dan outline harus mengikuti arah.
3. Pastikan tidak ada percikan lama; yang terlihat adalah ekor trail di belakang.
4. Tekan dash sekali: balok melesat cepat lalu melambat, dan satu bayangan
   tertinggal di posisi awal. Tekan lagi sebelum cooldown selesai: tidak boleh
   dash kedua.
5. Tekan serang saat musuh ada di layar. Tembakan harus membelok ke kubus
   musuh dan kamera langsung ikut mengarah ke target. Musuh dekat di belakang
   juga boleh dipilih otomatis.
