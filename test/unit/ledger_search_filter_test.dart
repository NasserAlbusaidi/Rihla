import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/models/settlement_model.dart';
import 'package:safar/features/ledger/widgets/ledger_search_sheet.dart';
import 'package:safar/l10n/generated/app_localizations_en.dart';

void main() {
  Expense exp({
    required String id,
    String? description,
    String? categoryId,
    String? categoryName,
    String? payerName,
    DateTime? createdAt,
  }) {
    return Expense(
      id: id,
      tripId: 'event-1',
      payerParticipantId: 'p1',
      amount: Decimal.parse('5.000'),
      scope: ExpenseScope.global,
      description: description,
      categoryId: categoryId,
      categoryName: categoryName,
      payerName: payerName,
      createdAt: createdAt ?? DateTime(2026, 5, 13, 10),
    );
  }

  Settlement set({
    required String id,
    String? payerName,
    String? recipientName,
    String? note,
    DateTime? settledAt,
  }) {
    return Settlement(
      id: id,
      tripId: 'event-1',
      payerParticipantId: 'p1',
      recipientParticipantId: 'p2',
      amount: Decimal.parse('1.000'),
      note: note,
      payerName: payerName,
      recipientName: recipientName,
      scope: 'event',
      settledAt: settledAt ?? DateTime(2026, 5, 12, 9),
    );
  }

  group('Ledger search filter', () {
    final l10n = AppLocalizationsEn();
    List<Object> filter(
      List<Expense> expenses,
      List<Settlement> settlements,
      String query,
    ) => debugFilter(expenses, settlements, query, l10n: l10n);

    final expenses = [
      exp(id: 'e1', description: 'Taxi to airport', payerName: 'Alice'),
      exp(
        id: 'e2',
        description: 'Dinner',
        categoryId: 'food',
        payerName: 'Bob',
      ),
      exp(
        id: 'e3',
        description: 'Hotel',
        categoryId: 'accommodation',
        payerName: 'Cara',
      ),
    ];
    final settlements = [
      set(
        id: 's1',
        payerName: 'Bob',
        recipientName: 'Alice',
        note: 'Trip square-up',
      ),
    ];

    test('empty query returns nothing', () {
      expect(filter(expenses, settlements, ''), isEmpty);
    });

    test('matches expense description', () {
      final hits = filter(expenses, settlements, 'taxi');
      expect(hits.length, 1);
      expect((hits.first as Expense).id, 'e1');
    });

    test('matches expense category', () {
      final hits = filter(expenses, settlements, 'food');
      expect(hits.length, 1);
      expect((hits.first as Expense).id, 'e2');
    });

    test('matches persisted categoryId when categoryName is absent', () {
      final hits = filter(
        [exp(id: 'e1', categoryId: 'groceries', payerName: 'Alice')],
        const [],
        'groceries',
      );

      expect(hits.length, 1);
      expect((hits.first as Expense).id, 'e1');
    });

    test('matches expense payer', () {
      final hits = filter(expenses, settlements, 'cara');
      expect(hits.length, 1);
      expect((hits.first as Expense).id, 'e3');
    });

    test('matches settlement payer/recipient/note', () {
      expect(filter(expenses, settlements, 'square').length, 1);
      // "Alice" hits both e1.payerName and s1.recipientName.
      expect(filter(expenses, settlements, 'Alice').length, 2);
    });

    test('case-insensitive', () {
      expect(filter(expenses, settlements, 'TAXI').length, 1);
      expect(filter(expenses, settlements, 'TaXi').length, 1);
    });

    test('no matches → empty list', () {
      expect(filter(expenses, settlements, 'zzzzz'), isEmpty);
    });

    test('results sorted newest-first', () {
      final older = exp(
        id: 'old',
        description: 'Alice old expense',
        createdAt: DateTime(2024, 1, 1),
      );
      final newer = exp(
        id: 'new',
        description: 'Alice new expense',
        createdAt: DateTime(2026, 6, 1),
      );
      final hits = filter([older, newer], const [], 'alice');
      expect(hits.map((h) => (h as Expense).id).toList(), ['new', 'old']);
    });
  });
}
