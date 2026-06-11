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
  Future<void> initialize(void Function(String? payload) onTap) async {}

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
    required String payload,
  }) async {}
}

/// #441 PR2 — anonymous shells must stay provably empty: the two
/// fcm_tokens set() sites skip silently while the user is anonymous;
/// removeToken (cleanup) stays open.
void main() {
  late FakeFirebaseFirestore db;
  late _MockFirebaseMessaging messaging;
  late StreamController<String> tokenRefresh;
  late ProviderContainer container;

  Provider<NotificationService> serviceProvider({bool Function()? isAnonymous}) {
    return Provider((ref) {
      final service = NotificationService(
        ref,
        messaging: messaging,
        firestore: db,
        currentUserId: () => 'uid-anon',
        isAnonymous: isAnonymous,
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

  test('initialize skips the token write for an anonymous user '
      '(silent skip, not an error)', () async {
    final service = container.read(serviceProvider(isAnonymous: () => true));

    expect(await service.initialize(), isTrue);

    final doc = await db.collection('fcm_tokens').doc('uid-anon').get();
    expect(doc.exists, isFalse);
    expect(
      container.read(notificationStatusProvider),
      isNot(NotificationStatus.error),
    );
  });

  test('token refresh skips the write while anonymous', () async {
    final service = container.read(serviceProvider(isAnonymous: () => true));
    await service.initialize();

    tokenRefresh.add('token-2');
    await Future<void>.delayed(Duration.zero);

    final doc = await db.collection('fcm_tokens').doc('uid-anon').get();
    expect(doc.exists, isFalse);
  });

  test('removeToken still deletes the doc while anonymous (cleanup stays open)',
      () async {
    await db.collection('fcm_tokens').doc('uid-anon').set({'token': 'stale'});
    final service = container.read(serviceProvider(isAnonymous: () => true));

    await service.removeToken();

    final doc = await db.collection('fcm_tokens').doc('uid-anon').get();
    expect(doc.exists, isFalse);
  });

  test('default (no isAnonymous override, injected uid) keeps writing the token',
      () async {
    final service = container.read(serviceProvider());

    expect(await service.initialize(), isTrue);

    final doc = await db.collection('fcm_tokens').doc('uid-anon').get();
    expect(doc.exists, isTrue);
    expect(doc.data()!['token'], 'token-1');
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
