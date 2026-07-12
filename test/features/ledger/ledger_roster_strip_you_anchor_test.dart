import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/ledger/widgets/ledger_roster_strip.dart';
import 'package:safar/l10n/generated/app_localizations.dart';
import 'package:safar/shared/widgets/r_avatar.dart';

/// #1169 — the "You" anchor hardcoded a decorative em-dash that is pixel-
/// identical to the OTHER-people empty-state "no balance yet" em-dash chip
/// (`_Chip`'s `isEmpty` branch), so it falsely read as "you have no balance"
/// even while the event header showed a real nonzero net for the current
/// user. Decided fix (option B, not option A): the anchor never renders a
/// value OR a dash — the header stays the sole surface for the user's own
/// net.
void main() {
  Widget buildStrip() {
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
          currentUserId: 'me-uid',
          others: [
            LedgerRosterPerson(
              participantId: 'p1',
              displayName: 'Bob',
              signedAmount: Decimal.parse('5.000'),
              currency: 'OMR',
            ),
          ],
        ),
      ),
    );
  }

  testWidgets(
    'You anchor renders no em-dash while a live nonzero balance is on screen',
    (tester) async {
      await tester.pumpWidget(buildStrip());
      await tester.pump();

      // The only "others" entry is live and nonzero, so it renders a signed
      // RAmount chip, not a dash. Any '—' found here can only be the
      // anchor's hardcoded placeholder — which must not exist.
      expect(
        find.text('—'),
        findsNothing,
        reason:
            'the You anchor must never render a decorative em-dash — it '
            'falsely reads as "no balance" even when the header shows a '
            'real nonzero net for the current user',
      );
    },
  );

  testWidgets(
    'You anchor avatar stays top-aligned with sibling roster tile avatars',
    (tester) async {
      await tester.pumpWidget(buildStrip());
      await tester.pump();

      final youAvatar = find.byWidgetPredicate(
        (w) => w is RAvatar && w.name == 'You',
      );
      final bobAvatar = find.byWidgetPredicate(
        (w) => w is RAvatar && w.name == 'Bob',
      );
      expect(youAvatar, findsOneWidget);
      expect(bobAvatar, findsOneWidget);

      expect(
        tester.getTopLeft(youAvatar).dy,
        tester.getTopLeft(bobAvatar).dy,
        reason:
            'removing the anchor dash must not shift its avatar out of '
            'alignment with the other roster tiles',
      );
    },
  );
}
