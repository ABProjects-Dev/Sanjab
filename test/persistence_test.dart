import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sanjab/data/profile_repository.dart';
import 'package:sanjab/data/session_repository.dart';
import 'package:sanjab/domain/game_session.dart';
import 'package:sanjab/domain/models.dart';

void main() {
  late Directory tempDir;
  late SessionRepository repository;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('sanjab_test');
    repository = SessionRepository(tempDir);
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  GameSession sampleSession() {
    final session = GameSession.fresh(nowMs: 1000);
    session.addPlayer('آزاده');
    session.addPlayer('بهرام');
    session.startNewRound(nowMs: 2000);
    session.setAnswer(session.players.first.id, 0, 'کاشان');
    return session;
  }

  test('ذخیره و بازیابی وضعیت بازی فعال', () async {
    final session = sampleSession();
    final saved = await repository.save(session, nowMs: 3000);
    expect(saved, isTrue);

    final loaded = await repository.load();
    expect(loaded, isNotNull);
    expect(loaded!.players.length, 2);
    expect(loaded.phase, GamePhase.playing);
    expect(
      loaded.currentRound!.answerOf(loaded.players.first.id, 0)!.text,
      'کاشان',
    );
    expect(loaded.savedAtEpochMs, 3000);
  });

  test(
    'فایل اصلی به‌صورت اتمیک نوشته می‌شود و فایل موقت باقی نمی‌ماند',
    () async {
      await repository.save(sampleSession(), nowMs: 10);
      final names = tempDir
          .listSync()
          .map((e) => e.path.split('/').last)
          .toList(growable: false);
      expect(names, contains('active_session.json'));
      expect(names.where((n) => n.endsWith('.tmp')), isEmpty);
    },
  );

  test('در صورت خرابی فایل اصلی، نسخهٔ پشتیبان بازیابی می‌شود', () async {
    final first = sampleSession();
    await repository.save(first, nowMs: 10);
    final second = sampleSession();
    second.addPlayer('سومین');
    await repository.save(second, nowMs: 20); // This save creates the backup.

    final main = File('${tempDir.path}/active_session.json');
    main.writeAsStringSync('{ این فایل خراب است');

    final loaded = await repository.load();
    expect(loaded, isNotNull);
    // The backup belongs to the previous save (two players).
    expect(loaded!.players.length, 2);
  });

  test('پاک‌سازی داده‌های موقت همهٔ فایل‌ها را حذف می‌کند', () async {
    await repository.save(sampleSession(), nowMs: 10);
    await repository.save(sampleSession(), nowMs: 20);
    await repository.clear();
    expect(tempDir.listSync().whereType<File>(), isEmpty);
    expect(await repository.load(), isNull);
  });

  test('در نبود فایل، null برگردانده می‌شود', () async {
    expect(await repository.load(), isNull);
  });

  test(
    'وضعیت شبکه‌ای و شناسه‌های پایدار در ذخیره و بازیابی حفظ می‌شود',
    () async {
      final session = GameSession.fresh(gameId: 'g-123', hostPlayerId: 'h1');
      session.addPlayer('میزبان', id: 'h1', isHost: true);
      session.addPlayer('مهمان', id: 'p2');
      session.setConnected('p2', false);
      await repository.save(session, nowMs: 500);

      final loaded = await repository.load();
      expect(loaded!.gameId, 'g-123');
      expect(loaded.hostPlayerId, 'h1');
      expect(loaded.playerById('p2')!.id, 'p2');
      expect(loaded.isConnected('p2'), isFalse);
    },
  );

  test(
    'فایل با schema قدیمی نادیده گرفته می‌شود و بازی تازه شروع می‌شود',
    () async {
      final legacy = <String, dynamic>{
        'v': 1,
        'phase': 'playing',
        'players': [
          {'id': 'p1', 'name': 'آزاده'},
        ],
        'rounds': <dynamic>[],
      };
      await File('${tempDir.path}/active_session.json')
          .writeAsString(jsonEncode(legacy));
      expect(await repository.load(), isNull);
      // A stale file must not block saving the newer state.
      final session = sampleSession();
      expect(await repository.save(session, nowMs: 10), isTrue);
      expect((await repository.load())!.phase, GamePhase.playing);
    },
  );

  test('فایل خراب، وضعیت بازی را از بین نمی‌برد', () async {
    final session = sampleSession();
    await repository.save(session, nowMs: 10);
    await repository.save(session, nowMs: 20); // The backup copy is created.
    await File('${tempDir.path}/active_session.json').writeAsString('{خراب');
    final loaded = await repository.load();
    expect(loaded, isNotNull);
    expect(loaded!.players.length, 2);
  });

  test('پاک‌سازی، فایل اصلی و پشتیبان را حذف می‌کند', () async {
    await repository.save(sampleSession(), nowMs: 10);
    await repository.save(sampleSession(), nowMs: 20);
    await repository.clear();
    expect(File('${tempDir.path}/active_session.json').existsSync(), isFalse);
    expect(
      File('${tempDir.path}/active_session.bak.json').existsSync(),
      isFalse,
    );
    expect(await repository.load(), isNull);
  });

  test(
    'پروفایل روی فایل ذخیره و بازیابی می‌شود و شناسهٔ بازیکن تغییر نمی‌کند',
    () async {
      final profiles = ProfileRepository(tempDir);
      final first = await profiles.load();
      expect(first.playerId.isNotEmpty, isTrue);

      expect(await profiles.save(first.copyWith(displayName: 'سارا')), isTrue);
      final reloaded = await profiles.load();
      expect(reloaded.displayName, 'سارا');
      expect(reloaded.playerId, first.playerId);

      final renamed = await profiles.save(
        reloaded.copyWith(displayName: 'مینا'),
      );
      expect(renamed, isTrue);
      final again = await profiles.load();
      expect(again.displayName, 'مینا');
      expect(again.playerId, first.playerId);
    },
  );
}
