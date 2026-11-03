# Architecture

## Project summary

Sanjab is a Persian-language, portrait-oriented Flutter game for playing a category-based word game over a local Wi-Fi network or phone hotspot. The Android app is implemented in Dart/Flutter; its Kotlin activity only handles the keep-screen-on platform channel.

The application uses a host-authoritative model: one device owns the canonical `GameSession`; player devices send input and render state received from that host. The repository contains no remote backend or HTTP API. Local networking uses TCP and UDP sockets.

## Repository map

```text
lib/
├── app.dart                 Flutter app, locale, RTL, lifecycle handling
├── main.dart                Composition root, error handling, initial bootstrap
├── core/                    Theme, Persian formatting, logging, screen-awake bridge
├── data/                    Profile, session, and room storage abstractions/adapters
├── domain/                  Game rules, models, scoring, profile and room records
├── net/                     TCP line channel, protocol, host, client, UDP discovery
├── state/                   GameController and inherited GameScope
└── ui/                      Navigation, screens, and reusable widgets
android/                     Android application and Flutter Gradle integration
assets/                      Vazirmatn fonts and application artwork
test/                        Unit, socket-network, controller, persistence, and widget tests
integration_test/            Device integration test for the hosting path
docs/                        Project documentation
```

GitHub Actions workflows are checked in under `.github/workflows/` for Flutter checks and Android release builds. No iOS, web, or desktop platform scaffold is checked in.

## Runtime composition

1. `lib/main.dart` initializes Flutter, locks the requested device orientation to portrait, installs Flutter/platform error handlers, and resolves the application-support directory (falling back to a temporary directory if path resolution fails).
2. It initializes `AppLogger` and constructs a `GameController` with `SessionRepository` and `ProfileRepository`.
3. `GameController.bootstrap()` loads the local profile, active host session and saved-room records, then marks the controller ready.
4. `SanjabApp` provides the controller through `GameScope` and builds a Persian, right-to-left, dark `MaterialApp`.
5. Screens call controller operations; the controller coordinates domain state, networking, persistence, timers, and notifications.

### Composition gap

`GameController` accepts a `RoomStore`, but defaults to `MemoryRoomStore`. The production composition in `main.dart` does not supply `RoomRepository`, even though that file implements durable JSON-backed room storage. As a result, room records created by the normal application process are in memory and do not survive process restart. The host session itself is separately persisted through `SessionRepository`; this does not make player-side saved-room records durable. This should be corrected and covered by a production-composition/restart test before relying on saved-room continuation on all devices.

## Layers and responsibilities

### Domain (`lib/domain/`)

- `models.dart`: players, answers, round records, phases, roles, submission states, and JSON representation.
- `game_session.dart`: host-authoritative game state and allowed transitions; does not import Flutter.
- `categories.dart`: stable IDs for the 13 categories and display order.
- `answer_rules.dart`: shared validation for the stop-button requirement.
- `scoring.dart`: per-category and per-round scores and standings.
- `profile.dart`: display-name validation and local identity/game/token ID generation.
- `room_record.dart`: saved-room value object.

The session has seven phases: `lobby`, `playing`, `paused`, `collecting`, `judging`, `roundResults`, and `finished`. A normal round proceeds from lobby/results to playing, then through collection and host-only judging to results. A host can explicitly finish a session.

### State (`lib/state/`)

`GameController` is the application coordinator and `ChangeNotifier`. It exposes profile, session, role, connection, timer, and answer state to the UI. Host-only operations mutate the canonical `GameSession`; player operations update local input optimistically and send messages to the host. Host updates are serialized into per-player state payloads. The controller handles reconnects, round snapshots, lifecycle saves, saved-room continuation, and final-session cleanup.

`GameScope` exposes the controller to widgets. `ui/navigation.dart` selects the play, judging, or results screen based on the current phase.

### Data (`lib/data/`)

Storage is expressed through interfaces so tests can substitute in-memory adapters:

- `ProfileStore` / `ProfileRepository`: profile JSON at `profile.json`.
- `SessionStore` / `SessionRepository`: the host's active session at `active_session.json`, with temporary-file replacement and a backup file.
- `RoomStore` / `RoomRepository`: up to 20 room records in `rooms.json`, also with a temporary file and backup. The durable adapter exists but is not currently wired into `main.dart`.

The application data directory is obtained from `path_provider`. These files are local application data, not a server-side account or permanent game-history service. `GameSession.finishAndClear()` clears round history and totals at the end of a session.

### Network (`lib/net/`)

- `protocol.dart`: typed JSON messages, protocol version validation, message IDs, duplicate detection and sequence guards.
- `line_channel.dart`: newline-delimited JSON over a TCP `Socket`.
- `host_server.dart`: TCP listener, unauthenticated-socket handshake gate, token/game/player validation, per-player channels and message dispatch.
- `game_client.dart`: player connection, hello handshake, reconnect scheduling and client messages.
- `discovery.dart`: UDP broadcast/probe-based host discovery.

The host prefers TCP port `50501` and falls back to a system-assigned port. UDP discovery uses port `50507`. The UI also supports QR and manual connection details. See [API](API.md) for message shapes and transport constraints.

