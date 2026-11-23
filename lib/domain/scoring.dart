/// Scoring engine: pure logic with no UI dependency.
///
/// Rules:
///  - empty answer ................................................... 0
///  - rejected answer ................................................ 0
///  - duplicate (decided by the referee) ............................. 5
///  - ordinary confirmed answer ..................................... 10
///  - sole confirmed answer with another duplicate in the category ..... 15
///  - sole confirmed answer with all others empty or rejected ......... 20
///
/// Key points:
///  * The 15 and 20 bonuses replace the base 10, they are not added to it.
///  * With more than one confirmed answer no bonus applies.
///  * The 20 rule requires that no duplicate exists in the category.
///  * Everything is computed in one pass, so scores are never double counted.
library;

import 'models.dart';

/// Score of an ordinary confirmed answer.
const int kScoreConfirmed = 10;

/// Score of a sole confirmed answer when another player is a duplicate.
const int kScoreUniqueWithDuplicate = 15;

/// Score of a sole confirmed answer when all others are empty or rejected.
const int kScoreUniqueAlone = 20;

/// Score of a duplicate answer.
const int kScoreDuplicate = 5;

/// Score of a rejected answer.
const int kScoreRejected = 0;

/// Score of an empty answer.
const int kScoreEmpty = 0;

/// One answer after scoring.
class ScoredAnswer {
  const ScoredAnswer({
    required this.playerId,
    required this.categoryId,
    required this.text,
    required this.status,
    required this.score,
    this.uniqueBonus = false,
  });

  final String playerId;
  final int categoryId;
  final String text;
  final JudgementStatus status;
  final int score;

  /// Whether this answer received the uniqueness bonus.
  final bool uniqueBonus;
}

/// Scoring result of one round.
class RoundScoring {
  const RoundScoring({required this.answers, required this.perPlayer});

  /// Scored answers.
  final List<ScoredAnswer> answers;

  /// Per-player score of the round; players without answers appear with 0.
  final Map<String, int> perPlayer;

  int scoreOf(String playerId, int categoryId) {
    for (final a in answers) {
      if (a.playerId == playerId && a.categoryId == categoryId) return a.score;
    }
    return 0;
  }

  ScoredAnswer? answerOf(String playerId, int categoryId) {
    for (final a in answers) {
      if (a.playerId == playerId && a.categoryId == categoryId) return a;
    }
    return null;
  }
}

/// Summary of one category's judgement, for display and tests.
class CategoryTally {
  const CategoryTally({
    required this.confirmedCount,
    required this.duplicateCount,
    required this.hasDuplicate,
    required this.uniqueConfirmed,
  });

  final int confirmedCount;
  final int duplicateCount;
  final bool hasDuplicate;

  /// Whether the category has exactly one confirmed answer.
  final bool uniqueConfirmed;
}

/// Count answer states in one category.
CategoryTally tallyCategory(List<AnswerEntry> categoryAnswers) {
  var confirmed = 0;
  var duplicate = 0;
  for (final a in categoryAnswers) {
    if (a.isBlank) continue;
    switch (a.status) {
      case JudgementStatus.confirmed:
        confirmed += 1;
      case JudgementStatus.duplicate:
        duplicate += 1;
      case JudgementStatus.rejected:
      case JudgementStatus.empty:
      case JudgementStatus.unchecked:
        break;
    }
  }
  return CategoryTally(
    confirmedCount: confirmed,
    duplicateCount: duplicate,
    hasDuplicate: duplicate > 0,
    uniqueConfirmed: confirmed == 1,
  );
}

/// Base score of an answer before the uniqueness rule.
int baseScoreOf(AnswerEntry answer) {
  if (answer.isBlank || answer.status == JudgementStatus.empty) return 0;
  switch (answer.status) {
    case JudgementStatus.confirmed:
      return kScoreConfirmed;
    case JudgementStatus.duplicate:
      return kScoreDuplicate;
    case JudgementStatus.rejected:
      return kScoreRejected;
    case JudgementStatus.unchecked:
      // An unjudged answer scores nothing; the referee must decide it.
      return 0;
    case JudgementStatus.empty:
      return kScoreEmpty;
  }
}

/// Score one category across all players.
List<ScoredAnswer> scoreCategory(List<AnswerEntry> categoryAnswers) {
  final tally = tallyCategory(categoryAnswers);
  final result = <ScoredAnswer>[];
  for (final a in categoryAnswers) {
    final blank = a.isBlank || a.status == JudgementStatus.empty;
    var score = baseScoreOf(a);
    var bonus = false;
    if (!blank &&
        a.status == JudgementStatus.confirmed &&
        tally.uniqueConfirmed) {
      // Uniqueness rule: the bonus replaces the base 10, it is not added.
      if (tally.hasDuplicate) {
        score = kScoreUniqueWithDuplicate; // Bonus with duplicate.
      } else {
        score = kScoreUniqueAlone; // Bonus alone.
      }
      bonus = true;
    }
    result.add(
      ScoredAnswer(
        playerId: a.playerId,
        categoryId: a.categoryId,
        text: a.text,
        status: blank ? JudgementStatus.empty : a.status,
        score: score,
        uniqueBonus: bonus,
      ),
    );
  }
  return result;
}

/// Score a whole round.
///
/// [answers] holds every answer of the round (players x active categories).
/// [playerIds] lists the round players so all appear in the score table.
RoundScoring scoreRound(
  List<AnswerEntry> answers, {
  required List<String> playerIds,
}) {
  final byCategory = <int, List<AnswerEntry>>{};
  for (final a in answers) {
    byCategory.putIfAbsent(a.categoryId, () => <AnswerEntry>[]).add(a);
  }
  final scored = <ScoredAnswer>[];
  for (final entry in byCategory.entries) {
    scored.addAll(scoreCategory(entry.value));
  }
  final perPlayer = <String, int>{for (final id in playerIds) id: 0};
  for (final a in scored) {
    perPlayer[a.playerId] = (perPlayer[a.playerId] ?? 0) + a.score;
  }
  return RoundScoring(answers: scored, perPlayer: perPlayer);
}

/// Standings by total score; ties share a rank.
List<Standing> buildStandings({
  required List<Player> players,
  required Map<String, int> totals,
}) {
  final rows = players
      .map(
        (p) => Standing(
          playerId: p.id,
          playerName: p.name,
          totalScore: totals[p.id] ?? 0,
          rank: 0,
        ),
      )
      .toList();
  final sorted = rows.toList()
    ..sort((a, b) {
      final byScore = b.totalScore.compareTo(a.totalScore);
      if (byScore != 0) return byScore;
      return a.playerName.compareTo(b.playerName);
    });
  return sorted
      .map((s) {
        final higher = rows.where((r) => r.totalScore > s.totalScore).length;
        return Standing(
          playerId: s.playerId,
          playerName: s.playerName,
          totalScore: s.totalScore,
          rank: higher + 1,
        );
      })
      .toList(growable: false);
}
