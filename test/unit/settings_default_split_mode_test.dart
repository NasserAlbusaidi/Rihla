import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/models/app_settings_model.dart';
import 'package:safar/core/models/split_mode.dart';
import 'package:safar/core/services/settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('SettingsService — defaultSplitMode round-trip', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('defaults to SplitMode.equally when nothing is persisted', () async {
      final prefs = await SharedPreferences.getInstance();
      final service = SettingsService(prefs);

      final settings = service.loadSettings();

      expect(settings.defaultSplitMode, SplitMode.equally);
    });

    test('persists and reloads a chosen split mode', () async {
      final prefs = await SharedPreferences.getInstance();
      final service = SettingsService(prefs);

      await service.saveDefaultSplitMode(SplitMode.shares);
      final reloaded = service.loadSettings();

      expect(reloaded.defaultSplitMode, SplitMode.shares);
    });

    test('falls back to equally for unknown stored values', () async {
      SharedPreferences.setMockInitialValues({
        'settings_default_split_mode': 'bogus-value',
      });
      final prefs = await SharedPreferences.getInstance();
      final service = SettingsService(prefs);

      expect(service.loadSettings().defaultSplitMode, SplitMode.equally);
    });
  });

  group('SplitModeX', () {
    test('storageKey is stable for every variant', () {
      expect(SplitMode.equally.storageKey, 'equally');
      expect(SplitMode.shares.storageKey, 'shares');
      expect(SplitMode.exact.storageKey, 'exact');
      expect(SplitMode.percent.storageKey, 'percent');
    });

    test('all modes are available after T4.N', () {
      for (final mode in SplitMode.values) {
        expect(mode.isAvailable, isTrue, reason: '$mode should be available');
      }
    });

    test('copyWith preserves defaultSplitMode when not overridden', () {
      const base = AppSettings(defaultSplitMode: SplitMode.shares);
      final copy = base.copyWith(currencyCode: 'AED');

      expect(copy.defaultSplitMode, SplitMode.shares);
      expect(copy.currencyCode, 'AED');
    });
  });
}
