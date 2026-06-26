import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/features/ledger/providers/category_provider.dart';
import 'package:safar/features/ledger/utils/ledger_categories.dart';

void main() {
  group('tripCategoriesProvider', () {
    test('emits the ten default categories in catalog order (#689)', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final categories = await container.read(
        tripCategoriesProvider('any-trip-id').future,
      );

      expect(categories, hasLength(10));
      expect(categories.map((c) => c.id).toList(), kCategoryIds);
      expect(categories.every((c) => c.isDefault), isTrue);
    });
  });
}
