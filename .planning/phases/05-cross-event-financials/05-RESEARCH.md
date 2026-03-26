# Phase 5: Cross-Event Financials - Research

**Researched:** 2026-03-27
**Domain:** Riverpod 2.x stream aggregation, Firestore subcollections, cross-event balance computation, Flutter financial UI
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Group Balance Aggregation**
- D-01: On-demand rollup — compute group balances from all events' expenses/settlements via Firestore streams. No cached group_ledger rows.
- D-02: Group balances include ALL events always. Running total that only changes when new expenses/settlements are added.
- D-03: Skip the `group_ledger` SQLite table entirely. On-demand rollup reads from existing Firestore expense/settlement streams. The group_ledger table is dead weight — no writes, no reads.
- D-04: Firebase UID matching for participant identity across events. Same UID = same person.
- D-05: New `groupBalancesProvider` (Riverpod provider) that watches all events in a group, reads per-event expenses/settlements, and runs BalanceCalculator across the combined dataset. BalanceCalculator stays pure.
- D-06: Watch all event streams, compute lazily. <10ms for typical groups.

**Group-Level Settlements**
- D-07: New Firestore subcollection: `groups/{groupId}/settlements/{id}`. Cross-event settlements live at the group level.
- D-08: Security rules: any group member can read/write group settlements.
- D-09: Group-level settlements are independent of per-event balances. Reduces GROUP balance, not any individual event's balance.
- D-10: Reuse existing `Settlement` model with a `scope` field: `'event'` or `'group'`. Group settlements have `groupId` but no `eventId`. BalanceCalculator treats them the same way.
- D-11: Partial settlements supported — suggested amount pre-filled but user can edit.
- D-12: Optional note/description field on group settlements.

**Balance Toggle UX**
- D-13: Group dashboard with drill-down approach. GroupDetailScreen shows group-level balances by default. Tapping a member's balance expands to show per-event breakdown.
- D-14: Per-event breakdown shows: event name + net amount per event. Tapping an event row navigates to that event's LedgerScreen.
- D-15: Balances section integrated into GroupDetailScreen as a section in the scrollable view.

**Member Balance Cards**
- D-16: Each member shows: name, net amount (green if owed money, red if owes), expand arrow.
- D-17: Hero balance card at top showing current user's net position with 'Settle up' CTA.
- D-18: Zero-balance members shown with neutral gray 'Settled' badge. Not hidden.
- D-19: Hero card hidden until first expense exists in any event.
- D-20: Members at zero balances show '0.000 OMR' and 'Settled' badge when events exist but no expenses.
- D-21: Settle-up CTA disabled with "All settled! No outstanding balances." when current user's net balance is zero.

**Cross-Event Settle-Up Flow**
- D-22: Two entry points: (1) 'Settle up' button on hero card, (2) Tap any member's balance card. Both navigate to GroupSettleUpScreen.
- D-23: New `GroupSettleUpScreen`. Separate from existing per-event SettleUpScreen.
- D-24: Each settlement card shows pairwise amount with expandable per-event breakdown.
- D-25: Optimized settlements shown by default (minimum transactions). No raw/simplified toggle.
- D-26: Success confirmation dialog with updated balance.

**Group Dashboard Layout**
- D-27: Section order: (1) Hero balance card, (2) Spending stats chips, (3) Member balances with expand, (4) Events timeline, (5) Invite code, (6) Recent activity.
- D-28: Spending stats: "Total: 245.500 OMR across 4 events" + top spenders with %. No charts.
- D-29: Existing members section merges with balances section. Member count moves to section header.
- D-30: Invite code section moves below events.

**Group Activity Log**
- D-31: 5 action types: event created, event deleted, group settlement recorded, member joined group, member left group. NOT individual expenses.
- D-32: `groups/{groupId}/activity/{activityId}`. Client-side fire-and-forget writes.
- D-33: Client-side fire-and-forget writes. No Cloud Functions.
- D-34: Dashboard shows 5 most recent. 'See all' navigates to full-screen list with cursor pagination (50 at a time).
- D-35: All group settlements visible in activity log to all group members.

**Offline Behavior**
- D-36: Firestore offline persistence serves last-fetched snapshots. Same transparent behavior as event-level data.
- D-37: Users can record group settlements while offline. Firestore queues the write. Optimistic UI.

**Navigation**
- D-38: GroupSettleUpScreen and full activity log pushed via Navigator.push with AppPageRoute. No new GoRouter routes.
- D-39: Per-event drill-down taps LedgerScreen(event, group) directly via Navigator.push.

**Testing Strategy**
- D-40: Priority 1: unit tests for BalanceCalculator with cross-event data. Priority 2: groupBalancesProvider with FakeFirebaseFirestore. Priority 3: GroupSettleUpScreen widget test. Phase 6 handles full coverage.
- D-41: Layered test approach: service tests use FakeFirebaseFirestore, provider tests use mock services, widget tests use overridden providers.

### Claude's Discretion
- GroupSettleUpScreen layout and visual design
- Activity log entry format and display styling
- Hero balance card visual design (gradients, shadows, typography)
- Member balance card expand/collapse animation
- Per-event breakdown row styling
- Spending stats chip layout and styling
- Activity log full-screen list layout
- Error handling for failed group settlement writes
- GroupActivityService implementation details
- groupBalancesProvider stream composition (how to combine multiple event streams)

