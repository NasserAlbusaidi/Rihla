import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iconsax/iconsax.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/groups/keys/group_keys.dart';
import 'package:safar/features/groups/widgets/group_settlement_summary.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

Widget _host(Widget child) => MaterialApp(
  theme: AppTheme.lightTheme,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

void main() {
  testWidgets(
    'summary card shows only the total chip — the transfer count lives in the '
    'headline, not a redundant pill (#158)',
    (tester) async {
      await tester.pumpWidget(
        _host(
          const _Card(),
        ),
      );

      // The single surviving chip is the total, marked by the wallet icon and
      // the "… total" label, keyed for the settle-up screen.
      expect(find.byIcon(Iconsax.wallet_3), findsOneWidget);
      expect(find.textContaining('total'), findsOneWidget);
      expect(find.byKey(GroupKeys.settleUpGroupTotalLabel), findsOneWidget);

      // No transfer-count pill anymore (the _SettlementIntro headline owns it).
      expect(find.textContaining('transfer'), findsNothing);
    },
  );
}

class _Card extends StatelessWidget {
  const _Card();
  @override
  Widget build(BuildContext context) => GroupSettlementSummaryCard(
    totalPending: Decimal.parse('12.000'),
    currency: 'OMR',
  );
}
