#!/usr/bin/env python3
"""List isi file .pck Godot 4 (header + direktori) untuk audit CI.

Output mudah dibaca: satu baris per file (path + ukuran), total di akhir.
Dipakai untuk memastikan patch pack hanya berisi file yang berubah.
"""
import os
import re
import struct
import sys


def read_pck_dir(path: str):
    with open(path, "rb") as f:
        buf = f.read()

    if struct.unpack("<I", buf[:4])[0] != 0x43504447:  # 'GDPK'
        raise SystemExit(f"Bukan PCK Godot: {path}")
    pack_ver = struct.unpack("<I", buf[4:8])[0]
    fsize = len(buf)
    hits = [m.start() for m in re.finditer(re.escape(b"res://"), buf)]

    def u32(p):
        return struct.unpack("<I", buf[p:p + 4])[0] if 0 <= p <= fsize - 4 else None

    # Struktur direktori: [count(I)] [ entry x count ]
    # entry: [path_len(I)][name(+nul?)][tail] dgn tail: offset(Q)+size(Q)+md5(16) (+flags dsb.)
    tails = (16, 20, 24, 28, 32, 36, 40, 44, 48, 52, 56, 60, 64)
    TAIL_REQUIRED = 16  # offset+size wajib ada di awal tail

    def walk(dir_off, count, nul, tail):
        pos = dir_off + 4
        entries = []
        for _ in range(count):
            pl = u32(pos)
            if pl is None or pl < 3 or pl > 4096 or pl <= (1 if nul else 0):
                return None
            pos += 4
            name_len = pl - (1 if nul else 0)
            if pos + pl > fsize:
                return None
            raw = buf[pos:pos + name_len]
            if nul and buf[pos + name_len] != 0:
                return None
            try:
                name = raw.decode("utf-8")
            except UnicodeDecodeError:
                return None
            if not name.startswith("res://"):
                return None
            pos += pl
            if pos + TAIL_REQUIRED > fsize:
                return None
            offs, size = struct.unpack("<QQ", buf[pos:pos + 16])
            if size > fsize + 64 * 1024 * 1024:
                return None
            entries.append((name, size))
            pos += tail
        if pos == fsize:
            return entries
        return None

    best = 0
    for h in hits:
        for nul in (0, 1):
            for tail in tails:
                count = u32(h - 8)
                # count tepat 8 byte sebelum nama: [count][plen][name]
                if count is None or count == 0 or count > 20000:
                    continue
                result = walk(h - 8, count, nul, tail)
                if result:
                    return result
                # diagnosa: hitung rantai maksimum dari candidate ini
                pos = h - 4
                # posisi plen kandidat = h-4; langkah: plenI + name + tail
                pl = u32(pos)
                chain = 0
                if pl and 3 <= pl <= 4096:
                    pos2 = pos + 4 + pl + tail
                    chain = 1
                    for _ in range(3):
                        pl2 = u32(pos2)
                        if pl2 is None or pl2 < 3 or pl2 > 4096:
                            break
                        if pos2 + 4 + pl2 > fsize:
                            break
                        seg = buf[pos2 + 4:pos2 + 4 + min(pl2, 16)]
                        if not seg.startswith(b"res://"):
                            break
                        pos2 = pos2 + 4 + pl2 + tail
                        chain += 1
                best = max(best, chain)

    raise SystemExit(
        f"Gagal parse direktori PCK {path} (pack_ver={pack_ver}, hits={len(hits)}, "
        f"fsize={fsize}, best_chain={best}, first_hits={hits[:3]}, last_hits={hits[-2:] if hits else []})")



def main() -> int:
    total = 0
    for p in sys.argv[1:]:
        print(f"== {p} ({os.path.getsize(p)} byte)")
        try:
            entries = read_pck_dir(p)
        except SystemExit as e:
            print("  ERROR:", e)
            continue
        total += len(entries)
        total_bytes = 0
        for name, size in sorted(entries):
            print(f"  {size:>12,}  {name.rstrip(chr(0))}")
            total_bytes += size
        print(f"  >> {len(entries)} file, konten total {total_bytes/1048576:.2f} MB")
        print()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
