import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_settings_model.dart';
import '../models/split_mode.dart';

class SettingsService {
  static const String _themeKey = 'settings_theme';
  static const String _languageKey = 'settings_language';
  static const String _currencyKey = 'settings_currency';
  static const String _pushNotificationsKey = 'settings_push_notifications';
  static const String _weeklyDigestKey = 'settings_weekly_digest';
  static const String _deviceNameKey = 'settings_device_name';
  static const String _onboardingCompleteKey = 'settings_onboarding_complete';
  static const String _defaultSplitModeKey = 'settings_default_split_mode';

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
    final weeklyDigestEnabled = _prefs.getBool(_weeklyDigestKey) ?? false;
    final deviceName = _prefs.getString(_deviceNameKey) ?? '';
    final onboardingComplete =
        _prefs.getBool(_onboardingCompleteKey) ?? false;
    final defaultSplitMode =
        splitModeFromStorage(_prefs.getString(_defaultSplitModeKey));

    return AppSettings(
      themeMode: themeMode,
      languageCode: languageCode,
      currencyCode: currencyCode,
      pushNotificationsEnabled: pushNotificationsEnabled,
      weeklyDigestEnabled: weeklyDigestEnabled,
      deviceName: deviceName,
      onboardingComplete: onboardingComplete,
      defaultSplitMode: defaultSplitMode,
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

  Future<void> saveWeeklyDigestEnabled(bool enabled) async {
    await _prefs.setBool(_weeklyDigestKey, enabled);
  }

  Future<void> saveDeviceName(String name) async {
    await _prefs.setString(_deviceNameKey, name);
  }

  Future<void> saveOnboardingComplete(bool complete) async {
    await _prefs.setBool(_onboardingCompleteKey, complete);
  }

  Future<void> saveDefaultSplitMode(SplitMode mode) async {
    await _prefs.setString(_defaultSplitModeKey, mode.storageKey);
  }
}
