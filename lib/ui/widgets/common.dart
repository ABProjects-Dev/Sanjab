/// ویجت‌های مشترک رابط کاربری.
library;

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/app_theme.dart';
import '../../core/persian.dart';
import '../../domain/models.dart';

/// کارت بخش‌بندی‌شده با عنوان اختیاری.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    this.title,
    this.trailing,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.color,
  });

  final String? title;
  final Widget? trailing;
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.outline, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    title!,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 10),
          ],
          child,
        ],
      ),
    );
  }
}

/// ردیف قابل لمس برای فهرست‌های منو.
class ActionTile extends StatelessWidget {
  const ActionTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.trailing,
    this.iconColor,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.surfaceHigh,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  size: 20,
                  color: iconColor ?? AppColors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
              trailing ??
                  const Icon(
                    Icons.chevron_left,
                    color: AppColors.textMuted,
                    size: 22,
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

/// برچسب کوچک وضعیت.
class PillLabel extends StatelessWidget {
  const PillLabel({
    super.key,
    required this.text,
    this.color = AppColors.primary,
    this.icon,
  });

  final String text;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: color.withValues(alpha: 0.5), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: TextStyle(
              fontFamily: 'Vazirmatn',
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// نام فارسی و رنگ هر وضعیت داوری.
String judgementLabel(JudgementStatus status) {
  switch (status) {
    case JudgementStatus.confirmed:
      return 'تأیید';
    case JudgementStatus.duplicate:
      return 'تکراری';
    case JudgementStatus.rejected:
      return 'رد';
    case JudgementStatus.empty:
      return 'خالی';
    case JudgementStatus.unchecked:
      return 'بررسی‌نشده';
  }
}

Color judgementColor(JudgementStatus status) {
  switch (status) {
    case JudgementStatus.confirmed:
      return AppColors.confirmed;
    case JudgementStatus.duplicate:
      return AppColors.duplicate;
    case JudgementStatus.rejected:
      return AppColors.rejected;
    case JudgementStatus.empty:
      return AppColors.textMuted;
    case JudgementStatus.unchecked:
      return AppColors.textSecondary;
  }
}

/// نمایش پیام کوتاه فارسی.
void showMessage(BuildContext context, String message) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// دیالوگ تأیید دوگزینه‌ای.
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'تأیید',
  String cancelLabel = 'انصراف',
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(cancelLabel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            minimumSize: const Size(96, 44),
            backgroundColor: destructive
                ? AppColors.rejected
                : AppColors.primary,
          ),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// نشانگر زمان‌سنج.
class TimerPill extends StatelessWidget {
  const TimerPill({super.key, required this.remainingMs, this.paused = false});

  final int remainingMs;
  final bool paused;

  @override
  Widget build(BuildContext context) {
    final color = paused
        ? AppColors.warning
        : (remainingMs <= 30000 ? AppColors.rejected : AppColors.timer);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: color.withValues(alpha: 0.55)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            paused ? Icons.pause_circle_outline : Icons.timer_outlined,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 6),
          Text(
            faTimer(remainingMs),
            style: TextStyle(
              fontFamily: 'Vazirmatn',
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: color,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}

/// نمایش QR روی یک سطح سفید و یکپارچه با حاشیهٔ کافی برای اسکن آسان.
///
/// نسخهٔ ۴.۰.۰: QR هرگز مستقیماً روی پس‌زمینهٔ رنگی برنامه قرار نمی‌گیرد؛
/// زمینه سفید با گوشهٔ گرد و فاصلهٔ سفید اطراف، کنتراست و خوانایی را در
/// اندازه‌های مختلف صفحه حفظ می‌کند.
class QrCodePanel extends StatelessWidget {
  const QrCodePanel({
    super.key,
    required this.data,
    this.size = 220,
    this.padding = 16,
  });

  final String data;
  final double size;
  final double padding;

  @override
  Widget build(BuildContext context) {
    final side = MediaQuery.sizeOf(context).shortestSide;
    // اندازه پویا تا در صفحه‌های کوچک هم QR و حاشیهٔ سفید جا شود.
    final qrSize = size > side * 0.6 ? side * 0.6 : size;
    return Center(
      child: Container(
        padding: EdgeInsets.all(padding),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: RepaintBoundary(
          child: QrImageView(
            data: data,
            size: qrSize,
            version: QrVersions.auto,
            backgroundColor: Colors.white,
            eyeStyle: const QrEyeStyle(
              eyeShape: QrEyeShape.square,
              color: Colors.black,
            ),
            dataModuleStyle: const QrDataModuleStyle(
              dataModuleShape: QrDataModuleShape.square,
              color: Colors.black,
            ),
            gapless: true,
            errorStateBuilder: (context, error) => SizedBox(
              width: qrSize,
              height: qrSize,
              child: const Center(
                child: Text(
                  'نمایش QR ممکن نشد.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Vazirmatn',
                    color: Colors.black87,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
