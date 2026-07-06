import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/ledger/keys/ledger_keys.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/utils/ledger_timeline.dart';
import 'package:safar/features/ledger/widgets/ledger_day_card.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

/// #967 — a tappable ledger expense row must announce as one merged button,
/// not four unlabeled fragments (title / payer-split / amount / share).
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
            expensePayerDisplayNames: const {'expense-1': 'Bob'},
            settlementDisplayNames: const {},
            owedByExpenseId: const {},
            onExpenseTap: (_) {},
          ),
        ),
      ),
    );
  }

  final expense = Expense(
    id: 'expense-1',
    tripId: 'event-1',
    payerParticipantId: 'bob',
    amount: Decimal.parse('12.000'),
    description: 'Dinner',
    categoryId: 'food',
    scope: ExpenseScope.global,
    createdAt: DateTime(2026, 5, 17),
  );

  testWidgets('an expense row merges into one button node with a composed '
      'label', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpRow(tester, expense);

    final node = tester.getSemantics(
      find.byKey(LedgerKeys.expenseCard('expense-1')),
    );
    final data = node.getSemanticsData();
    expect(node.flagsCollection.isButton, isTrue);
    expect(data.hasAction(SemanticsAction.tap), isTrue);
    // Composed: the title and the payer/amount fragments fold into one label.
    expect(data.label, contains('Dinner'));
    expect(data.label, contains('Bob'));
    handle.dispose();
  });
}
