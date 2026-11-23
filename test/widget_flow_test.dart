/// Widget tests: Home, Profile and Guide.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanjab/app.dart';
import 'package:sanjab/domain/profile.dart';
import 'package:sanjab/state/game_controller.dart';
import 'package:sanjab/state/game_scope.dart';
import 'package:sanjab/ui/screens/profile_screen.dart';
import 'package:sanjab/ui/screens/results_screen.dart';

import 'test_support/memory_profile_store.dart';
import 'test_support/memory_store.dart';

void main() {
  late MemorySessionStore store;
  late MemoryProfileStore profiles;
  late GameController controller;

  setUp(() {
    store = MemorySessionStore();
    profiles = MemoryProfileStore();
    controller = GameController(store: store, profileRepo: profiles);
  });

  tearDown(() async {
    await controller.closeSession(silent: true);
    controller.dispose();
  });

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1080, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await controller.bootstrap();
    await tester.pumpWidget(SanjabApp(controller: controller));
    await tester.pump();
  }

  testWidgets('صفحهٔ اصلی گزینه‌های میزبانی و پیوستن را نشان می‌دهد', (
    tester,
  ) async {
    await pumpApp(tester);
    expect(find.text('سنجاب'), findsWidgets);
    expect(find.text('ایجاد بازی'), findsOneWidget);
    expect(find.text('پیوستن به بازی'), findsOneWidget);
    expect(find.text('راهنمای بازی'), findsOneWidget);
    expect(find.text('تنظیمات'), findsOneWidget);
    // The profile display name appears on Home.
    expect(find.text('بازیکن آزمون'), findsOneWidget);
  });

  testWidgets('دکمهٔ ایجاد بازی بدون خطا در دسترس است', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('ایجاد بازی'));
    // Creating a game binds a real TCP port, which never completes inside the
    // fake-async zone: let the real event loop run, then pump the UI.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 400)),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(controller.isHost, isTrue, reason: 'the host must have started');

    // Shut the host down inside the test body: no ticker or debounce timer may
    // outlive it, and the test zone must end with no pending timers.
    await tester.runAsync(() => controller.closeSession(silent: true));
    await tester.pump(const Duration(seconds: 1));
    expect(controller.isHost, isFalse);
  });

  testWidgets(
    'ویرایش پروفایل: نام خالی پذیرفته نمی‌شود و نام درست ذخیره می‌شود',
    (tester) async {
      await controller.bootstrap();
      await tester.pumpWidget(
        GameScope(
          controller: controller,
          child: const MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: ProfileScreen(firstRun: false),
            ),
          ),
        ),
      );
      await tester.pump();

      final field = find.byType(TextField).first;
      await tester.enterText(field, '   ');
      await tester.tap(find.text('ذخیره'));
      await tester.pump();
      expect(find.text('نام نمایشی نمی‌تواند خالی باشد.'), findsWidgets);
      expect(profiles.profile.displayName, 'بازیکن آزمون');

      await tester.enterText(field, 'سارا');
      await tester.tap(find.text('ذخیره'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(profiles.profile.displayName, 'سارا');
      // Renaming keeps the stable player ID.
      expect(profiles.profile.playerId, 'test-player');
    },
  );

  testWidgets('صفحهٔ نتایج با پایان نشست به صفحهٔ اصلی بازمی‌گردد', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1080, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await controller.bootstrap();
    final created = await tester.runAsync(() => controller.createGame());
    expect(created, isTrue);

    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      GameScope(
        controller: controller,
        child: MaterialApp(
          navigatorKey: navigatorKey,
          home: const Scaffold(body: Center(child: Text('صفحهٔ اصلی آزمون'))),
        ),
      ),
    );
    navigatorKey.currentState!.push<void>(
      MaterialPageRoute<void>(builder: (_) => const ResultsScreen()),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ResultsScreen), findsOneWidget);

    await tester.runAsync(() => controller.finishGame());
    await tester.pumpAndSettle();

    expect(find.text('صفحهٔ اصلی آزمون'), findsOneWidget);
    expect(find.byType(ResultsScreen), findsNothing);
  });

  testWidgets('اعتبارسنجی طول نام نمایشی', (tester) async {
    expect(validateDisplayName(''), isNotNull);
    expect(validateDisplayName('   '), isNotNull);
    expect(validateDisplayName('ا' * (kMaxDisplayNameLength + 1)), isNotNull);
    expect(validateDisplayName('سارا'), isNull);
    expect(validateDisplayName('  سارا  '), isNull);
  });
}
