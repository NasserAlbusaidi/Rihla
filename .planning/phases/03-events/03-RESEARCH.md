# Phase 3: Events - Research

**Researched:** 2026-03-26
**Domain:** Flutter + Firestore event creation, typed event templates, CommandCenter adaptation, Supabase bridge
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Event Creation Flow**
- D-01: FAB on GroupDetailScreen is the entry point for creating events.
- D-02: Two-step flow: Step 1 full-screen type picker with visual cards. Step 2 creation form pre-filled based on selected type.
- D-03: Creation form fields: event name (required), optional start/end dates, participant picker. Currency inherited from group.
- D-04: Participant picker: checkbox list of all group members, all pre-checked by default. Creator can exclude anyone including themselves.
- D-05: After creation navigate directly to event hub (adapted CommandCenter). No intermediate share screen.
- D-06: No event invite codes. Events are group-internal only.
- D-07: Any group member can create an event.
- D-08: Name and dates are editable after creation. Event type is locked once created.
- D-09: Event creator can delete the event with a confirmation dialog. Soft delete (is_deleted flag) to preserve financial records.
- D-10: Event creator can add/remove participants after creation, picking only from existing group members.

**Event Types & Templates**
- D-11: Five event types: Trip, Camping, Travel, Night/Day Out, Custom.
- D-12: Module configuration per type: Trip (Ledger+Gear+Logistics+Vault+Memories), Camping (Ledger+Gear+Logistics+Memories), Travel (Ledger+Logistics+Vault+Memories), Night/Day Out (Ledger only), Custom (user toggles, Ledger default on).
- D-13: Only Camping type gets preset content: tent, sleeping bag, cooler auto-added to gear list on creation.
- D-14: Ledger is always enabled for every event type. Custom events have it on by default.
- D-15: Each event type has a distinct icon from Iconsax. Trip=airplane, Camping=tent/tree, Travel=car/suitcase, Night/Day Out=moon/sun, Custom=puzzle piece.
- D-16: Type picker shows visual cards with icon, name, short description, and enabled modules as chips.

**Event Hub Experience**
- D-17: Adapt existing CommandCenter for events. Refactor to accept event data. Module cards show/hide per event type config. Reuses all existing module screens.
- D-18: Event hub header: event name (large), event type badge (icon+type name), group name as subtitle. Uses existing ModuleHeader.
- D-19: Expense summary hero shown in event hub via Supabase bridge.
- D-20: Tap event card in group detail timeline navigates to adapted CommandCenter via Navigator.push.
- D-21: Existing module screens (ledger, gear, logistics, vault, memories) reused as-is. They receive event ID = Supabase trip ID via bridge.
- D-22: Supabase bridge — when Firestore event is created, also create a matching Supabase trip record with the same ID. Bridge remains until Phase 4.

**Event Timeline in Group**
- D-23: Events section in GroupDetailScreen replaces current EmptyStateView placeholder.
- D-24: Event card: type icon, event name, date range (or "No dates"), participant count, total spent ("0.000 OMR").
- D-25: Sorted date descending (newest first). Events without dates sorted to top.
- D-26: Past events (end date before today) have opacity 0.6. Still tappable.
- D-27: Section header shows "Events ({N})". Empty state with EmptyStateView.
- D-28: Tap event card navigates to event hub via Navigator.push.

**Firestore Data Model**
- D-29: Events stored as subcollection: `groups/{groupId}/events/{eventId}`.
- D-30: Participant IDs stored as array field: `participantIds: [uid1, uid2, ...]`.
- D-31: Participant names stored as map field: `participantNames: {uid1: "Nasser", uid2: "Ahmed"}`. Denormalized.
- D-32: Security rules: any group member can read events. Only event participants can write.
- D-33: Event document fields: id, name, type, groupId, createdBy, participantIds, participantNames, modules (map), startDate, endDate, currency, isDeleted, deletedAt, createdAt, updatedAt, bridgeTripId.

**Event Status/Lifecycle**
- D-34: No explicit status field. State derived from dates (same logic as Trip.isOngoing, Trip.isPast).
- D-35: Events without dates are treated as ongoing/active — never dimmed, sorted to top.

