import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iconsax/iconsax.dart';
import 'package:safar/core/theme/tokens/color_tokens.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/ledger/utils/ledger_categories.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppLocalizations en;
  late AppLocalizations ar;
  setUpAll(() async {
    en = await AppLocalizations.delegate.load(const Locale('en'));
    ar = await AppLocalizations.delegate.load(const Locale('ar'));
  });

  group('kCategoryIds catalog', () {
    test('has ten unique ids ending in other', () {
      expect(kCategoryIds, hasLength(10));
      expect(kCategoryIds.toSet(), hasLength(10));
      expect(kCategoryIds.last, 'other');
    });
  });

  group('ledgerCategoryBucket (#689 id-driven, not categoryName)', () {
    test('each id maps to a distinct 1-based bucket in catalog order', () {
      for (var i = 0; i < kCategoryIds.length; i++) {
        expect(ledgerCategoryBucket(kCategoryIds[i]), i + 1);
      }
    });

    test('persisted ids no longer collapse to Other (the bug)', () {
      // Pre-#689 the substring matcher had no case for these → all Other.
      expect(
        ledgerCategoryBucket('shopping'),
        isNot(ledgerCategoryBucket('other')),
      );
      expect(
        ledgerCategoryBucket('groceries'),
        isNot(ledgerCategoryBucket('other')),
      );
      expect(
        ledgerCategoryBucket('drinks'),
        isNot(ledgerCategoryBucket('other')),
      );
    });

    test('null and unknown ids fold to the Other bucket (last)', () {
      expect(ledgerCategoryBucket(null), kCategoryIds.length);
      expect(ledgerCategoryBucket('totally-unknown'), kCategoryIds.length);
      expect(ledgerCategoryBucket('other'), kCategoryIds.length);
    });
  });

  group('categoryNameForId', () {
    test('resolves each id to its localized name (EN)', () {
      expect(categoryNameForId('food', en), en.categoryFood);
      expect(categoryNameForId('groceries', en), en.categoryGroceries);
      expect(categoryNameForId('drinks', en), en.categoryDrinks);
      expect(categoryNameForId('transport', en), en.categoryTransport);
      expect(categoryNameForId('fuel', en), en.categoryFuel);
      expect(categoryNameForId('accommodation', en), en.categoryAccommodation);
      expect(categoryNameForId('activities', en), en.categoryActivities);
      expect(categoryNameForId('shopping', en), en.categoryShopping);
      expect(categoryNameForId('fees', en), en.categoryFees);
      expect(categoryNameForId('other', en), en.categoryOther);
    });

    test('null and unknown ids fall back to Other', () {
      expect(categoryNameForId(null, en), en.categoryOther);
      expect(categoryNameForId('nope', en), en.categoryOther);
    });

    test('Arabic differs from English for every catalog id', () {
      for (final id in kCategoryIds) {
        expect(categoryNameForId(id, ar), isNotEmpty);
        expect(
          categoryNameForId(id, ar),
          isNot(categoryNameForId(id, en)),
          reason: 'AR/$id should differ from EN',
        );
      }
    });
  });

  group('legacy bucket helpers resolve through the catalog', () {
    test('a persisted categoryId resolves to its category, not Other', () {
      expect(
        ledgerCategoryName(ledgerCategoryBucket('shopping'), en),
        en.categoryShopping,
      );
      expect(
        ledgerCategoryName(ledgerCategoryBucket('groceries'), en),
        en.categoryGroceries,
      );
    });

    test('out-of-range buckets fall back to Other', () {
      expect(ledgerCategoryName(0, en), en.categoryOther);
      expect(ledgerCategoryName(99, en), en.categoryOther);
    });
  });

  group('categoryColorForId reuses the six cat tokens (#689 decision)', () {
    const c = AppColorTokens.light;
    test('related categories share a hue, every id resolves', () {
      expect(categoryColorForId(c, 'food'), c.cat1);
      expect(categoryColorForId(c, 'drinks'), c.cat1); // shares with food
      expect(categoryColorForId(c, 'groceries'), c.cat4);
      expect(categoryColorForId(c, 'transport'), c.cat3);
      expect(categoryColorForId(c, 'fuel'), c.cat3); // shares with transport
      expect(categoryColorForId(c, 'accommodation'), c.cat2);
      expect(categoryColorForId(c, null), c.cat6);
      expect(categoryColorForId(c, 'unknown'), c.cat6);
    });
  });

  group('categoryIconForId', () {
    test('known ids map to their icon; unknown → box', () {
      expect(categoryIconForId('fuel'), Iconsax.gas_station);
      expect(categoryIconForId('drinks'), Iconsax.cup);
      expect(categoryIconForId('groceries'), Iconsax.shopping_cart);
      expect(categoryIconForId('unknown'), Iconsax.box);
      expect(categoryIconForId(null), Iconsax.box);
    });
  });

  group('categoryOrderForType (per-type smart default #689)', () {
    test('every type order is a permutation of the catalog', () {
      for (final t in EventType.values) {
        final order = categoryOrderForType(t);
        expect(order, hasLength(kCategoryIds.length));
        expect(
          order.toSet(),
          kCategoryIds.toSet(),
          reason: '$t order must contain every catalog id exactly once',
        );
      }
    });

    test('camping leads with groceries then fuel', () {
      final order = categoryOrderForType(EventType.camping);
      expect(order[0], 'groceries');
      expect(order[1], 'fuel');
    });

    test('night/day out leads with food then drinks', () {
      final order = categoryOrderForType(EventType.nightDayOut);
      expect(order[0], 'food');
      expect(order[1], 'drinks');
    });

    test('custom keeps the neutral catalog order', () {
      expect(categoryOrderForType(EventType.custom), kCategoryIds);
    });
  });
}
