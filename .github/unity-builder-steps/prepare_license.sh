#!/usr/bin/env bash
# Dipakai job build & sim-test: aktivasi lisensi Unity Personal
# (diextract verbatim dari step "Siapkan lisensi Unity" agar tidak duplikat).
set -uo pipefail
IMAGE="unityci/editor:ubuntu-2022.3.45f1-base-3"
ULF_IN_CONTAINER="/root/.local/share/unity3d/Unity/Unity_lic.ulf"

tulis_lisensi_ke_env() {
  # $1 = file .ulf ; tulis ke $GITHUB_ENV sebagai UNITY_LICENSE (heredoc)
  {
    echo "UNITY_LICENSE<<__ULF__"
    cat "$1"
    echo "__ULF__"
  } >> "$GITHUB_ENV"
}

bereskan() {
  rm -rf "${1:-/tmp/xxx-nonexist}" >/dev/null 2>&1 || true
  docker rm -f unity-activate >/dev/null 2>&1 || true
}

# ---- 1) Secret UNITY_LICENSE terisi? pakai langsung ----
if [ -n "${UNITY_LICENSE_SECRET:-}" ]; then
  echo "Secret UNITY_LICENSE terisi — pakai lisensi dari secrets (tanpa aktivasi)."
  TMP_ULF="$(mktemp)"
  printf '%s\n' "$UNITY_LICENSE_SECRET" > "$TMP_ULF"
  tulis_lisensi_ke_env "$TMP_ULF"
  rm -f "$TMP_ULF"
  echo "UNITY_LICENSE siap di \$GITHUB_ENV."
  exit 0
fi

# ---- 2) Kosong? aktivasi Personal otomatis lewat container ----
echo "Secret UNITY_LICENSE kosong — coba aktivasi Personal otomatis dengan $IMAGE."
if [ -z "${UNITY_EMAIL:-}" ] || [ -z "${UNITY_PASSWORD:-}" ]; then
  echo "::error::UNITY_LICENSE kosong DAN UNITY_EMAIL/UNITY_PASSWORD belum lengkap. Isi secrets UNITY_EMAIL + UNITY_PASSWORD (akun Unity biasa, 2FA nonaktif) — lihat docs/CARA_SETUP_CI.md. Fallback: isi UNITY_LICENSE dengan seluruh isi file .ulf dari Unity Hub di PC."
  exit 1
fi

# Saring log container: email/password tidak boleh bocor ke log run.
saring_log() {
  while IFS= read -r line; do
    if [ -n "${UNITY_EMAIL:-}" ]; then line="${line//"$UNITY_EMAIL"/[email-disaring]}"; fi
    if [ -n "${UNITY_PASSWORD:-}" ]; then line="${line//"$UNITY_PASSWORD"/[password-disaring]}"; fi
    printf '%s\n' "$line"
  done
}

docker rm -f unity-activate >/dev/null 2>&1 || true
echo "Pull image $IMAGE (bisa beberapa menit, image besar)…"
if ! docker pull "$IMAGE"; then
  echo "::error::Gagal pull image $IMAGE — periksa nama tag/koneksi runner."
  exit 1
fi

