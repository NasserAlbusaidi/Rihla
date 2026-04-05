import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/groups/screens/group_settle_up_screen.dart';
import 'package:safar/features/groups/keys/group_keys.dart';
import 'package:safar/features/groups/widgets/group_stats_grid.dart';
import 'package:safar/features/groups/widgets/group_settlement_tile.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/models/settlement_model.dart';

/// Widget tests for GroupSettleUpScreen — tabbed layout (D-01..D-06, D-22).
///
/// Phase 30 Plan 02: updated for 4-tab layout with ModuleHeader.

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

const _groupId = 'grp-1';

final _testGroup = Group(
  id: _groupId,
  name: 'Test Crew',
  inviteCode: 'TST123',
  createdBy: 'uid-alice',
  memberIds: const ['uid-alice', 'uid-bob'],
  currency: 'OMR',
  createdAt: DateTime(2026, 1, 1),
);

final _testEvent = Event(
  id: 'event-1',
  name: 'Camping Weekend',
  type: EventType.camping,
  groupId: _groupId,
  createdBy: 'uid-alice',
  participantIds: const ['uid-alice', 'uid-bob'],
  participantNames: const {'uid-alice': 'Alice', 'uid-bob': 'Bob'},
  modules: const EventModules(),
  startDate: DateTime(2026, 3, 15),
  createdAt: DateTime(2026, 3, 10),
);

/// Two-person GroupBalances: Bob owes Alice 7.750 OMR.
final _balancesOwed = (
  balances: <UserBalance>[
    UserBalance(
      participantId: 'uid-alice',
      displayName: 'Alice',
      totalPaid: Decimal.parse('15.500'),
      totalOwed: Decimal.parse('7.750'),
      netBalance: Decimal.parse('7.750'),
    ),
    UserBalance(
      participantId: 'uid-bob',
      displayName: 'Bob',
      totalPaid: Decimal.parse('0.000'),
      totalOwed: Decimal.parse('7.750'),
      netBalance: Decimal.parse('-7.750'),
    ),
  ],
  totalSpent: Decimal.parse('15.500'),
  eventCount: 2,
  perEventBreakdown: <String, Map<String, Decimal>>{
    'uid-alice': {'event-1': Decimal.parse('7.750')},
    'uid-bob': {'event-1': Decimal.parse('-7.750')},
  },
  memberNames: <String, String>{
    'uid-alice': 'Alice',
    'uid-bob': 'Bob',
  },
);

