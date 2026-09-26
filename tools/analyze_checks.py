#!/usr/bin/env python3
"""Skrip CEK SEMANTIK RINGAN untuk GDScript — menangkap bug kelas analyzer
yang lolos dari gdparse (parse-only):
  1) deklarasi 'var X' ganda di scope fungsi yang sama (error di Godot)
  2) pemakaian preload path yang file-nya tidak ada
  3) referensi konstanta/path scene yang hilang
Syarat pakai: python3 /tmp/analyze_checks.py <root_repo>
Keluar 0 bila tidak ada temuan eror, 1 bila ada.
"""
import os, re, sys

root = sys.argv[1] if len(sys.argv) > 1 else "."
problems = []
warns = []

ind_re = re.compile(r"^(\t*)")
var_re = re.compile(r"^\s*(?:static\s+)?var\s+([A-Za-z_]\w*)\s*(?::[^=]+)?\s*[:=]?")
func_re = re.compile(r"^\s*(?:static\s+)?func\s+([A-Za-z_]\w*)\s*\(")
preload_re = re.compile(r"preload\(\s*\"([^\"]+)\"\s*\)")
load_re = re.compile(r"load\(\s*\"([^\"]+)\"\s*\)|:\s*=\s*\"(res://[^\"]+)\"")

gd_files = []
for dp, dn, fn in os.walk(os.path.join(root, "project")):
    if ".godot" in dp or "export" in dp:
        continue
    for f in fn:
        if f.endswith(".gd"):
            gd_files.append(os.path.join(dp, f))

def indent_of(indent_str):
    return len(indent_str.replace(" " * 4, "\t"))

