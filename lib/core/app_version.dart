/// Single source of truth for the version string shown inside the app.
///
/// This file is generated from `version:` in `pubspec.yaml` by
/// `tool/sync_app_version.py`, and the `flutter-checks` workflow fails when the
/// two drift apart. Do not edit the values by hand.
library;

/// Version name, matching `versionName` of the Android build.
const String kAppVersionName = '1.1.2';

/// Android build number, matching `versionCode` of the Android build.
const int kAppVersionCode = 11;

/// Version label used in screens and dialogs.
String get kAppVersionLabel => '$kAppVersionName+$kAppVersionCode';
