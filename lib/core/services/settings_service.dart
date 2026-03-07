import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_settings_model.dart';

class SettingsService {
  static const String _themeKey = 'settings_theme';
  static const String _languageKey = 'settings_language';
  static const String _currencyKey = 'settings_currency';
  static const String _pushNotificationsKey = 'settings_push_notifications';
  static const String _deviceNameKey = 'settings_device_name';

  final SharedPreferences _prefs;

  SettingsService(this._prefs);

  /// Load settings from SharedPreferences
  AppSettings loadSettings() {
    final themeIndex = _prefs.getInt(_themeKey) ?? AppThemeMode.system.index;
    final themeMode = themeIndex >= 0 && themeIndex < AppThemeMode.values.length
        ? AppThemeMode.values[themeIndex]
        : AppThemeMode.system;

    final languageCode = _prefs.getString(_languageKey) ?? 'en';
    final currencyCode = _prefs.getString(_currencyKey) ?? 'OMR';
    final pushNotificationsEnabled =
        _prefs.getBool(_pushNotificationsKey) ?? false;
    final deviceName = _prefs.getString(_deviceNameKey) ?? '';

    return AppSettings(
      themeMode: themeMode,
      languageCode: languageCode,
      currencyCode: currencyCode,
      pushNotificationsEnabled: pushNotificationsEnabled,
      deviceName: deviceName,
    );
  }

  /// Save settings to SharedPreferences
  Future<void> saveThemeMode(AppThemeMode mode) async {
    await _prefs.setInt(_themeKey, mode.index);
  }

  Future<void> saveLanguage(String languageCode) async {
    await _prefs.setString(_languageKey, languageCode);
  }

  Future<void> saveCurrency(String currencyCode) async {
    await _prefs.setString(_currencyKey, currencyCode);
  }

  Future<void> savePushNotificationsEnabled(bool enabled) async {
    await _prefs.setBool(_pushNotificationsKey, enabled);
  }

  Future<void> saveDeviceName(String name) async {
    await _prefs.setString(_deviceNameKey, name);
  }
}
