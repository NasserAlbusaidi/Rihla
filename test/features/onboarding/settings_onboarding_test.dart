import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/services/settings_service.dart';

void main() {
  Future<ProviderContainer> makeContainer([Map<String, Object> seed = const {}]) async {
    SharedPreferences.setMockInitialValues(seed);
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('SettingsNotifier — onboarding flag', () {
    test('defaults to false when no value is stored', () async {
      final container = await makeContainer();
      expect(
        container.read(settingsProvider).onboardingComplete,
        isFalse,
      );
    });

    test('reads stored true from SharedPreferences', () async {
      final container = await makeContainer(const {
        'settings_onboarding_complete': true,
      });
      expect(
        container.read(settingsProvider).onboardingComplete,
        isTrue,
      );
    });

    test('setOnboardingComplete persists flag and updates state', () async {
      final container = await makeContainer();
      final notifier = container.read(settingsProvider.notifier);

      expect(container.read(settingsProvider).onboardingComplete, isFalse);

      await notifier.setOnboardingComplete(true);

      expect(container.read(settingsProvider).onboardingComplete, isTrue);

      // Persistence check — a fresh service over the same SharedPreferences
      // should read back the new value.
      final prefs = await SharedPreferences.getInstance();
      final freshService = SettingsService(prefs);
      expect(freshService.loadSettings().onboardingComplete, isTrue);
    });

    test('setOnboardingComplete can flip back to false', () async {
      final container = await makeContainer(const {
        'settings_onboarding_complete': true,
      });
      final notifier = container.read(settingsProvider.notifier);
      await notifier.setOnboardingComplete(false);
      expect(container.read(settingsProvider).onboardingComplete, isFalse);
    });
  });

  group('SettingsNotifier — weekly digest', () {
    test('defaults to false when no value is stored', () async {
      final container = await makeContainer();
      expect(
        container.read(settingsProvider).weeklyDigestEnabled,
        isFalse,
      );
    });

    test('setWeeklyDigestEnabled persists flag and updates state', () async {
      final container = await makeContainer();
      final notifier = container.read(settingsProvider.notifier);
      await notifier.setWeeklyDigestEnabled(true);

      expect(container.read(settingsProvider).weeklyDigestEnabled, isTrue);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('settings_weekly_digest'), isTrue);
    });
  });
}
