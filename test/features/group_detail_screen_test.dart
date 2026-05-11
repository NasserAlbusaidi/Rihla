import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/features/events/models/event_model.dart'
    show Event, EventModules, EventType;
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/events/widgets/event_card.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';
import 'package:safar/features/groups/keys/group_keys.dart';
import 'package:safar/features/groups/models/group_activity_log_model.dart';
import 'package:safar/features/groups/models/group_member_model.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/groups/screens/group_detail_screen.dart';
import 'package:safar/features/ledger/models/expense_model.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _groupId = 'group-1';

final _testGroup = Group(
  id: _groupId,
  name: 'Adventure Crew',
  inviteCode: 'ABC123',
  createdBy: 'uid-creator',
  memberIds: const ['uid-creator', 'uid-member'],
  currency: 'OMR',
  createdAt: DateTime(2026, 1, 1),
);

final _testMembers = [
  GroupMember(
    id: 'mem-1',
    groupId: _groupId,
    userId: 'uid-creator',
    displayName: 'Alice',
    role: 'CREATOR',
    joinedAt: DateTime(2026, 1, 1),
  ),
  GroupMember(
    id: 'mem-2',
    groupId: _groupId,
    userId: 'uid-member',
    displayName: 'Bob',
    role: 'MEMBER',
    joinedAt: DateTime(2026, 1, 2),
  ),
];

/// GroupBalances with totalSpent > 0 (expenses exist).
final _balancesWithExpenses = (
  balances: <UserBalance>[
    UserBalance(
      participantId: 'uid-creator',
      displayName: 'Alice',
      totalPaid: Decimal.parse('30.000'),
      totalOwed: Decimal.parse('15.000'),
      netBalance: Decimal.parse('15.000'),
    ),
    UserBalance(
      participantId: 'uid-member',
      displayName: 'Bob',
      totalPaid: Decimal.parse('0.000'),
      totalOwed: Decimal.parse('15.000'),
      netBalance: Decimal.parse('-15.000'),
    ),
  ],
  totalSpent: Decimal.parse('30.000'),
  eventCount: 1,
  perEventBreakdown: <String, Map<String, Decimal>>{
    'uid-creator': {'event-1': Decimal.parse('15.000')},
    'uid-member': {'event-1': Decimal.parse('-15.000')},
  },
  memberNames: <String, String>{'uid-creator': 'Alice', 'uid-member': 'Bob'},
);

/// GroupBalances with totalSpent == 0 (no expenses yet).
final _balancesEmpty = (
  balances: <UserBalance>[
    UserBalance(
      participantId: 'uid-creator',
      displayName: 'Alice',
      totalPaid: Decimal.zero,
      totalOwed: Decimal.zero,
      netBalance: Decimal.zero,
    ),
    UserBalance(
      participantId: 'uid-member',
      displayName: 'Bob',
      totalPaid: Decimal.zero,
      totalOwed: Decimal.zero,
      netBalance: Decimal.zero,
    ),
  ],
  totalSpent: Decimal.zero,
  eventCount: 0,
  perEventBreakdown: <String, Map<String, Decimal>>{},
  memberNames: <String, String>{'uid-creator': 'Alice', 'uid-member': 'Bob'},
);

final _testActivity = [
  GroupActivityLog(
    id: 'act-1',
    type: 'event_created',
    actorId: 'uid-creator',
    actorName: 'Alice',
    description: 'created an event',
    timestamp: DateTime(2026, 1, 15),
  ),
];

/// Wraps a widget with ProviderScope + MaterialApp.
///
/// Overrides groupDetailProvider, groupMembersProvider, groupEventsProvider,
/// groupBalancesProvider, groupActivityProvider, and currentUserIdProvider to
/// prevent Firestore calls in widget tests.
///
/// [currentUid] defaults to 'uid-creator' so settle-up CTA tests work without
/// a real Firebase Auth instance.
Widget _wrap(
  Widget child,
  SharedPreferences prefs, {
  required AsyncValue<GroupBalances> balancesAsync,
  List<GroupActivityLog> activities = const [],
  String? currentUid = 'uid-creator',
}) {
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      currentUserIdProvider.overrideWithValue(currentUid),
      groupDetailProvider(
        _groupId,
      ).overrideWith((ref) => Stream.value(_testGroup)),
      groupMembersProvider(
        _groupId,
      ).overrideWith((ref) => Stream.value(_testMembers)),
      groupEventsProvider(
        _groupId,
      ).overrideWith((ref) => Stream.value(const [])),
      groupBalancesProvider(_groupId).overrideWith((ref) => balancesAsync),
      groupActivityProvider(
        _groupId,
      ).overrideWith((ref) => Stream.value(activities)),
    ],
    child: MaterialApp(theme: AppTheme.lightTheme, home: child),
  );
}

