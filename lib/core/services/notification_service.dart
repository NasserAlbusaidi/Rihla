import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/firebase_config.dart';
import '../providers/settings_provider.dart';
import '../router/app_router.dart';
import 'local_notifier.dart';

enum NotificationStatus { off, enabled, permissionDenied, error }

/// Provider for the current notification device state.
final notificationStatusProvider = StateProvider<NotificationStatus>((ref) {
  return NotificationStatus.off;
});

/// Provider for notification service.
final notificationServiceProvider = Provider<NotificationService>((ref) {
  final service = NotificationService(ref);
  ref.onDispose(() {
    unawaited(service.dispose());
  });
  return service;
});

/// Service for handling push notifications via Firebase Cloud Messaging.
class NotificationService {
  NotificationService(
    this._ref, {
    FirebaseMessaging? messaging,
    FirebaseFirestore? firestore,
    String? Function()? currentUserId,
    String Function()? localeResolver,
    Stream<String>? tokenRefresh,
    Stream<RemoteMessage>? foregroundMessages,
    Stream<RemoteMessage>? openedMessages,
    LocalNotifier? localNotifier,
    void Function(String location)? onNavigate,
    Future<RemoteMessage?> Function()? initialMessage,
  }) : _messaging = messaging,
       _firestoreOverride = firestore,
       _currentUserIdOverride = currentUserId,
       _localeResolverOverride = localeResolver,
       _tokenRefreshOverride = tokenRefresh,
       _foregroundMessagesOverride = foregroundMessages,
       _openedMessagesOverride = openedMessages,
       _localNotifierOverride = localNotifier,
       _onNavigateOverride = onNavigate,
       _initialMessageOverride = initialMessage;

  final Ref _ref;

  FirebaseMessaging? _messaging;
  final FirebaseFirestore? _firestoreOverride;
  final String? Function()? _currentUserIdOverride;
  final String Function()? _localeResolverOverride;
  final Stream<String>? _tokenRefreshOverride;
  final Stream<RemoteMessage>? _foregroundMessagesOverride;
  final Stream<RemoteMessage>? _openedMessagesOverride;
  final void Function(String location)? _onNavigateOverride;
  final Future<RemoteMessage?> Function()? _initialMessageOverride;
  LocalNotifier? _localNotifierOverride;
  bool _initialized = false;
  int _notificationId = 0;
  StreamSubscription<String>? _tokenRefreshSubscription;
  StreamSubscription<RemoteMessage>? _messageSubscription;
  StreamSubscription<RemoteMessage>? _messageOpenedSubscription;

  FirebaseFirestore get _firestore =>
      _firestoreOverride ?? FirebaseConfig.firestore;

  String? get _currentUserId =>
      _currentUserIdOverride?.call() ?? FirebaseConfig.currentUser?.uid;

  /// Recipient locale persisted alongside the token so the server can localize
  /// push copy for terminated/backgrounded apps (#53). Falls back to 'en' (the
  /// [AppSettings] default) if settings are unavailable — must never throw a
  /// token write.
  String get _localeCode {
    final override = _localeResolverOverride;
    if (override != null) return override();
    try {
      return _ref.read(settingsProvider).languageCode;
    } catch (_) {
      return 'en';
    }
  }

  Stream<String> get _tokenRefresh =>
      _tokenRefreshOverride ?? _messaging!.onTokenRefresh;

  Stream<RemoteMessage> get _foregroundMessages =>
      _foregroundMessagesOverride ?? FirebaseMessaging.onMessage;

  Stream<RemoteMessage> get _openedMessages =>
      _openedMessagesOverride ?? FirebaseMessaging.onMessageOpenedApp;

  LocalNotifier get _localNotifier =>
      _localNotifierOverride ??= FlutterLocalNotifier();

  Future<RemoteMessage?> _getInitialMessage() =>
      _initialMessageOverride?.call() ?? _messaging!.getInitialMessage();

  /// Initialize Firebase Messaging. Call only after the user has opted in.
  Future<bool> initialize() async {
    if (_initialized) {
      await _saveToken();
      _setStatus(NotificationStatus.enabled);
      return true;
    }

    try {
      _messaging ??= FirebaseMessaging.instance;

      final permission = await _messaging!.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (permission.authorizationStatus == AuthorizationStatus.authorized ||
          permission.authorizationStatus == AuthorizationStatus.provisional) {
        _initialized = true;
        _setStatus(NotificationStatus.enabled);
        await _saveToken();

        await _localNotifier.initialize(_onLocalNotificationTap);

        _tokenRefreshSubscription ??= _tokenRefresh.listen(_onTokenRefresh);
        _messageSubscription ??= _foregroundMessages.listen(
          (message) => unawaited(_onForegroundMessage(message)),
        );
        _messageOpenedSubscription ??= _openedMessages.listen(_onMessageTap);

        // Cold-start tap: the app was launched FROM a notification while
        // terminated. Route once after listeners are wired.
        await _handleInitialMessage();
        return true;
      }

      _initialized = false;
      _setStatus(NotificationStatus.permissionDenied);
      return false;
    } catch (e) {
      _initialized = false;
      _setStatus(NotificationStatus.error);
      if (kDebugMode) debugPrint('FCM: Initialization failed: $e');
      return false;
    }
  }

