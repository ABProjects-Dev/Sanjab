/// سرور محلی میزبان: پذیرش اتصال بازیکنان، احراز دسترسی به نشست و
/// تبادل پیام‌های وضعیت (Host Authoritative).
library;

import 'dart:async';
import 'dart:io';

import 'line_channel.dart';
import 'protocol.dart';

/// درخواست ورود یک بازیکن.
class HelloRequest {
  const HelloRequest({
    required this.gameId,
    required this.token,
    required this.playerId,
    required this.displayName,
    required this.remoteAddress,
  });

  final String gameId;
  final String token;
  final String playerId;
  final String displayName;
  final String remoteAddress;
}

/// تصمیم میزبان دربارهٔ درخواست ورود.
class HelloDecision {
  const HelloDecision.accept({this.resumed = false})
    : accepted = true,
      reason = null;

  const HelloDecision.reject(String this.reason)
    : accepted = false,
      resumed = false;

  final bool accepted;
  final String? reason;

  /// آیا این بازیکن قبلاً در نشست بوده و اکنون دوباره وصل شده است.
  final bool resumed;
}

/// رویدادهای رسیده از بازیکنان به میزبان.
class HostCallbacks {
  const HostCallbacks({
    this.onHello,
    this.onAnswer,
    this.onStop,
    this.onSnapshot,
    this.onDisconnected,
    this.onPing,
  });

  final Future<HelloDecision> Function(HelloRequest request)? onHello;
  final void Function(
    String playerId,
    int roundIndex,
    int categoryId,
    String text,
  )?
  onAnswer;
  final void Function(String playerId, int roundIndex)? onStop;
  final void Function(
    String playerId,
    int roundIndex,
    Map<int, String> answers,
  )?
  onSnapshot;
  final void Function(String playerId)? onDisconnected;
  final void Function(String playerId)? onPing;
}

/// سرور شبکهٔ میزبان.
class HostNetwork {
  HostNetwork({
    required this.gameId,
    required this.token,
    required this.callbacks,
    this.preferredPort = 0,
  });

  final String gameId;
  final String token;
  final HostCallbacks callbacks;
  final int preferredPort;

  ServerSocket? _server;
  final Map<String, LineChannel> _channels = <String, LineChannel>{};
  final Map<String, MessageDeduper> _dedupers = <String, MessageDeduper>{};
  final Map<String, SequenceGuard> _guards = <String, SequenceGuard>{};
  final Set<String> _pendingHandshake = <String>{};

  /// شمارندهٔ اتصال‌های ناموفق (برای نمایش/گزارش).
  int rejectedConnections = 0;

  bool get isRunning => _server != null;

  int get port => _server?.port ?? 0;

  /// تعداد بازیکنان متصل.
  int get connectedCount => _channels.length;

  Set<String> get connectedPlayerIds => _channels.keys.toSet();

  /// راه‌اندازی سرور روی یک پورت آزاد.
  Future<void> start() async {
    if (_server != null) return;
    _server = await ServerSocket.bind(InternetAddress.anyIPv4, preferredPort);
    _server!.listen(_onSocket, onError: (Object _) {});
  }

