/// Domain logic: rounds, Stop with its threshold, answer collection, judging and sync.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sanjab/domain/categories.dart';
import 'package:sanjab/domain/game_session.dart';
import 'package:sanjab/domain/models.dart';

GameSession newSession({int players = 3}) {
  final session = GameSession.fresh(gameId: 'g1', hostPlayerId: 'h1');
  session.addPlayer('میزبان', id: 'h1', isHost: true);
  for (var i = 1; i < players; i++) {
    session.addPlayer('بازیکن $i', id: 'p$i');
  }
  return session;
}

/// Fill every active category with valid text (at least two characters) so the
/// Stop condition is satisfied.
void fillAllAnswers(GameSession session, String playerId, {String text = 'آب'}) {
  for (final categoryId in session.config.activeCategoryIds) {
    session.setAnswer(playerId, categoryId, text);
  }
}

void main() {
  group('بازیکنان', () {
    test('افزودن بازیکن با شناسهٔ پایدار و نام نمایشی', () {
      final session = GameSession.fresh();
      final player = session.addPlayer('سارا', id: 'u1');
      expect(player.id, 'u1');
      expect(session.playerById('u1')!.name, 'سارا');
    });

    test('نام خالی، نام تکراری و نام بلند پذیرفته نمی‌شود', () {
      final session = GameSession.fresh();
      session.addPlayer('سارا');
      expect(() => session.addPlayer('   '), throwsA(isA<GameRuleException>()));
      expect(
        () => session.addPlayer('سارا'),
        throwsA(isA<GameRuleException>()),
      );
      expect(
        () => session.addPlayer('ا' * 30),
        throwsA(isA<GameRuleException>()),
      );
    });

    test('تغییر نام، شناسه را عوض نمی‌کند', () {
      final session = GameSession.fresh();
      final player = session.addPlayer('سارا', id: 'u1');
      session.renamePlayer(player.id, 'سارا دو');
      expect(session.playerById('u1')!.name, 'سارا دو');
      expect(session.players.length, 1);
    });

    test('حذف بازیکن فقط در لابی مجاز است', () {
      final session = newSession();
      session.startNewRound(nowMs: 1000);
      expect(
        () => session.removePlayer('p1'),
        throwsA(isA<GameRuleException>()),
      );
    });

    test('قطع اتصال عضویت را کم نمی‌کند، اما خروج صریح در لابی حذف می‌کند', () {
      final session = newSession(players: 3);
      session.setConnected('p1', false);
      expect(session.activePlayerCount, 3);
      expect(session.canStartGame, isTrue);
      expect(session.markPlayerLeft('p2'), isTrue);
      expect(session.activePlayerCount, 2);
      expect(session.playerById('p2'), isNull);
      expect(session.canStartGame, isTrue);
    });

    test('خروج صریح پس از شروع تاریخچه را نگه می‌دارد و از دست‌های بعدی کنار می‌گذارد', () {
      final session = newSession(players: 3);
      session.totals['p1'] = 35;
      final first = session.startNewRound(nowMs: 0);

      expect(session.markPlayerLeft('p1'), isTrue);
      expect(session.activePlayerCount, 2);
      expect(session.playerById('p1'), isNotNull);
      expect(session.totals['p1'], 35);
      expect(session.hasPlayerLeft('p1'), isTrue);
      expect(first.activePlayerIdsAtStart, isNot(contains('p1')));
      expect(session.setAnswer('p1', 0, 'پاسخ'), isFalse);
      expect(session.canPlayerStop('p1'), isFalse);

      session.endRound(RoundEndReason.timer, nowMs: 420000);
      session.applySnapshot('h1', {}, roundIndex: first.index);
      session.applySnapshot('p2', {}, roundIndex: first.index);
      expect(session.allSnapshotsReceived, isTrue);
      expect(session.tryStartJudging(), isTrue);
      session.finalizeJudging();
      final second = session.startNewRound(nowMs: 500000);
      expect(second.answers.keys.any((key) => key.contains('|p1|')), isFalse);
    });
  });

  group('شروع دست', () {
    test('بدون بازیکن شروع نمی‌شود', () {
      final session = GameSession.fresh();
      expect(session.canStartGame, isFalse);
      expect(
        () => session.startNewRound(nowMs: 1000),
        throwsA(isA<GameRuleException>()),
      );
    });

    test('میزبان تنها می‌تواند شروع کند، استپ بزند و به داوری برسد', () {
      final session = newSession(players: 1);
      expect(session.canStartGame, isTrue);

      final round = session.startNewRound(nowMs: 1000);
      expect(round.activePlayerIdsAtStart, {'h1'});
      expect(round.stopThreshold, 1);
      fillAllAnswers(session, 'h1');

      expect(session.requestStop('h1', nowMs: 2000), isTrue);
      expect(session.phase, GamePhase.collecting);

      final snapshot = {
        for (final categoryId in session.config.activeCategoryIds)
          categoryId: round.answerOf('h1', categoryId)!.text,
      };
      expect(
        session.applySnapshot('h1', snapshot, roundIndex: round.index),
        isTrue,
      );
      expect(session.tryStartJudging(), isTrue);
      expect(session.phase, GamePhase.judging);
    });

    test('مدت دست ثابت ۷ دقیقه است', () {
      final session = newSession();
      final round = session.startNewRound(nowMs: 5000);
      expect(kRoundDurationSeconds, 420);
      expect(round.endEpochMs - round.startedAtEpochMs, 420 * 1000);
      expect(session.phase, GamePhase.playing);
    });

    test('شروع دست به هیچ کلمه یا حرفی وابسته نیست (نسخهٔ ۱.۰.۰)', () {
      final session = newSession();
      // Starting a round needs no text or word input.
      final first = session.startNewRound(nowMs: 0);
      expect(first.index, 1);
      expect(session.phase, GamePhase.playing);
      expect(
        session.currentRound!.answers.values.every((a) => a.isBlank),
        isTrue,
      );
    });

    test('پاسخ‌های خالی برای همهٔ بازیکنان و دسته‌ها ساخته می‌شود', () {
      final session = newSession(players: 2);
      final round = session.startNewRound(nowMs: 0);
      expect(round.answers.length, 2 * defaultActiveCategoryIds().length);
      expect(round.answers.values.every((a) => a.isBlank), isTrue);
    });
  });

  group('زمان‌سنج', () {
    test('باقی‌مانده بر اساس زمان واقعی محاسبه می‌شود', () {
      final session = newSession();
      session.startNewRound(nowMs: 1000);
      expect(session.remainingMs(1000), 420000);
      expect(session.remainingMs(61000), 360000);
      expect(session.remainingMs(999999), 0);
    });

    test('پایان زمان دست را به فاز دریافت پاسخ‌ها می‌برد', () {
      final session = newSession();
      session.startNewRound(nowMs: 0);
      expect(session.tickTimer(419000), isFalse);
      expect(session.tickTimer(421000), isTrue);
      expect(session.phase, GamePhase.collecting);
      expect(session.currentRound!.endReason, RoundEndReason.timer);
    });

    test('توقف و ادادمه، زمان باقی‌مانده را حفظ می‌کند', () {
      final session = newSession();
      session.startNewRound(nowMs: 0);
      expect(session.pause(60000), isTrue);
      expect(session.phase, GamePhase.paused);
      expect(session.remainingMs(120000), 360000);
      expect(session.resume(200000), isTrue);
      expect(session.phase, GamePhase.playing);
      expect(session.remainingMs(200000), 360000);
      expect(session.remainingMs(260000), 300000);
    });
  });

  group('استپ و دریافت پاسخ‌های پایانی', () {
    test('در بازی دونفره، استپ یک بازیکن دست را تمام می‌کند و پاسخ‌ها را قفل می‌کند', () {
      final session = newSession(players: 2);
      session.startNewRound(nowMs: 0);
      expect(session.setAnswer('h1', 0, 'تهران'), isTrue);
      fillAllAnswers(session, 'h1');
      expect(session.requestStop('h1', nowMs: 1000), isTrue);
      expect(session.phase, GamePhase.collecting);
      expect(session.currentRound!.endReason, RoundEndReason.playerStop);
      expect(session.isPlayerStopped('h1'), isTrue);
      expect(session.setAnswer('h1', 1, 'فامیل'), isFalse);
    });

    test('حد نصاب استپ در بازی سه‌نفره دو نفر است', () {
      final session = newSession(players: 3);
      final round = session.startNewRound(nowMs: 0);
      expect(round.stopThreshold, 2);
      fillAllAnswers(session, 'h1');
      fillAllAnswers(session, 'p1');
      expect(session.requestStop('h1', nowMs: 100), isTrue);
      expect(session.phase, GamePhase.playing, reason: 'یک استپ کافی نیست');
      expect(session.stopCount, 1);
      // A duplicate Stop from the same player is not counted.
      expect(session.requestStop('h1', nowMs: 150), isFalse);
      expect(session.stopCount, 1);
      expect(session.requestStop('p1', nowMs: 200), isTrue);
      expect(session.phase, GamePhase.collecting);
      expect(session.currentRound!.endReason, RoundEndReason.playerStop);
    });

    test('قطع اتصال بازیکن حد نصاب استپ را تغییر نمی‌دهد', () {
      final session = newSession(players: 4);
      final round = session.startNewRound(nowMs: 0);
      expect(round.stopThreshold, 2);
      session.setConnected('p1', false);
      session.setConnected('p2', false);
      expect(session.currentRound!.stopThreshold, 2);
      fillAllAnswers(session, 'h1');
      fillAllAnswers(session, 'p3');
      expect(session.requestStop('h1', nowMs: 10), isTrue);
      expect(session.requestStop('p3', nowMs: 20), isTrue);
      expect(session.phase, GamePhase.collecting);
    });

    test('حد نصاب شش‌نفره سه نفر است', () {
      final session = newSession(players: 6);
      final round = session.startNewRound(nowMs: 0);
      expect(round.stopThreshold, 3);
      fillAllAnswers(session, 'h1');
      fillAllAnswers(session, 'p1');
      fillAllAnswers(session, 'p2');
      session.requestStop('h1', nowMs: 1);
      session.requestStop('p1', nowMs: 2);
      expect(session.phase, GamePhase.playing);
      session.requestStop('p2', nowMs: 3);
      expect(session.phase, GamePhase.collecting);
    });

    test('استپ تکراری همان بازیکن دوباره اعمال نمی‌شود', () {
      final session = newSession();
      session.startNewRound(nowMs: 0);
      fillAllAnswers(session, 'p1');
      session.requestStop('p1', nowMs: 100);
      expect(session.requestStop('p1', nowMs: 200), isFalse);
    });

    test('Snapshot نهایی پاسخ‌ها را می‌نویسد و یک‌بار بیشتر اعمال نمی‌شود', () {
      final session = newSession(players: 2);
      final round = session.startNewRound(nowMs: 0);
      final applied = session.applySnapshot('p1', {
        0: 'تهران',
        1: 'رضایی',
      }, roundIndex: round.index);
      expect(applied, isTrue);
      expect(session.currentRound!.answerOf('p1', 0)!.text, 'تهران');
      expect(
        session.currentRound!.submissionOf('p1'),
        SubmissionState.received,
      );
      // A duplicate network message must not record the answer twice.
      final again = session.applySnapshot('p1', {
        0: 'مشهد',
      }, roundIndex: round.index);
      expect(again, isFalse);
      expect(session.currentRound!.answerOf('p1', 0)!.text, 'تهران');
    });

    test('داوری تا دریافت پاسخ همهٔ بازیکنان آغاز نمی‌شود', () {
      final session = newSession(players: 3);
      final round = session.startNewRound(nowMs: 0);
      session.endRound(RoundEndReason.timer, nowMs: 1000);
      session.applySnapshot('h1', {}, roundIndex: round.index);
      session.applySnapshot('p1', {}, roundIndex: round.index);
      expect(session.tryStartJudging(), isFalse);
      expect(session.phase, GamePhase.collecting);
      expect(session.pendingSnapshotPlayerIds, ['p2']);
      session.applySnapshot('p2', {}, roundIndex: round.index);
      expect(session.tryStartJudging(), isTrue);
      expect(session.phase, GamePhase.judging);
    });

    test('خروج در فاز دریافت، Snapshot معلق بازیکن را رفع می‌کند', () {
      final session = newSession(players: 2);
      final round = session.startNewRound(nowMs: 0);
      session.endRound(RoundEndReason.timer, nowMs: 420000);
      session.applySnapshot('h1', {}, roundIndex: round.index);

      expect(session.pendingSnapshotPlayerIds, ['p1']);
      expect(session.markPlayerLeft('p1'), isTrue);
      expect(session.pendingSnapshotPlayerIds, isEmpty);
      expect(session.tryStartJudging(), isTrue);
      expect(session.phase, GamePhase.judging);
    });

    test('بازیکن قطع‌شده با تصمیم صریح میزبان از دست کنار گذاشته می‌شود', () {
      final session = newSession(players: 2);
      final round = session.startNewRound(nowMs: 0);
      session.endRound(RoundEndReason.timer, nowMs: 1000);
      session.applySnapshot('h1', {}, roundIndex: round.index);
      expect(session.allSnapshotsReceived, isFalse);
      expect(session.markSnapshotReceived('p1'), isTrue);
      expect(session.allSnapshotsReceived, isTrue);
      expect(session.markSnapshotReceived('p1'), isFalse);
    });
  });

  group('داوری و امتیازها', () {
    test('داوری فقط در فاز داوری ممکن است', () {
      final session = newSession(players: 2);
      session.startNewRound(nowMs: 0);
      session.setAnswer('h1', 0, 'تهران');
      // Judging is not applied during the playing phase.
      session.setJudgement('h1', 0, JudgementStatus.confirmed);
      expect(
        session.currentRound!.answerOf('h1', 0)!.status,
        JudgementStatus.unchecked,
      );
    });

    test('ثبت نهایی با پاسخ بررسی‌نشده انجام نمی‌شود', () {
      final session = newSession(players: 2);
      final round = session.startNewRound(nowMs: 0);
      session.setAnswer('h1', 0, 'تهران');
      session.endRound(RoundEndReason.playerStop, nowMs: 10);
      session.applySnapshot('h1', {0: 'تهران'}, roundIndex: round.index);
      session.applySnapshot('p1', {0: ''}, roundIndex: round.index);
      session.tryStartJudging();
      expect(session.phase, GamePhase.judging);
      expect(
        () => session.finalizeJudging(),
        throwsA(isA<GameRuleException>()),
      );
    });

    test('امتیازها به مجموع اضافه می‌شوند و دوباره ثبت نمی‌شوند', () {
      final session = newSession(players: 2);
      final round = session.startNewRound(nowMs: 0);
      session.endRound(RoundEndReason.timer, nowMs: 10);
      session.applySnapshot('h1', {0: 'تهران'}, roundIndex: round.index);
      session.applySnapshot('p1', {0: ''}, roundIndex: round.index);
      session.tryStartJudging();
      session.setJudgement('h1', 0, JudgementStatus.confirmed);
      final scored = session.finalizeJudging();
      expect(scored.perPlayer['h1'], 20);
      expect(session.totals['h1'], 20);
      expect(session.phase, GamePhase.roundResults);
      // Judging cannot be repeated in this phase.
      expect(
        () => session.finalizeJudging(),
        throwsA(isA<GameRuleException>()),
      );
      expect(session.totals['h1'], 20);
    });

    test('دست‌های متوالی مجموع امتیاز را حفظ می‌کنند', () {
      final session = newSession(players: 2);
      final first = session.startNewRound(nowMs: 0);
      session.endRound(RoundEndReason.timer, nowMs: 10);
      session.applySnapshot('h1', {0: 'تهران'}, roundIndex: first.index);
      session.applySnapshot('p1', {}, roundIndex: first.index);
      session.tryStartJudging();
      session.setJudgement('h1', 0, JudgementStatus.confirmed);
      session.finalizeJudging();
      final total = session.totals['h1']!;
      expect(total, greaterThan(0));

      final second = session.startNewRound(nowMs: 2000);
      expect(second.index, 2);
      expect(session.phase, GamePhase.playing);
      expect(session.remainingMs(2000), 420000);
    });
  });

  group('اتصال و سریال‌سازی', () {
    test('وضعیت اتصال بازیکنان ثبت می‌شود', () {
      final session = newSession(players: 2);
      expect(session.isConnected('p1'), isTrue);
      session.setConnected('p1', false);
      expect(session.isConnected('p1'), isFalse);
    });

    test('تبدیل به JSON و بازگشت، وضعیت را حفظ می‌کند', () {
      final session = newSession(players: 2);
      final round = session.startNewRound(nowMs: 100);
      session.setAnswer('h1', 0, 'تهران');
      session.endRound(RoundEndReason.timer, nowMs: 200);
      session.applySnapshot('h1', {0: 'تهران'}, roundIndex: round.index);
      final restored = GameSession.fromJson(session.toJson());
      expect(restored.players.length, 2);
      expect(restored.phase, GamePhase.collecting);
      expect(restored.currentRound!.answerOf('h1', 0)!.text, 'تهران');
      expect(
        restored.currentRound!.submissionOf('h1'),
        SubmissionState.received,
      );
      expect(restored.gameId, 'g1');
      expect(GameSession.schemaVersion, 2);
    });

    test('وضعیت خروج صریح ذخیره می‌شود و نبودن کلید در دادهٔ قدیمی سازگار است', () {
      final session = newSession(players: 3);
      session.startNewRound(nowMs: 100);
      session.markPlayerLeft('p1');

      final restored = GameSession.fromJson(session.toJson());
      expect(restored.hasPlayerLeft('p1'), isTrue);
      expect(restored.activePlayerCount, 2);
      expect(restored.isConnected('p1'), isFalse);

      final legacyJson = session.toJson()..remove('left');
      final legacy = GameSession.fromJson(legacyJson);
      expect(legacy.leftPlayerIds, isEmpty);
      expect(legacy.activePlayerCount, 3);
    });

    test('پایان بازی داده‌های موقت را پاک می‌کند', () {
      final session = newSession(players: 2);
      session.startNewRound(nowMs: 0);
      session.finishAndClear();
      expect(session.rounds, isEmpty);
      expect(session.phase, GamePhase.lobby);
      expect(session.totals.values.every((v) => v == 0), isTrue);
      expect(session.players.length, 2);
    });

    test('تغییر دسته‌های فعال فقط پیش از شروع دست ممکن است', () {
      final session = newSession(players: 2);
      expect(session.setActiveCategories([0, 1]), isTrue);
      expect(session.config.activeCategoryIds, [0, 1]);
      session.startNewRound(nowMs: 0);
      expect(session.setActiveCategories([0]), isFalse);
    });
  });
}
