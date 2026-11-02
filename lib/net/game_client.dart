/// اتصال بازیکن عضو به میزبان (TCP روی شبکهٔ محلی) با تلاش مجدد خودکار.
library;

import 'dart:async';
import 'dart:io';

import 'line_channel.dart';
import 'protocol.dart';

/// وضعیت اتصال بازیکن.
enum ClientConnectionState {
  /// پیش از تلاش اتصال.
  idle,

  /// در حال اتصال.
  connecting,

  /// متصل و احراز هویت‌شده.
  connected,

  /// قطع شده و در حال تلاش مجدد.
  reconnecting,

  /// اتصال قطع شده و تلاش مجدد متوقف است.
  disconnected,

  /// میزبان درخواست را رد کرد.
  rejected,
}

/// اتصال یک بازیکن به میزبان.
class GameClient {
  GameClient({
    required this.hostAddress,
    required this.port,
    required this.gameId,
    required this.token,
    required this.playerId,
    required this.displayName,
    this.autoReconnect = true,
  });

  final String hostAddress;
  final int port;
  final String gameId;
  final String token;
  final String playerId;
  final String displayName;
  final bool autoReconnect;

  LineChannel? _channel;
  final MessageDeduper _deduper = MessageDeduper();
  final SequenceGuard _guard = SequenceGuard();
  final StreamController<NetMessage> _incoming =
      StreamController<NetMessage>.broadcast();
  final StreamController<ClientConnectionState> _states =
      StreamController<ClientConnectionState>.broadcast();

  ClientConnectionState _state = ClientConnectionState.idle;
  String? _lastError;
  int _attempt = 0;
  Timer? _retryTimer;
  bool _closedByUser = false;
  bool _helloReceived = false;

  /// پیام‌های رسیده از میزبان.
  Stream<NetMessage> get messages => _incoming.stream;

  /// تغییر وضعیت اتصال (برای نمایش در رابط کاربری).
  Stream<ClientConnectionState> get states => _states.stream;

  ClientConnectionState get state => _state;

  /// آخرین خطای قابل نمایش (فارسی).
  String? get lastError => _lastError;

  /// اتصال برقرار شد و helloAck دریافت شد.
  bool get isConnected => _state == ClientConnectionState.connected;

  void _setState(ClientConnectionState next) {
    if (_state == next) return;
    _state = next;
    if (!_states.isClosed) _states.add(next);
  }

  /// تلاش برای اتصال و احراز هویت.
  Future<bool> connect() async {
    _closedByUser = false;
    _setState(ClientConnectionState.connecting);
    try {
      final socket = await Socket.connect(
        hostAddress,
        port,
        timeout: const Duration(seconds: 6),
      );
      socket.setOption(SocketOption.tcpNoDelay, true);
      final channel = LineChannel(socket, label: '$hostAddress:$port');
      _channel = channel;
      _helloReceived = false;

      final ready = Completer<bool>();
      final subscription = channel.messages.listen((message) {
        if (!_helloReceived) {
          if (message.type == MsgType.helloAck) {
            _helloReceived = true;
            _attempt = 0;
            _lastError = null;
            _setState(ClientConnectionState.connected);
            _guard.reset();
            if (!ready.isCompleted) ready.complete(true);
            if (!_incoming.isClosed) _incoming.add(message);
            return;
          }
          if (message.type == MsgType.helloReject) {
            _lastError =
                message.payload['reason'] as String? ??
                'ورود به بازی پذیرفته نشد.';
            _setState(ClientConnectionState.rejected);
            if (!ready.isCompleted) ready.complete(false);
            unawaited(channel.close());
            return;
          }
        }
        if (!_deduper.accept(message.id)) return;
        if (message.type != MsgType.ping && !_guard.accept(message.seq)) return;
        if (!_incoming.isClosed) _incoming.add(message);
      });

      channel.done.then((_) async {
        await subscription.cancel();
        if (_closedByUser) {
          _setState(ClientConnectionState.disconnected);
          return;
        }
        _setState(ClientConnectionState.reconnecting);
        _scheduleReconnect();
      });

      channel.send(MsgType.hello, {
        'gid': gameId,
        'token': token,
        'pid': playerId,
        'name': displayName,
      });

      final ok = await ready.future.timeout(
        const Duration(seconds: 8),
        onTimeout: () {
          _lastError = 'میزبان پاسخ نداد. یک‌بار دیگر تلاش کنید.';
          return false;
        },
      );
      if (!ok) {
        await channel.close();
        if (_state != ClientConnectionState.rejected) {
          _setState(ClientConnectionState.disconnected);
        }
      }
      return ok;
    } catch (error) {
      _lastError = 'اتصال به میزبان برقرار نشد. شبکهٔ مشترک را بررسی کنید.';
      _setState(ClientConnectionState.reconnecting);
      _scheduleReconnect();
      return false;
    }
  }

  void _scheduleReconnect() {
    if (!autoReconnect || _closedByUser) return;
    _retryTimer?.cancel();
    _attempt += 1;
    final delayMs = (_attempt * 1200).clamp(1200, 8000);
    _retryTimer = Timer(Duration(milliseconds: delayMs), () {
      if (_closedByUser) return;
      unawaited(connect());
    });
  }

  /// ارسال پاسخ یک دسته به میزبان.
  bool sendAnswer(int roundIndex, int categoryId, String text) =>
      _channel?.send(MsgType.answer, {
        'r': roundIndex,
        'c': categoryId,
        't': text,
      }) ??
      false;

  /// ارسال درخواست استپ.
  bool sendStop(int roundIndex) =>
      _channel?.send(MsgType.stop, {'r': roundIndex}) ?? false;

  /// ارسال Snapshot نهایی پاسخ‌ها.
  bool sendSnapshot(int roundIndex, Map<int, String> answers) =>
      _channel?.send(MsgType.snapshot, {
        'r': roundIndex,
        'a': answers.map((k, v) => MapEntry(k.toString(), v)),
      }) ??
      false;

  /// بستن اتصال (بدون تلاش مجدد).
  Future<void> close() async {
    _closedByUser = true;
    _retryTimer?.cancel();
    await _channel?.close();
    _channel = null;
    _setState(ClientConnectionState.disconnected);
    await _incoming.close();
    await _states.close();
  }
}
