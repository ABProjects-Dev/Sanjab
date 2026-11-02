/// وضعیت کامل و مرجع بازی (منطق دامنه، بدون هیچ وابستگی به Flutter).
///
/// در نسخهٔ ۲.۰.۰ این کلاس روی دستگاه **میزبان** مرجع اصلی وضعیت است
/// (Host Authoritative) و روی دستگاه بازیکنان نسخهٔ همگام‌شدهٔ همان است.
/// همهٔ تغییرات از راه متدهای این کلاس انجام می‌شود و زمان‌سنج بر پایهٔ
/// «زمان واقعی» (Timestamp) کار می‌کند، نه شمارش تیک.
library;

import 'answer_rules.dart';
import 'categories.dart';
import 'models.dart';
import 'scoring.dart';

/// نام‌ها برای یکتاسازی مقایسه نرمال می‌شوند (فاصلهٔ اضافه و ی/ک عربی).
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

/// خطاهای قابل نمایش به کاربر (پیام فارسی و قابل فهم).
class GameRuleException implements Exception {
  GameRuleException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// وضعیت مرجع بازی.
class GameSession {
  GameSession({
    required this.config,
    List<Player>? players,
    List<RoundRecord>? rounds,
    Map<String, int>? totals,
    Set<String>? connectedPlayerIds,
    this.phase = GamePhase.lobby,
    this.playerSeq = 0,
    this.gameId = '',
    this.hostPlayerId = '',
    this.createdAtEpochMs = 0,
    this.savedAtEpochMs = 0,
  }) : players = players ?? <Player>[],
       rounds = rounds ?? <RoundRecord>[],
       totals = totals ?? <String, int>{},
       connectedPlayerIds = connectedPlayerIds ?? <String>{};

  /// نسخهٔ ساختار ذخیره‌سازی (۲ = ساختار چندنفرهٔ ۲.۰.۰).
  static const int schemaVersion = 2;

  /// حداقل بازیکن برای شروع بازی.
  static const int minPlayers = 2;

  GameConfig config;

  /// بازیکنان بازی (ترتیب نمایش).
  final List<Player> players;

  /// دست‌های انجام‌شده. بدون محدودیت تعداد.
  final List<RoundRecord> rounds;

  /// مجموع امتیاز هر بازیکن در کل بازی.
  final Map<String, int> totals;

  /// بازیکنانی که هم‌اکنون به میزبان متصل‌اند.
  final Set<String> connectedPlayerIds;

  GamePhase phase;

  int playerSeq;

  /// شناسهٔ یکتای نشست بازی (روی میزبان ساخته می‌شود).
  final String gameId;

  /// شناسهٔ بازیکن میزبان.
  final String hostPlayerId;

  final int createdAtEpochMs;

  int savedAtEpochMs;

  /// ساخت یک نشست تازه (لابی خالی).
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

  // --------------------------------------------------------------- بازیکنان

  /// افزودن بازیکن. نام باید غیرخالی و در بازی یکتا باشد.
  ///
  /// [id] اختیاری است؛ وقتی بازیکن عضو از دستگاه خودش شناسهٔ پایدار می‌فرستد
  /// از همان استفاده می‌شود تا هویت او با تغییر نام عوض نشود.
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

  /// حذف بازیکن (تنها در لابی مجاز است؛ وسط دست فهرست بازیکنان تغییر نمی‌کند).
  void removePlayer(String playerId) {
    if (phase != GamePhase.lobby) {
      throw GameRuleException('حذف بازیکن فقط در لابی امکان‌پذیر است.');
    }
    players.removeWhere((p) => p.id == playerId);
    connectedPlayerIds.remove(playerId);
    totals.remove(playerId);
    for (final round in rounds) {
      round.answers.removeWhere((_, a) => a.playerId == playerId);
      round.scores.remove(playerId);
      round.stoppedPlayerIds.remove(playerId);
      round.receivedSnapshotPlayerIds.remove(playerId);
    }
  }

  /// تغییر نام نمایشی بازیکن (هویت او تغییر نمی‌کند).
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

  /// به‌روزرسانی وضعیت اتصال یک بازیکن.
  void setConnected(String playerId, bool connected) {
    if (connected) {
      connectedPlayerIds.add(playerId);
    } else {
      connectedPlayerIds.remove(playerId);
    }
  }

