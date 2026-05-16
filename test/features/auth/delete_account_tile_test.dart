import 'package:decimal/decimal.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/auth/providers/auth_provider.dart';
import 'package:safar/features/auth/services/data_deletion_service.dart';
import 'package:safar/features/settings/keys/profile_keys.dart';
import 'package:safar/features/settings/providers/profile_stats_provider.dart'
    as profile_stats;
import 'package:safar/features/settings/screens/profile_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockDeletionService extends Mock implements DataDeletionService {}

class _MockUser extends Mock implements firebase_auth.User {}

firebase_auth.User _userWithEmail(String? email) {
  final u = _MockUser();
  when(() => u.uid).thenReturn('uid-x');
  when(() => u.email).thenReturn(email);
  return u;
}

Future<Widget> _wrap({
  required _MockDeletionService service,
  required String? email,
}) async {
  SharedPreferences.setMockInitialValues({'settings_device_name': 'Test User'});
  final prefs = await SharedPreferences.getInstance();
  final user = email == null ? null : _userWithEmail(email);

  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      dataDeletionServiceProvider.overrideWithValue(service),
      authUserChangesProvider.overrideWith(
        (ref) => Stream<firebase_auth.User?>.value(user),
      ),
      profile_stats.profileStatsProvider.overrideWith(
        (ref) => AsyncValue<profile_stats.ProfileStats>.data((
          groupCount: 0,
          eventCount: 0,
          totalSpent: Decimal.zero,
        )),
      ),
    ],
    child: MaterialApp.router(
      theme: AppTheme.lightTheme,
      routerConfig: GoRouter(
        initialLocation: '/profile',
        routes: [
          GoRoute(
            path: '/home',
            builder: (_, _) =>
                const Scaffold(body: SizedBox(key: Key('deleteAccount.home'))),
          ),
          GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen()),
        ],
      ),
    ),
  );
}

Future<void> _openDialog(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(ProfileKeys.deleteAccountTile));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ProfileKeys.deleteAccountTile));
  await tester.pumpAndSettle();
}

void main() {
  late _MockDeletionService service;

  setUp(() {
    service = _MockDeletionService();
  });

  testWidgets('delete tile is visible for both anonymous and linked users', (
    tester,
  ) async {
    await tester.pumpWidget(await _wrap(service: service, email: null));
    await tester.pumpAndSettle();
    expect(find.byKey(ProfileKeys.deleteAccountTile), findsOneWidget);

    await tester.pumpWidget(
      await _wrap(service: service, email: 'foo@example.com'),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(ProfileKeys.deleteAccountTile), findsOneWidget);
  });

  testWidgets('cancel does not call deleteAccount', (tester) async {
    await tester.pumpWidget(await _wrap(service: service, email: null));
    await tester.pumpAndSettle();
    await _openDialog(tester);

    await tester.tap(find.byKey(const Key('deleteAccount.cancel')));
    await tester.pumpAndSettle();

    verifyNever(() => service.deleteAccount());
  });

  testWidgets('successful deletion shows the success snack and goes home', (
    tester,
  ) async {
    when(
      () => service.deleteAccount(),
    ).thenAnswer((_) async => DeletionResult.ok);

    await tester.pumpWidget(await _wrap(service: service, email: null));
    await tester.pumpAndSettle();
    await _openDialog(tester);

    await tester.tap(find.byKey(const Key('deleteAccount.confirm')));
    await tester.pumpAndSettle();

    verify(() => service.deleteAccount()).called(1);
    expect(find.text('Account deleted.'), findsOneWidget);
    expect(find.byKey(const Key('deleteAccount.home')), findsOneWidget);
  });

  testWidgets('deletion errors show the retry snack', (tester) async {
    when(
      () => service.deleteAccount(),
    ).thenAnswer((_) async => DeletionResult.error);

    await tester.pumpWidget(
      await _wrap(service: service, email: 'foo@example.com'),
    );
    await tester.pumpAndSettle();
    await _openDialog(tester);

    await tester.tap(find.byKey(const Key('deleteAccount.confirm')));
    await tester.pumpAndSettle();

    expect(
      find.text("Couldn't delete the account. Try again."),
      findsOneWidget,
    );
    expect(find.byKey(const Key('deleteAccount.home')), findsNothing);
  });
}
