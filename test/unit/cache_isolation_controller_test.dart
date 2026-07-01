import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safar/core/providers/app_bootstrap_provider.dart';
import 'package:safar/core/providers/connectivity_provider.dart';
import 'package:safar/core/services/cache_isolation_controller.dart';
import 'package:safar/core/services/cache_uid_barrier.dart';
import 'package:safar/core/services/notification_service.dart';
import 'package:safar/features/auth/providers/auth_email_link_bootstrap_provider.dart';
import 'package:safar/features/auth/providers/cache_isolation_controller_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('markFirestorePersistenceDirty', () {
    test(
      'sets the dirty flag true so the next boot reconcile clears',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final prefs = await SharedPreferences.getInstance();

        await markFirestorePersistenceDirty(prefs);

        expect(prefs.getBool(kFirestorePersistenceDirtyKey), isTrue);
      },
    );
  });

  group('PlatformCacheIsolationController', () {
    test('engageIsolation flips the flag AND invalidates the leaf subscription '
        'providers (R5 P2-1)', () {
      // Stub the leaf providers with build-counters so we (a) avoid the real
      // Firebase/app_links/settings side effects and (b) can prove each was
      // invalidated — a fresh read after engageIsolation re-runs the build.
      final builds = <String, int>{
        'authLink': 0,
        'connectivity': 0,
        'notif': 0,
        'bootstrap': 0,
      };
      final container = ProviderContainer(
        overrides: [
          authEmailLinkBootstrapProvider.overrideWith((ref) {
            builds['authLink'] = builds['authLink']! + 1;
          }),
          connectivityProvider.overrideWith((ref) {
            builds['connectivity'] = builds['connectivity']! + 1;
            return ConnectivityNotifier(startPeriodicChecks: false);
          }),
          notificationServiceProvider.overrideWith((ref) {
            builds['notif'] = builds['notif']! + 1;
            return NotificationService(ref);
          }),
          appBootstrapProvider.overrideWith((ref) {
            builds['bootstrap'] = builds['bootstrap']! + 1;
          }),
        ],
      );
      addTearDown(container.dispose);

      // Materialize the leaves so there is something to tear down.
      container.read(authEmailLinkBootstrapProvider);
      container.read(connectivityProvider);
      container.read(notificationServiceProvider);
      container.read(appBootstrapProvider);
      expect(builds, {
        'authLink': 1,
        'connectivity': 1,
        'notif': 1,
        'bootstrap': 1,
      });
      expect(container.read(cacheIsolationProvider), isFalse);

      container.read(cacheIsolationControllerProvider).engageIsolation();

      expect(container.read(cacheIsolationProvider), isTrue);
      // Re-read to force any deferred rebuild after invalidation.
      container.read(authEmailLinkBootstrapProvider);
      container.read(connectivityProvider);
      container.read(notificationServiceProvider);
      container.read(appBootstrapProvider);
      expect(builds, {
        'authLink': 2,
        'connectivity': 2,
        'notif': 2,
        'bootstrap': 2,
      });
    });

    test('restart invokes the native restart channel method', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final controller = container.read(cacheIsolationControllerProvider);

      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(kCacheIsolationChannel, (call) async {
            calls.add(call);
            return null;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(kCacheIsolationChannel, null);
      });

      await controller.restart();

      expect(calls, hasLength(1));
      expect(calls.single.method, 'restart');
    });

    test(
      'restart that throws does NOT propagate and flips the restart-failed flag '
      'so the overlay can surface a manual escape (#45 §6.3)',
      () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final controller = container.read(cacheIsolationControllerProvider);

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(kCacheIsolationChannel, (call) async {
              throw PlatformException(
                code: 'no_handler',
                message: 'no native restart handler on this platform',
              );
            });
        addTearDown(() {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(kCacheIsolationChannel, null);
        });

        expect(container.read(cacheIsolationRestartFailedProvider), isFalse);

        // Must NOT throw — a propagating restart() strands the isolation
        // overlay with no escape (the codex re-gate [P1]).
        await controller.restart();

        expect(container.read(cacheIsolationRestartFailedProvider), isTrue);
      },
    );
  });
}
