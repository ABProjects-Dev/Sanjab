/// End-to-end test: two real controllers (host and player) on localhost with
/// real TCP sockets, from creating the game through judging to results.
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

  test('بازی تک‌نفره از شروع تا استپ و داوری کامل می‌شود', () async {
    expect(await host.createGame(), isTrue);
    expect(host.session.activePlayerCount, 1);

    host.startGame();
    expect(host.session.phase, GamePhase.playing);
    for (final category in host.activeCategories) {
      host.setAnswer(category.id, 'آب');
    }
    expect(host.iCanStop, isTrue);

    await host.requestStop();
    expect(host.session.phase, GamePhase.judging);
    expect(host.session.allSnapshotsReceived, isTrue);

    for (final category in host.activeCategories) {
      host.setJudgement('h1', category.id, JudgementStatus.confirmed);
    }
    host.finalizeJudging();
    expect(host.session.phase, GamePhase.roundResults);
  });

  test('جریان کامل بازی سه‌نفره: اتصال، دست، استپ، داوری و نتایج', () async {
    // Stop becomes available once every answer field of the player holds at
    // least two characters; to keep this flow quick the session uses two
    // active categories.
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

    // The host sees both players in the lobby.
    expect(
      await waitUntil(() => host.session.players.length == 3),
      isTrue,
      reason: 'بازیکنان باید در لابی میزبان ثبت شوند',
    );
    final joinedIds = host.session.players.map((p) => p.id).toList();
    expect(joinedIds, containsAll(<String>['h1', 'p1', 'p2']));

    // The player receives the synced lobby state.
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

    // A round starts without a word, letter or any text prerequisite.
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
    // The timer is fixed at seven minutes and synced with the host.
    expect((host.remainingMs / 1000).round(), 420);
    expect(
      ((player.remainingMs - host.remainingMs) / 1000).abs(),
      lessThanOrEqualTo(2),
      reason: 'زمان‌سنج بازیکن باید با میزبان همگام باشد',
    );

    // Answers travel from the player device to the host.
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

    // In a three-player game the threshold is two, so one Stop does not end it.
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
    // The host may keep writing until the round ends.
    host.setAnswer(1, 'الف‌رضا');
    expect(
      host.session.currentRound!.answerOf('h1', 1)!.text,
      'الف‌رضا',
    );
    // The second Stop ends the round for everyone.
    await player2.requestStop();
    // The collecting phase is brief and moves straight to judging, so either phase is accepted.
    final endedOnHost = await waitUntil(
      () =>
          host.session.phase == GamePhase.collecting ||
          host.session.phase == GamePhase.judging,
    );
    expect(endedOnHost, isTrue, reason: 'استپ بازیکن باید دست را تمام کند');
    expect(host.session.currentRound!.endReason, RoundEndReason.playerStop);

    // Every final answer is collected and judging begins.
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

    // Judging happens on the host only: p1 and h1 both said Tehran, so duplicate.
    // Category 0: one confirmed answer beside a duplicate scores 15 and 5.
    host.setJudgement('h1', 0, JudgementStatus.confirmed);
    host.setJudgement('p1', 0, JudgementStatus.duplicate);
    // The third player's extra answers, typed only to enable Stop, are rejected
    // so the expected scores stay unchanged.
    host.setJudgement('p2', 0, JudgementStatus.rejected);
    // Category 1: two different confirmed answers score 10 and 10.
    host.setJudgement('h1', 1, JudgementStatus.confirmed);
    host.setJudgement('p1', 1, JudgementStatus.confirmed);
    host.setJudgement('p2', 1, JudgementStatus.rejected);
    final scored = host.finalizeJudging();
    expect(scored.perPlayer['h1'], 25, reason: '۱۵ + ۱۰');
    expect(scored.perPlayer['p1'], 15, reason: '۵ + ۱۰');
    expect(host.session.phase, GamePhase.roundResults);

    // Results reach the player devices too.
    expect(
      await waitUntil(() => player.session.phase == GamePhase.roundResults),
      isTrue,
    );
    expect(player.session.totals['p1'], 15);

    // A new round keeps the scores and resets the timer to seven minutes.
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

  test('قطع اتصال موقت بازیکن او را از roster کم نمی‌کند و اتصال مجدد ممکن است', () async {
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
    // The player stays in the roster and the member count.
    expect(host.session.players.length, 2);
    expect(host.session.activePlayerCount, 2);

    expect(
      await player.joinGame(
        address: '127.0.0.1',
        port: host.hostPort,
        gameId: host.gameId,
        token: host.joinToken,
      ),
      isTrue,
    );
    expect(await waitUntil(() => host.session.isConnected('p1')), isTrue);
    expect(host.session.activePlayerCount, 2);
  });

  test('خروج صریح بازیکن در میانهٔ بازی حفظ تاریخچه را دارد و مانع ورود دوباره می‌شود', () async {
    expect(await host.createGame(activeCategoryIds: [0]), isTrue);
    expect(
      await player.joinGame(
        address: '127.0.0.1',
        port: host.hostPort,
        gameId: host.gameId,
        token: host.joinToken,
      ),
      isTrue,
    );
    expect(await waitUntil(() => host.session.activePlayerCount == 2), isTrue);
    host.startGame();
    expect(await waitUntil(() => player.session.phase == GamePhase.playing), isTrue);

    await player.leaveRoom();
    expect(await waitUntil(() => host.session.hasPlayerLeft('p1')), isTrue);
    expect(host.session.activePlayerCount, 1);
    expect(host.session.playerById('p1'), isNotNull);

    expect(
      await player.joinGame(
        address: '127.0.0.1',
        port: host.hostPort,
        gameId: host.gameId,
        token: host.joinToken,
      ),
      isFalse,
    );
    expect(host.session.activePlayerCount, 1);
  });

  test('خروج صریح بازیکن از اتاق، عضویت او را در میزبان حذف می‌کند', () async {
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
    expect(await waitUntil(() => host.session.activePlayerCount == 2), isTrue);

    await player.leaveRoom();
    expect(await waitUntil(() => host.session.activePlayerCount == 1), isTrue);
    expect(host.session.playerById('p1'), isNull);
    expect(host.session.players.map((p) => p.id), contains('h1'));
  });
}
