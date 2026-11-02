/// مخزن پروفایل حافظه‌ای برای آزمون‌ها (بدون I/O فایل).
library;

import 'package:sanjab/data/profile_repository.dart';
import 'package:sanjab/domain/profile.dart';

class MemoryProfileStore implements ProfileStore {
  MemoryProfileStore({Profile? initial})
    : profile =
          initial ??
          const Profile(playerId: 'test-player', displayName: 'بازیکن آزمون');

  Profile profile;
  int saveCount = 0;

  @override
  Future<Profile> load() async => profile;

  @override
  Future<bool> save(Profile value) async {
    profile = value;
    saveCount += 1;
    return true;
  }
}
