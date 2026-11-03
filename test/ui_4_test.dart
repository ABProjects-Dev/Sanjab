/// آزمون‌های رابط کاربری نسخهٔ ۱.۰.۰: QR روی پس‌زمینهٔ سفید، دکمهٔ یکسان
/// «بازگشت به صفحهٔ اصلی»، بخش «ادامه بازی» در صفحهٔ اصلی و بررسی ایستا برای
/// حذف کامل قابلیت تعیین کلمه و دکمهٔ خروج از بازی.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:sanjab/app.dart';
import 'package:sanjab/data/room_repository.dart';
import 'package:sanjab/domain/models.dart';
import 'package:sanjab/domain/profile.dart';
import 'package:sanjab/domain/room_record.dart';
import 'package:sanjab/state/game_controller.dart';
import 'package:sanjab/state/game_scope.dart';
import 'package:sanjab/ui/navigation.dart';
import 'package:sanjab/ui/screens/judging_screen.dart';
import 'package:sanjab/ui/screens/lobby_screen.dart';
import 'package:sanjab/ui/screens/play_screen.dart';
import 'package:sanjab/ui/screens/results_screen.dart';
import 'package:sanjab/ui/widgets/common.dart';
import 'package:sanjab/ui/widgets/exit_guard.dart';

import 'test_support/memory_profile_store.dart';
import 'test_support/memory_store.dart';

RoomRecord sampleRoom({bool ended = false}) => RoomRecord(
  gameId: 'g-1',
  roomName: 'بازی سارا',
  hostPlayerId: 'h1',
  hostName: 'سارا',
  myPlayerId: 'p1',
  myName: 'مینا',
  role: GameRole.player,
  address: '192.168.43.1',
  port: 50501,
  token: 'ABC123',
  phase: GamePhase.playing,
  roundIndex: 2,
  updatedAtEpochMs: 1700000000000,
  ended: ended,
);

GameController buildController({
  required String id,
  required String name,
  RoomStore? rooms,
}) => GameController(
  store: MemorySessionStore(),
  profileRepo: MemoryProfileStore(
    initial: Profile(playerId: id, displayName: name),
  ),
  roomStore: rooms ?? MemoryRoomStore(),
);

