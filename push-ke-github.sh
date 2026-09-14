#!/usr/bin/env bash
# ============================================================
# Mendorong project Unity ini ke github.com/KyokoApp/Unity
#
# Kenapa file ini ada: sandbox tempat project dibuat TIDAK punya
# kredensial GitHub (sudah dicoba, hasilnya:
#   fatal: could not read Username for 'https://github.com').
# Repo-nya sendiri sudah di-commit dan remote-nya sudah di-set,
# jadi yang kurang memang cuma autentikasi.
#
# Jalankan dari dalam folder unity-rpg:
#     bash push-ke-github.sh
# ============================================================
set -euo pipefail

REPO="https://github.com/KyokoApp/Unity.git"

say() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }
die() { printf '\n\033[31mGAGAL: %s\033[0m\n' "$1" >&2; exit 1; }

say "0. cek prasyarat"
[ -d .git ] || die "bukan repo git — jalankan dari dalam folder unity-rpg"
git rev-parse --verify HEAD >/dev/null || die "belum ada commit"
command -v git >/dev/null || die "git tidak ada"

# GitHub menolak file >100 MB; .glb besar harus lewat LFS
if command -v git-lfs >/dev/null; then
  git lfs install --local
  say "Git LFS aktif"
else
  say "Git LFS TIDAK ada — .glb akan di-commit biasa."
  echo "    Aman selama tidak ada file >100 MB. Cek:"
  find . -path ./.git -prune -o -type f -size +50M -print | sed 's/^/      /' || true
fi

say "1. remote"
if git remote get-url origin >/dev/null 2>&1; then
  CUR=$(git remote get-url origin)
  echo "    origin sudah di-set ke: $CUR"
  [ "$CUR" = "$REPO" ] || git remote set-url origin "$REPO"
else
  git remote add origin "$REPO"
fi
echo "    -> $(git remote get-url origin)"

say "2. isi yang akan didorong"
git log --oneline | sed 's/^/    /'
echo "    $(git ls-files | wc -l) file ter-track"

say "3. autentikasi"
echo "    Kalau diminta username/password, JANGAN pakai password akun."
echo "    Pakai Personal Access Token (Settings → Developer settings → Tokens)"
echo "    dengan scope 'repo'. Atau jalankan 'gh auth login' dulu kalau punya gh."

say "4. push"
git push -u origin main

say "selesai"
echo "    Buka https://github.com/KyokoApp/Unity untuk memastikan isinya masuk."
echo
echo "    Langkah berikutnya (lihat DESAIN.md):"
echo "      1. Buka folder ini di Unity Hub (Unity 6000.0.32f1)"
echo "      2. Buat URP Asset + Universal Renderer, pasang di Graphics & Quality"
echo "      3. Window → General → Test Runner → EditMode  (harus 7/7 hijau)"
echo "      4. Baru lanjut Tahap 2: character controller + kamera"
