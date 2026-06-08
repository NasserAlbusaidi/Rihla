import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/ledger/models/expense_category_model.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/providers/category_provider.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';
import 'package:safar/features/ledger/screens/edit_expense_screen.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

/// #261 PR-A: the edit editor must DISPLAY the expense's own stored currency
/// (label + input decimals), not a hardcoded 'OMR'. The write-preservation is
/// covered in edit_expense_screen_test.dart (#261 PR-0a). RED before A3: the
/// body's _tripCurrency getter hardcoded 'OMR' so a USD expense showed
/// 'AMOUNT · OMR'.
void main() {
  const eventRef = (groupId: 'group-1', eventId: 'event-1');

  Future<void> pumpEdit(WidgetTester tester, {required String currency}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserIdProvider.overrideWithValue('uid-yasmin'),
          eventExpensesProvider(eventRef).overrideWith(
            (ref) => Stream.value([
              Expense(
                id: 'expense-1',
                tripId: 'event-1',
                payerParticipantId: 'uid-yasmin',
                amount: Decimal.parse('12.50'),
                currency: currency,
                description: 'Dinner',
                scope: ExpenseScope.global,
                createdAt: DateTime(2026, 5, 30),
                createdBy: 'uid-yasmin',
              ),
            ]),
          ),
          eventDetailProvider(
            eventRef,
          ).overrideWith((ref) => Stream.value(_event)),
          tripCategoriesProvider(
            'event-1',
          ).overrideWith((ref) => Stream.value(const <ExpenseCategory>[])),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const EditExpenseScreen(
            groupId: 'group-1',
            eventId: 'event-1',
            expenseId: 'expense-1',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('editing a USD expense shows the USD amount label', (
    tester,
  ) async {
    await pumpEdit(tester, currency: 'USD');
    expect(find.text('Edit expense'), findsOneWidget);
    expect(find.text('AMOUNT · USD'), findsOneWidget);
    expect(find.text('AMOUNT · OMR'), findsNothing);
  });

  testWidgets('editing an OMR expense shows the OMR amount label', (
    tester,
  ) async {
    await pumpEdit(tester, currency: 'OMR');
    expect(find.text('AMOUNT · OMR'), findsOneWidget);
  });
}

final _event = Event(
  id: 'event-1',
  name: 'Marrakech',
  type: EventType.trip,
  groupId: 'group-1',
  createdBy: 'uid-yasmin',
  participantIds: const ['uid-yasmin', 'uid-layla'],
  participantNames: const {
    'uid-yasmin': 'Yasmin Khan',
    'uid-layla': 'Layla Hassan',
  },
  modules: const EventModules(),
  startDate: DateTime(2026, 3, 21),
  createdAt: DateTime(2026, 3, 20),
);
