#!/usr/bin/env python3
"""Generate lib/core/app_version.dart from the version in pubspec.yaml.

Usage:
    python3 tool/sync_app_version.py           # write the generated file
    python3 tool/sync_app_version.py --check   # exit 1 if the file is stale

The CI `Flutter checks` workflow runs the --check mode so the in-app version
can never drift away from the published package version.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PUBSPEC = ROOT / "pubspec.yaml"
TARGET = ROOT / "lib" / "core" / "app_version.dart"

TEMPLATE = """/// Single source of truth for the version string shown inside the app.
///
/// This file is generated from `version:` in `pubspec.yaml` by
/// `tool/sync_app_version.py`, and the `flutter-checks` workflow fails when the
/// two drift apart. Do not edit the values by hand.
library;

/// Version name, matching `versionName` of the Android build.
const String kAppVersionName = '{name}';

/// Android build number, matching `versionCode` of the Android build.
const int kAppVersionCode = {code};

/// Version label used in screens and dialogs.
String get kAppVersionLabel => '$kAppVersionName+$kAppVersionCode';
"""


def read_version() -> tuple[str, int]:
    text = PUBSPEC.read_text(encoding="utf-8")
    match = re.search(r"(?m)^version:\s*(\S+)\s*$", text)
    if not match:
        raise SystemExit("pubspec.yaml has no 'version:' line")
    raw = match.group(1).strip().strip('"')
    if "+" not in raw:
        raise SystemExit(f"version '{raw}' is not MAJOR.MINOR.PATCH+BUILD")
    name, code = raw.split("+", 1)
    if not re.fullmatch(r"\d+\.\d+\.\d+", name) or not code.isdigit():
        raise SystemExit(f"version '{raw}' is not MAJOR.MINOR.PATCH+BUILD")
    return name, int(code)


def render() -> str:
    name, code = read_version()
    return TEMPLATE.format(name=name, code=code)


def main() -> int:
    expected = render()
    if "--check" in sys.argv[1:]:
        if not TARGET.exists():
            print(f"{TARGET.relative_to(ROOT)} is missing; run tool/sync_app_version.py")
            return 1
        actual = TARGET.read_text(encoding="utf-8")
        if actual != expected:
            print(
                f"{TARGET.relative_to(ROOT)} is out of date with pubspec.yaml; "
                "run: python3 tool/sync_app_version.py"
            )
            return 1
        print("app version is in sync with pubspec.yaml")
        return 0

    TARGET.parent.mkdir(parents=True, exist_ok=True)
    TARGET.write_text(expected, encoding="utf-8")
    name, code = read_version()
    print(f"wrote {TARGET.relative_to(ROOT)} => {name}+{code}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
