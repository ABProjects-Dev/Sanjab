# Test Plan and Coverage

## Current inventory

Static count from the active branch `arena/0af07290-sanjab`:

- `test/`: 155 `test` / `testWidgets` declarations across 13 Dart files.
- `integration_test/`: one device integration test (`app_flow_test.dart`).
- Total: 156 declarations. This is a textual declaration count, not a count of successful executions or unique assertions.

The unit/widget test files cover:

| File | Main areas |
| --- | --- |
| `game_session_test.dart` | Player identity/admission, round transitions, timer, stop threshold, snapshot collection, judging, serialization |
| `scoring_test.dart` | Empty/rejected/duplicate/confirmed and unique-answer scoring, totals, rank/ties |
| `stop_validation_test.dart` | Minimum Stop eligibility, invisible/spacing normalization, shared answer length, UI enabled/disabled feedback |
| `protocol_test.dart` | Envelope validation, version/type/sequence/deduplication, size limits, discovery/QR parsing and token handling |
| `net_test.dart` | TCP framing, handshake limits/admission, message dispatch, state delivery, answer validation, snapshots/ack/retry, reconnect replacement |
| `controller_flow_test.dart` | Multi-player in-process game flow, host state, duplicate snapshot, wrong token and disconnect behavior |
| `persistence_test.dart` | Session file save/load, corruption/backup recovery, clear behavior |
| `room_resume_test.dart` | Host/player room persistence and resume, end/leave, migration and room repository behavior |
| `storage_concurrency_test.dart` | Concurrent session/room writes and preserving the latest mutation |
| `serial_task_queue_test.dart` | Serialized execution and continuation after a failed task |
| `app_controller_factory_test.dart` | Production composition and player-room restore after controller restart |
| `widget_flow_test.dart`, `ui_4_test.dart` | Main UI flows, results route completion, saved rooms, QR framing and source/UI invariants |

The integration test `integration_test/app_flow_test.dart` exercises first-run name entry, host creation, port/token setup, and lobby rendering on one Android device. It explicitly does not simulate a two-phone match.

## Run commands

Use a clean checkout with the project's supported Flutter stable toolchain. Preserve `pubspec.lock`; after any command, inspect `git status`. Flutter and Dart are unavailable in the current editing environment, so these commands have not yet been run locally for the active branch.

```bash
flutter pub get
flutter analyze
flutter test --concurrency=2
flutter build apk --debug
```

Device integration (requires an Android device/emulator):

```bash
flutter test integration_test/app_flow_test.dart -d <DEVICE_ID>
```

The GitHub Actions `Flutter checks` workflow runs Flutter tests, Dart analysis, and Android debug APK build. No result is available yet for this branch; a passing run on the current PR is required before merge. Any prior baseline run is not evidence for these changes. CI is not physical-LAN verification.

## Additional regression scenarios recommended

### Join lifecycle and routing

- Join an unreachable host, submit a wrong token, and receive a host rejection. Confirm the failed initial attempt leaves no reconnect timer or hidden connected client.
- Navigate away while `createGame()` or `resumeRoom()` is pending. Confirm no `setState` after disposal.
- If reconnect after an initial failure is kept intentionally, verify successful late reconnect navigates to the lobby exactly once and failure remains visible.

### Discovery and two-device networking

- Discover across ordinary Wi-Fi and a phone hotspot using at least two physical devices.
- Exercise a network that rejects limited broadcast; automatic discovery may not work there, so verify QR and manual joining remain usable.
- Verify QR and manual join when discovery is blocked; verify open-join beacon/token exposure is understood by the user.
- Run a full host/client match: reconnect, socket replacement, snapshot retry, lost acknowledgment, host/client backgrounding, and address/port changes.

### Session completion and persistence

- In a two-player lobby, temporarily disconnect the non-host and attempt to start; verify roster membership/count is preserved and the same ID can reconnect. Then test explicit exit separately and confirm it removes the member.
- Finish the game while every player is connected and verify results navigation/room removal.
- Disconnect a player, finish the game on the host, relaunch the player, and verify the room is labelled unverified. A connection failure must not be treated as proof of completion; verify manual removal works and a reachable terminal host rejection removes the room.
- Delay/fail file writes around lifecycle pause/detach and verify the last completed save is recoverable (BUG-07).
- Verify session/room backup recovery, file permission/sandbox behavior, app update compatibility, and recovery from malformed/old JSON.

### UI and Android device matrix

- Verify guide copy, answer counter/paste limit, Stop prompts, QR camera permission/denial, dark RTL layouts, and navigation on small and large devices.
- Check portrait-only behavior, screen-awake enable/disable, Android 7/API 24 minimum, and current Android versions.
- The project does not pin effective compile/target SDKs; record the Flutter/Android toolchain used for each release verification.

## Coverage gaps

- No automated full match across two physical devices or real Wi-Fi/hotspot broadcast test is present.
- Regression tests have been added for initial retry cancellation, explicit leave vs transient disconnect/reconnect, roster/history behavior, and legacy serialization. They have not yet been executed; widget disposal/lifecycle and physical discovery/session-completion scenarios still need verification.
- A passing test suite does not prove security properties, Android lifecycle durability, arbitrary network behavior, or release compatibility on all supported devices.
