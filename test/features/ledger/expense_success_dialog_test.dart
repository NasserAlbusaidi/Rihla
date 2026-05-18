import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/widgets/expense_success_dialog.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

void main() {
  Expense makeExpense() {
    return Expense(
      id: 'expense-1',
      tripId: 'event-1',
      payerParticipantId: 'uid-1',
      amount: Decimal.parse('1.450'),
      scope: ExpenseScope.global,
      categoryName: 'Food & Dining',
      createdAt: DateTime(2026, 5, 12),
    );
  }

  Widget wrap(Widget child, {Size size = const Size(360, 520)}) {
    return MaterialApp(
      theme: AppTheme.lightTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: Scaffold(body: Center(child: child)),
      ),
    );
  }

  testWidgets('fits a short Android viewport without render overflow', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        ExpenseSuccessDialog(
          expense: makeExpense(),
          currency: 'OMR',
          onDone: () {},
          onAddAnother: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
