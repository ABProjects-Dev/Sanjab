/// آزمون‌های نسخهٔ ۱.۰.۰: ذخیرهٔ اتاق، بازگشت به صفحهٔ اصلی، «ادامه بازی»
/// برای میزبان و بازیکن، خروج صریح از اتاق و پایان رسمی بازی.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sanjab/data/room_repository.dart';
import 'package:sanjab/data/session_repository.dart';
import 'package:sanjab/domain/game_session.dart';
import 'package:sanjab/domain/models.dart';
import 'package:sanjab/domain/profile.dart';
import 'package:sanjab/domain/room_record.dart';
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

GameController buildController({
  required String id,
  required String name,
  SessionStore? store,
  RoomStore? rooms,
  int Function()? clock,
}) => GameController(
  store: store ?? MemorySessionStore(),
  profileRepo: MemoryProfileStore(
    initial: Profile(playerId: id, displayName: name),
  ),
  roomStore: rooms ?? MemoryRoomStore(),
  clock: clock,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ذخیرهٔ اتاق روی دستگاه میزبان', () {
    test('ایجاد بازی، رکورد اتاق میزبان را پایدار ذخیره می‌کند', () async {
      final rooms = MemoryRoomStore();
      final host = buildController(id: 'h1', name: 'سارا', rooms: rooms);
      await host.bootstrap();
      await host.createGame();
      expect(rooms.records.length, 1);
      final room = rooms.records.single;
      expect(room.role, GameRole.host);
      expect(room.myPlayerId, 'h1');
      expect(room.gameId, host.gameId);
      expect(room.token, host.joinToken);
      expect(room.port, host.hostPort);
      expect(room.phase, GamePhase.lobby);
      expect(room.resumable, isFalse, reason: 'در لابی بازی قابل ادامه نیست');
      await host.closeSession(silent: true);
      host.dispose();
    });

    test('شروع دست، وضعیت و زمان باقی‌مانده را ذخیره می‌کند', () async {
      final rooms = MemoryRoomStore();
      final host = buildController(id: 'h1', name: 'سارا', rooms: rooms);
      await host.bootstrap();
      await host.createGame();
      host.session.addPlayer('مینا', id: 'p1');
      host.startGame();
      host.setAnswer(0, 'تهران');
      await host.flush();
      final room = rooms.records.single;
      expect(room.phase, GamePhase.playing);
      expect(room.roundIndex, 1);
      expect(room.myAnswers[0], 'تهران');
      expect(room.remainingMs, greaterThan(400000));
      expect(room.sessionSnapshot, isNotNull);
      await host.closeSession(silent: true);
      host.dispose();
    });

    test('بازگشت به صفحهٔ اصلی، اتاق و جلسه را حفظ می‌کند', () async {
      final rooms = MemoryRoomStore();
      final host = buildController(id: 'h1', name: 'سارا', rooms: rooms);
      await host.bootstrap();
      await host.createGame();
      host.session.addPlayer('مینا', id: 'p1');
      host.startGame();
      await host.backToHome();
      expect(host.role, GameRole.host, reason: 'نقش میزبان حفظ می‌شود');
      expect(host.session.phase, GamePhase.playing, reason: 'دست پایان نمی‌یابد');
      expect(host.netStatus, NetStatus.hosting, reason: 'سرور محلی فعال می‌ماند');
      expect(host.savedRooms.length, 1);
      await host.closeSession(silent: true);
      host.dispose();
    });
  });

  group('ادامه بازی میزبان', () {
    test('پس از بسته‌شدن برنامه، جلسه با پاسخ‌ها و زمان باقی‌مانده بازیابی می‌شود', () async {
      final store = MemorySessionStore();
      final rooms = MemoryRoomStore();
      final profile = MemoryProfileStore(
        initial: const Profile(playerId: 'h1', displayName: 'سارا'),
      );

      final first = GameController(
        store: store,
        profileRepo: profile,
        roomStore: rooms,
      );
      await first.bootstrap();
      await first.createGame();
      first.session.addPlayer('مینا', id: 'p1');
      first.startGame();
      first.setAnswer(0, 'تهران');
      final remainingBefore = first.remainingMs;
      await first.flush();
      // خاموش شدن ناگهانی برنامه: بدون closeSession منطقی، فقط توقف کنترلر.
      first.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 200));

      final second = GameController(
        store: store,
        profileRepo: profile,
        roomStore: rooms,
      );
      await second.bootstrap();
      expect(second.savedRooms, isNotEmpty, reason: 'اتاق ذخیره‌شده یافت می‌شود');
      final room = second.savedRooms.first;
      expect(room.resumable, isTrue);
      final ok = await second.resumeRoom(room);
      expect(ok, isTrue, reason: second.lastError ?? 'بازیابی باید موفق شود');
      expect(second.isHost, isTrue);
      expect(second.netStatus, NetStatus.hosting);
      expect(second.hostPort, greaterThan(0), reason: 'سرور محلی دوباره فعال شد');
      expect(second.session.phase, GamePhase.playing);
      expect(second.session.currentRound!.answerOf('h1', 0)!.text, 'تهران');
      expect(
        (second.remainingMs - remainingBefore).abs(),
        lessThan(30000),
        reason: 'زمان باقی‌مانده باید بازیابی شود',
      );
      await second.closeSession(silent: true);
      second.dispose();
    });

    test('بازیابی در مرحلهٔ داوری همان مرحله را برمی‌گرداند', () async {
      final rooms = MemoryRoomStore();
      final host = buildController(id: 'h1', name: 'سارا', rooms: rooms);
      await host.bootstrap();
      await host.createGame();
      host.session.addPlayer('مینا', id: 'p1');
      host.startGame();
      host.setAnswer(0, 'تهران');
      host.forceEndRound();
      // بازیکن در این آزمون کلاینت واقعی ندارد؛ دریافت پاسخ‌هایش را علامت می‌زنیم.
      host.session.markSnapshotReceived('p1');
      host.session.tryStartJudging();
      expect(host.session.phase, GamePhase.judging);
      await host.flush();
      final room = rooms.records.single;
      expect(room.phase, GamePhase.judging);
      await host.closeSession(silent: true);
      host.dispose();

      final restored = buildController(id: 'h1', name: 'سارا', rooms: rooms);
      await restored.bootstrap();
      final ok = await restored.resumeRoom(restored.savedRooms.first);
      expect(ok, isTrue);
      expect(restored.session.phase, GamePhase.judging);
      await restored.closeSession(silent: true);
      restored.dispose();
    });

    test('رکورد تکراری برای یک بازیکن در یک اتاق ساخته نمی‌شود', () async {
      final rooms = MemoryRoomStore();
      final host = buildController(id: 'h1', name: 'سارا', rooms: rooms);
      await host.bootstrap();
      await host.createGame();
      await host.flush();
      await host.flush();
      await host.flush();
      expect(rooms.records.length, 1);
      await host.closeSession(silent: true);
      host.dispose();
    });
  });

  group('ادامه بازی بازیکن', () {
    test('بازیکن پس از بسته‌شدن برنامه به همان اتاق برمی‌گردد بدون عضو تکراری', () async {
      final hostRooms = MemoryRoomStore();
      final host = buildController(id: 'h1', name: 'سارا', rooms: hostRooms);
      await host.bootstrap();
      await host.createGame();

      final playerStore = MemorySessionStore();
      final playerRooms = MemoryRoomStore();
      final playerProfile = MemoryProfileStore(
        initial: const Profile(playerId: 'p1', displayName: 'مینا'),
      );
      final first = GameController(
        store: playerStore,
        profileRepo: playerProfile,
        roomStore: playerRooms,
      );
      await first.bootstrap();
      final joined = await first.joinGame(
        address: '127.0.0.1',
        port: host.hostPort,
        gameId: host.gameId,
        token: host.joinToken,
        hostName: 'سارا',
      );
      expect(joined, isTrue);
      expect(
        await waitUntil(() => host.session.players.length == 2),
        isTrue,
      );
      host.startGame();
      expect(
        await waitUntil(() => first.session.phase == GamePhase.playing),
        isTrue,
      );
      first.setAnswer(0, 'مشهد');
      expect(
        await waitUntil(
          () => host.session.currentRound?.answerOf('p1', 0)?.text == 'مشهد',
        ),
        isTrue,
      );
      expect(playerRooms.records.length, 1);
      final savedRoom = playerRooms.records.single;
      expect(savedRoom.role, GameRole.player);
      expect(savedRoom.address, '127.0.0.1');
      expect(savedRoom.port, host.hostPort);

      // بسته شدن ناگهانی برنامهٔ بازیکن.
      await first.leaveGame();
      first.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 200));

      final second = GameController(
        store: playerStore,
        profileRepo: playerProfile,
        roomStore: playerRooms,
      );
      await second.bootstrap();
      expect(second.savedRooms.length, 1);
      final ok = await second.resumeRoom(second.savedRooms.first);
      expect(ok, isTrue, reason: second.lastError ?? 'اتصال دوباره باید موفق شود');
      expect(
        await waitUntil(() => second.session.players.length == 2),
        isTrue,
      );
      expect(
        host.session.players.where((p) => p.id == 'p1').length,
        1,
        reason: 'بازیکن تکراری ثبت نمی‌شود',
      );
      expect(second.myPlayerId, 'p1');
      expect(
        second.myAnswer(0),
        'مشهد',
        reason: 'پاسخ قبلی بازیکن حفظ می‌شود',
      );

      await second.leaveGame();
      second.dispose();
      await host.closeSession(silent: true);
      host.dispose();
    });

    test('اگر میزبان بازی را بازیابی نکرده باشد، پیام روشن داده می‌شود', () async {
      final rooms = MemoryRoomStore();
      final stale = RoomRecord(
        gameId: 'g-old',
        roomName: 'بازی سارا',
        hostPlayerId: 'h1',
        hostName: 'سارا',
        myPlayerId: 'p9',
        myName: 'مینا',
        role: GameRole.player,
        address: '127.0.0.1',
        port: 65533,
        token: 'ABCDEF',
        phase: GamePhase.playing,
        roundIndex: 1,
        updatedAtEpochMs: DateTime.now().millisecondsSinceEpoch,
      );
      await rooms.upsert(stale);
      final player = buildController(id: 'p9', name: 'مینا', rooms: rooms);
      await player.bootstrap();
      final ok = await player.resumeRoom(player.savedRooms.first);
      expect(ok, isFalse);
      expect(player.lastError, contains('در دسترس نیست'));
      expect(
        player.savedRooms.length,
        1,
        reason: 'رکورد برای تلاش دوباره حفظ می‌شود',
      );
      player.dispose();
    });
  });

  group('پایان رسمی بازی و خروج از اتاق', () {
    test('پایان بازی توسط میزبان همه را به صفحهٔ اصلی می‌برد و اتاق را حذف می‌کند', () async {
      final hostRooms = MemoryRoomStore();
      final host = buildController(id: 'h1', name: 'سارا', rooms: hostRooms);
      await host.bootstrap();
      await host.createGame();

      final playerRooms = MemoryRoomStore();
      final player = buildController(id: 'p1', name: 'مینا', rooms: playerRooms);
      await player.bootstrap();
      await player.joinGame(
        address: '127.0.0.1',
        port: host.hostPort,
        gameId: host.gameId,
        token: host.joinToken,
        hostName: 'سارا',
      );
      expect(await waitUntil(() => host.session.players.length == 2), isTrue);
      host.startGame();
      expect(
        await waitUntil(() => player.session.phase == GamePhase.playing),
        isTrue,
      );

      await host.finishGame();

      expect(
        await waitUntil(
          () => player.role == GameRole.none && player.session.phase == GamePhase.lobby,
        ),
        isTrue,
        reason: 'بازیکن آنلاین باید به صفحهٔ اصلی برگردد',
      );
      expect(player.savedRooms, isEmpty, reason: 'اتاق پایان‌یافته قابل ادامه نیست');
      expect(host.savedRooms, isEmpty);
      expect(
        host.netStatus,
        NetStatus.offline,
        reason: 'وضعیت شبکه پس از پایان رسمی غیرفعال است',
      );
      player.dispose();
      host.dispose();
    });

    test('خروج صریح از اتاق فقط همان اتاق را حذف می‌کند', () async {
      final rooms = MemoryRoomStore();
      final controller = buildController(id: 'p1', name: 'مینا', rooms: rooms);
      await controller.bootstrap();
      final now = DateTime.now().millisecondsSinceEpoch;
      final r1 = RoomRecord(
        gameId: 'g1',
        roomName: 'اتاق یک',
        hostPlayerId: 'h1',
        hostName: 'سارا',
        myPlayerId: 'p1',
        myName: 'مینا',
        role: GameRole.player,
        address: '10.0.0.5',
        port: 50501,
        token: 'AAA111',
        phase: GamePhase.playing,
        roundIndex: 2,
        updatedAtEpochMs: now,
      );
      final r2 = RoomRecord(
        gameId: 'g2',
        roomName: 'اتاق دو',
        hostPlayerId: 'h2',
        hostName: 'رضا',
        myPlayerId: 'p1',
        myName: 'مینا',
        role: GameRole.player,
        address: '10.0.0.9',
        port: 50501,
        token: 'BBB222',
        phase: GamePhase.playing,
        roundIndex: 1,
        updatedAtEpochMs: now + 1,
      );
      await rooms.upsert(r1);
      await rooms.upsert(r2);
      await controller.reloadSavedRooms();
      expect(controller.savedRooms.length, 2);
      await controller.leaveRoom(r2);
      expect(controller.savedRooms.length, 1);
      expect(controller.savedRooms.single.gameId, 'g1');
      controller.dispose();
    });
  });

  group('مهاجرت نشست ذخیره‌شدهٔ قدیمی', () {
    test('نشست ذخیره‌شدهٔ نسخهٔ قبل پس از آپدیت قابل ادامه است', () async {
      // دادهٔ شبیه‌سازی‌شدهٔ نشست قدیمی: schemaVersion = 2 و کلید حرف در دست.
      final legacyJson = <String, dynamic>{
        'v': 2,
        'phase': 'playing',
        'seq': 2,
        'gid': 'g-legacy',
        'hp': 'h1',
        'created': 1000,
        'saved': 2000,
        'players': [
          {'id': 'h1', 'name': 'سارا', 'h': true},
          {'id': 'p1', 'name': 'مینا', 'h': false},
        ],
        'conn': ['h1', 'p1'],
        'config': {
          'c': [0, 1, 2],
        },
        'rounds': [
          {
            'i': 1,
            'l': 'ب',
            'st': 1000,
            'en': DateTime.now().millisecondsSinceEpoch + 400000,
            'a': <String, dynamic>{},
            'sp': <String>[],
            'rs': <String>[],
            'as': ['h1', 'p1'],
            'pr': null,
            'er': null,
            'j': false,
            'sc': <String, int>{},
          },
        ],
        'totals': {'h1': 0, 'p1': 0},
      };
      final store = MemorySessionStore(GameSession.fromJson(legacyJson));
      final rooms = MemoryRoomStore();
      final controller = GameController(
        store: store,
        profileRepo: MemoryProfileStore(
          initial: const Profile(playerId: 'h1', displayName: 'سارا'),
        ),
        roomStore: rooms,
      );
      await controller.bootstrap();
      expect(
        controller.savedRooms,
        isNotEmpty,
        reason: 'رکورد اتاق برای نشست قدیمی ساخته می‌شود',
      );
      final room = controller.savedRooms.first;
      expect(room.gameId, 'g-legacy');
      expect(room.role, GameRole.host);
      expect(room.resumable, isTrue);
      final ok = await controller.resumeRoom(room);
      expect(ok, isTrue, reason: controller.lastError ?? '');
      expect(controller.session.phase, GamePhase.playing);
      expect(controller.joinToken, isNotEmpty, reason: 'توکن تازه ساخته می‌شود');
      await controller.closeSession(silent: true);
      controller.dispose();
    });

    test('JSON نسخهٔ قبل (با کلید حرف) بدون خطا خوانده می‌شود', () {
      final legacy = <String, dynamic>{
        'i': 1,
        'l': 'ب',
        'st': 0,
        'en': 420000,
        'a': <String, dynamic>{},
        'sp': <String>[],
        'rs': <String>[],
        'as': <String>[],
        'pr': null,
        'er': null,
        'j': false,
        'sc': <String, int>{},
      };
      final round = RoundRecord.fromJson(legacy);
      expect(round.index, 1);
      expect(round.endEpochMs, 420000);
    });
  });

  group('اعتبارسنجی QR', () {
    test('QR معتبر روی دستگاهی که هنوز نشستی ندارد پذیرفته می‌شود', () async {
      const fixed = 1700000000000;
      final controller = buildController(
        id: 'p1',
        name: 'مینا',
        clock: () => fixed,
      );
      await controller.bootstrap();
      final payload = <String, dynamic>{
        'v': 1,
        'type': 'sm_join',
        'gameId': 'g-1',
        'host': '192.168.43.1',
        'port': 50501,
        'token': 'ABC123',
        'hostName': 'سارا',
        'createdAt': fixed,
        'expiresAt': fixed + 60000,
      };
      expect(controller.qrPayloadValid(payload), isTrue);
      expect(
        controller.qrPayloadValid({...payload, 'expiresAt': fixed - 1000}),
        isFalse,
        reason: 'QR منقضی رد می‌شود',
      );
      expect(
        controller.qrPayloadValid({...payload, 'host': ''}),
        isFalse,
      );
      expect(controller.qrPayloadValid({...payload, 'port': 0}), isFalse);
      expect(controller.qrPayloadValid({...payload, 'token': ''}), isFalse);
      expect(controller.qrPayloadValid(null), isFalse);
      controller.dispose();
    });
  });

  group('ذخیره‌سازی فایل اتاق‌ها', () {
    test('درج/به‌روزرسانی، حذف و بازیابی از پشتیبان', () async {
      final dir = await Directory.systemTemp.createTemp('rooms_test');
      addTearDown(() async {
        if (dir.existsSync()) await dir.delete(recursive: true);
      });
      final repo = RoomRepository(dir);
      final base = RoomRecord(
        gameId: 'g1',
        roomName: 'اتاق',
        hostPlayerId: 'h1',
        hostName: 'سارا',
        myPlayerId: 'p1',
        myName: 'مینا',
        role: GameRole.player,
        address: '10.0.0.2',
        port: 50501,
        token: 'TOK123',
        phase: GamePhase.playing,
        roundIndex: 1,
        updatedAtEpochMs: 100,
      );
      expect(await repo.upsert(base), isTrue);
      expect(await repo.upsert(base.copyWith(roundIndex: 2)), isTrue);
      final loaded = await repo.loadAll();
      expect(loaded.length, 1, reason: 'رکورد تکراری ساخته نمی‌شود');
      expect(loaded.single.roundIndex, 2);

      // خراب‌کردن فایل اصلی: باید از نسخهٔ پشتیبان خوانده شود.
      final main = File('${dir.path}/rooms.json');
      await main.writeAsString('{ خراب');
      final recovered = await repo.loadAll();
      expect(recovered.length, 1, reason: 'بازیابی از فایل پشتیبان');

      expect(await repo.remove('g1', 'p1'), isTrue);
      expect((await repo.loadAll()), isEmpty);
      await repo.clear();
    });
  });
}
