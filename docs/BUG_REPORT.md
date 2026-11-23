# Bug Report and Remediation Status

**Review date:** 2026-11-04
**Source baseline:** `3e699a4e6ff2c4d0ec1c9f96a7de1c49d70514d8`
**Status:** The gameplay remediations are merged in PR #16 and passed Flutter tests, Dart analysis, and an Android debug build in CI. Local SDKs are unavailable; physical-device verification remains outstanding.

## BUG-01 — Failed initial join could continue reconnecting in the background

**Status: Fixed in source; regression test added.** `GameClient` now schedules automatic retries only after at least one successful handshake. Rejected handshakes do not retry. Failed join setup closes and releases the client, and `joinGame` returns the controller to its non-session state. The network test asserts that an unreachable host leaves no pending retry.

## BUG-02 — Home screen could call `setState` after disposal

**Status: Fixed in source.** The create/resume callbacks now return immediately when the state is no longer mounted; they no longer call `setState` in the unmounted branch. Widget-level lifecycle verification remains part of CI/device review.

## BUG-03 — Discovery fallback sent probes to interface addresses, not broadcasts

**Status: Fixed by removing the incorrect fallback.** Dart's `NetworkInterface` API does not expose the IPv4 subnet mask needed to derive a directed broadcast reliably. Discovery retains the limited-broadcast probe; QR and manual address entry remain the documented fallback. No per-interface broadcast claim remains. Physical Wi-Fi/hotspot discovery still requires device testing.

## BUG-04 — An offline player's saved room could outlive official session completion

**Status: Mitigated and represented accurately; a fully offline client cannot be invalidated remotely.** The home screen now labels an offline player's room as unverified and explains that it cannot know whether the host ended the match or is temporarily unreachable. A reachable authoritative host can reject a terminal session and remove the stale room. If official completion has shut down the host, a later connection failure is still inconclusive and the saved room can remain until the player removes it manually. Connected players remove their room on the official end event. Immediate cleanup on a device that receives no message is impossible without a backend or a later authoritative contact.

## BUG-05 — Guide and About copy contradicted the current rules

**Status: Fixed in source.** The guide no longer describes random/new letters, and the About dialog now describes local-network multiplayer rather than a one-device or entirely offline app. The guide distinguishes temporary network loss from explicit room exit.

## BUG-06 — Protocol source comment documented the wrong version

**Status: Fixed and protocol intentionally incremented.** The header and example now agree with `kProtocolVersion = 4`. Version 4 adds a dedicated explicit-leave message; exact-version compatibility remains intentional.

## BUG-07 — Lifecycle save Future was unobserved

**Status: Fixed as best-effort lifecycle handling.** `app.dart` starts the flush promptly and observes/logs asynchronous failures. Flutter's lifecycle callback cannot be awaited by the OS, so this does not guarantee completion if the process is killed immediately; event-driven persistence remains the primary safeguard.

## BUG-08 — Roster membership did not distinguish explicit exit from transient disconnect

**Status: Clarified and implemented; regression tests added.** A new protocol `leave` message and separate host callback handle explicit room exit while connected. Explicitly leaving removes a lobby player, or after a round has begun preserves historical player/score data while removing the player from the active roster, current stop threshold, pending snapshots, and later rounds. A normal socket disconnect does not remove roster membership or decrement the player count; the same player can reconnect. If the device is offline, it cannot notify the host; the UI distinguishes local record deletion from a host-notified exit and advises reconnecting first. The persisted session and authoritative state carry the explicit-left set, with compatibility for snapshots that predate the new field.

## Verification still required

- The merged gameplay changes passed Flutter tests, Dart analysis, and the Android debug build in CI; the same gates run on every pull request.
- Exercise discovery and full gameplay on physical Android devices across Wi-Fi and hotspot configurations.
- Verify lifecycle persistence under backgrounding and process termination; no claim of guaranteed completion on force-stop is made.

## Security and operational limitations (not classified as confirmed vulnerabilities)

- LAN messages are not protected by TLS. QR and open-join beacon data expose a bearer token to participants/devices that can read local network traffic.
- Do not port-forward the game host or use it as an Internet-facing service. Keep QR codes and join credentials private.
- Static review did not identify application-level encryption for local JSON files. Android app sandboxing and disabled manifest backup reduce exposure but do not guarantee protection on a compromised/rooted device.
- No network penetration test, fuzzing campaign, or malicious-LAN threat model validation was performed.
