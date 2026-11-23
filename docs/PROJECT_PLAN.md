# Project Plan and Verification

**Updated:** 2026-11-04
**Active branch:** `main`
**Latest published release:** 1.0.2 (`versionCode` 8)
**Release candidate:** 1.1.2 (`versionCode` 11), pending publication

## Current remediation

The gameplay and room-lifecycle changes in PR #16 are merged. Regression tests, Dart analysis, and the Android debug build passed in GitHub Actions. The current change set prepares version 1.1.0; local Flutter/Dart commands remain unavailable in this environment.

## Acceptance criteria before release

- `flutter test`, `flutter analyze`, and the Android debug build pass in CI for the 1.1.2 PR.
- Initial join failure does not retry invisibly; established reconnect remains supported.
- Explicit exit is delivered separately from transport disconnect. Explicit exit removes roster membership; transient disconnect preserves it and allows reconnect.
- Mid-game explicit exit preserves historical answers/scores while excluding the player from later rounds and current pending snapshot/Stop threshold.
- Persisted explicit-exit state survives serialization; legacy records without the optional field still load.
- Offline room status remains explicitly unverified until authoritative host contact; no claim of remote terminal detection while disconnected.
- Discovery fallback is not described as per-interface broadcast; QR/manual join remain available.

## Device-level follow-up

- Test complete matches on at least two Android devices over standard Wi-Fi and hotspot networks.
- Verify discovery where limited broadcast is blocked and exercise QR/manual joining.
- Disconnect/reconnect a player during the lobby and during a round; compare with explicit room exit.
- Finish a host session while the player is offline, relaunch the player, and verify the unverified state resolves only after host contact.
- Exercise app backgrounding and process termination; lifecycle flush is best effort, not a durability guarantee.

## Release and maintenance

- Keep every published artifact unchanged; publish the 1.1.2+11 candidate only after CI and signed APK verification pass.
- Preserve the original signing key and publish the APK/checksum assets through the Android release workflow.
- Consider pinning the supported Flutter/Gradle/JDK toolchain and Android SDK targets for reproducibility.
- Add a full two-device integration environment when practical.

## Verification record

CI is green for the merged changes; the release build gate was added for 1.1.2. No physical-device network or lifecycle matrix has been run. See [Project Status](PROJECT_STATUS.md), [Bug Report](BUG_REPORT.md), and [Test Plan](TEST_PLAN.md).
