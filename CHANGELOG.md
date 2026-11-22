# Changelog

Notable changes to Sanjab are recorded here. Version numbers follow Semantic Versioning; Android build numbers increase monotonically.

## [Unreleased]

### Improved

- Reduce release APK size: enable R8 minify and Android resource shrinking for the `release` build type, and raise the Gradle/Kotlin heap so the release build runs on CI-class runners.
- Downscale the in-app icon (`assets/images/app_icon_display.png`, shown at small sizes only) from 1024px to 384px.
- Drop the unused `vazirmatn_medium.ttf` (weight 500 is never referenced by the UI).
- Recompress the native splash bitmap losslessly.
- Keep the release artifact as a single universal APK covering all ABIs; ABI splitting is intentionally not used.

### Fixed

- Raise Android Gradle Plugin from 9.1.0 to 9.1.1, the minimum supported by Flutter 3.50.1, which broke `flutter pub get`/builds and CI with a plugin-apply failure.
- Pin the Flutter toolchain in the CI and release workflows to 3.50.1 so a floating `stable` channel cannot silently raise its minimum AGP again.
- Surface Gradle wrapper/build failures in the Flutter checks job as annotations (job logs are not always externally fetchable).

### Verification

- Flutter tests, Dart analysis, and the Android debug APK build pass in GitHub Actions for this branch (2026-11-22). Release-build verification of R8 (device smoke test or a signed release workflow run) is still pending.

## [1.1.0] - 2026-11-04

### Added

- Allow a game to start with a single player.
- Show player status through accessible, color-coded names in a single horizontally scrollable row.
- Add room menus to judging and results, including host QR access and explicit room-exit actions.

### Improved

- Preserve multiplayer room state when returning home and resuming, with separate host-close and player-exit actions.
- Keep player names, room controls, and Back behavior consistent across game phases.
- Scale the unchanged squirrel artwork inside the launcher and splash assets to add visual padding.

### Fixed

- Prevent a reconnect during active play from sending a final-answer snapshot and marking the player stopped.
- Defer home navigation after system Back to avoid navigation during the pop callback.

### Verification

- Flutter tests, Dart analysis, and Android debug APK build pass in GitHub Actions.

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
