/// رکورد «اتاق ذخیره‌شده» روی دستگاه هر بازیکن — نسخهٔ ۱.۰.۰.
///
/// هر دستگاه (میزبان یا بازیکن) برای هر اتاقی که به آن ملحق شده است یک رکورد
/// پایدار نگه می‌دارد تا پس از بازگشت به صفحه اصلی، بستن برنامه، خاموش شدن گوشی
/// یا قطع شبکه بتواند با گزینهٔ «ادامه بازی» به همان اتاق برگردد.
library;

import 'models.dart';

/// وضعیت آخرین اتصال به اتاق.
enum RoomLinkStatus {
  /// آخرین بار متصل بود.
  online,

  /// آخرین بار قطع بود.
  offline,

  /// اتصال در حال برقراری بود.
  connecting,
}

/// یک اتاق ذخیره‌شده روی این دستگاه.
class RoomRecord {
  RoomRecord({
    required this.gameId,
    required this.roomName,
    required this.hostPlayerId,
    required this.hostName,
    required this.myPlayerId,
    required this.myName,
    required this.role,
    required this.address,
    required this.port,
    required this.token,
    required this.phase,
    required this.roundIndex,
    required this.updatedAtEpochMs,
    this.remainingMs = 0,
    this.ended = false,
    this.linkStatus = RoomLinkStatus.offline,
    Map<int, String>? myAnswers,
    this.stopped = false,
    this.sessionSnapshot,
  }) : myAnswers = myAnswers ?? <int, String>{};

  /// شناسهٔ یکتای اتاق (همان شناسهٔ نشست میزبان).
  final String gameId;

  /// نام اتاق (نام بازی/میزبان).
  final String roomName;

  final String hostPlayerId;
  final String hostName;

  /// شناسهٔ پایدار همین دستگاه در نقش عضو اتاق.
  final String myPlayerId;
  final String myName;

  /// نقش این دستگاه در اتاق.
  final GameRole role;

  /// آدرس میزبان برای اتصال دوباره (روی دستگاه میزبان خالی است).
  final String address;
  final int port;
  final String token;

  /// وضعیت جلسه در آخرین ذخیره‌سازی.
  final GamePhase phase;

  /// شمارهٔ دست جاری.
  final int roundIndex;

  /// زمان آخرین فعالیت (برای مرتب‌سازی فهرست اتاق‌ها).
  final int updatedAtEpochMs;

  /// زمان باقی‌ماندهٔ دست در لحظهٔ ذخیره‌سازی (میلی‌ثانیه) — بازیابی زمان‌سنج.
  final int remainingMs;

  /// جلسه به‌صورت رسمی پایان یافته است (قابل ادامه نیست).
  final bool ended;

  final RoomLinkStatus linkStatus;

  /// پاسخ‌های ثبت‌شدهٔ این بازیکن در دست جاری.
  final Map<int, String> myAnswers;

  /// آیا این بازیکن استپ کرده است.
  final bool stopped;

  /// آخرین وضعیت معتبر بازی (JSON کامل نشست) برای بازیابی فوری رابط کاربری.
  final Map<String, dynamic>? sessionSnapshot;

  bool get isHost => role == GameRole.host;

  /// قابل ادامه است؟ لابی هم تا وقتی رسماً تمام نشده قابل بازیابی است.
  bool get resumable => !ended && phase != GamePhase.finished;

  /// کلید یکتای رکورد؛ برای هر بازیکن در هر اتاق فقط یک رکورد وجود دارد.
  String get key => '$gameId|$myPlayerId';

  RoomRecord copyWith({
    String? roomName,
    String? hostName,
    String? address,
    int? port,
    String? token,
    GamePhase? phase,
    int? roundIndex,
    int? updatedAtEpochMs,
    int? remainingMs,
    bool? ended,
    RoomLinkStatus? linkStatus,
    Map<int, String>? myAnswers,
    bool? stopped,
    Map<String, dynamic>? sessionSnapshot,
    bool clearSnapshot = false,
  }) => RoomRecord(
    gameId: gameId,
    roomName: roomName ?? this.roomName,
    hostPlayerId: hostPlayerId,
    hostName: hostName ?? this.hostName,
    myPlayerId: myPlayerId,
    myName: myName,
    role: role,
    address: address ?? this.address,
    port: port ?? this.port,
    token: token ?? this.token,
    phase: phase ?? this.phase,
    roundIndex: roundIndex ?? this.roundIndex,
    updatedAtEpochMs: updatedAtEpochMs ?? this.updatedAtEpochMs,
    remainingMs: remainingMs ?? this.remainingMs,
    ended: ended ?? this.ended,
    linkStatus: linkStatus ?? this.linkStatus,
    myAnswers: myAnswers ?? this.myAnswers,
    stopped: stopped ?? this.stopped,
    sessionSnapshot: clearSnapshot
        ? null
        : (sessionSnapshot ?? this.sessionSnapshot),
  );

  Map<String, dynamic> toJson() => {
    'gid': gameId,
    'room': roomName,
    'hid': hostPlayerId,
    'hn': hostName,
    'pid': myPlayerId,
    'pn': myName,
    'role': role.name,
    'addr': address,
    'port': port,
    'token': token,
    'phase': phase.name,
    'round': roundIndex,
    'at': updatedAtEpochMs,
    'rem': remainingMs,
    'ended': ended,
    'link': linkStatus.name,
    'ans': myAnswers.map((k, v) => MapEntry(k.toString(), v)),
    'stopped': stopped,
    'snap': sessionSnapshot,
  };

  static RoomRecord fromJson(Map<String, dynamic> json) => RoomRecord(
    gameId: json['gid'] as String? ?? '',
    roomName: json['room'] as String? ?? '',
    hostPlayerId: json['hid'] as String? ?? '',
    hostName: json['hn'] as String? ?? '',
    myPlayerId: json['pid'] as String? ?? '',
    myName: json['pn'] as String? ?? '',
    role: GameRole.values.firstWhere(
      (r) => r.name == json['role'],
      orElse: () => GameRole.player,
    ),
    address: json['addr'] as String? ?? '',
    port: (json['port'] as num?)?.toInt() ?? 0,
    token: json['token'] as String? ?? '',
    phase: GamePhase.values.firstWhere(
      (p) => p.name == json['phase'],
      orElse: () => GamePhase.lobby,
    ),
    roundIndex: (json['round'] as num?)?.toInt() ?? 0,
    updatedAtEpochMs: (json['at'] as num?)?.toInt() ?? 0,
    remainingMs: (json['rem'] as num?)?.toInt() ?? 0,
    ended: json['ended'] == true,
    linkStatus: RoomLinkStatus.values.firstWhere(
      (s) => s.name == json['link'],
      orElse: () => RoomLinkStatus.offline,
    ),
    myAnswers: (json['ans'] as Map<String, dynamic>? ?? const {}).map(
      (k, v) => MapEntry(int.tryParse(k) ?? -1, v as String),
    )..remove(-1),
    stopped: json['stopped'] == true,
    sessionSnapshot: json['snap'] as Map<String, dynamic>?,
  );
}
