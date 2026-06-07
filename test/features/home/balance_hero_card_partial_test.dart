import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/home/keys/home_keys.dart';
import 'package:safar/features/home/widgets/balance_hero_card.dart';
import 'package:safar/l10n/generated/app_localizations.dart';
import 'package:safar/shared/widgets/r_amount.dart';

// #244: when crossGroupBalanceOnceProvider reports partial == true (a per-event
// money read failed for some group), the hero must STILL render the number AND
// show the "may be incomplete" notice — not the blanket error card.
void main() {
  CrossGroupBalanceOnce result({required bool partial}) => (
        balance: (
          net: Decimal.parse('12.500'),
          owedToUser: Decimal.parse('12.500'),
          userOwes: Decimal.zero,
          groupCount: 1,
          isLoading: false,
        ),
        partial: partial,
      );

  Widget harness({required bool partial}) => ProviderScope(
        overrides: [
          crossGroupBalanceOnceProvider
              .overrideWith((ref) => result(partial: partial)),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: SingleChildScrollView(child: BalanceHeroCard()),
          ),
        ),
      );

  testWidgets('partial → shows the incomplete notice AND the number',
      (tester) async {
    await tester.pumpWidget(harness(partial: true));
    await tester.pumpAndSettle();

    expect(find.byKey(HomeKeys.balanceIncompleteNotice), findsOneWidget,
        reason: 'partial balance must surface the "may be incomplete" notice');
    // The number still renders (loaded card, not the error card).
    expect(find.byType(RAmount), findsWidgets);
    expect(find.text('Balance unavailable'), findsNothing,
        reason: 'partial must NOT fall back to the blanket error card');
  });

  testWidgets('not partial → no incomplete notice, number renders',
      (tester) async {
    await tester.pumpWidget(harness(partial: false));
    await tester.pumpAndSettle();

    expect(find.byKey(HomeKeys.balanceIncompleteNotice), findsNothing);
    expect(find.byType(RAmount), findsWidgets);
    expect(find.text('Balance unavailable'), findsNothing);
  });
}
