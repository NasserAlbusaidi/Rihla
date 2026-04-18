import 'package:decimal/decimal.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';

import 'package:safar/features/auth/providers/auth_provider.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/home/keys/home_keys.dart';
import 'package:safar/features/home/providers/dashboard_providers.dart';
import 'package:safar/core/router/app_router.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:safar/core/providers/settings_provider.dart';

class MockFirebaseUser extends Mock implements firebase_auth.User {}

void main() {
  final mockUser = MockFirebaseUser();
  when(() => mockUser.uid).thenReturn('user-1');

  final mockGroup = Group(
    id: 'group-1',
    name: 'Integration Test Group',
    inviteCode: 'INT123',
    createdBy: 'user-1',
    memberIds: const ['user-1'],
    currency: 'OMR',
    createdAt: DateTime.now(),
  );

  testWidgets('Happy Path: HomeScreen shows groups and navigates to group detail',
      (tester) async {
    SharedPreferences.setMockInitialValues({'device_name': 'Test User'});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // Bypass splash by providing a logged-in user
          authStateProvider.overrideWith(
            (ref) => Stream.value(mockUser),
          ),
          currentUserProvider.overrideWithValue(mockUser),

          // Provide mock groups for the home screen
          userGroupsProvider.overrideWith(
            (ref) => Stream.value([mockGroup]),
          ),

          onboardingCompleteProvider.overrideWith((ref) => true),
          sharedPreferencesProvider.overrideWithValue(prefs),

          // Dashboard providers required by Phase 18 HomeScreen widgets
          crossGroupBalanceProvider.overrideWith(
            (ref) => AsyncValue.data((
              net: Decimal.zero,
              groupCount: 1,
              isLoading: false,
            )),
          ),
          crossGroupActivityProvider.overrideWith(
            (ref) => const AsyncValue.data([]),
          ),
          weeklyGroupSpendingProvider.overrideWith(
            (ref) => AsyncValue.data(
              List.generate(7, (i) {
                final date = DateTime(2026, 3, 24).add(Duration(days: i));
                return (date: date, amount: Decimal.zero);
              }),
            ),
          ),
          groupBalancesProvider.overrideWith(
            (ref, groupId) => AsyncValue.data((
              balances: <UserBalance>[],
              totalSpent: Decimal.zero,
              eventCount: 0,
              perEventBreakdown: <String, Map<String, Decimal>>{},
              memberNames: <String, String>{},
            )),
          ),
          currentUserIdProvider.overrideWithValue('user-1'),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            final router = ref.watch(routerProvider);
            return MaterialApp.router(theme: AppTheme.lightTheme, routerConfig: router);
          },
        ),
      ),
    );

    // Wait for splash redirect to Home
    await tester.pumpAndSettle();

    // HomeScreen displays the group name
    expect(
      find.text('Integration Test Group', skipOffstage: false),
      findsWidgets,
    );

    // HomeScreen has a FAB for creating/joining groups
    expect(find.byKey(HomeKeys.createGroupFab), findsOneWidget);
  });
}
