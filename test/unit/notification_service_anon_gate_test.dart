import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:safar/core/services/local_notifier.dart';
import 'package:safar/core/services/notification_service.dart';

class _MockFirebaseMessaging extends Mock implements FirebaseMessaging {}

class _NoopLocalNotifier implements LocalNotifier {
  @override
  Future<void> clearAll() async {}

  @override
  Future<void> initialize(void Function(String? payload) onTap) async {}

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
    required String payload,
  }) async {}
}

/// Anonymous users can own groups after #648/#818, so push opt-in must write an
/// owner-keyed token doc for the anonymous UID as well as for durable UIDs.
void main() {
  late FakeFirebaseFirestore db;
  late _MockFirebaseMessaging messaging;
  late StreamController<String> tokenRefresh;
  late ProviderContainer container;

  Provider<NotificationService> serviceProvider() {
    return Provider((ref) {
      final service = NotificationService(
        ref,
        messaging: messaging,
        firestore: db,
        currentUserId: () => 'uid-anon',
        tokenRefresh: tokenRefresh.stream,
        foregroundMessages: const Stream<RemoteMessage>.empty(),
        openedMessages: const Stream<RemoteMessage>.empty(),
        localNotifier: _NoopLocalNotifier(),
        initialMessage: () async => null,
      );
      ref.onDispose(() => unawaited(service.dispose()));
      return service;
    });
  }

  setUp(() {
    db = FakeFirebaseFirestore();
    messaging = _MockFirebaseMessaging();
    tokenRefresh = StreamController<String>.broadcast();
    container = ProviderContainer();
    when(
      () => messaging.requestPermission(alert: true, badge: true, sound: true),
    ).thenAnswer((_) async => _settings(AuthorizationStatus.authorized));
    when(messaging.getToken).thenAnswer((_) async => 'token-1');
  });

  tearDown(() async {
    container.dispose();
    await tokenRefresh.close();
  });

  test('initialize writes the token for an anonymous owner uid', () async {
    final service = container.read(serviceProvider());

    expect(await service.initialize(), isTrue);

    final doc = await db.collection('fcm_tokens').doc('uid-anon').get();
    expect(doc.exists, isTrue);
    expect(doc.data()?['token'], 'token-1');
    expect(doc.data()?['user_id'], 'uid-anon');
    expect(
      container.read(notificationStatusProvider),
      NotificationStatus.enabled,
    );
  });

  test('token refresh updates the anonymous owner token doc', () async {
    final service = container.read(serviceProvider());
    await service.initialize();

    tokenRefresh.add('token-2');
    await Future<void>.delayed(Duration.zero);

    final doc = await db.collection('fcm_tokens').doc('uid-anon').get();
    expect(doc.data()?['token'], 'token-2');
  });

  test('removeToken deletes the anonymous owner token doc', () async {
    await db.collection('fcm_tokens').doc('uid-anon').set({'token': 'stale'});
    final service = container.read(serviceProvider());

    await service.removeToken();

    final doc = await db.collection('fcm_tokens').doc('uid-anon').get();
    expect(doc.exists, isFalse);
  });

  test('initialized service re-save keeps writing the owner token', () async {
    final service = container.read(serviceProvider());

    expect(await service.initialize(), isTrue);
    when(messaging.getToken).thenAnswer((_) async => 'token-3');
    expect(await service.initialize(), isTrue);

    final doc = await db.collection('fcm_tokens').doc('uid-anon').get();
    expect(doc.exists, isTrue);
    expect(doc.data()!['token'], 'token-3');
  });
}

NotificationSettings _settings(AuthorizationStatus authorizationStatus) {
  return NotificationSettings(
    alert: AppleNotificationSetting.enabled,
    announcement: AppleNotificationSetting.disabled,
    authorizationStatus: authorizationStatus,
    badge: AppleNotificationSetting.enabled,
    carPlay: AppleNotificationSetting.disabled,
    criticalAlert: AppleNotificationSetting.disabled,
    lockScreen: AppleNotificationSetting.enabled,
    notificationCenter: AppleNotificationSetting.enabled,
    showPreviews: AppleShowPreviewSetting.always,
    sound: AppleNotificationSetting.enabled,
    timeSensitive: AppleNotificationSetting.disabled,
    providesAppNotificationSettings: AppleNotificationSetting.disabled,
  );
}
