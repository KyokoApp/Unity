#!/usr/bin/env python3
"""
anime.py — alat bantu AnimeStudio untuk repo ini (tanpa dependensi, stdlib saja).

Fungsi:
  kick    : jalankan workflow AnimeStudio lewat API (tanpa buka browser)
  status  : lihat riwayat jalan + kesimpulannya
  pull    : unduh hasil ekstraksi (artifact atau release) lalu buka zip-nya
  games   : tampilkan daftar kode game yang dikenal workflow ini

Semua perintah butuh token GitHub di environment:

    export GITHUB_TOKEN=ghp_xxx          # Linux/macOS/Termux
    set GITHUB_TOKEN=ghp_xxx             # Windows CMD
    $env:GITHUB_TOKEN="ghp_xxx"          # PowerShell

Token cukup classik dengan scope `repo` + `workflow` (kalau repo private),
atau fine-grained: Contents read/write + Actions read/write.

Contoh:
    python3 animestudio/tools/anime.py status
    python3 animestudio/tools/anime.py kick --game GI --url "https://github.com/.../releases/download/v1/bundle.zip" --types Texture2D,TextAsset
    python3 animestudio/tools/anime.py pull --latest --out hasil
"""

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request
import zipfile

API = "https://api.github.com"
DEFAULT_REPO = os.environ.get("ANIME_REPO", "KyokoApp/Unity")
WORKFLOW_FILE = "animestudio.yml"

KODE_GAME = """Normal GI GI_Pack GI_CB1 GI_CB2 GI_CB3 GI_CB3Pre BH3 BH3Pre BH3PrePre
SR SR_CB2 ZZZ ZZZ_CB1 ZZZ_CB2 HNA_CB1 HYG_CB1 TOT Naraka EnsembleStars OPFP FakeHeader
FantasyOfWind ShiningNikki HelixWaltz2 NetEase AnchorPanic DreamscapeAlbireo ImaginaryFest
AliceGearAegis ProjectSekai CodenameJump GirlsFrontline Reverse1999 ArknightsEndfield
ArknightsEndfieldCB3 ArknightsEndfieldCB2 ArknightsEndfieldCB1 Arknights JJKPhantomParade
MuvLuvDimensions PartyAnimals LoveAndDeepspace SchoolGirlStrikers ExAstris PerpetualNovelty
RewindingCadence AzurPromiliaCBT2 AFKJourney PGR_GLB_KR PGR_CN_JP_TW PGR_CN_JP_TW_OLD
Archeland_KalpaOfUniverse Archeland_1114 NeuralCloud NeuralCloudCN HiganEruthyll WhiteCord
Mecharashi CastlevaniaMoonNightFantasy HYSXZY DoulaContinent BlessGlobal Starside
ResonanceSoltice OblivionOverride Dawnlands BB DynastyLegends2 EvernightCN XintianlongBabu
FrostpunkBeyondTheIce CatFantasy""".split()


def token():
    tok = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
    if not tok:
        sys.exit(
            "Token GitHub belum diset.\n"
            "  export GITHUB_TOKEN=ghp_xxxx   (Linux/macOS/Termux)\n"
            '  set GITHUB_TOKEN=ghp_xxxx      (Windows CMD)\n'
            "Bikin di: GitHub -> Settings -> Developer settings -> Personal access tokens"
        )
    return tok.strip()


def api(path, method="GET", body=None, repo=None, raw=False, follow=True):
    """Panggil REST API GitHub. follow=False dipakai untuk unduhan yang redirect."""
    url = path if path.startswith("http") else API + path
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", "Bearer " + token())
    req.add_header("Accept", "application/vnd.github+json")
    req.add_header("X-GitHub-Api-Version", "2022-11-28")
    req.add_header("User-Agent", "animestudio-helper")
    if data is not None:
        req.add_header("Content-Type", "application/json")

    if not follow:
        opener = urllib.request.build_opener(NoRedirect())
    else:
        opener = urllib.request.build_opener()
    try:
        with opener.open(req, timeout=120) as r:
            payload = r.read()
            if raw:
                return payload
            if not payload:
                return {}
            ctype = r.headers.get("Content-Type", "")
            if "json" in ctype:
                return json.loads(payload)
            return payload
    except urllib.error.HTTPError as e:
        detail = e.read().decode("utf-8", "replace")[:400]
        if e.code == 302 and not follow:  # redirect bukan error di sini
            return {"location": e.headers.get("Location")}
        sys.exit(f"HTTP {e.code} untuk {method} {url}\n{detail}")
    except urllib.error.URLError as e:
        sys.exit(f"Gagal konek ke GitHub: {e.reason}")


