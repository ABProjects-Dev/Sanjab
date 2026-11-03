# Project Overview

**Updated:** 2026-11-03
**Active source branch:** `arena/0af07290-sanjab` (unreleased changes)
**Current published release:** Sanjab 1.0.1 (`versionCode` 7)

## Product

Sanjab is a Persian-language, category-based word game for two or more Android phones on the same Wi-Fi network or phone hotspot. One phone hosts the session and is authoritative for admission, round timing, game state, judging, and scoring. Other phones join over the local network. No cloud account, public game server, or Internet connection is required for a match.

The app is built with Flutter and Dart. It presents a right-to-left Persian UI with the bundled Vazirmatn font and a dark, portrait-oriented design. The native Android layer is small: Kotlin implements the platform channel used to keep the display awake during active game phases.

## Current source and release status

The repository's checked-in source is newer than the published 1.0.1 release. Its current `pubspec.yaml` version remains `1.0.1+7`; work after that release is recorded under **Unreleased** in the changelog and has not been assigned a new release version. The source includes durable saved-room persistence for both hosts and players, answer-length enforcement, network framing limits, snapshot acknowledgments/retries, and remote session-end navigation. See [Features](FEATURES.md) and [Project Status](PROJECT_STATUS.md).

| Item | Current source |
| --- | --- |
| Package | `com.sanjab.game` |
| Minimum Android API | 24 (Android 7.0) |
| Android version | `1.0.1` / version code `7` |
| Flutter app UI | Persian, RTL, dark theme, portrait |
| Match transport | IPv4 TCP and UDP on the local network |
| Backend | None |
| Android native code | Main activity and screen-awake method channel |
| Protocol | Private, strict-version JSON protocol, current version 4 |

The effective Android compile/target SDK values are supplied by Flutter Gradle defaults rather than explicitly pinned in this repository. The project has no checked-in iOS, web, Windows, macOS, or Linux application scaffold.

## Main user journeys

1. A player creates or edits the device-local profile name.
2. A host creates a session, shares a six-character join token or QR code, and may configure active categories/open joining in the lobby.
3. Other players discover the host, scan the QR code, or enter LAN address and token manually.
4. The host can start once at least two player records are in the lobby roster; the current start gate does not separately require each listed player to be connected. Players enter answers on their own phones.
5. The host closes the round by timer, stop threshold, or host action; clients deliver final answer snapshots; the host judges and finalizes scores.
6. Players can reconnect or resume persisted rooms. The host can start another round or officially finish the session.

Full, source-aligned mechanics are in [Game Rules](GAME_RULES.md).

## Repository map

```text
lib/
  app.dart, main.dart       App shell, lifecycle integration, startup/composition
  core/                     Theme, Persian formatting, logging, platform helpers
  data/                     Profile, host-session, and saved-room repositories
  domain/                   Game/session models, rules, categories, scoring
  net/                      TCP framing/protocol, host/client, UDP discovery
  state/                    GameController and widget-facing GameScope
  ui/                       Navigation, screens, and shared widgets
android/                    Android app configuration and Kotlin activity
assets/                     Fonts and app artwork
 test/                      Dart domain, network, storage, controller, and widget tests
integration_test/           One Android-device hosting-flow test
docs/                       Project, behavior, API, review, test, and release docs
.github/workflows/           Flutter checks and signed Android release workflows
```

## Engineering and quality posture

The domain layer is Flutter-independent and unit-testable. The production composition uses file-backed JSON repositories; tests can inject in-memory stores. Repository write operations are serialized per instance, session and room files use temporary files and backup recovery, and saved room history is capped at 20 entries. The app logger is bounded and avoids logging answer text by design.

The network is intentionally local-only, not an Internet-facing service. TCP/UDP traffic is not TLS-encrypted, and a QR/open-join beacon carries a bearer join token. Use a trusted local network and do not share those credentials publicly. This is a security boundary/limitation, not a claim that the app has been penetration-tested.

The active unreleased branch implements the source fixes for BUG-01 through BUG-08, with new regression tests. Flutter/Dart tests, analysis, and Android build have not yet run for this branch because the SDK is unavailable locally; merge is contingent on passing PR CI. Physical-device verification remains outstanding. See [Bug Report](BUG_REPORT.md) and [Project Status](PROJECT_STATUS.md).

## Build and verification

With a compatible Flutter SDK and Android toolchain, the normal local checks are:

```bash
flutter analyze
flutter test
flutter build apk --debug
```

The source tree contains 155 `test`/`testWidgets` declarations under `test/` and one device integration test under `integration_test/` (static count, not an execution result). The integration test covers host setup on one device; it does not simulate a complete two-phone match.

No GitHub Actions result exists yet for this branch's changes. The review environment has no local `flutter` or `dart` executable, so no local test, analyzer, or build command was run. A passing CI run for this branch is required before merge; it is not a substitute for physical-device LAN testing. See [Test Plan](TEST_PLAN.md) for coverage and gaps.

## Documentation

- [Documentation index](README.md)
- [Architecture](ARCHITECTURE.md)
- [Game rules](GAME_RULES.md)
- [Features and limitations](FEATURES.md)
- [Source analysis](SOURCE_ANALYSIS.md)
- [Bug report](BUG_REPORT.md)
- [Test plan](TEST_PLAN.md)
- [Project status and plan](PROJECT_STATUS.md) / [Project plan](PROJECT_PLAN.md)
- [Local network API](API.md)
- [Requirements and current behavior](REQUIREMENTS.md)
- [Android release builds](ANDROID_RELEASE.md)
