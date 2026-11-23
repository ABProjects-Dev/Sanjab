/// Complete, authoritative game state (domain logic, no Flutter dependency).
///
/// On the **host** device this class is the authoritative state; clients hold
/// a synchronized copy (host-authoritative model).
/// All changes go through this class, and the timer is based on real
/// timestamps rather than accumulated ticks.
library;

import 'answer_rules.dart';
import 'categories.dart';
import 'models.dart';
import 'scoring.dart';

/// Normalize a name for uniqueness checks (spacing and Arabic/Persian letters).
String normalizeName(String value) {
  final buffer = StringBuffer();
  var lastSpace = true;
  for (final rune in value.trim().runes) {
    var ch = String.fromCharCode(rune);
    if (ch == 'ي' || ch == 'ى') ch = 'ی';
    if (ch == 'ك') ch = 'ک';
    if (ch == '\u200c') ch = ' ';
    if (ch.trim().isEmpty) {
      if (!lastSpace) {
        buffer.write(' ');
        lastSpace = true;
      }
    } else {
      buffer.write(ch);
      lastSpace = false;
    }
  }
  return buffer.toString().trim();
}

/// Game rule violation with a user-facing Persian message.
class GameRuleException implements Exception {
  GameRuleException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Authoritative game state.
class GameSession {
  GameSession({
    required this.config,
    List<Player>? players,
    List<RoundRecord>? rounds,
    Map<String, int>? totals,
    Set<String>? connectedPlayerIds,
    Set<String>? leftPlayerIds,
    this.phase = GamePhase.lobby,
    this.playerSeq = 0,
    this.gameId = '',
    this.hostPlayerId = '',
    this.createdAtEpochMs = 0,
    this.savedAtEpochMs = 0,
  }) : players = players ?? <Player>[],
       rounds = rounds ?? <RoundRecord>[],
       totals = totals ?? <String, int>{},
       connectedPlayerIds = connectedPlayerIds ?? <String>{},
       leftPlayerIds = leftPlayerIds ?? <String>{};

  /// Persisted schema version.
  static const int schemaVersion = 2;

  /// Minimum players to start; the host may practice alone.
  static const int minPlayers = 1;

  GameConfig config;

  /// Players in display order.
  final List<Player> players;

  /// Completed rounds (no fixed limit).
  final List<RoundRecord> rounds;

  /// Total score per player across the session.
  final Map<String, int> totals;

  /// Players currently connected to the host.
  final Set<String> connectedPlayerIds;

  /// Players who explicitly left; not to be confused with a dropped connection.
  final Set<String> leftPlayerIds;

  /// Players still in the session; a disconnect does not change membership.
  int get activePlayerCount =>
      players.where((player) => !leftPlayerIds.contains(player.id)).length;

  bool hasPlayerLeft(String playerId) => leftPlayerIds.contains(playerId);

  GamePhase phase;

  int playerSeq;

  /// Unique session ID, created on the host.
  final String gameId;

  /// Player ID of the host.
  final String hostPlayerId;

  final int createdAtEpochMs;

  int savedAtEpochMs;

  /// Create a fresh session (empty lobby).
  factory GameSession.fresh({
    int nowMs = 0,
    String gameId = '',
    String hostPlayerId = '',
  }) => GameSession(
    config: GameConfig(activeCategoryIds: defaultActiveCategoryIds()),
    gameId: gameId,
    hostPlayerId: hostPlayerId,
    createdAtEpochMs: nowMs,
    savedAtEpochMs: nowMs,
  );

  // ---------------------------------------------------------------- Players

