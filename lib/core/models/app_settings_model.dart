import 'package:flutter/material.dart';

enum AppThemeMode { light, dark, system }

class AppSettings {
  final AppThemeMode themeMode;
  final String languageCode;
  final String currencyCode;
  final bool pushNotificationsEnabled;
  final String deviceName;

  const AppSettings({
    this.themeMode = AppThemeMode.system,
    this.languageCode = 'en',
    this.currencyCode = 'OMR',
    this.pushNotificationsEnabled = false,
    this.deviceName = '',
  });

  factory AppSettings.defaultSettings() => const AppSettings();

  AppSettings copyWith({
    AppThemeMode? themeMode,
    String? languageCode,
    String? currencyCode,
    bool? pushNotificationsEnabled,
    String? deviceName,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      languageCode: languageCode ?? this.languageCode,
      currencyCode: currencyCode ?? this.currencyCode,
      pushNotificationsEnabled:
          pushNotificationsEnabled ?? this.pushNotificationsEnabled,
      deviceName: deviceName ?? this.deviceName,
    );
  }

  ThemeMode get theme => themeMode.toMaterialThemeMode();
}

/// Convert an [AppThemeMode] to Flutter's [ThemeMode] consumed by MaterialApp.
///
/// Preferred call site over [AppSettings.theme] when the caller only has the
/// enum value (e.g. reading via `ref.watch(settingsProvider.select((s) => s.themeMode))`).
extension AppThemeModeX on AppThemeMode {
  ThemeMode toMaterialThemeMode() => switch (this) {
    AppThemeMode.light => ThemeMode.light,
    AppThemeMode.dark => ThemeMode.dark,
    AppThemeMode.system => ThemeMode.system,
  };
}