for path in sorted(gd_files):
    rel = os.path.relpath(path, root)
    src = open(path, encoding="utf-8").read()
    lines = src.split("\n")
    # --- cek 1: deklarasi var ganda per scope fungsi ---
    # scope = urutan indent path dalam satu fungsi
    func_idents = []  # stack: (indent_level, declared:set)
    cur_func = None
    file_vids = set()
    for i, ln in enumerate(lines, 1):
        code = ln.split("#", 1)[0].rstrip()
        if not code.strip():
            continue
        m_ind = ind_re.match(code)
        ind = indent_of(m_ind.group(1)) if m_ind else 0
        fm = func_re.match(ln)
        if fm:
            cur_func = fm.group(1)
            func_idents = [(ind, set())]
            continue
        vm = var_re.match(ln)
        if vm:
            name = vm.group(1)
            if name.startswith("_") and False:
                pass
            if func_idents:
                # pop scope lebih dalam/in-line
                while func_idents and func_idents[-1][0] > ind:
                    func_idents.pop()
                while func_idents and func_idents[-1][0] == ind and func_idents[-1][0] > (
                    func_idents[0][0] if len(func_idents) > 1 else func_idents[0][0]):
                    break
                for lvl, decl in func_idents:
                    if lvl == ind and name in decl:
                        problems.append(f"{rel}:{i}: variabel '{name}' dideklarasikan ganda (func {cur_func}, indent {ind})")
                # catat di scope paling dalam yg indent == ind
                if func_idents and func_idents[-1][0] == ind:
                    func_idents[-1][1].add(name)
                else:
                    func_idents.append((ind, {name}))
            else:
                # variabel tingkat file
                if name in file_vids:
                    problems.append(f"{rel}:{i}: variabel file '{name}' dideklarasikan ganda")
                file_vids.add(name)
    # --- cek 2: preload path valid ---
    for m in preload_re.finditer(src):
        p = m.group(1)
        if p.startswith("res://"):
            tgt = os.path.join(root, "project", p[6:])
            if not os.path.exists(tgt):
                problems.append(f"{rel}: preload tidak ditemukan: {p}")
    # --- cek 3: load("res://...") path valid ---
    for m in re.finditer(r"\bload\(\s*\"(res://[^\"]+)\"\s*\)", src):
        p = m.group(1)
        tgt = os.path.join(root, "project", p[6:])
        if not os.path.exists(tgt):
            problems.append(f"{rel}: load path tidak ditemukan: {p}")
    # --- cek 4: string konstanta path tsd (yang di-load di file lain) ---
    # --- cek 4b: inferensi `:=` dari properti Node3D pada var bertipe Node ---
    # INSIDEN RONDE-38: `var d := x.global_position.distance_to(y)` dengan
    # x bertipe Node → analyzer Godot 4.5: "Cannot infer the type of d …"
    # → PARSE ERROR KERAS → skrip gagal compile → pack terbit dengan pemain
    # mati (tombol serang diam). gdparse TIDAK menangkap kelas ini; cek ini ya.
    prop_pat = (r"\.(global_position|position|rotation|scale|"
                r"global_transform|transform|basis|quaternion|distance_to|to_local|to_global|look_at)\b")
    # (a) variabel KELAS bertipe Node: terlihat di seluruh file
    class_node_vars = set()
    for m in re.finditer(r"^var\s+(\w+)\s*:\s*Node(?!\w)", src, re.M):
        class_node_vars.add(m.group(1))
    # (b) PARAMETER func bertipe Node: hanya dalam badan func-nya
    func_starts = [(i, ln) for i, ln in enumerate(lines) if re.match(r"^\s*(?:static\s+)?func\s", ln)]
    param_node_vars = {}  # varname -> list of (awal, akhir) badan fungsi
    for fi, (i, ln) in enumerate(func_starts):
        end = func_starts[fi + 1][0] if fi + 1 < len(func_starts) else len(lines)
        for pm in re.finditer(r"[(,]\s*(\w+)\s*:\s*Node(?!\w)", ln):
            param_node_vars.setdefault(pm.group(1), []).append((i, end))

    def _flag(varname: str, i: int, code: str) -> None:
        hit = re.search(r"\b" + re.escape(varname) + prop_pat, code)
        if hit is None:
            return
        if ":=" in code:
            problems.append(
                f"{rel}:{i + 1}: '{varname}' bertipe Node dipakai untuk '.{hit.group(1)}' "
                f"di baris `:=` — analyzer tidak bisa infer tipe → parse error keras. "
                f"Ketik var sebagai Node3D (atau beri tipe eksplisit).")
        else:
            warns.append(
                f"{rel}:{i + 1}: akses dinamis '.{hit.group(1)}' pada '{varname}' bertipe Node "
                f"(jalan di runtime, tapi tak diperiksa — pertimbangkan Node3D).")

    for varname in sorted(class_node_vars):
        for i, ln in enumerate(lines):
            _flag(varname, i, ln.split("#", 1)[0])
    for varname, ranges in sorted(param_node_vars.items()):
        for i, ln in enumerate(lines):
            if any(a <= i < b for a, b in ranges):
                _flag(varname, i, ln.split("#", 1)[0])

# cek global: konstanta *_PATH/*_SCENE di semua file
scene_refs = re.findall(r'"(res://[^"]+)"', "")
const_paths = set()
for path in gd_files:
    src = open(path, encoding="utf-8").read()
    for m in re.finditer(r"^\s*const\s+\w+\s*(?::\s*\w+\s*)?=\s*\"(res://[^\"]+)\"", src, re.M):
        const_paths.add((os.path.relpath(path, root), m.group(1)))
for rel, p in sorted(const_paths):
    tgt = os.path.join(root, "project", p[6:])
    if not os.path.exists(tgt):
        problems.append(f"{rel}: const path tidak ditemukan: {p}")

# cek 5: scene .tscn: script path eksternal valid + uid file (abaikan uid)
for dp, dn, fn in os.walk(os.path.join(root, "project")):
    if ".godot" in dp:
        continue
    for f in fn:
        if f.endswith(".tscn"):
            full = os.path.join(dp, f)
            rel = os.path.relpath(full, root)
            src = open(full, encoding="utf-8").read()
            for m in re.finditer(r'path="(res://[^"]+)"', src):
                tgt = os.path.join(root, "project", m.group(1)[6:])
                if not os.path.exists(tgt):
                    problems.append(f"{rel}: tscn rujuk path hilang: {m.group(1)}")

print(f"Discari: {len(gd_files)} file .gd")
for p in problems:
    print("EROR:", p)
for w in warns:
    print("WASPADA:", w)
if problems:
    sys.exit(1)
print("BERSIH ✓")
