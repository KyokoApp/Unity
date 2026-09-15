#!/usr/bin/env python3
"""
Pemeriksa struktural shader Aurelia, dijalankan TANPA Unity.

Apa yang bisa dibuktikan di sini:
  - nama shader cocok dengan yang dicari Stage2SceneBuilder lewat Shader.Find
  - kurung kurawal seimbang, HLSLPROGRAM/ENDHLSL berpasangan
  - setiap Pass punya #pragma vertex dan #pragma fragment
  - isi Properties{} dan CBUFFER_START(UnityPerMaterial) SAMA PERSIS

Poin terakhir itu yang penting. SRP Batcher menolak shader yang properti
materialnya tidak seluruhnya berada di cbuffer UnityPerMaterial, dan penolakan
itu tidak memunculkan error apa pun -- hanya tulisan kecil "not compatible" di
Inspector sementara draw call membengkak. Membandingkan dua daftar secara
mekanis jauh lebih andal daripada membacanya.

Apa yang TIDAK bisa dibuktikan di sini: sintaks HLSL, keberadaan include URP,
dan hasil visual. Itu hanya bisa diuji di Unity.
"""
import re, sys, glob, os

HERE       = os.path.dirname(os.path.abspath(__file__))
PROJECT    = os.path.abspath(os.path.join(HERE, "..", ".."))          # akar repo Unity
SHADER_DIR = os.path.join(PROJECT, "Assets", "_Project", "Shaders")
EXPECTED = {"AureliaTerrain.shader": "Aurelia/Terrain", "AureliaWater.shader": "Aurelia/Water"}

def strip_comments(s):
    s = re.sub(r"/\*.*?\*/", "", s, flags=re.S)
    return re.sub(r"//[^\n]*", "", s)

def properties_of(s):
    m = re.search(r"Properties\s*\{(.*?)\n\s*\}", s, re.S)
    if not m: return []
    return re.findall(r"^\s*(\w+)\s*\(", m.group(1), re.M)

def resolve_includes(body):
    """Ganti #include "Assets/..." dengan isi filenya, kalau file itu ada di
    repo. Include ke Packages/ (URP) tidak bisa dibaca di sini dan memang
    tidak perlu -- yang diperiksa hanya cbuffer milik kita sendiri."""
    def sub(m):
        p = os.path.join(PROJECT, m.group(1))
        return open(p).read() if os.path.exists(p) else ""
    prev = None
    for _ in range(5):
        if body == prev: break
        prev = body
        body = re.sub(r'#include\s+"(Assets/[^"]+)"', sub, body)
    return body

def decl_names(block):
    """Nama properti dari sebuah blok CBUFFER_START(UnityPerMaterial)."""
    TYPES = {"float","half","fixed","int","uint","bool",
             "float2","float3","float4","half2","half3","half4",
             "float2x2","float3x3","float4x4","double","real","real4"}
    out = []
    for m in re.finditer(r"CBUFFER_START\s*\(\s*UnityPerMaterial\s*\)(.*?)CBUFFER_END", block, re.S):
        for line in strip_comments(m.group(1)).split(";"):
            for tok in re.findall(r"[A-Za-z_]\w*", line):
                if tok not in TYPES and tok not in out:
                    out.append(tok)
    return out

def cbuffer_per_pass(s):
    out = []
    for m in re.finditer(r"HLSLPROGRAM(.*?)ENDHLSL", s, re.S):
        out.append(decl_names(resolve_includes(m.group(1))))
    return out

def main():
    ok = True
    files = sorted(glob.glob(os.path.join(SHADER_DIR, "*.shader")))
    if not files:
        print("TIDAK ADA file .shader di", os.path.normpath(SHADER_DIR)); return 1
    for f in files:
        name = os.path.basename(f)
        raw = open(f).read()
        s = strip_comments(raw)
        print(f"--- {name} ---")
        m = re.search(r'Shader\s+"([^"]+)"', s)
        declared = m.group(1) if m else None
        exp = EXPECTED.get(name)
        if exp and declared != exp:
            print(f"  [GAGAL] nama shader '{declared}' != diharapkan '{exp}'"); ok = False
        else:
            print(f"  [ok] nama shader: {declared}")

        b1, b2 = s.count("{"), s.count("}")
        print(f"  [{'ok' if b1==b2 else 'GAGAL'}] kurung kurawal {b1}/{b2}")
        ok &= (b1 == b2)

        h1, h2 = len(re.findall(r"HLSLPROGRAM", s)), len(re.findall(r"ENDHLSL", s))
        print(f"  [{'ok' if h1==h2 else 'GAGAL'}] HLSLPROGRAM {h1} / ENDHLSL {h2}")
        ok &= (h1 == h2)

        npass = len(re.findall(r"\bPass\b\s*\{", s))
        nv = len(re.findall(r"#pragma\s+vertex\s+\S+", s))
        nf = len(re.findall(r"#pragma\s+fragment\s+\S+", s))
        good = (nv == npass and nf == npass)
        print(f"  [{'ok' if good else 'GAGAL'}] Pass={npass}, pragma vertex={nv}, fragment={nf}")
        ok &= good

        props = properties_of(s)
        per_pass = cbuffer_per_pass(s)
        good = True
        for i, cbuf in enumerate(per_pass):
            def prop_in_cbuf(p):
                if p in cbuf:
                    return True
                if (p + "_ST") in cbuf:
                    return True
                return False
            def cbuf_in_props(c):
                if c in props:
                    return True
                if c.endswith("_ST") and c[:-3] in props:
                    return True
                return False
            miss_cb = [p for p in props if not prop_in_cbuf(p)]
            miss_pr = [c for c in cbuf if not cbuf_in_props(c)]
            if miss_cb or miss_pr:
                good = False
                print(f"        Pass {i+1}: kurang di cbuffer {miss_cb}; berlebih {miss_pr}")
        if per_pass and any(c != per_pass[0] for c in per_pass[1:]):
            good = False
            print(f"        cbuffer antar Pass BEDA: {per_pass}")
        if not any(per_pass):
            good = False
            print("        tidak ada CBUFFER_START(UnityPerMaterial) sama sekali")
        print(f"  [{'ok' if good else 'GAGAL'}] SRP Batcher: Properties({len(props)}) "
              f"vs cbuffer {npass} Pass {per_pass[0] if per_pass else []}")
        if not good:
            print("        -> shader akan ditandai 'SRP Batcher: not compatible'")
        ok &= good

        bad = [m.group(0) for m in re.finditer(r"(Attributes|Varyings)\s+(in|out)\s*\)", s)]
        if bad:
            print(f"  [GAGAL] parameter fungsi memakai keyword HLSL: {bad} -- ganti nama (mis. i/v)")
            ok = False
        else:
            print("  [ok] tidak ada parameter fungsi bernama keyword HLSL (in/out)")

    print("SEMUA CEK LULUS" if ok else "ADA YANG GAGAL")
    return 0 if ok else 1

if __name__ == "__main__":
    sys.exit(main())
