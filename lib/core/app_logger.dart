/// Internal technical logger with a size cap and controlled cleanup.
///
/// Principles:
///  - The user sees a readable Persian message;
///  - Technical detail goes to the internal log only;
///  - Player answers and personal data are never written to the log
///    (only IDs, counters and technical error names).
library;

import 'dart:async';
import 'dart:io';

/// Minimal file-backed logger.
class AppLogger {
  AppLogger._();

  static final AppLogger instance = AppLogger._();

  /// Maximum log file size in bytes; the file rotates at this limit.
  static const int maxFileBytes = 256 * 1024;

  /// Maximum number of rotated files kept.
  static const int maxRotatedFiles = 2;

  File? _file;
  bool _initialized = false;
  final List<String> _recent = <String>[];

  /// Recent log lines, shown on the technical log screen.
  List<String> get recent => List<String>.unmodifiable(_recent);

  /// Path of the current log file.
  String? get path => _file?.path;

  /// Initialize with the application data directory.
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

  /// Record a technical event. [message] must never contain player answers.
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
      // Logging must never throw.
    }
  }

  void error(String tag, Object error, [StackTrace? stack]) {
    log(tag, '${error.runtimeType}: $error');
    if (stack != null) {
      final first = stack.toString().split('\n').take(6).join(' | ');
      log(tag, 'trace: $first');
    }
  }

  /// Rotate files, keeping at most [maxRotatedFiles] rotations.
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
      // On failure, truncate the current file so it cannot grow without bound.
      try {
        _file!.writeAsStringSync('', flush: true);
      } catch (_) {}
    }
  }

  /// Delete every log file (from Settings).
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
