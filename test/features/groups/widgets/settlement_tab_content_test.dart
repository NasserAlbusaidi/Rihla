import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:iconsax/iconsax.dart';

import 'package:safar/features/groups/widgets/settlement_tab_content.dart';
import 'package:safar/features/groups/widgets/group_settlement_tile.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Map<String, dynamic> _buildSettlement({
  String fromUserId = 'uid-alice',
  String fromUserName = 'Alice',
  String toUserId = 'uid-bob',
  String toUserName = 'Bob',
  String amount = '7.500',
}) {
  return {
    'fromUserId': fromUserId,
    'fromUserName': fromUserName,
    'toUserId': toUserId,
    'toUserName': toUserName,
    'amount': Decimal.parse(amount),
  };
}

Widget _wrap(Widget child) =>
    MaterialApp(theme: AppTheme.lightTheme, home: Scaffold(body: child));

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('SettlementTabContent', () {
    testWidgets('renders empty state when settlements list is empty',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          SettlementTabContent(
            settlements: const [],
            isYourAction: true,
            isCreditor: false,
            emptyIcon: Iconsax.wallet_check,
            emptyTitle: 'Nothing to pay',
            emptyMessage: "You don't owe anyone.",
            currency: 'OMR',
            tileKeys: {},
            preSelectedMemberId: null,
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

      // Pump through flutter_animate timers (EmptyStateView uses fadeIn)
      await tester.pump(const Duration(milliseconds: 500));

      // Empty state title should appear
      expect(find.text('Nothing to pay'), findsOneWidget);
      // No tiles rendered
      expect(find.byType(GroupSettlementTile), findsNothing);
    });

    testWidgets('renders N tiles when settlements list has N items',
        (tester) async {
      final settlements = [
        _buildSettlement(),
        _buildSettlement(
          fromUserId: 'uid-charlie',
          fromUserName: 'Charlie',
          toUserId: 'uid-alice',
          toUserName: 'Alice',
          amount: '3.000',
        ),
      ];

      await tester.pumpWidget(
        _wrap(
          SettlementTabContent(
            settlements: settlements,
            isYourAction: false,
            isCreditor: false,
            emptyIcon: Iconsax.people,
            emptyTitle: 'All balanced',
            emptyMessage: 'No outstanding amounts.',
            currency: 'OMR',
            tileKeys: {},
            preSelectedMemberId: null,
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

      // 2 tiles rendered
      expect(find.byType(GroupSettlementTile), findsNWidgets(2));
    });
  });
}
