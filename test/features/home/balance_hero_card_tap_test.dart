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
/// becomes interactive (the home screen wires this to scroll to the journeys
/// list, the path to per-group settle-up).
void main() {
  testWidgets('loaded hero card invokes onTap when tapped', (tester) async {
    var taps = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserIdProvider.overrideWithValue('test-user-id'),
          userGroupsProvider.overrideWith((ref) => Stream.value([])),
          crossGroupBalanceProvider.overrideWith(
            (ref) => AsyncValue.data((
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
            )),
          ),
          crossGroupBalanceOnceProvider.overrideWith(
            (ref) => ref.watch(crossGroupBalanceProvider).maybeWhen(
                  data: (d) => (balance: d, partial: false),
                  orElse: () => Completer<CrossGroupBalanceOnce>().future,
                ),
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

    await tester.tap(find.byKey(HomeKeys.balanceHeroCard));
    await tester.pump();

    expect(taps, 1);
  });
}
