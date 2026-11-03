# Bug Report and Static Review Findings

**Review date:** 2026-11-03
**Source baseline:** `f6fb21168b138c02b523ffa0526a5a253caf8d4a`
**Scope:** Static review only. No local Flutter/Dart SDK was available; findings marked “not reproduced” are not runtime-confirmed. Source code was not modified.

Severity guide: **Medium** = can disrupt a normal user flow in a specific condition; **Low** = limited impact, misleading copy, or maintainability/durability risk. No critical or high-severity exploitable issue was confirmed in this review. Security boundaries/limitations are recorded separately from bugs.

## BUG-01 — Failed initial join can continue reconnecting in the background

- **Severity:** Medium
- **Status:** Confirmed source behavior; user-visible impact not reproduced.
- **Locations:** `lib/net/game_client.dart:138-145, 155-173`; `lib/state/game_controller.dart:659-720`; `lib/ui/screens/join_screen.dart:79-94`.
- **Evidence:** `GameClient.connect()` schedules `_scheduleReconnect()` on a connection exception and the channel completion path schedules reconnect unless explicitly closed as a user action. `_attachClient()` returns `false` to `joinGame()` without disposing/fully cancelling the client. The join screen then shows a connection error and stays on that route, but the client's retry timer remains able to connect later.
- **Cause:** Failed first-time admission and recovery of an established session share the same auto-reconnect behavior; the failure return does not stop the retry loop or communicate later success to the join route.
- **Impact:** A user may see a failed join while the client later connects in the background, without being navigated into the lobby. Rejected credentials may also be retried unnecessarily.
- **Suggested fix:** Distinguish initial connection from reconnecting an established session. On a failed initial join, cancel retries and dispose the client; alternatively expose retry state and navigate/notify when a later retry succeeds. Ensure an explicit `helloReject` does not trigger retries.
- **Retest:** Unit/network test for unreachable host, wrong token, and rejected handshake; assert no retry timer/client remains after a failed initial join. Add a widget test for late successful reconnect if that behavior is intentionally retained.

## BUG-02 — Home screen calls `setState` after widget disposal

- **Severity:** Medium
- **Status:** Confirmed source defect; lifecycle scenario not reproduced.
- **Locations:** `lib/ui/screens/home_screen.dart:42-48` and `75-81`.
- **Evidence:** After awaiting `createGame()` or `resumeRoom()`, the code checks `if (!mounted)` and then calls `setState(() => _busy = false)` inside that branch. The mounted check establishes that the state is disposed, so this call violates Flutter's lifecycle contract.
- **Cause:** Cleanup is mistakenly placed in the unmounted branch instead of returning without a state update.
- **Impact:** If the route is disposed while the operation is pending, Flutter can report `setState() called after dispose`; the operation may still finish in the controller.
- **Suggested fix:** Return immediately when `!mounted`; do not call `setState` on the disposed state. Decide separately whether the controller operation should be cancellable.
- **Retest:** Widget tests that dispose/pop the home route while create and resume futures are held pending; verify no exception and that operation completion is handled safely.

## BUG-03 — Interface-specific discovery fallback is not a broadcast

- **Severity:** Medium
- **Status:** Confirmed destination mismatch; network impact is conditional and untested.
- **Location:** `lib/net/discovery.dart:203-213`, especially line 212.
- **Evidence:** The comment says to send to each interface's broadcast address, but the loop passes `address` (the interface's own local IPv4 address) to `socket.send()`. Sending a UDP probe to the local interface address does not address the subnet broadcast.
- **Cause:** The code enumerates interface addresses without deriving their subnet broadcast address/mask.
- **Impact:** The fallback intended for networks that reject `255.255.255.255` may fail to discover hosts on those networks. QR and manual join remain alternatives. This is not evidence that discovery fails on every network.
- **Suggested fix:** Compute a valid subnet broadcast address per interface (with platform-safe handling) or remove the fallback claim and rely on a tested discovery mechanism. Avoid sending to loopback or unrelated interfaces.
- **Retest:** Add an injectable/unit test for address derivation; test discovery on two physical Android devices on ordinary Wi-Fi and a hotspot where global broadcast is restricted, plus QR/manual fallback.

## BUG-04 — Offline player's saved room can outlive an official session end

- **Severity:** Medium
- **Status:** Confirmed data-flow gap; reproduction requires multiple devices.
- **Locations:** `lib/state/game_controller.dart:1157-1205` and `1183-1192`.
- **Evidence:** The host broadcasts `sessionEnded`, waits 120 ms, and `_removeRoomsOfGame()` operates on the host's own local `roomStore`. A connected player removes its own record only after receiving `sessionEnded`. A disconnected player cannot receive the event, and no durable end marker/tombstone is distributed to that device.
- **Cause:** Session completion is represented as a best-effort event to connected clients rather than a durable state that a returning client can query.
- **Impact:** An offline player's saved room can remain listed as resumable after the host ends the match. A later resume attempt can fail because the host is gone, while the stale entry may continue to be offered.
- **Suggested fix:** Define offline completion semantics. Options include a durable server/session status that can be queried on rejoin, or explicitly treating stale offline rooms as reconnectable and removing them after a terminal host rejection. Do not claim immediate invalidation on offline devices without a mechanism that reaches them.
- **Retest:** Save a player room, disconnect that device, officially finish on the host, then relaunch/reconnect the player. Verify the room is either accurately marked pending/offline or removed after authoritative confirmation.

