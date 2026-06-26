import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/theme/tokens/color_tokens.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../events/models/event_model.dart';

/// Canonical category id catalog — the single source of truth for expense
/// categories (#689). Declaration order defines the default display order AND
/// the legacy 1-based "bucket" numbering the ledger filter strip pivots on
/// (bucket == index + 1).
///
/// Ids are PERSISTED on expenses as `categoryId`. Never rename or remove an
/// existing id without a migration; new ids may be appended.
const List<String> kCategoryIds = <String>[
  'food',
  'groceries',
  'drinks',
  'transport',
  'fuel',
  'accommodation',
  'activities',
  'shopping',
  'fees',
  'other',
];

/// The legacy display "bucket" (1-based) used by the ledger filter strip.
///
/// #689: now derived from the PERSISTED `categoryId` — NOT the never-persisted
/// `categoryName`, which was null for every Firebase expense and collapsed them
/// all to Other. Unknown / null ids fold to the Other bucket.
int ledgerCategoryBucket(String? categoryId) {
  final index = categoryId == null ? -1 : kCategoryIds.indexOf(categoryId);
  return index >= 0 ? index + 1 : kCategoryIds.length;
}

String _idForBucket(int bucket) =>
    (bucket >= 1 && bucket <= kCategoryIds.length)
    ? kCategoryIds[bucket - 1]
    : 'other';

String ledgerCategoryName(int bucket, AppLocalizations l10n) =>
    categoryNameForId(_idForBucket(bucket), l10n);

Color ledgerCategoryColor(AppColorTokens colors, int bucket) =>
    categoryColorForId(colors, _idForBucket(bucket));

IconData ledgerCategoryIcon(int bucket) =>
    categoryIconForId(_idForBucket(bucket));

/// Localized display name for a [categoryId]. Unknown / null → Other.
String categoryNameForId(String? id, AppLocalizations l10n) => switch (id) {
  'food' => l10n.categoryFood,
  'groceries' => l10n.categoryGroceries,
  'drinks' => l10n.categoryDrinks,
  'transport' => l10n.categoryTransport,
  'fuel' => l10n.categoryFuel,
  'accommodation' => l10n.categoryAccommodation,
  'activities' => l10n.categoryActivities,
  'shopping' => l10n.categoryShopping,
  'fees' => l10n.categoryFees,
  _ => l10n.categoryOther,
};

/// Theme color for a [categoryId]. Reuses the six `cat` tokens (#689 decision:
/// no new palette colors without design sign-off); related categories share a
/// hue and are disambiguated by icon + label.
Color categoryColorForId(AppColorTokens colors, String? id) => switch (id) {
  'food' || 'drinks' => colors.cat1,
  'accommodation' => colors.cat2,
  'transport' || 'fuel' => colors.cat3,
  'groceries' => colors.cat4,
  'activities' || 'shopping' => colors.cat5,
  _ => colors.cat6,
};

/// Icon for a [categoryId]. All names verified present in iconsax 0.0.8.
IconData categoryIconForId(String? id) => switch (id) {
  'food' => Iconsax.coffee,
  'groceries' => Iconsax.shopping_cart,
  'drinks' => Iconsax.cup,
  'transport' => Iconsax.car,
  'fuel' => Iconsax.gas_station,
  'accommodation' => Iconsax.house_2,
  'activities' => Iconsax.star,
  'shopping' => Iconsax.bag_2,
  'fees' => Iconsax.receipt,
  _ => Iconsax.box,
};

/// Per-event-type category ordering (#689) — the "smart default" that surfaces
/// the categories a given event type usually needs at the front of the picker.
/// Every list is a permutation of [kCategoryIds]; null-event callers pass
/// [EventType.custom] for the neutral default order.
List<String> categoryOrderForType(EventType type) => switch (type) {
  EventType.camping => const [
    'groceries',
    'fuel',
    'food',
    'drinks',
    'activities',
    'accommodation',
    'transport',
    'shopping',
    'fees',
    'other',
  ],
  EventType.trip || EventType.travel => const [
    'accommodation',
    'transport',
    'food',
    'activities',
    'drinks',
    'fuel',
    'groceries',
    'shopping',
    'fees',
    'other',
  ],
  EventType.nightDayOut => const [
    'food',
    'drinks',
    'activities',
    'transport',
    'shopping',
    'groceries',
    'fuel',
    'accommodation',
    'fees',
    'other',
  ],
  EventType.custom => kCategoryIds,
};
