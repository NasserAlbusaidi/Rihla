import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:safar/core/models/split_mode.dart';
import 'package:safar/core/providers/connectivity_provider.dart';
import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/ledger/models/expense_category_model.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/models/split_explanation.dart';
import 'package:safar/features/ledger/providers/category_provider.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';
import 'package:safar/features/ledger/screens/edit_expense_screen.dart';
import 'package:safar/features/ledger/services/expense_service.dart';
import 'package:safar/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

// #1092: an edit-expense save must write ONLY field clusters the user actually
// dirtied in this editor session. A concurrent edit by another participant to an
// untouched field (delivered as a fresh remote emission while the editor is
// open) must survive the save instead of being reverted to the stale form value.
//
// Harness: a two-phase StreamController feeds eventExpensesProvider — v1 seeds
// the editor (initState freezes its pristine baseline), then v2 (the concurrent
// edit) lands as `original` in _save. `_RecordingExpenseService` captures the
// exact updateExpense named args so we can assert which clusters the write map
// carried (mocktail's `captured` orders named args unpredictably, so a Fake is
// the robust capture surface here).

/// Records the last [updateExpense] call's named arguments. A [Fake] so any
/// un-overridden method throws — only `updateExpense` is exercised here.
class _RecordingExpenseService extends Fake implements ExpenseService {
  int callCount = 0;
  Decimal? amountArg;
  String? descriptionArg;
  ExpenseScope? scopeArg;
  List<String>? customSplitParticipantsArg;
  SplitMode? splitModeArg;
  Map<String, Decimal>? splitDistributionArg;
  bool clearSplitArg = false;
  SplitExplanation? splitExplanationArg;
  bool clearExplanationArg = false;
  String? categoryIdArg;
  String? payerParticipantIdArg;

  @override
  Future<void> updateExpense({
    required String groupId,
    required String eventId,
    required String expenseId,
    Decimal? amount,
    String? currency,
    String? description,
    ExpenseScope? scope,
    String? subGroupId,
    List<String>? customSplitParticipants,
    SplitMode? splitMode,
    Map<String, Decimal>? splitDistribution,
    bool clearSplit = false,
    SplitExplanation? splitExplanation,
    bool clearExplanation = false,
    String? note,
    String? categoryId,
    String? payerParticipantId,
    String? lastEditedBy,
  }) async {
    callCount++;
    amountArg = amount;
    descriptionArg = description;
    scopeArg = scope;
    customSplitParticipantsArg = customSplitParticipants;
    splitModeArg = splitMode;
    splitDistributionArg = splitDistribution;
    clearSplitArg = clearSplit;
    splitExplanationArg = splitExplanation;
    clearExplanationArg = clearExplanation;
    categoryIdArg = categoryId;
    payerParticipantIdArg = payerParticipantId;
  }
}

class _PopSpy extends NavigatorObserver {
  int popCount = 0;
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    popCount++;
    super.didPop(route, previousRoute);
  }
}

