import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/groups/screens/join_group_screen.dart';
import 'package:safar/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpJoin(WidgetTester tester, Widget home) async {
    final prefs = await SharedPreferences.getInstance();
    final router = GoRouter(
      initialLocation: '/screen',
      routes: [GoRoute(path: '/screen', builder: (_, _) => home)],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          deviceLocalesProvider.overrideWithValue(const [Locale('en')]),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          theme: AppTheme.lightTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  String fieldText(WidgetTester tester, Finder finder) =>
      tester.widget<TextField>(finder).controller!.text;

  testWidgets('route-supplied initialInviteCode prefills the code field', (
    tester,
  ) async {
    await pumpJoin(tester, const JoinGroupScreen(initialInviteCode: 'ROUTED'));

    final fields = find.byType(TextField);
    // Name field (0), invite-code field (1).
    expect(fieldText(tester, fields.at(1)), 'ROUTED');
  });

  testWidgets('#293: join name is NOT seeded from settings', (tester) async {
    SharedPreferences.setMockInitialValues({
      'settings_device_name': 'DeviceName',
    });

    await pumpJoin(tester, const JoinGroupScreen());

    final fields = find.byType(TextField);
    expect(fieldText(tester, fields.at(0)), isEmpty);
    expect(fieldText(tester, fields.at(1)), isEmpty);
  });
}
