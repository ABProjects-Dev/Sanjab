# Project Plan and Prioritized Follow-up

**Updated:** 2026-11-03
**Source baseline:** `f6fb21168b138c02b523ffa0526a5a253caf8d4a`
**Current published release:** 1.0.1 (`versionCode` 7)

This is a source-review follow-up plan, not a claim that the listed items have been fixed. Current code changes after 1.0.1 remain under **Unreleased** in `CHANGELOG.md`.

## P1 — Fix first-join retry lifecycle

**Status:** Open — see [Bug Report](BUG_REPORT.md) for evidence and retest details.

Acceptance criteria:
- Failed initial connection and explicit rejection stop retry attempts and dispose/clear the first-join client, unless late reconnect is intentionally exposed in UI.
- Established-client reconnect behavior remains available.
- Tests cover unreachable host, rejected token, and any intentional late-success route behavior.

## P1 — Correct async widget disposal handling

**Status:** Open — see [Bug Report](BUG_REPORT.md) for evidence and retest details.

Acceptance criteria:
- No `setState` is called after `mounted` becomes false in create/resume flows.
- Widget tests dispose the route while each awaited controller action is pending and assert no framework exception.

## P1 — Make session completion observable to offline players

**Status:** Open — see [Bug Report](BUG_REPORT.md) for evidence and retest details.

Acceptance criteria:
- Define whether an offline client's saved room is pending, terminal, or reconnectable after host completion.
- A returning player does not see a permanently misleading “resume” item.
- Two-device test covers host finish while the client is disconnected and client app is restarted.

## P1 — Validate LAN discovery fallback

**Status:** Open — see [Bug Report](BUG_REPORT.md) for evidence and retest details.

Acceptance criteria:
- Per-interface destinations are actual IPv4 subnet broadcast addresses or the fallback is accurately removed/documented.
- Unit tests validate address/mask calculation; physical devices verify global-broadcast-restricted Wi-Fi/hotspot behavior.
- QR and manual join remain available when discovery fails.

## P2 — Align user-facing guide and source comments

**Status:** Open — BUG-05 and BUG-06 in [Bug Report](BUG_REPORT.md).

Acceptance criteria:
- Guide accurately states no letter is selected, explains LAN/hotspot multiplayer, answer and Stop rules, and avoids ambiguous “offline” wording.
- About dialog describes a multiplayer local-network app, not a one-device game.
- `protocol.dart` example and comment use the runtime version constant's value (currently 3).
- A widget/source test guards against stale letter-selection copy and protocol version mismatch.

## P2 — Clarify minimum players in a disconnected lobby

**Status:** Requirement clarification needed — see [Bug Report](BUG_REPORT.md).

Acceptance criteria:
- Decide whether the minimum two players means roster entries or devices connected at start.
- If connected players are required, use that count consistently in lobby UI and domain validation; otherwise document the reconnect semantics.
- Test disconnect-before-start and reconnect-during-round behavior.

## P2 — Validate lifecycle persistence and error recovery

**Status:** Needs device verification — see [Bug Report](BUG_REPORT.md) for evidence and retest details.

Acceptance criteria:
- Determine whether pause/detach flush completes reliably on supported Android versions.
- Keep periodic/event-driven saves as primary; test immediate background/termination and relaunch with delayed/failing storage.
- Ensure persistence failures become observable without leaking player answers into logs.

## P2 — Improve release reproducibility and maintainability

- Decide and document supported Flutter/Gradle/JDK versions and pin Android compile/target SDKs if reproducibility requires it.
- Use one maintained app-version source instead of repeated UI literals.
- Consider decomposing the ~1,727-line `GameController` by use case (session, network, persistence/lifecycle) without changing behavior; add tests before refactoring.
- Add two-device network integration coverage, especially discovery, disconnection/reconnect, app backgrounding, and host completion.

## Completed source work (present at reviewed baseline)

- File-backed saved-room records are wired in the production controller factory and survive controller restart.
- Session/room mutations are serialized per repository instance.
- TCP frame size and pending handshake count/time are bounded.
- Final snapshots use acknowledgment, retry, reconnect resend, and duplicate-safe acknowledgment.
- The 80-grapheme answer ceiling is enforced in UI/domain/controller/host paths with visible errors.
- Results route handles remote official finish/reset and returns to home.
- Launcher/home/play squirrel branding is aligned.

These items are source findings and have targeted regression tests; the latest checked-in baseline also passed the GitHub Actions Flutter checks below. They are not all part of the already-published 1.0.1 binary.

## Verification record

- Published releases: [1.0.1](https://github.com/behrouzxp-dev/Sanjab/releases/tag/1.0.1) and [1.0.0](https://github.com/behrouzxp-dev/Sanjab/releases/tag/1.0.0).
- GitHub Actions run [41651598932](https://github.com/behrouzxp-dev/Sanjab/actions/runs/41651598932) completed successfully on reviewed SHA `f6fb21168b138c02b523ffa0526a5a253caf8d4a` (tests, analysis, Android debug build workflow).
- No local checks or physical-device/two-phone tests were run in this review because local Flutter/Dart executables are unavailable. See [Test Plan](TEST_PLAN.md).