### UI and platform (`lib/ui/`, `android/`)

The UI includes home, profile, host lobby, join/QR scanner, play, judging, results, guide, and settings/log screens. It is Persian and RTL, uses the bundled Vazirmatn font, and uses a fixed dark theme. The Android manifest requests network-state/Wi-Fi permissions and camera permission for QR scanning. The Android namespace and application ID are `com.sanjab.game`; the Dart package/import name remains `sanjab`. `MainActivity.kt` implements the `com.sanjab.game/screen` method channel to keep the display on during active game phases. The new application ID represents a separate Android package and does not update or replace an installation built with the former application ID.

## Game rules represented in code

- A game needs at least two players to start. A newly created round has no selected letter or word.
- There are 13 categories with stable IDs. The host can select active categories in the lobby or between rounds.
- Each round lasts 420 seconds, using an epoch deadline and host clock synchronization rather than decrement-only state.
- Stop is accepted only once per player and only when every active answer has at least two Unicode runes after the shared invisible/spacing-character filter. The round stop threshold is `ceil(active players at round start / 2)`; later disconnections do not change the threshold.
- After a round ends, the host collects final snapshots, judges non-empty answers and computes scores. Only the host can judge/finalize.
- Scores are 0 for empty/rejected, 5 for duplicate, 10 for a normal confirmed answer, 15 for the sole confirmed answer when another answer in that category is marked duplicate, and 20 for the sole confirmed answer when other entries are empty/rejected. The special 15/20 score replaces, rather than adds to, 10.

## Current implementation findings and verification

The following are source-level observations; network race conditions and UI lifecycle findings have not been reproduced on physical devices.

1. **Saved-room persistence is not wired into the app composition.** `main.dart` omits `RoomRepository`, so `GameController` uses its `MemoryRoomStore` default. Host-session recovery is separately backed by `SessionRepository`, but player-side saved-room records do not reliably survive a process restart.
2. **The app version is `1.0.1+7`.** The home/about screens display `1.0.1`, matching `pubspec.yaml` and Android `versionName`; Android `versionCode` is 7. The UI literals are duplicated and may drift in a future update.
3. **Protocol comments are stale.** `protocol.dart`'s file comment describes envelope version 2, while runtime serialization uses `kProtocolVersion = 3` from `models.dart`.
4. **Initial state follows channel registration.** `HostNetwork` registers the accepted channel, sends `helloAck`, then calls `onConnected`; the app broadcasts state from that callback so the new player receives its initial lobby snapshot immediately.
5. **Reconnect cleanup is channel-identity-safe.** Message dispatch and completion cleanup operate only when the channel map still points to that exact socket. Replacing a connection cannot let the old socket remove or act as the new one.
6. **Final snapshots use acknowledgment and retry.** `GameClient` retains the pending round and answer map, retries every two seconds, and resends immediately after reconnect until a matching positive `snapshotAck` arrives. The host re-acknowledges a duplicate already-applied snapshot without applying it again.
7. **TCP line-size protection is applied after line splitting.** `LineChannel` uses `LineSplitter` before `NetMessage.parse` enforces its cap, so a peer that withholds a newline can cause a large temporary buffer. This remains a local-network resource-exhaustion risk; a global pending-socket limit is also absent.
8. **File saves are not serialized.** `_scheduleSave` clears its scheduling flag before the asynchronous write completes, while `SessionRepository` reuses a single temporary filename. Rapid host input or a lifecycle flush can overlap writes; a queued/serialized writer and concurrent-save test are advisable.
9. **The prior `1.0.0` release is signed and verified.** GitHub Release `1.0.0` contains its signed APK and SHA-256 file. The successful workflow run is [41547414107](https://github.com/behrouzxp-dev/Sanjab/actions/runs/41547414107). The release workflow omits the test-only `integration_test` dependency from the runner's temporary production dependency resolution, passes the keystore path to Gradle, and verifies the APK certificate before upload.
10. **The current CI checks pass.** Flutter analysis, tests, and the debug APK build succeeded for the merged multiplayer-reliability changes in run [41568333376](https://github.com/behrouzxp-dev/Sanjab/actions/runs/41568333376). This does not replace two-device or physical-network verification.
11. **Target SDK is Flutter-derived.** `targetSdk` and `compileSdk` come from Flutter Gradle defaults and are not explicitly pinned in the app Gradle file.

## Architectural constraints

- The LAN protocol is not encrypted with TLS. The join token is a bearer credential; QR data includes it, and open-join discovery can announce it on the local network. Treat the Wi-Fi/hotspot as a trusted network and do not expose the token publicly.
- The host is authoritative, but player answer fields are mirrored locally for responsiveness and reconciled through host state updates.
- The TCP host drops answer strings longer than 80 Dart string characters, but the current answer fields do not enforce the same limit. Longer player answers can be silently absent from host state and final snapshots.
- There is no permanent score/history backend; finishing a game removes active session data.
- User-facing guide/settings copy contains stale statements about random letters, stop semantics, offline use, and single-device play; these should be kept aligned with current behavior.
