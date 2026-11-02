/// آزمون‌های نسخهٔ ۱.۰.۰ — اعتبارسنجی دکمهٔ «استپ».
///
/// یازده سناریوی الزامی سند ۱.۰.۰ در سه لایه آزموده می‌شود:
///  ۱) قاعدهٔ متن (کاراکتر معتبر، فاصله، نیم‌فاصله، کاراکتر نامرئی)
///  ۲) منطق دامنه (`GameSession.canPlayerStop` / `requestStop`)
///  ۳) منطق اجرای عملیات و رابط کاربری (کنترلر و صفحهٔ بازی، شامل بازی چندنفره)
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shotormorgh/domain/answer_rules.dart';
import 'package:shotormorgh/domain/game_session.dart';
import 'package:shotormorgh/domain/models.dart';
import 'package:shotormorgh/domain/profile.dart';
import 'package:shotormorgh/state/game_controller.dart';
import 'package:shotormorgh/state/game_scope.dart';
import 'package:shotormorgh/ui/screens/play_screen.dart';

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

/// ساخت نشست سه‌نفره با دو دستهٔ فعال (برای آزمون سریع قاعدهٔ «همهٔ فیلدها»).
GameSession newSession({int players = 3, List<int> categories = const [0, 1]}) {
  final session = GameSession.fresh(gameId: 'g1', hostPlayerId: 'h1');
  session.setActiveCategories(categories);
  session.addPlayer('میزبان', id: 'h1', isHost: true);
  for (var i = 1; i < players; i++) {
    session.addPlayer('بازیکن $i', id: 'p$i');
  }
  return session;
}

