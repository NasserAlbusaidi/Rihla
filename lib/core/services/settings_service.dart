import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_settings_model.dart';
import '../models/split_mode.dart';
import '../utils/name_validators.dart';

class SettingsService {
  static const String _themeKey = 'settings_theme';
  static const String languageKey = 'settings_language';
  static const String _currencyKey = 'settings_currency';
  static const String _pushNotificationsKey = 'settings_push_notifications';
  static const String _notificationPromptSeenKey =
      'settings_notification_prompt_seen';
  static const String _emailLinkNudgeSeenKey =
      'settings_email_link_nudge_seen';
  static const String _currencyExplainerSeenKey =
      'settings_currency_explainer_seen';
  static const String _weeklyDigestKey = 'settings_weekly_digest';
  static const String _deviceNameKey = 'settings_device_name';
  static const String _onboardingCompleteKey = 'settings_onboarding_complete';
  static const String _defaultSplitModeKey = 'settings_default_split_mode';

  final SharedPreferences _prefs;

  SettingsService(this._prefs);

  /// Load settings from SharedPreferences.
  ///
  /// [deviceLanguageCode] seeds the language on first run (when the user has
  /// never made an explicit choice) so an Arabic phone boots Arabic (#286). A
  /// stored choice always wins; an absent device hint falls back to English.
  AppSettings loadSettings({String? deviceLanguageCode}) {
    // D5a reverted (#900): the dark pass shipped (DESIGN.md §13 D5), so an
    // unset/corrupt stored value falls back to system again.
    final themeIndex = _prefs.getInt(_themeKey) ?? AppThemeMode.system.index;
    final themeMode = themeIndex >= 0 && themeIndex < AppThemeMode.values.length
        ? AppThemeMode.values[themeIndex]
        : AppThemeMode.system;

    final languageCode =
        _prefs.getString(languageKey) ?? deviceLanguageCode ?? 'en';
    final currencyCode = _prefs.getString(_currencyKey) ?? 'OMR';
    final pushNotificationsEnabled =
        _prefs.getBool(_pushNotificationsKey) ?? false;
    final notificationPromptSeen =
        _prefs.getBool(_notificationPromptSeenKey) ?? false;
    final emailLinkNudgeSeen =
        _prefs.getBool(_emailLinkNudgeSeenKey) ?? false;
    final currencyExplainerSeen =
        _prefs.getBool(_currencyExplainerSeenKey) ?? false;
    final weeklyDigestEnabled = _prefs.getBool(_weeklyDigestKey) ?? false;
    final rawDeviceName = _prefs.getString(_deviceNameKey) ?? '';
    final deviceName = _sanitizePersistedDeviceName(rawDeviceName);
    final onboardingComplete = _prefs.getBool(_onboardingCompleteKey) ?? false;
    final defaultSplitMode = splitModeFromStorage(
      _prefs.getString(_defaultSplitModeKey),
    );

    return AppSettings(
      themeMode: themeMode,
      languageCode: languageCode,
      currencyCode: currencyCode,
      pushNotificationsEnabled: pushNotificationsEnabled,
      notificationPromptSeen: notificationPromptSeen,
      emailLinkNudgeSeen: emailLinkNudgeSeen,
      currencyExplainerSeen: currencyExplainerSeen,
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
    await _prefs.setString(languageKey, languageCode);
  }

  Future<void> saveCurrency(String currencyCode) async {
    await _prefs.setString(_currencyKey, currencyCode);
  }

  Future<void> savePushNotificationsEnabled(bool enabled) async {
    await _prefs.setBool(_pushNotificationsKey, enabled);
  }

  Future<void> saveNotificationPromptSeen(bool seen) async {
    await _prefs.setBool(_notificationPromptSeenKey, seen);
  }

  Future<void> saveEmailLinkNudgeSeen(bool seen) async {
    await _prefs.setBool(_emailLinkNudgeSeenKey, seen);
  }

  Future<void> saveCurrencyExplainerSeen(bool seen) async {
    await _prefs.setBool(_currencyExplainerSeenKey, seen);
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

  String _sanitizePersistedDeviceName(String value) {
    if (value.trim().isEmpty) return '';
    return validateDisplayName(value) == null
        ? normalizeDisplayName(value)
        : '';
  }
}
