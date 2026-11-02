# Requirements and Current Behavior

## Purpose and scope

ShotorMorgh is a Persian, category-based word game for two or more people using Android devices on one local Wi-Fi network or hotspot. One device hosts the session; other devices join it. No external game server is part of the implementation.

This document records requirements visible in the current source and distinguishes them from observed gaps. It is not a claim that a release build or physical-device verification has passed.

## Users and primary flows

### First-run profile

- A device has a stable generated player ID and a user-editable display name.
- The display name must contain 1–24 trimmed Dart string characters and must be unique within a game after whitespace and selected Persian/Arabic letter normalization.
- Changing the display name does not change the player ID.
- A configured display name is required before hosting or joining.

### Host a game

- The host creates a new session and a six-character join token.
- A host TCP listener starts on preferred port `50501`, falling back to an OS-assigned port when needed.
- The lobby allows category selection, open-join configuration, player visibility/removal and QR sharing.
- At least two players are required before the first round can start.
- New players are accepted only while the host session is in the lobby. Previously registered players may reconnect after the game starts, subject to host validation.

### Join a game

- Players can discover hosts over UDP broadcast, scan a QR code, or enter connection details manually.
- A joining client presents game ID, token, persistent player ID and display name in the TCP hello message.
- The host validates the session/token/player and is the authority for admission.
- Reconnection reuses the stable player ID; duplicate simultaneous sessions for that ID are replaced by the host.

### Play, judge and finish

- A round has the fixed duration of seven minutes (420 seconds); the user cannot configure the duration.
- The game has 13 categories (IDs 0–12) and no letter/word selection step.
- The host may pause/resume or end a round. The timer is based on an epoch end time, and clients apply a host clock offset.
- A player may stop only when every active category answer meets the minimum-character rule. Each player can stop once; the round ends after `ceil(active player count at round start / 2)` stop requests, or on timeout/host decision.
- At round end, clients submit their final answer snapshot. The host waits for snapshots or an explicit host decision to resolve a disconnected player before judging.
- Only the host judges. Every non-empty answer must be marked confirmed, duplicate, or rejected before finalization.
- The score is computed once per round and accumulated for the current game. Equal totals share a rank.
- The host can officially finish the session. That invalidates active join/resume state and returns connected clients to the home flow.

## Stop-answer validation

The shared domain rule used by the controller and host requires each active answer to contain at least two `String.runes` after filtering whitespace, control, zero-width, directionality and other configured invisible code points. It does not measure user-perceived grapheme clusters. This rule is intentionally stricter than a non-empty check.

## Categories and score rules

The stable category IDs and Persian labels are defined in `lib/domain/categories.dart`:

| ID | Category |
| ---: | --- |
| 0 | Name |
| 1 | Family name |
| 2 | City |
| 3 | Country |
| 4 | Food |
| 5 | Fruit |
| 6 | Animal |
| 7 | Color |
| 8 | Occupation |
| 9 | Objects |
| 10 | Flower |
| 11 | Car |
| 12 | Body parts |

Display order is maintained separately from ID order. Active categories are selected by the host before a round or between rounds.

| Judgement result | Score per answer |
| --- | ---: |
| Empty | 0 |
| Rejected | 0 |
| Duplicate | 5 |
| Confirmed, ordinary | 10 |
| Sole confirmed answer with at least one duplicate in category | 15 (replaces 10) |
| Sole confirmed answer with all other entries empty/rejected | 20 (replaces 10) |

If more than one answer is confirmed in a category, the unique-answer bonus is not applied.

## Persistence and lifecycle

- The profile is stored locally in `profile.json`.
- The host's active `GameSession` is stored in `active_session.json` with a temporary-file write and backup fallback.
- The source includes a durable `RoomRepository` for `rooms.json`, with atomic replacement, backup recovery and a cap of 20 rooms.
- **Current gap:** the production app does not inject `RoomRepository`; `GameController` therefore defaults to `MemoryRoomStore`. Player-side room-list continuation across process restarts is not guaranteed in the current app composition. The controller and repository tests do not establish that the real composition persists these room records.
- On Android app lifecycle transitions to background/inactive/hidden/detached, the controller is asked to flush its current saved state.
- There is no permanent game-history or account service. Officially finishing a session clears the active session/history.

## Platform and non-functional requirements

- Current checked-in platform scaffold: Android.
- Android application ID: `com.shotormorgh.game`.
- `minSdk`: 24 (Android 7.0). `versionName`: 1.0.0; `versionCode`: 6.
- Java and Kotlin JVM targets are 17. `compileSdk` and `targetSdk` are sourced from Flutter Gradle defaults in this repository.
- Flutter app is Persian-only, RTL, dark-themed and portrait-oriented, and bundles Vazirmatn font assets.
- TCP/UDP sockets require the Android `INTERNET` permission; network-state and Wi-Fi permissions are declared. Camera permission is required at runtime for QR scanning.
- The logger keeps a bounded log file and recent in-memory lines; implementation comments state that player answer text should not be logged.
- The local network traffic is plain TCP/UDP and has no TLS encryption. Join credentials should be shared only with intended players on a trusted local network.

## Verification requirements

The repository contains 126 `test`/`testWidgets` declarations under `test/` and one device integration test under `integration_test/`. The test suites cover domain transitions, scoring, stop validation, protocol/discovery, live sockets, controller flows, local persistence, room continuation and widgets. The integration test explicitly covers the host setup path; it does not simulate a two-phone network game.

For a code or release change, run the relevant Flutter tests, `flutter analyze`, and the applicable Android builds on a machine with Flutter/Dart and Android tooling installed. This version-metadata update did not execute tests, static analysis or builds because Flutter and Dart executables are not available in the current workspace.

## Current metadata and documentation notes

- The app version metadata is now `1.0.0+6`: `pubspec.yaml` uses `1.0.0+6`, Android uses version name `1.0.0` and version code 6, and the UI displays `1.0.0`. The UI values remain hardcoded and could drift later.
- `lib/net/protocol.dart`'s leading comment says protocol version 2; the implementation constant is 3. This is a network protocol version, not the app release version.
- The README's former links to a missing `documentation/` directory have been replaced with links to this `docs/` set. Historical release/signing reports remain absent because no authoritative copies were in the repository.
- The README states target SDK 36, while `android/app/build.gradle.kts` uses `flutter.targetSdkVersion`; the effective SDK value depends on the Flutter toolchain used to build.
