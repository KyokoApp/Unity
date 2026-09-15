#!/usr/bin/env python3
"""Cek referensi assembly: meniru CARA UNITY menyusun project, bukan cara harness.

KENAPA SKRIP INI ADA
--------------------
Unity TIDAK mengompilasi semua skrip jadi satu gundukan. Tiap folder dengan
`*.asmdef` adalah assembly sendiri, dan ia hanya boleh memakai jenis dari
assembly yang ia DAFTARKAN di `references`. Harness `unitystub` menggabungkan
semua skrip ke satu proyek csproj, jadi pelanggaran batas assembly -- skrip
Runtime menyentuh UnityEditor, memakai URP tanpa mereferensikan
`Unity.RenderPipelines.Universal.Runtime`, memakai `Unity.Collections` yang
tidak terdaftar -- LOLOS di harness lalu meledak di CI setelah 6-12 menit dan
selepasan lisensi terbuang. Itu persis yang terjadi pada RPG.Runtime di run
v0.2.0-col-fix9: `Csc ... RPG.Runtime.dll -> exitcode 1`.

Aturannya sederhana dan bisa diperiksa tanpa engine: untuk tiap `using X;`
di dalam folder ber-asmdef, cari assembly yang menyediakannya.

Keterbatasan yang jujur: ini memeriksa namespace, bukan tanda tangan anggota.
Yang TIDAK bisa ditangkap: salah nama properti, overload berbeda, atau API
yang ada di Editor tapi hilang di Player (mis. `#if UNITY_EDITOR` yang bocor).
Itu ranah _verify/unitystub.
"""
import os
import re
import json
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
ASSETS = os.path.join(ROOT, "Assets")

# using -> assembly yang harus tersedia. Hanya namespace yang TIDAK dijamin
# ada oleh UnityEngine core (yang otomatis direferensikan kecuali
# noEngineReferences). Tabel ini kecil karena project ini kecil; kalau nanti
# memakai paket baru, tambahkan barisnya di sini.
NAMESPACE_OWNER = {
    "UnityEditor": "UnityEditor",                       # hanya assembly Editor-only
    "UnityEditor.Rendering": "UnityEditor.Rendering",
    "UnityEngine.Rendering.Universal": "Unity.RenderPipelines.Universal.Runtime",
    "UnityEngine.Rendering.Universal.Editor": "Unity.RenderPipelines.Universal.Editor",
    "UnityEditor.Rendering.Universal": "Unity.RenderPipelines.Universal.Editor",
    "UnityEngine.UI": "UnityEngine.UI",
    "UnityEngine.EventSystems": "UnityEngine.UI",
    "Unity.Collections": "Unity.Collections",
    "Unity.Mathematics": "Unity.Mathematics",
    "Unity.Jobs": "Unity.Jobs",
    "Unity.Burst": "Unity.Burst",
    "UnityEngine.InputSystem": "Unity.InputSystem",
    "UnityEngine.AddressableAssets": "Unity.Addressables",
    "GLTFast": "glTFast",
    "UniGLTF": "UniGLTF",
    "UniGLTF.Editor": "UniGLTF.Editor",
    "VRM": "VRM",
    "VRM10": "VRM10",
    "TMPro": "Unity.TextMeshPro",
}

# Nama assembly yang dianggap "editor-only": skrip Player tidak boleh memakainya
# di luar blok #if UNITY_EDITOR.
EDITOR_ONLY = {"UnityEditor", "UnityEditor.Rendering",
               "Unity.RenderPipelines.Universal.Editor", "UniGLTF.Editor"}

RE_USING = re.compile(r"^\s*using\s+(?:static\s+)?([A-Za-z_][\w.]*)\s*;", re.M)
RE_NS = re.compile(r"^\s*namespace\s+([A-Za-z_][\w.]*)", re.M)
RE_DEFINE = re.compile(r"^\s*#if\s+(.*)$")
RE_ENDIF = re.compile(r"^\s*#endif")


