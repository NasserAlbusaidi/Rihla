import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/auth/providers/auth_provider.dart';
import 'package:safar/features/auth/services/auth_recovery_service.dart';
import 'package:decimal/decimal.dart';
import 'package:safar/features/settings/keys/profile_keys.dart';
import 'package:safar/features/settings/providers/profile_stats_provider.dart'
    as profile_stats;
import 'package:safar/features/settings/screens/profile_screen.dart';
import 'package:safar/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockRecoveryService extends Mock implements AuthRecoveryService {}

class _MockUser extends Mock implements firebase_auth.User {}

firebase_auth.User _userWithEmail(String? email) {
  final u = _MockUser();
  when(() => u.uid).thenReturn('uid-x');
  when(() => u.email).thenReturn(email);
  return u;
}

Future<Widget> _wrap({
  required _MockRecoveryService service,
  required String? email,
}) async {
  SharedPreferences.setMockInitialValues({
    'settings_device_name': 'Test User',
  });
  final prefs = await SharedPreferences.getInstance();

  final user = email == null ? null : _userWithEmail(email);

  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      authRecoveryServiceProvider.overrideWithValue(service),
      authUserChangesProvider.overrideWith(
        (ref) => Stream<firebase_auth.User?>.value(user),
      ),
      profile_stats.profileStatsProvider.overrideWith(
        (ref) => AsyncValue<profile_stats.ProfileStats>.data(
          (groupCount: 0, eventCount: 0, totalSpent: Decimal.zero),
        ),
      ),
    ],
    child: MaterialApp.router(
      theme: AppTheme.lightTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: GoRouter(
        initialLocation: '/profile',
        routes: [
          GoRoute(
            path: '/profile',
            builder: (_, _) => const ProfileScreen(),
          ),
        ],
      ),
    ),
  );
}

void main() {
  late _MockRecoveryService service;

  setUp(() {
    service = _MockRecoveryService();
  });

  testWidgets('sign-out row is hidden for unlinked users', (tester) async {
    await tester.pumpWidget(await _wrap(service: service, email: null));
    await tester.pumpAndSettle();

    expect(find.byKey(ProfileKeys.signOutDeviceTile), findsNothing);
    expect(find.text('Not set'), findsOneWidget);
  });

  testWidgets('sign-out row is visible for linked users', (tester) async {
    await tester.pumpWidget(
      await _wrap(service: service, email: 'foo@example.com'),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(ProfileKeys.signOutDeviceTile), findsOneWidget);
    expect(find.text('foo@example.com'), findsOneWidget);
  });

  testWidgets('cancelling the dialog does not call signOutCurrentDevice',
      (tester) async {
    await tester.pumpWidget(
      await _wrap(service: service, email: 'foo@example.com'),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(ProfileKeys.signOutDeviceTile));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ProfileKeys.signOutDeviceTile));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('signOutConfirm.cancel')));
    await tester.pumpAndSettle();

    verifyNever(() => service.signOutCurrentDevice());
  });

  testWidgets('confirming calls signOutCurrentDevice and surfaces a snack',
      (tester) async {
    when(() => service.signOutCurrentDevice()).thenAnswer((_) async {});

    await tester.pumpWidget(
      await _wrap(service: service, email: 'foo@example.com'),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(ProfileKeys.signOutDeviceTile));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ProfileKeys.signOutDeviceTile));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('signOutConfirm.confirm')));
    await tester.pumpAndSettle();

    verify(() => service.signOutCurrentDevice()).called(1);
    expect(find.text('Signed out'), findsOneWidget);
  });

  testWidgets('failure surfaces a friendly snack', (tester) async {
    when(() => service.signOutCurrentDevice()).thenThrow(StateError('boom'));

    await tester.pumpWidget(
      await _wrap(service: service, email: 'foo@example.com'),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(ProfileKeys.signOutDeviceTile));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ProfileKeys.signOutDeviceTile));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('signOutConfirm.confirm')));
    await tester.pumpAndSettle();

    expect(find.text("Couldn't sign out. Try again."), findsOneWidget);
  });
}
