/// موتور امتیازدهی نسخهٔ ۱.۰.۰ — منطق خالص و مستقل از رابط کاربری.
///
/// قوانین (بند ۹ سند نسخه ۱.۰.۰):
///  - پاسخ خالی ..................................................... ۰
///  - پاسخ ردشده .................................................... ۰
///  - پاسخ تکراری (تشخیص دستی داور) ................................. ۵
///  - پاسخ تأییدشدهٔ عادی .......................................... ۱۰
///  - تنها پاسخ تأییدشدهٔ دسته و وجود پاسخ تکراری در سایر بازیکنان ... ۱۵
///  - تنها پاسخ تأییدشدهٔ دسته و بقیهٔ پاسخ‌ها خالی یا ردشده ......... ۲۰
///
/// نکته‌های کلیدی:
///  * امتیاز ویژه «۱۵» و «۲۰» امتیاز نهایی همان پاسخ است و با ۱۰ جمع نمی‌شود.
///  * اگر بیش از یک پاسخ تأییدشده وجود داشته باشد، امتیاز ویژه اعمال نمی‌شود.
///  * قانون ۲۰ تنها وقتی اعمال می‌شود که هیچ پاسخ تکراری در آن دسته نباشد.
///  * همهٔ محاسبات یک‌بار و در یک گذر انجام می‌شود، پس امتیاز دوباره ثبت نمی‌شود.
library;

import 'models.dart';

/// امتیاز پاسخ تأییدشدهٔ عادی.
const int kScoreConfirmed = 10;

/// امتیاز پاسخ تأییدشدهٔ یکتا در حضور پاسخ تکراری دیگران.
const int kScoreUniqueWithDuplicate = 15;

/// امتیاز پاسخ تأییدشدهٔ یکتا وقتی بقیهٔ پاسخ‌ها خالی یا ردشده‌اند.
const int kScoreUniqueAlone = 20;

/// امتیاز پاسخ تکراری.
const int kScoreDuplicate = 5;

/// امتیاز پاسخ ردشده.
const int kScoreRejected = 0;

/// امتیاز پاسخ خالی.
const int kScoreEmpty = 0;

/// یک پاسخ پس از امتیازدهی.
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

  /// آیا امتیاز ویژهٔ یکتا (۱۵ یا ۲۰) به این پاسخ داده شده است.
  final bool uniqueBonus;
}

/// نتیجهٔ امتیازدهی یک دست.
class RoundScoring {
  const RoundScoring({required this.answers, required this.perPlayer});

  /// پاسخ‌های امتیازدهی‌شده.
  final List<ScoredAnswer> answers;

  /// امتیاز هر بازیکن در این دست (بازیکنان بدون پاسخ هم با ۰ حاضرند).
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

/// خلاصهٔ داوری یک دسته، برای نمایش و آزمون.
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

  /// آیا دقیقاً یک پاسخ تأییدشده در دسته وجود دارد.
  final bool uniqueConfirmed;
}

/// شمارش وضعیت پاسخ‌های یک دسته.
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

/// امتیاز پایهٔ یک پاسخ، پیش از اعمال قانون یکتایی.
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
      // پاسخ داوری‌نشده امتیاز ندارد؛ داور باید وضعیت آن را مشخص کند.
      return 0;
    case JudgementStatus.empty:
      return kScoreEmpty;
  }
}

/// امتیازدهی یک دسته (همهٔ پاسخ‌های همان دسته از همهٔ بازیکنان).
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
      // قانون یکتایی: امتیاز نهایی جای ۱۰ می‌نشیند و جمع نمی‌شود.
      if (tally.hasDuplicate) {
        score = kScoreUniqueWithDuplicate; // ۱۵
      } else {
        score = kScoreUniqueAlone; // ۲۰
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

/// امتیازدهی کامل یک دست.
///
/// [answers] همهٔ پاسخ‌های دست (همهٔ بازیکنان × همهٔ دسته‌های فعال).
/// [playerIds] فهرست بازیکنان دست؛ برای اطمینان از حضور همه در جدول امتیاز.
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

/// رتبه‌بندی بر اساس مجموع امتیاز. تساوی ⇒ رتبهٔ مشترک.
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
