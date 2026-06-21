import 'dart:async';

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

/// #627 — `_SplitPreviewCard` must memoize the disambiguation name map (keyed on
/// event identity) and the `allocateExpenseOwed` allocation (keyed on the
/// allocation inputs), instead of recomputing both on every amount keystroke.
///
/// The two invariants the memo must NOT break (display-only, but money-faithful):
///   • owed figures always reflect the live inputs (no stale cache), and
///   • the name map refreshes on a same-id rename (Event.== is id-only — #106).
/// Plus the win itself: a pure amount keystroke recomputes owed but NOT the name
/// map.
Event eventWith({Map<String, String>? names}) => Event(
  id: 'event-1',
  name: 'Marrakech',
  type: EventType.trip,
  groupId: 'group-1',
  createdBy: 'uid-yasmin',
  participantIds: const ['uid-yasmin', 'uid-layla'],
  participantNames:
      names ??
      const {'uid-yasmin': 'Yasmin Khan', 'uid-layla': 'Layla Hassan'},
  modules: const EventModules(),
  startDate: DateTime(2026, 3, 21),
  createdAt: DateTime(2026, 3, 20),
);

void main() {
  setUp(() {
    debugSplitPreviewNameComputes = 0;
    debugSplitPreviewOwedComputes = 0;
  });

  Future<void> pumpEditor(
    WidgetTester tester, {
    required Expense initial,
    Stream<Event>? eventStream,
    bool settle = true,
  }) async {
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
          )).overrideWith((ref) => eventStream ?? Stream.value(eventWith())),
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
    if (settle) await tester.pumpAndSettle();
  }

  Expense expenseWith({
    required SplitMode mode,
    Map<String, Decimal>? distribution,
    required String amount,
  }) => Expense(
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

  testWidgets('owed updates when the amount changes (no stale cache)', (
    tester,
  ) async {
    await pumpEditor(
      tester,
      initial: expenseWith(
        mode: SplitMode.shares,
        amount: '9.000',
        distribution: {
          'uid-yasmin': Decimal.fromInt(2),
          'uid-layla': Decimal.fromInt(1),
        },
      ),
    );
    // shares 2:1 of 9.000 → 6.000 / 3.000
    expect(find.text('OMR 6.000'), findsWidgets);
    expect(find.text('OMR 3.000'), findsWidgets);

    await tester.enterText(find.byType(TextField).first, '12.000');
    await tester.pumpAndSettle();

    // shares 2:1 of 12.000 → 8.000 / 4.000; the stale figures must be gone.
    expect(find.text('OMR 8.000'), findsWidgets);
    expect(find.text('OMR 4.000'), findsWidgets);
    expect(find.text('OMR 6.000'), findsNothing);
    expect(find.text('OMR 3.000'), findsNothing);
  });

  testWidgets('name map refreshes on a same-id participant rename (#106)', (
    tester,
  ) async {
    final controller = StreamController<Event>();
    addTearDown(controller.close);

    await pumpEditor(
      tester,
      initial: expenseWith(mode: SplitMode.equally, amount: '9.000'),
      eventStream: controller.stream,
      settle: false,
    );
    controller.add(eventWith());
    await tester.pumpAndSettle();

    // 'Layla' is a non-payer/non-creator name → it shows ONLY in the preview
    // tile (compacted first name), isolating this assertion to the memoized map.
    expect(find.text('Layla'), findsOneWidget);

    // Same event id, renamed participant → a fresh Event instance. Event.== is
    // id-only, so a ==-keyed cache would keep showing the stale name.
    controller.add(
      eventWith(
        names: const {
          'uid-yasmin': 'Yasmin Khan',
          'uid-layla': 'Mariam Hassan',
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Mariam'), findsOneWidget);
    expect(find.text('Layla'), findsNothing);
  });

  testWidgets('amount keystroke recomputes owed but NOT the name map', (
    tester,
  ) async {
    await pumpEditor(
      tester,
      initial: expenseWith(
        mode: SplitMode.shares,
        amount: '9.000',
        distribution: {
          'uid-yasmin': Decimal.fromInt(2),
          'uid-layla': Decimal.fromInt(1),
        },
      ),
    );
    final namesAfterLoad = debugSplitPreviewNameComputes;
    final owedAfterLoad = debugSplitPreviewOwedComputes;
    expect(namesAfterLoad, greaterThanOrEqualTo(1));
    expect(owedAfterLoad, greaterThanOrEqualTo(1));

    await tester.enterText(find.byType(TextField).first, '12.000');
    await tester.pumpAndSettle();

    // The win: the name map is event-derived; the event is unchanged while
    // typing, so it must NOT be recomputed.
    expect(debugSplitPreviewNameComputes, namesAfterLoad);
    // The amount changed → owed must reallocate (fresh, non-stale figures).
    expect(debugSplitPreviewOwedComputes, greaterThan(owedAfterLoad));
  });

  testWidgets('equal split never runs the owed allocation', (tester) async {
    await pumpEditor(
      tester,
      initial: expenseWith(mode: SplitMode.equally, amount: '9.000'),
    );
    expect(find.text('OMR 4.500'), findsWidgets); // 9.000 / 2
    expect(debugSplitPreviewOwedComputes, 0);

    await tester.enterText(find.byType(TextField).first, '12.000');
    await tester.pumpAndSettle();

    expect(find.text('OMR 6.000'), findsWidgets); // 12.000 / 2
    expect(debugSplitPreviewOwedComputes, 0);
  });
}
