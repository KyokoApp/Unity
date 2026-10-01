#!/usr/bin/env bash
#
# PATCHED return_license.sh untuk game-ci/unity-builder@v4 (disalin menimpa
# dist/platforms/ubuntu/steps/return_license.sh di runner oleh workflow
# apk-release). Pasangan dari activate.sh: seat Personal diakuisisi lewat
# Unity.Licensing.Client (--activate-all --include-personal) yang menghasilkan
# ENTITLEMENT (UnityEntitlementLicense.xml), bukan file .ulf — jadi
# --return-ulf biasanya balas error 1404 "Ulf license file not found".
# Itu NORMAL: server Unity menandai seat "SameMachine" (machine-id image
# game-ci tetap), sehingga run berikutnya memakai ulang seat yang sama.
#
# File ini di-SOURCE oleh runsteps.sh setelah build; jangan exit — kegagalan
# return hanya boleh jadi warning (exit code job tetap milik build).
#

CLIENT="/opt/unity/Editor/Data/Resources/Licensing/Client/Unity.Licensing.Client"

echo "Returning personal license seat"

RETURN_EXIT_CODE=1
return_attempt=0
while [ "$return_attempt" -lt 3 ]; do
  RETURN_OUTPUT=$("$CLIENT" --return-ulf 2>&1)
  RETURN_EXIT_CODE=$?
  if [ -n "$RETURN_OUTPUT" ]; then
    echo "$RETURN_OUTPUT"
  fi
  if [ "$RETURN_EXIT_CODE" -eq 0 ]; then
    echo "Personal license seat returned"
    break
  fi
  if echo "$RETURN_OUTPUT" | grep -qiE "not found|1404"; then
    echo "Info: tidak ada .ulf untuk dikembalikan — seat diaktifkan sebagai entitlement (Unity.Licensing.Client), bukan file lisensi. Normal: status SameMachine membuat seat Personal dipakai ulang otomatis oleh run berikutnya."
    RETURN_EXIT_CODE=0
    break
  fi
  return_attempt=$((return_attempt + 1))
  echo "::warning ::Failed to return personal license seat, retry #$return_attempt"
  sleep 10
done

if [ "$RETURN_EXIT_CODE" -ne 0 ]; then
  echo "::warning ::Personal seat mungkin masih tertahan. Bila run berikutnya gagal karena kehabisan seat, lepaskan lewat https://id.unity.com (atau jalankan Unity.Licensing.Client --return-ulf)."
fi
