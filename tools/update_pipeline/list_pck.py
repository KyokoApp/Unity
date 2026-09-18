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
            if pos + 4 >= fsize:
                return None
            sl = u32(pos)
            if sl is None or sl < 5 or sl > 4096:
                return None
            npos = pos + 4
            if npos + sl > fsize:
                return None
            raw = buf[npos:npos + sl]
            name = raw.split(b"\x00")[0].decode("utf-8", "replace")
            if len(name) < 4 or any(ord(c) < 32 for c in name):
                return None
            qs = npos + sl  # posisi setelah nama (nul mungkin termasuk sl)
            # geser melewati terminator/padding zeros (maks 4), pilih kandidat pertama
            # yang menghasilkan pasangan (offs,size) yang masuk akal
            if mode == "direct_q" or mode == "direct_q_flags":
                got = None
                extra = 4 if mode == "direct_q_flags" else 0
                if qs + 32 + extra <= fsize:
                    offs, size = struct.unpack("<QQ", buf[qs:qs + 16])
                    if offs <= fsize + 8192 and size <= fsize + 8192 and offs + size <= fsize + 16384:
                        entries.append((name, size))
                        if i == count - 1:
                            return entries if fsize - (qs + 32 + extra) <= 72 else None
                        pos = qs + 32 + extra
                        continue
                return None
            got = None
            for k in range(0, 5):
                p2 = qs + k
                if p2 + 16 > fsize:
                    break
                if k > 0 and buf[qs + k - 1] != 0:
                    break  # di luar nol: berhenti
                offs, size = struct.unpack("<QQ", buf[p2:p2 + 16])
                if offs <= fsize + 8192 and size <= fsize + 8192 and offs + size <= fsize + 16384:
                    got = (offs, size, p2 + 16 + 16 + 4)  # +md5 +flags
                    break
            if got is None:
                return None
            offs, size, pos = got
            entries.append((name, size))
            if i == count - 1:
                return entries if fsize - pos <= 72 else None
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
        for mode in ("scan", "direct_q", "direct_q_flags"):
            got = parse(cand, count, mode)
            if got:
                return got

    tail = buf[-48:].hex() if fsize > 48 else buf.hex()
    d32 = u64(32)
    ddiag = ""
    if d32 is not None and 0 < d32 < fsize:
        ddiag = (f"count@d32={u32(d32)} count+4={u32(d32+4)} count+32={u32(d32+32)}\n"
                 f"hex d32..+96: {buf[d32:d32+96].hex()}\n"
                 f"ascii d32..+96: {buf[d32:d32+96]!r}")
    raise SystemExit(
        f"Gagal parse direktori PCK {path} (pack_ver={pack_ver}, hits={len(hits)}, "
        f"fsize={fsize}, doff32={d32})\nfirst hits: {hits[:4]}\n"
        f"last hits: {hits[-6:] if hits else []}\nhex -48..EOF: {tail}\n{ddiag}")



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
