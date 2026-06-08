import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/ledger/widgets/ledger_hero_block.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

/// #261 PR-B — proves the ledger money display is currency-aware (NOT a silent
/// all-OMR no-op): a USD group renders the USD code + 2 decimals, a JPY group
/// 0 decimals, and neither renders the old hardcoded 'OMR'/3dp.
void main() {
  Widget host(Widget child) => MaterialApp(
    theme: AppTheme.lightTheme,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );

  testWidgets('trip caption renders USD + 2 decimals (not OMR/3dp)', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        LedgerTripCaption(
          total: Decimal.parse('142.50'),
          currency: 'USD',
          expenseCount: 3,
          settledCount: 0,
        ),
      ),
    );
    expect(find.textContaining('USD 142.50'), findsOneWidget);
    expect(find.textContaining('OMR'), findsNothing);
    expect(find.textContaining('142.500'), findsNothing); // no OMR 3dp drift
  });

  testWidgets('trip caption renders JPY + 0 decimals', (tester) async {
    await tester.pumpWidget(
      host(
        LedgerTripCaption(
          total: Decimal.parse('1200'),
          currency: 'JPY',
          expenseCount: 2,
          settledCount: 0,
        ),
      ),
    );
    expect(find.textContaining('JPY 1200'), findsOneWidget);
    expect(find.textContaining('1200.000'), findsNothing);
  });

  testWidgets('hero statement uses the passed currency code, not OMR', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        LedgerHeroStatement(
          kind: LedgerHeroKind.positive,
          amount: Decimal.parse('12.50'),
          currency: 'USD',
          peopleCount: 2,
        ),
      ),
    );
    // The inline money prefix is '+USD' (was hardcoded '+OMR').
    expect(find.textContaining('USD'), findsAtLeastNWidgets(1));
    expect(find.textContaining('OMR'), findsNothing);
  });
}
