import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
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
class NotificationService with WidgetsBindingObserver {
  NotificationService(
    this._ref, {
    FirebaseMessaging? messaging,
    FirebaseFirestore? firestore,
    String? Function()? currentUserId,
    bool Function()? isAnonymous,
    String Function()? localeResolver,
    Stream<String>? tokenRefresh,
    Stream<RemoteMessage>? foregroundMessages,
    Stream<RemoteMessage>? openedMessages,
    LocalNotifier? localNotifier,
    void Function(String location)? onNavigate,
    Future<RemoteMessage?> Function()? initialMessage,
    Future<NotificationSettings> Function()? notificationSettings,
  }) : _messaging = messaging,
       _firestoreOverride = firestore,
       _currentUserIdOverride = currentUserId,
       _isAnonymousOverride = isAnonymous,
       _localeResolverOverride = localeResolver,
       _tokenRefreshOverride = tokenRefresh,
       _foregroundMessagesOverride = foregroundMessages,
       _openedMessagesOverride = openedMessages,
       _localNotifierOverride = localNotifier,
       _onNavigateOverride = onNavigate,
       _initialMessageOverride = initialMessage,
       _notificationSettingsOverride = notificationSettings;

  final Ref _ref;

  FirebaseMessaging? _messaging;
  final FirebaseFirestore? _firestoreOverride;
  final String? Function()? _currentUserIdOverride;
  final bool Function()? _isAnonymousOverride;
  final String Function()? _localeResolverOverride;
  final Stream<String>? _tokenRefreshOverride;
  final Stream<RemoteMessage>? _foregroundMessagesOverride;
  final Stream<RemoteMessage>? _openedMessagesOverride;
  final void Function(String location)? _onNavigateOverride;
  final Future<RemoteMessage?> Function()? _initialMessageOverride;
  final Future<NotificationSettings> Function()? _notificationSettingsOverride;
  LocalNotifier? _localNotifierOverride;
  bool _initialized = false;
  bool _lifecycleObserverAdded = false;
  int _notificationId = 0;
  StreamSubscription<String>? _tokenRefreshSubscription;
  StreamSubscription<RemoteMessage>? _messageSubscription;
  StreamSubscription<RemoteMessage>? _messageOpenedSubscription;

  FirebaseFirestore get _firestore =>
      _firestoreOverride ?? FirebaseConfig.firestore;

  String? get _currentUserId =>
      _currentUserIdOverride?.call() ?? FirebaseConfig.currentUser?.uid;

  bool get _isCurrentUserAnonymous {
    final override = _isAnonymousOverride;
    if (override != null) return override();
    // An injected test uid implies a durable user; FirebaseConfig.currentUser
    // throws [core/no-app] in unit tests without Firebase (#390).
    if (_currentUserIdOverride != null) return false;
    try {
      return FirebaseConfig.currentUser?.isAnonymous ?? false;
    } catch (_) {
      return false;
    }
  }

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

  /// Read-only OS permission snapshot — NEVER `requestPermission`, which would
  /// re-prompt on every resume (#482).
  Future<NotificationSettings> _getNotificationSettings() =>
      _notificationSettingsOverride?.call() ??
      _messaging!.getNotificationSettings();

