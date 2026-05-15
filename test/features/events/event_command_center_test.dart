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
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';

void main() {
  testWidgets('renders current day badge when event is in progress', (
    tester,
  ) async {
    final today = DateUtils.dateOnly(DateTime.now());
    final event = _event(
      startDate: today.subtract(const Duration(days: 2)),
      endDate: today.add(const Duration(days: 4)),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          eventDetailProvider((
            groupId: 'group-1',
            eventId: 'event-1',
          )).overrideWith((_) => Stream<Event?>.value(event)),
          groupDetailProvider(
            'group-1',
          ).overrideWith((_) => Stream<Group?>.value(_group)),
          eventExpensesProvider((
            groupId: 'group-1',
            eventId: 'event-1',
          )).overrideWith((_) => Stream.value(const [])),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const EventCommandCenter(
            groupId: 'group-1',
            eventId: 'event-1',
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byKey(EventKeys.dayBadge), findsOneWidget);
    expect(find.text('Day 3 of 7'), findsOneWidget);
  });

  testWidgets('ledger module card routes to the event ledger path', (
    tester,
  ) async {
    final event = _event(
      startDate: DateTime(2026, 1, 1),
      endDate: DateTime(2026, 1, 3),
    );

    await _pumpEventHubRouter(tester, event);

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

  testWidgets('expense hero routes to the event ledger path', (tester) async {
    final event = _event(
      startDate: DateTime(2026, 1, 1),
      endDate: DateTime(2026, 1, 3),
    );

    await _pumpEventHubRouter(tester, event);

    await tester.tap(find.byKey(EventKeys.addExpenseChip));
    await tester.pumpAndSettle();

    expect(find.text('LedgerRoute:event-1'), findsOneWidget);
  });

  testWidgets('activity module card routes to the event activity path', (
    tester,
  ) async {
    final event = _event(
      startDate: DateTime(2026, 1, 1),
      endDate: DateTime(2026, 1, 3),
    );

    await _pumpEventHubRouter(tester, event);

    await tester.tap(find.byKey(EventKeys.activityCard));
    await tester.pumpAndSettle();

    expect(find.text('ActivityRoute:event-1'), findsOneWidget);
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

Future<void> _pumpEventHubRouter(WidgetTester tester, Event event) async {
  final router = GoRouter(
    initialLocation: '/group/group-1/event/event-1',
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
              ),
              GoRoute(
                path: 'activity',
                builder: (_, state) => Scaffold(
                  body: Text('ActivityRoute:${state.pathParameters['eid']}'),
                ),
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
        eventDetailProvider((
          groupId: 'group-1',
          eventId: 'event-1',
        )).overrideWith((_) => Stream<Event?>.value(event)),
        groupDetailProvider(
          'group-1',
        ).overrideWith((_) => Stream<Group?>.value(_group)),
        eventExpensesProvider((
          groupId: 'group-1',
          eventId: 'event-1',
        )).overrideWith((_) => Stream.value(const [])),
        eventSettlementsProvider((
          groupId: 'group-1',
          eventId: 'event-1',
        )).overrideWith((_) => Stream.value(const [])),
      ],
      child: MaterialApp.router(
        theme: AppTheme.lightTheme,
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

final _group = Group(
  id: 'group-1',
  name: 'Friends',
  inviteCode: 'ABC123',
  createdBy: 'uid-1',
  memberIds: const ['uid-1', 'uid-2'],
  createdAt: DateTime(2026, 1, 1),
);
