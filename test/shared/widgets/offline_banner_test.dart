import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/core/providers/connectivity_provider.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/l10n/generated/app_localizations.dart';
import 'package:safar/shared/widgets/offline_banner.dart';

// Uses the same direct pump pattern as the existing OfflineBanner harness in
// test/unit/widget_coverage_test.dart instead of `pumpRihlaApp`. The shared
// helper calls `tester.pump()` + a delayed pump which (combined with the
// real `ConnectivityNotifier`'s periodic timer and binding observer) makes
// the test framework hang at finalization. The direct pattern uses
// `pumpWidget` + a single `pump` which completes cleanly.

Future<void> _pumpOfflineBanner(WidgetTester tester, {Locale? locale}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        connectivityProvider.overrideWith(
          (ref) => ConnectivityNotifier()..setOffline(),
        ),
      ],
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: AppTheme.lightTheme,
        home: const Scaffold(body: OfflineBanner()),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('OfflineBanner renders English offline message in en locale',
      (tester) async {
    await _pumpOfflineBanner(tester);
    expect(
      find.text("You're offline — changes will sync later"),
      findsOneWidget,
    );
  });

  testWidgets('OfflineBanner renders Arabic offline message in ar locale',
      (tester) async {
    await _pumpOfflineBanner(tester, locale: const Locale('ar'));
    expect(
      find.text("أنت غير متصل — ستتم مزامنة التغييرات لاحقًا"),
      findsOneWidget,
    );
  });
}
