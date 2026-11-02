/// گزارش‌گیری فنی داخلی با محدودیت حجم و پاک‌سازی کنترل‌شده.
///
/// اصول (بند ۱۷ سند پروژه):
///  - پیام فارسی و قابل فهم برای کاربر نمایش داده می‌شود؛
///  - جزئیات فنی در گزارش داخلی ذخیره می‌شود؛
///  - محتوای پاسخ بازیکنان و اطلاعات شخصی هرگز در گزارش نوشته نمی‌شود
///    (فقط شناسه‌ها، شمارنده‌ها و نام فنی خطا).
library;

import 'dart:async';
import 'dart:io';

/// گزارش‌دهندهٔ سادهٔ فایل‌محور.
class AppLogger {
  AppLogger._();

  static final AppLogger instance = AppLogger._();

  /// حداکثر حجم فایل گزارش (بایت). با رسیدن به این حجم، فایل چرخش می‌کند.
  static const int maxFileBytes = 256 * 1024;

  /// حداکثر تعداد فایل‌های چرخشی نگه‌داری‌شده.
  static const int maxRotatedFiles = 2;

  File? _file;
  bool _initialized = false;
  final List<String> _recent = <String>[];

  /// آخرین خطوط گزارش (برای نمایش در صفحهٔ گزارش‌های فنی).
  List<String> get recent => List<String>.unmodifiable(_recent);

  /// مسیر فایل گزارش جاری.
  String? get path => _file?.path;

  /// راه‌اندازی با پوشهٔ دادهٔ برنامه.
  void init(Directory dir) {
    try {
      final logDir = Directory('${dir.path}/logs');
      if (!logDir.existsSync()) logDir.createSync(recursive: true);
      _file = File('${logDir.path}/app.log');
      _initialized = true;
      if (_file!.existsSync()) {
        final lines = _file!.readAsLinesSync();
        _recent
          ..clear()
          ..addAll(
            lines.length > 200 ? lines.sublist(lines.length - 200) : lines,
          );
      }
    } catch (_) {
      _initialized = false;
    }
  }

  /// ثبت یک رخداد فنی. [message] هرگز نباید محتوای پاسخ بازیکنان باشد.
  void log(String tag, String message) {
    final stamp = DateTime.now().toIso8601String();
    final line = '[$stamp] $tag: $message';
    _recent.add(line);
    if (_recent.length > 200) _recent.removeAt(0);
    if (!_initialized) return;
    try {
      final file = _file!;
      if (file.existsSync() && file.lengthSync() > maxFileBytes) {
        _rotate();
      }
      file.writeAsStringSync('$line\n', mode: FileMode.append, flush: true);
    } catch (_) {
      // گزارش‌گیری هرگز نباید خودش باعث خطا شود.
    }
  }

  void error(String tag, Object error, [StackTrace? stack]) {
    log(tag, '${error.runtimeType}: $error');
    if (stack != null) {
      final first = stack.toString().split('\n').take(6).join(' | ');
      log(tag, 'trace: $first');
    }
  }

  /// چرخش فایل‌ها با حفظ حداکثر [maxRotatedFiles] فایل.
  void _rotate() {
    try {
      final dir = _file!.parent;
      final oldest = File('${dir.path}/app.log.$maxRotatedFiles');
      if (oldest.existsSync()) oldest.deleteSync();
      for (var i = maxRotatedFiles - 1; i >= 1; i--) {
        final from = File('${dir.path}/app.log.$i');
        if (from.existsSync()) {
          from.renameSync('${dir.path}/app.log.${i + 1}');
        }
      }
      _file!.renameSync('${dir.path}/app.log.1');
    } catch (_) {
      // در صورت شکست، فایل جاری پاک می‌شود تا حجم نامحدود رشد نکند.
      try {
        _file!.writeAsStringSync('', flush: true);
      } catch (_) {}
    }
  }

  /// پاک‌سازی کامل گزارش‌ها (از تنظیمات).
  Future<void> clear() async {
    _recent.clear();
    if (!_initialized) return;
    try {
      final dir = _file!.parent;
      if (dir.existsSync()) {
        for (final entity in dir.listSync()) {
          if (entity is File && entity.path.contains('app.log')) {
            entity.deleteSync();
          }
        }
      }
    } catch (_) {}
  }
}
