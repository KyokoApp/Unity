#!/usr/bin/env python3
"""List isi file .pck Godot 4 (header + direktori) untuk audit CI.

Output mudah dibaca: satu baris per file (path + ukuran), total di akhir.
Dipakai untuk memastikan patch pack hanya berisi file yang berubah.
"""
import os
import struct
import sys


def _looks_valid(entries, filesize):
    if not entries:
        return False
    for name, size in entries:
        if size > filesize + 4 * 1024 * 1024:
            return False
        if not name or not all(31 < ord(c) < 127 for c in name):
            return False
    return True


def read_pck_dir(path: str):
    with open(path, "rb") as f:
        buf = f.read()

    if struct.unpack("<I", buf[:4])[0] != 0x43504447:  # 'GDPK'
        raise SystemExit(f"Bukan PCK Godot: {path}")

    # Header Godot 4 (PACK_FORMAT_VERSION=2):
    #   magic(I) pack_ver(I) ver_major(I) ver_minor(I) flags(I)
    #   dir_offset(Q) dir_len(Q) reserved(64)
    # Beberapa build menambahkan ver_patch(I) sebelum flags -> coba keduanya.
    base = struct.unpack("<I", buf[4:8])[0]
    header_variants = [16, 20]  # offset 'flags' bila tanpa/dengan ver_patch

    def try_parse(flags_pos):
        dir_offset, dir_len = struct.unpack("<QQ", buf[flags_pos + 4: flags_pos + 20])
        if not (0 < dir_offset < len(buf)) or dir_offset + 4 >= len(buf):
            return None
        count = struct.unpack("<I", buf[dir_offset:dir_offset + 4])[0]
        if not (0 < count < 100000):
            return None
        pos = dir_offset + 4
        entries = []
        for _ in range(count):
            if pos + 4 > len(buf):
                return None
            plen = struct.unpack("<I", buf[pos:pos + 4])[0]
            pos += 4
            if plen == 0 or plen > 4096 or pos + plen > len(buf):
                return None
            name = buf[pos:pos + plen].rstrip(b"\x00").decode("utf-8", "replace")
            pos += plen
            if pos + 32 > len(buf):
                return None
            offs, size = struct.unpack("<QQ", buf[pos:pos + 16])
            pos += 16 + 16  # skip md5
            entries.append((name, size))
        return entries if _looks_valid(entries, len(buf)) else None

    for flags_pos in header_variants:
        entries = try_parse(flags_pos)
        if entries:
            return entries

    # Terakhir: ambil nilai dir_offset mentah untuk bantuan debug.
    dbg1 = struct.unpack("<QQ", buf[20:36]) if len(buf) > 36 else (0, 0)
    raise SystemExit(
        f"Gagal parse direktori PCK {path} (pack_ver={base}, kandidat offset16/20, "
        f"dir_offset~{dbg1[0]}, panjang={len(buf)})")


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
