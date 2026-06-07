import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/ledger/models/expense_category_model.dart';
import 'package:safar/features/ledger/keys/ledger_keys.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/providers/category_provider.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';
import 'package:safar/features/ledger/screens/edit_expense_screen.dart';
import 'package:safar/features/ledger/services/expense_service.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

class _MockExpenseService extends Mock implements ExpenseService {}

void main() {
  testWidgets(
    'shows the loading scaffold while the expense stream has no value',
    (tester) async {
      await _pumpEditExpenseScreen(
        tester,
        expenses: const Stream<List<Expense>>.empty(),
      );

      expect(find.byKey(LedgerKeys.editExpenseSheet), findsOneWidget);
      expect(find.byType(Scaffold), findsOneWidget);
    },
  );

  testWidgets('shows a load error when the expense stream fails', (
    tester,
  ) async {
    await _pumpEditExpenseScreen(
      tester,
      expenses: Stream<List<Expense>>.error(StateError('boom')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Could not load expense'), findsOneWidget);
    expect(
      find.text('Something went wrong. Try again in a moment.'),
      findsOneWidget,
    );
    expect(find.text('Back'), findsOneWidget);
  });

  testWidgets('shows not-found when the target expense is absent', (
    tester,
  ) async {
    await _pumpEditExpenseScreen(
      tester,
      expenses: Stream<List<Expense>>.value(const []),
    );
    await tester.pumpAndSettle();

    expect(find.text('Expense not found'), findsOneWidget);
    expect(find.text('This expense may have been deleted.'), findsOneWidget);
  });

  testWidgets(
    '#248 PR4 a participant who is not the creator sees the editor (open edit)',
    (tester) async {
      // uid-layla is in _event.participantIds but did not create the expense.
      await _pumpEditExpenseScreen(
        tester,
        currentUid: 'uid-layla',
        expenses: Stream<List<Expense>>.value([
          _expense(createdBy: 'uid-yasmin'),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(LedgerKeys.editExpenseSheet), findsOneWidget);
      expect(find.text('View only'), findsNothing);
    },
  );

  testWidgets(
    '#248 PR4 a non-participant still sees view-only',
    (tester) async {
      // uid-zara is NOT in _event.participantIds.
      await _pumpEditExpenseScreen(
        tester,
        currentUid: 'uid-zara',
        expenses: Stream<List<Expense>>.value([
          _expense(createdBy: 'uid-yasmin'),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.text('View only'), findsOneWidget);
      expect(
        find.text('Only people in this event can edit expenses.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('creator can save an amount change', (tester) async {
    final service = _MockExpenseService();
    when(
      () => service.updateExpense(
        groupId: 'group-1',
        eventId: 'event-1',
        expenseId: 'expense-1',
        amount: Decimal.parse('15'),
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
    ).thenAnswer((_) async {});

    await _pumpEditableRoute(
      tester,
      expenseService: service,
      expenses: Stream<List<Expense>>.value([
        _expense(createdBy: 'uid-yasmin'),
      ]),
    );

    await tester.tap(find.text('Open edit'));
    await tester.pumpAndSettle();
    expect(find.text('Edit expense'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '15');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    verify(
      () => service.updateExpense(
        groupId: 'group-1',
        eventId: 'event-1',
        expenseId: 'expense-1',
        amount: Decimal.parse('15'),
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
    ).called(1);
    expect(find.text('Open edit'), findsOneWidget);
  });

  testWidgets('creator can confirm deletion', (tester) async {
    final service = _MockExpenseService();
    when(
      () => service.deleteExpense(
        groupId: 'group-1',
        eventId: 'event-1',
        expenseId: 'expense-1',
        lastEditedBy: 'uid-yasmin',
      ),
    ).thenAnswer((_) async {});

    await _pumpEditableRoute(
      tester,
      expenseService: service,
      expenses: Stream<List<Expense>>.value([
        _expense(createdBy: 'uid-yasmin'),
      ]),
    );

    await tester.tap(find.text('Open edit'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Delete this expense'));
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    verify(
      () => service.deleteExpense(
        groupId: 'group-1',
        eventId: 'event-1',
        expenseId: 'expense-1',
        lastEditedBy: 'uid-yasmin',
      ),
    ).called(1);
    expect(find.text('Open edit'), findsOneWidget);
  });

  testWidgets('shows a snackbar when saving an edit fails', (tester) async {
    final service = _MockExpenseService();
    when(
      () => service.updateExpense(
        groupId: 'group-1',
        eventId: 'event-1',
        expenseId: 'expense-1',
        amount: Decimal.parse('18'),
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
    ).thenThrow(StateError('locked'));

    await _pumpEditableRoute(
      tester,
      expenseService: service,
      expenses: Stream<List<Expense>>.value([
        _expense(createdBy: 'uid-yasmin'),
      ]),
    );

    await tester.tap(find.text('Open edit'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '18');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.text('Failed to update expense: Bad state: locked'),
      findsOneWidget,
    );
  });

  testWidgets('delete confirmation can be cancelled', (tester) async {
    final service = _MockExpenseService();

    await _pumpEditableRoute(
      tester,
      expenseService: service,
      expenses: Stream<List<Expense>>.value([
        _expense(createdBy: 'uid-yasmin'),
      ]),
    );

    await tester.tap(find.text('Open edit'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Delete this expense'));
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Edit expense'), findsOneWidget);
    verifyNever(
      () => service.deleteExpense(
        groupId: any(named: 'groupId'),
        eventId: any(named: 'eventId'),
        expenseId: any(named: 'expenseId'),
        lastEditedBy: any(named: 'lastEditedBy'),
      ),
    );
  });

  testWidgets('shows a snackbar when deletion fails', (tester) async {
    final service = _MockExpenseService();
    when(
      () => service.deleteExpense(
        groupId: 'group-1',
        eventId: 'event-1',
        expenseId: 'expense-1',
        lastEditedBy: 'uid-yasmin',
      ),
    ).thenThrow(StateError('permission denied'));

    await _pumpEditableRoute(
      tester,
      expenseService: service,
      expenses: Stream<List<Expense>>.value([
        _expense(createdBy: 'uid-yasmin'),
      ]),
    );

    await tester.tap(find.text('Open edit'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Delete this expense'));
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.text('Failed to delete expense: Bad state: permission denied'),
      findsOneWidget,
    );
  });
}

Future<void> _pumpEditExpenseScreen(
  WidgetTester tester, {
  required Stream<List<Expense>> expenses,
  String? currentUid = 'uid-yasmin',
}) async {
  const eventRef = (groupId: 'group-1', eventId: 'event-1');

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserIdProvider.overrideWithValue(currentUid),
        eventExpensesProvider(eventRef).overrideWith((ref) => expenses),
        // #248 PR4: the screen now gates edit on event participation.
        eventDetailProvider(
          eventRef,
        ).overrideWith((ref) => Stream.value(_event)),
        tripCategoriesProvider(
          'event-1',
        ).overrideWith((ref) => Stream.value(_categories)),
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
  await tester.pump();
}

Future<void> _pumpEditableRoute(
  WidgetTester tester, {
  required Stream<List<Expense>> expenses,
  required ExpenseService expenseService,
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
        expenseServiceProvider.overrideWithValue(expenseService),
        eventExpensesProvider(eventRef).overrideWith((ref) => expenses),
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
}

Expense _expense({required String createdBy}) {
  return Expense(
    id: 'expense-1',
    tripId: 'event-1',
    payerParticipantId: 'uid-yasmin',
    amount: Decimal.parse('12.500'),
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
