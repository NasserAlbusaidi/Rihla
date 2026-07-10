import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Seam over `flutter_local_notifications` so [NotificationService] stays
/// unit-testable — the platform plugin (and its channel wiring) lives ONLY in
/// [FlutterLocalNotifier]; tests inject a fake implementation (#53).
abstract interface class LocalNotifier {
  /// Initializes the plugin and the Android channel. [onTap] receives the
  /// notification's `payload` string when the user taps a displayed local
  /// notification.
  Future<void> initialize(void Function(String? payload) onTap);

  Future<void> clearAll();

  /// Displays a heads-up local notification carrying [payload] for tap routing.
  Future<void> show({
    required int id,
    required String title,
    required String body,
    required String payload,
  });
}

/// Production [LocalNotifier] backed by `flutter_local_notifications`.
class FlutterLocalNotifier implements LocalNotifier {
  FlutterLocalNotifier([FlutterLocalNotificationsPlugin? plugin])
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  /// MUST match the AndroidManifest `default_notification_channel_id` meta-data
  /// so OS-displayed (backgrounded) notifications and our foreground ones share
  /// one channel.
  static const channelId = 'rihla_activity';
  static const channelName = 'Activity';
  static const _channelDescription = 'Settlements and group activity';

  /// Branded small-icon drawable (#484). A status-bar icon is masked by its
  /// alpha and tinted, so a full-colour launcher renders as a white square —
  /// `ic_launcher_monochrome` is the white-on-transparent brand silhouette
  /// (`res/drawable-*`), the same mark the backgrounded FCM path uses via the
  /// `default_notification_icon` manifest meta-data. Bare name: the plugin
  /// resolves it in the `drawable` resource type.
  static const _smallIcon = 'ic_launcher_monochrome';

  bool _initialized = false;

  @override
  Future<void> initialize(void Function(String? payload) onTap) async {
    if (_initialized) return;
    const androidInit = AndroidInitializationSettings(_smallIcon);
    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: DarwinInitializationSettings(),
    );
    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) => onTap(response.payload),
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            channelId,
            channelName,
            description: _channelDescription,
            importance: Importance.high,
          ),
        );
    _initialized = true;
  }

  @override
  Future<void> clearAll() => _plugin.cancelAll();

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
    required String payload,
  }) async {
    await _plugin.show(
      id,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          channelDescription: _channelDescription,
          importance: Importance.high,
          priority: Priority.high,
          icon: _smallIcon,
        ),
        // #941: foreground FCM messages are rendered by us, not the OS (iOS
        // suppresses banners while foregrounded). Without explicit Darwin
        // details the plugin would fall back to implicit defaults; spell out
        // the presentation so a foreground push shows a banner + plays a sound.
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBanner: true,
          presentSound: true,
          presentBadge: true,
        ),
      ),
      payload: payload,
    );
  }
}
