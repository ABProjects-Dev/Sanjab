/// Host-local server: accepts player connections, authenticates session access
/// and exchanges state messages (host authoritative).
library;

import 'dart:async';
import 'dart:io';

import '../core/app_logger.dart';
import '../domain/answer_rules.dart';
import 'line_channel.dart';
import 'protocol.dart';

/// A player's join request.
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

/// The host's decision about a join request.
class HelloDecision {
  const HelloDecision.accept({this.resumed = false})
    : accepted = true,
      reason = null;

  const HelloDecision.reject(String this.reason)
    : accepted = false,
      resumed = false;

  final bool accepted;
  final String? reason;

  /// Whether this player was already in the session and is reconnecting.
  final bool resumed;
}

/// Events delivered from players to the host.
class HostCallbacks {
  const HostCallbacks({
    this.onHello,
    this.onConnected,
    this.onAnswer,
    this.onStop,
    this.onLeave,
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
  final void Function(String playerId)? onLeave;
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

/// The host network server.
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
  StreamSubscription<Socket>? _acceptSubscription;
  final Map<String, LineChannel> _channels = <String, LineChannel>{};
  final Map<String, MessageDeduper> _dedupers = <String, MessageDeduper>{};
  final Map<String, SequenceGuard> _guards = <String, SequenceGuard>{};
  final Set<String> _pendingHandshake = <String>{};
  final Map<String, LineChannel> _pendingChannels = <String, LineChannel>{};
  final Map<String, Timer> _pendingTimers = <String, Timer>{};
  int _pendingSequence = 0;

  /// Counter of rejected connections, for diagnostics.
  int rejectedConnections = 0;

  bool get isRunning => _server != null;

  int get port => _server?.port ?? 0;

  /// Number of connected players.
  int get connectedCount => _channels.length;

  /// Number of sockets currently waiting for a valid hello handshake.
  int get pendingHandshakeCount => _pendingHandshake.length;

  Set<String> get connectedPlayerIds => _channels.keys.toSet();

  /// Start the server on a free port.
  ///
  /// Accepting is deliberately defensive: a peer may reset between the TCP
  /// handshake and `accept`, and dart:io reports that as an error on the
  /// listening socket. Such an error must never escape as an uncaught exception
  /// nor end the accept loop, because the host has to keep admitting players.
  Future<void> start() async {
    if (_server != null) return;
    final server = await ServerSocket.bind(InternetAddress.anyIPv4, preferredPort);
    _server = server;
    _acceptSubscription = server.listen(
      _onSocket,
      onError: (Object error, StackTrace stack) {
        AppLogger.instance.error('net.accept.listen', error, stack);
      },
      cancelOnError: false,
    );
  }

  /// Local IPv4 addresses, for display and manual join.
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

  /// Accept one socket without ever letting it throw into the accept loop.
  ///
  /// A peer that connects and resets immediately is legitimate traffic; the
  /// resulting errors (socket configuration, stream setup) must be dropped on
  /// the floor instead of surfacing as uncaught errors.
  void _onSocket(Socket socket) {
    try {
      _acceptSocket(socket);
    } catch (error, stack) {
      rejectedConnections += 1;
      AppLogger.instance.error('net.accept.socket', error, stack);
      try {
        socket.destroy();
      } catch (_) {
        // Already gone.
      }
    }
  }

  void _acceptSocket(Socket socket) {
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
          // No message other than hello is accepted before authentication.
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

    // Short window for the handshake.
    _pendingTimers[key] = Timer(const Duration(seconds: 15), () {
      if (boundPlayerId == null && !channel.isClosed) {
        unawaited(channel.close());
      }
    });

    // Internal callback that binds the player ID after acceptance.
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
    // Minimal input validation.
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
    // 1) Duplicate message?
    final deduper = _dedupers[playerId];
    if (deduper != null && !deduper.accept(message.id)) return;
    // 2) Ordering: an old message is ignored.
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
        if (!isAnswerWithinLimit(text)) {
          _sendAnswerLengthError(channel);
          return;
        }
        callbacks.onAnswer?.call(playerId, round, category, text);
      case MsgType.stop:
        final round = message.payload['r'];
        if (round is! int) return;
        callbacks.onStop?.call(playerId, round);
      case MsgType.leave:
        callbacks.onLeave?.call(playerId);
        unawaited(disconnect(playerId));
      case MsgType.snapshot:
        final round = message.payload['r'];
        final answers = message.payload['a'];
        if (round is! int || answers is! Map<String, dynamic>) return;
        final parsed = <int, String>{};
        var rejectedLongAnswer = false;
        for (final entry in answers.entries) {
          final id = int.tryParse(entry.key);
          final value = entry.value;
          if (id == null || value is! String) continue;
          if (!isAnswerWithinLimit(value)) {
            rejectedLongAnswer = true;
            continue;
          }
          parsed[id] = value;
        }
        if (rejectedLongAnswer) _sendAnswerLengthError(channel);
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
        // Host-only message types are not accepted from a player.
        return;
    }
  }

  void _sendAnswerLengthError(LineChannel channel) {
    channel.send(MsgType.error, {
      'reason':
          'پاسخ بیشتر از ۸۰ نویسه است و ثبت نشد؛ لطفاً آن را کوتاه‌تر کنید.',
    });
  }

  /// Send a per-player state payload.
  bool sendState(String playerId, Map<String, dynamic> payload) {
    final channel = _channels[playerId];
    if (channel == null || channel.isClosed) return false;
    return channel.send(MsgType.state, payload);
  }

  /// Send a specific message to one player.
  bool sendTo(String playerId, MsgType type, Map<String, dynamic> payload) {
    final channel = _channels[playerId];
    if (channel == null || channel.isClosed) return false;
    return channel.send(type, payload);
  }

  /// Broadcast a message to every player.
  void broadcast(MsgType type, Map<String, dynamic> payload) {
    for (final entry in _channels.entries) {
      if (!entry.value.isClosed) entry.value.send(type, payload);
    }
  }

  /// Disconnect one player (kick or session end).
  Future<void> disconnect(String playerId) async {
    final channel = _channels.remove(playerId);
    if (channel != null) {
      _dedupers.remove(playerId);
      _guards.remove(playerId);
      callbacks.onDisconnected?.call(playerId);
      await channel.close();
    }
  }

  /// Stop the server and close every connection.
  /// Stop accepting immediately, without waiting for the teardown.
  ///
  /// Closing the listening socket releases the port synchronously. The accept
  /// subscription is deliberately left in place: dart:io reports an
  /// accept-time peer reset as an error on that stream, and cancelling the
  /// subscription would turn a late error into an uncaught zone error. The
  /// stream ends by itself once the socket is closed.
  void dispose() {
    final server = _server;
    _server = null;
    if (server != null) unawaited(server.close());
    _closeChannels();
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    // Close the listening socket first, keeping onError attached until the
    // close has completed; the subscription then ends with the stream.
    await server?.close();
    _acceptSubscription = null;
    await _closeChannelsAsync();
  }

  void _closeChannels() {
    for (final timer in _pendingTimers.values) {
      timer.cancel();
    }
    _pendingTimers.clear();
    for (final channel in <LineChannel>[
      ..._channels.values,
      ..._pendingChannels.values,
    ]) {
      unawaited(channel.close());
    }
    _pendingChannels.clear();
    _pendingHandshake.clear();
    _channels.clear();
    _dedupers.clear();
    _guards.clear();
    _pendingSockets.clear();
  }

  Future<void> _closeChannelsAsync() async {
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