def asmdef_files():
    for dirpath, dirnames, filenames in os.walk(ASSETS):
        dirnames[:] = [d for d in dirnames if d not in ("Scenes", "Shaders", "Art")]
        for f in filenames:
            if f.endswith(".asmdef"):
                yield os.path.join(dirpath, f)


def cs_files(folder):
    for dirpath, _dirnames, filenames in os.walk(folder):
        for f in filenames:
            if f.endswith(".cs"):
                yield os.path.join(dirpath, f)


def editor_guarded(text, match_start):
    """True kalau posisi `match_start` berada di dalam blok #if UNITY_EDITOR."""
    depth = 0
    guarded = False
    stack = []
    for line in text[:match_start].splitlines():
        m = RE_DEFINE.match(line)
        if m:
            cond = m.group(1)
            guarded_here = "UNITY_EDITOR" in cond and "!" not in cond.split("UNITY_EDITOR")[0]
            stack.append(guarded_here)
            depth += 1
        elif RE_ENDIF.match(line):
            if stack:
                stack.pop()
            depth = max(0, depth - 1)
    return any(stack)


def owner_of(ns):
    """Cari assembly penyedia namespace, terpanjang dulu (UnityEngine.UI sebelum UnityEngine)."""
    best = None
    for key, asm in NAMESPACE_OWNER.items():
        if ns == key or ns.startswith(key + "."):
            if best is None or len(key) > len(best[0]):
                best = (key, asm)
    return best[1] if best else None


def main():
    problems = []
    checked = 0
    for path in sorted(asmdef_files()):
        folder = os.path.dirname(path)
        with open(path, encoding="utf-8") as fh:
            spec = json.load(fh)
        name = spec.get("name", os.path.basename(path)[:-7])
        refs = set(spec.get("references", []))
        auto = spec.get("autoReferenced", True)
        editor_only = spec.get("includePlatforms", []) == ["Editor"]
        no_engine = spec.get("noEngineReferences", False)
        own_ns = set()
        for cs in cs_files(folder):
            m = RE_NS.search(open(cs, encoding="utf-8").read())
            if m:
                own_ns.add(m.group(1))

        for cs in cs_files(folder):
            text = open(cs, encoding="utf-8").read()
            for m in RE_USING.finditer(text):
                ns = m.group(1)
                checked += 1
                if ns in own_ns or ns.startswith("System") or ns.startswith("RPG"):
                    continue
                # `using Debug = UnityEngine.Debug;` -> ambil sisi kanan
                if "=" in ns:
                    continue
                need = owner_of(ns)
                if need is None:
                    if no_engine and (ns == "UnityEngine" or ns.startswith("UnityEngine.")):
                        problems.append((cs, name, ns,
                                        "pakai UnityEngine tapi noEngineReferences: true"))
                    continue
                if need in refs:
                    continue
                if need == "UnityEditor":
                    if editor_only:
                        continue                      # assembly Editor: UnityEditor selalu ada
                    if editor_guarded(text, m.start()):
                        continue                      # aman: di dalam #if UNITY_EDITOR
                    problems.append((cs, name, ns,
                                     "UnityEditor hanya boleh dipakai di dalam #if UNITY_EDITOR "
                                     "pada assembly non-Editor (kalau tidak, build Player gagal "
                                     "atau assembly Editor-only bocor ke APK)"))
                    continue
                problems.append((cs, name, ns,
                                  f"assembly '{need}' tidak ada di references {sorted(refs)}"))

    print(f"asmdef: {len(list(asmdef_files()))} file, {checked} directive using diperiksa")
    if problems:
        for cs, asm, ns, why in problems:
            rel = os.path.relpath(cs, ROOT)
            print(f"  [X] {rel}: `using {ns};` di {asm} -- {why}", file=sys.stderr)
        print("\nKegagalan seperti ini LOLOS di _verify/unitystub (semua skrip jadi satu "
              "assembly) dan baru terlihat setelah Unity mengompilasi per-asmdef di CI.",
              file=sys.stderr)
        return 1
    print("  [ok] semua using tercakup referensi asmdef-nya")
    return 0


if __name__ == "__main__":
    sys.exit(main())
