# Notification Opt-Out Lifecycle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make push opt-out race-safe, reconcile an explicitly disabled device on cold boot, and remove already-delivered notifications before tap routing is torn down.

**Architecture:** `NotificationService.removeToken()` becomes an ordered shutdown: mark delivery inactive, cancel token-producing/foreground listeners, clear delivered notifications while tap routing is still available, delete the owner token document, then tear down tap routing when clearing succeeded. Cold boot keeps the #635 no-service fast path for a fresh default, but uses the existing SharedPreferences push-key presence to reconcile devices that previously expressed a push preference.

**Tech Stack:** Flutter 3.41, Dart 3.11, Riverpod 2.x, Firebase Messaging/Firestore, SharedPreferences, flutter_local_notifications 18.0.1, flutter_test, mocktail.

## Global Constraints

- Implement #1096 first, then #1104, with separate conventional commits.
- The final commit body must contain both `Closes #1096` and `Closes #1104`.
- Add a failing regression test before each production behavior change and preserve the exact failing output for the PR body.
- Do not edit `security/firestore.rules`, `functions/**`, or any `**/models/**.dart` file.
- Keep the `fcm_tokens/{uid}` write map and delete path unchanged; no Firestore data shape changes.
- Keep the #635 cold-boot no-op for a device with no persisted push preference.
- Do not request notification permission, save a token, or set `NotificationStatus.enabled` while push intent is off.
- `removeToken()` must set `_initialized = false` before its first `await` and cancel token refresh before awaiting Firestore deletion.
- Delivered-notification clearing must happen while FCM tap routing is still subscribed.
- A tray-clear failure must not skip token deletion or `NotificationStatus.off`; tap routing stays alive when clearing fails so an uncleared notification remains routeable.
- Do not weaken or delete existing tests.
- Run full `flutter test` and `flutter analyze` after each issue. No widget file is in scope, so `tool/check_theme_purity.sh` is not required unless scope changes.

**Gate classification:** Exempt under the repository Operating Contract. The plan changes notification-service lifecycle ordering and reads the presence of an existing local preference key; it does not touch money, rules/Functions validation, route definitions/deep-link parsing/back guards, or a Firestore read/write schema.

---

## File Structure

- Modify `lib/core/services/notification_service.dart`: order producer, tray, token-doc, and tap-routing shutdown; guard stale refresh callbacks.
- Modify `lib/core/services/settings_service.dart`: expose whether the existing push preference key has ever been persisted.
- Modify `lib/core/providers/app_bootstrap_provider.dart`: reconcile explicit OFF on cold boot while retaining the absent-key fast path.
- Modify `lib/core/services/local_notifier.dart`: expose and implement delivered/scheduled notification clearing through the pinned plugin's `cancelAll()` API.
- Modify `test/unit/notification_service_test.dart`: deterministic pending-delete race coverage and delivered-notification ordering/error coverage.
- Modify `test/unit/notification_service_anon_gate_test.dart`: keep the `LocalNotifier` fake aligned with its interface.
- Modify `test/unit/settings_notifier_test.dart`: pin absent-key versus explicit-false push preference history.
- Modify `test/core/providers/app_bootstrap_wiring_test.dart`: pin fresh-disabled no-op and explicit-disabled reconciliation.
- Create `test/unit/local_notifier_test.dart`: prove the production wrapper delegates clearing to the plugin.

### Task 1: Issue #1096 — stop refresh resurrection and reconcile explicit OFF

**Files:**
- Modify: `lib/core/services/notification_service.dart`
- Modify: `lib/core/services/settings_service.dart`
- Modify: `lib/core/providers/app_bootstrap_provider.dart`
- Modify: `test/unit/notification_service_test.dart`
- Modify: `test/unit/settings_notifier_test.dart`
- Modify: `test/core/providers/app_bootstrap_wiring_test.dart`

**Interfaces:**
- Produces: `SettingsService.hasPushNotificationsPreference -> bool`.
- Produces: `runInitialNotificationSync(..., {bool hasPersistedPushPreference = false, bool handleInitialMessage = true})`.
- Produces: `_cancelDeliverySubscriptions()` and `_cancelTapRoutingSubscription()` private lifecycle boundaries.
- Preserves: `NotificationService.removeToken() -> Future<void>` public signature for Task 1.

- [ ] **Step 1: Write the pending-delete token-refresh regression**

Add Firestore mock types to `test/unit/notification_service_test.dart`, loosen `_serviceProvider`'s Firestore parameter to `FirebaseFirestore`, and add this behavior:

