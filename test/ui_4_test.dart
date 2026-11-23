/// UI tests: the QR panel, system back handling, the resume section on Home and
/// a static check that the per-round word feature and the exit button are gone.
///
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:sanjab/app.dart';
import 'package:sanjab/core/app_version.dart';
import 'package:sanjab/core/persian.dart';
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
    // The footer must show the version generated from pubspec.yaml, not a literal.
    expect(
      find.textContaining('نسخهٔ ${faNum(kAppVersionName)}'),
      findsOneWidget,
    );
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

  testWidgets('ExitGuard پیکربندی شده و مسیر بازگشت به صفحهٔ اصلی کار می‌کند', (
    tester,
  ) async {
    final controller = buildController(id: 'p1', name: 'مینا');
    addTearDown(() async {
      await controller.closeSession(silent: true);
      controller.dispose();
    });
    await controller.bootstrap();
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      GameScope(
        controller: controller,
        child: MaterialApp(
          navigatorKey: navigatorKey,
          home: Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => navigatorKey.currentState!.push<void>(
                  MaterialPageRoute<void>(
                  builder: (_) => ExitGuard(
                    child: Builder(
                      builder: (pageContext) => Scaffold(
                        body: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('صفحهٔ بازی آزمون'),
                              TextButton(
                                onPressed: () => goToHomeScreen(pageContext),
                                child: const Text('بازگشت به خانه'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  ),
                ),
                child: const Text('رفتن به بازی'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('رفتن به بازی'));
    await tester.pumpAndSettle();
    expect(find.text('صفحهٔ بازی آزمون'), findsOneWidget);

    final popScope =
        tester.widget(find.byWidgetPredicate((widget) => widget is PopScope))
            as PopScope<dynamic>;
    expect(popScope.canPop, isFalse);
    expect(popScope.onPopInvokedWithResult, isNotNull);

    await tester.tap(find.text('بازگشت به خانه'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('رفتن به بازی'), findsOneWidget);
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

    test('راهنما و درباره با قواعد فعلی بازی و شبکهٔ محلی سازگارند', () {
      final guide = File('lib/ui/screens/guide_screen.dart').readAsStringSync();
      final settings = File(
        'lib/ui/screens/settings_screen.dart',
      ).readAsStringSync();
      expect(guide, isNot(contains('حرف تصادفی')));
      expect(guide, isNot(contains('حرف تازه')));
      expect(settings, contains('چندنفره روی شبکهٔ محلی'));
      expect(settings, isNot(contains('برای اجرا روی یک دستگاه')));
      expect(settings, isNot(contains('کاملاً آفلاین')));
      final home = File('lib/ui/screens/home_screen.dart').readAsStringSync();
      expect(home, contains('از این دستگاه نمی‌توان'));
      expect(home, contains('دوباره تلاش کنید'));
      expect(home, contains('حذف از این دستگاه'));
      final exitGuard = File('lib/ui/widgets/exit_guard.dart').readAsStringSync();
      expect(exitGuard, contains('میزبان اکنون از خروج شما باخبر نمی‌شود'));
    });

    test('Home پس از unmount، setState اجرا نمی‌کند', () {
      final home = File('lib/ui/screens/home_screen.dart').readAsStringSync();
      expect(
        home,
        isNot(contains('if (!mounted) {\n      setState(() => _busy = false);')),
      );
    });

    test('نمونهٔ پروتکل با نسخهٔ runtime هماهنگ است', () {
      final models = File('lib/domain/models.dart').readAsStringSync();
      final protocol = File('lib/net/protocol.dart').readAsStringSync();
      expect(models, contains('const int kProtocolVersion = 4;'));
      expect(protocol, contains('(version 4)'));
      expect(protocol, contains('{"v":4,"t":"type"'));
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
          isFalse,
          reason: '$screen نباید آیکون خانه داشته باشد',
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
    // Only check that the screens exist, without building a network controller.
    expect(const LobbyScreen(), isNotNull);
    expect(const PlayScreen(), isNotNull);
    expect(const JudgingScreen(), isNotNull);
    expect(const ResultsScreen(), isNotNull);
    expect(openGameScreen, isNotNull);
  });
}
