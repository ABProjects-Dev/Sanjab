/// نگهبان دکمهٔ Back گوشی و ابزار مشترک «بازگشت به صفحه اصلی».
///
/// بازگشت به صفحهٔ اصلی، اتاق را برای ادامه نگه می‌دارد؛ اما اگر میزبان
/// تنها عضو باقی‌مانده باشد، اتاق خودکار بسته می‌شود. خروج صریح همچنان از
/// گزینهٔ «بستن اتاق» یا «خروج از اتاق» در منو در دسترس است.
library;

import 'package:flutter/material.dart';

import '../../state/game_scope.dart';
import 'common.dart';

/// دکمهٔ بازگشت گوشی؛ رفتار اتاق را بر اساس حضور اعضای دیگر تعیین می‌کند.
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

/// بازگشت به صفحهٔ اصلی؛ میزبان تنها، اتاق را خودکار می‌بندد.
Future<void> goToHomeScreen(BuildContext context) async {
  final controller = GameScope.read(context);
  await controller.backToHome();
  if (!context.mounted) return;
  Navigator.of(context).popUntil((route) => route.isFirst);
}

/// خروج صریح از اتاق (با تأیید): میزبان اتاق را می‌بندد و جلسه برای همه
/// پایان می‌یابد؛ بازیکن فقط از عضویت خودش خارج می‌شود.
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
