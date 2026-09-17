#!/usr/bin/env python3
"""LAPORAN ASET — membaca metadata GLB/ZIP (tanpa dependensi luar).

Dipakai oleh .github/workflows/fetch-assets.yml untuk mengidentifikasi
file aset pengguna (nama klip animasi, skeleton, skala) sebelum kode
game disesuaikan. Mencetak laporan ke stdout; kode keluar selalu 0.

    python3 tools/fetch_assets_report.py berkas1 [berkas2 ...]
"""
import io
import json
import os
import struct
import sys
import zipfile


def glb_json(buf: bytes):
    """Ambil dict JSON dari chunk pertama GLB; None bila bukan GLB."""
    if len(buf) < 20 or buf[0:4] != b"glTF":
        return None
    clen, ctype = struct.unpack("<I4s", buf[12:20])
    if ctype != b"JSON" or len(buf) < 20 + clen:
        return None
    try:
        return json.loads(buf[20:20 + clen].decode("utf-8", "replace"))
    except Exception as exc:  # noqa: BLE001
        return {"__error__": repr(exc)}


def summarize(label: str, buf: bytes, out: list) -> None:
    js = glb_json(buf)
    if js is None:
        out.append("- %s: BUKAN GLB (magic=%r, %d byte)"
                   % (label, buf[:8], len(buf)))
        return
    if "__error__" in js:
        out.append("- %s: JSON GLB tidak terbaca: %s" % (label, js["__error__"]))
        return
    nodes = js.get("nodes", [])
    anims = js.get("animations", [])
    skins = js.get("skins", [])
    meshes = js.get("meshes", [])
    mats = js.get("materials", [])
    out.append("- %s: GLB %d byte | node=%d mesh=%d skin=%d animasi=%d "
               "material=%d" % (label, len(buf), len(nodes), len(meshes),
                                len(skins), len(anims), len(mats)))
    names = [n.get("name", "?") for n in nodes]
    out.append("  node (maks 40): " + ", ".join(names[:40]))
    for i, s in enumerate(skins[:2]):
        jn = [names[j] if j < len(names) else "?%d" % j
              for j in s.get("joints", [])]
        out.append("  skin%d join(%d): %s"
                   % (i, len(jn), ", ".join(jn[:12])))
    accessors = js.get("accessors", [])
    for i, a in enumerate(anims):
        dur = 0.0
        for smp in a.get("samplers", []):
            inp = smp.get("input")
            if isinstance(inp, int) and inp < len(accessors):
                mx = accessors[inp].get("max")
                if mx:
                    try:
                        dur = max(dur, float(mx[0]))
                    except (TypeError, ValueError):
                        pass
        out.append("  anim%d: '%s' saluran=%d durasi=%.2fs"
                   % (i, a.get("name", "?"), len(a.get("channels", [])), dur))
    if mats:
        out.append("  material: "
                   + ", ".join(m.get("name", "?") for m in mats[:16]))


def process(path: str, out: list) -> None:
    try:
        with open(path, "rb") as f:
            buf = f.read()
    except OSError as exc:
        out.append("== %s: TIDAK TERBACA (%s) ==" % (path, exc))
        return
    out.append("== %s (%d byte) ==" % (path, len(buf)))
    if buf[:2] == b"PK":
        out.append("  (arsip ZIP)")
        try:
            zf = zipfile.ZipFile(io.BytesIO(buf))
        except zipfile.BadZipFile as exc:
            out.append("  ZIP rusak: %s" % exc)
            return
        for info in zf.infolist():
            out.append("  zip-entry: %s (%d byte)"
                       % (info.filename, info.file_size))
        for info in zf.infolist():
            if info.filename.lower().endswith((".glb", ".vrm")):
                try:
                    summarize("zip:" + info.filename, zf.read(info), out)
                except Exception as exc:  # noqa: BLE001
                    out.append("  gagal baca %s: %s" % (info.filename, exc))
    else:
        summarize(os.path.basename(path), buf, out)


def main() -> int:
    out = ["== LAPORAN ASET (fetch-assets.yml) ==", ""]
    for p in sys.argv[1:]:
        process(p, out)
        out.append("")
    print("\n".join(out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