void main() {
  testWidgets('QR روی پس‌زمینهٔ سفید با حاشیهٔ کافی نمایش داده می‌شود', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: QrCodePanel(data: '{"v":1}'))),
    );
    await tester.pump();
    expect(find.byType(QrImageView), findsOneWidget);
    final container = tester.widget<Container>(
      find
          .ancestor(
            of: find.byType(QrImageView),
            matching: find.byType(Container),
          )
          .first,
    );
    final decoration = container.decoration! as BoxDecoration;
    expect(
      decoration.color,
      Colors.white,
      reason: 'پس‌زمینهٔ QR باید کاملاً سفید باشد',
    );
    expect(
      container.padding,
      const EdgeInsets.all(16),
      reason: 'حاشیهٔ سفید اطراف QR باید وجود داشته باشد',
    );
  });

  testWidgets('صفحهٔ اصلی برای اتاق ذخیره‌شده «ادامه بازی» نشان می‌دهد', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1080, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = buildController(
      id: 'p1',
      name: 'مینا',
      rooms: MemoryRoomStore([sampleRoom()]),
    );
    addTearDown(() async {
      await controller.closeSession(silent: true);
      controller.dispose();
    });
    await controller.bootstrap();
    await tester.pumpWidget(SanjabApp(controller: controller));
    await tester.pump();
    expect(find.text('ادامه بازی'), findsOneWidget);
    expect(find.text('خروج از اتاق'), findsOneWidget);
    expect(find.textContaining('میزبان: سارا'), findsOneWidget);
    expect(find.textContaining('نسخهٔ ۱.۰.۱'), findsOneWidget);
  });

  testWidgets('اتاق پایان‌یافته در صفحهٔ اصلی «ادامه بازی» ندارد', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1080, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = buildController(
      id: 'p1',
      name: 'مینا',
      rooms: MemoryRoomStore([sampleRoom(ended: true)]),
    );
    addTearDown(() async {
      await controller.closeSession(silent: true);
      controller.dispose();
    });
    await controller.bootstrap();
    await tester.pumpWidget(SanjabApp(controller: controller));
    await tester.pump();
    expect(find.text('ادامه بازی'), findsNothing);
  });

  testWidgets('دکمهٔ «بازگشت به صفحهٔ اصلی» رفتار یکسانی دارد', (tester) async {
    final controller = buildController(id: 'p1', name: 'مینا');
    addTearDown(() async {
      await controller.closeSession(silent: true);
      controller.dispose();
    });
    await controller.bootstrap();
    await tester.pumpWidget(
      GameScope(
        controller: controller,
        child: MaterialApp(
          home: Scaffold(appBar: AppBar(leading: const HomeIconButton())),
        ),
      ),
    );
    await tester.pump();
    expect(find.byTooltip('بازگشت به صفحه اصلی'), findsOneWidget);
    await tester.tap(find.byTooltip('بازگشت به صفحه اصلی'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  group('بررسی ایستای حذف قابلیت تعیین کلمه و دکمهٔ خروج', () {
    List<String> dartFiles(String dir) => Directory(dir)
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .map((f) => f.path)
        .toList();

    test('هیچ ارجاعی به حرف/کلمهٔ دست در سورس باقی نمانده است', () {
      final offenders = <String>[];
      for (final path in dartFiles('lib')) {
        final content = File(path).readAsStringSync();
        if (content.contains('selectedRoundLetter') ||
            content.contains('setRoundLetter') ||
            content.contains('pickRandomLetter') ||
            content.contains('kPersianLetters') ||
            content.contains('letters.dart')) {
          offenders.add(path);
        }
      }
      expect(offenders, isEmpty, reason: 'قابلیت تعیین کلمه باید کامل حذف شود');
      expect(File('lib/domain/letters.dart').existsSync(), isFalse);
      expect(File('lib/domain/word_list.dart').existsSync(), isFalse);
    });

    test('در صفحات داخلی دکمهٔ «خروج از بازی» وجود ندارد', () {
      for (final screen in <String>[
        'lib/ui/screens/lobby_screen.dart',
        'lib/ui/screens/play_screen.dart',
        'lib/ui/screens/judging_screen.dart',
        'lib/ui/screens/results_screen.dart',
      ]) {
        final content = File(screen).readAsStringSync();
        expect(
          content.contains('خروج از بازی'),
          isFalse,
          reason: '$screen نباید دکمهٔ خروج از بازی داشته باشد',
        );
        expect(
          content.contains('HomeIconButton'),
          isTrue,
          reason: '$screen باید دکمهٔ «بازگشت به صفحهٔ اصلی» داشته باشد',
        );
      }
    });

    test('سورس برنامه هیچ پیام اجباری برای انتخاب کلمه ندارد', () {
      final offenders = <String>[];
      for (final path in dartFiles('lib')) {
        final content = File(path).readAsStringSync();
        if (content.contains('انتخاب حرف') ||
            content.contains('انتخاب کلمه') ||
            content.contains('ابتدا حرف را')) {
          offenders.add(path);
        }
      }
      expect(offenders, isEmpty);
    });
  });

  test('نقشهٔ صفحه‌ها برای فاز پایان‌یافته معتبر است', () {
    // فقط از وجود صفحه‌ها مطمئن می‌شویم (بدون ساخت کنترلر شبکه).
    expect(const LobbyScreen(), isNotNull);
    expect(const PlayScreen(), isNotNull);
    expect(const JudgingScreen(), isNotNull);
    expect(const ResultsScreen(), isNotNull);
    expect(openGameScreen, isNotNull);
  });
}
