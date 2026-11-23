/// Game state management: the bridge between domain logic, the local network and the UI.
///
/// Two roles:
///  * **Host**: the only source of game state. [createGame] creates a session,
///    starts the local server, admits players, and owns the timer, judging and
///    scoring; it pushes authoritative state to every device.
///  * **Player**: [joinGame] connects to the host, sends its own answers and
///    mirrors the authoritative state received from the host.
///
/// No traffic leaves the local network: all communication happens on a hotspot
/// or shared Wi-Fi.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/app_logger.dart';
import '../core/persian.dart';
import '../core/screen_awake.dart';
import '../data/profile_repository.dart';
import '../data/room_repository.dart';
import '../data/session_repository.dart';
import '../domain/answer_rules.dart';
import '../domain/categories.dart';
import '../domain/game_session.dart';
import '../domain/models.dart';
import '../domain/profile.dart';
import '../domain/room_record.dart';
import '../domain/scoring.dart';
import '../net/discovery.dart';
import '../net/game_client.dart';
import '../net/host_server.dart';
import '../net/protocol.dart';

/// Port the host prefers for the local game server.
const int kDefaultHostPort = 50501;

/// Network state as shown in the UI.
enum NetStatus {
  /// No active session.
  offline,

  /// Host waiting for players.
  hosting,

  /// Player is connected.
  connected,

  /// Player is trying to reconnect.
  reconnecting,

  /// Connection is down.
  disconnected,
}

