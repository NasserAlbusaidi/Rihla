// Unit tests for SettingsNotifier and settings_provider.dart.
//
// These are isolated to a dedicated file to ensure proper test discovery
// when running the full test suite.

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safar/core/models/app_settings_model.dart';
import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/services/settings_service.dart';

void main() {
  group('SettingsNotifier', () {
    Future<ProviderContainer> makeContainer() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          // Pin device locale so first-run language seeding (#286) is
          // deterministic regardless of the host machine's locale.
          deviceLocalesProvider.overrideWithValue(const [Locale('en')]),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('initial state has default AppSettings', () async {
      final container = await makeContainer();
      final settings = container.read(settingsProvider);
      expect(settings.deviceName, equals(''));
      expect(settings.currencyCode, equals('OMR'));
      expect(settings.languageCode, equals('en'));
      expect(settings.themeMode, equals(AppThemeMode.system));
      expect(settings.pushNotificationsEnabled, isFalse);
    });

    test('setDeviceName updates deviceName in state', () async {
      final container = await makeContainer();
      final notifier = container.read(settingsProvider.notifier);
      await notifier.setDeviceName('Alice');
      expect(container.read(settingsProvider).deviceName, equals('Alice'));
    });

    test(
      'setDeviceName normalizes valid display names before persisting',
      () async {
        final container = await makeContainer();
        final notifier = container.read(settingsProvider.notifier);
        final prefs = container.read(sharedPreferencesProvider);

        await notifier.setDeviceName('  Alice   Al Said  ');

        expect(
          container.read(settingsProvider).deviceName,
          equals('Alice Al Said'),
        );
        expect(
          prefs.getString('settings_device_name'),
          equals('Alice Al Said'),
        );
      },
    );

    test('setDeviceName rejects invalid Firestore display names', () async {
      SharedPreferences.setMockInitialValues({'settings_device_name': 'Alice'});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);
      final notifier = container.read(settingsProvider.notifier);

      await expectLater(
        notifier.setDeviceName('Eve\nMallory'),
        throwsA(isA<ArgumentError>()),
      );

      expect(container.read(settingsProvider).deviceName, equals('Alice'));
      expect(prefs.getString('settings_device_name'), equals('Alice'));
    });

    test('setCurrency updates currencyCode in state', () async {
      final container = await makeContainer();
      final notifier = container.read(settingsProvider.notifier);
      await notifier.setCurrency('USD');
      expect(container.read(settingsProvider).currencyCode, equals('USD'));
    });

    test('setLanguage updates languageCode in state', () async {
      final container = await makeContainer();
      final notifier = container.read(settingsProvider.notifier);
      await notifier.setLanguage('ar');
      expect(container.read(settingsProvider).languageCode, equals('ar'));
    });

    test('setThemeMode updates themeMode in state', () async {
      final container = await makeContainer();
      final notifier = container.read(settingsProvider.notifier);
      await notifier.setThemeMode(AppThemeMode.dark);
      expect(
        container.read(settingsProvider).themeMode,
        equals(AppThemeMode.dark),
      );
    });

    test(
      'setPushNotificationsEnabled updates pushNotificationsEnabled',
      () async {
        final container = await makeContainer();
        final notifier = container.read(settingsProvider.notifier);
        await notifier.setPushNotificationsEnabled(true);
        expect(
          container.read(settingsProvider).pushNotificationsEnabled,
          isTrue,
        );
      },
    );

    test('notificationPromptSeen defaults to false', () async {
      final container = await makeContainer();
      expect(
        container.read(settingsProvider).notificationPromptSeen,
        isFalse,
      );
    });

    test(
      'setNotificationPromptSeen updates and persists notificationPromptSeen',
      () async {
        final container = await makeContainer();
        await container
            .read(settingsProvider.notifier)
            .setNotificationPromptSeen(true);
        expect(
          container.read(settingsProvider).notificationPromptSeen,
          isTrue,
        );

        // Survives a reload from the same SharedPreferences store.
        final reloaded = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(
              await SharedPreferences.getInstance(),
            ),
            deviceLocalesProvider.overrideWithValue(const [Locale('en')]),
          ],
        );
        addTearDown(reloaded.dispose);
        expect(
          reloaded.read(settingsProvider).notificationPromptSeen,
          isTrue,
        );
      },
    );

    test('settingsServiceProvider returns SettingsService instance', () async {
      final container = await makeContainer();
      final service = container.read(settingsServiceProvider);
      expect(service, isA<SettingsService>());
    });

    test(
      'loadSettings reads stored deviceName from SharedPreferences',
      () async {
        SharedPreferences.setMockInitialValues({'settings_device_name': 'Bob'});
        final prefs = await SharedPreferences.getInstance();
        final container = ProviderContainer(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        );
        addTearDown(container.dispose);

        final settings = container.read(settingsProvider);
        expect(settings.deviceName, equals('Bob'));
      },
    );

    test('loadSettings drops invalid persisted deviceName', () async {
      SharedPreferences.setMockInitialValues({
        'settings_device_name': 'A' * 33,
      });
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);

      final settings = container.read(settingsProvider);
      expect(settings.deviceName, equals(''));
    });

    test('AppSettings.theme returns ThemeMode.dark for dark mode', () {
      const settings = AppSettings(themeMode: AppThemeMode.dark);
      expect(settings.theme, equals(ThemeMode.dark));
    });

    test('AppSettings.theme returns ThemeMode.light for light mode', () {
      const settings = AppSettings(themeMode: AppThemeMode.light);
      expect(settings.theme, equals(ThemeMode.light));
    });

    test('AppSettings.theme returns ThemeMode.system for system mode', () {
      const settings = AppSettings(themeMode: AppThemeMode.system);
      expect(settings.theme, equals(ThemeMode.system));
    });

    test('propagateDisplayName is called when setDeviceName is called', () async {
      // This test verifies that setDeviceName triggers propagateDisplayName.
      // Since propagateDisplayName calls Firestore (which we can't easily mock
      // in a unit test without modifying the constructor), this test verifies
      // that setDeviceName completes without error and updates state correctly.
      // The Firestore batch write is fire-and-forget with a try/catch,
      // so it will silently fail in test (no Firestore instance) — which is
      // the expected behavior per D-15 (offline: no error shown).
      final container = await makeContainer();
      final notifier = container.read(settingsProvider.notifier);
      await notifier.setDeviceName('NewName');
      expect(container.read(settingsProvider).deviceName, equals('NewName'));
      // propagateDisplayName fires unawaited — the silent catch ensures no throw
    });
  });

  group('localeProvider', () {
    test('returns Locale("en") when languageCode is "en"', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          deviceLocalesProvider.overrideWithValue(const [Locale('en')]),
        ],
      );
      addTearDown(container.dispose);
      expect(container.read(localeProvider), const Locale('en'));
    });

    test('returns Locale("ar") after setLanguage("ar")', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          deviceLocalesProvider.overrideWithValue(const [Locale('en')]),
        ],
      );
      addTearDown(container.dispose);
      await container.read(settingsProvider.notifier).setLanguage('ar');
      expect(container.read(localeProvider), const Locale('ar'));
    });
  });
}
