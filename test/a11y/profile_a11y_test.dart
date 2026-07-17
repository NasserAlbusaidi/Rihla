// #1283 — accessibility guideline matchers for ProfileScreen.
//
// Arrange section copied from test/features/profile/profile_screen_test.dart
// (`_buildTestApp`/`_phase26Overrides`/`_pumpWithAnimations`) — reuse, don't
// invent new fixtures.

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:safar/core/config/app_metadata.dart';
import 'package:safar/core/providers/app_bootstrap_provider.dart';
import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/services/notification_service.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/settings/providers/profile_stats_provider.dart';
import 'package:safar/features/settings/screens/profile_screen.dart';
import 'package:safar/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockNotificationService extends Mock implements NotificationService {}

Widget _buildTestApp(Widget widget, {List<Override> overrides = const [], Locale? locale}) {
  final router = GoRouter(
    initialLocation: '/profile',
    routes: [GoRoute(path: '/profile', builder: (ctx, state) => widget)],
  );

  return ProviderScope(
    overrides: overrides,
    child: MaterialApp.router(
      theme: AppTheme.lightTheme,
      locale: locale,
      routerConfig: router,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    ),
  );
}

AsyncValue<ProfileStats> _statsData() => AsyncValue.data((
  groupCount: 3,
  eventCount: 5,
  spentByCurrency: [(currency: 'OMR', amount: Decimal.parse('120.000'))],
));

/// Pump the widget tree and advance time enough for all flutter_animate
/// animations to complete (identity section delays up to 200ms; support
/// section delays up to 500ms).
Future<void> _pumpWithAnimations(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 700));
  await tester.pump();
}

List<Override> _phase26Overrides({required SharedPreferences prefs}) {
  final mockNotifService = MockNotificationService();
  when(mockNotifService.initialize).thenAnswer((_) async => true);
  when(mockNotifService.removeToken).thenAnswer((_) async {});

  return [
    sharedPreferencesProvider.overrideWithValue(prefs),
    profileStatsProvider.overrideWith((ref) => _statsData()),
    notificationStatusProvider.overrideWith(
      (ref) => NotificationStatus.enabled,
    ),
    notificationServiceProvider.overrideWithValue(mockNotifService),
    appBootstrapProvider.overrideWith((ref) {}),
    appMetadataProvider.overrideWith(
      (ref) => Future.value(
        const AppMetadata(
          appName: 'Rihla',
          packageName: 'com.safar.safar',
          version: '2.2.0',
          buildNumber: '1',
        ),
      ),
    ),
  ];
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpScreen(WidgetTester tester, {required Locale locale}) async {
    SharedPreferences.setMockInitialValues({
      'settings_device_name': 'Alice',
    });
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      _buildTestApp(
        const ProfileScreen(),
        overrides: _phase26Overrides(prefs: prefs),
        locale: locale,
      ),
    );
    await _pumpWithAnimations(tester);
  }

  group('ProfileScreen accessibility (#1283)', () {
    testWidgets('EN meets labeledTapTargetGuideline', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpScreen(tester, locale: const Locale('en'));

      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });

    testWidgets('AR meets labeledTapTargetGuideline', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpScreen(tester, locale: const Locale('ar'));

      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });

    // androidTapTargetGuideline (48x48) is deliberately NOT asserted — the
    // top-bar "Share Rihla" action (GhostIcon, Iconsax.export_1,
    // lib/features/settings/widgets/profile/ghost_icon.dart) is a hardcoded
    // 44x44 SizedBox tap area, matching the project's 44dp floor
    // (docs/DESIGN.md §4) but under Android's 48dp. Same project-wide
    // deliberate-floor pattern as Home/GroupDetail — reported upstream, not
    // fixed in this test-only PR.
    testWidgets('EN meets textContrastGuideline', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpScreen(tester, locale: const Locale('en'));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      handle.dispose();
    });

    testWidgets('AR meets textContrastGuideline', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpScreen(tester, locale: const Locale('ar'));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      handle.dispose();
    });
  });
}
