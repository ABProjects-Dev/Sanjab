/// Android back-button guard plus the shared return-to-Home helper.
///
/// Going Home keeps the room resumable, but a lone host closes it automatically.
/// An explicit exit is still available from the menu.
///
library;

import 'package:flutter/material.dart';

import '../../state/game_scope.dart';
import 'common.dart';

/// Back button handling that depends on whether other members are present.
class ExitGuard extends StatelessWidget {
  const ExitGuard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) goToHomeScreen(context);
        });
      },
      child: child,
    );
  }
}

/// Return Home; a lone host closes the room automatically.
Future<void> goToHomeScreen(BuildContext context) async {
  final controller = GameScope.read(context);
  await controller.backToHome();
  if (!context.mounted) return;
  Navigator.of(context).popUntil((route) => route.isFirst);
}

/// Explicit exit after confirmation: the host closes the room and ends the
/// session for everyone, while a player leaves only its own membership.
Future<void> confirmLeaveRoom(
  BuildContext context, {
  String? roomName,
  bool isHostRole = false,
}) async {
  final controller = GameScope.read(context);
  final ok = await confirmDialog(
    context,
    title: isHostRole ? 'بستن اتاق' : 'خروج از اتاق',
    message: isHostRole
        ? 'با بستن اتاق، بازی برای همهٔ بازیکنان پایان می‌یابد و '
              'اطلاعات اتاق از این دستگاه حذف می‌شود. ادامه می‌دهید؟'
        : !controller.amIConnected
        ? 'این دستگاه آفلاین است؛ میزبان اکنون از خروج شما باخبر نمی‌شود و '
              'ممکن است شما را همچنان در شمارش نگه دارد. ادامه، فقط اطلاعات '
              'محلی اتاق را حذف می‌کند. برای اعلام خروج به میزبان، ابتدا وصل شوید.'
        : 'از اتاق «${roomName ?? controller.gameName}» خارج می‌شوید؟ '
              'برای ورود دوباره باید از میزبان بخواهید شما را دوباره وصل کند. '
              'با بازگشت به صفحهٔ اصلی، اتاق در صورت حضور بازیکنان دیگر حفظ می‌شود.',
    confirmLabel: isHostRole ? 'بستن اتاق' : 'خروج از اتاق',
    destructive: true,
  );
  if (!ok) return;
  await controller.leaveRoom();
  if (!context.mounted) return;
  Navigator.of(context).popUntil((route) => route.isFirst);
}
