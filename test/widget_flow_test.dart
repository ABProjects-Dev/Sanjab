/// آزمون ویجت نسخهٔ ۱.۰.۰: صفحهٔ اصلی، پروفایل و راهنمای بازی.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanjab/app.dart';
import 'package:sanjab/domain/profile.dart';
import 'package:sanjab/state/game_controller.dart';
import 'package:sanjab/state/game_scope.dart';
import 'package:sanjab/ui/screens/profile_screen.dart';

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
    // نام نمایشی پروفایل روی صفحهٔ اصلی دیده می‌شود.
    expect(find.text('بازیکن آزمون'), findsOneWidget);
  });

  testWidgets('دکمهٔ ایجاد بازی بدون خطا در دسترس است', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('ایجاد بازی'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
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
      // شناسهٔ پایدار بازیکن با تغییر نام عوض نمی‌شود.
      expect(profiles.profile.playerId, 'test-player');
    },
  );

  testWidgets('اعتبارسنجی طول نام نمایشی', (tester) async {
    expect(validateDisplayName(''), isNotNull);
    expect(validateDisplayName('   '), isNotNull);
    expect(validateDisplayName('ا' * (kMaxDisplayNameLength + 1)), isNotNull);
    expect(validateDisplayName('سارا'), isNull);
    expect(validateDisplayName('  سارا  '), isNull);
  });
}
