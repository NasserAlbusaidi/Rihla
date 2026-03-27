# Phase 12: Expense & Logistics Provider Rewiring - Research

**Researched:** 2026-03-28
**Domain:** Flutter/Riverpod — provider substitution and Firestore write wiring
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** Use `Event.currency` directly — no group fallback. Event already has a `currency` field (defaults to `'OMR'`). Replace `userTripsProvider` lookup with `widget.event.currency` (or equivalent).
- **D-02:** Fix both `add_expense_screen.dart` and `edit_expense_sheet.dart` — both have identical `_tripCurrency` bugs reading from dead `userTripsProvider`.
- **D-03:** Derive `isLeader` from `event.createdBy == currentUser?.uid` — replaces `trip?.leaderId == currentUser?.uid` via `userTripsProvider`. Fix in both `split_scope_selector.dart` (`_PayerSelector`) and `edit_expense_sheet.dart`.
- **D-04:** Wire all 6 debugPrint stubs in `logistics_screen.dart` to `SubGroupService` methods: removeMember (line 158), addMember via onDrop (line 165), addMember via member picker (line 320), deleteSubGroup (line 361), updateSubGroup / rename (line 482), createSubGroup (line 489).
- **D-05:** Pass capacity value from create dialog to `SubGroupService.createSubGroup()` — stop discarding the captured value (`final _ = ...`).
- **D-06:** Follow Phase 11 gear pattern: snackbar on write failure, no retry button, auto-dismiss. Apply to all logistics write operations.
- **D-07:** Payer/currency fixes are read-path changes — no error handling needed there.
- **D-08:** Delete `userTripsProvider` in this phase after all consumers are rewired. Dead code should not survive to Phase 13.

### Claude's Discretion

- Exact snackbar wording and duration for logistics errors
- How to structure try/catch in logistics screen methods
- Whether to extract a helper for eventRef construction in logistics screen
- Test structure and organization
- Implementation of `SubGroupService.updateSubGroup()` — follow existing service method patterns

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope

</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| FIN-01 | Per-event balance shows what each member owes/is owed within that event | Payer-override dropdown depends on isLeader; isLeader currently broken because it reads from dead `userTripsProvider`. Fix enables payer selection which enables correct per-event balance attribution. |
| EVT-08 | Existing trip functionality (ledger, gear, logistics, vault, activity, memories) works within events | Currency derivation and logistics write mutations are the remaining broken pieces. Phase 12 closes them. |

</phase_requirements>

---

## Summary

Phase 12 is a surgical wiring phase: three independent breakages, all caused by the same root cause — stale references to `userTripsProvider` and its Trip-based `leaderId`/`currency` data — need to be replaced with direct access to Event fields and SubGroupService calls.

The `userTripsProvider` reads from SQLite via `CacheService.getCachedTrips()`. After the Supabase removal in Phase 7, that table is never populated for new events. Any `.firstWhere(t => t.id == eventId)` call against it returns null, which causes `_tripCurrency` to fall back to 'OMR' unconditionally and `isLeader` to evaluate false unconditionally. Both bugs are read-path only — no async calls, no error handling needed to fix them.

The logistics stubs are write-path: six `debugPrint` comments left from Phase 4 when SubGroupService was upgraded to require `EventRef` but the screen was not yet updated. `SubGroupService` already has 4 of the 5 needed methods (`createSubGroup`, `addMember`, `removeMember`, `deleteSubGroup`). Only `updateSubGroup` needs to be created. The snackbar error pattern from Phase 11 (`gear_screen.dart`) is the exact reference implementation to follow.

**Primary recommendation:** Three isolated fix areas, each under 30 lines of change. Implement as three separate plans in sequence: (1) currency fix, (2) isLeader fix, (3) logistics wire-up + updateSubGroup + userTripsProvider deletion.

---

## Standard Stack

No new dependencies. All changes use existing in-repo code.

### Existing Assets in Use

