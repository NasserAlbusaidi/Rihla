import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/home/keys/home_keys.dart';
import 'package:safar/features/home/widgets/balance_hero_card.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

/// #284 — the balance hero must NOT be a dead end. When given an [onTap] it
/// becomes interactive (the home screen wires this to the per-group balance
/// breakdown sheet, the path to per-group settle-up).
void main() {
  testWidgets('loaded hero card invokes onTap when tapped', (tester) async {
    var taps = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserIdProvider.overrideWithValue('test-user-id'),
          userGroupsProvider.overrideWith((ref) => Stream.value([])),
          crossGroupHomeBalanceProvider.overrideWith(
            (ref) => AsyncValue.data((
              balance: (
                byCurrency: [
                  (
                    currency: 'OMR',
                    net: Decimal.parse('12.500'),
                    owedToUser: Decimal.parse('12.500'),
                    userOwes: Decimal.zero,
                  ),
                ],
                groupCount: 2,
                isLoading: false,
              ),
              partial: false,
            )),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: BalanceHeroCard(onTap: () => taps++),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // #807/#916: a tappable hero carries a visible cue for what tapping does
    // — since PR-5 §3 that is the balance-by-group breakdown sheet.
    final hintFinder = find.text('See balance by group');
    expect(hintFinder, findsOneWidget);
    final hint = tester.widget<Text>(hintFinder);
    expect(hint.maxLines, 1);
    expect(hint.overflow, TextOverflow.ellipsis);
    expect(
      find.ancestor(of: hintFinder, matching: find.byType(Flexible)),
      findsOneWidget,
    );

    await tester.tap(find.byKey(HomeKeys.balanceHeroCard));
    await tester.pump();

    expect(taps, 1);
  });
}