```dart
class _MockFirebaseFirestore extends Mock implements FirebaseFirestore {}

class _MockTokenCollection extends Mock
    implements CollectionReference<Map<String, dynamic>> {}

class _MockTokenDocument extends Mock
    implements DocumentReference<Map<String, dynamic>> {}

// In main(), before tests register typed mocktail fallback arguments.
setUpAll(() {
  registerFallbackValue(<String, dynamic>{});
  registerFallbackValue(SetOptions(merge: true));
});

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
      final data = invocation.positionalArguments.first as Map<String, dynamic>;
      writes.add(data['token']! as String);
    });
    when(tokenDoc.delete).thenAnswer((_) {
      deleteStarted.complete();
      return deleteAck.future;
    });
    when(
      () => messaging.requestPermission(alert: true, badge: true, sound: true),
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
```

- [ ] **Step 2: Run the regression and save RED evidence**

Run:

```bash
flutter test test/unit/notification_service_test.dart --plain-name 'removeToken blocks token refresh before a pending delete acknowledges (#1096)'
```

Expected: FAIL at the `writes isEmpty` assertion because `token-2` is written while the delete future is pending. Copy the complete failure into the Task 1 report for the PR body.

- [ ] **Step 3: Stop delivery before deletion**

Implement the minimum ordering in `notification_service.dart`:

```dart
Future<void> _onTokenRefresh(String token) async {
  if (!_initialized) return;
  final userId = _currentUserId;
  if (userId == null) return;
  // existing unchanged write map
}

Future<void> removeToken() async {
  _initialized = false;
  await _cancelDeliverySubscriptions();
  try {
    _messaging ??= FirebaseMessaging.instance;
    final userId = _currentUserId;
    if (userId != null) {
      await _firestore.collection('fcm_tokens').doc(userId).delete();
    }
  } catch (e) {
    if (kDebugMode) debugPrint('FCM: Token removal failed: $e');
  } finally {
    await _cancelTapRoutingSubscription();
    _setStatus(NotificationStatus.off);
  }
}

Future<void> _cancelDeliverySubscriptions() async {
  await _tokenRefreshSubscription?.cancel();
  await _messageSubscription?.cancel();
  _tokenRefreshSubscription = null;
  _messageSubscription = null;
  _removeLifecycleObserver();
}

Future<void> _cancelTapRoutingSubscription() async {
  await _messageOpenedSubscription?.cancel();
  _messageOpenedSubscription = null;
}

Future<void> _cancelSubscriptions() async {
  await _cancelDeliverySubscriptions();
  await _cancelTapRoutingSubscription();
}
```

Also set `_initialized = false` before `dispose()` cancels subscriptions so no stale refresh callback can write during disposal.

- [ ] **Step 4: Re-run the #1096 race test GREEN**

Run the Step 2 command. Expected: PASS, with no `token-2` write while deletion is pending.

- [ ] **Step 5: Pin the existing preference-key breadcrumb**

Add to `test/unit/settings_notifier_test.dart`:

```dart
test('push preference distinguishes a fresh default from explicit opt-out', () async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final service = SettingsService(prefs);

  expect(service.hasPushNotificationsPreference, isFalse);

  await service.savePushNotificationsEnabled(false);

  expect(service.hasPushNotificationsPreference, isTrue);
});
```

Run:

```bash
flutter test test/unit/settings_notifier_test.dart --plain-name 'push preference distinguishes a fresh default from explicit opt-out'
```

Expected: compile-time FAIL because `hasPushNotificationsPreference` does not exist.

- [ ] **Step 6: Expose the existing-key check**

Add to `SettingsService` without changing the key or stored value:

```dart
bool get hasPushNotificationsPreference =>
    _prefs.containsKey(_pushNotificationsKey);
```

Re-run the Step 5 command. Expected: PASS.

- [ ] **Step 7: Pin cold-boot reconciliation decisions**

Import `package:safar/core/models/app_settings_model.dart`, keep the existing fresh-disabled test, then add to `app_bootstrap_wiring_test.dart`:

```dart
test(
  'kickInitialNotificationSync reconciles an explicitly disabled user (#1096)',
  () async {
    runInitialNotificationSync(
      const AppSettings(pushNotificationsEnabled: false),
      () => mockNotificationService,
      hasPersistedPushPreference: true,
    );
    await Future<void>.delayed(Duration.zero);

    verify(() => mockNotificationService.removeToken()).called(1);
    verifyNever(
      () => mockNotificationService.initialize(
        handleInitialMessage: any(named: 'handleInitialMessage'),
      ),
    );
  },
);
```

Run:

```bash
flutter test test/core/providers/app_bootstrap_wiring_test.dart --plain-name 'kickInitialNotificationSync reconciles an explicitly disabled user (#1096)'
```

Expected: compile-time FAIL because `hasPersistedPushPreference` does not exist.

- [ ] **Step 8: Wire explicit-disabled cold-boot cleanup**

Implement:

