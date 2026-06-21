import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/models/split_mode.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/models/split_explanation.dart';

void main() {
  group('SplitItem round-trip', () {
    test('toMap/fromMap preserves all fields incl. Arabic label (RTL)', () {
      const item = SplitItem(
        label: 'قهوة',
        amountFils: 1500,
        quantity: 2,
        participantIds: ['p2', 'p1'],
        allocation: 'equal',
      );
      final restored = SplitItem.fromMap(item.toMap());
      expect(restored.label, 'قهوة');
      expect(restored.amountFils, 1500);
      expect(restored.quantity, 2);
      expect(restored.participantIds, ['p2', 'p1']);
      expect(restored.allocation, 'equal');
    });

    test('fromMap tolerates missing optional keys (lenient read)', () {
      final item = SplitItem.fromMap({
        'label': 'Tea',
        'amountFils': 500,
        'participantIds': ['p1'],
      });
      expect(item.quantity, 1);
      expect(item.allocation, 'equal');
    });
  });

  group('SplitAdjustment round-trip', () {
    test('toMap/fromMap preserves type, amountFils, allocation', () {
      const adj = SplitAdjustment(
        type: 'tip',
        amountFils: 1500,
        allocation: 'proportional',
      );
      final restored = SplitAdjustment.fromMap(adj.toMap());
      expect(restored.type, 'tip');
      expect(restored.amountFils, 1500);
      expect(restored.allocation, 'proportional');
    });

    test('fromMap is lenient — missing keys default, unknown type does not throw', () {
      final a = SplitAdjustment.fromMap({});
      expect(a.type, 'service');
      expect(a.amountFils, 0);
      expect(a.allocation, 'equal');

      // A legacy/unknown token (e.g. the old 'service_charge') reads fine for
      // DISPLAY — the lenient side never throws. The allocator is the strict side.
      final legacy = SplitAdjustment.fromMap({
        'type': 'service_charge',
        'amountFils': 250,
      });
      expect(legacy.type, 'service_charge');
      expect(legacy.amountFils, 250);
      expect(legacy.allocation, 'equal');
    });
  });

  group('SplitExplanation round-trip', () {
    test('toMap/fromMap preserves type, version, items', () {
      const exp = SplitExplanation(
        items: [
          SplitItem(label: 'Pizza', amountFils: 3000, participantIds: ['p1', 'p2']),
        ],
      );
      final restored = SplitExplanation.fromMap(exp.toMap());
      expect(restored.type, 'itemized');
      expect(restored.version, 1);
      expect(restored.items.length, 1);
      expect(restored.items.first.label, 'Pizza');
      expect(restored.items.first.amountFils, 3000);
    });

    test('omits adjustments key when null or empty, round-trips typed adjustments (#605)', () {
      const noAdj = SplitExplanation(items: []);
      expect(noAdj.toMap().containsKey('adjustments'), isFalse);

      // Empty list is treated like null — no key written (keeps top-level count minimal).
      const emptyAdj = SplitExplanation(items: [], adjustments: []);
      expect(emptyAdj.toMap().containsKey('adjustments'), isFalse);

      const withAdj = SplitExplanation(
        items: [],
        adjustments: [
          SplitAdjustment(type: 'service', amountFils: 250, allocation: 'equal'),
          SplitAdjustment(
            type: 'discount',
            amountFils: 100,
            allocation: 'proportional',
          ),
        ],
      );
      final restored = SplitExplanation.fromMap(withAdj.toMap());
      expect(restored.adjustments, isNotNull);
      expect(restored.adjustments!.length, 2);
      // SplitAdjustment has no value == — compare field-by-field.
      expect(restored.adjustments!.first.type, 'service');
      expect(restored.adjustments!.first.amountFils, 250);
      expect(restored.adjustments!.first.allocation, 'equal');
      expect(restored.adjustments![1].type, 'discount');
      expect(restored.adjustments![1].amountFils, 100);
      expect(restored.adjustments![1].allocation, 'proportional');
    });
  });

  group('Expense splitExplanation persistence', () {
    Expense base() => Expense(
      id: 'e1',
      tripId: 't1',
      payerParticipantId: 'p1',
      amount: Decimal.parse('1.000'),
      scope: ExpenseScope.global,
      splitMode: SplitMode.exact,
      splitDistribution: {
        'p1': Decimal.parse('0.500'),
        'p2': Decimal.parse('0.500'),
      },
      createdAt: DateTime.utc(2026, 6, 20),
      currency: 'OMR',
    );

    test('toFirestore OMITS splitExplanation when null (null fails the is-map rules bound)', () {
      expect(base().toFirestore().containsKey('splitExplanation'), isFalse);
    });

    test('toFirestore writes + fromFirestore restores splitExplanation', () {
      final e = base().copyWith(
        splitExplanation: const SplitExplanation(
          items: [
            SplitItem(label: 'Latte', amountFils: 500, participantIds: ['p1']),
            SplitItem(label: 'Mocha', amountFils: 500, participantIds: ['p2']),
          ],
        ),
      );
      final map = e.toFirestore();
      expect(map['splitExplanation'], isA<Map>());

      final restored = Expense.fromFirestore({...map, 'id': 'e1'});
      expect(restored.splitExplanation, isNotNull);
      expect(restored.splitExplanation!.type, 'itemized');
      expect(restored.splitExplanation!.items.length, 2);
      expect(restored.splitExplanation!.items.first.label, 'Latte');
      expect(restored.splitExplanation!.items.first.amountFils, 500);
    });

    test('fromFirestore yields null splitExplanation when key absent', () {
      final map = base().toFirestore();
      final restored = Expense.fromFirestore({...map, 'id': 'e1'});
      expect(restored.splitExplanation, isNull);
    });
  });
}
