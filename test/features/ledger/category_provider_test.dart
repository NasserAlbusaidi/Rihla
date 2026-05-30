import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/features/ledger/providers/category_provider.dart';

void main() {
  group('tripCategoriesProvider', () {
    test('emits six default categories', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final categories = await container
          .read(tripCategoriesProvider('any-trip-id').future);

      expect(categories, hasLength(6));
      expect(
        categories.map((c) => c.id).toList(),
        ['food', 'transport', 'accommodation', 'activities', 'shopping', 'other'],
      );
      expect(categories.every((c) => c.isDefault), isTrue);
    });
  });
}
