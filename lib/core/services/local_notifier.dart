import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Seam over `flutter_local_notifications` so [NotificationService] stays
/// unit-testable — the platform plugin (and its channel wiring) lives ONLY in
/// [FlutterLocalNotifier]; tests inject a fake implementation (#53).
abstract interface class LocalNotifier {
  /// Initializes the plugin and the Android channel. [onTap] receives the
  /// notification's `payload` string when the user taps a displayed local
  /// notification.
  Future<void> initialize(void Function(String? payload) onTap);

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

  bool _initialized = false;

  @override
  Future<void> initialize(void Function(String? payload) onTap) async {
    if (_initialized) return;
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
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
        ),
      ),
      payload: payload,
    );
  }
}
