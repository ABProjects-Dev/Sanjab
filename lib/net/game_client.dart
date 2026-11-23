/// A joined player's TCP connection to the host, with automatic retry.
library;

import 'dart:async';
import 'dart:io';

import 'line_channel.dart';
import 'protocol.dart';

/// Player connection state.
enum ClientConnectionState {
  /// Before the first connection attempt.
  idle,

  /// Connecting.
  connecting,

  /// Connected and authenticated.
  connected,

  /// Disconnected and retrying.
  reconnecting,

  /// Disconnected with retries stopped.
  disconnected,

  /// The host rejected the request.
  rejected,
}

/// One player's connection to the host.
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
  Timer? _snapshotRetryTimer;
  int? _pendingSnapshotRound;
  Map<int, String>? _pendingSnapshotAnswers;
  bool _closedByUser = false;
  bool _helloReceived = false;
  bool _hasConnectedOnce = false;

  static const Duration _snapshotRetryInterval = Duration(seconds: 2);

  /// Coalescing window for answer messages: typing sends one frame instead of
  /// one frame per keystroke, which keeps the host broadcast fan-out small.
  static const Duration _answerCoalesceInterval = Duration(milliseconds: 150);

  final Map<int, String> _pendingAnswers = <int, String>{};
  int? _pendingAnswerRound;
  Timer? _answerTimer;

  /// Messages received from the host.
  Stream<NetMessage> get messages => _incoming.stream;

  /// Connection state changes, for the UI.
  Stream<ClientConnectionState> get states => _states.stream;

  ClientConnectionState get state => _state;

  /// Last user-facing error message.
  String? get lastError => _lastError;

  /// Connected and authenticated: helloAck was received.
  bool get isConnected => _state == ClientConnectionState.connected;

  /// Exposed for diagnostics/tests: initial connection failures must not retry.
  bool get hasPendingReconnect => _retryTimer?.isActive ?? false;

  void _setState(ClientConnectionState next) {
    if (_state == next) return;
    _state = next;
    if (!_states.isClosed) _states.add(next);
  }

  /// Connect and authenticate.
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
            _hasConnectedOnce = true;
            _attempt = 0;
            _lastError = null;
            _setState(ClientConnectionState.connected);
            _guard.reset();
            if (!ready.isCompleted) ready.complete(true);
            if (!_incoming.isClosed) _incoming.add(message);
            _sendPendingSnapshot();
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
        if (message.type == MsgType.snapshotAck) {
          _handleSnapshotAck(message);
        }
        if (!_incoming.isClosed) _incoming.add(message);
      });

      channel.done.then((_) async {
        await subscription.cancel();
        if (_closedByUser) {
          _setState(ClientConnectionState.disconnected);
          return;
        }
        if (_state == ClientConnectionState.rejected) return;
        if (!_hasConnectedOnce) {
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
      if (_hasConnectedOnce) {
        _setState(ClientConnectionState.reconnecting);
        _scheduleReconnect();
      } else {
        _setState(ClientConnectionState.disconnected);
      }
      return false;
    }
  }

  void _scheduleReconnect() {
    if (!autoReconnect || _closedByUser || !_hasConnectedOnce) return;
    _retryTimer?.cancel();
    _attempt += 1;
    final delayMs = (_attempt * 1200).clamp(1200, 8000);
    _retryTimer = Timer(Duration(milliseconds: delayMs), () {
      if (_closedByUser) return;
      unawaited(connect());
    });
  }

  /// Queue an answer update for the host.
  ///
  /// The latest text per category is kept and flushed on a short timer, so a
  /// burst of keystrokes produces a single message per category.
  bool sendAnswer(int roundIndex, int categoryId, String text) {
    final channel = _channel;
    if (channel == null || _closedByUser) return false;
    final pendingRound = _pendingAnswerRound;
    if (pendingRound != null && pendingRound != roundIndex) {
      // A new round started while answers of the previous one were still
      // queued: flush them first so they keep their own round index instead of
      // being relabeled with the newer one.
      _flushPendingAnswers();
    }
    _pendingAnswerRound = roundIndex;
    _pendingAnswers[categoryId] = text;
    _answerTimer ??= Timer(_answerCoalesceInterval, () {
      _answerTimer = null;
      _flushPendingAnswers();
    });
    return true;
  }

  void _flushPendingAnswers() {
    final channel = _channel;
    final roundIndex = _pendingAnswerRound;
    if (channel == null || _closedByUser || roundIndex == null) {
      _pendingAnswers.clear();
      _pendingAnswerRound = null;
      return;
    }
    final pending = Map<int, String>.from(_pendingAnswers);
    _pendingAnswers.clear();
    _pendingAnswerRound = null;
    pending.forEach((categoryId, text) {
      channel.send(MsgType.answer, {
        'r': roundIndex,
        'c': categoryId,
        't': text,
      });
    });
  }

  /// Send every queued answer immediately.
  ///
  /// Used before a Stop request so the host holds this player's complete
  /// answers before it validates and records the Stop.
  void flushPendingAnswers() {
    _answerTimer?.cancel();
    _answerTimer = null;
    _flushPendingAnswers();
  }

  /// Send a Stop request.
  ///
  /// Any queued answer of the same round is flushed first: the two frames share
  /// one ordered channel, so the answers cannot be overtaken by the Stop.
  bool sendStop(int roundIndex) {
    flushPendingAnswers();
    return _channel?.send(MsgType.stop, {'r': roundIndex}) ?? false;
  }

  /// Announce an explicit exit; a plain disconnect never sends this.
  bool sendLeave() {
    if (!isConnected || _closedByUser) return false;
    return _channel?.send(MsgType.leave, const <String, dynamic>{}) ?? false;
  }

  /// Send a final-answer snapshot and retry it until the host acknowledges it.
  bool sendSnapshot(int roundIndex, Map<int, String> answers) {
    if (_closedByUser) return false;
    _pendingSnapshotRound = roundIndex;
    _pendingSnapshotAnswers = Map<int, String>.unmodifiable(answers);
    _sendPendingSnapshot();
    _snapshotRetryTimer ??= Timer.periodic(
      _snapshotRetryInterval,
      (_) => _sendPendingSnapshot(),
    );
    return true;
  }

  void _sendPendingSnapshot() {
    final roundIndex = _pendingSnapshotRound;
    final answers = _pendingSnapshotAnswers;
    final channel = _channel;
    if (roundIndex == null || answers == null || !isConnected) return;
    channel?.send(MsgType.snapshot, {
      'r': roundIndex,
      'a': answers.map((key, value) => MapEntry(key.toString(), value)),
    });
  }

  void _handleSnapshotAck(NetMessage message) {
    final roundIndex = message.payload['r'];
    if (message.payload['received'] != true ||
        roundIndex is! int ||
        roundIndex != _pendingSnapshotRound) {
      return;
    }
    discardPendingSnapshot();
  }

  /// Stop retrying a snapshot that is no longer relevant to the current round.
  void discardPendingSnapshot() {
    _snapshotRetryTimer?.cancel();
    _snapshotRetryTimer = null;
    _pendingSnapshotRound = null;
    _pendingSnapshotAnswers = null;
  }

  /// Close the connection without retrying.
  Future<void> close() async {
    _closedByUser = true;
    _answerTimer?.cancel();
    _answerTimer = null;
    _pendingAnswers.clear();
    _pendingAnswerRound = null;
    _retryTimer?.cancel();
    _snapshotRetryTimer?.cancel();
    _snapshotRetryTimer = null;
    _pendingSnapshotRound = null;
    _pendingSnapshotAnswers = null;
    await _channel?.close();
    _channel = null;
    _setState(ClientConnectionState.disconnected);
    await _incoming.close();
    await _states.close();
  }
}
