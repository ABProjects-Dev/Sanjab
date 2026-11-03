# Project Plan and Verification

**Updated:** 2026-11-03
**Active branch:** `arena/c87aff83-sanjab`
**Latest published release:** 1.0.1 (`versionCode` 7)
**Release candidate:** 1.0.2 (`versionCode` 8), pending publication

## Current remediation

BUG-01 through BUG-08 are implemented in the current unreleased branch. The scope, explicit-exit decision, and remaining limitations are recorded in [Bug Report](BUG_REPORT.md). Regression tests have been added but have not yet run locally because Flutter and Dart are absent from the editing environment.

## Acceptance criteria before merge

- `flutter test`, `flutter analyze`, and the Android debug build pass in CI for this exact PR.
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

- Keep the published 1.0.1 artifact unchanged; publish the 1.0.2+8 candidate only after CI and signed APK verification pass.
- Update the app version only in a separately reviewed release change.
- Consider pinning the supported Flutter/Gradle/JDK toolchain and Android SDK targets for reproducibility.
- Add a full two-device integration environment when practical.

## Verification record

No current-branch CI result exists yet. A prior successful workflow on another source baseline does not satisfy this PR's merge condition. See [Project Status](PROJECT_STATUS.md), [Bug Report](BUG_REPORT.md), and [Test Plan](TEST_PLAN.md).
