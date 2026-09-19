#!/bin/sh
## export_android.sh — export launcher sebagai APK debug via Godot CLI.
## Prasyarat (lihat README, bagian "Build APK"):
##  1) Binari editor Godot (GODOT_BIN) — lokal build sumber / editor resmi.
##  2) Export templates 4.5.2.stable terpasang (~/.local/share/godot/export_templates)
##     → jalankan tools/fetch_export_templates.sh bila belum ada.
##  3) Android SDK layout minimal (tools/android-sdk/): build-tools/34.0.0
##     dengan aapt2 + apksigner, platform-tools/adb; keystore debug.
##  4) Editor settings (export android sdk path) — ditulis otomatis skrip ini.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-/home/user/tools/godot-src/bin/godot.linuxbsd.editor.x86_64}"
SDK="${ANDROID_SDK_ROOT:-/home/user/tools/android-sdk}"
JRE="${JAVA_HOME:-/home/user/tools/jdk/jdk4py/java-runtime}"
KS="$ROOT/exports/android/debug.keystore"

mkdir -p "$ROOT/exports/android"

# tulis editor settings untuk ANDROID SDK/JAVA/keystore (kedua lokasi XDG)
for D in "$HOME/.local/share/godot" "$HOME/.config/godot"; do
    mkdir -p "$D"
    cat > "$D/editor_settings-4.5.tres" <<EOF
[resource]
export/android/android_sdk_path = "$SDK"
export/android/java_sdk_path = "$JRE"
export/android/debug_keystore = "$KS"
export/android/debug_keystore_user = "androiddebugkey"
export/android/debug_keystore_pass = "android"
EOF
done

if [ ! -f "$HOME/.local/share/godot/export_templates/4.5.2.stable/android_debug.apk" ]; then
    echo "[warn] export templates belum terpasang; mencoba mengunduh ..."
    sh "$ROOT/tools/fetch_export_templates.sh" "$SDK" || true
fi

echo "[export] preset 'Android Launcher' -> exports/android/PulauToon-debug.apk"
"$GODOT_BIN" --headless --path "$ROOT/project" --export-debug "Android Launcher" \
    "$ROOT/exports/android/PulauToon-debug.apk" 2>&1 | tee "$ROOT/exports/android/export.log"
echo "[export] selesai (lihat exports/android/export.log)"