void main() {
  testWidgets(
    'A: a category-only save does not revert a concurrent amount edit (#1092)',
    (tester) async {
      final service = _RecordingExpenseService();
      final h = await _pumpConcurrentEditor(tester, service: service, v1: [
        _expense(amount: '10.000', categoryId: 'food'),
      ]);

      // B's concurrent edit lands: amount 10 → 25.
      h.controller.add([_expense(amount: '25.000', categoryId: 'food')]);
      await tester.pump();

      // A touches ONLY the category (taps a different chip).
      await tester.ensureVisible(find.text('Transport'));
      await tester.tap(find.text('Transport'));
      await tester.pump();

      await _tapSave(tester);

      expect(
        service.amountArg,
        isNull,
        reason: "amount write absent — B's 25.000 survives",
      );
      expect(service.splitModeArg, isNull, reason: 'splitMode not written');
      expect(
        service.splitDistributionArg,
        isNull,
        reason: 'splitDistribution not written',
      );
      expect(service.clearSplitArg, isFalse, reason: 'clearSplit stays false');
      expect(
        service.categoryIdArg,
        isNotNull,
        reason: 'the category change IS written',
      );
    },
  );

  testWidgets('B: a money edit still writes the amount (#1092)', (tester) async {
    final service = _RecordingExpenseService();
    final h = await _pumpConcurrentEditor(tester, service: service, v1: [
      _expense(amount: '10.000', categoryId: 'food'),
    ]);

    h.controller.add([_expense(amount: '25.000', categoryId: 'food')]);
    await tester.pump();

    // A edits the amount to 15 — the money cluster is genuinely dirty.
    await tester.enterText(find.byType(TextField).first, '15');
    await tester.pump();

    await _tapSave(tester);

    expect(
      service.amountArg,
      Decimal.parse('15'),
      reason: "the user's own 15 is written, not v2's 25",
    );
  });

  testWidgets(
    'C: a pristine save writes nothing and still pops the editor (#1092)',
    (tester) async {
      final service = _RecordingExpenseService();
      final h = await _pumpConcurrentEditor(tester, service: service, v1: [
        _expense(amount: '10.000', categoryId: 'food'),
      ]);

      // Touch nothing; save.
      await _tapSave(tester);

      expect(
        service.callCount,
        0,
        reason: 'a pristine save must not call updateExpense',
      );
      // The editor still pops (didPop fires) — key-absence would false-green
      // since the sheet key sits on the route-level KeyedSubtree.
      expect(h.popSpy.popCount, 1, reason: 'the editor route popped');
    },
  );

  testWidgets(
    'D: a scope global→custom→global round-trip does not false-dirty money '
    '(#1092)',
    (tester) async {
      final service = _RecordingExpenseService();
      final h = await _pumpConcurrentEditor(tester, service: service, v1: [
        _expense(amount: '10.000', categoryId: 'food'),
      ]);

      h.controller.add([_expense(amount: '25.000', categoryId: 'food')]);
      await tester.pump();

      // Toggle scope Everyone → Some people → Everyone; change nothing else.
      // The round-trip seeds an inert _customSplitParticipants set (never
      // cleared) — the scope mask in moneyDirty must read false through it.
      await tester.ensureVisible(find.text('Some people'));
      await tester.tap(find.text('Some people'));
      await tester.pump();
      await tester.tap(find.text('Everyone'));
      await tester.pump();

      await _tapSave(tester);

      expect(
        service.amountArg,
        isNull,
        reason: "no revert — B's 25.000 survives a pure scope round-trip",
      );
    },
  );

  testWidgets(
    'E: a relabel-only itemized edit does not open the money gate (#1092)',
    (tester) async {
      final service = _RecordingExpenseService();
      final h = await _pumpConcurrentEditor(
        tester,
        service: service,
        v1: [_itemizedExpense()],
        physicalSize: const Size(1000, 2400),
      );

      // B concurrently re-itemizes and moves the money to 25.000.
      h.controller.add([_reItemizedExpense()]);
      await tester.pump();

      // A relabels one item (cosmetic) — distribution/amount untouched.
      await tester.tap(find.text('Itemized').first);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('itemized_label_0')),
        'Tajine',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('split_sheet_apply')));
      await tester.pumpAndSettle();

      await _tapSave(tester);

      expect(
        service.amountArg,
        isNull,
        reason: "amount not reverted by a display-only relabel — B's 25 stays",
      );
      expect(service.splitModeArg, isNull, reason: 'splitMode not written');
      expect(
        service.splitDistributionArg,
        isNull,
        reason: 'splitDistribution not written',
      );
      expect(service.clearSplitArg, isFalse, reason: 'clearSplit stays false');
      expect(
        service.splitExplanationArg,
        isNotNull,
        reason: 'the relabelled explanation IS written',
      );
    },
  );

  testWidgets(
    'F: a description-only save does not revert a concurrent payer edit (#1092)',
    (tester) async {
      final service = _RecordingExpenseService();
      final h = await _pumpConcurrentEditor(tester, service: service, v1: [
        _expense(amount: '10.000', categoryId: 'food', payer: 'uid-yasmin'),
      ]);

      // B concurrently changes who paid.
      h.controller.add([
        _expense(amount: '10.000', categoryId: 'food', payer: 'uid-layla'),
      ]);
      await tester.pump();

      // A edits ONLY the description.
      await tester.enterText(
        find.widgetWithText(TextField, 'Description'),
        'Dinner at the souq',
      );
      await tester.pump();

      await _tapSave(tester);

      expect(
        service.payerParticipantIdArg,
        isNull,
        reason: "payer write absent — B's uid-layla survives",
      );
      expect(
        service.descriptionArg,
        'Dinner at the souq',
        reason: 'the description change IS written',
      );
    },
  );
}

