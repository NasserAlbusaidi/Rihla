import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/ledger/widgets/ledger_roster_strip.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

/// #569 — the roster strip's signed-balance chip must not overflow vertically
/// when a balance string is long (large amount and/or a 3-decimal currency on a
/// multi-currency group). Before the fix the chip `Text` had no `maxLines`, so a
/// long string wrapped to two lines and blew the strip's fixed 128px / 102px
/// content band → "BOTTOM OVERFLOWED BY 3.0 PIXELS".
void main() {
  Widget buildStrip(List<LedgerRosterPerson> others) {
    return MaterialApp(
      theme: AppTheme.lightTheme,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: LedgerRosterStrip(
          state: LedgerRosterState.live,
          currency: 'OMR',
          currentUserDisplayName: 'You',
          others: others,
        ),
      ),
    );
  }

  testWidgets(
    'large OMR balance chip does not overflow the strip vertically',
    (tester) async {
      await tester.pumpWidget(
        buildStrip([
          LedgerRosterPerson(
            participantId: 'p1',
            displayName: 'Bob',
            signedAmount: Decimal.parse('1234567.890'),
            currency: 'OMR',
          ),
        ]),
      );
      await tester.pump();

      expect(
        tester.takeException(),
        isNull,
        reason: 'roster chip must shrink long balances, not wrap and overflow',
      );
    },
  );

  testWidgets(
    'multi-currency roster (long OMR + USD chips) does not overflow',
    (tester) async {
      await tester.pumpWidget(
        buildStrip([
          LedgerRosterPerson(
            participantId: 'p1',
            displayName: 'Bob',
            signedAmount: Decimal.parse('982341.500'),
            currency: 'OMR',
          ),
          LedgerRosterPerson(
            participantId: 'p2',
            displayName: 'Carla',
            signedAmount: -Decimal.parse('45678.90'),
            currency: 'USD',
          ),
        ]),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
    },
  );
}
