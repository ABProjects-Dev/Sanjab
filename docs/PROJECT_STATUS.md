# Project Status

**As of:** 2026-11-04
**Active source branch:** `arena/da68caee-sanjab`
**Latest published release:** 1.0.2 (`versionCode` 8)
**Release candidate:** 1.1.0 (`versionCode` 9), pending PR checks and signed APK publication.

## Summary

The current source includes the changes merged in PR #16: single-player game start, accessible color-coded player names in a single horizontal row, room menus and host QR access across game phases, improved host/player room exit and resume behavior, and the reconnect fix preventing a player from being marked stopped during active play.

## Verification status

| Check | Result |
| --- | --- |
| Local Flutter tests, analysis, Android build | **Not run:** Flutter and Dart SDK executables are not installed in this environment |
| CI for the merged gameplay changes | **Passed:** Flutter tests, Dart analysis, and Android debug APK build in GitHub Actions |
| CI for the 1.1.0 version-bump PR | **Pending** |
| Signed production APK for 1.1.0 | **Pending** release workflow |
| Physical two-device Wi-Fi/hotspot and lifecycle checks | **Not run** |

## Release posture

- The app version is being advanced to `1.1.0+9`; the Android `versionName` and `versionCode` are kept in sync with `pubspec.yaml`.
- The 1.0.2 APK's SHA-256 sidecar has not been independently checked. Do not describe the 1.0.2 checksum as independently verified.
- The 1.1.0 release workflow must verify the APK signature against the configured production keystore and attach the APK and its SHA-256 sidecar to the GitHub Release.
- No network penetration test, physical-device network matrix, or force-stop durability test has been performed.

## Remaining verification

1. Pass Flutter tests, Dart analysis, and Android debug APK build for the 1.1.0 version-bump PR.
2. Publish the signed APK through the Android release workflow and verify its reported signing certificate matches the configured release key.
3. Test discovery, reconnect/explicit leave, host completion while a client is offline, and lifecycle persistence on physical Android devices.
