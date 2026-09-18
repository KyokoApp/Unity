#!/usr/bin/env python3
"""Generate include_filter untuk export preset "PatchPack" berdasarkan
`git diff` antara baseline commit (tools/update_pipeline/baseline_commit.txt)
dan HEAD.

Tujuannya: patch pack hanya berisi file yang BENAR-BENAR berubah sejak
baseline, sehingga pemain tidak perlu mengunduh ulang seluruh aset setiap
update. Patch bersifat kumulatif terhadap assets_v1.pck.

Script ini menulis ulang baris `export_filter` / `include_filter` di blok
[preset.6] ("PatchPack") pada export_presets.cfg.
"""
import os
import re
import subprocess
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, "..", ".."))
CFG_PATH = os.path.join(REPO_ROOT, "export_presets.cfg")
BASELINE_FILE = os.path.join(SCRIPT_DIR, "baseline_commit.txt")
PATCH_PRESET_NAME = "PatchPack"

# Folder yang memang menjadi isi paket aset (diunduh pemain).
PACK_CONTENT_PREFIXES = (
    "_scenes/",
    "_models/",
    "materials/",
)

# Folder yang tidak pernah boleh masuk patch (sama seperti exclude_filter).
NEVER_INCLUDE_PREFIXES = (
    ".git", ".github/", "Amv/", "images/", "videos/",
    "Universal Animation Library 2[Standard]/",
    "tools/", "build/", "exported/", "_script/",
    "docs/",
)

ALWAYS_INCLUDE = ("project.godot",)

# Exclude_filter PatchPack dipaksa slim: glob luas seperti `_models/*` AKAN
# menutupi include_filter (exclude menang di exporter Godot!) sehingga model
# baru tidak pernah masuk patch. Cukup jagokan konten berat-statis yang
# memang tak pernah di-patch (filter ini juga jala pengaman ganda).
SLIM_PATCH_EXCLUDES = "Universal Animation Library 2[Standard]/*, Amv/*, videos/*, images/*, icon_192.png, icon_432.png, _scenes/bootstrapper.tscn"

# File yang hidupnya di APK (bukan di paket aset) — bootstrapper & script
# tidak boleh ikut patch meski berada di bawah prefix konten.
NEVER_INCLUDE_FILES = (
    "_scenes/bootstrapper.tscn",
)


def read_baseline() -> str:
    if not os.path.exists(BASELINE_FILE):
        return ""
    with open(BASELINE_FILE, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#"):
                return line
    return ""


def git_changed_files(baseline: str) -> list[str]:
    try:
        out = subprocess.check_output(
            ["git", "diff", "--name-only", f"{baseline}..HEAD"],
            cwd=REPO_ROOT, text=True,
        )
    except subprocess.CalledProcessError as exc:
        print(f"[gen_patch_filter] git diff gagal ({exc}); fallback ke daftar minimal.", file=sys.stderr)
        return []
    return [line.strip() for line in out.splitlines() if line.strip()]


def is_pack_relevant(path: str) -> bool:
    if path in ALWAYS_INCLUDE:
        return True
    if path in NEVER_INCLUDE_FILES:
        return False
    if any(path.startswith(p) for p in NEVER_INCLUDE_PREFIXES):
        return False
    if path.endswith(".cs") or path.endswith(".uid"):
        return False
    return any(path.startswith(p) for p in PACK_CONTENT_PREFIXES)


def build_include_list(changed: list[str]) -> list[str]:
    files = [p for p in changed if is_pack_relevant(p) and os.path.exists(os.path.join(REPO_ROOT, p))]
    for extra in ALWAYS_INCLUDE:
        if extra not in files and os.path.exists(os.path.join(REPO_ROOT, extra)):
            files.append(extra)
    # Stabilkan urutan agar hasil deterministik.
    return sorted(files)


def rewrite_preset(cfg_text: str, include_list: list[str]) -> str:
    include_str = ", ".join(include_list)
    # Cari blok [preset.N] milik PatchPack.
    preset_re = re.compile(r"(\[preset\.(\d+)\][^\[]*?name=\"%s\")" % re.escape(PATCH_PRESET_NAME), re.S)
    m = preset_re.search(cfg_text)
    if not m:
        raise SystemExit(f'Preset "{PATCH_PRESET_NAME}" tidak ditemukan di export_presets.cfg')

    start = m.start(1)
    next_preset = cfg_text.find("\n[preset.", start + 5)
    end = next_preset if next_preset != -1 else len(cfg_text)
    block = cfg_text[start:end]

    block_new = re.sub(r'export_filter="[^"]*"', 'export_filter="selected_resources"', block, count=1)
    block_new = re.sub(
        r'include_filter="[^"]*"',
        'include_filter="%s"' % include_str,
        block_new, count=1,
    )
    # PENTING: rapikan exclude_filter — glob luas (mis. "_models/*") akan
    # menimpa include_filter sehingga aset baru tidak pernah ikut patch.
    block_new = re.sub(
        r'exclude_filter="[^"]*"',
        'exclude_filter="%s"' % SLIM_PATCH_EXCLUDES,
        block_new, count=1,
    )
    return cfg_text[:start] + block_new + cfg_text[end:]


def main() -> int:
    baseline = read_baseline()
    if not baseline:
        print("[gen_patch_filter] baseline kosong -> patch hanya berisi file minimum.")
        include = list(ALWAYS_INCLUDE)
    else:
        changed = git_changed_files(baseline)
        include = build_include_list(changed)
        print(f"[gen_patch_filter] baseline={baseline[:10]}.. -> {len(include)} file berubah sejak baseline:")
        for f in include:
            print("   + " + f)

    with open(CFG_PATH, "r", encoding="utf-8") as f:
        cfg = f.read()
    cfg = rewrite_preset(cfg, include)
    with open(CFG_PATH, "w", encoding="utf-8") as f:
        f.write(cfg)

    print(f"[gen_patch_filter] PatchPack include_filter ditulis ({len(include)} entri).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