| Asset | Location | Role in This Phase |
|-------|----------|--------------------|
| `Event.currency` | `lib/features/events/models/event_model.dart:165` | Direct replacement for `_tripCurrency` getter |
| `Event.createdBy` | `lib/features/events/models/event_model.dart:159` | Used to derive `isLeader` |
| `currentUserProvider` | `lib/features/auth/providers/auth_provider.dart` | Provides Firebase UID for `isLeader` comparison |
| `SubGroupService` | `lib/features/logistics/services/sub_group_service.dart` | 4 existing write methods + new `updateSubGroup` |
| `subGroupServiceProvider` | `lib/features/logistics/providers/sub_group_provider.dart:18` | Provider for SubGroupService instance |
| `eventRef` record | `logistics_screen.dart:52` | Already constructed, available throughout screen |
| Phase 11 snackbar pattern | `gear_screen.dart:576-637` | Try/catch + `ScaffoldMessenger.showSnackBar` reference |

---

## Architecture Patterns

### Pattern 1: Currency Fix — Direct Field Access

**What:** Replace `_tripCurrency` getter (which reads from dead `userTripsProvider`) with direct access to `event.currency` or `widget.event.currency`.

**Files affected:** `add_expense_screen.dart` (lines 63-75), `edit_expense_sheet.dart` (lines 51-58)

**Before:**
```dart
// lib/features/ledger/screens/add_expense_screen.dart (lines 63-75)
String get _tripCurrency {
  final trips = ref.read(userTripsProvider).valueOrNull;
  if (trips == null) return 'OMR';
  final trip = trips.cast<Trip?>().firstWhere(
    (t) => t!.id == widget.eventId,
    orElse: () => null,
  );
  return trip?.currency ?? 'OMR';
}
```

**After (`add_expense_screen.dart`):**
The screen already watches `eventAsync` (line 302-304 in `build()`). However, `_tripCurrency` is a getter used in `_onKeyPress` and `_showSuccessDialog` — places that run outside `build()`. The simplest fix is to make `_tripCurrency` read from the event directly. Since `add_expense_screen.dart` already watches `eventDetailProvider`, the most direct approach is to store the event in state or derive currency at build time.

**Simplest approach:** Replace the getter with a stored field that gets populated from the event or falls back inline:
```dart
// add_expense_screen.dart — replace _tripCurrency getter
String get _tripCurrency {
  // Event is passed via eventDetailProvider watched in build().
  // For non-build callsites (_onKeyPress, _showSuccessDialog),
  // read the provider directly.
  final event = ref.read(
    eventDetailProvider((groupId: widget.groupId, eventId: widget.eventId)),
  ).valueOrNull;
  return event?.currency ?? 'OMR';
}
```

**After (`edit_expense_sheet.dart`):** Same approach. The sheet has `widget.groupId`, `widget.eventId` available. No provider is currently watched for the event — add a direct `ref.read(eventDetailProvider(...))` in the getter, or pass the Event as a constructor parameter. Per D-01, use `widget.event.currency` if the event is available on the widget; if not, `ref.read(eventDetailProvider(...)).valueOrNull?.currency ?? 'OMR'`.

**Note on `add_expense_screen.dart` line 179:** There is a secondary `userTripsProvider` reference in the `_submit()` method inside a debug branch (`if (currentParticipant == null)`). This is diagnostic logging. It should also be removed/replaced with a comment when the import is deleted per D-08.

**Confidence:** HIGH — `Event.currency` is a non-nullable `String` field (defaults to `'OMR'`) confirmed at `event_model.dart:165,182`.

### Pattern 2: isLeader Fix — createdBy Comparison

**What:** Replace `trip?.leaderId == currentUser?.uid` with `event.createdBy == currentUser?.uid`.

**Files affected:**
- `split_scope_selector.dart` — `_PayerSelector.build()` (lines 381-394)
- `edit_expense_sheet.dart` — `_buildPayerSelector()` (lines 356-361)

**Before (`split_scope_selector.dart`, lines 381-394):**
```dart
final trip = ref
    .watch(userTripsProvider)
    .valueOrNull
    ?.cast<Trip?>()
    .firstWhere(
      (t) => t!.id == event.id,
      orElse: () => null,
    );
final isLeader = trip?.leaderId == ref.watch(currentUserProvider)?.uid;
```

