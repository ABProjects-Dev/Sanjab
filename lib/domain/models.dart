/// Sanjab domain data models (multiplayer).
///
/// This library has no Flutter dependency, so game logic stays testable and
/// independent of the UI. The single source of truth is [GameSession] on the
/// host; other devices keep a synchronized copy.
library;

/// Network protocol version. Increase it whenever message shapes change.
const int kProtocolVersion = 4;

/// Fixed round duration: seven minutes (420 seconds).
const int kRoundDurationSeconds = 420;

/// Fixed round duration in milliseconds.
const int kRoundDurationMs = kRoundDurationSeconds * 1000;

/// Judgement state of one answer.
enum JudgementStatus {
  /// Not judged yet.
  unchecked,

  /// Confirmed (valid answer).
  confirmed,

  /// Duplicate, as decided manually by the referee.
  duplicate,

  /// Rejected.
  rejected,

  /// Empty field (the player entered nothing).
  empty,
}

/// Reason a round ended.
enum RoundEndReason {
  /// The seven-minute timer expired.
  timer,

  /// A player pressed Stop.
  playerStop,

  /// The host pressed Stop.
  hostStop,

  /// Manual host decision.
  referee,
}

/// Current game phase.
///
/// [collecting] means the round time is over and the host is gathering final
/// snapshots from every player.
enum GamePhase {
  /// Lobby: players are joining and the game has not started.
  lobby,

  /// A round is running and the timer is active.
  playing,

  /// The round is paused.
  paused,

  /// The round is over and final answers are being collected.
  collecting,

  /// Judging is active (host device only).
  judging,

  /// Round results are displayed.
  roundResults,

  /// The host formally ended the session.
  finished,
}

/// Submission state of one player in a round.
enum SubmissionState {
  /// Typing answers.
  typing,

  /// Stopped and sent the answers.
  stopped,

  /// The host acknowledged the answers.
  received,

  /// The player is disconnected.
  offline,
}

/// Device role in the session.
enum GameRole {
  /// No active session.
  none,

  /// Host: authoritative state owner.
  host,

  /// Joined player.
  player,
}

/// A player. The ID is stable and independent of the display name.
class Player {
  const Player({required this.id, required this.name, this.isHost = false});

  final String id;
  final String name;
  final bool isHost;

  Player copyWith({String? name, bool? isHost}) =>
      Player(id: id, name: name ?? this.name, isHost: isHost ?? this.isHost);

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'h': isHost};

  static Player fromJson(Map<String, dynamic> json) => Player(
    id: json['id'] as String,
    name: json['name'] as String,
    isHost: json['h'] as bool? ?? false,
  );
}

/// One answer: a player, a category and a round.
class AnswerEntry {
  const AnswerEntry({
    required this.playerId,
    required this.categoryId,
    required this.text,
    required this.status,
  });

  final String playerId;
  final int categoryId;
  final String text;
  final JudgementStatus status;

  /// A blank answer scores nothing and cannot be judged.
  bool get isBlank => text.trim().isEmpty;

  /// Unique answer key: round | player | category.
  static String keyOf(int roundIndex, String playerId, int categoryId) =>
      '$roundIndex|$playerId|$categoryId';

  AnswerEntry copyWith({String? text, JudgementStatus? status}) => AnswerEntry(
    playerId: playerId,
    categoryId: categoryId,
    text: text ?? this.text,
    status: status ?? this.status,
  );

  Map<String, dynamic> toJson() => {
    'p': playerId,
    'c': categoryId,
    't': text,
    's': status.name,
  };

  static AnswerEntry fromJson(Map<String, dynamic> json) => AnswerEntry(
    playerId: json['p'] as String,
    categoryId: (json['c'] as num).toInt(),
    text: json['t'] as String,
    status: JudgementStatus.values.firstWhere(
      (s) => s.name == json['s'],
      orElse: () => JudgementStatus.unchecked,
    ),
  );
}

/// Game configuration. The round duration is fixed; only the host chooses the
/// active categories, in the lobby.
class GameConfig {
  const GameConfig({required this.activeCategoryIds});

  /// Active category IDs in display order.
  final List<int> activeCategoryIds;

  /// Fixed round duration (always 420 seconds).
  int get roundDurationSeconds => kRoundDurationSeconds;

  int get roundDurationMs => kRoundDurationMs;

  GameConfig copyWith({List<int>? activeCategoryIds}) => GameConfig(
    activeCategoryIds: activeCategoryIds ?? this.activeCategoryIds,
  );

  Map<String, dynamic> toJson() => {'c': activeCategoryIds};