class NoRedirect(urllib.request.HTTPRedirectHandler):
    """Jangan ikut redirect otomatis — supaya token GitHub tidak ikut terkirim ke host lain."""

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def rupiah_bytes(n):
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if n < 1024 or unit == "TB":
            return f"{n:.1f} {unit}" if unit != "B" else f"{int(n)} B"
        n /= 1024


# --------------------------------------------------------------------------- kick
def cmd_kick(args):
    body = {
        "ref": args.branch,
        "inputs": {
            "game": args.game,
            "bundle_url": args.url,
            "types": args.types,
            "export_type": args.export,
            "group_assets": args.group,
            "map_op": "None",
            "cli_build": args.build,
            "publish_release": args.publish,
        },
    }
    if args.unity:
        body["inputs"]["unity_version"] = args.unity

    api(f"/repos/{args.repo}/actions/workflows/{WORKFLOW_FILE}/dispatches", "POST", body)
    print(f"✅ Workflow dikirim ke {args.repo} (branch {args.branch})")
    print(f"   game={args.game} types={args.types or '(semua)'} export={args.export} publish_release={args.publish}")
    time.sleep(4)

    runs = api(f"/repos/{args.repo}/actions/workflows/{WORKFLOW_FILE}/runs?per_page=1")
    if not runs.get("workflow_runs"):
        print("   (belum ada run yang muncul, cek sebentar lagi dengan: anime.py status)")
        return 0
    run = runs["workflow_runs"][0]
    print(f"   Run #{run['run_number']} — {run['html_url']}")

    if args.watch:
        if args.no_browser:
            print(f"   Tonton log di HP/browser: {run['html_url']}")
        return cmd_watch(args, run["id"], run["run_number"])
    return 0


def cmd_watch(args, run_id, run_number):
    terakhir = ""
    while True:
        r = api(f"/repos/{args.repo}/actions/runs/{run_id}")
        st = f"{r['status']} / {r.get('conclusion') or '-'}"
        if st != terakhir:
            print(f"   [#{run_number}] {st}")
            terakhir = st
        if r["status"] == "completed":
            concl = r.get("conclusion")
            print(f"   Selesai: {concl}")
            if concl != "success":
                print("   ⚠️  Bukan sukses — buka halaman run untuk lihat log/ringkasan:")
            print(f"   Ringkasan & log: {r['html_url']}")
            if args.pull_saat_selesai:
                print()
                pull_results(args.repo, run_number=run_number, out=args.out or "hasil")
            return 0
        time.sleep(12)


# ------------------------------------------------------------------------- status
def cmd_status(args):
    data = api(
        f"/repos/{args.repo}/actions/workflows/{WORKFLOW_FILE}/runs?per_page={args.limit}"
    )
    runs = data.get("workflow_runs", [])
    if not runs:
        print("Belum ada riwayat jalan untuk workflow ini.")
        return 0
    print(f"Riwayat AnimeStudio di {args.repo}:\n")
    for r in runs:
        inputs = ""
        try:
            payload = api(f"/repos/{args.repo}/actions/runs/{r['id']}")
            # inputs tidak ada di API v3; pakai ringkasan dari nama run
        except SystemExit:
            pass
        print(f"  #{r['run_number']:<4} {r['created_at'][:16].replace('T', ' ')}  "
              f"{r['status']:<11} {r.get('conclusion') or '-':<10} {r['display_title'][:44]}")
    terbaru = runs[0]
    print(f"\nRun terbaru: {terbaru['html_url']}")
    print(f"Ambil hasilnya: python3 {os.path.basename(__file__)} pull --run {terbaru['run_number']}")
    return 0


