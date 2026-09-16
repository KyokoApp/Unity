#!/usr/bin/env python3
"""Rata-rata warna screenshot PNG, tanpa dependensi apa pun.

Kenapa ini ada di CI dan bukan di HP: satu-satunya cara membedakan
"dunia hitam karena build player" dan "dunia hitam karena scene/shader
memang salah" adalah melihat hasil render. SceneShots.cs sudah merender
tiga suasana di EDITOR saat build CI berjalan dan menulisnya ke shots/,
jadi angkanya bisa diambil dari sana -- tanpa perlu menunggu screenshot HP.

Klasifikasi yang dipakai (0..255, rata-rata semua kanal):
  max < 24            -> HITAM   : tidak ada satu pun pass yang menggambar
  warna ~ clear color -> KOSONG  : kamera meng-clear, tapi tidak ada objek
  R dan B tinggi, G rendah -> MAGENTA : material tidak menemukan shader
  selain itu            -> ADA     : dunia tergambar di editor

MAGENTA bukan kosmetik: itu warna yang Unity pakai untuk "shader gagal/tidak
ada", jadi dunia boleh saja tergambar bentuknya tapi tidak akan pernah terlihat
benar di player. Angka (225,55,233) dari run v0.2.0-cel-fix20 adalah contoh
aslinya -- dan "ADA: dunia tergambar" yang lama menolaknya, itu bug alat ukur.

Ditulis dengan stdlib saja karena runner tidak punya PIL, dan hasil apa
pun yang gagal didekode dilaporkan, tidak pernah menggagalkan build.
"""
import glob
import os
import struct
import sys
import zlib

FILTER_NONE, FILTER_SUB, FILTER_UP, FILTER_AVG, FILTER_PAETH = range(5)


def _paeth(a, b, c):
    p = a + b - c
    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
    if pa <= pb and pa <= pc:
        return a
    return b if pb <= pc else c


def decode(path):
    d = open(path, "rb").read()
    if d[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("bukan PNG")
    pos, w = 8, None
    h = bd = ct = None
    idat = bytearray()
    while pos + 8 <= len(d):
        ln = struct.unpack(">I", d[pos:pos + 4])[0]
        typ = d[pos + 4:pos + 8]
        body = d[pos + 8:pos + 8 + ln]
        pos += 12 + ln
        if typ == b"IHDR":
            w, h, bd, ct = struct.unpack(">IIBB", body[:10])
        elif typ == b"IDAT":
            idat += body
        elif typ == b"IEND":
            break
    if w is None:
        raise ValueError("IHDR hilang")
    if bd != 8:
        raise ValueError("bit depth %d belum didukung" % bd)
    channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}.get(ct)
    if channels is None:
        raise ValueError("color type %d belum didukung" % ct)
    raw = zlib.decompress(bytes(idat))
    bpp = channels
    stride = w * bpp
    out = bytearray(h * stride)
    prev = bytearray(stride)
    p = 0
    for y in range(h):
        f = raw[p]; p += 1
        line = bytearray(raw[p:p + stride]); p += stride
        if f == FILTER_SUB:
            for x in range(bpp, stride):
                line[x] = (line[x] + line[x - bpp]) & 255
        elif f == FILTER_UP:
            for x in range(stride):
                line[x] = (line[x] + prev[x]) & 255
        elif f == FILTER_AVG:
            for x in range(stride):
                a = line[x - bpp] if x >= bpp else 0
                line[x] = (line[x] + ((a + prev[x]) >> 1)) & 255
        elif f == FILTER_PAETH:
            for x in range(stride):
                a = line[x - bpp] if x >= bpp else 0
                c = prev[x - bpp] if x >= bpp else 0
                line[x] = (line[x] + _paeth(a, prev[x], c)) & 255
        elif f != FILTER_NONE:
            raise ValueError("filter %d tidak dikenal" % f)
        base = y * stride
        out[base:base + stride] = line
        prev = line
    return w, h, channels, out


