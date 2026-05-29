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
              (ref) => AsyncValue.data((
                net: Decimal.parse('-5.500'),
                groupCount: 2,
                isLoading: false,
              )),
            ),
          ],
        ),
      );
      await tester.pump();

      expect(find.textContaining('you owe'), findsAtLeastNWidgets(1));
      expect(find.textContaining('5.500'), findsOneWidget);
    });

    testWidgets('Test 2: shows owed copy when net is positive', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(
          child: const BalanceHeroCard(),
          overrides: [
            crossGroupBalanceProvider.overrideWith(
              (ref) => AsyncValue.data((
                net: Decimal.parse('3.250'),
                groupCount: 1,
                isLoading: false,
              )),
            ),
          ],
        ),
      );
      await tester.pump();

      expect(find.textContaining('owed'), findsAtLeastNWidgets(1));
      expect(find.textContaining('3.250'), findsOneWidget);
    });

    testWidgets(
      'Test 3: shows settled copy with zero amount when net is zero',
      (tester) async {
        await tester.pumpWidget(
          buildTestWidget(
            child: const BalanceHeroCard(),
            overrides: [
              crossGroupBalanceProvider.overrideWith(
                (ref) => AsyncValue.data((
                  net: Decimal.zero,
                  groupCount: 3,
                  isLoading: false,
                )),
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
              (ref) => AsyncValue.data((
                net: Decimal.zero,
                groupCount: 0,
                isLoading: false,
              )),
            ),
          ],
        ),
      );
      await tester.pump();

      expect(find.byKey(HomeKeys.balanceHeroCard), findsOneWidget);
    });
  });
}
