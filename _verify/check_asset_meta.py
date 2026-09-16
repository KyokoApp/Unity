#!/usr/bin/env python3
"""Pastikan setiap aset Unity yang dilacak git punya .meta yang dilacak juga.

Mengapa ini ada (dan mengapa ia harus gagal, bukan cuma peringatan):
GUID sebuah aset Unity TIDAK disimpan di dalam berkas asetnya, ia disimpan di
berkas .meta di sebelahnya. Kalau .meta tidak ikut di repo, Unity membuat yang
BARU (acak) setiap kali proyek di-import -- dan di CI, setiap build adalah
import baru. Semua rujukan antar-aset di proyek ini (scene -> naskah MonoBehaviour,
material -> shader, ProjectSettings -> URP asset) adalah rujukan GUID, jadi
rujukan itu patah diam-diam: tidak ada error, yang ada objek tidak tergambar.

Buktinya run v0.2.0-cel-fix20: tiga .mat di-commit tanpa .shader.meta di repo ->
screenshot editor berubah dari (175,185,155) jadi magenta (225,55,233) = warna
"material tidak menemukan shader"-nya Unity. Run sebelumnya (fix19) lolos hanya
karena asetnya dibuat dan dipakai di dalam run yang sama.

Aturan: berkas ber-ekstensi aset di bawah Assets/ yang dilacak git HARUS punya
<f>.meta yang dilacak git juga. Ekstensi yang tidak dikenal Unity dilewati
(.md, .txt, .json konfigurasi harness, dst) supaya tidak cerewet.

Dipakai di .github/workflows/verify.yml -- murah, tanpa Unity, dan menangkap
regresi ini dalam hitungan detik, bukan dalam satu jam build + satu screenshot HP.
"""
import os
import sys

# Ekstensi yang bikin Unity membuat .meta (hanya yang bisa dirujuk via GUID).
ASSET_EXT = {
    ".cs", ".shader", ".hlsl", ".cginc", ".compute", ".mat", ".asset", ".unity",
    ".prefab", ".asmdef", ".asmref", ".playable", ".physicMaterial",
    ".physicsMaterial2D", ".anim", ".overrideController", ".mask", ".guiskin",
    ".fontSettings", ".renderTexture", ".spriteatlas", ".terrainlayer",
    ".mixer", ".audioMixerGroup", ".controller", ".lighting", ".minimalmotion",
    ".motionfeatures", ".presets", ".sampleasset", ".talk", ".wat",
    ".fbx", ".obj", ".png", ".jpg", ".jpeg", ".tga", ".psd", ".exr", ".hdr",
    ".wav", ".mp3", ".ogg", ".aif", ".aiff", ".tif", ".tiff", ".bmp", ".gif",
    ".glb", ".gltf", ".vrm", ".ttf", ".otf",
}
# Berkas yang memang tidak boleh/ tidak perlu punya .meta.
SKIP_NAMES = {"README.md", "LICENSE", "LISENSI.md"}


def offenders(paths):
    """Daftar berkas aset yang .meta-nya tidak ada di daftar yang diberikan."""
    tracked = set(paths)
    out = []
    for p in paths:
        if os.sep not in p and p in SKIP_NAMES:
            continue
        if os.path.basename(p) in SKIP_NAMES:
            continue
        ext = os.path.splitext(p)[1].lower()
        if ext not in ASSET_EXT:
            continue
        if p.endswith(".meta"):
            continue
        if p + ".meta" not in tracked:
            out.append(p)
    return out


def main(argv):
    args = [a for a in argv[1:] if not a.startswith("--")]
    if "--selftest" in argv:
        sample = ["Assets/A/a.cs", "Assets/A/a.cs.meta", "Assets/A/x.shader",
                  "Assets/A/b.mat", "Assets/A/b.mat.meta", "Assets/A/notes.md"]
        got = offenders(sample)
        want = ["Assets/A/x.shader"]
        ok = got == want
        print("SELFTEST %s: rujukan=%s harapan=%s" % ("LULUS" if ok else "GAGAL", got, want))
        return 0 if ok else 1

    if args:
        paths = [l.strip().replace(os.sep, "/") for a in args for l in open(a) if l.strip()]
    else:
        paths = [l.strip().replace(os.sep, "/") for l in sys.stdin if l.strip()]
    bad = offenders(paths)
    if bad:
        print("ADA %d aset Unity tanpa .meta yang dilacak (GUID-nya diacak ulang tiap import):" % len(bad))
        for b in bad:
            print("  " + b)
        print("Perbaiki: biarkan Unity meng-import sekali, lalu commit berkas .meta-nya.")
        return 1
    print("OK: %d berkas diperiksa, semua aset punya .meta." % len(paths))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
