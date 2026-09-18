# Android signing keystore

The signing keystore is **not** stored in this repository. It used to be committed here
together with its password in plaintext, which meant anyone with read access to the repo
could produce an APK signed with the app's identity — Android would install it over a real
build as a legitimate "update". That is removed.

## One-time setup

Generate a keystore once and keep it somewhere safe (a password manager attachment, an
encrypted drive). Losing it means users must uninstall before they can install a new build.

```bash
keytool -keyalg RSA -genkeypair \
  -alias permanentkey \
  -keystore permanent.keystore \
  -deststoretype pkcs12 \
  -validity 20000 \
  -dname "CN=AnimeRunner,OU=Dev,O=KyokoApp,C=ID"
```

## Wire it into CI

In GitHub, open **Settings → Secrets and variables → Actions → Repository secrets** and add:

| Secret | Value |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | `base64 -w0 permanent.keystore` (Linux) or `certutil -encode` (Windows) |
| `ANDROID_KEYSTORE_PASSWORD` | keystore password |
| `ANDROID_KEY_ALIAS` | `permanentkey` (or whatever alias you chose) |
| `ANDROID_KEY_PASSWORD` | key password, if different from the keystore password |

The `Configure Keystore and Godot Editor Settings` step in
`.github/workflows/android-build.yml` decodes the blob into `.keystore/release.keystore` on
the runner and fails loudly if the secrets are missing. It deliberately does **not** fall
back to generating a fresh keystore: a new key would break `INSTALL_FAILED_UPDATE_INCOMPATIBLE`
protection for everyone who already has the app installed.

## If you are migrating from the old committed keystore

Recover it from history before it was removed, then upload that exact file as the secret so
existing installs keep updating cleanly:

```bash
git fetch --unshallow   # only needed if your clone is shallow
git show 30d2c6e177698dcf500d7825b183c77e85cb5d40:.keystore/permanent.keystore > permanent.keystore
base64 -w0 permanent.keystore   # paste the output into ANDROID_KEYSTORE_BASE64
```

That commit is the last one containing the file (`.keystore/permanent.keystore`, 2716 bytes).

## Rotating the keystore

If you must start from a new key, users on the old build cannot update in place — they have
to uninstall first. Publish the new APK under a new package name, or announce the uninstall
step in the release notes.
