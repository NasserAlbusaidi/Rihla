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
import 'package:safar/features/ledger/models/expense_model.dart';

import '../../helpers/pump_rihla_app.dart';

/// Slice 1 of #202 — widget coverage for [EventRecapScreen].
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

  List<Override> overridesFor(EventRecap recap) => [
        eventDetailProvider(eventRef).overrideWith((ref) => Stream.value(event())),
        eventRecapProvider(eventRef).overrideWithValue(recap),
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
    expect(find.text('You'), findsOneWidget);
    expect(find.text('You paid'), findsOneWidget);
    expect(find.text('Your share'), findsOneWidget);
    // Settlement touched this user (net 0 ≠ paid − share), so the reconciling
    // Settlements row MUST be visible — otherwise 100/50/0 reads as broken math.
    expect(find.text('Settlements'), findsOneWidget);
    expect(find.text('Net'), findsOneWidget);
  });

  testWidgets('square-but-active user still shows paid/share (no settlement)',
      (tester) async {
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

  testWidgets('renders Arabic strings under RTL locale', (tester) async {
    await pumpRihlaApp(
      tester,
      const EventRecapScreen(groupId: 'g1', eventId: 'e1'),
      locale: const Locale('ar'),
      overrides: overridesFor(settledRecap()),
    );

    expect(find.text('إجمالي الإنفاق'), findsOneWidget); // Total spent
    expect(find.text('أنت'), findsOneWidget); // You
    expect(find.text('الصافي'), findsOneWidget); // Net
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
}
