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
GODOT="${GODOT_BIN:-$ROOT/tools/godot-src/bin/godot.linuxbsd.editor.x86_64}"
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
timeout 150 "$GODOT" --headless --path "$PRJ" -- --server "$URL" > "$LOGS/run1.log" 2>&1 || true
grep -q "Semua konten siap" "$LOGS/run1.log" && ok "semua pack diunduh launcher" || grep "updater" "$LOGS/run1.log" | head -5
grep -q "Dunia siap" "$LOGS/run1.log" && ok "dunia selesai digenerate" || fail "dunia tidak selesai"
ERRS=$(grep -cE "SCRIPT ERROR|Parse Error|ERROR: " "$LOGS/run1.log" || true)
[ "$ERRS" = "0" ] && ok "tanpa error runtime" || { fail "$ERRS error runtime"; grep -E "SCRIPT ERROR|Parse Error|ERROR: " "$LOGS/run1.log" | head -10; }

say "6. Uji delta update (ubah 1 file di 1 pack)"
sed -i 's/Color(0.93, 0.65, 0.25)/Color(0.93, 0.66, 0.25)/' "$PRJ/packs/core_scripts/game_root.gd" 2>/dev/null || \
  sed -i 's/(0.86, 0.64, 0.24)/(0.86, 0.64, 0.26)/' "$PRJ/packs/ui/hud.gd"
python3 "$ROOT/tools/build_packs.py" --godot "$GODOT" > "$LOGS/build2.log" 2>&1
grep -E "^\[change\]" "$LOGS/build2.log" | tee "$LOGS/delta_changes.txt"
NCHANGE=$(grep -c "^\[change\]" "$LOGS/build2.log" || true)
[ "$NCHANGE" = "1" ] && ok "delta: hanya 1 pack berubah" || fail "delta: $NCHANGE pack berubah (harusnya 1)"
timeout 90 "$GODOT" --headless --path "$PRJ" -- --server "$URL" > "$LOGS/run2.log" 2>&1 || true
grep -q "Perlu mengunduh 1 pack" "$LOGS/run2.log" && ok "launcher hanya mengunduh 1 pack" || { fail "launcher mengunduh != 1 pack"; grep "Perlu mengunduh" "$LOGS/run2.log"; }

say "7. Uji offline (server mati, pack lokal ada)"
kill $SRV_PID 2>/dev/null
sleep 0.5
timeout 90 "$GODOT" --headless --path "$PRJ" -- --server "$URL" > "$LOGS/run3.log" 2>&1 || true
grep -q "pack lokal" "$LOGS/run3.log" && ok "mode offline berfungsi" || fail "mode offline gagal"

say "Selesai — ringkasan:"
cat "$LOGS/summary.txt"
