import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

/// Pumps [child] inside a minimal Rihla app shell:
/// `ProviderScope` (with `sharedPreferencesProvider` overridden by default)
/// → `MaterialApp` (with localization delegates and theme).
///
/// Defaults to English locale. Pass [locale] to force Arabic. Pass [overrides]
/// to inject additional Riverpod overrides on top of the SharedPreferences
/// default.
///
/// **Router-aware tests are NOT supported by this helper** — it wraps `child`
/// in a plain `MaterialApp`, not `MaterialApp.router`. PR1's translated
/// surfaces (`OfflineBanner`, `WordmarkLogo`) don't navigate, so the trade
/// is acceptable. When PR3 needs to widget-test a screen that calls
/// `context.go(...)` or asserts on a route guard, add a sibling
/// `pumpRihlaAppRouted` helper rather than overloading this one.
///
/// **Locale wiring drift, by design:** this helper passes [locale] directly
/// into `MaterialApp`, bypassing both `settingsProvider` and `localeProvider`.
/// Unit tests using this helper therefore CANNOT catch a regression where
/// `localeProvider` is wired wrong but `MaterialApp.locale` happens to be
/// hardcoded somewhere. The Arabic golden-path integration test
/// (`integration_test/golden_path_arabic_test.dart`) is the only PR1
/// coverage for the full `settings → localeProvider →
/// MaterialApp.router(locale)` chain.
Future<void> pumpRihlaApp(
  WidgetTester tester,
  Widget child, {
  Locale locale = const Locale('en'),
  List<Override> overrides = const [],
}) async {
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        ...overrides,
      ],
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: AppTheme.lightTheme,
        home: child,
      ),
    ),
  );
  await tester.pumpAndSettle();
}