## BUG-05 — In-app help and About copy contradict current gameplay

- **Severity:** Low
- **Status:** Confirmed copy defect.
- **Locations:** `lib/ui/screens/guide_screen.dart:22-25, 49, 136-137` says a random/new letter is used; `lib/ui/screens/settings_screen.dart:66-71` describes the multiplayer app as a one-device game and uses ambiguous “entirely offline” wording.
- **Evidence:** Current domain source has no letter-selection phase (`GameSession.startNewRound` creates a round directly), and the game is multiplayer over a local network. The guide elsewhere correctly describes LAN, so the statements conflict within the app.
- **Cause:** User-facing copy was not updated with the current no-letter, LAN multiplayer rules.
- **Impact:** Players may prepare answers using a nonexistent letter rule or misunderstand device/network requirements.
- **Suggested fix:** Update the guide and About dialog to say that each phone joins the same local Wi-Fi/hotspot, no Internet/backend is used, and current rounds have no selected letter. Keep the meaning of “offline” precise.
- **Retest:** Add a source/widget copy check for prohibited stale letter/device claims and manually verify guide text on a device.

## BUG-06 — Protocol source comment documents the wrong version

- **Severity:** Low
- **Status:** Confirmed source-comment mismatch; runtime protocol is unaffected.
- **Location:** `lib/net/protocol.dart:1-4` versus `lib/domain/models.dart` (`kProtocolVersion = 3`).
- **Evidence:** The top comment and JSON example describe version 2, while serializer/parser use version 3.
- **Cause:** Comment/example not updated after the protocol version increment.
- **Impact:** Maintainers or external readers can implement incompatible messages based on the stale example; no runtime behavior change is implied.
- **Suggested fix:** Update the comment/example to v3 and keep the constant as the single source of truth.
- **Retest:** Documentation/source test or review that the example's `v` matches `kProtocolVersion`.

## BUG-07 — Lifecycle save is requested but not awaited

- **Severity:** Low (potential durability risk)
- **Status:** Confirmed source behavior; data-loss impact is unverified.
- **Locations:** `lib/app.dart:43-50`; persistence work is performed by `GameController.flush()` / `_persistNow()`.
- **Evidence:** Lifecycle callback invokes the asynchronous flush without awaiting or explicitly handling its Future. A `detached` callback can therefore return while file writes are still pending.
- **Cause:** The Flutter lifecycle callback is synchronous, while storage is asynchronous; completion is not tracked by the callback.
- **Impact:** If the OS terminates the process immediately, the latest snapshot may not finish writing. Normal pause behavior may provide enough time; no loss was reproduced.
- **Suggested fix:** Keep periodic/event-driven persistence as the primary guarantee; document the lifecycle write as best effort. Consider an explicit tracked flush/error path and avoid relying solely on `detached`.
- **Retest:** Instrument a delayed/failing store in tests and exercise background/force-stop/relaunch on representative Android versions. Verify the most recent completed snapshot is recoverable.

## BUG-08 — Lobby minimum counts roster entries, not connected players

- **Severity:** Low / requirement ambiguity
- **Status:** Source behavior confirmed; whether it is a defect depends on the intended lobby rule.
- **Locations:** `lib/ui/screens/lobby_screen.dart:74-80, 156-157`; `lib/domain/game_session.dart:237-255`; disconnected roster entries are retained by `GameController`.
- **Evidence:** The lobby and domain start checks use `players.length`. A round separately snapshots `connectedPlayerIds` into `activePlayerIdsAtStart`. A disconnected player remains in `players`, so a host can start when only the host is presently connected as long as a second roster entry remains.
- **Impact:** If “at least two players” means two currently participating devices, a one-device round can start unintentionally; Stop threshold then uses the smaller connected set. A previously joined player can reconnect after the round starts, so the intended semantics need to be explicit.
- **Suggested fix:** Decide whether minimum players means roster members or currently connected devices. If live participation is required, gate start on connected count; otherwise clarify this behavior in the lobby/help text and verify reconnect behavior during a round.
- **Retest:** In a two-player lobby, disconnect the non-host and attempt to start. Assert the chosen product rule, then reconnect during/after start and verify active-player and Stop-threshold behavior.

## Security and operational limitations (not classified as confirmed vulnerabilities)

- LAN messages are not protected by TLS. QR and open-join beacon data expose a bearer token to participants/devices that can read the local network traffic.
- Do not port-forward the game host or use it as an Internet-facing service. Keep QR codes and join credentials private.
- Static review did not identify application-level encryption for local JSON files. Android app sandboxing and disabled manifest backup reduce exposure but do not guarantee protection on a compromised/rooted device.
- No network penetration test, fuzzing campaign, or malicious-LAN threat model validation was performed.

## Review disposition

These items are documentation-only findings for this task. No code fixes were applied because the task explicitly restricts changes to documentation. Priorities and proposed follow-up work are in [Project Plan](PROJECT_PLAN.md).
