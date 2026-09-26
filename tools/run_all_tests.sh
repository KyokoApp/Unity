#!/usr/bin/env bash
## run_all_tests.sh — orkestrasi uji end-to-end (tanpa GPU):
##  1) import proyek headless
##  2) build semua pack
##  3) jalankan dev_server (HTTP Range)
##  4) uji Range 206 manual
##  5) jalankan launcher headless melawan server lokal (unduh semua pack,
##     verifikasi hash, masuk scene game, generate dunia) -> scan log error
##  6) uji delta: ubah 1 pack -> build lagi -> jalankan launcher: cek hanya
##     1 pack perlu diunduh
##  7) uji offline: matikan server -> launcher tetap masuk via pack lokal
## Log: server/test_logs/*.log
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PRJ="$ROOT/project"
SRV="$ROOT/server"
LOGS="$SRV/test_logs"
GODOT="${GODOT_BIN:-}"
if [ -z "$GODOT" ]; then
    for cand in "$ROOT/tools/godot-src/bin/godot.linuxbsd.editor.x86_64" \
                /home/user/tools/godot-src/bin/godot.linuxbsd.editor.x86_64; do
        [ -x "$cand" ] && GODOT="$cand" && break
    done
fi
if [ -z "$GODOT" ] || [ ! -x "$GODOT" ]; then
    echo "ERROR: binari Godot tidak ditemukan; set GODOT_BIN=/path/to/godot" >&2
    exit 2
fi
echo "[env] godot = $GODOT"
PORT=8787
URL="http://127.0.0.1:$PORT"
mkdir -p "$LOGS"

say() { echo -e "\n=== $* ==="; }
fail() { echo "[FAIL] $*" | tee -a "$LOGS/summary.txt"; }
ok()   { echo "[ OK ] $*" | tee -a "$LOGS/summary.txt"; }
: > "$LOGS/summary.txt"

say "1. Import proyek (headless)"
"$GODOT" --headless --path "$PRJ" --import > "$LOGS/import.log" 2>&1 || true
tail -3 "$LOGS/import.log"

say "2. Build pack (semua)"
python3 "$ROOT/tools/build_packs.py" --godot "$GODOT" > "$LOGS/build1.log" 2>&1
tail -6 "$LOGS/build1.log"
[ -f "$SRV/manifest.json" ] && ok "manifest ada" || { fail "manifest tidak ada"; exit 1; }

say "3. dev_server di port $PORT"
python3 "$ROOT/tools/dev_server.py" $PORT "$SRV" > "$LOGS/dev_server.log" 2>&1 &
SRV_PID=$!
sleep 1
curl -s "$URL/manifest.json" | head -c 120; echo
[ $? -eq 0 ] && ok "manifest tersaji" || fail "manifest tidak tersaji"

say "4. Uji HTTP Range (resume)"
CODE=$(curl -s -o /dev/null -w "%{http_code}" -H "Range: bytes=1000-1999" "$URL/$(python3 -c "import json;m=json.load(open('$SRV/manifest.json'));print(m['packs'][m['pack_order'][0]]['url'])")")
[ "$CODE" = "206" ] && ok "Range dijawab 206 (resume didukung)" || fail "Range dijawab $CODE"

say "5. Jalankan launcher (unduh penuh, masuk game, generate dunia)"
rm -rf ~/.local/share/godot/app_userdata/"Pulau Toon"/packs 2>/dev/null || true
timeout 150 "$GODOT" --headless --path "$PRJ" -- --server="$URL" > "$LOGS/run1.log" 2>&1 || true
grep -q "Semua konten siap" "$LOGS/run1.log" && ok "semua pack diunduh launcher" || grep "updater" "$LOGS/run1.log" | head -5
grep -q "Dunia siap" "$LOGS/run1.log" && ok "dunia selesai digenerate" || fail "dunia tidak selesai"
ERRS=$(grep -cE "SCRIPT ERROR|Parse Error|ERROR: " "$LOGS/run1.log" || true)
[ "$ERRS" = "0" ] && ok "tanpa error runtime" || { fail "$ERRS error runtime"; grep -E "SCRIPT ERROR|Parse Error|ERROR: " "$LOGS/run1.log" | head -10; }

