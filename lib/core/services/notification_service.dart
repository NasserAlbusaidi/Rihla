import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';

enum NotificationStatus {
  off,
  enabled,
  permissionDenied,
  error,
}

/// Provider for the current notification device state.
final notificationStatusProvider = StateProvider<NotificationStatus>((ref) {
  return NotificationStatus.off;
});

/// Provider for notification service.
final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService(ref);
});

/// Service for handling push notifications via Firebase Cloud Messaging.
class NotificationService {
  NotificationService(this._ref);

  final Ref _ref;

  FirebaseMessaging? _messaging;
  bool _initialized = false;
  StreamSubscription<String>? _tokenRefreshSubscription;
  StreamSubscription<RemoteMessage>? _messageSubscription;
  StreamSubscription<RemoteMessage>? _messageOpenedSubscription;

  SupabaseClient get _client => SupabaseConfig.client;

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

        _tokenRefreshSubscription ??= _messaging!.onTokenRefresh.listen(
          _onTokenRefresh,
        );
        _messageSubscription ??= FirebaseMessaging.onMessage.listen(
          _onForegroundMessage,
        );
        _messageOpenedSubscription ??=
            FirebaseMessaging.onMessageOpenedApp.listen(_onMessageTap);
        return true;
      }

      _initialized = false;
      _setStatus(NotificationStatus.permissionDenied);
      debugPrint('FCM: Permission denied');
      return false;
    } catch (e) {
      _initialized = false;
      _setStatus(NotificationStatus.error);
      debugPrint('FCM: Initialization failed: $e');
      return false;
    }
  }

  /// Save FCM token to Supabase.
  Future<void> _saveToken() async {
    if (!_initialized) return;

    try {
      final token = await _messaging!.getToken();
      if (token == null) return;

      final userId = _client.auth.currentUser?.id;
      if (userId == null) return;

      await _client.from('fcm_tokens').upsert({
        'user_id': userId,
        'token': token,
        'platform': defaultTargetPlatform.name,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id, token');
    } catch (e) {
      debugPrint('FCM: Failed to save token: $e');
      _setStatus(NotificationStatus.error);
    }
  }

  /// Handle token refresh.
  Future<void> _onTokenRefresh(String token) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;

    try {
      await _client.from('fcm_tokens').upsert({
        'user_id': userId,
        'token': token,
        'platform': defaultTargetPlatform.name,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id, token');
    } catch (e) {
      debugPrint('FCM: Token refresh save failed: $e');
      _setStatus(NotificationStatus.error);
    }
  }

  /// Handle foreground messages.
  void _onForegroundMessage(RemoteMessage message) {
    debugPrint('FCM foreground: ${message.notification?.title}');
  }

  /// Handle when user taps a notification.
  void _onMessageTap(RemoteMessage message) {
    debugPrint('FCM tap: ${message.data}');
  }

  /// Remove token when notifications are disabled or the user signs out.
  Future<void> removeToken() async {
    try {
      _messaging ??= FirebaseMessaging.instance;
      final token = await _messaging!.getToken();
      if (token != null) {
        await _client.from('fcm_tokens').delete().eq('token', token);
      }
    } catch (e) {
      debugPrint('FCM: Token removal failed: $e');
    } finally {
      _initialized = false;
      _setStatus(NotificationStatus.off);
    }
  }

  /// Reset device state after sign out.
  void markSignedOut() {
    _initialized = false;
    _setStatus(NotificationStatus.off);
  }

  bool get isInitialized => _initialized;

  void _setStatus(NotificationStatus status) {
    _ref.read(notificationStatusProvider.notifier).state = status;
  }
}
