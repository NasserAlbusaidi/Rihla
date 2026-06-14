import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/groups/keys/group_keys.dart';
import 'package:safar/features/groups/widgets/settle_up_page_body.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/models/settlement_model.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

/// #283 — a recorded payment in the settle-up history exposes a "correct this"
/// affordance that, after a confirmation dialog, hands the original [Settlement]
/// back to the screen so it can record an offsetting reverse settlement
/// (append-only — the original row stays).

Widget _host(Widget body) {
  return ProviderScope(
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Scaffold(body: body),
      ),
    ),
  );
}

SettleUpPageBody _bodyWithHistory({
  void Function(Settlement settlement)? onCorrect,
}) {
  return SettleUpPageBody(
    subjectName: 'Beach House',
    buckets: [
      (
        currency: 'OMR',
        optimalSettlements: const <Map<String, dynamic>>[],
        balances: [
          UserBalance(
            participantId: 'uid-ahmed',
            displayName: 'Ahmed',
            totalPaid: Decimal.parse('5.000'),
            totalOwed: Decimal.zero,
            netBalance: Decimal.parse('5.000'),
          ),
          UserBalance(
            participantId: 'uid-sara',
            displayName: 'Sara',
            totalPaid: Decimal.zero,
            totalOwed: Decimal.parse('5.000'),
            netBalance: Decimal.parse('-5.000'),
          ),
        ],
      ),
    ],
    rawNames: const {'uid-ahmed': 'Ahmed', 'uid-sara': 'Sara'},
    settlementsAsync: AsyncValue.data([
      Settlement(
        id: 's1',
        tripId: 'event-1',
        payerParticipantId: 'uid-ahmed',
        recipientParticipantId: 'uid-sara',
        amount: Decimal.parse('5.000'),
        settledAt: DateTime(2026, 6, 7),
        payerName: 'Ahmed',
        recipientName: 'Sara',
      ),
    ]),
    currentUid: 'uid-ahmed',
    tileKeys: const {},
    onRecord:
        ({
          required settlement,
          required fromRawName,
          required toRawName,
          required fromUserId,
          required toUserId,
          required suggestedAmount,
          required String currency,
        }) {},
    onCorrect: onCorrect,
  );
}

void main() {
  testWidgets(
    'a history tile shows a correct affordance that confirms then fires onCorrect',
    (tester) async {
      Settlement? corrected;
      await tester.pumpWidget(
        _host(_bodyWithHistory(onCorrect: (s) => corrected = s)),
      );
      await tester.pumpAndSettle();

      final button = find.byKey(GroupKeys.settleUpCorrectButton);
      expect(button, findsOneWidget);

      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();

      // Confirmation dialog appears before any write.
      expect(find.text('Correct this payment?'), findsOneWidget);
      expect(corrected, isNull, reason: 'must not fire before confirmation');

      await tester.tap(find.text('Record correction'));
      await tester.pumpAndSettle();

      expect(corrected, isNotNull);
      expect(corrected!.id, 's1');
    },
  );

  testWidgets('cancelling the correction dialog does not fire onCorrect', (
    tester,
  ) async {
    Settlement? corrected;
    await tester.pumpWidget(
      _host(_bodyWithHistory(onCorrect: (s) => corrected = s)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(GroupKeys.settleUpCorrectButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(corrected, isNull);
  });

  testWidgets('the correct affordance is hidden when onCorrect is null', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_bodyWithHistory(onCorrect: null)));
    await tester.pumpAndSettle();

    expect(find.byKey(GroupKeys.settleUpCorrectButton), findsNothing);
  });
}
