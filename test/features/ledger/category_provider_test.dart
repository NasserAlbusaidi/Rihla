import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/features/ledger/providers/category_provider.dart';

void main() {
  group('categoryLoadingProvider', () {
    test('default is false', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(categoryLoadingProvider), isFalse);
    });

    test('mutable via notifier', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(categoryLoadingProvider.notifier).state = true;
      expect(container.read(categoryLoadingProvider), isTrue);
    });
  });

  group('categoryErrorProvider', () {
    test('default is null', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(categoryErrorProvider), isNull);
    });

    test('mutable via notifier', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(categoryErrorProvider.notifier).state = 'boom';
      expect(container.read(categoryErrorProvider), 'boom');
    });
  });

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

  group('CategoryService', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
      addTearDown(container.dispose);
    });

    test('createCategory returns null (custom categories not supported)',
        () async {
      final service = container.read(categoryServiceProvider);
      final result =
          await service.createCategory(tripId: 't1', name: 'Snacks');
      expect(result, isNull);
    });

    test('updateCategory returns false', () async {
      final service = container.read(categoryServiceProvider);
      final result = await service.updateCategory(categoryId: 'food');
      expect(result, isFalse);
    });

    test('deleteCategory returns false', () async {
      final service = container.read(categoryServiceProvider);
      final result = await service.deleteCategory('food');
      expect(result, isFalse);
    });
  });
}