Future<void> _tapSave(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(FilledButton, 'Save'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

// --- harness ---------------------------------------------------------------

Future<({StreamController<List<Expense>> controller, _PopSpy popSpy})>
_pumpConcurrentEditor(
  WidgetTester tester, {
  required _RecordingExpenseService service,
  required List<Expense> v1,
  String currentUid = 'uid-yasmin',
  Size? physicalSize,
}) async {
  if (physicalSize != null) {
    tester.view.physicalSize = physicalSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();

  final controller = StreamController<List<Expense>>();
  addTearDown(controller.close);
  final popSpy = _PopSpy();
  final connectivity = ConnectivityNotifier(startPeriodicChecks: false);

  const eventRef = (groupId: 'group-1', eventId: 'event-1');
  final router = GoRouter(
    observers: [popSpy],
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
        sharedPreferencesProvider.overrideWithValue(prefs),
        currentUserIdProvider.overrideWithValue(currentUid),
        connectivityProvider.overrideWith((ref) => connectivity),
        expenseServiceProvider.overrideWithValue(service),
        eventExpensesProvider(eventRef).overrideWith((ref) => controller.stream),
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

  // Buffered until the /edit screen subscribes — v1 seeds the editor's frozen
  // pristine baseline in initState.
  controller.add(v1);
  await tester.pump();
  await tester.tap(find.text('Open edit'));
  await tester.pumpAndSettle();

  return (controller: controller, popSpy: popSpy);
}

Expense _expense({
  required String amount,
  required String categoryId,
  String payer = 'uid-yasmin',
}) {
  return Expense(
    id: 'expense-1',
    tripId: 'event-1',
    payerParticipantId: payer,
    amount: Decimal.parse(amount),
    currency: 'OMR',
    description: 'Dinner',
    scope: ExpenseScope.global,
    categoryId: categoryId,
    createdAt: DateTime(2026, 5, 30),
    createdBy: 'uid-yasmin',
  );
}

// An itemized expense (persists AS exact + a splitExplanation). Its distribution
// sums to 12.500 so the #250 exact-sync guard passes on save.
Expense _itemizedExpense() {
  return Expense(
    id: 'expense-1',
    tripId: 'event-1',
    payerParticipantId: 'uid-yasmin',
    amount: Decimal.parse('12.500'),
    currency: 'OMR',
    description: 'Dinner',
    scope: ExpenseScope.global,
    categoryId: 'food',
    createdAt: DateTime(2026, 5, 30),
    createdBy: 'uid-yasmin',
    splitMode: SplitMode.exact,
    // Must equal what the items reduce to, or re-reducing on relabel-apply
    // would change the distribution and (correctly) trip moneyDirty: Tagine
    // 8.500 → yasmin; Mint tea 4.000 split two ways → 2.000 each.
    splitDistribution: {
      'uid-yasmin': Decimal.parse('10.500'),
      'uid-layla': Decimal.parse('2.000'),
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

// B's concurrent re-itemization: different amount AND distribution, so a
// leak of the money gate would revert the amount to the form's stale 12.500.
Expense _reItemizedExpense() {
  return Expense(
    id: 'expense-1',
    tripId: 'event-1',
    payerParticipantId: 'uid-yasmin',
    amount: Decimal.parse('25.000'),
    currency: 'OMR',
    description: 'Dinner',
    scope: ExpenseScope.global,
    categoryId: 'food',
    createdAt: DateTime(2026, 5, 30),
    createdBy: 'uid-yasmin',
    splitMode: SplitMode.exact,
    splitDistribution: {
      'uid-yasmin': Decimal.parse('20.000'),
      'uid-layla': Decimal.parse('5.000'),
    },
    splitExplanation: const SplitExplanation(
      items: [
        SplitItem(
          label: 'Feast',
          amountFils: 25000,
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
  ExpenseCategory(
    id: 'transport',
    tripId: 'event-1',
    name: 'Transport',
    icon: 'transport',
    color: '#3B82C2',
    createdAt: DateTime(2026, 1, 1),
  ),
];
