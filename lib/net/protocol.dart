/// پروتکل پیام‌های شبکهٔ محلی «سنجاب» (نسخهٔ ۲).
///
/// همهٔ پیام‌ها JSON تک‌خطی با ساختار یکسان هستند:
/// `{"v":2,"t":"type","id":"msg-id","q":12,"p":{...}}`
///  - `v` نسخهٔ پروتکل (پیام با نسخهٔ ناسازگار رد می‌شود)
///  - `t` نوع پیام
///  - `id` شناسهٔ یکتای پیام (برای جلوگیری از پردازش دوباره)
///  - `q` شمارهٔ ترتیب (Sequence) برای کنترل ترتیب پیام‌های یک فرستنده
///  - `p` محتوای پیام
library;

import 'dart:convert';
import 'dart:math';

import '../domain/models.dart' show kProtocolVersion;

/// نوع پیام‌های پروتکل.
enum MsgType {
  /// بازیکن: درخواست ورود به نشست.
  hello,

  /// میزبان: پذیرش ورود.
  helloAck,

  /// میزبان: رد ورود.
  helloReject,

  /// میزبان: وضعیت کامل و معتبر بازی.
  state,

  /// بازیکن: تغییر پاسخ یک دسته.
  answer,

  /// بازیکن: درخواست استپ (پایان دست).
  stop,

  /// بازیکن: ارسال Snapshot نهایی پاسخ‌ها.
  snapshot,

  /// میزبان: تأیید دریافت Snapshot یک بازیکن.
  snapshotAck,

  /// میزبان: پایان داوری و اعلام نتایج.
  results,

  /// میزبان: پایان رسمی جلسه؛ همهٔ بازیکنان باید به صفحهٔ اصلی برگردند و
  /// نشست برای همیشه نامعتبر می‌شود (نسخهٔ ۱.۰.۰).
  sessionEnded,

  /// هر دو طرف: بررسی زنده‌بودن اتصال.
  ping,

  /// هر دو طرف: پاسخ بررسی زنده‌بودن.
  pong,

  /// خطای پروتکل یا رد درخواست.
  error,
}

/// خطای پروتکل (پیام نامعتبر، نسخهٔ ناسازگار و …).
class ProtocolException implements Exception {
  ProtocolException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// یک پیام شبکه.
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

  /// تبدیل پیام به یک خط JSON (بدون نویسهٔ خط جدید در متن).
  String encode() => '${jsonEncode(toJson())}\n';

  /// ساخت پیام از نقشهٔ JSON با اعتبارسنجی کامل.
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
    if (line.length > kMaxMessageBytes) {
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

/// حداکثر اندازهٔ یک پیام (بایت). از پیام‌های بزرگ و مخرب جلوگیری می‌کند.
const int kMaxMessageBytes = 256 * 1024;

/// ساخت شناسهٔ یکتای پیام.
String newMessageId([Random? random]) {
  final rnd = random ?? Random();
  final buffer = StringBuffer();
  for (var i = 0; i < 16; i++) {
    buffer.write(rnd.nextInt(16).toRadixString(16));
  }
  return buffer.toString();
}

/// کنترل تکرار پیام‌ها.
///
/// پیام‌های تکراری (بر اساس شناسه) نادیده گرفته می‌شوند؛ در نتیجه ارسال دوبارهٔ
/// یک پاسخ یا Snapshot باعث ثبت چندبارهٔ آن نمی‌شود.
class MessageDeduper {
  MessageDeduper({this.capacity = 512});

  final int capacity;
  final Set<String> _seen = <String>{};
  final List<String> _order = <String>[];

  /// اگر پیام تازه باشد true برمی‌گرداند و آن را ثبت می‌کند.
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

/// کنترل ترتیب پیام‌های یک فرستنده بر اساس شمارهٔ ترتیب.
class SequenceGuard {
  int _lastSeq = -1;

  /// اگر پیام جدیدتر از آخرین پیام پذیرفته‌شده باشد true برمی‌گرداند.
  bool accept(int seq) {
    if (seq <= _lastSeq) return false;
    _lastSeq = seq;
    return true;
  }

  int get lastSeq => _lastSeq;

  void reset() => _lastSeq = -1;
}
