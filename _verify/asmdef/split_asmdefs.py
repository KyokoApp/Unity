#!/usr/bin/env python3
"""Bangun ulang project sesuai .asmdef, supaya kompilasi diperiksa seperti Unity.

MENGAPA
-------
_verify/unitystub mengompilasi SEMUA skrip + SEMUA stub dalam SATU assembly.
Unity tidak begitu: tiap .asmdef adalah assembly terpisah yang cuma boleh
memakai apa yang ia daftarkan di `references`. Selisih itu sudah memakan
berjam-jam: di run v0.2.0-cel-fix9 Unity melaporkan

    Csc Library/Bee/artifacts/1300b0aE.dag/RPG.Runtime.dll -> exitcode 1

sedangkan harness satu-gundukan itu hijau, karena jenis yang sebenarnya
hanya ada di assembly lain (atau yang stub-nya kita karang sendiri) tetap
kelihatan "ada" kalau semuanya dilebur jadi satu.

CARA KERJA
----------
1. Pecah berkas stub menjadi satu folder per ASSEMBLY, memakai namespace ->
   assembly (tabel di check_asmdef_refs.py, ditambah beberapa entri stub).
2. Untuk tiap .asmdef di Assets, tulis csproj dengan AssemblyName + referensi
   yang sama, isi Compile-nya hanya .cs di folder itu.
3. Bangun berurutan (topologis) dengan dotnet build.

Kalau `dotnet build` gagal, penyebabnya sama dengan yang akan dikatakan Unity,
tanpa menunggu 6-12 menit build player dan tanpa memakan seat lisensi Unity.

Skrip ini SENGAJA tidak dipakai sebagai gerbang (continue-on-error di
verify.yml) sampai terbukti stabil di beberapa run.
"""
import json
import os
import re
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
ASSETS = os.path.join(ROOT, "Assets")
STUB_DIR = os.path.join(ROOT, "_verify", "unitystub")
OUT = os.path.join(HERE, ".generated")

# namespace -> assembly yang menyediakannya (untuk stub kita).
NS_TO_ASM = {
    "UnityEngine": "__UnityEngine",
    "UnityEngine.Rendering": "__UnityEngine",
    "UnityEngine.Profiling": "__UnityEngine",
    "UnityEngine.EventSystems": "UnityEngine.UI",
    "UnityEngine.SceneManagement": "__UnityEngine",
    "UnityEngine.Rendering.Universal": "Unity.RenderPipelines.Universal.Runtime",
    "UnityEditor": "UnityEditor",
    "UnityEditor.SceneManagement": "UnityEditor",
    "UnityEditor.Build": "UnityEditor",
    "UnityEditor.Build.Reporting": "UnityEditor",
    "UnityEditor.Rendering": "UnityEditor",
    "UnityEditor.Rendering.Universal": "Unity.RenderPipelines.Universal.Editor",
    "UniGLTF": "UniGLTF",
    "UniGLTF.Editor": "UniGLTF.Editor",
    "VRM": "VRM",
    "VRM10": "VRM10",
}
# Assembly buatan sendiri yang menyediakan stub: tidak bisa direferensikan
# lewat nama Unity, jadi kita petakan dari referensi asmdef.
STUB_ASSEMBLIES = {
    "__UnityEngine": ["UnityEngine", "UnityEngine.CoreModule"],
    "UnityEditor": ["UnityEditor"],
    "Unity.RenderPipelines.Universal.Runtime": ["Unity.RenderPipelines.Universal.Runtime"],
    "Unity.RenderPipelines.Universal.Editor": ["Unity.RenderPipelines.Universal.Editor"],
    "UnityEngine.UI": ["UnityEngine.UI"],
    "UniGLTF": ["UniGLTF"],
    "UniGLTF.Editor": ["UniGLTF.Editor"],
    "VRM": ["VRM"],
    "VRM10": ["VRM10"],
}
GLOBAL_USINGS = ["System", "System.Collections.Generic", "System.IO", "System.Linq"]