Finder _textContaining(String value) {
  return find.byWidgetPredicate((widget) {
    if (widget is! Text) return false;
    return (widget.data?.contains(value) ?? false) ||
        (widget.textSpan?.toPlainText().contains(value) ?? false);
  });
}

Future<void> _scrollUntilVisible(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    260,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late SharedPreferences prefs;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({'device_name': 'Test User'});
    prefs = await SharedPreferences.getInstance();
  });

  group('GroupDetailScreen current layout', () {
    testWidgets('shows cover header and balance card when balances load', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const GroupDetailScreen(groupId: _groupId),
          prefs,
          balancesAsync: AsyncValue.data(_balancesWithExpenses),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(GroupKeys.detailScreen), findsOneWidget);
      expect(find.text('Adventure Crew'), findsOneWidget);
      expect(find.text('GROUP · 2 MEMBERS'), findsOneWidget);
      expect(find.text('Your balance here'), findsOneWidget);
      expect(_textContaining('15.000'), findsWidgets);
      expect(find.text('they owe you'), findsOneWidget);
      expect(find.byKey(GroupKeys.settleUpCta), findsOneWidget);
    });

    testWidgets('zero balance shows all-settled state and settle-up path', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const GroupDetailScreen(groupId: _groupId),
          prefs,
          balancesAsync: AsyncValue.data(_balancesEmpty),
        ),
      );
      await tester.pumpAndSettle();

      expect(_textContaining('0.000'), findsWidgets);
      expect(find.text('all settled'), findsOneWidget);
      expect(find.byKey(GroupKeys.settleUpCta), findsOneWidget);
    });

    testWidgets('shows Members section with balance rows', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const GroupDetailScreen(groupId: _groupId),
          prefs,
          balancesAsync: AsyncValue.data(_balancesWithExpenses),
        ),
      );
      await tester.pumpAndSettle();

      await _scrollUntilVisible(
        tester,
        find.byKey(GroupKeys.membersAndBalancesSection),
      );

      expect(find.byKey(GroupKeys.membersAndBalancesSection), findsOneWidget);
      expect(find.text('MEMBERS'), findsOneWidget);

      expect(find.text('Alice'), findsWidgets);
      expect(find.text('Bob'), findsOneWidget);
    });

    testWidgets('shows current user balance amount when expenses exist', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const GroupDetailScreen(groupId: _groupId),
          prefs,
          balancesAsync: AsyncValue.data(_balancesWithExpenses),
        ),
      );
      await tester.pumpAndSettle();

      expect(_textContaining('15.000'), findsWidgets);
      expect(find.text('they owe you'), findsOneWidget);
    });

    testWidgets('keeps activity out of the inline group detail feed', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const GroupDetailScreen(groupId: _groupId),
          prefs,
          balancesAsync: AsyncValue.data(_balancesEmpty),
          activities: _testActivity,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(GroupKeys.recentActivitySection), findsNothing);
      expect(find.text('created an event'), findsNothing);
    });

    testWidgets('overflow menu exposes settings and activity destinations', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const GroupDetailScreen(groupId: _groupId),
          prefs,
          balancesAsync: AsyncValue.data(_balancesEmpty),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();

      expect(find.text('Group settings'), findsOneWidget);
      expect(find.text('Activity'), findsOneWidget);
    });

    testWidgets(
      'invite code section is not rendered (D-05 — moved to Phase 29)',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            const GroupDetailScreen(groupId: _groupId),
            prefs,
            balancesAsync: AsyncValue.data(_balancesEmpty),
          ),
        );
        await tester.pumpAndSettle();

        // Invite code section removed from GroupDetailScreen per D-05
        expect(find.byKey(GroupKeys.inviteCodeSection), findsNothing);
      },
    );

    testWidgets('stats grid from the old layout is no longer rendered', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const GroupDetailScreen(groupId: _groupId),
          prefs,
          balancesAsync: AsyncValue.data(_balancesWithExpenses),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(GroupKeys.statsGrid), findsNothing);
      expect(find.byKey(GroupKeys.statYourBalance), findsNothing);
      expect(find.byKey(GroupKeys.statGroupTotal), findsNothing);
      expect(find.byKey(GroupKeys.statActiveMembers), findsNothing);
      expect(find.byKey(GroupKeys.statEvents), findsNothing);
    });

    testWidgets('shows settle-up CTA when balance is non-zero', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const GroupDetailScreen(groupId: _groupId),
          prefs,
          balancesAsync: AsyncValue.data(_balancesWithExpenses),
        ),
      );
      await tester.pumpAndSettle();

      // Current user (uid-creator) has netBalance of 15.000 — CTA must appear
      expect(find.byKey(GroupKeys.settleUpCta), findsOneWidget);
    });

    testWidgets('keeps settle-up CTA visible when all balances are zero', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const GroupDetailScreen(groupId: _groupId),
          prefs,
          balancesAsync: AsyncValue.data(_balancesEmpty),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(GroupKeys.settleUpCta), findsOneWidget);
    });

    testWidgets('section order: Events before Members; Activity is overflow', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const GroupDetailScreen(groupId: _groupId),
          prefs,
          balancesAsync: AsyncValue.data(_balancesEmpty),
          activities: _testActivity,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(GroupKeys.eventsSection), findsOneWidget);
      await _scrollUntilVisible(
        tester,
        find.byKey(GroupKeys.membersAndBalancesSection),
      );
      expect(find.byKey(GroupKeys.membersAndBalancesSection), findsOneWidget);
      expect(find.byKey(GroupKeys.recentActivitySection), findsNothing);
    });

    testWidgets('has RefreshIndicator wrapping scrollable content (D-11)', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const GroupDetailScreen(groupId: _groupId),
          prefs,
          balancesAsync: AsyncValue.data(_balancesEmpty),
        ),
      );
      await tester.pumpAndSettle();

      // RefreshIndicator must be present in the widget tree
      expect(find.byType(RefreshIndicator), findsOneWidget);
    });

    testWidgets('member sees event creation actions without a FAB', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const GroupDetailScreen(groupId: _groupId),
          prefs,
          balancesAsync: AsyncValue.data(_balancesEmpty),
          currentUid: 'uid-creator',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(FloatingActionButton), findsNothing);
      expect(find.text('New event'), findsWidgets);
      expect(find.text('Create Event'), findsOneWidget);
    });

    testWidgets('member can create events through the same group actions', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const GroupDetailScreen(groupId: _groupId),
          prefs,
          balancesAsync: AsyncValue.data(_balancesEmpty),
          currentUid: 'uid-member',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(FloatingActionButton), findsNothing);
      expect(find.text('New event'), findsWidgets);
      expect(find.text('Create Event'), findsOneWidget);
    });

    testWidgets('creator sees empty events create action', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const GroupDetailScreen(groupId: _groupId),
          prefs,
          balancesAsync: AsyncValue.data(_balancesEmpty),
          currentUid: 'uid-creator',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(GroupKeys.noEventsEmpty), findsOneWidget);
      expect(find.text('Create Event'), findsOneWidget);
    });

    testWidgets('member sees empty events create action', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const GroupDetailScreen(groupId: _groupId),
          prefs,
          balancesAsync: AsyncValue.data(_balancesEmpty),
          currentUid: 'uid-member',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(GroupKeys.noEventsEmpty), findsOneWidget);
      expect(find.text('Create Event'), findsOneWidget);
      expect(
        find.text('Create your first event to start planning together.'),
        findsOneWidget,
      );
    });

    testWidgets('tapping event card navigates to ledger route', (tester) async {
      final testEvent = Event(
        id: 'event-1',
        groupId: _groupId,
        name: 'Beach Trip',
        type: EventType.trip,
        createdAt: DateTime(2026, 1, 10),
        participantIds: const ['uid-creator', 'uid-member'],
        participantNames: const {'uid-creator': 'Alice', 'uid-member': 'Bob'},
        modules: const EventModules(),
        createdBy: 'uid-creator',
      );
      final eventRef = (groupId: _groupId, eventId: testEvent.id);
      final navigatedRoutes = <String>[];

      final router = GoRouter(
        initialLocation: '/group/$_groupId',
        routes: [
          GoRoute(
            path: '/group/:gid',
            builder: (context, state) => ProviderScope(
              overrides: [
                sharedPreferencesProvider.overrideWithValue(prefs),
                currentUserIdProvider.overrideWithValue('uid-creator'),
                groupDetailProvider(
                  _groupId,
                ).overrideWith((ref) => Stream.value(_testGroup)),
                groupMembersProvider(
                  _groupId,
                ).overrideWith((ref) => Stream.value(_testMembers)),
                groupEventsProvider(
                  _groupId,
                ).overrideWith((ref) => Stream.value([testEvent])),
                groupBalancesProvider(
                  _groupId,
                ).overrideWith((ref) => AsyncValue.data(_balancesWithExpenses)),
                groupActivityProvider(
                  _groupId,
                ).overrideWith((ref) => Stream.value(const [])),
                eventExpensesProvider(
                  eventRef,
                ).overrideWith((ref) => Stream.value(const [])),
              ],
              child: GroupDetailScreen(groupId: state.pathParameters['gid']!),
            ),
            routes: [
              GoRoute(
                path: 'event/:eid',
                builder: (context, state) {
                  navigatedRoutes.add(
                    '/group/${state.pathParameters['gid']}'
                    '/event/${state.pathParameters['eid']}',
                  );
                  return const Scaffold(body: Text('Event hub'));
                },
                routes: [
                  GoRoute(
                    path: 'ledger',
                    builder: (context, state) {
                      navigatedRoutes.add(
                        '/group/${state.pathParameters['gid']}'
                        '/event/${state.pathParameters['eid']}/ledger',
                      );
                      return const Scaffold(body: Text('Ledger'));
                    },
                  ),
                ],
              ),
            ],
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp.router(theme: AppTheme.lightTheme, routerConfig: router),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Beach Trip'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Beach Trip'));
      await tester.pumpAndSettle();

      expect(
        navigatedRoutes,
        contains('/group/$_groupId/event/${testEvent.id}/ledger'),
      );
    });

    testWidgets(
      'shows inline error with retry button when group fails to load (D-12)',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              sharedPreferencesProvider.overrideWithValue(prefs),
              currentUserIdProvider.overrideWithValue('uid-creator'),
              groupDetailProvider(
                _groupId,
              ).overrideWith((ref) => Stream.error(Exception('Network error'))),
              groupMembersProvider(
                _groupId,
              ).overrideWith((ref) => Stream.value(_testMembers)),
              groupEventsProvider(
                _groupId,
              ).overrideWith((ref) => Stream.value(const [])),
              groupBalancesProvider(
                _groupId,
              ).overrideWith((ref) => AsyncValue.data(_balancesEmpty)),
              groupActivityProvider(
                _groupId,
              ).overrideWith((ref) => Stream.value(const [])),
            ],
            child: MaterialApp(
              theme: AppTheme.lightTheme,
              home: const GroupDetailScreen(groupId: _groupId),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Could not load group'), findsOneWidget);
        expect(
          find.text('Check your connection and try again.'),
          findsOneWidget,
        );
        expect(find.text('Retry'), findsOneWidget);
      },
    );

    testWidgets('event card shows personal balance when provided', (
      tester,
    ) async {
      final testEvent = Event(
        id: 'event-1',
        groupId: _groupId,
        name: 'Beach Trip',
        type: EventType.trip,
        createdAt: DateTime(2026, 1, 10),
        participantIds: const [],
        participantNames: const {},
        modules: const EventModules(),
        createdBy: 'uid-creator',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            eventExpensesProvider((
              groupId: _groupId,
              eventId: 'event-1',
            )).overrideWith((ref) => Stream.value(const [])),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(
              body: EventCard(
                event: testEvent,
                personalBalance: Decimal.parse('-5.000'),
                onTap: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Personal balance text must appear when personalBalance is non-null
      expect(find.textContaining('5.000'), findsWidgets);
    });
  });
}
