/// In-memory session store for widget tests.
///
/// Widget tests run under FakeAsync, where real file I/O never completes.
/// This implementation satisfies the same [SessionStore] contract without
/// touching the disk.
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
