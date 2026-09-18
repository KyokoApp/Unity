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

    def next_entry_start(pos):
        """Cari awal entry berikutnya dalam jendela kecil (padding/flags)."""
        for step in range(0, 13):
            pl = u32(pos + step)
            if pl is None or pl < 3 or pl > 4096:
                continue
            name_off = pos + step + 4
            if buf[name_off:name_off + 6] != b"res://":
                continue
            # nama harus diakhiri nul atau data-tail valid
            return pos + step
        return None

    def walk(dir_off, count):
        """Parse adaptif dari count entry; abaikan padding/flags kecil antar entry."""
        pos = next_entry_start(dir_off + 4)
        if pos is None:
            return None
        entries = []
        for _ in range(count):
            pl = u32(pos)
            if pl is None or pl < 3 or pl > 4096:
                return None
            name_off = pos + 4
            if name_off + pl > fsize:
                return None
            raw = buf[name_off:name_off + pl]
            if raw.endswith(b"\x00"):
                raw = raw[:-1]
            name = raw.decode("utf-8", "replace")
            if not name.startswith("res://"):
                return None
            pos = name_off + pl
            # offset+size (16B) + md5 (16B) wajib ada
            if pos + 32 > fsize:
                return None
            offs, size = struct.unpack("<QQ", buf[pos:pos + 16])
            pos += 32
            entries.append((name, size))
            # loncat ke entry berikut (padding/flags kecil), kecuali entry terakhir
            if len(entries) < count:
                nxt = next_entry_start(pos)
                if nxt is None or nxt - pos > 12:
                    return None
                pos = nxt
        # setelah semua entry: boleh ada trailer (padding/magic/md5 cks)
        # dir v3 diakhiri: md5(16)+GDPK(4)? toleransi sampai 44 byte
        if fsize - pos <= 44:
            return entries
        return None

    best_chain = 0
    for h in hits:
        for cback in (8, 12, 16, 20):
            count = u32(h - cback)
            if count is None or count == 0 or count > 50000:
                continue
            got = walk(h - cback, count)
            if got:
                return got
        # diagnosa rantai terpanjang (tanpa count): mulai dari plen@h-4
        pos = h - 4
        chain = 0
        while chain < 5000:
            pl = u32(pos)
            if pl is None or pl < 3 or pl > 4096:
                break
            noff = pos + 4
            if buf[noff:noff + 6] != b"res://":
                break
            nxt = next_entry_start(noff + pl + 32)
            if nxt is None:
                break
            chain += 1
            pos = nxt
        best_chain = max(best_chain, chain)
        # lacak percobaan terbaik untuk diagnosa (manual chain tanpa count)
        # (skip: hanya hitung res hits)

    # diagnosa: ambil 4 entry dari hit pertama yang valid struktur lokalnya saja
    sample = []
    for h in hits[:80]:
        pl = u32(h - 4)
        if pl and 3 <= pl <= 4096 and buf[h:h + 6] == b"res://":
            raw = buf[h:h + min(pl, 60)].split(b"\x00")[0]
            sample.append(raw.decode("utf-8", "replace"))
        if len(sample) >= 4:
            break

    tail = buf[-48:].hex() if fsize > 48 else buf.hex()
    around = buf[hits[-1] - 16:hits[-1] + 16].hex() if hits else "-"
    raise SystemExit(
        f"Gagal parse direktori PCK {path} (pack_ver={pack_ver}, hits={len(hits)}, "
        f"fsize={fsize}, best_chain={best_chain})\n"
        f"sample offsets: {hits[:6]}\nlast hits: {hits[-6:] if hits else []}\n"
        f"sampel nama: {sample}\nhex -48..EOF: {tail}\nhex di sekitar hit terakhir: {around}")



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