  /// Initialize Firebase Messaging. Call only after the user has opted in.
  Future<bool> initialize({bool handleInitialMessage = true}) async {
    if (_initialized) {
      await _saveToken();
      _setStatus(NotificationStatus.enabled);
      _addLifecycleObserver();
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
        _addLifecycleObserver();

        // Cold-start tap: the app was launched FROM a notification while
        // terminated. Route once after listeners are wired.
        if (handleInitialMessage) {
          await _handleInitialMessage();
        }
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

  /// Re-writes the stored token doc so its `locale` follows an app-language
  /// change (#483). The server localizes push copy from `fcm_tokens/{uid}.locale`
  /// (#53), which is otherwise frozen at first-write — a user who switches
  /// EN↔AR would keep receiving the old language until a random token rotation.
  /// Delegates to [_saveToken], so it no-ops while push is off/uninitialized and
  /// stays a silent skip for anonymous shells (#441).
  Future<void> refreshTokenLocale() => _saveToken();

  /// Save FCM token to Firestore.
  Future<void> _saveToken() async {
    if (!_initialized) return;

    try {
      final token = await _messaging!.getToken();
      if (token == null) return;

      final userId = _currentUserId;
      if (userId == null) return;
      // #441: anonymous shells must stay empty so a discarded shell never
      // strands data. Silent skip — by design, not an error state.
      if (_isCurrentUserAnonymous) return;

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
    if (_isCurrentUserAnonymous) return;

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

  /// Deep-links a notification tap to the landing where the entry lives, for the
  /// transactional types whose triggers ship a routing payload (#179):
  /// - `event` (event-created) → that event's hub `/group/$gid/event/$eid`
  /// - `expense` (expense-created) and an *event* `settlement` → that event's
  ///   ledger `/group/$gid/event/$eid/ledger`
  /// - a *group* `settlement` (no `eventId`, `groupSettlementNotifier`) and
  ///   `member_join` → the group hub `/group/$gid`
  /// - `claim_request` → group settings `/group/$gid/settings`
  /// - `claim_decided` → the group for claimed/current-member decisions, invite
  ///   join route, or join-group fallback depending on the decision payload
  ///
  /// `expense`/`event` always carry a non-empty `eventId` (their triggers fire
  /// on `events/{eid}/…` paths); the `hasEvent` guard degrades any future
  /// event-less payload to the group hub. Unknown types are ignored
  /// (forward-compatible).
  void _routeFromData(Map<String, dynamic> data) {
    final type = data['type'];
    if (type != 'settlement' &&
        type != 'member_join' &&
        type != 'expense' &&
        type != 'event' &&
        type != 'claim_request' &&
        type != 'claim_decided') {
      return;
    }
    final groupId = data['groupId'];
    if (groupId is! String || groupId.isEmpty) return;

    if (type == 'claim_request') {
      _navigate('/group/$groupId/settings');
      return;
    }

    if (type == 'claim_decided') {
      final decision = data['decision'];
      if (decision == 'claimed') {
        _navigate('/group/$groupId');
        return;
      }
      if (decision == 'declined') {
        if (data['routeability'] == 'member') {
          _navigate('/group/$groupId');
          return;
        }
        final inviteCode = data['inviteCode'];
        if (inviteCode is String && inviteCode.isNotEmpty) {
          _navigate('/join/$inviteCode');
        } else {
          _navigate('/join-group');
        }
        return;
      }
      _navigate('/join-group');
      return;
    }

    final eventId = data['eventId'];
    final hasEvent = eventId is String && eventId.isNotEmpty;
    if (hasEvent) {
      if (type == 'event') {
        _navigate('/group/$groupId/event/$eventId');
        return;
      }
      if (type == 'expense' || type == 'settlement') {
        _navigate('/group/$groupId/event/$eventId/ledger');
        return;
      }
    }
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

  /// #482: the OS notification permission can be revoked (or re-granted) in
  /// system Settings while the app is alive. Re-read it on resume so the
  /// Settings toggle stops reading a confident ON after a revoke — and recovers
  /// after a re-grant.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_recheckPermissionOnResume());
    }
  }

  void _addLifecycleObserver() {
    if (_lifecycleObserverAdded) return;
    try {
      WidgetsBinding.instance.addObserver(this);
      _lifecycleObserverAdded = true;
    } catch (_) {
      // No widgets binding (pure unit tests) — the resume re-check is wired in
      // production only; tests drive didChangeAppLifecycleState directly.
    }
  }

  void _removeLifecycleObserver() {
    if (!_lifecycleObserverAdded) return;
    try {
      WidgetsBinding.instance.removeObserver(this);
    } catch (_) {
      // see _addLifecycleObserver
    }
    _lifecycleObserverAdded = false;
  }

  Future<void> _recheckPermissionOnResume() async {
    try {
      final status = (await _getNotificationSettings()).authorizationStatus;
      final granted =
          status == AuthorizationStatus.authorized ||
          status == AuthorizationStatus.provisional;
      if (!granted) {
        // notDetermined shouldn't occur post opt-in; only a real denial flips
        // the toggle so a transient unknown never blanks a working state.
        if (status == AuthorizationStatus.denied) {
          _setStatus(NotificationStatus.permissionDenied);
        }
        return;
      }
      // Permission is present. If setup never completed (the user granted it in
      // OS Settings AFTER an in-app denial), run the full init so a token is
      // actually saved — otherwise the toggle reads ON with no token (#482).
      // initialize() does NOT re-prompt: requestPermission returns the existing
      // grant without UI once it's already granted.
      if (!_initialized) {
        await initialize();
      } else {
        _setStatus(NotificationStatus.enabled);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('FCM: resume permission re-check failed: $e');
    }
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
    _removeLifecycleObserver();
  }
}
