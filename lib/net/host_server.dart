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
    this.onConnected,
    this.onAnswer,
    this.onStop,
    this.onSnapshot,
    this.onDisconnected,
    this.onPing,
  });

  final Future<HelloDecision> Function(HelloRequest request)? onHello;

  /// Called after an accepted player's channel is registered and helloAck sent.
  final void Function(HelloRequest request)? onConnected;

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

/// Maximum simultaneous sockets waiting for a valid hello handshake.
const int kMaxPendingHandshakes = 32;

/// سرور شبکهٔ میزبان.
class HostNetwork {
  HostNetwork({
    required this.gameId,
    required this.token,
    required this.callbacks,
    this.preferredPort = 0,
    this.maxPendingHandshakes = kMaxPendingHandshakes,
  }) : assert(maxPendingHandshakes > 0);

  final String gameId;
  final String token;
  final HostCallbacks callbacks;
  final int preferredPort;
  final int maxPendingHandshakes;

  ServerSocket? _server;
  final Map<String, LineChannel> _channels = <String, LineChannel>{};
  final Map<String, MessageDeduper> _dedupers = <String, MessageDeduper>{};
  final Map<String, SequenceGuard> _guards = <String, SequenceGuard>{};
  final Set<String> _pendingHandshake = <String>{};
  final Map<String, LineChannel> _pendingChannels = <String, LineChannel>{};
  final Map<String, Timer> _pendingTimers = <String, Timer>{};
  int _pendingSequence = 0;

  /// شمارندهٔ اتصال‌های ناموفق (برای نمایش/گزارش).
  int rejectedConnections = 0;

  bool get isRunning => _server != null;

  int get port => _server?.port ?? 0;

  /// تعداد بازیکنان متصل.
  int get connectedCount => _channels.length;

  /// Number of sockets currently waiting for a valid hello handshake.
  int get pendingHandshakeCount => _pendingHandshake.length;

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
    if (_pendingHandshake.length >= maxPendingHandshakes) {
      rejectedConnections += 1;
      socket.destroy();
      return;
    }

    socket.setOption(SocketOption.tcpNoDelay, true);
    final channel = LineChannel(socket, label: 'pending');
    final key = 'pending-${++_pendingSequence}';
    _pendingHandshake.add(key);
    _pendingChannels[key] = channel;
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
      final playerId = boundPlayerId!;
      if (identical(_channels[playerId], channel)) {
        _handleMessage(playerId, channel, message);
      }
    });

    channel.done.then((_) {
      _pendingTimers.remove(key)?.cancel();
      _pendingHandshake.remove(key);
      _pendingSockets.remove(key);
      _pendingChannels.remove(key);
      final playerId = boundPlayerId;
      if (playerId != null && identical(_channels[playerId], channel)) {
        _channels.remove(playerId);
        _dedupers.remove(playerId);
        _guards.remove(playerId);
        callbacks.onDisconnected?.call(playerId);
      }
    });

    // فرصت کوتاه برای handshake.
    _pendingTimers[key] = Timer(const Duration(seconds: 15), () {
      if (boundPlayerId == null && !channel.isClosed) {
        unawaited(channel.close());
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
    if (channel.isClosed) {
      if (!_channels.containsKey(request.playerId)) {
        callbacks.onDisconnected?.call(request.playerId);
      }
      return;
    }

    // Register the replacement before closing the old channel. Its completion
    // callback must not remove this newer channel.
    final previous = _channels[request.playerId];
    _channels[request.playerId] = channel;
    _dedupers[request.playerId] = MessageDeduper();
    _guards[request.playerId] = SequenceGuard();
    _pendingSockets.remove(key)?.call(request.playerId);
    _pendingHandshake.remove(key);
    _pendingChannels.remove(key);
    _pendingTimers.remove(key)?.cancel();

    if (previous != null && !previous.isClosed) {
      unawaited(previous.close());
    }

    channel.send(MsgType.helloAck, {
      'pid': request.playerId,
      'gid': gameId,
      'resumed': decision.resumed,
      'serverNow': DateTime.now().millisecondsSinceEpoch,
    });
    // The app can now broadcast initial state to this registered channel.
    callbacks.onConnected?.call(request);
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
    if (channel != null) {
      _dedupers.remove(playerId);
      _guards.remove(playerId);
      callbacks.onDisconnected?.call(playerId);
      await channel.close();
    }
  }

  /// خاموش‌کردن سرور و بستن همهٔ اتصال‌ها.
  Future<void> stop() async {
    final server = _server;
    _server = null;
    await server?.close();

    for (final channel in _channels.values.toList()) {
      await channel.close();
    }
    for (final timer in _pendingTimers.values) {
      timer.cancel();
    }
    for (final channel in _pendingChannels.values.toList()) {
      await channel.close();
    }
    _pendingTimers.clear();
    _pendingChannels.clear();
    _pendingHandshake.clear();
    _channels.clear();
    _dedupers.clear();
    _guards.clear();
    _pendingSockets.clear();
  }
}