**Pull-to-Refresh Fix (Phase 2 Gap #8)**
- D-36: Pull-to-refresh on home screen invalidates userGroupsProvider via ref.invalidate.

**Offline Behavior**
- D-37: Event data uses Firestore offline persistence only. No SQLite caching for events in Phase 3.
- D-38: Users can create events while offline. Optimistic UI via Firestore offline persistence.

### Claude's Discretion
- Event card visual design and spacing in the timeline
- Type picker card layout (grid vs vertical list) and visual treatment
- Creation form layout and validation UX
- Module toggle design for Custom events
- Bridge trip creation implementation details (timing, field mapping)
- Firestore security rule implementation for events subcollection
- Camping preset gear item details (names, categories, priorities)
- Error handling for failed event creation or bridge sync

### Deferred Ideas (OUT OF SCOPE)
- Event archive/complete action (manually marking done regardless of dates)
- Event notifications (push notifications on create/modify)
- Budget tracking per event
- Event description/notes field
- Non-group-member event participants (invite codes for events)
- Event duplication ("create another like this")
- Group-level event search/filter
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| EVT-01 | User can create an event inside a group | EventService.createEvent() writing to groups/{groupId}/events/{eventId} + Supabase bridge trip creation |
| EVT-02 | Event creation offers type selection: Trip, Camping, Travel, Night/Day Out, Custom | EventType enum + EventTypePickerScreen two-step flow (D-02, D-11) |
| EVT-03 | Event type controls which modules are visible | EventModules class (mirrors TripModules) with per-type config (D-12); EventCommandCenter filters module cards |
| EVT-04 | Event type pre-fills relevant content (Camping adds tent/sleeping bag/cooler) | EventService.createEvent() calls GearService.addItem() for Camping type after bridge trip is created (D-13) |
| EVT-05 | Custom events let user pick modules manually with no preset content | Custom type shows module toggles in CreateEventScreen. Ledger locked on (D-14) |
| EVT-06 | Group members are pre-populated as event participants (user can add/remove) | Participant picker in CreateEventScreen pre-checks all group members from groupMembersProvider (D-04, D-10) |
| EVT-07 | Event timeline in group shows chronological list of past and upcoming events with financial totals | groupEventsProvider (StreamProvider.family) replaces _buildEventsSection placeholder in GroupDetailScreen (D-23 to D-28) |
| EVT-08 | Existing trip functionality (ledger, gear, logistics, vault, activity, memories) works within events | Supabase bridge (D-22) + EventCommandCenter passes bridgeTripId to existing module screens as Trip object |
</phase_requirements>

---

## Summary

Phase 3 builds on two completed foundations: Firestore groups (Phase 2) and the legacy Supabase trip layer. The central engineering challenge is the **Supabase bridge** — events need to feel fully functional immediately, but the existing module screens (ledger, gear, logistics, vault, memories) are hardwired to Supabase trip IDs. The solution is to create a matching Supabase trip record with the same UUID when a Firestore event is created, allowing all existing module screens to function without modification. This bridge is explicitly temporary (Phase 4 migrates everything to Firestore).

The second challenge is **adapting CommandCenter** to accept an `Event` model instead of a `Trip` model. The existing CommandCenter reads from `userTripsProvider` and `currentTripProvider` — these are Supabase-backed providers. The new `EventCommandCenter` will receive its `Event` object directly as a constructor parameter (pushed via Navigator.push), and construct a lightweight `Trip` object from the event's `bridgeTripId` field to pass to the existing module screens. This avoids refactoring all module screens in Phase 3.

The third challenge is the **typed event template system** — five event types with distinct module configurations, one type (Camping) with preset gear content. The implementation pattern mirrors `TripModules` with a new `EventModules` class that also includes `memories`. The preset gear seeding happens synchronously after the bridge trip is created, calling the existing `GearService.addItem()` in a loop.

**Primary recommendation:** Create a self-contained `lib/features/events/` feature directory with `models/`, `providers/`, `screens/`, `services/`, and `widgets/` subdirectories. Keep the Supabase bridge encapsulated in `EventService` so Phase 4 can delete it cleanly.

---

## Standard Stack

### Core (all versions already in pubspec.yaml — no new dependencies)

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `cloud_firestore` | `^6.2.0` (installed) | Event document storage, subcollection stream | Already established in Phase 2. Events subcollection inherits same patterns. |
| `firebase_auth` | `^6.3.0` (installed) | Current user UID for security rules | Established in Phase 1. No change. |
| `supabase_flutter` | `^2.3.4` (installed) | Bridge trip creation in Supabase | Already installed. Bridge writes use existing TripService.createTrip() or direct Supabase client calls. |
| `flutter_riverpod` | `^2.4.9` (installed) | StreamProvider.family for event streams | Same pattern as groupDetailProvider. |
| `go_router` | `^13.2.0` (installed) | Top-level routing (events do NOT use GoRouter) | Events stay in Navigator.push zone per CONTEXT.md D-20, D-28. |
| `iconsax` | `^0.0.8` (installed) | Event type icons, module icons | D-15 specifies Iconsax icons explicitly. |
| `flutter_animate` | `^4.5.0` (installed) | Card entry animations, staggered list | Established pattern in CommandCenter and GroupDetailScreen. |
| `uuid` | already in pubspec | Event document ID generation | Same pattern as GroupService. |

### Testing (all already installed)

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `fake_cloud_firestore` | `^4.1.0+1` | In-memory Firestore for EventService tests | Established in Phase 2 group_service_test.dart |
| `firebase_auth_mocks` | `^0.15.1` | Mock auth UID in EventService tests | Established in Phase 2 |
| `mocktail` | already in pubspec | Mock GearService in EventService unit tests | Established project-wide |

**No new dependencies required for Phase 3.** All needed libraries are already installed.

---

## Architecture Patterns

### Recommended Project Structure

```
lib/features/events/
├── models/
│   ├── event_model.dart          # Event + EventModules + EventType
│   └── event_type_config.dart    # Static module config per type + preset definitions
├── providers/
│   └── event_provider.dart       # EventService + StreamProvider.family patterns
├── screens/
│   ├── event_type_picker_screen.dart   # Step 1: type selection
│   ├── create_event_screen.dart        # Step 2: form
│   └── event_command_center.dart       # Adapted CommandCenter
└── widgets/
    ├── event_card.dart                 # Timeline card in GroupDetailScreen
    └── event_module_list.dart          # Adapted ModuleList for events
```

### Pattern 1: Event Model (mirrors Group + TripModules)

```dart
// Source: lib/features/groups/models/group_model.dart (direct mirror)
// Source: lib/features/trip/models/trip_model.dart (TripModules mirror for EventModules)

class Event {
  final String id;
  final String name;
  final EventType type;
  final String groupId;
  final String createdBy;
  final List<String> participantIds;
  final Map<String, String> participantNames; // {uid: displayName}
  final EventModules modules;
  final DateTime? startDate;
  final DateTime? endDate;
  final String currency;
  final bool isDeleted;
  final DateTime? deletedAt;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String bridgeTripId; // Supabase trip ID for module bridge (D-33)

  // Date-derived lifecycle (mirrors Trip.isOngoing / Trip.isPast exactly)
  bool get isOngoing { ... }
  bool get isPast { ... }

  factory Event.fromDoc(DocumentSnapshot doc) { ... }
  Map<String, dynamic> toFirestoreMap() { ... }
  Event copyWith({ ... }) { ... }
}

enum EventType {
  trip,
  camping,
  travel,
  nightDayOut,
  custom;
}

class EventModules {
  final bool ledger;  // always true — enforced at construction time
  final bool gear;
  final bool logistics;
  final bool vault;
  final bool memories;

  // factory constructors per type, consistent with D-12
  factory EventModules.forType(EventType type) { ... }
  factory EventModules.fromMap(Map<String, dynamic> map) { ... }
  Map<String, dynamic> toMap() { ... }
  EventModules copyWith({ ... }) { ... }
}
```

**Critical detail:** `EventModules.ledger` is always `true`. Enforce this in the constructor with `assert(ledger == true)` or hardcode it. Custom events allow toggling other modules but not ledger (D-14).

### Pattern 2: Event Provider (mirrors group_provider.dart exactly)

```dart
// Source: lib/features/groups/providers/group_provider.dart
// StreamProvider.family pattern — mirror groupDetailProvider

/// Reactive stream of all events in a specific group.
final groupEventsProvider =
    StreamProvider.family<List<Event>, String>((ref, groupId) {
  return FirebaseConfig.firestore
      .collection('groups')
      .doc(groupId)
      .collection('events')
      .where('isDeleted', isEqualTo: false)
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((snap) => snap.docs.map(Event.fromDoc).toList());
});

/// Reactive stream for a single event.
final eventDetailProvider =
    StreamProvider.family<Event?, String>((ref, eventId) {
  // NOTE: eventId alone is not enough — needs groupId too.
  // Use a record type as the family parameter:
  // StreamProvider.family<Event?, ({String groupId, String eventId})>
  // This matches the established pattern for compound keys.
});
```

**Compound key pattern for eventDetailProvider:** Use a Dart record `({String groupId, String eventId})` as the family parameter. This is the correct Riverpod 2.x approach for two-parameter providers. Example:

```dart
final eventDetailProvider =
    StreamProvider.family<Event?, ({String groupId, String eventId})>(
        (ref, params) {
  return FirebaseConfig.firestore
      .collection('groups')
      .doc(params.groupId)
      .collection('events')
      .doc(params.eventId)
      .snapshots()
      .map((doc) => doc.exists ? Event.fromDoc(doc) : null);
});
```

### Pattern 3: EventService (mirrors GroupService write pattern)

```dart
// Source: lib/features/groups/providers/group_provider.dart (GroupService)

class EventService {
  final Ref _ref;

  /// Create event in Firestore + create Supabase bridge trip atomically.
  ///
  /// Step 1: Write event to groups/{groupId}/events/{eventId} in Firestore.
  /// Step 2: Create matching Supabase trip with id = eventId (bridge, D-22).
  /// Step 3: If Camping type, seed gear presets via GearService (D-13).
  ///
  /// Bridge trip creation is fire-and-forget with error logging — event
  /// creation must not fail if Supabase is unreachable (offline-first).
  Future<Event> createEvent({
    required String groupId,
    required String name,
    required EventType type,
    required List<String> participantIds,
    required Map<String, String> participantNames,
    required EventModules modules,
    required String currency,
    DateTime? startDate,
    DateTime? endDate,
  }) async { ... }

  Future<void> updateEvent({
    required String groupId,
    required String eventId,
    String? name,
    DateTime? startDate,
    DateTime? endDate,
  }) async { ... }

  Future<void> deleteEvent({
    required String groupId,
    required String eventId,
  }) async { ... } // soft delete: isDeleted=true, deletedAt=now

  Future<void> updateParticipants({
    required String groupId,
    required String eventId,
    required List<String> participantIds,
    required Map<String, String> participantNames,
  }) async { ... }
}
```

### Pattern 4: Supabase Bridge Trip Creation

The bridge creates a Supabase trip record with the same UUID as the Firestore event. The Supabase trip record needs minimum fields to satisfy existing module screens:

```dart
// Source: Supabase trips table schema (from trip_model.dart + supabase/migrations/)

Future<void> _createBridgeTrip({
  required String eventId,   // becomes the Supabase trip.id
  required String eventName,
  required String currency,
  required String creatorUserId,
  required EventModules modules,
  DateTime? startDate,
  DateTime? endDate,
}) async {
  try {
    final supabase = SupabaseConfig.client;

    // Create trip with the Firestore event ID as the Supabase trip ID.
    // The module config mirrors EventModules -> TripModules field mapping.
    await supabase.from('trips').insert({
      'id': eventId,
      'name': eventName,
      'invite_code': _generateBridgeCode(), // needs unique code, can be random
      'leader_id': creatorUserId, // Supabase user ID (may differ from Firebase UID)
      'modules': {
        'docs': modules.vault,    // vault -> docs mapping
        'gear': modules.gear,
        'itinerary': false,
        'logistics': modules.logistics,
      },
      'currency': currency,
      'source': 'event_bridge', // marker for Phase 4 migration (CONTEXT.md specifics)
      if (startDate != null) 'start_date': startDate.toIso8601String().split('T').first,
      if (endDate != null) 'end_date': endDate.toIso8601String().split('T').first,
    });
  } catch (e) {
    // Bridge creation failure must not block event creation.
    // Log the error — Phase 4 migration will handle orphaned events.
    debugPrint('Bridge trip creation failed for event $eventId: $e');
  }
}
```

**CRITICAL PITFALL — Supabase UID vs Firebase UID:** The `leader_id` field on the Supabase trip expects a Supabase auth UID. The current user's Supabase UID is `SupabaseConfig.currentUser?.id`, NOT the Firebase UID from `FirebaseConfig.currentUser?.uid`. These are different identity systems. The bridge trip must use the Supabase UID. If Supabase is not initialized (credentials absent), bridge creation must be skipped gracefully.

**CRITICAL PITFALL — invite_code uniqueness:** The Supabase `trips` table has a unique constraint on `invite_code`. Bridge trips need a unique code. Use a UUID-derived short code or a random 8-char string. Do NOT use the event ID directly — it's too long and may collide with format expectations.

### Pattern 5: EventCommandCenter (adapted CommandCenter)

The existing `CommandCenter` reads from `userTripsProvider` + `currentTripProvider` — both Supabase-backed. The adapted `EventCommandCenter` receives the `Event` object directly as a constructor parameter.

To reuse existing module screens without modification, create a `Trip` facade from the event:

```dart
class EventCommandCenter extends ConsumerWidget {
  final Event event;
  final Group group; // for subtitle display

  const EventCommandCenter({super.key, required this.event, required this.group});

  /// Build a Trip facade from the Event for passing to legacy module screens.
  /// The Trip.id = event.bridgeTripId so module screens read the right Supabase data.
  Trip _buildTripFacade() {
    return Trip(
      id: event.bridgeTripId,
      name: event.name,
      inviteCode: '', // unused in module screens
      leaderId: event.createdBy, // approximate — Supabase UID mismatch risk (see pitfalls)
      modules: TripModules(
        docs: event.modules.vault,
        gear: event.modules.gear,
        itinerary: false,
        logistics: event.modules.logistics,
      ),
      createdAt: event.createdAt,
      startDate: event.startDate,
      endDate: event.endDate,
      currency: event.currency,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trip = _buildTripFacade();
    // ... use existing ModuleList, ExpenseSummaryHero with the trip facade
  }
}
```

**No seed provider needed in Phase 3:** The existing `_tripDataSeedProvider` in CommandCenter calls `SyncService.downloadTripData()`. The `EventCommandCenter` does NOT need this — module data for bridge trips was already being written to Supabase at creation time. The Supabase providers will load data on demand. The SyncService pattern should be preserved for legacy trip CommandCenter but omitted from EventCommandCenter.

### Pattern 6: Sorting Events Without Dates

Decision D-25 says events without dates sort to the top (before dated events). The Firestore query cannot encode this logic — implement it client-side after the snapshot arrives:

```dart
// In groupEventsProvider map transform:
.map((snap) {
  final events = snap.docs.map(Event.fromDoc).toList();
  // Events without endDate sort to top; dated events sort by createdAt desc
  events.sort((a, b) {
    if (a.startDate == null && b.startDate == null) {
      return b.createdAt.compareTo(a.createdAt);
    }
    if (a.startDate == null) return -1; // a has no date: a goes first
    if (b.startDate == null) return 1;  // b has no date: b goes first
    return b.createdAt.compareTo(a.createdAt); // both dated: newest first
  });
  return events;
});
```

**Note:** Ordering in Firestore query by `createdAt descending` gives the initial order; client-side sort then applies the "no dates to top" rule. Do NOT add a secondary `orderBy('startDate')` to the Firestore query as it would break the composite index and not handle nulls.

### Pattern 7: Camping Preset Gear Seeding

After bridge trip creation succeeds, seed three gear items for Camping events:

```dart
// Source: lib/features/gear/providers/gear_provider.dart GearService.addItem()

if (type == EventType.camping) {
  final gearService = _ref.read(gearServiceProvider);
  // Seed sequentially — GearService.addItem() handles offline gracefully
  await gearService.addItem(
    tripId: event.bridgeTripId,
    itemName: 'Tent',
    isHighPriority: true,
  );
  await gearService.addItem(
    tripId: event.bridgeTripId,
    itemName: 'Sleeping Bag',
    isHighPriority: true,
  );
  await gearService.addItem(
    tripId: event.bridgeTripId,
    itemName: 'Cooler',
    isHighPriority: false,
  );
}
```

**Do NOT use parallel Future.wait for gear seeding** — GearService.addItem() sets loading/error providers. Parallel calls would race on those providers. Sequential await is correct.

### Pattern 8: Firestore Security Rules Extension

Extend existing `security/firestore.rules` for the events subcollection. The existing generic subcollection rule already covers `groups/{groupId}/events/{eventId}` — read this carefully before writing a separate rule:

```
// CURRENT: generic subcollection rule in firestore.rules
match /{subcollection}/{docId} {
  function isGroupMember() {
    return request.auth != null &&
      request.auth.uid in
        get(/databases/$(database)/documents/groups/$(groupId)).data.memberIds;
  }
  allow read, write: if isGroupMember();
}
```

This rule ALREADY allows any group member to read AND write all subcollections. D-32 requires: "any group member can read, but only event participants can write." The current blanket rule is too permissive for writes.

The new events-specific rule must:
1. Override the generic rule with a more specific `match /events/{eventId}` path (Firestore applies the most specific matching rule)
2. Allow read for all group members
3. Allow create for all group members (D-07: any member can create events)
4. Allow update/delete only for event participants (checked via `participantIds` array on the event document)

```
match /groups/{groupId}/events/{eventId} {
  function isGroupMember() {
    return request.auth != null &&
      request.auth.uid in
        get(/databases/$(database)/documents/groups/$(groupId)).data.memberIds;
  }

  function isEventParticipant() {
    return request.auth != null &&
      request.auth.uid in resource.data.participantIds;
  }

  function isValidEventCreate() {
    return request.auth != null &&
      request.resource.data.name is string &&
      request.resource.data.name.size() > 0 &&
      request.resource.data.type is string &&
      request.resource.data.participantIds is list &&
      request.resource.data.participantIds.size() > 0;
  }

  allow read: if isGroupMember();
  allow create: if isGroupMember() && isValidEventCreate();
  allow update: if isEventParticipant();
  allow delete: if false; // soft deletes only (D-09)
}
```

**Security rule get() cost:** This rule uses exactly 1 `get()` call (the group document membership check). Well within the 10-get limit.

**Important:** The events-specific rule will shadow the generic `/{subcollection}/{docId}` rule for the `events` subcollection because Firestore uses the most specific matching path. This is intentional.

### Anti-Patterns to Avoid

- **Passing Event directly to existing module screens:** Module screens accept `Trip` objects. Do not refactor them in Phase 3. Use the Trip facade pattern (Pattern 5).
- **Using GoRouter for event screens:** Events stay in the `Navigator.push` zone (D-20). Do not add event routes to `app_router.dart`.
- **Caching events in SQLite in Phase 3:** D-37 explicitly uses Firestore offline persistence only for events. No SQLite writes for events.
- **Making bridge trip creation block event creation:** If Supabase is offline or unconfigured, the Firestore event must still be created successfully. Bridge is fire-and-forget.
- **Calling SyncService.downloadTripData() in EventCommandCenter:** The legacy seed provider pattern is for Supabase-primary trips. EventCommandCenter has no equivalent — module screens will load on demand from Supabase providers.
- **Using EventType as a Dart enum backed by int:** Use a string-backed enum or store as String in Firestore. Firestore stores strings, not ints. An int-backed Dart enum would need explicit `EventType.fromString()` deserialization.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Firestore subcollection stream | Custom polling or periodic re-fetch | `FirebaseFirestore.collection('groups').doc(id).collection('events').snapshots()` | Real-time listeners are already the established pattern from Phase 2 |
| Event ID generation | Timestamp + random suffix | `const Uuid().v4()` (already a dependency) | Established in GroupService — `const uuid = Uuid(); uuid.v4()` |
| Date formatting on event cards | Custom formatter | `intl.DateFormat('MMM d')` (already imported in GroupDetailScreen via `intl` package) | Already installed, format matches UI-SPEC "Mar 28 – Apr 2" |
| Type picker press animation | Custom gesture detector + scale animation | `_PressableWrapper` pattern from `SmartModuleCard` (wrap `GestureDetector` with `AnimatedScale`) | UI-SPEC references this pattern explicitly |
| Participant checkbox list | Custom stateful list management | `StatefulBuilder` inside `ConsumerStatefulWidget` with local `Set<String>` for selections | Simple local state in the form screen |
| Offline event creation indicator | Custom sync status widget | `OfflineBanner` shared widget already watches `connectivityProvider` | Already shows when offline — no extra indicator needed per UI-SPEC |

---

## Common Pitfalls

### Pitfall 1: Supabase UID / Firebase UID Mismatch in Bridge

**What goes wrong:** `leader_id` in the Supabase trips table expects the Supabase auth UID (`SupabaseConfig.currentUser?.id`), not the Firebase UID (`FirebaseConfig.currentUser?.uid`). If bridge trip creation uses the Firebase UID, Supabase RLS policies for trip ownership will be wrong — the "leader" cannot delete their own bridge trip.

**Why it happens:** The codebase now has two auth systems. Developers familiar with only the new Firebase flow will reach for `FirebaseConfig.currentUser`.

**How to avoid:** In `EventService._createBridgeTrip()`, explicitly document which UID source is used: `final supabaseUid = SupabaseConfig.currentUser?.id;`. If Supabase is not initialized (credentials absent), skip bridge creation entirely. This is already handled by `SupabaseConfig.initialize()` guard (`_initialized` flag).

**Warning signs:** Bridge trip created successfully but GearService calls fail with "trip not found" or permission errors in module screens.

### Pitfall 2: Generic Subcollection Rule Overridden by Specific Events Rule

**What goes wrong:** After adding the specific `match /groups/{groupId}/events/{eventId}` rule, tests that relied on the generic `match /{subcollection}/{docId}` rule for events will fail. Firestore Emulator must be used to verify both the old rule (for `members`) and the new rule (for `events`) still work.

**Why it happens:** Adding a more specific rule shadows the generic one for that collection path. The `members` subcollection still uses the generic rule; `events` now uses the specific one.

**How to avoid:** After adding the events rule, run Firestore security rule tests via Firebase Emulator for BOTH `events` and `members` subcollection paths.

### Pitfall 3: serverTimestamp Null for Offline-Created Events

**What goes wrong:** Events created offline have `createdAt: null` until they sync (Pitfall 13 in PITFALLS.md). The sort logic in `groupEventsProvider` calls `b.createdAt.compareTo(a.createdAt)` — this throws a null reference.

**Why it happens:** `FieldValue.serverTimestamp()` is null in offline-written documents until the server commits.

**How to avoid:** Store a client-generated `createdAt` (`DateTime.now().toUtc()`) as the primary timestamp in the Firestore document, separate from a `serverCreatedAt: FieldValue.serverTimestamp()` field. The `Event.fromDoc()` factory reads `createdAt` from the client field, never from the server timestamp. This matches the pattern described in PITFALLS.md Pitfall 13.

### Pitfall 4: Camping Gear Seeding Fails Silently While Offline

**What goes wrong:** `GearService.addItem()` tries Supabase first and falls back to SQLite if offline. For bridge trips, the SQLite path writes locally — but the bridge trip may not yet exist in Supabase, so gear items written to SQLite will be orphaned when sync runs.

**Why it happens:** `GearService.addItem()` was designed for Supabase-primary trips where Supabase write always succeeds or SQLite queues the item. Bridge trips are a new pattern.

**How to avoid:** The gear seeding call should happen AFTER bridge trip creation succeeds (not fire-and-forget). Sequence: (1) Write Firestore event. (2) Create Supabase bridge trip. (3) Seed gear items. Step 3 only runs if step 2 succeeds. If offline (step 2 fails), defer gear seeding — the user can add items manually when online. Log this clearly. An alternative: seed gear items only after the online bridge trip creation confirms, not during the optimistic offline path.

### Pitfall 5: Event Card Total Spent Shows Stale Data Without Ledger Integration

**What goes wrong:** Event card shows "0.000 OMR" always — correct for Phase 3 (financials come in Phase 5). But if developers pre-wire the expense total to `tripExpensesProvider(event.bridgeTripId)` now, they create a dependency that may be slow or error when Supabase is unreachable.

**How to avoid:** Hardcode `"0.000 OMR"` as a static string in the EventCard widget for Phase 3. Do not subscribe to expense providers in the event card. Add a TODO comment: `// TODO(Phase 5): replace with real group-level financial total`. This matches D-24 ("shows '0.000 OMR' until financials exist").

### Pitfall 6: Pull-to-Refresh Already Partially Implemented

**What goes wrong:** The home screen already has `RefreshIndicator` with `onRefresh: () async => ref.refresh(userGroupsProvider.future)` (line 38 in home_screen.dart). However, `ref.refresh()` on a `StreamProvider` does NOT force a re-fetch from Firestore server — it just reattaches to the same stream. D-36 specifies using `ref.invalidate(userGroupsProvider)` to force a fresh subscription.

**Why it happens:** `ref.refresh` and `ref.invalidate` have different semantics for `StreamProvider`. `ref.refresh(provider.future)` gets the current value of the underlying Future, but for a StreamProvider backed by a Firestore listener, the stream stays open indefinitely — `invalidate` closes and reopens the stream, which triggers a fresh server fetch.

**How to avoid:** The `onRefresh` callback in home_screen.dart needs to change from `ref.refresh(userGroupsProvider.future)` to `ref.invalidate(userGroupsProvider)`. D-36 is explicit about this. The current implementation will appear to work (the stream doesn't error) but will not force a server round-trip.

**Current state:** `home_screen.dart` line 38 uses `ref.refresh(userGroupsProvider.future)` — this needs to change to `ref.invalidate(userGroupsProvider)`.

---

## Code Examples

### EventType with Firestore serialization

```dart
// Firestore stores as string. Use named values matching Firestore field strings.
enum EventType {
  trip('trip'),
  camping('camping'),
  travel('travel'),
  nightDayOut('night_day_out'),
  custom('custom');

  final String value;
  const EventType(this.value);

  static EventType fromString(String value) {
    return EventType.values.firstWhere(
      (e) => e.value == value,
      orElse: () => EventType.custom,
    );
  }
}
```

### EventModules.forType factory

```dart
// Source: decisions D-12 from 03-CONTEXT.md
factory EventModules.forType(EventType type) {
  return switch (type) {
    EventType.trip => const EventModules(
        ledger: true, gear: true, logistics: true, vault: true, memories: true),
    EventType.camping => const EventModules(
        ledger: true, gear: true, logistics: true, vault: false, memories: true),
    EventType.travel => const EventModules(
        ledger: true, gear: false, logistics: true, vault: true, memories: true),
    EventType.nightDayOut => const EventModules(
        ledger: true, gear: false, logistics: false, vault: false, memories: false),
    EventType.custom => const EventModules(
        ledger: true, gear: false, logistics: false, vault: false, memories: false),
  };
}
```

### Event.fromDoc with client timestamp pattern

```dart
factory Event.fromDoc(DocumentSnapshot doc) {
  final data = doc.data() as Map<String, dynamic>;
  // Use client-generated 'createdAt' (ISO string), not serverTimestamp,
  // to avoid null during offline writes (PITFALLS.md #13).
  DateTime createdAt;
  final rawCreatedAt = data['createdAt'];
  if (rawCreatedAt is Timestamp) {
    createdAt = rawCreatedAt.toDate();
  } else if (rawCreatedAt is String) {
    createdAt = DateTime.parse(rawCreatedAt);
  } else {
    createdAt = DateTime.now(); // fallback for offline-written docs
  }

  return Event(
    id: doc.id,
    name: data['name'] as String,
    type: EventType.fromString(data['type'] as String? ?? 'custom'),
    groupId: data['groupId'] as String,
    createdBy: data['createdBy'] as String,
    participantIds: List<String>.from(data['participantIds'] as List? ?? []),
    participantNames: Map<String, String>.from(data['participantNames'] as Map? ?? {}),
    modules: EventModules.fromMap(data['modules'] as Map<String, dynamic>? ?? {}),
    startDate: data['startDate'] != null
        ? (data['startDate'] as Timestamp).toDate()
        : null,
    endDate: data['endDate'] != null
        ? (data['endDate'] as Timestamp).toDate()
        : null,
    currency: data['currency'] as String? ?? 'OMR',
    isDeleted: data['isDeleted'] as bool? ?? false,
    deletedAt: data['deletedAt'] != null
        ? (data['deletedAt'] as Timestamp).toDate()
        : null,
    createdAt: createdAt,
    updatedAt: data['updatedAt'] != null
        ? (data['updatedAt'] as Timestamp).toDate()
        : null,
    bridgeTripId: data['bridgeTripId'] as String? ?? doc.id,
  );
}
```

### groupEventsProvider with client-side sort

```dart
final groupEventsProvider =
    StreamProvider.family<List<Event>, String>((ref, groupId) {
  return FirebaseConfig.firestore
      .collection('groups')
      .doc(groupId)
      .collection('events')
      .where('isDeleted', isEqualTo: false)
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((snap) {
        final events = snap.docs.map(Event.fromDoc).toList();
        // Client-side sort: events without dates float to the top (D-25).
        events.sort((a, b) {
          if (a.startDate == null && b.startDate == null) {
            return b.createdAt.compareTo(a.createdAt);
          }
          if (a.startDate == null) return -1;
          if (b.startDate == null) return 1;
          return b.createdAt.compareTo(a.createdAt);
        });
        return events;
      });
});
```

**Composite index required:** The query `where('isDeleted', isEqualTo: false).orderBy('createdAt', descending: true)` requires a composite index on `(isDeleted ASC, createdAt DESC)` in the `events` collection. Add this to `firestore.indexes.json` before testing (PITFALLS.md #8).

### GroupDetailScreen with FAB and events section

```dart
// GroupDetailScreen changes:
// 1. Add FAB to Scaffold (not Expanded)
// 2. Replace _buildEventsSection() placeholder

@override
Widget build(BuildContext context, WidgetRef ref) {
  return Scaffold(
    backgroundColor: AppColors.background,
    floatingActionButton: FloatingActionButton(
      onPressed: () => Navigator.of(context).push(
        AppPageRoute(
          builder: (_) => EventTypePickerScreen(groupId: groupId),
        ),
      ),
      backgroundColor: AppColors.primary,
      shape: const CircleBorder(),
      child: const Icon(Iconsax.add, color: Colors.black),
    ),
    body: ... // existing body unchanged
  );
}
```

---

## Environment Availability

Step 2.6: SKIPPED — Phase 3 introduces no new external tools or services. All dependencies (Firestore, Supabase, Firebase Auth) were verified available in Phase 2. No new CLI tools, databases, or services required.

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | flutter_test (built-in) + fake_cloud_firestore + firebase_auth_mocks + mocktail |
| Config file | pubspec.yaml dev_dependencies (existing) |
| Quick run command | `flutter test test/unit/event_model_test.dart test/unit/event_service_test.dart -x` |
| Full suite command | `flutter test` |

### Phase Requirements to Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| EVT-01 | createEvent writes Firestore doc + bridge trip | unit | `flutter test test/unit/event_service_test.dart -x` | No — Wave 0 |
| EVT-02 | EventType enum serializes 5 types correctly | unit | `flutter test test/unit/event_model_test.dart -x` | No — Wave 0 |
| EVT-03 | EventModules.forType returns correct config per type | unit | `flutter test test/unit/event_model_test.dart -x` | No — Wave 0 |
| EVT-04 | Camping event seeds tent/sleeping bag/cooler | unit | `flutter test test/unit/event_service_test.dart -x` | No — Wave 0 |
| EVT-05 | Custom event modules user-configurable, ledger always on | unit | `flutter test test/unit/event_model_test.dart -x` | No — Wave 0 |
| EVT-06 | Participant picker pre-checks all group members | widget | `flutter test test/features/events/create_event_test.dart -x` | No — Wave 0 |
| EVT-07 | GroupDetailScreen shows event list from provider | widget | `flutter test test/features/events/group_detail_events_test.dart -x` | No — Wave 0 |
| EVT-08 | EventCommandCenter shows modules matching event.modules | widget | `flutter test test/features/events/event_command_center_test.dart -x` | No — Wave 0 |
| D-36 | Pull-to-refresh calls ref.invalidate not ref.refresh | unit | `flutter test test/features/home/home_screen_groups_test.dart -x` | Yes — needs update |

### Sampling Rate

- Per task commit: `flutter test test/unit/event_model_test.dart test/unit/event_service_test.dart -x`
- Per wave merge: `flutter test`
- Phase gate: Full suite green before `/gsd:verify-work`

### Wave 0 Gaps

- `test/unit/event_model_test.dart` — covers EVT-02, EVT-03, EVT-05 (EventType serialization, EventModules.forType, lifecycle computed properties)
- `test/unit/event_service_test.dart` — covers EVT-01, EVT-04 (createEvent Firestore write + bridge + gear seeding). Mirrors `group_service_test.dart` using `FakeFirebaseFirestore` + `MockFirebaseAuth`.
- `test/features/events/create_event_test.dart` — covers EVT-06 (widget test for participant picker with mocked providers)
- `test/features/events/group_detail_events_test.dart` — covers EVT-07 (GroupDetailScreen widget test with events section, mirrors group_screens_test.dart)
- `test/features/events/event_command_center_test.dart` — covers EVT-08 (EventCommandCenter shows correct modules, mirrors command_center_test.dart)

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Trip model with TripModules | Event model with EventModules (extends TripModules + memories) | Phase 3 | New model needed — TripModules has no `memories` field |
| CommandCenter reads from userTripsProvider | EventCommandCenter receives Event as constructor param | Phase 3 | Simpler — no global provider needed for per-event hub |
| Ledger/Gear/Vault/Logistics screens accept Trip | Same screens still accept Trip (bridge) | Phase 4 (migration deferred) | Bridge pattern maintains backward compat |

---

## Open Questions

1. **Supabase invite_code uniqueness for bridge trips**
   - What we know: Supabase `trips` table has unique constraint on `invite_code`
   - What's unclear: Is there a length/format constraint on invite codes enforced at DB level? The existing code generates 6-char codes with specific character exclusions.
   - Recommendation: Use a UUID v4 as the bridge invite code (too long to type, but bridge trips are never joined manually). Verify no DB-level length check exists in supabase/migrations. If there is a check, use `_generateInviteCode()` with a uniqueness retry (already exists in TripService).

2. **Memories module support in EventCommandCenter**
   - What we know: EventModules includes `memories: bool`, Trip/Camping/Travel/Custom(opt) types include memories. The existing ModuleList in CommandCenter does NOT include a memories card.
   - What's unclear: Does a MemoriesScreen already exist? CONTEXT.md says "Reuses all existing module screens" (D-17, D-21) but TripModules has no `memories` field. REQUIREMENTS.md EVT-08 says "activity, memories" work within events.
   - Recommendation: Check `lib/features/memories/` — if a `MemoriesScreen` exists, wire it in EventCommandCenter. If not, omit the memories card from the EventCommandCenter in Phase 3 (do not create new modules). The context says "reused as-is" — if memories screen doesn't exist in current codebase, the module card just doesn't appear.

3. **Bridge trip creation when both auth systems have different sessions**
   - What we know: Firebase anonymous UID and Supabase anonymous UID are independent.
   - What's unclear: Is there a guarantee that Supabase is initialized and has an active session when event creation happens? The `SupabaseConfig._initialized` guard exists.
   - Recommendation: In EventService, check `SupabaseConfig.isAuthenticated` before attempting bridge creation. If false (Supabase not initialized), skip bridge creation and set `bridgeTripId = eventId` as placeholder for future reconciliation. Log a warning.

---

## Sources

### Primary (HIGH confidence)

- `lib/features/groups/providers/group_provider.dart` — GroupService write pattern, StreamProvider.family pattern, Firebase UID access pattern — verified by reading source
- `lib/features/groups/models/group_model.dart` — Firestore serialization pattern (fromDoc/toMap), immutability pattern — verified by reading source
- `lib/features/trip/models/trip_model.dart` — TripModules pattern, date-derived lifecycle (isOngoing/isPast) — verified by reading source
- `lib/features/home/screens/command_center.dart` — CommandCenter structure to adapt — verified by reading source
- `lib/features/home/widgets/module_list.dart` — ModuleList Trip dependency — verified by reading source
- `security/firestore.rules` — existing security rule structure, generic subcollection rule — verified by reading source
- `.planning/phases/03-events/03-CONTEXT.md` — all locked decisions D-01 through D-38
- `.planning/phases/03-events/03-UI-SPEC.md` — component inventory, interaction contracts, animation spec
- `.planning/research/PITFALLS.md` — Pitfalls 5, 8, 13 directly applicable to Phase 3

### Secondary (MEDIUM confidence)

- Riverpod 2.x Dart record family parameter pattern — established pattern from Riverpod docs, used successfully in Phase 2 for compound keys
- Firestore composite index requirement for `where + orderBy` — documented in PITFALLS.md #8 with official Firebase source

### Tertiary (LOW confidence)

- Gear seeding sequential vs parallel — recommendation based on observed loading/error provider pattern in GearService; not formally tested

---

## Metadata

**Confidence breakdown:**

- Event model + EventModules: HIGH — direct mirror of tested Group + TripModules patterns
- EventService + Firestore writes: HIGH — established GroupService pattern
- Supabase bridge: MEDIUM — bridge pattern is new, Supabase UID/Firebase UID mismatch risk documented
- Security rules extension: HIGH — existing rules inspected, specific override pattern documented
- Gear seeding: MEDIUM — sequential pattern recommendation based on provider side-effects analysis
- Camping presets content: HIGH — D-13 explicitly specifies tent, sleeping bag, cooler

**Research date:** 2026-03-26
**Valid until:** 2026-04-26 (Firestore stable, no fast-moving dependencies)