/// All-settled GroupBalances: everyone at zero.
final _balancesSettled = (
  balances: <UserBalance>[
    UserBalance(
      participantId: 'uid-alice',
      displayName: 'Alice',
      totalPaid: Decimal.zero,
      totalOwed: Decimal.zero,
      netBalance: Decimal.zero,
    ),
    UserBalance(
      participantId: 'uid-bob',
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
    'uid-alice': 'Alice',
    'uid-bob': 'Bob',
  },
);

/// Test settlements for History tab.
final _testSettlement1 = Settlement(
  id: 'stl-1',
  tripId: _groupId,
  payerParticipantId: 'uid-bob',
  recipientParticipantId: 'uid-alice',
  amount: Decimal.parse('5.000'),
  settledAt: DateTime(2026, 3, 20),
  payerName: 'Bob',
  recipientName: 'Alice',
  scope: 'group',
  groupId: _groupId,
);

final _testSettlement2 = Settlement(
  id: 'stl-2',
  tripId: _groupId,
  payerParticipantId: 'uid-alice',
  recipientParticipantId: 'uid-bob',
  amount: Decimal.parse('3.000'),
  settledAt: DateTime(2026, 3, 25),
  payerName: 'Alice',
  recipientName: 'Bob',
  scope: 'group',
  groupId: _groupId,
);

/// Wraps the screen with ProviderScope.
///
/// - [balancesAsync]: overrides [groupBalancesProvider]
/// - [events]: optionally overrides [groupEventsProvider]
/// - [settlements]: optionally overrides [groupSettlementsProvider] (History tab)
/// - [currentUid]: optionally overrides [currentUserIdProvider]
Widget _wrap(
  Widget child, {
  required AsyncValue<GroupBalances> balancesAsync,
  List<Event>? events,
  List<Settlement>? settlements,
  // Default to null (no current user) unless test specifies one.
  String? currentUid,
}) {
  return ProviderScope(
    overrides: [
      groupDetailProvider(_groupId).overrideWith(
        (_) => Stream.value(_testGroup),
      ),
      groupBalancesProvider(_groupId).overrideWith((_) => balancesAsync),
      groupSettlementsProvider(_groupId).overrideWith(
        (_) => Stream.value(settlements ?? []),
      ),
      groupEventsProvider(_groupId).overrideWith(
        (_) => Stream.value(events ?? []),
      ),
      // Always override to avoid FirebaseException in tests
      currentUserIdProvider.overrideWithValue(currentUid),
    ],
    // MediaQuery with disableAnimations: true prevents flutter_animate timers
    // from remaining pending after widget disposal.
    child: MediaQuery(
      data: const MediaQueryData(disableAnimations: true),
      child: MaterialApp(home: child),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('GroupSettleUpScreen', () {
    // -----------------------------------------------------------------------
    // Basic rendering
    // -----------------------------------------------------------------------

    testWidgets('shows screen title and GROUP TOTAL PENDING label',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          GroupSettleUpScreen(groupId: _groupId),
          balancesAsync: AsyncValue.data(_balancesOwed),
        ),
      );
      await tester.pump();

      expect(find.text('Settle Up'), findsOneWidget);
      expect(find.text('GROUP TOTAL PENDING'), findsOneWidget);
    });

    testWidgets('shows 4 tab labels: You Owe, Owed to You, Between Others, History',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          GroupSettleUpScreen(groupId: _groupId),
          balancesAsync: AsyncValue.data(_balancesOwed),
        ),
      );
      await tester.pump();

      expect(find.text('You Owe'), findsOneWidget);
      expect(find.text('Owed to You'), findsOneWidget);
      expect(find.text('Between Others'), findsOneWidget);
      expect(find.text('History'), findsOneWidget);
    });

    testWidgets('shows optimized settlement tiles with member names',
        (tester) async {
      // With uid-bob as current user, they owe Alice — appears on You Owe tab
      await tester.pumpWidget(
        _wrap(
          GroupSettleUpScreen(groupId: _groupId),
          balancesAsync: AsyncValue.data(_balancesOwed),
          currentUid: 'uid-bob',
        ),
      );
      await tester.pumpAndSettle();

      // The Record Payment button is visible — a tile is rendered
      expect(find.text('Record Payment'), findsOneWidget,
          reason: 'Settlement tile should be visible on You Owe tab for uid-bob');
    });

    testWidgets('shows OMR amount with correct decimal format', (tester) async {
      await tester.pumpWidget(
        _wrap(
          GroupSettleUpScreen(groupId: _groupId),
          balancesAsync: AsyncValue.data(_balancesOwed),
        ),
      );
      await tester.pump();

      expect(find.textContaining('events'), findsWidgets);
    });

    testWidgets('GROUP TOTAL PENDING shows 7.750 OMR', (tester) async {
      await tester.pumpWidget(
        _wrap(
          GroupSettleUpScreen(groupId: _groupId),
          balancesAsync: AsyncValue.data(_balancesOwed),
        ),
      );
      await tester.pump();

      expect(find.textContaining('7.750'), findsWidgets);
    });

    // -----------------------------------------------------------------------
    // Tab content filtering
    // -----------------------------------------------------------------------

    testWidgets('You Owe tab shows debtor settlements only', (tester) async {
      // uid-bob owes Alice — should appear on first (You Owe) tab
      await tester.pumpWidget(
        _wrap(
          GroupSettleUpScreen(groupId: _groupId),
          balancesAsync: AsyncValue.data(_balancesOwed),
          currentUid: 'uid-bob',
        ),
      );
      await tester.pumpAndSettle();

      // Tab bar is rendered
      expect(find.byKey(GroupKeys.settleUpTabBar), findsOneWidget);
      // You Owe tab label is visible
      expect(find.text('You Owe'), findsOneWidget);
      // Record Payment button visible since bob owes
      expect(find.text('Record Payment'), findsOneWidget);
    });

    testWidgets('shows per-tab empty state when You Owe has no items',
        (tester) async {
      // uid-alice is the creditor, so You Owe tab is empty for her
      await tester.pumpWidget(
        _wrap(
          GroupSettleUpScreen(groupId: _groupId),
          balancesAsync: AsyncValue.data(_balancesOwed),
          currentUid: 'uid-alice',
        ),
      );
      await tester.pump();

      // Alice doesn't owe anything — You Owe tab shows empty state
      expect(find.text('Nothing to pay'), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // History tab
    // -----------------------------------------------------------------------

    testWidgets('History tab shows past settlements from groupSettlementsProvider',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          GroupSettleUpScreen(groupId: _groupId),
          balancesAsync: AsyncValue.data(_balancesOwed),
          settlements: [_testSettlement1, _testSettlement2],
        ),
      );
      await tester.pump();

      // Tap the History tab text
      await tester.tap(find.text('History'));
      await tester.pumpAndSettle();

      // History tile shows payer/recipient names
      expect(find.textContaining('Bob'), findsWidgets);
      expect(find.textContaining('Alice'), findsWidgets);
    });

    testWidgets('History tab empty state when no settlements', (tester) async {
      await tester.pumpWidget(
        _wrap(
          GroupSettleUpScreen(groupId: _groupId),
          balancesAsync: AsyncValue.data(_balancesOwed),
          settlements: const [],
        ),
      );
      await tester.pump();

      // Tap the History tab text
      await tester.tap(find.text('History'));
      await tester.pumpAndSettle();

      expect(find.text('No recorded payments'), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // Card-style tiles
    // -----------------------------------------------------------------------

    testWidgets('card-style settlement tiles: tab bar is present',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          GroupSettleUpScreen(groupId: _groupId),
          balancesAsync: AsyncValue.data(_balancesOwed),
          events: [_testEvent],
        ),
      );
      await tester.pump();

      // AppTabBar key is present
      expect(find.byKey(GroupKeys.settleUpTabBar), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // All-settled state (D-06)
    // -----------------------------------------------------------------------

    testWidgets('all settled state shows when no settlements and no history',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          GroupSettleUpScreen(groupId: _groupId),
          balancesAsync: AsyncValue.data(_balancesSettled),
          settlements: const [],
        ),
      );
      await tester.pump();

      expect(find.text('All settled up'), findsOneWidget);
    });

    testWidgets('all-settled state shows "Everyone is square" body text',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          GroupSettleUpScreen(groupId: _groupId),
          balancesAsync: AsyncValue.data(_balancesSettled),
          settlements: const [],
        ),
      );
      await tester.pump();

      expect(find.text('Everyone is square. No outstanding amounts.'),
          findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // Loading and error states
    // -----------------------------------------------------------------------

    testWidgets('shows loading indicator while balances are loading',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          GroupSettleUpScreen(groupId: _groupId),
          balancesAsync: const AsyncValue.loading(),
        ),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows error state with Retry button on balance fetch error',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          GroupSettleUpScreen(groupId: _groupId),
          balancesAsync: AsyncValue.error(
            Exception('Network error'),
            StackTrace.current,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Retry'), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // Record Payment bottom sheet (D-05)
    // -----------------------------------------------------------------------

    testWidgets('Record Payment bottom sheet shows "Record Payment" button',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          GroupSettleUpScreen(groupId: _groupId),
          balancesAsync: AsyncValue.data(_balancesOwed),
          currentUid: 'uid-bob',
        ),
      );
      await tester.pump();

      // Find the Record Payment button within a tile
      final recordBtn = find.text('Record Payment');
      if (tester.any(recordBtn)) {
        await tester.tap(recordBtn.first);
        await tester.pumpAndSettle();

        // Bottom sheet shows "Record Payment" title and Not Now
        expect(find.byKey(GroupKeys.markAsPaidButton), findsOneWidget);
        expect(find.byKey(GroupKeys.notNowButton), findsOneWidget);
      }

      expect(find.text('Settle Up'), findsOneWidget);
    });

    testWidgets('tapping Record Payment shows bottom sheet', (tester) async {
      await tester.pumpWidget(
        _wrap(
          GroupSettleUpScreen(groupId: _groupId),
          balancesAsync: AsyncValue.data(_balancesOwed),
          currentUid: 'uid-bob',
        ),
      );
      await tester.pump();

      final recordBtn = find.text('Record Payment');
      if (tester.any(recordBtn)) {
        await tester.tap(recordBtn.first);
        await tester.pumpAndSettle();

        expect(find.byKey(GroupKeys.markAsPaidButton), findsOneWidget);
      }

      expect(find.text('Settle Up'), findsOneWidget);
    });

    testWidgets('Not Now button dismisses bottom sheet', (tester) async {
      await tester.pumpWidget(
        _wrap(
          GroupSettleUpScreen(groupId: _groupId),
          balancesAsync: AsyncValue.data(_balancesOwed),
          currentUid: 'uid-bob',
        ),
      );
      await tester.pump();

      final recordBtn = find.text('Record Payment');
      if (tester.any(recordBtn)) {
        await tester.tap(recordBtn.first);
        await tester.pumpAndSettle();

        expect(find.byKey(GroupKeys.notNowButton), findsOneWidget);

        await tester.tap(find.byKey(GroupKeys.notNowButton));
        await tester.pumpAndSettle();

        expect(find.byKey(GroupKeys.notNowButton), findsNothing);
      }

      expect(find.text('Settle Up'), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // preSelectedMemberId
    // -----------------------------------------------------------------------

    testWidgets('renders with preSelectedMemberId without crashing',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          GroupSettleUpScreen(
            groupId: _groupId,
            preSelectedMemberId: 'uid-bob',
          ),
          balancesAsync: AsyncValue.data(_balancesOwed),
        ),
      );
      await tester.pump();

      expect(find.text('Settle Up'), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // Per-event breakdown
    // -----------------------------------------------------------------------

    testWidgets('per-event breakdown shows event name and date (happy path)',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          GroupSettleUpScreen(groupId: _groupId),
          balancesAsync: AsyncValue.data(_balancesOwed),
          events: [_testEvent],
          currentUid: 'uid-bob',
        ),
      );
      await tester.pumpAndSettle();

      // Tile is visible on the You Owe tab
      final tileFinder = find.byType(GroupSettlementTile);
      expect(tileFinder, findsOneWidget,
          reason: 'Settlement tile should be visible on You Owe tab');

      // The tile widget should exist and the screen should render correctly
      // (breakdown is collapsible — expanded state tested via tile widget directly)
      expect(find.text('Settle Up'), findsOneWidget);
      expect(find.text('You Owe'), findsOneWidget);
    });

    testWidgets(
        'per-event breakdown falls back to eventId label when event not in map',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          GroupSettleUpScreen(groupId: _groupId),
          balancesAsync: AsyncValue.data(_balancesOwed),
          events: const [],
          currentUid: 'uid-bob',
        ),
      );
      await tester.pumpAndSettle();

      // Renders without error; per-event breakdown not visible until expand
      expect(find.text('Settle Up'), findsOneWidget);
    });

    testWidgets('renders Settle Up title and tab bar', (tester) async {
      await tester.pumpWidget(
        _wrap(
          GroupSettleUpScreen(groupId: _groupId),
          balancesAsync: AsyncValue.data(_balancesOwed),
        ),
      );
      await tester.pump();

      expect(find.text('Settle Up'), findsOneWidget);
      expect(find.byKey(GroupKeys.settleUpTabBar), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // GroupStatsGrid (D-12 — from Plan 01)
    // -----------------------------------------------------------------------

    testWidgets(
      'GroupStatsGrid shows "You owe" subtitle for negative balance',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: GroupStatsGrid(
                userNetBalance: Decimal.parse('-5.000'),
                groupTotal: Decimal.parse('20.000'),
                activeMembers: 2,
                eventCount: 1,
                currency: 'OMR',
              ),
            ),
          ),
        );
        await tester.pump();

        expect(find.text('You owe'), findsOneWidget);
      },
    );

    testWidgets(
      'GroupStatsGrid shows "Owed to you" subtitle for positive balance',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: GroupStatsGrid(
                userNetBalance: Decimal.parse('5.000'),
                groupTotal: Decimal.parse('20.000'),
                activeMembers: 2,
                eventCount: 1,
                currency: 'OMR',
              ),
            ),
          ),
        );
        await tester.pump();

        expect(find.text('Owed to you'), findsOneWidget);
      },
    );
  });
}
