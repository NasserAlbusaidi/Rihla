import 'package:flutter/material.dart';

enum AppThemeMode { light, dark, system }

class AppSettings {
  final AppThemeMode themeMode;
  final String languageCode;
  final String currencyCode;
  final bool pushNotificationsEnabled;

  const AppSettings({
    this.themeMode = AppThemeMode.system,
    this.languageCode = 'en',
    this.currencyCode = 'OMR',
    this.pushNotificationsEnabled = false,
  });

  factory AppSettings.defaultSettings() => const AppSettings();

  AppSettings copyWith({
    AppThemeMode? themeMode,
    String? languageCode,
    String? currencyCode,
    bool? pushNotificationsEnabled,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      languageCode: languageCode ?? this.languageCode,
      currencyCode: currencyCode ?? this.currencyCode,
      pushNotificationsEnabled:
          pushNotificationsEnabled ?? this.pushNotificationsEnabled,
    );
  }

  ThemeMode get theme => switch (themeMode) {
    AppThemeMode.light => ThemeMode.light,
    AppThemeMode.dark => ThemeMode.dark,
    AppThemeMode.system => ThemeMode.system,
  };
}
