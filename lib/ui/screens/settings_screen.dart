/// تنظیمات ضروری برنامه: گزارش فنی، پاک‌سازی داده‌های موقت و دربارهٔ برنامه.
library;

import 'package:flutter/material.dart';

import '../../core/app_logger.dart';
import '../../core/persian.dart';
import '../../state/game_scope.dart';
import '../widgets/common.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = GameScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('تنظیمات')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
          children: [
            SectionCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  ActionTile(
                    icon: Icons.bug_report_outlined,
                    title: 'گزارش‌های فنی',
                    subtitle: 'مشاهدهٔ رخدادها و خطاهای داخلی برنامه',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const TechnicalLogsScreen(),
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  ActionTile(
                    icon: Icons.cleaning_services_outlined,
                    title: 'پاک‌سازی داده‌های موقت',
                    subtitle: 'حذف اطلاعات بازی ذخیره‌شده روی این دستگاه',
                    iconColor: Colors.orangeAccent,
                    onTap: () async {
                      final ok = await confirmDialog(
                        context,
                        title: 'پاک‌سازی داده‌های موقت',
                        message: 'اطلاعات بازی جاری روی این دستگاه پاک می‌شود و قابل بازگشت نیست. ادامه می‌دهید؟',
                        confirmLabel: 'پاک کن',
                        destructive: true,
                      );
                      if (!ok) return;
                      await controller.discardSavedGame();
                      if (!context.mounted) return;
                      showMessage(context, 'داده‌های موقت پاک شد.');
                    },
                  ),
                  const Divider(height: 1),
                  ActionTile(
                    icon: Icons.info_outline_rounded,
                    title: 'دربارهٔ برنامه',
                    subtitle: 'سنجاب — نسخهٔ ${faNum('1.0.1')}',
                    onTap: () => showAboutDialog(
                      context: context,
                      applicationName: 'سنجاب',
                      applicationVersion: faNum('1.0.1'),
                      applicationLegalese:
                          'شناسهٔ بسته: com.sanjab.game\nچندنفره روی شبکهٔ محلی؛ بدون نیاز به اینترنت',
                      children: const [
                        SizedBox(height: 10),
                        Text(
                          'بازی گروهی اسم و فامیل روی چند دستگاه در یک شبکهٔ محلی.\n'
                          'تمام منطق بازی به‌صورت مستقل در Flutter (Dart) پیاده‌سازی شده است.',
                          style: TextStyle(
                            fontFamily: 'Vazirmatn',
                            fontSize: 13,
                            height: 1.8,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'تم برنامه همیشه تاریک است و گزینهٔ تغییر تم وجود ندارد. '
              'هیچ صدایی و لرزشی در برنامه استفاده نمی‌شود.',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// نمایش آخرین رخدادهای فنی ثبت‌شده (برای بررسی توسعه‌دهنده).
class TechnicalLogsScreen extends StatefulWidget {
  const TechnicalLogsScreen({super.key});

  @override
  State<TechnicalLogsScreen> createState() => _TechnicalLogsScreenState();
}

class _TechnicalLogsScreenState extends State<TechnicalLogsScreen> {
  @override
  Widget build(BuildContext context) {
    final lines = AppLogger.instance.recent.reversed.toList(growable: false);
    return Scaffold(
      appBar: AppBar(
        title: const Text('گزارش‌های فنی'),
        actions: [
          IconButton(
            tooltip: 'پاک‌سازی گزارش‌ها',
            onPressed: () async {
              final ok = await confirmDialog(
                context,
                title: 'پاک‌سازی گزارش‌ها',
                message: 'همهٔ گزارش‌های فنی پاک شوند؟',
                confirmLabel: 'پاک کن',
                destructive: true,
              );
              if (!ok) return;
              await AppLogger.instance.clear();
              if (mounted) setState(() {});
            },
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: lines.isEmpty
            ? const Center(child: Text('گزارشی ثبت نشده است.'))
            : ListView.builder(
                padding: const EdgeInsets.all(14),
                itemCount: lines.length,
                itemBuilder: (context, index) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    lines[index],
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      height: 1.6,
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}
