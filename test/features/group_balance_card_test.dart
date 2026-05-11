import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/groups/keys/group_keys.dart';
import 'package:safar/features/groups/widgets/group_member_balance_card.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/core/theme/tokens/color_tokens.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

UserBalance _balance({
  String participantId = 'p1',
  String displayName = 'Alice',
  required String netBalance,
}) {
  final net = Decimal.parse(netBalance);
  return UserBalance(
    participantId: participantId,
    displayName: displayName,
    totalPaid: Decimal.zero,
    totalOwed: Decimal.zero,
    netBalance: net,
  );
}

Widget _wrap(Widget child) => MaterialApp(
  theme: AppTheme.lightTheme,
  home: Scaffold(body: child),
);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('GroupMemberBalanceCard', () {
    test('positive balance shown in emerald color', () async {
      // This is a widget test — use testWidgets below.
    });

    testWidgets('positive balance shown in emerald color', (tester) async {
      bool expanded = false;

      await tester.pumpWidget(
        _wrap(
          StatefulBuilder(
            builder: (context, setState) {
              return GroupMemberBalanceCard(
                balance: _balance(netBalance: '25.000'),
                perEventBreakdown: const {},
                eventNames: const {},
                currency: 'OMR',
                isExpanded: expanded,
                onExpandChanged: (v) => setState(() => expanded = v),
              );
            },
          ),
        ),
      );

      // Amount text is present
      expect(find.textContaining('25'), findsOneWidget);

      // Find the Text widget showing the amount and check its color
      final texts = tester.widgetList<Text>(find.byType(Text));
      final amountText = texts.firstWhere(
        (t) => t.data?.contains('25') ?? false,
        orElse: () => throw StateError('Amount text not found'),
      );
      expect(
        (amountText.style?.color ?? Colors.transparent).toARGB32(),
        AppColorTokens.light.successText.toARGB32(),
        reason: 'Positive balance should be shown in WCAG-safe successText',
      );
    });

    testWidgets('negative balance shown in rose color', (tester) async {
      bool expanded = false;

      await tester.pumpWidget(
        _wrap(
          StatefulBuilder(
            builder: (context, setState) {
              return GroupMemberBalanceCard(
                balance: _balance(netBalance: '-10.500'),
                perEventBreakdown: const {},
                eventNames: const {},
                currency: 'OMR',
                isExpanded: expanded,
                onExpandChanged: (v) => setState(() => expanded = v),
              );
            },
          ),
        ),
      );

      expect(find.textContaining('10'), findsOneWidget);

      final texts = tester.widgetList<Text>(find.byType(Text));
      final amountText = texts.firstWhere(
        (t) => t.data?.contains('10') ?? false,
        orElse: () => throw StateError('Amount text not found'),
      );
      expect(
        (amountText.style?.color ?? Colors.transparent).toARGB32(),
        AppColorTokens.light.errorText.toARGB32(),
        reason: 'Negative balance should be shown in WCAG-safe errorText',
      );
    });

    testWidgets('zero balance shows Settled badge', (tester) async {
      bool expanded = false;

      await tester.pumpWidget(
        _wrap(
          StatefulBuilder(
            builder: (context, setState) {
              return GroupMemberBalanceCard(
                balance: _balance(netBalance: '0'),
                perEventBreakdown: const {},
                eventNames: const {},
                currency: 'OMR',
                isExpanded: expanded,
                onExpandChanged: (v) => setState(() => expanded = v),
              );
            },
          ),
        ),
      );

      expect(find.byKey(GroupKeys.settledBadge), findsOneWidget);
    });

    testWidgets('tap expands to show per-event breakdown', (tester) async {
      bool expanded = false;

      await tester.pumpWidget(
        _wrap(
          StatefulBuilder(
            builder: (context, setState) {
              return GroupMemberBalanceCard(
                balance: _balance(netBalance: '15.000'),
                perEventBreakdown: {'event1': Decimal.parse('15.000')},
                eventNames: const {'event1': 'Camping Trip'},
                currency: 'OMR',
                isExpanded: expanded,
                onExpandChanged: (v) => setState(() => expanded = v),
              );
            },
          ),
        ),
      );

      // Initially collapsed — no Settle button
      expect(find.byKey(GroupKeys.settleButton), findsNothing);

      // Tap the card header to expand
      await tester.tap(find.text('Alice'));
      await tester.pumpAndSettle();

      // After expansion, event name is prominently rendered
      expect(find.text('Camping Trip'), findsOneWidget);
    });

    testWidgets(
      'onSettleUpTap fires when Settle button tapped in expanded state',
      (tester) async {
        bool expanded = true;
        bool settleUpCalled = false;

        await tester.pumpWidget(
          _wrap(
            StatefulBuilder(
              builder: (context, setState) {
                return GroupMemberBalanceCard(
                  balance: _balance(netBalance: '-20.000'),
                  perEventBreakdown: {'event1': Decimal.parse('-20.000')},
                  eventNames: const {'event1': 'Road Trip'},
                  currency: 'OMR',
                  isExpanded: expanded,
                  onExpandChanged: (v) => setState(() => expanded = v),
                  onSettleUpTap: () {
                    settleUpCalled = true;
                  },
                );
              },
            ),
          ),
        );

        await tester.pumpAndSettle();

        // Settle button should be visible in expanded state with non-zero balance
        expect(find.byKey(GroupKeys.settleButton), findsOneWidget);

        // Tap Settle button
        await tester.tap(find.byKey(GroupKeys.settleButton));
        await tester.pump();

        expect(
          settleUpCalled,
          isTrue,
          reason:
              'onSettleUpTap should fire when Settle button is tapped (D-22)',
        );
      },
    );

    testWidgets('Settle button hidden for zero balance member', (tester) async {
      await tester.pumpWidget(
        _wrap(
          GroupMemberBalanceCard(
            balance: _balance(netBalance: '0'),
            perEventBreakdown: const {},
            eventNames: const {},
            currency: 'OMR',
            isExpanded: true,
            onExpandChanged: (_) {},
            onSettleUpTap: () {},
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Settle button should NOT appear for settled member
      expect(find.byKey(GroupKeys.settleButton), findsNothing);
    });
  });
}
