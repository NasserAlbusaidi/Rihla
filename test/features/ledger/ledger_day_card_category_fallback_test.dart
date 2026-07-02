import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/utils/ledger_timeline.dart';
import 'package:safar/features/ledger/widgets/ledger_day_card.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

/// #789 — a no-description expense row falls back to its category name
/// (#689-spirit) instead of the generic "Expense".
void main() {
  Future<void> pumpRow(WidgetTester tester, Expense expense) {
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
            currentParticipantId: 'alice',
            participantCount: 3,
            expensePayerDisplayNames: const {},
            settlementDisplayNames: const {},
            owedByExpenseId: const {},
            onExpenseTap: (_) {},
          ),
        ),
      ),
    );
  }

  Expense expense({String? description, String? categoryId}) => Expense(
    id: 'expense-1',
    tripId: 'event-1',
    payerParticipantId: 'bob',
    amount: Decimal.parse('12.000'),
    description: description,
    categoryId: categoryId,
    scope: ExpenseScope.global,
    createdAt: DateTime(2026, 5, 17),
  );

  testWidgets('no description + known category → category name', (tester) async {
    await pumpRow(tester, expense(categoryId: 'food'));
    expect(find.text('Food'), findsOneWidget);
    expect(find.text('Expense'), findsNothing);
  });

  testWidgets('no description + no category → "Other"', (tester) async {
    await pumpRow(tester, expense());
    expect(find.text('Other'), findsOneWidget);
    expect(find.text('Expense'), findsNothing);
  });

  testWidgets('a description still wins over the category fallback', (
    tester,
  ) async {
    await pumpRow(tester, expense(description: 'Dinner', categoryId: 'food'));
    expect(find.text('Dinner'), findsOneWidget);
    expect(find.text('Food'), findsNothing);
  });
}
