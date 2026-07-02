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
  DateTime? createdAt,
  String payerParticipantId = 'uid-a',
}) => Expense(
  id: id,
  tripId: 'event-1',
  payerParticipantId: payerParticipantId,
  amount: Decimal.parse(amount),
  scope: scope,
  splitMode: splitMode,
  isDeleted: isDeleted,
  currency: currency,
  createdAt: createdAt ?? DateTime(2026, 6, 1),
  description: id,
);

/// Builds N exact-split (always-flagged) expenses in one [currency] with
/// descending amounts, for exercising the per-currency cap.
List<ReviewFlag> _exactFlags(
  String currency,
  List<String> amounts, {
  String prefix = 'e',
}) => [
  for (var i = 0; i < amounts.length; i++)
    ReviewFlag(
      _exp(
        id: '$prefix-$i',
        amount: amounts[i],
        currency: currency,
        splitMode: SplitMode.exact,
      ),
      ReviewReason.exactSplit,
    ),
];

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

    test('an expense paid by a departed (non-live) member is flagged', () {
      final flags = detectReviewWorthyExpenses(
        [
          _exp(id: 'gone-pays', payerParticipantId: 'uid-gone'),
          _exp(id: 'live-pays', payerParticipantId: 'uid-a'),
        ],
        activeParticipantIds: {'uid-a'},
      );
      expect(
        flags
            .where((f) => f.reason == ReviewReason.payerNotInParticipants)
            .map((f) => f.expense.id),
        ['gone-pays'],
      );
    });

    test(
      'departed-payer check is skipped when the live-member set is unknown (empty)',
      () {
        // Guards every existing single-arg caller: with no activeParticipantIds
        // the payer check must NOT fire even though "uid-gone" is absent.
        final flags = detectReviewWorthyExpenses([
          _exp(id: 'gone-pays', payerParticipantId: 'uid-gone'),
        ]);
        expect(
          flags.where((f) => f.reason == ReviewReason.payerNotInParticipants),
          isEmpty,
        );
      },
    );

    test('a departed payer + exact split carries both reasons', () {
      final flags = detectReviewWorthyExpenses(
        [
          _exp(
            id: 'gone-exact',
            payerParticipantId: 'uid-gone',
            splitMode: SplitMode.exact,
          ),
          _exp(id: 'live', payerParticipantId: 'uid-a'),
        ],
        activeParticipantIds: {'uid-a'},
      );
      final reasons = flags
          .where((f) => f.expense.id == 'gone-exact')
          .map((f) => f.reason)
          .toSet();
      expect(reasons, {
        ReviewReason.exactSplit,
        ReviewReason.payerNotInParticipants,
      });
    });
  });

  group('reviewItemList (#521 — per-currency bucket cap)', () {
    test(
      'a high-value row in a later-alphabet currency is never hidden by the cap',
      () {
        // 5 JPY rows that each out-rank the OMR row by RAW magnitude (JPY 600+
        // > OMR 5) — under a flat cross-currency sort + take(5) they fill the
        // list and the only OMR row is dropped. Per-currency bucketing must
        // still surface it.
        final flags = [
          ..._exactFlags('JPY', ['1000', '900', '800', '700', '600'],
              prefix: 'jpy'),
          ReviewFlag(
            _exp(
              id: 'omr-only',
              amount: '5.000',
              currency: 'OMR',
              splitMode: SplitMode.exact,
            ),
            ReviewReason.exactSplit,
          ),
        ];

        final result = reviewItemList(flags);

        expect(
          result.shown.map((e) => e.id),
          contains('omr-only'),
          reason: 'the lone OMR row must not be buried behind cheaper JPY rows',
        );
        // Each currency is within its cap, so nothing is hidden.
        expect(result.overflow, 0);
      },
    );

    test('a single-currency event still shows up to the cap (no regression)', () {
      final flags = _exactFlags(
        'OMR',
        ['9.000', '8.000', '7.000', '6.000', '5.000', '4.000', '3.000'],
      );

      final result = reviewItemList(flags);

      expect(result.shown.length, kReviewPerCurrencyCap); // 5
      expect(result.overflow, 2);
      // Highest amounts first within the (single) currency bucket.
      expect(result.shown.map((e) => e.id), [
        'e-0',
        'e-1',
        'e-2',
        'e-3',
        'e-4',
      ]);
    });

    test('each currency is capped independently', () {
      final flags = [
        ..._exactFlags('OMR', ['9', '8', '7', '6', '5', '4'], prefix: 'omr'),
        ..._exactFlags('USD', ['9', '8', '7'], prefix: 'usd'),
      ];

      final result = reviewItemList(flags);

      // OMR: 6 rows → 5 shown, 1 hidden. USD: 3 rows → all shown.
      expect(result.shown.where((e) => e.currency == 'OMR').length, 5);
      expect(result.shown.where((e) => e.currency == 'USD').length, 3);
      expect(result.overflow, 1);
    });

    test('equal same-currency amounts tiebreak by createdAt desc then id asc', () {
      final flags = [
        ReviewFlag(
          _exp(
            id: 'older',
            amount: '5.000',
            splitMode: SplitMode.exact,
            createdAt: DateTime(2026, 6, 1),
          ),
          ReviewReason.exactSplit,
        ),
        ReviewFlag(
          _exp(
            id: 'newer',
            amount: '5.000',
            splitMode: SplitMode.exact,
            createdAt: DateTime(2026, 6, 3),
          ),
          ReviewReason.exactSplit,
        ),
        ReviewFlag(
          _exp(
            id: 'aaa',
            amount: '5.000',
            splitMode: SplitMode.exact,
            createdAt: DateTime(2026, 6, 3),
          ),
          ReviewReason.exactSplit,
        ),
      ];

      final result = reviewItemList(flags);

      // newer before older; among the two newest (same createdAt), id ascending.
      expect(result.shown.map((e) => e.id), ['aaa', 'newer', 'older']);
    });
  });
}