  bool isConnected(String playerId) => connectedPlayerIds.contains(playerId);

  /// آیا بازی می‌تواند شروع شود؟
  bool get canStartGame =>
      phase == GamePhase.lobby && players.length >= minPlayers;

  /// بازیکن با شناسه.
  Player? playerById(String id) {
    for (final p in players) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// نام نمایشی بازیکن (برای نمایش در رابط کاربری).
  String nameOf(String playerId) => playerById(playerId)?.name ?? '—';

  // ------------------------------------------------------------------- دست‌ها

  /// دست جاری (آخرین دست) یا null.
  RoundRecord? get currentRound => rounds.isEmpty ? null : rounds.last;

  /// آیا دستی در جریان/داوری/نتایج است؟
  bool get hasActiveGame =>
      rounds.isNotEmpty &&
      (phase == GamePhase.playing ||
          phase == GamePhase.paused ||
          phase == GamePhase.collecting ||
          phase == GamePhase.judging ||
          phase == GamePhase.roundResults);

  /// شروع یک دست جدید بدون هیچ کلمه یا حرفی، با حفظ امتیازهای قبلی.
  ///
  /// نسخهٔ ۴.۰.۰: قابلیت تعیین کلمه/حرف برای دست‌ها به‌طور کامل حذف شده است؛
  /// شروع دست به هیچ ورودی متنی وابسته نیست.
  RoundRecord startNewRound({
    required int nowMs,
    List<int>? activeCategoryIds,
  }) {
    if (players.length < minPlayers) {
      throw GameRuleException('برای شروع بازی حداقل دو بازیکن لازم است.');
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
      activePlayerIdsAtStart: Set<String>.from(connectedPlayerIds),
    );
    for (final player in players) {
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

  /// تغییر دسته‌های فعال (تنها پیش از شروع دست یا بین دست‌ها).
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

  /// مدت باقی‌ماندهٔ دست جاری بر اساس زمان واقعی (میلی‌ثانیه).
  int remainingMs(int nowMs) {
    final round = currentRound;
    if (round == null) return 0;
    if (round.pausedRemainingMs != null) return round.pausedRemainingMs!;
    final remaining = round.endEpochMs - nowMs;
    return remaining < 0 ? 0 : remaining;
  }

  /// توقف موقت زمان‌سنج (فقط میزبان).
  bool pause(int nowMs) {
    final round = currentRound;
    if (round == null || phase != GamePhase.playing) return false;
    round.pausedRemainingMs = remainingMs(nowMs);
    phase = GamePhase.paused;
    return true;
  }

  /// ادامهٔ بازی از همان زمان قبلی (فقط میزبان).
  bool resume(int nowMs) {
    final round = currentRound;
    if (round == null || phase != GamePhase.paused) return false;
    final remaining = round.pausedRemainingMs ?? kRoundDurationMs;
    round.endEpochMs = nowMs + remaining;
    round.pausedRemainingMs = null;
    phase = GamePhase.playing;
    return true;
  }

  /// ثبت/ویرایش پاسخ یک بازیکن در یک دسته (میزبان آن را اعتبارسنجی می‌کند).
  bool setAnswer(String playerId, int categoryId, String text) {
    final round = currentRound;
    if (round == null || phase != GamePhase.playing) return false;
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

  /// آیا بازیکن استپ کرده است؟
  bool isPlayerStopped(String playerId) =>
      currentRound?.stoppedPlayerIds.contains(playerId) ?? false;

  /// تعداد استپ‌های ثبت‌شده در دست جاری.
  int get stopCount => currentRound?.stoppedPlayerIds.length ?? 0;

  /// (نسخهٔ ۴.۱.۰) آیا همهٔ فیلدهای پاسخ این بازیکن شرط دکمهٔ «استپ» را دارند؟
  ///
  /// تنها دسته‌های فعال و قابل تکمیل در دست جاری بررسی می‌شوند و هر فیلد
  /// باید حداقل [kStopMinValidChars] کاراکتر معتبر داشته باشد. فاصلهٔ
  /// ابتدا/انتها، فاصله‌های میانی، نیم‌فاصله و کاراکترهای غیرقابل مشاهده
  /// به حساب نمی‌آیند.
  bool canPlayerStop(String playerId) {
    final round = currentRound;
    if (round == null) return false;
    if (phase != GamePhase.playing && phase != GamePhase.paused) return false;
    if (playerById(playerId) == null) return false;
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

  /// (نسخهٔ ۴.۱.۰) دسته‌هایی که پاسخ این بازیکن در آن‌ها هنوز شرط حداقل
  /// دو کاراکتر معتبر را ندارد — برای نمایش راهنمای دکمهٔ استپ.
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

  /// درخواست استپ یک بازیکن.
  ///
  /// نسخهٔ ۲.۱.۰: هر بازیکن فقط یک بار می‌تواند استپ کند و پیام تکراری
  /// دوباره شمارش نمی‌شود. دست تنها زمانی پایان می‌یابد که تعداد
  /// استپ‌کنندگان به حد نصاب ceil(بازیکن‌های فعال در ابتدای دست / ۲) برسد.
  /// قطع ارتباط بازیکن باعث تغییر حد نصاب نمی‌شود.
  ///
  /// مقدار بازگشتی: true اگر استپ با موفقیت ثبت شود (بستن دست با رسیدن به
  /// حد نصاب یا خیر). endRound فقط یک بار اجرا می‌شود چون فاز پس از playing
  /// خارج می‌شود.
  ///
  /// نسخهٔ ۴.۱.۰: پیش از ثبت استپ، کامل بودن پاسخ‌های همان بازیکن بررسی
  /// می‌شود ([canPlayerStop]). پیام قدیمی/تکراری یا درخواست دستگاهی که
  /// همهٔ فیلدهایش را پر نکرده است، بی‌اثر رد می‌شود.
  bool requestStop(String playerId, {required int nowMs}) {
    final round = currentRound;
    if (round == null) return false;
    if (phase != GamePhase.playing && phase != GamePhase.paused) return false;
    if (playerById(playerId) == null) return false;
    if (!canPlayerStop(playerId)) return false;
    // هر بازیکن فقط یک بار استپ می‌کند؛ پیام تکراری دوباره شمارش نمی‌شود.
    if (round.stoppedPlayerIds.contains(playerId)) return false;
    round.stoppedPlayerIds.add(playerId);
    // دست تنها وقتی پایان می‌یابد که به حد نصاب برسیم.
    if (round.stoppedPlayerIds.length >= round.stopThreshold) {
      return endRound(RoundEndReason.playerStop, nowMs: nowMs);
    }
    return true;
  }

  /// پایان دست توسط میزبان (زمان یا تصمیم میزبان).
  bool endRound(RoundEndReason reason, {required int nowMs}) {
    final round = currentRound;
    if (round == null) return false;
    if (phase != GamePhase.playing && phase != GamePhase.paused) return false;
    round.pausedRemainingMs = null;
    round.endReason = reason;
    phase = GamePhase.collecting;
    return true;
  }

  /// بررسی اتمام زمان؛ در صورت پایان، دست را می‌بندد و true برمی‌گرداند.
  bool tickTimer(int nowMs) {
    if (phase != GamePhase.playing) return false;
    if (remainingMs(nowMs) > 0) return false;
    return endRound(RoundEndReason.timer, nowMs: nowMs);
  }

  // ------------------------------------------------- دریافت پاسخ‌های پایانی

  /// اعمال Snapshot نهایی پاسخ‌های یک بازیکن روی میزبان.
  ///
  /// این متد idempotent است: اگر Snapshot همان بازیکن قبلاً دریافت شده باشد،
  /// دوباره اعمال نمی‌شود (جلوگیری از ثبت چندبارهٔ پاسخ پس از پیام تکراری شبکه).
  bool applySnapshot(
    String playerId,
    Map<int, String> answers, {
    required int roundIndex,
  }) {
    final round = currentRound;
    if (round == null || round.index != roundIndex) return false;
    if (playerById(playerId) == null) return false;
    if (round.receivedSnapshotPlayerIds.contains(playerId)) return false;
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
    // پاسخ‌های استپ‌شده قفل می‌شوند.
    round.stoppedPlayerIds.add(playerId);
    round.receivedSnapshotPlayerIds.add(playerId);
    return true;
  }

  /// علامت‌گذاری دریافت Snapshot بدون تغییر پاسخ‌ها (برای بازیکن قطع‌شده).
  bool markSnapshotReceived(String playerId) {
    final round = currentRound;
    if (round == null) return false;
    if (playerById(playerId) == null) return false;
    if (round.receivedSnapshotPlayerIds.contains(playerId)) return false;
    round.receivedSnapshotPlayerIds.add(playerId);
    return true;
  }

  /// بازیکنانی که Snapshot نهایی آن‌ها هنوز دریافت نشده است.
  List<String> get pendingSnapshotPlayerIds {
    final round = currentRound;
    if (round == null) return const <String>[];
    return players
        .map((p) => p.id)
        .where((id) => !round.receivedSnapshotPlayerIds.contains(id))
        .toList(growable: false);
  }

  /// آیا پاسخ‌های همهٔ بازیکنان دریافت شده است؟
  bool get allSnapshotsReceived => pendingSnapshotPlayerIds.isEmpty;

  /// جمع‌بندی فاز دریافت: اگر همهٔ Snapshotها رسیده باشند، داوری آغاز می‌شود.
  bool tryStartJudging() {
    if (phase != GamePhase.collecting) return false;
    if (!allSnapshotsReceived) return false;
    phase = GamePhase.judging;
    return true;
  }

  // ------------------------------------------------------------------ داوری

  /// تعیین وضعیت داوری یک پاسخ (تنها روی دستگاه میزبان).
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

  /// تعداد پاسخ‌های غیرخالی که هنوز داوری نشده‌اند.
  int get uncheckedCount {
    final round = currentRound;
    if (round == null) return 0;
    return round.answers.values
        .where((a) => !a.isBlank && a.status == JudgementStatus.unchecked)
        .length;
  }

  /// آیا همهٔ پاسخ‌های غیرخالی این دسته داوری شده‌اند؟
  bool isCategoryJudged(int categoryId) {
    final round = currentRound;
    if (round == null) return true;
    return round.answers.values
        .where((a) => a.categoryId == categoryId)
        .every((a) => a.isBlank || a.status != JudgementStatus.unchecked);
  }

  /// پاسخ‌های یک دسته در دست جاری (به ترتیب بازیکنان).
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

  /// نهایی‌کردن داوری: محاسبهٔ امتیاز دست جاری و افزودن به مجموع.
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

  /// امتیازدهی ذخیره‌شدهٔ یک دست (برای نمایش نتایج).
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

  /// رتبه‌بندی بر اساس مجموع امتیاز.
  List<Standing> standings() =>
      buildStandings(players: players, totals: totals);

  /// پایان کامل بازی؛ داده‌های موقت پاک می‌شوند (تاریخچهٔ دائمی نگه داشته نمی‌شود).
  void finishAndClear() {
    rounds.clear();
    totals.clear();
    for (final p in players) {
      totals[p.id] = 0;
    }
    phase = GamePhase.lobby;
  }

  // ---------------------------------------------------------------- سریال‌سازی

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
    'config': config.toJson(),
    'rounds': rounds.map((r) => r.toJson()).toList(growable: false),
    'totals': totals,
  };

  static GameSession fromJson(Map<String, dynamic> json) {
    // دادهٔ نسخهٔ قدیمی (۱.۰.۰) قابل ادامه دادن در نسخهٔ شبکه‌ای نیست؛
    // چون ساختار بازیکنان، شناسه‌ها و داوری تغییر کرده است.
    final version = (json['v'] as num?)?.toInt();
    if (version != null && version != schemaVersion) {
      throw FormatException(
        'نسخهٔ دادهٔ ذخیره‌شده ($version) با این نسخهٔ برنامه سازگار نیست.',
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
    // اعتبارسنجی: بازیکنان و پاسخ‌ها باید منسجم باشند.
    session.players.removeWhere((p) => p.id.isEmpty || p.name.trim().isEmpty);
    for (final round in session.rounds) {
      round.answers.removeWhere(
        (_, a) => session.playerById(a.playerId) == null,
      );
    }
    return session;
  }
}
