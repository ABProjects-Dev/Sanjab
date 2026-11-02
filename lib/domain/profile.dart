/// پروفایل محلی دستگاه (بند ۷ سند نسخه ۱.۰.۰).
///
/// هر دستگاه یک شناسهٔ بازیکن پایدار و یک نام نمایشی دارد. شناسه مستقل از
/// نام است تا تغییر نام، هویت بازیکن در نشست فعال را عوض نکند.
library;

import 'dart:math';

/// پروفایل کاربر روی این دستگاه.
class Profile {
  const Profile({required this.playerId, required this.displayName});

  /// شناسهٔ داخلی پایدار بازیکن (هرگز نمایش داده نمی‌شود).
  final String playerId;

  /// نام نمایشی که به بقیهٔ بازیکنان نشان داده می‌شود.
  final String displayName;

  /// پروفایل پیش‌فرض پیش از اولین تنظیم نام.
  static const Profile empty = Profile(playerId: '', displayName: '');

  bool get isConfigured => playerId.isNotEmpty && displayName.trim().isNotEmpty;

  Profile copyWith({String? playerId, String? displayName}) => Profile(
    playerId: playerId ?? this.playerId,
    displayName: displayName ?? this.displayName,
  );

  Map<String, dynamic> toJson() => {'id': playerId, 'name': displayName};

  static Profile fromJson(Map<String, dynamic> json) => Profile(
    playerId: json['id'] as String? ?? '',
    displayName: json['name'] as String? ?? '',
  );
}

/// طول مجاز نام نمایشی.
const int kMinDisplayNameLength = 1;
const int kMaxDisplayNameLength = 24;

/// اعتبارسنجی نام نمایشی؛ در صورت نامعتبر بودن پیام فارسی برمی‌گرداند.
String? validateDisplayName(String value) {
  final clean = value.trim();
  if (clean.isEmpty) return 'نام نمایشی نمی‌تواند خالی باشد.';
  if (clean.length < kMinDisplayNameLength) {
    return 'نام نمایشی حداقل یک نویسه لازم دارد.';
  }
  if (clean.length > kMaxDisplayNameLength) {
    return 'نام نمایشی حداکثر ۲۴ نویسه می‌تواند باشد.';
  }
  return null;
}

/// ساخت شناسهٔ یکتای بازیکن (بدون وابستگی به بستهٔ بیرونی).
String generatePlayerId([Random? random]) {
  final rnd = random ?? Random.secure();
  const alphabet = '0123456789abcdefghijklmnopqrstuvwxyz';
  final buffer = StringBuffer('u');
  for (var i = 0; i < 12; i++) {
    buffer.write(alphabet[rnd.nextInt(alphabet.length)]);
  }
  return buffer.toString();
}

/// ساخت شناسهٔ نشست بازی.
String generateGameId([Random? random]) {
  final rnd = random ?? Random.secure();
  const alphabet = '0123456789abcdef';
  final buffer = StringBuffer();
  for (var i = 0; i < 16; i++) {
    buffer.write(alphabet[rnd.nextInt(alphabet.length)]);
  }
  return buffer.toString();
}

/// ساخت توکن اتصال (کلید ورود به نشست) — ۶ نویسهٔ خوانا.
String generateJoinToken([Random? random]) {
  final rnd = random ?? Random.secure();
  const alphabet = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
  final buffer = StringBuffer();
  for (var i = 0; i < 6; i++) {
    buffer.write(alphabet[rnd.nextInt(alphabet.length)]);
  }
  return buffer.toString();
}
