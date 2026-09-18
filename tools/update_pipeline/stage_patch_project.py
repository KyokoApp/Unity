#!/usr/bin/env python3
"""Stage proyek minimal untuk mengekspor PATCH pack yang benar-benar kecil.

Masalah: `--export-pack` dengan `export_filter="selected_resources"` di
Godot 4.5 tidak memangkas isi pack seperti yang diharapkan di pipeline ini
(patch selalu seukuran paket aset penuh ~50 MB).

Solusi: buat proyek temporer (build/patch_project) yang hanya berisi file
yang berubah sejak baseline + cache import Godot, lalu export dengan
export_filter="all_resources" di proyek itu — exporter hanya bisa
mengekspor apa yang memang ada di sana.

Yang disalin:
- project.godot apa adanya (project.binary patch akan identik dengan paket
  utama, sehingga aman walau di-load menimpa yang lama).
- Seluruh cache `.godot/imported/` + uid_cache.bin + global script class
  cache (dibutuhkan exporter untuk mengkonversi sumber; yang diekspor
  tetap hanya yang direferensikan file yang disalin).
- Hanya file sumber yang berubah dan relevan (aturan sama dengan
  gen_patch_filter.is_pack_relevant) + sidecar .import-nya.
"""
import os
import re
import shutil
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, "..", ".."))
STAGE_DIR = os.path.join(REPO_ROOT, "build", "patch_project")
CHANGED_LIST = os.path.join(REPO_ROOT, "build", "android", "changed_files.txt")

sys.path.insert(0, SCRIPT_DIR)
from gen_patch_filter import is_pack_relevant  # noqa: E402

PRESET_TEMPLATE = """[preset.0]

name="PatchPack"
platform="Linux"
runnable=false
dedicated_server=false
custom_features=""
export_filter="all_resources"
include_filter=""
exclude_filter=""
export_path=""
encryption_include_filters=""
encryption_exclude_filters=""
encrypt_pck=false
encrypt_directory=false
script_export_mode=2

[preset.0.options]

binary_format/architecture="x86_64"
"""


def copy_file(rel: str) -> bool:
    src = os.path.join(REPO_ROOT, rel)
    if not os.path.exists(src):
        return False
    dst = os.path.join(STAGE_DIR, rel)
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    shutil.copy2(src, dst)
    # Sidecar .import milik sumber.
    import_src = src + ".import"
    if os.path.exists(import_src):
        shutil.copy2(import_src, dst + ".import")
    return True


def main() -> int:
    if not os.path.exists(CHANGED_LIST):
        raise SystemExit(f"Daftar perubahan tidak ditemukan: {CHANGED_LIST}")

    with open(CHANGED_LIST, "r", encoding="utf-8") as f:
        changed = [line.strip() for line in f if line.strip()]

    # Bersihkan sisa run sebelumnya agar file basi tidak ikut patch.
    if os.path.isdir(STAGE_DIR):
        shutil.rmtree(STAGE_DIR)
    os.makedirs(STAGE_DIR, exist_ok=True)

    # 1) Tulis export preset minimal.
    with open(os.path.join(STAGE_DIR, "export_presets.cfg"), "w", encoding="utf-8") as f:
        f.write(PRESET_TEMPLATE)

    # 2) project.godot apa adanya (project.binary di patch identik dengan
    #    paket utama -> aman ditimpa berlapis saat runtime).
    shutil.copy2(os.path.join(REPO_ROOT, "project.godot"),
                 os.path.join(STAGE_DIR, "project.godot"))

    # 3) Cache import keseluruhan (hanya sebagai sumber konversi; yang
    #    diekspor tetap hanya yang direferensikan file yang disalin).
    godot_dir = os.path.join(REPO_ROOT, ".godot")
    imported = os.path.join(godot_dir, "imported")
    if os.path.isdir(imported):
        shutil.copytree(imported, os.path.join(STAGE_DIR, ".godot", "imported"),
                        dirs_exist_ok=True)
    for extra in ("uid_cache.bin", "global_script_class_cache.cfg"):
        p = os.path.join(godot_dir, extra)
        if os.path.exists(p):
            shutil.copy2(p, os.path.join(STAGE_DIR, ".godot", extra))

    # 4) Hanya file yang berubah dan relevan untuk paket aset.
    copied = []
    for rel in changed:
        if not is_pack_relevant(rel):
            continue
        if copy_file(rel):
            copied.append(rel)

    print("[stage_patch_project] file disalin ke proyek staged:")
    for rel in copied:
        print("   + " + rel)
    print(f"[stage_patch_project] stage dir: {STAGE_DIR}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
