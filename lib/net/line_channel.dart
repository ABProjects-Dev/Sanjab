/// A TCP channel that exchanges JSON messages delimited by newline bytes.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'protocol.dart';

/// A TCP connection that exchanges [NetMessage]s as single-line JSON.
class LineChannel {
  LineChannel(this._socket, {this.label = ''}) {
    _subscription = _socket.listen(
      _onData,
      onError: (Object _) => _fail(),
      onDone: _closeFromStream,
      cancelOnError: true,
    );
  }

  final Socket _socket;
  final String label;
  BytesBuilder _lineBytes = BytesBuilder(copy: false);

  final StreamController<NetMessage> _messages =
      StreamController<NetMessage>.broadcast();
  final Completer<void> _done = Completer<void>();

  StreamSubscription<Uint8List>? _subscription;
  int _lineLength = 0;
  int _seq = 0;
  bool _closed = false;

  /// Incoming parsed messages. Invalid messages are ignored.
  Stream<NetMessage> get messages => _messages.stream;

  /// Completes when the socket is closed.
  Future<void> get done => _done.future;

  bool get isClosed => _closed;

  /// Remote address, when available.
  String get remoteAddress {
    try {
      return '${_socket.remoteAddress.address}:${_socket.remotePort}';
    } catch (_) {
      return label;
    }
  }

  /// Sends one message. Returns false when the channel is closed or the socket
  /// rejects the write.
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
      _fail();
      return false;
    }
  }

  /// Closes the socket and releases stream resources.
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
    _finish();
  }

  void _onData(List<int> chunk) {
    for (final byte in chunk) {
      if (_closed) return;
      if (byte == 0x0A) {
        final line = _lineBytes.takeBytes();
        _lineLength = 0;
        var end = line.length;
        if (end > 0 && line[end - 1] == 0x0D) end -= 1;
        if (end == 0) continue;
        _onLine(utf8.decode(line.sublist(0, end), allowMalformed: true));
        continue;
      }

      // Count raw bytes before buffering or decoding a potentially unterminated
      // frame. A CR in CRLF is included in this defensive limit.
      if (_lineLength >= kMaxMessageBytes) {
        _fail();
        return;
      }
      _lineBytes.addByte(byte);
      _lineLength += 1;
    }
  }

  void _onLine(String line) {
    if (line.trim().isEmpty) return;
    try {
      final message = NetMessage.parse(line);
      if (!_messages.isClosed) _messages.add(message);
    } on ProtocolException {
      // Invalid messages are discarded without ending the connection.
    }
  }

  /// Stops receiving immediately and destroys the socket, including when an
  /// oversized frame has not yet reached its newline delimiter.
  void _fail() {
    if (_closed) return;
    _closed = true;
    unawaited(_subscription?.cancel());
    _socket.destroy();
    _finish();
  }

  void _closeFromStream() {
    if (_closed) return;
    _closed = true;
    unawaited(_subscription?.cancel());
    _finish();
  }

  void _finish() {
    _lineBytes = BytesBuilder(copy: false);
    _lineLength = 0;
    if (!_messages.isClosed) unawaited(_messages.close());
    if (!_done.isCompleted) _done.complete();
  }
}
