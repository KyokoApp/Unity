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

    def valid_off_size(p):
        """QQ di p harus offset/size yang masuk akal."""
        if p + 16 > fsize:
            return False
        offs, size = struct.unpack("<QQ", buf[p:p + 16])
        return 100 <= offs < fsize and 0 <= size <= fsize and offs + size <= fsize + 16

    def valid_name(p):
        """U32 di p terlihat seperti panjang path dan diikuti nama res://."""
        pl = u32(p)
        if pl is None or pl < 7 or pl > 4096:
            return None
        if buf[p + 4:p + 10] != b"res://":
            return None
        return pl

    def walk(dir_off, count):
        pos = dir_off + 4
        entries = []
        for i in range(count):
            pl = valid_name(pos)
            if pl is None:
                return None, i, pos
            name_end = pos + 4 + pl
            name = buf[pos + 4:name_end].rstrip(b"\x00").decode("utf-8", "replace")
            k_max = min(5, fsize - name_end)
            got = False
            k_start = 1 if buf[name_end:name_end + 1] == b"\x00" else 0
            for k in range(k_start, k_max + 1):
                p2 = name_end + k
                if k > 0 and buf[name_end + k - 1] != 0:
                    break  # nol diizinkan saja; kalau bukan nol, berhenti
                if valid_off_size(p2):
                    offs, size = struct.unpack("<QQ", buf[p2:p2 + 16])
                    pos = p2 + 16 + 16  # +md5
                    entries.append((name, size))
                    got = True
                    break
            if not got:
                return None, i, pos
            if i == count - 1:
                break
            # cari awal entry berikut (mungkin ada flags/pad 0..12 byte)
            nxt = None
            for j in range(13):
                if pos + j >= fsize:
                    break
                if j > 0 and buf[pos + j - 1] != 0 and buf[pos + j - 1] > 127:
                    break  # padding = nol; flags kecil diabaikan (I32 LE umumnya byte akhir nol)
                if valid_name(pos + j) is not None:
                    nxt = pos + j
                    break
            if nxt is None:
                return None, i + 1, pos
            pos = nxt
        if fsize - pos <= 72:
            return entries, count, pos
        return None, count, pos

    best = (0, -1, -1)
    for h in hits:
        for cback in (4, 8, 12, 16, 20):
            count = u32(h - cback)
            if count is None or count == 0 or count > 50000:
                continue
            got, done, pos = walk(h - cback, count)
            if got:
                return got
            if done > best[0]:
                best = (done, h, -1)

    tail = buf[-48:].hex() if fsize > 48 else buf.hex()
    sample = [buf[h:h + 40].split(b"\x00")[0].decode("utf-8", "replace") for h in hits[:4]]
    raise SystemExit(
        f"Gagal parse direktori PCK {path} (pack_ver={pack_ver}, hits={len(hits)}, "
        f"fsize={fsize}, best_progress={best[0]})\n"
        f"first hits: {hits[:6]}\nlast hits: {hits[-6:] if hits else []}\n"
        f"sampel: {sample}\nhex -48..EOF: {tail}")



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
