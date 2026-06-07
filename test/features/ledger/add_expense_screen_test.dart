import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:safar/core/models/split_mode.dart';
import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/ledger/models/expense_category_model.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/providers/category_provider.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';
import 'package:safar/features/ledger/screens/add_expense_screen.dart';
import 'package:safar/features/ledger/services/expense_service.dart';
import 'package:safar/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockExpenseService extends Mock implements ExpenseService {}

void main() {
  testWidgets('renders Add Expense as a single-page wireframe form', (
    tester,
  ) async {
    await _pumpAddExpenseScreen(tester);

    expect(find.text('Add expense'), findsOneWidget);
    expect(find.text('AMOUNT · OMR'), findsOneWidget);
    expect(find.text('Description'), findsOneWidget);
    expect(find.text('Category'), findsOneWidget);
    expect(find.text('Paid by'), findsOneWidget);
    expect(find.text('Split between'), findsOneWidget);
    expect(find.text('Where'), findsOneWidget);
  });

  testWidgets('accepts Arabic keyboard digits in the amount field', (
    tester,
  ) async {
    await _pumpAddExpenseScreen(tester);

    await tester.enterText(find.byType(TextField).first, '١٢٫٣٤٥');
    await tester.pump();

    expect(find.text('12'), findsOneWidget);
    expect(find.text('.345'), findsOneWidget);
  });

  testWidgets('renders decimal fraction left-to-right under Arabic locale', (
    tester,
  ) async {
    await _pumpAddExpenseScreen(tester, locale: const Locale('ar'));

    await tester.enterText(find.byType(TextField).first, '٠٫٥');
    await tester.pump();

    // Padded to OMR's 3dp precision (#156); still LTR.
    final fractionText = find.text('.500');
    expect(fractionText, findsOneWidget);
    expect(Directionality.of(tester.element(fractionText)), TextDirection.ltr);
  });

  testWidgets('renders the amount label left-to-right under Arabic locale', (
    tester,
  ) async {
    await _pumpAddExpenseScreen(tester, locale: const Locale('ar'));

    final labelText = find.text('المبلغ · OMR');
    expect(labelText, findsOneWidget);
    // RED today: the label sits outside the hero's LTR Directionality, so the
    // composite 'المبلغ · OMR' inherits RTL and scrambles (#150).
    expect(Directionality.of(tester.element(labelText)), TextDirection.ltr);
  });

  testWidgets(
    'amount field disables interactive selection (no stuck handles)',
    (tester) async {
      await _pumpAddExpenseScreen(tester);

      final field = tester.widget<TextField>(find.byType(TextField).first);
      // RED today: enableInteractiveSelection is null (default true), so the
      // transparent overlay field shows iOS selection handles over the label.
      expect(field.enableInteractiveSelection, isFalse);
    },
  );

  testWidgets(
    'displayed amount pads trailing zeros to currency precision (#156)',
    (tester) async {
      await _pumpAddExpenseScreen(tester);

      await tester.enterText(find.byType(TextField).first, '2.5');
      await tester.pump();

      // RED today: the hero shows the raw '.5', mismatching the 3dp shown
      // everywhere else. The pad is display-only…
      expect(find.text('.500'), findsOneWidget);
      // …the (transparent) controller — the source of the persisted Decimal —
      // still holds the raw '2.5', so the write path is provably untouched.
      final field = tester.widget<TextField>(find.byType(TextField).first);
      expect(field.controller?.text, '2.5');
    },
  );

  testWidgets('default zero is not padded (#156)', (tester) async {
    await _pumpAddExpenseScreen(tester);
    // The untouched default stays a clean 'OMR 0', not 'OMR 0.000'.
    expect(find.text('.000'), findsNothing);
  });

  testWidgets('split-preview tile shows the per-person amount in full, LTR (#151)', (
    tester,
  ) async {
    await _pumpAddExpenseScreen(tester, locale: const Locale('ar'));

    await tester.enterText(find.byType(TextField).first, '5');
    await tester.pump();

    // each = 5 / 2 participants = 2.500. Money now renders code-first 'OMR 2.500'
    // (#144) — the Latin code + Western digits is itself what stops the bidi
    // scrambling this test guards; it must still show in full (no ellipsis) and
    // be wrapped LTR. The summary line is 'OMR 2.500 لكل شخص' (different exact
    // string), so find.text('OMR 2.500') matches only the per-tile amount(s).
    final amount = find.text('OMR 2.500');
    expect(amount, findsWidgets);
    // RED today: the amount Text has overflow: ellipsis and no LTR wrapper.
    expect(
      tester.widget<Text>(amount.first).overflow,
      isNot(TextOverflow.ellipsis),
    );
    expect(Directionality.of(tester.element(amount.first)), TextDirection.ltr);
  });

  testWidgets('selects the default zero when amount field is focused', (
    tester,
  ) async {
    await _pumpAddExpenseScreen(tester);

    final amountField = tester.widget<TextField>(find.byType(TextField).first);

    await tester.tap(find.byType(TextField).first);
    await tester.pump();

    expect(
      amountField.controller?.selection,
      const TextSelection(baseOffset: 0, extentOffset: 1),
    );
  });

  testWidgets('one eligible participant shows one coherent split state (#152)', (
    tester,
  ) async {
    await _pumpAddExpenseScreen(tester, event: _soloEvent);

    await tester.enterText(find.byType(TextField).first, '5');
    await tester.pump();

    // The method card correctly notes a split method needs 2+ people…
    expect(find.text('Pick at least two people to split.'), findsOneWidget);
    // …so the preview must NOT simultaneously claim a finished "1 way · X each"
    // split. RED today: editorSplitSummary renders "Equally · 1 way" and
    // editorEachAmount renders "5.000 each".
    expect(find.textContaining('1 way'), findsNothing);
    expect(find.textContaining('each'), findsNothing);
  });

  testWidgets('submits a new expense with current user creator metadata', (
    tester,
  ) async {
    final service = _MockExpenseService();
    when(
      () => service.addExpense(
        groupId: 'group-1',
        eventId: 'event-1',
        payerParticipantId: 'uid-yasmin',
        amount: Decimal.parse('12.5'),
        description: null,
        scope: ExpenseScope.global,
        customSplitParticipants: null,
        splitMode: SplitMode.equally,
        splitDistribution: null,
        categoryId: null,
        createdBy: 'uid-yasmin',
      ),
    ).thenAnswer((_) async => _expense);

    await _pumpAddExpenseScreen(tester, expenseService: service);

    await tester.enterText(find.byType(TextField).first, '12.5');
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Expense Saved'), findsOneWidget);
    verify(
      () => service.addExpense(
        groupId: 'group-1',
        eventId: 'event-1',
        payerParticipantId: 'uid-yasmin',
        amount: Decimal.parse('12.5'),
        description: null,
        scope: ExpenseScope.global,
        customSplitParticipants: null,
        splitMode: SplitMode.equally,
        splitDistribution: null,
        categoryId: null,
        createdBy: 'uid-yasmin',
      ),
    ).called(1);
  });

  testWidgets('rejects zero amounts before submit', (tester) async {
    await _pumpAddExpenseScreen(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pump();

    expect(find.text('Amount must be greater than zero'), findsOneWidget);
  });

  testWidgets('rejects submit when the current uid is not an event participant', (
    tester,
  ) async {
    await _pumpAddExpenseScreen(tester, event: _eventWithoutCurrentUser);

    await tester.enterText(find.byType(TextField).first, '4');
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pump();

    expect(
      find.text('Could not identify your participant record.'),
      findsOneWidget,
    );
  });

  testWidgets('shows a snackbar when add expense fails', (tester) async {
    final service = _MockExpenseService();
    when(
      () => service.addExpense(
        groupId: 'group-1',
        eventId: 'event-1',
        payerParticipantId: 'uid-yasmin',
        amount: Decimal.parse('7'),
        description: null,
        scope: ExpenseScope.global,
        customSplitParticipants: null,
        splitMode: SplitMode.equally,
        splitDistribution: null,
        categoryId: null,
        createdBy: 'uid-yasmin',
      ),
    ).thenThrow(StateError('offline'));

    await _pumpAddExpenseScreen(tester, expenseService: service);

    await tester.enterText(find.byType(TextField).first, '7');
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.text('Failed to add expense: Bad state: offline'),
      findsOneWidget,
    );
  });
}

