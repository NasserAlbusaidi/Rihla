import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/events/keys/event_keys.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/events/screens/event_command_center.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

void main() {
  testWidgets('renders current day badge when event is in progress', (
    tester,
  ) async {
    final today = DateUtils.dateOnly(DateTime.now());
    final event = _event(
      startDate: today.subtract(const Duration(days: 2)),
      endDate: today.add(const Duration(days: 4)),
    );

    await tester.pumpWidget(_wrap(event: event));
    await tester.pumpAndSettle();

    expect(find.byKey(EventKeys.dayBadge), findsOneWidget);
    expect(find.text('Day 3 of 7'), findsOneWidget);
  });

  testWidgets('empty state — shows "Nothing to settle yet" and dashed CTA', (
    tester,
  ) async {
    final event = _event(
      startDate: DateTime(2026, 1, 1),
      endDate: DateTime(2026, 1, 3),
    );

    await tester.pumpWidget(_wrap(event: event));
    await tester.pumpAndSettle();

    expect(find.text('Nothing to settle yet'), findsOneWidget);
    expect(find.text('Add the first expense'), findsOneWidget);
    // Ledger summary strip is hidden in the empty state.
    expect(find.byKey(EventKeys.ledgerCard), findsNothing);
  });

  testWidgets(
    'settled state — shows "All settled" and ledger strip with total',
    (tester) async {
      final event = _event(
        startDate: DateTime(2026, 1, 1),
        endDate: DateTime(2026, 1, 3),
      );
      final expense = _expense(
        id: 'x1',
        eventId: event.id,
        payer: 'uid-1',
        amount: Decimal.parse('10.000'),
      );

      await tester.pumpWidget(
        _wrap(event: event, expenses: [expense], balances: _settledBalances),
      );
      await tester.pumpAndSettle();

      expect(find.text('All settled'), findsOneWidget);
      expect(find.byKey(EventKeys.ledgerCard), findsOneWidget);
      expect(find.text('· 1 expense'), findsOneWidget);
    },
  );

  testWidgets('you-are-owed state — sage hero with per-row breakdown', (
    tester,
  ) async {
    final event = _event(
      startDate: DateTime(2026, 1, 1),
      endDate: DateTime(2026, 1, 3),
    );
    final expense = _expense(
      id: 'x1',
      eventId: event.id,
      payer: 'uid-1',
      amount: Decimal.parse('20.000'),
    );

    await tester.pumpWidget(
      _wrap(event: event, expenses: [expense], balances: _userOwedBalances),
    );
    await tester.pumpAndSettle();

    expect(find.text('YOU ARE OWED'), findsOneWidget);
    expect(find.textContaining('owes you', findRichText: true), findsOneWidget);
  });

  testWidgets('#261: non-OMR group renders its currency code, not OMR', (
    tester,
  ) async {
    final event = _event(
      startDate: DateTime(2026, 1, 1),
      endDate: DateTime(2026, 1, 3),
    );
    final expense = _expense(
      id: 'x1',
      eventId: event.id,
      payer: 'uid-1',
      amount: Decimal.parse('20.00'),
      currency: 'USD',
    );

    await tester.pumpWidget(
      _wrap(
        event: event,
        expenses: [expense],
        balances: _userOwedBalances,
        currency: 'USD',
      ),
    );
    await tester.pumpAndSettle();

    // The event hero + trip-total strip render the group's currency code.
    expect(find.textContaining('USD'), findsAtLeastNWidgets(1));
    expect(find.textContaining('OMR'), findsNothing);
  });

  testWidgets('you-owe state — rust hero with per-row breakdown', (
    tester,
  ) async {
    final event = _event(
      startDate: DateTime(2026, 1, 1),
      endDate: DateTime(2026, 1, 3),
    );
    final expense = _expense(
      id: 'x1',
      eventId: event.id,
      payer: 'uid-2',
      amount: Decimal.parse('20.000'),
    );

    await tester.pumpWidget(
      _wrap(event: event, expenses: [expense], balances: _userOwingBalances),
    );
    await tester.pumpAndSettle();

    expect(find.text('YOU OWE'), findsOneWidget);
    expect(find.textContaining('you owe', findRichText: true), findsOneWidget);
  });

  testWidgets('ledger summary strip routes to the event ledger path', (
    tester,
  ) async {
    final event = _event(
      startDate: DateTime(2026, 1, 1),
      endDate: DateTime(2026, 1, 3),
    );
    final expense = _expense(
      id: 'x1',
      eventId: event.id,
      payer: 'uid-1',
      amount: Decimal.parse('10.000'),
    );

    await _pumpEventHubRouter(
      tester,
      event,
      expenses: [expense],
      balances: _settledBalances,
    );

    await tester.tap(find.byKey(EventKeys.ledgerCard));
    await tester.pumpAndSettle();

    expect(find.text('LedgerRoute:event-1'), findsOneWidget);
  });

  testWidgets('direct route back button returns to group route', (
    tester,
  ) async {
    final event = _event(
      startDate: DateTime(2026, 1, 1),
      endDate: DateTime(2026, 1, 3),
    );

    await _pumpEventHubRouter(tester, event);

    await tester.tap(find.byIcon(Iconsax.arrow_left));
    await tester.pumpAndSettle();

    expect(find.text('GroupRoute:group-1'), findsOneWidget);
  });

  testWidgets('add expense button routes to /ledger/add', (tester) async {
    final event = _event(
      startDate: DateTime(2026, 1, 1),
      endDate: DateTime(2026, 1, 3),
    );

    await _pumpEventHubRouter(tester, event);

    await tester.tap(find.byKey(EventKeys.addExpenseChip));
    await tester.pumpAndSettle();

    expect(find.text('AddExpenseRoute:event-1'), findsOneWidget);
  });

  testWidgets('settings button routes to the event settings path', (
    tester,
  ) async {
    final event = _event(
      startDate: DateTime(2026, 1, 1),
      endDate: DateTime(2026, 1, 3),
    );

    await _pumpEventHubRouter(tester, event);

    await tester.tap(find.byKey(EventKeys.settingsButton));
    await tester.pumpAndSettle();

    expect(find.text('SettingsRoute:event-1'), findsOneWidget);
  });
}

