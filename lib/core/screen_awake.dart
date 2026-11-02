/// روشن نگه‌داشتن صفحهٔ گوشی در طول بازی.
///
/// پیاده‌سازی با یک کانال سادهٔ پلتفرمی در لایهٔ اندروید انجام می‌شود
/// (بدون وابستگی اضافی). در محیط تست/دسکتاپ بی‌صدا نادیده گرفته می‌شود.
library;

import 'package:flutter/services.dart';

class ScreenAwake {
  ScreenAwake._();

  static const MethodChannel _channel = MethodChannel(
    'com.sanjab.game/screen',
  );

  static bool _current = false;

  /// فعال/غیرفعال کردن روشن ماندن صفحه.
  static Future<void> setEnabled(bool enabled) async {
    if (_current == enabled) return;
    _current = enabled;
    try {
      await _channel.invokeMethod<void>('keepScreenOn', enabled);
    } on MissingPluginException {
      // محیط تست یا پلتفرم بدون پیاده‌سازی — نادیده گرفته می‌شود.
    } on PlatformException {
      // شکست در تنظیم فلگ سیستم نباید جریان بازی را متوقف کند.
    } catch (_) {
      // در محیط‌هایی که Binding یا پیاده‌سازی پلتفرم آماده نیست (آزمون، دسکتاپ)
      // این قابلیت بی‌صدا نادیده گرفته می‌شود و هرگز جریان بازی را قطع نمی‌کند.
    }
  }
}
