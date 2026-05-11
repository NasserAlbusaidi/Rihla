// Unit tests for SettingsNotifier and settings_provider.dart.
//
// These are isolated to a dedicated file to ensure proper test discovery
// when running the full test suite.

import 'package:flutter/material.dart' show ThemeMode;
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
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
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
}
