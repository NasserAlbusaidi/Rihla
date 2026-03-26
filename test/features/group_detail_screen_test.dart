import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/features/events/providers/event_provider.dart';
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
/// groupBalancesProvider, and groupActivityProvider to prevent Firestore calls
/// in widget tests.
Widget _wrap(
  Widget child,
  SharedPreferences prefs, {
  required AsyncValue<GroupBalances> balancesAsync,
  List<GroupActivityLog> activities = const [],
}) {
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
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
    child: MaterialApp(home: child),
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
    testWidgets('shows GroupBalanceHero when expenses exist', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const GroupDetailScreen(groupId: _groupId),
          prefs,
          balancesAsync: AsyncValue.data(_balancesWithExpenses),
        ),
      );
      await tester.pumpAndSettle();

      // GroupBalanceHero renders "GROUP BALANCES" label
      expect(find.text('GROUP BALANCES'), findsOneWidget);
    });

    testWidgets('hides GroupBalanceHero when no expenses exist (D-19)',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          const GroupDetailScreen(groupId: _groupId),
          prefs,
          balancesAsync: AsyncValue.data(_balancesEmpty),
        ),
      );
      await tester.pumpAndSettle();

      // GroupBalanceHero must NOT be shown when totalSpent == 0
      expect(find.text('GROUP BALANCES'), findsNothing);
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
      expect(find.text('Members & Balances'), findsOneWidget);

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

      expect(find.text('Recent Activity'), findsOneWidget);
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

      expect(find.text('See all activity'), findsOneWidget);
    });

    testWidgets('invite code section appears below events section (D-30)',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          const GroupDetailScreen(groupId: _groupId),
          prefs,
          balancesAsync: AsyncValue.data(_balancesEmpty),
        ),
      );
      await tester.pumpAndSettle();

      // Both "Events" and "Invite Code" headers should be visible
      expect(find.text('Events'), findsOneWidget);
      expect(find.text('Invite Code'), findsOneWidget);

      // Verify layout order: Events appears before Invite Code in the widget tree.
      // We find their positions via renderObject coordinates.
      final eventsOffset =
          tester.getTopLeft(find.text('Events').first);
      final inviteOffset =
          tester.getTopLeft(find.text('Invite Code').first);

      // Invite Code section must be below the Events section (higher Y coordinate)
      expect(inviteOffset.dy, greaterThan(eventsOffset.dy));
    });
  });
}