**After:**
```dart
final currentUid = ref.watch(currentUserProvider)?.uid;
final isLeader = currentUid != null && event.createdBy == currentUid;
```

The `event` object is already a constructor parameter on `_PayerSelector`. No additional provider fetch needed.

**Before (`edit_expense_sheet.dart`, lines 356-361):**
```dart
final trips = ref.watch(userTripsProvider).valueOrNull;
final trip = trips?.cast<Trip?>().firstWhere(
  (t) => t!.id == widget.eventId,
  orElse: () => null,
);
final isLeader = trip?.leaderId == ref.watch(currentUserProvider)?.uid;
```

**After:** `edit_expense_sheet.dart` has `widget.groupId` and `widget.eventId` but NOT a `widget.event` parameter currently. Two options:
- Option A: Watch `eventDetailProvider` inside `_buildPayerSelector()` (introduces async dependency)
- Option B: Add an `Event event` constructor parameter to `EditExpenseSheet`

Per the existing code at line 367-372, `_buildPayerSelector()` already calls `ref.watch(eventDetailProvider(...))` to get the event for participant lookup. So the event is already fetched inside that method — `isLeader` can be derived from it:

```dart
// Already in _buildPayerSelector()
final eventAsync = ref.watch(eventDetailProvider(
  (groupId: widget.groupId, eventId: widget.eventId),
));
final event = eventAsync.valueOrNull;
if (event == null) return const SizedBox.shrink();
// Replace trip?.leaderId check with:
final currentUid = ref.watch(currentUserProvider)?.uid;
final isLeader = currentUid != null && event.createdBy == currentUid;
```

**Confidence:** HIGH — `Event.createdBy` confirmed non-nullable at `event_model.dart:159`.

### Pattern 3: Logistics Write Wiring — Phase 11 Snackbar Pattern

**What:** Replace 6 `debugPrint` stubs with `SubGroupService` calls wrapped in try/catch with failure snackbar.

**Reference pattern (from `gear_screen.dart:580-594`):**
```dart
HapticService.selection();
try {
  await ref.read(gearServiceProvider).updateGearItem(
    groupId: widget.event.groupId,
    eventId: widget.event.id,
    gearItemId: item.id,
    isHighPriority: !item.isHighPriority,
  );
} catch (e) {
  if (mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Couldn't update priority — try again")),
    );
  }
}
```

**The 6 logistics wiring points:**

**1. removeMember (logistics_screen.dart line 158):**
```dart
// SubgroupCard passes (SubGroupMember member, SubGroup group) to onRemoveMember
onRemoveMember: (member, group) async {
  final eventRef = (groupId: widget.event.groupId, eventId: widget.event.id);
  try {
    await ref.read(subGroupServiceProvider).removeMember(
      groupId: eventRef.groupId,
      eventId: eventRef.eventId,
      subGroupId: group.id,
      memberId: member.id,  // SubGroupMember.id is the Firestore doc ID
    );
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't remove member — try again")),
      );
    }
  }
},
```

**Key insight on `memberId`:** `SubGroupMember.id` is the Firestore document ID in the `members` subcollection. The `removeMember` call deletes that document by ID. This ID comes from `SubGroupMember.fromFirestore` — it's stored in the `id` field on the map. Confirmed in `sub_group_service.dart:70` where `memberId = const Uuid().v4()` is used as both the doc ID and the stored `id` field during `addMember`.

**2. addMember via onDrop (logistics_screen.dart line 165):**
```dart
// SubgroupCard.onDrop passes a Participant
onDrop: (participant) async {
  try {
    await ref.read(subGroupServiceProvider).addMember(
      groupId: widget.event.groupId,
      eventId: widget.event.id,
      subGroupId: group.id,
      participantId: participant.id,
      displayName: participant.displayName ?? '',
    );
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't add member — try again")),
      );
    }
  }
},
```

