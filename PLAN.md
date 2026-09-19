# PLAN — Pulau Toon (Godot 4.5 Android, Third-Person Island)

Game third-person eksplorasi pulau untuk Android mid-range. Aplikasi APK hanya
*launcher*; seluruh konten game dikirim via resource pack (.pck) ber-versi.

## Tahapan kerja (checklist)

- [x] **0. Recon lingkungan** — repo kosong; sandbox tanpa Godot/JDK/SDK; jaringan
      terbatas (allowlist: GitHub API/codeload, PyPI, npm). **Solusi: GitHub Actions
      “bridge”** untuk mengambil biner (editor, export templates Android, SDK,
      paket X/GL) lalu push ke branch `arena/bridge-assets` → tarik via codeload.
- [~] **1. Setup tooling lokal** (editor Godot 4.5.2 dibangun dari source — build berjalan; JDK(keytool) ✓, aapt2 ✓; export templates & SDK belum tersedia) — install Godot 4.5.2, export templates (Android),
      Android SDK (build-tools 35, platform android-35, platform-tools), JDK
      (jdk4py), kaykit asset, Xvfb+mesa/lavapipe (screenshot GPU-less).
- [x] **2. Project setup + sistem pack + launcher** — struktur `project/` dengan
      pemisahan ketat `launcher/` vs `packs/*`; updater (manifest, versi, hash
      SHA-256, resume Range, retry backoff, offline mode, cek storage); tooling
      `tools/build_packs.py` (export_presets generator, versi hanya naik bila isi
      berubah, manifest.json); `tools/dev_server.py` (dukung Range).
- [x] **3. Terrain pulau prosedural** — chunk grid + LOD + streaming
      (WorkerThreadPool), falloff pulau, bioma (pantai/hutan/rumput/bukit,
      sungai/danau), air toon + foam pantai, langit + siklus siang-malam.
- [x] **4. Visual toon** — shader cel 3-band + rim, outline inverted-hull,
      lighting seimbang (uji screenshot, iterasi exposure), fog tipis.
- [x] **5. Karakter + animasi** — KayKit Adventurers (CC0), AnimationTree
      (locomotion blendspace + air/crouch/swim/action), anim tambahan prosedural
      untuk crouch/swim, material toon + outline.
- [x] **6. Third-person controller + touch** — CharacterBody3D halus,
      SpringArm anti-tembus, joystick virtual, tombol aksi (layout bisa diatur),
      multi-touch, safe area, pause otomatis saat background.
- [x] **7. Isi dunia + optimasi** — MultiMeshInstance3D pohon/batu/rumput/bunga,
      bangunan landmark + collider, pickup, preset kualitas Rendah/Sedang/Tinggi
      (skala render, jarak pandang, kepadatan, shadow, batas FPS), audio.
- [~] **8. Build APK** (preset+skrip ada; butuh templates+SDK+JDK lengkap) — export preset Android (arm64, landscape, permission
      INTERNET), debug keystore, build, log export; AAB via preset rilis.
- [ ] **9. Uji bukti** (menunggu biner editor: import→smoke test→pack export→uji delta/resume) — screenshot visual (Xvfb+lavapipe), uji update parsial
      (log hanya 1 pack yang diunduh), uji offline, headless error-scan.
- [x] **10. Docs final** (README/CREDITS/DECISIONS rampung; PLAN diperbarui) — README (build APK, rilis update, hosting), CREDITS,
      DECISIONS final, ringkasan + bukti.

## Struktur repo

```
Unity/
├─ project/            # Godot project root
│  ├─ project.godot
│  ├─ launcher/        # isi APK (minimal)
│  └─ packs/<id>/      # konten game, 1 folder = 1 pack
├─ tools/              # build_packs.py, dev_server.py, scripts util
├─ server/             # output: manifest.json + packs/*.pck (gitignored)
└─ .github/workflows/  # bridge.yml (ambil biner), CI smoke
```

## Cara uji cepat (setelah tooling siap)

```
python3 tools/build_packs.py           # bangun pack + manifest
python3 tools/dev_server.py 8787 server&
tools/bin/godot --headless --path project -- --server http://127.0.0.1:8787
```
