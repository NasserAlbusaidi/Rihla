import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/models/split_mode.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
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

  testWidgets(
    'non-payer sees their per-person share on a global equal split',
    (tester) async {
      await pumpRow(tester, globalEqualFromFirestore(), viewerId: 'alice');

      // Two amounts render: the expense total and the viewer's share.
      expect(find.byType(RAmount), findsNWidgets(2));
    },
  );

  testWidgets(
    'personal expense splits 1 way and bills non-payers nothing',
    (tester) async {
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
    },
  );

  testWidgets(
    'global non-equal (percent) split shows no misleading equal share',
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

      // The row cannot reproduce BalanceCalculator's weighted allocation, so it
      // must omit the per-head share rather than show a wrong equal figure.
      expect(find.byType(RAmount), findsOneWidget);
    },
  );
}