**3. addMember via member picker (logistics_screen.dart line 320):**
The picker's `onTap` runs inside a `Consumer` widget, making `context.mounted` not directly available. The fix: pop the bottom sheet first, then call the service from the outer screen state (pass a callback), OR perform the write inside the Consumer and close the sheet regardless. The simpler approach — close the sheet, then write from a method on `_LogisticsScreenState` — avoids passing context into the Consumer.

Alternatively, call the service in the tap handler and close the sheet:
```dart
onTap: () async {
  HapticService.lightClick();
  Navigator.pop(context);  // close sheet first
  try {
    await ref.read(subGroupServiceProvider).addMember(
      groupId: widget.event.groupId,
      eventId: widget.event.id,
      subGroupId: group.id,
      participantId: p.id,
      displayName: p.displayName ?? '',
    );
  } catch (e) {
    // Use ScaffoldMessenger root messenger — inner sheet context is gone
    // Use the outer context stored before opening the sheet.
  }
},
```
The cleanest approach is to pass an `addMember` callback to `_showMemberPicker` from `_LogisticsScreenState`, letting the Consumer call back into the screen's state method where mounted/context are valid.

**4. deleteSubGroup (logistics_screen.dart line 361):**
```dart
onPressed: () async {
  Navigator.pop(context);
  try {
    await ref.read(subGroupServiceProvider).deleteSubGroup(
      groupId: widget.event.groupId,
      eventId: widget.event.id,
      subGroupId: group.id,
    );
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't delete group — try again")),
      );
    }
  }
},
```

**5. updateSubGroup / rename (logistics_screen.dart line 482):**
Requires new `SubGroupService.updateSubGroup()` method (see Pattern 4 below).

**6. createSubGroup (logistics_screen.dart line 489):**
```dart
} else {
  final capacity = int.tryParse(_capacityController.text) ?? 4;
  Navigator.pop(context);
  try {
    await ref.read(subGroupServiceProvider).createSubGroup(
      groupId: widget.event.groupId,
      eventId: widget.event.id,
      name: name,
      type: type.value,
      capacity: capacity,
    );
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't create group — try again")),
      );
    }
  }
}
```
Note: The `final _ = int.tryParse(_capacityController.text) ?? 4` on line 472-473 intentionally discards the value today. Per D-05, assign it and pass to `createSubGroup`.

### Pattern 4: New SubGroupService.updateSubGroup()

**What:** Add a method to update name and/or capacity on an existing sub-group document.

**Follow the pattern of `deleteSubGroup`:**
```dart
/// Update a sub-group's name and/or capacity.
Future<void> updateSubGroup({
  required String groupId,
  required String eventId,
  required String subGroupId,
  String? name,
  int? capacity,
}) async {
  final updates = <String, dynamic>{};
  if (name != null) updates['name'] = name;
  if (capacity != null) updates['capacity'] = capacity;
  if (updates.isEmpty) return;
  try {
    await eventSubcollection(groupId, eventId, 'sub_groups')
        .doc(subGroupId)
        .update(updates);
  } on FirebaseException catch (e) {
    debugPrint('SubGroupService.updateSubGroup failed: ${e.code} ${e.message}');
    rethrow;
  }
}
```

**Confidence:** HIGH — `eventSubcollection` helper and `FirebaseException` catch pattern confirmed from existing service methods.

### Pattern 5: Deleting userTripsProvider (D-08)

**What:** Remove `userTripsProvider` definition from `trip_provider.dart` and all import references.

**All current consumers (confirmed by grep):**
1. `lib/features/ledger/widgets/split_scope_selector.dart` — import + usage at line 382
2. `lib/features/ledger/screens/edit_expense_sheet.dart` — import + usage at lines 52, 356
3. `lib/features/ledger/screens/add_expense_screen.dart` — import + usage at lines 64, 179
4. `lib/features/trip/providers/trip_provider.dart:28` — definition site

