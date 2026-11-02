/// مدیریت وضعیت بازی ۱.۰.۰ — پل میان منطق دامنه، شبکهٔ محلی و رابط کاربری.
///
/// دو نقش:
///  * **میزبان (Host)**: تنها مرجع وضعیت بازی. با [createGame] نشست می‌سازد،
///    سرور محلی را بالا می‌آورد، ورود بازیکنان را مدیریت می‌کند، زمان‌سنج و
///    داوری و امتیازدهی فقط روی دستگاه او انجام می‌شود و وضعیت را برای همه
///    می‌فرستد.
///  * **بازیکن (Player)**: با [joinGame] به میزبان وصل می‌شود، پاسخ‌های خود را
///    می‌فرستد و وضعیت معتبر را از میزبان می‌گیرد (Host Authoritative).
///
/// هیچ داده‌ای از شبکهٔ اینترنت رد و بدل نمی‌شود؛ همهٔ ارتباطات روی شبکهٔ محلی
/// (Hotspot یا Wi-Fi مشترک) است.
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

/// حالت اتصال شبکه برای نمایش در رابط کاربری.
enum NetStatus {
  /// نشستی فعال نیست.
  offline,

  /// میزبان در حال انتظار برای بازیکنان.
  hosting,

  /// بازیکن متصل است.
  connected,

  /// بازیکن در حال تلاش برای اتصال مجدد.
  reconnecting,

  /// اتصال قطع شده است.
  disconnected,
}

