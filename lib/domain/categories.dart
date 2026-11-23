/// Game categories. IDs are permanent and never reordered.
library;

/// One game category.
class GameCategory {
  const GameCategory(this.id, this.title);

  final int id;
  final String title;
}

/// Single source of truth for all 13 categories.
/// IDs never change: 0..9 are the ten original categories (objects = 9),
/// 10 = flower, 11 = car, 12 = body parts.
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

/// Display order of categories.
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

/// Categories in display order.
List<GameCategory> orderedCategories() => kCategoryDisplayOrder
    .map((id) => kAllCategories.firstWhere((c) => c.id == id))
    .toList(growable: false);

/// IDs of all categories in display order (all active by default).
List<int> defaultActiveCategoryIds() => List<int>.from(kCategoryDisplayOrder);

/// Look up a category by ID.
GameCategory? categoryById(int id) {
  for (final c in kAllCategories) {
    if (c.id == id) return c;
  }
  return null;
}

/// Active categories in display order, from a list of IDs.
List<GameCategory> activeCategoriesOf(List<int> ids) {
  final set = ids.toSet();
  return orderedCategories()
      .where((c) => set.contains(c.id))
      .toList(growable: false);
}
