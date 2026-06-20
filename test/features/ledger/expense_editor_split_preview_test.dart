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
import 'package:safar/features/ledger/providers/category_provider.dart';
import 'package:safar/features/ledger/widgets/expense_editor_body.dart';
import 'package:safar/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// #242 — the "Split between" preview must show each person's REAL owed amount
/// for shares/exact/percent (true WYSIWYG), not the misleading equal figure.
/// Equal splits are unchanged. Pumps the editor in EDIT mode so the seeded
/// expense's splitMode/splitDistribution drive the preview immediately.
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

void main() {
  Future<void> pumpEditor(WidgetTester tester, Expense initial) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          currentUserIdProvider.overrideWithValue('uid-yasmin'),
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

  Expense expenseWith({
    required SplitMode mode,
    Map<String, Decimal>? distribution,
    required String amount,
  }) =>
      Expense(
        id: 'expense-1',
        tripId: 'event-1',
        payerParticipantId: 'uid-yasmin',
        amount: Decimal.parse(amount),
        scope: ExpenseScope.global,
        createdAt: DateTime(2026, 5, 30),
        createdBy: 'uid-yasmin',
        splitMode: mode,
        splitDistribution: distribution,
      );

  testWidgets('shares 2:1 → preview shows real 6.000 / 3.000, not equal 4.500',
      (tester) async {
    await pumpEditor(
      tester,
      expenseWith(
        mode: SplitMode.shares,
        amount: '9.000',
        distribution: {
          'uid-yasmin': Decimal.fromInt(2),
          'uid-layla': Decimal.fromInt(1),
        },
      ),
    );

    expect(find.text('OMR 6.000'), findsWidgets);
    expect(find.text('OMR 3.000'), findsWidgets);
    // The misleading equal figure (9.000 / 2) must NOT appear on a tile.
    expect(find.text('OMR 4.500'), findsNothing);
    // The "{amount} each" chip is replaced for non-equal modes.
    expect(find.textContaining('each'), findsNothing);
    expect(find.text('Amounts vary per person.'), findsOneWidget);
  });

  testWidgets('percent 60/40 → preview shows 6.000 / 4.000 (not 60.000 / 40.000)',
      (tester) async {
    await pumpEditor(
      tester,
      expenseWith(
        mode: SplitMode.percent,
        amount: '10.000',
        distribution: {
          'uid-yasmin': Decimal.parse('60'),
          'uid-layla': Decimal.parse('40'),
        },
      ),
    );

    expect(find.text('OMR 6.000'), findsWidgets);
    expect(find.text('OMR 4.000'), findsWidgets);
    expect(find.text('OMR 60.000'), findsNothing); // percent ≠ currency
    expect(find.text('Amounts vary per person.'), findsOneWidget);
  });

  testWidgets('exact split → preview echoes the entered amounts verbatim',
      (tester) async {
    await pumpEditor(
      tester,
      expenseWith(
        mode: SplitMode.exact,
        amount: '9.000',
        distribution: {
          'uid-yasmin': Decimal.parse('1.500'),
          'uid-layla': Decimal.parse('7.500'),
        },
      ),
    );

    expect(find.text('OMR 1.500'), findsWidgets);
    expect(find.text('OMR 7.500'), findsWidgets);
    expect(find.text('OMR 4.500'), findsNothing);
    expect(find.text('Amounts vary per person.'), findsOneWidget);
  });

  testWidgets('equal split is UNCHANGED — uniform "each" amount + chip',
      (tester) async {
    await pumpEditor(
      tester,
      expenseWith(mode: SplitMode.equally, amount: '9.000'),
    );

    // Both tiles show the uniform 4.500, and the "each" chip remains.
    expect(find.text('OMR 4.500'), findsWidgets);
    expect(find.textContaining('each'), findsWidgets);
    expect(find.text('Amounts vary per person.'), findsNothing);
  });
}
