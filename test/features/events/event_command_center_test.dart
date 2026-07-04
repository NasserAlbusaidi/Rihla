import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/events/keys/event_keys.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/events/screens/event_command_center.dart';
import 'package:safar/features/groups/models/group_member_model.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';
import 'package:safar/features/ledger/providers/ledger_view_provider.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

/// #758 — the tabbed event view's balance header + closed-state affordances.
/// Tab switching / panels / FAB behavior lives in event_tabs_test.dart.
void main() {
  testWidgets('empty state — header shows "Nothing to settle yet"', (
    tester,
  ) async {
    final event = _event(
      startDate: DateTime(2026, 1, 1),
      endDate: DateTime(2026, 1, 3),
    );

    await tester.pumpWidget(_wrap(event: event));
    await tester.pumpAndSettle();

    expect(find.text('Nothing to settle yet'), findsOneWidget);
  });

  testWidgets('settled state — header shows "All settled"', (tester) async {
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
  });

  testWidgets(
    '#689: the Expenses tab trip caption speaks the event type '
    '(camping → CAMPING TOTAL)',
    (tester) async {
      final event = _event(
        startDate: DateTime(2026, 1, 1),
        endDate: DateTime(2026, 1, 3),
        type: EventType.camping,
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

      expect(find.textContaining('CAMPING TOTAL'), findsOneWidget);
      expect(find.textContaining('TRIP TOTAL'), findsNothing);
    },
  );

  testWidgets('you-are-owed state — sage overline in the header', (
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
  });

  testWidgets('you-owe state — rust overline in the header', (tester) async {
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

    expect(find.textContaining('USD'), findsAtLeastNWidgets(1));
    expect(find.textContaining('OMR'), findsNothing);
  });

  testWidgets(
    '#631: header computes "you owe" through the shared ledgerViewProvider '
    '(no injected balances)',
    (tester) async {
      final event = _event(
        startDate: DateTime(2026, 1, 1),
        endDate: DateTime(2026, 1, 3),
      );
      // uid-2 pays 20 OMR, equal-split between the two participants → I (uid-1)
      // owe 10, uid-2 is owed 10. No balance override: this drives the REAL
      // BalanceCalculator pass via ledgerViewProvider end-to-end.
      final expense = _expense(
        id: 'x1',
        eventId: event.id,
        payer: 'uid-2',
        amount: Decimal.parse('20.000'),
      );
      final eventRef = (groupId: event.groupId, eventId: event.id);

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
            ).overrideWith((_) => Stream.value([expense])),
            eventSettlementsProvider(
              eventRef,
            ).overrideWith((_) => Stream.value(const [])),
            groupMembersProvider(event.groupId).overrideWith(
              (_) => Stream.value([
                _realMember('uid-1', 'Mona'),
                _realMember('uid-2', 'Nasser'),
              ]),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: EventCommandCenter(groupId: event.groupId, eventId: event.id),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('YOU OWE'), findsOneWidget);
    },
  );

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

  testWidgets(
    '#708 close-wiring: no receipt CTA on a closed event with no expenses',
    (tester) async {
      final event = _event(
        startDate: DateTime(2026, 1, 1),
        endDate: DateTime(2026, 1, 3),
        isClosed: true,
        closedBy: 'uid-1',
      );

      await _pumpEventHubRouter(tester, event);

      expect(find.byKey(EventKeys.closedBanner), findsOneWidget);
      expect(find.byKey(EventKeys.closedBannerViewReceipt), findsNothing);
    },
  );

  group('#789 — live "Day N of M" eyebrow badge', () {
    // Dates anchored at local noon ± whole days so the badge is deterministic
    // regardless of when the suite runs: start=today-2, end=today+4 → DAY 3/7.
    Event liveEvent({bool isClosed = false}) {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day, 12);
      return _event(
        startDate: today.subtract(const Duration(days: 2)),
        endDate: today.add(const Duration(days: 4)),
        isClosed: isClosed,
        closedBy: isClosed ? 'uid-1' : null,
      );
    }

    testWidgets('live multi-day trip shows "DAY 3 OF 7" in the eyebrow', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(event: liveEvent()));
      await tester.pumpAndSettle();

      expect(find.textContaining('DAY 3 OF 7'), findsOneWidget);
    });

    testWidgets('a past trip shows no day badge', (tester) async {
      await tester.pumpWidget(
        _wrap(
          event: _event(
            startDate: DateTime(2026, 1, 1),
            endDate: DateTime(2026, 1, 3),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('DAY '), findsNothing);
    });

    testWidgets('a closed event shows no day badge even with live dates', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(event: liveEvent(isClosed: true)));
      await tester.pumpAndSettle();

      expect(find.textContaining('DAY 3 OF 7'), findsNothing);
    });
  });

  group('#811 — open-event recap banner (labelled entry, replaces the cup)', () {
    testWidgets(
      'open event with expenses shows the labelled recap banner',
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

        await _pumpEventHubRouter(tester, event, expenses: [expense]);

        expect(find.byKey(EventKeys.openRecapBanner), findsOneWidget);
        expect(find.byKey(EventKeys.closedBanner), findsNothing);
      },
    );

    testWidgets('tapping the banner routes to the recap screen', (tester) async {
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

      await _pumpEventHubRouter(tester, event, expenses: [expense]);

      await tester.tap(find.byKey(EventKeys.openRecapBannerViewRecap));
      await tester.pumpAndSettle();

      expect(find.text('RecapRoute:event-1'), findsOneWidget);
    });

    testWidgets('open event with NO expenses hides the banner', (tester) async {
      final event = _event(
        startDate: DateTime(2026, 1, 1),
        endDate: DateTime(2026, 1, 3),
      );

      await _pumpEventHubRouter(tester, event);

      expect(find.byKey(EventKeys.openRecapBanner), findsNothing);
    });

    testWidgets(
      'closed event uses the Recap tab, NOT the open banner',
      (tester) async {
        final event = _event(
          startDate: DateTime(2026, 1, 1),
          endDate: DateTime(2026, 1, 3),
          isClosed: true,
          closedBy: 'uid-1',
        );
        final expense = _expense(
          id: 'x1',
          eventId: event.id,
          payer: 'uid-1',
          amount: Decimal.parse('10.000'),
        );

        await _pumpEventHubRouter(tester, event, expenses: [expense]);

        expect(find.byKey(EventKeys.openRecapBanner), findsNothing);
        expect(find.byKey(EventKeys.closedBanner), findsOneWidget);
        expect(find.byKey(EventKeys.tabRecap), findsOneWidget);
      },
    );

    testWidgets('renders without overflow in a narrow RTL layout', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

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
      final eventRef = (groupId: event.groupId, eventId: event.id);

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
            ).overrideWith((_) => Stream.value([expense])),
            eventSettlementsProvider(
              eventRef,
            ).overrideWith((_) => Stream.value(const [])),
            groupMembersProvider(event.groupId).overrideWith(
              (_) => Stream.value([
                _realMember('uid-1', 'Mona'),
                _realMember('uid-2', 'Nasser'),
              ]),
            ),
          ],
          child: MaterialApp(
            locale: const Locale('ar'),
            theme: AppTheme.lightTheme,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: EventCommandCenter(groupId: event.groupId, eventId: event.id),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(EventKeys.openRecapBanner), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('#382 PR-5 — per-currency header', () {
    testWidgets('settled in OMR but owing in USD — header is NOT settled', (
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
        amount: Decimal.parse('15.00'),
        currency: 'USD',
      );

      await tester.pumpWidget(
        _wrap(
          event: event,
          expenses: [expense],
          buckets: {
            'OMR': _settledBalances,
            'USD': [
              _balance(
                uid: 'uid-1',
                name: 'Mona',
                net: Decimal.parse('-15.00'),
              ),
              _balance(
                uid: 'uid-2',
                name: 'Nasser',
                net: Decimal.parse('15.00'),
              ),
            ],
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('All settled'), findsNothing);
      expect(find.text('YOU OWE'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(EventKeys.balanceHeader),
          matching: find.textContaining('USD'),
        ),
        findsWidgets,
      );
    });

    testWidgets(
      'mixed signs — both bucket lines render, no tri-state overline',
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
          _wrap(
            event: event,
            expenses: [expense],
            buckets: {
              'OMR': _userOwedBalances,
              'USD': [
                _balance(
                  uid: 'uid-1',
                  name: 'Mona',
                  net: Decimal.parse('-15.00'),
                ),
                _balance(
                  uid: 'uid-2',
                  name: 'Nasser',
                  net: Decimal.parse('15.00'),
                ),
              ],
            },
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('YOU ARE OWED'), findsNothing);
        expect(find.text('YOU OWE'), findsNothing);
        expect(find.text('All settled'), findsNothing);
        final header = find.byKey(EventKeys.balanceHeader);
        expect(
          find.descendant(of: header, matching: find.textContaining('10.000')),
          findsWidgets,
        );
        expect(
          find.descendant(of: header, matching: find.textContaining('USD')),
          findsWidgets,
        );
      },
    );

    testWidgets(
      'L13: sub-tolerance residual is NOT settled (exact-zero gate)',
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
          _wrap(
            event: event,
            expenses: [expense],
            buckets: {
              'OMR': [
                _balance(
                  uid: 'uid-1',
                  name: 'Mona',
                  net: Decimal.parse('0.0005'),
                ),
                _balance(
                  uid: 'uid-2',
                  name: 'Nasser',
                  net: Decimal.parse('-0.0005'),
                ),
              ],
            },
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('All settled'), findsNothing);
        expect(find.text('YOU ARE OWED'), findsOneWidget);
      },
    );
  });
}