/// پر کردن همهٔ دسته‌های فعال با متن معتبر.
void fillAll(GameSession session, String playerId, {String text = 'آب'}) {
  for (final categoryId in session.config.activeCategoryIds) {
    session.setAnswer(playerId, categoryId, text);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ---------------------------------------------------------------- لایهٔ متن
  group('قاعدهٔ کاراکتر معتبر', () {
    test('۱) متن خالی معتبر نیست', () {
      expect(isAnswerEligibleForStop(''), isFalse);
      expect(validAnswerCharCount(''), 0);
    });

    test('۲) یک کاراکتر کافی نیست و دو کاراکتر کافی است', () {
      expect(isAnswerEligibleForStop('ا'), isFalse);
      expect(isAnswerEligibleForStop('آب'), isTrue);
      expect(validAnswerCharCount('آب'), 2);
      expect(kStopMinValidChars, 2);
    });

    test('۳) فاصلهٔ ابتدا و انتها کاراکتر معتبر شمرده نمی‌شود', () {
      expect(isAnswerEligibleForStop('   '), isFalse);
      expect(isAnswerEligibleForStop('  ا  '), isFalse);
      expect(isAnswerEligibleForStop('  آب  '), isTrue);
      // فاصله‌های میانی هم شمرده نمی‌شوند.
      expect(validAnswerCharCount('ا ب'), 2);
      expect(validAnswerCharCount('ا  ب  پ'), 3);
    });

    test('۴) کاراکترهای نامرئی و نیم‌فاصله به‌تنهایی معتبر نیستند', () {
      // نیم‌فاصله، فاصلهٔ صفرعرض، BOM، LRM/RLM و فاصلهٔ محافظت‌شده
      expect(isAnswerEligibleForStop('\u200c\u200c'), isFalse);
      expect(isAnswerEligibleForStop('\u200b\u200b'), isFalse);
      expect(isAnswerEligibleForStop('\ufeff\u200e'), isFalse);
      expect(isAnswerEligibleForStop('\u00a0\u00a0'), isFalse);
      expect(isAnswerEligibleForStop('\t\n\r'), isFalse);
      // مخلوط نامرئی با یک حرف واقعی هم کافی نیست.
      expect(isAnswerEligibleForStop('\u200cا\u200c'), isFalse);
      // دو حرف واقعی در کنار کاراکترهای نامرئی معتبر است.
      expect(isAnswerEligibleForStop('\u200cآب\u200c'), isTrue);
    });

    test('۵) نرمال‌سازی پاسخ، فاصله‌ها و کاراکترهای نامرئی را حذف می‌کند', () {
      expect(normalizeAnswerForStop('  آب\u200c  '), 'آب');
      expect(normalizeAnswerForStop('\u200bتهران\u00a0'), 'تهران');
    });
  });

  // -------------------------------------------------------------- لایهٔ دامنه
  group('منطق دامنه: فعال شدن دکمهٔ استپ', () {
    test('۶) همهٔ فیلدها خالی ⇒ استپ مجاز نیست', () {
      final session = newSession();
      session.startNewRound(nowMs: 0);
      expect(session.canPlayerStop('h1'), isFalse);
      expect(session.pendingStopCategoryIds('h1').length, 2);
      expect(session.requestStop('h1', nowMs: 100), isFalse);
      expect(session.stopCount, 0);
      expect(session.phase, GamePhase.playing);
    });

    test('۷) یک فیلد با یک کاراکتر ⇒ استپ مجاز نیست', () {
      final session = newSession();
      session.startNewRound(nowMs: 0);
      session.setAnswer('h1', 0, 'آب');
      session.setAnswer('h1', 1, 'پ');
      expect(session.canPlayerStop('h1'), isFalse);
      expect(session.pendingStopCategoryIds('h1'), <int>[1]);
      expect(session.requestStop('h1', nowMs: 100), isFalse);
    });

    test('۸) همهٔ فیلدها دقیقاً دو کاراکتر ⇒ استپ مجاز است', () {
      final session = newSession();
      session.startNewRound(nowMs: 0);
      session.setAnswer('h1', 0, 'آب');
      session.setAnswer('h1', 1, 'پت');
      expect(session.canPlayerStop('h1'), isTrue);
      expect(session.pendingStopCategoryIds('h1'), isEmpty);
      expect(session.requestStop('h1', nowMs: 100), isTrue);
      expect(session.stopCount, 1);
    });

    test('۹) یک فیلد فقط فاصله ⇒ استپ مجاز نیست', () {
      final session = newSession();
      session.startNewRound(nowMs: 0);
      session.setAnswer('h1', 0, 'آب');
      session.setAnswer('h1', 1, '   ');
      expect(session.canPlayerStop('h1'), isFalse);
      expect(session.requestStop('h1', nowMs: 100), isFalse);
    });

    test('۱۰) فیلد با «فاصله + دو حرف معتبر» معتبر است', () {
      final session = newSession();
      session.startNewRound(nowMs: 0);
      session.setAnswer('h1', 0, '  آب  ');
      session.setAnswer('h1', 1, '\u200cپت\u200c');
      expect(session.canPlayerStop('h1'), isTrue);
    });

    test('۱۱) کوتاه شدن یک پاسخ پس از فعال شدن ⇒ استپ دوباره غیرمجاز', () {
      final session = newSession();
      session.startNewRound(nowMs: 0);
      fillAll(session, 'h1');
      expect(session.canPlayerStop('h1'), isTrue);
      session.setAnswer('h1', 0, 'آ');
      expect(session.canPlayerStop('h1'), isFalse);
      // تکمیل مجدد ⇒ دوباره مجاز.
      session.setAnswer('h1', 0, 'آب');
      expect(session.canPlayerStop('h1'), isTrue);
    });

    test('۱۲) درخواست تکراری/قدیمی در حالت غیرمجاز هیچ اثری ندارد', () {
      final session = newSession();
      session.startNewRound(nowMs: 0);
      for (var i = 0; i < 5; i++) {
        expect(session.requestStop('h1', nowMs: 100 + i), isFalse);
      }
      expect(session.stopCount, 0);
      expect(session.isPlayerStopped('h1'), isFalse);
      expect(session.phase, GamePhase.playing);
    });

    test('۱۳) قاعده فقط پاسخ همان بازیکن را می‌سنجد', () {
      final session = newSession();
      session.startNewRound(nowMs: 0);
      fillAll(session, 'h1');
      expect(session.canPlayerStop('h1'), isTrue);
      expect(session.canPlayerStop('p1'), isFalse);
      expect(session.requestStop('p1', nowMs: 10), isFalse);
      expect(session.stopCount, 0);
    });

    test('۱۴) تنها دسته‌های فعال بررسی می‌شوند', () {
      final session = newSession(categories: const [0, 3]);
      session.startNewRound(nowMs: 0);
      session.setAnswer('h1', 0, 'آب');
      session.setAnswer('h1', 3, 'پت');
      // دستهٔ ۱ فعال نیست؛ خالی بودنش مانع استپ نیست.
      expect(session.setAnswer('h1', 1, ''), isFalse);
      expect(session.canPlayerStop('h1'), isTrue);
    });
  });

  // --------------------------------------------- لایهٔ کنترلر (بازی چندنفره)
  group('منطق اجرای عملیات استپ در کنترلر و همگام‌سازی چندنفره', () {
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
      expect(await host.createGame(activeCategoryIds: [0, 1]), isTrue);
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
        ),
        isTrue,
      );
      expect(await waitUntil(() => host.session.players.length == 3), isTrue);
      host.startGame();
      expect(await waitUntil(() => player.session.phase == GamePhase.playing),
          isTrue);
      await waitUntil(() => player2.session.phase == GamePhase.playing);
    });

    tearDown(() async {
      await host.closeSession(silent: true);
      await player.leaveGame();
      await player2.leaveGame();
      host.dispose();
      player.dispose();
      player2.dispose();
    });

    test('۱۵) فیلدهای خالی: دکمه غیرفعال و درخواست استپ رد می‌شود', () async {
      expect(host.iCanStop, isFalse);
      expect(host.myPendingStopFields, 2);
      expect(host.stopHintText, contains('۲'));
      await host.requestStop();
      await player.requestStop();
      expect(host.session.stopCount, 0, reason: 'هیچ استپی نباید ثبت شود');
      expect(player.lastError, contains('حرف'));
      expect(host.lastError, contains('حرف'));
    });

    test('۱۶) یک فیلد کوتاه: دکمه غیرفعال است', () async {
      host.setAnswer(0, 'آب');
      host.setAnswer(1, 'پ');
      expect(host.iCanStop, isFalse);
      expect(host.myPendingStopFields, 1);
      await host.requestStop();
      expect(host.session.stopCount, 0);
    });

    test('۱۷) هر دو فیلد دوکاراکتری: دکمه فعال و استپ ثبت می‌شود', () async {
      host.setAnswer(0, 'آب');
      host.setAnswer(1, 'پت');
      expect(host.iCanStop, isTrue);
      expect(host.stopHintText, isEmpty);
      await host.requestStop();
      expect(host.iAmStopped, isTrue);
      expect(host.session.stopCount, 1);
    });

    test('۱۸) پس از کوتاه شدن یک پاسخ، دکمه دوباره غیرفعال می‌شود',
        () async {
      host.setAnswer(0, 'آب');
      host.setAnswer(1, 'پت');
      expect(host.iCanStop, isTrue);
      host.setAnswer(1, '');
      expect(host.iCanStop, isFalse);
      host.setAnswer(1, 'پ');
      expect(host.iCanStop, isFalse);
      host.setAnswer(1, 'پت');
      expect(host.iCanStop, isTrue);
    });

    test('۱۹) ویرایش سریع و هم‌زمان چند فیلد: وضعیت درست به‌روز می‌شود',
        () async {
      const samples = <String, bool>{
        '': false,
        'ا': false,
        'آب': true,
        '  آب  ': true,
        '   ': false,
        '\u200c': false,
        'پت': true,
        'آب ': true,
        ' آ': false,
      };
      for (final entry in samples.entries) {
        host.setAnswer(0, entry.key);
        host.setAnswer(1, entry.key);
        expect(
          host.iCanStop,
          entry.value,
          reason: 'مقدار «${entry.key}» ⇒ انتظار ${entry.value}',
        );
      }
      // تغییر هم‌زمان دو فیلد: یکی کامل و دیگری ناقص ⇒ غیرفعال.
      host.setAnswer(0, 'آب');
      host.setAnswer(1, 'پ');
      expect(host.iCanStop, isFalse);
      host.setAnswer(1, 'پت');
      expect(host.iCanStop, isTrue);
    });

    test('۲۰) استپ بازیکن با پاسخ کامل، در همهٔ دستگاه‌ها هم‌گام می‌شود',
        () async {
      // بازیکن فیلدها را پر می‌کند؛ میزبان هم‌گام می‌گیرد.
      player.setAnswer(0, 'تهران');
      player.setAnswer(1, 'رضا');
      expect(await waitUntil(() => player.iCanStop), isTrue);
      expect(
        await waitUntil(() => host.session.canPlayerStop('p1')),
        isTrue,
        reason: 'میزبان باید پاسخ‌های کامل بازیکن را داشته باشد',
      );
      await player.requestStop();
      expect(
        await waitUntil(() => host.session.stopCount == 1),
        isTrue,
        reason: 'استپ معتبر بازیکن باید روی میزبان ثبت شود',
      );
      expect(host.session.isPlayerStopped('p1'), isTrue);
      expect(
        host.session.phase,
        GamePhase.playing,
        reason: 'در بازی سه‌نفره یک استپ دست را تمام نمی‌کند',
      );
      // میزبان خودش پاسخ‌ها را پر نکرده است؛ قاعده برای هر بازیکن جداست.
      expect(host.iCanStop, isFalse, reason: 'سنجش با پاسخ‌های همان بازیکن');

      // بازیکن دوم با پاسخ ناقص نمی‌تواند استپ کند.
      player2.setAnswer(0, 'شیراز');
      expect(player2.iCanStop, isFalse);
      await player2.requestStop();
      expect(host.session.stopCount, 1);
      expect(player2.lastError, contains('حرف'));

      // پس از تکمیل، استپ دوم دست را برای همه تمام می‌کند.
      player2.setAnswer(1, 'کریم');
      expect(await waitUntil(() => player2.iCanStop), isTrue);
      await player2.requestStop();
      expect(
        await waitUntil(
          () =>
              host.session.phase == GamePhase.collecting ||
              host.session.phase == GamePhase.judging,
        ),
        isTrue,
      );
      expect(host.session.currentRound!.endReason, RoundEndReason.playerStop);
      // هر دو بازیکن استپ‌کرده‌اند (پس از فاز دریافت پاسخ‌ها، Snapshot هر
      // بازیکن هم او را «قفل‌شده» می‌کند؛ رفتار نسخهٔ ۱.۰.۰ بدون تغییر).
      expect(host.session.isPlayerStopped('p1'), isTrue);
      expect(host.session.isPlayerStopped('p2'), isTrue);
      // بازیکن استپ‌کرده پاسخ‌هایش را می‌فرستد و میزبان همه را می‌گیرد.
      expect(
        await waitUntil(
          () =>
              host.session.phase == GamePhase.judging &&
              host.submissionOf('p1') == SubmissionState.received &&
              host.submissionOf('p2') == SubmissionState.received,
        ),
        isTrue,
        reason: 'داوری باید با پاسخ‌های هر دو بازیکن آغاز شود',
      );
      expect(host.session.currentRound!.answerOf('p1', 0)!.text, 'تهران');
      expect(host.session.currentRound!.answerOf('p2', 0)!.text, 'شیراز');
    });
  });

  // ------------------------------------------------------- لایهٔ رابط کاربری
  group('رابط کاربری صفحهٔ بازی', () {
    late GameController controller;

    tearDown(() {
      controller.dispose();
    });

    Future<void> pumpPlayScreen(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1080, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      controller = GameController(
        store: MemorySessionStore(),
        profileRepo: MemoryProfileStore(
          initial: const Profile(playerId: 'p1', displayName: 'مینا'),
        ),
      );
      await controller.bootstrap();
      // نشست آمادهٔ بازی (بدون شبکه) تا صفحهٔ بازی آزموده شود.
      controller.session.setActiveCategories(const [0, 1]);
      controller.session.addPlayer('سارا', id: 'h1', isHost: true);
      controller.session.addPlayer('مینا', id: 'p1');
      controller.session.startNewRound(nowMs: 0);
      await tester.pumpWidget(
        GameScope(
          controller: controller,
          child: const MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: PlayScreen(),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    FilledButton stopButton(WidgetTester tester) => tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('استپ'),
        matching: find.byType(FilledButton),
      ),
    );

    testWidgets('۲۱) فیلدهای خالی: دکمهٔ استپ غیرفعال و راهنما دیده می‌شود',
        (tester) async {
      await pumpPlayScreen(tester);
      expect(stopButton(tester).onPressed, isNull);
      expect(find.textContaining('حداقل ۲ حرف'), findsOneWidget);
    });

    testWidgets('۲۲) با تکمیل همهٔ فیلدها دکمه فعال و با کوتاه شدن غیرفعال '
        'می‌شود', (tester) async {
      await pumpPlayScreen(tester);
      final fields = find.byType(TextField);
      expect(fields, findsNWidgets(2));

      await tester.enterText(fields.at(0), 'آب');
      await tester.enterText(fields.at(1), 'پ');
      await tester.pump();
      expect(stopButton(tester).onPressed, isNull, reason: 'یک فیلد کوتاه است');

      await tester.enterText(fields.at(1), 'پت');
      await tester.pump();
      expect(stopButton(tester).onPressed, isNotNull);
      expect(find.textContaining('حداقل ۲ حرف'), findsNothing);

      // پاسخ‌ها همچنان قابل ویرایش‌اند (غیرفعال بودن دکمه مانع تایپ نیست).
      await tester.enterText(fields.at(0), ' ');
      await tester.pump();
      expect(stopButton(tester).onPressed, isNull, reason: 'فیلد تنها فاصله است');
      expect(
        tester.widget<TextField>(fields.at(0)).enabled,
        isTrue,
        reason: 'فیلدها باید همچنان قابل ویرایش باشند',
      );

      await tester.enterText(fields.at(0), 'تهران');
      await tester.pump();
      expect(stopButton(tester).onPressed, isNotNull);
    });
  });
}
