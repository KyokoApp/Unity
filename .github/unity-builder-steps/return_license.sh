#!/usr/bin/env bash
#
# PATCHED return_license.sh untuk game-ci/unity-builder@v4 (disalin menimpa
# dist/platforms/ubuntu/steps/return_license.sh di runner oleh workflow
# apk-release). Pasangan dari activate.sh yang diakuisisi lewat
# Unity.Licensing.Client: seat Personal HARUS dikembalikan setelah build,
# kalau tidak seat bocor dan run-run berikutnya gagal "kehabisan seat".
#
# File ini di-SOURCE oleh runsteps.sh setelah build; jangan exit — kegagalan
# return hanya boleh jadi warning (exit code job tetap milik build).
#

CLIENT="/opt/unity/Editor/Data/Resources/Licensing/Client/Unity.Licensing.Client"

echo "Returning personal license seat"

RETURN_EXIT_CODE=1
return_attempt=0
while [ "$return_attempt" -lt 3 ]; do
  "$CLIENT" --return-ulf
  RETURN_EXIT_CODE=$?
  if [ "$RETURN_EXIT_CODE" -eq 0 ]; then
    echo "Personal license seat returned"
    break
  fi
  return_attempt=$((return_attempt + 1))
  echo "::warning ::Failed to return personal license seat, retry #$return_attempt"
  sleep 10
done

if [ "$RETURN_EXIT_CODE" -ne 0 ]; then
  echo "::warning ::Personal seat mungkin masih tertahan. Bila run berikutnya gagal karena kehabisan seat, lepaskan lewat https://id.unity.com (atau jalankan Unity.Licensing.Client --return-ulf)."
fi
