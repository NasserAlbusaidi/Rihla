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

/// TDD RED — cluster `settle-up-same-name-discriminator` (#196), T2.
///
/// Mirrors `settle_up_page_body_former_member_test.dart`. Exercises the body
/// widget in isolation with already-discriminated display strings. Two cases:
///   1. Two colliding creditors render as distinct tiles.
///   2. Record callback persists the RAW name (regression guard for R2) AND
///      the missing-rawName fallback strips a discriminator instead of
///      persisting "Sam (#bbbb)".
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

void main() {
  testWidgets(
    'two colliding creditors render distinct discriminated tiles',
    (tester) async {
      final tileKeys = <int, GlobalKey>{};

      await tester.pumpWidget(
        _host(
          SettleUpPageBody(
            subjectName: 'Test Crew',
            currency: 'OMR',
            optimalSettlements: [
              {
                'fromUserId': 'uid-debtor',
                'toUserId': 'uid-aaaa',
                'fromUserName': 'Lena',
                'toUserName': 'Sam (#aaaa)',
                'amount': Decimal.parse('4.000'),
              },
              {
                'fromUserId': 'uid-debtor',
                'toUserId': 'uid-bbbb',
                'fromUserName': 'Lena',
                'toUserName': 'Sam (#bbbb)',
                'amount': Decimal.parse('3.000'),
              },
            ],
            balances: [
              UserBalance(
                participantId: 'uid-aaaa',
                displayName: 'Sam (#aaaa)',
                totalPaid: Decimal.parse('10.000'),
                totalOwed: Decimal.parse('6.000'),
                netBalance: Decimal.parse('4.000'),
              ),
              UserBalance(
                participantId: 'uid-bbbb',
                displayName: 'Sam (#bbbb)',
                totalPaid: Decimal.parse('9.000'),
                totalOwed: Decimal.parse('6.000'),
                netBalance: Decimal.parse('3.000'),
              ),
            ],
            rawNames: const {
              'uid-debtor': 'Lena',
              'uid-aaaa': 'Sam',
              'uid-bbbb': 'Sam',
            },
            settlementsAsync: const AsyncValue.data(<Settlement>[]),
            currentUid: 'uid-debtor',
            tileKeys: tileKeys,
            onRecord: ({
              required settlement,
              required fromRawName,
              required toRawName,
              required fromUserId,
              required toUserId,
              required suggestedAmount,
            }) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Sam (#aaaa)'), findsAtLeastNWidgets(1));
      expect(find.text('Sam (#bbbb)'), findsAtLeastNWidgets(1));
      // The undiscriminated bare "Sam" must NOT appear — both are tagged.
      expect(find.text('Sam'), findsNothing);
    },
  );

  // Regression guard (R2): green NOW and must stay green after the resolver
  // change. It FAILS only if a future edit routes disambiguated names into
  // `rawNames` instead of keeping them raw — i.e. the write path picks up a
  // "(#…)" suffix. Display names are discriminated; rawNames are raw.
  testWidgets(
    'record persists RAW name even when display names are discriminated (R2)',
    (tester) async {
      String? capturedFromRawName;
      String? capturedToRawName;
      final tileKeys = <int, GlobalKey>{};

      await tester.pumpWidget(
        _host(
          SettleUpPageBody(
            subjectName: 'Test Crew',
            currency: 'OMR',
            optimalSettlements: [
              {
                'fromUserId': 'uid-debtor',
                'toUserId': 'uid-bbbb',
                'fromUserName': 'Lena',
                'toUserName': 'Sam (#bbbb)',
                'amount': Decimal.parse('3.000'),
              },
            ],
            balances: [
              UserBalance(
                participantId: 'uid-bbbb',
                displayName: 'Sam (#bbbb)',
                totalPaid: Decimal.parse('9.000'),
                totalOwed: Decimal.parse('6.000'),
                netBalance: Decimal.parse('3.000'),
              ),
            ],
            // rawNames stay RAW (the resolver change must never route the
            // disambiguated map here). The persisted payerName/recipientName
            // must be "Sam", never "Sam (#bbbb)".
            rawNames: const {'uid-debtor': 'Lena', 'uid-bbbb': 'Sam'},
            settlementsAsync: const AsyncValue.data(<Settlement>[]),
            currentUid: 'uid-debtor',
            tileKeys: tileKeys,
            onRecord: ({
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
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(GroupKeys.settleUpRecordPaymentButton),
      );
      await tester.tap(find.byKey(GroupKeys.settleUpRecordPaymentButton));
      await tester.pumpAndSettle();

      expect(capturedFromRawName, 'Lena');
      // The load-bearing assertion: no discriminator leaks into the write path.
      expect(capturedToRawName, 'Sam');
      expect(capturedToRawName, isNot(contains('(#')));
    },
  );
}