# --------------------------------------------------------------------------- pull
def pull_results(repo, run_number=None, out="hasil", keep_zip=False):
    if run_number is None:
        runs = api(f"/repos/{repo}/actions/workflows/{WORKFLOW_FILE}/runs?per_page=1")
        if not runs.get("workflow_runs"):
            sys.exit("Belum ada run.")
        run = runs["workflow_runs"][0]
        run_number = run["run_number"]
    else:
        runs = api(f"/repos/{repo}/actions/workflows/{WORKFLOW_FILE}/runs?per_page=30")
        cocok = [r for r in runs.get("workflow_runs", []) if r["run_number"] == run_number]
        if not cocok:
            sys.exit(f"Run #{run_number} tidak ketemu (cek: anime.py status)")
        run = cocok[0]

    print(f"Run #{run_number} — status {run['status']} / {run.get('conclusion') or '-'}")
    os.makedirs(out, exist_ok=True)
    dibuat = []

    # 1) artifact (kalau ada)
    arts = api(f"/repos/{repo}/actions/runs/{run['id']}/artifacts")
    for a in arts.get("artifacts", []):
        if a["expired"]:
            print(f"  artifact {a['name']} sudah kedaluwarsa (lewat masa simpan)")
            continue
        print(f"  mengunduh artifact {a['name']} ({rupiah_bytes(a['size_in_bytes'])}) ...")
        target = os.path.join(out, f"{a['name']}.zip")
        unduh_artifact(repo, a["id"], target)
        dibuat.append(target)

    # 2) release (kalau publish_release=yes atau hasilnya besar)
    tag = f"extract-{run_number}"
    try:
        rel = api(f"/repos/{repo}/releases/tags/{tag}")
        for asset in rel.get("assets", []):
            print(f"  mengunduh release asset {asset['name']} ({rupiah_bytes(asset['size'])}) ...")
            target = os.path.join(out, asset["name"])
            unduh_asset(repo, asset["id"], target)
            dibuat.append(target)
    except SystemExit:
        pass

    if not dibuat:
        print("  Tidak ada artifact/release untuk run ini (mungkin hasilnya kosong).")
        return 1

    # buka zip-nya
    for z in list(dibuat):
        if not z.lower().endswith(".zip"):
            continue
        tujuan = os.path.join(out, os.path.basename(z)[:-4])
        try:
            with zipfile.ZipFile(z) as zf:
                zf.extractall(tujuan)
                n = len(zf.namelist())
            print(f"  ✅ {os.path.basename(z)} -> {tujuan}/ ({n} entri)")
            if not keep_zip:
                os.remove(z)
        except zipfile.BadZipFile:
            print(f"  ⚠️  {z} bukan zip valid (mungkin bagian .001 dari pecahan — buka dengan 7z/ZArchiver)")

    total = 0
    for root, _, files in os.walk(out):
        for f in files:
            total += os.path.getsize(os.path.join(root, f))
    print(f"\nSelesai. Isi {out}/ = {rupiah_bytes(total)}")
    return 0


def unduh_artifact(repo, artifact_id, target):
    """Artifact GitHub: request pertama redirect ke blob storage — token jangan ikut."""
    req = urllib.request.Request(
        f"{API}/repos/{repo}/actions/artifacts/{artifact_id}/zip"
    )
    req.add_header("Authorization", "Bearer " + token())
    req.add_header("User-Agent", "animestudio-helper")
    opener = urllib.request.build_opener(NoRedirect())
    try:
        with opener.open(req, timeout=60) as r:
            _simpan(r, target)
    except urllib.error.HTTPError as e:
        if e.code != 302:
            sys.exit(f"Gagal ambil artifact: HTTP {e.code}")
        url = e.headers.get("Location")
        req2 = urllib.request.Request(url)
        req2.add_header("User-Agent", "animestudio-helper")
        with urllib.request.urlopen(req2, timeout=600) as r2:
            _simpan(r2, target)