# Di dalam container:
#  - aktivasi seat Personal via Unity.Licensing.Client (jalur resmi baru;
#    .alf/license.unity3d.com sudah ditutup Unity untuk Personal),
#  - fallback: login lewat unity-editor -createProject (terbukti login OK),
#  - tunggu Unity_lic.ulf bila client menuliskannya,
#  - cari serial Personal di state/log client (nilai TIDAK dicetak),
#  - kembalikan seat (--return-ulf) agar tidak bocor ke run berikutnya.
echo "Jalankan aktivasi Personal (kredensial lewat env container, log disaring)…"
set +e
docker run --name unity-activate \
  -e UNITY_EMAIL -e UNITY_PASSWORD \
  "$IMAGE" \
  bash -c 'set -u
    CLIENT="/opt/unity/Editor/Data/Resources/Licensing/Client/Unity.Licensing.Client"
    ULF="/root/.local/share/unity3d/Unity/Unity_lic.ulf"
    sanitasi_serial() { sed -E -e "s/[A-Za-z0-9_-]*UnityPers[A-Za-z0-9_-]*/[serial-disaring]/g" -e "s/[0-9]{12,16}-[A-Za-z0-9]{6,}/[serial-disaring]/g"; }
    touch /tmp/marker

    echo "[activation] == Unity.Licensing.Client --help (cek dukungan flag) =="
    "$CLIENT" --help 2>&1 | head -60 || true

    echo "[activation] == Aktivasi seat: Licensing.Client --activate-all --include-personal =="
    "$CLIENT" --activate-all --include-personal --username "$UNITY_EMAIL" --password "$UNITY_PASSWORD" > /tmp/client_out.txt 2>&1
    CLIENT_STATUS=$?
    echo "[activation] licensing-client exit=$CLIENT_STATUS"
    sanitasi_serial < /tmp/client_out.txt | head -40 || true

    i=0
    while [ "$i" -lt 20 ] && [ ! -s "$ULF" ]; do sleep 1; i=$((i+1)); done
    if [ -s "$ULF" ]; then echo "[activation] Unity_lic.ulf tertulis setelah ${i}s"; fi

    if [ ! -s "$ULF" ] && [ "$CLIENT_STATUS" -ne 0 ]; then
      echo "[activation] == client gagal & ulf belum ada — fallback login unity-editor (-createProject) =="
      unity-editor -batchmode -nographics -quit -createProject /tmp/actproj -logFile /tmp/editor_out.txt -username "$UNITY_EMAIL" -password "$UNITY_PASSWORD"
      EDITOR_EXIT=$?
      echo "[activation] unity-editor exit=$EDITOR_EXIT"
      echo "[activation] ---- tail log editor (disaring) ----"
      sanitasi_serial < /tmp/editor_out.txt 2>/dev/null | tail -30 || true
      i=0
      while [ "$i" -lt 20 ] && [ ! -s "$ULF" ]; do sleep 1; i=$((i+1)); done
      if [ -s "$ULF" ]; then echo "[activation] Unity_lic.ulf tertulis setelah ${i}s (jalur editor)"; fi
    fi

    echo "[activation] == Diagnostik: file baru selama aktivasi (hanya path) =="
    find /root -xdev -newer /tmp/marker -type f 2>/dev/null | head -60 || true
    echo "[activation] == Cari ulf/alf =="
    find /root -xdev \( -name "*.ulf" -o -name "*.alf" \) 2>/dev/null | head -10 || true
    ls -la /root/.local/share/unity3d/Unity/ 2>/dev/null || echo "[activation] direktori /root/.local/share/unity3d/Unity tidak ada"

    echo "[activation] == Cari serial Personal di output/state/log client (nilai tidak dicetak) =="
    SERIAL="$(grep -rhoaE "[0-9]{10,16}-UnityPers[A-Za-z0-9]{4,}" /tmp/client_out.txt /tmp/editor_out.txt /root/.config /root/.local /root/.cache 2>/dev/null | grep -v "XXXX$" | head -1 || true)"
    if [ -n "${SERIAL:-}" ]; then
      printf "%s" "$SERIAL" > /tmp/serial.txt
      echo "[activation] kandidat serial ditemukan (panjang ${#SERIAL}, awalan ${SERIAL:0:5}...) — nilai lengkap tidak dicetak"
    else
      echo "[activation] tidak ada kandidat serial di disk"
    fi

    echo "[activation] == Kembalikan seat Personal (cegah kebocoran seat) =="
    "$CLIENT" --return-ulf > /tmp/client_ret.txt 2>&1
    RET_STATUS=$?
    echo "[activation] return-ulf exit=$RET_STATUS"
    sanitasi_serial < /tmp/client_ret.txt | head -10 || true
    if [ "$RET_STATUS" -ne 0 ]; then
      echo "[activation][warning] return-ulf gagal — bila run berikutnya lapor kehabisan seat, lepaskan di https://id.unity.com (bagian license/seat)."
    fi
    exit 0' \
  2>&1 | saring_log
EDITOR_STATUS=${PIPESTATUS[0]}
set -e

echo "Container aktivasi selesai (exit code $EDITOR_STATUS) — ambil hasil dari container."
TMP_DIR="$(mktemp -d)"

# ---- Hasil A: file .ulf (diambil dari container, patokan utama) ----
if docker cp "unity-activate:/root/.local/share/unity3d/Unity" "$TMP_DIR/UnityLicDir" 2>/dev/null; then
  ls -la "$TMP_DIR/UnityLicDir" | sed 's/^/[license-dir] /' || true
fi
if [ -s "$TMP_DIR/UnityLicDir/Unity_lic.ulf" ]; then
  tulis_lisensi_ke_env "$TMP_DIR/UnityLicDir/Unity_lic.ulf"
  bereskan "$TMP_DIR"
  echo "Aktivasi Personal berhasil — UNITY_LICENSE (.ulf) siap di \$GITHUB_ENV."
  exit 0
fi

# ---- Hasil B: serial Personal (unity-builder v4 mendukung serial+email+password) ----
docker cp "unity-activate:/tmp/serial.txt" "$TMP_DIR/serial.txt" 2>/dev/null || true
SERIAL=""
if [ -s "$TMP_DIR/serial.txt" ]; then
  SERIAL="$(tr -d '\r\n' < "$TMP_DIR/serial.txt")"
fi
if [ -n "${SERIAL:-}" ] && [ "${#SERIAL}" -ge 24 ]; then
  echo "::add-mask::$SERIAL"
  {
    echo "UNITY_SERIAL<<__SERIAL__"
    printf '%s\n' "$SERIAL"
    echo "__SERIAL__"
  } >> "$GITHUB_ENV"
  SERIAL_LEN="${#SERIAL}"
  bereskan "$TMP_DIR"
  echo "Aktivasi Personal berhasil — UNITY_SERIAL (panjang $SERIAL_LEN, nilai disamarkan) siap di \$GITHUB_ENV; unity-builder akan aktivasi dengan serial + email + password."
  exit 0
fi

echo "::error::Aktivasi Personal otomatis GAGAL: tidak ada $ULF_IN_CONTAINER maupun serial Personal di container (lihat diagnostik [activation] di atas). Penyebab umum: UNITY_EMAIL/UNITY_PASSWORD salah, 2FA masih aktif, seat Personal habis (lepaskan di https://id.unity.com), atau gangguan server Unity. Fallback manual: isi secret UNITY_LICENSE dengan .ulf dari Unity Hub di PC — lihat docs/CARA_SETUP_CI.md."
bereskan "$TMP_DIR"
exit 1