  /// Add a player. The name must be non-empty and unique in the session.
  ///
  /// [id] is optional: when a joining device supplies its stable id the id is
  /// reused, so identity survives a display-name change.
  Player addPlayer(String name, {String? id, bool isHost = false}) {
    final clean = name.trim();
    if (clean.isEmpty) {
      throw GameRuleException('نام نمایشی نمی‌تواند خالی باشد.');
    }
    if (clean.length > 24) {
      throw GameRuleException('نام نمایشی حداکثر ۲۴ نویسه می‌تواند باشد.');
    }
    final normalized = normalizeName(clean);
    if (players.any((p) => normalizeName(p.name) == normalized)) {
      throw GameRuleException(
        'این نام قبلاً ثبت شده است. نام دیگری انتخاب کنید.',
      );
    }
    String playerId;
    if (id != null && id.isNotEmpty) {
      if (players.any((p) => p.id == id)) {
        throw GameRuleException('این شناسهٔ بازیکن قبلاً در بازی ثبت شده است.');
      }
      playerId = id;
    } else {
      playerSeq += 1;
      playerId = 'p$playerSeq';
    }
    final player = Player(id: playerId, name: clean, isHost: isHost);
    players.add(player);
    connectedPlayerIds.add(playerId);
    totals.putIfAbsent(playerId, () => 0);
    return player;
  }

  /// Remove a player (lobby only; the roster is frozen once a round starts).
  void removePlayer(String playerId) {
    if (phase != GamePhase.lobby) {
      throw GameRuleException('حذف بازیکن فقط در لابی امکان‌پذیر است.');
    }
    players.removeWhere((p) => p.id == playerId);
    connectedPlayerIds.remove(playerId);
    leftPlayerIds.remove(playerId);
    totals.remove(playerId);
    for (final round in rounds) {
      round.answers.removeWhere((_, a) => a.playerId == playerId);
      round.scores.remove(playerId);
      round.stoppedPlayerIds.remove(playerId);
      round.receivedSnapshotPlayerIds.remove(playerId);
    }
  }

  /// Record an explicit exit. A normal disconnect must not call this.
  ///
  /// In the lobby the record is removed. After the start, history and totals are
  /// kept, but the player leaves the roster, thresholds and later rounds.
  bool markPlayerLeft(String playerId) {
    if (playerId == hostPlayerId || playerById(playerId) == null) return false;
    if (phase == GamePhase.finished) return false;
    if (phase == GamePhase.lobby) {
      removePlayer(playerId);
      return true;
    }
    if (!leftPlayerIds.add(playerId)) return false;
    connectedPlayerIds.remove(playerId);
    final round = currentRound;
    if (round != null &&
        (phase == GamePhase.playing ||
            phase == GamePhase.paused ||
            phase == GamePhase.collecting)) {
      round.activePlayerIdsAtStart.remove(playerId);
      round.stoppedPlayerIds.remove(playerId);
      if (phase == GamePhase.collecting) {
        round.receivedSnapshotPlayerIds.add(playerId);
      }
    }
    return true;
  }

  /// Rename a player without changing identity.
  void renamePlayer(String playerId, String newName) {
    final clean = newName.trim();
    if (clean.isEmpty) {
      throw GameRuleException('نام نمایشی نمی‌تواند خالی باشد.');
    }
    if (clean.length > 24) {
      throw GameRuleException('نام نمایشی حداکثر ۲۴ نویسه می‌تواند باشد.');
    }
    final normalized = normalizeName(clean);
    if (players.any(
      (p) => p.id != playerId && normalizeName(p.name) == normalized,
    )) {
      throw GameRuleException(
        'این نام قبلاً ثبت شده است. نام دیگری انتخاب کنید.',
      );
    }
    final index = players.indexWhere((p) => p.id == playerId);
    if (index < 0) {
      throw GameRuleException('بازیکن یافت نشد.');
    }
    players[index] = players[index].copyWith(name: clean);
  }

  /// Update a player's connection state.
  void setConnected(String playerId, bool connected) {
    if (connected && !leftPlayerIds.contains(playerId)) {
      connectedPlayerIds.add(playerId);
    } else {
      connectedPlayerIds.remove(playerId);
    }
  }

  bool isConnected(String playerId) => connectedPlayerIds.contains(playerId);

  /// Whether the game can start.
  bool get canStartGame =>
      phase == GamePhase.lobby && activePlayerCount >= minPlayers;

