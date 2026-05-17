import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/app_theme.dart';

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

/// Widget tests for GroupSettleUpScreen — single-page wireframe layout.
///
/// Layout (Hi_GroupSettle): italic headline → 2 summary chips →
/// optimized transfer cards → "Each person's net" → inline payment history.

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
  memberNames: <String, String>{'uid-alice': 'Alice', 'uid-bob': 'Bob'},
  memberRawNames: <String, String>{'uid-alice': 'Alice', 'uid-bob': 'Bob'},
);

/// All-settled GroupBalances.
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
  memberNames: <String, String>{'uid-alice': 'Alice', 'uid-bob': 'Bob'},
  memberRawNames: <String, String>{'uid-alice': 'Alice', 'uid-bob': 'Bob'},
);

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

Widget _wrap(
  Widget child, {
  required AsyncValue<GroupBalances> balancesAsync,
  List<Event>? events,
  List<Settlement>? settlements,
  String? currentUid,
}) {
  return ProviderScope(
    overrides: [
      groupDetailProvider(
        _groupId,
      ).overrideWith((_) => Stream.value(_testGroup)),
      groupBalancesProvider(_groupId).overrideWith((_) => balancesAsync),
      groupSettlementsProvider(
        _groupId,
      ).overrideWith((_) => Stream.value(settlements ?? [])),
      groupEventsProvider(
        _groupId,
      ).overrideWith((_) => Stream.value(events ?? [])),
      currentUserIdProvider.overrideWithValue(currentUid),
    ],
    child: MediaQuery(
      data: const MediaQueryData(disableAnimations: true),
      child: MaterialApp(theme: AppTheme.lightTheme, home: child),
    ),
  );
}

void main() {
  group('GroupSettleUpScreen', () {
    testWidgets('shows screen title and transfer summary chip', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const GroupSettleUpScreen(groupId: _groupId),
          balancesAsync: AsyncValue.data(_balancesOwed),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Settle Up'), findsOneWidget);
      expect(find.text('1 transfer'), findsOneWidget);
    });

    testWidgets('renders italic headline and "total" chip', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const GroupSettleUpScreen(groupId: _groupId),
          balancesAsync: AsyncValue.data(_balancesOwed),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining("everyone's even"), findsOneWidget);
      expect(find.textContaining('total'), findsOneWidget);
    });

    testWidgets('renders settlement tile in unified list', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const GroupSettleUpScreen(groupId: _groupId),
          balancesAsync: AsyncValue.data(_balancesOwed),
          currentUid: 'uid-bob',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(GroupSettlementTile), findsOneWidget);
    });

    testWidgets('Mark paid button visible when current user is the debtor', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const GroupSettleUpScreen(groupId: _groupId),
          balancesAsync: AsyncValue.data(_balancesOwed),
          currentUid: 'uid-bob',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Mark paid'), findsOneWidget);
    });

    testWidgets('Mark paid button hidden for the creditor', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const GroupSettleUpScreen(groupId: _groupId),
          balancesAsync: AsyncValue.data(_balancesOwed),
          currentUid: 'uid-alice',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Mark paid'), findsNothing);
    });

    testWidgets('GROUP TOTAL PENDING shows 7.750 OMR', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const GroupSettleUpScreen(groupId: _groupId),
          balancesAsync: AsyncValue.data(_balancesOwed),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('7.750'), findsWidgets);
    });

    testWidgets('inline history shows past settlements', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const GroupSettleUpScreen(groupId: _groupId),
          balancesAsync: AsyncValue.data(_balancesOwed),
          settlements: [_testSettlement1, _testSettlement2],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Payment history'), findsOneWidget);
      // History tiles render RichText spans — the substring lives in a span.
      expect(find.textContaining('paid', findRichText: true), findsWidgets);
    });

    testWidgets('history section omitted when no settlements', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const GroupSettleUpScreen(groupId: _groupId),
          balancesAsync: AsyncValue.data(_balancesOwed),
          settlements: const [],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Payment history'), findsNothing);
    });

    testWidgets('all settled state shows when no settlements and no history', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const GroupSettleUpScreen(groupId: _groupId),
          balancesAsync: AsyncValue.data(_balancesSettled),
          settlements: const [],
        ),
      );
      await tester.pump();

      expect(find.text('All settled up'), findsOneWidget);
    });

    testWidgets('all-settled state shows "Everyone is square" body text', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const GroupSettleUpScreen(groupId: _groupId),
          balancesAsync: AsyncValue.data(_balancesSettled),
          settlements: const [],
        ),
      );
      await tester.pump();

      expect(
        find.text('Everyone is square. No outstanding amounts.'),
        findsOneWidget,
      );
    });

    testWidgets('shows loading indicator while balances are loading', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const GroupSettleUpScreen(groupId: _groupId),
          balancesAsync: const AsyncValue.loading(),
        ),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows error state with Retry button on balance fetch error', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const GroupSettleUpScreen(groupId: _groupId),
          balancesAsync: AsyncValue.error(
            Exception('Network error'),
            StackTrace.current,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('Mark paid opens record payment sheet', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const GroupSettleUpScreen(groupId: _groupId),
          balancesAsync: AsyncValue.data(_balancesOwed),
          currentUid: 'uid-bob',
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Mark paid'));
      await tester.pumpAndSettle();

      expect(find.byKey(GroupKeys.markAsPaidButton), findsOneWidget);
      expect(find.byKey(GroupKeys.notNowButton), findsOneWidget);
    });

    testWidgets('Not Now button dismisses bottom sheet', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const GroupSettleUpScreen(groupId: _groupId),
          balancesAsync: AsyncValue.data(_balancesOwed),
          currentUid: 'uid-bob',
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Mark paid'));
      await tester.pumpAndSettle();

      expect(find.byKey(GroupKeys.notNowButton), findsOneWidget);

      await tester.tap(find.byKey(GroupKeys.notNowButton));
      await tester.pumpAndSettle();

      expect(find.byKey(GroupKeys.notNowButton), findsNothing);
    });

    testWidgets('renders with preSelectedMemberId without crashing', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const GroupSettleUpScreen(
            groupId: _groupId,
            preSelectedMemberId: 'uid-bob',
          ),
          balancesAsync: AsyncValue.data(_balancesOwed),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Settle Up'), findsOneWidget);
    });

    testWidgets('renders per-event breakdown context', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const GroupSettleUpScreen(groupId: _groupId),
          balancesAsync: AsyncValue.data(_balancesOwed),
          events: [_testEvent],
          currentUid: 'uid-bob',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(GroupSettlementTile), findsOneWidget);
      expect(find.text('Settle Up'), findsOneWidget);
    });

    testWidgets(
      'GroupStatsGrid shows "You owe" subtitle for negative balance',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
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
            theme: AppTheme.lightTheme,
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
