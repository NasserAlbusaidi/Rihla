import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/models/split_mode.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/models/settlement_model.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';
import 'package:safar/features/ledger/utils/ledger_timeline.dart';
import 'package:safar/features/ledger/widgets/ledger_day_card.dart';
import 'package:safar/l10n/generated/app_localizations.dart';
import 'package:safar/shared/widgets/r_amount.dart';

/// Regression for #125: a global/equal-split expense persists
/// `customSplitParticipants: []` (the writer coalesces null -> []), so the
/// ledger row read it back as an empty list and rendered "split 0 ways" while
/// suppressing the per-person share.
///
/// The row must mirror BalanceCalculator's recipient selection by scope:
///   global/subGroup -> all participants, personal -> payer only,
///   custom -> the listed participants (empty -> all, matching the calculator).
/// And it must NOT invent an equal per-head share for a non-equal split
/// (shares/exact/percent), which the widget cannot reproduce faithfully.
///
/// Fixtures use `Expense.fromFirestore` (the `[]` shape production persists)
/// except where a typed splitMode/distribution is needed.
void main() {
  // Mirror `ledgerViewProvider`'s #629 memo: a non-equal split's row reads its
  // precomputed gross owed map (the row no longer allocates in build()). Equal
  // splits get no entry and take the row's cheap arithmetic branch.
  Map<String, Map<String, Decimal>> owedMapFor(Expense expense) {
    final mode = expense.splitMode;
    final dist = expense.splitDistribution;
    if (mode == null ||
        mode == SplitMode.equally ||
        dist == null ||
        dist.isEmpty) {
      return const {};
    }
    return {
      expense.id: BalanceCalculator.allocateExpenseOwed(
        amount: expense.amount,
        splitMode: expense.splitMode,
        splitDistribution: expense.splitDistribution,
        scope: expense.scope,
        customSplitParticipants: expense.customSplitParticipants,
        payerId: expense.payerParticipantId,
        participantIds: const <String>[],
        currency: expense.currency,
        onFallback: null,
      ),
    };
  }

  Future<void> pumpRow(
    WidgetTester tester,
    Expense expense, {
    required String viewerId,
    int participantCount = 3,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: LedgerDayCard(
            dayLabel: 'Today',
            sub: null,
            items: [LedgerExpenseItem(expense)],
            currentParticipantId: viewerId,
            participantCount: participantCount,
            expensePayerDisplayNames: const {'e1': 'Aisha'},
            settlementDisplayNames: const {},
            owedByExpenseId: owedMapFor(expense),
            onExpenseTap: (_) {},
          ),
        ),
      ),
    );
  }

  Expense globalEqualFromFirestore() => Expense.fromFirestore({
    'id': 'e1',
    'eventId': 'event-1',
    'payerParticipantId': 'orphan',
    'amountFils': 12000, // 12.000 OMR
    'currency': 'OMR',
    'description': 'Dinner',
    'scope': 'global',
    'customSplitParticipants': <String>[],
    'createdAt': '2026-05-17T00:00:00.000',
  });

  testWidgets(
    'global equal split persisted with empty list shows "split 3 ways"',
    (tester) async {
      await pumpRow(tester, globalEqualFromFirestore(), viewerId: 'alice');

      expect(find.textContaining('split 3 ways'), findsOneWidget);
      expect(find.textContaining('split 0 ways'), findsNothing);
    },
  );

  testWidgets('non-payer sees their per-person share on a global equal split', (
    tester,
  ) async {
    await pumpRow(tester, globalEqualFromFirestore(), viewerId: 'alice');

    // Two amounts render: the expense total and the viewer's share.
    expect(find.byType(RAmount), findsNWidgets(2));
  });

  testWidgets('personal expense splits 1 way and bills non-payers nothing', (
    tester,
  ) async {
    final personal = Expense.fromFirestore({
      'id': 'e1',
      'eventId': 'event-1',
      'payerParticipantId': 'orphan',
      'amountFils': 12000,
      'currency': 'OMR',
      'description': 'Solo snack',
      'scope': 'personal',
      'customSplitParticipants': <String>[],
      'createdAt': '2026-05-17T00:00:00.000',
    });

    await pumpRow(tester, personal, viewerId: 'alice');

    // Personal = payer only: BalanceCalculator splits across {payer}.
    expect(find.textContaining('split 1 way'), findsOneWidget);
    expect(find.textContaining('ways'), findsNothing);
    // A non-payer owes nothing on a personal expense -> no share line.
    expect(find.byType(RAmount), findsOneWidget);
  });

  /// A signed share line is `RAmount(sign: true, value: ...)`; the gross total
  /// is `RAmount(sign: false)`. Match on both so the finder is unambiguous.
  Finder signedShare(Decimal value) => find.byWidgetPredicate(
    (w) => w is RAmount && w.sign && w.value == value,
  );

  // #591: the ledger row now reuses BalanceCalculator.allocateExpenseOwed for
  // non-equal splits (shares/exact/percent) — reconstructing the signed,
  // current-user-relative figure — instead of the #125 omission. The persisted
  // balance and the row sub-line are byte-for-byte the same number (WYSIWYG).
  testWidgets(
    'global percent split shows the real signed per-person share (#591)',
    (tester) async {
      final percent = Expense(
        id: 'e1',
        tripId: 'event-1',
        payerParticipantId: 'orphan',
        amount: Decimal.parse('12.000'),
        scope: ExpenseScope.global,
        customSplitParticipants: const [],
        splitMode: SplitMode.percent,
        splitDistribution: {
          'orphan': Decimal.parse('50'),
          'alice': Decimal.parse('30'),
          'carol': Decimal.parse('20'),
        },
        createdAt: DateTime(2026, 5, 17),
      );

      await pumpRow(tester, percent, viewerId: 'alice');

      // alice owes 30% of 12.000 = 3.600; she is not the payer -> -3.600.
      expect(find.byType(RAmount), findsNWidgets(2));
      expect(signedShare(Decimal.parse('-3.600')), findsOneWidget);
    },
  );

  testWidgets(
    'shares 2:1 split: participant sees real -owed, payer sees real +net (#591)',
    (tester) async {
      Expense shares({required String payer}) => Expense(
        id: 'e1',
        tripId: 'event-1',
        payerParticipantId: payer,
        amount: Decimal.parse('12.000'),
        scope: ExpenseScope.global,
        customSplitParticipants: const [],
        splitMode: SplitMode.shares,
        splitDistribution: {
          'orphan': Decimal.parse('2'),
          'alice': Decimal.parse('1'),
        },
        createdAt: DateTime(2026, 5, 17),
      );

      // Participant alice: 1/3 of 12.000 = 4.000 owed, not payer -> -4.000.
      await pumpRow(tester, shares(payer: 'orphan'), viewerId: 'alice');
      expect(find.byType(RAmount), findsNWidgets(2));
      expect(signedShare(Decimal.parse('-4.000')), findsOneWidget);

      // Payer orphan: owes own 2/3 = 8.000; others owe them 12.000 - 8.000 = +4.000.
      await pumpRow(tester, shares(payer: 'orphan'), viewerId: 'orphan');
      expect(find.byType(RAmount), findsNWidgets(2));
      expect(signedShare(Decimal.parse('4.000')), findsOneWidget);
    },
  );

  // Orthogonal axis (different split mode): exact amounts, not weights.
  testWidgets(
    'exact split shows the real signed per-person share (#591)',
    (tester) async {
      final exact = Expense(
        id: 'e1',
        tripId: 'event-1',
        payerParticipantId: 'orphan',
        amount: Decimal.parse('12.000'),
        scope: ExpenseScope.global,
        customSplitParticipants: const [],
        splitMode: SplitMode.exact,
        splitDistribution: {
          'orphan': Decimal.parse('8.000'),
          'alice': Decimal.parse('4.000'),
        },
        createdAt: DateTime(2026, 5, 17),
      );

      await pumpRow(tester, exact, viewerId: 'alice');

      // alice's exact owed is 4.000; not the payer -> -4.000.
      expect(find.byType(RAmount), findsNWidgets(2));
      expect(signedShare(Decimal.parse('-4.000')), findsOneWidget);
    },
  );

  testWidgets('day stamp renders bare date and optional sub-caption', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const Scaffold(
          body: Column(
            children: [
              LedgerDayStamp(label: 'May 19'),
              LedgerDayStamp(label: 'Yesterday · May 18', sub: '2 entries'),
            ],
          ),
        ),
      ),
    );

    expect(find.text('May 19'), findsOneWidget);
    expect(find.text('Yesterday'), findsOneWidget);
    expect(find.text('MAY 18'), findsOneWidget);
    expect(find.text('2 entries'), findsOneWidget);
    expect(find.text('·'), findsOneWidget);
  });

  testWidgets(
    'custom split uses listed participants for split count and share',
    (tester) async {
      final custom = Expense(
        id: 'e1',
        tripId: 'event-1',
        payerParticipantId: 'orphan',
        amount: Decimal.parse('12.000'),
        description: 'Shared taxi',
        scope: ExpenseScope.custom,
        customSplitParticipants: const ['alice', 'carol'],
        splitMode: SplitMode.equally,
        createdAt: DateTime(2026, 5, 17),
      );

      await pumpRow(tester, custom, viewerId: 'alice');

      expect(find.textContaining('split 2 ways'), findsOneWidget);
      expect(find.byType(RAmount), findsNWidgets(2));
    },
  );

  testWidgets('payer outside custom split sees full amount as their share', (
    tester,
  ) async {
    final custom = Expense(
      id: 'e1',
      tripId: 'event-1',
      payerParticipantId: 'orphan',
      amount: Decimal.parse('12.000'),
      description: 'Gift',
      scope: ExpenseScope.custom,
      customSplitParticipants: const ['alice', 'carol'],
      splitMode: SplitMode.equally,
      createdAt: DateTime(2026, 5, 17),
    );

    await pumpRow(tester, custom, viewerId: 'orphan');

    expect(find.textContaining('\u{2068}You\u{2069} paid · split 2 ways'), findsOneWidget);
    expect(find.byType(RAmount), findsNWidgets(2));
  });

  testWidgets('payer inside equal split sees amount minus their own share', (
    tester,
  ) async {
    await pumpRow(tester, globalEqualFromFirestore(), viewerId: 'orphan');

    expect(find.textContaining('\u{2068}You\u{2069} paid · split 3 ways'), findsOneWidget);
    expect(find.byType(RAmount), findsNWidgets(2));
  });

  testWidgets('zero participants suppresses viewer share line', (tester) async {
    await pumpRow(
      tester,
      globalEqualFromFirestore(),
      viewerId: 'alice',
      participantCount: 0,
    );

    expect(find.textContaining('split 0 ways'), findsOneWidget);
    expect(find.byType(RAmount), findsOneWidget);
  });

  testWidgets('settlement row uses fallback names and settlement label', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: LedgerDayCard(
            dayLabel: 'Today',
            sub: null,
            items: [
              LedgerSettlementItem(
                Settlement(
                  id: 's1',
                  tripId: 'event-1',
                  amount: Decimal.parse('3.000'),
                  settledAt: DateTime(2026, 5, 17),
                ),
              ),
            ],
            currentParticipantId: 'alice',
            participantCount: 2,
            expensePayerDisplayNames: const {},
            settlementDisplayNames: const {},
            owedByExpenseId: const {},
            onExpenseTap: (_) {},
          ),
        ),
      ),
    );

    await tester.pump();

    expect(find.text('\u{2068}Someone\u{2069} paid \u{2068}someone\u{2069}'), findsOneWidget);
    expect(find.text('SETTLEMENT'), findsOneWidget);
  });

  testWidgets('settlement row prefers resolved names and renders note', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: LedgerDayCard(
            dayLabel: 'Today',
            sub: null,
            items: [
              LedgerSettlementItem(
                Settlement(
                  id: 's1',
                  tripId: 'event-1',
                  payerName: 'Persisted Payer',
                  recipientName: 'Persisted Recipient',
                  amount: Decimal.parse('3.000'),
                  note: 'Cash at dinner',
                  settledAt: DateTime(2026, 5, 17),
                ),
              ),
            ],
            currentParticipantId: 'alice',
            participantCount: 2,
            expensePayerDisplayNames: const {},
            settlementDisplayNames: const {
              's1': (
                payerName: 'Resolved Payer',
                recipientName: 'Resolved Recipient',
              ),
            },
            owedByExpenseId: const {},
            onExpenseTap: (_) {},
          ),
        ),
      ),
    );

    await tester.pump();

    expect(find.text('\u{2068}Resolved Payer\u{2069} paid \u{2068}Resolved Recipient\u{2069}'), findsOneWidget);
    expect(
      find.textContaining('Cash at dinner', findRichText: true),
      findsOneWidget,
    );
  });
}
