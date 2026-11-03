# Android Release Builds

## Current release

Version `1.0.2` (`versionCode` 8) is the current published Sanjab release. The 1.1.0 (`versionCode` 9) candidate adds solo play, color-coded player status, additional room controls, and safer room resume behavior.

The signed APK and release-generated SHA-256 sidecar for 1.0.2 are attached to its GitHub Release:

- [Sanjab-1.0.2.apk](https://github.com/behrouzxp-dev/Sanjab/releases/download/1.0.2/Sanjab-1.0.2.apk)
- [Sanjab-1.0.2.apk.sha256](https://github.com/behrouzxp-dev/Sanjab/releases/download/1.0.2/Sanjab-1.0.2.apk.sha256)
- [GitHub Release 1.0.2](https://github.com/behrouzxp-dev/Sanjab/releases/tag/1.0.2)

The 1.0.2 checksum sidecar has not been independently verified; do not describe that checksum as independently verified. Earlier releases, [Sanjab 1.0.1](https://github.com/behrouzxp-dev/Sanjab/releases/tag/1.0.1) and [Sanjab 1.0.0](https://github.com/behrouzxp-dev/Sanjab/releases/tag/1.0.0), remain available.

## Required GitHub Actions secrets

The repository release workflow requires these repository secrets:

- `ANDROID_KEYSTORE_BASE64` — Base64-encoded contents of the password-protected PKCS#12 release keystore.
- `ANDROID_KEYSTORE_PASS` — keystore password.
- `ANDROID_KEY_ALIAS` — release-key alias.
- `ANDROID_KEY_PASS` — release-key password.

Keep the original keystore and all passwords outside the repository. The workflow decodes the keystore into the runner's temporary directory, validates it, and never uploads the keystore or passwords. Do not put secret values in source, documentation, or chat.

## Run the release workflow

1. Confirm that the intended version tag exists, points to the intended source, and has a GitHub Release.
2. Open **Actions → Android release → Run workflow** on the `main` branch.
3. Enter the existing tag (for example, `1.1.0`). The workflow verifies that the tag matches the version in `pubspec.yaml`.
4. Wait for dependency resolution, the Android release build, and APK certificate verification to finish.
5. Confirm that `Sanjab-<tag>.apk` and `Sanjab-<tag>.apk.sha256` are attached to the GitHub Release.

The upload step uses `--clobber`; rerunning the workflow for an existing tag replaces assets with those same names. Check the selected tag carefully before dispatching. The workflow checks out the selected tag. Before resolving production dependencies, it removes the test-only Flutter SDK dependency `integration_test` from the runner's temporary checkout of `pubspec.yaml`; this avoids registering a test-only Android plugin in the production APK. The repository's checked-in `pubspec.yaml` and app version are not changed by that runner-side step.

The workflow passes the temporary keystore path explicitly to Gradle and compares the APK's SHA-256 signing-certificate fingerprint with the configured keystore before upload. It fails rather than uploading an APK whose signature does not match. The current `main` Gradle release configuration is fail-closed and does not fall back to the debug key.

## Local builds

A debug APK can be built locally with `flutter build apk --debug`. A local release build requires a local keystore file and the Gradle values `ANDROID_KEYSTORE` (file path), `ANDROID_KEYSTORE_PASS`, `ANDROID_KEY_ALIAS`, and `ANDROID_KEY_PASS`, supplied as Gradle properties or environment variables. `ANDROID_KEYSTORE_BASE64` is only the workflow's transport secret; Gradle does not consume it directly. The `gradlew` and `gradlew.bat` scripts are not tracked, so a local Android build may need the wrapper-generation step used by the workflow. Use a compatible Flutter/Android toolchain; `compileSdk` and `targetSdk` currently come from Flutter Gradle defaults and are not explicitly pinned in this repository.
