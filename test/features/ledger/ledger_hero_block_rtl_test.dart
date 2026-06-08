import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/ledger/widgets/ledger_hero_block.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

/// #144: the V5R ledger-hero statement composes money as a [Row] of
/// `[Text('+OMR'), Text(whole), Text(frac)]`. Under an Arabic (RTL) ambient
/// direction the Row would lay those pieces right-to-left and scramble the
/// figure. The widget must force LTR for the money sub-tree.
void main() {
  Future<void> pumpHero(
    WidgetTester tester, {
    required LedgerHeroKind kind,
    required Decimal amount,
    Locale? locale,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        theme: AppTheme.lightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: LedgerHeroStatement(
            kind: kind,
            amount: amount,
            currency: 'OMR',
            peopleCount: 2,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('hero money is forced LTR in Arabic — positive (#144)', (
    tester,
  ) async {
    await pumpHero(
      tester,
      kind: LedgerHeroKind.positive,
      amount: Decimal.parse('12.450'),
      locale: const Locale('ar'),
    );

    final prefix = find.text('+OMR');
    expect(prefix, findsOneWidget);
    // Even though the app is RTL, the money sub-tree resolves LTR so the
    // OMR / whole / fraction pieces and the directional padding don't reverse.
    expect(Directionality.of(tester.element(prefix)), TextDirection.ltr);
  });

  testWidgets('hero money is forced LTR in Arabic — negative (#144)', (
    tester,
  ) async {
    await pumpHero(
      tester,
      kind: LedgerHeroKind.negative,
      amount: Decimal.parse('-7.300'),
      locale: const Locale('ar'),
    );

    final prefix = find.text('−OMR'); // U+2212 minus
    expect(prefix, findsOneWidget);
    expect(Directionality.of(tester.element(prefix)), TextDirection.ltr);
  });
}
