import 'package:flutter/material.dart';

import 'split_mode.dart';

enum AppThemeMode { light, dark, system }

class AppSettings {
  final AppThemeMode themeMode;
  final String languageCode;
  final String currencyCode;
  final bool pushNotificationsEnabled;

  /// True once we've proactively shown the OS notification-permission prompt at
  /// a natural moment (first group join/create). Gates that prompt to fire
  /// exactly once so a default-off [pushNotificationsEnabled] no longer hides
  /// the system dialog forever (#288).
  final bool notificationPromptSeen;

  /// True once the user has dismissed (or acted on) the one-time home nudge to
  /// back up their anonymous account by linking an email. Gates that nudge to
  /// appear at most once so it stays a non-blocking prompt, never a nag (#285).
  final bool emailLinkNudgeSeen;
  final bool weeklyDigestEnabled;
  final String deviceName;
  final bool onboardingComplete;
  final SplitMode defaultSplitMode;

  const AppSettings({
    this.themeMode = AppThemeMode.system,
    this.languageCode = 'en',
    this.currencyCode = 'OMR',
    this.pushNotificationsEnabled = false,
    this.notificationPromptSeen = false,
    this.emailLinkNudgeSeen = false,
    this.weeklyDigestEnabled = false,
    this.deviceName = '',
    this.onboardingComplete = false,
    this.defaultSplitMode = SplitMode.equally,
  });

  factory AppSettings.defaultSettings() => const AppSettings();

  AppSettings copyWith({
    AppThemeMode? themeMode,
    String? languageCode,
    String? currencyCode,
    bool? pushNotificationsEnabled,
    bool? notificationPromptSeen,
    bool? emailLinkNudgeSeen,
    bool? weeklyDigestEnabled,
    String? deviceName,
    bool? onboardingComplete,
    SplitMode? defaultSplitMode,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      languageCode: languageCode ?? this.languageCode,
      currencyCode: currencyCode ?? this.currencyCode,
      pushNotificationsEnabled:
          pushNotificationsEnabled ?? this.pushNotificationsEnabled,
      notificationPromptSeen:
          notificationPromptSeen ?? this.notificationPromptSeen,
      emailLinkNudgeSeen: emailLinkNudgeSeen ?? this.emailLinkNudgeSeen,
      weeklyDigestEnabled: weeklyDigestEnabled ?? this.weeklyDigestEnabled,
      deviceName: deviceName ?? this.deviceName,
      onboardingComplete: onboardingComplete ?? this.onboardingComplete,
      defaultSplitMode: defaultSplitMode ?? this.defaultSplitMode,
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
