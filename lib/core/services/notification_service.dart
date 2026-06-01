import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/firebase_config.dart';

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
    Stream<String>? tokenRefresh,
    Stream<RemoteMessage>? foregroundMessages,
    Stream<RemoteMessage>? openedMessages,
  }) : _messaging = messaging,
       _firestoreOverride = firestore,
       _currentUserIdOverride = currentUserId,
       _tokenRefreshOverride = tokenRefresh,
       _foregroundMessagesOverride = foregroundMessages,
       _openedMessagesOverride = openedMessages;

  final Ref _ref;

  FirebaseMessaging? _messaging;
  final FirebaseFirestore? _firestoreOverride;
  final String? Function()? _currentUserIdOverride;
  final Stream<String>? _tokenRefreshOverride;
  final Stream<RemoteMessage>? _foregroundMessagesOverride;
  final Stream<RemoteMessage>? _openedMessagesOverride;
  bool _initialized = false;
  StreamSubscription<String>? _tokenRefreshSubscription;
  StreamSubscription<RemoteMessage>? _messageSubscription;
  StreamSubscription<RemoteMessage>? _messageOpenedSubscription;

  FirebaseFirestore get _firestore =>
      _firestoreOverride ?? FirebaseConfig.firestore;

  String? get _currentUserId =>
      _currentUserIdOverride?.call() ?? FirebaseConfig.currentUser?.uid;

  Stream<String> get _tokenRefresh =>
      _tokenRefreshOverride ?? _messaging!.onTokenRefresh;

  Stream<RemoteMessage> get _foregroundMessages =>
      _foregroundMessagesOverride ?? FirebaseMessaging.onMessage;

  Stream<RemoteMessage> get _openedMessages =>
      _openedMessagesOverride ?? FirebaseMessaging.onMessageOpenedApp;

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

        _tokenRefreshSubscription ??= _tokenRefresh.listen(_onTokenRefresh);
        _messageSubscription ??= _foregroundMessages.listen(
          _onForegroundMessage,
        );
        _messageOpenedSubscription ??= _openedMessages.listen(_onMessageTap);
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
        'updated_at': DateTime.now().toIso8601String(),
      }, SetOptions(merge: true));
    } catch (e) {
      if (kDebugMode) debugPrint('FCM: Token refresh save failed: $e');
      _setStatus(NotificationStatus.error);
    }
  }

  /// Handle foreground messages.
  void _onForegroundMessage(RemoteMessage message) {}

  /// Handle when user taps a notification.
  void _onMessageTap(RemoteMessage message) {}

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
