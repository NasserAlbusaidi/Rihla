import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/widgets/settle_up_tab_layout.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/models/settlement_model.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

final _testGroup = Group(
  id: 'grp-1',
  name: 'Test Crew',
  inviteCode: 'TST123',
  createdBy: 'uid-alice',
  memberIds: const ['uid-alice', 'uid-bob'],
  currency: 'OMR',
  createdAt: DateTime(2026, 1, 1),
);

final _emptyBalances = (
  balances: <UserBalance>[],
  totalSpent: Decimal.zero,
  eventCount: 0,
  perEventBreakdown: <String, Map<String, Decimal>>{},
  memberNames: <String, String>{},
);

/// Stateful host that provides a TabController to the layout.
class _TabHost extends StatefulWidget {
  final Widget Function(TabController) builder;

  const _TabHost({required this.builder});

  @override
  State<_TabHost> createState() => _TabHostState();
}

class _TabHostState extends State<_TabHost> with SingleTickerProviderStateMixin {
  late final TabController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(_controller);
}

Widget _wrap(Widget Function(TabController) builder) => ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: _TabHost(builder: builder),
        ),
      ),
    );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('SettleUpTabLayout', () {
    testWidgets('renders 4 tabs in the AppTabBar', (tester) async {
      await tester.pumpWidget(
        _wrap(
          (controller) => SettleUpTabLayout(
            controller: controller,
            group: _testGroup,
            optimalSettlements: const [],
            balancesData: _emptyBalances,
            settlementsAsync: const AsyncValue.data([]),
            currentUid: null,
            tileKeys: {},
            onRecord: ({
              required settlement,
              required fromName,
              required toName,
              required fromUserId,
              required toUserId,
              required suggestedAmount,
            }) {},
            buildBreakdown: (_, __) => {},
          ),
        ),
      );

      await tester.pump();

      // All-settled state rendered (empty settlements + empty history)
      expect(find.text('All settled up'), findsOneWidget);
    });

    testWidgets('renders 4 tab labels when settlements exist', (tester) async {
      final settlements = [
        {
          'fromUserId': 'uid-bob',
          'fromUserName': 'Bob',
          'toUserId': 'uid-alice',
          'toUserName': 'Alice',
          'amount': Decimal.parse('7.500'),
        },
      ];

      await tester.pumpWidget(
        _wrap(
          (controller) => SettleUpTabLayout(
            controller: controller,
            group: _testGroup,
            optimalSettlements: settlements,
            balancesData: _emptyBalances,
            settlementsAsync: const AsyncValue.data([]),
            currentUid: 'uid-alice',
            tileKeys: {},
            onRecord: ({
              required settlement,
              required fromName,
              required toName,
              required fromUserId,
              required toUserId,
              required suggestedAmount,
            }) {},
            buildBreakdown: (_, __) => {},
          ),
        ),
      );

      // Pump past flutter_animate entrance animations
      await tester.pump(const Duration(milliseconds: 300));

      // The 4 tab labels must be present
      expect(find.text('You Owe'), findsOneWidget);
      expect(find.text('Owed to You'), findsOneWidget);
      expect(find.text('Between Others'), findsOneWidget);
      expect(find.text('History'), findsOneWidget);
    });
  });
}
