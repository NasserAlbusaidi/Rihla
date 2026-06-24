# Issue 667 Event Offline Write Acks Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix event settings update/delete flows so an offline Firestore write that is accepted locally does not leave the UI waiting forever for server acknowledgement.

**Architecture:** Keep `EventService.updateEvent` and `EventService.deleteEvent` as the write-boundary methods that return Firestore ack futures. Change the two UI callers to race those futures with `awaitServerAck`, mirroring the existing expense-edit and create-event `#412` pattern, then mark queued writes through `ConnectivityNotifier.noteQueuedWrite()`. Add widget regressions that model offline Firestore with never-completing service futures. Current Flutter analyzer also requires a syntax-only cleanup in `GroupService.stageGroup`: keep the group-create write map's existing omit-when-null `glyph`/`inkIndex` contract, but express it with null-aware map entries so `flutter analyze` stays clean.

**Tech Stack:** Flutter, Riverpod, GoRouter, mocktail, `awaitServerAck` from `lib/core/utils/write_ack.dart`, `ConnectivityNotifier` from `lib/core/providers/connectivity_provider.dart`.

---

## Live Code Verification

- Issue: `#667 fix(events): event update/delete await raw Firestore update() - offline UI hangs`.
- `lib/features/events/services/event_service.dart:180-200` soft-deletes events by awaiting the raw Firestore `.update()` future.
- `lib/features/events/services/event_service.dart:206-242` metadata updates await the raw Firestore `.update()` future.
- `lib/features/events/widgets/event_info_section.dart:97-138` sets `_isSaving`, awaits `updateEvent`, then shows `eventUpdated` and clears `_isSaving`; offline, the await never returns.
- `lib/features/events/widgets/event_danger_section.dart:251-257` awaits `deleteEvent`, then routes to `/group/$groupId`; offline, navigation never happens.
- Existing correct pattern:
  - `lib/features/events/screens/create_event_screen.dart:146-180` reads connectivity, calls `stageEvent`, awaits `awaitServerAck(..., skipWait: connectivityStatus != ConnectivityStatus.online)`, then calls `noteLocalWrite()` or `noteQueuedWrite()`.
  - `lib/features/ledger/screens/edit_expense_screen.dart:125-181` applies the same bounded-ack pattern to expense update.
  - `lib/features/ledger/screens/edit_expense_screen.dart:246-268` applies it to expense delete.
- `lib/core/utils/write_ack.dart:30-59` returns `WriteAck.queued` on timeout or `skipWait`, while early errors still propagate.
- `lib/core/providers/connectivity_provider.dart:133-148` defines `noteLocalWrite()` and `noteQueuedWrite()`.
- `lib/features/groups/providers/group_provider.dart:217-237` creates `groups/{groupId}` with optional `glyph` and `inkIndex`; analyzer flags the old collection-`if` null checks, but the required persisted contract is still key omission when the value is null.
- `security/firestore.rules:268-304` `validGroupCreate` allow-lists optional `glyph` and `inkIndex`, and accepts them only when absent or valid; explicit null is not valid.
- `lib/features/groups/models/group_model.dart:61-78` `Group.fromDoc` reads absent or wrong-typed `glyph`/`inkIndex` as null.

## Spec Verification Rubric

1. Callsite classification:
   - OUTBOUND: `EventInfoSection._save` feeds `EventService.updateEvent`, which writes `groups/{groupId}/events/{eventId}`.
   - OUTBOUND: `EventDangerSection._executeDelete` feeds `EventService.deleteEvent`, which writes `groups/{groupId}/events/{eventId}`.
   - OUTBOUND but unchanged: `EventDangerSection._executeDelete` also calls `GroupActivityService.logGroupEvent` fire-and-forget before delete; this plan does not await or change that activity write.
   - OUTBOUND syntax-only cleanup: `GroupService.stageGroup` feeds `batch.set(db.collection('groups').doc(groupId), {...})`. The write-map contract remains omit `glyph`/`inkIndex` when null; no new key, value, fallback, or explicit-null behavior is introduced.
   - INBOUND: `EventSettingsScreen` reads `eventDetailProvider`; `EventService.watchEvent` reads the same event doc and returns null when `isDeleted` is true; `EventService.watchGroupEvents` reads non-deleted event docs.
   - INBOUND for group stamp fields: `Group.fromDoc` reads `glyph` and `inkIndex`; absent values remain null.
