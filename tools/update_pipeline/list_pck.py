#!/usr/bin/env python3
"""List isi file .pck Godot 4 (header + direktori) untuk audit CI.

Output mudah dibaca: satu baris per file (path + ukuran), total di akhir.
Dipakai untuk memastikan patch pack hanya berisi file yang berubah.
"""
import os
import struct
import sys


def read_pck_dir(path: str):
    with open(path, "rb") as f:
        buf = f.read()

    if struct.unpack("<I", buf[:4])[0] != 0x43504447:  # 'GDPK'
        raise SystemExit(f"Bukan PCK Godot: {path}")
    pack_ver = struct.unpack("<I", buf[4:8])[0]

    fsize = len(buf)
    # Strategi toleran-versi (v1/v2/v3 memiliki header & stride entry berbeda):
    # temukan kemunculan "res://" pertama yang merupakan awal nama entry,
    # mundur untuk menemukan [count][path_len], lalu coba berbagai
    # layout tail entry konsisten (offset+size+md5[=32] atau +flags[=36]).
    tails = [
        ("offs,size,md5", 32),                 # v2
        ("offs,size,flags,md5", 36),           # v3 varian A
        ("offs,size,md5,flags", 36),           # v3 varian B
    ]
    import re as _re

    def u32(p):
        return struct.unpack("<I", buf[p:p + 4])[0]

    starts = [m.start() for m in _re.finditer(_re.escape(b"res://"), buf)]
    for start in starts:
        for pre in (4, 8, 12):  # jarak mundur: cukup plen, atau count+plen
            cpos = start - pre
            if cpos < 8:
                continue
            # coba dua interpretasi: count di cpos / cpos+4; plen tepat sebelum nama
            for count_off in (cpos, cpos + 4):
                count = u32(count_off)
                if not (0 < count < 1000000):
                    continue
                plen = u32(start - 4)
                name1 = buf[start:start + min(plen, fsize - start)]
                if plen < 6 or plen > 4096:
                    continue
                # nama pertama harus persis sepanjang kesempatan ditawar tol_b? cukup res://
                if not name1.startswith(b"res://"):
                    continue
                for _label, stride in tails:
                    pos = count_off + 4
                    entries = []
                    ok = True
                    for _ in range(count):
                        if pos + 4 > fsize:
                            ok = False
                            break
                        pl = u32(pos)
                        pos += 4
                        if pl < 2 or pl > 4096 or pos + pl > fsize:
                            ok = False
                            break
                        name = buf[pos:pos + pl].rstrip(b"\x00").decode("utf-8", "replace")
                        pos += pl
                        if pos + stride > fsize:
                            ok = False
                            break
                        offs, size = struct.unpack("<QQ", buf[pos:pos + 16])
                        if size > fsize + 16 * 1024 * 1024:
                            ok = False
                            break
                        if not name or any(ord(c) < 32 for c in name):
                            ok = False
                            break
                        pos += stride
                        entries.append((name, size))
                    # Direktori valid: habis sampai EOF (direktori selalu di ujung)
                    if ok and pos == fsize:
                        return entries

    dbg = struct.unpack("<QQ", buf[16:32])
    raise SystemExit(
        f"Gagal parse direktori PCK {path} (pack_ver={pack_ver}, panjang={fsize}, "
        f"bytes 16-31: {dbg[0]}/{dbg[1]})")


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
            print(f"  {size:>12,}  {name}")
            total_bytes += size
        print(f"  >> {len(entries)} file, konten total {total_bytes/1048576:.2f} MB")
        print()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
