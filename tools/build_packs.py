#!/usr/bin/env python3
## build_packs.py — Bangun resource pack (.pck) per folder project/packs/*.
##
## - Versi pack hanya naik bila ISI folder berubah (hash konten).
## - Men-generate export_presets.cfg (1 preset Android APK + N preset pack).
## - Menjalankan Godot headless untuk export pack yang berubah.
## - Menulis server/manifest.json (id, version, size, sha256, url, deps).
##
## Pakai:  python3 tools/build_packs.py [--godot PATH] [--force] [--skip-export]
import json, hashlib, os, sys, subprocess, shutil, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROJECT = os.path.join(ROOT, "project")
PACKS_DIR = os.path.join(PROJECT, "packs")
SERVER_DIR = os.path.join(ROOT, "server")
SERVER_PACKS = os.path.join(SERVER_DIR, "packs")
DB_PATH = os.path.join(SERVER_DIR, "versions.json")

# Urutan & dependensi antar pack (untuk manifest + verifikasi bootstrap).
PACK_DEFS = {
    "core_scripts": {"deps": []},
    "shaders_materials": {"deps": []},
    "world_terrain": {"deps": ["shaders_materials"]},
    "world_props_forest": {"deps": ["shaders_materials", "world_terrain"]},
    "world_props_beach": {"deps": ["shaders_materials", "world_terrain"]},
    "animations": {"deps": []},
    "character_player": {"deps": ["animations", "shaders_materials"]},
    "ui": {"deps": []},
    "audio_sfx": {"deps": []},
    "audio_music": {"deps": []},
}
PACK_ORDER = list(PACK_DEFS.keys())

def find_godot():
    for p in os.environ.get("GODOT_BIN", "").split(":"):
        if p and os.path.isfile(p):
            return p
    candidates = [
        os.path.join(ROOT, "tools", "godot-src", "bin", "godot.linuxbsd.editor.x86_64"),
        os.path.join(ROOT, "tools", "bin", "godot"),
        shutil.which("godot") or "",
    ]
    for c in candidates:
        if c and os.path.isfile(c):
            return c
    return None

def file_sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()

def folder_hash(path):
    h = hashlib.sha256()
    # DETERMINISTIK: kumpulkan dulu SEMUA path relatif lalu urutkan —
    # os.walk() menelusuri subdir sesuai urutan filesystem (beda antar mesin/
    # checkout) yang pernah bikin hash sama-isi beda-urutan → bump versi liar
    # (world_terrain 1.0.26→1.0.27 tanpa perubahan, kick-39).
    rels = []
    for dirpath, _dirs, files in os.walk(path):
        for fn in files:
            if fn.endswith(".import"):
                continue  # dihasilkan ulang saat export; tidak menandai perubahan konten
            rels.append(os.path.relpath(os.path.join(dirpath, fn), path).replace(os.sep, "/"))
    for rel in sorted(rels):
        full = os.path.join(path, rel)
        h.update(rel.encode())
        h.update(b"\0")
        h.update(file_sha256(full).encode())
        h.update(b"\n")
    return h.hexdigest()

def load_db():
    if os.path.isfile(DB_PATH):
        with open(DB_PATH) as f:
            return json.load(f)
    return {"packs": {}}

def save_db(db):
    os.makedirs(SERVER_DIR, exist_ok=True)
    with open(DB_PATH, "w") as f:
        json.dump(db, f, indent=1, ensure_ascii=False)

def bump_version(v):
    parts = [int(x) for x in v.split(".")]
    parts[-1] += 1
    return ".".join(str(x) for x in parts)

