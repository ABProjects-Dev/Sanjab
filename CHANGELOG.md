# Changelog

Notable changes to Sanjab are recorded here. Version numbers follow Semantic Versioning; Android build numbers increase monotonically.

## [Unreleased]

### Added

- Persist host and player saved-room records through the production file-backed repository, with resume after app/controller restart.
- Keep up to 20 saved rooms and recover room data from a backup when the primary file is unreadable.
- Enforce an 80-grapheme-cluster answer limit across typing, paste, domain validation, and host input, with a visible error for rejected over-limit data.
- Return connected players to the home route when the host officially ends or resets the session.
- Align the squirrel artwork across launcher, splash, home, and play surfaces.

### Fixed

- Serialize session and room writes to prevent concurrent operations from overwriting newer updates.
- Bound incoming TCP frames by UTF-8 bytes and cap pending host handshakes.
- Enforce the shared answer-length and Stop-eligibility rules across UI, domain, controller, and host validation, with visible feedback for rejected input.

## [1.0.1] - 2026-11-03

### Fixed

- Make final-answer snapshot delivery reliable with host acknowledgments, retries, and resend after a reconnect.
- Deliver the initial lobby state only after the joining player's socket is registered.
- Prevent replaced sockets from acting as or removing the player's current connection.
- Acknowledge duplicate snapshots without applying the answers more than once.

### Verification

- Flutter tests, Dart analysis, and Android debug APK build run in GitHub Actions.
- The Android release workflow builds the signed production APK and verifies its certificate before uploading it to GitHub Releases.

## [1.0.0] - 2026-11-02

- Initial stable Android release.
