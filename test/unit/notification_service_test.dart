import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:safar/core/services/local_notifier.dart';
import 'package:safar/core/services/notification_service.dart';

class _MockFirebaseMessaging extends Mock implements FirebaseMessaging {}

class _MockFirebaseFirestore extends Mock implements FirebaseFirestore {}

// ignore: subtype_of_sealed_class
class _MockTokenCollection extends Mock
    implements CollectionReference<Map<String, dynamic>> {}

// ignore: subtype_of_sealed_class
class _MockTokenDocument extends Mock
    implements DocumentReference<Map<String, dynamic>> {}

/// Records shows and exposes the tap callback so tests can simulate a tap on a
/// foreground-displayed local notification.
class _FakeLocalNotifier implements LocalNotifier {
  final List<Map<String, String>> shown = [];
  void Function(String? payload)? onTap;
  int clearAllCalls = 0;
  FutureOr<void> Function()? onClearAll;

  @override
  Future<void> clearAll() async {
    clearAllCalls += 1;
    await onClearAll?.call();
  }

  @override
  Future<void> initialize(void Function(String? payload) onTap) async {
    this.onTap = onTap;
  }

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
    required String payload,
  }) async {
    shown.add({'title': title, 'body': body, 'payload': payload});
  }
}

void main() {
  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
    registerFallbackValue(SetOptions(merge: true));
  });

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
    'token write persists the resolver locale for server-side copy (#53)',
    () async {
      final db = FakeFirebaseFirestore();
      final messaging = _MockFirebaseMessaging();
      final tokenRefresh = StreamController<String>.broadcast();
      final serviceProvider = _serviceProvider(
        messaging: messaging,
        firestore: db,
        currentUserId: () => 'uid-1',
        localeResolver: () => 'ar',
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

      final tokenDoc = await db.collection('fcm_tokens').doc('uid-1').get();
      expect(tokenDoc.data()?['locale'], 'ar');
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
    'refreshTokenLocale re-saves the stored token with the current locale (#483)',
    () async {
      final db = FakeFirebaseFirestore();
      final messaging = _MockFirebaseMessaging();
      final tokenRefresh = StreamController<String>.broadcast();
      var locale = 'en';
      final serviceProvider = _serviceProvider(
        messaging: messaging,
        firestore: db,
        currentUserId: () => 'uid-1',
        localeResolver: () => locale,
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
      expect(
        (await db.collection('fcm_tokens').doc('uid-1').get())
            .data()?['locale'],
        'en',
      );

      // App language switches EN→AR: refreshTokenLocale must rewrite the locale.
      locale = 'ar';
      await service.refreshTokenLocale();

      expect(
        (await db.collection('fcm_tokens').doc('uid-1').get())
            .data()?['locale'],
        'ar',
      );
    },
  );

  test(
    'refreshTokenLocale is a no-op when notifications were never initialized (#483)',
    () async {
      final db = FakeFirebaseFirestore();
      final messaging = _MockFirebaseMessaging();
      final tokenRefresh = StreamController<String>.broadcast();
      final serviceProvider = _serviceProvider(
        messaging: messaging,
        firestore: db,
        currentUserId: () => 'uid-1',
        localeResolver: () => 'ar',
        tokenRefresh: tokenRefresh.stream,
      );
      final container = ProviderContainer();
      addTearDown(container.dispose);
      addTearDown(tokenRefresh.close);

      final service = container.read(serviceProvider);
      // No initialize() → push is off → must not write a token.
      await service.refreshTokenLocale();

      expect(
        (await db.collection('fcm_tokens').doc('uid-1').get()).exists,
        isFalse,
      );
      verifyNever(messaging.getToken);
    },
  );

  test(
    'removeToken invalidates initialize awaiting permission (#1096)',
    () async {
      final db = FakeFirebaseFirestore();
      final messaging = _MockFirebaseMessaging();
      final tokenRefresh = StreamController<String>.broadcast();
      final foreground = StreamController<RemoteMessage>.broadcast();
      final opened = StreamController<RemoteMessage>.broadcast();
      final permissionStarted = Completer<void>();
      final permissionResult = Completer<NotificationSettings>();
      final provider = _serviceProvider(
        messaging: messaging,
        firestore: db,
        currentUserId: () => 'uid-1',
        tokenRefresh: tokenRefresh.stream,
        foregroundMessages: foreground.stream,
        openedMessages: opened.stream,
      );
      final container = ProviderContainer();
      addTearDown(container.dispose);
      addTearDown(tokenRefresh.close);
      addTearDown(foreground.close);
      addTearDown(opened.close);
      when(
        () =>
            messaging.requestPermission(alert: true, badge: true, sound: true),
      ).thenAnswer((_) {
        permissionStarted.complete();
        return permissionResult.future;
      });
      when(messaging.getToken).thenAnswer((_) async => 'token-1');

      final service = container.read(provider);
      final initialization = service.initialize();
      await permissionStarted.future;

      await service.removeToken();
      permissionResult.complete(_settings(AuthorizationStatus.authorized));
      await initialization;

      expect(
        container.read(notificationStatusProvider),
        NotificationStatus.off,
        reason: 'opt-out must invalidate an in-flight permission request',
      );
      expect(
        (await db.collection('fcm_tokens').doc('uid-1').get()).exists,
        isFalse,
      );
      verifyNever(messaging.getToken);
      expect(tokenRefresh.hasListener, isFalse);
      expect(foreground.hasListener, isFalse);
      expect(opened.hasListener, isFalse);
    },
  );

  test(
    'removeToken invalidates initialize awaiting getToken (#1096)',
    () async {
      final db = FakeFirebaseFirestore();
      final messaging = _MockFirebaseMessaging();
      final tokenRefresh = StreamController<String>.broadcast();
      final foreground = StreamController<RemoteMessage>.broadcast();
      final opened = StreamController<RemoteMessage>.broadcast();
      final getTokenStarted = Completer<void>();
      final tokenResult = Completer<String?>();
      final provider = _serviceProvider(
        messaging: messaging,
        firestore: db,
        currentUserId: () => 'uid-1',
        tokenRefresh: tokenRefresh.stream,
        foregroundMessages: foreground.stream,
        openedMessages: opened.stream,
      );
      final container = ProviderContainer();
      addTearDown(container.dispose);
      addTearDown(tokenRefresh.close);
      addTearDown(foreground.close);
      addTearDown(opened.close);
      when(
        () =>
            messaging.requestPermission(alert: true, badge: true, sound: true),
      ).thenAnswer((_) async => _settings(AuthorizationStatus.authorized));
      when(messaging.getToken).thenAnswer((_) {
        getTokenStarted.complete();
        return tokenResult.future;
      });

      final service = container.read(provider);
      final initialization = service.initialize();
      await getTokenStarted.future;

      await service.removeToken();
      tokenResult.complete('token-1');
      await initialization;

      expect(
        (await db.collection('fcm_tokens').doc('uid-1').get()).exists,
        isFalse,
        reason: 'opt-out must invalidate an in-flight token save',
      );
      expect(
        container.read(notificationStatusProvider),
        NotificationStatus.off,
      );
      expect(tokenRefresh.hasListener, isFalse);
      expect(foreground.hasListener, isFalse);
      expect(opened.hasListener, isFalse);
    },
  );

  test(
    'active re-registration does not invalidate in-flight setup (#480)',
    () async {
      final firestore = _MockFirebaseFirestore();
      final collection = _MockTokenCollection();
      final tokenDoc = _MockTokenDocument();
      final messaging = _MockFirebaseMessaging();
      final tokenRefresh = StreamController<String>.broadcast();
      final foreground = StreamController<RemoteMessage>.broadcast();
      final opened = StreamController<RemoteMessage>.broadcast();
      final notifier = _FakeLocalNotifier();
      final firstSetStarted = Completer<void>();
      final firstSetAck = Completer<void>();
      final nav = <String>[];
      var getTokenCalls = 0;
      var setCalls = 0;
      when(() => firestore.collection('fcm_tokens')).thenReturn(collection);
      when(() => collection.doc('uid-1')).thenReturn(tokenDoc);
      when(() => tokenDoc.set(any(), any())).thenAnswer((_) {
        setCalls += 1;
        if (setCalls == 1) {
          firstSetStarted.complete();
          return firstSetAck.future;
        }
        return Future<void>.value();
      });
      when(
        () =>
            messaging.requestPermission(alert: true, badge: true, sound: true),
      ).thenAnswer((_) async => _settings(AuthorizationStatus.authorized));
      when(messaging.getToken).thenAnswer((_) async {
        getTokenCalls += 1;
        return getTokenCalls == 1 ? 'token-1' : 'token-2';
      });
      final provider = _serviceProvider(
        messaging: messaging,
        firestore: firestore,
        currentUserId: () => 'uid-1',
        tokenRefresh: tokenRefresh.stream,
        foregroundMessages: foreground.stream,
        openedMessages: opened.stream,
        localNotifier: notifier,
        onNavigate: nav.add,
        initialMessage: () async =>
            const RemoteMessage(data: {'type': 'member_join', 'groupId': 'g1'}),
      );
      final container = ProviderContainer();
      addTearDown(() async {
        container.dispose();
        await tokenRefresh.close();
        await foreground.close();
        await opened.close();
      });

      final service = container.read(provider);
      final firstInitialization = service.initialize();
      await firstSetStarted.future;
      final secondInitialization = service.initialize();

      try {
        final secondResult = await secondInitialization;
        firstSetAck.complete();
        final firstResult = await firstInitialization;

        expect(
          (
            firstResult: firstResult,
            secondResult: secondResult,
            notifierInitialized: notifier.onTap != null,
            tokenRefreshListening: tokenRefresh.hasListener,
            foregroundListening: foreground.hasListener,
            openedListening: opened.hasListener,
            navigation: nav.join(','),
          ),
          (
            firstResult: true,
            secondResult: true,
            notifierInitialized: true,
            tokenRefreshListening: true,
            foregroundListening: true,
            openedListening: true,
            navigation: '/group/g1',
          ),
          reason: 'active re-registration must share the in-flight setup owner',
        );
      } finally {
        if (!firstSetAck.isCompleted) firstSetAck.complete();
        await secondInitialization;
        await firstInitialization;
      }
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

  test(
    'removeToken clears delivered notifications before cancelling tap routing (#1104)',
    () async {
      final db = FakeFirebaseFirestore();
      final messaging = _MockFirebaseMessaging();
      final tokenRefresh = StreamController<String>.broadcast();
      final opened = StreamController<RemoteMessage>.broadcast();
      final notifier = _FakeLocalNotifier();
      bool? tapListenerAliveDuringClear;
      notifier.onClearAll = () {
        tapListenerAliveDuringClear = opened.hasListener;
      };
      final provider = _serviceProvider(
        messaging: messaging,
        firestore: db,
        currentUserId: () => 'uid-1',
        tokenRefresh: tokenRefresh.stream,
        openedMessages: opened.stream,
        localNotifier: notifier,
      );
      final container = ProviderContainer();
      addTearDown(container.dispose);
      addTearDown(tokenRefresh.close);
      addTearDown(opened.close);
      when(
        () =>
            messaging.requestPermission(alert: true, badge: true, sound: true),
      ).thenAnswer((_) async => _settings(AuthorizationStatus.authorized));
      when(messaging.getToken).thenAnswer((_) async => 'token-1');

      final service = container.read(provider);
      await service.initialize();
      await service.removeToken();

      expect(notifier.clearAllCalls, 1);
      expect(tapListenerAliveDuringClear, isTrue);
      expect(opened.hasListener, isFalse);
    },
  );

  test(
    'removeToken waits for delete acknowledgement before its final clear (#1104)',
    () async {
      final firestore = _MockFirebaseFirestore();
      final collection = _MockTokenCollection();
      final tokenDoc = _MockTokenDocument();
      final messaging = _MockFirebaseMessaging();
      final tokenRefresh = StreamController<String>.broadcast();
      final opened = StreamController<RemoteMessage>.broadcast();
      final notifier = _FakeLocalNotifier();
      final deleteStarted = Completer<void>();
      final deleteAck = Completer<void>();
      var deleteAcknowledged = false;
      bool? deleteAcknowledgedDuringClear;
      bool? tapListenerAliveDuringClear;
      notifier.onClearAll = () {
        deleteAcknowledgedDuringClear = deleteAcknowledged;
        tapListenerAliveDuringClear = opened.hasListener;
      };
      when(() => firestore.collection('fcm_tokens')).thenReturn(collection);
      when(() => collection.doc('uid-1')).thenReturn(tokenDoc);
      when(() => tokenDoc.set(any(), any())).thenAnswer((_) async {});
      when(tokenDoc.delete).thenAnswer((_) {
        deleteStarted.complete();
        return deleteAck.future;
      });
      when(
        () =>
            messaging.requestPermission(alert: true, badge: true, sound: true),
      ).thenAnswer((_) async => _settings(AuthorizationStatus.authorized));
      when(messaging.getToken).thenAnswer((_) async => 'token-1');
      final provider = _serviceProvider(
        messaging: messaging,
        firestore: firestore,
        currentUserId: () => 'uid-1',
        tokenRefresh: tokenRefresh.stream,
        openedMessages: opened.stream,
        localNotifier: notifier,
      );
      final container = ProviderContainer();
      addTearDown(() async {
        container.dispose();
        await tokenRefresh.close();
        await opened.close();
      });

      final service = container.read(provider);
      await service.initialize();
      final removal = service.removeToken();
      await deleteStarted.future;

      try {
        expect(notifier.clearAllCalls, 0);
        expect(opened.hasListener, isTrue);

        deleteAcknowledged = true;
        deleteAck.complete();
        await removal;

        expect(notifier.clearAllCalls, 1);
        expect(deleteAcknowledgedDuringClear, isTrue);
        expect(tapListenerAliveDuringClear, isTrue);
        expect(opened.hasListener, isFalse);
      } finally {
        if (!deleteAck.isCompleted) {
          deleteAcknowledged = true;
          deleteAck.complete();
        }
        await removal;
      }
    },
  );

  test(
    'new opt-in supersedes removeToken while delete is pending (#1096/#1104)',
    () async {
      final firestore = _MockFirebaseFirestore();
      final collection = _MockTokenCollection();
      final tokenDoc = _MockTokenDocument();
      final messaging = _MockFirebaseMessaging();
      final tokenRefresh = StreamController<String>.broadcast();
      final foreground = StreamController<RemoteMessage>.broadcast();
      final opened = StreamController<RemoteMessage>.broadcast();
      final notifier = _FakeLocalNotifier();
      final deleteStarted = Completer<void>();
      final deleteAck = Completer<void>();
      final writes = <({String token, bool afterDeleteStarted})>[];
      var getTokenCalls = 0;
      when(() => firestore.collection('fcm_tokens')).thenReturn(collection);
      when(() => collection.doc('uid-1')).thenReturn(tokenDoc);
      when(() => tokenDoc.set(any(), any())).thenAnswer((invocation) async {
        final data =
            invocation.positionalArguments.first as Map<String, dynamic>;
        writes.add((
          token: data['token']! as String,
          afterDeleteStarted: deleteStarted.isCompleted,
        ));
      });
      when(tokenDoc.delete).thenAnswer((_) {
        deleteStarted.complete();
        return deleteAck.future;
      });
      when(
        () =>
            messaging.requestPermission(alert: true, badge: true, sound: true),
      ).thenAnswer((_) async => _settings(AuthorizationStatus.authorized));
      when(messaging.getToken).thenAnswer((_) async {
        getTokenCalls += 1;
        return getTokenCalls == 1 ? 'token-1' : 'token-2';
      });
      final provider = _serviceProvider(
        messaging: messaging,
        firestore: firestore,
        currentUserId: () => 'uid-1',
        tokenRefresh: tokenRefresh.stream,
        foregroundMessages: foreground.stream,
        openedMessages: opened.stream,
        localNotifier: notifier,
      );
      final container = ProviderContainer();
      addTearDown(() async {
        container.dispose();
        await tokenRefresh.close();
        await foreground.close();
        await opened.close();
      });

      final service = container.read(provider);
      expect(await service.initialize(), isTrue);
      expect(tokenRefresh.hasListener, isTrue);
      expect(foreground.hasListener, isTrue);
      expect(opened.hasListener, isTrue);

      final removal = service.removeToken();
      await deleteStarted.future;
      final reactivation = service.initialize();

      try {
        expect(await reactivation, isTrue);
        expect(
          writes.last,
          (token: 'token-2', afterDeleteStarted: true),
          reason: 'the newer token set must enqueue after the pending delete',
        );

        deleteAck.complete();
        await removal;

        expect(
          (
            status: container.read(notificationStatusProvider),
            tokenRefreshListening: tokenRefresh.hasListener,
            foregroundListening: foreground.hasListener,
            openedListening: opened.hasListener,
            clearAllCalls: notifier.clearAllCalls,
          ),
          (
            status: NotificationStatus.enabled,
            tokenRefreshListening: true,
            foregroundListening: true,
            openedListening: true,
            clearAllCalls: 0,
          ),
          reason: 'stale opt-out cleanup must not override the newer opt-in',
        );
      } finally {
        if (!deleteAck.isCompleted) deleteAck.complete();
        await reactivation;
        await removal;
      }
    },
  );

  test(
    'removeToken keeps tap routing alive when notification clearing fails (#1104)',
    () async {
      final db = FakeFirebaseFirestore();
      final messaging = _MockFirebaseMessaging();
      final tokenRefresh = StreamController<String>.broadcast();
      final opened = StreamController<RemoteMessage>.broadcast();
      final notifier = _FakeLocalNotifier()
        ..onClearAll = () => throw StateError('clear failed');
      final provider = _serviceProvider(
        messaging: messaging,
        firestore: db,
        currentUserId: () => 'uid-1',
        tokenRefresh: tokenRefresh.stream,
        openedMessages: opened.stream,
        localNotifier: notifier,
      );
      final container = ProviderContainer();
      addTearDown(() async {
        container.dispose();
        await tokenRefresh.close();
        await opened.close();
      });
      when(
        () =>
            messaging.requestPermission(alert: true, badge: true, sound: true),
      ).thenAnswer((_) async => _settings(AuthorizationStatus.authorized));
      when(messaging.getToken).thenAnswer((_) async => 'token-1');

      final service = container.read(provider);
      await service.initialize();
      await service.removeToken();

      expect(notifier.clearAllCalls, 1);
      expect(
        (await db.collection('fcm_tokens').doc('uid-1').get()).exists,
        isFalse,
      );
      expect(
        container.read(notificationStatusProvider),
        NotificationStatus.off,
      );
      expect(opened.hasListener, isTrue);
    },
  );

  test(
    'removeToken keeps tap routing alive when token deletion fails (#1104)',
    () async {
      final firestore = _MockFirebaseFirestore();
      final collection = _MockTokenCollection();
      final tokenDoc = _MockTokenDocument();
      final messaging = _MockFirebaseMessaging();
      final tokenRefresh = StreamController<String>.broadcast();
      final opened = StreamController<RemoteMessage>.broadcast();
      final notifier = _FakeLocalNotifier();
      when(() => firestore.collection('fcm_tokens')).thenReturn(collection);
      when(() => collection.doc('uid-1')).thenReturn(tokenDoc);
      when(() => tokenDoc.set(any(), any())).thenAnswer((_) async {});
      when(tokenDoc.delete).thenThrow(StateError('delete failed'));
      when(
        () =>
            messaging.requestPermission(alert: true, badge: true, sound: true),
      ).thenAnswer((_) async => _settings(AuthorizationStatus.authorized));
      when(messaging.getToken).thenAnswer((_) async => 'token-1');
      final provider = _serviceProvider(
        messaging: messaging,
        firestore: firestore,
        currentUserId: () => 'uid-1',
        tokenRefresh: tokenRefresh.stream,
        openedMessages: opened.stream,
        localNotifier: notifier,
      );
      final container = ProviderContainer();
      addTearDown(() async {
        container.dispose();
        await tokenRefresh.close();
        await opened.close();
      });

      final service = container.read(provider);
      await service.initialize();
      await service.removeToken();

      expect(notifier.clearAllCalls, 1);
      verify(tokenDoc.delete).called(1);
      expect(
        container.read(notificationStatusProvider),
        NotificationStatus.off,
      );
      expect(opened.hasListener, isTrue);
    },
  );

  test(
    'fresh explicit opt-out routes opened notifications while delete is pending (#1104)',
    () async {
      final firestore = _MockFirebaseFirestore();
      final collection = _MockTokenCollection();
      final tokenDoc = _MockTokenDocument();
      final messaging = _MockFirebaseMessaging();
      final tokenRefresh = StreamController<String>.broadcast();
      final opened = StreamController<RemoteMessage>.broadcast(sync: true);
      final deleteStarted = Completer<void>();
      final deleteAck = Completer<void>();
      final nav = <String>[];
      var initialMessageCalls = 0;
      when(() => firestore.collection('fcm_tokens')).thenReturn(collection);
      when(() => collection.doc('uid-1')).thenReturn(tokenDoc);
      when(tokenDoc.delete).thenAnswer((_) {
        deleteStarted.complete();
        return deleteAck.future;
      });
      final provider = _serviceProvider(
        messaging: messaging,
        firestore: firestore,
        currentUserId: () => 'uid-1',
        tokenRefresh: tokenRefresh.stream,
        openedMessages: opened.stream,
        onNavigate: nav.add,
        initialMessage: () async {
          initialMessageCalls += 1;
          return const RemoteMessage(
            data: {'type': 'member_join', 'groupId': 'initial'},
          );
        },
      );
      final container = ProviderContainer();
      addTearDown(() async {
        container.dispose();
        await tokenRefresh.close();
        await opened.close();
      });

      final service = container.read(provider);
      final removal = service.removeToken(handleInitialMessage: false);
      await deleteStarted.future;

      try {
        expect(initialMessageCalls, 0);
        expect(
          opened.hasListener,
          isTrue,
          reason:
              'explicit OFF must route delivered notification taps while cleanup is pending',
        );

        opened.add(
          const RemoteMessage(
            data: {'type': 'expense', 'groupId': 'g1', 'eventId': 'e1'},
          ),
        );
        await Future<void>.delayed(Duration.zero);

        expect(nav, ['/group/g1/event/e1/ledger']);
        verifyNever(
          () => messaging.requestPermission(
            alert: true,
            badge: true,
            sound: true,
          ),
        );
        verifyNever(messaging.getToken);
      } finally {
        deleteAck.complete();
        await removal;
      }
    },
  );

  test(
    'removeToken handles a disabled cold-start tap without opting in (#1104)',
    () async {
      final messaging = _MockFirebaseMessaging();
      final tokenRefresh = StreamController<String>.broadcast();
      final opened = StreamController<RemoteMessage>.broadcast();
      final nav = <String>[];
      final provider = _serviceProvider(
        messaging: messaging,
        firestore: FakeFirebaseFirestore(),
        currentUserId: () => 'uid-1',
        tokenRefresh: tokenRefresh.stream,
        openedMessages: opened.stream,
        onNavigate: nav.add,
        initialMessage: () async =>
            const RemoteMessage(data: {'type': 'member_join', 'groupId': 'g5'}),
      );
      final container = ProviderContainer();
      addTearDown(container.dispose);
      addTearDown(tokenRefresh.close);
      addTearDown(opened.close);

      final service = container.read(provider);
      await service.removeToken(handleInitialMessage: true);

      expect(nav, ['/group/g5']);
      verifyNever(
        () =>
            messaging.requestPermission(alert: true, badge: true, sound: true),
      );
      verifyNever(messaging.getToken);
    },
  );

  test(
    'removeToken defaults to preserving a higher-priority cold-start route (#1104)',
    () async {
      final messaging = _MockFirebaseMessaging();
      final tokenRefresh = StreamController<String>.broadcast();
      final nav = <String>[];
      var initialMessageCalls = 0;
      final provider = _serviceProvider(
        messaging: messaging,
        firestore: FakeFirebaseFirestore(),
        currentUserId: () => 'uid-1',
        tokenRefresh: tokenRefresh.stream,
        onNavigate: nav.add,
        initialMessage: () async {
          initialMessageCalls += 1;
          return const RemoteMessage(
            data: {'type': 'member_join', 'groupId': 'g5'},
          );
        },
      );
      final container = ProviderContainer();
      addTearDown(container.dispose);
      addTearDown(tokenRefresh.close);

      final service = container.read(provider);
      await service.removeToken();

      expect(initialMessageCalls, 0);
      expect(nav, isEmpty);
      verifyNever(
        () =>
            messaging.requestPermission(alert: true, badge: true, sound: true),
      );
      verifyNever(messaging.getToken);
    },
  );

  test(
    'removeToken blocks token refresh before a pending delete acknowledges (#1096)',
    () async {
      final firestore = _MockFirebaseFirestore();
      final collection = _MockTokenCollection();
      final tokenDoc = _MockTokenDocument();
      final messaging = _MockFirebaseMessaging();
      final tokenRefresh = StreamController<String>.broadcast(sync: true);
      final deleteStarted = Completer<void>();
      final deleteAck = Completer<void>();
      final writes = <String>[];

      when(() => firestore.collection('fcm_tokens')).thenReturn(collection);
      when(() => collection.doc('uid-1')).thenReturn(tokenDoc);
      when(() => tokenDoc.set(any(), any())).thenAnswer((invocation) async {
        final data =
            invocation.positionalArguments.first as Map<String, dynamic>;
        writes.add(data['token']! as String);
      });
      when(tokenDoc.delete).thenAnswer((_) {
        deleteStarted.complete();
        return deleteAck.future;
      });
      when(
        () =>
            messaging.requestPermission(alert: true, badge: true, sound: true),
      ).thenAnswer((_) async => _settings(AuthorizationStatus.authorized));
      when(messaging.getToken).thenAnswer((_) async => 'token-1');

      final provider = _serviceProvider(
        messaging: messaging,
        firestore: firestore,
        currentUserId: () => 'uid-1',
        tokenRefresh: tokenRefresh.stream,
      );
      final container = ProviderContainer();
      addTearDown(container.dispose);
      addTearDown(tokenRefresh.close);
      final service = container.read(provider);
      await service.initialize();
      writes.clear();

      final removal = service.removeToken();
      await deleteStarted.future;
      try {
        tokenRefresh.add('token-2');
        await Future<void>.delayed(Duration.zero);
        expect(
          writes,
          isEmpty,
          reason: 'an opt-out refresh must not recreate fcm_tokens/uid-1',
        );
      } finally {
        deleteAck.complete();
        await removal;
      }
    },
  );

  group('consumer (#53)', () {
    Future<
      ({
        NotificationService service,
        _FakeLocalNotifier notifier,
        List<String> nav,
      })
    >
    boot({
      Stream<RemoteMessage>? foreground,
      Stream<RemoteMessage>? opened,
      Future<RemoteMessage?> Function()? initialMessage,
      bool handleInitialMessage = true,
    }) async {
      final messaging = _MockFirebaseMessaging();
      final tokenRefresh = StreamController<String>.broadcast();
      final notifier = _FakeLocalNotifier();
      final nav = <String>[];
      final provider = _serviceProvider(
        messaging: messaging,
        firestore: FakeFirebaseFirestore(),
        currentUserId: () => 'uid-1',
        tokenRefresh: tokenRefresh.stream,
        foregroundMessages: foreground,
        openedMessages: opened,
        localNotifier: notifier,
        onNavigate: nav.add,
        initialMessage: initialMessage,
      );
      final container = ProviderContainer();
      addTearDown(container.dispose);
      addTearDown(tokenRefresh.close);
      when(
        () =>
            messaging.requestPermission(alert: true, badge: true, sound: true),
      ).thenAnswer((_) async => _settings(AuthorizationStatus.authorized));
      when(messaging.getToken).thenAnswer((_) async => 'token-1');
      final service = container.read(provider);
      await service.initialize(handleInitialMessage: handleInitialMessage);
      return (service: service, notifier: notifier, nav: nav);
    }

    test(
      'foreground message with a notification displays it locally',
      () async {
        final foreground = StreamController<RemoteMessage>.broadcast();
        addTearDown(foreground.close);
        final h = await boot(foreground: foreground.stream);

        foreground.add(
          const RemoteMessage(
            notification: RemoteNotification(
              title: 'Trip',
              body: 'Ahmed settled',
            ),
            data: {'type': 'settlement', 'groupId': 'g1'},
          ),
        );
        await Future<void>.delayed(Duration.zero);

        expect(h.notifier.shown, hasLength(1));
        expect(h.notifier.shown.first['title'], 'Trip');
        expect(h.notifier.shown.first['body'], 'Ahmed settled');
        expect(h.notifier.shown.first['payload'], contains('"groupId":"g1"'));
      },
    );

    test(
      'foreground data-only message (no notification) is NOT displayed',
      () async {
        final foreground = StreamController<RemoteMessage>.broadcast();
        addTearDown(foreground.close);
        final h = await boot(foreground: foreground.stream);

        foreground.add(
          const RemoteMessage(data: {'type': 'settlement', 'groupId': 'g1'}),
        );
        await Future<void>.delayed(Duration.zero);

        expect(h.notifier.shown, isEmpty);
      },
    );

    test(
      'tapping an event-settlement notification routes to the event ledger',
      () async {
        final opened = StreamController<RemoteMessage>.broadcast();
        addTearDown(opened.close);
        final h = await boot(opened: opened.stream);

        opened.add(
          const RemoteMessage(
            data: {'type': 'settlement', 'groupId': 'g7', 'eventId': 'e1'},
          ),
        );
        await Future<void>.delayed(Duration.zero);

        expect(h.nav, ['/group/g7/event/e1/ledger']);
      },
    );

    test(
      'tapping a group-settlement notification (no eventId) routes to the group',
      () async {
        final opened = StreamController<RemoteMessage>.broadcast();
        addTearDown(opened.close);
        final h = await boot(opened: opened.stream);

        opened.add(
          const RemoteMessage(data: {'type': 'settlement', 'groupId': 'g7'}),
        );
        await Future<void>.delayed(Duration.zero);

        expect(h.nav, ['/group/g7']);
      },
    );

    test(
      'tapping an expense notification routes to the event ledger',
      () async {
        final opened = StreamController<RemoteMessage>.broadcast();
        addTearDown(opened.close);
        final h = await boot(opened: opened.stream);

        opened.add(
          const RemoteMessage(
            data: {'type': 'expense', 'groupId': 'g7', 'eventId': 'e1'},
          ),
        );
        await Future<void>.delayed(Duration.zero);

        expect(h.nav, ['/group/g7/event/e1/ledger']);
      },
    );

    test(
      'tapping an event-created notification routes to the event hub',
      () async {
        final opened = StreamController<RemoteMessage>.broadcast();
        addTearDown(opened.close);
        final h = await boot(opened: opened.stream);

        opened.add(
          const RemoteMessage(
            data: {'type': 'event', 'groupId': 'g7', 'eventId': 'e1'},
          ),
        );
        await Future<void>.delayed(Duration.zero);

        expect(h.nav, ['/group/g7/event/e1']);
      },
    );

    test('tapping a member_join notification routes to the group', () async {
      final opened = StreamController<RemoteMessage>.broadcast();
      addTearDown(opened.close);
      final h = await boot(opened: opened.stream);

      opened.add(
        const RemoteMessage(data: {'type': 'member_join', 'groupId': 'g9'}),
      );
      await Future<void>.delayed(Duration.zero);

      expect(h.nav, ['/group/g9']);
    });

    test(
      'tapping a claim_request notification routes to group settings',
      () async {
        final opened = StreamController<RemoteMessage>.broadcast();
        addTearDown(opened.close);
        final h = await boot(opened: opened.stream);

        opened.add(
          const RemoteMessage(data: {'type': 'claim_request', 'groupId': 'g7'}),
        );
        await Future<void>.delayed(Duration.zero);

        expect(h.nav, ['/group/g7/settings']);
      },
    );

    test(
      'tapping a claimed claim_decided notification routes to the group',
      () async {
        final opened = StreamController<RemoteMessage>.broadcast();
        addTearDown(opened.close);
        final h = await boot(opened: opened.stream);

        opened.add(
          const RemoteMessage(
            data: {
              'type': 'claim_decided',
              'groupId': 'g7',
              'decision': 'claimed',
            },
          ),
        );
        await Future<void>.delayed(Duration.zero);

        expect(h.nav, ['/group/g7']);
      },
    );

    test(
      'tapping a declined claim_decided notification routes to the invite',
      () async {
        final opened = StreamController<RemoteMessage>.broadcast();
        addTearDown(opened.close);
        final h = await boot(opened: opened.stream);

        opened.add(
          const RemoteMessage(
            data: {
              'type': 'claim_decided',
              'groupId': 'g7',
              'decision': 'declined',
              'inviteCode': 'ABC123',
            },
          ),
        );
        await Future<void>.delayed(Duration.zero);

        expect(h.nav, ['/join/ABC123']);
      },
    );

    test(
      'tapping a declined member-routeable claim_decided notification routes to the group',
      () async {
        final opened = StreamController<RemoteMessage>.broadcast();
        addTearDown(opened.close);
        final h = await boot(opened: opened.stream);

        opened.add(
          const RemoteMessage(
            data: {
              'type': 'claim_decided',
              'groupId': 'g7',
              'decision': 'declined',
              'inviteCode': 'ABC123',
              'routeability': 'member',
            },
          ),
        );
        await Future<void>.delayed(Duration.zero);

        expect(h.nav, ['/group/g7']);
      },
    );

    test(
      'tapping a declined claim_decided without inviteCode routes to join-group',
      () async {
        final opened = StreamController<RemoteMessage>.broadcast();
        addTearDown(opened.close);
        final h = await boot(opened: opened.stream);

        opened.add(
          const RemoteMessage(
            data: {
              'type': 'claim_decided',
              'groupId': 'g7',
              'decision': 'declined',
            },
          ),
        );
        await Future<void>.delayed(Duration.zero);

        expect(h.nav, ['/join-group']);
      },
    );

    test('legacy claim_decided notification routes to join-group', () async {
      final opened = StreamController<RemoteMessage>.broadcast();
      addTearDown(opened.close);
      final h = await boot(opened: opened.stream);

      opened.add(
        const RemoteMessage(data: {'type': 'claim_decided', 'groupId': 'g7'}),
      );
      await Future<void>.delayed(Duration.zero);

      expect(h.nav, ['/join-group']);
    });

    test('unknown type or missing groupId does not route', () async {
      final opened = StreamController<RemoteMessage>.broadcast();
      addTearDown(opened.close);
      final h = await boot(opened: opened.stream);

      opened.add(
        const RemoteMessage(data: {'type': 'mystery', 'groupId': 'g1'}),
      );
      opened.add(
        const RemoteMessage(data: {'type': 'settlement'}),
      ); // no groupId
      opened.add(const RemoteMessage(data: {'type': 'claim_request'}));
      opened.add(
        const RemoteMessage(
          data: {'type': 'claim_decided', 'decision': 'claimed'},
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(h.nav, isEmpty);
    });

    test(
      'tapping a foreground local notification routes from its payload',
      () async {
        final h = await boot();

        h.notifier.onTap!('{"type":"settlement","groupId":"g3"}');

        expect(h.nav, ['/group/g3']);
      },
    );

    test(
      'cold-start (terminated) launch from a notification routes once',
      () async {
        final h = await boot(
          initialMessage: () async => const RemoteMessage(
            data: {'type': 'member_join', 'groupId': 'g5'},
          ),
        );

        expect(h.nav, ['/group/g5']);
      },
    );

    test(
      'initialize can skip only cold-start notification routing after an invite wins',
      () async {
        final h = await boot(
          handleInitialMessage: false,
          initialMessage: () async => const RemoteMessage(
            data: {'type': 'member_join', 'groupId': 'g5'},
          ),
        );

        expect(h.nav, isEmpty);

        h.notifier.onTap!('{"type":"settlement","groupId":"g3"}');
        expect(h.nav, ['/group/g3']);
      },
    );
  });

  group('resume permission re-check (#482)', () {
    test(
      'an OS permission revoke while running flips the status to permissionDenied',
      () async {
        final messaging = _MockFirebaseMessaging();
        final tokenRefresh = StreamController<String>.broadcast();
        var osStatus = AuthorizationStatus.authorized;
        final provider = _serviceProvider(
          messaging: messaging,
          firestore: FakeFirebaseFirestore(),
          currentUserId: () => 'uid-1',
          tokenRefresh: tokenRefresh.stream,
          notificationSettings: () async => _settings(osStatus),
        );
        final container = ProviderContainer();
        addTearDown(container.dispose);
        addTearDown(tokenRefresh.close);

        when(
          () => messaging.requestPermission(
            alert: true,
            badge: true,
            sound: true,
          ),
        ).thenAnswer((_) async => _settings(AuthorizationStatus.authorized));
        when(messaging.getToken).thenAnswer((_) async => 'token-1');

        final service = container.read(provider);
        await service.initialize();
        expect(
          container.read(notificationStatusProvider),
          NotificationStatus.enabled,
        );

        // User revokes the permission in OS Settings, then returns to the app.
        osStatus = AuthorizationStatus.denied;
        service.didChangeAppLifecycleState(AppLifecycleState.resumed);
        await Future<void>.delayed(Duration.zero);

        expect(
          container.read(notificationStatusProvider),
          NotificationStatus.permissionDenied,
        );
      },
    );

    test(
      'granting in OS Settings after an in-app denial recovers on resume and '
      'saves a token (no confident-ON-with-no-token)',
      () async {
        final db = FakeFirebaseFirestore();
        final messaging = _MockFirebaseMessaging();
        final tokenRefresh = StreamController<String>.broadcast();
        var osStatus = AuthorizationStatus.denied;
        final provider = _serviceProvider(
          messaging: messaging,
          firestore: db,
          currentUserId: () => 'uid-1',
          tokenRefresh: tokenRefresh.stream,
          notificationSettings: () async => _settings(osStatus),
        );
        final container = ProviderContainer();
        addTearDown(container.dispose);
        addTearDown(tokenRefresh.close);

        // requestPermission mirrors the live OS state: denied at first, then
        // authorized once the user grants it in Settings (no UI is shown when
        // already granted).
        when(
          () => messaging.requestPermission(
            alert: true,
            badge: true,
            sound: true,
          ),
        ).thenAnswer((_) async => _settings(osStatus));
        when(messaging.getToken).thenAnswer((_) async => 'token-1');

        final service = container.read(provider);
        await service.initialize();
        expect(
          container.read(notificationStatusProvider),
          NotificationStatus.permissionDenied,
        );
        expect(
          (await db.collection('fcm_tokens').doc('uid-1').get()).exists,
          isFalse,
          reason: 'no token while permission is denied',
        );

        // User grants in OS Settings and returns to the app.
        osStatus = AuthorizationStatus.authorized;
        service.didChangeAppLifecycleState(AppLifecycleState.resumed);
        await Future<void>.delayed(Duration.zero);

        expect(
          container.read(notificationStatusProvider),
          NotificationStatus.enabled,
        );
        expect(
          (await db.collection('fcm_tokens').doc('uid-1').get())
              .data()?['token'],
          'token-1',
          reason: 'resume recovery must actually save a token',
        );
      },
    );
  });
}

Provider<NotificationService> _serviceProvider({
  required FirebaseMessaging messaging,
  required FirebaseFirestore firestore,
  required String? Function() currentUserId,
  required Stream<String> tokenRefresh,
  String Function()? localeResolver,
  Stream<RemoteMessage>? foregroundMessages,
  Stream<RemoteMessage>? openedMessages,
  LocalNotifier? localNotifier,
  void Function(String location)? onNavigate,
  Future<RemoteMessage?> Function()? initialMessage,
  Future<NotificationSettings> Function()? notificationSettings,
}) {
  return Provider((ref) {
    final service = NotificationService(
      ref,
      messaging: messaging,
      firestore: firestore,
      currentUserId: currentUserId,
      localeResolver: localeResolver,
      tokenRefresh: tokenRefresh,
      foregroundMessages:
          foregroundMessages ?? const Stream<RemoteMessage>.empty(),
      openedMessages: openedMessages ?? const Stream<RemoteMessage>.empty(),
      localNotifier: localNotifier ?? _FakeLocalNotifier(),
      onNavigate: onNavigate,
      // Default: no cold-start message. Avoids hitting the unstubbed mock's
      // getInitialMessage in tests that don't exercise cold-start routing.
      initialMessage: initialMessage ?? () async => null,
      notificationSettings: notificationSettings,
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
