import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iconsax/iconsax.dart';
import 'package:safar/core/theme/tokens/color_tokens.dart';
import 'package:safar/features/ledger/models/expense_category_model.dart';

void main() {
  group('ExpenseCategory', () {
    test('fromJson reads all persisted fields', () {
      final category = ExpenseCategory.fromJson({
        'id': 'cat-food',
        'trip_id': 'event-1',
        'name': 'Food',
        'icon': 'food',
        'color': '#123ABC',
        'is_default': true,
        'created_at': '2026-05-01T08:30:00.000Z',
      });

      expect(category.id, 'cat-food');
      expect(category.tripId, 'event-1');
      expect(category.name, 'Food');
      expect(category.icon, 'food');
      expect(category.color, '#123ABC');
      expect(category.isDefault, isTrue);
      expect(category.createdAt, DateTime.parse('2026-05-01T08:30:00.000Z'));
    });

    test('fromJson applies optional defaults', () {
      final category = ExpenseCategory.fromJson({
        'id': 'cat-other',
        'trip_id': 'event-1',
        'name': 'Other',
      });

      expect(category.icon, 'other');
      expect(category.color, '#22C55E');
      expect(category.isDefault, isFalse);
      expect(category.createdAt, isNull);
    });

    test('toJson writes Firebase/cache fields without derived id', () {
      const category = ExpenseCategory(
        id: 'cat-food',
        tripId: 'event-1',
        name: 'Food',
        icon: 'food',
        color: '#123ABC',
        isDefault: true,
      );

      expect(category.toJson(), {
        'trip_id': 'event-1',
        'name': 'Food',
        'icon': 'food',
        'color': '#123ABC',
        'is_default': true,
      });
    });

    test('iconData maps known category names and unknowns to receipt', () {
      const cases = {
        'gas': Iconsax.gas_station,
        'food': Iconsax.coffee,
        'gear': Iconsax.bag_2,
        'lodging': Iconsax.house,
        'transport': Iconsax.car,
        'other': Iconsax.receipt,
        'unexpected': Iconsax.receipt,
      };

      for (final entry in cases.entries) {
        final category = ExpenseCategory(
          id: entry.key,
          tripId: 'event-1',
          name: entry.key,
          icon: entry.key,
        );
        expect(category.iconData, entry.value);
      }
    });

    test('resolveColor parses valid hex and falls back to success token', () {
      const valid = ExpenseCategory(
        id: 'valid',
        tripId: 'event-1',
        name: 'Valid',
        color: '#123ABC',
      );
      const invalid = ExpenseCategory(
        id: 'invalid',
        tripId: 'event-1',
        name: 'Invalid',
        color: 'not-a-color',
      );

      expect(valid.resolveColor(AppColorTokens.light), const Color(0xFF123ABC));
      expect(
        invalid.resolveColor(AppColorTokens.light),
        AppColorTokens.light.success,
      );
    });
  });
}
