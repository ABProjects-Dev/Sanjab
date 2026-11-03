# Architecture

**Updated:** 2026-11-03; reflects active unreleased branch `arena/c87aff83-sanjab`.

## System overview

Sanjab is a Flutter/Dart Android game for local-network multiplayer. It has no remote game server or public HTTP API. Each device runs an app instance; the host device owns the authoritative `GameSession`, while player devices maintain synchronized local state and send player actions. The network uses IPv4 TCP and UDP.

The Android native layer is small. `MainActivity.kt` implements a MethodChannel to keep the display awake during active phases; game rules and orchestration are in Dart.

```text
Flutter UI (screens/widgets/navigation)
                 │
                 ▼
      GameController / GameScope
       ├── GameSession, rules, scoring
       ├── HostNetwork / GameClient / UDP discovery
       └── ProfileStore / SessionStore / RoomStore
                 │
                 ▼
       JSON files in app data directory
```

## Repository map

```text
lib/
  main.dart, app.dart, app_controller_factory.dart  Startup and production composition
  core/                                             Theme, Persian formatting, logs, helpers
  data/                                             Profile, session, saved-room repositories
  domain/                                           Models, session rules, categories and scoring
  net/                                              TCP framing, protocol, host/client, discovery
  state/                                            GameController and GameScope
  ui/                                               Navigation, screens, reusable widgets
android/                                            Android build/configuration and Kotlin activity
assets/                                             Vazirmatn fonts and app artwork
test/                                               Domain, network, storage, controller and widgets
integration_test/                                   Single-device Android host-flow test
docs/                                               Project documentation
.github/workflows/                                  Flutter checks and Android release build
```

No iOS, web, desktop, or backend service scaffold is checked in.

## Startup and composition

1. `lib/main.dart` initializes Flutter, requests portrait orientations, registers Flutter/platform error handlers, obtains application-support storage (falls back to a system temporary directory on failure), initializes the logger, creates the production controller and bootstraps saved state.
2. `createProductionGameController` injects file-backed profile, active-session and room stores. `GameController` accepts in-memory stores for tests.
3. `SanjabApp` provides the controller via `GameScope`, builds the Persian RTL dark Material app, and registers app lifecycle handling.
4. Screens issue actions through the controller and render its `ChangeNotifier` state. `ui/navigation.dart` maps current phase to play, judging or results routes.

## Layer responsibilities

### Domain (`lib/domain/`)

- `models.dart`: player, answer, round, phase, role, submission and protocol-independent model values.
- `game_session.dart`: session transitions, admission/name rules, round timer, Stop threshold, snapshot collection and judging guards. It does not depend on Flutter.
- `categories.dart`: 13 stable category IDs and labels/display order.
- `answer_rules.dart`: shared 80-grapheme-cluster maximum and minimum-valid-content rules used by input and host validation.
- `scoring.dart`: per-category/per-round points and cumulative standings.
- `profile.dart`, `room_record.dart`: local identity and resumable-room data.

A normal round moves through `playing`, `collecting`, `judging` and `roundResults`; the session also represents `lobby`, `paused`, and `finished`.

### State and application coordination (`lib/state/`)

`GameController` is the application coordinator and a `ChangeNotifier`. It owns profile/session state, host/client lifecycle, connection status, timers, answer operations, save scheduling, room resume/exit and state publication/application. Host operations mutate the canonical session; player actions are locally reflected and sent to the host. Host state is serialized into a recipient-specific payload so players receive their own answer map with shared roster/phase/score information.

`GameScope` exposes/listens to the controller. The controller is about 1,814 lines on the current branch and combines multiple responsibilities; this increases change and test complexity. It is a maintainability concern, not a standalone correctness defect.

### Data (`lib/data/`)

- `ProfileRepository`: profile JSON and stable player ID.
- `SessionRepository`: host active-session JSON, temporary-file replacement and backup recovery.
- `RoomRepository`: saved-room JSON, temporary-file replacement, backup recovery, serialized mutation and a 20-record limit.
- Production composition injects the file-backed room store; memory stores support tests.

Storage is local to the Android app sandbox. It is not cloud sync or permanent match history. Repository write queues are per instance, not global cross-process locks. Session/round history can grow with an unusually long match; room-list and logs have explicit bounds.

### Network (`lib/net/`)

- `protocol.dart`: JSON message envelope, exact protocol-version check, message IDs, deduplication and sequence guards.
- `line_channel.dart`: newline-delimited UTF-8 over TCP with a 256 KiB raw frame limit.
- `host_server.dart`: all-interface IPv4 listener, handshake admission, token/game/player validation, per-player channel management and message dispatch.
- `game_client.dart`: authenticated join, player messages, snapshot acknowledgment/retry and automatic reconnect.
- `discovery.dart`: UDP probe/beacon on port 50507.

The host prefers TCP port 50501 and falls back to an OS-assigned port. At most 32 unauthenticated sockets may wait for a hello; a handshake has a 15-second deadline. QR and manual connection are alternatives to discovery. Details: [Local Network API](API.md).

### UI and Android

UI includes home/profile, lobby, join/QR scanner, play, judging, results, guide, settings and technical logs. The app is Persian RTL with bundled Vazirmatn, dark theme, portrait orientation, camera use for QR and screen-awake integration. Android application ID/namespace is `com.sanjab.game`; Dart package name is `sanjab`. Minimum Android API is 24. Effective compile/target SDK values are Flutter Gradle defaults, not pinned in the project.

## Persistence and lifecycle flow

- Host active state is saved to `active_session.json`; profiles and room records have their own JSON files.
- Player records persist room/token/address, own answer/phase data and a local session snapshot for reconnect/resume.
- Writes use temp files and backups, and room write operations serialize their read-modify-write flow.
- App paused/inactive/hidden/detached events start `controller.flush()` and observe/log errors. The callback cannot be awaited by the OS; this is best effort, not a guarantee against immediate process termination.
- Official finish sends a `sessionEnded` event to connected players and deletes host-local session/room records. An offline client's room is labelled unverified until authoritative host contact; immediate invalidation without reconnecting is impossible.

## Security boundaries

The LAN protocol is not TLS-encrypted. A six-character join token is a bearer credential; a QR code includes it and an open-join UDP beacon may broadcast it to the LAN. The app is not designed for Internet exposure; do not port-forward the host. Android manifest backup is disabled, but application-level encryption for JSON data was not identified. This static review is not a security audit or penetration test.

## Current implementation notes

- Runtime and documented protocol version is 4. The protocol includes a dedicated explicit `leave` message; transport disconnect remains a separate event.
- Explicit leave updates active roster membership and persists departed IDs; transient disconnect retains roster membership and allows reconnect.
- Initial join failures do not retain an automatic retry; the invalid per-interface discovery fallback has been removed.
- Current source candidate is 1.0.2+8; the latest published artifact remains 1.0.1+7 until the release workflow succeeds.

See [Source Analysis](SOURCE_ANALYSIS.md), [Bug Report](BUG_REPORT.md), and [Project Status](PROJECT_STATUS.md). Current-branch CI is pending, and no local checks or physical-device networking have been run for this change set.
