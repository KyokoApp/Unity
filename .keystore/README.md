# Keystore Configuration

This directory contains the permanent static signing keystore (`permanent.keystore`) for building Android APKs (`InfiniteRunner-Lite.apk`).

### Keystore Details:
- **File**: `permanent.keystore`
- **Format**: PKCS12
- **Alias**: `permanentkey`
- **Keystore Password**: `permanentpass123`
- **Key Password**: `permanentpass123`
- **Validity**: 20,000 days

Using this permanent keystore guarantees that every subsequent CI build and update APK will have the exact same cryptographic signature fingerprint (`SHA1` / `SHA256`), eliminating the `INSTALL_FAILED_UPDATE_INCOMPATIBLE` error and allowing updates over existing installs without uninstallation.