// ───────────────────────────── Helpers

Widget _wrap({
  required Event event,
  List<Expense> expenses = const [],
  List<UserBalance>? balances,
  String currency = 'OMR',
}) {
  final eventRef = (groupId: event.groupId, eventId: event.id);
  return ProviderScope(
    overrides: [
      currentUserIdProvider.overrideWithValue('uid-1'),
      eventDetailProvider(
        eventRef,
      ).overrideWith((_) => Stream<Event?>.value(event)),
      groupDetailProvider(
        event.groupId,
      ).overrideWith((_) => Stream<Group?>.value(_group.copyWith(currency: currency))),
      eventExpensesProvider(
        eventRef,
      ).overrideWith((_) => Stream.value(expenses)),
      eventSettlementsProvider(
        eventRef,
      ).overrideWith((_) => Stream.value(const [])),
      if (balances != null)
        eventBalancesProvider((
          eventRef: eventRef,
          event: event,
        )).overrideWith((_) => AsyncValue.data(balances)),
    ],
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: EventCommandCenter(groupId: event.groupId, eventId: event.id),
    ),
  );
}

Future<void> _pumpEventHubRouter(
  WidgetTester tester,
  Event event, {
  List<Expense> expenses = const [],
  List<UserBalance>? balances,
}) async {
  final eventRef = (groupId: event.groupId, eventId: event.id);
  final router = GoRouter(
    initialLocation: '/group/${event.groupId}/event/${event.id}',
    routes: [
      GoRoute(
        path: '/group/:gid',
        builder: (_, state) =>
            Scaffold(body: Text('GroupRoute:${state.pathParameters['gid']}')),
        routes: [
          GoRoute(
            path: 'event/:eid',
            builder: (_, state) => EventCommandCenter(
              groupId: state.pathParameters['gid']!,
              eventId: state.pathParameters['eid']!,
            ),
            routes: [
              GoRoute(
                path: 'ledger',
                builder: (_, state) => Scaffold(
                  body: Text('LedgerRoute:${state.pathParameters['eid']}'),
                ),
                routes: [
                  GoRoute(
                    path: 'add',
                    builder: (_, state) => Scaffold(
                      body: Text(
                        'AddExpenseRoute:${state.pathParameters['eid']}',
                      ),
                    ),
                  ),
                ],
              ),
              GoRoute(
                path: 'settings',
                builder: (_, state) => Scaffold(
                  body: Text('SettingsRoute:${state.pathParameters['eid']}'),
                ),
              ),
            ],
          ),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserIdProvider.overrideWithValue('uid-1'),
        eventDetailProvider(
          eventRef,
        ).overrideWith((_) => Stream<Event?>.value(event)),
        groupDetailProvider(
          event.groupId,
        ).overrideWith((_) => Stream<Group?>.value(_group)),
        eventExpensesProvider(
          eventRef,
        ).overrideWith((_) => Stream.value(expenses)),
        eventSettlementsProvider(
          eventRef,
        ).overrideWith((_) => Stream.value(const [])),
        if (balances != null)
          eventBalancesProvider((
            eventRef: eventRef,
            event: event,
          )).overrideWithValue(AsyncValue.data(balances)),
      ],
      child: MaterialApp.router(
        theme: AppTheme.lightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Event _event({required DateTime startDate, required DateTime endDate}) {
  return Event(
    id: 'event-1',
    name: 'Marrakech',
    type: EventType.trip,
    groupId: 'group-1',
    createdBy: 'uid-1',
    participantIds: const ['uid-1', 'uid-2'],
    participantNames: const {'uid-1': 'Mona', 'uid-2': 'Nasser'},
    modules: const EventModules(),
    startDate: startDate,
    endDate: endDate,
    createdAt: startDate,
  );
}

Expense _expense({
  required String id,
  required String eventId,
  required String payer,
  required Decimal amount,
  String currency = 'OMR',
}) {
  return Expense(
    id: id,
    tripId: eventId,
    payerParticipantId: payer,
    amount: amount,
    scope: ExpenseScope.global,
    createdAt: DateTime(2026, 1, 2),
    createdBy: payer,
    currency: currency,
  );
}

final _group = Group(
  id: 'group-1',
  name: 'Friends',
  inviteCode: 'ABC123',
  createdBy: 'uid-1',
  memberIds: const ['uid-1', 'uid-2'],
  createdAt: DateTime(2026, 1, 1),
);

UserBalance _balance({
  required String uid,
  required String name,
  required Decimal net,
}) {
  return UserBalance(
    participantId: uid,
    displayName: name,
    totalPaid: Decimal.zero,
    totalOwed: Decimal.zero,
    netBalance: net,
  );
}

final _settledBalances = <UserBalance>[
  _balance(uid: 'uid-1', name: 'Mona', net: Decimal.zero),
  _balance(uid: 'uid-2', name: 'Nasser', net: Decimal.zero),
];

final _userOwedBalances = <UserBalance>[
  _balance(uid: 'uid-1', name: 'Mona', net: Decimal.parse('10.000')),
  _balance(uid: 'uid-2', name: 'Nasser', net: Decimal.parse('-10.000')),
];

final _userOwingBalances = <UserBalance>[
  _balance(uid: 'uid-1', name: 'Mona', net: Decimal.parse('-10.000')),
  _balance(uid: 'uid-2', name: 'Nasser', net: Decimal.parse('10.000')),
];
