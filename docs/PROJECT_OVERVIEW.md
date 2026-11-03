# Project Overview

**Updated:** 2026-11-04
**Active source branch:** `arena/da68caee-sanjab` (1.1.0 release preparation)
**Latest published release:** Sanjab 1.0.2 (`versionCode` 8)
**Current release candidate:** Sanjab 1.1.0 (`versionCode` 9), pending publication

## Product

Sanjab is a Persian-language, category-based word game for Android that supports solo play and multiplayer over the same Wi-Fi network or phone hotspot. In multiplayer, one phone hosts the session and is authoritative for admission, round timing, game state, judging, and scoring; other phones join over the local network. No cloud account, public game server, or Internet connection is required.

The app is built with Flutter and Dart. It presents a right-to-left Persian UI with the bundled Vazirmatn font and a dark, portrait-oriented design. The native Android layer is small: Kotlin implements the platform channel used to keep the display awake during active game phases.

## Current source and release status

The repository's checked-in source includes the 1.1.0 release candidate (`pubspec.yaml` `1.1.0+9`) and its release notes are in `CHANGELOG.md`. The latest published APK is 1.0.2; publishing the 1.1.0 signed APK is pending PR checks and the Android release workflow. The source includes single-player starts, saved-room persistence, answer-length enforcement, network framing limits, snapshot acknowledgment/retry, explicit leave, resumed-room navigation, and color-coded player status. See [Features](FEATURES.md) and [Project Status](PROJECT_STATUS.md).

| Item | Current source |
| --- | --- |
| Package | `com.sanjab.game` |
| Minimum Android API | 24 (Android 7.0) |
| Android version | `1.1.0` / version code `9` candidate |
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
4. The host can start with at least one active player in the lobby roster. Players enter answers on their own phones.
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

The merged gameplay changes have passed Flutter tests, Dart analysis, and an Android debug build in GitHub Actions. Local checks remain unavailable because the editing environment has no Flutter/Dart SDK, and physical-device verification remains outstanding. The 1.1.0 version-bump PR is pending CI. See [Bug Report](BUG_REPORT.md) and [Project Status](PROJECT_STATUS.md).

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
