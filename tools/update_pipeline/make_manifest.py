#!/usr/bin/env python3
"""Generate version.json untuk sistem update in-game.

Manifest memberi tahu aplikasi paket mana yang perlu diunduh:
- `assets_v1.pck`  : paket dasar (nama STABIL agar pemain lama tidak
                     mengunduh ulang; hanya di-replace saat re-base).
- `patch_X.pck`    : patch kumulatif terhadap baseline; nama mengikuti
                     versionCode sehingga setiap rilis punya nama unik.

Client memverifikasi SHA256 tiap paket -> update hanya mengunduh paket
yang kontennya benar-benar berubah.
"""
import argparse
import hashlib
import json
import os
import sys


def sha256_of(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--build-dir", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--release-base-url", required=True,
                    help="Base URL folder release, mis. https://github.com/<org>/<repo>/releases/download/<tag>")
    ap.add_argument("--version", required=True, help="Versi game, mis. 1.0.12")
    ap.add_argument("--version-code", required=True)
    ap.add_argument("--base-name", default="assets_v1.pck")
    ap.add_argument("--patch-name", required=True)
    ap.add_argument("--apk-name", default="InfiniteRunner-Lite.apk")
    ap.add_argument("--changed-files", default="",
                    help="File teks berisi daftar path yang berubah (satu per baris). "
                         "Dipakai untuk mengisi flag requires_restart / needs_new_apk.")
    ap.add_argument("--changed-files-skip-base", default="",
                    help="File teks daftar path berubah SEJAK RILIS SUKSES TERAKHIR. "
                         "Keputusan skip base pack 50MB diambil dari daftar ini "
                         "(bukan diff kumulatif patch-baseline yang selalu berubah).")
    ap.add_argument("--prev-manifest", default="",
                    help="version.json rilis SEBELUMNYA: saat skip-base, entri base "
                         "disalin utuh (URL+sha+size lama) agar client lama loncat "
                         "tanpa unduh ulang, tapi INSTALL ULANG tetap bisa fetch.")
    ap.add_argument("--base-asset-info", default="",
                    help="JSON {size,digest} aset assets_v1.pck di release (fallback "
                         "bila prev-manifest tidak punya entri base).")
    args = ap.parse_args()

    def pack_entry(name: str, order: int, is_patch: bool) -> dict:
        path = os.path.join(args.build_dir, name)
        if not os.path.exists(path):
            raise SystemExit(f"File paket tidak ditemukan: {path}")
        return {
            "name": name,
            "url": f"{args.release_base_url}/{name}",
            "size": os.path.getsize(path),
            "sha256": sha256_of(path),
            "is_patch": is_patch,
            "order": order,
        }

    changed: list[str] = []
    if args.changed_files and os.path.exists(args.changed_files):
        with open(args.changed_files, encoding="utf-8") as f:
            changed = [line.strip() for line in f if line.strip()]

    # Hemat unduhan ala update game mobile: bila diff SEJAK RILIS TERAKHIR
    # hanya berisi kode (script C# yang dikompilasi ke APK / berkas CI),
    # konten paket dasar identik secara fungsi -> JANGAN masukkan
    # assets_v1.pck ke manifest. Client memakai base embedded/lokal; patch
    # kumulatif kecil ditumpuk di atasnya (baseline patch boleh tertinggal,
    # karena patch lama->baru tetap penuh).
    CODE_ONLY_PREFIXES = ("_script/", ".github/", "tools/", "docs/")
    CODE_ONLY_ROOT = ("README", "LICENSE", ".gitignore", ".gitattributes")

    def is_code_only_change(c: str) -> bool:
        if any(c.startswith(p) for p in CODE_ONLY_PREFIXES):
            return True
        if "/" not in c and any(c.startswith(r) for r in CODE_ONLY_ROOT):
            return True
        return False

    changed_since_last: list[str] = []
    if args.changed_files_skip_base and os.path.exists(args.changed_files_skip_base):
        with open(args.changed_files_skip_base, encoding="utf-8") as f:
            changed_since_last = [line.strip() for line in f if line.strip()]

    base_content_changed = (not changed_since_last) or any(
        not is_code_only_change(c) for c in changed_since_last)

    # Semantik "update data game" ala Mobile Legends:
    # - requires_restart: file yang hanya dibaca saat boot berubah
    #   (project.godot) -> client sarankan restart otomatis setelah unduh.
    # - needs_new_apk: kode C# berubah. Sumber .cs TIDAK dieksekusi dari
    #   .pck (assembly ter-kompilasi ke dalam APK), jadi pemain dipersilakan
    #   mengunduh APK baru — game tetap jalan dengan kode lama.
    def any_changed(pred) -> bool:
        return any(pred(c) for c in changed)

    requires_restart = any_changed(lambda c: c == "project.godot" or c == "export_presets.cfg")
    needs_new_apk = any_changed(lambda c: c.startswith("_script/") or c.endswith(".csproj") or c.endswith(".sln"))

    def reused_base_entry() -> dict | None:
        """Entri base yang menunjuk file LAMA di release (unduhan lama tetap valid).
        Sumber 1: prev version.json. Sumber 2: info digest aset dari gh api."""
        if args.prev_manifest and os.path.exists(args.prev_manifest):
            try:
                with open(args.prev_manifest, encoding="utf-8") as f:
                    prev = json.load(f)
                for p in prev.get("packs", []):
                    if p.get("name") == args.base_name and p.get("url") and p.get("sha256"):
                        e = dict(p)
                        e["order"] = 1
                        e["is_patch"] = False
                        print("[make_manifest] Entri base dipakai ulang dari prev version.json.")
                        return e
            except Exception as ex:
                print(f"[make_manifest] prev manifest tak terbaca: {ex}")
        if args.base_asset_info and os.path.exists(args.base_asset_info):
            try:
                with open(args.base_asset_info, encoding="utf-8") as f:
                    info = json.load(f)
                digest = str(info.get("digest", ""))
                sha = digest.split(":", 1)[1] if ":" in digest else digest
                size = int(info.get("size", 0))
                if sha and size > 0:
                    print("[make_manifest] Entri base dipakai ulang dari digest aset release.")
                    return {
                        "name": args.base_name,
                        "url": f"{args.release_base_url}/{args.base_name}",
                        "size": size,
                        "sha256": sha,
                        "is_patch": False,
                        "order": 1,
                    }
            except Exception as ex:
                print(f"[make_manifest] info aset base tak terbaca: {ex}")
        return None

    packs = []
    if base_content_changed:
        packs.append(pack_entry(args.base_name, order=1, is_patch=False))
    else:
        reused = reused_base_entry()
        if reused is not None:
            # PENTING: base TETAP dicantumkan (menunjuk file lama yang identik
            # secara fungsi) supaya install ulang tetap mengunduh data dasar;
            # client yang sudah punya file itu loncat berkat sha yang sama.
            packs.append(reused)
            with open(os.path.join(args.build_dir, "skip_base_upload.flag"), "w") as f:
                f.write("1\n")
            print("[make_manifest] Hanya kode berubah -> upload base dilewati, "
                  "manifest menunjuk file base lama (hemat ~50MB).")
        else:
            # Tidak ada referensi file lama -> sertakan base baru + upload
            # (lebih aman daripada membiarkan install ulang kehabisan data).
            print("[make_manifest] Referensi base lama tidak ada -> base baru disertakan.")
            packs.append(pack_entry(args.base_name, order=1, is_patch=False))
    packs.append(pack_entry(args.patch_name, order=2, is_patch=True))

    apk_path = os.path.join(args.build_dir, args.apk_name)
    apk_sha = sha256_of(apk_path) if os.path.exists(apk_path) else ""
    apk_size = os.path.getsize(apk_path) if os.path.exists(apk_path) else 0

    manifest = {
        "version": args.version,
        "version_code": int(args.version_code),
        "apk_url": f"{args.release_base_url}/{args.apk_name}",
        "apk_sha256": apk_sha,
        "apk_size": apk_size,
        "requires_restart": requires_restart,
        "needs_new_apk": needs_new_apk,
        "changed_files_count": len(changed),
        "packs": packs,
    }

    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2)

    print(json.dumps(manifest, indent=2))
    print(f"[make_manifest] version.json ditulis ke {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