After Phase 12 fixes, all three consumers will no longer use `userTripsProvider`. The import of `trip_provider.dart` in each file may still be needed if other providers from that file are used:
- `add_expense_screen.dart` uses `currentParticipantProvider` (in `trip_provider.dart`) — keep import, only remove `userTripsProvider` usage
- `edit_expense_sheet.dart` uses `currentParticipantProvider` — keep import
- `split_scope_selector.dart` uses `currentParticipantProvider` via `auth_provider.dart`, and imports `trip_provider.dart` explicitly — check if any other symbol from that file is used; if only `userTripsProvider` and `Trip` type are used, the import can be removed

**Check:** `split_scope_selector.dart` also imports `trip_model.dart` (line 9). The `Trip` type is only referenced in the dead `userTripsProvider` lookup (removed by this phase). Both imports (`trip_provider.dart` and `trip_model.dart`) can be deleted from `split_scope_selector.dart`.

**Definition deletion:** Remove `userTripsProvider` from `trip_provider.dart` (lines 26-30). The import `CacheService` at the top of `trip_provider.dart` is also used by `tripLogisticsParticipantsProvider` (line 36) — keep `CacheService` import unless that provider is also deleted. `tripLogisticsParticipantsProvider` is out of scope for Phase 12 per D-08 boundary (only `userTripsProvider` is deleted).

### Anti-Patterns to Avoid

- **Reading a provider inside a getter on ConsumerStatefulWidget:** `ref.read` in a getter called from non-build methods is fine; `ref.watch` in a getter is not (must be inside `build`). All `_tripCurrency` getter fixes use `ref.read`.
- **Calling `SubGroupService` methods directly from inside a Consumer's `builder` that uses a local `ref`:** The inner `ref` does not have access to the outer `ScaffoldMessenger`. Close the sheet first or pass a callback.
- **Leaving Trip/Supabase imports when they are no longer needed:** After `userTripsProvider` is removed, prune unused `trip_provider.dart` and `trip_model.dart` imports.
- **Forgetting the `mounted` check before snackbar:** Widget may have disposed by the time the async write completes. Always `if (mounted)` guard snackbar calls.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Firestore write to sub-group | Custom write helper | `SubGroupService` methods | Already tested, follows `FirestoreRepository` pattern |
| Currency code | Additional provider/lookup | `event.currency` field directly | Already on the model, non-nullable, defaults to 'OMR' |
| Leader check | Fetch group members, compare roles | `event.createdBy == currentUid` | Event already has this field; leader = creator in this app |
| Error UI for write failures | Custom error widget | `ScaffoldMessenger.showSnackBar` | Phase 11 established this as the project standard |

---

## Common Pitfalls

### Pitfall 1: memberId vs participantId in removeMember

**What goes wrong:** Calling `SubGroupService.removeMember(memberId: member.participantId)` instead of `member.id`.

