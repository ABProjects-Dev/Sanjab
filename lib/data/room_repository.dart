/// Durable storage of saved rooms on each device.
///
/// Properties:
///  * Atomic writes (temp + rename) with a `.bak` backup;
///  * One record per room and player pair, never duplicated;
///  * Corruption tolerance: the backup is read when the main file is corrupt;
///  * Multiple rooms per device.
library;

import 'dart:convert';
import 'dart:io';

import '../core/app_logger.dart';
import '../core/serial_task_queue.dart';
import '../domain/room_record.dart';

/// Room storage contract (for testability).
abstract class RoomStore {
  Future<void> ensureDirectory();

  /// Saved rooms on this device.
  Future<List<RoomRecord>> loadAll();

  /// Insert or update a room; the key is room ID plus player ID.
  Future<bool> upsert(RoomRecord record);

  /// Remove one room record.
  Future<bool> remove(String gameId, String myPlayerId);

  /// Delete everything.
  Future<void> clear();
}

/// File-backed implementation on device storage.
class RoomRepository implements RoomStore {
  RoomRepository(this.directory);

  final Directory directory;
  final SerialTaskQueue _writes = SerialTaskQueue();

  String get _mainPath => '${directory.path}/rooms.json';
  String get _tempPath => '${directory.path}/rooms.json.tmp';
  String get _backupPath => '${directory.path}/rooms.bak.json';

  @override
  Future<void> ensureDirectory() async {
    if (!directory.existsSync()) {
      await directory.create(recursive: true);
    }
  }

  @override
  Future<List<RoomRecord>> loadAll() async {
    final records = await _read(_mainPath);
    if (records != null) return records;
    final backup = await _read(_backupPath);
    if (backup != null) {
      AppLogger.instance.log('storage', 'rooms main file unreadable, backup used');
      return backup;
    }
    return <RoomRecord>[];
  }

  Future<List<RoomRecord>?> _read(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return null;
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) return null;
      final items = json['rooms'];
      if (items is! List) return null;
      final records = <RoomRecord>[];
      for (final item in items) {
        if (item is! Map<String, dynamic>) continue;
        try {
          final record = RoomRecord.fromJson(item);
          if (record.gameId.isEmpty || record.myPlayerId.isEmpty) continue;
          records.add(record);
        } catch (error, stack) {
          AppLogger.instance.error('storage.rooms.item', error, stack);
        }
      }
      return records;
    } catch (error, stack) {
      AppLogger.instance.error('storage.rooms.read', error, stack);
      return null;
    }
  }

  Future<bool> _writeAll(List<RoomRecord> records) async {
    try {
      await ensureDirectory();
      final payload = jsonEncode({
        'v': 1,
        'rooms': records.map((r) => r.toJson()).toList(growable: false),
      });
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
          // The backup is best effort.
        }
      }
      await temp.rename(_mainPath);
      return true;
    } catch (error, stack) {
      AppLogger.instance.error('storage.rooms.write', error, stack);
      return false;
    }
  }

  @override
  Future<bool> upsert(RoomRecord record) {
    return _writes.run(() async {
      final records = await loadAll();
      final index = records.indexWhere((r) => r.key == record.key);
      if (index >= 0) {
        records[index] = record;
      } else {
        records.add(record);
      }
      // Keep at most 20 rooms so the file cannot grow without bound; oldest go first.
      if (records.length > 20) {
        records.sort(
          (a, b) => b.updatedAtEpochMs.compareTo(a.updatedAtEpochMs),
        );
        records.removeRange(20, records.length);
      }
      return _writeAll(records);
    });
  }

  @override
  Future<bool> remove(String gameId, String myPlayerId) {
    return _writes.run(() async {
      final records = await loadAll();
      records.removeWhere(
        (r) => r.gameId == gameId && r.myPlayerId == myPlayerId,
      );
      return _writeAll(records);
    });
  }

  @override
  Future<void> clear() async {
    await _writes.run(() async {
      for (final path in <String>[_mainPath, _tempPath, _backupPath]) {
        try {
          final file = File(path);
          if (await file.exists()) await file.delete();
        } catch (error, stack) {
          AppLogger.instance.error('storage.rooms.clear', error, stack);
        }
      }
    });
  }
}

/// In-memory implementation for tests.
class MemoryRoomStore implements RoomStore {
  MemoryRoomStore([List<RoomRecord>? initial])
    : _records = List<RoomRecord>.from(initial ?? const <RoomRecord>[]);

  final List<RoomRecord> _records;

  List<RoomRecord> get records => List<RoomRecord>.unmodifiable(_records);

  @override
  Future<void> ensureDirectory() async {}

  @override
  Future<List<RoomRecord>> loadAll() async => List<RoomRecord>.from(_records);

  @override
  Future<bool> upsert(RoomRecord record) async {
    final index = _records.indexWhere((r) => r.key == record.key);
    if (index >= 0) {
      _records[index] = record;
    } else {
      _records.add(record);
    }
    return true;
  }

  @override
  Future<bool> remove(String gameId, String myPlayerId) async {
    _records.removeWhere(
      (r) => r.gameId == gameId && r.myPlayerId == myPlayerId,
    );
    return true;
  }

  @override
  Future<void> clear() async => _records.clear();
}
