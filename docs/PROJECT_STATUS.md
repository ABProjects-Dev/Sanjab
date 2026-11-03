# Project Status

**As of:** 2026-11-03
**Active source branch:** `arena/0af07290-sanjab`
**Published release:** 1.0.1 (`versionCode` 7); current branch changes are unreleased.

## Summary

The active change set addresses BUG-01 through BUG-08 in [Bug Report](BUG_REPORT.md), including the clarified distinction between explicit room exit and temporary network loss. A dedicated protocol message handles explicit exit; transient disconnections keep roster membership. An offline client still cannot learn about host completion until it reconnects, and the UI now presents that state as unverified rather than terminal.

## Verification status

| Check | Result |
| --- | --- |
| Local `flutter test`, `flutter analyze`, Android build | **Not run:** Flutter and Dart SDK executables are not installed in this environment |
| New regression tests | Added for retry cancellation, explicit leave, transient disconnect/reconnect, roster semantics and persistence compatibility; **not yet executed** |
| GitHub Actions / PR CI | **Pending** for the current change set |
| Physical two-device Wi-Fi/hotspot and lifecycle checks | **Not run**; required where noted in the Bug Report and Test Plan |

A previous CI run on a different source baseline is not evidence for this patch. Merge is contingent on passing checks for the current PR.

## Remediation summary

- Failed initial joins no longer keep a hidden reconnect loop; client cleanup and rejected handshakes are covered by regression tests.
- Home create/resume flows return safely when their widget is disposed.
- The invalid per-interface discovery fallback was removed; limited broadcast plus QR/manual join remain.
- Offline player rooms are shown as unverified until the host can be contacted.
- Guide/About copy matches current local-network multiplayer and no-letter rules.
- Protocol documentation matches version 4, which adds the explicit-leave message.
- Lifecycle flush failures are observed and logged; completion remains best effort because Flutter lifecycle callbacks are synchronous.
- Explicit leave decrements active roster membership; transient disconnect does not. Mid-game exit retains history and scores while excluding the player from later participation.

## Security and release posture

- Local-network protocol has no TLS. Join tokens are bearer credentials; do not port-forward the host or use untrusted networks.
- Android release 1.0.1 is published; this patch has not been released.
- No network penetration test, physical-device network matrix, or force-stop durability test has been performed.

## Next steps

1. Run the complete Flutter tests, static analysis and Android debug build in CI.
2. Fix any failures and rerun checks before considering merge.
3. Verify discovery, explicit leave/reconnect, official finish while a client is offline, and lifecycle persistence on physical Android devices.
4. Keep the release version unchanged until a separately reviewed release is prepared.