2. Concrete claims checked against code:
   - `EventService.updateEvent` signature is `Future<void> updateEvent({required String groupId, required String eventId, String? name, DateTime? startDate, DateTime? endDate, String? description})`.
   - `EventService.deleteEvent` signature is `Future<void> deleteEvent({required String groupId, required String eventId})`.
   - Event save button key is `EventKeys.saveChangesButton`.
   - Delete tile/dialog/confirm keys are `EventKeys.deleteEventTile`, `EventKeys.deleteEventDialog`, and `EventKeys.deleteEventConfirmButton`.
   - `GroupService.stageGroup` accepts `String? glyph` and `int? inkIndex`, and writes group docs through the inline map at `group_provider.dart:217-237`.
3. Read-path per write-path:
   - Update write is consumed by `eventDetailProvider -> EventService.watchEvent -> Event.fromDoc`, then rendered by `EventSettingsScreen` and other event screens.
   - Delete write is consumed by `EventService.watchEvent`, which returns null for `event.isDeleted`, and `EventService.watchGroupEvents`, which queries `isDeleted == false`.
   - Group-create stamp fields are consumed by `userGroupsProvider -> GroupService.watchUserGroups -> Group.fromDoc` and by `GroupService.watchGroup -> Group.fromDoc`; absence stays null.
4. Event fields enumerated from `Event`:
   - `id`, `name`, `type`, `groupId`, `createdBy`, `participantIds`, `participantNames`, `modules`, `startDate`, `endDate`, `isDeleted`, `deletedAt`, `createdAt`, `updatedAt`, `description`.
   - This plan does not add, remove, migrate, or reinterpret any field.
5. Data contracts:
   - `updateEvent` continues to write only `updatedAt` plus non-null optional keys among `name`, `startDate`, `endDate`, and `description`.
   - `deleteEvent` continues to write `isDeleted: true`, `deletedAt: FieldValue.serverTimestamp()`, and `updatedAt: FieldValue.serverTimestamp()`.
   - UI callers change how long they wait for the ack; they do not change persisted maps.
   - `stageGroup` continues to write exactly these group-create keys: `id`, `name`, `inviteCode`, `createdBy`, `memberIds`, `currency`, `isDeleted`, `deletedAt`, optional `glyph`, optional `inkIndex`, `createdAt`, `updatedAt`.
   - The analyzer cleanup changes only Dart map syntax from `if (glyph != null) 'glyph': glyph` / `if (inkIndex != null) 'inkIndex': inkIndex` to `'glyph': ?glyph` / `'inkIndex': ?inkIndex`; both forms omit the key when the value is null and include the non-null value unchanged.
6. Arithmetic decomposition:
   - No arithmetic or money aggregation is changed.
7. Orthogonal adversarial pass:
   - Online permission/validation failures must still surface through existing catch blocks because `awaitServerAck` propagates errors raised before timeout when `connectivityStatus == ConnectivityStatus.online`.
   - Known-offline writes use `skipWait: true`, so their failures are observed through `awaitServerAck` late-error logging instead of inline UI catch blocks; this is the same optimistic queued-write contract used by the existing create/edit flows.
   - Activity logging failure must still not block delete routing because the existing try/catch around `logGroupEvent` remains unchanged.
   - Group-create rules compatibility is preserved because absent optional stamp keys are still absent and non-null stamp values are still validated by `validGlyph` / `validInkIndex`.
   - No route tree, path, event schema, money, rules, or Cloud Functions behavior is changed.

