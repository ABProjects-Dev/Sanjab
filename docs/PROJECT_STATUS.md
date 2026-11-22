# Project Status

**As of:** 2026-11-22
**Active source branch:** `main`
**Latest published release:** 1.1.0 (`versionCode` 9)
**Release candidate:** 1.1.1 (`versionCode` 10), pending signed APK publication through the Android release workflow.

## Summary

The current source includes the changes merged in PR #16 (single-player game start, color-coded player names, room menus and host QR access, improved room exit/resume, and the reconnect fix) and PR #19 (release APK size reduction with R8 minify and resource shrinking, smaller in-app artwork, the unused Vazirmatn Medium font removed, AGP 9.1.1 with Flutter pinned to 3.50.1 in CI, and non-fatal analyzer infos).

## Verification status

| Check | Result |
| --- | --- |
| Local Flutter tests, analysis, Android build | **Not run:** Flutter and Dart SDK executables are not installed in this environment |
| CI for the merged gameplay changes (PR #16) | **Passed:** Flutter tests, Dart analysis, and Android debug APK build in GitHub Actions |
| CI for PR #19 (APK size + toolchain) | **Passed** (2026-11-22): Flutter tests, Dart analysis, Android debug APK build |
| CI for the 1.1.1 preparation PR | **Pending** at time of writing |
| Signed production APK for 1.1.1 | **Pending** release workflow |
| Physical two-device Wi-Fi/hotspot and lifecycle checks | **Not run** |

## Release posture

- The app version is `1.1.1+10`; the Android `versionName` and `versionCode` are kept in sync with `pubspec.yaml`.
- The 1.0.2 APK's SHA-256 sidecar has not been independently checked. Do not describe the 1.0.2 checksum as independently verified.
- The 1.1.0 release workflow must verify the APK signature against the configured production keystore and attach the APK and its SHA-256 sidecar to the GitHub Release.
- No network penetration test, physical-device network matrix, or force-stop durability test has been performed.

## Remaining verification

1. Pass Flutter tests, Dart analysis, and Android debug APK build for the 1.1.1 preparation PR.
2. Publish the signed APK through the Android release workflow and verify its reported signing certificate matches the configured release key.
3. Test discovery, reconnect/explicit leave, host completion while a client is offline, and lifecycle persistence on physical Android devices.