def gen_export_presets(pack_infos):
    """Tulis export_presets.cfg lengkap (semua key wajib preset Godot 4.5).
    preset.0 = Android Launcher APK; sisanya 1 preset .pck per pack."""
    out = []
    launcher_opts = {
        "gradle_build/gradle_build_directory": '""',
        "gradle_build/compress_native_libraries": "false",
        "gradle_build/export_format": "0",
        "gradle_build/min_sdk": '""',
        "gradle_build/target_sdk": '""',
    }
    launcher = [
        '[preset.0]',
        'name="Android Launcher"',
        'platform="Android"',
        'runnable=true',
        'dedicated_server=false',
        'custom_features="mobile"',
        'export_filter="resources"',
        'include_filter="launcher/*,project.godot"',
        'export_files=PackedStringArray()',
        'exclude_filter=""',
        'export_path="exports/android/ASekai.apk"',
        'patch_list=PackedStringArray()',
        'seed=0',
        'encrypt_pck=false',
        'encrypt_directory=false',
        'encryption_include_filters=""',
        'encryption_exclude_filters=""',
        'seed=0',
        'script_export_mode=2',
        '[preset.0.options]',
        'custom_template/debug=""',
        'custom_template/release=""',
        'custom_template/use_custom_build=false',
        'icon="res://launcher/icon.png"',
        'app_category=2',
        'package_name_config/unique_name="dev.pulautoon.launcher"',
        'package_name_config/name="A-Sekai"',
        'package_name_config/signed=true',
        'package_name_config/app_category=2',
        'package_name_config/retain_data_on_uninstall=false',
        'package_name_config/exclude_from_recents=false',
        'launcher_icons/main_192x192="res://launcher/icon.png"',
        'launcher_icons/adaptive_foreground_432x432="res://launcher/icon.png"',
        'launcher_icons/adaptive_background_432x432="res://launcher/icon.png"',
        'launcher_icons/adaptive_monochrome_432x432="res://launcher/icon.png"',
        'version/code=1',
        'version/name="0.1.0"',
        'architectures/armeabi-v7a=false',
        'architectures/arm64-v8a=true',
        'architectures/x86=false',
        'architectures/x86_64=false',
        'permissions/internet=true',
        'permissions/access_network_state=false',
        'permissions/vibrate=false',
        'screen/immersive_mode=true',
        'screen/support_small=true',
        'screen/support_normal=true',
        'screen/support_large=true',
        'screen/support_xlarge=true',
        'screen/orientation=0',
        'keystore/debug=""',
        'keystore/debug_user=""',
        'keystore/debug_password=""',
        'keystore/release=""',
        'keystore/release_user=""',
        'keystore/release_password=""',
        'apk_expansion/enable=false',
        'apk_expansion/SALT=""',
        'apk_expansion/public_key=""',
        'xr_features/xr_mode=0',
        'xr_features/hand_tracking=0',
        'xr_features/hand_tracking_frequency=0',
        'xr_features/passthrough=0',
        'xr_features/depth_sensing=0',
        'xr_features/boundary_passthrough=false',
    ]
    out += launcher
    idx = 1
    for pid in PACK_ORDER:
        info = pack_infos[pid]
        out += [
            f'[preset.{idx}]',
            f'name="Pack {pid}"',
            'platform="Android"',
            'runnable=false',
            'dedicated_server=false',
            'export_filter="resources"',
            f'include_filter="packs/{pid}/*"',
            'export_files=PackedStringArray()',
            'exclude_filter=""',
            f'export_path="server/packs/{pid}-{info["version"]}.pck"',
            'patch_list=PackedStringArray()',
            'encrypt_pck=false',
            'encrypt_directory=false',
            'encryption_include_filters=""',
            'encryption_exclude_filters=""',
            'seed=0',
            'script_export_mode=2',
            f'[preset.{idx}.options]',
            'randomize_export_signature=false',
        ]
        idx += 1
    # preset APK menyeluruh (all-in-one): embed SEMUA packs/* ke dalam APK.
    # Dijalankan launcher via fallback res://packs/<id> (tanpa server konten);
    # update delta berikutnya masih menimpa konten via pck berversi terunduh.
    aio = [l for l in launcher]
    for i, l in enumerate(aio):
        if l.startswith('name="'):
            aio[i] = 'name="Android AIO"'
        elif l.startswith('include_filter='):
            aio[i] = 'include_filter="launcher/*,project.godot,packs/*"'
        elif l.startswith('export_path='):
            aio[i] = 'export_path="exports/android/ASekai.apk"'
        elif l.startswith('version/code='):
            aio[i] = 'version/code=2'
    for i, l in enumerate(aio):
        if l == '[preset.0]':
            aio[i] = f'[preset.{idx}]'
        elif l == '[preset.0.options]':
            aio[i] = f'[preset.{idx}.options]'
    out += aio
    with open(os.path.join(PROJECT, "export_presets.cfg"), "w") as f:
        f.write("\n".join(out) + "\n")

def adopt_icon_if_present():
    """Bila ada file.jpg di root repo (ditaruh pengguna), jadikan launcher/icon.png lalu hapus."""
    src = os.path.join(ROOT, "file.jpg")
    dst = os.path.join(PROJECT, "launcher", "icon.png")
    if not os.path.exists(src):
        return
    try:
        from PIL import Image
        im = Image.open(src).convert("RGBA").resize((512, 512))
        im.save(dst)
        os.remove(src)
        print(f"[ikon] {src} -> {dst} lalu dihapus")
    except Exception as e:  # tanpa PIL: salin mentah saja (Godot bisa baca jpg)
        import shutil
        shutil.copyfile(src, os.path.join(PROJECT, "launcher", "icon.png"))
        os.remove(src)
        print("[ikon] disalin mentah (tanpa PIL)")

