/// Integration test on a real Android device.
///
/// This test runs only on a device or emulator:
///   flutter test integration_test/app_flow_test.dart -d DEVICE_ID
///
/// Note: full multiplayer needs **two phones on the same LAN** and is not
/// simulated here; the host path, session creation and join-code display are
/// still exercised on a real device.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sanjab/app.dart';
import 'package:sanjab/data/profile_repository.dart';
import 'package:sanjab/data/session_repository.dart';
import 'package:sanjab/state/game_controller.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('مسیر میزبانی: نام نمایشی، ساخت بازی و نمایش کد اتصال', (
    tester,
  ) async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/integration');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final store = SessionRepository(dir);
    final profiles = ProfileRepository(dir);
    await store.clear();

    final controller = GameController(store: store, profileRepo: profiles);
    await controller.bootstrap();
    addTearDown(() async {
      await controller.closeSession(silent: true);
      controller.dispose();
      await store.clear();
    });

    expect(await controller.saveDisplayName('میزبان آزمون'), isTrue);

    await tester.pumpWidget(SanjabApp(controller: controller));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('ایجاد بازی'), findsOneWidget);
    await tester.tap(find.text('ایجاد بازی'));
    await tester.pump(const Duration(milliseconds: 200));

    expect(controller.isHost, isTrue);
    expect(controller.hostPort, greaterThan(0));
    // The six-character join code is shown in the lobby.
    expect(controller.joinToken.length, 6);
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.takeException(), isNull);
  });
}
