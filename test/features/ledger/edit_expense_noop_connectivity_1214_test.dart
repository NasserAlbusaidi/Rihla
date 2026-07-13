import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:safar/core/models/split_mode.dart';
import 'package:safar/core/providers/connectivity_provider.dart';
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

class _MockExpenseService extends Mock implements ExpenseService {}

class _FakeSplitExplanation extends Fake implements SplitExplanation {}

/// Spies on the connectivity side effects the edit screen drives after a save
/// (#1214). A REAL [ConnectivityNotifier] (not a Mock) so `noteQueuedWrite`'s
/// internal `_beginPendingWriteReplayBarrier` still runs exactly as in
/// production (and fails open exactly as it does in every other widget test
/// without a live Firebase app) — only the call counts are observed.
class _SpyConnectivityNotifier extends ConnectivityNotifier {
  _SpyConnectivityNotifier() : super(startPeriodicChecks: false);

  int noteQueuedWriteCalls = 0;
  int noteLocalWriteCalls = 0;

  @override
  void noteQueuedWrite({String? groupId}) {
    noteQueuedWriteCalls++;
    super.noteQueuedWrite(groupId: groupId);
  }

  @override
  void noteLocalWrite({String? groupId}) {
    noteLocalWriteCalls++;
    super.noteLocalWrite(groupId: groupId);
  }
}

