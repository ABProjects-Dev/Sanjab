/// Temporary persistence of the active game session on the device.
///
/// Requirements:
///  - No permanent history of games or players is kept;
///  - The active game is saved so an abrupt app exit is recoverable;
///    (continuation of the previous line)
///  - Writes are atomic: write a temp file, then replace the target;
///  - A backup copy is kept so a corrupt main file can be recovered
///    from the last known-good state.
library;

import 'dart:convert';
import 'dart:io';

import '../core/app_logger.dart';
import '../core/serial_task_queue.dart';
import '../domain/game_session.dart';

/// Session storage contract, for testability and easy substitution.
abstract class SessionStore {
  Future<void> ensureDirectory();

  Future<GameSession?> load();

  Future<bool> save(GameSession session, {required int nowMs});

  Future<void> clear();
}

/// File-backed implementation on device storage.
class SessionRepository implements SessionStore {
  SessionRepository(this.directory);

  /// Application data directory (injectable for tests).
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

  /// Load the saved session, falling back to the backup if the main file is corrupt.
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

  /// Atomically save the session; on error the previous state is kept.
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
            // The backup is best effort; its failure must not block the main write.
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

  /// Delete all temporary game data after queued writes finish.
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
