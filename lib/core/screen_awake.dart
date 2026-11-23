/// Keeps the screen awake during play.
///
/// Implemented with a small platform channel on the Android side
/// (no extra dependency). Silently ignored on test and desktop platforms.
library;

import 'package:flutter/services.dart';

class ScreenAwake {
  ScreenAwake._();

  static const MethodChannel _channel = MethodChannel(
    'com.sanjab.game/screen',
  );

  static bool _current = false;

  /// Enable or disable keeping the screen awake.
  static Future<void> setEnabled(bool enabled) async {
    if (_current == enabled) return;
    _current = enabled;
    try {
      await _channel.invokeMethod<void>('keepScreenOn', enabled);
    } on MissingPluginException {
      // Test environment or platform without an implementation: ignore.
    } on PlatformException {
      // A failed system flag must not interrupt gameplay.
    } catch (_) {
      // Where the binding or platform side is unavailable (tests, desktop),
      // this feature is ignored silently and never interrupts gameplay.
    }
  }
}