/// A single-participant event: the split preview and the split-method card
/// must not contradict each other at count == 1 (#152).
final _soloEvent = Event(
  id: 'event-1',
  name: 'Solo trip',
  type: EventType.trip,
  groupId: 'group-1',
  createdBy: 'uid-yasmin',
  participantIds: const ['uid-yasmin'],
  participantNames: const {'uid-yasmin': 'Yasmin Khan'},
  modules: const EventModules(),
  startDate: DateTime(2026, 3, 21),
  createdAt: DateTime(2026, 3, 20),
);

Future<void> _pumpAddExpenseScreen(
  WidgetTester tester, {
  Locale locale = const Locale('en'),
  Event? event,
  ExpenseService? expenseService,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        currentUserIdProvider.overrideWithValue('uid-yasmin'),
        if (expenseService != null)
          expenseServiceProvider.overrideWithValue(expenseService),
        eventDetailProvider((
          groupId: 'group-1',
          eventId: 'event-1',
        )).overrideWith((ref) => Stream.value(event ?? _event)),
        tripCategoriesProvider(
          'event-1',
        ).overrideWith((ref) => Stream.value(_categories)),
      ],
      child: MaterialApp(
        locale: locale,
        theme: AppTheme.lightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const AddExpenseScreen(groupId: 'group-1', eventId: 'event-1'),
      ),
    ),
  );

  await tester.pumpAndSettle();
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

final _eventWithoutCurrentUser = Event(
  id: 'event-1',
  name: 'Marrakech, four ways',
  type: EventType.trip,
  groupId: 'group-1',
  createdBy: 'uid-layla',
  participantIds: const ['uid-layla'],
  participantNames: const {'uid-layla': 'Layla Hassan'},
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
  ExpenseCategory(
    id: 'transit',
    tripId: 'event-1',
    name: 'Transit',
    icon: 'transport',
    color: '#8C6A2F',
    createdAt: DateTime(2026, 1, 1),
  ),
];

final _expense = Expense(
  id: 'expense-1',
  tripId: 'event-1',
  payerParticipantId: 'uid-yasmin',
  amount: Decimal.parse('12.5'),
  scope: ExpenseScope.global,
  createdAt: DateTime(2026, 5, 31),
  createdBy: 'uid-yasmin',
);
