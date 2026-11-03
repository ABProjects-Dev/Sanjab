# Local Network API

**Updated:** 2026-11-03; active source branch `arena/c87aff83-sanjab`.

This is Sanjab's private local-network protocol, not a public REST/HTTP API. The host is authoritative. Protocol implementation is under `lib/net/`; `kProtocolVersion` is 4 in `lib/domain/models.dart`.

## Transports

| Transport | Port | Purpose |
| --- | ---: | --- |
| TCP | 50501 preferred; OS-assigned fallback | Host-client gameplay |
| UDP | 50507 | Discovery probe and host beacon |

TCP binds to all IPv4 interfaces and carries newline-delimited UTF-8 JSON. `LineChannel` counts incoming raw bytes incrementally and closes a connection when an unterminated frame exceeds 256 KiB. Completed messages are also checked by UTF-8 byte length. The host permits at most 32 sockets pending hello and limits a pending handshake to 15 seconds.

## Message envelope

```json
{
  "v": 4,
  "t": "answer",
  "id": "16-character-message-id",
  "q": 4,
  "p": {"r": 1, "c": 0, "t": "Example"}
}
```

| Field | Meaning |
| --- | --- |
| `v` | Exact protocol version; current value is 4 |
| `t` | Message type (`MsgType` name) |
| `id` | Non-empty message ID, maximum 64 characters; generated ID is 16 hex characters |
| `q` | Non-negative per-channel sequence number |
| `p` | Type-specific JSON object |

Sequence starts at 1. The receiver deduplicates message IDs (bounded capacity 512) and rejects non-increasing sequence numbers; ping is exempt from sequence ordering. Unknown type, malformed JSON, incompatible version, and over-limit frames are not accepted. Parse-invalid complete lines are discarded by the channel without automatically closing the socket.

The header comment/example and runtime encoding/decoding use version 4. Version 4 adds the dedicated `leave` message; the protocol continues to reject mismatched versions.

## Handshake and gameplay messages

A client first sends `hello`. The host validates game ID, token, player ID and game rules; accepted sockets are registered before the app broadcasts initial state. Existing player IDs can reconnect; a new player is not admitted after the lobby phase.

| Type | Direction | Payload / behavior |
| --- | --- | --- |
| `hello` | Client → host | `gid`, `token`, `pid`, `name` |
| `helloAck` | Host → client | `pid`, `gid`, `resumed`, `serverNow` |
| `helloReject` | Host → client | User-readable `reason` |
| `state` | Host → one player | Current authoritative state (keys below); answer map is recipient-specific |
| `answer` | Client → host | `r` round, `c` category, `t` text; host validates phase/player/category and 80-grapheme-cluster limit |
| `stop` | Client → host | `r` round index; host independently checks Stop eligibility and duplicate state |
| `leave` | Client → host | Explicit room exit; distinct from transport loss. Host removes lobby membership or records a mid-game departure while preserving history |
| `snapshot` | Client → host | `r` round; `a` map from category ID strings to answer text; host validates fields/lengths |
| `snapshotAck` | Host → player | `r`, `received`; positively acknowledges accepted snapshot |
| `results` | Host → client | Supported by client parser/handler, but no current host send site was found; host uses `state` updates |
| `sessionEnded` | Host → connected clients | `reason`, `gameId`; client removes its saved room after receiving it |
| `error` | Host → player | User-readable `reason` |
| `ping` / `pong` | Either direction | Supported protocol messages; no periodic application client ping sender was found |

The client retains a pending final snapshot and retries every two seconds until it receives a matching positive acknowledgment. On reconnect it resends the snapshot. The host re-acknowledges an already-applied same-round duplicate without applying it twice. Host-only messages are not accepted as client commands.

## Authoritative `state` payload

| Key | Description |
| --- | --- |
| `seq` | Host state sequence counter |
| `serverNow` | Host synchronized epoch milliseconds |
| `phase` | Current `GamePhase` name |
| `round` | Round index, or 0 when no round exists |
| `endEpochMs`, `pausedRemainingMs`, `endReason` | Timer/end metadata when applicable |
| `judged` | Whether current round is finalized |
| `players` | Entries `{id, name, h, c}` for ID/name/host/connected status |
| `cats` | Active category ID list |
| `totals` | Cumulative score by player ID |
| `submissions` | Submission state by player ID |
| `my` | This recipient's active-category answer text only |
| `roundScores` | Current per-player round scores |
| `pending` | Player IDs whose final snapshots are still pending/unresolved |

Client derives a clock offset from `serverNow`, applies host state and persists its local room record.

## UDP discovery

The client sends `SANJAB_DISCOVER_V2` to UDP port 50507 using IPv4 limited broadcast. No per-interface directed-broadcast fallback is attempted because the Dart API does not expose subnet masks. Hosts respond and periodically announce JSON beacons of this form:

```json
{
  "k": "SM_HOST",
  "gid": "game-id",
  "gn": "game name",
  "hn": "host name",
  "port": 50501,
  "open": true,
  "token": "ABC234",
  "pc": 2
}
```

A valid beacon requires `k = "SM_HOST"`, non-empty `gid`, and a port in 1–65535. In open-join mode the beacon contains the token; otherwise it omits it. Networks that block limited broadcast may not support automatic discovery; QR/manual joining are the documented alternatives.

## QR payload

```json
{
  "v": 1,
  "type": "sm_join",
  "gameId": "game-id",
  "host": "192.168.1.10",
  "port": 50501,
  "token": "ABC234",
  "hostName": "Host",
  "createdAt": 0,
  "expiresAt": 604800000
}
```

QR data includes the bearer token. The parser validates expected type/version, game ID, host, positive port, token, and rejects an expiry in the past. The host still validates the token during TCP handshake.

## Security and reliability notes

- TCP/UDP are not TLS-encrypted. Do not use the service as an Internet-facing server or forward its port.
- A six-character join token is a bearer credential. Protect QR images and open-join beacon data.
- The network code is intended for trusted local networks; this is not a hardened public protocol and has not undergone a penetration test.
- Initial connection failure does not retry in the background; automatic reconnect is reserved for an established session.
- Official session-end is sent to connected players only. An offline player's saved room remains explicitly unverified until authoritative host contact; immediate remote invalidation is impossible without reconnection or a backend.
- Current answer limit is 80 user-perceived grapheme clusters. The separate Stop minimum counts valid code points after invisible/spacing normalization; see [Game Rules](GAME_RULES.md).

All issues above are source-review findings. Runtime impact requiring Wi-Fi/device behavior is not represented as reproduced. See [Bug Report](BUG_REPORT.md) and [Test Plan](TEST_PLAN.md).
