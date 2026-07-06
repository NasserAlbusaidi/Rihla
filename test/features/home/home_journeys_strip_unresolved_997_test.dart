import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/auth/providers/auth_provider.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/home/keys/home_keys.dart';
import 'package:safar/features/home/providers/dashboard_providers.dart';
import 'package:safar/features/home/screens/home_screen.dart';
import 'package:safar/features/home/widgets/journey_ticket_card.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

// ---------------------------------------------------------------------------
// #997 refute follow-up — `activeJourneysProvider` used to `continue`-skip a
// group's tickets entirely while its balance facade was loading/errored. If
// EVERY active group's facade is unresolved (the sustained-flaky-network
// condition #997 is about), the provider returns `data([])`, and
// `_JourneysStrip` renders that as the "No upcoming journeys" empty state —
// a false negative on the primary home surface, worse than the false
// "0.000 settled" the rest of this PR fixes. Ticket EXISTENCE must come from
// `groupEventsProvider` alone; only the net DISPLAY suppresses while the
// balance facade is unresolved.
// ---------------------------------------------------------------------------

Group _makeGroup(String id, String name) => Group(
  id: id,
  name: name,
  inviteCode: 'ABC123',
  createdBy: 'test-user-id',
  memberIds: const ['test-user-id'],
  currency: 'OMR',
  createdAt: DateTime(2026, 1, 1),
);

Event _makeActiveEvent({required String id, required String groupId}) =>
    Event(
      id: id,
      name: 'Event $id',
      type: EventType.trip,
      groupId: groupId,
      createdBy: 'test-user-id',
      participantIds: const ['test-user-id'],
      participantNames: const {'test-user-id': 'Nasser'},
      modules: const EventModules(),
      startDate: DateTime.now().subtract(const Duration(days: 1)),
      endDate: DateTime.now().add(const Duration(days: 1)),
      createdAt: DateTime.now().subtract(const Duration(days: 1)),
    );

List<Override> _baseOverrides(Group group, Event event) => [
  currentUserIdProvider.overrideWithValue('test-user-id'),
  userGroupsProvider.overrideWith((ref) => Stream.value([group])),
  crossGroupHomeBalanceProvider.overrideWith(
    (ref) => const AsyncValue.data((
      balance: (
        byCurrency: <CurrencyBalance>[],
        groupCount: 1,
        isLoading: false,
      ),
      partial: false,
    )),
  ),
  crossGroupActivityProvider.overrideWith((ref) => const AsyncValue.data([])),
  groupBalancesProvider.overrideWith(
    (ref, groupId) => const AsyncValue.data((
      balances: <String, List<UserBalance>>{},
      totalSpent: <String, Decimal>{},
      eventCount: 0,
      perEventBreakdown: <String, Map<String, Map<String, Decimal>>>{},
      memberNames: <String, String>{},
      memberRawNames: <String, String>{},
    )),
  ),
  groupEventsProvider.overrideWith((ref, groupId) => Stream.value([event])),
];

Widget _buildTestApp({
  required List<Override> overrides,
  required SharedPreferences prefs,
}) {
  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(path: '/home', builder: (ctx, state) => const HomeScreen()),
      GoRoute(
        path: '/group/:gid/event/:eid',
        builder: (ctx, state) =>
            Scaffold(body: Text('Event:${state.pathParameters['eid']}')),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      linkedEmailProvider.overrideWithValue('secured@example.com'),
      isDurableUserProvider.overrideWithValue(true),
      ...overrides,
    ],
    child: MaterialApp.router(
      theme: AppTheme.lightTheme,
      routerConfig: router,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    ),
  );
}

/// `_GroupRow`'s trailing balance skeleton shimmers via `Skeletonizer` — as
/// does the journeys strip's own loading placeholder — so `pumpAndSettle`
/// never terminates. Pump a bounded number of frames instead.
Future<void> _pumpFrames(WidgetTester tester, {int times = 24}) async {
  for (var i = 0; i < times; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  testWidgets(
    'a loading balance facade keeps the journey ticket visible — no false '
    '"No upcoming journeys" empty state',
    (tester) async {
      final group = _makeGroup('g1', 'Desert Crew');
      final event = _makeActiveEvent(id: 'e1', groupId: 'g1');
      await tester.pumpWidget(
        _buildTestApp(
          prefs: prefs,
          overrides: [
            ..._baseOverrides(group, event),
            homeGroupBalanceProvider.overrideWith(
              (ref, groupId) => const AsyncValue.loading(),
            ),
          ],
        ),
      );
      await _pumpFrames(tester);

      expect(
        find.text('No upcoming or active journeys'),
        findsNothing,
        reason:
            'a real active journey must not vanish behind a loading '
            'balance facade',
      );
      expect(
        find.byType(JourneyTicketCard),
        findsOneWidget,
        reason:
            'ticket existence comes from groupEventsProvider, not the '
            'balance facade',
      );
      expect(
        find.byKey(HomeKeys.journeyTicketBalanceUnresolved),
        findsOneWidget,
        reason:
            'the unresolved balance must render a neutral affordance, not '
            'a false 0.000',
      );
    },
  );

  testWidgets(
    'a sticky-errored balance facade keeps the journey ticket visible — no '
    'false "No upcoming journeys" empty state',
    (tester) async {
      final group = _makeGroup('g1', 'Desert Crew');
      final event = _makeActiveEvent(id: 'e1', groupId: 'g1');
      await tester.pumpWidget(
        _buildTestApp(
          prefs: prefs,
          overrides: [
            ..._baseOverrides(group, event),
            homeGroupBalanceProvider.overrideWith(
              (ref, groupId) =>
                  AsyncValue.error(Exception('denied'), StackTrace.empty),
            ),
          ],
        ),
      );
      await _pumpFrames(tester);

      expect(find.text('No upcoming or active journeys'), findsNothing);
      expect(find.byType(JourneyTicketCard), findsOneWidget);
      expect(
        find.byKey(HomeKeys.journeyTicketBalanceUnresolved),
        findsOneWidget,
      );
    },
  );
}
