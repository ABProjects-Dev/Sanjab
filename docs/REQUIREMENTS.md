# Requirements and Current Behavior

## Purpose and scope

Sanjab is a Persian, category-based word game for two or more people using Android devices on one local Wi-Fi network or hotspot. One device hosts the session; other devices join it. No external game server is part of the implementation.

This document records requirements visible in the current source and distinguishes them from observed gaps. The Android release workflow builds and signature-checks the APK before publication; a published APK does not constitute two-device or broad physical-device verification.

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
- The host can officially finish the session. That invalidates active join/resume state and is intended to return connected clients to the home flow; a player already on the results screen may remain there (see the known implementation caveat below).

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
- **Current gap:** the production app does not inject `RoomRepository`; `GameController` therefore defaults to `MemoryRoomStore`. Player-side saved-room records are not reliably preserved across process restarts. The controller and repository tests do not establish that the real composition persists these records.
- On Android app lifecycle transitions to background/inactive/hidden/detached, the controller is asked to flush its current saved state.
- There is no permanent game-history or account service. Officially finishing a session clears the active session/history.

## Platform and non-functional requirements

- Current checked-in platform scaffold: Android.
- Android application ID and namespace: `com.sanjab.game`. The Dart package name remains `sanjab` because it is a separate identifier used by Dart imports.
- Changing the Android application ID creates a distinct Android package: it does not upgrade/replace an existing installation built with the former application ID and has separate application data.
- Release signing configuration reads `ANDROID_KEYSTORE`, `ANDROID_KEYSTORE_PASS`, `ANDROID_KEY_ALIAS`, and `ANDROID_KEY_PASS` from Gradle properties or environment variables; external build configurations must use these names.
- `minSdk`: 24 (Android 7.0). Current `versionName`: 1.0.1; `versionCode`: 7.
- Java and Kotlin JVM targets are 17. `compileSdk` and `targetSdk` are sourced from Flutter Gradle defaults in this repository.
- Flutter app is Persian-only, RTL, dark-themed and portrait-oriented, and bundles Vazirmatn font assets.
- TCP/UDP sockets require the Android `INTERNET` permission; network-state and Wi-Fi permissions are declared. Camera permission is required at runtime for QR scanning.
- The logger keeps a bounded log file and recent in-memory lines; implementation comments state that player answer text should not be logged.
- The local network traffic is plain TCP/UDP and has no TLS encryption. Join credentials should be shared only with intended players on a trusted local network.

## Known implementation caveats from static review

These findings are code-derived and have not all been reproduced on a device or under fault injection:

- The host rejects answer strings longer than 80 Dart string characters, but the UI does not cap input at that length; an overlength answer can be silently dropped.
- The 256 KiB protocol cap is checked after `LineSplitter` has assembled a line, so a peer that sends without a newline can grow a receive buffer before the check runs. The host still has no global pending-socket limit.
- The join path now broadcasts state only after `HostNetwork` registers the accepted channel and sends `helloAck`.
- Reconnect message and completion handlers now verify channel identity; an old socket cannot process messages as or remove its replacement.
- Final snapshots are retained and retried until the host acknowledges the matching round. Reconnects resend pending snapshots, and the host repeats acknowledgments for already-applied duplicates without changing the stored answers.
- Regression tests cover initial-state delivery, channel replacement, snapshot retry/acknowledgment, and duplicate snapshot acknowledgment. The merged network changes passed the Flutter Actions test job in run [41568333376](https://github.com/behrouzxp-dev/Sanjab/actions/runs/41568333376).
- Save scheduling permits a new asynchronous save while a previous save is still writing to the same temporary path. Host answer edits trigger frequent session saves; concurrent writes may conflict and need serialization.
- A failed initial join can leave the client's automatic reconnect loop active while the join screen remains on the failure state.
- A player receiving official session end while on the results screen may remain on that route; the results listener only handles transition to a new playing phase.
- Home-screen async create/resume handlers call `setState` in their `!mounted` branches, which can raise a lifecycle error if the route was disposed.

## Verification requirements

The repository contains 131 `test`/`testWidgets` declarations under `test/` and one device integration test under `integration_test/`. The integration test covers the host setup path; it does not simulate a two-phone network game.

Flutter analysis, the full test suite, and the Android debug APK build succeeded for the merged multiplayer-reliability changes in [run 41568333376](https://github.com/behrouzxp-dev/Sanjab/actions/runs/41568333376). The signed Android `1.0.0` release and certificate verification succeeded in [run 41547414107](https://github.com/behrouzxp-dev/Sanjab/actions/runs/41547414107). These checks do not substitute for a full two-phone game, physical-device testing, or all Wi-Fi/hotspot combinations.

## Current metadata, release and documentation notes

- App version metadata is `1.0.1+7`: `pubspec.yaml` uses `1.0.1+7`, Android uses version name `1.0.1` and version code 7, and the UI displays `1.0.1`. The UI values remain hardcoded and could drift later.
- GitHub Release `1.0.1` contains `Sanjab-1.0.1.apk` plus its `.sha256` checksum. See [the release page](https://github.com/behrouzxp-dev/Sanjab/releases/tag/1.0.1). The prior `1.0.0` release remains available.
- `lib/net/protocol.dart`'s leading comment says protocol version 2; the implementation constant is 3. This is a network protocol version, not the app release version.
- The README links to the checked-in `docs/` set. Historical `documentation/*.txt` reports remain absent because no authoritative copies were found.
- `android/app/build.gradle.kts` uses `flutter.targetSdkVersion`; the effective target SDK depends on the Flutter toolchain and is not pinned here.
