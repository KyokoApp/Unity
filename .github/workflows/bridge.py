#!/usr/bin/env python3
"""Bridge v8: unduh biner di runner -> tar.zst -> pecah -> push via Contents API
(satu-satunya kanal tulis yang lolos) ke arena/bridge-assets/chunks/.
Log progres ditulis ke .github/bridge-log.md di branch sesi."""
import base64, glob, hashlib, json, os, subprocess, sys, time, urllib.request, urllib.parse

TOK = os.environ["GH_TOKEN"]
REPO = os.environ["GITHUB_REPOSITORY"]
SESSION_BRANCH = os.environ["SESSION_BRANCH"]
TARGET_BRANCH = "arena/bridge-assets"
CHUNK = 700000  # byte (base64 < 1MB limit contents API)
API = "https://api.github.com/repos/%s" % REPO
LINES = []

def log(*a):
    line = " ".join(str(x) for x in a)
    print(line, flush=True)
    LINES.append(line)

def api(method, url, data=None):
    body = json.dumps(data).encode() if data is not None else None
    req = urllib.request.Request(url, data=body, method=method, headers={
        "Authorization": "Bearer " + TOK, "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28", "Content-Type": "application/json"})
    with urllib.request.urlopen(req) as r:
        raw = r.read()
        return json.loads(raw) if raw else {}

def upload_log(extra=""):
    txt = "# bridge log\n\n```\n" + "\n".join(LINES) + "\n" + extra + "\n```\n"
    path = ".github/bridge-log.md"
    sha = None
    try:
        cur = api("GET", "%s/contents/%s?ref=%s" % (API, urllib.parse.quote(path), urllib.parse.quote(SESSION_BRANCH, safe="")))
        sha = cur["sha"]
    except Exception:
        pass
    payload = {"message": "ci: bridge log", "content": base64.b64encode(txt.encode()).decode(), "branch": SESSION_BRANCH}
    if sha:
        payload["sha"] = sha
    api("PUT", "%s/contents/%s" % (API, urllib.parse.quote(path)), payload)

def phase(name):
    log("\n=== FASE:", name, time.strftime("%H:%M:%S"), "===")

def sh(args, timeout=1800):
    p = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
    return p.returncode, (p.stdout or "")[-400:], (p.stderr or "")[-400:]

def dl(url, out):
    for i in range(3):
        rc, so, se = sh(["curl", "-sL", "--retry", "3", "-o", out, "-w", "%{http_code} %{size_download}", url])
        if rc == 0 and os.path.exists(out) and os.path.getsize(out) > 1000:
            log("unduh OK:", so)
            return True
        log("unduh gagal(%d) %s %s" % (rc, so[-150:], se[-150:]))
    return False