def split_stub_file(path):
    """Kembalikan {assembly: [(namespace, kode)]} dari satu berkas stub.

    Berkas stub ditulis rapat (satu namespace per baris, {...} sebaris), jadi
    pemecahannya cukup mengikuti `namespace X` di kolom 0 dan menyeimbangkan
    kurung kurawal.
    """
    out = {}
    lines = open(path, encoding="utf-8").read().split("\n")
    head = []      # using / komentar di luar namespace apa pun -> ikut ke semua
    i = 0
    while i < len(lines):
        line = lines[i]
        m = re.match(r"^namespace\s+([A-Za-z_][\w.]*)\s*$", line)
        if not m:
            m2 = re.match(r"^namespace\s+([A-Za-z_][\w.]*)\s*\{", line)
            if not m2:
                head.append(line)
                i += 1
                continue
        ns = (m or m2).group(1)
        buf, depth = [], 0
        started = False
        while i < len(lines):
            for ch in lines[i]:
                if ch == "{":
                    depth += 1
                    started = True
                elif ch == "}":
                    depth -= 1
            buf.append(lines[i])
            i += 1
            if started and depth <= 0:
                break
        asm = NS_TO_ASM.get(ns)
        if asm is None:                      # namespace terpanjang yang cocok
            for k, v in sorted(NS_TO_ASM.items(), key=lambda kv: -len(kv[0])):
                if ns.startswith(k + "."):
                    asm = v
                    break
        out.setdefault(asm or "__UnityEngine", []).append((ns, "\n".join(buf)))
    return out, head


def collect():
    per_asm = {}
    for f in sorted(os.listdir(STUB_DIR)):
        if not f.endswith(".cs"):
            continue
        chunk, head = split_stub_file(os.path.join(STUB_DIR, f))
        for asm, items in chunk.items():
            per_asm.setdefault(asm, []).extend(items)
        if head:
            # using/namespace global (mis. `namespace UnityEngine { class X {} }`
            # ditulis satu baris) -> tempel ke assembly yang memakainya lewat
            # penelusuran nama; sederhananya: letakkan di __UnityEngine dan
            # biarkan yang lain melihatnya sebagai jenis global.
            per_asm.setdefault("__UnityEngine", []).append(
                ("<inline>", "\n".join(head)))
    return per_asm


# Urutan tetap assembly stub: yang di belakang boleh melihat yang di depan.
# Kenapa tetap dan bukan hasil analisis graf: stub saling memakai jenis
# (UnityEditor memakai UnityEngine, URP memakai keduanya, UniVRM memakai
# keduanya) dan analisis otomatis mudah salah arah -> siklus. Urutan salah
# hanya berarti satu referensi kurang, yang muncul sebagai error palsu; error
# palsu lebih mahal daripada longgar, jadi yang longgar yang dipilih.
# Yang sebenarnya diuji tetap ketat: proyek skrip hanya mendapat referensi
# yang DAFTAR di .asmdef-nya sendiri.
STUB_ORDER = ["__UnityEngine", "UnityEngine.UI", "UnityEditor",
              "Unity.RenderPipelines.Universal.Runtime",
              "Unity.RenderPipelines.Universal.Editor",
              "UniGLTF", "UniGLTF.Editor", "VRM", "VRM10"]


def write_stubs(per_asm):
    os.makedirs(OUT, exist_ok=True)
    order = [a for a in STUB_ORDER if a in per_asm] + [a for a in per_asm if a not in STUB_ORDER]
    built = []
    for asm in order:
        items = per_asm[asm]
        proj = os.path.join(OUT, asm)
        os.makedirs(proj, exist_ok=True)
        src = ["// DIHASILKAN oleh _verify/asmdef/split_asmdefs.py -- jangan disunting.",
               "using System;", "using UnityEngine;", ""]
        for ns, code in items:
            src.append(f"// --- {ns} (dari stub) ---")
            src.append(code)
        src.append("")
        open(os.path.join(proj, "stubs.cs"), "w", encoding="utf-8").write("\n".join(src))
        # semua stub yang sudah dibangun lebih dulu = boleh dipakai
        write_csproj(proj, asm, ["stubs.cs"], list(built))
        built.append(asm)
    return built


