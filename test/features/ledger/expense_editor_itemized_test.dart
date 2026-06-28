import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/models/split_mode.dart';
import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/ledger/models/expense_category_model.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/models/split_explanation.dart';
import 'package:safar/features/ledger/providers/category_provider.dart';
import 'package:safar/features/ledger/widgets/expense_editor_body.dart';
import 'package:safar/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// #203 S2 PR2 — the editor body wires the Itemized option into the "How" sheet
/// and reconstructs it on reopen from the stored splitExplanation.
final _event = Event(
  id: 'event-1',
  name: 'Coffee run',
  type: EventType.trip,
  groupId: 'group-1',
  createdBy: 'n',
  participantIds: const ['h', 'k', 'n', 's'],
  participantNames: const {
    'h': 'Hessa',
    'k': 'Khalid',
    'n': 'Nasser',
    's': 'Sara',
  },
  modules: const EventModules(),
  startDate: DateTime(2026, 3, 21),
  createdAt: DateTime(2026, 3, 20),
);

const _items = [
  SplitItem(
    label: 'Pastries',
    amountFils: 1200,
    participantIds: ['h', 'k', 'n', 's'],
  ),
  SplitItem(label: 'Americano', amountFils: 1600, participantIds: ['n']),
  SplitItem(label: 'Espresso', amountFils: 1200, participantIds: ['s']),
  SplitItem(label: 'Latte', amountFils: 2100, participantIds: ['k']),
];

Expense _itemizedExpense() => Expense(
      id: 'expense-1',
      tripId: 'event-1',
      payerParticipantId: 'n',
      amount: Decimal.parse('6.100'),
      scope: ExpenseScope.global,
      createdAt: DateTime(2026, 5, 30),
      createdBy: 'n',
      splitMode: SplitMode.exact,
      splitDistribution: {
        'n': Decimal.parse('1.900'),
        's': Decimal.parse('1.500'),
        'k': Decimal.parse('2.400'),
        'h': Decimal.parse('0.300'),
      },
      splitExplanation: const SplitExplanation(items: _items),
    );

/// #605 — an itemized expense that also carries a bill-level adjustment.
/// Pastries 5.100 (1.275 each) + Service 1.000 equal (0.250 each) = 1.525 each,
/// Σ = 6.100, so the seeded sheet reconciles out of the box.
Expense _itemizedExpenseWithAdjustment() => Expense(
      id: 'expense-2',
      tripId: 'event-1',
      payerParticipantId: 'n',
      amount: Decimal.parse('6.100'),
      scope: ExpenseScope.global,
      createdAt: DateTime(2026, 5, 30),
      createdBy: 'n',
      splitMode: SplitMode.exact,
      splitDistribution: {
        'h': Decimal.parse('1.525'),
        'k': Decimal.parse('1.525'),
        'n': Decimal.parse('1.525'),
        's': Decimal.parse('1.525'),
      },
      splitExplanation: const SplitExplanation(
        items: [
          SplitItem(
            label: 'Pastries',
            amountFils: 5100,
            participantIds: ['h', 'k', 'n', 's'],
          ),
        ],
        adjustments: [
          SplitAdjustment(type: 'service', amountFils: 1000, allocation: 'equal'),
        ],
      ),
    );

void main() {
  Future<void> pumpEditor(WidgetTester tester, Expense initial) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          currentUserIdProvider.overrideWithValue('n'),
          eventDetailProvider((
            groupId: 'group-1',
            eventId: 'event-1',
          )).overrideWith((ref) => Stream.value(_event)),
          tripCategoriesProvider(
            'event-1',
          ).overrideWith((ref) => Stream.value(const <ExpenseCategory>[])),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ExpenseEditorBody(
              groupId: 'group-1',
              eventId: 'event-1',
              mode: ExpenseEditorMode.edit,
              currency: 'OMR',
              initial: initial,
              onSubmit: (_) async {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  // #485: the itemized state shows on the Split card's keyed summary line, and
  // the weights sheet opens from the card's mode segment (an itemized expense is
  // persisted as exact, so "Exact" reopens it on the itemized tab).
  Finder summary() => find.byKey(const Key('split_card_summary'));

  Future<void> openHow(WidgetTester tester) async {
    final exact = find.text('Exact');
    await tester.ensureVisible(exact);
    await tester.tap(exact);
    await tester.pumpAndSettle();
  }

  testWidgets('reopening an itemized expense shows the Itemized summary',
      (tester) async {
    await pumpEditor(tester, _itemizedExpense());

    // The summary reads "Itemized" + the item count. (A broken itemized→exact
    // regression would render "amounts vary" here, failing the checks below.)
    expect(
      find.descendant(of: summary(), matching: find.text('Itemized')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: summary(), matching: find.text('4 items')),
      findsOneWidget,
    );
  });

  testWidgets('opening How on an itemized expense preselects the itemized tab',
      (tester) async {
    await pumpEditor(tester, _itemizedExpense());
    await openHow(tester);

    // The sheet opened on the Itemized tab with the seeded rows.
    expect(find.byKey(const Key('itemized_label_0')), findsOneWidget);
    expect(find.byKey(const Key('itemized_label_3')), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Pastries'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Latte'), findsOneWidget);
  });

  testWidgets(
      'switching to Equally and applying clears the itemized summary',
      (tester) async {
    await pumpEditor(tester, _itemizedExpense());
    await openHow(tester);

    // Inside the sheet, switch to the plain Equal tab and apply. The card's mode
    // segment also shows "Equal" (behind the sheet), so target the sheet's tab
    // via .last.
    await tester.tap(find.text('Equal').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('split_sheet_apply')));
    await tester.pumpAndSettle();

    // The summary is no longer itemized — it reverts to the equal "each" line.
    expect(
      find.descendant(of: summary(), matching: find.text('Itemized')),
      findsNothing,
    );
    expect(
      find.descendant(of: summary(), matching: find.text('4 items')),
      findsNothing,
    );
    expect(
      find.descendant(of: summary(), matching: find.textContaining('each')),
      findsOneWidget,
    );
  });

  testWidgets('reopen seeds the adjustment row and apply retains it (#605)',
      (tester) async {
    await pumpEditor(tester, _itemizedExpenseWithAdjustment());

    await openHow(tester);
    // The seeded adjustment row is present → initialAdjustments threading works.
    expect(find.byKey(const Key('itemized_adjustment_0')), findsOneWidget);
    final apply = tester.widget<ElevatedButton>(
      find.byKey(const Key('split_sheet_apply')),
    );
    expect(apply.onPressed, isNotNull, reason: 'seed reconciles → Apply enabled');
    await tester.tap(find.byKey(const Key('split_sheet_apply')));
    await tester.pumpAndSettle();

    // Reopen — the adjustment survived apply (bridge no longer drops it).
    await openHow(tester);
    expect(find.byKey(const Key('itemized_adjustment_0')), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });
}