def gather():
    gv = "4.5.2"
    os.makedirs("/tmp/bridge/godot", exist_ok=True)
    phase("godot-editor")
    ok = dl("https://github.com/godotengine/godot/releases/download/%s-stable/Godot_v%s-stable_linux.x86_64.zip" % (gv, gv),
            "/tmp/bridge/godot/Godot_v%s_linux.x86_64.zip" % gv)
    if not ok:
        ok = dl("https://downloads.tuxfamily.org/godotengine/%s/Godot_v%s-stable_linux.x86_64.zip" % (gv, gv),
                "/tmp/bridge/godot/Godot_v%s_linux.x86_64.zip" % gv)
    log("editor:", "OK" if ok else "GAGAL")
    phase("templates-android")
    ok2 = dl("https://github.com/godotengine/godot/releases/download/%s-stable/Godot_v%s-stable_export_templates.tpz" % (gv, gv), "/tmp/tpz.tpz")
    if not ok2:
        ok2 = dl("https://downloads.tuxfamily.org/godotengine/%s/Godot_v%s-stable_export_templates.tpz" % (gv, gv), "/tmp/tpz.tpz")
    if ok2:
        os.makedirs("/tmp/bridge/templates/4.5.2.stable", exist_ok=True)
        rc, so, se = sh(["unzip", "-o", "-q", "-j", "/tmp/tpz.tpz",
                         "templates/android_debug.apk", "templates/android_release.apk", "templates/version.txt",
                         "-d", "/tmp/bridge/templates/4.5.2.stable"])
        log("unzip tpz rc=%d %s" % (rc, se[-200:]))
        os.remove("/tmp/tpz.tpz")
    log("templates:", "OK" if ok2 else "GAGAL")
    phase("android-sdk")
    ah = os.environ.get("ANDROID_HOME", "")
    bts = sorted(glob.glob(ah + "/build-tools/*"))
    pls = sorted(glob.glob(ah + "/platforms/android-*"))
    log("build-tools:", bts[-1] if bts else "NONE", "| platform:", pls[-1] if pls else "NONE")
    if bts and pls:
        os.makedirs("/tmp/sdkpack/android-sdk/build-tools", exist_ok=True)
        os.makedirs("/tmp/sdkpack/android-sdk/platforms", exist_ok=True)
        sh(["cp", "-r", bts[-1], "/tmp/sdkpack/android-sdk/build-tools/"])
        sh(["cp", "-r", pls[-1], "/tmp/sdkpack/android-sdk/platforms/"])
        sh(["cp", "-r", ah + "/platform-tools", "/tmp/sdkpack/android-sdk/"])
        rc, so, se = sh(["tar", "-C", "/tmp/sdkpack", "-czf", "/tmp/bridge/android-sdk.tgz", "android-sdk"], timeout=600)
        log("sdk tgz rc=%d size=%d" % (rc, os.path.getsize("/tmp/bridge/android-sdk.tgz")))
    phase("x-debs")
    pkgs = ("xvfb xkb-data libgl1-mesa-dri libglx-mesa0 libegl-mesa0 libglapi-mesa mesa-vulkan-drivers libvulkan1 "
            "libglvnd0 libglx0 libgl1 libegl1 libdrm2 libx11-6 libx11-xcb1 libxcb1 libxcb-dri3-0 libxcb-present0 "
            "libxcb-randr0 libxcb-shm0 libxcb-sync1 libxcb-xfixes0 libxcb-glx0 libxau6 libxdmcp6 libbsd0 libmd0 "
            "libxshmfence1 libxxf86vm1 libxfixes3 libxdamage1 libxext6 libexpat1 libllvm15 libelf1 libsensors5 "
            "libxfont2 libfontenc1 libpixman-1-0 libxkbfile1 fonts-dejavu-core").split()
    sh(["sudo", "apt-get", "update", "-qq"], timeout=300)
    os.makedirs("/tmp/bridge/debs", exist_ok=True)
    rc, so, se = sh(["bash", "-c", "cd /tmp/bridge/debs && apt-get download $(apt-cache depends --recurse --no-recommends --no-suggests --no-conflicts --no-breaks --no-replaces --no-enhances %s | grep -oP '^[a-zA-Z0-9][\\w.+-]+' | sort -u)" % " ".join(pkgs)], timeout=600)
    # buang paket sistem dasar yang tidak dibutuhkan
    DROP = ("libc6_", "dpkg_", "debconf_", "cdebconf_", "perl-base_", "tar_", "coreutils_", "libacl1_", "libattr1_",
            "libcap2_", "libcap-ng0_", "libdb5.3_", "libdebian-installer4_", "libgcrypt20_", "libgpg-error0_",
            "liblzma5_", "libpcre2-8-0_", "libselinux1_", "install-info_", "gcc-12-base_", "libaudit", "libbz2-",
            "libcrypt1_", "libpam", "libmount1_", "libsmartcols1_", "libblkid1_", "libuuid1_", "grep_", "sed_",
            "libseccomp2_", "libsystemd0_", "libudev1_", "init-system-helpers_", "base-files_", "base-passwd_",
            "libdebconfclient0_", "libsemanage", "libsepol", "bzip2_", "gzip_", "hostname_", "login_", "ncurses",
            "libncurses", "mawk_", "libsigsegv", "xxd_", "zlib1g_", "libstdc++6_", "libgcc-s1_")
    kept = 0
    for f in glob.glob("/tmp/bridge/debs/*.deb"):
        base = os.path.basename(f)
        if any(base.startswith(d) for d in DROP):
            os.remove(f)
        else:
            kept += 1
    log("debs rc=%d kept=%d" % (rc, kept))
    phase("fonts")
    os.makedirs("/tmp/bridge/fonts", exist_ok=True)
    for src, dst in [("ofl/baloo2/Baloo2%5Bwght%5D.ttf", "Baloo2.ttf"), ("ofl/quicksand/Quicksand%5Bwght%5D.ttf", "Quicksand.ttf")]:
        rc, so, se = sh(["bash", "-c", "gh api 'repos/google/fonts/contents/%s' --jq '.content' | base64 -d > /tmp/bridge/fonts/%s" % (src, dst)])
        log("font", dst, "rc=%d" % rc)

