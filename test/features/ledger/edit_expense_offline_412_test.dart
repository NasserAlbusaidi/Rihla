import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:safar/core/providers/connectivity_provider.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/ledger/models/expense_category_model.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/providers/category_provider.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';
import 'package:safar/features/ledger/screens/edit_expense_screen.dart';
import 'package:safar/features/ledger/services/expense_service.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

class _MockExpenseService extends Mock implements ExpenseService {}

// #412 RED: offline, updateExpense/deleteExpense futures resolve only on
// SERVER ack — awaiting them raw means the edit screen never pops and the
// user is stuck on a spinner until reconnect.
void main() {
  testWidgets(
    '#412: offline edit-save pops back within bounded time',
    (tester) async {
      final service = _MockExpenseService();
      when(
        () => service.updateExpense(
          groupId: 'group-1',
          eventId: 'event-1',
          expenseId: 'expense-1',
          amount: Decimal.parse('15'),
          currency: 'OMR',
          description: null,
          scope: null,
          customSplitParticipants: null,
          splitMode: null,
          splitDistribution: null,
          clearSplit: false,
          categoryId: null,
          payerParticipantId: null,
          lastEditedBy: 'uid-yasmin',
        ),
      ).thenAnswer((_) => Completer<void>().future); // real offline: no ack

      final connectivity = ConnectivityNotifier(startPeriodicChecks: false)
        ..setOffline();
      late ProviderContainer container;

      await _pumpEditableRoute(
        tester,
        expenseService: service,
        connectivity: connectivity,
        onContainer: (c) => container = c,
      );

      await tester.tap(find.text('Open edit'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '15');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pump();
      // Past kWriteAckTimeout — fixed pumps only (ConnectivityNotifier trap).
      await tester.pump(const Duration(seconds: 6));
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Open edit'), findsOneWidget); // popped back
      expect(container.read(ledgerRevisionProvider), 1); // #104 bump fired
      expect(connectivity.state, ConnectivityStatus.syncing); // #357 banner
    },
  );

  testWidgets(
    '#412: offline delete shows the deleted snackbar and pops within '
    'bounded time',
    (tester) async {
      final service = _MockExpenseService();
      when(
        () => service.deleteExpense(
          groupId: 'group-1',
          eventId: 'event-1',
          expenseId: 'expense-1',
          lastEditedBy: 'uid-yasmin',
        ),
      ).thenAnswer((_) => Completer<void>().future);

      final connectivity = ConnectivityNotifier(startPeriodicChecks: false)
        ..setOffline();
      late ProviderContainer container;

      await _pumpEditableRoute(
        tester,
        expenseService: service,
        connectivity: connectivity,
        onContainer: (c) => container = c,
      );

      await tester.tap(find.text('Open edit'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Delete this expense'));
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 6));
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Expense deleted'), findsOneWidget);
      expect(find.text('Open edit'), findsOneWidget); // popped back
      expect(container.read(ledgerRevisionProvider), 1);
      expect(connectivity.state, ConnectivityStatus.syncing);
    },
  );
}

Future<void> _pumpEditableRoute(
  WidgetTester tester, {
  required ExpenseService expenseService,
  required ConnectivityNotifier connectivity,
  required void Function(ProviderContainer) onContainer,
}) async {
  const eventRef = (groupId: 'group-1', eventId: 'event-1');
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () => context.push('/edit'),
              child: const Text('Open edit'),
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/edit',
        builder: (context, state) => const EditExpenseScreen(
          groupId: 'group-1',
          eventId: 'event-1',
          expenseId: 'expense-1',
        ),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserIdProvider.overrideWithValue('uid-yasmin'),
        connectivityProvider.overrideWith((ref) => connectivity),
        expenseServiceProvider.overrideWithValue(expenseService),
        eventExpensesProvider(eventRef).overrideWith(
          (ref) => Stream.value([_expense(createdBy: 'uid-yasmin')]),
        ),
        eventDetailProvider(
          eventRef,
        ).overrideWith((ref) => Stream.value(_event)),
        tripCategoriesProvider(
          'event-1',
        ).overrideWith((ref) => Stream.value(_categories)),
      ],
      child: MaterialApp.router(
        theme: AppTheme.lightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  await tester.pump();
  onContainer(
    ProviderScope.containerOf(tester.element(find.byType(Scaffold).first)),
  );
}

Expense _expense({required String createdBy}) {
  return Expense(
    id: 'expense-1',
    tripId: 'event-1',
    payerParticipantId: 'uid-yasmin',
    amount: Decimal.parse('12.500'),
    currency: 'OMR',
    description: 'Dinner',
    scope: ExpenseScope.global,
    createdAt: DateTime(2026, 5, 30),
    createdBy: createdBy,
  );
}

final _event = Event(
  id: 'event-1',
  name: 'Marrakech, four ways',
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

final _categories = [
  ExpenseCategory(
    id: 'food',
    tripId: 'event-1',
    name: 'Food',
    icon: 'food',
    color: '#C2693B',
    createdAt: DateTime(2026, 1, 1),
  ),
];
