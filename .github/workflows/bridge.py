#!/usr/bin/env python3
"""Bridge driver: ambil biner di runner, push ke arena/bridge-assets via REST API,
laporkan tiap fase lewat file .github/bridge-log.md di branch sesi."""
import base64, glob, hashlib, json, os, subprocess, sys, time, urllib.request, urllib.parse

TOK = os.environ.get("PUSHER_TOKEN") or os.environ["GH_TOKEN"]
REPO = os.environ["GITHUB_REPOSITORY"]
SESSION_BRANCH = os.environ["SESSION_BRANCH"]
TARGET_BRANCH = "arena/bridge-assets"
API = "https://api.github.com/repos/%s" % REPO
LINES = []

def log(*a):
    line = " ".join(str(x) for x in a)
    print(line, flush=True)
    LINES.append(line)

def api(method, url, data=None, is_git=False):
    body = json.dumps(data).encode() if data is not None else None
    req = urllib.request.Request(url if not is_git else url, data=body, method=method, headers={
        "Authorization": "Bearer " + TOK, "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28", "Content-Type": "application/json"})
    with urllib.request.urlopen(req) as r:
        return json.loads(r.read())

def upload_log():
    txt = "# bridge log\n\n```\n" + "\n".join(LINES) + "\n```\n"
    path = ".github/bridge-log.md"
    sha = None
    try:
        cur = api("GET", "%s/contents/%s?ref=%s" % (API, urllib.parse.quote(path), urllib.parse.quote(SESSION_BRANCH, safe="")))
        sha = cur["sha"]
    except Exception:
        sha = None
    payload = {"message": "ci: bridge log", "content": base64.b64encode(txt.encode()).decode(), "branch": SESSION_BRANCH}
    if sha:
        payload["sha"] = sha
    api("PUT", "%s/contents/%s" % (API, urllib.parse.quote(path)), payload)

def phase(name):
    log("\n=== FASE:", name, time.strftime("%H:%M:%S"), "===")

def sh(args, timeout=900):
    p = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
    return p.returncode, (p.stdout or "")[-500:], (p.stderr or "")[-500:]

def dl(url, out):
    for i in range(3):
        rc, so, se = sh(["curl", "-sL", "--retry", "3", "-o", out, "-w", "%{http_code} %{size_download}", url], timeout=1800)
        if rc == 0 and os.path.exists(out) and os.path.getsize(out) > 1000:
            log("unduh OK:", so)
            return True
        log("unduh gagal(%d):" % rc, se[-200:])
    return False