def write_csproj(proj, asm, files, refs):
    lines = ["<Project Sdk=\"Microsoft.NET.Sdk\">", "  <PropertyGroup>",
             "    <TargetFramework>net8.0</TargetFramework>",
             "    <LangVersion>latest</LangVersion>",
             "    <Nullable>disable</Nullable>",
             "    <EnableDefaultCompileItems>false</EnableDefaultCompileItems>",
             f"    <AssemblyName>{asm}</AssemblyName>",
             "    <DefineConstants>$(DefineConstants);UNITY_EDITOR;UNITY_6000_0_OR_NEWER</DefineConstants>",
             "    <NoWarn>CS0169;CS0414;CS0649;CS0067;CS0108;CS0114</NoWarn>",
             "  </PropertyGroup>", "  <ItemGroup>"]
    for f in files:
        lines.append(f"    <Compile Include=\"{f}\" />")
    lines.append("  </ItemGroup>")
    if refs:
        lines.append("  <ItemGroup>")
        for r in refs:
            rel = os.path.relpath(os.path.join(OUT, r, f"{r}.csproj"), proj)
            lines.append(f"    <ProjectReference Include=\"{rel}\" />")
        lines.append("  </ItemGroup>")
    lines += ["</Project>", ""]
    open(os.path.join(proj, f"{asm}.csproj"), "w", encoding="utf-8").write("\n".join(lines))


def project_names():
    return {a for a in os.listdir(OUT)} if os.path.isdir(OUT) else set()


def main():
    if os.path.isdir(OUT):
        shutil.rmtree(OUT)
    per_asm = collect()
    print("stub yang dipecah per assembly:")
    for a, items in sorted(per_asm.items()):
        print(f"  {a:48s} {len(items)} namespace")
    write_stubs(per_asm)

    # Tiap .asmdef -> satu proyek, isinya hanya .cs di foldernya.
    osys = project_names()
    order = []
    for dirpath, _d, files in os.walk(ASSETS):
        for f in files:
            if not f.endswith(".asmdef"):
                continue
            path = os.path.join(dirpath, f)
            spec = json.load(open(path, encoding="utf-8"))
            name = spec["name"]
            folder = os.path.dirname(path)
            cs = sorted(os.path.relpath(os.path.join(dirpath, x), dirpath)
                        for x in os.listdir(folder) if x.endswith(".cs"))
            if not cs:
                continue
            proj = os.path.join(OUT, name)
            os.makedirs(proj, exist_ok=True)
            for rel in cs:
                shutil.copy(os.path.join(folder, rel), os.path.join(proj, rel))
            wanted = set(spec.get("references", [])) | (
                set() if spec.get("noEngineReferences") else {"UnityEngine"})
            # nama Unity yang tidak ada di dunia stub -> dipetakan ke stub terdekat
            mapped = set()
            for w in wanted:
                if w in osys:
                    mapped.add(w)
                elif w.startswith("UnityEditor"):
                    mapped.add("UnityEditor")
            refs = sorted(mapped & osys) + sorted(mapped - osys)
            write_csproj(proj, name, cs, [r for r in refs if r != name])
            order.append(name)
            print(f"  proyek {name:20s} <- {len(cs)} berkas, referensi: {', '.join(sorted(wanted)) or '(kosong)'}")

    if not order:
        print("tidak ada asmdef, selesai.")
        return 0

    if shutil.which("dotnet") is None:
        print("\ndotnet tidak tersedia: proyek sudah dibuat di "
              f"{os.path.relpath(OUT, ROOT)}, tidak dikompilasi.")
        return 0

    rc_total = 0
    for name in order:
        proj = os.path.join(OUT, name, f"{name}.csproj")
        print(f"\n=== dotnet build {name} ===", flush=True)
        r = subprocess.run(["dotnet", "build", proj, "--nologo", "-c", "Release",
                            "-warnaserror", "-v", "q"],
                           capture_output=True, text=True)
        out = (r.stdout or "") + (r.stderr or "")
        errs = [l for l in out.splitlines() if ": error " in l or ": warning " in l]
        for l in errs[:40]:
            print("  " + l.strip())
        if r.returncode != 0:
            rc_total = 1
            print(f"  -> {name} GAGAL ({len(errs)} baris diagnostik). "
                  "Inilah yang akan dikatakan Unity soal assembly yang sama.")
        else:
            print(f"  -> {name} OK")
    return rc_total


if __name__ == "__main__":
    sys.exit(main())
