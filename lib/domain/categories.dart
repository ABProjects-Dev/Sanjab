/// فهرست دسته‌های بازی — برگرفته از نسخهٔ Kotlin (شناسه‌ها برای همیشه پایدارند).
library;

/// یک دستهٔ بازی.
class GameCategory {
  const GameCategory(this.id, this.title);

  final int id;
  final String title;
}

/// تنها منبع حقیقت برای همهٔ ۱۳ دستهٔ بازی.
/// شناسه‌ها هرگز تغییر نمی‌کنند: ۰..۹ = ده دستهٔ اصلی («اشیاء» = ۹)
/// و ۱۰ = گل، ۱۱ = ماشین، ۱۲ = اعضای بدن.
const List<GameCategory> kAllCategories = <GameCategory>[
  GameCategory(0, 'اسم'),
  GameCategory(1, 'فامیل'),
  GameCategory(2, 'شهر'),
  GameCategory(3, 'کشور'),
  GameCategory(4, 'غذا'),
  GameCategory(5, 'میوه'),
  GameCategory(6, 'حیوان'),
  GameCategory(7, 'رنگ'),
  GameCategory(8, 'شغل'),
  GameCategory(9, 'اشیاء'),
  GameCategory(10, 'گل'),
  GameCategory(11, 'ماشین'),
  GameCategory(12, 'اعضای بدن'),
];

/// ترتیب نمایش دسته‌ها (همان ترتیب نسخهٔ Kotlin).
const List<int> kCategoryDisplayOrder = <int>[
  0,
  1,
  2,
  3,
  4,
  5,
  10,
  6,
  7,
  8,
  11,
  12,
  9,
];

/// دسته‌های به ترتیب نمایش.
List<GameCategory> orderedCategories() => kCategoryDisplayOrder
    .map((id) => kAllCategories.firstWhere((c) => c.id == id))
    .toList(growable: false);

/// شناسهٔ همهٔ دسته‌ها به ترتیب نمایش (پیش‌فرض: همه فعال).
List<int> defaultActiveCategoryIds() => List<int>.from(kCategoryDisplayOrder);

/// یافتن دسته با شناسه.
GameCategory? categoryById(int id) {
  for (final c in kAllCategories) {
    if (c.id == id) return c;
  }
  return null;
}

/// دسته‌های فعال به ترتیب نمایش، از روی فهرست شناسه‌ها.
List<GameCategory> activeCategoriesOf(List<int> ids) {
  final set = ids.toSet();
  return orderedCategories()
      .where((c) => set.contains(c.id))
      .toList(growable: false);
}
