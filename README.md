# Sanjab

Sanjab is a Persian-language, category-based word game for Android. It supports solo play and multiplayer over a shared local Wi-Fi network or phone hotspot. In multiplayer, one phone hosts the authoritative game session and others join over the LAN; a public Internet connection or remote game server is not required.

## Release and source status

| Item | Value |
| --- | --- |
| Latest published release | `1.1.1` |
| Checked-in app version | `1.1.2+11` (`versionCode` 11) — release candidate |
| Android package | `com.sanjab.game` |
| Minimum Android | API 24 (Android 7.0) |
| UI | Persian, right-to-left, dark theme, portrait, Vazirmatn |
| Network | Local IPv4 TCP/UDP; no cloud backend |

The repository source identifies the 1.1.2 release candidate (`versionCode` 11) in `CHANGELOG.md`. The Android app version is derived from `pubspec.yaml` (`versionName` and `versionCode` in Gradle, and `lib/core/app_version.dart` for the in-app label), so no version literal is duplicated by hand. Publishing the signed APK is pending the Android release workflow. See [Project Status](docs/PROJECT_STATUS.md).

## Features

- Host/join over a shared Wi-Fi network or hotspot, with LAN discovery, six-character join token, QR code, or manual address entry.
- 13 categories, fixed seven-minute rounds, no letter-selection step, solo starts, and host-authoritative timer/judging/scoring for multiplayer.
- Answer input capped at 80 user-perceived grapheme clusters; Stop requires every active category field to contain at least two valid characters.
- Player reconnect, final-answer snapshot acknowledgment/retry, and persistent host/player room records.
- Local profile, score totals, saved-room resume, local technical logs, and Android screen-awake behavior during play.

Read [Game Rules](docs/GAME_RULES.md) for full scoring and round behavior. The local-network protocol is not TLS-encrypted; join tokens are bearer credentials. Use a trusted LAN and do not publish QR codes or open-join beacon data.

## Repository layout

```text
lib/                  Flutter/Dart app, domain, state, storage and networking
android/              Android application and native platform bridge
assets/               Fonts and artwork
test/                 Domain, networking, controller, storage and widget tests
integration_test/     One Android-device host-flow integration test
docs/                 Project, architecture, rules, API, review and release docs
.github/workflows/     Flutter checks and Android release workflows
```

## Development and verification

With a compatible Flutter/Android toolchain:

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

The Flutter test suite, Dart analysis, and Android debug APK build run in GitHub Actions for every push and pull request, and the release build has its own manually dispatched workflow. The integration test covers host setup on one device, not a complete two-phone match; physical-device LAN behavior still needs verification.

The Gradle wrapper scripts (`gradlew`, `gradlew.bat`, `gradle/wrapper/gradle-wrapper.jar`) are tracked, so a local build needs only a JDK and the Android SDK. See [Android Release Builds](docs/ANDROID_RELEASE.md) for signed APK publication and checksum verification.

## Documentation

Start at the [documentation index](docs/README.md). Key documents:

- [Project overview](docs/PROJECT_OVERVIEW.md) and [architecture](docs/ARCHITECTURE.md)
- [Game rules](docs/GAME_RULES.md) and [features/limitations](docs/FEATURES.md)
- [Source analysis](docs/SOURCE_ANALYSIS.md) and [bug report](docs/BUG_REPORT.md)
- [Test plan](docs/TEST_PLAN.md) and [project status](docs/PROJECT_STATUS.md)
- [Local Network API](docs/API.md), [requirements](docs/REQUIREMENTS.md), and [release guide](docs/ANDROID_RELEASE.md)