def main():
    gv = "4.5.2"
    os.makedirs("/tmp/bridge", exist_ok=True)
    phase("probe-channel")
    try:
        upload_log()
        log("CHANNEL_OK contents-api")
    except Exception as e:
        print("CHANNEL_FAIL", repr(e))
        return 2
    phase("godot-editor")
    os.makedirs("/tmp/bridge/godot", exist_ok=True)
    ok = dl("https://downloads.tuxfamily.org/godotengine/%s/Godot_v%s-stable_linux.x86_64.zip" % (gv, gv), "/tmp/bridge/godot/Godot_v%s_linux.x86_64.zip" % gv)
    if not ok:
        ok = dl("https://github.com/godotengine/godot/releases/download/%s-stable/Godot_v%s-stable_linux.x86_64.zip" % (gv, gv), "/tmp/bridge/godot/Godot_v%s_linux.x86_64.zip" % gv)
    log("editor:", "OK" if ok else "GAGAL")
    upload_log()
    phase("templates-android")
    ok2 = dl("https://downloads.tuxfamily.org/godotengine/%s/Godot_v%s-stable_export_templates.tpz" % (gv, gv), "/tmp/tpz.tpz")
    if not ok2:
        ok2 = dl("https://github.com/godotengine/godot/releases/download/%s-stable/Godot_v%s-stable_export_templates.tpz" % (gv, gv), "/tmp/tpz.tpz")
    log("tpz:", "OK" if ok2 else "GAGAL")
    if ok2:
        os.makedirs("/tmp/bridge/templates/4.5.2.stable", exist_ok=True)
        rc, so, se = sh(["unzip", "-o", "-q", "-j", "/tmp/tpz.tpz",
                         "templates/android_debug.apk", "templates/android_release.apk", "templates/version.txt",
                         "-d", "/tmp/bridge/templates/4.5.2.stable"])
        log("unzip tpz rc=%d %s" % (rc, se[-200:]))
        os.remove("/tmp/tpz.tpz")
    upload_log()
    phase("android-sdk")
    ah = os.environ.get("ANDROID_HOME", "")
    log("ANDROID_HOME=", ah)
    bts = sorted(glob.glob(ah + "/build-tools/*"))
    pls = sorted(glob.glob(ah + "/platforms/android-*"))
    log("build-tools:", bts[-1] if bts else "NONE")
    log("platform:", pls[-1] if pls else "NONE")
    if bts and pls:
        os.makedirs("/tmp/sdkpack/android-sdk/build-tools", exist_ok=True)
        os.makedirs("/tmp/sdkpack/android-sdk/platforms", exist_ok=True)
        sh(["cp", "-r", bts[-1], "/tmp/sdkpack/android-sdk/build-tools/"])
        sh(["cp", "-r", pls[-1], "/tmp/sdkpack/android-sdk/platforms/"])
        sh(["cp", "-r", ah + "/platform-tools", "/tmp/sdkpack/android-sdk/"])
        rc, so, se = sh(["tar", "-C", "/tmp/sdkpack", "-czf", "/tmp/bridge/android-sdk.tgz", "android-sdk"], timeout=600)
        log("sdk tgz rc=%d size=%d" % (rc, os.path.getsize("/tmp/bridge/android-sdk.tgz") if os.path.exists("/tmp/bridge/android-sdk.tgz") else -1))
    upload_log()
    phase("x-debs")
    pkgs = ("xvfb x11-xkb-utils xkb-data libgl1-mesa-dri libglx-mesa0 libegl-mesa0 libglapi-mesa mesa-vulkan-drivers libvulkan1 "
            "libglvnd0 libglx0 libgl1 libegl1 libdrm2 libx11-6 libx11-xcb1 libxcb1 libxcb-dri3-0 libxcb-present0 libxcb-randr0 "
            "libxcb-shm0 libxcb-sync1 libxcb-xfixes0 libxcb-glx0 libxau6 libxdmcp6 libbsd0 libmd0 libxshmfence1 libxxf86vm1 "
            "libxfixes3 libxdamage1 libxext6 libexpat1 libllvm15 libelf1 libsensors5 libxfont2 libfontenc1 libpixman-1-0 "
            "libxkbfile1 fonts-dejavu-core libxmuu1 xauth").split()
    sh(["sudo", "apt-get", "update", "-qq"], timeout=300)
    rc, so, se = sh(["bash", "-c", "cd /tmp/bridge/debs 2>/dev/null || mkdir -p /tmp/bridge/debs && cd /tmp/bridge/debs && apt-get download $(apt-cache depends --recurse --no-recommends --no-suggests --no-conflicts --no-breaks --no-replaces --no-enhances %s | grep -oP '^[a-zA-Z0-9][\\w.+-]+' | sort -u)" % " ".join(pkgs)], timeout=600)
    debs = glob.glob("/tmp/bridge/debs/*.deb")
    log("debs rc=%d count=%d" % (rc, len(debs)))
    upload_log()
    phase("fonts")
    os.makedirs("/tmp/bridge/fonts", exist_ok=True)
    for src, dst in [("ofl/baloo2/Baloo2%5Bwght%5D.ttf", "Baloo2.ttf"), ("ofl/quicksand/Quicksand%5Bwght%5D.ttf", "Quicksand.ttf")]:
        rc, so, se = sh(["bash", "-c", "gh api 'repos/google/fonts/contents/%s' --jq '.content' | base64 -d > /tmp/bridge/fonts/%s" % (src, dst)])
        log("font", dst, "rc=%d" % rc)
    phase("manifest")
    for f in sorted(glob.glob("/tmp/bridge/**", recursive=True)):
        if os.path.isfile(f):
            h = hashlib.sha256(open(f, "rb").read()).hexdigest()
            log("sha256 %s %d %s" % (h, os.path.getsize(f), os.path.relpath(f, "/tmp/bridge")))
    upload_log()
    phase("rest-push")
    gitapi = "https://api.github.com/repos/%s/git" % REPO
    parent = []
    try:
        refs = api("GET", gitapi + "/refs/heads/" + urllib.parse.quote(TARGET_BRANCH, safe=""))
        parent = [refs["object"]["sha"]]
        log("branch ada, parent:", parent[0][:8])
    except Exception:
        log("branch baru")
    files = sorted([f for f in glob.glob("/tmp/bridge/**", recursive=True) if os.path.isfile(f)])
    tree = []
    CH = 55 * 1024 * 1024
    for f in files:
        rel = os.path.relpath(f, "/tmp/bridge").replace(os.sep, "/")
        data = open(f, "rb").read()
        parts = [data] if len(data) <= CH else [data[i:i+CH] for i in range(0, len(data), CH)]
        for idx, part in enumerate(parts):
            name = rel if len(parts) == 1 else (rel + ".part%02d" % idx)
            b = api("POST", gitapi + "/blobs", {"content": base64.b64encode(part).decode(), "encoding": "base64"})
            tree.append({"path": name, "mode": "100644", "type": "blob", "sha": b["sha"]})
            log("blob ok:", name, len(part))
    t = api("POST", gitapi + "/trees", {"tree": tree})
    c = api("POST", gitapi + "/commits", {"message": "bridge payload", "tree": t["sha"], "parents": parent})
    log("commit:", c["sha"])
    ref_path = gitapi + "/refs/heads/" + urllib.parse.quote(TARGET_BRANCH, safe="")
    try:
        api("PATCH", ref_path, {"sha": c["sha"], "force": True})
    except Exception:
        api("POST", gitapi + "/refs", {"ref": "refs/heads/" + TARGET_BRANCH, "sha": c["sha"]})
    log("PUSHED", TARGET_BRANCH)
    phase("verify")
    time.sleep(10)
    br = api("GET", API + "/branches/" + urllib.parse.quote(TARGET_BRANCH, safe=""))
    log("VERIFY_OK", br.get("name"))
    upload_log()
    log("SELESAI")
    return 0

if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as e:
        import traceback
        log("EXCEPTION:", repr(e))
        log(traceback.format_exc()[-1500:])
        try:
            upload_log()
        except Exception as e2:
            print("LOGUPLOAD_FAIL", repr(e2))
        sys.exit(3)
