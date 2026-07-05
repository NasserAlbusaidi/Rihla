import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:safar/core/models/app_settings_model.dart';
import 'package:safar/core/services/settings_service.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('AppThemeMode.toMaterialThemeMode()', () {
    test('light → ThemeMode.light', () {
      expect(AppThemeMode.light.toMaterialThemeMode(), ThemeMode.light);
    });
    test('dark → ThemeMode.dark', () {
      expect(AppThemeMode.dark.toMaterialThemeMode(), ThemeMode.dark);
    });
    test('system → ThemeMode.system', () {
      expect(AppThemeMode.system.toMaterialThemeMode(), ThemeMode.system);
    });
  });

  group('AppSettings.theme getter (mapping parity)', () {
    test('light', () {
      expect(const AppSettings(themeMode: AppThemeMode.light).theme,
          ThemeMode.light);
    });
    test('dark', () {
      expect(const AppSettings(themeMode: AppThemeMode.dark).theme,
          ThemeMode.dark);
    });
    test('system', () {
      expect(const AppSettings(themeMode: AppThemeMode.system).theme,
          ThemeMode.system);
    });
  });

  group('SettingsService theme persistence round-trip', () {
    test('save dark, reload returns dark', () async {
      final prefs = await SharedPreferences.getInstance();
      final svc = SettingsService(prefs);
      await svc.saveThemeMode(AppThemeMode.dark);
      expect(svc.loadSettings().themeMode, AppThemeMode.dark);
    });
    test('save light, reload returns light', () async {
      final prefs = await SharedPreferences.getInstance();
      final svc = SettingsService(prefs);
      await svc.saveThemeMode(AppThemeMode.light);
      expect(svc.loadSettings().themeMode, AppThemeMode.light);
    });
    test('default when unset is system (D5a reverted, #900)', () async {
      final prefs = await SharedPreferences.getInstance();
      final svc = SettingsService(prefs);
      expect(svc.loadSettings().themeMode, AppThemeMode.system);
    });
  });
}
