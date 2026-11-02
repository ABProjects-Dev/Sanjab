# Architecture

## Project summary

ShotorMorgh is a Persian-language, portrait-oriented Flutter game for playing a category-based word game over a local Wi-Fi network or phone hotspot. The Android app is implemented in Dart/Flutter; its Kotlin activity only handles the keep-screen-on platform channel.

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

There are no iOS, web, desktop, or CI workflow directories in the checked-in project tree at the time of this analysis.

## Runtime composition

1. `lib/main.dart` initializes Flutter, locks the requested device orientation to portrait, installs Flutter/platform error handlers, and resolves the application-support directory (falling back to a temporary directory if path resolution fails).
2. It initializes `AppLogger` and constructs a `GameController` with `SessionRepository` and `ProfileRepository`.
3. `GameController.bootstrap()` loads the local profile, active host session and saved-room records, then marks the controller ready.
4. `ShotorMorghApp` provides the controller through `GameScope` and builds a Persian, right-to-left, dark `MaterialApp`.
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

The UI includes home, profile, host lobby, join/QR scanner, play, judging, results, guide, and settings/log screens. It is Persian and RTL, uses the bundled Vazirmatn font, and uses a fixed dark theme. The Android manifest requests network-state/Wi-Fi permissions and camera permission for QR scanning. `MainActivity.kt` implements the `com.shotormorgh.game/screen` method channel to keep the display on during active game phases.

## Game rules represented in code

- A game needs at least two players to start. A newly created round has no selected letter or word.
- There are 13 categories with stable IDs. The host can select active categories in the lobby or between rounds.
- Each round lasts 420 seconds, using an epoch deadline and host clock synchronization rather than decrement-only state.
- Stop is accepted only once per player and only when every active answer has at least two Unicode runes after the shared invisible/spacing-character filter. The round stop threshold is `ceil(active players at round start / 2)`; later disconnections do not change the threshold.
- After a round ends, the host collects final snapshots, judges non-empty answers and computes scores. Only the host can judge/finalize.
- Scores are 0 for empty/rejected, 5 for duplicate, 10 for a normal confirmed answer, 15 for the sole confirmed answer when another answer in that category is marked duplicate, and 20 for the sole confirmed answer when other entries are empty/rejected. The special 15/20 score replaces, rather than adds to, 10.

## Important implementation observations

These are findings from source inspection, not modifications made as part of the documentation task:

1. **Saved-room persistence is not wired into the app composition.** `main.dart` omits `RoomRepository`, so `GameController` uses its in-memory default. Prioritize this before promising player room recovery after process restart.
2. **The settings/about screen reports version `1.0.0`.** Package and Android configuration identify this source as `4.1.0+5` / version code 5. Use a single version source to prevent drift.
3. **Protocol comments are stale.** `protocol.dart`'s file comment describes an envelope version 2, while `kProtocolVersion` in `models.dart` is 3 and is the value used by serialization.
4. **Historical documentation files are absent.** Before this update, the README linked to a `documentation/` tree that was not in the repository. Its documentation section now links to this `docs/` set; the historical release/signing reports were not recreated because no authoritative copies were present.
5. **Release signing/build behavior was not executed here.** Android configuration reads signing values from Gradle properties or environment variables and otherwise selects debug signing for the release build path. Verify the intended signing behavior on a configured build machine before distributing a release.

## Architectural constraints

- The LAN protocol is not encrypted with TLS. The join token is an access credential; QR data includes it, and open-join discovery can announce it on the local network. Treat the Wi-Fi/hotspot as a trusted network and do not expose the token publicly.
- The host is authoritative, but player answer fields are mirrored locally for responsiveness and reconciled through host state updates.
- There is no permanent score/history backend; finishing a game removes active session data.
- `targetSdk` and `compileSdk` are taken from Flutter Gradle defaults in the app Gradle file; they are not explicitly pinned there, despite the README's stated target SDK.