  static GameConfig fromJson(Map<String, dynamic> json) => GameConfig(
    activeCategoryIds: (json['c'] as List<dynamic>)
        .map((e) => (e as num).toInt())
        .toList(growable: false),
  );
}

/// Complete state of one round.
class RoundRecord {
  RoundRecord({
    required this.index,
    required this.startedAtEpochMs,
    required this.endEpochMs,
    Map<String, AnswerEntry>? answers,
    Set<String>? stoppedPlayerIds,
    Set<String>? receivedSnapshotPlayerIds,
    Set<String>? activePlayerIdsAtStart,
    this.pausedRemainingMs,
    this.endReason,
    this.judged = false,
    Map<String, int>? scores,
  }) : answers = answers ?? <String, AnswerEntry>{},
       stoppedPlayerIds = stoppedPlayerIds ?? <String>{},
       receivedSnapshotPlayerIds = receivedSnapshotPlayerIds ?? <String>{},
       activePlayerIdsAtStart =
           activePlayerIdsAtStart ?? <String>{},
       scores = scores ?? <String, int>{};

  /// Round number, starting at 1.
  final int index;

  final int startedAtEpochMs;

  /// Round end time on the host clock; the authoritative timer basis.
  int endEpochMs;

  /// Answers keyed by round|player|category.
  final Map<String, AnswerEntry> answers;

  /// Players who pressed Stop; their answers are locked.
  final Set<String> stoppedPlayerIds;

  /// Players whose final snapshot the host received and acknowledged.
  final Set<String> receivedSnapshotPlayerIds;

  /// IDs of players active when this round started (a snapshot).
  /// A later disconnect does not change the Stop threshold.
  final Set<String> activePlayerIdsAtStart;

  /// Stop threshold for ending the round: ceil(active players / 2).
  int get stopThreshold {
    final active = activePlayerIdsAtStart.length;
    if (active <= 0) return 1;
    return (active / 2).ceil();
  }

  /// Remaining milliseconds at pause time; null means not paused.
  int? pausedRemainingMs;

  RoundEndReason? endReason;

  /// Whether judging of this round is final.
  bool judged;

  /// Per-player score of this round after judging is finalized.
  final Map<String, int> scores;

  bool get isPaused => pausedRemainingMs != null;

  AnswerEntry? answerOf(String playerId, int categoryId) =>
      answers[AnswerEntry.keyOf(index, playerId, categoryId)];

  SubmissionState submissionOf(String playerId) {
    if (receivedSnapshotPlayerIds.contains(playerId)) {
      return SubmissionState.received;
    }
    if (stoppedPlayerIds.contains(playerId)) return SubmissionState.stopped;
    return SubmissionState.typing;
  }

  Map<String, dynamic> toJson() => {
    'i': index,
    'st': startedAtEpochMs,
    'en': endEpochMs,
    'a': answers.map((k, v) => MapEntry(k, v.toJson())),
    'sp': stoppedPlayerIds.toList(),
    'rs': receivedSnapshotPlayerIds.toList(),
    'as': activePlayerIdsAtStart.toList(),
    'pr': pausedRemainingMs,
    'er': endReason?.name,
    'j': judged,
    'sc': scores,
  };

  static RoundRecord fromJson(Map<String, dynamic> json) => RoundRecord(
    index: (json['i'] as num).toInt(),
    startedAtEpochMs: (json['st'] as num).toInt(),
    endEpochMs: (json['en'] as num).toInt(),
    answers: (json['a'] as Map<String, dynamic>).map(
      (k, v) => MapEntry(k, AnswerEntry.fromJson(v as Map<String, dynamic>)),
    ),
    stoppedPlayerIds: ((json['sp'] as List<dynamic>?) ?? const [])
        .map((e) => e as String)
        .toSet(),
    receivedSnapshotPlayerIds: ((json['rs'] as List<dynamic>?) ?? const [])
        .map((e) => e as String)
        .toSet(),
    activePlayerIdsAtStart: ((json['as'] as List<dynamic>?) ?? const [])
        .map((e) => e as String)
        .toSet(),
    pausedRemainingMs: (json['pr'] as num?)?.toInt(),
    endReason: json['er'] == null
        ? null
        : RoundEndReason.values.firstWhere(
            (r) => r.name == json['er'],
            orElse: () => RoundEndReason.referee,
          ),
    judged: json['j'] as bool? ?? false,
    scores: (json['sc'] as Map<String, dynamic>? ?? const {}).map(
      (k, v) => MapEntry(k, (v as num).toInt()),
    ),
  );
}

/// One standings row.
class Standing {
  const Standing({
    required this.playerId,
    required this.playerName,
    required this.totalScore,
    required this.rank,
  });

  final String playerId;
  final String playerName;
  final int totalScore;
  final int rank;
}
