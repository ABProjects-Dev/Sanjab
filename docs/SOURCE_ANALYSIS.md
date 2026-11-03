# Source Analysis

**Review date:** 2026-11-03
**Reviewed source baseline:** `f6fb21168b138c02b523ffa0526a5a`
**Method:** static source, configuration, test, documentation, and CI review. No executable files were changed. No local tests/builds were run because Flutter and Dart SDK executables are absent in the review environment.

## System shape

Sanjab is a single Flutter process per device with a layered Dart codebase. There is no server repository or remote backend. The host device's `GameSession` is authoritative; clients send actions and snapshots and receive a per-client state payload. Dart asynchronous I/O, timers, futures, and streams drive sockets and app tasks; no explicit application worker thread or coroutine framework was found.

```text
Flutter screens
      │ user actions / ChangeNotifier updates
      ▼
GameController (application coordinator)
   ├── GameSession + scoring/rules (domain)
   ├── HostNetwork / GameClient / UDP discovery (network)
   └── ProfileRepository / SessionRepository / RoomRepository (JSON files)
```

## Module responsibilities

| Area | Main files | Observed responsibility |
| --- | --- | --- |
| Startup and app shell | `lib/main.dart`, `lib/app.dart`, `lib/app_controller_factory.dart` | Flutter initialization, orientation, error handlers, data-directory selection, production dependency composition, lifecycle callback, RTL app shell |
| Domain | `lib/domain/models.dart`, `game_session.dart`, `categories.dart`, `answer_rules.dart`, `scoring.dart`, `profile.dart`, `room_record.dart` | Flutter-independent data, phases, transition guards, validation, categories, score calculation, identity, persisted room shape |
| State/coordinator | `lib/state/game_controller.dart`, `game_scope.dart` | Host/client use cases, listener state, timers, reconnection, persistence, authoritative state application, route-facing phase |
| Persistence | `lib/data/profile_repository.dart`, `session_repository.dart`, `room_repository.dart`, `lib/core/serial_task_queue.dart` | Local JSON stores, atomic-ish replacement/backup recovery, bounded room history, serialized mutations per repository instance |
| Network | `lib/net/protocol.dart`, `line_channel.dart`, `host_server.dart`, `game_client.dart`, `discovery.dart` | Versioned JSON envelope, TCP framing, handshake/admission, state and snapshot messages, reconnect, UDP announcements/probes |
| UI | `lib/ui/screens/`, `lib/ui/widgets/`, `lib/ui/navigation.dart` | Home/profile/join/lobby/play/judging/results/guide/settings/log flows, dialogs, QR scanner, phase routing |
| Android | `android/app/src/main/AndroidManifest.xml`, `build.gradle.kts`, `MainActivity.kt` | Package/permissions/build integration and a screen-awake MethodChannel; game rules remain in Dart |

## Runtime and data flow

1. Startup requests portrait orientations, installs Flutter/platform error handlers, resolves the application-support directory (with a system-temp fallback), initializes the local logger, creates production file-backed stores and bootstraps the controller.
2. The controller restores profile, host state and room records. UI screens read/listen through `GameScope`.
3. The host starts TCP on port 50501 or an OS-selected port, starts UDP discovery on 50507 if possible, and runs the authoritative timer.
4. A client sends `hello` with game ID, join token, persistent player ID and display name. The host validates it, registers/replaces the channel, acknowledges, then publishes state.
5. Players submit individual answers. The host validates actions; after round end, clients send snapshots until acknowledged. The host judges, scores and broadcasts per-player state.
6. Controller changes are persisted through JSON repositories; app lifecycle transitions request a flush. Hosts and clients each keep their own local records.

The domain `GameSession` is separated from Flutter and uses explicit phases (`lobby`, `playing`, `paused`, `collecting`, `judging`, `roundResults`, `finished`). `GameController` is a broad orchestration point (~1,727 lines at this baseline), which is a maintainability risk: it owns networking, state, navigation-facing phase changes, timers, storage and notifications. This is an architectural observation, not evidence of a functional defect by itself.

## Persistence and error handling

