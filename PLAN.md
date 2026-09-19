# PLAN — Pulau Toon (Godot 4.5 Android, Third-Person Island)

Game third-person eksplorasi pulau untuk Android mid-range. Aplikasi APK hanya
*launcher*; seluruh konten game dikirim via resource pack (.pck) ber-versi.

## Tahapan kerja (checklist final)

- [x] **0. Recon lingkungan** — sandbox tanpa Godot/JDK/SDK; jaringan allowlist:
      github.com core + codeload + PyPI + npm; host biner (tuxfamily, release
      assets, LFS media, debian, dl.google) diblok.
- [x] **1. Setup tooling lokal** — Godot 4.5.2-stable dibangun dari source
      (62 menit, `tools/godot-src/` sebelah repo); JDK dari PyPI jdk4py
      (Temurin 25.0.2 + keytool); aapt2 2.20 dari npm aaptjs3; apksigner.jar
      dari npm @postar/apktool-node; KayKit Adventurers (CC0) terverifikasi.
      Export templates resmi → satu-satunya aset yang tidak terjangkau (D-18).
- [x] **2. Project setup + sistem pack + launcher** — `project/launcher/` vs
      `project/packs/*`; updater: manifest ber-versi, SHA-256, resume via HTTP
      Range, retry backoff, mode offline, cek storage; `tools/build_packs.py`
      (generate export_presets, versi naik hanya untuk pack berubah, manifest);
      `tools/dev_server.py` (Range 206).
- [x] **3. Terrain pulau prosedural** — chunk grid + LOD + streaming worker,
      falloff pulau, bioma, sungai+danau (river-field cache 200×200), air toon
      + foam, sky + siklus siang-malam.
- [x] **4. Visual toon** — cel shader 3-band + rim, outline inverted-hull,
      lighting seimbang, fog ringan; bukti: `docs/screenshots/` (peta + 3 momen
      siang/senja/malam, renderer CPU shader-accurate — sandbox tanpa GPU).
- [x] **5. Karakter + animasi** — Knight.glb KayKit diririg + 76 animasi;
      AnimationTree 240 transisi (fix indentasi `_sm_setup_transitions`);
      resolver nama animasi; crouch/swim dipetakan ke varian (D-10).
- [x] **6. Third-person controller + touch** — SpringArm anti-tembus, joystick
      kiri + geser kanan multi-touch, tombol aksi (skala/posisi bisa diatur),
      safe area, pause otomatis saat background.
- [x] **7. Isi dunia + optimasi** — MultiMesh pohon/batu/rumput; visibility
      range; preset kualitas Rendah/Sedang/Tinggi (skala render, jarak pandang,
      kepadatan, shadow, batas FPS); audio prosedural.
- [~] **8. Build APK** — preset runnable arm64-v8a + INTERNET + landscape
      lengkap; keystore debug ter-generate; SDK/JDK/apksigner/aapt2
      tervalidasi satu per satu. **Bloker tunggal:** dua berkas export template
      (egress sandbox; lihat `docs/BUKTI_UJI.md` §5). Container jaringan normal:
      `sh tools/fetch_export_templates.sh && sh tools/export_android.sh`.
- [x] **9. Uji bukti** — `tools/run_all_tests.sh` → **8/8 hijau** (fresh 10
      pack, delta 1 pack ui 35 KB, resume 206, offline, 0 SCRIPT ERROR di
      ketiga run); detail: `docs/BUKTI_UJI.md`.
- [x] **10. Docs final** — README, CREDITS, DECISIONS (D-1..D-18), PLAN,
      BUKTI_UJI, skrip: build_packs/dev_server/run_all_tests/fetch_templates/
      export_android/visual_proof.

## Struktur repo

```
Unity/
├─ project/            # Godot project root
│  ├─ project.godot
│  ├─ launcher/        # isi APK (minimal)
│  ├─ packs/<id>/      # konten game, 1 folder = 1 pack
│  └─ dev_probe/       # tools dev (visual_proof.gd — ter-version)
├─ tools/              # build_packs.py, dev_server.py, run_all_tests.sh,
│                      # fetch_export_templates.sh, export_android.sh, pck_list.py
├─ server/             # output: manifest.json + packs/*.pck (gitignored)
└─ docs/               # screenshots/, BUKTI_UJI.md
```

## Cara uji cepat

```bash
export GODOT_BIN=/path/to/godot.linuxbsd.editor.x86_64
bash tools/run_all_tests.sh     # orkestrasi penuh (8/8)
```
