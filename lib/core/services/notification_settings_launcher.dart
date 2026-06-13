import 'package:app_settings/app_settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens the OS notification-settings page for this app (#470).
///
/// Once OS notification permission has been denied, Android 13+ never re-shows
/// the system dialog, so the in-app toggle cannot re-request it. The only
/// recovery path is the OS settings page — this is the deep-link to it.
///
/// Injectable so the Settings toggle's denied → recover path can be asserted in
/// widget tests without hitting a platform channel.
typedef OpenNotificationSettings = Future<void> Function();

final openNotificationSettingsProvider = Provider<OpenNotificationSettings>(
  (ref) =>
      () => AppSettings.openAppSettings(type: AppSettingsType.notification),
);
