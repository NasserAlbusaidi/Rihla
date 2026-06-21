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

  Finder howCard() => find.byKey(const Key('split_mode_card'));

  testWidgets('reopening an itemized expense shows the Itemized How card',
      (tester) async {
    await pumpEditor(tester, _itemizedExpense());

    // The How card reads "Itemized" + the item count, not "Exact".
    expect(
      find.descendant(of: howCard(), matching: find.text('Itemized')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: howCard(), matching: find.text('4 items')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: howCard(), matching: find.text('Exact')),
      findsNothing,
    );
  });

  testWidgets('opening How on an itemized expense preselects the itemized tab',
      (tester) async {
    await pumpEditor(tester, _itemizedExpense());

    // Tap the How section's "Customise" action.
    await tester.tap(find.descendant(
      of: find.ancestor(
        of: find.text('How'),
        matching: find.byType(Column),
      ).first,
      matching: find.text('Customise'),
    ).first);
    await tester.pumpAndSettle();

    // The sheet opened on the Itemized tab with the seeded rows.
    expect(find.byKey(const Key('itemized_label_0')), findsOneWidget);
    expect(find.byKey(const Key('itemized_label_3')), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Pastries'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Latte'), findsOneWidget);
  });

  testWidgets(
      'switching to Equally and applying clears the itemized How card',
      (tester) async {
    await pumpEditor(tester, _itemizedExpense());

    // Open the How sheet.
    await tester.tap(find.descendant(
      of: find.ancestor(
        of: find.text('How'),
        matching: find.byType(Column),
      ).first,
      matching: find.text('Customise'),
    ).first);
    await tester.pumpAndSettle();

    // Switch to the plain Equal mode and apply (chip label = splitModeEqually).
    await tester.tap(find.text('Equal'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('split_sheet_apply')));
    await tester.pumpAndSettle();

    // The How card is no longer itemized — it reverts to the equal label, and
    // "Itemized" / the item-count subtitle are gone.
    expect(
      find.descendant(of: howCard(), matching: find.text('Itemized')),
      findsNothing,
    );
    expect(
      find.descendant(of: howCard(), matching: find.text('4 items')),
      findsNothing,
    );
    expect(
      find.descendant(of: howCard(), matching: find.text('Equal')),
      findsOneWidget,
    );
  });
}
