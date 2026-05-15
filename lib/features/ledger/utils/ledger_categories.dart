import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/theme/tokens/color_tokens.dart';

/// Maps a free-text expense category name onto one of six stable buckets.
///
/// Bucket → category:
///   1 = Food, 2 = Lodging, 3 = Transit, 4 = Groceries,
///   5 = Activities, 6 = Other (default).
int ledgerCategoryBucket(String? name) {
  if (name == null) return 6;
  final lower = name.toLowerCase();
  bool any(List<String> needles) => needles.any(lower.contains);
  if (any(const ['food', 'rest', 'din', 'meal'])) return 1;
  if (any(const ['lodg', 'hotel', 'accom', 'stay'])) return 2;
  if (any(const ['trans', 'taxi', 'flight', 'uber', 'train'])) return 3;
  if (any(const ['groc', 'supermark'])) return 4;
  if (any(const ['activ', 'entertain', 'tour', 'ticket'])) return 5;
  return 6;
}

String ledgerCategoryName(int bucket) => switch (bucket) {
  1 => 'Food',
  2 => 'Lodging',
  3 => 'Transit',
  4 => 'Groceries',
  5 => 'Activities',
  _ => 'Other',
};

Color ledgerCategoryColor(AppColorTokens colors, int bucket) => switch (bucket) {
  1 => colors.cat1,
  2 => colors.cat2,
  3 => colors.cat3,
  4 => colors.cat4,
  5 => colors.cat5,
  _ => colors.cat6,
};

IconData ledgerCategoryIcon(int bucket) => switch (bucket) {
  1 => Iconsax.coffee,
  2 => Iconsax.house_2,
  3 => Iconsax.car,
  4 => Iconsax.shopping_cart,
  5 => Iconsax.star,
  _ => Iconsax.box,
};
