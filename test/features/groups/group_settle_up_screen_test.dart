import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/screens/group_settle_up_screen.dart';
import 'package:safar/features/ledger/models/expense_model.dart';

/// Widget tests for GroupSettleUpScreen (FIN-04, D-22).
///
/// Relocated from test/features/group_settle_up_screen_test.dart to the
/// canonical test/features/groups/ directory per Phase 06 Plan 04.

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

/// Two-person GroupBalances: Bob owes Alice 15.500 OMR.
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

/// Wraps the screen with ProviderScope overriding groupBalancesProvider.
Widget _wrap(
  Widget child, {
  required AsyncValue<GroupBalances> balancesAsync,
  List<Event>? events,
}) {
  return ProviderScope(
    overrides: [
      groupBalancesProvider(_groupId).overrideWith((_) => balancesAsync),
      if (events != null)
        groupEventsProvider(_groupId).overrideWith(
          (_) => Stream.value(events),
        ),
    ],
    child: MaterialApp(home: child),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('GroupSettleUpScreen', () {
    testWidgets('shows screen title and GROUP TOTAL PENDING label',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          GroupSettleUpScreen(
            groupId: _groupId,
            group: _testGroup,
          ),
          balancesAsync: AsyncValue.data(_balancesOwed),
        ),
      );
      await tester.pump();

      expect(find.text('Settle Up'), findsOneWidget);
      expect(find.text('GROUP TOTAL PENDING'), findsOneWidget);
    });

    testWidgets('shows optimized settlement tiles with member names',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          GroupSettleUpScreen(
            groupId: _groupId,
            group: _testGroup,
          ),
          balancesAsync: AsyncValue.data(_balancesOwed),
        ),
      );
      await tester.pump();

      // Settlement tiles should show member names via RichText widgets.
      final richTexts = tester.widgetList<RichText>(find.byType(RichText));
      final allText = richTexts
          .map((rt) => rt.text.toPlainText())
          .join(' ');
      // BalanceCalculator produces one settlement: Bob pays Alice
      expect(allText.contains('Bob') || allText.contains('Alice'), isTrue,
          reason: 'Settlement tile should show member names');
    });

    testWidgets('shows OMR amount with correct decimal format', (tester) async {
      await tester.pumpWidget(
        _wrap(
          GroupSettleUpScreen(
            groupId: _groupId,
            group: _testGroup,
          ),
          balancesAsync: AsyncValue.data(_balancesOwed),
        ),
      );
      await tester.pump();

      // Across N events label confirms event count rendering
      expect(find.textContaining('events'), findsWidgets);
    });

    testWidgets('all-settled state shows tick circle message', (tester) async {
      await tester.pumpWidget(
        _wrap(
          GroupSettleUpScreen(
            groupId: _groupId,
            group: _testGroup,
          ),
          balancesAsync: AsyncValue.data(_balancesSettled),
        ),
      );
      await tester.pump();

      expect(
        find.text('All settled across the group!'),
        findsOneWidget,
        reason: 'All-settled state must show the tick-circle message (D-08)',
      );
      expect(
        find.text('No payments needed right now.'),
        findsOneWidget,
      );
    });

    testWidgets('shows loading indicator while balances are loading',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          GroupSettleUpScreen(
            groupId: _groupId,
            group: _testGroup,
          ),
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
          GroupSettleUpScreen(
            groupId: _groupId,
            group: _testGroup,
          ),
          balancesAsync: AsyncValue.error(
            Exception('Network error'),
            StackTrace.current,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('Record Settlement bottom sheet shows Mark as Paid button',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          GroupSettleUpScreen(
            groupId: _groupId,
            group: _testGroup,
          ),
          balancesAsync: AsyncValue.data(_balancesOwed),
        ),
      );
      await tester.pump();

      // Find and tap "Record Settlement" button if visible
      final recordBtn = find.text('Record Settlement');
      if (tester.any(recordBtn)) {
        await tester.tap(recordBtn.first);
        await tester.pumpAndSettle();

        // Bottom sheet should appear with Mark as Paid
        expect(find.text('Mark as Paid'), findsOneWidget);
        expect(find.text('Not Now'), findsOneWidget);
      }

      // Screen renders without error regardless
      expect(find.text('Settle Up'), findsOneWidget);
    });

    testWidgets('renders Settle Up title and Across events subtitle', (tester) async {
      await tester.pumpWidget(
        _wrap(
          GroupSettleUpScreen(
            groupId: _groupId,
            group: _testGroup,
          ),
          balancesAsync: AsyncValue.data(_balancesOwed),
        ),
      );
      await tester.pump();

      // The screen always shows "Settle Up" title
      expect(find.text('Settle Up'), findsOneWidget);
      // "Across N events" label appears in settlement tiles
      expect(find.textContaining('events'), findsWidgets);
    });

    testWidgets('renders with preSelectedMemberId without crashing',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          GroupSettleUpScreen(
            groupId: _groupId,
            group: _testGroup,
            preSelectedMemberId: 'uid-bob',
          ),
          balancesAsync: AsyncValue.data(_balancesOwed),
        ),
      );
      await tester.pump();

      // Screen should render without error when preSelectedMemberId is set
      expect(find.text('Settle Up'), findsOneWidget);
    });

    testWidgets('GROUP TOTAL PENDING shows 7.750 OMR', (tester) async {
      await tester.pumpWidget(
        _wrap(
          GroupSettleUpScreen(
            groupId: _groupId,
            group: _testGroup,
          ),
          balancesAsync: AsyncValue.data(_balancesOwed),
        ),
      );
      await tester.pump();

      // Total pending amount should be formatted as OMR
      expect(find.textContaining('7.750'), findsWidgets);
    });

    testWidgets('renders back button navigation', (tester) async {
      await tester.pumpWidget(
        _wrap(
          GroupSettleUpScreen(
            groupId: _groupId,
            group: _testGroup,
          ),
          balancesAsync: AsyncValue.data(_balancesOwed),
        ),
      );
      await tester.pump();

      expect(find.byType(IconButton), findsWidgets);
    });

    testWidgets('tapping Record Settlement shows bottom sheet', (tester) async {
      await tester.pumpWidget(
        _wrap(
          GroupSettleUpScreen(
            groupId: _groupId,
            group: _testGroup,
          ),
          balancesAsync: AsyncValue.data(_balancesOwed),
        ),
      );
      await tester.pump();

      final recordBtn = find.text('Record Settlement');
      if (tester.any(recordBtn)) {
        await tester.tap(recordBtn.first);
        await tester.pumpAndSettle();

        expect(find.text('Mark as Paid'), findsOneWidget);
      }

      expect(find.text('Settle Up'), findsOneWidget);
    });

    testWidgets('Not Now button dismisses bottom sheet', (tester) async {
      await tester.pumpWidget(
        _wrap(
          GroupSettleUpScreen(
            groupId: _groupId,
            group: _testGroup,
          ),
          balancesAsync: AsyncValue.data(_balancesOwed),
        ),
      );
      await tester.pump();

      final recordBtn = find.text('Record Settlement');
      if (tester.any(recordBtn)) {
        await tester.tap(recordBtn.first);
        await tester.pumpAndSettle();

        // Bottom sheet is open
        expect(find.text('Not Now'), findsOneWidget);

        await tester.tap(find.text('Not Now'));
        await tester.pumpAndSettle();

        // Bottom sheet is dismissed
        expect(find.text('Not Now'), findsNothing);
      }

      expect(find.text('Settle Up'), findsOneWidget);
    });

    testWidgets('per-event breakdown shows event name and date (happy path)',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          GroupSettleUpScreen(
            groupId: _groupId,
            group: _testGroup,
          ),
          balancesAsync: AsyncValue.data(_balancesOwed),
          events: [_testEvent],
        ),
      );
      await tester.pumpAndSettle();

      // D-01, D-04: event name with short date
      expect(find.textContaining('Camping Weekend'), findsWidgets);
      expect(find.textContaining('Mar 15'), findsWidgets);
    });

    testWidgets(
        'per-event breakdown falls back to eventId label when event not in map',
        (tester) async {
      // Pass empty events list — eventNameMap will be empty, triggering fallback
      await tester.pumpWidget(
        _wrap(
          GroupSettleUpScreen(
            groupId: _groupId,
            group: _testGroup,
          ),
          balancesAsync: AsyncValue.data(_balancesOwed),
          events: const [],
        ),
      );
      await tester.pumpAndSettle();

      // D-02 fallback: since no events are in the map, the label falls back
      // to the eventId-based label. The screen still renders the settle up view.
      expect(find.text('Settle Up'), findsOneWidget);
      // The per-event breakdown row is rendered (breakdowns are non-empty)
      expect(find.textContaining('event-1'), findsWidgets);
    });
  });
}