```dart
void kickInitialNotificationSync(
  WidgetRef ref, {
  bool handleInitialMessage = true,
}) {
  runInitialNotificationSync(
    ref.read(settingsProvider),
    () => ref.read(notificationServiceProvider),
    hasPersistedPushPreference: ref
        .read(settingsServiceProvider)
        .hasPushNotificationsPreference,
    handleInitialMessage: handleInitialMessage,
  );
}

void runInitialNotificationSync(
  AppSettings settings,
  NotificationService Function() serviceFactory, {
  bool hasPersistedPushPreference = false,
  bool handleInitialMessage = true,
}) {
  if (!settings.pushNotificationsEnabled && !hasPersistedPushPreference) {
    return;
  }
  unawaited(
    _syncNotifications(settings, serviceFactory(), handleInitialMessage),
  );
}
```

This keeps a fresh absent-key default from resolving `notificationServiceProvider`, while an explicit stored `false` retries the same owner-doc delete on every cold boot until it acknowledges.

- [ ] **Step 9: Verify Task 1**

Run:

```bash
flutter test test/unit/notification_service_test.dart test/unit/notification_service_anon_gate_test.dart test/unit/settings_notifier_test.dart test/core/providers/app_bootstrap_wiring_test.dart
flutter test
flutter analyze
git diff --check
```

Expected: all tests pass; analyze reports `No issues found!`; diff check exits 0. Confirm no forbidden path is changed and no `fcm_tokens` write-map key changed.

- [ ] **Step 10: Commit #1096**

```bash
git add lib/core/services/notification_service.dart lib/core/services/settings_service.dart lib/core/providers/app_bootstrap_provider.dart test/unit/notification_service_test.dart test/unit/settings_notifier_test.dart test/core/providers/app_bootstrap_wiring_test.dart
git commit -m 'fix(notifications): close token refresh opt-out race' -m 'Refs #1096'
```

### Task 2: Issue #1104 — clear delivered notifications before tap teardown

**Files:**
- Modify: `lib/core/services/local_notifier.dart`
- Modify: `lib/core/services/notification_service.dart`
- Modify: `lib/core/providers/app_bootstrap_provider.dart`
- Modify: `test/unit/notification_service_test.dart`
- Modify: `test/unit/notification_service_anon_gate_test.dart`
- Modify: `test/core/providers/app_bootstrap_wiring_test.dart`
- Create: `test/unit/local_notifier_test.dart`

**Interfaces:**
- Produces: `LocalNotifier.clearAll() -> Future<void>`.
- Changes: `NotificationService.removeToken({bool handleInitialMessage = false}) -> Future<void>`.
- Consumes: Task 1's `_cancelDeliverySubscriptions()` and `_cancelTapRoutingSubscription()` boundaries.
- Preserves: auth-recovery callers that omit `handleInitialMessage` never consume or navigate from an initial notification.

- [ ] **Step 1: Write the delivered-notification ordering regression**

Give `_FakeLocalNotifier` an extra `clearAll()` method, a call counter, and an `onClearAll` callback; this compiles before the interface changes. Add:

```dart
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
      () => messaging.requestPermission(alert: true, badge: true, sound: true),
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
```

- [ ] **Step 2: Run the regression and save RED evidence**

Run:

```bash
flutter test test/unit/notification_service_test.dart --plain-name 'removeToken clears delivered notifications before cancelling tap routing (#1104)'
```

Expected: FAIL with `Expected: <1>, Actual: <0>` for `clearAllCalls`. Copy the complete failure into the Task 2 report for the PR body.

- [ ] **Step 3: Write the production-adapter delegation test**

Create `test/unit/local_notifier_test.dart`:

```dart
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:safar/core/services/local_notifier.dart';

class _MockNotificationsPlugin extends Mock
    implements FlutterLocalNotificationsPlugin {}

void main() {
  test('clearAll delegates to the platform notification plugin', () async {
    final plugin = _MockNotificationsPlugin();
    when(plugin.cancelAll).thenAnswer((_) async {});

    await FlutterLocalNotifier(plugin).clearAll();

    verify(plugin.cancelAll).called(1);
  });
}
```

Run `flutter test test/unit/local_notifier_test.dart`. Expected: compile-time FAIL because `clearAll()` does not exist.

- [ ] **Step 4: Add the clear seam and ordered shutdown**

Add to `LocalNotifier` and `FlutterLocalNotifier`:

```dart
Future<void> clearAll();

@override
Future<void> clearAll() => _plugin.cancelAll();
```

Add a no-op override to `_NoopLocalNotifier`. Then evolve `removeToken`:

