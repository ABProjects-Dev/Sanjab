/// نقطهٔ ورود برنامهٔ «سنجاب».
library;

import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'app_controller_factory.dart';
import 'core/app_logger.dart';
import 'core/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // جهت صفحه: فقط Portrait.
  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // مدیریت خطاهای عمومی برنامه.
  FlutterError.onError = (FlutterErrorDetails details) {
    AppLogger.instance.error('flutter', details.exception, details.stack);
    if (kDebugMode) {
      FlutterError.presentError(details);
    }
  };
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    AppLogger.instance.error('platform', error, stack);
    return true;
  };

  // ویجت خطا: پیام فارسی به‌جای صفحهٔ قرمز.
  ErrorWidget.builder = (FlutterErrorDetails details) {
    return const _FriendlyErrorView();
  };

  // پوشهٔ دادهٔ برنامه برای ذخیره‌سازی موقت.
  Directory dataDir;
  try {
    final support = await getApplicationSupportDirectory();
    dataDir = Directory(support.path);
  } catch (error, stack) {
    AppLogger.instance.error('paths', error, stack);
    dataDir = Directory('${Directory.systemTemp.path}/sanjab');
  }
  if (!dataDir.existsSync()) {
    try {
      dataDir.createSync(recursive: true);
    } catch (_) {}
  }
  AppLogger.instance.init(dataDir);

  final controller = createProductionGameController(dataDir);
  await controller.bootstrap();

  runApp(SanjabApp(controller: controller));
}

/// نمایش خطای قابل فهم برای کاربر (به‌جای صفحهٔ خطای پیش‌فرض).
class _FriendlyErrorView extends StatelessWidget {
  const _FriendlyErrorView();

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        color: AppColors.background,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(24),
        child: const Text(
          'خطایی رخ داد. لطفاً برنامه را دوباره باز کنید؛ اطلاعات بازی حفظ شده است.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Vazirmatn',
            color: AppColors.textPrimary,
            fontSize: 15,
            height: 1.9,
          ),
        ),
      ),
    );
  }
}