## Files

- Create: `test/features/events/event_settings_offline_412_test.dart`
  - Widget regression tests for event update/delete offline behavior using never-completing mocked service futures.
- Modify: `test/features/events/event_settings_screen_test.dart`
  - Add timer-free `connectivityProvider` overrides to existing event settings save/delete harnesses, because the production widgets will now read connectivity.
- Modify: `lib/features/events/widgets/event_info_section.dart`
  - Import connectivity/write-ack helpers and race `updateEvent` against `awaitServerAck`.
- Modify: `lib/features/events/widgets/event_danger_section.dart`
  - Import connectivity/write-ack helpers and race `deleteEvent` against `awaitServerAck`.
- Modify: `lib/features/groups/providers/group_provider.dart`
  - Keep the existing group-create `glyph`/`inkIndex` omit-when-null contract while updating the map entries to the analyzer-required null-aware syntax.

## Task 1: Write Failing Event Settings Offline Tests

**Files:**
- Create: `test/features/events/event_settings_offline_412_test.dart`

- [x] **Step 1: Add the regression test file**

Create `test/features/events/event_settings_offline_412_test.dart` with:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safar/core/providers/connectivity_provider.dart';
import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/events/keys/event_keys.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/events/services/event_service.dart';
import 'package:safar/features/events/widgets/event_danger_section.dart';
import 'package:safar/features/events/widgets/event_info_section.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/services/group_activity_service.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

class _MockEventService extends Mock implements EventService {}

class _MockGroupActivityService extends Mock implements GroupActivityService {}

void main() {
  setUpAll(() {
    registerFallbackValue(DateTime(2026, 1, 1));
  });

  testWidgets(
    '#667: offline event settings save releases spinner and marks queued',
    (tester) async {
      final service = _MockEventService();
      final connectivity = ConnectivityNotifier(startPeriodicChecks: false)
        ..setOffline();
      late ProviderContainer container;

      when(
        () => service.updateEvent(
          groupId: 'group-1',
          eventId: 'event-1',
          name: 'Updated Event',
          startDate: null,
          endDate: null,
          description: null,
        ),
      ).thenAnswer((_) => Completer<void>().future);

      await tester.pumpWidget(
        _wrapInfoSection(
          eventService: service,
          connectivity: connectivity,
          onContainer: (c) => container = c,
        ),
      );
      await tester.pump();

      await tester.enterText(find.byType(TextField).first, 'Updated Event');
      await tester.tap(find.byKey(EventKeys.saveChangesButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      expect(find.text('Event updated'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Save Changes'), findsOneWidget);
      expect(container.read(connectivityProvider), ConnectivityStatus.syncing);
      verify(
        () => service.updateEvent(
          groupId: 'group-1',
          eventId: 'event-1',
          name: 'Updated Event',
          startDate: null,
          endDate: null,
          description: null,
        ),
      ).called(1);
    },
  );

  testWidgets(
    '#667: offline event delete routes back and marks queued',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'settings_device_name': 'Test User',
      });
      final prefs = await SharedPreferences.getInstance();
      final service = _MockEventService();
      final activityService = _MockGroupActivityService();
      final connectivity = ConnectivityNotifier(startPeriodicChecks: false)
        ..setOffline();
      late ProviderContainer container;

      when(
        () => activityService.logGroupEvent(
          groupId: any(named: 'groupId'),
          type: any(named: 'type'),
          actorId: any(named: 'actorId'),
          actorName: any(named: 'actorName'),
          description: any(named: 'description'),
          metadata: any(named: 'metadata'),
        ),
      ).thenReturn(null);
      when(
        () => service.deleteEvent(groupId: 'group-1', eventId: 'event-1'),
      ).thenAnswer((_) => Completer<void>().future);

      await tester.pumpWidget(
        _wrapDangerSection(
          prefs: prefs,
          eventService: service,
          activityService: activityService,
          connectivity: connectivity,
          onContainer: (c) => container = c,
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(EventKeys.deleteEventTile));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.tap(find.byKey(EventKeys.deleteEventConfirmButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      expect(find.text('Group:group-1'), findsOneWidget);
      expect(container.read(connectivityProvider), ConnectivityStatus.syncing);
      verify(
        () => service.deleteEvent(groupId: 'group-1', eventId: 'event-1'),
      ).called(1);
    },
  );
}

Widget _wrapInfoSection({
  required EventService eventService,
  required ConnectivityNotifier connectivity,
  required void Function(ProviderContainer) onContainer,
}) {
  return ProviderScope(
    overrides: [
      eventServiceProvider.overrideWithValue(eventService),
      connectivityProvider.overrideWith((ref) => connectivity),
    ],
    child: Builder(
      builder: (context) {
        return MaterialApp(
          theme: AppTheme.lightTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                onContainer(ProviderScope.containerOf(context));
              });
              return Scaffold(body: EventInfoSection(event: _event()));
            },
          ),
        );
      },
    ),
  );
}

