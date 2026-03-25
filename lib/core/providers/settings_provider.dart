import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_settings_model.dart';
import '../services/settings_service.dart';

/// Provider for SharedPreferences instance
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('SharedPreferences must be overridden in main()');
});

/// Provider for SettingsService
final settingsServiceProvider = Provider<SettingsService>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return SettingsService(prefs);
});

/// Notifier to manage global application settings
class SettingsNotifier extends StateNotifier<AppSettings> {
  final SettingsService _service;

  SettingsNotifier(this._service) : super(_service.loadSettings());

  Future<void> setThemeMode(AppThemeMode mode) async {
    await _service.saveThemeMode(mode);
    state = state.copyWith(themeMode: mode);
  }

  Future<void> setLanguage(String languageCode) async {
    await _service.saveLanguage(languageCode);
    state = state.copyWith(languageCode: languageCode);
  }

  Future<void> setCurrency(String currencyCode) async {
    await _service.saveCurrency(currencyCode);
    state = state.copyWith(currencyCode: currencyCode);
  }

  Future<void> setPushNotificationsEnabled(bool enabled) async {
    await _service.savePushNotificationsEnabled(enabled);
    state = state.copyWith(pushNotificationsEnabled: enabled);
  }

  Future<void> setDeviceName(String name) async {
    await _service.saveDeviceName(name);
    state = state.copyWith(deviceName: name);
  }
}

/// Provider for SettingsNotifier
final settingsProvider = StateNotifierProvider<SettingsNotifier, AppSettings>((
  ref,
) {
  final service = ref.watch(settingsServiceProvider);
  return SettingsNotifier(service);
});
