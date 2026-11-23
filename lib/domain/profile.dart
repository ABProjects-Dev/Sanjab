/// Device-local profile.
///
/// Each device has a stable player ID and a display name. The ID is separate
/// from the name, so renaming never changes identity in an active session.
library;

import 'dart:math';

/// The user profile on this device.
class Profile {
  const Profile({required this.playerId, required this.displayName});

  /// Stable internal player ID, never shown to other players.
  final String playerId;

  /// Display name shown to the other players.
  final String displayName;

  /// Default profile before a name is set.
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

/// Allowed display-name length.
const int kMinDisplayNameLength = 1;
const int kMaxDisplayNameLength = 24;

/// Validate a display name; returns a Persian message when invalid.
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

/// Generate a unique player ID without an external package.
String generatePlayerId([Random? random]) {
  final rnd = random ?? Random.secure();
  const alphabet = '0123456789abcdefghijklmnopqrstuvwxyz';
  final buffer = StringBuffer('u');
  for (var i = 0; i < 12; i++) {
    buffer.write(alphabet[rnd.nextInt(alphabet.length)]);
  }
  return buffer.toString();
}

/// Generate a session (game) ID.
String generateGameId([Random? random]) {
  final rnd = random ?? Random.secure();
  const alphabet = '0123456789abcdef';
  final buffer = StringBuffer();
  for (var i = 0; i < 16; i++) {
    buffer.write(alphabet[rnd.nextInt(alphabet.length)]);
  }
  return buffer.toString();
}

/// Generate the join token: six readable characters.
String generateJoinToken([Random? random]) {
  final rnd = random ?? Random.secure();
  const alphabet = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
  final buffer = StringBuffer();
  for (var i = 0; i < 6; i++) {
    buffer.write(alphabet[rnd.nextInt(alphabet.length)]);
  }
  return buffer.toString();
}
