# Local Network API

## Scope and compatibility

This is the app's private local-network protocol, not a public HTTP/REST API. The host-authoritative TCP server and UDP discovery are implemented in `lib/net/`. Messages use JSON and the implementation constant `kProtocolVersion = 3` from `lib/domain/models.dart`.

Compatibility is exact-version: the parser rejects a message with a different protocol version. The leading comment in `lib/net/protocol.dart` still shows version 2; the runtime serializer/parser use version 3.

## Transports and endpoints

| Transport | Port | Purpose |
| --- | ---: | --- |
| TCP | 50501 preferred; otherwise OS-assigned | Player-to-host game connection |
| UDP | 50507 | Host discovery probes and announcements |

The host binds TCP to `0.0.0.0`/all IPv4 interfaces. TCP uses newline-delimited UTF-8 JSON. A `LineChannel` sends one serialized message followed by `\n` and parses each received line. `NetMessage.parse` limits a completed line to 256 × 1024 Dart string characters (the constant is named `kMaxMessageBytes`; the implementation checks `String.length`, not encoded UTF-8 byte length). This limit is applied after `LineSplitter` has assembled a line, not as an incremental socket-buffer cap.

## TCP message envelope

Every message has this shape:

```json
{
  "v": 3,
  "t": "answer",
  "id": "16-character-message-id",
  "q": 4,
  "p": {"r": 1, "c": 0, "t": "Example"}
}
```

| Field | Type | Meaning |
| --- | --- | --- |
| `v` | integer | Protocol version; must equal 3 |
| `t` | string | Exact `MsgType` enum name |
| `id` | string | Non-empty message ID, maximum length 64; generated IDs are 16 hexadecimal characters |
| `q` | non-negative integer | Per-channel sequence number |
| `p` | JSON object | Type-specific payload; defaults to an empty object if omitted/null |

The sender starts sequence numbers at 1. The receiver ignores duplicate message IDs (bounded deduper capacity 512) and non-increasing sequence numbers; ping messages are exempt from sequence ordering checks. Malformed, unknown-type, oversized, or version-incompatible messages are rejected by the parser. The channel discards parse-invalid lines without itself closing the TCP connection.

## TCP message types

### Handshake

1. An unauthenticated client must send `hello` first. A pending handshake is closed after 15 seconds.
2. The host validates the game ID, token, player ID and the app-level admission decision.
3. On success the host registers/replaces the player's active channel, sends `helloAck`, and then notifies the app so it can broadcast the current state to the newly registered client. Otherwise it sends `helloReject` and closes the channel.

| Type | Direction | Payload |
| --- | --- | --- |
| `hello` | Client → host | `gid`: game ID string; `token`: six-character join token; `pid`: stable player ID; `name`: display name |
| `helloAck` | Host → client | `pid`: player ID; `gid`: game ID; `resumed`: boolean; `serverNow`: host epoch milliseconds |
| `helloReject` | Host → client | `reason`: user-facing rejection string |

The host accepts an existing player ID as a reconnection. A new player is rejected once a round has begun. The host validates display-name uniqueness and other game rules in its callback.

### Game messages

| Type | Direction | Payload and behavior |
| --- | --- | --- |
| `state` | Host → one player | Authoritative state object described below. Each player receives only their own answer map, plus shared session information. |
| `answer` | Client → host | `r`: round index integer; `c`: category ID integer; `t`: answer text string. Host currently drops answer strings longer than 80 Dart string characters and validates phase/player/category in the domain. |
| `stop` | Client → host | `r`: round index integer. Host independently validates eligibility and duplicate stop state. |
| `snapshot` | Client → host | `r`: round index integer; `a`: object mapping category-ID strings to answer strings. Host ignores invalid category keys and values longer than 80 characters. |
| `snapshotAck` | Host → player | `r`: round index; `received`: boolean. Sent when a player's snapshot is applied; a duplicate retransmission for an already-received snapshot in the same round is acknowledged again without reapplying it. |
| `results` | Host → client (supported by client parser/handler) | Client applies this payload using the same authoritative-state handler as `state`. No current host send site for `results` was found; host round updates use `state`. |
| `sessionEnded` | Host → all connected players | `reason`: string; `gameId`: game ID. Clients detach and remove the saved room. |
| `error` | Host → player | `reason`: user-facing error string. |
| `ping` | Either direction (supported) | Empty/application-defined object. Host replies with `pong` and `serverNow`; protocol handler ignores ping sequence ordering. |
| `pong` | Either direction (supported) | Host response includes `serverNow`; currently no periodic client ping sender was found in the application flow. |

