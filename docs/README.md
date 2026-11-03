# Documentation Index

All technical documentation in this repository is maintained in English. Review date for this set: 2026-11-04.

- [Project Overview](PROJECT_OVERVIEW.md) — scope, platform, current source/release status, repository map.
- [Architecture](ARCHITECTURE.md) — runtime composition, layers, state and persistence/network flow.
- [Game Rules](GAME_RULES.md) — current implemented round, Stop, judging, and scoring rules.
- [Features and Limitations](FEATURES.md) — implemented functionality, boundaries, and non-features.
- [Source Analysis](SOURCE_ANALYSIS.md) — static review of design, reliability, security, compatibility, and testing.
- [Bug Report](BUG_REPORT.md) — evidence-based findings, severity, suggested fixes, and retest steps.
- [Test Plan](TEST_PLAN.md) — test inventory, recorded CI, commands, and manual/device coverage gaps.
- [Project Status](PROJECT_STATUS.md) — concise current status and recommended next steps.
- [Project Plan](PROJECT_PLAN.md) — prioritized follow-up acceptance criteria and completed source work.
- [Requirements and Current Behavior](REQUIREMENTS.md) — user flows, constraints, persistence, and verification status.
- [Local Network API](API.md) — TCP/UDP protocol, discovery, QR, and security boundaries.
- [Android Release Builds](ANDROID_RELEASE.md) — signed release workflow, secrets, and artifact verification.

`SOURCE_ANALYSIS.md` is explicitly a historical review of the pre-remediation baseline. `PROJECT_STATUS.md`, `PROJECT_PLAN.md`, `REQUIREMENTS.md`, and `ARCHITECTURE.md` describe the active 1.1.0 release candidate. CI passed for the merged gameplay changes; the version-bump PR is pending checks. Static review and CI are not substitutes for physical-device or two-phone verification.