// #1214 RED: a value-equal (no-op) OFFLINE expense edit must not flip
// connectivity.
//
// `moneyDirty` (expense_editor_body.dart) is a STRING compare, so retyping
// the stored amount with different formatting ("12.500" -> "12.50") sets
// moneyDirty even though the DECIMAL value is unchanged. edit_expense_screen
// .dart's `_save` then computes every updateExpense arg via a DECIMAL compare
// against `original`, so every arg resolves to null — a genuine no-op. Offline,
// that reaches `awaitServerAck(..., skipWait: true)` unconditionally (skipWait
// is driven by connectivity status alone, not by whether anything was queued),
// which calls `noteQueuedWrite` and flips a genuinely-offline device toward
// "syncing"/"online" even though nothing was ever written.
void main() {
  setUpAll(() {
    registerFallbackValue(Decimal.zero);
    registerFallbackValue(ExpenseScope.global);
    registerFallbackValue(SplitMode.equally);
    registerFallbackValue(_FakeSplitExplanation());
  });

  testWidgets(
    '#1214: a value-equal offline edit does not call noteQueuedWrite',
    (tester) async {
      final service = _MockExpenseService();
      // Stubbed defensively (any-matchers) so a regression that DOES reach the
      // service doesn't throw "not stubbed" and mask the real assertion below.
      when(
        () => service.updateExpense(
          groupId: any(named: 'groupId'),
          eventId: any(named: 'eventId'),
          expenseId: any(named: 'expenseId'),
          amount: any(named: 'amount'),
          currency: any(named: 'currency'),
          description: any(named: 'description'),
          scope: any(named: 'scope'),
          subGroupId: any(named: 'subGroupId'),
          customSplitParticipants: any(named: 'customSplitParticipants'),
          splitMode: any(named: 'splitMode'),
          splitDistribution: any(named: 'splitDistribution'),
          clearSplit: any(named: 'clearSplit'),
          splitExplanation: any(named: 'splitExplanation'),
          clearExplanation: any(named: 'clearExplanation'),
          note: any(named: 'note'),
          categoryId: any(named: 'categoryId'),
          payerParticipantId: any(named: 'payerParticipantId'),
          lastEditedBy: any(named: 'lastEditedBy'),
        ),
      ).thenAnswer((_) => Completer<void>().future); // never acks: real offline

      final connectivity = _SpyConnectivityNotifier()..setOffline();
      late ProviderContainer container;

      await _pumpEditableRoute(
        tester,
        expenseService: service,
        connectivity: connectivity,
        onContainer: (c) => container = c,
      );

      await tester.tap(find.text('Open edit'));
      await tester.pumpAndSettle();
      // Value-equal retype: stored amount is 12.500, retype as 12.50 — the
      // editor's string-compare moneyDirty flips true; the Decimal value does
      // not change, so every updateExpense arg the screen builds is null.
      await tester.enterText(find.byType(TextField).first, '12.50');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Open edit'), findsOneWidget); // popped back regardless

      verifyNever(
        () => service.updateExpense(
          groupId: any(named: 'groupId'),
          eventId: any(named: 'eventId'),
          expenseId: any(named: 'expenseId'),
          amount: any(named: 'amount'),
          currency: any(named: 'currency'),
          description: any(named: 'description'),
          scope: any(named: 'scope'),
          subGroupId: any(named: 'subGroupId'),
          customSplitParticipants: any(named: 'customSplitParticipants'),
          splitMode: any(named: 'splitMode'),
          splitDistribution: any(named: 'splitDistribution'),
          clearSplit: any(named: 'clearSplit'),
          splitExplanation: any(named: 'splitExplanation'),
          clearExplanation: any(named: 'clearExplanation'),
          note: any(named: 'note'),
          categoryId: any(named: 'categoryId'),
          payerParticipantId: any(named: 'payerParticipantId'),
          lastEditedBy: any(named: 'lastEditedBy'),
        ),
      );
      expect(
        connectivity.noteQueuedWriteCalls,
        0,
        reason: 'a value-equal no-op save must not report a queued write',
      );
      expect(
        connectivity.noteLocalWriteCalls,
        0,
        reason: 'a value-equal no-op save must not report a local write',
      );
      expect(
        connectivity.state,
        ConnectivityStatus.offline,
        reason: 'connectivity must not move off offline for a no-op save',
      );
      expect(
        container.read(ledgerRevisionProvider),
        0,
        reason: 'nothing was written — no home balance refresh needed',
      );
    },
  );

  testWidgets(
    '#1214 companion: a genuine offline edit still calls noteQueuedWrite',
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
          subGroupId: any(named: 'subGroupId'),
          customSplitParticipants: any(named: 'customSplitParticipants'),
          splitMode: any(named: 'splitMode'),
          splitDistribution: any(named: 'splitDistribution'),
          clearSplit: any(named: 'clearSplit'),
          splitExplanation: any(named: 'splitExplanation'),
          clearExplanation: any(named: 'clearExplanation'),
          note: any(named: 'note'),
          categoryId: any(named: 'categoryId'),
          payerParticipantId: any(named: 'payerParticipantId'),
          lastEditedBy: any(named: 'lastEditedBy'),
        ),
      ).thenAnswer((_) => Completer<void>().future); // real offline: no ack

      final connectivity = _SpyConnectivityNotifier()..setOffline();
      late ProviderContainer container;

      await _pumpEditableRoute(
        tester,
        expenseService: service,
        connectivity: connectivity,
        onContainer: (c) => container = c,
      );

      await tester.tap(find.text('Open edit'));
      await tester.pumpAndSettle();
      // A genuine value change: 12.500 -> 15.
      await tester.enterText(find.byType(TextField).first, '15');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Open edit'), findsOneWidget); // popped back

      verify(
        () => service.updateExpense(
          groupId: any(named: 'groupId'),
          eventId: any(named: 'eventId'),
          expenseId: any(named: 'expenseId'),
          amount: any(named: 'amount'),
          currency: any(named: 'currency'),
          description: any(named: 'description'),
          scope: any(named: 'scope'),
          subGroupId: any(named: 'subGroupId'),
          customSplitParticipants: any(named: 'customSplitParticipants'),
          splitMode: any(named: 'splitMode'),
          splitDistribution: any(named: 'splitDistribution'),
          clearSplit: any(named: 'clearSplit'),
          splitExplanation: any(named: 'splitExplanation'),
          clearExplanation: any(named: 'clearExplanation'),
          note: any(named: 'note'),
          categoryId: any(named: 'categoryId'),
          payerParticipantId: any(named: 'payerParticipantId'),
          lastEditedBy: any(named: 'lastEditedBy'),
        ),
      ).called(1);
      expect(
        connectivity.noteQueuedWriteCalls,
        1,
        reason: 'a genuine offline edit must still report the queued write',
      );
      expect(container.read(ledgerRevisionProvider), 1);
      expect(connectivity.state, ConnectivityStatus.syncing);
    },
  );
}

Future<void> _pumpEditableRoute(
  WidgetTester tester, {
  required ExpenseService expenseService,
  required ConnectivityNotifier connectivity,
  required void Function(ProviderContainer) onContainer,
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
        connectivityProvider.overrideWith((ref) => connectivity),
        expenseServiceProvider.overrideWithValue(expenseService),
        eventExpensesProvider(eventRef).overrideWith(
          (ref) => Stream.value([_expense(createdBy: 'uid-yasmin')]),
        ),
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
  onContainer(
    ProviderScope.containerOf(tester.element(find.byType(Scaffold).first)),
  );
}

Expense _expense({required String createdBy}) {
  return Expense(
    id: 'expense-1',
    tripId: 'event-1',
    payerParticipantId: 'uid-yasmin',
    amount: Decimal.parse('12.500'),
    currency: 'OMR',
    description: 'Dinner',
    scope: ExpenseScope.global,
    createdAt: DateTime(2026, 5, 30),
    createdBy: createdBy,
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