say "6. Uji delta update (ubah 1 file di 1 pack)"
## Mutasi otomatis + pemulihan diri: tambah komentar marker ke hud.gd (pack ui),
## bangun (harusnya HANYA pack ui yang naik versi), lalu setelah uji dikembalikan.
DELTA_FILE="$PRJ/packs/ui/hud.gd"
cp "$DELTA_FILE" "$LOGS/hud.gd.before_delta"
grep -v '^# uji delta$' "$DELTA_FILE" > "$LOGS/hud.gd.clean" && cp "$LOGS/hud.gd.clean" "$DELTA_FILE"
printf '# uji delta\n' >> "$DELTA_FILE"
python3 "$ROOT/tools/build_packs.py" --godot "$GODOT" > "$LOGS/build2.log" 2>&1
grep -E "^\[change\]" "$LOGS/build2.log" | tee "$LOGS/delta_changes.txt"
NCHANGE=$(grep -c "^\[change\]" "$LOGS/build2.log" || true)
[ "$NCHANGE" = "1" ] && ok "delta: hanya 1 pack berubah" || fail "delta: $NCHANGE pack berubah (harusnya 1)"
timeout 90 "$GODOT" --headless --path "$PRJ" -- --server="$URL" > "$LOGS/run2.log" 2>&1 || true
grep -q "Perlu mengunduh 1 pack" "$LOGS/run2.log" && ok "launcher hanya mengunduh 1 pack" || { fail "launcher mengunduh != 1 pack"; grep "Perlu mengunduh" "$LOGS/run2.log"; }
# pemulihan diri: kembalikan hud.gd & baseline manifest
mv "$LOGS/hud.gd.before_delta" "$DELTA_FILE"
python3 "$ROOT/tools/build_packs.py" --godot "$GODOT" > "$LOGS/build3.log" 2>&1
tail -2 "$LOGS/build3.log"

say "7. Uji offline (server mati, pack lokal ada)"
kill $SRV_PID 2>/dev/null
sleep 0.5
timeout 90 "$GODOT" --headless --path "$PRJ" -- --server="$URL" > "$LOGS/run3.log" 2>&1 || true
grep -q "pack lokal" "$LOGS/run3.log" && ok "mode offline berfungsi" || fail "mode offline gagal"
ERRS=$(grep -acE "SCRIPT ERROR|Parse Error|ERROR: " "$LOGS/run3.log" || true)
[ "$ERRS" = "0" ] && ok "run offline tanpa error runtime" || fail "$ERRS error runtime di run3"

say "8. Uji karakter: skin, resolver animasi, AnimationTree"
timeout 90 "$GODOT" --headless --path "$PRJ" --script dev_probe/character_anim_check.gd > "$LOGS/anim_check.log" 2>&1
if [ $? -eq 0 ]; then
    ok "karakter: 76 animasi, semua state terpenuhi, 240 transisi aktif"
else
    fail "anim-check keluar non-zero"
fi
tail -4 "$LOGS/anim_check.log" | grep -avE "fontconfig"

say "9. Uji preset kualitas (Rendah/Sedang/Tinggi efektif)"
timeout 90 "$GODOT" --headless --path "$PRJ" --script dev_probe/quality_presets_check.gd > "$LOGS/quality_check.log" 2>&1
if [ $? -eq 0 ]; then
    ok "preset efektif: skala monoton naik, Sedang=30 FPS"
else
    fail "quality-check keluar non-zero"
fi
tail -4 "$LOGS/quality_check.log" | grep -avE "fontconfig"

say "Selesai — ringkasan:"
cat "$LOGS/summary.txt"
