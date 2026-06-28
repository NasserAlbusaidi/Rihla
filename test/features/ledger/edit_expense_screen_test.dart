import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:safar/core/models/split_mode.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/ledger/models/expense_category_model.dart';
import 'package:safar/features/ledger/keys/ledger_keys.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/models/split_explanation.dart';
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
    ).called(1);
    expect(find.text('Open edit'), findsOneWidget);
  });

  testWidgets(
    'amount edit threads the expense currency, not a hardcoded OMR (#261)',
    (tester) async {
      // RED before the clobber fix: _save omitted currency:, so updateExpense
      // defaulted it to OMR and re-scaled amountFils — corrupting a non-OMR
      // expense. The save must forward original.currency ('USD' here).
      final service = _MockExpenseService();
      when(
        () => service.updateExpense(
          groupId: 'group-1',
          eventId: 'event-1',
          expenseId: 'expense-1',
          amount: Decimal.parse('15'),
          currency: 'USD',
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
          _expense(createdBy: 'uid-yasmin', currency: 'USD'),
        ]),
      );

      await tester.tap(find.text('Open edit'));
      await tester.pumpAndSettle();
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
          currency: 'USD',
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
    },
  );

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

  // #203 S2 PR1 — switching an itemized expense to an Equally split must
  // orphan-delete the now-stale splitExplanation (clearExplanation: true), not
  // leave itemized metadata stranded on a non-itemized expense.
  testWidgets(
    '#203 S2: itemized → equal edit clears splitExplanation (orphan-delete)',
    (tester) async {
      final service = _MockExpenseService();
      when(
        () => service.updateExpense(
          groupId: any(named: 'groupId'),
          eventId: any(named: 'eventId'),
          expenseId: any(named: 'expenseId'),
          amount: any(named: 'amount'),
          currency: any(named: 'currency'),
          description: any(named: 'description'),
          scope: any(named: 'scope'),
          customSplitParticipants: any(named: 'customSplitParticipants'),
          splitMode: any(named: 'splitMode'),
          splitDistribution: any(named: 'splitDistribution'),
          clearSplit: any(named: 'clearSplit'),
          splitExplanation: any(named: 'splitExplanation'),
          clearExplanation: any(named: 'clearExplanation'),
          categoryId: any(named: 'categoryId'),
          payerParticipantId: any(named: 'payerParticipantId'),
          lastEditedBy: any(named: 'lastEditedBy'),
        ),
      ).thenAnswer((_) async {});

      await _pumpEditableRoute(
        tester,
        expenseService: service,
        expenses: Stream<List<Expense>>.value([_itemizedExpense()]),
      );

      await tester.tap(find.text('Open edit'));
      await tester.pumpAndSettle();

      // #485: open the weights sheet from the Split card's mode segment. The
      // seeded expense is itemized (persisted as exact), so "Exact" reopens it.
      final exact = find.text('Exact');
      await tester.ensureVisible(exact);
      await tester.pumpAndSettle();
      await tester.tap(exact);
      await tester.pumpAndSettle();
      // Switch to the plain Equal split (the card's mode segment also shows
      // "Equal", so target the sheet's tab via .last), then Apply.
      await tester.tap(find.text('Equal').last);
      await tester.pump();
      await tester.tap(find.byKey(const Key('split_sheet_apply')));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // The split went equal AND its itemized metadata was orphan-deleted.
      verify(
        () => service.updateExpense(
          groupId: 'group-1',
          eventId: 'event-1',
          expenseId: 'expense-1',
          amount: any(named: 'amount'),
          currency: any(named: 'currency'),
          description: any(named: 'description'),
          scope: any(named: 'scope'),
          customSplitParticipants: any(named: 'customSplitParticipants'),
          splitMode: any(named: 'splitMode'),
          splitDistribution: any(named: 'splitDistribution'),
          clearSplit: true,
          splitExplanation: null,
          clearExplanation: true,
          categoryId: any(named: 'categoryId'),
          payerParticipantId: any(named: 'payerParticipantId'),
          lastEditedBy: any(named: 'lastEditedBy'),
        ),
      ).called(1);
    },
  );

  // #203 S2 PR1 — an edit that touches neither the split nor its metadata (here
  // a description-only change on an itemized expense) must NOT rewrite or clear
  // the splitExplanation: it passes splitExplanation: null + clearExplanation:
  // false so updateExpense leaves the stored map untouched. (Authoring a
  // *changed* itemized result — the relabel-only case — needs PR2's editor; the
  // independent set/clear/preserve branches are pinned at the service layer.)
  // The amount is left at the seeded 12.500 so the exact-split sync guard, which
  // checks the stored distribution sums to the current amount, does not fire.
  testWidgets(
    '#203 S2: a description-only edit on an itemized expense leaves '
    'splitExplanation untouched',
    (tester) async {
      final service = _MockExpenseService();
      when(
        () => service.updateExpense(
          groupId: any(named: 'groupId'),
          eventId: any(named: 'eventId'),
          expenseId: any(named: 'expenseId'),
          amount: any(named: 'amount'),
          currency: any(named: 'currency'),
          description: any(named: 'description'),
          scope: any(named: 'scope'),
          customSplitParticipants: any(named: 'customSplitParticipants'),
          splitMode: any(named: 'splitMode'),
          splitDistribution: any(named: 'splitDistribution'),
          clearSplit: any(named: 'clearSplit'),
          splitExplanation: any(named: 'splitExplanation'),
          clearExplanation: any(named: 'clearExplanation'),
          categoryId: any(named: 'categoryId'),
          payerParticipantId: any(named: 'payerParticipantId'),
          lastEditedBy: any(named: 'lastEditedBy'),
        ),
      ).thenAnswer((_) async {});

      await _pumpEditableRoute(
        tester,
        expenseService: service,
        expenses: Stream<List<Expense>>.value([_itemizedExpense()]),
      );

      await tester.tap(find.text('Open edit'));
      await tester.pumpAndSettle();
      // Change only the description; the split (exact) and its sum are untouched
      // so the #250 exact-sync guard passes and updateExpense is reached.
      await tester.enterText(
        find.widgetWithText(TextField, 'Description'),
        'Dinner at the souq',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      verify(
        () => service.updateExpense(
          groupId: 'group-1',
          eventId: 'event-1',
          expenseId: 'expense-1',
          amount: any(named: 'amount'),
          currency: any(named: 'currency'),
          description: 'Dinner at the souq',
          scope: any(named: 'scope'),
          customSplitParticipants: any(named: 'customSplitParticipants'),
          splitMode: any(named: 'splitMode'),
          splitDistribution: any(named: 'splitDistribution'),
          clearSplit: any(named: 'clearSplit'),
          splitExplanation: null,
          clearExplanation: false,
          categoryId: any(named: 'categoryId'),
          payerParticipantId: any(named: 'payerParticipantId'),
          lastEditedBy: any(named: 'lastEditedBy'),
        ),
      ).called(1);
    },
  );
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

Expense _expense({required String createdBy, String currency = 'OMR'}) {
  return Expense(
    id: 'expense-1',
    tripId: 'event-1',
    payerParticipantId: 'uid-yasmin',
    amount: Decimal.parse('12.500'),
    currency: currency,
    description: 'Dinner',
    scope: ExpenseScope.global,
    createdAt: DateTime(2026, 5, 30),
    createdBy: createdBy,
  );
}

// #203 S2 PR1: an itemized expense — persists AS exact + a splitExplanation.
// Its distribution sums to the total (12.500) so the exact-split sync check
// passes on save.
Expense _itemizedExpense() {
  return Expense(
    id: 'expense-1',
    tripId: 'event-1',
    payerParticipantId: 'uid-yasmin',
    amount: Decimal.parse('12.500'),
    currency: 'OMR',
    description: 'Dinner',
    scope: ExpenseScope.global,
    createdAt: DateTime(2026, 5, 30),
    createdBy: 'uid-yasmin',
    splitMode: SplitMode.exact,
    splitDistribution: {
      'uid-yasmin': Decimal.parse('8.500'),
      'uid-layla': Decimal.parse('4.000'),
    },
    splitExplanation: const SplitExplanation(
      items: [
        SplitItem(
          label: 'Tagine',
          amountFils: 8500,
          participantIds: ['uid-yasmin'],
        ),
        SplitItem(
          label: 'Mint tea',
          amountFils: 4000,
          participantIds: ['uid-yasmin', 'uid-layla'],
        ),
      ],
    ),
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