class GameController extends ChangeNotifier {
  GameController({
    required this.store,
    required this.profileRepo,
    RoomStore? roomStore,
    int Function()? clock,
  }) : _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch),
       roomStore = roomStore ?? MemoryRoomStore();

  final SessionStore store;
  final ProfileStore profileRepo;

  /// ذخیره‌سازی پایدار اتاق‌های این دستگاه (نسخهٔ ۱.۰.۰).
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

  /// آدرس میزبان که این دستگاه (در نقش بازیکن) به آن وصل شده است.
  String _hostAddress = '';
  bool _openJoin = true;
  int _hostPort = 0;
  String _hostName = '';
  List<String> _localAddresses = const <String>[];

  /// اتاق‌های ذخیره‌شده روی این دستگاه (نسخهٔ ۱.۰.۰).
  List<RoomRecord> _rooms = <RoomRecord>[];

  /// آیا نشست به‌صورت resmi (رسمی) تمام شده است. پس از پایان رسمی، بازیابی
  /// این نشست امکان‌پذیر نیست و QR / توکن نامعتبر است.
  bool _sessionFinished = false;

  /// اختلاف ساعت دستگاه با میزبان (برای زمان‌سنج همگام).
  int _clockOffsetMs = 0;

  /// جلوگیری از ارسال چندبارهٔ Snapshot توسط بازیکن.
  bool _snapshotSent = false;

  bool _ready = false;
  bool foundSavedGame = false;
  String? _lastError;
  String? _lastNotice;

  Timer? _ticker;
  Timer? _hostPingTimer;
  int _lastTickSecond = -1;
  bool _saveScheduled = false;
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

  /// نام نمایشی این دستگاه.
  String get myPlayerId => _profile.playerId;

  int nowMs() => _clock();

  /// زمان همگام‌شده با میزبان (روی دستگاه بازیکن، اختلاف ساعت جبران می‌شود).
  int syncedNowMs() => _clock() + _clockOffsetMs;

  /// مدت باقی‌ماندهٔ دست جاری بر اساس زمان مرجع میزبان.
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

  /// (نسخهٔ ۱.۰.۰) آیا دکمهٔ «استپ» برای این دستگاه فعال است؟
  ///
  /// شرط: فاز بازی، استپ نکرده باشیم و همهٔ فیلدهای پاسخ همین بازیکن
  /// حداقل دو کاراکتر معتبر داشته باشند. وضعیت در همهٔ دستگاه‌ها بر اساس
  /// پاسخ‌های همان بازیکن سنجیده می‌شود (روی میزبان با نسخهٔ معتبر پاسخ‌ها).
  bool get iCanStop {
    if (_session.phase != GamePhase.playing) return false;
    if (iAmStopped) return false;
    return _session.canPlayerStop(myPlayerId);
  }

  /// تعداد فیلدهای پاسخ این بازیکن که هنوز شرط حداقل دو کاراکتر را ندارند.
  int get myPendingStopFields =>
      _session.pendingStopCategoryIds(myPlayerId).length;

  /// متن راهنمای دکمهٔ غیرفعال «استپ».
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

  // ------------------------------------------------------------ چرخهٔ عمر

  /// بارگذاری پروفایل و بازی ذخیره‌شده در شروع برنامه.
  Future<void> bootstrap() async {
    try {
      _profile = await profileRepo.load();
      if (!_profile.isConfigured) {
        // شناسه ساخته شده است؛ نام نمایشی بعداً در صفحهٔ پروفایل تعیین می‌شود.
        await profileRepo.save(_profile);
      }
      await store.ensureDirectory();
      await roomStore.ensureDirectory();
      _rooms = await roomStore.loadAll();
      final loaded = await store.load();
      if (loaded != null && loaded.phase != GamePhase.lobby) {
        // بازی نیمه‌تمام میزبان (یا نشست قبلی) قابل بازیابی است.
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
      // مهاجرت نشست‌های ذخیره‌شدهٔ قدیمی: ممکن است نشست موجود باشد اما رکورد
      // اتاق متناظر نداشته باشد؛ رکورد را می‌سازیم تا «ادامه بازی» در دسترس باشد.
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
            // توکن نشست در نسخه‌های قبلی ذخیره نمی‌شد؛ هنگام بازیابی تازه می‌شود.
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

  /// ذخیرهٔ فوری وضعیت (هنگام رفتن برنامه به پس‌زمینه).
  Future<void> flush() async {
    await _persistNow();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _hostPingTimer?.cancel();
    unawaited(_hostNet?.stop());
    unawaited(_beacon?.stop());
    unawaited(_client?.close());
    super.dispose();
  }

  // ---------------------------------------------------------------- پروفایل

  /// ذخیرهٔ نام نمایشی. در نشست فعال، نام در فهرست بازیکنان هم به‌روز می‌شود.
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

  // ------------------------------------------------------------- میزبان

  /// ایجاد بازی: نشست تازه، سرور محلی و اعلان شناسایی.
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

  /// راه‌اندازی سرور محلی، اعلان کشف و زمان‌سنج میزبان.
  ///
  /// این بخش هم در «ایجاد بازی» و هم در «ادامه بازی میزبان» استفاده می‌شود تا
  /// پس از بازیابی، سرور و QR دوباره فعال شوند (نسخهٔ ۱.۰.۰).
  Future<bool> _startHostServices() async {
    HostCallbacks callbacks() => HostCallbacks(
      onHello: _handleHello,
      onAnswer: _handleRemoteAnswer,
      onStop: _handleRemoteStop,
      onSnapshot: _handleRemoteSnapshot,
      onDisconnected: _handlePlayerDisconnected,
      onPing: (_) {},
    );

    await _hostNet?.stop();
    await _beacon?.stop();
    _hostNet = null;
    _beacon = null;

    // ابتدا پورت پیش‌فرض؛ اگر در دسترس نبود یک پورت آزاد از سیستم گرفته می‌شود.
    HostNetwork? network;
    for (final preferredPort in const <int>[50501, 0]) {
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
      playerCount: _session.players.length,
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

  /// روشن/خاموش کردن ورود بدون کد از شبکهٔ محلی.
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
      playerCount: _session.players.length,
    );
    unawaited(_beacon!.start());
    notifyListeners();
  }

  /// تغییر دسته‌های فعال در لابی.
  void setActiveCategories(List<int> ids) {
    if (!isHost) return;
    if (!_session.setActiveCategories(ids)) {
      _setError('تغییر دسته‌ها در این مرحله ممکن نیست.');
      return;
    }
    _broadcastState();
    _touch();
  }

  /// حذف بازیکن از لابی توسط میزبان.
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
    _broadcastState();
    _touch();
  }

  Future<HelloDecision> _handleHello(HelloRequest request) async {
    if (_sessionFinished) {
      return const HelloDecision.reject(
        'این نشست بازی به‌صورت resmi تمام شده است؛ ورود امکان‌پذیر نیست.',
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
      // اتصال مجدد بازیکن قبلی: پاسخ‌های قبلی حفظ می‌شوند.
      _session.setConnected(request.playerId, true);
      _session.renamePlayer(request.playerId, request.displayName);
      _broadcastState();
      _touch();
      return const HelloDecision.accept(resumed: true);
    }
    try {
      _session.addPlayer(request.displayName, id: request.playerId);
    } on GameRuleException catch (e) {
      return HelloDecision.reject(e.message);
    }
    AppLogger.instance.log('net', 'player joined');
    _beacon?.updatePlayerCount(_session.players.length);
    _broadcastState();
    _touch();
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
    // نسخهٔ ۱.۰.۰: میزبان نیز مستقلاً بررسی می‌کند که پاسخ‌های همان بازیکن
    // کامل باشد؛ درخواست قدیمی/تکراری یا ناقص بی‌اثر رد می‌شود.
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
    // نسخهٔ ۱.۰.۰: اگر حد نصاب استپ هنوز کامل نشده، دست ادامه دارد و نباید
    // پاسخ‌های هیچ دستگاهی (از جمله میزبان) قفل شود.
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
    final applied = _session.applySnapshot(
      playerId,
      answers,
      roundIndex: roundIndex,
    );
    if (applied) {
      _hostNet?.sendTo(playerId, MsgType.snapshotAck, {
        'r': roundIndex,
        'received': true,
      });
      AppLogger.instance.log('net', 'snapshot received');
    }
    _session.tryStartJudging();
    _broadcastState();
    _touch();
  }

  void _handlePlayerDisconnected(String playerId) {
    _session.setConnected(playerId, false);
    AppLogger.instance.log('net', 'player disconnected');
    _broadcastState();
    _touch();
  }

  /// تصمیم صریح میزبان دربارهٔ بازیکن قطع‌شده: پاسخ‌های دریافت‌شده حفظ می‌شوند
  /// و پاسخ‌های نرسیده خالی تلقی نمی‌شوند؛ داور خودش تصمیم می‌گیرد.
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

  // -------------------------------------------------------------- بازیکن

  /// جست‌وجوی میزبان‌های فعال در شبکهٔ محلی.
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

  /// پیوستن به بازی با آدرس و کد اتصال.
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
    _gameId = gameId;
    _joinToken = token;
    _hostName = hostName;
    _hostAddress = address;
    _hostPort = port;
    _role = GameRole.player;
    _netStatus = NetStatus.reconnecting;
    _clockOffsetMs = 0;
    _snapshotSent = false;
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
    if (!ok) return false;
    await _persistNow();
    notifyListeners();
    return true;
  }

  /// ساخت و اتصال کلاینت بازیکن (مشترک بین «پیوستن» و «ادامه بازی»).
  Future<bool> _attachClient({
    required String address,
    required int port,
    required String gameId,
    required String token,
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
    client.states.listen((state) {
      _clientState = state;
      _netStatus = switch (state) {
        ClientConnectionState.connected => NetStatus.connected,
        ClientConnectionState.reconnecting => NetStatus.reconnecting,
        ClientConnectionState.connecting => NetStatus.reconnecting,
        ClientConnectionState.rejected => NetStatus.disconnected,
        ClientConnectionState.disconnected => NetStatus.disconnected,
        ClientConnectionState.idle => NetStatus.offline,
      };
      if (state == ClientConnectionState.disconnected && isPlayer) {
        _scheduleSave();
      }
      // رد شدن صریح توسط میزبان یعنی نشست پایان یافته یا نامعتبر شده است؛
      // رکورد اتاق باید حذف شود تا «ادامه بازی» فریب‌دهنده نباشد.
      if (state == ClientConnectionState.rejected && isPlayer) {
        unawaited(_handleSessionEnded(
          'این جلسه پایان یافته یا نامعتبر است. اتاق از فهرست ادامه بازی حذف شد.',
        ));
      }
      notifyListeners();
    });
    client.messages.listen(_handleServerMessage);

    final ok = await client.connect();
    if (!ok) {
      _setError(client.lastError ?? 'اتصال به میزبان برقرار نشد.');
      _netStatus = NetStatus.disconnected;
      notifyListeners();
      return false;
    }
    _netStatus = NetStatus.connected;
    return true;
  }

  /// خروج از بازی (بازیکن).
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
        _snapshotSent = true;
        _setNotice('پاسخ‌های شما به میزبان رسید.');
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
      case MsgType.snapshot:
      case MsgType.ping:
        break;
      case MsgType.pong:
        break;
    }
  }

  /// اعمال وضعیت معتبر میزبان روی نسخهٔ محلی بازیکن.
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
        for (final raw in playersJson) {
          if (raw is! Map<String, dynamic>) continue;
          final id = raw['id'] as String?;
          final name = raw['name'] as String?;
          if (id == null || id.isEmpty || name == null) continue;
          incoming.add(Player(id: id, name: name, isHost: raw['h'] == true));
          if (raw['c'] == true) connected.add(id);
        }
        if (incoming.isNotEmpty) {
          _session.players
            ..clear()
            ..addAll(incoming);
          _session.connectedPlayerIds
            ..clear()
            ..addAll(connected);
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
        // وضعیت ارسال هر بازیکن.
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
        // پاسخ‌های من از میزبان (تا زمانی که در حال تایپ هستم، متن محلی حفظ می‌شود).
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
      // ذخیرهٔ پایدار وضعیت روی دستگاه بازیکن (بند ۷ سند ۱.۰.۰).
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
    _snapshotSent = false;
    _session.rounds.add(
      RoundRecord(
        index: roundIndex,
        startedAtEpochMs: nowMs(),
        endEpochMs: nowMs() + kRoundDurationMs,
      ),
    );
  }

  // ---------------------------------------------------------------- بازی

  /// شروع دست توسط میزبان (زمان‌سنج از همان لحظه آغاز می‌شود).
  ///
  /// نسخهٔ ۱.۰.۰: شروع دست به هیچ کلمه یا حرفی وابسته نیست.
  void startGame() {
    if (!isHost) return;
    if (!_session.canStartGame) {
      _setError('برای شروع بازی حداقل دو بازیکن لازم است.');
      return;
    }
    try {
      _session.startNewRound(nowMs: syncedNowMs());
    } on GameRuleException catch (e) {
      _setError(e.message);
      return;
    }
    _snapshotSent = false;
    _broadcastState();
    _syncTicker();
    _syncScreenAwake();
    _touch();
  }

  /// شروع دست بعدی (حرف تصادفی جدید، حفظ امتیازها).
  void startNextRound() {
    if (!isHost) return;
    try {
      _session.startNewRound(nowMs: syncedNowMs());
    } on GameRuleException catch (e) {
      _setError(e.message);
      return;
    }
    _snapshotSent = false;
    _broadcastState();
    _syncTicker();
    _syncScreenAwake();
    _touch();
  }

  /// ثبت پاسخ (میزبان: مستقیم، بازیکن: ارسال به میزبان + به‌روزرسانی محلی).
  void setAnswer(int categoryId, String text) {
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
    // بازیکن: ابتدا نمایش محلی (بدون تأخیر) و سپس ارسال به میزبان.
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

  /// فشردن دکمهٔ «استپ».
  ///
  /// نسخهٔ ۱.۰.۰: پیش از هر کاری، کامل بودن پاسخ‌های همین بازیکن بررسی
  /// می‌شود؛ اگر حتی یک فیلد کمتر از دو کاراکتر معتبر داشته باشد، عملیات
  /// رد می‌شود (حتی با لمس مکرر دکمه یا رویداد قدیمی/تکراری).
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
      // تا رسیدن به حد نصاب استپ، دست ادامه دارد و پاسخ‌ها قفل نمی‌شوند.
      if (_session.phase == GamePhase.collecting) {
        _afterRoundEnded();
      } else {
        _broadcastState();
      }
      _touch();
      return;
    }
    // بازیکن: ابتدا آخرین پاسخ‌ها روی کانال (ترتیب‌دار) فرستاده می‌شود تا
    // میزبان پیش از پردازش استپ، پاسخ‌های کامل همین بازیکن را داشته باشد.
    for (final category in activeCategories) {
      _client?.sendAnswer(round.index, category.id, myAnswer(category.id));
    }
    _client?.sendStop(round.index);
    _setNotice('درخواست استپ برای میزبان ارسال شد.');
  }

  /// توقف/ادامهٔ زمان‌سنج (فقط میزبان).
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

  /// پایان دستی دست توسط میزبان.
  void forceEndRound() {
    if (!isHost) return;
    if (_session.endRound(RoundEndReason.referee, nowMs: syncedNowMs())) {
      _afterRoundEnded();
      _touch();
    }
  }

  /// پس از پایان دست: پاسخ‌های خود را به میزبان می‌فرستیم و منتظر بقیه می‌مانیم.
  void _afterRoundEnded() {
    final round = _session.currentRound;
    if (round == null) return;
    if (isHost) {
      _session.applySnapshot(
        myPlayerId,
        _ownAnswers(_session),
        roundIndex: round.index,
      );
      _snapshotSent = true;
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

  void _maybeSendSnapshot() {
    if (isHost) return;
    final round = _session.currentRound;
    if (round == null) return;
    if (_snapshotSent) return;
    if (_client == null || !_client!.isConnected) return;
    final ok = _client!.sendSnapshot(round.index, _ownAnswers(_session));
    if (ok) _snapshotSent = true;
  }

  // ---------------------------------------------------------------- داوری

  void setJudgement(String playerId, int categoryId, JudgementStatus? status) {
    if (!isHost) return;
    _session.setJudgement(playerId, categoryId, status);
    _touch(save: false);
  }

  /// ثبت نهایی داوری و اعلام نتایج به همهٔ دستگاه‌ها.
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

  /// پایان رسمی بازی توسط میزبان (بند ۵ سند ۱.۰.۰).
  ///
  /// - پایان جلسه برای همهٔ دستگاه‌ها ارسال می‌شود؛ بازیکنان آنلاین بی‌درنگ به
  ///   صفحهٔ اصلی می‌روند و وضعیت پایان برای بازیکنان آفلاین ذخیره می‌شود.
  /// - وضعیت اتاق «پایان‌یافته» می‌شود، اتصال و QR نامعتبر و «ادامه بازی» حذف
  ///   می‌شود و بازیکنان نمی‌توانند به جلسهٔ پایان‌یافته برگردند.
  Future<void> finishGame() async {
    if (!isHost) return;
    final gameId = _gameId;
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

  /// اعلام پایان جلسه به همهٔ بازیکنان و علامت‌گذاری اتاق‌های همان نشست.
  Future<void> _broadcastSessionEnded(String reason) async {
    _hostNet?.broadcast(MsgType.sessionEnded, {
      'reason': reason,
      'gameId': _gameId,
    });
    // فرصت کوتاه برای رسیدن پیام پیش از بستن سوکت‌ها.
    await Future<void>.delayed(const Duration(milliseconds: 120));
  }

  /// حذف همهٔ رکوردهای اتاق مربوط به یک نشست (پایان رسمی یا خروج از اتاق).
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

  /// پایان جلسه روی دستگاه بازیکن (پس از اعلام رسمی میزبان).
  Future<void> _handleSessionEnded(String reason) async {
    final gameId = _gameId;
    await _detachAll();
    await _removeRoomsOfGame(gameId);
    _sessionFinished = true;
    _lastNotice = reason;
    _syncTicker();
    _syncScreenAwake();
    notifyListeners();
  }

  /// بازگشت به صفحهٔ اصلی بدون خروج از اتاق (بند ۵ سند ۱.۰.۰).
  ///
  /// جلسه پایان نمی‌یابد، اطلاعات اتاق حفظ می‌شود، ارتباط بازیکنان دیگر قطع
  /// نمی‌شود (میزبان سرور را بالا نگه می‌دارد) و کاربر می‌تواند با «ادامه بازی»
  /// برگردد.
  Future<void> backToHome() async {
    await _persistNow();
    notifyListeners();
  }

  /// خروج صریح از اتاق (متفاوت از بازگشت به صفحهٔ اصلی) — با تأیید کاربر.
  ///
  /// رکورد اتاق از این دستگاه حذف می‌شود تا دیگر «ادامه بازی» نداشته باشد.
  /// اگر میزبان باشد، جلسه برای همه پایان می‌یابد (چون میزبان مرجع است).
  Future<void> leaveRoom([RoomRecord? room]) async {
    final target = room;
    if (target != null) {
      await roomStore.remove(target.gameId, target.myPlayerId);
      if (target.gameId == _gameId && target.myPlayerId == myPlayerId) {
        await _detachAll();
        await store.clear();
      }
      await _reloadRooms();
      notifyListeners();
      return;
    }
    final gameId = _gameId;
    if (isHost) {
      await _broadcastSessionEnded('میزبان از اتاق خارج شد؛ بازی پایان یافت.');
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

  /// قطع همهٔ ارتباط‌ها و بازگشت به حالت بی‌نقش، بدون پاک‌کردن رکورد اتاق.
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
    _snapshotSent = false;
    _clockOffsetMs = 0;
    _session = GameSession.fresh(nowMs: nowMs());
  }

  /// خروج از بازی (سازگاری با کد نسخه‌های قبل): ارتباط‌ها بسته می‌شوند اما
  /// رکورد اتاق حفظ می‌شود تا «ادامه بازی» ممکن باشد.
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

  // ------------------------------------------------------- اتاق‌های ذخیره‌شده

  /// اتاق‌های قابل نمایش روی این دستگاه (جدیدترین اول).
  List<RoomRecord> get savedRooms {
    final list = _rooms.where((r) => !r.ended).toList(growable: false);
    final sorted = List<RoomRecord>.from(list)
      ..sort((a, b) => b.updatedAtEpochMs.compareTo(a.updatedAtEpochMs));
    return List<RoomRecord>.unmodifiable(sorted);
  }

  /// آیا اتاق قابل ادامه‌ای وجود دارد؟
  bool get hasResumableRoom => savedRooms.any((r) => r.resumable);

  /// اتاق جاری این دستگاه (اگر نقشی فعال باشد).
  RoomRecord? get activeRoom {
    if (_gameId.isEmpty || _role == GameRole.none) return null;
    for (final room in _rooms) {
      if (room.gameId == _gameId && room.myPlayerId == myPlayerId) return room;
    }
    return null;
  }

  /// بارگذاری دوبارهٔ فهرست اتاق‌ها از حافظهٔ پایدار (برای رابط کاربری و آزمون).
  Future<void> reloadSavedRooms() async {
    await _reloadRooms();
    notifyListeners();
  }

  Future<void> _reloadRooms() async {
    _rooms = await roomStore.loadAll();
    foundSavedGame = _rooms.any((r) => r.resumable);
  }

  /// ساخت رکورد اتاق از وضعیت فعلی.
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

  /// بازیابی اتاق ذخیره‌شده («ادامه بازی») برای میزبان یا بازیکن.
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
    _snapshotSent = false;
    _clockOffsetMs = 0;

    // بازیابی زمان‌سنج از زمان باقی‌ماندهٔ ذخیره‌شده.
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
    // بازیکنان پس از بازیابی، ابتدا «قطع‌شده» هستند تا دوباره وصل شوند.
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
    _snapshotSent = false;
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
    );
    if (!ok) {
      // اتاق در دسترس نیست: رکورد حفظ می‌شود تا بعداً دوباره تلاش شود.
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

  /// ساخت payload QR Code برای اتصال به میزبان (بند ۱).
  ///
  /// شامل: شناسهٔ نشست، آدرس میزبان، پورت، توکن اتصال، نام میزبان،
  /// زمان ساخت و وقت انقضاء (QR بعد از پایان جلسه نامعتبر می‌شود).
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

  /// اعتبارسنجی دادهٔ اسکن‌شده از QR.
  ///
  /// نسخهٔ ۱.۰.۰: اعتبارسنجی «ساختاری» است و به نشست محلی این دستگاه وابسته
  /// نیست؛ پیش از این، مقایسه با شناسهٔ نشست محلی باعث می‌شد اسکن QR روی
  /// دستگاه بازیکن (که هنوز نشستی ندارد) همیشه رد شود.
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

  /// دور ریختن همهٔ بازی‌های ذخیره‌شده روی این دستگاه.
  Future<void> discardSavedGame() async {
    await closeSession(silent: true);
    await store.clear();
    await roomStore.clear();
    await _reloadRooms();
    _role = GameRole.none;
    _session = GameSession.fresh(nowMs: nowMs());
    notifyListeners();
  }

  // -------------------------------------------------------------- داخلی

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
      _beacon?.updatePlayerCount(_session.players.length);
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
            // زمان تمام شده؛ منتظر اعلام میزبان می‌مانیم (بدون تغییر وضعیت).
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

  void _scheduleSave() {
    if (_saveScheduled) return;
    _saveScheduled = true;
    scheduleMicrotask(() async {
      _saveScheduled = false;
      await _persistNow();
    });
  }

  Future<void> _persistNow() async {
    if (_role == GameRole.none) return;
    if (isHost) {
      final ok = await store.save(_session, nowMs: nowMs());
      if (!ok) {
        _lastError = 'ذخیرهٔ اطلاعات بازی انجام نشد.';
      }
    }
    final record = _roomRecordFromState();
    if (record == null) return;
    final ok = await roomStore.upsert(record);
    if (!ok && _lastError == null) {
      _lastError = 'ذخیرهٔ اطلاعات اتاق انجام نشد.';
    }
    await _reloadRooms();
  }
}
