/// A saved-room record on a device, for either role.
///
/// Every device keeps one durable record per room it joined, so Home, an app
/// restart, a device restart or a network drop can still resume the same room
/// through the resume action.
library;

import 'models.dart';

/// Last known link state of the room.
enum RoomLinkStatus {
  /// Last attempt was connected.
  online,

  /// Last attempt was disconnected.
  offline,

  /// Connection was being established.
  connecting,
}

/// One saved room on this device.
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

  /// Unique room ID (the host session ID).
  final String gameId;

  /// Room name (the host's game name).
  final String roomName;

  final String hostPlayerId;
  final String hostName;

  /// Stable ID of this device's membership in the room.
  final String myPlayerId;
  final String myName;

  /// This device's role in the room.
  final GameRole role;

  /// Host address for reconnecting; empty on the host device.
  final String address;
  final int port;
  final String token;

  /// Session phase at the last save.
  final GamePhase phase;

  /// Current round index.
  final int roundIndex;

  /// Last activity time, used to sort the room list.
  final int updatedAtEpochMs;

  /// Remaining round time at save (milliseconds), used to restore the timer.
  final int remainingMs;

  /// The session ended formally and cannot be resumed.
  final bool ended;

  final RoomLinkStatus linkStatus;

  /// This player's answers in the current round.
  final Map<int, String> myAnswers;

  /// Whether this player pressed Stop.
  final bool stopped;

  /// Last authoritative session JSON, used to restore the UI immediately.
  final Map<String, dynamic>? sessionSnapshot;

  bool get isHost => role == GameRole.host;

  /// Whether the room can be resumed; a lobby counts until it ends formally.
  bool get resumable => !ended && phase != GamePhase.finished;

  /// Unique record key: one record per player per room.
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