- Profiles, active host sessions and saved rooms are file-backed JSON in the application data directory. Session and room writes use temporary files and backups; room repository writes serialize read-modify-write operations and cap the history at 20 records.
- Queueing is per repository instance. This protects concurrent operations through the same repository object; it is not a cross-process/global locking mechanism.
- If resolving the support directory fails, startup falls back to `Directory.systemTemp`, which may be less durable under OS cleanup. This is a fallback path, not the normal Android path.
- The app has a bounded rotating local logger and global Flutter/platform error hooks. Logging is intended to avoid player answer contents. Error-path behavior and persistence failures still merit device-level fault testing.
- `app.dart` calls `controller.flush()` on paused/inactive/hidden/detached lifecycle events without awaiting the returned Future. This is a possible last-write durability race if the process is terminated immediately; the actual timing must be validated on devices (see BUG-07).

## Network and security assessment

- TCP is newline-delimited UTF-8 JSON, exact protocol version 3, with message IDs, per-channel sequences, duplicate suppression, a 256 KiB frame limit, a pending-handshake cap of 32 and a 15-second handshake deadline.
- The host is authoritative, verifies session/token/player identity, and does not expose an Internet service. Automatic reconnect is linear backoff from about 1.2 to 8 seconds.
- LAN TCP/UDP is unencrypted. QR and open-join beacons carry the token as a bearer credential. The application should be used on a trusted local network and not port-forwarded.
- Android manifest backup is disabled. No app-layer encryption of JSON persistence or TLS layer was identified; no claim of cryptographic or penetration testing is made.
- The fallback in `discoverHosts()` is annotated as per-interface broadcast but sends to each interface's own IPv4 address. Its expected broadcast behavior is therefore not implemented; impact is conditional on networks that reject the global broadcast.

## Correctness, compatibility, and testability

- The 80-character input rule is consistently defined as 80 grapheme clusters for UI/host acceptance. The minimum Stop rule is different: it counts valid Unicode code points after removing invisible/spacing runes.
- Protocol compatibility is exact-version and runtime version is 3. The top comment/example in `protocol.dart` still documents version 2.
- App version literals in home/settings and build metadata currently agree at 1.0.1 / code 7, but they are repeated and can drift.
- Host-authoritative timers prevent clients from ending rounds on their local clock. Snapshot retries and duplicate acknowledgment have targeted source tests.
- The test tree has 144 unit/widget/network/controller/storage test declarations and one device integration test. Tests include domain rules/scoring, socket behavior, snapshot retry, persistence/restart, concurrency, widgets and host setup. Discovery across actual Wi-Fi/hotspot hardware, two-device gameplay, lifecycle termination, network loss and camera permission flows remain manual/device-level concerns.
- The latest recorded CI run on the reviewed source SHA passed tests, analysis and Android debug build. This does not imply test coverage of every issue in this report.

## Confirmed source observations vs. hypotheses

| Finding | Certainty | User impact status |
| --- | --- | --- |
| Home screen calls `setState` after checking `!mounted` in create/resume paths | Confirmed source defect | Runtime error is conditional on disposal during the awaited operation; not reproduced |
| Failed initial client connection can leave automatic reconnect active while join UI already reports failure | Confirmed source behavior | Hidden/later connection and navigation mismatch is plausible; not reproduced on hardware |
| Interface-specific discovery loop sends to local interface address, not broadcast | Confirmed source defect | Discovery failure is conditional; requires live network testing |
| Offline client does not receive official end event and host only removes its own local room records | Confirmed architecture gap | Stale “resume” entry can remain; reproduce with two devices and one offline at finish |
| Lobby minimum uses roster size while round's active-player snapshot uses connected IDs | Confirmed source behavior; requirement-dependent | A solo-connected round can start if another roster entry is disconnected; confirm intended rule |
| Guide/About text contradicts current multiplayer/no-letter rules | Confirmed UI copy defect | User confusion, no game-state impact |
| Protocol file header says version 2 while runtime uses version 3 | Confirmed documentation/comment mismatch | No wire compatibility impact by itself |
| Lifecycle flush future is not awaited | Confirmed source behavior; effect uncertain | Durability risk under rapid process termination; needs device test |

See [Bug Report](BUG_REPORT.md) for evidence, severity, suggested changes and regression checks.