**Why it happens:** `SubGroupMember` has both `id` (the Firestore doc ID) and `participantId` (the participant's ID). The `removeMember` method deletes the document by its doc ID, not by participant ID.

**How to avoid:** Use `member.id` — this is the UUID assigned during `addMember` (stored in both the doc ID and the `id` field of the document).

**Warning signs:** Deletion silently fails (no document at that path).

### Pitfall 2: ScaffoldMessenger context after Navigator.pop

**What goes wrong:** Showing a snackbar after calling `Navigator.pop(context)` — the context may reference a popped route's scaffold.

**Why it happens:** Dialogs and bottom sheets have their own `Scaffold` tree. After popping the sheet, `context` refers to the sheet's disposed widget tree.

**How to avoid:** Pop the modal first, then show the snackbar using the screen's own context via `if (mounted)` guard. For stubs inside Consumer builders (the member picker sheet), pass a callback to `_showMemberPicker` and call the service after the sheet is dismissed.

**Warning signs:** "Looking up a deactivated widget's ancestor" errors, or snackbar not appearing.

### Pitfall 3: Import cleanup causes compile errors

**What goes wrong:** Deleting `userTripsProvider` from `trip_provider.dart` while files still import it.

**Why it happens:** Import removal must be coordinated with usage removal in the same commit.

**How to avoid:** In the deletion task, grep for all `userTripsProvider` references, remove usages first, then remove the definition and imports atomically.

**Warning signs:** `Undefined name 'userTripsProvider'` compile errors.

### Pitfall 4: _tripCurrency getter called before event is available

**What goes wrong:** `_tripCurrency` is called during `_onKeyPress` (decimal precision calculation) before the event has loaded from Firestore.

**Why it happens:** `eventDetailProvider` is a `StreamProvider` — it starts in loading state.

**How to avoid:** `ref.read(...).valueOrNull?.currency ?? 'OMR'` — the `?? 'OMR'` fallback handles the loading state gracefully. This is correct because OMR (3 decimal places) is the project default currency.

**Warning signs:** Different decimal precision behavior when event loads late.

---

## Code Examples

### _tripCurrency fix (add_expense_screen.dart)

```dart
/// Get the event's currency code
String get _tripCurrency {
  return ref
      .read(eventDetailProvider(
        (groupId: widget.groupId, eventId: widget.eventId),
      ))
      .valueOrNull
      ?.currency ?? 'OMR';
}
```

### _tripCurrency fix (edit_expense_sheet.dart)

```dart
/// Get the event's currency code
String get _tripCurrency {
  return ref
      .read(eventDetailProvider(
        (groupId: widget.groupId, eventId: widget.eventId),
      ))
      .valueOrNull
      ?.currency ?? 'OMR';
}
```

### isLeader fix (split_scope_selector.dart _PayerSelector.build)

```dart
// Replace the trip lookup block (lines 381-394) with:
final currentUid = ref.watch(currentUserProvider)?.uid;
final isLeader = currentUid != null && event.createdBy == currentUid;

if (!isLeader || participants.isEmpty) {
  return const SizedBox.shrink();
}
```

### isLeader fix (edit_expense_sheet.dart _buildPayerSelector)

```dart
// The event is already fetched later in the method — move the fetch up
// and use it for both the isLeader check and participant lookup.
final eventAsync = ref.watch(eventDetailProvider(
  (groupId: widget.groupId, eventId: widget.eventId),
));
final event = eventAsync.valueOrNull;
if (event == null) return const SizedBox.shrink();

final currentUid = ref.watch(currentUserProvider)?.uid;
final isLeader = currentUid != null && event.createdBy == currentUid;

if (!isLeader) return const SizedBox.shrink();
```

### logistics removeMember wiring

```dart
onRemoveMember: (member, group) async {
  try {
    await ref.read(subGroupServiceProvider).removeMember(
      groupId: widget.event.groupId,
      eventId: widget.event.id,
      subGroupId: group.id,
      memberId: member.id,
    );
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't remove member — try again")),
      );
    }
  }
},
```

---

## Environment Availability

Step 2.6: SKIPPED (no external dependencies — all changes are code/provider substitutions using existing Firestore SDK and in-repo services).

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | flutter_test (built-in) + mocktail 1.0.4 + fake_cloud_firestore 4.1.0+1 |
| Config file | None — standard Flutter test runner |
| Quick run command | `flutter test test/unit/sub_group_service_test.dart test/features/logistics_screen_mutations_test.dart -x` |
| Full suite command | `flutter test` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| FIN-01 | Payer dropdown renders when `event.createdBy == currentUid` | Widget | `flutter test test/features/ledger/payer_selector_test.dart -x` | Wave 0 |
| FIN-01 | Payer dropdown hidden when user is not creator | Widget | same file | Wave 0 |
| EVT-08 | `_tripCurrency` returns `event.currency` not hardcoded OMR | Unit/Widget | `flutter test test/features/ledger/trip_currency_test.dart -x` | Wave 0 |
| EVT-08 | `removeMember` calls `SubGroupService.removeMember` with correct `member.id` | Widget | `flutter test test/features/logistics_screen_mutations_test.dart -x` | Wave 0 |
| EVT-08 | `addMember` (drop) calls `SubGroupService.addMember` | Widget | same file | Wave 0 |
| EVT-08 | `addMember` (picker) calls `SubGroupService.addMember` | Widget | same file | Wave 0 |
| EVT-08 | `deleteSubGroup` calls `SubGroupService.deleteSubGroup` | Widget | same file | Wave 0 |
| EVT-08 | `updateSubGroup` calls `SubGroupService.updateSubGroup` | Widget | same file | Wave 0 |
| EVT-08 | `createSubGroup` calls `SubGroupService.createSubGroup` with capacity | Widget | same file | Wave 0 |
| EVT-08 | `SubGroupService.updateSubGroup` writes name+capacity to Firestore | Unit | `flutter test test/unit/sub_group_service_test.dart -x` | ❌ extend existing |
| EVT-08 | Write failure shows snackbar | Widget | `test/features/logistics_screen_mutations_test.dart` | Wave 0 |

### Sampling Rate

- **Per task commit:** `flutter test test/unit/sub_group_service_test.dart -x` (service unit) + relevant screen test
- **Per wave merge:** `flutter test`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps

- [ ] `test/features/logistics_screen_mutations_test.dart` — covers removeMember, addMember (both), deleteSubGroup, updateSubGroup, createSubGroup, snackbar on failure
- [ ] `test/features/ledger/payer_selector_test.dart` — covers isLeader true/false rendering
- [ ] `test/features/ledger/trip_currency_test.dart` — covers `_tripCurrency` returning `event.currency`
- [ ] `test/unit/sub_group_service_test.dart` — extend existing with `updateSubGroup` test

---

## Open Questions

1. **Does `edit_expense_sheet.dart` need an `Event` constructor parameter?**
   - What we know: The sheet currently takes `groupId`, `eventId`, and `expense`. `_buildPayerSelector()` already fetches the event via `eventDetailProvider` — so the information is accessible.
   - What's unclear: Whether adding `Event event` as a constructor parameter would simplify both the `_tripCurrency` getter and the `_buildPayerSelector()` method.
   - Recommendation: Skip adding the constructor parameter. Use `ref.read(eventDetailProvider(...)).valueOrNull` in the getter and the existing `ref.watch(eventDetailProvider(...))` in `_buildPayerSelector()`. This is the smallest change.

2. **Does the addMember-via-picker stub need a callback pattern or can it write inline?**
   - What we know: The picker is a Consumer inside a `showModalBottomSheet`. The inner Consumer's `ref` is valid. The outer screen context is accessible via closure.
   - Recommendation: Pop the sheet first (`Navigator.pop(context)`), then call the service on the outer screen's `ref` via a callback passed into `_showMemberPicker`. This avoids ScaffoldMessenger context issues (Pitfall 2).

---

## Sources

### Primary (HIGH confidence)

- Direct code inspection of: `add_expense_screen.dart`, `edit_expense_sheet.dart`, `split_scope_selector.dart`, `logistics_screen.dart`, `sub_group_service.dart`, `sub_group_model.dart`, `event_model.dart`, `trip_provider.dart`, `expense_provider.dart`, `sub_group_provider.dart`
- Phase 11 reference implementation: `gear_screen.dart:576-637` (snackbar error pattern)
- `11-CONTEXT.md` D-01 through D-07 (error handling decisions carried into Phase 12 as D-06)
- `12-CONTEXT.md` (all locked decisions verified against live code)

### Secondary (MEDIUM confidence)

- `sub_group_service_test.dart` — confirms `addMember` stores `memberId` as doc ID and in `id` field

---

## Metadata

**Confidence breakdown:**
- Currency fix: HIGH — `Event.currency` is a non-nullable field with OMR default; getter swap is mechanical
- isLeader fix: HIGH — `Event.createdBy` is non-nullable; `currentUserProvider` already used in the same file
- Logistics wiring: HIGH — SubGroupService methods confirmed via source code; snackbar pattern confirmed from Phase 11
- `updateSubGroup` implementation: HIGH — follows identical pattern to `deleteSubGroup` with Firestore `update()` call
- `userTripsProvider` deletion: HIGH — all consumers identified via grep; post-fix consumers will not reference it

**Research date:** 2026-03-28
**Valid until:** N/A — all research is against in-repo code, not external sources
