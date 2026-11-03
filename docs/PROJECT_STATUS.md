# Project Status

**As of:** 2026-11-03
**Reviewed source baseline:** `f6fb21168b138c02b523ffa0526a5a253caf8d4a`
**Published release:** 1.0.1 (`versionCode` 7)

## Summary

Sanjab is a functional Android/Flutter local-network multiplayer game. The current source includes the recent persistence, protocol framing, answer-length, snapshot retry, and results-routing changes. The published GitHub Release remains 1.0.1; the source still reports `1.0.1+7`, and later changes are unreleased.

This status is based on source/configuration and recorded CI metadata. No physical-device LAN run was performed in this review. No local tests/analyzer/build were run because Dart and Flutter SDK executables are absent from the environment.

## Verification record

| Check | Result | Evidence / scope |
| --- | --- | --- |
| GitHub Actions Flutter checks | **Passed** | Run [41651598932](https://github.com/behrouzxp-dev/Sanjab/actions/runs/41651598932), completed 2026-11-03 on the exact reviewed baseline SHA; workflow includes tests, analysis and Android debug APK build |
| Local `flutter test` / `flutter analyze` / build | **Not run** | `flutter` and `dart` are not installed in the review environment |
| Static test inventory | **Counted** | 144 declarations in `test/` + one integration declaration; this count is not a test result |
| Two-device LAN gameplay | **Not verified in this review** | Existing integration test is single-device host setup; see [Test Plan](TEST_PLAN.md) |
| Physical Android lifecycle/network matrix | **Not run** | Required for device-specific discovery, reconnect, and persistence findings |

## Confirmed completed source work

- Production controller composition injects a file-backed `RoomRepository`; host and player room data can be stored and resumed.
- Session and room repository writes are serialized within each repository instance; bounded TCP framing and pending-handshake limits are present.
- Answer maximum is enforced as 80 grapheme clusters; Stop minimum validation is shared across UI/domain/host.
- Final answer snapshots use positive acknowledgments, retry, reconnect resend, and duplicate-safe acknowledgment.
- Results UI listens for authoritative session end/reset and returns to the home route.
- Android release 1.0.1 is published and its release workflow validates APK signing.

These statements describe source and release metadata; “completed” does not mean every path was independently reproduced during this documentation review.

## Open findings

The detailed evidence, severity and retest instructions are in [Bug Report](BUG_REPORT.md):

1. **Medium:** initial join failure may leave automatic reconnect active while the join route reports failure (BUG-01).
2. **Medium:** HomeScreen calls `setState` after an unmounted check on create/resume paths (BUG-02).
3. **Medium:** interface-specific host-discovery fallback targets local interface addresses rather than broadcast addresses (BUG-03).
4. **Medium:** an offline player's saved room may outlive official host completion (BUG-04).
5. **Low:** guide/About text is stale or contradictory (BUG-05).
6. **Low:** protocol source comment says v2 while runtime is v3 (BUG-06).
7. **Low / needs device verification:** lifecycle flush is not awaited (BUG-07).
8. **Low / requirement clarification:** lobby start eligibility counts roster entries, not live connections (BUG-08).

No executable fixes were made because this task allows documentation-only changes.

## Security and release posture

- Local-network-only protocol; no TLS. Join token is a bearer credential; QR/open-join discovery can expose it on the LAN.
- Do not expose the host through port forwarding or untrusted networks.
- Android minimum API is 24. Compile/target SDK values are inherited from Flutter Gradle defaults rather than pinned.
- Release signing secrets are consumed by the GitHub Actions release workflow; never store them in source or public documentation.

## Recommended next steps

1. Address BUG-01 and BUG-02 with focused lifecycle/retry regression tests.
2. Correct/test per-interface UDP broadcast and validate discovery on actual Wi-Fi/hotspot devices.
3. Decide and implement offline-client completion semantics; test stale room behavior.
4. Update in-app guide/About copy and protocol version comment.
5. Test lifecycle persistence and run a complete two-device network matrix before the next release.
6. Decide whether to pin supported Flutter/Android toolchain and SDK targets before cutting a new release.

See [Project Plan](PROJECT_PLAN.md) for prioritized acceptance criteria and [Android Release Builds](ANDROID_RELEASE.md) for release procedure.