  /// آدرس‌های IPv4 محلی دستگاه (برای نمایش و ورود دستی).
  Future<List<String>> localAddresses() async {
    final result = <String>[];
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final iface in interfaces) {
        for (final address in iface.addresses) {
          if (!address.isLoopback) result.add(address.address);
        }
      }
    } catch (_) {}
    return result;
  }

  void _onSocket(Socket socket) {
    socket.setOption(SocketOption.tcpNoDelay, true);
    final channel = LineChannel(socket, label: 'pending');
    final key = 'pending-${DateTime.now().microsecondsSinceEpoch}';
    _pendingHandshake.add(key);
    String? boundPlayerId;

    channel.messages.listen((message) {
      if (boundPlayerId == null) {
        if (message.type != MsgType.hello) {
          // پیش از احراز هویت هیچ پیام دیگری پذیرفته نمی‌شود.
          rejectedConnections += 1;
          channel.send(MsgType.helloReject, {
            'reason': 'ابتدا باید به بازی وارد شوید.',
          });
          channel.close();
          return;
        }
        unawaited(_handleHello(channel, message, key));
        return;
      }
      _handleMessage(boundPlayerId!, channel, message);
    });

    channel.done.then((_) {
      _pendingHandshake.remove(key);
      if (boundPlayerId != null) {
        final wasBound = _channels.remove(boundPlayerId);
        _dedupers.remove(boundPlayerId);
        _guards.remove(boundPlayerId);
        if (wasBound != null) callbacks.onDisconnected?.call(boundPlayerId!);
      }
    });

    // فرصت کوتاه برای handshake.
    Timer(const Duration(seconds: 15), () {
      if (boundPlayerId == null && !channel.isClosed) {
        channel.close();
      }
    });

    // callback داخلی برای ثبت شناسه پس از پذیرش.
    _pendingSockets[key] = (id) => boundPlayerId = id;
  }

  final Map<String, void Function(String playerId)> _pendingSockets =
      <String, void Function(String)>{};

  Future<void> _handleHello(
    LineChannel channel,
    NetMessage message,
    String key,
  ) async {
    final p = message.payload;
    final request = HelloRequest(
      gameId: p['gid'] as String? ?? '',
      token: p['token'] as String? ?? '',
      playerId: p['pid'] as String? ?? '',
      displayName: p['name'] as String? ?? '',
      remoteAddress: channel.remoteAddress,
    );
    // اعتبارسنجی حداقلی ورودی‌ها.
    if (request.gameId != gameId && request.gameId != '*') {
      rejectedConnections += 1;
      channel.send(MsgType.helloReject, {
        'reason': 'این بازی پیدا نشد یا تمام شده است.',
      });
      await channel.close();
      return;
    }
    if (request.token != token) {
      rejectedConnections += 1;
      channel.send(MsgType.helloReject, {'reason': 'کد اتصال درست نیست.'});
      await channel.close();
      return;
    }
    if (request.playerId.isEmpty || request.playerId.length > 40) {
      rejectedConnections += 1;
      channel.send(MsgType.helloReject, {
        'reason': 'شناسهٔ بازیکن معتبر نیست.',
      });
      await channel.close();
      return;
    }
    final decision =
        await callbacks.onHello?.call(request) ??
        const HelloDecision.reject('میزبان اکنون آمادهٔ پذیرش بازیکن نیست.');
    if (!decision.accepted) {
      rejectedConnections += 1;
      channel.send(MsgType.helloReject, {
        'reason': decision.reason ?? 'ورود به بازی پذیرفته نشد.',
      });
      await channel.close();
      return;
    }

    // جای‌گزینی اتصال قبلی همان بازیکن (اتصال مجدد).
    final previous = _channels.remove(request.playerId);
    if (previous != null && !previous.isClosed) {
      unawaited(previous.close());
    }
    _channels[request.playerId] = channel;
    _dedupers[request.playerId] = MessageDeduper();
    _guards[request.playerId] = SequenceGuard();
    _pendingSockets[key]?.call(request.playerId);
    _pendingHandshake.remove(key);

    channel.send(MsgType.helloAck, {
      'pid': request.playerId,
      'gid': gameId,
      'resumed': decision.resumed,
      'serverNow': DateTime.now().millisecondsSinceEpoch,
    });
  }

  void _handleMessage(
    String playerId,
    LineChannel channel,
    NetMessage message,
  ) {
    // ۱) پیام تکراری؟
    final deduper = _dedupers[playerId];
    if (deduper != null && !deduper.accept(message.id)) return;
    // ۲) ترتیب پیام‌ها (پیام قدیمی نادیده گرفته می‌شود).
    final guard = _guards[playerId];
    if (guard != null && message.type != MsgType.ping) {
      if (!guard.accept(message.seq)) return;
    }
    switch (message.type) {
      case MsgType.answer:
        final round = message.payload['r'];
        final category = message.payload['c'];
        final text = message.payload['t'];
        if (round is! int || category is! int || text is! String) return;
        if (text.length > 80) return; // پاسخ غیرمنطقی
        callbacks.onAnswer?.call(playerId, round, category, text);
      case MsgType.stop:
        final round = message.payload['r'];
        if (round is! int) return;
        callbacks.onStop?.call(playerId, round);
      case MsgType.snapshot:
        final round = message.payload['r'];
        final answers = message.payload['a'];
        if (round is! int || answers is! Map<String, dynamic>) return;
        final parsed = <int, String>{};
        for (final entry in answers.entries) {
          final id = int.tryParse(entry.key);
          final value = entry.value;
          if (id == null || value is! String || value.length > 80) continue;
          parsed[id] = value;
        }
        callbacks.onSnapshot?.call(playerId, round, parsed);
      case MsgType.ping:
        channel.send(MsgType.pong, {
          'serverNow': DateTime.now().millisecondsSinceEpoch,
        });
        callbacks.onPing?.call(playerId);
      case MsgType.pong:
        break;
      case MsgType.hello:
      case MsgType.helloAck:
      case MsgType.helloReject:
      case MsgType.state:
      case MsgType.snapshotAck:
      case MsgType.results:
      case MsgType.sessionEnded:
      case MsgType.error:
        // پیام‌هایی که فقط میزبان می‌فرستد؛ از بازیکن پذیرفته نمی‌شوند.
        return;
    }
  }

  /// ارسال وضعیت شخصی‌سازی‌شده به یک بازیکن.
  bool sendState(String playerId, Map<String, dynamic> payload) {
    final channel = _channels[playerId];
    if (channel == null || channel.isClosed) return false;
    return channel.send(MsgType.state, payload);
  }

  /// ارسال پیام مشخص به یک بازیکن.
  bool sendTo(String playerId, MsgType type, Map<String, dynamic> payload) {
    final channel = _channels[playerId];
    if (channel == null || channel.isClosed) return false;
    return channel.send(type, payload);
  }

  /// اعلام نتایج داوری به همهٔ بازیکنان.
  void broadcast(MsgType type, Map<String, dynamic> payload) {
    for (final entry in _channels.entries) {
      if (!entry.value.isClosed) entry.value.send(type, payload);
    }
  }

  /// قطع اتصال یک بازیکن (اخراج یا پایان نشست).
  Future<void> disconnect(String playerId) async {
    final channel = _channels.remove(playerId);
    if (channel != null) await channel.close();
  }

  /// خاموش‌کردن سرور و بستن همهٔ اتصال‌ها.
  Future<void> stop() async {
    for (final channel in _channels.values.toList()) {
      await channel.close();
    }
    _channels.clear();
    _dedupers.clear();
    _guards.clear();
    _pendingSockets.clear();
    await _server?.close();
    _server = null;
  }
}
