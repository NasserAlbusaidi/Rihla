import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/core/keys/shared_keys.dart';
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

Future<void> _pumpOfflineBanner(
  WidgetTester tester, {
  Locale? locale,
  ConnectivityStatus status = ConnectivityStatus.offline,
}) async {
  // Timer-free notifier (#357) so the periodic check never settles into a hang.
  final notifier = ConnectivityNotifier(startPeriodicChecks: false);
  switch (status) {
    case ConnectivityStatus.offline:
      notifier.setOffline();
    case ConnectivityStatus.syncing:
      notifier.setSyncing();
    case ConnectivityStatus.online:
      notifier.setOnline();
  }
  await tester.pumpWidget(
    ProviderScope(
      overrides: [connectivityProvider.overrideWith((ref) => notifier)],
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
      find.text('أنت غير متصل — ستتم مزامنة التغييرات لاحقًا'),
      findsOneWidget,
    );
  });

  testWidgets('OfflineBanner renders "Saved — will sync" when syncing (#357)',
      (tester) async {
    await _pumpOfflineBanner(tester, status: ConnectivityStatus.syncing);
    expect(find.text('Saved — will sync'), findsOneWidget);
    // The offline copy must NOT show in the syncing state.
    expect(find.text("You're offline — changes will sync later"), findsNothing);
  });

  testWidgets('OfflineBanner renders the Arabic syncing message (#357)',
      (tester) async {
    await _pumpOfflineBanner(
      tester,
      locale: const Locale('ar'),
      status: ConnectivityStatus.syncing,
    );
    expect(find.text('تم الحفظ — ستتم المزامنة'), findsOneWidget);
  });

  testWidgets('OfflineBanner is hidden when online (#357)', (tester) async {
    await _pumpOfflineBanner(tester, status: ConnectivityStatus.online);
    expect(find.byKey(SharedKeys.offlineBanner), findsNothing);
    expect(find.text('Saved — will sync'), findsNothing);
    expect(find.text("You're offline — changes will sync later"), findsNothing);
  });
}
