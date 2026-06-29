import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safar/features/events/keys/event_keys.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/models/event_recap.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/events/providers/event_recap_provider.dart';
import 'package:safar/features/events/screens/event_recap_screen.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/providers/ledger_view_provider.dart';

import '../../helpers/pump_rihla_app.dart';

/// #202 Slice 1 + #721 Slice 2 — widget coverage for [EventRecapScreen].
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const eventRef = (groupId: 'g1', eventId: 'e1');

  Decimal d(String s) => Decimal.parse(s);

  UserBalance ub(String id, String paid, String owed, String net) =>
      UserBalance(
        participantId: id,
        displayName: id,
        totalPaid: d(paid),
        totalOwed: d(owed),
        netBalance: d(net),
      );

  Expense expense(
    String id, {
    required String payer,
    required String amount,
    String currency = 'OMR',
    String? categoryId,
    String? description,
  }) =>
      Expense(
        id: id,
        tripId: 'e1',
        payerParticipantId: payer,
        amount: d(amount),
        scope: ExpenseScope.global,
        createdAt: DateTime(2026, 1, 1),
        currency: currency,
        categoryId: categoryId,
        description: description,
      );

  // The screen resolves display names from ledgerViewProvider; in tests its real
  // Firebase-backed body must be overridden (Gate P2). Only rosterDisplayNames
  // is read by the recap screen.
  LedgerView fakeLedgerView(Map<String, String> roster) => (
        participants: const [],
        balances: const {},
        eventTotal: const {},
        rosterDisplayNames: roster,
        expensePayerDisplayNames: const {},
        settlementDisplayNames: const {},
        owedByExpenseId: const {},
      );

  Event event() => Event(
    id: 'e1',
    name: 'Jabal Trip',
    type: EventType.trip,
    groupId: 'g1',
    createdBy: 'a',
    participantIds: const ['a', 'b'],
    participantNames: const {'a': 'Alice', 'b': 'Bob'},
    modules: const EventModules(),
    createdAt: DateTime(2026, 3, 1),
  );

  // a paid 100, share 50, received a 50 settlement → net 0, settled -50.
  EventRecap settledRecap() => EventRecap.from(
    eventId: 'e1',
    eventName: 'Jabal Trip',
    startDate: null,
    endDate: null,
    participantIds: const ['a', 'b'],
    expenseCount: 2,
    totalSpentByCurrency: {'OMR': d('100')},
    balances: {
      'OMR': [ub('a', '100', '50', '0'), ub('b', '0', '50', '0')],
    },
    uid: 'a',
  );

  List<Override> overridesFor(
    EventRecap recap, {
    Map<String, String> roster = const {'a': 'Alice', 'b': 'Bob'},
    String? uid = 'a',
  }) =>
      [
        eventDetailProvider(eventRef)
            .overrideWith((ref) => Stream.value(event())),
        eventRecapProvider(eventRef).overrideWithValue(recap),
        ledgerViewProvider(eventRef).overrideWithValue(fakeLedgerView(roster)),
        currentUserIdProvider.overrideWithValue(uid),
      ];

  testWidgets('renders the recap screen with money rows (EN)', (tester) async {
    await pumpRihlaApp(
      tester,
      const EventRecapScreen(groupId: 'g1', eventId: 'e1'),
      overrides: overridesFor(settledRecap()),
    );

    expect(find.byKey(EventKeys.recapScreen), findsOneWidget);
    expect(find.text('Jabal Trip'), findsOneWidget);
    expect(find.text('Total spent'), findsOneWidget);
    // #721: the user's position is folded into the Total card (net/paid/share);
    // the standalone "You" section and "Settlements" row are gone.
    expect(find.text('You paid'), findsOneWidget);
    expect(find.text('Your share'), findsOneWidget);
    expect(find.text('Net'), findsOneWidget);
    expect(find.text('You'), findsNothing);
    expect(find.text('Settlements'), findsNothing);
  });

  testWidgets('square-but-active user still shows paid/share (no settlement)', (
    tester,
  ) async {
    // a paid exactly their share → net 0, no settlement. Block must NOT blank.
    final recap = EventRecap.from(
      eventId: 'e1',
      eventName: 'Jabal Trip',
      startDate: null,
      endDate: null,
      participantIds: const ['a', 'b'],
      expenseCount: 2,
      totalSpentByCurrency: {'OMR': d('200')},
      balances: {
        'OMR': [ub('a', '100', '100', '0'), ub('b', '100', '100', '0')],
      },
      uid: 'a',
    );
    await pumpRihlaApp(
      tester,
      const EventRecapScreen(groupId: 'g1', eventId: 'e1'),
      overrides: overridesFor(recap),
    );

    expect(find.text('You paid'), findsOneWidget);
    expect(find.text('Your share'), findsOneWidget);
    // No settlements → that row is suppressed.
    expect(find.text('Settlements'), findsNothing);
    expect(find.text('Net'), findsOneWidget);
  });

  testWidgets('pluralizes one participant and one expense in the subtitle', (
    tester,
  ) async {
    final recap = EventRecap.from(
      eventId: 'e1',
      eventName: 'Solo Dinner',
      startDate: null,
      endDate: null,
      participantIds: const ['a'],
      expenseCount: 1,
      totalSpentByCurrency: {'OMR': d('12')},
      balances: {
        'OMR': [ub('a', '12', '12', '0')],
      },
      uid: 'a',
    );

    await pumpRihlaApp(
      tester,
      const EventRecapScreen(groupId: 'g1', eventId: 'e1'),
      overrides: overridesFor(recap),
    );

    expect(find.text('1 person · 1 expense'), findsOneWidget);
    expect(find.text('1 people · 1 expenses'), findsNothing);
  });

  testWidgets('renders Arabic strings under RTL locale', (tester) async {
    await pumpRihlaApp(
      tester,
      const EventRecapScreen(groupId: 'g1', eventId: 'e1'),
      locale: const Locale('ar'),
      overrides: overridesFor(settledRecap()),
    );

    expect(find.text('إجمالي الإنفاق'), findsOneWidget); // Total spent
    expect(find.text('الصافي'), findsOneWidget); // Net (in the merged card)
    expect(find.text('من دفع'), findsOneWidget); // Who paid
  });

  testWidgets('empty event shows the empty state', (tester) async {
    final empty = EventRecap.from(
      eventId: 'e1',
      eventName: 'Jabal Trip',
      startDate: null,
      endDate: null,
      participantIds: const ['a', 'b'],
      expenseCount: 0,
      totalSpentByCurrency: const {},
      balances: const {},
      uid: 'a',
    );
    await pumpRihlaApp(
      tester,
      const EventRecapScreen(groupId: 'g1', eventId: 'e1'),
      overrides: overridesFor(empty),
    );
    // EmptyStateView runs a flutter_animate entrance ticker → drain it or
    // teardown throws "A Timer is still pending."
    await tester.pumpAndSettle();

    expect(find.text('Nothing to wrap up yet'), findsOneWidget);
  });

  // ── #721 Slice 2: full money summary ──────────────────────────────────────

  testWidgets('outstanding event renders all summary sections (#721)', (
    tester,
  ) async {
    final recap = EventRecap.from(
      eventId: 'e1',
      eventName: 'Goa Trip',
      startDate: null,
      endDate: null,
      participantIds: const ['a', 'b', 'c', 'dd'],
      expenseCount: 3,
      totalSpentByCurrency: {'OMR': d('380.5')},
      balances: {
        'OMR': [
          ub('a', '300.5', '95.125', '205.375'),
          ub('b', '80', '95.125', '-15.125'),
          ub('c', '0', '95.125', '-95.125'),
          ub('dd', '0', '95.125', '-95.125'),
        ],
      },
      expenses: [
        expense('e1',
            payer: 'a',
            amount: '180',
            categoryId: 'accommodation',
            description: 'Beach villa'),
        expense('e2', payer: 'a', amount: '120.5', categoryId: 'food'),
        expense('e3', payer: 'b', amount: '80', categoryId: 'transport'),
      ],
      uid: 'a',
    );
    await pumpRihlaApp(
      tester,
      const EventRecapScreen(groupId: 'g1', eventId: 'e1'),
      overrides: overridesFor(recap,
          roster: const {'a': 'Alice', 'b': 'Bob', 'c': 'Carol', 'dd': 'Dana'}),
    );

    expect(find.text('Top payer'), findsOneWidget);
    expect(find.text('Biggest expense'), findsOneWidget);
    expect(find.text('Beach villa'), findsOneWidget); // biggest uses description
    expect(find.text('By category'), findsOneWidget);
    expect(find.text('Who paid'), findsOneWidget);
    expect(find.text("Who's up / down"), findsOneWidget);
    expect(find.text('Accommodation'), findsOneWidget); // category bar only
    expect(find.text('Outstanding balances'), findsOneWidget);
    // Debtor count, NOT the 3 non-zero-net rows that include the creditor (a).
    expect(find.textContaining('3 people still owe'), findsOneWidget);
  });

  testWidgets('settled event shows the settled status + settled rows (#721)', (
    tester,
  ) async {
    final recap = EventRecap.from(
      eventId: 'e1',
      eventName: 'Goa Trip',
      startDate: null,
      endDate: null,
      participantIds: const ['a', 'b'],
      expenseCount: 2,
      totalSpentByCurrency: {'OMR': d('200')},
      balances: {
        'OMR': [ub('a', '100', '100', '0'), ub('b', '100', '100', '0')],
      },
      expenses: [
        expense('e1', payer: 'a', amount: '100', categoryId: 'food'),
        expense('e2', payer: 'b', amount: '100', categoryId: 'food'),
      ],
      uid: 'a',
    );
    await pumpRihlaApp(
      tester,
      const EventRecapScreen(groupId: 'g1', eventId: 'e1'),
      overrides: overridesFor(recap),
    );

    expect(find.text("Everyone's settled up"), findsOneWidget);
    expect(find.text('settled'), findsNWidgets(2)); // both net-0 rows
    expect(find.text('Outstanding balances'), findsNothing);
  });

  testWidgets('multi-currency: per-currency note + headers (#721)', (
    tester,
  ) async {
    final recap = EventRecap.from(
      eventId: 'e1',
      eventName: 'Lisbon Trip',
      startDate: null,
      endDate: null,
      participantIds: const ['a', 'b'],
      expenseCount: 2,
      totalSpentByCurrency: {'USD': d('100'), 'OMR': d('30')},
      balances: {
        'USD': [ub('a', '100', '50', '50'), ub('b', '0', '50', '-50')],
        'OMR': [ub('a', '30', '30', '0')],
      },
      expenses: [
        expense('e1', payer: 'a', amount: '100', currency: 'USD', categoryId: 'food'),
        expense('e2', payer: 'a', amount: '30', currency: 'OMR', categoryId: 'transport'),
      ],
      uid: 'a',
    );
    await pumpRihlaApp(
      tester,
      const EventRecapScreen(groupId: 'g1', eventId: 'e1'),
      overrides: overridesFor(recap),
    );

    expect(
      find.text("Balances are kept per currency — they're never added together."),
      findsOneWidget,
    );
    // Each currency block has its own "By category".
    expect(find.text('By category'), findsNWidgets(2));
  });

  testWidgets('settlement-only currency renders without crashing (#721 Gate P1)',
      (tester) async {
    // EUR is a balance currency with NO expense — its block has no highlights /
    // category / who-paid, only nets + status. Must not throw on .first.
    final recap = EventRecap.from(
      eventId: 'e1',
      eventName: 'Mixed Trip',
      startDate: null,
      endDate: null,
      participantIds: const ['a', 'b'],
      expenseCount: 1,
      totalSpentByCurrency: {'OMR': d('10')},
      balances: {
        'OMR': [ub('a', '10', '10', '0')],
        'EUR': [ub('a', '0', '0', '-50'), ub('b', '0', '0', '50')],
      },
      expenses: [expense('e1', payer: 'a', amount: '10', currency: 'OMR')],
      uid: 'a',
    );
    await pumpRihlaApp(
      tester,
      const EventRecapScreen(groupId: 'g1', eventId: 'e1'),
      overrides: overridesFor(recap),
    );

    expect(find.byKey(EventKeys.recapScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
    // OMR settled (a net 0), EUR outstanding (a owes 50 → 1 debtor).
    expect(find.text("Everyone's settled up"), findsOneWidget);
    expect(find.textContaining('1 person still owes'), findsOneWidget);
  });

  testWidgets('zero-amount expense bar does not NaN-crash (#721 Gate P2)', (
    tester,
  ) async {
    final recap = EventRecap.from(
      eventId: 'e1',
      eventName: 'Freebie',
      startDate: null,
      endDate: null,
      participantIds: const ['a'],
      expenseCount: 1,
      totalSpentByCurrency: {'OMR': d('0')},
      balances: {
        'OMR': [ub('a', '0', '0', '0')],
      },
      expenses: [expense('e1', payer: 'a', amount: '0', categoryId: 'food')],
      uid: 'a',
    );
    await pumpRihlaApp(
      tester,
      const EventRecapScreen(groupId: 'g1', eventId: 'e1'),
      overrides: overridesFor(recap),
    );

    expect(find.byKey(EventKeys.recapScreen), findsOneWidget);
    expect(find.text('By category'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
