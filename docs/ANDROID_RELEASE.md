# Android Release Builds

The `Android release` GitHub Actions workflow builds a signed production APK and uploads it, plus a SHA-256 checksum, to an existing GitHub Release. It does not build or publish a debug APK.

## Required GitHub Actions secrets

Configure these repository secrets before running the workflow:

- `ANDROID_KEYSTORE_BASE64` — base64-encoded contents of the password-protected PKCS#12 release keystore.
- `ANDROID_KEYSTORE_PASS` — keystore password.
- `ANDROID_KEY_ALIAS` — release key alias.
- `ANDROID_KEY_PASS` — release key password.

Keep the original keystore and its passwords outside the repository. The workflow decodes the keystore into the runner's temporary directory, validates it, and removes it when the hosted runner is discarded. It never uploads the keystore or passwords.

## Publish a release APK

1. Ensure the release tag already exists, points to the intended source, and has a GitHub Release.
2. Open **Actions → Android release → Run workflow** on the `main` branch.
3. Enter the existing release tag (for example, `1.0.0`). The tag must match the app version in `pubspec.yaml`.
4. Wait for the workflow to build the APK and verify that its signing certificate matches the configured keystore.
5. Confirm that `Sanjab-<tag>.apk` and `Sanjab-<tag>.apk.sha256` appear as assets on the GitHub Release.

The Gradle release build is fail-closed: it never falls back to the debug signing key. Release tasks fail unless all four signing values are configured. Debug builds remain available for CI and development.
