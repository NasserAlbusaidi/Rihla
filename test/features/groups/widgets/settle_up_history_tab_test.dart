import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/app_theme.dart';

import 'package:safar/features/groups/widgets/settle_up_history_tab.dart';
import 'package:safar/features/ledger/models/settlement_model.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Settlement _buildSettlement({
  String id = 'set-1',
  String? payerParticipantId = 'uid-alice',
  String? recipientParticipantId = 'uid-bob',
  String amount = '7.500',
  String? payerName = 'Alice',
  String? recipientName = 'Bob',
}) {
  return Settlement(
    id: id,
    tripId: 'grp-1',
    payerParticipantId: payerParticipantId,
    recipientParticipantId: recipientParticipantId,
    amount: Decimal.parse(amount),
    settledAt: DateTime(2026, 1, 15),
    payerName: payerName,
    recipientName: recipientName,
  );
}

Widget _wrap(Widget child) => ProviderScope(
      child: MaterialApp(theme: AppTheme.lightTheme, home: Scaffold(body: child)),
    );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('SettleUpHistoryTab', () {
    testWidgets('renders loading state when settlementsAsync is loading',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          const SettleUpHistoryTab(
            settlementsAsync: AsyncValue.loading(),
            currency: 'OMR',
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('renders empty state when settlements list is empty',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          const SettleUpHistoryTab(
            settlementsAsync: AsyncValue.data([]),
            currency: 'OMR',
          ),
        ),
      );

      // Pump through flutter_animate timers (EmptyStateView uses fadeIn)
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('No recorded payments'), findsOneWidget);
    });

    testWidgets('renders list of history tiles when settlementsAsync has data',
        (tester) async {
      final settlements = [
        _buildSettlement(),
        _buildSettlement(
          id: 'set-2',
          payerParticipantId: 'uid-charlie',
          recipientParticipantId: 'uid-alice',
          amount: '3.000',
          payerName: 'Charlie',
          recipientName: 'Alice',
        ),
      ];

      await tester.pumpWidget(
        _wrap(
          SettleUpHistoryTab(
            settlementsAsync: AsyncValue.data(settlements),
            currency: 'OMR',
          ),
        ),
      );

      // Pump past flutter_animate entrance animations
      await tester.pump(const Duration(milliseconds: 300));

      // Both payment texts present
      expect(find.textContaining('Alice paid Bob'), findsOneWidget);
      expect(find.textContaining('Charlie paid Alice'), findsOneWidget);
    });
  });
}
