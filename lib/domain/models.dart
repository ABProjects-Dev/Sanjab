/// مدل‌های دادهٔ دامنهٔ بازی «سنجاب» — نسخهٔ ۱.۰.۰ (چندنفره).
///
/// این فایل هیچ وابستگی‌ای به Flutter ندارد تا منطق بازی مستقل از رابط کاربری
/// و قابل تست باشد. تنها منبع حقیقت وضعیت بازی، [GameSession] روی دستگاه
/// میزبان است و بقیهٔ دستگاه‌ها نسخهٔ همگام‌شدهٔ همان را نگه می‌دارند.
library;

/// شناسهٔ نسخهٔ پروتکل شبکه. با تغییر ساختار پیام‌ها افزایش می‌یابد.
const int kProtocolVersion = 4;

/// مدت ثابت هر دست: ۷ دقیقه = ۴۲۰ ثانیه (بند ۶ سند نسخه ۱.۰.۰).
const int kRoundDurationSeconds = 420;

/// مدت ثابت هر دست بر حسب میلی‌ثانیه.
const int kRoundDurationMs = kRoundDurationSeconds * 1000;

/// وضعیت داوری یک پاسخ.
enum JudgementStatus {
  /// هنوز داوری نشده است.
  unchecked,

  /// تأییدشده (پاسخ معتبر).
  confirmed,

  /// تکراری (داور به‌صورت دستی تشخیص داده است).
  duplicate,

  /// ردشده.
  rejected,

  /// خانه خالی (بازیکن پاسخی وارد نکرده است).
  empty,
}

/// دلیل پایان یک دست.
enum RoundEndReason {
  /// پایان زمان ۷ دقیقه‌ای.
  timer,

  /// درخواست استپ یک بازیکن.
  playerStop,

  /// استپ میزبان.
  hostStop,

  /// تصمیم میزبان (پایان دستی).
  referee,
}

/// فاز جاری بازی.
///
/// [collecting] فاز تازهٔ نسخهٔ ۱.۰.۰ است: زمان دست تمام شده و میزبان در حال
/// دریافت Snapshot نهایی پاسخ‌های همهٔ بازیکنان است.
enum GamePhase {
  /// لابی: بازیکنان در حال پیوستن هستند و بازی شروع نشده است.
  lobby,

  /// دست در جریان است و زمان‌سنج فعال است.
  playing,

  /// دست به‌صورت موقت متوقف شده است.
  paused,

  /// دست تمام شده و میزبان در حال دریافت پاسخ‌های نهایی همهٔ بازیکنان است.
  collecting,

  /// صفحهٔ داوری فعال است (فقط روی دستگاه میزبان).
  judging,

  /// نتایج دست نمایش داده می‌شود.
  roundResults,

  /// نشست به‌صورت رسمی توسط میزبان پایان یافته است (نسخهٔ ۱.۰.۰).
  finished,
}

/// وضعیت ارسال پاسخ‌های یک بازیکن در یک دست.
enum SubmissionState {
  /// در حال نوشتن پاسخ‌ها.
  typing,

  /// استپ کرده و پاسخ‌های خود را فرستاده است.
  stopped,

  /// میزبان دریافت پاسخ‌های او را تأیید کرده است.
  received,

  /// اتصال او قطع شده است.
  offline,
}

/// نقش دستگاه در نشست بازی.
enum GameRole {
  /// هیچ نشستی فعال نیست.
  none,

  /// میزبان (مرجع اصلی وضعیت).
  host,

  /// بازیکن عضو.
  player,
}

/// یک بازیکن. شناسهٔ بازیکن در طول کل بازی پایدار و مستقل از نام نمایشی است.
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

/// یک پاسخ (یک بازیکن در یک دسته از یک دست).
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

  /// پاسخ خالی: نه امتیاز دارد و نه قابل داوری است.
  bool get isBlank => text.trim().isEmpty;

  /// کلید یکتای پاسخ در کل بازی: «شناسهٔ دست | شناسهٔ بازیکن | شناسهٔ دسته».
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

/// تنظیمات یک بازی. مدت دست در نسخهٔ ۱.۰.۰ ثابت است و قابل تغییر نیست؛
/// تنها دسته‌های فعال در لابی توسط میزبان انتخاب می‌شوند.
class GameConfig {
  const GameConfig({required this.activeCategoryIds});

  /// شناسهٔ دسته‌های فعال، به ترتیب نمایش.
  final List<int> activeCategoryIds;

  /// مدت ثابت هر دست (همیشه ۴۲۰ ثانیه).
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

/// وضعیت کامل یک دست.
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

  /// شمارهٔ دست (از ۱).
  final int index;

  final int startedAtEpochMs;

  /// زمان پایان دست بر اساس ساعت مرجع میزبان. مبنای معتبر زمان‌سنج.
  int endEpochMs;

  /// پاسخ‌ها با کلید «دست|بازیکن|دسته».
  final Map<String, AnswerEntry> answers;

  /// بازیکنانی که استپ کرده‌اند (پاسخ‌هایشان قفل شده است).
  final Set<String> stoppedPlayerIds;

  /// بازیکنانی که Snapshot نهایی پاسخ‌هایشان توسط میزبان دریافت و تأیید شده است.
  final Set<String> receivedSnapshotPlayerIds;

  /// شناسه‌های بازیکنان فعال در زمان شروع این دست (عکس‌WORK状ه است).
  /// قطع ارتباط بعد از شروع دست حد نصاب را تغییر نمی‌دهد.
  final Set<String> activePlayerIdsAtStart;

  /// حد نصاب استپ برای پایان خودکار دست: ceil(بازیکن‌های فعال / ۲).
  int get stopThreshold {
    final active = activePlayerIdsAtStart.length;
    if (active <= 0) return 1;
    return (active / 2).ceil();
  }

  /// زمان باقی‌مانده (میلی‌ثانیه) در لحظهٔ توقف موقت؛ null یعنی متوقف نیست.
  int? pausedRemainingMs;

  RoundEndReason? endReason;

  /// آیا داوری این دست نهایی شده است.
  bool judged;

  /// امتیاز هر بازیکن در این دست (پس از نهایی‌شدن داوری).
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

/// یک ردیف رتبه‌بندی.
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
