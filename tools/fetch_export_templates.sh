#!/bin/sh
# Unduh export templates Godot 4.5.2 (untuk export Android CLI).
# Mencoba beberapa mirror; cukup satu yang berhasil.
set -e
VER=4.5.2
DEST="$HOME/.local/share/godot/export_templates/${VER}.stable"
mkdir -p "$DEST"
URLS="
https://github.com/godotengine/godot/releases/download/4.5.2-stable/Godot_v4.5.2-stable_export_templates.tpz
https://downloads.tuxfamily.org/godotengine/4.5.2/Godot_v4.5.2-stable_export_templates.tpz
"
TPZ=/tmp/godot_templates.tpz
OK=0
for U in $URLS; do
    echo "[fetch] $U"
    if curl -sL --fail --max-time 1800 -o "$TPZ" "$U"; then
        echo "[fetch] sukses: $U"
        OK=1
        break
    fi
    echo "[fetch] gagal: $U (mencoba mirror berikutnya)"
done
[ "$OK" = "1" ] || { echo "ERROR: semua mirror gagal (jaringan egress terbatas?). Pasang templates manual."; exit 1; }
cd /tmp
rm -rf godot_templates_extract && mkdir godot_templates_extract
cd godot_templates_extract && unzip -qo "$TPZ" templates/android_debug.apk templates/android_release.apk templates/version.txt && cp templates/* "$DEST/" && echo "[fetch] templates terpasang di $DEST"
ls -la "$DEST"
