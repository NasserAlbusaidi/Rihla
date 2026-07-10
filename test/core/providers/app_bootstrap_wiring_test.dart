import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:safar/core/models/app_settings_model.dart';
import 'package:safar/core/providers/app_bootstrap_provider.dart';
import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/services/notification_service.dart';
import 'package:safar/features/auth/providers/auth_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockNotificationService extends Mock implements NotificationService {}

void main() {
  late MockNotificationService mockNotificationService;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockNotificationService = MockNotificationService();
    when(
      () => mockNotificationService.initialize(
        handleInitialMessage: any(named: 'handleInitialMessage'),
      ),
    ).thenAnswer((_) async => true);
    when(
      () => mockNotificationService.removeToken(
        handleInitialMessage: any(named: 'handleInitialMessage'),
      ),
    ).thenAnswer((_) async {});
    when(
      () => mockNotificationService.refreshTokenLocale(),
    ).thenAnswer((_) async {});
  });

  group('appBootstrapProvider wiring', () {
    // #635: the eager boot-time sync no longer fires on provider ACTIVATION —
    // it's deferred to a post-first-frame callback in SafarApp.initState. So
    // merely activating the provider must NOT touch the notification service;
    // the listener now reacts only to LATER toggles.
    test(
      'does NOT call initialize() on activation (deferred off first frame, #635)',
      () async {
        final container = ProviderContainer(
          overrides: [
            notificationServiceProvider.overrideWithValue(
              mockNotificationService,
            ),
            sharedPreferencesProvider.overrideWithValue(
              await SharedPreferences.getInstance(),
            ),
          ],
        );
        addTearDown(container.dispose);

        // Push enabled BEFORE activation — under the OLD fireImmediately this
        // would have synced synchronously during activation.
        await container
            .read(settingsProvider.notifier)
            .setPushNotificationsEnabled(true);

        container.read(appBootstrapProvider);
        await Future<void>.delayed(Duration.zero);

        verifyNever(() => mockNotificationService.initialize());
      },
    );

    // #635: the deferred initial kick must preserve the exact old behaviour —
    // a push-enabled returning user STILL gets initialize() (the sync isn't
    // lost, only later), and a disabled fresh user is a no-op with NO
    // removeToken() on initial boot.
    test(
      'kickInitialNotificationSync syncs a push-enabled user (no regression, #635)',
      () async {
        final container = ProviderContainer(
          overrides: [
            notificationServiceProvider.overrideWithValue(
              mockNotificationService,
            ),
            sharedPreferencesProvider.overrideWithValue(
              await SharedPreferences.getInstance(),
            ),
          ],
        );
        addTearDown(container.dispose);

        await container
            .read(settingsProvider.notifier)
            .setPushNotificationsEnabled(true);
        container.read(appBootstrapProvider);
        await Future<void>.delayed(Duration.zero);
        // Activation alone did nothing (deferred).
        verifyNever(() => mockNotificationService.initialize());

        // Simulate the post-first-frame kick.
        runInitialNotificationSync(
          container.read(settingsProvider),
          () => container.read(notificationServiceProvider),
        );
        await Future<void>.delayed(Duration.zero);

        verify(
          () => mockNotificationService.initialize(handleInitialMessage: true),
        ).called(1);
      },
    );

    test(
      'kickInitialNotificationSync can skip initial notification routing only',
      () async {
        final container = ProviderContainer(
          overrides: [
            notificationServiceProvider.overrideWithValue(
              mockNotificationService,
            ),
            sharedPreferencesProvider.overrideWithValue(
              await SharedPreferences.getInstance(),
            ),
          ],
        );
        addTearDown(container.dispose);

        await container
            .read(settingsProvider.notifier)
            .setPushNotificationsEnabled(true);

        runInitialNotificationSync(
          container.read(settingsProvider),
          () => container.read(notificationServiceProvider),
          handleInitialMessage: false,
        );
        await Future<void>.delayed(Duration.zero);

        verify(
          () => mockNotificationService.initialize(handleInitialMessage: false),
        ).called(1);
      },
    );

    test(
      'kickInitialNotificationSync is a no-op for a disabled user — no removeToken (#635)',
      () async {
        final container = ProviderContainer(
          overrides: [
            notificationServiceProvider.overrideWithValue(
              mockNotificationService,
            ),
            sharedPreferencesProvider.overrideWithValue(
              await SharedPreferences.getInstance(),
            ),
          ],
        );
        addTearDown(container.dispose);

        // Fresh user: push disabled (the default).
        container.read(appBootstrapProvider);

        runInitialNotificationSync(
          container.read(settingsProvider),
          () => container.read(notificationServiceProvider),
        );
        await Future<void>.delayed(Duration.zero);

        verifyNever(() => mockNotificationService.initialize());
        verifyNever(
          () => mockNotificationService.removeToken(
            handleInitialMessage: any(named: 'handleInitialMessage'),
          ),
        );
      },
    );

    test(
      'kickInitialNotificationSync reconciles an explicitly disabled user (#1096)',
      () async {
        runInitialNotificationSync(
          const AppSettings(pushNotificationsEnabled: false),
          () => mockNotificationService,
          hasPersistedPushPreference: true,
        );
        await Future<void>.delayed(Duration.zero);

        verify(
          () => mockNotificationService.removeToken(handleInitialMessage: true),
        ).called(1);
        verifyNever(
          () => mockNotificationService.initialize(
            handleInitialMessage: any(named: 'handleInitialMessage'),
          ),
        );
      },
    );

    test(
      'disabled cold-start forwards invite arbitration to removeToken (#1104)',
      () async {
        runInitialNotificationSync(
          const AppSettings(pushNotificationsEnabled: false),
          () => mockNotificationService,
          hasPersistedPushPreference: true,
          handleInitialMessage: false,
        );
        await Future<void>.delayed(Duration.zero);

        verify(
          () =>
              mockNotificationService.removeToken(handleInitialMessage: false),
        ).called(1);
        verifyNever(
          () => mockNotificationService.initialize(
            handleInitialMessage: any(named: 'handleInitialMessage'),
          ),
        );
      },
    );

    test(
      'calls removeToken() when pushNotificationsEnabled is toggled off',
      () async {
        final container = ProviderContainer(
          overrides: [
            notificationServiceProvider.overrideWithValue(
              mockNotificationService,
            ),
            sharedPreferencesProvider.overrideWithValue(
              await SharedPreferences.getInstance(),
            ),
          ],
        );
        addTearDown(container.dispose);

        // Start with push enabled
        await container
            .read(settingsProvider.notifier)
            .setPushNotificationsEnabled(true);

        // Activate bootstrap
        container.read(appBootstrapProvider);
        await Future<void>.delayed(Duration.zero);

        // Reset call tracking
        reset(mockNotificationService);
        when(
          () => mockNotificationService.removeToken(handleInitialMessage: true),
        ).thenAnswer((_) async {});

        // Toggle off
        await container
            .read(settingsProvider.notifier)
            .setPushNotificationsEnabled(false);
        await Future<void>.delayed(Duration.zero);

        verify(
          () => mockNotificationService.removeToken(handleInitialMessage: true),
        ).called(1);
      },
    );

    test(
      'does NOT reset pushNotificationsEnabled when initialize() fails (#470)',
      () async {
        final container = ProviderContainer(
          overrides: [
            notificationServiceProvider.overrideWithValue(
              mockNotificationService,
            ),
            sharedPreferencesProvider.overrideWithValue(
              await SharedPreferences.getInstance(),
            ),
          ],
        );
        addTearDown(container.dispose);

        // OS permission denied → initialize() returns false.
        when(
          () => mockNotificationService.initialize(
            handleInitialMessage: any(named: 'handleInitialMessage'),
          ),
        ).thenAnswer((_) async => false);

        // User explicitly opted in.
        await container
            .read(settingsProvider.notifier)
            .setPushNotificationsEnabled(true);

        container.read(appBootstrapProvider);

        // Drain the async syncNotifications() chain (initialize → would-reset).
        for (var i = 0; i < 5; i++) {
          await Future<void>.delayed(Duration.zero);
        }

        // Intent must survive: OS reality is reflected by
        // notificationStatusProvider, never by mutating the persisted pref.
        expect(
          container.read(settingsProvider).pushNotificationsEnabled,
          isTrue,
        );
      },
    );

    test(
      'does not call removeToken() when notifications are already off on activation',
      () async {
        final container = ProviderContainer(
          overrides: [
            notificationServiceProvider.overrideWithValue(
              mockNotificationService,
            ),
            sharedPreferencesProvider.overrideWithValue(
              await SharedPreferences.getInstance(),
            ),
          ],
        );
        addTearDown(container.dispose);

        container.read(appBootstrapProvider);
        await Future<void>.delayed(Duration.zero);

        verifyNever(
          () => mockNotificationService.removeToken(
            handleInitialMessage: any(named: 'handleInitialMessage'),
          ),
        );
      },
    );

    test(
      'main.dart defers appBootstrapProvider activation to the coordinator',
      () {
        final main = File('lib/main.dart').readAsStringSync();

        expect(main, contains('runColdStartCoordinator'));
        expect(main, isNot(contains('ref.watch(appBootstrapProvider)')));
      },
    );
  });

  // #480: an in-place anon→durable link (Settings "Link Google", home backup
  // nudge, create-screen account link, or email-link completion) keeps the SAME
  // uid, so the pref-listener (pushNotificationsEnabled unchanged) never
  // re-fires and no restart re-runs bootstrap. Bootstrap must re-register on
  // the link transition so a push-enabled user refreshes the existing
  // owner-keyed fcm_tokens doc with the durable credential state.
  group('appBootstrapProvider anon→durable token re-save (#480)', () {
    Future<ProviderContainer> makeContainer(
      StreamController<User?> authChanges, {
      required bool pushEnabled,
    }) async {
      final container = ProviderContainer(
        overrides: [
          notificationServiceProvider.overrideWithValue(
            mockNotificationService,
          ),
          sharedPreferencesProvider.overrideWithValue(
            await SharedPreferences.getInstance(),
          ),
          authUserChangesProvider.overrideWith((ref) => authChanges.stream),
        ],
      );
      addTearDown(container.dispose);
      if (pushEnabled) {
        await container
            .read(settingsProvider.notifier)
            .setPushNotificationsEnabled(true);
      }
      container.read(appBootstrapProvider);
      await Future<void>.delayed(Duration.zero);
      return container;
    }

    test(
      're-calls initialize() on in-place anon→durable link when push is on',
      () async {
        final authChanges = StreamController<User?>();
        addTearDown(authChanges.close);
        await makeContainer(authChanges, pushEnabled: true);

        // Establish the anon baseline, then ignore the boot-time initialize().
        authChanges.add(MockUser(uid: 'u1', isAnonymous: true));
        await Future<void>.delayed(Duration.zero);
        clearInteractions(mockNotificationService);

        // Same uid, now durable = an in-place linkWithCredential.
        authChanges.add(MockUser(uid: 'u1', isAnonymous: false));
        await Future<void>.delayed(Duration.zero);

        verify(
          () => mockNotificationService.initialize(
            handleInitialMessage: any(named: 'handleInitialMessage'),
          ),
        ).called(1);
      },
    );

    test('does NOT re-register when push is off', () async {
      final authChanges = StreamController<User?>();
      addTearDown(authChanges.close);
      await makeContainer(authChanges, pushEnabled: false);

      authChanges.add(MockUser(uid: 'u1', isAnonymous: true));
      await Future<void>.delayed(Duration.zero);
      clearInteractions(mockNotificationService);

      authChanges.add(MockUser(uid: 'u1', isAnonymous: false));
      await Future<void>.delayed(Duration.zero);

      verifyNever(() => mockNotificationService.initialize());
    });

    test(
      'does NOT re-register on a uid SWAP (recovery already restarts)',
      () async {
        final authChanges = StreamController<User?>();
        addTearDown(authChanges.close);
        await makeContainer(authChanges, pushEnabled: true);

        authChanges.add(MockUser(uid: 'anon-uid', isAnonymous: true));
        await Future<void>.delayed(Duration.zero);
        clearInteractions(mockNotificationService);

        // Different uid + durable = a sign-out/sign-in swap, not an in-place
        // link; that path restarts the app and re-runs bootstrap on its own.
        authChanges.add(MockUser(uid: 'durable-uid', isAnonymous: false));
        await Future<void>.delayed(Duration.zero);

        verifyNever(() => mockNotificationService.initialize());
      },
    );
  });

  // #483: the server localizes push copy from fcm_tokens/{uid}.locale, which is
  // frozen at token-write time. A language switch updates prefs + state but
  // never re-saved the token, so an EN→AR user kept getting English pushes until
  // a random FCM rotation. Bootstrap must re-save the token locale on a language
  // change — but only for a push-enabled user (the service no-ops otherwise).
  group('appBootstrapProvider language-change token re-save (#483)', () {
    Future<ProviderContainer> makeContainer({required bool pushEnabled}) async {
      final container = ProviderContainer(
        overrides: [
          notificationServiceProvider.overrideWithValue(
            mockNotificationService,
          ),
          sharedPreferencesProvider.overrideWithValue(
            await SharedPreferences.getInstance(),
          ),
          // Pin the boot language to 'en' so the EN→AR change is deterministic.
          deviceLocalesProvider.overrideWithValue(const [Locale('en')]),
        ],
      );
      addTearDown(container.dispose);
      if (pushEnabled) {
        await container
            .read(settingsProvider.notifier)
            .setPushNotificationsEnabled(true);
      }
      container.read(appBootstrapProvider);
      await Future<void>.delayed(Duration.zero);
      return container;
    }

    test(
      're-saves the token locale on a language change when push is on',
      () async {
        final container = await makeContainer(pushEnabled: true);
        clearInteractions(mockNotificationService);

        await container.read(settingsProvider.notifier).setLanguage('ar');
        await Future<void>.delayed(Duration.zero);

        verify(() => mockNotificationService.refreshTokenLocale()).called(1);
      },
    );

    test('does NOT re-save the token locale when push is off', () async {
      final container = await makeContainer(pushEnabled: false);
      clearInteractions(mockNotificationService);

      await container.read(settingsProvider.notifier).setLanguage('ar');
      await Future<void>.delayed(Duration.zero);

      verifyNever(() => mockNotificationService.refreshTokenLocale());
    });
  });
}
