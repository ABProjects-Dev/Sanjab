# Requirements and Current Behavior

**Updated:** 2026-11-03
**Active source branch:** `arena/c87aff83-sanjab`; changes are unreleased.

## Purpose and scope

Sanjab is a Persian category-based word game for at least two Android phones on one local Wi-Fi network or hotspot. One phone hosts the authoritative match; other devices join over the local network. The implementation contains no cloud account or remote game server. This document describes source behavior, not physical-device verification.

## User flows

### Profile and identity

- A device has a stable generated player ID and an editable display name.
- A name must be non-empty, no longer than 24 Dart string code units after trimming, and unique within the session after normalization of selected whitespace and Persian/Arabic characters.
- Renaming does not change player identity. Hosting/joining requires a display name.

### Host and roster

- Host creation makes a new game ID and six-character join token.
- TCP listener prefers port `50501` and uses an OS-assigned port if unavailable.
- Lobby supports category selection, open-join setting, player list/removal, connection details and QR.
- At least two active roster members are required to start. A temporary network disconnect does not remove roster membership or decrement the count; the same player may reconnect.
- New players are accepted only in the lobby; previously registered player IDs may reconnect after play starts.
- Explicit “exit room” is a protocol action distinct from socket loss. In the lobby, the player is removed. After a round starts, historical answers/scores remain while the player is excluded from active membership, the current Stop threshold/pending snapshot set, and later rounds.

### Join and discovery

- A player can use UDP limited-broadcast discovery, a QR code, or manual LAN address/port/token. No incorrect per-interface broadcast fallback is claimed.
- TCP hello presents game ID, token, stable player ID and display name. The host decides admission.
- Automatic reconnect is for an established session. Failed initial connection attempts and explicit rejection do not leave a hidden retry loop.

### Play, judge and finish

- The game has 13 categories and no letter/word selection step.
- Each round is a fixed 420 seconds. The host can pause/resume or manually end; host epoch time is authoritative.
- The Stop minimum requires every active category answer to have at least two valid Unicode code points after whitespace/invisible-character filtering. This minimum is distinct from the maximum input limit.
- Maximum answer size is 80 grapheme clusters, shared across UI, domain, controller and host; over-limit values receive visible feedback.
- Each player can Stop once. The round ends on `ceil(connected player count at round start / 2)` accepted Stop requests, timeout, or host action. Temporary mid-round disconnection does not alter the threshold. An explicit exit removes that player from the current threshold.
- On end, the host collects client snapshots and then judges. Only the host judges; non-empty answers must receive a judgement before finalization.
- Empty/rejected = 0, duplicate = 5, ordinary confirmed = 10, sole confirmed with a duplicate elsewhere in the category = 15, sole confirmed with all others empty/rejected = 20. Unique scores replace 10 rather than add to it. Cumulative ties share rank.
- Connected clients receive the official host-end event and remove their saved room. An offline player cannot receive it; their local room is explicitly shown as unverified until the host is contacted. A reachable host can reject a terminal session, but if official completion has shut down the host, connection failure remains inconclusive and the player may need to remove the saved room manually. Immediate remote invalidation without a backend or later authoritative contact is not possible.

Full rule details: [Game Rules](GAME_RULES.md).

## Storage and lifecycle

- Profile, host active session and saved rooms use local JSON repositories.
- The production controller factory injects file-backed profile/session/room repositories; tests can use memory stores.
- Explicit-left IDs are persisted in the session. Older records without this optional field load with no left players.
- Session and room stores use temporary-file replacement and backup recovery. Room mutations serialize per repository instance, and the repository retains at most 20 rooms.
- Lifecycle pause/inactive/hidden/detached callbacks start a flush and observe/log failures. Lifecycle callbacks cannot be awaited by the OS; this is best effort, not a guarantee against immediate process termination.
- If application-support path resolution fails, startup falls back to `Directory.systemTemp`; this fallback may be less durable than normal app storage.

## Platform and release

- Android package: `com.sanjab.game`; minimum API 24.
- Latest published release is `1.0.1+7`; this branch's source is the unreleased `1.0.2+8` candidate.
- Persian RTL, dark theme, portrait. QR scanner requires camera access; networking is local IPv4 TCP/UDP.
- Effective `compileSdk`/`targetSdk` are inherited from Flutter Gradle defaults, not pinned.
- App includes a screen-awake MethodChannel and bounded local technical logs.

## Security and privacy boundary

- No remote game service or public API exists in the source.
- TCP/UDP traffic is unencrypted. QR and open-join beacon include/expose a bearer token on the local network; use a trusted LAN and do not port-forward.
- Local game JSON is in the app data sandbox; no application-layer encryption was identified. Android manifest backup is disabled.
- No network penetration test or packet inspection has been performed.

## Verification status

- Regression tests have been added for initial-join retry, explicit exit vs transient disconnect, reconnect, roster/state persistence and legacy snapshot loading.
- The local environment has no Flutter or Dart executable, so the new and existing suites have not been run locally. Current PR CI and device-level verification are pending; do not use an older CI run as evidence for this branch.
- No full automated two-device match or real Wi-Fi/hotspot discovery matrix is present. See [Test Plan](TEST_PLAN.md).
- BUG-01 through BUG-08 remediation and remaining limitations are recorded in [Bug Report](BUG_REPORT.md).