def main():
    adopt_icon_if_present()
    force = "--force" in sys.argv
    skip_export = "--skip-export" in sys.argv
    godot = None
    if "--godot" in sys.argv:
        i = sys.argv.index("--godot")
        godot = sys.argv[i + 1]
    if not godot:
        godot = find_godot()
    os.makedirs(SERVER_PACKS, exist_ok=True)
    db = load_db()
    packs_db = db.setdefault("packs", {})
    pack_infos = {}
    changed = []
    for pid in PACK_ORDER:
        src = os.path.join(PACKS_DIR, pid)
        if not os.path.isdir(src):
            print(f"[skip] {pid}: folder tidak ada")
            pack_infos[pid] = {"version": "0.0.0", "size": 0, "sha256": "", "exists": False}
            continue
        h = folder_hash(src)
        entry = packs_db.get(pid, {})
        if force or entry.get("content_hash") != h:
            version = bump_version(entry.get("version", "1.0.0"))
            print(f"[change] {pid}: konten berubah -> v{version}")
            entry = {"content_hash": h, "version": version}
            changed.append(pid)
        else:
            entry = {"content_hash": h, "version": entry.get("version", "1.0.0")}
        packs_db[pid] = entry
        pack_infos[pid] = {
            "version": entry["version"],
            "size": 0,
            "sha256": "",
            "exists": True,
        }
    # generate presets dengan versi terkini agar export_path benar
    gen_export_presets(pack_infos)
    # export pack yang berubah (atau yang belum punya file .pck di server)
    export_log = []
    for pid in PACK_ORDER:
        info = pack_infos[pid]
        if not info["exists"]:
            continue
        pck_name = f"{pid}-{info['version']}.pck"
        pck_path = os.path.join(SERVER_PACKS, pck_name)
        need_export = pid in changed or not os.path.isfile(pck_path)
        if need_export and not skip_export:
            if not godot:
                print(f"[error] Godot tidak ditemukan; jalankan dengan --godot PATH")
                sys.exit(2)
            t0 = time.time()
            env = dict(os.environ)
            env.setdefault("XDG_DATA_HOME", os.path.join(ROOT, "..", ".xdg") if False else os.path.expanduser("~/.xdg"))
            cmd = [godot, "--headless", "--path", PROJECT, "--export-pack", f"Pack {pid}", pck_path]
            print(f"[export] {pid} -> {pck_name}")
            proc = subprocess.run(cmd, capture_output=True, text=True, timeout=900, env=env)
            lines = [l for l in proc.stdout.splitlines() if "error" in l.lower() or "warn" in l.lower()]
            lines += [l for l in proc.stderr.splitlines() if l.strip()]
            export_log.append({
                "pack": pid, "version": info["version"], "returncode": proc.returncode,
                "duration_s": round(time.time() - t0, 1),
                "messages": lines[-25:],
            })
            if proc.returncode != 0:
                print(f"[error] export {pid} gagal (rc={proc.returncode})")
                print("\n".join(lines[-15:]))
                sys.exit(3)
        if os.path.isfile(pck_path):
            info["size"] = os.path.getsize(pck_path)
            info["sha256"] = file_sha256(pck_path)
            print(f"[ok] {pid} v{info['version']}  {info['size']} B  sha256 {info['sha256'][:12]}…")
    # bersihkan pck lama di server
    keep = {f"{pid}-{pack_infos[pid]['version']}.pck" for pid in PACK_ORDER if pack_infos[pid].get("exists")}
    for fn in os.listdir(SERVER_PACKS):
        if fn.endswith(".pck") and fn not in keep:
            os.remove(os.path.join(SERVER_PACKS, fn))
            print(f"[clean] hapus {fn}")
    # manifest — pembandingan semver (max() polos salah urut: "1.0.10" < "1.0.7")
    def _vkey(v: str):
        return tuple(int(x) for x in str(v).split(".") if str(x).isdigit())
    game_version = max((info["version"] for info in pack_infos.values() if info["exists"]),
                       key=_vkey, default="1.0.0")
    manifest = {
        "game_version": game_version,
        "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "pack_order": [pid for pid in PACK_ORDER if pack_infos[pid]["exists"]],
        "packs": {
            pid: {
                "version": pack_infos[pid]["version"],
                "size": pack_infos[pid]["size"],
                "sha256": pack_infos[pid]["sha256"],
                "url": f"packs/{pid}-{pack_infos[pid]['version']}.pck",
                "deps": PACK_DEFS[pid]["deps"],
            }
            for pid in PACK_ORDER if pack_infos[pid]["exists"]
        },
    }
    with open(os.path.join(SERVER_DIR, "manifest.json"), "w") as f:
        json.dump(manifest, f, indent=1, ensure_ascii=False)
    # SNAPSHOT bundel: ikut di-export ke APK AIO lewat include_filter "packs/*"
    # supaya launcher kenal konten bawaan saat offline-total (tanpa server).
    with open(os.path.join(PROJECT, "packs", "manifest.json"), "w") as f:
        json.dump(manifest, f, indent=1, ensure_ascii=False)
    with open(os.path.join(SERVER_DIR, "build_log.json"), "w") as f:
        json.dump(export_log, f, indent=1, ensure_ascii=False)
    save_db(db)
    print(f"[manifest] {SERVER_DIR}/manifest.json  game v{game_version}")
    if exported_any(changed):
        print(f"[changed] {', '.join(changed)}")
    else:
        print("[changed] tidak ada pack berubah — tdk ada unduhan ulang nanti (delta OK)")

def exported_any(changed):
    return len(changed) > 0

if __name__ == "__main__":
    main()
