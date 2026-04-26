import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
  memberNames: <String, String>{
    'uid-creator': 'Alice',
    'uid-member': 'Bob',
  },
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
  memberNames: <String, String>{
    'uid-creator': 'Alice',
    'uid-member': 'Bob',
  },
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
      groupDetailProvider(_groupId).overrideWith(
        (ref) => Stream.value(_testGroup),
      ),
      groupMembersProvider(_groupId).overrideWith(
        (ref) => Stream.value(_testMembers),
      ),
      groupEventsProvider(_groupId).overrideWith(
        (ref) => Stream.value(const []),
      ),
      groupBalancesProvider(_groupId).overrideWith(
        (ref) => balancesAsync,
      ),
      groupActivityProvider(_groupId).overrideWith(
        (ref) => Stream.value(activities),
      ),
    ],
    child: MaterialApp(theme: AppTheme.lightTheme, home: child),
  );
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

  group('GroupDetailScreen financial sections', () {
    testWidgets('shows stats grid when expenses exist', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const GroupDetailScreen(groupId: _groupId),
          prefs,
          balancesAsync: AsyncValue.data(_balancesWithExpenses),
        ),
      );
      await tester.pumpAndSettle();

      // Stats grid replaces GroupBalanceHero (D-08)
      expect(find.byKey(GroupKeys.statsGrid), findsOneWidget);
    });

    testWidgets(
        'stats grid is always visible; settle-up CTA hidden when zero balance',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          const GroupDetailScreen(groupId: _groupId),
          prefs,
          balancesAsync: AsyncValue.data(_balancesEmpty),
        ),
      );
      await tester.pumpAndSettle();

      // Stats grid is always shown (D-08) — replaces the conditional hero
      expect(find.byKey(GroupKeys.statsGrid), findsOneWidget);
      // Settle-up CTA must be hidden when all balances are zero (D-10)
      expect(find.byKey(GroupKeys.settleUpCta), findsNothing);
    });

    testWidgets('shows Members & Balances section with GroupMemberBalanceCard tiles',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          const GroupDetailScreen(groupId: _groupId),
          prefs,
          balancesAsync: AsyncValue.data(_balancesWithExpenses),
        ),
      );
      await tester.pumpAndSettle();

      // Section header renamed from "Members" to "Members & Balances"
      expect(find.byKey(GroupKeys.membersAndBalancesSection), findsOneWidget);

      // Member names rendered via GroupMemberBalanceCard header rows
      expect(find.text('Alice'), findsWidgets);
      expect(find.text('Bob'), findsOneWidget);
    });

    testWidgets('shows spending stats chips when expenses exist', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const GroupDetailScreen(groupId: _groupId),
          prefs,
          balancesAsync: AsyncValue.data(_balancesWithExpenses),
        ),
      );
      await tester.pumpAndSettle();

      // GroupSpendingStats renders a chip containing the formatted total
      // e.g. "OMR 30.000 across 1 events"
      expect(find.textContaining('30.000'), findsWidgets);
    });

    testWidgets('shows Recent Activity section', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const GroupDetailScreen(groupId: _groupId),
          prefs,
          balancesAsync: AsyncValue.data(_balancesEmpty),
          activities: _testActivity,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(GroupKeys.recentActivitySection), findsOneWidget);
    });

    testWidgets('shows See all activity button', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const GroupDetailScreen(groupId: _groupId),
          prefs,
          balancesAsync: AsyncValue.data(_balancesEmpty),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(GroupKeys.seeAllActivityButton), findsOneWidget);
    });

    testWidgets('invite code section is not rendered (D-05 — moved to Phase 29)',
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
    });

    testWidgets('stats grid shows 4 stat tiles', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const GroupDetailScreen(groupId: _groupId),
          prefs,
          balancesAsync: AsyncValue.data(_balancesWithExpenses),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(GroupKeys.statsGrid), findsOneWidget);
      expect(find.byKey(GroupKeys.statYourBalance), findsOneWidget);
      expect(find.byKey(GroupKeys.statGroupTotal), findsOneWidget);
      expect(find.byKey(GroupKeys.statActiveMembers), findsOneWidget);
      expect(find.byKey(GroupKeys.statEvents), findsOneWidget);
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

    testWidgets('hides settle-up CTA when all balances are zero',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          const GroupDetailScreen(groupId: _groupId),
          prefs,
          balancesAsync: AsyncValue.data(_balancesEmpty),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(GroupKeys.settleUpCta), findsNothing);
    });

    testWidgets('section order: Events before Members before Activity (D-09)',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          const GroupDetailScreen(groupId: _groupId),
          prefs,
          balancesAsync: AsyncValue.data(_balancesEmpty),
          activities: _testActivity,
        ),
      );
      await tester.pumpAndSettle();

      final eventsOffset =
          tester.getTopLeft(find.byKey(GroupKeys.eventsSection).first);
      final membersOffset =
          tester.getTopLeft(find.byKey(GroupKeys.membersAndBalancesSection).first);
      final activityOffset =
          tester.getTopLeft(find.byKey(GroupKeys.recentActivitySection).first);

      // Events < Members < Activity (lower Y = higher on screen)
      expect(eventsOffset.dy, lessThan(membersOffset.dy));
      expect(membersOffset.dy, lessThan(activityOffset.dy));
    });

    testWidgets('has RefreshIndicator wrapping scrollable content (D-11)',
        (tester) async {
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

    testWidgets('shows inline error with retry button when group fails to load (D-12)',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            currentUserIdProvider.overrideWithValue('uid-creator'),
            groupDetailProvider(_groupId).overrideWith(
              (ref) => Stream.error(Exception('Network error')),
            ),
            groupMembersProvider(_groupId).overrideWith(
              (ref) => Stream.value(_testMembers),
            ),
            groupEventsProvider(_groupId).overrideWith(
              (ref) => Stream.value(const []),
            ),
            groupBalancesProvider(_groupId).overrideWith(
              (ref) => AsyncValue.data(_balancesEmpty),
            ),
            groupActivityProvider(_groupId).overrideWith(
              (ref) => Stream.value(const []),
            ),
          ],
          child: MaterialApp(
           theme: AppTheme.lightTheme,
            home: GroupDetailScreen(groupId: _groupId),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Error state shows inline message, not full-screen replacement
      expect(find.text('Failed to load group'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);

      // ModuleHeader is still visible in error state (inline, not full replacement)
      expect(find.text('Group'), findsOneWidget);
    });

    testWidgets('event card shows personal balance when provided',
        (tester) async {
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
            eventExpensesProvider(
              (groupId: _groupId, eventId: 'event-1'),
            ).overrideWith((ref) => Stream.value(const [])),
          ],
          child: MaterialApp(theme: AppTheme.lightTheme, home: Scaffold(
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
