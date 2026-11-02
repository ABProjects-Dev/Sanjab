/// ذخیره‌ساز درون‌حافظه‌ای برای تست‌های ویجت.
///
/// تست‌های ویجت در ناحیهٔ FakeAsync اجرا می‌شوند و ورودی/خروجی واقعی فایل
/// در آن ناحیه تکمیل نمی‌شود؛ این پیاده‌سازی همان قرارداد [SessionStore] را
/// بدون I/O برآورده می‌کند.
library;

import 'package:sanjab/data/session_repository.dart';
import 'package:sanjab/domain/game_session.dart';

class MemorySessionStore implements SessionStore {
  MemorySessionStore([this.initial]);

  GameSession? initial;
  GameSession? saved;
  int saveCount = 0;
  int clearCount = 0;

  @override
  Future<void> ensureDirectory() async {}

  @override
  Future<GameSession?> load() async => initial ?? saved;

  @override
  Future<bool> save(GameSession session, {required int nowMs}) async {
    saveCount++;
    saved = GameSession.fromJson(session.toJson());
    return true;
  }

  @override
  Future<void> clear() async {
    clearCount++;
    saved = null;
    initial = null;
  }
}
