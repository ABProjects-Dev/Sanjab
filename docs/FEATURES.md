# Features and Limitations

Status reflects the active unreleased branch `arena/0af07290-sanjab` as of 2026-11-03. “Implemented” means present in source; it does not imply a physical-device test has passed.

## Implemented

### Game and UX

- Persian, right-to-left Flutter UI with Vazirmatn, fixed dark theme, and portrait orientation.
- Device-local profile and stable player identity; host lobby with player list, category selection, QR and join-token display, and optional open join.
- Thirteen categories and seven-minute rounds, with host pause/resume/end-round controls.
- Shared 80-grapheme-cluster answer ceiling across entry, domain, controller, and host validation; visible length feedback and rejected-input notice.
- Stop eligibility check across all active categories, per-player Stop deduplication, and a stop threshold based on the connected roster at round start.
- Host-side final-answer collection, manual judging, per-round scoring, cumulative totals, and tie-aware rankings.
- Explicit distinction between returning to Home while retaining a room and leaving/finishing a room.
- Results route reacts to authoritative session completion/reset and returns to the home route.
- Local technical-log viewer and bounded rotating file logs; logs are designed not to include answer contents.

### Local multiplayer and resilience

- IPv4 TCP host/client communication, newline-delimited JSON messages, UDP LAN discovery, QR join, and manual address/token entry.
- Host-authoritative session state; new admissions in the lobby; existing players can reconnect by stable player ID. Explicit room exit is a distinct protocol action; transient socket loss preserves membership, while explicit exit removes the player from active participation.
- Acknowledged/retried final answer snapshots, including resend after reconnect and idempotent acknowledgment of duplicates.
- Bounded TCP frames (256 KiB) and at most 32 pending host handshakes, with a 15-second handshake deadline.
- Preferred TCP port 50501 with an OS-assigned fallback; UDP discovery port 50507.
- Saved host session and durable saved-room records for either role. File-backed repositories use temporary replacement, backup recovery, serialized mutations per repository instance, and a 20-room cap.
- Android screen-awake platform channel during active game phases.

### Build and release

- Android application, minimum API 24; current app version is 1.0.1+7.
- GitHub Actions workflow for Flutter tests, analysis, and Android debug APK build.
- Separate manually dispatched signed Android release workflow with signing-certificate verification and APK/checksum upload.

## Constraints and explicit non-features

- Matches require participating phones on the same local network; the app does not set up a hotspot itself.
- No account service, cloud synchronization, remote game backend, public REST API, or Internet match mode is present.
- TCP/UDP traffic is not TLS-encrypted. The six-character join token is a bearer credential; QR data and open-join beacons can expose it to devices on the LAN.
- No application-level encryption of local JSON data was identified. Android app data is sandboxed; manifest backup is disabled, but that is not a substitute for cryptographic protection against a device compromise.
- No fully automated two-phone end-to-end match is present. The integration test covers one-device host setup only; real-network behavior needs physical-device testing.
- Effective compile/target SDK values are Flutter Gradle defaults rather than explicitly pinned project values.
- The published 1.0.1 APK predates some current-source fixes. The repository version remains 1.0.1+7; follow-up source changes are unreleased.

## Current limitations and verification gaps

- Flutter/Dart checks for the current branch are pending because the local editing environment has no SDK. Merge is contingent on passing PR CI.
- Automatic discovery uses limited broadcast only; some networks may block it, so QR/manual joining remain necessary fallbacks.
- An offline player cannot receive host session completion; the saved room remains explicitly unverified until authoritative host contact.
- Flutter lifecycle callbacks cannot be awaited by the OS; a lifecycle-triggered flush is best effort and not guaranteed to finish before abrupt process termination.
- No complete two-device Wi-Fi/hotspot matrix, lifecycle force-stop test, or network security assessment has been performed. See [Bug Report](BUG_REPORT.md) and [Test Plan](TEST_PLAN.md).