def unduh_asset(repo, asset_id, target):
    req = urllib.request.Request(
        f"{API}/repos/{repo}/releases/assets/{asset_id}",
        headers={"Accept": "application/octet-stream"},
    )
    req.add_header("Authorization", "Bearer " + token())
    req.add_header("User-Agent", "animestudio-helper")
    opener = urllib.request.build_opener(NoRedirect())
    try:
        with opener.open(req, timeout=600) as r:
            _simpan(r, target)
    except urllib.error.HTTPError as e:
        if e.code != 302:
            sys.exit(f"Gagal ambil asset: HTTP {e.code}")
        url = e.headers.get("Location")
        req2 = urllib.request.Request(url)
        req2.add_header("User-Agent", "animestudio-helper")
        with urllib.request.urlopen(req2, timeout=600) as r2:
            _simpan(r2, target)


def _simpan(response, target):
    with open(target, "wb") as f:
        sisa = response.headers.get("Content-Length")
        sisa = int(sisa) if sisa else None
        sudah = 0
        while True:
            chunk = response.read(1 << 20)
            if not chunk:
                break
            f.write(chunk)
            sudah += len(chunk)
            if sisa:
                print(f"\r    {rupiah_bytes(sudah)} / {rupiah_bytes(sisa)}", end="")
        if sisa:
            print()


def cmd_games(args):
    print("Kode game yang dikenal workflow AnimeStudio:\n")
    for i in range(0, len(KODE_GAME), 4):
        print("  " + "".join(f"{k:<26}" for k in KODE_GAME[i:i + 4]).rstrip())
    print("\nSelain itu ada pula puluhan game Unity CN (PGR, Neural Cloud, Mecharashi, dll).")
    return 0


# -------------------------------------------------------------------------- main
def main():
    p = argparse.ArgumentParser(
        description="Alat bantu AnimeStudio (jalan di runner Windows GitHub).",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    p.add_argument("--repo", default=DEFAULT_REPO, help=f"owner/repo (default: {DEFAULT_REPO})")
    sub = p.add_subparsers(dest="cmd", required=True)

    k = sub.add_parser("kick", help="jalankan workflow lewat API")
    k.add_argument("--game", required=True, help="kode game, mis. GI")
    k.add_argument("--url", required=True, help="link bundle (release GitHub / http / path di repo)")
    k.add_argument("--types", default="Texture2D,Sprite,TextAsset", help="jenis asset, kosong = semua")
    k.add_argument("--export", default="Convert", choices=["Convert", "Raw", "Dump", "JSON"])
    k.add_argument("--group", default="ByType", choices=["ByType", "ByContainer", "BySource", "None"])
    k.add_argument("--unity", default="", help="versi Unity, mis. 2020.3.30f1")
    k.add_argument("--build", default="net10", choices=["net10", "net9"])
    k.add_argument("--publish", default="no", choices=["no", "yes"], help="taruh hasil di Releases juga?")
    k.add_argument("--branch", default="main", help="branch tempat workflow dijalankan")
    k.add_argument("--watch", action="store_true", help="pantau sampai selesai")
    k.add_argument("--pull-saat-selesai", action="store_true", help="langsung unduh hasilnya")
    k.add_argument("--out", default="hasil", help="folder tujuan kalau --pull-saat-selesai")
    k.add_argument("--no-browser", action="store_true", help="jangan cetak link browser (hemat output)")
    k.set_defaults(func=cmd_kick)

    s = sub.add_parser("status", help="riwayat jalan")
    s.add_argument("--limit", type=int, default=5)
    s.set_defaults(func=cmd_status)

    u = sub.add_parser("pull", help="unduh hasil ekstraksi")
    u.add_argument("--run", type=int, default=None, help="nomor run (default: terbaru)")
    u.add_argument("--latest", action="store_true", help="pakai run terbaru (default)")
    u.add_argument("--out", default="hasil")
    u.add_argument("--keep-zip", action="store_true", help="jangan hapus zip setelah dibuka")
    u.set_defaults(func=lambda a: pull_results(a.repo, a.run, a.out, a.keep_zip))

    g = sub.add_parser("games", help="daftar kode game")
    g.set_defaults(func=cmd_games)

    args = p.parse_args()
    return args.func(args)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print("\ndibatalkan")
        sys.exit(130)
