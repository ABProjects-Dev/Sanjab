/// کانال پیام‌محور روی یک Socket TCP (JSON تک‌خطی).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'protocol.dart';

/// یک اتصال TCP که پیام‌های [NetMessage] را با جداکنندهٔ خط مبادله می‌کند.
class LineChannel {
  LineChannel(this._socket, {this.label = ''}) {
    _subscription = _socket
        .cast<List<int>>()
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen(
          _onLine,
          onError: (Object error) => _fail(error),
          onDone: () => _close(notify: true),
          cancelOnError: true,
        );
  }

  final Socket _socket;
  final String label;

  final StreamController<NetMessage> _messages =
      StreamController<NetMessage>.broadcast();
  final Completer<void> _done = Completer<void>();

  StreamSubscription<String>? _subscription;
  int _seq = 0;
  bool _closed = false;

  /// جریان پیام‌های دریافتی (پیام‌های نامعتبر نادیده گرفته می‌شوند).
  Stream<NetMessage> get messages => _messages.stream;

  /// با بسته‌شدن اتصال تکمیل می‌شود.
  Future<void> get done => _done.future;

  bool get isClosed => _closed;

  /// آدرس مبدأ (برای نمایش وضعیت شبکه).
  String get remoteAddress {
    try {
      return '${_socket.remoteAddress.address}:${_socket.remotePort}';
    } catch (_) {
      return label;
    }
  }

  /// ارسال یک پیام. در صورت بسته‌بودن اتصال false برمی‌گرداند.
  bool send(MsgType type, Map<String, dynamic> payload) {
    if (_closed) return false;
    _seq += 1;
    final message = NetMessage(
      type: type,
      id: newMessageId(),
      seq: _seq,
      payload: payload,
    );
    try {
      _socket.add(utf8.encode(message.encode()));
      return true;
    } catch (_) {
      _close(notify: true);
      return false;
    }
  }

  /// بستن اتصال.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await _socket.flush();
    } catch (_) {}
    try {
      await _subscription?.cancel();
    } catch (_) {}
    try {
      await _socket.close();
    } catch (_) {}
    if (!_messages.isClosed) await _messages.close();
    if (!_done.isCompleted) _done.complete();
  }

  void _onLine(String line) {
    if (line.trim().isEmpty) return;
    try {
      final message = NetMessage.parse(line);
      if (!_messages.isClosed) _messages.add(message);
    } on ProtocolException {
      // پیام نامعتبر دور ریخته می‌شود؛ اتصال قطع نمی‌شود.
    }
  }

  void _fail(Object error) {
    _close(notify: false);
  }

  void _close({required bool notify}) {
    if (_closed) return;
    _closed = true;
    _subscription?.cancel();
    _messages.close();
    if (!_done.isCompleted) _done.complete();
  }
}
