# Game Rules

This document describes the rules implemented by the checked-in Dart domain code, not optional house rules. The authoritative implementation is in `lib/domain/game_session.dart`, `answer_rules.dart`, `categories.dart`, and `scoring.dart`.

## Match and lobby

- A match may have one or more players. One device is the host and source of truth, including in solo play.
- Players have a persistent device-local ID and a display name. Names must be non-empty, at most 24 Dart string code units, and unique after the game's normalization of whitespace, Persian/Arabic yeh and kaf, and zero-width non-joiner.
- New players can join in the lobby. Once a round has started, only an existing player ID may reconnect; new entrants are rejected.
- The host can remove a player only in the lobby and can select one or more active categories before a round or between rounds.
- The start gate requires at least one active roster member. Temporary transport disconnection does not remove a player from the roster or decrement this count; the player may reconnect. Explicit exit is a separate action: it removes the player in the lobby, or after a round starts preserves history while excluding the player from later rounds and the current Stop threshold.
- There is no chosen-letter or chosen-word step in the implemented rules. A round begins directly with active answer fields.

## Categories

The app defines 13 categories. Their stable IDs are 0 through 12; the display order/labels are defined in `lib/domain/categories.dart`.

| ID | Category |
| ---: | --- |
| 0 | Name |
| 1 | Family name |
| 2 | City |
| 3 | Country |
| 4 | Food |
| 5 | Fruit |
| 6 | Animal |
| 7 | Color |
| 8 | Occupation |
| 9 | Objects |
| 10 | Flower |
| 11 | Car |
| 12 | Body parts |

## Round lifecycle

The normal state flow is `lobby` → `playing` → `collecting` → `judging` → `roundResults`; another round can then begin. Other represented phases are `paused` and `finished`.

- Each round lasts 420 seconds (7 minutes). The duration is fixed, not user-configurable.
- The host's epoch deadline controls the timer. Clients use the host's reported time offset; client clocks do not decide when a round ends.
- The host may pause/resume or end the round manually. Timer expiry also ends it.
- A player may request **Stop** once per round only if every active category field passes the minimum-answer rule below.
- The stop threshold is `ceil(number of players connected at round start / 2)`. Temporary disconnections after the round starts do not lower that threshold; an explicit exit removes that player from the active threshold. At the threshold, the host ends the round.
- When a round ends, players send their final snapshots. The host waits for the required snapshots or an explicit host-side decision about an unavailable player before judging.
- Only the host judges answers. Every non-empty answer must have a judgement before scores can be finalized.

## Answer limits and Stop eligibility

Two distinct text rules apply:

1. **Maximum answer length:** no more than 80 user-perceived grapheme clusters. The UI, controller, domain, and host share this limit; typing/paste is constrained and over-limit network input receives a visible error rather than being silently accepted. The rule comes from `lib/domain/answer_rules.dart` and the `characters` package.
2. **Minimum for Stop:** every active answer must contain at least two valid Unicode code points after the rule removes whitespace, controls, zero-width characters, direction marks, and other configured invisible characters. Spaces do not count, including spaces inside an answer. This minimum is not a grapheme-cluster count.

Empty fields are allowed if the player does not request Stop; blank answers earn no points. A player can still end a round by timer or host action without every field being filled.

## Judging and scoring

Duplicate detection is manual: the host marks each non-empty answer confirmed, duplicate, or rejected. Blank answers are treated as empty.

| Answer state / category condition | Points |
| --- | ---: |
| Empty | 0 |
| Rejected | 0 |
| Duplicate | 5 |
| Confirmed, when not the sole confirmed answer | 10 |
| Sole confirmed answer, with at least one duplicate in the category | 15 |
| Sole confirmed answer, all other entries empty or rejected | 20 |

The 15- and 20-point unique-answer values replace the ordinary 10 points; they are not added to it. If more than one answer is confirmed in a category, no unique-answer bonus applies. Scores are accumulated across rounds; ties share rank.

## End and persistence

The host may officially finish the session. Connected clients receive a `sessionEnded` event and remove the local saved-room record. Host and player sessions are stored locally to support resume. An offline player cannot receive the end event; their saved room is shown as unverified until the host is contacted. If the host has shut down after finishing, an unsuccessful reconnect cannot prove completion, so the player may remove the stale room manually. Immediate offline invalidation is not possible without reconnection or a backend.

Further source-level feature details are in [Features](FEATURES.md); transport and message semantics are in [Local Network API](API.md).
