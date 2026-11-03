/// آزمون سرتاسری نسخهٔ ۱.۰.۰: دو کنترلر واقعی (میزبان و بازیکن) روی
/// لوکال‌هاست با سوکت TCP واقعی؛ از ساخت بازی تا داوری و نتایج.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sanjab/domain/models.dart';
import 'package:sanjab/domain/profile.dart';
import 'package:sanjab/net/protocol.dart';
import 'package:sanjab/state/game_controller.dart';

import 'test_support/memory_profile_store.dart';
import 'test_support/memory_store.dart';

Future<bool> waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 8),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) return true;
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
  return condition();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late GameController host;
  late GameController player;
  late GameController player2;

  setUp(() async {
    host = GameController(
      store: MemorySessionStore(),
      profileRepo: MemoryProfileStore(
        initial: const Profile(playerId: 'h1', displayName: 'سارا'),
      ),
    );
    player = GameController(
      store: MemorySessionStore(),
      profileRepo: MemoryProfileStore(
        initial: const Profile(playerId: 'p1', displayName: 'مینا'),
      ),
    );
    player2 = GameController(
      store: MemorySessionStore(),
      profileRepo: MemoryProfileStore(
        initial: const Profile(playerId: 'p2', displayName: 'رضا'),
      ),
    );
    await host.bootstrap();
    await player.bootstrap();
    await player2.bootstrap();
  });

  tearDown(() async {
    await host.closeSession(silent: true);
    await player.leaveGame();
    await player2.leaveGame();
    host.dispose();
    player.dispose();
    player2.dispose();
  });

  test('جریان کامل بازی سه‌نفره: اتصال، دست، استپ، داوری و نتایج', () async {
    // نسخهٔ ۱.۰.۰: دکمهٔ استپ زمانی فعال می‌شود که همهٔ فیلدهای پاسخ
    // بازیکن حداقل دو کاراکتر داشته باشند؛ برای آزمون‌پذیر ماندن این جریان،
    // دسته‌های فعال به دو دسته محدود می‌شود.
    expect(await host.createGame(activeCategoryIds: [0, 1]), isTrue);
    expect(host.isHost, isTrue);
    expect(host.hostPort, greaterThan(0));
    expect(host.joinToken.length, 6);

    expect(
      await player.joinGame(
        address: '127.0.0.1',
        port: host.hostPort,
        gameId: host.gameId,
        token: host.joinToken,
      ),
      isTrue,
    );
    expect(
      await player2.joinGame(
        address: '127.0.0.1',
        port: host.hostPort,
        gameId: host.gameId,
        token: host.joinToken,
        hostName: 'سارا',
      ),
      isTrue,
    );

    // میزبان هر دو بازیکن را در لابی می‌بیند.
    expect(
      await waitUntil(() => host.session.players.length == 3),
      isTrue,
      reason: 'بازیکنان باید در لابی میزبان ثبت شوند',
    );
    final joinedIds = host.session.players.map((p) => p.id).toList();
    expect(joinedIds, containsAll(<String>['h1', 'p1', 'p2']));

    // بازیکن وضعیت همگام‌شدهٔ لابی را دریافت می‌کند.
    expect(
      await waitUntil(() => player.session.players.length == 3),
      isTrue,
      reason: 'وضعیت میزبان باید به بازیکن برسد',
    );
    expect(
      await waitUntil(() => player2.session.players.length == 3),
      isTrue,
      reason: 'بازیکن تازه‌وارد باید وضعیت اولیهٔ لابی را دریافت کند',
    );

    // نسخهٔ ۱.۰.۰: دست بدون هیچ کلمه یا حرفی و بدون هیچ پیش‌نیاز متنی شروع می‌شود.
    host.startGame();
    expect(host.session.phase, GamePhase.playing);
    expect(
      await waitUntil(() => player.session.phase == GamePhase.playing),
      isTrue,
    );
    expect(
      player.session.currentRound!.index,
      host.session.currentRound!.index,
    );
    // زمان‌سنج ثابت ۷ دقیقه و همگام با میزبان است.
    expect((host.remainingMs / 1000).round(), 420);
    expect(
      ((player.remainingMs - host.remainingMs) / 1000).abs(),
      lessThanOrEqualTo(2),
      reason: 'زمان‌سنج بازیکن باید با میزبان همگام باشد',
    );

    // پاسخ‌ها از دستگاه بازیکن به میزبان می‌رسد.
    player.setAnswer(0, 'تهران');
    player.setAnswer(1, 'رضا');
    player2.setAnswer(0, 'شیراز');
    player2.setAnswer(1, 'کریم');
    host.setAnswer(0, 'تهران');
    host.setAnswer(1, 'الف');
    expect(
      await waitUntil(
        () => host.session.currentRound!.answerOf('p1', 0)?.text == 'تهران',
      ),
      isTrue,
      reason: 'پاسخ بازیکن باید روی میزبان ثبت شود',
    );

    // در بازی سه‌نفره حد نصاب استپ دو نفر است؛ یک استپ دست را تمام نمی‌کند.
    await player.requestStop();
    expect(
      await waitUntil(() => host.session.stopCount == 1),
      isTrue,
      reason: 'استپ اول باید روی میزبان ثبت شود',
    );
    expect(host.session.phase, GamePhase.playing);
    expect(
      host.session.isPlayerStopped('p1'),
      isTrue,
      reason: 'پاسخ‌های بازیکن استپ‌کرده قفل می‌شود',
    );
    expect(
      host.session.isPlayerStopped('h1'),
      isFalse,
      reason: 'با استپ یک بازیکن، پاسخ‌های میزبان نباید قفل شود',
    );
    // میزبان می‌تواند تا پایان دست به نوشتن ادامه دهد.
    host.setAnswer(1, 'الف‌رضا');
    expect(
      host.session.currentRound!.answerOf('h1', 1)!.text,
      'الف‌رضا',
    );
    // استپ دوم (بازیکن سوم) دست را برای همه تمام می‌کند.
    await player2.requestStop();
    // فاز «دریافت پاسخ‌ها» کوتاه است و بی‌درنگ به داوری می‌رسد؛ پس هر دو حالت پذیرفته است.
    final endedOnHost = await waitUntil(
      () =>
          host.session.phase == GamePhase.collecting ||
          host.session.phase == GamePhase.judging,
    );
    expect(endedOnHost, isTrue, reason: 'استپ بازیکن باید دست را تمام کند');
    expect(host.session.currentRound!.endReason, RoundEndReason.playerStop);

    // پاسخ نهایی همهٔ بازیکنان جمع‌آوری و داوری آغاز می‌شود.
    expect(
      await waitUntil(() => host.session.phase == GamePhase.judging),
      isTrue,
      reason: 'پس از رسیدن پاسخ همه، داوری باید آغاز شود',
    );
    expect(player.session.phase, GamePhase.judging);
    for (final id in <String>['h1', 'p1', 'p2']) {
      expect(
        host.submissionOf(id),
        SubmissionState.received,
        reason: 'پاسخ نهایی همهٔ بازیکنان باید دریافت شده باشد',
      );
    }

    // داوری فقط روی میزبان: p1 و h1 «تهران» گفته‌اند ⇒ تکراری و صفر امتیاز یکتا.
    // دستهٔ ۰: یک پاسخ تأییدشده در کنار یک تکراری ⇒ ۱۵ و ۵
    host.setJudgement('h1', 0, JudgementStatus.confirmed);
    host.setJudgement('p1', 0, JudgementStatus.duplicate);
    // پاسخ‌های تکمیلی بازیکن سوم (که برای فعال شدن استپ نوشته شد) رد می‌شود
    // تا امتیازها همان انتظار پیشین بماند.
    host.setJudgement('p2', 0, JudgementStatus.rejected);
    // دستهٔ ۱: دو پاسخ متفاوت تأییدشده ⇒ ۱۰ و ۱۰
    host.setJudgement('h1', 1, JudgementStatus.confirmed);
    host.setJudgement('p1', 1, JudgementStatus.confirmed);
    host.setJudgement('p2', 1, JudgementStatus.rejected);
    final scored = host.finalizeJudging();
    expect(scored.perPlayer['h1'], 25, reason: '۱۵ + ۱۰');
    expect(scored.perPlayer['p1'], 15, reason: '۵ + ۱۰');
    expect(host.session.phase, GamePhase.roundResults);

    // نتایج به بازیکنان هم می‌رسد.
    expect(
      await waitUntil(() => player.session.phase == GamePhase.roundResults),
      isTrue,
    );
    expect(player.session.totals['p1'], 15);

    // دست جدید: امتیازها حفظ و زمان‌سنج دوباره ۷ دقیقه می‌شود.
    host.startNextRound();
    expect(host.session.currentRound!.index, 2);
    expect(host.session.totals['h1'], 25);
    expect(
      await waitUntil(() => player.session.currentRound?.index == 2),
      isTrue,
    );
    expect((host.remainingMs / 1000).round(), 420);
  });

  test('دریافت تکراری Snapshot دوباره تأیید می‌شود اما پاسخ عوض نمی‌شود', () async {
    expect(await host.createGame(activeCategoryIds: [0]), isTrue);
    final socket = await Socket.connect('127.0.0.1', host.hostPort);
    final received = <NetMessage>[];
    final subscription = socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          try {
            received.add(NetMessage.parse(line));
          } on ProtocolException {
            // Ignore malformed data in the test listener.
          }
        });

    socket.add(
      utf8.encode(
        NetMessage(
          type: MsgType.hello,
          id: 'raw-hello',
          seq: 1,
          payload: {
            'gid': host.gameId,
            'token': host.joinToken,
            'pid': 'raw-player',
            'name': 'بازیکن خام',
          },
        ).encode(),
      ),
    );
    await socket.flush();
    expect(
      await waitUntil(
        () => received.any((message) => message.type == MsgType.helloAck),
      ),
      isTrue,
    );
    expect(await waitUntil(() => host.session.players.length == 2), isTrue);

    host.startGame();
    host.forceEndRound();
    expect(await waitUntil(() => host.session.phase == GamePhase.collecting), isTrue);

    Future<void> sendSnapshot(int sequence, String answer) async {
      socket.add(
        utf8.encode(
          NetMessage(
            type: MsgType.snapshot,
            id: 'raw-snapshot-$sequence',
            seq: sequence,
            payload: {
              'r': 1,
              'a': {'0': answer},
            },
          ).encode(),
        ),
      );
      await socket.flush();
    }

    await sendSnapshot(2, 'تهران');
    expect(
      await waitUntil(
        () =>
            received
                .where((message) => message.type == MsgType.snapshotAck)
                .length ==
            1,
      ),
      isTrue,
    );
    await sendSnapshot(3, 'مشهد');
    expect(
      await waitUntil(
        () =>
            received
                .where((message) => message.type == MsgType.snapshotAck)
                .length ==
            2,
      ),
      isTrue,
    );
    expect(
      host.session.currentRound!.answerOf('raw-player', 0)!.text,
      'تهران',
    );

    await subscription.cancel();
    socket.destroy();
  });

  test('بازیکن با کد نادرست وارد نمی‌شود', () async {
    expect(await host.createGame(), isTrue);
    final ok = await player.joinGame(
      address: '127.0.0.1',
      port: host.hostPort,
      gameId: host.gameId,
      token: 'ZZZZZZ',
    );
    expect(ok, isFalse);
    expect(player.lastError, isNotNull);
    expect(host.session.players.length, 1);
  });

  test('قطع اتصال بازیکن روی میزبان مشخص می‌شود', () async {
    expect(await host.createGame(), isTrue);
    expect(
      await player.joinGame(
        address: '127.0.0.1',
        port: host.hostPort,
        gameId: host.gameId,
        token: host.joinToken,
      ),
      isTrue,
    );
    expect(await waitUntil(() => host.session.players.length == 2), isTrue);
    await player.leaveGame();
    expect(
      await waitUntil(() => !host.session.isConnected('p1')),
      isTrue,
      reason: 'وضعیت اتصال بازیکن باید به‌روزرسانی شود',
    );
    // بازیکن در فهرست می‌ماند و میزبان دربارهٔ او تصمیم می‌گیرد.
    expect(host.session.players.length, 2);
  });
}
