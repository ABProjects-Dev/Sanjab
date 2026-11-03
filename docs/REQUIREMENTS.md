# Requirements and Current Behavior

**Reviewed against:** `f6fb21168b138c02b523ffa0526a5a253caf8d4a` on 2026-11-03.

## Purpose and scope

Sanjab is a Persian category-based word game for at least two Android phones on one local Wi-Fi network or hotspot. One phone hosts the authoritative match; other devices join over the local network. The implementation contains no cloud account or remote game server. This document records current source behavior and observed gaps; it is not a statement that all paths were device-tested.

## User flows

### Profile and identity

- A device has a stable generated player ID and an editable display name.
- A name must be non-empty, no longer than 24 Dart string code units after trimming, and unique within the session after normalization of selected whitespace and Persian/Arabic characters.
- Renaming does not change player identity. Hosting/joining requires a display name.

### Host

- Host creation makes a new game ID and six-character join token.
- TCP listener prefers port `50501` and uses an OS-assigned port if unavailable.
- Lobby supports category selection, open-join setting, player list/removal, connection details and QR.
- At least two players must be in the roster to start. The current lobby/domain gate checks roster size, not live connection count; disconnected listed players can remain in the roster.
- New players are accepted only in the lobby; previously registered player IDs may reconnect after play starts.

### Join

- A player can use UDP discovery, a QR code, or manual LAN address/port/token.
- TCP hello presents game ID, token, stable player ID and display name. The host decides admission.
- The client automatically reconnects; an initial connection failure may leave its retry loop alive while the UI displays an error (see [BUG-01](BUG_REPORT.md)).

### Play, judge and finish

- The source has 13 categories and no letter/word selection step.
- Each round is a fixed 420 seconds. The host can pause/resume or manually end; host epoch time is authoritative.
- The Stop minimum requires every active category answer to have at least two valid Unicode code points after whitespace/invisible-character filtering. This minimum is distinct from the maximum input limit.
- Maximum answer size is 80 grapheme clusters, shared across UI, domain, controller and host; over-limit values receive visible feedback.
- Each player can Stop once. The round ends on `ceil(connected player count at round start / 2)` accepted Stop requests, timeout, or host action. Mid-round disconnection does not alter the threshold.
- On end, the host collects client snapshots and then judges. Only the host judges; non-empty answers must receive a judgement before finalization.
- Empty/rejected = 0, duplicate = 5, ordinary confirmed = 10, sole confirmed with a duplicate elsewhere in the category = 15, sole confirmed with all others empty/rejected = 20. Unique scores replace 10 rather than add to it. Cumulative ties share rank.
- Host official finish informs connected clients and removes the host's local saved-room data. Offline player records may remain stale because they cannot receive that event (BUG-04).

Full rule details: [Game Rules](GAME_RULES.md).

## Storage and lifecycle

- Profile, host active session and saved rooms use local JSON repositories.
- The production controller factory injects file-backed profile/session/room repositories; tests can use memory stores.
- Session and room stores use temporary-file replacement and backup recovery. Room mutations serialize per repository instance, and the repository retains at most 20 rooms.
- The app requests a storage flush on lifecycle pause/inactive/hidden/detached. The Future is not awaited; its durability under immediate process termination needs device testing (BUG-07).
- If application-support path resolution fails, startup falls back to `Directory.systemTemp`; this fallback may be less durable than normal app storage.

## Platform and release

- Android package: `com.sanjab.game`; minimum API 24.
- Current source version is `1.0.1+7`. Published release is 1.0.1; newer source changes are unreleased.
- Persian RTL, dark theme, portrait. QR scanner requires camera access; networking is local IPv4 TCP/UDP.
- Effective `compileSdk`/`targetSdk` are inherited from Flutter Gradle defaults, not pinned.
- App includes a screen-awake MethodChannel and bounded local technical logs.

## Security and privacy boundary

- No remote game service or public API exists in the source.
- TCP/UDP traffic is unencrypted. QR and open-join beacon include/expose a bearer token on the local network; use a trusted LAN and do not port-forward.
- Local game JSON is in the app data sandbox; no application-layer encryption was identified. Android manifest backup is disabled.
- The static review did not perform security testing or packet inspection.

## Verification and known gaps

- `test/` contains 144 test/widget declarations; `integration_test/` contains one host-setup device test. Counts are static declarations, not executed results.
- GitHub Actions Flutter checks passed on the exact reviewed baseline: [run 41651598932](https://github.com/behrouzxp-dev/Sanjab/actions/runs/41651598932), including tests, analysis and Android debug APK build.
- Local checks were not run in this review because Flutter and Dart executables are missing from the environment.
- No full automated two-device match or real Wi-Fi/hotspot discovery matrix is present. See [Test Plan](TEST_PLAN.md).
- Source-level defects and evidence are itemized in [Bug Report](BUG_REPORT.md); none was fixed because the task scope is documentation-only.
