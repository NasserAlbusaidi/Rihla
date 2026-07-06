import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/router/app_router.dart';
import 'package:safar/core/services/cache_isolation_controller.dart';
import 'package:safar/features/auth/providers/cache_isolation_controller_provider.dart';
import 'package:safar/main.dart';

/// Records restart() calls so the manual-restart affordance can be verified.
class _RecordingController implements CacheIsolationController {
  int restarts = 0;
  @override
  void engageIsolation() {}
  @override
  Future<void> restart() async {
    restarts += 1;
  }
}

void main() {
  // Drains the overlay's restart watchdog timer so the test doesn't end with a
  // pending Timer.
  Future<void> drainWatchdog(WidgetTester tester) =>
      tester.pump(const Duration(seconds: 8));

  testWidgets(
    'engaged isolation short-circuits SafarApp to the overlay before the router '
    'is ever built (#45 §3.7)',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            cacheIsolationProvider.overrideWith((ref) => true),
            // If the short-circuit (build) or the post-frame guard failed,
            // SafarApp would read routerProvider and this throw would surface
            // the regression.
            routerProvider.overrideWith(
              (ref) => throw StateError('router must not build while isolated'),
            ),
          ],
          child: const SafarApp(),
        ),
      );
      // One frame only — the splash's indeterminate progress bar never settles.
      await tester.pump();

      expect(
        find.byKey(const Key('cache-isolation-overlay')),
        findsOneWidget,
      );

      await drainWatchdog(tester);
    },
  );

  testWidgets(
    'a failed restart surfaces a manual restart affordance whose retry '
    're-invokes restart() — the overlay can never strand (#45 §6.3, codex [P1])',
    (tester) async {
      final controller = _RecordingController();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            cacheIsolationProvider.overrideWith((ref) => true),
            cacheIsolationRestartFailedProvider.overrideWith((ref) => true),
            cacheIsolationControllerProvider.overrideWithValue(controller),
            routerProvider.overrideWith(
              (ref) => throw StateError('router must not build while isolated'),
            ),
          ],
          child: const SafarApp(),
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('cache-isolation-restart')), findsOneWidget);
      // The opaque "switching" splash is replaced by the manual affordance.
      expect(find.byKey(const Key('cache-isolation-overlay')), findsNothing);

      await tester.tap(find.text('Try again'));
      await tester.pump();
      expect(controller.restarts, 1);

      await drainWatchdog(tester);
    },
  );

  testWidgets(
    'the overlay surfaces a manual restart after the watchdog window even '
    'without an explicit failure (#45 §6.3 — restart no-op case)',
    (tester) async {
      final controller = _RecordingController();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            cacheIsolationProvider.overrideWith((ref) => true),
            cacheIsolationControllerProvider.overrideWithValue(controller),
            routerProvider.overrideWith(
              (ref) => throw StateError('router must not build while isolated'),
            ),
          ],
          child: const SafarApp(),
        ),
      );
      await tester.pump();

      // Pre-watchdog: opaque splash, no escape yet.
      expect(find.byKey(const Key('cache-isolation-overlay')), findsOneWidget);
      expect(find.byKey(const Key('cache-isolation-restart')), findsNothing);

      // Past the watchdog window: manual affordance appears.
      await tester.pump(const Duration(seconds: 8));
      expect(find.byKey(const Key('cache-isolation-restart')), findsOneWidget);
    },
  );

  testWidgets(
    'iOS: failed restart shows manual-restart copy with NO retry button — '
    'the native channel has no iOS handler, so retry can never succeed (#946)',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final controller = _RecordingController();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            cacheIsolationProvider.overrideWith((ref) => true),
            cacheIsolationRestartFailedProvider.overrideWith((ref) => true),
            cacheIsolationControllerProvider.overrideWithValue(controller),
            routerProvider.overrideWith(
              (ref) => throw StateError('router must not build while isolated'),
            ),
          ],
          child: const SafarApp(),
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const Key('cache-isolation-manual-restart')),
        findsOneWidget,
      );
      expect(find.byType(ElevatedButton), findsNothing);
      // Outcome-neutral instruction copy, not the generic error copy.
      expect(find.text('One last step'), findsOneWidget);
      expect(find.text("Something's off"), findsNothing);

      await drainWatchdog(tester);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'Android: failed restart keeps the retry affordance (#946 regression pin)',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final controller = _RecordingController();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            cacheIsolationProvider.overrideWith((ref) => true),
            cacheIsolationRestartFailedProvider.overrideWith((ref) => true),
            cacheIsolationControllerProvider.overrideWithValue(controller),
            routerProvider.overrideWith(
              (ref) => throw StateError('router must not build while isolated'),
            ),
          ],
          child: const SafarApp(),
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('cache-isolation-restart')), findsOneWidget);
      expect(
        find.byKey(const Key('cache-isolation-manual-restart')),
        findsNothing,
      );
      await tester.tap(find.byType(ElevatedButton));
      await tester.pump();
      expect(controller.restarts, 1);

      await drainWatchdog(tester);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'the overlay follows the in-app locale, not the system locale — Arabic '
    'manual-restart instructions render for an AR-preference user (#946 Gate P2)',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final controller = _RecordingController();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            cacheIsolationProvider.overrideWith((ref) => true),
            cacheIsolationRestartFailedProvider.overrideWith((ref) => true),
            cacheIsolationControllerProvider.overrideWithValue(controller),
            localeProvider.overrideWithValue(const Locale('ar')),
            routerProvider.overrideWith(
              (ref) => throw StateError('router must not build while isolated'),
            ),
          ],
          child: const SafarApp(),
        ),
      );
      await tester.pump();

      expect(find.text('خطوة أخيرة'), findsOneWidget);
      expect(find.text('One last step'), findsNothing);

      await drainWatchdog(tester);
      debugDefaultTargetPlatformOverride = null;
    },
  );
}
