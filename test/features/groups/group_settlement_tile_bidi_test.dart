import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/groups/widgets/group_settlement_tile.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

/// #1216b — the settle-up direction headline (`settleUpYouOwe`/`settleUpOwesYou`)
/// renders as a Semantics label; it must FSI/PDI-isolate the name at the l10n
/// arg so the 13-key contract stays uniform (the visible direction protection
/// is the already-isolated `_captionName`).
Widget _host(Widget child) => MaterialApp(
      theme: AppTheme.lightTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

const _rlo = '\u{202E}';
String _fsi(String s) => '\u{2068}$s\u{2069}';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('You-owe headline isolates the recipient name', (tester) async {
    await tester.pumpWidget(
      _host(
        GroupSettlementTile(
          fromName: 'You',
          toName: 'Bob$_rlo',
          amount: Decimal.parse('5.000'),
          currency: 'OMR',
          breakdown: const {},
          isYourAction: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final labels = tester
        .widgetList<Semantics>(find.byType(Semantics))
        .map((s) => s.properties.label)
        .whereType<String>();
    expect(
      labels.any((l) => l.contains(_fsi('Bob$_rlo'))),
      isTrue,
      reason: 'settleUpYouOwe must isolate the name',
    );
  });

  testWidgets('Owes-you headline isolates the payer name', (tester) async {
    await tester.pumpWidget(
      _host(
        GroupSettlementTile(
          fromName: 'Sara$_rlo',
          toName: 'You',
          amount: Decimal.parse('5.000'),
          currency: 'OMR',
          breakdown: const {},
          isYourAction: false,
          isCreditor: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final labels = tester
        .widgetList<Semantics>(find.byType(Semantics))
        .map((s) => s.properties.label)
        .whereType<String>();
    expect(
      labels.any((l) => l.contains(_fsi('Sara$_rlo'))),
      isTrue,
      reason: 'settleUpOwesYou must isolate the name',
    );
  });
}
