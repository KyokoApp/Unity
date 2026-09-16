#!/usr/bin/env python3
"""Bake tekstur data untuk gaya toon — TANPA Unity, stdlib saja.

Keluaran (di-commit ke repo supaya CI + clone baru langsung jalan):
  Assets/_Project/Textures/ToonRamp_Default.png  64x8, ramp cahaya 1D
  Assets/_Project/Textures/WindNoise.png         256x256, RG=arah B=kekuatan

Deterministik: hash integer, tanpa random. Dijalankan ulang kapan saja:
  python3 tools/bake_toon_textures.py
"""
import math, os, struct, zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Assets", "_Project", "Textures")

def chunk(typ, data):
    c = struct.pack(">I", len(data)) + typ + data
    return c + struct.pack(">I", zlib.crc32(typ + data) & 0xFFFFFFFF)

def write_png(path, w, h, rows):
    raw = b"".join(b"\x00" + bytes(r) for r in rows)
    png = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(raw, 9))
           + chunk(b"IEND", b""))
    with open(path, "wb") as f:
        f.write(png)
    print(f"  {os.path.relpath(path, ROOT)} ({w}x{h}, {len(png)//1024} KB)")

def smooth(a, b, x):
    t = min(1.0, max(0.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)

def bake_ramp():
    # 3 stop: bayangan biru-lembut -> tengah netral -> terang putih.
    # Transisi smooth (lebar ~12%) supaya tepi tingkat tidak menggergaji.
    W, H = 64, 8
    shadow = (158, 168, 209)
    mid = (226, 229, 236)
    lit = (255, 255, 255)
    rows = []
    for _ in range(H):
        row = []
        for x in range(W):
            t = x / (W - 1)
            k1 = smooth(0.38, 0.52, t)
            k2 = smooth(0.68, 0.82, t)
            c = [shadow[i] + (mid[i] - shadow[i]) * k1 + (lit[i] - mid[i]) * k2
                 for i in range(3)]
            row += [int(round(v)) for v in c] + [255]
        rows.append(row)
    write_png(os.path.join(OUT, "ToonRamp_Default.png"), W, H, rows)

def hash2(x, y):
    n = (x * 374761393 + y * 668265263) & 0xFFFFFFFF
    n = (n ^ (n >> 13)) & 0xFFFFFFFF
    n = (n * 1274126177) & 0xFFFFFFFF
    return ((n ^ (n >> 16)) & 0xFFFFFFFF) / 4294967296.0

def vnoise(x, y):
    xi, yi = math.floor(x), math.floor(y)
    xf, yf = x - xi, y - yi
    u, v = xf * xf * (3 - 2 * xf), yf * yf * (3 - 2 * yf)
    a = hash2(xi, yi)
    b = hash2(xi + 1, yi)
    c = hash2(xi, yi + 1)
    d = hash2(xi + 1, yi + 1)
    return a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v

def fbm(x, y, octaves=4):
    total, amp, freq, norm = 0.0, 0.5, 1.0, 0.0
    for _ in range(octaves):
        total += amp * vnoise(x * freq, y * freq)
        norm += amp
        amp *= 0.5
        freq *= 2.03
    return total / norm

def bake_wind():
    W, H = 256, 256
    rows = []
    for y in range(H):
        row = []
        for x in range(W):
            # Dua medan arah (offset beda supaya tidak berkorelasi) +
            # satu mask hembusan frekuensi rendah.
            dx = fbm(x / 34.0, y / 34.0)
            dy = fbm(x / 34.0 + 13.7, y / 34.0 + 7.1)
            gust = fbm(x / 90.0 + 3.3, y / 90.0 + 9.9, 3)
            gust = smooth(0.25, 0.85, gust)
            row += [int(dx * 255), int(dy * 255), int(gust * 255), 255]
        rows.append(row)
    write_png(os.path.join(OUT, "WindNoise.png"), W, H, rows)

if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    print("Baking tekstur toon:")
    bake_ramp()
    bake_wind()
    print("SELESAI")