  /// Save FCM token to Firestore.
  Future<void> _saveToken() async {
    if (!_initialized) return;

    try {
      final token = await _messaging!.getToken();
      if (token == null) return;

      final userId = _currentUserId;
      if (userId == null) return;

      await _firestore.collection('fcm_tokens').doc(userId).set({
        'user_id': userId,
        'token': token,
        'platform': defaultTargetPlatform.name,
        'locale': _localeCode,
        'updated_at': DateTime.now().toIso8601String(),
      }, SetOptions(merge: true));
    } catch (e) {
      if (kDebugMode) debugPrint('FCM: Failed to save token: $e');
      _setStatus(NotificationStatus.error);
    }
  }

  /// Handle token refresh.
  Future<void> _onTokenRefresh(String token) async {
    final userId = _currentUserId;
    if (userId == null) return;

    try {
      await _firestore.collection('fcm_tokens').doc(userId).set({
        'user_id': userId,
        'token': token,
        'platform': defaultTargetPlatform.name,
        'locale': _localeCode,
        'updated_at': DateTime.now().toIso8601String(),
      }, SetOptions(merge: true));
    } catch (e) {
      if (kDebugMode) debugPrint('FCM: Token refresh save failed: $e');
      _setStatus(NotificationStatus.error);
    }
  }

  /// Handle foreground messages. The OS does NOT auto-display a `notification`
  /// payload while the app is foregrounded, so render it ourselves; data-only
  /// messages (no `notification`) are silent by design.
  Future<void> _onForegroundMessage(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;
    try {
      await _localNotifier.show(
        id: _nextNotificationId(),
        title: notification.title ?? '',
        body: notification.body ?? '',
        payload: jsonEncode(message.data),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('FCM: foreground display failed: $e');
    }
  }

  /// Handle a tap on a notification that the OS displayed (app was
  /// backgrounded). Routes from the FCM data payload.
  void _onMessageTap(RemoteMessage message) {
    _routeFromData(message.data);
  }

  /// Handle a tap on a local notification we displayed in the foreground. The
  /// payload is the JSON-encoded FCM data map.
  void _onLocalNotificationTap(String? payload) {
    if (payload == null || payload.isEmpty) return;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map<String, dynamic>) _routeFromData(decoded);
    } catch (e) {
      if (kDebugMode) debugPrint('FCM: bad local-notification payload: $e');
    }
  }

  Future<void> _handleInitialMessage() async {
    try {
      final message = await _getInitialMessage();
      if (message != null) _routeFromData(message.data);
    } catch (e) {
      if (kDebugMode) debugPrint('FCM: initial message handling failed: $e');
    }
  }

  /// Deep-links a notification to the relevant group landing. Only `settlement`
  /// and `member_join` types with a non-empty `groupId` route; anything else is
  /// ignored (forward-compatible with future types).
  void _routeFromData(Map<String, dynamic> data) {
    final type = data['type'];
    if (type != 'settlement' && type != 'member_join') return;
    final groupId = data['groupId'];
    if (groupId is! String || groupId.isEmpty) return;
    _navigate('/group/$groupId');
  }

  void _navigate(String location) {
    final override = _onNavigateOverride;
    if (override != null) {
      override(location);
      return;
    }
    try {
      _ref.read(routerProvider).go(location);
    } catch (e) {
      if (kDebugMode) debugPrint('FCM: navigation to $location failed: $e');
    }
  }

  int _nextNotificationId() {
    _notificationId = (_notificationId + 1) & 0x7fffffff;
    return _notificationId;
  }

  /// Remove token when notifications are disabled.
  Future<void> removeToken() async {
    try {
      _messaging ??= FirebaseMessaging.instance;
      final userId = _currentUserId;
      if (userId != null) {
        await _firestore.collection('fcm_tokens').doc(userId).delete();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('FCM: Token removal failed: $e');
    } finally {
      await _cancelSubscriptions();
      _initialized = false;
      _setStatus(NotificationStatus.off);
    }
  }

  Future<void> dispose() async {
    await _cancelSubscriptions();
  }

  void _setStatus(NotificationStatus status) {
    _ref.read(notificationStatusProvider.notifier).state = status;
  }

  Future<void> _cancelSubscriptions() async {
    await _tokenRefreshSubscription?.cancel();
    await _messageSubscription?.cancel();
    await _messageOpenedSubscription?.cancel();
    _tokenRefreshSubscription = null;
    _messageSubscription = null;
    _messageOpenedSubscription = null;
  }
}