### Deferred Ideas (OUT OF SCOPE)
- Multi-currency aggregation across events
- Financial milestone celebrations in activity log
- Spending charts/graphs on group dashboard
- Comprehensive activity logging beyond 5 core types
- Export group financial summary as PDF (ENH-05)
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| FIN-01 | Per-event balance shows what each member owes/is owed within that event | Already implemented via `eventBalancesProvider` (Phase 4). Phase 5 surfaces these balances in GroupDetailScreen per-event drill-down. |
| FIN-02 | Group-level balance shows net balance per member across ALL events | `groupBalancesProvider` aggregates all `eventExpensesProvider` and `eventSettlementsProvider` streams + group settlements. `BalanceCalculator.calculateBalances` runs on combined lists. |
| FIN-03 | User can toggle between per-event and group-level balance view | Implemented as expand/collapse on member balance cards (D-13). Tapping member expands per-event breakdown; default view is group total. |
| FIN-04 | Cross-event settle-up: "You owe Nasser 15.500 across 3 events — settle now?" | `GroupSettleUpScreen` with `BalanceCalculator.calculateOptimalSettlements` on group-level balances. Settlement written to `groups/{groupId}/settlements`. |
| FIN-05 | Group-level balance updates via write-time aggregation when settlements or expenses change | Firestore streams are live — `groupBalancesProvider` recomputes when any watched stream emits. Group settlements stream also watched. |
| FIN-06 | Group spending stats: total spent across all events, per-member contribution breakdown | Derived from aggregated expenses in `groupBalancesProvider`. Total = sum of all expense amounts. Contribution % = each member's totalPaid / group total. |
| FIN-07 | Settlement optimization works at both event and group level | `BalanceCalculator.calculateOptimalSettlements` already exists and works on `List<UserBalance>` — same function used for both levels. |
| GRP-04 | Group dashboard shows total spent across all events, member count, and per-member running balances | `GroupDetailScreen` receives new financial sections: hero card, stats chips, member balances. Data from `groupBalancesProvider`. |
| GRP-05 | Group activity log shows group-level events | `GroupActivityService` writes to `groups/{groupId}/activity`. `groupActivityProvider` streams to GroupDetailScreen. 5 action types (D-31). |
</phase_requirements>

---

## Summary

Phase 5 is a **provider composition + two new screens + one new service** phase. The core technical work is composing multiple Firestore streams into a single reactive group balance computation. Everything needed already exists: `BalanceCalculator` is pure and extensible, `eventExpensesProvider`/`eventSettlementsProvider` are live Firestore streams, and `SettleUpScreen` is a ready template for `GroupSettleUpScreen`.

The primary architectural challenge is the `groupBalancesProvider` implementation. It must watch `groupEventsProvider` (the list of events), then for each event watch both `eventExpensesProvider` and `eventSettlementsProvider`, then watch group-level settlements, and finally combine everything through `BalanceCalculator`. In Riverpod 2.x, this is a `Provider.family` that uses `ref.watch` across an unknown-count list of family providers — the canonical pattern for this is described below.

The `Settlement` model needs a `scope` field added and a new `fromFirestore`/`toFirestore` path that writes to `groups/{groupId}/settlements` (not under an event). The `GroupActivityService` mirrors the existing `ActivityService` but targets `groups/{groupId}/activity` and writes 5 group-level action types. No new navigation infrastructure is needed — all new screens use `Navigator.push`.

**Primary recommendation:** Build in four waves — (1) data layer (GroupSettlementService, GroupActivityService, Settlement.scope), (2) providers (groupBalancesProvider, groupSettlementsProvider, groupActivityProvider), (3) GroupDetailScreen layout restructure + new widgets, (4) GroupSettleUpScreen.

---

## Standard Stack

### Core (all already in pubspec.yaml)

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `cloud_firestore` | `^6.2.0` | Group settlements + activity subcollections | Already the project's primary cloud database. New paths follow established patterns. |
| `flutter_riverpod` | `^2.4.9` | `groupBalancesProvider`, stream composition | All providers in the project use Riverpod 2.x. No change. |
| `decimal` | `^3.2.4` | All monetary math in group balances | Mandatory per CLAUDE.md. No floating point for money. |
| `flutter_animate` | `^4.5.0` | Expand/collapse animations on member balance cards | Already used in SettleUpScreen. |
| `fake_cloud_firestore` | `^4.1.0+1` | GroupSettlementService tests, groupBalancesProvider tests | Established test pattern across Phase 4. |
| `mocktail` | `^1.0.4` | Non-Firestore mock surfaces | Already in dev_dependencies. |

### No New Dependencies Required
This phase introduces no new pub.dev dependencies. All required libraries are already present.

**Version verification:** Confirmed from pubspec.yaml read on 2026-03-27.

---

## Architecture Patterns

### Recommended Project Structure (new files only)

```
lib/features/groups/
├── services/
│   ├── group_settlement_service.dart  # NEW — CRUD for groups/{id}/settlements
│   └── group_activity_service.dart    # NEW — writes to groups/{id}/activity
├── providers/
│   └── group_balance_provider.dart    # NEW — groupBalancesProvider, groupSettlementsProvider, groupActivityProvider
├── screens/
│   ├── group_detail_screen.dart       # MODIFIED — restructured with new sections
│   ├── group_settle_up_screen.dart    # NEW — cross-event settlement UI
│   └── group_activity_screen.dart     # NEW — full-screen activity log
└── widgets/
    ├── group_member_tile.dart          # MODIFIED — adds balance column
    ├── group_balance_hero.dart         # NEW — hero card with settle-up CTA
    ├── group_member_balance_card.dart  # NEW — expandable balance tile
    ├── group_spending_stats.dart       # NEW — stats chips row
    └── group_activity_tile.dart        # NEW — single activity log entry

lib/features/ledger/
└── models/
    └── settlement_model.dart           # MODIFIED — add scope field, new Firestore paths
```

