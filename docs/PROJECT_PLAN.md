# Project Plan and Analysis Snapshot

**Analysis date:** 2026-11-02

**Scope:** Source, tests, Flutter/package configuration and Android scaffold in this repository.

**Change scope:** App version metadata and documentation; gameplay logic and behavior were not intentionally changed.

## Current project state

- Flutter/Dart Android game, Dart package `shotormorgh`, Android application ID `com.sanjab.game`, version `1.0.0+6`.
- Persian RTL dark portrait UI; bundled Vazirmatn font and artwork.
- Host-authoritative multiplayer using local TCP plus UDP discovery, QR and manual join paths.
- 13 category IDs, fixed seven-minute rounds, stop quorum, host-only judging and scoring.
- Local profile and host-session JSON repositories; room-record storage adapter exists but is not wired into production composition.
- 12 Dart files under `test/` contain 126 `test`/`testWidgets` declarations; one device integration test exists. This is a static source count, not a test execution result.
- No `.github` workflow files, CI configuration, or iOS/web/desktop scaffolds were found in the checked-in tree during analysis.
- Flutter, Dart and Java executables were not available in the current workspace, so tests, analysis and builds could not be run.

## Priority recommendations

This is a set of evidence-based recommendations, not a claim that the work is already scheduled or approved.

### P0 — Wire durable saved-room storage

**Finding:** `GameController` defaults to `MemoryRoomStore`; `main.dart` does not pass the existing `RoomRepository`.

**Recommended work:** Construct `RoomRepository` with the application-support directory and inject it into `GameController` in the production composition root.

**Acceptance criteria:**
- Host and player room records survive an actual app/process restart.
- Existing host-session recovery and player resume paths remain correct.
- Add a composition-level/restart regression test proving the production path uses durable storage.
- Run the complete test suite and a two-device or repeatable network integration test when devices are available.

### P1 — Make displayed version derive from package metadata

**Finding:** The home/About UI currently displays `1.0.0`, matching package and Android version name `1.0.0` with Android version code 6. The UI text is still hardcoded in more than one screen.

**Recommended work:** Use one version source or a maintained generated value for the UI and build configuration to prevent future drift.

**Acceptance criteria:** The UI's displayed version and Android/package version agree; a test guards against recurrence.

### P1 — Verify LAN join and reconnect end-to-end

The source has socket and controller tests, but the device integration test explicitly covers only the host setup path and not a two-phone game. Exercise host/player joins, discovery and fallback join, stop/snapshot/judging, disconnect/reconnect, and room restore on real supported Android network combinations.

### P2 — Synchronize protocol documentation and source comments

`protocol.dart`'s header describes version 2 while the runtime constant is 3. Update the stale source comment when code changes are next authorized and add an assertion/documentation source of truth so protocol upgrades remain synchronized.

### P2 — Keep release metadata and documentation aligned

- The app version is now `1.0.0+6`; centralize the duplicate UI version literals as tracked above under P1.
- The README links to this `docs/` set now. Historical `documentation/*.txt` files, including publication and release reports, remain absent; restore them only from an authoritative source and do not fabricate signing or release records.
- README says target SDK 36 but app Gradle uses Flutter's `targetSdkVersion` default. Either pin and verify an explicit target or document the Flutter-derived value accurately.

### P2 — Verify release signing configuration safely

The app build reads signing values from Gradle properties/environment. No keystore is checked in (as desired). Before a stable release, verify the intended release signing config on a controlled build host and confirm missing/incomplete settings cannot silently produce an incorrectly signed artifact. Never add the keystore or passwords to Git.

### P3 — Add CI only when the project owner wants it

No GitHub Actions workflows were found. A small CI workflow could run `flutter analyze` and `flutter test` for pull requests once Flutter-version and runner requirements are agreed. Android release builds/signing should not be automated without a reviewed secret/configuration plan, and stable releases require owner approval.

## Suggested implementation sequence

1. Fix production `RoomStore` injection and add process-restart coverage.
2. Centralize the already-matching UI/package version values and add a regression test against future drift.
3. Run Flutter formatting, analysis, all 126 unit/widget/network declarations, and the device integration test where available.
4. Verify two-device LAN scenarios and Android debug/release builds on a configured machine.
5. Verify the protocol version comment against the runtime constant and decide whether historical release documents should be restored from an authoritative source.
6. Consider CI after toolchain and release-signing requirements are agreed.

## Decisions requiring project-owner input

- Is support for platforms beyond Android required, or should the repository remain Android-only?
- Should the historical `documentation/*.txt` references be restored from an authoritative archive or retired?
- Which Flutter SDK version should CI and release builds pin?
- Should the app enforce a minimum secure-network model or continue to assume a trusted local Wi-Fi/hotspot?
- Is a two-device physical test environment available for release validation?

## Verification record for this version-metadata task

- Updated app release metadata and user-facing version references to `1.0.0`; kept Android `versionCode` monotonic at 6.
- Kept package dependency versions, Android Gradle plugin versions, network protocol version and stored-data schema versions unchanged.
- Flutter and Dart executables are absent from this workspace, so Flutter tests, static analysis and Android builds were not run.
- `git diff --check` passed. Static checks confirmed `pubspec.yaml` version `1.0.0+6`, Android `versionName` `1.0.0` / `versionCode` 6, matching UI version literals and the updated UI test expectation.
- Markdown relative links, code-fence balance and trailing whitespace checks passed across the README and `docs/` files.
