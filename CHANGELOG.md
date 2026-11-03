# Changelog

Notable changes to Sanjab are recorded here. Version numbers follow Semantic Versioning; Android build numbers increase monotonically.

## [1.0.2] - 2026-11-03

### Added

- Add protocol v4 explicit room-exit messages, preserving departure state and historical scores while distinguishing a full exit from transient disconnection.
- Persist host and player saved-room records through the production file-backed repository, with resume after app/controller restart.
- Keep up to 20 saved rooms and recover room data from a backup when the primary file is unreadable.
- Enforce an 80-grapheme-cluster answer limit across typing, paste, domain validation, and host input, with a visible error for rejected over-limit data.
- Return connected players to the home route when the host officially ends or resets the session.
- Align the squirrel artwork across launcher, splash, home, and play surfaces.

### Fixed

- Stop hidden reconnect attempts after an initial join failure while retaining reconnect for established sessions.
- Prevent `setState` after disposal in home create/resume flows.
- Remove the invalid per-interface discovery fallback and document QR/manual join for networks that block limited broadcast.
- Display an offline player's saved room as unverified until the host can be contacted.
- Correct the guide and About copy to match local-network multiplayer and no-letter game rules.
- Observe and log lifecycle flush failures as best-effort persistence.
- Serialize session and room writes to prevent concurrent operations from overwriting newer updates.
- Bound incoming TCP frames by UTF-8 bytes and cap pending host handshakes.
- Enforce the shared answer-length and Stop-eligibility rules across UI, domain, controller, and host validation, with visible feedback for rejected input.

### Verification

- Added regression coverage for initial-join retry cancellation, explicit leave versus transient disconnect/reconnect, roster/history persistence, and UI/protocol copy invariants.

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
