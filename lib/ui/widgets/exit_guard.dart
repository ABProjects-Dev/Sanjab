/// نگهبان دکمهٔ Back گوشی و ابزار مشترک «بازگشت به صفحه اصلی».
///
/// نسخهٔ ۱.۰.۰: در تمام صفحات داخلی، بازگشت به معنی **خروج از اتاق نیست**؛
/// جلسه ادامه می‌یابد، اطلاعات حفظ می‌شود و کاربر می‌تواند با «ادامه بازی»
/// برگردد. خروج صریح از اتاق عملیات جداگانه‌ای با تأیید کاربر است.
library;

import 'package:flutter/material.dart';

import '../../state/game_scope.dart';
import 'common.dart';

/// دکمهٔ بازگشت گوشی در صفحه‌های بازی: بازگشت به صفحهٔ اصلی (نه خروج).
class ExitGuard extends StatelessWidget {
  const ExitGuard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) return;
        goToHomeScreen(context);
      },
      child: child,
    );
  }
}

/// بازگشت به صفحهٔ اصلی بدون پایان‌دادن جلسه و بدون خروج از اتاق.
Future<void> goToHomeScreen(BuildContext context) async {
  final controller = GameScope.read(context);
  await controller.backToHome();
  if (!context.mounted) return;
  Navigator.of(context).popUntil((route) => route.isFirst);
}

/// خروج صریح از اتاق (با تأیید) — تفاوت اصلی آن با بازگشت به صفحهٔ اصلی:
/// رکورد اتاق از دستگاه حذف می‌شود و «ادامه بازی» دیگر وجود ندارد.
Future<void> confirmLeaveRoom(
  BuildContext context, {
  String? roomName,
  bool isHostRole = false,
}) async {
  final controller = GameScope.read(context);
  final ok = await confirmDialog(
    context,
    title: 'خروج از اتاق',
    message: isHostRole
        ? 'با خروج شما از اتاق، بازی برای همهٔ بازیکنان پایان می‌یابد و '
              'اطلاعات اتاق از این دستگاه حذف می‌شود. ادامه می‌دهید؟'
        : !controller.amIConnected
        ? 'این دستگاه آفلاین است؛ میزبان اکنون از خروج شما باخبر نمی‌شود و '
              'ممکن است شما را همچنان در شمارش نگه دارد. ادامه، فقط اطلاعات '
              'محلی اتاق را حذف می‌کند. برای اعلام خروج به میزبان، ابتدا وصل شوید.'
        : 'از اتاق «${roomName ?? controller.gameName}» خارج می‌شوید؟ '
              'برای ورود دوباره باید از میزبان بخواهید شما را دوباره وصل کند. '
              'توجه کنید که بازگشت به صفحهٔ اصلی به معنی خروج از اتاق نیست.',
    confirmLabel: 'خروج از اتاق',
    destructive: true,
  );
  if (!ok) return;
  await controller.leaveRoom();
  if (!context.mounted) return;
  Navigator.of(context).popUntil((route) => route.isFirst);
}

/// دکمهٔ استاندارد «بازگشت به صفحهٔ اصلی» برای نوار بالای صفحات داخلی.
class HomeIconButton extends StatelessWidget {
  const HomeIconButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.home_rounded),
      tooltip: 'بازگشت به صفحه اصلی',
      onPressed: () => goToHomeScreen(context),
    );
  }
}
