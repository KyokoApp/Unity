#!/usr/bin/env bash
#
# PATCHED activate.sh untuk game-ci/unity-builder@v4 (disalin menimpa
# dist/platforms/ubuntu/steps/activate.sh di runner oleh workflow apk-release).
#
# Alasan: unity-builder@v4 hanya tahu aktivasi SERIAL (unity-editor -serial)
# dan LICENSE SERVER. Untuk lisensi Unity Personal keduanya sudah tidak
# berlaku: jalur .alf/license.unity3d.com ditutup Unity, dan aktivasi serial
# via CLI tidak lagi diterima untuk seat Personal (gagal 5x retry, run
# 36824328286). Strategi yang benar saat ini: akuisisi seat Personal langsung
# dari layanan lisensi Unity lewat Unity.Licensing.Client.
# Ref: game-ci/cli PR #246 ("personal (free) license activation via the
#      Unity licensing client").
#
# File ini di-SOURCE oleh runsteps.sh, jadi WAJIB menyetel UNITY_EXIT_CODE
# dan tidak boleh exit langsung.
#

CLIENT="/opt/unity/Editor/Data/Resources/Licensing/Client/Unity.Licensing.Client"

echo "Requesting activation (personal license via Unity.Licensing.Client)"

if [ ! -x "$CLIENT" ]; then
  echo "::error ::Unity.Licensing.Client tidak ditemukan di $CLIENT — image editor berubah?"
  UNITY_EXIT_CODE=1
else
  retry_count=0
  delay=15
  UNITY_EXIT_CODE=1
  while [ "$retry_count" -lt 5 ]; do
    # Kredensial hanya lewat argv proses di dalam container build (sekali jalan);
    # nilai secret otomatis disamarkan GitHub di log. Jangan set -x di sini.
    "$CLIENT" --activate-all --include-personal \
      --username "$UNITY_EMAIL" \
      --password "$UNITY_PASSWORD"
    UNITY_EXIT_CODE=$?

    if [ "$UNITY_EXIT_CODE" -eq 0 ]; then
      echo "Activation successful (personal seat)"
      break
    fi

    retry_count=$((retry_count + 1))
    echo "::warning ::Activation failed, attempting retry #$retry_count"
    sleep "$delay"
    delay=$((delay * 2))
  done

  if [ "$UNITY_EXIT_CODE" -ne 0 ]; then
    echo "Unclassified error occured while trying to activate license."
    echo "Exit code was: $UNITY_EXIT_CODE"
    echo "::error ::There was an error while trying to activate the Unity license (personal seat via licensing client). Periksa UNITY_EMAIL/UNITY_PASSWORD, 2FA harus nonaktif, dan seat Personal tidak sedang terpakai/dibocorkan run lain (lepaskan di https://id.unity.com bila perlu)."
  fi
fi
