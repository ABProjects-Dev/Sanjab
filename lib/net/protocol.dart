/// Sanjab local-network message protocol (version 4).
///
/// Every message is single-line JSON with the same envelope:
/// `{"v":4,"t":"type","id":"msg-id","q":12,"p":{...}}`
///  - `v` protocol version; a mismatched version is rejected
///  - `t` message type
///  - `id` unique message ID, used to drop duplicate deliveries
///  - `q` per-sender sequence number used for ordering
///  - `p` message payload
library;

import 'dart:convert';
import 'dart:math';

import '../domain/models.dart' show kProtocolVersion;

/// Protocol message types.
enum MsgType {
  /// Player: request to join the session.
  hello,

  /// Host: join accepted.
  helloAck,

  /// Host: join rejected.
  helloReject,

  /// Host: complete authoritative state.
  state,

  /// Player: answer text changed for a category.
  answer,

  /// Player: Stop request (end the round).
  stop,

  /// Player: explicit exit, distinct from a transient disconnect.
  leave,

  /// Player: final answer snapshot.
  snapshot,

  /// Host: acknowledgement of a player's snapshot.
  snapshotAck,

  /// Host: judging finished, results announced.
  results,

  /// Host: the session ended formally; players return Home and the session
  /// becomes permanently invalid.
  sessionEnded,

  /// Either side: liveness check.
  ping,

  /// Either side: liveness reply.
  pong,

  /// Protocol error or rejected request.
  error,
}

/// Protocol error: invalid message, incompatible version, and so on.
class ProtocolException implements Exception {
  ProtocolException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// One network message.
class NetMessage {
  NetMessage({
    required this.type,
    required this.id,
    required this.seq,
    this.payload = const <String, dynamic>{},
  });

  final MsgType type;
  final String id;
  final int seq;
  final Map<String, dynamic> payload;

  Map<String, dynamic> toJson() => {
    'v': kProtocolVersion,
    't': type.name,
    'id': id,
    'q': seq,
    'p': payload,
  };

  /// Encode to one JSON line (no embedded newline).
  String encode() => '${jsonEncode(toJson())}\n';

  /// Build a message from a JSON map with full validation.
  static NetMessage fromJson(Map<String, dynamic> json) {
    final version = json['v'];
    if (version is! int) {
      throw ProtocolException('پیام نامعتبر: نسخهٔ پروتکل مشخص نیست.');
    }
    if (version != kProtocolVersion) {
      throw ProtocolException(
        'نسخهٔ برنامهٔ دستگاه مقابل سازگار نیست (نسخهٔ $version).',
      );
    }
    final rawType = json['t'];
    if (rawType is! String) {
      throw ProtocolException('پیام نامعتبر: نوع پیام مشخص نیست.');
    }
    MsgType? type;
    for (final t in MsgType.values) {
      if (t.name == rawType) {
        type = t;
        break;
      }
    }
    if (type == null) {
      throw ProtocolException('پیام نامعتبر: نوع «$rawType» شناخته نمی‌شود.');
    }
    final id = json['id'];
    if (id is! String || id.isEmpty || id.length > 64) {
      throw ProtocolException('پیام نامعتبر: شناسهٔ پیام معتبر نیست.');
    }
    final seq = json['q'];
    if (seq is! int || seq < 0) {
      throw ProtocolException('پیام نامعتبر: شمارهٔ ترتیب معتبر نیست.');
    }
    final payload = json['p'];
    if (payload != null && payload is! Map<String, dynamic>) {
      throw ProtocolException('پیام نامعتبر: محتوای پیام معتبر نیست.');
    }
    return NetMessage(
      type: type,
      id: id,
      seq: seq,
      payload: (payload as Map<String, dynamic>?) ?? const <String, dynamic>{},
    );
  }

  static NetMessage parse(String line) {
    if (line.length > kMaxMessageBytes ||
        utf8.encode(line).length > kMaxMessageBytes) {
      throw ProtocolException('پیام نامعتبر: اندازهٔ پیام بیش از حد مجاز است.');
    }
    Object? decoded;
    try {
      decoded = jsonDecode(line);
    } on FormatException {
      throw ProtocolException('پیام نامعتبر: ساختار JSON خراب است.');
    }
    if (decoded is! Map<String, dynamic>) {
      throw ProtocolException('پیام نامعتبر: ساختار پیام معتبر نیست.');
    }
    return fromJson(decoded);
  }
}

/// Maximum message size in bytes, to bound hostile or oversized frames.
const int kMaxMessageBytes = 256 * 1024;

/// Generate a unique message ID.
String newMessageId([Random? random]) {
  final rnd = random ?? Random();
  final buffer = StringBuffer();
  for (var i = 0; i < 16; i++) {
    buffer.write(rnd.nextInt(16).toRadixString(16));
  }
  return buffer.toString();
}

/// Duplicate-message guard.
///
/// Messages with a known ID are ignored, so a retransmitted answer or snapshot
/// is not applied twice.
class MessageDeduper {
  MessageDeduper({this.capacity = 512});

  final int capacity;
  final Set<String> _seen = <String>{};
  final List<String> _order = <String>[];

  /// Returns true and records the ID when the message is new.
  bool accept(String id) {
    if (!_seen.add(id)) return false;
    _order.add(id);
    if (_order.length > capacity) {
      final oldest = _order.removeAt(0);
      _seen.remove(oldest);
    }
    return true;
  }

  int get length => _seen.length;

  void clear() {
    _seen.clear();
    _order.clear();
  }
}

/// Per-sender message ordering by sequence number.
class SequenceGuard {
  int _lastSeq = -1;

  /// Returns true when the message is newer than the last accepted one.
  bool accept(int seq) {
    if (seq <= _lastSeq) return false;
    _lastSeq = seq;
    return true;
  }

  int get lastSeq => _lastSeq;

  void reset() => _lastSeq = -1;
}