### Pattern 1: groupBalancesProvider — Watching Variable-Length Provider Lists

**What:** In Riverpod 2.x, a `Provider.family` that watches `groupEventsProvider`, then calls `ref.watch` for each event's expenses and settlements, combining them all into a single `AsyncValue<GroupBalances>`.

**Why this is the right pattern:** `groupBalancesProvider` has a variable-length dependency list (number of events per group is not known at compile time). The standard Riverpod 2.x idiom is to use `Provider.family` (not `StreamProvider.family`) and call `ref.watch` for each family member inside the provider body. The provider recomputes when any watched value changes.

**When to use:** Aggregating data from N Firestore streams where N is dynamic.

```dart
// Source: established Riverpod 2.x pattern — ref.watch in loop is valid
// in Provider.family bodies (not in StreamProvider bodies).

/// Record type for group balance result
typedef GroupBalances = ({
  List<UserBalance> balances,
  Decimal totalSpent,
  int eventCount,
  // Per-event breakdown: memberId -> {eventId -> netBalance}
  Map<String, Map<String, Decimal>> perEventBreakdown,
});

final groupBalancesProvider =
    Provider.family<AsyncValue<GroupBalances>, String>((ref, groupId) {
  // Step 1: Watch the events list
  final eventsAsync = ref.watch(groupEventsProvider(groupId));
  if (eventsAsync.isLoading && !eventsAsync.hasValue) {
    return const AsyncValue.loading();
  }
  if (eventsAsync.hasError) {
    return AsyncValue.error(eventsAsync.error!, eventsAsync.stackTrace!);
  }

  final events = eventsAsync.valueOrNull ?? [];

  // Step 2: Watch group-level settlements
  final groupSettlementsAsync = ref.watch(groupSettlementsProvider(groupId));

  // Step 3: For each event, watch expenses and settlements
  // ref.watch in a loop is valid inside Provider.family bodies
  final List<Expense> allExpenses = [];
  final List<Settlement> allSettlements = [];
  bool isLoadingAny = false;

  for (final event in events) {
    final eventRef = (groupId: groupId, eventId: event.id) as EventRef;
    final expensesAsync = ref.watch(eventExpensesProvider(eventRef));
    final settlementsAsync = ref.watch(eventSettlementsProvider(eventRef));

    if ((expensesAsync.isLoading && !expensesAsync.hasValue) ||
        (settlementsAsync.isLoading && !settlementsAsync.hasValue)) {
      isLoadingAny = true;
      continue;  // Use stale data if available, skip if not
    }

    allExpenses.addAll(expensesAsync.valueOrNull ?? []);
    allSettlements.addAll(settlementsAsync.valueOrNull ?? []);
  }

  // Include group-level settlements
  allSettlements.addAll(groupSettlementsAsync.valueOrNull ?? []);

  if (isLoadingAny && allExpenses.isEmpty) {
    return const AsyncValue.loading();
  }

  // Step 4: Build unified participant list from group members
  // (UID-based identity: same UID across events = same person, D-04)
  // ... build participants from groupMembersProvider(groupId) ...

  // Step 5: Run BalanceCalculator on combined data
  final balances = BalanceCalculator.calculateBalances(
    expenses: allExpenses,
    settlements: allSettlements,
    participants: participants,
  );

  return AsyncValue.data((
    balances: balances,
    totalSpent: BalanceCalculator.calculateTotalExpenses(allExpenses),
    eventCount: events.length,
    perEventBreakdown: _buildPerEventBreakdown(events, ref, groupId),
  ));
});
```

**Critical note on participant identity:** `eventExpensesProvider` uses `payerParticipantId` which is a Firebase UID (since Phase 4 migrated to UID-based participants). The `groupMembersProvider` also returns UIDs as `GroupMember.userId`. So participant identity across events is UID-based — build `Participant` objects from `groupMembersProvider` with `id = member.userId`.

**Critical note on Settlement scope:** Group settlements (D-09) use the same `BalanceCalculator` path. The `payerParticipantId` and `recipientParticipantId` are Firebase UIDs. When building the participant list for `BalanceCalculator`, use UIDs. Group settlements' `tripId` field can be set to the groupId as a sentinel (or left empty) — the calculator only uses `payerParticipantId` and `recipientParticipantId`.

### Pattern 2: GroupSettlementService — New Firestore Path

**What:** A new service for `groups/{groupId}/settlements/{id}`. Mirrors `SettlementService` but writes to the group-level collection instead of an event subcollection.

