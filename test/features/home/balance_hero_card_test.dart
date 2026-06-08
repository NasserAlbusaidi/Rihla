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
import 'package:safar/shared/widgets/skeleton_loader.dart';

/// #261: build a single-OMR-currency [CrossGroupBalance] from a net string,
/// deriving the owed/owes split (so the bucket is consistent and shown). A zero
/// net with no split → empty byCurrency (the all-settled state).
CrossGroupBalance _omr(String net, {int groupCount = 1}) {
  final n = Decimal.parse(net);
  if (n == Decimal.zero) {
    return (
      byCurrency: const <CurrencyBalance>[],
      groupCount: groupCount,
      isLoading: false,
    );
  }
  return (
    byCurrency: [
      (
        currency: 'OMR',
        net: n,
        owedToUser: n > Decimal.zero ? n : Decimal.zero,
        userOwes: n < Decimal.zero ? n.abs() : Decimal.zero,
      ),
    ],
    groupCount: groupCount,
    isLoading: false,
  );
}

/// #261: single-OMR bucket with an explicit owed/owes split (net need not equal
/// owed-owes for these display tests).
CrossGroupBalance _omrSplit(
  String net,
  String owed,
  String owes, {
  int groupCount = 1,
}) => (
  byCurrency: [
    (
      currency: 'OMR',
      net: Decimal.parse(net),
      owedToUser: Decimal.parse(owed),
      userOwes: Decimal.parse(owes),
    ),
  ],
  groupCount: groupCount,
  isLoading: false,
);

void main() {
  Widget buildTestWidget({
    required Widget child,
    required List<Override> overrides,
  }) {
    return ProviderScope(
      overrides: [
        currentUserIdProvider.overrideWithValue('test-user-id'),
        userGroupsProvider.overrideWith((ref) => Stream.value([])),
        ...overrides,
        // #104: BalanceHeroCard now reads the one-shot variant. Bridge it to the
        // per-test crossGroupBalanceProvider override; loading stays loading.
        // #244: the once-provider now yields CrossGroupBalanceOnce — wrap the
        // bridged value as a non-partial result (these tests exercise the
        // number, not the partial affordance).
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
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );
  }

  group('BalanceHeroCard', () {
    test('widget class exists', () {
      // Structural assertion — just importing the file is enough
      expect(BalanceHeroCard, isNotNull);
    });

    testWidgets('Test 1: shows owe copy when net is negative', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(
          child: const BalanceHeroCard(),
          overrides: [
            crossGroupBalanceProvider.overrideWith(
              (ref) => AsyncValue.data(_omr('-5.500', groupCount: 2)),
            ),
          ],
        ),
      );
      await tester.pump();

      expect(find.textContaining('you owe'), findsAtLeastNWidgets(1));
      // #261: the bucket is now consistent (net −5.500 ⇒ userOwes 5.500), so the
      // amount shows in BOTH the hero net and the legend "you owe" line.
      expect(find.textContaining('5.500'), findsAtLeastNWidgets(1));
    });

    testWidgets('Test 2: shows owed copy when net is positive', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(
          child: const BalanceHeroCard(),
          overrides: [
            crossGroupBalanceProvider.overrideWith(
              (ref) => AsyncValue.data(_omr('3.250', groupCount: 1)),
            ),
          ],
        ),
      );
      await tester.pump();

      expect(find.textContaining('owed'), findsAtLeastNWidgets(1));
      // #261: consistent bucket (net +3.250 ⇒ owedToUser 3.250) ⇒ amount in the
      // hero net AND the legend "owed to you" line.
      expect(find.textContaining('3.250'), findsAtLeastNWidgets(1));
    });

    testWidgets(
      'Test 3: shows settled copy with zero amount when net is zero',
      (tester) async {
        await tester.pumpWidget(
          buildTestWidget(
            child: const BalanceHeroCard(),
            overrides: [
              crossGroupBalanceProvider.overrideWith(
                (ref) => AsyncValue.data(_omr('0', groupCount: 3)),
              ),
            ],
          ),
        );
        await tester.pump();

        expect(find.text('All settled across journeys'), findsOneWidget);
        expect(find.textContaining('0.000'), findsAtLeastNWidgets(1));
      },
    );

    testWidgets('Test 4: shows SkeletonLoader when loading', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(
          child: const BalanceHeroCard(),
          overrides: [
            crossGroupBalanceProvider.overrideWith(
              (ref) => const AsyncValue.loading(),
            ),
          ],
        ),
      );
      await tester.pump();

      expect(find.byType(SkeletonLoader), findsOneWidget);
    });

    testWidgets('Test 5: has key HomeKeys.balanceHeroCard', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(
          child: const BalanceHeroCard(),
          overrides: [
            crossGroupBalanceProvider.overrideWith(
              (ref) => AsyncValue.data(_omr('0', groupCount: 0)),
            ),
          ],
        ),
      );
      await tester.pump();

      expect(find.byKey(HomeKeys.balanceHeroCard), findsOneWidget);
    });

    testWidgets(
      'Test 6: split legend reads owedToUser/userOwes from the record (#110)',
      (tester) async {
        await tester.pumpWidget(
          buildTestWidget(
            child: const BalanceHeroCard(),
            overrides: [
              crossGroupBalanceProvider.overrideWith(
                (ref) => AsyncValue.data(
                  _omrSplit('5.000', '12.000', '7.000', groupCount: 2),
                ),
              ),
            ],
          ),
        );
        await tester.pump();

        // Legend amounts come straight off the record — the old per-group
        // re-walk (which used userGroupsProvider, overridden empty here) is gone.
        expect(find.textContaining('12.000'), findsOneWidget);
        expect(find.textContaining('7.000'), findsOneWidget);
      },
    );
  });
}
