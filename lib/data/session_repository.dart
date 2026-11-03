/// ذخیره‌سازی موقت وضعیت بازی روی حافظهٔ محلی دستگاه.
///
/// الزامات سند (بند ۱۱):
///  - هیچ سابقهٔ دائمی از بازی‌ها یا بازیکنان ساخته نمی‌شود؛
///  - وضعیت بازی فعال به‌صورت موقت ذخیره می‌شود تا اگر برنامه ناگهانی بسته شد
///    قابل بازیابی باشد؛
///  - نوشتن «اتمیک» است: ابتدا در فایل موقت نوشته و سپس جای‌گزین می‌شود؛
///  - یک نسخهٔ پشتیبان (`.bak`) نگه داشته می‌شود تا در صورت خرابی فایل اصلی،
///    آخرین وضعیت سالم بازیابی شود.
library;

import 'dart:convert';
import 'dart:io';

import '../core/app_logger.dart';
import '../core/serial_task_queue.dart';
import '../domain/game_session.dart';

/// قرارداد ذخیره‌سازی وضعیت بازی (برای تست‌پذیری و جای‌گزینی آسان).
abstract class SessionStore {
  Future<void> ensureDirectory();

  Future<GameSession?> load();

  Future<bool> save(GameSession session, {required int nowMs});

  Future<void> clear();
}

/// پیاده‌سازی فایل‌محور روی حافظهٔ محلی دستگاه.
class SessionRepository implements SessionStore {
  SessionRepository(this.directory);

  /// پوشهٔ دادهٔ برنامه (تزریق‌پذیر برای تست).
  final Directory directory;
  final SerialTaskQueue _writes = SerialTaskQueue();

  String get _mainPath => '${directory.path}/active_session.json';
  String get _tempPath => '${directory.path}/active_session.json.tmp';
  String get _backupPath => '${directory.path}/active_session.bak.json';

  @override
  Future<void> ensureDirectory() async {
    if (!directory.existsSync()) {
      await directory.create(recursive: true);
    }
  }

  /// بارگذاری وضعیت ذخیره‌شده. در صورت خرابی فایل اصلی، از پشتیبان استفاده می‌شود.
  @override
  Future<GameSession?> load() async {
    final main = await _read(_mainPath);
    if (main != null) return main;
    final backup = await _read(_backupPath);
    if (backup != null) {
      AppLogger.instance.log(
        'storage',
        'main session file unreadable, backup restored',
      );
      return backup;
    }
    return null;
  }

  Future<GameSession?> _read(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return null;
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) return null;
      return GameSession.fromJson(json);
    } catch (error, stack) {
      AppLogger.instance.error('storage.read', error, stack);
      return null;
    }
  }

  /// ذخیرهٔ اتمیک وضعیت. در صورت خطا، وضعیت قبلی حفظ می‌شود.
  @override
  Future<bool> save(GameSession session, {required int nowMs}) async {
    final String payload;
    try {
      session.savedAtEpochMs = nowMs;
      // Capture an immutable snapshot at call time; later mutations must be
      // written by their own queued save rather than changing this request.
      payload = jsonEncode(session.toJson());
    } catch (error, stack) {
      AppLogger.instance.error('storage.save', error, stack);
      return false;
    }

    return _writes.run(() async {
      try {
        await ensureDirectory();
        final temp = File(_tempPath);
        final handle = await temp.open(mode: FileMode.write);
        try {
          await handle.writeString(payload);
          await handle.flush();
        } finally {
          await handle.close();
        }
        final main = File(_mainPath);
        if (await main.exists()) {
          try {
            await main.copy(_backupPath);
          } catch (_) {
            // پشتیبان اختیاری است؛ شکست آن مانع ذخیرهٔ اصلی نمی‌شود.
          }
        }
        await temp.rename(_mainPath);
        return true;
      } catch (error, stack) {
        AppLogger.instance.error('storage.save', error, stack);
        return false;
      }
    });
  }

  /// پاک‌سازی کامل داده‌های موقت بازی، پس از پایان ذخیره‌های در صف.
  @override
  Future<void> clear() async {
    await _writes.run(() async {
      for (final path in <String>[_mainPath, _tempPath, _backupPath]) {
        try {
          final file = File(path);
          if (await file.exists()) await file.delete();
        } catch (error, stack) {
          AppLogger.instance.error('storage.clear', error, stack);
        }
      }
    });
  }
}