```dart
// Source: SettlementService pattern (lib/features/ledger/services/settlement_service.dart)
class GroupSettlementService extends FirestoreRepository {
  GroupSettlementService() : super();

  @visibleForTesting
  GroupSettlementService.withFirestore(super.db) : super.withFirestore();

  Stream<List<Settlement>> watchGroupSettlements(String groupId) {
    return db
        .collection('groups')
        .doc(groupId)
        .collection('settlements')
        .where('isDeleted', isEqualTo: false)
        .orderBy('settledAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((doc) =>
            Settlement.fromFirestore({...doc.data(), 'id': doc.id})).toList());
  }

  Future<Settlement> addGroupSettlement({
    required String groupId,
    required String payerParticipantId,    // Firebase UID
    required String recipientParticipantId, // Firebase UID
    required Decimal amount,
    String currency = 'OMR',
    String? note,
  }) async {
    final id = const Uuid().v4();
    final now = DateTime.now().toUtc();
    final data = <String, dynamic>{
      'id': id,
      'groupId': groupId,           // groupId instead of eventId
      'scope': 'group',             // D-10
      'payerParticipantId': payerParticipantId,
      'recipientParticipantId': recipientParticipantId,
      'amountFils': MoneySerializer.toSubunits(amount, currency),
      'currency': currency,
      'note': note,
      'isDeleted': false,
      'deletedAt': null,
      'settledAt': now.toIso8601String(),
    };
    await db.collection('groups').doc(groupId)
        .collection('settlements').doc(id).set(data);
    return Settlement.fromFirestore(data);
  }
}
```

**Settlement model change:** Add `scope` field (`'event'` | `'group'`), `groupId` field (nullable — only set for group settlements). `fromFirestore` already works because the calculator only needs `payerParticipantId`, `recipientParticipantId`, and `amount`.

### Pattern 3: GroupActivityService — Fire-and-Forget at Group Level

**What:** Mirrors `ActivityService` but targets `groups/{groupId}/activity`. Writes 5 action types (D-31). Cursor pagination for 'see all' view (D-34).

```dart
// Source: ActivityService pattern (lib/features/activity/services/activity_service.dart)
class GroupActivityService extends FirestoreRepository {
  GroupActivityService() : super();

  @visibleForTesting
  GroupActivityService.withFirestore(super.db) : super.withFirestore();

  Stream<List<GroupActivityLog>> watchRecentActivity(
    String groupId, {
    int limit = 5,
  }) {
    return db.collection('groups').doc(groupId).collection('activity')
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => GroupActivityLog.fromFirestore(doc.data()))
            .toList());
  }

  /// Cursor-paginated for full activity log (D-34)
  Stream<List<GroupActivityLog>> watchActivityPage(
    String groupId, {
    DocumentSnapshot? startAfter,
    int limit = 50,
  }) {
    var query = db.collection('groups').doc(groupId).collection('activity')
        .orderBy('timestamp', descending: true)
        .limit(limit);
    if (startAfter != null) query = query.startAfterDocument(startAfter);
    return query.snapshots().map((snap) => snap.docs
        .map((doc) => GroupActivityLog.fromFirestore(doc.data())).toList());
  }

  Future<void> logGroupEvent({
    required String groupId,
    required String type,        // 'event_created' | 'event_deleted' | 'settlement_recorded' | 'member_joined' | 'member_left'
    required String actorId,     // Firebase UID
    required String actorName,
    required String description,
    Map<String, dynamic>? metadata, // eventId, amount, etc.
  }) async {
    final id = const Uuid().v4();
    // Fire-and-forget: unawaited write, log error but don't throw (D-33)
    unawaited(
      db.collection('groups').doc(groupId).collection('activity').doc(id).set({
        'id': id,
        'type': type,
        'actorId': actorId,
        'actorName': actorName,
        'description': description,
        'metadata': metadata ?? {},
        'timestamp': FieldValue.serverTimestamp(),
      }).catchError((e) => debugPrint('[GroupActivity] log failed: $e')),
    );
  }
}
```

### Pattern 4: Per-Event Breakdown — Computing Delta per Event

**What:** To show "Camping: +10.500 OMR" in the expandable per-event breakdown (D-14), the `groupBalancesProvider` must compute per-event balances separately for each event and store them keyed by `(memberId, eventId)`.

