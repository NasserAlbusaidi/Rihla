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

// #224 — direct coverage for ExpenseEditorBody.
//
// Scope note (reconciled against code): most of the issue's "Proposed work" is
// already covered or unreachable in THIS widget —
//   * split-method distributions that sum to the amount, and the exact-split
//     residual -> alphabetically-last-recipient contract, live in the
//     BalanceCalculator / showCustomSplitSheet and are covered by
//     balance_calculations_test.dart (:93,:180), split_rounding_test.dart,
//     issue_195_exact_split_renormalize_boundary_test.dart, and
//     custom_split_sheet_test.dart;
//   * zero / payer-missing / submit-failure are covered by
//     add_expense_screen_test.dart (:217,:226,:241);
//   * the empty/non-numeric -> editorPleaseEnterValidAmount branch is
//     UNREACHABLE: _sanitizeAmount floors empty input to '0', so _amount is
//     always parseable (the zero path handles it instead);
//   * currency-scale OMR/JPY/USD entry is unreachable here — _tripCurrency is
//     hardcoded 'OMR' (gated by #61).
//
// The one genuine, reachable, money-sensitive gap: editing ONLY the amount of a
// non-equally expense must preserve splitMode + splitDistribution into the
// payload. Silently dropping the custom split would re-distribute everyone's
// share — a money-wrong regression. We pin it for shares and percent (weights
// independent of the total, so preservation across an amount edit is
// unambiguously correct).
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
  Future<ExpenseEditorPayload?> editAmountAndSave(
    WidgetTester tester, {
    required Expense initial,
    required String newAmount,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    ExpenseEditorPayload? captured;

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
              initial: initial,
              onSubmit: (payload) async => captured = payload,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Change ONLY the amount; leave the split untouched.
    await tester.enterText(find.byType(TextField).first, newAmount);
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pump(); // _submit runs through the awaited onSubmit
    await tester.pump(
      const Duration(milliseconds: 200),
    ); // drain HapticService.success()'s 100ms timer

    return captured;
  }

  Expense expenseWithSplit({
    required SplitMode mode,
    required Map<String, Decimal> distribution,
  }) => Expense(
    id: 'expense-1',
    tripId: 'event-1',
    payerParticipantId: 'uid-yasmin',
    amount: Decimal.parse('12.000'),
    scope: ExpenseScope.global,
    createdAt: DateTime(2026, 5, 30),
    createdBy: 'uid-yasmin',
    splitMode: mode,
    splitDistribution: distribution,
  );

  testWidgets('amount-only edit preserves a shares split + its distribution', (
    tester,
  ) async {
    final payload = await editAmountAndSave(
      tester,
      initial: expenseWithSplit(
        mode: SplitMode.shares,
        distribution: {
          'uid-yasmin': Decimal.fromInt(2),
          'uid-layla': Decimal.fromInt(1),
        },
      ),
      newAmount: '20',
    );

    expect(payload, isNotNull);
    expect(payload!.amount, Decimal.parse('20'));
    expect(payload.splitMode, SplitMode.shares);
    expect(payload.splitDistribution, {
      'uid-yasmin': Decimal.fromInt(2),
      'uid-layla': Decimal.fromInt(1),
    });
  });

  testWidgets('amount-only edit preserves a percent split + its distribution', (
    tester,
  ) async {
    final payload = await editAmountAndSave(
      tester,
      initial: expenseWithSplit(
        mode: SplitMode.percent,
        distribution: {
          'uid-yasmin': Decimal.parse('60'),
          'uid-layla': Decimal.parse('40'),
        },
      ),
      newAmount: '33.000',
    );

    expect(payload, isNotNull);
    expect(payload!.amount, Decimal.parse('33'));
    expect(payload.splitMode, SplitMode.percent);
    expect(payload.splitDistribution, {
      'uid-yasmin': Decimal.parse('60'),
      'uid-layla': Decimal.parse('40'),
    });
  });

  // #247 — the split preview must equal the persisted/calculated split, with no
  // payer auto-insertion. The preview tiles render FIRST names; the "Paid by"
  // card renders FULL names ("Yasmin Khan"), so an exact "Yasmin"/"Layla" match
  // isolates the split-preview tiles.
  Future<void> pumpEditor(
    WidgetTester tester, {
    required Expense initial,
    ValueChanged<ExpenseEditorPayload>? onSubmit,
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
              initial: initial,
              onSubmit: (payload) async => onSubmit?.call(payload),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Expense customExpense(List<String> customSplit) => Expense(
    id: 'expense-1',
    tripId: 'event-1',
    payerParticipantId: 'uid-yasmin',
    amount: Decimal.parse('12.000'),
    scope: ExpenseScope.custom,
    createdAt: DateTime(2026, 5, 30),
    createdBy: 'uid-yasmin',
    customSplitParticipants: customSplit,
    splitMode: SplitMode.equally,
    splitDistribution: null,
  );

  testWidgets(
    'custom-split preview shows exactly the persisted set, not the payer (#247)',
    (tester) async {
      // Payer = Yasmin (me), custom split = {Layla} only. The preview must show
      // ONLY Layla. Inserting the payer would lie that this is a 2-way split
      // while the ledger records the full amount on Layla — the #247 bug.
      await pumpEditor(tester, initial: customExpense(const ['uid-layla']));

      expect(find.text('Layla'), findsOneWidget);
      expect(find.text('Yasmin'), findsNothing);
    },
  );

  testWidgets(
    'empty custom split previews as the global set, mirroring the calculator (#247)',
    (tester) async {
      // Deselect-all custom set: BalanceCalculator falls back to a global split
      // over ALL participants, so the preview must show everyone — not "no
      // split" and not just the payer.
      await pumpEditor(tester, initial: customExpense(const []));

      expect(find.text('Yasmin'), findsOneWidget);
      expect(find.text('Layla'), findsOneWidget);
    },
  );

  testWidgets(
    'switching to custom scope seeds self and persists it on save (#247)',
    (tester) async {
      ExpenseEditorPayload? captured;
      await pumpEditor(
        tester,
        onSubmit: (payload) => captured = payload,
        initial: Expense(
          id: 'expense-1',
          tripId: 'event-1',
          payerParticipantId: 'uid-yasmin',
          amount: Decimal.parse('12.000'),
          scope: ExpenseScope.global,
          createdAt: DateTime(2026, 5, 30),
          createdBy: 'uid-yasmin',
          splitMode: SplitMode.equally,
        ),
      );

      // Open the "Split between" customise sheet (a 2+ participant global split
      // shows two "Customise" actions; the first is Split between).
      final customise = find.text('Customise').first;
      await tester.ensureVisible(customise);
      await tester.tap(customise);
      await tester.pumpAndSettle();

      // Switch to Custom scope: the current participant is seeded as the sole
      // (deselectable) selection.
      await tester.tap(find.text('Custom'));
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget);

      // Apply, then save: the seeded self must persist into the write payload —
      // the calculator splits over exactly this set.
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(captured, isNotNull);
      expect(captured!.scope, ExpenseScope.custom);
      expect(captured!.customSplitParticipants, ['uid-yasmin']);
    },
  );

  testWidgets(
    'single-person custom split keeps the non-equal split gate disabled (#247)',
    (tester) async {
      // custom {Layla}, payer Yasmin → _splitParticipantIds is [Layla] (no
      // payer insert) → length 1 → the "How" customise action stays disabled,
      // leaving only the "Split between" action. Re-adding the payer insert
      // would wrongly re-enable a non-equal split over a single person.
      await pumpEditor(tester, initial: customExpense(const ['uid-layla']));

      expect(find.text('Customise'), findsOneWidget);
    },
  );

  // #247 — pure seeding rule. Money-adjacent (decides who a custom split lands
  // on), so table-driven across the clean / guarded / no-op cases.
  group('seedCustomSplitOnScopeChange', () {
    test('seeds the current participant when entering an empty custom split', () {
      expect(
        seedCustomSplitOnScopeChange(
          newScope: ExpenseScope.custom,
          current: const <String>{},
          currentParticipantId: 'uid-yasmin',
        ),
        {'uid-yasmin'},
      );
    });

    test('does not seed when the participant id is unknown (null guard)', () {
      expect(
        seedCustomSplitOnScopeChange(
          newScope: ExpenseScope.custom,
          current: const <String>{},
          currentParticipantId: null,
        ),
        isEmpty,
      );
    });

    test('does not re-seed a non-empty custom set', () {
      expect(
        seedCustomSplitOnScopeChange(
          newScope: ExpenseScope.custom,
          current: const {'uid-layla'},
          currentParticipantId: 'uid-yasmin',
        ),
        {'uid-layla'},
      );
    });

    test('does not seed when switching to a non-custom scope', () {
      expect(
        seedCustomSplitOnScopeChange(
          newScope: ExpenseScope.global,
          current: const <String>{},
          currentParticipantId: 'uid-yasmin',
        ),
        isEmpty,
      );
    });
  });
}
