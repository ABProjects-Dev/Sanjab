# Android Release Builds

## Current release

Version `1.1.1` (`versionCode` 10) is the current published Sanjab release: it reduces the release APK size (R8 minify and resource shrinking, smaller in-app artwork, unused font removed) and modernizes the CI/Android toolchain. The 1.1.2 (`versionCode` 11) candidate makes the published artifact verifiable and non-overwritable, adds a CI release-build gate, and makes `pubspec.yaml` the single version source.

The signed APK and release-generated SHA-256 sidecar for 1.1.1 are attached to its GitHub Release:

- [Sanjab-v1.1.1.apk](https://github.com/ABProjects-Dev/Sanjab/releases/download/v1.1.1/Sanjab-v1.1.1.apk)
- [Sanjab-v1.1.1.apk.sha256](https://github.com/ABProjects-Dev/Sanjab/releases/download/v1.1.1/Sanjab-v1.1.1.apk.sha256)
- [GitHub Release v1.1.1](https://github.com/ABProjects-Dev/Sanjab/releases/tag/v1.1.1)

The checksum sidecar is produced by the release workflow but has not been independently re-verified; do not describe any checksum as independently verified. Earlier releases remain available: [Sanjab 1.1.0](https://github.com/ABProjects-Dev/Sanjab/releases/tag/1.1.0), [Sanjab 1.0.2](https://github.com/ABProjects-Dev/Sanjab/releases/tag/1.0.2), [Sanjab 1.0.1](https://github.com/ABProjects-Dev/Sanjab/releases/tag/1.0.1) and [Sanjab 1.0.0](https://github.com/ABProjects-Dev/Sanjab/releases/tag/1.0.0).

## Required GitHub Actions secrets

The repository release workflow requires these repository secrets:

- `ANDROID_KEYSTORE_BASE64` — Base64-encoded contents of the password-protected PKCS#12 release keystore.
- `ANDROID_KEYSTORE_PASS` — keystore password.
- `ANDROID_KEY_ALIAS` — release-key alias.
- `ANDROID_KEY_PASS` — release-key password.

Keep the original keystore and all passwords outside the repository. The workflow decodes the keystore into the runner's temporary directory, validates it, and never uploads the keystore or passwords. Do not put secret values in source, documentation, or chat.

## APK size and build configuration

The release artifact is a single universal APK covering all ABIs (`armeabi-v7a`, `arm64-v8a`, `x86_64`); ABI splitting is intentionally not used. The `release` build type runs R8 minify and Android resource shrinking, which requires a machine or CI runner with sufficient memory (see `org.gradle.jvmargs` in `android/gradle.properties`; GitHub Actions runners are sufficient). If a future release build fails on R8 keep-rule errors from a plugin, add minimal rules to `android/app/proguard-rules.pro` rather than disabling minification.

The in-app icon asset is shipped at 384px (it is rendered at small sizes only); the 1024px master remains the source for `tool/generate_brand_assets.sh`. Only the Vazirmatn weights used by the UI (400/600/700) are bundled.

## Run the release workflow

1. Confirm that the intended version tag exists, points to the intended source, and has a GitHub Release.
2. Open **Actions → Android release → Run workflow** on the `main` branch.
3. Enter the existing tag (for example, `v1.1.2`). The workflow verifies that the tag matches the version in `pubspec.yaml`; a leading `v` in the tag is optional and is ignored for the comparison.
4. Wait for dependency resolution, the Android release build, and APK certificate verification to finish.
5. Confirm that `Sanjab-<tag>.apk` and `Sanjab-<tag>.apk.sha256` are attached to the GitHub Release.

The upload step never overwrites an existing asset: if `Sanjab-<tag>.apk` is already attached, the workflow fails instead of silently replacing a published artifact. Re-publishing a corrected build requires deleting the old asset (or creating a new tag) as a deliberate, reviewed action. Release immutability should be enabled in the repository settings. The workflow checks out the selected tag. Before resolving production dependencies, it removes the test-only Flutter SDK dependency `integration_test` from the runner's temporary checkout of `pubspec.yaml`; this avoids registering a test-only Android plugin in the production APK. The repository's checked-in `pubspec.yaml` and app version are not changed by that runner-side step.

The workflow passes the temporary keystore path explicitly to Gradle, compares the APK's SHA-256 signing-certificate fingerprint with the configured keystore, and reads `versionName`/`versionCode` back from the built APK with `aapt2` to compare them with `pubspec.yaml`. It fails rather than uploading an APK whose signature or version does not match. The Gradle release configuration is fail-closed and does not fall back to the debug key.

## Local builds

A debug APK can be built locally with `flutter build apk --debug`. A local release build requires a local keystore file and the Gradle values `ANDROID_KEYSTORE` (file path), `ANDROID_KEYSTORE_PASS`, `ANDROID_KEY_ALIAS`, and `ANDROID_KEY_PASS`, supplied as Gradle properties or environment variables. `ANDROID_KEYSTORE_BASE64` is only the workflow's transport secret; Gradle does not consume it directly.

The Gradle wrapper (`gradlew`, `gradlew.bat`, `gradle/wrapper/gradle-wrapper.jar`) is tracked, so `cd android && ./gradlew ...` works with only a JDK and the Android SDK. `compileSdk` and `targetSdk` are pinned to 36 in `android/app/build.gradle.kts`, and `versionName`/`versionCode` are derived from `pubspec.yaml`.

## CI release gate

`Flutter checks` runs `flutter test` (with an lcov coverage report), a version-sync check (`tool/sync_app_version.py --check`), `flutter analyze`, and `flutter build apk --debug` on every push and pull request. On every push and on manual dispatch it additionally builds `flutter build apk --release` with a throwaway CI keystore after the test job passes, prints the aapt2 badging output and APK size, and launches the APK on an API 30 emulator, so R8 minification, resource shrinking and the release-only code paths are exercised before a release is dispatched. Because the gate runs on branch pushes, a branch can only be merged while its release build is green.