// ───────────────────────────── Helpers

Widget _wrap({
  required Event event,
  List<Expense> expenses = const [],
  List<UserBalance>? balances,
  Map<String, List<UserBalance>>? buckets,
  String currency = 'OMR',
}) {
  final eventRef = (groupId: event.groupId, eventId: event.id);
  return ProviderScope(
    overrides: [
      currentUserIdProvider.overrideWithValue('uid-1'),
      eventDetailProvider(
        eventRef,
      ).overrideWith((_) => Stream<Event?>.value(event)),
      groupDetailProvider(event.groupId).overrideWith(
        (_) => Stream<Group?>.value(_group.copyWith(currency: currency)),
      ),
      eventExpensesProvider(
        eventRef,
      ).overrideWith((_) => Stream.value(expenses)),
      eventSettlementsProvider(
        eventRef,
      ).overrideWith((_) => Stream.value(const [])),
      groupMembersProvider(event.groupId).overrideWith(
        (_) => Stream.value([
          _realMember('uid-1', 'Mona'),
          _realMember('uid-2', 'Nasser'),
        ]),
      ),
      if (balances != null || buckets != null)
        ledgerViewProvider(eventRef).overrideWithValue(
          _ledgerView(
            event: event,
            expenses: expenses,
            balances: buckets ?? {currency: balances!},
          ),
        ),
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
              GoRoute(
                path: 'recap',
                builder: (_, state) => Scaffold(
                  body: Text('RecapRoute:${state.pathParameters['eid']}'),
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
        groupMembersProvider(event.groupId).overrideWith(
          (_) => Stream.value([
            _realMember('uid-1', 'Mona'),
            _realMember('uid-2', 'Nasser'),
          ]),
        ),
        if (balances != null)
          ledgerViewProvider(eventRef).overrideWithValue(
            _ledgerView(
              event: event,
              expenses: expenses,
              balances: {'OMR': balances},
            ),
          ),
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

Event _event({
  required DateTime startDate,
  required DateTime endDate,
  EventType type = EventType.trip,
  bool isClosed = false,
  String? closedBy,
}) {
  return Event(
    id: 'event-1',
    name: 'Marrakech',
    type: type,
    groupId: 'group-1',
    createdBy: 'uid-1',
    participantIds: const ['uid-1', 'uid-2'],
    participantNames: const {'uid-1': 'Mona', 'uid-2': 'Nasser'},
    modules: const EventModules(),
    startDate: startDate,
    endDate: endDate,
    createdAt: startDate,
    isClosed: isClosed,
    closedAt: isClosed ? DateTime(2026, 5, 1) : null,
    closedBy: closedBy,
  );
}

Expense _expense({
  required String id,
  required String eventId,
  required String payer,
  required Decimal amount,
  String currency = 'OMR',
  String? categoryId,
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
    categoryId: categoryId,
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

/// Synthetic [LedgerView] for tests that inject pre-baked balances. The
/// tabbed shell reads `balances`, `eventTotal`, and `rosterDisplayNames`; the
/// embedded ledger panel additionally reads the display-name maps, which stay
/// empty (payer rows then render their fallbacks — fine for these tests).
LedgerView _ledgerView({
  required Event event,
  required List<Expense> expenses,
  required Map<String, List<UserBalance>> balances,
}) {
  return (
    participants: const [],
    balances: balances,
    eventTotal: BalanceCalculator.calculateTotalExpensesByCurrency(expenses),
    rosterDisplayNames: {
      for (final id in event.participantIds)
        if (event.participantNames[id] != null) id: event.participantNames[id]!,
    },
    expensePayerDisplayNames: const {},
    settlementDisplayNames: const {},
    owedByExpenseId: const {},
  );
}

GroupMember _realMember(String uid, String name) => GroupMember(
  id: 'doc-$uid',
  groupId: 'group-1',
  userId: uid,
  displayName: name,
  role: 'member',
  joinedAt: DateTime(2026, 1, 1),
);

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
