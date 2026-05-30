import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iconsax/iconsax.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/groups/widgets/group_settlement_summary.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

void main() {
  testWidgets(
    'total chip shows a money icon, not a single-letter currency monogram (#157)',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: GroupSettlementSummaryCard(
              totalPending: Decimal.parse('12.000'),
              currency: 'OMR',
            ),
          ),
        ),
      );

      // RED today: the total chip renders currency[0] == 'O' as a Text glyph.
      expect(find.text('O'), findsNothing);
      // GREEN: a real money icon replaces the stray monogram.
      expect(find.byIcon(Iconsax.wallet_3), findsOneWidget);
    },
  );
}