```dart
Future<void> removeToken({bool handleInitialMessage = false}) async {
  _initialized = false;
  await _cancelDeliverySubscriptions();
  var notificationsCleared = false;
  var tokenRemoved = false;
  try {
    if (handleInitialMessage) {
      _messaging ??= FirebaseMessaging.instance;
      _messageOpenedSubscription ??= _openedMessages.listen(_onMessageTap);
      await _handleInitialMessage();
    }
    try {
      await _localNotifier.clearAll();
      notificationsCleared = true;
    } catch (e) {
      if (kDebugMode) debugPrint('FCM: Notification clear failed: $e');
    }

    final userId = _currentUserId;
    if (userId != null) {
      await _firestore.collection('fcm_tokens').doc(userId).delete();
      tokenRemoved = true;
    }
  } catch (e) {
    if (kDebugMode) debugPrint('FCM: Token removal failed: $e');
  } finally {
    if (notificationsCleared && tokenRemoved) {
      await _cancelTapRoutingSubscription();
    }
    _setStatus(NotificationStatus.off);
  }
}
```

Pass the cold-start arbitration flag only from the settings opt-out path:

```dart
if (!settings.pushNotificationsEnabled) {
  await notificationService.removeToken(
    handleInitialMessage: handleInitialMessage,
  );
  return;
}
```

Update mocktail stubs/verifications in `app_bootstrap_wiring_test.dart` for the named argument. Auth-recovery continues calling `removeToken()` with the default `false` and still gets full teardown when its provider is invalidated/disposed.

- [ ] **Step 5: Add clear-failure coverage**

Configure `_FakeLocalNotifier.clearAll()` to throw and assert that `removeToken()` still deletes `fcm_tokens/{uid}`, sets `NotificationStatus.off`, and leaves `opened.hasListener == true` so an uncleared notification remains routeable. Add the symmetric delete-failure case: after a successful clear but a thrown Firestore delete, status is off and the opened listener remains alive because the server can still deliver against the surviving token document. These tests must pass without changing either production error to a success.

- [ ] **Step 6: Add disabled cold-start tap coverage**

Construct an uninitialized `NotificationService` with an `initialMessage` carrying a known route, call `removeToken(handleInitialMessage: true)`, and assert navigation happens once without `requestPermission()` or `getToken()`. Add a companion `handleInitialMessage: false` assertion so a higher-priority invite deep link remains authoritative.

- [ ] **Step 7: Verify Task 2**

Run:

```bash
flutter test test/unit/local_notifier_test.dart test/unit/notification_service_test.dart test/unit/notification_service_anon_gate_test.dart test/core/providers/app_bootstrap_wiring_test.dart
flutter test
flutter analyze
git diff --check
```

Expected: all tests pass; analyze reports `No issues found!`; diff check exits 0. Confirm `security/firestore.rules`, `functions/**`, and `**/models/**.dart` are untouched.

- [ ] **Step 8: Commit #1104 and both closing lines**

```bash
git add lib/core/services/local_notifier.dart lib/core/services/notification_service.dart lib/core/providers/app_bootstrap_provider.dart test/unit/local_notifier_test.dart test/unit/notification_service_test.dart test/unit/notification_service_anon_gate_test.dart test/core/providers/app_bootstrap_wiring_test.dart
git commit -m 'fix(notifications): clear delivered pushes on opt-out' -m 'Closes #1096' -m 'Closes #1104'
```

### Task 3: Whole-branch review and PR

**Files:**
- Review: every file in `origin/main...HEAD`
- Create remotely: one GitHub pull request

**Interfaces:**
- Consumes: Task 1 and Task 2 commits plus both saved RED outputs.
- Produces: one reviewable PR from `fix/1096-1104-notification-lifecycle`.

- [ ] **Step 1: Review scope and requirements**

Run:

```bash
git diff --name-only origin/main...HEAD
git diff --check origin/main...HEAD
git log --format=fuller origin/main..HEAD
git diff --stat origin/main...HEAD
```

Expected: only the plan and files listed above; no forbidden path; two issue commits; final commit body includes both closing lines.

- [ ] **Step 2: Request whole-branch code review**

Package `origin/main...HEAD` and dispatch an independent reviewer against this plan and the delegation brief. Resolve every Critical/Important finding and re-run the covering tests before re-review.

- [ ] **Step 3: Run fresh final verification**

Run:

```bash
flutter test
flutter analyze
git diff --check origin/main...HEAD
git status --short
```

Expected: 0 test failures, 0 analyze issues, no whitespace errors, clean worktree.

- [ ] **Step 4: Push and create the PR**

```bash
git push -u origin fix/1096-1104-notification-lifecycle
gh pr create --base main --head fix/1096-1104-notification-lifecycle
```

The PR body must contain: a concise summary; `Closes #1096` and `Closes #1104`; exact test commands/results; verbatim RED output for each issue; confirmation that the existing `fcm_tokens/{uid}` map/path is unchanged; and the verified owner-only rules references without claiming `FakeFirebaseFirestore` enforces them.