**How:** Call `BalanceCalculator.calculateBalances` once per event (with that event's participants as participants) to get per-event `UserBalance`, then merge into the group balance by summing nets across events.

```dart
// Per-event breakdown helper
Map<String, Map<String, Decimal>> _buildPerEventBreakdown(
  List<Event> events,
  AutoDisposeProviderRef ref,
  String groupId,
) {
  // result: { memberId -> { eventId -> netBalance } }
  final breakdown = <String, Map<String, Decimal>>{};

  for (final event in events) {
    final eventRef = (groupId: groupId, eventId: event.id) as EventRef;
    final expenses = ref.watch(eventExpensesProvider(eventRef)).valueOrNull ?? [];
    final settlements = ref.watch(eventSettlementsProvider(eventRef)).valueOrNull ?? [];

    // Build participants for THIS event (UID-based)
    final participants = event.participantIds.map((uid) => Participant(
      id: uid,
      tripId: event.id,
      role: ParticipantRole.member,
      joinedAt: event.createdAt,
      displayName: event.participantNames[uid],
    )).toList();

    final eventBalances = BalanceCalculator.calculateBalances(
      expenses: expenses,
      settlements: settlements,
      participants: participants,
    );

    for (final b in eventBalances) {
      breakdown.putIfAbsent(b.participantId, () => {})[event.id] = b.netBalance;
    }
  }

  return breakdown;
}
```

### Pattern 5: Security Rules Extension

**What:** The existing `groups/{groupId}/{subcollection}/{docId}` catch-all rule already covers `settlements` and `activity` subcollections at the group level. No new rules are strictly required — the existing generic rule at line 90-97 of `firestore.rules` handles them.

**Verification:** The existing rule is:
```
match /{subcollection}/{docId} {
  function isGroupMember() {
    return request.auth != null &&
      request.auth.uid in
        get(/databases/$(database)/documents/groups/$(groupId)).data.memberIds;
  }
  allow read, write: if isGroupMember();
}
```

This covers `groups/{groupId}/settlements/{id}` and `groups/{groupId}/activity/{id}` — any group member can read/write. This is exactly D-08. No changes to `firestore.rules` are required.

**Confidence:** HIGH — verified by reading `security/firestore.rules` directly.

### Pattern 6: GroupDetailScreen Restructure

**What:** The current `GroupDetailScreen` has sections: stats row, invite, members, events. Phase 5 reorders to: hero card, stats chips, members+balances, events, invite, activity (D-27/D-28/D-29/D-30).

**Key implementation note:** The current `_buildMembersSection` creates a `Column` of `GroupMemberTile`. Phase 5 replaces this with `GroupMemberBalanceCard` widgets that are expandable. The existing `GroupMemberTile` can either be deprecated or extended via `copyWith`-style modification. Since `GroupMemberTile` is a StatelessWidget and the new card needs expand/collapse state, a new `GroupMemberBalanceCard` (StatefulWidget or AnimatedContainer-based) is cleaner.

### Anti-Patterns to Avoid

- **Awaiting fire-and-forget activity writes:** `logGroupEvent` must be fire-and-forget (`unawaited`). Awaiting it blocks settlement recording.
- **Computing group balances in the UI layer:** All balance math stays in `BalanceCalculator` (pure). The UI only calls formatters.
- **Using `double` for totals or percentages:** Contribution percentages must use `Decimal` arithmetic throughout, converting to `double` only at the final `Text()` display step.
- **Watching `groupSettlementsProvider` inside `eventBalancesProvider`:** Per-event balances remain event-scoped (D-09). Group settlements only affect group-level balances.
- **Mutating the `List<Expense>` or `List<Settlement>` from Firestore streams:** Always create new combined lists (`[...eventExpenses, ...moreExpenses]`), never `addAll` to a provider-emitted list.
- **Passing `Event` objects into provider family keys for `groupBalancesProvider`:** Event objects are not hashable as family keys. Use the `groupId` String as the family key; retrieve events inside the provider body.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Settlement optimization | Greedy debt-minimization algorithm | `BalanceCalculator.calculateOptimalSettlements` | Already exists, tested, handles Decimal precision correctly |
| Balance computation | Custom summation logic | `BalanceCalculator.calculateBalances` | Already handles 4 expense scopes, settlement adjustments, sub-groups |
| Money serialization | Custom int/Decimal conversion | `MoneySerializer.toSubunits` / `fromSubunits` | Handles OMR 3-decimal-place scaling correctly |
| Firestore stream management | Manual subscription / dispose | Riverpod `StreamProvider.family` with `ref.watch` | Riverpod manages lifecycle, auto-disposes when unwatched |
| Cursor pagination | Manual offset tracking | Firestore `startAfterDocument` | Firestore's native cursor API is correct and efficient |
| Expand/collapse animation | Custom animation controller | `AnimatedCrossFade` or `AnimatedSize` + `flutter_animate` | Already used in the project; `flutter_animate` is in pubspec |

**Key insight:** `BalanceCalculator` is a pure function class. It does not know about groups vs. events. Calling it with a combined multi-event expense list is architecturally valid — the planner should not introduce a `GroupBalanceCalculator` class. Same function, different inputs.

---

## Common Pitfalls

### Pitfall 1: Participant Identity Mismatch Across Events

**What goes wrong:** Group members and event participants both use Firebase UIDs, but the `Participant` model's `id` field holds the UID while `GroupMember.userId` also holds the UID. If participant list for `BalanceCalculator` is built from `event.participantIds` (which are UIDs), and group settlements use `payerParticipantId` as UID, they match. But if any legacy code uses a generated UUID for `participantId` instead of Firebase UID, cross-event aggregation breaks silently (settlement applies to wrong person).

**Why it happens:** Phase 4 migrated to UID-based participants, but `Participant.id` in tests still uses `'p1'`, `'p2'` string IDs. Group balance computation relies on ID equality.

**How to avoid:** When building participants for `groupBalancesProvider`, always source IDs from `event.participantIds` (which are Firebase UIDs) and from `groupMembersProvider` (which returns `GroupMember.userId` = Firebase UID). Run a quick assertion in debug mode: every `payerParticipantId` in an expense should exist in the group member list.

**Warning signs:** Group balance shows zero for everyone even though events have expenses. Individual event balances work but group balance does not.

### Pitfall 2: ref.watch in Provider.family Loops (Correct Usage)

**What goes wrong:** Using `ref.watch` in a loop inside a `StreamProvider.family` body is invalid (stream bodies cannot yield synchronously). However, inside a regular `Provider.family` body, `ref.watch` in a loop IS valid and correct — Riverpod tracks all watched dependencies regardless of loop structure.

**Why it happens:** Confusion between `Provider.family` (synchronous computation body) and `StreamProvider.family` (async stream body).

**How to avoid:** `groupBalancesProvider` must be `Provider.family`, not `StreamProvider.family`. The result type is `AsyncValue<GroupBalances>` to communicate loading/error states.

**Warning signs:** If using StreamProvider with a loop, `ref.watch` calls inside the stream body will throw `StateError` about watching providers in async generators.

### Pitfall 3: Group Settlement `tripId` Field

**What goes wrong:** `Settlement` model has a required `tripId` field (legacy from Supabase). Group settlements don't belong to a trip/event. Passing an empty string or `groupId` as `tripId` can cause confusion.

**Why it happens:** The `Settlement` model was built event-scoped. The `scope` field (D-10) distinguishes group vs. event, but `tripId` still needs a value.

**How to avoid:** For group settlements, set `tripId = groupId` (document this convention clearly in the model). Alternatively, make `tripId` nullable — but this is a larger model change. The simplest path: `tripId = groupId` as a sentinel for `scope == 'group'` settlements.

**Warning signs:** `fromFirestore` throws a null assertion on `tripId` for group settlements.

### Pitfall 4: BalanceCalculator with Empty Participant List

**What goes wrong:** When building participants for `groupBalancesProvider` from `groupMembersProvider`, if the members stream hasn't loaded yet, the participant list is empty. `BalanceCalculator.calculateBalances` returns `[]` when `participants.isEmpty` (line 222 in expense_provider.dart). The group balance silently shows nothing.

**Why it happens:** Race condition between `groupMembersProvider` resolving and `groupBalancesProvider` computing.

**How to avoid:** Check `groupMembersAsync.hasValue` before running BalanceCalculator. Return `AsyncValue.loading()` if members haven't loaded. This is already the pattern used by `eventBalancesProvider` (lines 114-121 in expense_provider.dart).

**Warning signs:** Group balance section shows loading spinner indefinitely or shows "0 members, 0 balances" even though events exist.

### Pitfall 5: Firestore `orderBy` on `timestamp` for Activity Logs with `FieldValue.serverTimestamp()`

**What goes wrong:** When writing activity logs with `FieldValue.serverTimestamp()` and immediately reading them via a stream, the pending write document has `timestamp = null` until the server round-trip completes. Ordering by `timestamp` descending can fail or place the pending doc incorrectly.

**Why it happens:** Firestore's offline-first writes return documents with `hasPendingWrites = true` and `FieldValue.serverTimestamp()` resolves to the device time locally, but ordering in queries uses the server value.

**How to avoid:** Use a client-side `DateTime.now().toIso8601String()` string field (as done in `ActivityService.addActivityLog`) rather than `FieldValue.serverTimestamp()` for the ordering field. Then use `Timestamp.fromDate(now)` for the server timestamp separately if needed. Alternatively, write a client timestamp as a fallback and accept minor ordering inconsistency for the optimistic write window.

**Warning signs:** Activity log shows the newly added entry at the bottom instead of the top, or the `orderBy` query fails with a missing index error.

### Pitfall 6: Per-Event Breakdown Missing Events Where User is Not a Participant

**What goes wrong:** A group member who was added to the group but not to a specific event will not appear in that event's `participantIds`. Their per-event breakdown for that event should show "Not a participant" or simply omit that event.

**Why it happens:** Group membership and event participation are separate. A user can be in the group but not in every event.

**How to avoid:** When building the per-event breakdown for a member, only include events where `event.participantIds.contains(memberId)`. The `_buildPerEventBreakdown` function naturally handles this because `BalanceCalculator` only processes participants in its list — but the UI should check `breakdown[memberId]?[eventId]` existence before rendering.

---

## Code Examples

### Combining Multiple Event Streams (verified against existing codebase)

```dart
// Source: pattern derived from eventBalancesProvider (expense_provider.dart lines 105-151)
// and groupEventsProvider (event_provider.dart lines 37-72)

// In groupBalancesProvider — aggregating N event streams:
final eventsAsync = ref.watch(groupEventsProvider(groupId));
final events = eventsAsync.valueOrNull ?? [];

for (final event in events) {
  final eventRef = (groupId: groupId, eventId: event.id) as EventRef;
  // These are StreamProviders — ref.watch returns AsyncValue<List<T>>
  final expensesValue = ref.watch(eventExpensesProvider(eventRef));
  final settlementsValue = ref.watch(eventSettlementsProvider(eventRef));
  // Use .valueOrNull to get data even if stale while refreshing
  allExpenses.addAll(expensesValue.valueOrNull ?? []);
  allSettlements.addAll(settlementsValue.valueOrNull ?? []);
}
```

### Adding a Group Settlement (new path)

```dart
// Source: SettlementService.addSettlement pattern (settlement_service.dart lines 53-78)
// Path changes from eventSubcollection() to direct group collection path

await db
    .collection('groups')
    .doc(groupId)
    .collection('settlements')
    .doc(id)
    .set({
  'id': id,
  'groupId': groupId,    // replaces 'eventId'
  'scope': 'group',      // D-10
  'payerParticipantId': payerUid,
  'recipientParticipantId': recipientUid,
  'amountFils': MoneySerializer.toSubunits(amount, 'OMR'),
  'currency': 'OMR',
  'note': note,
  'isDeleted': false,
  'deletedAt': null,
  'settledAt': now.toIso8601String(),
});
```

### Member Contribution Percentage (Decimal arithmetic)

```dart
// Source: BalanceCalculator.calculateTotalExpenses pattern (expense_provider.dart line 392)
// Never use double for intermediate calculation

Decimal totalSpent = BalanceCalculator.calculateTotalExpenses(allExpenses);

// Contribution % for each member
for (final balance in groupBalances) {
  final pct = totalSpent > Decimal.zero
      ? (balance.totalPaid / totalSpent * Decimal.fromInt(100))
          .toDecimal(scaleOnInfinitePrecision: 1)
      : Decimal.zero;
  // Display: '${pct.toStringAsFixed(1)}%' — only double conversion at Text()
}
```

### Fire-and-Forget Activity Log Write

```dart
// Source: existing ActivityService pattern
// unawaited() prevents async context leaks while not blocking the caller

import 'dart:async' show unawaited;

// Inside GroupSettleUpScreen._recordSettlement():
unawaited(
  groupActivityService.logGroupEvent(
    groupId: groupId,
    type: 'settlement_recorded',
    actorId: currentUid,
    actorName: currentUserName,
    description: '$fromName settled $amountFormatted with $toName',
    metadata: {
      'payerUid': fromUid,
      'recipientUid': toUid,
      'amountFils': MoneySerializer.toSubunits(amount, 'OMR'),
    },
  ),
);
```

### GroupMemberBalanceCard expand/collapse pattern

```dart
// Source: Flutter AnimatedCrossFade / flutter_animate pattern (flutter_animate is in pubspec)
// Use AnimatedSize for smooth height expansion

class GroupMemberBalanceCard extends StatefulWidget { ... }

class _GroupMemberBalanceCardState extends State<GroupMemberBalanceCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Container(
        // ... styling
        child: AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          child: Column(
            children: [
              _buildSummaryRow(),
              if (_expanded) _buildPerEventBreakdown(),
            ],
          ),
        ),
      ),
    );
  }
}
```

### Test Pattern for groupBalancesProvider

```dart
// Source: balance_calculations_test.dart + activity_service_test.dart patterns
// Provider test uses container + FakeFirebaseFirestore

test('groupBalancesProvider aggregates expenses across 2 events', () async {
  final fakeFirestore = FakeFirebaseFirestore();

  // Seed group with 2 events, each with 1 expense
  await fakeFirestore.collection('groups').doc('g1')
      .collection('events').doc('e1')
      .collection('expenses').doc('exp1').set({
    'id': 'exp1',
    'eventId': 'e1',
    'payerParticipantId': 'uid1',
    'amountFils': 30000,  // 30.000 OMR
    'currency': 'OMR',
    'scope': 'global',
    'isDeleted': false,
    'createdAt': DateTime.now().toIso8601String(),
  });

  // Override providers in ProviderContainer
  final container = ProviderContainer(overrides: [
    // inject FakeFirebaseFirestore via service providers
  ]);

  final result = container.read(groupBalancesProvider('g1'));
  // ... assert balances
});
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| SQLite group_ledger table | On-demand Firestore stream rollup | D-03 (Phase 5 decision) | Eliminates cache invalidation; always fresh |
| Per-event settle-up only | Group-level settle-up | Phase 5 | Surfaces the cross-event debt that is Rihla's core value prop |
| Separate members + balances sections | Merged members/balances section | D-29 | Fewer scrolls to reach financial info |

**Deprecated/outdated for this phase:**
- `group_ledger` SQLite table: exists in schema (DATA-04) but explicitly dead weight per D-03. The planner should NOT add any writes or reads to this table.

---

## Open Questions

1. **`groupBalancesProvider` loading state during partial data**
   - What we know: When a group has 10 events and 3 are still loading from Firestore, should the provider show loading or show partial balances?
   - What's unclear: The UX for "partial results visible, more loading" vs. "wait for all data before showing any".
   - Recommendation: Use partial results (show balances for events whose data has arrived, add a subtle "updating..." indicator if `isLoadingAny` is true). This is what `eventBalancesProvider` does — it uses `valueOrNull` and falls back to empty list. Consistent.

2. **GroupMember.userId vs. event.participantIds alignment**
   - What we know: Phase 4 migrated event participants to use Firebase UIDs as participant IDs. GroupMember.userId is also a Firebase UID. D-04 says UID matching works.
   - What's unclear: Whether ALL existing events created before Phase 4 have UID-based participantIds or some have legacy UUID-based IDs.
   - Recommendation: The planner should include a verification step: read `event.participantIds` for any event and confirm they are Firebase UIDs (format: 28-character alphanumeric strings) not UUID v4 format.

3. **`GroupActivityLog` model — new model or reuse `ActivityLog`?**
   - What we know: Group activity has different fields (no `eventId` as primary, different action types). The existing `ActivityLog` model is event-scoped.
   - What's unclear: Whether reusing `ActivityLog` with nullable fields creates confusion.
   - Recommendation: Create a new `GroupActivityLog` model. It's simpler than adding nullable fields to `ActivityLog` and avoids confusion about which fields apply where. Small file (~50 lines).

---

## Environment Availability

Step 2.6: SKIPPED (no new external dependencies — all required tools and services are already confirmed in-use from prior phases).

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | flutter_test (Flutter SDK built-in) + fake_cloud_firestore 4.1.0+1 + mocktail 1.0.4 |
| Config file | none — standard Flutter test runner |
| Quick run command | `flutter test test/unit/` |
| Full suite command | `flutter test` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| FIN-01 | Per-event balance returns correct net per member | unit | `flutter test test/unit/balance_calculations_test.dart` | ✅ (extend existing) |
| FIN-02 | Group balance aggregates expenses across 2+ events | unit | `flutter test test/unit/group_balance_provider_test.dart` | ❌ Wave 0 |
| FIN-03 | Expand/collapse shows per-event breakdown | widget | `flutter test test/features/group_balance_card_test.dart` | ❌ Wave 0 |
| FIN-04 | GroupSettleUpScreen shows correct optimized settlements | widget | `flutter test test/features/group_settle_up_screen_test.dart` | ❌ Wave 0 |
| FIN-05 | Group balance updates when new settlement recorded | unit | `flutter test test/unit/group_balance_provider_test.dart` | ❌ Wave 0 |
| FIN-06 | Spending stats: total and contribution % computed correctly | unit | `flutter test test/unit/group_balance_provider_test.dart` | ❌ Wave 0 |
| FIN-07 | calculateOptimalSettlements works on group-level balances | unit | `flutter test test/unit/balance_calculations_test.dart` | ✅ (extend existing) |
| GRP-04 | GroupDetailScreen renders all 6 financial sections | widget | `flutter test test/features/group_detail_screen_test.dart` | ❌ Wave 0 |
| GRP-05 | GroupActivityService writes and reads 5 action types | unit | `flutter test test/unit/group_activity_service_test.dart` | ❌ Wave 0 |

### Sampling Rate
- **Per task commit:** `flutter test test/unit/`
- **Per wave merge:** `flutter test`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `test/unit/group_balance_provider_test.dart` — covers FIN-02, FIN-05, FIN-06 (use ProviderContainer + fake services)
- [ ] `test/unit/group_activity_service_test.dart` — covers GRP-05 (use FakeFirebaseFirestore, mirror activity_service_test.dart)
- [ ] `test/features/group_detail_screen_test.dart` — covers GRP-04 (widget test with overridden providers)
- [ ] `test/features/group_balance_card_test.dart` — covers FIN-03 (expand/collapse interaction test)
- [ ] `test/features/group_settle_up_screen_test.dart` — covers FIN-04 (widget test with mock groupBalancesProvider)

---

## Project Constraints (from CLAUDE.md)

| Directive | Impact on Phase 5 |
|-----------|------------------|
| **Immutability** — always create new objects, never mutate | `allExpenses` must be `[...list1, ...list2]` spread, not `addAll` on a provider-emitted list. All new models use `copyWith` pattern. |
| **Decimal package for all money** | Contribution % computation, total spent, and per-event breakdown must use `Decimal` throughout. Convert to `double` only at `Text()`. |
| **TDD mandatory** — write tests first | Wave 0 creates test files before implementation. Each plan starts with failing tests. |
| **80%+ test coverage** | Full coverage targeted in Phase 6 (D-40). Phase 5 covers priority tests (D-40/D-41). |
| **Feature-first directory structure** | New files go in `lib/features/groups/` for group features, `lib/features/ledger/` for settlement model changes. |
| **200-400 lines typical per file, 800 max** | `GroupDetailScreen` is currently ~395 lines. After adding 6 sections it will exceed 800. Extract sections into separate widget files in `lib/features/groups/widgets/`. |
| **GSD workflow enforcement** — do not make direct repo edits outside GSD | Phase execution proceeds through `gsd:execute-phase`. |
| **No hardcoded values** — use constants | Currency `'OMR'` should come from `group.currency`. Activity type strings should be constants in `GroupActivityService`. |

---

## Sources

### Primary (HIGH confidence)

- Direct codebase reads — all code examples verified against actual source files
  - `lib/features/ledger/providers/expense_provider.dart` — BalanceCalculator, eventBalancesProvider pattern
  - `lib/features/ledger/services/settlement_service.dart` — SettlementService pattern for GroupSettlementService
  - `lib/features/activity/services/activity_service.dart` — ActivityService fire-and-forget pattern
  - `lib/features/groups/screens/group_detail_screen.dart` — current structure being extended
  - `lib/features/groups/providers/group_provider.dart` — groupMembersProvider, groupDetailProvider patterns
  - `lib/features/events/providers/event_provider.dart` — groupEventsProvider pattern
  - `lib/core/services/firestore_repository.dart` — FirestoreRepository base class
  - `security/firestore.rules` — existing rules covering group subcollections
  - `lib/features/ledger/models/settlement_model.dart` — Settlement model fields
  - `lib/features/ledger/screens/settle_up_screen.dart` — template for GroupSettleUpScreen
  - `lib/features/events/widgets/event_spending_hero.dart` — template for group balance hero card
  - `lib/features/groups/widgets/group_member_tile.dart` — widget being extended

### Secondary (MEDIUM confidence)

- Riverpod 2.x documentation — `ref.watch` in loops inside `Provider.family` bodies is valid per Riverpod 2.x semantics. Verified by existing `eventBalancesProvider` pattern which uses conditional `ref.watch` calls.
- Firestore generic subcollection security rules — the existing catch-all `match /{subcollection}/{docId}` rule verified to cover `settlements` and `activity` subcollections.

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all packages already in pubspec.yaml, versions verified
- Architecture patterns: HIGH — derived from reading actual production code in the codebase
- Security rules: HIGH — verified by reading firestore.rules directly; no changes needed
- BalanceCalculator extension: HIGH — pure function, extending is straightforward
- GroupBalancesProvider stream composition: MEDIUM — Riverpod loop-watch pattern is established but the specific `AsyncValue<GroupBalances>` result type with partial loading behavior needs care
- Pitfalls: MEDIUM-HIGH — participant identity pitfall is flagged as the most likely failure mode

**Research date:** 2026-03-27
**Valid until:** 2026-04-27 (Riverpod 2.x is stable; no expected breaking changes in window)
