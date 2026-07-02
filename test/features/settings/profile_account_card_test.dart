// Account-card rework (#428 PR-B): Google row, durable-gated sign-out,
// tap-gated restore entries, Google-aware sign-out copy.
//
// Visibility matrix:
//   anon + zero groups   → link row + both restore rows; no sign-out
//   anon + groups        → link row + both restore rows VISIBLE; a tap is
//                          blocked with restoreBlockedHasData (the emptiness
//                          check moved from row visibility to tap time —
//                          friction audit tranche 2; the authoritative gate
//                          still runs AT THE SWAP, #647/#648)
//   Google-linked (no email) → Google row + sign-out; no link/restore rows
//   email-linked         → legacy behavior + no Google row
// Harness mirrors sign_out_tile_test.dart.

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
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/settings/keys/profile_keys.dart';
import 'package:safar/features/settings/providers/profile_stats_provider.dart'
    as profile_stats;
import 'package:safar/features/settings/screens/profile_screen.dart';
import 'package:safar/l10n/generated/app_localizations.dart';
import 'package:safar/l10n/generated/app_localizations_en.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockRecoveryService extends Mock implements AuthRecoveryService {}

class _MockUser extends Mock implements firebase_auth.User {}

class _MockUserInfo extends Mock implements firebase_auth.UserInfo {}

firebase_auth.User _anonUser() {
  final u = _MockUser();
  when(() => u.uid).thenReturn('anon-1');
  when(() => u.email).thenReturn(null);
  when(() => u.isAnonymous).thenReturn(true);
  when(() => u.providerData).thenReturn(const []);
  return u;
}

firebase_auth.User _googleUser({String? email}) {
  final info = _MockUserInfo();
  when(() => info.providerId).thenReturn('google.com');
  when(() => info.email).thenReturn(email ?? 'g@gmail.com');
  final u = _MockUser();
  when(() => u.uid).thenReturn('g-1');
  // Top-level email deliberately null — the case B.2 newly enables.
  when(() => u.email).thenReturn(null);
  when(() => u.isAnonymous).thenReturn(false);
  when(() => u.providerData).thenReturn([info]);
  return u;
}

firebase_auth.User _emailUser(String email) {
  final info = _MockUserInfo();
  when(() => info.providerId).thenReturn('password');
  when(() => info.email).thenReturn(email);
  final u = _MockUser();
  when(() => u.uid).thenReturn('e-1');
  when(() => u.email).thenReturn(email);
  when(() => u.isAnonymous).thenReturn(false);
  when(() => u.providerData).thenReturn([info]);
  return u;
}

Group _group() => Group(
  id: 'g1',
  name: 'Trip',
  inviteCode: 'ABCDEF',
  createdBy: 'u1',
  memberIds: const ['u1'],
  createdAt: DateTime(2026, 1, 1),
);

Future<Widget> _wrap({
  required _MockRecoveryService service,
  required firebase_auth.User? user,
  List<Group>? groups,
}) async {
  SharedPreferences.setMockInitialValues({
    'settings_device_name': 'Test User',
  });
  final prefs = await SharedPreferences.getInstance();

  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      authRecoveryServiceProvider.overrideWithValue(service),
      authUserChangesProvider.overrideWith(
        (ref) => Stream<firebase_auth.User?>.value(user),
      ),
      // #648: the Google restore now gates on a provably-empty shell, which
      // awaits firebaseUserProvider.future (distinct from authUserChangesProvider
      // above — the gate reads the membership-aware pair). Seed it with the same
      // user so an anon+empty shell still reaches restoreWithGoogle.
      firebaseUserProvider.overrideWith(
        (ref) => Stream<firebase_auth.User?>.value(user),
      ),
      userGroupsProvider.overrideWith(
        (ref) => Stream.value(groups ?? const <Group>[]),
      ),
      profile_stats.profileStatsProvider.overrideWith(
        (ref) => const AsyncValue<profile_stats.ProfileStats>.data(
          (
            groupCount: 0,
            eventCount: 0,
            spentByCurrency: <profile_stats.CurrencySpend>[],
          ),
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
          GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen()),
          GoRoute(
            path: '/recover',
            builder: (_, _) => const Scaffold(body: Text('RecoverStub')),
          ),
        ],
      ),
    ),
  );
}

