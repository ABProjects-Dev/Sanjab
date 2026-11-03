# Project Plan and Analysis Snapshot

**Review date:** 2026-11-03

**Scope:** Static review of the Flutter/Dart source, tests, Android/Gradle setup, GitHub Actions workflows and project documentation. Findings below are source-derived unless explicitly tied to a successful GitHub Actions run. No physical-device fault-injection was performed.

## Current project and release state

- Flutter/Dart Android game; Dart package `sanjab`, Android application ID `com.sanjab.game`.
- App version `1.0.1+7`; Android version name `1.0.1`, version code 7.
- Persian RTL dark portrait UI, bundled Vazirmatn font, host-authoritative multiplayer on a local TCP/UDP network.
- GitHub Release `1.0.1` is the current release page for the signed APK and its SHA-256 checksum; the previous `1.0.0` release remains available.
- The previous `1.0.0` signed release build and certificate-fingerprint check succeeded in [Android release run 41547414107](https://github.com/behrouzxp-dev/Sanjab/actions/runs/41547414107).
- Flutter analysis, all tests, and debug APK build succeeded in [Flutter checks run 41568333376](https://github.com/behrouzxp-dev/Sanjab/actions/runs/41568333376). These checks do not prove two-device network behavior.
- `test/` contains 131 `test`/`testWidgets` declarations; `integration_test/` has one device test for host setup, not a complete two-phone game.
- GitHub Actions workflows are present under `.github/workflows/`. The release workflow excludes the test-only `integration_test` dependency from the runner's temporary production dependency resolution, passes the keystore path explicitly, and rejects an APK signed with a different certificate.

## Prioritized follow-up

The entries below record implementation status; physical-device verification remains distinct from automated tests.

### P0 — Persist player room records in production

**Status:** Implemented. `main.dart` now uses a production controller factory that injects `RoomRepository`; a fresh-controller restart test verifies that a saved player room survives.

**Impact addressed:** Player-side saved-room records now use the same application-support directory as the other production repositories.

**Implemented and covered:**
- `createProductionGameController` injects file-backed `SessionRepository`, `ProfileRepository`, and `RoomRepository` from the application-support directory.
- A composition/restart test verifies saved player-room records are loaded by a fresh controller.
- Existing repository tests continue to cover backup recovery and the 20-room cap.

### P1 — Serialize file-backed saves

**Status:** Implemented with a reusable serial task queue. Session saves snapshot JSON when requested; room mutations serialize their full read-modify-write transaction. Tests cover queue ordering, recovery after a failed task, concurrent session saves, and concurrent room upserts.

**Implemented and covered:**
- A reusable serial task queue ensures only one operation at a time uses each repository's temporary paths.
- Session payloads are snapshotted at call time; room read-modify-write mutations stay within the queue.
- Tests verify queue ordering, continued operation after failure, and preservation of concurrent session/room updates.

### P1 — Correct join-state delivery and reconnect ownership

**Status:** Implemented and covered by regression tests. Flutter Actions passed on the merged source in [run 41568333376](https://github.com/behrouzxp-dev/Sanjab/actions/runs/41568333376).

`HostNetwork` now registers the accepted channel and sends `helloAck` before notifying the app to broadcast state. Message dispatch and disconnect cleanup check that the channel instance is still current, so a replaced socket cannot act as or remove its replacement. Tests cover immediate initial-state delivery and same-player replacement.

### P1 — Make final snapshot delivery acknowledgment-based

**Status:** Implemented and covered by regression tests. Flutter Actions passed on the merged source in [run 41568333376](https://github.com/behrouzxp-dev/Sanjab/actions/runs/41568333376).

`GameClient` retains a pending snapshot and retries it every two seconds until the matching positive acknowledgment arrives. It sends the pending payload immediately after reconnect. The host responds again to a duplicate same-round snapshot without applying the answers twice. Tests cover timeout retry/stop-after-ack, retry after reconnect, and duplicate acknowledgment with idempotent application.

### P1 — Bound network framing before line allocation

**Status:** Implemented. The TCP channel counts raw UTF-8 bytes incrementally, closes an over-limit socket before a newline is required, and the host caps pending handshakes at 32 while cleaning up timers and callbacks. Regression tests cover an oversized unterminated frame and pending-capacity release.

**Implemented and covered:**
- Enforce the 256 KiB frame limit incrementally on raw bytes, before a line is complete.
- Limit concurrent pending handshakes, close excess/abusive sockets, and cancel per-connection timers on completion.
- Tests exercise an oversized unterminated frame and verify that handshake capacity is reclaimed.

### P1 — Align answer input with the host's 80-character cap

**Finding:** The host silently drops answer/snapshot values longer than 80 Dart string characters, but the play-screen fields do not enforce that limit.

**Acceptance criteria:**
- Apply an explicit UI limit matching the server rule or revise the server rule consistently.
- Give clear feedback rather than silently losing a player's answer.
- Test normal typing, paste, and final snapshots at and beyond the boundary.

### P1 — Fix results navigation for remotely ended sessions

**Finding:** The player controller resets to lobby after `sessionEnded`, while `ResultsScreen` only handles transition to a new playing round. A player on results may remain on that route.

**Acceptance criteria:** Add a widget/controller navigation test proving that a remotely ended game returns every connected player to the home flow.

### P2 — Guard async UI lifecycle paths

**Finding:** `HomeScreen` calls `setState` in `!mounted` branches after asynchronous create/resume operations.

**Acceptance criteria:** Avoid state updates after disposal and add a widget test that disposes the route while the operation is pending.

### P2 — Make failed initial joins terminate or complete visibly

**Finding:** A failed initial connection can leave `GameClient`'s automatic reconnect loop active while the join screen stays in its failure state. A later background connection can leave the user connected without navigating into the game.

**Acceptance criteria:** Close/cancel the client after a failed join, or expose reconnect state and navigate on later success; test both outcomes.

### P2 — Keep release metadata and user-facing copy aligned

- The UI version is hardcoded in multiple places; derive it from one maintained source or add a guard test.
- `targetSdk` and `compileSdk` are Flutter Gradle defaults, not explicitly pinned; document or pin the toolchain expectation.
- `guide_screen.dart` contains stale copy about random letters and stop behavior; settings copy describes the game as single-device/offline despite LAN multiplayer.
- `protocol.dart` has a stale header comment saying version 2 while runtime `kProtocolVersion` is 3.

## Verification and release record

- GitHub release `1.0.1` is current: [release page](https://github.com/behrouzxp-dev/Sanjab/releases/tag/1.0.1).
- The release workflow validated the APK's signing certificate against the configured keystore before upload. The workflow change is documented in [Android Release Builds](ANDROID_RELEASE.md).
- The latest merged multiplayer-reliability changes passed Flutter analysis, tests, and debug APK build in [run 41568333376](https://github.com/behrouzxp-dev/Sanjab/actions/runs/41568333376). These checks do not replace physical-device testing.
- Regression tests for join ordering, reconnect replacement, snapshot retry, and duplicate acknowledgment were added in `test/net_test.dart` and `test/controller_flow_test.dart`.
- Flutter analysis, tests, and debug APK build passed in [run 41568333376](https://github.com/behrouzxp-dev/Sanjab/actions/runs/41568333376). No full two-phone game test, physical-device network matrix, or fault-injection run is recorded.
