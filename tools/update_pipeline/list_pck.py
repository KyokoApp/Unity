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

    def u64(p):
        return struct.unpack("<Q", buf[p:p + 8])[0] if 0 <= p <= fsize - 8 else None

    def valid_offs(p):
        """QQ di p = (offset, size) yang masuk akal; offset relatif terhadap file_base."""
        if p + 16 > fsize:
            return None
        offs, size = struct.unpack("<QQ", buf[p:p + 16])
        if offs > fsize or size > fsize or offs + size > fsize + 4096:
            return None
        return offs, size

    def parse(dir_off, count, mode):
        pos = dir_off + 4  # lewati count
        entries = []
        for i in range(count):
            pl = u32(pos)
            if pl is None or pl < 6 or pl > 4096 or pos + 4 + pl > fsize:
                return None
            if buf[pos + 4:pos + 10] != b"res://":
                return None
            name = buf[pos + 4:pos + 4 + pl].decode("utf-8", "replace")
            tail = pos + 4 + pl
            os_ = None
            for k in range(0, (7 if mode == "adaptive" else 1)):
                p2 = tail + k
                if k > 0 and buf[tail + k - 1] != 0 and buf[tail + k - 1] < 128:
                    # padding hanya zeros; kalau byte non-nol kecil itu bagian Q, berhenti
                    break
                os_ = valid_offs(p2)
                if os_:
                    offs, size = os_
                    pos2 = p2 + 16 + 16 + 4  # +md5 +flags
                    break
            if os_ is None:
                return None
            entries.append((name, size))
            if i == count - 1:
                return entries if fsize - pos2 <= 72 else None
            # entry berikutnya tepat di pos2 (strict) atau geser kecil (adaptive)
            if mode == "adaptive":
                nxt = None
                for j in range(0, 13):
                    pl2 = u32(pos2 + j)
                    if pl2 is not None and 6 <= pl2 <= 4096 and buf[pos2 + j + 4:pos2 + j + 10] == b"res://":
                        nxt = pos2 + j
                        break
                if nxt is None:
                    return None
                pos = nxt
            else:
                pos = pos2
        return None

    cands = []
    doff32 = u64(32)  # dir_offset V3 persis di header (offset 32)
    if doff32 is not None and 0 < doff32 < fsize:
        cands.append(doff32)
    for h in hits:
        for cback in (8, 12, 16):  # count sebelum [slen][name]
            cp = h - cback
            if cp >= 0:
                cands.append(cp)
    for cand in cands:
        count = u32(cand)
        if count is None or count == 0 or count > 50000:
            continue
        for mode in ("strict", "adaptive"):
            got = parse(cand, count, mode)
            if got:
                return got

    tail = buf[-48:].hex() if fsize > 48 else buf.hex()
    raise SystemExit(
        f"Gagal parse direktori PCK {path} (pack_ver={pack_ver}, hits={len(hits)}, "
        f"fsize={fsize}, doff32={u64(32)})\nfirst hits: {hits[:4]}\n"
        f"last hits: {hits[-6:] if hits else []}\nhex -48..EOF: {tail}")



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