Widget _wrapDangerSection({
  required SharedPreferences prefs,
  required EventService eventService,
  required GroupActivityService activityService,
  required ConnectivityNotifier connectivity,
  required void Function(ProviderContainer) onContainer,
}) {
  final event = _event();
  final router = GoRouter(
    initialLocation: '/danger',
    routes: [
      GoRoute(
        path: '/danger',
        builder: (_, _) => Builder(
          builder: (context) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              onContainer(ProviderScope.containerOf(context));
            });
            return Scaffold(
              body: EventDangerSection(
                groupId: event.groupId,
                eventId: event.id,
                event: event,
                isAdmin: true,
              ),
            );
          },
        ),
      ),
      GoRoute(
        path: '/group/:gid',
        builder: (_, state) =>
            Scaffold(body: Text('Group:${state.pathParameters['gid']}')),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      eventServiceProvider.overrideWithValue(eventService),
      groupActivityServiceProvider.overrideWithValue(activityService),
      connectivityProvider.overrideWith((ref) => connectivity),
      currentUserIdProvider.overrideWithValue('uid-creator'),
      eventExpensesProvider(
        (groupId: event.groupId, eventId: event.id),
      ).overrideWith((ref) => Stream.value(const [])),
      eventSettlementsProvider(
        (groupId: event.groupId, eventId: event.id),
      ).overrideWith((ref) => Stream.value(const [])),
    ],
    child: MaterialApp.router(
      theme: AppTheme.lightTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    ),
  );
}

Event _event() {
  return Event(
    id: 'event-1',
    name: 'Original Event',
    type: EventType.trip,
    groupId: 'group-1',
    createdBy: 'uid-creator',
    participantIds: const ['uid-creator'],
    participantNames: const {'uid-creator': 'Creator'},
    modules: const EventModules(),
    createdAt: DateTime(2026, 6, 24),
  );
}
```

- [x] **Step 2: Run the focused RED command**

Run:

```bash
flutter test test/features/events/event_settings_offline_412_test.dart
```

Expected: FAIL. The save test should not find `Event updated`, and/or the delete test should not find `Group:group-1`, because the current code awaits never-completing service futures.

## Task 2: Prepare Existing Event Settings Tests For Connectivity Reads

**Files:**
- Modify: `test/features/events/event_settings_screen_test.dart`

- [x] **Step 1: Import the connectivity provider**

Add:

```dart
import 'package:safar/core/providers/connectivity_provider.dart';
```

- [x] **Step 2: Add timer-free connectivity to `_wrapSettings`**

Inside the nested `ProviderScope(overrides: [...])` in `_wrapSettings`, add:

```dart
                    connectivityProvider.overrideWith(
                      (ref) => ConnectivityNotifier(startPeriodicChecks: false),
                    ),
