import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/models/split_mode.dart';
import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/utils/name_validators.dart';
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
              currency: 'OMR',
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
              currency: 'OMR',
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

      // #485: scope is picked inline on the Split card. Tap "Some people"
      // (custom): the current participant is seeded as the sole (deselectable)
      // selection — no separate Customise sheet / Apply step anymore.
      final somePeople = find.text('Some people');
      await tester.ensureVisible(somePeople);
      await tester.tap(somePeople);
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget);

      // Save: the seeded self must persist into the write payload — the
      // calculator splits over exactly this set.
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(captured, isNotNull);
      expect(captured!.scope, ExpenseScope.custom);
      expect(captured!.customSplitParticipants, ['uid-yasmin']);
    },
  );

  // #250 — an EXACT split is absolute amounts; if the amount is changed after
  // the split was set, the stored distribution no longer sums to the total and
  // the calculator would SILENTLY re-split equally. _submit must reject this
  // (warn + don't persist) so the user can fix it.
  testWidgets(
    '#250: amount-only edit that drifts an EXACT split blocks save with a warning',
    (tester) async {
      final payload = await editAmountAndSave(
        tester,
        initial: expenseWithSplit(
          mode: SplitMode.exact,
          distribution: {
            'uid-yasmin': Decimal.parse('8.000'),
            'uid-layla': Decimal.parse('4.000'),
          },
        ),
        newAmount: '20', // 8+4=12 != 20 → drift > tolerance
      );

      expect(payload, isNull, reason: 'stale exact split must not persist');
      expect(find.textContaining('no longer add up'), findsOneWidget);
    },
  );

  // #528 — an amount whose integer subunits would exceed Number.MAX_SAFE_INTEGER
  // (2^53-1) must be blocked at submit. Above it the Dart int64 amountFils reads
  // back as a divergent JS number server-side, breaking balance-oracle parity.
  testWidgets(
    '#528: an amount over the safe-subunit cap blocks save with a warning',
    (tester) async {
      // A 14-digit amount renders very wide in the amount hero; widen the test
      // surface so layout completes and the submit-time guard (the unit under
      // test) actually runs, instead of failing on a hero RenderFlex overflow.
      tester.view.physicalSize = const Size(2400, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final payload = await editAmountAndSave(
        tester,
        initial: expenseWithSplit(
          mode: SplitMode.shares,
          distribution: {
            'uid-yasmin': Decimal.fromInt(1),
            'uid-layla': Decimal.fromInt(1),
          },
        ),
        // OMR 1e13 × 1000 scale = 1e16 subunits > 2^53-1.
        newAmount: '10000000000000',
      );

      expect(payload, isNull, reason: 'over-cap amount must not persist');
      expect(find.textContaining('too large'), findsOneWidget);
    },
  );

  testWidgets(
    'single-person custom split keeps the non-equal split gate disabled (#247)',
    (tester) async {
      // custom {Layla}, payer Yasmin → _splitParticipantIds is [Layla] (no
      // payer insert) → length 1 → the Split card shows the "pick at least two"
      // gate (#152) and disables the mode segment, never a finished split.
      // Re-adding the payer insert would wrongly re-enable a non-equal split
      // over a single person.
      await pumpEditor(tester, initial: customExpense(const ['uid-layla']));

      expect(
        find.text('Pick at least two people to split.'),
        findsOneWidget,
      );
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

  testWidgets(
    '#250: an EXACT split that still sums to the amount saves normally',
    (tester) async {
      final payload = await editAmountAndSave(
        tester,
        initial: expenseWithSplit(
          mode: SplitMode.exact,
          distribution: {
            'uid-yasmin': Decimal.parse('8.000'),
            'uid-layla': Decimal.parse('4.000'),
          },
        ),
        newAmount: '12', // re-entered same total → sum matches → valid
      );

      expect(payload, isNotNull);
      expect(payload!.splitMode, SplitMode.exact);
      expect(payload.splitDistribution, {
        'uid-yasmin': Decimal.parse('8.000'),
        'uid-layla': Decimal.parse('4.000'),
      });
    },
  );

  // #220 — inline free-text validation on the note/description field. The write
  // path stores controller.text.trim(); security/firestore.rules' validFreeText
  // rejects >280 chars or control chars with an opaque permission-denied, so the
  // editor now surfaces a friendly inline message as the user types instead.
  Expense globalExpense() => Expense(
    id: 'expense-1',
    tripId: 'event-1',
    payerParticipantId: 'uid-yasmin',
    amount: Decimal.parse('12.000'),
    scope: ExpenseScope.global,
    createdAt: DateTime(2026, 5, 30),
    createdBy: 'uid-yasmin',
    splitMode: SplitMode.equally,
  );

  testWidgets('#220: an over-length note shows an inline error', (tester) async {
    await pumpEditor(tester, initial: globalExpense());
    await tester.enterText(
      find.widgetWithText(TextField, 'Description'),
      'a' * (kFreeTextMaxLength + 1),
    );
    await tester.pump();
    expect(find.text('Keep it to 280 characters or fewer.'), findsOneWidget);
  });

  testWidgets('#220: a control character in the note shows an inline error', (
    tester,
  ) async {
    // The single-line field strips \n/\r on input, but a non-line-terminator
    // control char (DEL) can still arrive (e.g. paste) — the validator catches
    // it and the editor surfaces the message.
    await pumpEditor(tester, initial: globalExpense());
    await tester.enterText(
      find.widgetWithText(TextField, 'Description'),
      'del${String.fromCharCode(0x7f)}here',
    );
    await tester.pump();
    expect(
      find.text('Remove line breaks or special characters.'),
      findsOneWidget,
    );
  });

  testWidgets('#220: fixing the note clears the inline error', (tester) async {
    await pumpEditor(tester, initial: globalExpense());
    final note = find.widgetWithText(TextField, 'Description');
    await tester.enterText(note, 'a' * (kFreeTextMaxLength + 1));
    await tester.pump();
    expect(find.text('Keep it to 280 characters or fewer.'), findsOneWidget);

    await tester.enterText(note, 'Dinner at the souq');
    await tester.pump();
    expect(find.text('Keep it to 280 characters or fewer.'), findsNothing);
  });

  // #248 PR5 — the editor surfaces provenance (who ADDED / last EDITED) as a
  // compact byline under the description, distinct from the "Paid by" card.
  // Names embed inside "Added by …" so they never collide with the exact
  // first-name/full-name matchers elsewhere on the form.
  Expense provenanceExpense({
    required String createdBy,
    String lastEditedBy = '',
  }) => Expense(
    id: 'expense-1',
    tripId: 'event-1',
    payerParticipantId: 'uid-yasmin',
    amount: Decimal.parse('12.000'),
    description: 'Dinner',
    scope: ExpenseScope.global,
    createdAt: DateTime(2026, 5, 30),
    createdBy: createdBy,
    lastEditedBy: lastEditedBy,
    splitMode: SplitMode.equally,
  );

  testWidgets('#248 PR5: byline shows the creator when there is no later editor',
      (tester) async {
    await pumpEditor(tester, initial: provenanceExpense(createdBy: 'uid-yasmin'));

    expect(find.text('Added by Yasmin Khan'), findsOneWidget);
  });

  testWidgets('#248 PR5: byline names creator AND editor on a third-party edit',
      (tester) async {
    await pumpEditor(
      tester,
      initial: provenanceExpense(
        createdBy: 'uid-yasmin',
        lastEditedBy: 'uid-layla',
      ),
    );

    expect(
      find.text('Added by Yasmin Khan · edited by Layla Hassan'),
      findsOneWidget,
    );
  });

  testWidgets('#248 PR5: a self-edit shows only the creator (no "edited by")',
      (tester) async {
    await pumpEditor(
      tester,
      initial: provenanceExpense(
        createdBy: 'uid-yasmin',
        lastEditedBy: 'uid-yasmin',
      ),
    );

    expect(find.text('Added by Yasmin Khan'), findsOneWidget);
    expect(find.textContaining('edited by'), findsNothing);
  });

  testWidgets('#248 PR5: a legacy expense with no creator shows no byline',
      (tester) async {
    await pumpEditor(tester, initial: provenanceExpense(createdBy: ''));

    expect(find.textContaining('Added by'), findsNothing);
  });

  testWidgets('#248 PR5: add mode never shows a provenance byline',
      (tester) async {
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
              mode: ExpenseEditorMode.add,
              currency: 'OMR',
              onSubmit: (_) async {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Added by'), findsNothing);
  });

  // #203 S2 PR1 — the editor round-trips an itemized expense's splitExplanation
  // through the submit payload. PR1 has no UI to author it, so the only path is
  // edit mode reconstructing it from the initial expense. An amount-unchanged
  // save (so the exact-split sum check passes) must hand it back intact.
  testWidgets('#203 S2: edit mode round-trips splitExplanation into the payload',
      (tester) async {
    final initial = Expense(
      id: 'expense-1',
      tripId: 'event-1',
      payerParticipantId: 'uid-yasmin',
      amount: Decimal.parse('12.000'),
      scope: ExpenseScope.global,
      createdAt: DateTime(2026, 5, 30),
      createdBy: 'uid-yasmin',
      splitMode: SplitMode.exact,
      splitDistribution: {
        'uid-yasmin': Decimal.parse('8.000'),
        'uid-layla': Decimal.parse('4.000'),
      },
      splitExplanation: const SplitExplanation(
        items: [
          SplitItem(
            label: 'Tagine',
            amountFils: 8000,
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

    final payload = await editAmountAndSave(
      tester,
      initial: initial,
      newAmount: '12', // unchanged total → exact sum check passes
    );

    expect(payload, isNotNull);
    expect(payload!.splitMode, SplitMode.exact);
    final explanation = payload.splitExplanation;
    expect(explanation, isNotNull);
    expect(explanation!.type, 'itemized');
    expect(explanation.items.length, 2);
    expect(explanation.items[0].label, 'Tagine');
    expect(explanation.items[0].amountFils, 8000);
    expect(explanation.items[1].participantIds, ['uid-yasmin', 'uid-layla']);
  });

  // #807: category is mandatory at creation (#787) — the section title must
  // announce it up front (asterisk), not only via the blocked-submit error.
  testWidgets('#807: add mode marks the Category section required',
      (tester) async {
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
              mode: ExpenseEditorMode.add,
              currency: 'OMR',
              onSubmit: (_) async {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Category *', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('#807: edit mode keeps the Category title unmarked (edits are '
      'exempt from the category mandate)', (tester) async {
    await pumpEditor(
      tester,
      initial: provenanceExpense(createdBy: 'uid-yasmin'),
    );

    expect(
      find.textContaining('Category *', findRichText: true),
      findsNothing,
    );
    expect(find.text('Category'), findsOneWidget);
  });

  testWidgets('#871 — the amount input itself carries the accessible name '
      '(not just a nearby decorative Text)', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpEditor(
      tester,
      initial: provenanceExpense(createdBy: 'uid-yasmin'),
    );

    final node = tester.getSemantics(find.bySemanticsLabel('AMOUNT · OMR'));
    expect(
      node.flagsCollection.isTextField,
      isTrue,
      reason:
          'TalkBack/VoiceOver must announce the name ON the edit box '
          '(WCAG 4.1.2); a sibling caption Text is not an accessible name.',
    );
    handle.dispose();
  });
}