  /// Player with the given ID.
  Player? playerById(String id) {
    for (final p in players) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Display name of a player, for the UI.
  String nameOf(String playerId) => playerById(playerId)?.name ?? '—';

  // ------------------------------------------------------------------ Rounds

  /// The current (last) round, or null.
  RoundRecord? get currentRound => rounds.isEmpty ? null : rounds.last;

  /// Whether a round is in play, judging or results.
  bool get hasActiveGame =>
      rounds.isNotEmpty &&
      (phase == GamePhase.playing ||
          phase == GamePhase.paused ||
          phase == GamePhase.collecting ||
          phase == GamePhase.judging ||
          phase == GamePhase.roundResults);

  /// Start a new round without any letter or word, keeping previous scores.
  ///
  /// Choosing a word or letter per round has been removed entirely; starting a
  /// round depends on no text input.
  RoundRecord startNewRound({
    required int nowMs,
    List<int>? activeCategoryIds,
  }) {
    if (activePlayerCount < minPlayers) {
      throw GameRuleException('برای شروع بازی حداقل یک بازیکن لازم است.');
    }
    final previous = currentRound;
    if (previous != null && !previous.judged) {
      throw GameRuleException('ابتدا داوری دست جاری را کامل کنید.');
    }
    if (phase != GamePhase.lobby && phase != GamePhase.roundResults) {
      throw GameRuleException('در این وضعیت شروع دست جدید ممکن نیست.');
    }
    if (activeCategoryIds != null && activeCategoryIds.isNotEmpty) {
      setActiveCategories(activeCategoryIds);
    }
    final index = rounds.length + 1;
    final round = RoundRecord(
      index: index,
      startedAtEpochMs: nowMs,
      endEpochMs: nowMs + kRoundDurationMs,
      activePlayerIdsAtStart: connectedPlayerIds
          .where((playerId) => !leftPlayerIds.contains(playerId))
          .toSet(),
    );
    for (final player in players.where((p) => !leftPlayerIds.contains(p.id))) {
      for (final categoryId in config.activeCategoryIds) {
        round.answers[AnswerEntry.keyOf(
          index,
          player.id,
          categoryId,
        )] = AnswerEntry(
          playerId: player.id,
          categoryId: categoryId,
          text: '',
          status: JudgementStatus.empty,
        );
      }
    }
    rounds.add(round);
    phase = GamePhase.playing;
    return round;
  }

  /// Change active categories (only before a round or between rounds).
  bool setActiveCategories(List<int> ids) {
    if (phase != GamePhase.lobby && phase != GamePhase.roundResults) {
      return false;
    }
    final cleaned = <int>[];
    for (final id in ids) {
      if (categoryById(id) != null && !cleaned.contains(id)) cleaned.add(id);
    }
    if (cleaned.isEmpty) return false;
    config = config.copyWith(
      activeCategoryIds: List<int>.unmodifiable(cleaned),
    );
    return true;
  }

  /// Remaining time of the current round in milliseconds, from the real clock.
  int remainingMs(int nowMs) {
    final round = currentRound;
    if (round == null) return 0;
    if (round.pausedRemainingMs != null) return round.pausedRemainingMs!;
    final remaining = round.endEpochMs - nowMs;
    return remaining < 0 ? 0 : remaining;
  }

  /// Pause the timer (host only).
  bool pause(int nowMs) {
    final round = currentRound;
    if (round == null || phase != GamePhase.playing) return false;
    round.pausedRemainingMs = remainingMs(nowMs);
    phase = GamePhase.paused;
    return true;
  }

  /// Resume from the paused remaining time (host only).
  bool resume(int nowMs) {
    final round = currentRound;
    if (round == null || phase != GamePhase.paused) return false;
    final remaining = round.pausedRemainingMs ?? kRoundDurationMs;
    round.endEpochMs = nowMs + remaining;
    round.pausedRemainingMs = null;
    phase = GamePhase.playing;
    return true;
  }

  /// Set or edit one answer; the host validates it.
  bool setAnswer(String playerId, int categoryId, String text) {
    final round = currentRound;
    if (round == null || phase != GamePhase.playing) return false;
    if (leftPlayerIds.contains(playerId)) return false;
    if (!isAnswerWithinLimit(text)) return false;
    if (round.stoppedPlayerIds.contains(playerId)) return false;
    if (playerById(playerId) == null) return false;
    final key = AnswerEntry.keyOf(round.index, playerId, categoryId);
    final existing = round.answers[key];
    if (existing == null) return false;
    if (existing.text == text) return false;
    round.answers[key] = existing.copyWith(
      text: text,
      status: text.trim().isEmpty
          ? JudgementStatus.empty
          : JudgementStatus.unchecked,
    );
    return true;
  }

  /// Whether the player has pressed Stop.
  bool isPlayerStopped(String playerId) =>
      currentRound?.stoppedPlayerIds.contains(playerId) ?? false;

  /// Number of recorded Stop requests in the current round.
  int get stopCount => currentRound?.stoppedPlayerIds.length ?? 0;

  /// Whether every answer field of this player satisfies the Stop rule.
  ///
  /// Only the active categories of the current round are checked, and each field
  /// needs at least [kStopMinValidChars] valid characters. Leading, trailing and
  /// inner spaces, half-spaces and invisible characters do not count.
  ///
  bool canPlayerStop(String playerId) {
    final round = currentRound;
    if (round == null) return false;
    if (phase != GamePhase.playing && phase != GamePhase.paused) return false;
    if (playerById(playerId) == null || leftPlayerIds.contains(playerId)) {
      return false;
    }
    final categoryIds = config.activeCategoryIds;
    if (categoryIds.isEmpty) return false;
    for (final categoryId in categoryIds) {
      final answer = round.answers[AnswerEntry.keyOf(
        round.index,
        playerId,
        categoryId,
      )];
      if (answer == null) return false;
      if (!isAnswerEligibleForStop(answer.text)) return false;
    }
    return true;
  }

  /// Categories where this player's answer still misses the minimum valid
  /// characters; used for the Stop hint text.
  List<int> pendingStopCategoryIds(String playerId) {
    final round = currentRound;
    if (round == null) return const <int>[];
    final pending = <int>[];
    for (final categoryId in config.activeCategoryIds) {
      final answer = round.answers[AnswerEntry.keyOf(
        round.index,
        playerId,
        categoryId,
      )];
      if (answer == null || !isAnswerEligibleForStop(answer.text)) {
        pending.add(categoryId);
      }
    }
    return pending;
  }

  /// A player pressed Stop.
  ///
  /// Each player may Stop once; a duplicate message is not counted again. The
  /// round ends only when the number of stoppers reaches ceil(active players at
  /// round start / 2). A disconnect does not change the threshold.
  ///
  ///
  /// Returns true when the Stop is accepted, whether or not the threshold ended
  /// the round: endRound runs once because the phase leaves playing.
  ///
  ///
  /// The player's own answers are validated before the Stop is recorded, so an
  /// old or duplicate message, or a request from a device whose fields are still
  /// incomplete, is rejected without effect.
  bool requestStop(String playerId, {required int nowMs}) {
    final round = currentRound;
    if (round == null) return false;
    if (phase != GamePhase.playing && phase != GamePhase.paused) return false;
    if (playerById(playerId) == null) return false;
    if (!canPlayerStop(playerId)) return false;
    // One Stop per player; duplicate messages are not counted again.
    if (round.stoppedPlayerIds.contains(playerId)) return false;
    round.stoppedPlayerIds.add(playerId);
    // The round ends only once the Stop threshold is reached.
    if (round.stoppedPlayerIds.length >= round.stopThreshold) {
      return endRound(RoundEndReason.playerStop, nowMs: nowMs);
    }
    return true;
  }

  /// End the round as host (timeout or manual decision).
  bool endRound(RoundEndReason reason, {required int nowMs}) {
    final round = currentRound;
    if (round == null) return false;
    if (phase != GamePhase.playing && phase != GamePhase.paused) return false;
    round.pausedRemainingMs = null;
    round.endReason = reason;
    phase = GamePhase.collecting;
    return true;
  }

  /// Check for timeout; ends the round and returns true when it expires.
  bool tickTimer(int nowMs) {
    if (phase != GamePhase.playing) return false;
    if (remainingMs(nowMs) > 0) return false;
    return endRound(RoundEndReason.timer, nowMs: nowMs);
  }

  // ------------------------------------------- Final answer collection

  /// Apply a player's final answer snapshot on the host.
  ///
  /// Idempotent: a snapshot already received from the same player is not applied
  /// twice, so duplicate network messages cannot rewrite answers.
  bool applySnapshot(
    String playerId,
    Map<int, String> answers, {
    required int roundIndex,
  }) {
    final round = currentRound;
    if (round == null || round.index != roundIndex) return false;
    if (playerById(playerId) == null || leftPlayerIds.contains(playerId)) {
      return false;
    }
    if (round.receivedSnapshotPlayerIds.contains(playerId)) return false;
    if (answers.values.any((text) => !isAnswerWithinLimit(text))) return false;
    for (final entry in answers.entries) {
      final key = AnswerEntry.keyOf(round.index, playerId, entry.key);
      final existing = round.answers[key];
      if (existing == null) continue;
      final text = entry.value;
      if (existing.text == text) continue;
      round.answers[key] = existing.copyWith(
        text: text,
        status: text.trim().isEmpty
            ? JudgementStatus.empty
            : JudgementStatus.unchecked,
      );
    }
    // Stopped answers are locked.
    round.stoppedPlayerIds.add(playerId);
    round.receivedSnapshotPlayerIds.add(playerId);
    return true;
  }

  /// Mark the snapshot as received without changing answers (offline player).
  bool markSnapshotReceived(String playerId) {
    final round = currentRound;
    if (round == null) return false;
    if (playerById(playerId) == null) return false;
    if (round.receivedSnapshotPlayerIds.contains(playerId)) return false;
    round.receivedSnapshotPlayerIds.add(playerId);
    return true;
  }

  /// Players whose final snapshot has not arrived yet.
  List<String> get pendingSnapshotPlayerIds {
    final round = currentRound;
    if (round == null) return const <String>[];
    return players
        .map((p) => p.id)
        .where(
          (id) =>
              !leftPlayerIds.contains(id) &&
              !round.receivedSnapshotPlayerIds.contains(id),
        )
        .toList(growable: false);
  }

  /// Whether every player's snapshot has arrived.
  bool get allSnapshotsReceived => pendingSnapshotPlayerIds.isEmpty;

  /// Close the collecting phase and start judging once all snapshots arrived.
  bool tryStartJudging() {
    if (phase != GamePhase.collecting) return false;
    if (!allSnapshotsReceived) return false;
    phase = GamePhase.judging;
    return true;
  }

  // ------------------------------------------------------------- Judging

  /// Set the judgement of one answer (host device only).
  void setJudgement(String playerId, int categoryId, JudgementStatus? status) {
    final round = currentRound;
    if (round == null || phase != GamePhase.judging) return;
    final key = AnswerEntry.keyOf(round.index, playerId, categoryId);
    final existing = round.answers[key];
    if (existing == null || existing.isBlank) return;
    final next =
        status == JudgementStatus.empty ||
            status == JudgementStatus.unchecked ||
            status == null
        ? JudgementStatus.unchecked
        : status;
    round.answers[key] = existing.copyWith(status: next);
  }

  /// Number of non-empty answers not judged yet.
  int get uncheckedCount {
    final round = currentRound;
    if (round == null) return 0;
    return round.answers.values
        .where((a) => !a.isBlank && a.status == JudgementStatus.unchecked)
        .length;
  }

  /// Whether all non-empty answers of this category are judged.
  bool isCategoryJudged(int categoryId) {
    final round = currentRound;
    if (round == null) return true;
    return round.answers.values
        .where((a) => a.categoryId == categoryId)
        .every((a) => a.isBlank || a.status != JudgementStatus.unchecked);
  }

  /// Answers of one category in the current round, in player order.
  List<AnswerEntry> answersOfCategory(int categoryId) {
    final round = currentRound;
    if (round == null) return const <AnswerEntry>[];
    final list = <AnswerEntry>[];
    for (final player in players) {
      final a =
          round.answers[AnswerEntry.keyOf(round.index, player.id, categoryId)];
      if (a != null) list.add(a);
    }
    return list;
  }

  /// Finalize judging: score the round and add it to the totals.
  RoundScoring finalizeJudging() {
    final round = currentRound;
    if (round == null) {
      throw GameRuleException('دستی برای داوری وجود ندارد.');
    }
    if (phase != GamePhase.judging) {
      throw GameRuleException('داوری در این وضعیت امکان‌پذیر نیست.');
    }
    if (uncheckedCount > 0) {
      throw GameRuleException('پیش از ثبت نهایی، همهٔ پاسخ‌ها را داوری کنید.');
    }
    final scored = scoreRound(
      round.answers.values.toList(growable: false),
      playerIds: players.map((p) => p.id).toList(growable: false),
    );
    round.scores
      ..clear()
      ..addAll(scored.perPlayer);
    round.answers.updateAll(
      (_, a) => a.isBlank ? a.copyWith(status: JudgementStatus.empty) : a,
    );
    for (final entry in scored.perPlayer.entries) {
      totals[entry.key] = (totals[entry.key] ?? 0) + entry.value;
    }
    round.judged = true;
    phase = GamePhase.roundResults;
    return scored;
  }

  /// Stored scoring of a round, for the results screen.
  RoundScoring scoringOfRound(int roundIndex) {
    final round = rounds.firstWhere(
      (r) => r.index == roundIndex,
      orElse: () => rounds.last,
    );
    return scoreRound(
      round.answers.values.toList(growable: false),
      playerIds: players.map((p) => p.id).toList(growable: false),
    );
  }

  /// Standings by total score.
  List<Standing> standings() =>
      buildStandings(players: players, totals: totals);

  /// Finish the game and clear temporary data; no permanent history is kept.
  void finishAndClear() {
    rounds.clear();
    leftPlayerIds.clear();
    totals.clear();
    for (final p in players) {
      totals[p.id] = 0;
    }
    phase = GamePhase.lobby;
  }

  // ------------------------------------------------------- Serialization

  Map<String, dynamic> toJson() => {
    'v': schemaVersion,
    'phase': phase.name,
    'seq': playerSeq,
    'gid': gameId,
    'hp': hostPlayerId,
    'created': createdAtEpochMs,
    'saved': savedAtEpochMs,
    'players': players.map((p) => p.toJson()).toList(growable: false),
    'conn': connectedPlayerIds.toList(),
    'left': leftPlayerIds.toList(),
    'config': config.toJson(),
    'rounds': rounds.map((r) => r.toJson()).toList(growable: false),
    'totals': totals,
  };

  static GameSession fromJson(Map<String, dynamic> json) {
    // Older schema data cannot be continued in this model because players,
    // identities and judging changed shape.
    final version = (json['v'] as num?)?.toInt();
    if (version != null && version != schemaVersion) {
      throw FormatException(
        'نسخهٔ ساختار دادهٔ ذخیره‌شده ($version) با این مدل سازگار نیست.',
      );
    }
    final session = GameSession(
      config: GameConfig.fromJson(json['config'] as Map<String, dynamic>),
      players: (json['players'] as List<dynamic>? ?? const [])
          .map((e) => Player.fromJson(e as Map<String, dynamic>))
          .toList(),
      rounds: (json['rounds'] as List<dynamic>? ?? const [])
          .map((e) => RoundRecord.fromJson(e as Map<String, dynamic>))
          .toList(),
      totals: (json['totals'] as Map<String, dynamic>? ?? const {}).map(
        (k, v) => MapEntry(k, (v as num).toInt()),
      ),
      connectedPlayerIds: ((json['conn'] as List<dynamic>?) ?? const [])
          .map((e) => e as String)
          .toSet(),
      leftPlayerIds: ((json['left'] as List<dynamic>?) ?? const [])
          .map((e) => e as String)
          .toSet(),
      phase: GamePhase.values.firstWhere(
        (p) => p.name == json['phase'],
        orElse: () => GamePhase.lobby,
      ),
      playerSeq: (json['seq'] as num?)?.toInt() ?? 0,
      gameId: json['gid'] as String? ?? '',
      hostPlayerId: json['hp'] as String? ?? '',
      createdAtEpochMs: (json['created'] as num?)?.toInt() ?? 0,
      savedAtEpochMs: (json['saved'] as num?)?.toInt() ?? 0,
    );
    // Validate consistency between players and answers.
    session.players.removeWhere((p) => p.id.isEmpty || p.name.trim().isEmpty);
    session.leftPlayerIds.removeWhere(
      (id) =>
          session.playerById(id) == null ||
          id == session.hostPlayerId,
    );
    session.connectedPlayerIds.removeAll(session.leftPlayerIds);
    for (final round in session.rounds) {
      round.answers.removeWhere(
        (_, a) => session.playerById(a.playerId) == null,
      );
    }
    return session;
  }
}