The client retains its final snapshot and retries it every two seconds until it receives a `snapshotAck` with `received: true` for the same round. A reconnect resends the pending snapshot immediately. The host treats same-round duplicates idempotently and repeats the acknowledgment, allowing recovery when the original acknowledgment was lost.

Host-side messages such as `state`, `snapshotAck`, `results`, `sessionEnded` and `error` are not accepted as client commands after handshake.

## Authoritative `state` payload

The host currently sends these fields:

| Key | Description |
| --- | --- |
| `seq` | Host state sequence counter |
| `serverNow` | Host's synchronized epoch time in milliseconds |
| `phase` | `GamePhase` enum name |
| `round` | Current round index, or 0 when no round exists |
| `endEpochMs` | Current round's host-clock end time, when available |
| `pausedRemainingMs` | Remaining time while paused, otherwise null |
| `endReason` | `RoundEndReason` enum name, when set |
| `judged` | Whether current round judging is finalized |
| `players` | Array of `{id, name, h, c}` for player ID, display name, host flag and connection flag |
| `cats` | Active category ID array |
| `totals` | Object mapping player IDs to cumulative score |
| `submissions` | Object mapping player IDs to current submission-state names |
| `my` | Object mapping active category ID strings to this recipient's answer text |
| `roundScores` | Current round's per-player scores |
| `pending` | Player IDs whose final snapshots have not been received/resolved |

The client applies host time offset from `serverNow`, builds/updates its local session snapshot and persists its local room state through the configured `RoomStore`.

## UDP discovery

The client sends the UTF-8 probe `SANJAB_DISCOVER_V2` to UDP port 50507 (broadcast and interface-specific addresses). A host answers probes and periodically broadcasts a JSON beacon:

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

Required parse fields are `k = "SM_HOST"`, non-empty `gid` and a port in 1–65535. `gn`, `hn`, `open`, `token`, and `pc` have defaults/optional handling. In open-join mode the beacon includes the token; otherwise the beacon omits it. Discovery can fail on networks that block broadcast; QR/manual joining is the fallback.

## QR join payload

The host UI encodes this JSON object for QR joining:

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

`createdAt` is the current device epoch time and `expiresAt` is seven days later. The structural validator requires `v = 1`, `type = "sm_join"`, non-empty `gameId`, `token` and `host`, a positive numeric port, and rejects a supplied expiry in the past. The host still validates the token during TCP handshake; a structurally valid QR alone does not authorize a connection.

## Security and operational notes

- TCP and UDP messages are not TLS-encrypted. Use this protocol only on a network trusted by the host and participants.
- The join token is a bearer credential. A QR contains it, and an open-join UDP beacon can expose it to devices on the same LAN. Do not publish QR images or beacon data publicly.
- The host checks the token and game ID and limits player ID length to 40. The protocol is not a hardened Internet-facing service; avoid port forwarding or exposing the host outside the local network.
- No external service or REST endpoint is used by the game protocol.

## Implementation caveats from static review

- Because the size check runs after line splitting, a peer that sends a long unterminated TCP line may consume memory until the socket is closed. The 15-second handshake timeout does not impose an incremental line-length cap or a global pending-socket limit.
- Host answer and snapshot values longer than 80 Dart string characters are silently dropped. The current play-screen text fields do not enforce that same limit, so an overlength answer can appear locally but be absent on the host.
- Initial state is now broadcast by the app callback after the host registers the accepted channel. Completion and message handlers for a replaced socket check channel identity so they cannot remove or operate on the replacement.
- Final snapshots are retried every two seconds until a matching acknowledgment arrives; reconnects resend pending snapshots, and the host re-acknowledges an already-applied same-round snapshot. These code paths have regression tests, but they still need execution in CI and physical-device verification.

These are source-review findings; they have not all been reproduced with network fault injection.
