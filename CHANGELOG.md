# Changelog

Notable changes to Sanjab are recorded here. Version numbers follow Semantic Versioning; Android build numbers increase monotonically.

## [1.0.1] - 2026-11-03

### Fixed

- Make final-answer snapshot delivery reliable with host acknowledgments, retries, and resend after reconnect.
- Deliver the initial lobby state only after the joining player's socket is registered.
- Prevent replaced sockets from acting as or removing the player's current connection.
- Acknowledge duplicate snapshots without applying the answers more than once.

### Verification

- Flutter tests, Dart analysis, and Android debug APK build run in GitHub Actions.
- The Android release workflow builds the signed production APK and verifies its certificate before uploading it to GitHub Releases.

## [1.0.0] - 2026-11-02

- Initial stable Android release.
