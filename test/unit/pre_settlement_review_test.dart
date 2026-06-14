import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/models/split_mode.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/services/pre_settlement_review.dart';

/// #204 — pure detection of review-worthy expenses for the pre-settlement
/// review sheet. No money calculation; soft-deleted expenses ignored; the
/// large-amount heuristic is per-currency and never fires on a lone expense.

Expense _exp({
  required String id,
  String amount = '5.000',
  ExpenseScope scope = ExpenseScope.global,
  SplitMode? splitMode = SplitMode.equally,
  bool isDeleted = false,
  String currency = 'OMR',
}) => Expense(
  id: id,
  tripId: 'event-1',
  payerParticipantId: 'uid-a',
  amount: Decimal.parse(amount),
  scope: scope,
  splitMode: splitMode,
  isDeleted: isDeleted,
  currency: currency,
  createdAt: DateTime(2026, 6, 1),
  description: id,
);

void main() {
  group('detectReviewWorthyExpenses', () {
    test('ordinary equal-split global expenses produce no flags', () {
      expect(
        detectReviewWorthyExpenses([_exp(id: 'a'), _exp(id: 'b')]),
        isEmpty,
      );
    });

    test('an exact split is flagged', () {
      final flags = detectReviewWorthyExpenses([
        _exp(id: 'a', splitMode: SplitMode.exact),
        _exp(id: 'b'),
      ]);
      expect(
        flags
            .where((f) => f.reason == ReviewReason.exactSplit)
            .map((f) => f.expense.id),
        ['a'],
      );
    });

    test('a custom-participant scope is flagged', () {
      final flags = detectReviewWorthyExpenses([
        _exp(id: 'a', scope: ExpenseScope.custom),
        _exp(id: 'b'),
      ]);
      expect(
        flags
            .where((f) => f.reason == ReviewReason.customParticipants)
            .map((f) => f.expense.id),
        ['a'],
      );
    });

    test('a personal scope is flagged', () {
      final flags = detectReviewWorthyExpenses([
        _exp(id: 'a', scope: ExpenseScope.personal),
        _exp(id: 'b'),
      ]);
      expect(
        flags
            .where((f) => f.reason == ReviewReason.personal)
            .map((f) => f.expense.id),
        ['a'],
      );
    });

    test('an expense dominating the event total is flagged large', () {
      final flags = detectReviewWorthyExpenses([
        _exp(id: 'villa', amount: '120.000'),
        _exp(id: 'coffee', amount: '2.000'),
        _exp(id: 'snack', amount: '3.000'),
      ]);
      expect(
        flags
            .where((f) => f.reason == ReviewReason.largeAmount)
            .map((f) => f.expense.id),
        ['villa'],
      );
    });

    test('a lone expense is never flagged large', () {
      expect(
        detectReviewWorthyExpenses([
          _exp(id: 'only', amount: '50.000'),
        ]).where((f) => f.reason == ReviewReason.largeAmount),
        isEmpty,
      );
    });

    test('soft-deleted expenses are ignored entirely', () {
      expect(
        detectReviewWorthyExpenses([
          _exp(id: 'a', splitMode: SplitMode.exact, isDeleted: true),
          _exp(id: 'b'),
        ]),
        isEmpty,
      );
    });

    test('the large-amount heuristic is per-currency (no cross-currency mix)', () {
      final flags = detectReviewWorthyExpenses([
        _exp(id: 'omr-big', amount: '100.000', currency: 'OMR'),
        _exp(id: 'omr-small', amount: '1.000', currency: 'OMR'),
        _exp(id: 'usd-big', amount: '100.00', currency: 'USD'),
        _exp(id: 'usd-small', amount: '1.00', currency: 'USD'),
      ]);
      expect(
        flags
            .where((f) => f.reason == ReviewReason.largeAmount)
            .map((f) => f.expense.id)
            .toSet(),
        {'omr-big', 'usd-big'},
      );
    });

    test('one expense can carry multiple reasons (exact + large)', () {
      final flags = detectReviewWorthyExpenses([
        _exp(id: 'big', amount: '100.000', splitMode: SplitMode.exact),
        _exp(id: 'small', amount: '1.000'),
      ]);
      final reasonsForBig = flags
          .where((f) => f.expense.id == 'big')
          .map((f) => f.reason)
          .toSet();
      expect(reasonsForBig, {ReviewReason.exactSplit, ReviewReason.largeAmount});
    });
  });
}
