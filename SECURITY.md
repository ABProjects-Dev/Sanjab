# Security Policy

## Supported versions

Only the latest published release receives security fixes.

| Version | Supported |
| --- | --- |
| 1.1.x | Yes |
| < 1.1 | No |

## Reporting a vulnerability

Do not open a public issue for a security report. Contact the maintainers
privately (GitHub private vulnerability reporting on this repository, or the
owner account) with:

- the affected version and Android version,
- steps to reproduce,
- the expected and observed behavior,
- any relevant log excerpts **without** player answers or personal data.

You will receive an acknowledgement, an assessment, and a coordinated
disclosure timeline. Please do not publish details before a fix is released.

## Known design limitations

Sanjab is a local-network game with no server component. Traffic between the
host and the players is **not TLS-encrypted** and the six-character join token
is a bearer credential. Run matches only on a trusted Wi-Fi network or hotspot,
and do not forward the game port or expose it to the Internet.

These are documented product constraints, not vulnerabilities. Reports are
still welcome if a documented limitation can be escalated (for example, a way
to read answer data or take over a session without being on the local network).