def push_chunks():
    phase("pack-payload")
    rc, so, se = sh(["tar", "-C", "/tmp/bridge", "-I", "zstd -12 -T2", "-cf", "/tmp/payload.tar.zst", "."])
    size = os.path.getsize("/tmp/payload.tar.zst")
    sha = hashlib.sha256(open("/tmp/payload.tar.zst", "rb").read()).hexdigest()
    log("payload rc=%d size=%d sha=%s" % (rc, size, sha[:16]))
    data = open("/tmp/payload.tar.zst", "rb").read()
    parts = [data[i:i+CHUNK] for i in range(0, len(data), CHUNK)]
    log("chunks:", len(parts))
    phase("contents-push")
    uploaded = skipped = failed = 0
    for i, part in enumerate(parts):
        path = "chunks/%s/p%05d" % ("main", i)
        gbs = hashlib.sha1(b"blob %d\0" % len(part) + part).hexdigest()
        remote_sha = None
        try:
            cur = api("GET", "%s/contents/%s?ref=%s" % (API, urllib.parse.quote(path), urllib.parse.quote(TARGET_BRANCH, safe="")))
            remote_sha = cur.get("sha")
        except Exception:
            remote_sha = None
        if remote_sha == gbs:
            skipped += 1
            continue
        payload = {"message": "ci: chunk p%05d" % i, "content": base64.b64encode(part).decode(),
                   "branch": TARGET_BRANCH}
        if remote_sha:
            payload["sha"] = remote_sha
        for attempt in range(3):
            try:
                api("PUT", "%s/contents/%s" % (API, urllib.parse.quote(path)), payload)
                uploaded += 1
                break
            except Exception as e:
                log("put chunk %d gagal(%d): %r" % (i, attempt, e))
                time.sleep(3)
        else:
            failed += 1
        if (i + 1) % 40 == 0:
            log("progress %d/%d (up=%d skip=%d fail=%d)" % (i + 1, len(parts), uploaded, skipped, failed))
            upload_log()
    mani = {"parts": len(parts), "size": size, "sha256": sha, "chunk": CHUNK, "format": "tar.zst"}
    path = "chunks/main/MANIFEST.json"
    sha_remote = None
    try:
        cur = api("GET", "%s/contents/%s?ref=%s" % (API, urllib.parse.quote(path), urllib.parse.quote(TARGET_BRANCH, safe="")))
        sha_remote = cur.get("sha")
    except Exception:
        pass
    payload = {"message": "ci: manifest", "content": base64.b64encode(json.dumps(mani).encode()).decode(),
               "branch": TARGET_BRANCH}
    if sha_remote:
        payload["sha"] = sha_remote
    api("PUT", "%s/contents/%s" % (API, urllib.parse.quote(path)), payload)
    log("SELESAI push: up=%d skip=%d fail=%d" % (uploaded, skipped, failed))
    return failed == 0

def main():
    phase("probe-channel")
    upload_log()
    log("CHANNEL_OK")
    gather()
    upload_log()
    ok = push_chunks()
    phase("verify")
    time.sleep(2)
    br = api("GET", API + "/branches/" + urllib.parse.quote(TARGET_BRANCH, safe=""))
    log("VERIFY_OK", br.get("name"), br["commit"]["sha"][:8])
    upload_log()
    log("SELESAI-SEMUA")
    return 0 if ok else 4

if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as e:
        import traceback
        log("EXCEPTION:", repr(e))
        log(traceback.format_exc()[-1200:])
        try:
            upload_log()
        except Exception as e2:
            print("LOGUPLOAD_FAIL", repr(e2))
        sys.exit(3)