def mean(path, want=4000):
    w, h, ch, px = decode(path)
    stride = w * ch
    step = max(1, (w * h) // want)
    acc = [0, 0, 0]
    n = 0
    for i in range(0, w * h, step):
        o = (i // w) * stride + (i % w) * ch
        if ch >= 3:
            acc[0] += px[o]; acc[1] += px[o + 1]; acc[2] += px[o + 2]
        else:
            acc[0] += px[o]; acc[1] += px[o]; acc[2] += px[o]
        n += 1
    if not n:
        raise ValueError("tidak ada piksel")
    return w, h, [v // n for v in acc], n


def classify(rgb, clear_hint=None):
    mx = max(rgb)
    if mx < 24:
        return "HITAM: tidak ada yang digambar (backbuffer tidak pernah di-clear?)"
    if clear_hint:
        # camera.backgroundColor ditulis kode dalam 0..1, screenshot dalam 0..255.
        # Tanpa normalisasi ini jaraknya selalu ~500 dan aturan KOSONG tidak
        # pernah aktif: aturan yang tampaknya menjaga padahal tidak berjalan
        # (tertangkep oleh selftest -- itu gunanya).
        if max(clear_hint) <= 1.0:
            clear_hint = tuple(int(round(c * 255)) for c in clear_hint)
        dr = sum(abs(a - b) for a, b in zip(rgb, clear_hint))
        if dr < 40:
            return ("KOSONG: hasilnya = warna clear kamera, jadi tidak ada "
                    "satu pun objek yang tergambar")
    r, g, b = rgb
    if min(r, b) > 140 and g < 0.55 * min(r, b):
        return ("MAGENTA: yang tergambar adalah material error Unity (shader "
                "tidak ditemukan/tidak di-compile untuk target), bukan dunia")
    return "ADA: dunia tergambar"


def _selftest():
    """Encode balik pakai hanya stdlib, lalu pastikan dekoder membaca rata-rata
    yang sama untuk filter NONE (0) dan UP (2). Kalau filter lain yang meleset,
    yang salah adalah aritmetika prediknya -- di CI itu akan muncul sebagai
    angka aneh, bukan sebagai kegagalan build, jadi dicek di sini."""
    import os
    import tempfile
    w, h, ch = 4, 3, 3
    stride = w * ch
    rows = []
    for y in range(h):
        row = bytearray()
        for x in range(w):
            row += bytes((x * 60, y * 80, 128))
        rows.append(bytes(row))

    def chunk(t, b):
        return struct.pack(">I", len(b)) + t + b + struct.pack(">I", zlib.crc32(t + b))

    def png(filter_type):
        parts = []
        for y, r in enumerate(rows):
            if filter_type == 0:
                data = r
            else:
                prev = rows[y - 1] if y else bytes(stride)
                data = bytes((r[i] - prev[i]) % 256 for i in range(stride))
            parts.append(bytes([filter_type]) + data)
        ihdr = struct.pack(">IIBB", w, h, 8, 2)
        return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) +
                chunk(b"IDAT", zlib.compress(b"".join(parts))) + chunk(b"IEND", b""))

    exp = []
    for c in range(3):
        vals = [rows[y][x * 3 + c] for y in range(h) for x in range(w)]
        exp.append(sum(vals) // len(vals))
    for ft in (0, 2):
        fd, path = tempfile.mkstemp(suffix=".png")
        os.close(fd)
        open(path, "wb").write(png(ft))
        try:
            got = mean(path)
        finally:
            os.unlink(path)
        assert (got[0], got[1]) == (w, h), got
        assert got[2] == exp, ("filter", ft, got[2], exp)
    # Klasifikasinya sendiri juga diuji, bukan cuma dekodernya: kasus-kasus ini
    # adalah angka nyata yang pernah keluar dari CI, dan salah satu di antaranya
    # (magenta) dulu lolos sebagai "ADA" -- itu artinya penjaga, bukan bukti.
    cases = [((0, 0, 0), "HITAM"), ((21, 24, 32), "ADA"),
             ((225, 55, 233), "MAGENTA"), ((181, 7, 185), "MAGENTA"),
             ((158, 178, 199), "KOSONG"), ((175, 185, 155), "ADA"),
             ((160, 115, 73), "ADA")]
    for rgb_, want in cases:
        got = classify(rgb_, clear_hint=(0.62, 0.70, 0.78))
        assert got.startswith(want), (rgb_, want, got)
    print("selftest OK: filter NONE + UP didekode identik, rata-rata", exp)
    print("selftest OK: 7 kasus klasifikasi warna, termasuk magenta-fix20")


if __name__ == "__main__":
    if "--selftest" in sys.argv:
        _selftest(); raise SystemExit(0)
    args = [a for a in sys.argv[1:] if not a.startswith("-")]
    files = args or sorted(glob.glob("shots/*.png")) + sorted(glob.glob("Assets/**/shots/*.png", recursive=True))
    files = [f for f in files if os.path.isfile(f)]
    if not files:
        print("SHOT=TIDAK-ADA (SceneShots tidak menulis PNG -> tidak ada bukti render editor)")
        raise SystemExit(0)
    for f in files:
        try:
            w, h, rgb, n = mean(f)
            print("%-40s %dx%d mean_r=%3d mean_g=%3d mean_b=%3d  [%d sampel] -> %s"
                  % (os.path.basename(f), w, h, rgb[0], rgb[1], rgb[2], n, classify(rgb)))
        except Exception as e:
            print("%-40s GAGAL BACA: %s: %s" % (os.path.basename(f), type(e).__name__, e))
