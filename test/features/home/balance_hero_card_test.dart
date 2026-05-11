import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/home/keys/home_keys.dart';
import 'package:safar/features/home/widgets/balance_hero_card.dart';
import 'package:safar/features/home/widgets/quick_action_tray.dart';
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

  group('QuickActionTray', () {
    testWidgets('Test 6: renders 4 buttons with correct labels', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: QuickActionTray(
              onAddExpense: () {},
              onSettleUp: () {},
              onInviteFriend: () {},
              onActivity: () {},
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Add Expense'), findsOneWidget);
      expect(find.text('Settle Up'), findsOneWidget);
      expect(find.text('Invite Friend'), findsOneWidget);
      expect(find.text('Activity'), findsOneWidget);
    });

    testWidgets('Test 7: buttons have correct keys', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: QuickActionTray(
              onAddExpense: () {},
              onSettleUp: () {},
              onInviteFriend: () {},
              onActivity: () {},
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(HomeKeys.quickActionTray), findsOneWidget);
      expect(find.byKey(HomeKeys.addExpenseAction), findsOneWidget);
      expect(find.byKey(HomeKeys.settleUpAction), findsOneWidget);
      expect(find.byKey(HomeKeys.inviteAction), findsOneWidget);
      expect(find.byKey(HomeKeys.activityAction), findsOneWidget);
    });

    testWidgets('Test 8: button tap invokes corresponding callback', (
      tester,
    ) async {
      var addExpenseCalled = false;
      var settleUpCalled = false;
      var inviteCalled = false;
      var activityCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: QuickActionTray(
              onAddExpense: () => addExpenseCalled = true,
              onSettleUp: () => settleUpCalled = true,
              onInviteFriend: () => inviteCalled = true,
              onActivity: () => activityCalled = true,
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(HomeKeys.addExpenseAction));
      await tester.pump();
      expect(addExpenseCalled, isTrue);

      await tester.tap(find.byKey(HomeKeys.settleUpAction));
      await tester.pump();
      expect(settleUpCalled, isTrue);

      await tester.tap(find.byKey(HomeKeys.inviteAction));
      await tester.pump();
      expect(inviteCalled, isTrue);

      await tester.tap(find.byKey(HomeKeys.activityAction));
      await tester.pump();
      expect(activityCalled, isTrue);
    });
  });
}
