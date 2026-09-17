#!/usr/bin/env python3
"""PENEMPATAN ASET — memutuskan file unduhan menjadi:

    models/AureliaChar.glb   <- sumber mesh karakter (mesh terbanyak)
    models/AureliaAnim.glb   <- sumber klip animasi (animasi terbanyak,
                                bila beda dengan sumber mesh)

Nama baku ini dibaca oleh runtime/character_rig.gd (model_paths /
anim_paths). Tidak ada dependensi luar; kode keluar 1 bila tidak ada
GLB valid sama sekali (cache CI dilewati oleh hashFiles juga).

    python3 tools/fetch_assets_place.py berkas1 [berkas2 ...]
"""
import io
import json
import os
import struct
import sys
import zipfile


def glb_json(buf: bytes):
    if len(buf) < 20 or buf[0:4] != b"glTF":
        return None
    clen, ctype = struct.unpack("<I4s", buf[12:20])
    if ctype != b"JSON" or len(buf) < 20 + clen:
        return None
    try:
        return json.loads(buf[20:20 + clen].decode("utf-8", "replace"))
    except Exception:  # noqa: BLE001
        return None


def candidates(paths: list) -> list:
    out = []
    for p in paths:
        try:
            with open(p, "rb") as f:
                buf = f.read()
        except OSError:
            continue
        if buf[:2] == b"PK":
            try:
                zf = zipfile.ZipFile(io.BytesIO(buf))
            except zipfile.BadZipFile:
                continue
            for info in zf.infolist():
                if info.filename.lower().endswith((".glb", ".vrm")):
                    out.append({"data": zf.read(info),
                                "label": "%s::%s" % (p, info.filename)})
        else:
            out.append({"data": buf, "label": p})
    return out


def main() -> int:
    parsed = []
    for c in candidates(sys.argv[1:]):
        js = glb_json(c["data"])
        if js is None:
            continue
        anims = [a.get("name", "?") for a in js.get("animations", [])]
        parsed.append({**c,
                       "n_mesh": len(js.get("meshes", [])),
                       "n_anim": len(anims),
                       "anims": anims})
    if not parsed:
        print("TIDAK ADA GLB VALID DITEMUKAN — models/ tidak diubah")
        return 1

    os.makedirs("models", exist_ok=True)
    by_mesh = sorted(parsed, key=lambda x: (-x["n_mesh"], x["n_anim"]))
    ## Animasi: jumlah terbanyak; pada seri, hindari varian root-motion
    ## (ialan "_rm") — gerak karakter digerakkan CharacterMotor, bukan klip.
    by_anim = sorted(parsed, key=lambda x: (-x["n_anim"],
                                            "_rm" in x["label"].lower(),
                                            -x["n_mesh"]))
    char = by_mesh[0]
    anim = by_anim[0] if (by_anim[0]["n_anim"] > 0
                          and by_anim[0] is not char) else None

    with open("models/AureliaChar.glb", "wb") as f:
        f.write(char["data"])
    print("models/AureliaChar.glb <- %s (mesh=%d anim=%d)"
          % (char["label"], char["n_mesh"], char["n_anim"]))
    if anim is not None:
        with open("models/AureliaAnim.glb", "wb") as f:
            f.write(anim["data"])
        print("models/AureliaAnim.glb <- %s (klip: %s)"
              % (anim["label"], ", ".join(anim["anims"][:20])))
    else:
        print("klip animasi dibaca dari AureliaChar.glb sendiri")
    return 0


if __name__ == "__main__":
    sys.exit(main())
