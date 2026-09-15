Keystore untuk signing APK release, supaya install tanpa uninstall.

- Alias: yuki
- Store pass: yuki123
- Key pass: yuki123
- File: release.keystore (PKCS12, legacy PBE-SHA1-3DES supaya kompatibel dengan Gradle/JDK8)

Repo ini PRIVAT, jadi aman commit di sini. Kalau repo jadi publik, pindahkan ke Secret:
  ANDROID_KEYSTORE_BASE64 = base64 dari file ini
  ANDROID_KEYSTORE_PASS = yuki123
  ANDROID_KEYALIAS_NAME = yuki
  ANDROID_KEYALIAS_PASS = yuki123
