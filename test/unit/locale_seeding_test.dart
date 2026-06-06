// #286 — on first run the app should default to the device's system locale
// (Arabic phone -> Arabic app), then honor any stored override the user picked.

import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safar/core/providers/settings_provider.dart';

void main() {
  group('resolveSupportedLanguageCode', () {
    const supported = [Locale('ar'), Locale('en')];

    test('returns the first supported device language', () {
      expect(
        resolveSupportedLanguageCode(const [Locale('ar')], supported),
        'ar',
      );
    });

    test('skips unsupported locales and picks the next supported one', () {
      expect(
        resolveSupportedLanguageCode(
          const [Locale('fr'), Locale('ar')],
          supported,
        ),
        'ar',
      );
    });

    test('ignores the region subtag when matching', () {
      expect(
        resolveSupportedLanguageCode(const [Locale('ar', 'OM')], supported),
        'ar',
      );
    });

    test('returns null when no device locale is supported', () {
      expect(
        resolveSupportedLanguageCode(const [Locale('fr')], supported),
        isNull,
      );
    });

    test('returns null for an empty device locale list', () {
      expect(resolveSupportedLanguageCode(const [], supported), isNull);
    });
  });

  group('first-run locale seeding', () {
    Future<ProviderContainer> container({
      required List<Locale> deviceLocales,
      Map<String, Object> prefs = const {},
    }) async {
      SharedPreferences.setMockInitialValues(prefs);
      final sp = await SharedPreferences.getInstance();
      final c = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(sp),
          deviceLocalesProvider.overrideWithValue(deviceLocales),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('Arabic device with no stored choice boots Arabic', () async {
      final c = await container(deviceLocales: const [Locale('ar')]);
      expect(c.read(settingsProvider).languageCode, 'ar');
      expect(c.read(localeProvider), const Locale('ar'));
    });

    test('stored language overrides the device locale', () async {
      final c = await container(
        deviceLocales: const [Locale('ar')],
        prefs: const {'settings_language': 'en'},
      );
      expect(c.read(settingsProvider).languageCode, 'en');
      expect(c.read(localeProvider), const Locale('en'));
    });

    test('unsupported device locale falls back to English', () async {
      final c = await container(deviceLocales: const [Locale('fr')]);
      expect(c.read(settingsProvider).languageCode, 'en');
    });

    test('English device with no stored choice boots English', () async {
      final c = await container(deviceLocales: const [Locale('en')]);
      expect(c.read(settingsProvider).languageCode, 'en');
    });
  });
}
