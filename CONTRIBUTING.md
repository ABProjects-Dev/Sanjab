# Contributing

## Before you start

- Read `AGENTS.md`; it holds the permanent project rules (documentation
  language, branch strategy, security, versioning, release policy).
- Source-controlled documentation, code comments, commit messages, branch
  names, issues, and pull requests are written in **English**. The app UI is
  Persian and stays Persian.

## Branch and commit rules

- Branch from `main` using `feature/*`, `fix/*`, `refactor/*`, or `docs/*`.
- Use Conventional Commits, for example `fix: reject duplicate display names on reconnect`.
- Never commit keystores, passwords, tokens, or `local.properties`.

## Local checks

```bash
python3 tool/sync_app_version.py --check   # app version matches pubspec.yaml
flutter pub get
flutter analyze
flutter test --coverage
flutter build apk --debug
```

The Gradle wrapper is tracked, so Android builds work with only a JDK and the
Android SDK:

```bash
cd android && ./gradlew --version
```

## Versioning

`pubspec.yaml` is the single source of the app version. After changing it, run:

```bash
python3 tool/sync_app_version.py
```

Commit the regenerated `lib/core/app_version.dart` together with the change;
CI fails if the two files disagree.

## Pull requests

Every pull request must state what changed, why, how it was verified (commands
and actual results), and any risk or breaking change. Do not merge with a red
CI run. Do not force-push shared branches.
