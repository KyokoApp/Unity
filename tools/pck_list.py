#!/usr/bin/env python3
## pck_list.py — daftar isi file .pck (header Godot 4 PCK).
## Pakai: python3 tools/pck_list.py path/ke/file.pck
import struct, sys

def read_pck(path):
    with open(path, "rb") as f:
        data = f.read()
    if data[:4] != b"GDPC" and data[:4] != b"GDPK":
        # PCK bisa menempel di akhir binary (exe/apk): cari magic GDPC dari belakang
        idx = data.rfind(b"GDPC")
        if idx == -1:
            print("bukan file PCK (magic GDPC tidak ditemukan)")
            return
        off = idx
    else:
        off = 0
    ver = struct.unpack("<I", data[off + 4:off + 8])[0]
    print(f"PCK format v{ver}")
    pos = off + 4 * 4 + 4 * 4 + 16 * 4  # magic + ver + godot ver + reserved
    flags = struct.unpack("<I", data[pos:pos + 4])[0]
    pos += 4
    file_base = struct.unpack("<Q", data[pos:pos + 8])[0]
    pos += 8
    files = []
    count = struct.unpack("<I", data[pos:pos + 4])[0]
    pos += 4
    for _ in range(count):
        name_len = struct.unpack("<I", data[pos:pos + 4])[0]
        pos += 4
        name = data[pos:pos + name_len].rstrip(b"\x00").decode("utf-8", "replace")
        pos += name_len
        f_off, f_size = struct.unpack("<QQ", data[pos:pos + 16])
        pos += 16
        pos += 16  # md5
        if flags & 1:
            pos += 4
        files.append((name, f_off, f_size))
    total = 0
    for name, o, s in sorted(files):
        print(f"{s:>10d}  {name}")
        total += s
    print(f"-- {len(files)} file, {total} B ({total/1048576:.1f} MB) tak terkompres")

if __name__ == "__main__":
    read_pck(sys.argv[1])