void main() {
  final l10n = AppLocalizationsEn();
  late _MockRecoveryService service;

  setUp(() {
    service = _MockRecoveryService();
  });

  group('anonymous + zero groups', () {
    testWidgets('link row + both restore rows; sign-out hidden',
        (tester) async {
      await tester.pumpWidget(
        await _wrap(service: service, user: _anonUser()),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(ProfileKeys.googleLinkTile), findsOneWidget);
      expect(find.byKey(ProfileKeys.profileRestoreGoogleTile), findsOneWidget);
      expect(find.byKey(ProfileKeys.profileRestoreEmailTile), findsOneWidget);
      expect(find.byKey(ProfileKeys.signOutDeviceTile), findsNothing);
      expect(find.byKey(ProfileKeys.googleAccountTile), findsNothing);
    });

    testWidgets('restore-with-Google row triggers restoreWithGoogle',
        (tester) async {
      when(() => service.restoreWithGoogle())
          .thenAnswer((_) async => throw StateError('never returns'));
      await tester.pumpWidget(
        await _wrap(service: service, user: _anonUser()),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(ProfileKeys.profileRestoreGoogleTile),
      );
      await tester.tap(find.byKey(ProfileKeys.profileRestoreGoogleTile));
      await tester.pumpAndSettle();

      verify(() => service.restoreWithGoogle()).called(1);
    });

    testWidgets('restore-with-email row pushes /recover', (tester) async {
      await tester.pumpWidget(
        await _wrap(service: service, user: _anonUser()),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(ProfileKeys.profileRestoreEmailTile),
      );
      await tester.tap(find.byKey(ProfileKeys.profileRestoreEmailTile));
      await tester.pumpAndSettle();

      expect(find.text('RecoverStub'), findsOneWidget);
      verifyNever(() => service.restoreWithGoogle());
    });

    testWidgets('link row opens the durable-credential sheet', (tester) async {
      await tester.pumpWidget(
        await _wrap(service: service, user: _anonUser()),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(ProfileKeys.googleLinkTile));
      await tester.tap(find.byKey(ProfileKeys.googleLinkTile));
      await tester.pumpAndSettle();

      expect(find.text(l10n.durableGateTitle), findsOneWidget);
      verifyNever(() => service.linkGoogleToCurrentUser());
    });
  });

  group('anonymous + populated shell', () {
    testWidgets('restore rows stay visible; link row stays', (tester) async {
      await tester.pumpWidget(
        await _wrap(service: service, user: _anonUser(), groups: [_group()]),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(ProfileKeys.profileRestoreGoogleTile), findsOneWidget);
      expect(find.byKey(ProfileKeys.profileRestoreEmailTile), findsOneWidget);
      expect(find.byKey(ProfileKeys.googleLinkTile), findsOneWidget);
    });

    testWidgets(
        'email restore tap is blocked with the has-data explanation — '
        'no /recover push', (tester) async {
      await tester.pumpWidget(
        await _wrap(service: service, user: _anonUser(), groups: [_group()]),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(ProfileKeys.profileRestoreEmailTile),
      );
      await tester.tap(find.byKey(ProfileKeys.profileRestoreEmailTile));
      await tester.pumpAndSettle();

      expect(find.text('RecoverStub'), findsNothing);
      expect(find.text(l10n.restoreBlockedHasData), findsOneWidget);
    });

    testWidgets(
        'Google restore tap is blocked with the has-data explanation — '
        'restoreWithGoogle never called', (tester) async {
      await tester.pumpWidget(
        await _wrap(service: service, user: _anonUser(), groups: [_group()]),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(ProfileKeys.profileRestoreGoogleTile),
      );
      await tester.tap(find.byKey(ProfileKeys.profileRestoreGoogleTile));
      await tester.pumpAndSettle();

      expect(find.text(l10n.restoreBlockedHasData), findsOneWidget);
      verifyNever(() => service.restoreWithGoogle());
    });
  });

  group('Google-linked user without top-level email', () {
    testWidgets('Google row + sign-out visible; link/restore rows hidden',
        (tester) async {
      await tester.pumpWidget(
        await _wrap(service: service, user: _googleUser()),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(ProfileKeys.googleAccountTile), findsOneWidget);
      expect(find.text('g@gmail.com'), findsOneWidget);
      expect(find.byKey(ProfileKeys.signOutDeviceTile), findsOneWidget);
      expect(find.byKey(ProfileKeys.googleLinkTile), findsNothing);
      expect(find.byKey(ProfileKeys.profileRestoreGoogleTile), findsNothing);
    });

    testWidgets(
        'sign-out dialog shows the Google copy (no empty-email gap) and '
        'confirm calls signOutCurrentDevice', (tester) async {
      when(() => service.signOutCurrentDevice()).thenAnswer((_) async {});
      // The recovery identity is Google (linkedEmail null) — the dialog must
      // say "sign back in with Google", not the email-link instruction.
      await tester.pumpWidget(
        await _wrap(service: service, user: _googleUser()),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(ProfileKeys.signOutDeviceTile));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ProfileKeys.signOutDeviceTile));
      await tester.pumpAndSettle();

      expect(find.text(l10n.signOutContentGoogle), findsOneWidget);

      await tester.tap(find.byKey(const Key('signOutConfirm.confirm')));
      await tester.pumpAndSettle();
      verify(() => service.signOutCurrentDevice()).called(1);
    });
  });

  group('email-linked user', () {
    testWidgets('legacy behavior: email row + sign-out; no Google row',
        (tester) async {
      await tester.pumpWidget(
        await _wrap(service: service, user: _emailUser('foo@example.com')),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(ProfileKeys.googleAccountTile), findsNothing);
      expect(find.byKey(ProfileKeys.googleLinkTile), findsNothing);
      expect(find.byKey(ProfileKeys.signOutDeviceTile), findsOneWidget);
      expect(find.text('foo@example.com'), findsOneWidget);
      expect(find.byKey(ProfileKeys.profileRestoreGoogleTile), findsNothing);
    });
  });

  // #487 bullet 3: the account section was one flat list that mixed the
  // credential/recovery rows with the irreversible Delete. It now splits into
  // a "Backup & recovery" block and an isolated "Danger" block.
  group('danger zone isolation (#487 bullet 3)', () {
    testWidgets(
        'recovery rows sit under BACKUP & RECOVERY; delete lives alone in a '
        'separate DANGER block', (tester) async {
      await tester.pumpWidget(
        await _wrap(service: service, user: _anonUser()),
      );
      await tester.pumpAndSettle();

      // The single "ACCOUNT" header is replaced by two labelled blocks.
      expect(find.text(l10n.profileSectionBackupRecovery), findsOneWidget);
      expect(find.text(l10n.profileSectionDanger), findsOneWidget);

      // Delete is isolated inside the danger card…
      expect(
        find.descendant(
          of: find.byKey(ProfileKeys.dangerZoneCard),
          matching: find.byKey(ProfileKeys.deleteAccountTile),
        ),
        findsOneWidget,
      );
      // …and the recovery/link rows do NOT leak into the danger card.
      expect(
        find.descendant(
          of: find.byKey(ProfileKeys.dangerZoneCard),
          matching: find.byKey(ProfileKeys.profileRestoreEmailTile),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byKey(ProfileKeys.dangerZoneCard),
          matching: find.byKey(ProfileKeys.googleLinkTile),
        ),
        findsNothing,
      );
    });

    testWidgets('durable user also gets the isolated DANGER block',
        (tester) async {
      await tester.pumpWidget(
        await _wrap(service: service, user: _emailUser('foo@example.com')),
      );
      await tester.pumpAndSettle();

      expect(find.text(l10n.profileSectionDanger), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(ProfileKeys.dangerZoneCard),
          matching: find.byKey(ProfileKeys.deleteAccountTile),
        ),
        findsOneWidget,
      );
    });
  });
}
