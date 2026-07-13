import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/groups/widgets/settle_up_page_body.dart';
import 'package:safar/features/ledger/models/settlement_model.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

/// #1215 — the payment-history date row builds its own `DateFormat.MMMd`
/// inline (not through the shared `localized_dates.dart`/`AppFormatters`
/// chokepoints), so it needs its own coverage: under `ar`, the rendered date
/// must use Western digits, not Arabic-Indic.
void main() {
  testWidgets(
    'settle-up payment history renders Western date digits under ar locale',
    (tester) async {
      final tileKeys = <int, GlobalKey>{};

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            locale: const Locale('ar'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: MediaQuery(
              data: const MediaQueryData(disableAnimations: true),
              child: Scaffold(
                body: SettleUpPageBody(
                  scope: SettleScope.group,
                  subjectName: 'Camp',
                  simplifyDebts: true,
                  buckets: const [],
                  rawNames: const {},
                  settlementsAsync: AsyncValue.data([
                    Settlement(
                      id: 's1',
                      tripId: 'event-1',
                      payerName: 'Layla',
                      recipientName: 'Omar',
                      amount: Decimal.parse('4.000'),
                      currency: 'OMR',
                      settledAt: DateTime(2026, 5, 19),
                    ),
                  ]),
                  currentUid: 'layla',
                  tileKeys: tileKeys,
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
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('19'), findsWidgets);
      expect(find.textContaining('١٩'), findsNothing);
    },
  );
}
