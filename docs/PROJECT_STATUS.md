# Project Status

**As of:** 2026-11-22
**Active source branch:** `main`
**Latest published release:** 1.1.1 (`versionCode` 10)
**Release candidate:** 1.1.2 (`versionCode` 11), pending signed APK publication through the Android release workflow.

## Summary

The current source includes the merged gameplay work (PR #16), the 1.1.1 release-size work (PR #19), the 1.1.1 preparation merge (PR #20), and the 1.1.2 audit remediation: a release-build gate and emulator smoke test in CI, published-artifact integrity checks (no silent overwrite, signer and version verification), a single version source, reconnect and duplicate-name robustness, debounced answer persistence, coalesced answer frames, WCAG AA text contrast, a camera-permission fallback for QR scanning, explicit `compileSdk`/`targetSdk`, coverage reporting, tracked Gradle wrapper files, pinned action SHAs, and repository/security hygiene files.

## Verification status

| Check | Result |
| --- | --- |
| Local Flutter tests, analysis, Android build | **Not run:** Flutter and Dart SDK executables are not installed in this environment |
| CI for the merged gameplay changes (PR #16) | **Passed:** Flutter tests, Dart analysis, and Android debug APK build in GitHub Actions |
| CI for PR #19 (APK size + toolchain) | **Passed** (2026-11-22): Flutter tests, Dart analysis, Android debug APK build |
| CI for the 1.1.1 preparation PR (PR #20) | **Passed** |
| Signed production APK for 1.1.1 | **Published** (2026-11-22) with its SHA-256 sidecar |
| Physical two-device Wi-Fi/hotspot and lifecycle checks | **Not run** |

## Release posture

- The app version is `1.1.2+11`. `pubspec.yaml` is the single source: Gradle derives `versionName`/`versionCode` from it, `lib/core/app_version.dart` is generated from it, and CI fails if the generated file drifts.
- The 1.0.2 APK's SHA-256 sidecar has not been independently checked. Do not describe the 1.0.2 checksum as independently verified.
- The release workflow verifies the APK signature against the configured production keystore, checks that the APK version matches `pubspec.yaml`, and refuses to overwrite an already published artifact of the same name.
- No network penetration test, physical-device network matrix, or force-stop durability test has been performed.

## Remaining verification

1. Pass Flutter tests, Dart analysis, the Android debug APK build, and the manually dispatched release build for 1.1.2.
2. Publish the signed APK through the Android release workflow and verify the reported signing certificate and package version.
3. Test discovery, reconnect/explicit leave, host completion while a client is offline, and lifecycle persistence on physical Android devices.
4. Decide on the remaining Level-1 finding from the audit: player identity is not authenticated inside the LAN (a participant holding the 6-character join token can claim another player's ID). Fixing it requires a protocol version bump.
