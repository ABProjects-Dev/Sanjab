/// ذخیره‌سازی محلی پروفایل (شناسهٔ پایدار بازیکن + نام نمایشی).
library;

import 'dart:convert';
import 'dart:io';

import '../core/app_logger.dart';
import '../domain/profile.dart';

/// قرارداد ذخیره‌سازی پروفایل (برای آزمون‌پذیری و جای‌گزینی).
abstract class ProfileStore {
  Future<Profile> load();
  Future<bool> save(Profile profile);
}

/// مخزن پروفایل روی فایل محلی دستگاه.
class ProfileRepository implements ProfileStore {
  ProfileRepository(this.directory);

  final Directory directory;

  File get _file => File('${directory.path}/profile.json');
  File get _temp => File('${directory.path}/profile.json.tmp');

  /// بارگذاری پروفایل؛ در نبود یا خرابی فایل، پروفایل تازه ساخته می‌شود.
  @override
  Future<Profile> load() async {
    try {
      if (!await _file.exists()) {
        return Profile(playerId: generatePlayerId(), displayName: '');
      }
      final raw = await _file.readAsString();
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) {
        return Profile(playerId: generatePlayerId(), displayName: '');
      }
      final profile = Profile.fromJson(json);
      if (profile.playerId.isEmpty) {
        return profile.copyWith(playerId: generatePlayerId());
      }
      return profile;
    } catch (error, stack) {
      AppLogger.instance.error('profile.load', error, stack);
      return Profile(playerId: generatePlayerId(), displayName: '');
    }
  }

  /// ذخیرهٔ اتمیک پروفایل.
  @override
  Future<bool> save(Profile profile) async {
    try {
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      await _temp.writeAsString(jsonEncode(profile.toJson()), flush: true);
      await _temp.rename(_file.path);
      return true;
    } catch (error, stack) {
      AppLogger.instance.error('profile.save', error, stack);
      return false;
    }
  }
}