```

- [x] **Step 3: Add timer-free connectivity to `_wrapDangerSection`**

Inside the top-level `ProviderScope(overrides: [...])` in `_wrapDangerSection`, add:

```dart
      connectivityProvider.overrideWith(
        (ref) => ConnectivityNotifier(startPeriodicChecks: false),
      ),
```

- [x] **Step 4: Add timer-free connectivity to the bespoke save-button route test**

Inside the bespoke `ProviderScope(overrides: [...])` in the `Save Changes button calls updateEvent on tap` test, add:

```dart
                        connectivityProvider.overrideWith(
                          (ref) => ConnectivityNotifier(startPeriodicChecks: false),
                        ),
```

## Task 3: Implement Bounded Ack Handling In Event Settings Widgets

**Files:**
- Modify: `lib/features/events/widgets/event_info_section.dart`
- Modify: `lib/features/events/widgets/event_danger_section.dart`

- [x] **Step 1: Update `EventInfoSection` imports**

Add imports:

```dart
import '../../../core/providers/connectivity_provider.dart';
import '../../../core/utils/write_ack.dart';
```

- [x] **Step 2: Race event metadata saves against server ack**

Replace the raw `await ref.read(eventServiceProvider).updateEvent(...)` block in `_save` with:

```dart
      final connectivity = ref.read(connectivityProvider.notifier);
      final connectivityStatus = ref.read(connectivityProvider);
      final outcome = await awaitServerAck(
        ref
            .read(eventServiceProvider)
            .updateEvent(
              groupId: widget.event.groupId,
              eventId: widget.event.id,
              name: name != widget.event.name ? name : null,
              startDate: _startDate,
              endDate: _endDate,
              description: description.isNotEmpty ? description : null,
            ),
        skipWait: connectivityStatus != ConnectivityStatus.online,
      );
      if (outcome == WriteAck.acked) {
        connectivity.noteLocalWrite();
      } else {
        connectivity.noteQueuedWrite();
      }
```

- [x] **Step 3: Update `EventDangerSection` imports**

Add imports:

```dart
import '../../../core/providers/connectivity_provider.dart';
import '../../../core/utils/write_ack.dart';
```

- [x] **Step 4: Race event deletes against server ack**

Replace the raw delete await in `_executeDelete` with:

```dart
      final connectivity = ref.read(connectivityProvider.notifier);
      final connectivityStatus = ref.read(connectivityProvider);
      final outcome = await awaitServerAck(
        ref
            .read(eventServiceProvider)
            .deleteEvent(groupId: groupId, eventId: eventId),
        skipWait: connectivityStatus != ConnectivityStatus.online,
      );
      if (outcome == WriteAck.acked) {
        connectivity.noteLocalWrite();
      } else {
        connectivity.noteQueuedWrite();
      }
```

- [x] **Step 5: Run the focused GREEN command**

Run:

```bash
flutter test test/features/events/event_settings_offline_412_test.dart
```

Expected: PASS.

## Task 4: Run Regression And Safety Verification

**Files:**
- No additional file edits.

- [x] **Step 1: Run neighboring event settings tests**

Run:

```bash
flutter test test/features/events/event_settings_screen_test.dart
```

Expected: PASS.

- [x] **Step 2: Run existing #412 write-ack tests**

Run:

```bash
flutter test test/core/utils/write_ack_test.dart test/core/providers/connectivity_provider_test.dart test/features/events/create_event_test.dart test/features/ledger/edit_expense_offline_412_test.dart
```

Expected: PASS.

- [x] **Step 3: Run analyzer**

Run:

```bash
flutter analyze
```

Expected: no issues.

- [x] **Step 4: Run theme purity check for changed widgets**

Run:

```bash
bash tool/check_theme_purity.sh
```

Expected: PASS.

- [x] **Step 5: Run the full Flutter suite**

Run:

```bash
flutter test
```

Expected: PASS.
