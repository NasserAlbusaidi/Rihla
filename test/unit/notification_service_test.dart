import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:safar/core/services/notification_service.dart';

class _MockFirebaseMessaging extends Mock implements FirebaseMessaging {}

void main() {
  test(
    'initialize stores the current token and marks notifications enabled',
    () async {
      final db = FakeFirebaseFirestore();
      final messaging = _MockFirebaseMessaging();
      final tokenRefresh = StreamController<String>.broadcast();
      final serviceProvider = _serviceProvider(
        messaging: messaging,
        firestore: db,
        currentUserId: () => 'uid-1',
        tokenRefresh: tokenRefresh.stream,
      );
      final container = ProviderContainer();
      addTearDown(container.dispose);
      addTearDown(tokenRefresh.close);

      when(
        () =>
            messaging.requestPermission(alert: true, badge: true, sound: true),
      ).thenAnswer((_) async => _settings(AuthorizationStatus.authorized));
      when(messaging.getToken).thenAnswer((_) async => 'token-1');

      final service = container.read(serviceProvider);

      expect(await service.initialize(), isTrue);

      expect(
        container.read(notificationStatusProvider),
        NotificationStatus.enabled,
      );
      final tokenDoc = await db.collection('fcm_tokens').doc('uid-1').get();
      expect(tokenDoc.data()?['token'], 'token-1');
      expect(tokenDoc.data()?['user_id'], 'uid-1');
    },
  );

  test(
    'initialize denies without trying to save a token when permission is denied',
    () async {
      final messaging = _MockFirebaseMessaging();
      final tokenRefresh = StreamController<String>.broadcast();
      final serviceProvider = _serviceProvider(
        messaging: messaging,
        firestore: FakeFirebaseFirestore(),
        currentUserId: () => 'uid-1',
        tokenRefresh: tokenRefresh.stream,
      );
      final container = ProviderContainer();
      addTearDown(container.dispose);
      addTearDown(tokenRefresh.close);

      when(
        () =>
            messaging.requestPermission(alert: true, badge: true, sound: true),
      ).thenAnswer((_) async => _settings(AuthorizationStatus.denied));

      final service = container.read(serviceProvider);

      expect(await service.initialize(), isFalse);

      expect(
        container.read(notificationStatusProvider),
        NotificationStatus.permissionDenied,
      );
      verifyNever(messaging.getToken);
    },
  );

  test('initialize marks error when permission request throws', () async {
    final messaging = _MockFirebaseMessaging();
    final tokenRefresh = StreamController<String>.broadcast();
    final serviceProvider = _serviceProvider(
      messaging: messaging,
      firestore: FakeFirebaseFirestore(),
      currentUserId: () => 'uid-1',
      tokenRefresh: tokenRefresh.stream,
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    addTearDown(tokenRefresh.close);

    when(
      () => messaging.requestPermission(alert: true, badge: true, sound: true),
    ).thenThrow(StateError('permission failed'));

    final service = container.read(serviceProvider);

    expect(await service.initialize(), isFalse);
    expect(
      container.read(notificationStatusProvider),
      NotificationStatus.error,
    );
  });

  test(
    'token refresh overwrites the stored token for the current user',
    () async {
      final db = FakeFirebaseFirestore();
      final messaging = _MockFirebaseMessaging();
      final tokenRefresh = StreamController<String>.broadcast();
      final serviceProvider = _serviceProvider(
        messaging: messaging,
        firestore: db,
        currentUserId: () => 'uid-1',
        tokenRefresh: tokenRefresh.stream,
      );
      final container = ProviderContainer();
      addTearDown(container.dispose);
      addTearDown(tokenRefresh.close);

      when(
        () =>
            messaging.requestPermission(alert: true, badge: true, sound: true),
      ).thenAnswer((_) async => _settings(AuthorizationStatus.provisional));
      when(messaging.getToken).thenAnswer((_) async => 'token-1');

      final service = container.read(serviceProvider);
      await service.initialize();

      tokenRefresh.add('token-2');
      await Future<void>.delayed(Duration.zero);

      final tokenDoc = await db.collection('fcm_tokens').doc('uid-1').get();
      expect(tokenDoc.data()?['token'], 'token-2');
    },
  );

  test(
    'removeToken deletes the stored token, cancels listeners, and marks off',
    () async {
      final db = FakeFirebaseFirestore();
      final messaging = _MockFirebaseMessaging();
      final tokenRefresh = StreamController<String>.broadcast();
      final serviceProvider = _serviceProvider(
        messaging: messaging,
        firestore: db,
        currentUserId: () => 'uid-1',
        tokenRefresh: tokenRefresh.stream,
      );
      final container = ProviderContainer();
      addTearDown(container.dispose);
      addTearDown(tokenRefresh.close);

      when(
        () =>
            messaging.requestPermission(alert: true, badge: true, sound: true),
      ).thenAnswer((_) async => _settings(AuthorizationStatus.authorized));
      when(messaging.getToken).thenAnswer((_) async => 'token-1');

      final service = container.read(serviceProvider);
      await service.initialize();

      await service.removeToken();

      final tokenDoc = await db.collection('fcm_tokens').doc('uid-1').get();
      expect(tokenDoc.exists, isFalse);
      expect(
        container.read(notificationStatusProvider),
        NotificationStatus.off,
      );
    },
  );
}

Provider<NotificationService> _serviceProvider({
  required FirebaseMessaging messaging,
  required FakeFirebaseFirestore firestore,
  required String? Function() currentUserId,
  required Stream<String> tokenRefresh,
}) {
  return Provider((ref) {
    final service = NotificationService(
      ref,
      messaging: messaging,
      firestore: firestore,
      currentUserId: currentUserId,
      tokenRefresh: tokenRefresh,
      foregroundMessages: const Stream<RemoteMessage>.empty(),
      openedMessages: const Stream<RemoteMessage>.empty(),
    );
    ref.onDispose(() => unawaited(service.dispose()));
    return service;
  });
}

NotificationSettings _settings(AuthorizationStatus authorizationStatus) {
  return NotificationSettings(
    alert: AppleNotificationSetting.enabled,
    announcement: AppleNotificationSetting.disabled,
    authorizationStatus: authorizationStatus,
    badge: AppleNotificationSetting.enabled,
    carPlay: AppleNotificationSetting.disabled,
    lockScreen: AppleNotificationSetting.enabled,
    notificationCenter: AppleNotificationSetting.enabled,
    showPreviews: AppleShowPreviewSetting.always,
    timeSensitive: AppleNotificationSetting.disabled,
    criticalAlert: AppleNotificationSetting.disabled,
    sound: AppleNotificationSetting.enabled,
    providesAppNotificationSettings: AppleNotificationSetting.disabled,
  );
}
