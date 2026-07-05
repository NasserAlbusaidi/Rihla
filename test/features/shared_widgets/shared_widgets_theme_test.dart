// Smoke test for Phase 37 Wave 2 shared-widget migration.
//
// Confirms every migrated widget in `lib/shared/widgets/` builds without
// throwing in BOTH the light and the dark theme — i.e. `context.colors.*`
// resolves on every code path touched by the palette swap.
//
// This is a smoke gate, not a pixel test. Plan 05 owns golden tests.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax/iconsax.dart';

import 'package:safar/core/providers/connectivity_provider.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/l10n/generated/app_localizations.dart';
import 'package:safar/shared/widgets/empty_state_view.dart';
import 'package:safar/shared/widgets/loading_button.dart';
import 'package:safar/shared/widgets/r_avatar.dart';
import 'package:safar/shared/widgets/module_header.dart';
import 'package:safar/shared/widgets/offline_banner.dart';
import 'package:safar/shared/widgets/skeleton_loader.dart';
import 'package:safar/shared/widgets/skeleton_primitives.dart';

/// Wraps [child] in a themed [MaterialApp] using [mode] for the active
/// ThemeMode. Both themes register the full AppColorTokens / Spacing /
/// Shadow extension set, so `context.colors` resolves under either.
Widget _wrap(Widget child, {required ThemeMode mode}) {
  return ProviderScope(
    overrides: [
      // Offline banner reads this; give it a deterministic value so the
      // banner widget builds its non-empty branch when requested.
      connectivityProvider.overrideWith(
        (ref) => ConnectivityNotifier(startPeriodicChecks: false)..setOffline(),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: mode,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  // Build inside a bounded constraints box — some widgets (skeletons)
  // rely on parent height.
  Widget bounded(Widget child) =>
      SizedBox(width: 400, height: 400, child: child);

  // The widget set. Each entry is { label → builder }. Builders are
  // closures rather than cached widgets because some carry TickerProvider
  // coupling that must happen fresh per pump.
  final widgets = <String, Widget Function()>{
    'EmptyStateView': () => const EmptyStateView(
          icon: Iconsax.calendar,
          title: 'Empty',
          message: 'Nothing here yet',
        ),
    'EmptyStateView (with action)': () => EmptyStateView(
          icon: Iconsax.add_circle,
          title: 'Add one',
          message: 'Tap below',
          actionLabel: 'Create',
          onAction: () {},
        ),
    'RAvatar': () => const RAvatar(size: 48, name: 'Alice Smith'),
    'LoadingButton (idle)': () => LoadingButton(
          label: 'Tap',
          isLoading: false,
          onPressed: () {},
        ),
    'LoadingButton (loading)': () => LoadingButton(
          label: 'Tap',
          isLoading: true,
          onPressed: () {},
        ),
    'ModuleHeader (light)': () => const ModuleHeader(
          title: 'Expenses',
          subtitle: 'LEDGER',
        ),
    'ModuleHeader (dark)': () => const ModuleHeader(
          title: 'Expenses',
          subtitle: 'LEDGER',
          useDarkTheme: true,
        ),
    'OfflineBanner': () => const OfflineBanner(),
    'SkeletonLoader.dashboardHero': () =>
        bounded(SkeletonLoader.dashboardHero()),
    'SkeletonLoader.eventCard': () => bounded(SkeletonLoader.eventCard()),
    'SkeletonLoader.groupList': () => bounded(SkeletonLoader.groupList()),
    'SkeletonLoader.expenseList': () => bounded(SkeletonLoader.expenseList()),
    'SkeletonLoader.gearList': () => bounded(SkeletonLoader.gearList()),
    'SkeletonLoader.photoGrid': () => bounded(SkeletonLoader.photoGrid()),
    'SkeletonLoader.generic': () => bounded(SkeletonLoader.generic()),
    'SkeletonLoader.cardList': () => bounded(SkeletonLoader.cardList()),
    'SkeletonLoader.documentList': () =>
        bounded(SkeletonLoader.documentList()),
    'SkeletonLoader.card()': () => bounded(SkeletonLoader.card()),
    'SkeletonCircle': () => const SkeletonCircle(size: 24),
    'SkeletonBar': () => const SkeletonBar(width: 100),
    'SkeletonBlock': () => const SkeletonBlock(width: 80, height: 40),
    'SkeletonRow': () => const SkeletonRow(),
    'SkeletonCard': () => const SkeletonCard(),
  };

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    group('Shared widgets render under $mode', () {
      for (final entry in widgets.entries) {
        testWidgets(entry.key, (tester) async {
          await tester.pumpWidget(_wrap(entry.value(), mode: mode));
          // Let any initial animations (flutter_animate entrances, skeleton
          // shimmer, etc) settle without risking a `pumpAndSettle` hang on
          // looping shimmer tickers.
          await tester.pump(const Duration(milliseconds: 500));
          expect(tester.takeException(), isNull,
              reason:
                  '${entry.key} threw under $mode — check context.colors resolution');
        });
      }
    });
  }
}