class GameController extends ChangeNotifier {
  GameController({
    required this.store,
    required this.profileRepo,
    RoomStore? roomStore,
    int Function()? clock,
    this.preferredHostPort = kDefaultHostPort,
  }) : _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch),
       roomStore = roomStore ?? MemoryRoomStore();

  /// Default preferred host port, mirrored for callers that only build a QR or
  /// a manual-entry default without holding the instance.
  static const int defaultHostPort = kDefaultHostPort;

  /// Port the host tries first; any free port is used when it is taken.
  ///
  /// Tests pin a distinct value so parallel or consecutive suites never race for
  /// the same listening port.
  final int preferredHostPort;

  final SessionStore store;
  final ProfileStore profileRepo;

  /// Durable room storage for this device.
  final RoomStore roomStore;
  final int Function() _clock;

  GameSession _session = GameSession.fresh();
  Profile _profile = Profile.empty;

  GameRole _role = GameRole.none;
  NetStatus _netStatus = NetStatus.offline;

  HostNetwork? _hostNet;
  DiscoveryBeacon? _beacon;
  GameClient? _client;
  ClientConnectionState _clientState = ClientConnectionState.idle;

  String _gameId = '';
  String _joinToken = '';

  /// Host address this device connected to in the player role.
  String _hostAddress = '';
  bool _openJoin = true;
  int _hostPort = 0;
  String _hostName = '';
  List<String> _localAddresses = const <String>[];

  /// Rooms saved on this device.
  List<RoomRecord> _rooms = <RoomRecord>[];

  /// Whether the session ended formally. Afterwards the session cannot be
  /// restored and its QR code and join token are invalid.
  bool _sessionFinished = false;

  /// Clock difference against the host, used to sync the timer.
  int _clockOffsetMs = 0;

  /// Snapshot is complete only after the matching host acknowledgment arrives.
  bool _snapshotAcknowledged = false;
  bool _snapshotRequested = false;
  int? _snapshotRoundIndex;

  bool _ready = false;
  bool foundSavedGame = false;
  String? _lastError;
  String? _lastNotice;

  Timer? _ticker;
  Timer? _hostPingTimer;
  int _lastTickSecond = -1;
  bool _saveScheduled = false;
  Timer? _saveTimer;

  /// Incremented whenever pending persistence must be abandoned (room exit,
  /// session end); a write that started earlier and lands later is then
  /// discarded instead of resurrecting deleted data.
  int _persistEpoch = 0;

  /// The write currently in progress, so a room exit can wait for it instead of
  /// racing it (an older write landing after the removal would bring the room
  /// back).
  Future<void>? _inFlightSave;

  /// Coalescing window for background persistence of typing and state changes.
  static const Duration _saveDebounce = Duration(milliseconds: 600);
  int _stateSeq = 0;
  bool _applyingRemoteState = false;

  // ------------------------------------------------------------------ Getter

  GameSession get session => _session;
  Profile get profile => _profile;
  GameRole get role => _role;
  bool get isHost => _role == GameRole.host;
  bool get isPlayer => _role == GameRole.player;
  bool get isReady => _ready;
  NetStatus get netStatus => _netStatus;
  ClientConnectionState get clientState => _clientState;
  String? get lastError => _lastError;
  String? get lastNotice => _lastNotice;
  String get gameId => _gameId;
  String get joinToken => _joinToken;
  String get hostName => _hostName;
  bool get openJoin => _openJoin;
  int get hostPort => _hostPort;
  List<String> get localAddresses => List<String>.unmodifiable(_localAddresses);
  bool get sessionFinished => _sessionFinished;
  String get gameName => _hostName.isEmpty ? 'بازی سنجاب' : 'بازی $_hostName';

  /// Display name of this device.
  String get myPlayerId => _profile.playerId;

  int nowMs() => _clock();

  /// Host-synchronized time; the player compensates for clock skew.
  int syncedNowMs() => _clock() + _clockOffsetMs;

  /// Remaining time of the current round on the host clock.
  int get remainingMs => _session.remainingMs(syncedNowMs());

  List<GameCategory> get activeCategories =>
      activeCategoriesOf(_session.config.activeCategoryIds);

  List<Player> get players => List<Player>.unmodifiable(_session.players);

  bool isPlayerStopped(String playerId) => _session.isPlayerStopped(playerId);

  SubmissionState submissionOf(String playerId) =>
      _session.currentRound?.submissionOf(playerId) ?? SubmissionState.typing;

  String answerText(String playerId, int categoryId) =>
      _session.currentRound?.answerOf(playerId, categoryId)?.text ?? '';

  String myAnswer(int categoryId) => answerText(myPlayerId, categoryId);

  bool get iAmStopped => _session.isPlayerStopped(myPlayerId);

  /// Whether the Stop button is enabled on this device.
  ///
  /// Requires the playing phase, no Stop yet, and at least two valid characters
  /// in every answer field of this player. Every device evaluates the player's
  /// own answers; the host uses the authoritative copy.
  bool get iCanStop {
    if (_session.phase != GamePhase.playing) return false;
    if (iAmStopped) return false;
    return _session.canPlayerStop(myPlayerId);
  }

  /// Answer fields of this player that still miss the two-character minimum.
  int get myPendingStopFields =>
      _session.pendingStopCategoryIds(myPlayerId).length;

  /// Hint text for the disabled Stop button.
  String get stopHintText {
    final pending = myPendingStopFields;
    if (pending <= 0) return '';
    return 'برای فعال شدن استپ، همهٔ پاسخ‌ها باید حداقل '
        '${faNum(kStopMinValidChars)} حرف داشته باشند '
        '(${faNum(pending)} پاسخ هنوز کوتاه است).';
  }

  bool get amIConnected =>
      isHost || _clientState == ClientConnectionState.connected;

  int get connectedPlayerCount => _session.connectedPlayerIds.length;

  void clearMessages() {
    _lastError = null;
    _lastNotice = null;
  }

  void _setError(String message) {
    _lastError = message;
    notifyListeners();
  }

  void _setNotice(String message) {
    _lastNotice = message;
    notifyListeners();
  }

  // ----------------------------------------------------------- Lifecycle

  /// Load the profile and any saved session at startup.
  Future<void> bootstrap() async {
    try {
      _profile = await profileRepo.load();
      if (!_profile.isConfigured) {
        // The ID exists already; the display name is chosen later on the profile screen.
        await profileRepo.save(_profile);
      }
      await store.ensureDirectory();
      await roomStore.ensureDirectory();
      _rooms = await roomStore.loadAll();
      final loaded = await store.load();
      if (loaded != null && loaded.phase != GamePhase.lobby) {
        // An unfinished host game or previous session can be restored.
        _session = loaded;
        _gameId = loaded.gameId;
        _hostName =
            loaded.playerById(loaded.hostPlayerId)?.name ??
            _profile.displayName;
        if (loaded.phase == GamePhase.playing && loaded.tickTimer(nowMs())) {
          loaded.applySnapshot(
            loaded.hostPlayerId,
            _ownAnswers(loaded),
            roundIndex: loaded.currentRound!.index,
          );
        }
        _role = GameRole.host;
        foundSavedGame = true;
        _netStatus = NetStatus.offline;
      }
      if (!foundSavedGame) {
        foundSavedGame = _rooms.any((r) => r.resumable);
      }
      // Migration of older saved sessions: a session may exist without a matching
      // room record; create the record so Resume stays available.
      if (_role == GameRole.host &&
          _session.phase != GamePhase.lobby &&
          _gameId.isNotEmpty &&
          !_rooms.any((r) => r.gameId == _gameId && r.myPlayerId == myPlayerId)) {
        await roomStore.upsert(
          RoomRecord(
            gameId: _gameId,
            roomName: gameName,
            hostPlayerId: _session.hostPlayerId.isEmpty
                ? myPlayerId
                : _session.hostPlayerId,
            hostName: _profile.displayName,
            myPlayerId: myPlayerId,
            myName: _profile.displayName,
            role: GameRole.host,
            address: '',
            port: 0,
            // Older versions did not persist the join token; it is regenerated on restore.
            token: '',
            phase: _session.phase,
            roundIndex: _session.currentRound?.index ?? 0,
            updatedAtEpochMs: nowMs(),
            remainingMs: _session.remainingMs(nowMs()),
            sessionSnapshot: _session.toJson(),
          ),
        );
        await _reloadRooms();
      }
    } catch (error, stack) {
      AppLogger.instance.error('bootstrap', error, stack);
      _lastError = 'بازیابی اطلاعات قبلی انجام نشد؛ از ابتدا شروع کنید.';
    }
    _ready = true;
    _syncTicker();
    notifyListeners();
  }

  /// Persist the state immediately (for example when the app goes to background).
  ///
  /// Any pending debounced save is superseded by this immediate write.
  Future<void> flush() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    _saveScheduled = false;
    await _persistNow();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _hostPingTimer?.cancel();
    _saveTimer?.cancel();
    _saveTimer = null;
    unawaited(_hostNet?.stop());
    unawaited(_beacon?.stop());
    unawaited(_client?.close());
    super.dispose();
  }

  // -------------------------------------------------------------- Profile

  /// Save the display name and update it in the active session roster.
  Future<bool> saveDisplayName(String name) async {
    final error = validateDisplayName(name);
    if (error != null) {
      _setError(error);
      return false;
    }
    final clean = name.trim();
    final previous = _profile;
    _profile = _profile.copyWith(displayName: clean);
    if (_session.playerById(_profile.playerId) != null) {
      try {
        _session.renamePlayer(_profile.playerId, clean);
      } on GameRuleException catch (e) {
        _profile = previous;
        _setError(e.message);
        return false;
      }
    }
    await profileRepo.save(_profile);
    if (isHost) _broadcastState();
    _lastNotice = 'نام نمایشی ذخیره شد.';
    notifyListeners();
    return true;
  }

  // ----------------------------------------------------------------- Host

  /// Create a game: fresh session, local server and discovery beacon.
  Future<bool> createGame({List<int>? activeCategoryIds}) async {
    if (_profile.displayName.trim().isEmpty) {
      _setError('پیش از ایجاد بازی، نام نمایشی خود را در پروفایل وارد کنید.');
      return false;
    }
    await closeSession(silent: true);
    _gameId = generateGameId();
    _joinToken = generateJoinToken();
    _hostName = _profile.displayName;
    _role = GameRole.host;
    _sessionFinished = false;
    _session = GameSession.fresh(
      nowMs: nowMs(),
      gameId: _gameId,
      hostPlayerId: _profile.playerId,
    );
    if (activeCategoryIds != null && activeCategoryIds.isNotEmpty) {
      _session.setActiveCategories(activeCategoryIds);
    }
    try {
      _session.addPlayer(
        _profile.displayName,
        id: _profile.playerId,
        isHost: true,
      );
    } on GameRuleException catch (e) {
      _setError(e.message);
      return false;
    }

    if (!await _startHostServices()) {
      _role = GameRole.none;
      return false;
    }
    await _persistNow();
    _broadcastState();
    notifyListeners();
    return true;
  }

  /// Start the local server, discovery and the host timer.
  ///
  /// Shared by Create and Resume on the host, so the server and QR come back
  /// after a restore.
  Future<bool> _startHostServices() async {
    HostCallbacks callbacks() => HostCallbacks(
      onHello: _handleHello,
      onConnected: (_) {
        _broadcastState();
        _touch();
      },
      onAnswer: _handleRemoteAnswer,
      onStop: _handleRemoteStop,
      onLeave: _handleRemoteLeave,
      onSnapshot: _handleRemoteSnapshot,
      onDisconnected: _handlePlayerDisconnected,
      onPing: (_) {},
    );

    await _hostNet?.stop();
    await _beacon?.stop();
    _hostNet = null;
    _beacon = null;

    // Try the default port first; otherwise take any free port from the system.
    HostNetwork? network;
    for (final preferredPort in <int>[preferredHostPort, 0]) {
      final candidate = HostNetwork(
        gameId: _gameId,
        token: _joinToken,
        preferredPort: preferredPort,
        callbacks: callbacks(),
      );
      try {
        await candidate.start();
        network = candidate;
        break;
      } catch (error) {
        AppLogger.instance.log(
          'host.start',
          'port $preferredPort unavailable: $error',
        );
        await candidate.stop();
      }
    }
    if (network == null) {
      _setError(
        'راه‌اندازی شبکهٔ محلی انجام نشد. Hotspot یا Wi-Fi را بررسی کنید.',
      );
      return false;
    }
    _hostNet = network;
    _hostPort = network.port;
    _localAddresses = await network.localAddresses();
    _beacon = DiscoveryBeacon(
      gameId: _gameId,
      gameName: gameName,
      hostName: _hostName,
      port: _hostPort,
      openJoin: _openJoin,
      token: _joinToken,
      playerCount: _session.activePlayerCount,
    );
    final beaconOk = await _beacon!.start();
    if (!beaconOk) {
      AppLogger.instance.log(
        'discovery',
        'beacon port unavailable; manual join only',
      );
    }
    _netStatus = NetStatus.hosting;
    _startHostTicker();
    _syncTicker();
    _syncScreenAwake();
    return true;
  }

  /// Toggle open join from the local network.
  void setOpenJoin(bool value) {
    if (!isHost) return;
    _openJoin = value;
    _beacon?.stop();
    _beacon = DiscoveryBeacon(
      gameId: _gameId,
      gameName: gameName,
      hostName: _hostName,
      port: _hostPort,
      openJoin: _openJoin,
      token: _joinToken,
      playerCount: _session.activePlayerCount,
    );
    unawaited(_beacon!.start());
    notifyListeners();
  }

  /// Change the active categories in the lobby.
  void setActiveCategories(List<int> ids) {
    if (!isHost) return;
    if (!_session.setActiveCategories(ids)) {
      _setError('تغییر دسته‌ها در این مرحله ممکن نیست.');
      return;
    }
    _broadcastState();
    _touch();
  }

  /// Remove a player from the lobby (host only).
  Future<void> removePlayer(String playerId) async {
    if (!isHost) return;
    if (playerId == _profile.playerId) return;
    try {
      _session.removePlayer(playerId);
    } on GameRuleException catch (e) {
      _setError(e.message);
      return;
    }
    _hostNet?.sendTo(playerId, MsgType.error, {
      'reason': 'میزبان شما را از بازی خارج کرد.',
    });
    await _hostNet?.disconnect(playerId);
    _beacon?.updatePlayerCount(_session.activePlayerCount);
    _broadcastState();
    _touch();
  }

  Future<HelloDecision> _handleHello(HelloRequest request) async {
    if (_sessionFinished) {
      return const HelloDecision.reject(
        'این نشست بازی به‌صورت رسمی تمام شده است؛ ورود امکان‌پذیر نیست.',
      );
    }
    if (_session.hasPlayerLeft(request.playerId)) {
      return const HelloDecision.reject(
        'شما به‌طور کامل از این بازی خارج شده‌اید و امکان اتصال دوباره ندارید.',
      );
    }
    if (_session.phase != GamePhase.lobby &&
        _session.playerById(request.playerId) == null) {
      return const HelloDecision.reject(
        'بازی شروع شده است؛ ورود بازیکن تازه ممکن نیست.',
      );
    }
    final existing = _session.playerById(request.playerId);
    if (existing != null) {
      // Reconnecting player: keep previous answers and only refresh the display
      // name. A name that now collides with another player must not abort the
      // handshake (an unhandled GameRuleException would leave the socket pending
      // until the 15s timeout), so the old name is kept in that case.
      _session.setConnected(request.playerId, true);
      try {
        _session.renamePlayer(request.playerId, request.displayName);
      } on GameRuleException catch (e) {
        AppLogger.instance.log('net', 'reconnect rename skipped: ${e.message}');
      }
      return const HelloDecision.accept(resumed: true);
    }
    try {
      _session.addPlayer(request.displayName, id: request.playerId);
    } on GameRuleException catch (e) {
      return HelloDecision.reject(e.message);
    }
    AppLogger.instance.log('net', 'player joined');
    _beacon?.updatePlayerCount(_session.activePlayerCount);
    return const HelloDecision.accept();
  }

  void _handleRemoteAnswer(
    String playerId,
    int roundIndex,
    int categoryId,
    String text,
  ) {
    final round = _session.currentRound;
    if (round == null || round.index != roundIndex) return;
    if (_session.setAnswer(playerId, categoryId, text)) {
      _broadcastState();
      _touch(save: false);
    }
  }

  void _handleRemoteStop(String playerId, int roundIndex) {
    final round = _session.currentRound;
    if (round == null || round.index != roundIndex) return;
    // The host independently checks that the player's own answers are complete;
    // an old, duplicate or incomplete request is dropped without effect.
    if (!_session.canPlayerStop(playerId)) {
      AppLogger.instance.log('net', 'stop rejected: incomplete answers');
      _hostNet?.sendTo(playerId, MsgType.error, {
        'reason':
            'استپ ثبت نشد: همهٔ پاسخ‌ها باید حداقل '
            '${faNum(kStopMinValidChars)} حرف داشته باشند.',
      });
      return;
    }
    if (!_session.requestStop(playerId, nowMs: nowMs())) return;
    // If the Stop threshold is not reached yet the round continues and no device,
    // including the host, may lock its answers.
    if (_session.phase == GamePhase.collecting) {
      _afterRoundEnded();
    } else {
      _broadcastState();
    }
    _touch();
  }

  void _handleRemoteSnapshot(
    String playerId,
    int roundIndex,
    Map<int, String> answers,
  ) {
    final round = _session.currentRound;
    final alreadyReceived =
        round != null &&
        round.index == roundIndex &&
        round.receivedSnapshotPlayerIds.contains(playerId);
    final applied = _session.applySnapshot(
      playerId,
      answers,
      roundIndex: roundIndex,
    );
    if (applied || alreadyReceived) {
      // A retransmission may arrive after the first acknowledgment was lost.
      // Re-acknowledge it without applying the snapshot twice.
      _hostNet?.sendTo(playerId, MsgType.snapshotAck, {
        'r': roundIndex,
        'received': true,
      });
    }
    if (!applied) return;
    AppLogger.instance.log('net', 'snapshot received');
    _session.tryStartJudging();
    _broadcastState();
    _touch();
  }

  void _handlePlayerDisconnected(String playerId) {
    // Transport loss is not an explicit departure: retain roster membership so
    // the same player may reconnect without changing the player count.
    _session.setConnected(playerId, false);
    AppLogger.instance.log('net', 'player disconnected');
    _broadcastState();
    _touch();
  }

  void _handleRemoteLeave(String playerId) {
    if (!isHost || !_session.markPlayerLeft(playerId)) return;
    _beacon?.updatePlayerCount(_session.activePlayerCount);
    final round = _session.currentRound;
    if ((_session.phase == GamePhase.playing ||
            _session.phase == GamePhase.paused) &&
        round != null &&
        round.stoppedPlayerIds.length >= round.stopThreshold &&
        _session.endRound(
          RoundEndReason.playerStop,
          nowMs: syncedNowMs(),
        )) {
      _afterRoundEnded();
    } else if (_session.phase == GamePhase.collecting) {
      _session.tryStartJudging();
    }
    AppLogger.instance.log('net', 'player explicitly left');
    _broadcastState();
    _touch();
  }

  /// Explicit host decision about a disconnected player: received answers are
  /// kept and missing ones are not treated as empty; the referee decides.
  void resolveOfflinePlayer(String playerId) {
    if (!isHost) return;
    if (_session.markSnapshotReceived(playerId)) {
      _session.tryStartJudging();
      _broadcastState();
      _touch();
      _setNotice(
        'این بازیکن از این دست کنار گذاشته شد؛ پاسخ‌های دریافتی حفظ شد.',
      );
    }
  }

  // ---------------------------------------------------------------- Player

  /// Search for active hosts on the local network.
  Future<List<DiscoveredHost>> scanHosts({
    Duration timeout = const Duration(milliseconds: 2500),
  }) async {
    if (_profile.displayName.trim().isEmpty) {
      _setError(
        'پیش از پیوستن به بازی، نام نمایشی خود را در پروفایل وارد کنید.',
      );
      return const <DiscoveredHost>[];
    }
    return discoverHosts(timeout: timeout);
  }

  /// Join a game with an address and a join token.
  Future<bool> joinGame({
    required String address,
    required int port,
    required String gameId,
    required String token,
    String hostName = '',
  }) async {
    if (_profile.displayName.trim().isEmpty) {
      _setError(
        'پیش از پیوستن به بازی، نام نمایشی خود را در پروفایل وارد کنید.',
      );
      return false;
    }
    await closeSession(silent: true);
    _sessionFinished = false;
    _gameId = gameId;
    _joinToken = token;
    _hostName = hostName;
    _hostAddress = address;
    _hostPort = port;
    _role = GameRole.player;
    _netStatus = NetStatus.reconnecting;
    _clockOffsetMs = 0;
    _resetSnapshotTracking();
    _session = GameSession.fresh(
      nowMs: nowMs(),
      gameId: gameId,
      hostPlayerId: '',
    );

    final ok = await _attachClient(
      address: address,
      port: port,
      gameId: gameId,
      token: token,
    );
    if (!ok) {
      await _detachAll();
      return false;
    }
    await _persistNow();
    notifyListeners();
    return true;
  }

  /// Build and connect the player client, shared by Join and Resume.
  Future<bool> _attachClient({
    required String address,
    required int port,
    required String gameId,
    required String token,
    bool removeRoomOnReject = false,
  }) async {
    final client = GameClient(
      hostAddress: address,
      port: port,
      gameId: gameId,
      token: token,
      playerId: _profile.playerId,
      displayName: _profile.displayName,
    );
    _client = client;
    var connectedOnce = false;
    client.states.listen((state) {
      if (!identical(_client, client)) return;
      if (state == ClientConnectionState.connected) connectedOnce = true;
      _clientState = state;
      _netStatus = switch (state) {
        ClientConnectionState.connected => NetStatus.connected,
        ClientConnectionState.reconnecting => NetStatus.reconnecting,
        ClientConnectionState.connecting => NetStatus.reconnecting,
        ClientConnectionState.rejected => NetStatus.disconnected,
        ClientConnectionState.disconnected => NetStatus.disconnected,
        ClientConnectionState.idle => NetStatus.offline,
      };
      if (state == ClientConnectionState.connected && isPlayer) {
        _maybeSendSnapshot();
      }
      if (state == ClientConnectionState.disconnected &&
          isPlayer &&
          connectedOnce) {
        _scheduleSave();
      }
      // An explicit rejection means the session ended or became invalid, so the room
      // record is removed and Resume is not offered misleadingly.
      if (state == ClientConnectionState.rejected &&
          isPlayer &&
          connectedOnce) {
        unawaited(_handleSessionEnded(
          'این جلسه پایان یافته یا نامعتبر است. اتاق از فهرست ادامه بازی حذف شد.',
        ));
      }
      notifyListeners();
    });
    client.messages.listen((message) {
      if (identical(_client, client)) _handleServerMessage(message);
    });

    final ok = await client.connect();
    if (!ok) {
      final terminalResumeRejection =
          removeRoomOnReject &&
          client.state == ClientConnectionState.rejected;
      final failedGameId = _gameId;
      if (terminalResumeRejection) {
        await _detachAll();
        await _removeRoomsOfGame(failedGameId);
        _sessionFinished = true;
        _setError(
          'میزبان این نشست را پایان‌یافته یا نامعتبر اعلام کرد؛ اتاق از فهرست حذف شد.',
        );
        return false;
      }
      _setError(client.lastError ?? 'اتصال به میزبان برقرار نشد.');
      _netStatus = NetStatus.disconnected;
      await client.close();
      if (identical(_client, client)) _client = null;
      _clientState = ClientConnectionState.disconnected;
      notifyListeners();
      return false;
    }
    _netStatus = NetStatus.connected;
    return true;
  }

  /// Leave the game as a player.
  Future<void> leaveGame() async {
    await _client?.close();
    _client = null;
    _clientState = ClientConnectionState.idle;
    _role = GameRole.none;
    _netStatus = NetStatus.offline;
    _session = GameSession.fresh(nowMs: nowMs());
    _syncTicker();
    _syncScreenAwake();
    notifyListeners();
  }

  void _handleServerMessage(NetMessage message) {
    if (_applyingRemoteState) return;
    switch (message.type) {
      case MsgType.state:
        _applyAuthoritativeState(message.payload);
      case MsgType.results:
        _applyAuthoritativeState(message.payload);
      case MsgType.snapshotAck:
        final roundIndex = message.payload['r'];
        if (message.payload['received'] == true &&
            roundIndex is int &&
            roundIndex == _snapshotRoundIndex) {
          _snapshotAcknowledged = true;
          _snapshotRequested = true;
          _setNotice('پاسخ‌های شما به میزبان رسید.');
        }
      case MsgType.sessionEnded:
        final reason =
            message.payload['reason'] as String? ??
            'بازی توسط میزبان پایان یافت.';
        unawaited(_handleSessionEnded(reason));
      case MsgType.error:
        final reason = message.payload['reason'] as String?;
        if (reason != null) _setError(reason);
      case MsgType.helloReject:
        final reason = message.payload['reason'] as String?;
        if (reason != null) _setError(reason);
      case MsgType.helloAck:
      case MsgType.hello:
      case MsgType.answer:
      case MsgType.stop:
      case MsgType.leave:
      case MsgType.snapshot:
      case MsgType.ping:
        break;
      case MsgType.pong:
        break;
    }
  }

  /// Apply the host's authoritative state to the local player copy.
  void _applyAuthoritativeState(Map<String, dynamic> payload) {
    _applyingRemoteState = true;
    try {
      final serverNow = (payload['serverNow'] as num?)?.toInt();
      if (serverNow != null) {
        _clockOffsetMs = serverNow - _clock();
      }
      final phaseName = payload['phase'] as String? ?? 'lobby';
      final phase = GamePhase.values.firstWhere(
        (p) => p.name == phaseName,
        orElse: () => GamePhase.lobby,
      );
      final playersJson = payload['players'];
      if (playersJson is List) {
        final incoming = <Player>[];
        final connected = <String>{};
        final left = <String>{};
        for (final raw in playersJson) {
          if (raw is! Map<String, dynamic>) continue;
          final id = raw['id'] as String?;
          final name = raw['name'] as String?;
          if (id == null || id.isEmpty || name == null) continue;
          incoming.add(Player(id: id, name: name, isHost: raw['h'] == true));
          if (raw['c'] == true) connected.add(id);
          if (raw['l'] == true) left.add(id);
        }
        if (incoming.isNotEmpty) {
          _session.players
            ..clear()
            ..addAll(incoming);
          _session.connectedPlayerIds
            ..clear()
            ..addAll(connected.difference(left));
          _session.leftPlayerIds
            ..clear()
            ..addAll(left);
          final hostId = incoming
              .firstWhere((p) => p.isHost, orElse: () => incoming.first)
              .id;
          if (_hostName.isEmpty) {
            _hostName = incoming.firstWhere((p) => p.id == hostId).name;
          }
        }
      }
      final cats = payload['cats'];
      if (cats is List) {
        final ids = cats.map((e) => (e as num).toInt()).toList(growable: false);
        _session.config = GameConfig(activeCategoryIds: ids);
      }
      final totals = payload['totals'];
      if (totals is Map<String, dynamic>) {
        _session.totals
          ..clear()
          ..addAll(totals.map((k, v) => MapEntry(k, (v as num).toInt())));
      }
      final roundIndex = (payload['round'] as num?)?.toInt() ?? 0;
      if (roundIndex > 0) {
        _ensureRound(roundIndex);
        final round = _session.currentRound!;
        round.endEpochMs =
            (payload['endEpochMs'] as num?)?.toInt() ?? round.endEpochMs;
        round.pausedRemainingMs = (payload['pausedRemainingMs'] as num?)
            ?.toInt();
        final reasonName = payload['endReason'] as String?;
        round.endReason = reasonName == null
            ? null
            : RoundEndReason.values.firstWhere(
                (r) => r.name == reasonName,
                orElse: () => RoundEndReason.referee,
              );
        // Submission state per player.
        final submissions = payload['submissions'];
        if (submissions is Map<String, dynamic>) {
          round.stoppedPlayerIds.clear();
          round.receivedSnapshotPlayerIds.clear();
          submissions.forEach((id, value) {
            final state = value as String?;
            if (state == SubmissionState.received.name) {
              round.receivedSnapshotPlayerIds.add(id);
              round.stoppedPlayerIds.add(id);
            } else if (state == SubmissionState.stopped.name) {
              round.stoppedPlayerIds.add(id);
            }
          });
        }
        // My answers come from the host, but local text wins while I am typing.
        final mine = payload['my'];
        if (mine is Map<String, dynamic>) {
          final typing = !round.stoppedPlayerIds.contains(_profile.playerId);
          for (final entry in mine.entries) {
            final categoryId = int.tryParse(entry.key);
            final text = entry.value;
            if (categoryId == null || text is! String) continue;
            final key = AnswerEntry.keyOf(
              round.index,
              _profile.playerId,
              categoryId,
            );
            final existing = round.answers[key];
            if (existing == null) {
              round.answers[key] = AnswerEntry(
                playerId: _profile.playerId,
                categoryId: categoryId,
                text: text,
                status: text.trim().isEmpty
                    ? JudgementStatus.empty
                    : JudgementStatus.unchecked,
              );
              continue;
            }
            if (typing) continue;
            round.answers[key] = existing.copyWith(
              text: text,
              status: text.trim().isEmpty
                  ? JudgementStatus.empty
                  : JudgementStatus.unchecked,
            );
          }
        }
        final roundScores = payload['roundScores'];
        if (roundScores is Map<String, dynamic>) {
          round.scores
            ..clear()
            ..addAll(
              roundScores.map((k, v) => MapEntry(k, (v as num).toInt())),
            );
        }
        round.judged = payload['judged'] == true;
      }
      _session.phase = phase;
      _stateSeq = (payload['seq'] as num?)?.toInt() ?? _stateSeq;
      if (phase == GamePhase.collecting) {
        _maybeSendSnapshot();
      }
      _syncTicker();
      _syncScreenAwake();
      // Persist the state on the player device.
      if (isPlayer) _scheduleSave();
      notifyListeners();
    } catch (error, stack) {
      AppLogger.instance.error('applyState', error, stack);
    } finally {
      _applyingRemoteState = false;
    }
  }

  void _ensureRound(int roundIndex) {
    final current = _session.currentRound;
    if (current != null && current.index == roundIndex) return;
    _resetSnapshotTracking();
    _session.rounds.add(
      RoundRecord(
        index: roundIndex,
        startedAtEpochMs: nowMs(),
        endEpochMs: nowMs() + kRoundDurationMs,
      ),
    );
  }

  // ------------------------------------------------------------------ Game

  /// Start a round as host; the timer starts immediately.
  ///
  /// Starting a round needs neither a word nor a letter.
  void startGame() {
    if (!isHost) return;
    if (!_session.canStartGame) {
      _setError('برای شروع بازی حداقل یک بازیکن لازم است.');
      return;
    }
    try {
      _session.startNewRound(nowMs: syncedNowMs());
    } on GameRuleException catch (e) {
      _setError(e.message);
      return;
    }
    _resetSnapshotTracking();
    _broadcastState();
    _syncTicker();
    _syncScreenAwake();
    _touch();
  }

  /// Start the next round, keeping the scores.
  void startNextRound() {
    if (!isHost) return;
    try {
      _session.startNewRound(nowMs: syncedNowMs());
    } on GameRuleException catch (e) {
      _setError(e.message);
      return;
    }
    _resetSnapshotTracking();
    _broadcastState();
    _syncTicker();
    _syncScreenAwake();
    _touch();
  }

  /// Record an answer: directly on the host, otherwise send and update locally.
  void setAnswer(int categoryId, String text) {
    if (!isAnswerWithinLimit(text)) {
      _setError('پاسخ حداکثر می‌تواند ۸۰ نویسه داشته باشد.');
      return;
    }
    final round = _session.currentRound;
    if (round == null) return;
    if (_session.phase != GamePhase.playing) return;
    if (_session.isPlayerStopped(myPlayerId)) return;
    if (isHost) {
      if (_session.setAnswer(myPlayerId, categoryId, text)) {
        _broadcastState();
        _touch();
      }
      return;
    }
    // Player: render locally first (no lag), then send to the host.
    final key = AnswerEntry.keyOf(round.index, myPlayerId, categoryId);
    final existing = round.answers[key];
    if (existing == null) return;
    if (existing.text != text) {
      round.answers[key] = existing.copyWith(
        text: text,
        status: text.trim().isEmpty
            ? JudgementStatus.empty
            : JudgementStatus.unchecked,
      );
      notifyListeners();
    }
    _client?.sendAnswer(round.index, categoryId, text);
  }

  /// Pressing the Stop button.
  ///
  /// The player's own answers are validated first; a single field with fewer
  /// than two valid characters rejects the action, even on repeated taps or an
  /// old or duplicate event.
  Future<void> requestStop() async {
    final round = _session.currentRound;
    if (round == null) return;
    if (_session.phase != GamePhase.playing &&
        _session.phase != GamePhase.paused) {
      return;
    }
    if (iAmStopped) return;
    if (!_session.canPlayerStop(myPlayerId)) {
      _setError(
        'برای استپ باید همهٔ پاسخ‌ها حداقل '
        '${faNum(kStopMinValidChars)} حرف داشته باشند.',
      );
      return;
    }
    if (isHost) {
      if (!_session.requestStop(myPlayerId, nowMs: syncedNowMs())) return;
      // Until the Stop threshold is met the round continues and answers stay unlocked.
      if (_session.phase == GamePhase.collecting) {
        _afterRoundEnded();
      } else {
        _broadcastState();
      }
      _touch();
      return;
    }
    // Player: flush the latest answers first on the ordered channel so the host
    // has this player's complete answers before handling the Stop. sendStop
    // additionally flushes anything queued after these writes.
    for (final category in activeCategories) {
      _client?.sendAnswer(round.index, category.id, myAnswer(category.id));
    }
    _client?.sendStop(round.index);
    _setNotice('درخواست استپ برای میزبان ارسال شد.');
  }

  /// Pause or resume the timer (host only).
  void pauseGame() {
    if (!isHost) return;
    if (_session.pause(syncedNowMs())) {
      _broadcastState();
      _syncTicker();
      _touch();
    }
  }

  void resumeGame() {
    if (!isHost) return;
    if (_session.resume(syncedNowMs())) {
      _broadcastState();
      _syncTicker();
      _touch();
    }
  }

  /// End the round manually as host.
  void forceEndRound() {
    if (!isHost) return;
    if (_session.endRound(RoundEndReason.referee, nowMs: syncedNowMs())) {
      _afterRoundEnded();
      _touch();
    }
  }

  /// After the round ends, send our own answers and wait for the others.
  void _afterRoundEnded() {
    final round = _session.currentRound;
    if (round == null) return;
    if (isHost) {
      _session.applySnapshot(
        myPlayerId,
        _ownAnswers(_session),
        roundIndex: round.index,
      );
      _snapshotAcknowledged = true;
      _snapshotRequested = true;
      _snapshotRoundIndex = round.index;
      _session.tryStartJudging();
      _broadcastState();
    } else {
      _maybeSendSnapshot();
    }
    _syncTicker();
    _syncScreenAwake();
  }

  Map<int, String> _ownAnswers(GameSession session) {
    final round = session.currentRound;
    final result = <int, String>{};
    if (round == null) return result;
    for (final categoryId in session.config.activeCategoryIds) {
      final answer = round.answerOf(myPlayerId, categoryId);
      if (answer != null) result[categoryId] = answer.text;
    }
    return result;
  }

  void _resetSnapshotTracking() {
    _client?.discardPendingSnapshot();
    _snapshotAcknowledged = false;
    _snapshotRequested = false;
    _snapshotRoundIndex = null;
  }

  void _maybeSendSnapshot() {
    if (isHost || _session.phase != GamePhase.collecting) return;
    final round = _session.currentRound;
    if (round == null) return;
    if (_snapshotRoundIndex != round.index) {
      _resetSnapshotTracking();
      _snapshotRoundIndex = round.index;
    }
    if (_snapshotAcknowledged || _snapshotRequested) return;
    final client = _client;
    if (client == null || !client.isConnected) return;
    // GameClient retains and retries the payload until a matching snapshotAck.
    _snapshotRequested = client.sendSnapshot(
      round.index,
      _ownAnswers(_session),
    );
  }

  // --------------------------------------------------------------- Judging

  void setJudgement(String playerId, int categoryId, JudgementStatus? status) {
    if (!isHost) return;
    _session.setJudgement(playerId, categoryId, status);
    _touch(save: false);
  }

  /// Finalize judging and announce results to every device.
  RoundScoring finalizeJudging() {
    if (!isHost) {
      throw GameRuleException('داوری فقط روی دستگاه میزبان انجام می‌شود.');
    }
    final scored = _session.finalizeJudging();
    _broadcastState();
    _syncTicker();
    _touch();
    return scored;
  }

  /// Formally end the game as host.
  ///
  /// - The end is broadcast; online players return Home immediately and offline
  ///   players find the ended state when they next start the app.
  /// - The room is marked ended, its connection and QR become invalid and Resume
  ///   disappears; nobody can rejoin an ended session.
  Future<void> finishGame() async {
    if (!isHost) return;
    final gameId = _gameId;
    await _cancelPendingSave();
    await _broadcastSessionEnded(
      'بازی توسط میزبان به‌صورت رسمی پایان یافت.',
    );
    await _detachAll();
    await store.clear();
    await _removeRoomsOfGame(gameId);
    _sessionFinished = true;
    _lastNotice = 'بازی به‌صورت رسمی پایان یافت.';
    _syncTicker();
    _syncScreenAwake();
    notifyListeners();
  }

  /// Broadcast the session end and mark the rooms of that session.
  Future<void> _broadcastSessionEnded(String reason) async {
    _hostNet?.broadcast(MsgType.sessionEnded, {
      'reason': reason,
      'gameId': _gameId,
    });
    // Give the message a brief moment to arrive before closing sockets.
    await Future<void>.delayed(const Duration(milliseconds: 120));
  }

  /// Delete every room record of one session (formal end or explicit exit).
  Future<void> _removeRoomsOfGame(String gameId) async {
    if (gameId.isEmpty) return;
    final all = await roomStore.loadAll();
    for (final room in all) {
      if (room.gameId == gameId) {
        await roomStore.remove(room.gameId, room.myPlayerId);
      }
    }
    await _reloadRooms();
  }

  /// End the session on a player device after the host announced it.
  Future<void> _handleSessionEnded(String reason) async {
    final gameId = _gameId;
    await _cancelPendingSave();
    await _detachAll();
    await _removeRoomsOfGame(gameId);
    _sessionFinished = true;
    _lastNotice = reason;
    _syncTicker();
    _syncScreenAwake();
    notifyListeners();
  }

  /// Return Home keeping the room resumable.
  ///
  /// A lone host closes the room on return so the server and discovery stop;
  /// with other members present the state and connections are kept and the host
  /// can come back through Resume.
  Future<void> backToHome() async {
    if (isHost && _session.activePlayerCount <= 1) {
      await leaveRoom();
      return;
    }
    await _persistNow();
    notifyListeners();
  }

  /// Explicit exit from the room, distinct from going Home, after confirmation.
  ///
  /// The room record is removed so Resume is no longer offered.
  /// As host this ends the session for everyone, since the host is authoritative.
  Future<void> leaveRoom([RoomRecord? room]) async {
    await _cancelPendingSave();
    final target = room;
    if (target != null) {
      final isCurrentRoom =
          target.gameId == _gameId && target.myPlayerId == myPlayerId;
      if (isCurrentRoom) {
        if (isHost) {
          await _broadcastSessionEnded('میزبان از اتاق خارج شد؛ بازی پایان یافت.');
        } else if (isPlayer) {
          // Only this explicit action removes roster membership; a socket loss
          // is handled separately and remains reconnectable.
          _client?.sendLeave();
        }
        await _detachAll();
        await store.clear();
      }
      await roomStore.remove(target.gameId, target.myPlayerId);
      if (target.isHost && isCurrentRoom) {
        await _removeRoomsOfGame(target.gameId);
      }
      await _reloadRooms();
      notifyListeners();
      return;
    }
    final gameId = _gameId;
    if (isHost) {
      await _broadcastSessionEnded('میزبان از اتاق خارج شد؛ بازی پایان یافت.');
    } else if (isPlayer) {
      _client?.sendLeave();
    }
    await _detachAll();
    await store.clear();
    await _removeRoomsOfGame(gameId);
    if (gameId.isNotEmpty) {
      await roomStore.remove(gameId, myPlayerId);
    }
    await _reloadRooms();
    notifyListeners();
  }

  /// Close all links and return to the role-less state, keeping the room record.
  Future<void> _detachAll() async {
    await _hostNet?.stop();
    _hostNet = null;
    await _beacon?.stop();
    _beacon = null;
    await _client?.close();
    _client = null;
    _clientState = ClientConnectionState.idle;
    _ticker?.cancel();
    _ticker = null;
    _hostPingTimer?.cancel();
    _hostPingTimer = null;
    _role = GameRole.none;
    _netStatus = NetStatus.offline;
    _gameId = '';
    _joinToken = '';
    _hostPort = 0;
    _hostAddress = '';
    _hostName = '';
    _localAddresses = const <String>[];
    _resetSnapshotTracking();
    _clockOffsetMs = 0;
    _session = GameSession.fresh(nowMs: nowMs());
  }

  /// Leave the game (legacy entry point): links are closed but the room record
  /// is kept so Resume stays possible.
  Future<void> closeSession({bool silent = false}) async {
    final keep = _role == GameRole.host ? _session : null;
    final keepGameId = _gameId;
    final keepToken = _joinToken;
    final keepHostName = _hostName;
    final keepAddress = _hostAddress;
    final keepPort = _hostPort;
    await _persistNow();
    await _detachAll();
    if (keep != null) {
      _session = keep;
      _gameId = keepGameId;
      _joinToken = keepToken;
      _hostName = keepHostName;
      _hostAddress = keepAddress;
      _hostPort = keepPort;
      _role = GameRole.host;
    }
    foundSavedGame = _rooms.any((r) => r.resumable);
    _syncTicker();
    _syncScreenAwake();
    if (!silent) notifyListeners();
  }

  // --------------------------------------------------------- Saved rooms

  /// Rooms shown on this device, newest first.
  List<RoomRecord> get savedRooms {
    final list = _rooms.where((r) => !r.ended).toList(growable: false);
    final sorted = List<RoomRecord>.from(list)
      ..sort((a, b) => b.updatedAtEpochMs.compareTo(a.updatedAtEpochMs));
    return List<RoomRecord>.unmodifiable(sorted);
  }

  /// Whether a resumable room exists.
  bool get hasResumableRoom => savedRooms.any((r) => r.resumable);

  /// Current room of this device when a role is active.
  RoomRecord? get activeRoom {
    if (_gameId.isEmpty || _role == GameRole.none) return null;
    for (final room in _rooms) {
      if (room.gameId == _gameId && room.myPlayerId == myPlayerId) return room;
    }
    return null;
  }

  /// Reload the room list from storage, for the UI and tests.
  Future<void> reloadSavedRooms() async {
    await _reloadRooms();
    notifyListeners();
  }

  Future<void> _reloadRooms() async {
    _rooms = await roomStore.loadAll();
    foundSavedGame = _rooms.any((r) => r.resumable);
  }

  /// Build a room record from the current state.
  RoomRecord? _roomRecordFromState() {
    if (_gameId.isEmpty || _role == GameRole.none) return null;
    final round = _session.currentRound;
    final answers = <int, String>{};
    if (round != null) {
      for (final categoryId in _session.config.activeCategoryIds) {
        final answer = round.answerOf(myPlayerId, categoryId);
        if (answer != null && answer.text.trim().isNotEmpty) {
          answers[categoryId] = answer.text;
        }
      }
    }
    return RoomRecord(
      gameId: _gameId,
      roomName: gameName,
      hostPlayerId: _session.hostPlayerId.isEmpty
          ? (isHost ? myPlayerId : '')
          : _session.hostPlayerId,
      hostName: isHost ? _profile.displayName : _hostName,
      myPlayerId: myPlayerId,
      myName: _profile.displayName,
      role: _role,
      address: isHost
          ? (_localAddresses.isNotEmpty ? _localAddresses.first : '')
          : _hostAddress,
      port: _hostPort,
      token: _joinToken,
      phase: _session.phase,
      roundIndex: round?.index ?? 0,
      updatedAtEpochMs: nowMs(),
      remainingMs: _session.remainingMs(syncedNowMs()),
      linkStatus: switch (_netStatus) {
        NetStatus.connected || NetStatus.hosting => RoomLinkStatus.online,
        NetStatus.reconnecting => RoomLinkStatus.connecting,
        _ => RoomLinkStatus.offline,
      },
      myAnswers: answers,
      stopped: round?.stoppedPlayerIds.contains(myPlayerId) ?? false,
      sessionSnapshot: _session.toJson(),
    );
  }

  /// Resume a saved room as host or player.
  Future<bool> resumeRoom(RoomRecord room) async {
    if (room.myPlayerId != _profile.playerId) {
      _setError(
        'این اتاق به پروفایل دیگری تعلق دارد و با این دستگاه قابل بازیابی نیست.',
      );
      return false;
    }
    if (!room.resumable) {
      _setError('این اتاق پایان یافته است و قابل ادامه نیست.');
      return false;
    }
    return room.isHost ? _resumeAsHost(room) : _resumeAsPlayer(room);
  }

  Future<bool> _resumeAsHost(RoomRecord room) async {
    final snapshot = room.sessionSnapshot;
    if (snapshot == null) {
      _setError('اطلاعات ذخیره‌شدهٔ این جلسه کامل نیست.');
      return false;
    }
    GameSession restored;
    try {
      restored = GameSession.fromJson(snapshot);
    } catch (error, stack) {
      AppLogger.instance.error('resume.host', error, stack);
      _setError('بازیابی جلسه انجام نشد؛ دادهٔ ذخیره‌شده معتبر نیست.');
      return false;
    }
    if (restored.hostPlayerId != _profile.playerId) {
      _setError('فقط میزبان اصلی می‌تواند این جلسه را بازیابی کند.');
      return false;
    }
    await closeSession(silent: true);
    _session = restored;
    _role = GameRole.host;
    _gameId = room.gameId;
    _joinToken = room.token.isEmpty ? generateJoinToken() : room.token;
    _hostName =
        restored.playerById(restored.hostPlayerId)?.name ??
        _profile.displayName;
    _hostAddress = '';
    _sessionFinished = false;
    _resetSnapshotTracking();
    _clockOffsetMs = 0;

    // Restore the timer from the saved remaining time.
    final round = _session.currentRound;
    if (round != null) {
      final remaining = room.remainingMs > 0
          ? room.remainingMs
          : kRoundDurationMs;
      if (_session.phase == GamePhase.playing) {
        round.endEpochMs = nowMs() + remaining;
        round.pausedRemainingMs = null;
      } else if (_session.phase == GamePhase.paused) {
        round.pausedRemainingMs = remaining;
      }
    }
    // After a restore, players start out disconnected until they reconnect.
    for (final player in _session.players) {
      if (player.id != myPlayerId) {
        _session.setConnected(player.id, false);
      }
    }
    if (!await _startHostServices()) {
      _role = GameRole.none;
      return false;
    }
    await _persistNow();
    _broadcastState();
    _lastNotice = 'جلسهٔ قبلی بازیابی شد؛ QR جدید برای اتصال بازیکنان آماده است.';
    notifyListeners();
    return true;
  }

  Future<bool> _resumeAsPlayer(RoomRecord room) async {
    if (room.address.isEmpty || room.port <= 0 || room.token.isEmpty) {
      _setError('اطلاعات اتصال این اتاق برای بازیابی کافی نیست.');
      return false;
    }
    final snapshot = room.sessionSnapshot;
    await closeSession(silent: true);
    _role = GameRole.player;
    _gameId = room.gameId;
    _joinToken = room.token;
    _hostName = room.hostName;
    _hostAddress = room.address;
    _hostPort = room.port;
    _netStatus = NetStatus.reconnecting;
    _clockOffsetMs = 0;
    _resetSnapshotTracking();
    _sessionFinished = false;
    if (snapshot != null) {
      try {
        _session = GameSession.fromJson(snapshot);
      } catch (error, stack) {
        AppLogger.instance.error('resume.player', error, stack);
        _session = GameSession.fresh(
          nowMs: nowMs(),
          gameId: room.gameId,
          hostPlayerId: room.hostPlayerId,
        );
      }
    } else {
      _session = GameSession.fresh(
        nowMs: nowMs(),
        gameId: room.gameId,
        hostPlayerId: room.hostPlayerId,
      );
    }
    _session.phase = room.phase == GamePhase.finished
        ? GamePhase.lobby
        : room.phase;
    _restoreMyAnswers(room.myAnswers);

    final ok = await _attachClient(
      address: room.address,
      port: room.port,
      gameId: room.gameId,
      token: room.token,
      removeRoomOnReject: true,
    );
    if (!ok) {
      if (_sessionFinished) {
        _syncTicker();
        notifyListeners();
        return false;
      }
      // The room is unreachable for now; the record stays for a later retry.
      _netStatus = NetStatus.disconnected;
      _role = GameRole.player;
      _setError(
        'اتاق در حال حاضر در دسترس نیست. مطمئن شوید میزبان بازی را بازیابی '
        'کرده و هر دو دستگاه به یک شبکهٔ محلی وصل‌اند؛ سپس دوباره تلاش کنید.',
      );
      await _client?.close();
      _client = null;
      _clientState = ClientConnectionState.idle;
      _syncTicker();
      notifyListeners();
      return false;
    }
    _netStatus = NetStatus.connected;
    await _persistNow();
    _lastNotice = 'به اتاق قبلی وصل شدید.';
    _syncTicker();
    _syncScreenAwake();
    notifyListeners();
    return true;
  }

  void _restoreMyAnswers(Map<int, String> answers) {
    final round = _session.currentRound;
    if (round == null || answers.isEmpty) return;
    answers.forEach((categoryId, text) {
      final key = AnswerEntry.keyOf(round.index, myPlayerId, categoryId);
      final existing = round.answers[key];
      if (existing == null) {
        round.answers[key] = AnswerEntry(
          playerId: myPlayerId,
          categoryId: categoryId,
          text: text,
          status: text.trim().isEmpty
              ? JudgementStatus.empty
              : JudgementStatus.unchecked,
        );
      } else {
        round.answers[key] = existing.copyWith(text: text);
      }
    });
  }

  /// Build the QR payload used to join the host.
  ///
  /// Contains the session ID, host address, port, join token, host name,
  /// creation time and expiry; the QR becomes invalid once the session ends.
  Map<String, dynamic> qrConnectionPayload() {
    final now = nowMs();
    return <String, dynamic>{
      'v': 1,
      'type': 'sm_join',
      'gameId': _gameId,
      'host': _localAddresses.isNotEmpty ? _localAddresses.first : '',
      'port': _hostPort,
      'token': _joinToken,
      'hostName': _hostName,
      'createdAt': now,
      'expiresAt': now + const Duration(days: 7).inMilliseconds,
    };
  }

  /// Validate data scanned from a QR code.
  ///
  /// Validation is structural and independent of any local session, because
  /// comparing against a local session ID used to reject every scan on a player
  /// device that had no session yet.
  bool qrPayloadValid(Map<String, dynamic>? payload) {
    if (payload == null) return false;
    if (payload['v'] != 1 || payload['type'] != 'sm_join') return false;
    final gameId = payload['gameId'];
    if (gameId is! String || gameId.isEmpty) return false;
    final token = payload['token'];
    if (token is! String || token.isEmpty) return false;
    final host = payload['host'];
    if (host is! String || host.isEmpty) return false;
    final port = payload['port'];
    if (port is! num || port <= 0) return false;
    final expiresAt = (payload['expiresAt'] as num?)?.toInt();
    if (expiresAt != null && nowMs() > expiresAt) return false;
    return true;
  }

  /// Discard every saved game on this device.
  Future<void> discardSavedGame() async {
    await _cancelPendingSave();
    await closeSession(silent: true);
    await store.clear();
    await roomStore.clear();
    await _reloadRooms();
    _role = GameRole.none;
    _session = GameSession.fresh(nowMs: nowMs());
    notifyListeners();
  }

  // -------------------------------------------------------------- Internal

  void _broadcastState() {
    final host = _hostNet;
    if (host == null) return;
    _stateSeq += 1;
    for (final player in _session.players) {
      if (player.id == myPlayerId) continue;
      host.sendState(player.id, _statePayloadFor(player.id));
    }
  }

  Map<String, dynamic> _statePayloadFor(String playerId) {
    final round = _session.currentRound;
    final submissions = <String, String>{};
    if (round != null) {
      for (final player in _session.players) {
        submissions[player.id] = round.submissionOf(player.id).name;
      }
    }
    final myAnswers = <String, String>{};
    if (round != null) {
      for (final categoryId in _session.config.activeCategoryIds) {
        final answer = round.answerOf(playerId, categoryId);
        if (answer != null) myAnswers[categoryId.toString()] = answer.text;
      }
    }
    return {
      'seq': _stateSeq,
      'serverNow': syncedNowMs(),
      'phase': _session.phase.name,
      'round': round?.index ?? 0,
      'endEpochMs': round?.endEpochMs,
      'pausedRemainingMs': round?.pausedRemainingMs,
      'endReason': round?.endReason?.name,
      'judged': round?.judged ?? false,
      'players': _session.players
          .map(
            (p) => {
              'id': p.id,
              'name': p.name,
              'h': p.isHost,
              'c': _session.isConnected(p.id),
              'l': _session.hasPlayerLeft(p.id),
            },
          )
          .toList(growable: false),
      'cats': _session.config.activeCategoryIds,
      'totals': _session.totals,
      'submissions': submissions,
      'my': myAnswers,
      'roundScores': round?.scores ?? const <String, int>{},
      'pending': _session.pendingSnapshotPlayerIds,
    };
  }

  void _startHostTicker() {
    _hostPingTimer?.cancel();
    _hostPingTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _beacon?.updatePlayerCount(_session.activePlayerCount);
    });
  }

  void _syncTicker() {
    final needTicker =
        _session.phase == GamePhase.playing &&
        (isHost || _clientState == ClientConnectionState.connected);
    if (needTicker && _ticker == null) {
      _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (isHost) {
          if (_session.tickTimer(syncedNowMs())) {
            _afterRoundEnded();
            _lastTickSecond = -1;
            _touch();
            return;
          }
        }
        final second = (remainingMs / 1000).ceil();
        if (second != _lastTickSecond) {
          _lastTickSecond = second;
          if (second <= 0 && !isHost) {
            // Time is up; wait for the host announcement without changing state.
            notifyListeners();
          } else {
            notifyListeners();
          }
        }
      });
    } else if (!needTicker && _ticker != null) {
      _ticker!.cancel();
      _ticker = null;
    }
    _lastTickSecond = -1;
  }

  void _syncScreenAwake() {
    final inGame =
        _session.phase == GamePhase.playing ||
        _session.phase == GamePhase.paused ||
        _session.phase == GamePhase.collecting ||
        _session.phase == GamePhase.judging ||
        _session.phase == GamePhase.roundResults;
    unawaited(ScreenAwake.setEnabled(inGame));
  }

  void _touch({bool save = true}) {
    notifyListeners();
    if (save) _scheduleSave();
  }

  /// Drop any pending save, wait for a running one, and refuse both.
  Future<void> _cancelPendingSave() async {
    _persistEpoch += 1;
    _saveTimer?.cancel();
    _saveTimer = null;
    _saveScheduled = false;
    final running = _inFlightSave;
    if (running != null) {
      // Errors are already handled inside the write itself.
      await running;
    }
  }

  void _scheduleSave() {
    if (_saveScheduled) return;
    _saveScheduled = true;
    // Debounce: answer-by-answer typing would otherwise rewrite the whole
    // session and room JSON for every keystroke. A pending timer is flushed
    // explicitly by [_persistNow] callers (lifecycle flush, leave, finish).
    _saveTimer?.cancel();
    _saveTimer = Timer(_saveDebounce, () async {
      _saveScheduled = false;
      _saveTimer = null;
      await _persistNow();
    });
  }

  Future<void> _persistNow() {
    final write = _writeState();
    _inFlightSave = write;
    return write.whenComplete(() {
      if (identical(_inFlightSave, write)) _inFlightSave = null;
    });
  }

  Future<void> _writeState() async {
    if (_role == GameRole.none) return;
    final epoch = _persistEpoch;
    if (isHost) {
      final ok = await store.save(_session, nowMs: nowMs());
      if (!ok) {
        _lastError = 'ذخیرهٔ اطلاعات بازی انجام نشد.';
      }
      // A room exit or a session end happened while this write was running.
      if (epoch != _persistEpoch) return;
    }
    final record = _roomRecordFromState();
    if (record == null) return;
    final ok = await roomStore.upsert(record);
    if (!ok && _lastError == null) {
      _lastError = 'ذخیرهٔ اطلاعات اتاق انجام نشد.';
    }
    // An exit that landed while the room write was running already reloaded.
    if (epoch != _persistEpoch) return;
    await _reloadRooms();
  }
}
