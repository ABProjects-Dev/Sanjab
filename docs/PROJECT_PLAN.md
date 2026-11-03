# Project Plan and Analysis Snapshot

**Review date:** 2026-11-03

**Scope:** Static review of the Flutter/Dart source, tests, Android/Gradle setup, GitHub Actions workflows and project documentation. Findings below are source-derived unless explicitly tied to a successful GitHub Actions run. No physical-device fault-injection was performed.

## Current project and release state

- Flutter/Dart Android game; Dart package `sanjab`, Android application ID `com.sanjab.game`.
- App version `1.0.0+6`; Android version name `1.0.0`, version code 6.
- Persian RTL dark portrait UI, bundled Vazirmatn font, host-authoritative multiplayer on a local TCP/UDP network.
- GitHub Release `1.0.0` is published with `Sanjab-1.0.0.apk` and `Sanjab-1.0.0.apk.sha256`.
- The signed release build and certificate-fingerprint check succeeded in [Android release run 41547414107](https://github.com/behrouzxp-dev/Sanjab/actions/runs/41547414107).
- Flutter analysis, tests, and debug APK build succeeded in [Flutter checks run 41540382070](https://github.com/behrouzxp-dev/Sanjab/actions/runs/41540382070). These checks do not prove two-device network behavior.
- `test/` contains 126 `test`/`testWidgets` declarations; `integration_test/` has one device test for host setup, not a complete two-phone game.
- GitHub Actions workflows are present under `.github/workflows/`. The release workflow excludes the test-only `integration_test` dependency from the runner's temporary production dependency resolution, passes the keystore path explicitly, and rejects an APK signed with a different certificate.

## Prioritized follow-up

These recommendations are not claims that the work has already been implemented or reproduced on physical devices.

### P0 — Persist player room records in production

**Finding:** `main.dart` does not inject the durable `RoomRepository`; `GameController` defaults to `MemoryRoomStore`.

**Impact:** Player-side saved-room records are not reliable across app-process restarts, despite the UI's continuation flow. The host's separate persisted session does not solve this player-side gap.

**Acceptance criteria:**
- Inject `RoomRepository` using the application-support directory in the production composition root.
- Add a composition/restart test proving that host and player records survive a real process restart.
- Keep backup recovery and the room-count cap covered by tests.

### P1 — Serialize file-backed saves

**Finding:** `_scheduleSave` can start a second asynchronous save while the previous save is still in progress; the file repositories reuse fixed temporary paths. Frequent host edits or a lifecycle flush can overlap writes.

**Acceptance criteria:**
- Serialize or coalesce writes to each repository so only one write uses a temporary path at a time.
- Preserve the latest state when several saves are requested rapidly.
- Add a deterministic concurrent-save/recovery test.

### P1 — Correct join-state delivery and reconnect ownership

**Findings:** The host's hello callback broadcasts state before the new channel is registered. The old channel's completion callback can also remove a replacement channel without checking identity.

**Acceptance criteria:**
- Send the current state after successful channel registration.
- Make disconnect cleanup conditional on the exact channel instance still being current.
- Add controller/network regression tests for a lone player waiting in the lobby and reconnecting while the old socket closes.

### P1 — Make final snapshot delivery acknowledgment-based

**Finding:** A player marks a final snapshot as sent when it is queued locally; a same-round reconnect does not necessarily reset or retry it.

**Acceptance criteria:**
- Track pending versus acknowledged snapshots separately.
- Retry safely after reconnect or timeout until the host acknowledges the snapshot.
- Add a deterministic test for a disconnect between local send and host receipt.

### P1 — Bound network framing before line allocation

**Finding:** `LineSplitter` accumulates input before `NetMessage.parse` checks the 256 KiB character limit. A 15-second handshake timeout does not cap the in-progress line or aggregate pending sockets.

**Acceptance criteria:**
- Enforce an incremental byte limit before completing a line.
- Bound pending handshakes, remove per-connection callbacks on close, and close abusive sockets promptly.
- Test an oversized unterminated frame and many concurrent unauthenticated sockets.

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

- GitHub release `1.0.0` is live: [release page](https://github.com/behrouzxp-dev/Sanjab/releases/tag/1.0.0).
- The release workflow validated the APK's signing certificate against the configured keystore before upload. The workflow change is documented in [Android Release Builds](ANDROID_RELEASE.md).
- The latest recorded Flutter checks passed: [run 41540382070](https://github.com/behrouzxp-dev/Sanjab/actions/runs/41540382070).
- No full two-phone game test, physical-device network matrix, or fault-injection run is recorded. The static network and UI findings above need regression tests and device verification.
- During this documentation update, Flutter tests and analysis were not re-run locally; only documentation/workflow text was reviewed.
