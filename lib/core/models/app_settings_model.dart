import 'package:flutter/material.dart';

enum AppThemeMode { light, dark, system }

class AppSettings {
  final AppThemeMode themeMode;
  final String languageCode;
  final String currencyCode;
  final bool pushNotificationsEnabled;
  final bool weeklyDigestEnabled;
  final String deviceName;
  final bool onboardingComplete;

  const AppSettings({
    this.themeMode = AppThemeMode.system,
    this.languageCode = 'en',
    this.currencyCode = 'OMR',
    this.pushNotificationsEnabled = false,
    this.weeklyDigestEnabled = false,
    this.deviceName = '',
    this.onboardingComplete = false,
  });

  factory AppSettings.defaultSettings() => const AppSettings();

  AppSettings copyWith({
    AppThemeMode? themeMode,
    String? languageCode,
    String? currencyCode,
    bool? pushNotificationsEnabled,
    bool? weeklyDigestEnabled,
    String? deviceName,
    bool? onboardingComplete,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      languageCode: languageCode ?? this.languageCode,
      currencyCode: currencyCode ?? this.currencyCode,
      pushNotificationsEnabled:
          pushNotificationsEnabled ?? this.pushNotificationsEnabled,
      weeklyDigestEnabled: weeklyDigestEnabled ?? this.weeklyDigestEnabled,
      deviceName: deviceName ?? this.deviceName,
      onboardingComplete: onboardingComplete ?? this.onboardingComplete,
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
