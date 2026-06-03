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
}
