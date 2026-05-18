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

void main() {
  testWidgets('renders formatted former member but records raw names', (
    tester,
  ) async {
    String? capturedFromRawName;
    String? capturedToRawName;
    final tileKeys = <int, GlobalKey>{};

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Scaffold(
              body: SettleUpPageBody(
                subjectName: 'Camp',
                currency: 'OMR',
                optimalSettlements: [
                  {
                    'fromUserId': 'bob',
                    'toUserId': 'orphan',
                    'fromUserName': 'Bob',
                    'toUserName': 'Aisha (former member)',
                    'amount': Decimal.parse('4.000'),
                  },
                ],
                balances: [
                  UserBalance(
                    participantId: 'orphan',
                    displayName: 'Aisha (former member)',
                    totalPaid: Decimal.parse('30.000'),
                    totalOwed: Decimal.parse('10.000'),
                    netBalance: Decimal.parse('20.000'),
                  ),
                ],
                rawNames: const {'bob': 'Bob', 'orphan': 'Aisha'},
                settlementsAsync: const AsyncValue.data(<Settlement>[]),
                currentUid: 'bob',
                tileKeys: tileKeys,
                onRecord:
                    ({
                      required settlement,
                      required fromRawName,
                      required toRawName,
                      required fromUserId,
                      required toUserId,
                      required suggestedAmount,
                    }) {
                      capturedFromRawName = fromRawName;
                      capturedToRawName = toRawName;
                    },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Aisha (former member)'), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(GroupKeys.settleUpRecordPaymentButton),
    );
    await tester.tap(find.byKey(GroupKeys.settleUpRecordPaymentButton));
    await tester.pumpAndSettle();

    expect(capturedFromRawName, 'Bob');
    expect(capturedToRawName, 'Aisha');
  });
}
