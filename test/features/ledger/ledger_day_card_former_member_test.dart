import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/utils/ledger_timeline.dart';
import 'package:safar/features/ledger/widgets/ledger_day_card.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

void main() {
  testWidgets('renders former-member payer display name', (tester) async {
    final expense = Expense(
      id: 'expense-1',
      tripId: 'event-1',
      payerParticipantId: 'orphan',
      amount: Decimal.parse('12.000'),
      description: 'Dinner',
      scope: ExpenseScope.global,
      createdAt: DateTime(2026, 5, 17),
    );

    await tester.pumpWidget(
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
            expensePayerDisplayNames: const {
              'expense-1': 'Aisha (former member)',
            },
            settlementDisplayNames: const {},
            owedByExpenseId: const {},
            onExpenseTap: (_) {},
          ),
        ),
      ),
    );

    expect(
      find.textContaining('\u{2068}Aisha (former member)\u{2069} paid'),
      findsOneWidget,
    );
  });
}
