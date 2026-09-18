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
        magic = struct.unpack("<I", f.read(4))[0]
        if magic != 0x43504447:  # 'GDPK' little-endian
            raise SystemExit(f"Bukan PCK Godot (magic={magic:#x}): {path}")
        pack_ver = struct.unpack("<I", f.read(4))[0]
        major, minor, patch = struct.unpack("<III", f.read(12))
        flags = struct.unpack("<I", f.read(4))[0]
        if pack_ver == 1:
            # Godot 3: flags(4) lalu reserved(64), direktori di ujung file;
            # offset dihitung dari total panjang? -> fallback sederhana:
            # Godot 3 menulis count langsung setelah header.
            dir_offset = 32  # magic+ver+major+minor+patch+flags = 24? kompensasi di bawah
            f.seek(4 * 6)    # magic, packver, major, minor, patch, flags
        else:
            # Godot 4 (PACK_FORMAT_VERSION=2): flags(4), dir_offset(8), dir_len(8), reserved(64)
            dir_offset, dir_len = struct.unpack("<QQ", f.read(16))
            f.read(64)  # reserved

        f.seek(dir_offset)
        count = struct.unpack("<I", f.read(4))[0]
        entries = []
        for _ in range(count):
            path_len = struct.unpack("<I", f.read(4))[0]
            name = f.read(path_len).rstrip(b"\x00").decode("utf-8", "replace")
            offs, size = struct.unpack("<QQ", f.read(16))
            f.read(16)  # md5
            entries.append((name, size))
        return entries


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
