import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/auth/providers/auth_provider.dart';
import 'package:safar/features/auth/services/auth_recovery_service.dart';
import 'package:safar/features/auth/services/durable_credential_exception.dart';
import 'package:safar/features/groups/models/group_model.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/home/keys/home_keys.dart';
import 'package:safar/features/home/widgets/account_backup_nudge.dart';
import 'package:safar/l10n/generated/app_localizations.dart';
import 'package:safar/l10n/generated/app_localizations_en.dart';

class _MockAuthRecoveryService extends Mock implements AuthRecoveryService {}

class _FakeAuthCredential extends Fake implements AuthCredential {}

GoogleLinkConflictException _conflict() => GoogleLinkConflictException(
  credential: _FakeAuthCredential(),
  cause: FirebaseAuthException(code: 'credential-already-in-use'),
);

Group _group() => Group(
  id: 'g1',
  name: 'Trip',
  inviteCode: 'ABCDEF',
  createdBy: 'u1',
  memberIds: const ['u1'],
  createdAt: DateTime(2026, 1, 1),
);

Future<void> _pump(
  WidgetTester tester, {
  required SharedPreferences prefs,
  bool isDurable = false,
  Locale? locale,
  AuthRecoveryService? recovery,
  Stream<List<Group>>? groups,
}) async {
  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(
        path: '/home',
        builder: (ctx, state) =>
            const Scaffold(body: SingleChildScrollView(child: AccountBackupNudge())),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        isDurableUserProvider.overrideWithValue(isDurable),
        if (recovery != null)
          authRecoveryServiceProvider.overrideWithValue(recovery),
        if (groups != null) userGroupsProvider.overrideWith((ref) => groups),
      ],
      child: MaterialApp.router(
        theme: AppTheme.lightTheme,
        locale: locale,
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  late SharedPreferences prefs;
  late _MockAuthRecoveryService recovery;

  setUpAll(() {
    registerFallbackValue(_FakeAuthCredential());
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    recovery = _MockAuthRecoveryService();
  });

  testWidgets('shows for an anonymous user who has not dismissed it', (
    tester,
  ) async {
    await _pump(tester, prefs: prefs);

    expect(find.byKey(HomeKeys.accountBackupNudge), findsOneWidget);
    expect(find.byKey(HomeKeys.accountBackupNudgeCta), findsOneWidget);
  });

  testWidgets(
      'hidden for ANY durable user — Google-linked without email included '
      '(#428: the old linkedEmail==null condition mis-nudged them)',
      (tester) async {
    await _pump(tester, prefs: prefs, isDurable: true);

    expect(find.byKey(HomeKeys.accountBackupNudge), findsNothing);
  });

  testWidgets('hidden once the dismiss flag is set', (tester) async {
    SharedPreferences.setMockInitialValues({
      'settings_email_link_nudge_seen': true,
    });
    prefs = await SharedPreferences.getInstance();

    await _pump(tester, prefs: prefs);

    expect(find.byKey(HomeKeys.accountBackupNudge), findsNothing);
  });

  testWidgets('CTA opens the durable-credential (Google) sheet (#428)',
      (tester) async {
    await _pump(tester, prefs: prefs);

    await tester.tap(find.byKey(HomeKeys.accountBackupNudgeCta));
    await tester.pumpAndSettle();

    final l10n = AppLocalizationsEn();
    expect(find.text(l10n.durableGateTitle), findsOneWidget);
  });

  // #647 box (e): the voluntary backup nudge routes through the SAME gated
  // sheet as the create/join gate (showDurableCredentialSheet) — it must never
  // hand-roll a link. So a Google link-conflict on a POPULATED anon shell hits
  // the empty-shell guard: dead-end copy, and restoreWithGoogle is NEVER
  // reached (a swap would silently orphan this device's groups, #647/#648).
  // Characterization test pinning already-correct routing — not a bug fix.
  testWidgets(
    'CTA → link conflict on a populated shell shows the dead-end copy and '
    'never swaps accounts (#647)',
    (tester) async {
      when(
        () => recovery.linkGoogleToCurrentUser(),
      ).thenThrow(_conflict());

      await _pump(
        tester,
        prefs: prefs,
        recovery: recovery,
        groups: Stream.value([_group()]),
      );

      await tester.tap(find.byKey(HomeKeys.accountBackupNudgeCta));
      await tester.pumpAndSettle();

      final l10n = AppLocalizationsEn();
      await tester.tap(find.text(l10n.durableGateContinueGoogle));
      // conflict-loading / _restoring spinners animate forever, so
      // pumpAndSettle would time out — bounded pumps instead.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text(l10n.durableGateConflict), findsOneWidget);
      expect(find.byKey(const Key('durableGate.switch')), findsNothing);
      verifyNever(
        () => recovery.restoreWithGoogle(credential: any(named: 'credential')),
      );
    },
  );

  testWidgets('Not now dismisses the card and persists the flag', (
    tester,
  ) async {
    await _pump(tester, prefs: prefs);
    expect(find.byKey(HomeKeys.accountBackupNudge), findsOneWidget);

    await tester.tap(find.byKey(HomeKeys.accountBackupNudgeDismiss));
    await tester.pumpAndSettle();

    expect(find.byKey(HomeKeys.accountBackupNudge), findsNothing);
    expect(prefs.getBool('settings_email_link_nudge_seen'), isTrue);
  });

  // Regression: the card renders for the common anonymous case on every device.
  // Its actions must never RenderFlex-overflow at narrow widths, and the long
  // Arabic CTA ("أضف بريدًا إلكترونيًا") is the worst case in RTL.
  for (final (name, locale) in const [
    ('English', Locale('en')),
    ('Arabic', Locale('ar')),
  ]) {
    for (final width in const [360.0, 320.0]) {
      testWidgets('does not overflow at ${width.toInt()}px in $name', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 720);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await _pump(tester, prefs: prefs, locale: locale);

        expect(find.byKey(HomeKeys.accountBackupNudge), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
