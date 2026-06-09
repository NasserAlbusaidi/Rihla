import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/auth/providers/auth_provider.dart';
import 'package:safar/features/home/keys/home_keys.dart';
import 'package:safar/features/home/widgets/account_backup_nudge.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

Future<void> _pump(
  WidgetTester tester, {
  required SharedPreferences prefs,
  String? linkedEmail,
  Locale? locale,
}) async {
  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(
        path: '/home',
        builder: (ctx, state) =>
            const Scaffold(body: SingleChildScrollView(child: AccountBackupNudge())),
      ),
      GoRoute(
        path: '/profile/link-email',
        builder: (ctx, state) =>
            const Scaffold(body: Text('LinkEmailScreen-marker')),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        linkedEmailProvider.overrideWithValue(linkedEmail),
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

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  testWidgets('shows for an anonymous user who has not dismissed it', (
    tester,
  ) async {
    await _pump(tester, prefs: prefs, linkedEmail: null);

    expect(find.byKey(HomeKeys.accountBackupNudge), findsOneWidget);
    expect(find.byKey(HomeKeys.accountBackupNudgeCta), findsOneWidget);
  });

  testWidgets('hidden when an email is already linked', (tester) async {
    await _pump(tester, prefs: prefs, linkedEmail: 'traveller@example.com');

    expect(find.byKey(HomeKeys.accountBackupNudge), findsNothing);
  });

  testWidgets('hidden once the dismiss flag is set', (tester) async {
    SharedPreferences.setMockInitialValues({
      'settings_email_link_nudge_seen': true,
    });
    prefs = await SharedPreferences.getInstance();

    await _pump(tester, prefs: prefs, linkedEmail: null);

    expect(find.byKey(HomeKeys.accountBackupNudge), findsNothing);
  });

  testWidgets('Add email routes to the link-email screen', (tester) async {
    await _pump(tester, prefs: prefs, linkedEmail: null);

    await tester.tap(find.byKey(HomeKeys.accountBackupNudgeCta));
    await tester.pumpAndSettle();

    expect(find.text('LinkEmailScreen-marker'), findsOneWidget);
  });

  testWidgets('Not now dismisses the card and persists the flag', (
    tester,
  ) async {
    await _pump(tester, prefs: prefs, linkedEmail: null);
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

        await _pump(tester, prefs: prefs, linkedEmail: null, locale: locale);

        expect(find.byKey(HomeKeys.accountBackupNudge), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
