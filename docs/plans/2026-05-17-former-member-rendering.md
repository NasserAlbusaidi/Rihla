# Task: Render dormant anon-UID creators/payers as "former member" (v6)

> v1 → v2 closed four architectural [P1]s. v2 → v3 closed two implementation-shape
> [P1]s and three [P2]s. v3 → v4 fixed Step B's `events.expand` over-expansion +
> the `?? fromName` persistence fallback, and corrected four file:line errors that
> the in-session spec-verification checklist caught. v4 → v5 replaced the flat
> `calculateBalances` call with per-event computation summed at the user level.
> v5 → v6 fixes the codex-v5 [P1]: v5's per-event sum aggregated `totalPaid` and
> `totalOwed` only, but `BalanceCalculator` builds `netBalance = (totalPaid +
> settlementAdj) - totalOwed` at `expense_provider.dart:305` — event-scoped
> settlement adjustments live in `netBalance` only, so summing paid/owed silently
> drops them. v6 sums `netBalance` per UID alongside `totalPaid`/`totalOwed`,
> making `netBalance` the source-of-truth for the final net (paid/owed remain as
> informational aggregates for display fields). v6 also mirrors the
> `(former member)` suffix rejection into `displayNameMapValuesAreValid` (used
> by `event.participantNames`), notes the product side-effect that group/event
> names inherit the suffix ban, and extends acceptance #10 to grep group-scoped
> settlements too. Codex review sessions share session
> `019e33d0-b65a-7053-a08b-c5e8c4a3c136` (`.context/codex-session-id`).

## Context

Rihla uses Firebase anonymous auth. Each anon UID gets stamped onto historical Firestore records as `event.createdBy`, `expense.payerParticipantId` (the `paidBy` UID), `settlement.payerParticipantId` / `settlement.recipientParticipantId`, and `activityLog.actorId`. When a user later recovers their account via email link, a new UID takes over and the v1.2 server-side post-recovery cleanup callable repoints membership to the new UID. But:

1. **Pre-recovery cleanup callable wasn't always there.** Some anon UIDs predate that flow.
2. **The cleanup callable cannot delete real historical attribution.** UIDs that appear as `paidBy` on expenses or `from`/`to` on settlements are intentionally left behind so financial history stays accurate.
3. **Some anon UIDs never recovered at all** — original device lost/wiped, user never linked an email. Those UIDs are forever orphaned.

Production canary: group `78cb99b0…` has one dormant anon UID that is `createdBy` on 5 events, `payerParticipantId` on 1 expense, and `payerParticipantId` on 1 settlement. There is no live `groups/{gid}/members/{uid}` doc for it, and no tombstone either. Today the UI either silently drops that UID, or renders one of several stale-string fallbacks: `'Member'`, `'Someone'`, `'Unknown'`. None of those communicate to the user *who* this balance row corresponds to, and the group settle-up sheet is materially broken because the UID is filtered out *before* the balance calculation even runs.

The fix is **UI-and-derived-state-only**: synthesize a participant entry for every orphan UID found in expenses/settlements before `BalanceCalculator` runs, resolve a stable display name from the data already loaded, and render `'<name> (former member)'` everywhere a member name appears for that UID. **No Firestore writes, no server migration, no schema changes, no tombstone backfill.**

### Why this isn't a server-side tombstone backfill

The `+16` follow-up tracked in `docs/REAL-DEVICE-QA.md:242` is explicit: *"Fix is UI-level: mark `participantIds` entries whose UID is no longer in `group.memberIds` as 'former member' rather than deleting their data."* A server backfill (synthesise a tombstone `groups/{gid}/members/{uid}` doc for every orphan UID across every group) would require iterating every group + every event + every expense + every settlement to enumerate orphan UIDs, choosing a display name from competing sources at migration time, baking one choice in forever, racing with active recovery flows, and shipping a one-time script we'd have to maintain or delete. The client already reads every Firestore field needed; centralising the resolution and rendering gets the same UX outcome with zero server change.

### Tombstones the resolver must still handle

The v1.2 server-side account deletion flow (`functions/src/callables/deleteAccount.ts` + `lib/features/auth/services/data_deletion_service.dart`) creates tombstone `GroupMember` docs (`isTombstone: true`) when a user deletes their account. These already arrive via `groupMembersProvider` (no filter at `lib/features/groups/providers/group_provider.dart:408-423`). The resolver must render tombstones identically to dormant orphan UIDs — same `(former member)` suffix — so future tombstones are covered by the same code path with no extra work.

## Goal

1. Add a centralised UID → `(rawName, isFormer)` resolver as a pure utility.
2. **Expand the group-level participant set** in `groupBalancesProvider` to include orphan UIDs found in expenses/settlements *before* `BalanceCalculator.calculateBalances` runs — otherwise the resolver has nothing to name. (v1 spec missed this and would have shipped a no-op for group settle-up.)
3. Route every live render site through the resolver's `formatDisplay()` helper.
4. **Keep raw names separate from display strings on the write path.** Settlement creation callbacks must persist the raw name, never the `(former member)`-suffixed display string. (v1 spec would have leaked formatted strings into Firestore.)

Behavior changes: dormant anon UIDs and tombstoned members now render with their last-known name + `(former member)` suffix and appear as balance rows in group settle-up. Risk: medium — pure client rendering + a derived-state expansion, no Firestore writes, no schema changes, no security rule changes. Verified across the live render surface (12 sites) before writing this spec.

## Constraints

### Scope is the rendering pipeline + the one derived-state expansion required to make rendering possible

- Add the resolver, the participant-set expansion in `groupBalancesProvider`, and edits to render leaves. No model changes.
- Do not change `GroupMember`, `Event`, `Expense`, `Settlement`, or `ActivityLog` models.
- Do not change Firestore schema or Cloud Functions. **One additive change to `security/firestore.rules`:** extend `isValidDisplayName` and `displayNameMapValuesAreValid` with a trailing-suffix rejection so `' (former member)'` cannot be persisted as a display name or `event.participantNames` map value (mirror of the client validator change — see "Edit — display name validator" below). No other rule changes; no schema/collection/index changes.
- Do not backfill tombstones, run a migration, or write a script.
- Do not rewrite `BalanceCalculator`. It stays untouched — it operates on `Participant` records and is name-agnostic.

### Activity logs are out of scope (already stable)

`ActivityLog.actorName` (`lib/features/activity/models/activity_log_model.dart:11`) is precomputed at write time and persisted to both Firestore and SQLite. Historical logs render the actor's name as it was at the time of the action. Touching activity rendering would relabel historically-correct entries — the actor was *not* "former" at the time of the action.

### Event creator label is out of scope

`Event.createdBy` (`lib/features/events/models/event_model.dart:67`) is stored but never rendered in any current screen. Adding event creator attribution is a separate UX decision.

### EventCommandCenter is in scope (still routable) — but flagged

EventCommandCenter renders payer names at `lib/features/events/screens/event_command_center.dart:733-735` and `:1008`. Per `CLAUDE.md`, the UI bypasses it (event cards jump to `/event/:eid/ledger`), but the route `/event/:eid` is still wired at `lib/core/router/app_router.dart:266-276` and reachable via deep link or direct typing. Fix it — it's a five-line change in two places — and add an inline comment noting that EventCommandCenter is kept for deep-link compatibility per CLAUDE.md.

### Visual treatment is a textual suffix, single source of truth

- Append `' (former member)'` to the rendered name. Example: `'Aisha (former member)'`. Codex review weighed `(former)` vs `(former member)`; for a financial app where status materially affects how users read a balance row, the explicit form is worth the extra width.
- Do **not** introduce a new color, a new font style, an italic variant, or a new shared widget. The existing typography and color tokens are sufficient. A textual marker is unambiguous, accessible, screen-reader-friendly, and avoids color-token churn.
- The suffix lives in a single constant `MemberNameResolver.formerSuffix` so future Arabic localisation can swap it in one place (queued post-launch per memory).

### Resolution order (scope-dependent, deterministic)

**Group-scoped lookups** (`groupBalancesProvider`, group settle-up, group detail member rows):
1. Live group member — `members.firstWhereOrNull((m) => m.userId == uid && !m.isTombstone)` against `groupMembersProvider(groupId)`. Return `(member.displayName, isFormer: false)`.
2. Tombstone group member — same stream, `m.userId == uid && m.isTombstone`. Return `(member.displayName, isFormer: true)`.
3. **Caller-supplied fallback name map** — see "Fallback name pre-build" below. Return `(name, isFormer: true)`.
4. Last resort — `('Former member', isFormer: true)`. No raw UID is ever exposed.

**Event-scoped lookups** (`ledger_screen`, event settle-up, event command center, ledger search hits for event-scoped expenses):
1. `event.participantNames[uid]` if present — historical name at event creation. Return `(name, isFormer: !liveMember)`. **Historical-first** is the policy: if a member changed their display name after the event was created, the per-event row keeps the name they had when the expense was added. This matches current behavior at `lib/features/ledger/screens/ledger_screen.dart:87-89` and `:166`; the spec preserves it.
2. Live group member (same UID). Return `(member.displayName, isFormer: false)`.
3. Tombstone group member. Return `(member.displayName, isFormer: true)`.
4. Caller-supplied fallback. Return `(name, isFormer: true)`.
5. Last resort — `('Former member', isFormer: true)`.

The resolver is a pure synchronous function over already-loaded data. It does not perform Firestore reads. Callers pass `List<GroupMember>` / nullable `Event` / nullable `Map<String, String>` fallback map. **Live-wins-over-tombstone** is the right default; if both exist for the same UID that's a data bug and the UI should not mark a live member as former.

### Fallback name pre-build (group-scoped) — `event.participantNames` is the primary source

For the production canary case (dormant UID is `createdBy` on events) the most reliable name source is `event.participantNames[uid]` — populated at event creation by the user who knew the orphan UID at the time. Modern Firestore expenses do not carry `payerName` (`Expense.fromFirestore` at `expense_model.dart:173-198` does not populate it; `toFirestore` at `:201-206` explicitly excludes it from writes). So a fallback chain that scans only expenses + settlements will rarely find anything for the canary; codex v2 review called this out explicitly.

The fallback `Map<String, String> uidToFallbackName` is built once per `groupBalancesProvider` rebuild, in this priority order (**first-write-wins** so the highest-priority source sticks):

1. **`event.participantNames` across all loaded events** — iterate `for event in events: for (uid, name) in event.participantNames: uidToFallbackName[uid] ??= name`. Highest priority because it's the most populated source and reflects the name the user knew when the record was created.
2. **`Settlement.payerName` / `Settlement.recipientName` from `allSettlements`** — second-priority because settlements consistently carry names today (both event-scoped and group-scoped settlement creation paths persist them).
3. **`Expense.payerName` from `allExpenses`** — last-priority and rarely effective for Firestore-sourced expenses; kept in the chain because legacy SQLite-cached expenses may still carry it.

The build is a single linear pass over `events`, `allSettlements`, `allExpenses` — O(events + settlements + expenses) total, not `O(uidCount * recordCount)`. The resulting map is then handed to `MemberNameResolver.resolveGroupScoped` as the fallback for any UID not found in live or tombstone members.

### Two return shapes — raw vs. formatted — to prevent persistence leakage

The resolver exposes two methods:

- `MemberNameResolver.resolveGroupScoped(...)` / `MemberNameResolver.resolveEventScoped(...)` return `MemberDisplay { String rawName; bool isFormer; }`. Used by write paths (settlement creation) and any caller that needs the unadorned name (the `'You'` branch + the `event_command_center` first-name truncation).
- `MemberNameResolver.format(MemberDisplay)` returns the display string: `'Aisha (former member)'` if `isFormer`, else `'Aisha'`. Used by render leaves.

### Concrete data contracts (added in v3 — these are the implementation-level shapes)

The v2 spec said "two different shapes" without nailing them down. Codex v2 review correctly called this out as the place the Firestore leak would reappear. The shapes below are normative; the implementation MUST match them or pick an explicitly equivalent variant documented inline.

**`groupBalancesProvider` return record** — adds one new field, no renames:

```dart
({
  List<UserBalance> balances,
  Decimal totalSpent,
  int eventCount,
  Map<String, Map<String, Decimal>> perEventBreakdown,
  Map<String, String> memberNames,      // uid -> FORMATTED display string ("Aisha (former member)")
  Map<String, String> memberRawNames,   // uid -> RAW name ("Aisha") — NEW
})
```

Consumers that render a name with no further user-input context (group detail member rows, group settle-up tiles for display) use `memberNames`. Consumers on the write path (the `onRecord` callback wiring in `SettleUpPageBody`) look up `memberRawNames[uid]` and pass that into settlement creation.

**`BalanceCalculator.calculateOptimalSettlements` return-element map keys** — keep the existing shape; the caller does NOT mutate the optimal-settlement records to add raw names. Instead, the caller (`SettleUpPageBody` / `GroupSettleUpScreen`) holds a sibling `Map<String, String> rawNames` keyed by uid, and looks up `rawNames[fromUserId]` / `rawNames[toUserId]` at the `onRecord` callsite.

The optimal-settlement map keeps its current keys (`fromUserId`, `toUserId`, `fromUserName`, `toUserName`, `amount`). The `fromUserName` / `toUserName` are FORMATTED — they feed tile display. Renaming them would touch every test and consumer; the cleaner change is the sibling `rawNames` map.

**`SettleUpPageBody.onRecord` callback signature** — parameter names change to make raw/formatted impossible to confuse:

Before (current):
```dart
({
  required Map<String, dynamic> settlement,
  required String fromName,        // ambiguous
  required String toName,          // ambiguous
  required String fromUserId,
  required String toUserId,
  required Decimal suggestedAmount,
}) -> void
```

After (v3):
```dart
({
  required Map<String, dynamic> settlement,
  required String fromRawName,     // CHANGED — explicitly raw, no suffix
  required String toRawName,       // CHANGED
  required String fromUserId,
  required String toUserId,
  required Decimal suggestedAmount,
}) -> void
```

The callsite at `settle_up_page_body.dart:124-160` constructs the callback args as (`SettleUpPageBody` is `StatelessWidget` at `:22`, so constructor fields are accessed directly — no `widget.` prefix):
```dart
onRecord: () => onRecord(
  settlement: settlement,
  fromRawName: rawNames[fromUserId] ?? MemberNameResolver.stripFormerSuffix(fromName),
  toRawName: rawNames[toUserId] ?? MemberNameResolver.stripFormerSuffix(toName),
  fromUserId: fromUserId,
  toUserId: toUserId,
  suggestedAmount: amount,
),
```

The fallback is `MemberNameResolver.stripFormerSuffix(fromName)`, **not** the bare formatted string. `stripFormerSuffix` is a pure helper added to the resolver: `value.endsWith(formerSuffix) ? value.substring(0, value.length - formerSuffix.length) : value`. Codex v3 review caught that a bare-formatted defensive fallback would silently persist `(former member)` to Firestore.

**Codex v4 review then caught a follow-on edge:** if a user picked `'Aisha (former member)'` as their display name, `stripFormerSuffix` would mutate it to `'Aisha'` in release builds, silently corrupting user-chosen data. v5 closes that edge by extending the existing `isValidDisplayName` validator at `lib/core/utils/name_validators.dart:3` (and its mirror in `security/firestore.rules`) to **reject any name ending in `' (former member)'`**. With the validator change, no legitimate user-chosen name can end in the suffix — so `stripFormerSuffix` is provably safe for any string it ever sees: if it ends in the suffix, the suffix was added by the formatter and stripping recovers the raw name; if it doesn't, the string is returned unchanged.

The validator extension is a small additive rule — existing names that happen to end in `(former member)` (no users have this today; the suffix wording is new in v5) would only fail validation on the next rename attempt, never spontaneously. The server-side mirror in `firestore.rules` enforces the same rule for any client that bypasses validation.

Combined with the in-debug-mode assertion `assert(rawNames.containsKey(fromUserId), 'rawNames must include every settlement participant');`, the fallback never silently masks a real wiring bug in dev, while still keeping writes raw in release if a UID slips through.

(`assert` is compiled out of release builds in Flutter, so the contract is enforced at development time but never crashes a user.)

**`SettleUpScreen` (event-scoped) — dual map construction**

Event settle-up does NOT consume `groupBalancesProvider`. It builds its own event-local participants + name maps at `settle_up_screen.dart:90-97`. v3 specifies dual map construction here too:

```dart
// Build BOTH maps in one pass over event.participantIds:
final Map<String, String> userDisplayNames = {};
final Map<String, String> userRawNames = {};
for (final uid in event.participantIds) {
  final display = MemberNameResolver.resolveEventScoped(
    uid: uid,
    event: event,
    members: groupMembers,
    fallbackName: null,  // event-scoped lookup uses event.participantNames as primary source
  );
  userDisplayNames[uid] = MemberNameResolver.format(display);
  userRawNames[uid] = display.rawName;
}
```

`userDisplayNames` feeds `BalanceCalculator.calculateOptimalSettlements`. `userRawNames` is passed into `SettleUpPageBody.rawNames` constructor param. Settlement creation at `settle_up_screen.dart:274-275` consumes `fromRawName` / `toRawName` from the callback, never the formatted strings.

`GroupSettleUpScreen` follows the same pattern but uses `resolveGroupScoped` against the group-level fallback map.

**Persisted writes — final enumeration** (these are the lines the implementer must not get wrong):
- `lib/features/ledger/screens/settle_up_screen.dart:274-275` — event settlement creation receives `fromRawName` / `toRawName` from the callback, writes to `Settlement.payerName` / `recipientName`.
- `lib/features/groups/screens/group_settle_up_screen.dart:339-340` — group settlement creation, same pattern.
- No other write path should be touched by this spec. Grep `Settlement(` constructor invocations in the modified files to confirm.

**Current-user `'You'` label is preserved at the leaf, not in the resolver.** Today `lib/features/ledger/widgets/ledger_day_card.dart` `_ExpenseRow.build` renders `final payerName = isPayer ? 'You' : (expense.payerName ?? 'Member');` and `event_command_center.dart:733-735` renders `expense.payerParticipantId == currentUid ? 'You paid' : '${...} paid'`. Both call sites continue to short-circuit to `'You'` *before* asking the resolver. The resolver's job is only to name UIDs that aren't the current user; the `(former member)` suffix never appears next to "You" because the current user can't be former.

## Files to touch

### New

- `lib/features/groups/services/member_name_resolver.dart` — pure Dart, no Riverpod, no Firebase. ≤ 110 lines. Exposes:
  - `MemberDisplay { String rawName; bool isFormer; }` record/class.
  - `MemberNameResolver.resolveGroupScoped({required String uid, required List<GroupMember> members, String? fallbackName})` → `MemberDisplay`.
  - `MemberNameResolver.resolveEventScoped({required String uid, required Event event, required List<GroupMember> members, String? fallbackName})` → `MemberDisplay`.
  - `MemberNameResolver.format(MemberDisplay)` → `String` (appends `formerSuffix` when `isFormer`).
  - `MemberNameResolver.formerSuffix` → `' (former member)'` (constant).
  - `MemberNameResolver.formerMemberLiteral` → `'Former member'` (the last-resort raw-name constant, exported so `event_command_center` can short-circuit truncation against it).
  - `MemberNameResolver.stripFormerSuffix(String value) → String` — pure helper: returns `value` with `formerSuffix` removed if present, else `value` unchanged. Used by the defensive fallback in the `onRecord` callsite to guarantee raw-name persistence even if the upstream `rawNames` map is missing a uid.
- `test/unit/member_name_resolver_test.dart` — covers every branch of both scopes, live-wins-over-tombstone, fallback-name path, last-resort, and `format()` suffix application (live → no suffix, every isFormer source → suffix).
- `test/features/groups/group_balance_provider_orphan_uid_test.dart` — provider-level test: given a group with one live member plus one expense `payerParticipantId` and one settlement `payerParticipantId` referencing a UID with no `GroupMember` doc, `groupBalancesProvider` returns a balance row for the orphan UID with the synthesized name and the orphan participates in net balances.
- `test/features/ledger/ledger_day_card_former_member_test.dart` — widget test: `LedgerDayCard` renders `'Aisha (former member)'` for an expense whose `payerParticipantId` matches an orphan UID (mocked event participantNames).
- `test/features/groups/settle_up_page_body_former_member_test.dart` — widget test: `SettleUpPageBody` net-balances list renders the formatted string for an orphan UID, AND `onRecord` callback receives the raw name (not the formatted one) when the user taps record-payment.

### Edit — provider layer (per-event aggregation, v6)

The v4 design called for a single aggregate `BalanceCalculator.calculateBalances` call with a participants list expanded to include orphan UIDs. Codex v4 review correctly identified that this still corrupts `global`-scope expense math: adding an orphan from Event A to the flat participants list means every `global`-scope expense gets split across the expanded list regardless of which event the expense came from. The orphan ends up charged for expenses in events they were never part of.

The fix is **per-event balance computation summed at the user level**, with all settlements applied in a single end-pass. This mirrors how `_buildPerEventBreakdown` (at `lib/features/groups/providers/group_balance_provider.dart:224-264`) already works for the per-event drill-down map. The aggregate `balances` list now consumes the same machinery.

**`lib/features/groups/providers/group_balance_provider.dart`** — replace the body from approximately `:175-208` (the current Steps 5-8 that build `participants`, call `calculateBalances` once, and build `memberNames`) with the algorithm below. Steps 1-4 (event loading) and Step 9 (per-event breakdown, return) are unchanged.

```
// === v5 aggregate-balance computation ===

// (1) Build the uidToFallbackName map ONCE for the whole group.
//     Priority order is first-write-wins, per "Fallback name pre-build" above:
//       (a) event.participantNames across all events
//       (b) Settlement.payerName / recipientName from all settlements
//       (c) Expense.payerName from all expenses
final uidToFallbackName = <String, String>{};
for (final event in events) {
  for (final entry in event.participantNames.entries) {
    uidToFallbackName.putIfAbsent(entry.key, () => entry.value);
  }
}
for (final s in allSettlements) {
  if (s.payerParticipantId != null && s.payerName != null) {
    uidToFallbackName.putIfAbsent(s.payerParticipantId!, () => s.payerName!);
  }
  if (s.recipientParticipantId != null && s.recipientName != null) {
    uidToFallbackName.putIfAbsent(s.recipientParticipantId!, () => s.recipientName!);
  }
}
for (final e in allExpenses) {
  if (e.payerName != null) {
    uidToFallbackName.putIfAbsent(e.payerParticipantId, () => e.payerName!);
  }
}

// (2) Build a per-event index of expenses + settlements so we can iterate cleanly.
//     (allExpenses and allEventSettlements are already collected by Step 4; partition them.)
final expensesByEvent = <String, List<Expense>>{};
final eventSettlementsByEvent = <String, List<Settlement>>{};
for (final event in events) {
  expensesByEvent[event.id] = [];
  eventSettlementsByEvent[event.id] = [];
}
for (final e in allExpenses) {
  expensesByEvent[e.tripId]?.add(e);  // tripId is the event ID in the Phase-39 model
}
for (final s in allEventSettlements) {
  eventSettlementsByEvent[s.tripId]?.add(s);
}

// (3) Per-event accumulation. Compute event-local balances using event-local
//     participants (live + event-local financial orphans). Sum per-user.
//
// IMPORTANT (v6): we must sum `netBalance` per UID, not just totalPaid/totalOwed.
// BalanceCalculator at expense_provider.dart:305 builds
//   netBalance = (totalPaid + settlementAdj) - totalOwed
// where settlementAdj captures the event-scoped settlement effects. If we only
// sum totalPaid + totalOwed across events, settlement adjustments vanish from
// the aggregate. Source-of-truth for the final net is sum(b.netBalance) +
// groupSettlementAdj. totalPaid/totalOwed are kept as informational aggregates
// (UserBalance.totalPaid/totalOwed are consumed by some UI as "lifetime paid"
// and "lifetime owed" — they decompose cleanly because BalanceCalculator builds
// them only from splits, no settlement contribution).
final totalPaidPerUid = <String, Decimal>{};
final totalOwedPerUid = <String, Decimal>{};
final netBalancePerUid = <String, Decimal>{};  // includes event-scoped settlement adjustments
final liveMemberIds = members.map((m) => m.userId).toSet();
final allOrphansSeen = <String>{};  // for memberNames/memberRawNames maps later

for (final event in events) {
  final eventExpenses = expensesByEvent[event.id] ?? const <Expense>[];
  final eventSettlements = eventSettlementsByEvent[event.id] ?? const <Settlement>[];

  // Event-local financial orphans = UIDs in this event's expenses/settlements
  // that are NOT live members of the group AND are not already in this event's
  // participantIds. (event.participantIds may already cover them — no harm if so;
  // the Set deduplicates.)
  final eventFinancialUids = <String>{
    for (final e in eventExpenses) e.payerParticipantId,
    for (final s in eventSettlements) ...[
      if (s.payerParticipantId != null) s.payerParticipantId!,
      if (s.recipientParticipantId != null) s.recipientParticipantId!,
    ],
  };
  final eventLocalOrphans = eventFinancialUids.difference(liveMemberIds);
  allOrphansSeen.addAll(eventLocalOrphans);

  final eventParticipantUids = <String>{
    ...event.participantIds,
    ...eventLocalOrphans,
  };
  if (eventParticipantUids.isEmpty) continue;

  final eventParticipants = eventParticipantUids.map((uid) {
    final display = MemberNameResolver.resolveGroupScoped(
      uid: uid,
      members: members,
      fallbackName: uidToFallbackName[uid],
    );
    return Participant(
      id: uid,
      tripId: event.id,
      role: ParticipantRole.member,
      joinedAt: event.createdAt,
      // NOTE: formatted, NOT raw. UserBalance.displayName is consumed by
      // group_detail_screen._MemberRow at :831 with the pattern
      // `balances[i].displayName ?? memberNames[...] ?? 'Member'`. If we
      // pass raw here, the raw string wins the ?? chain and the
      // (former member) suffix never renders. Raw is exposed only via
      // memberRawNames (built in step 6) and consumed by write paths.
      displayName: MemberNameResolver.format(display),
    );
  }).toList();

  // Per-event balance — pass event-scoped settlements so they're correctly
  // adjusted in this event's math.
  final eventBalances = BalanceCalculator.calculateBalances(
    expenses: eventExpenses,
    settlements: eventSettlements,
    participants: eventParticipants,
  );

  for (final b in eventBalances) {
    totalPaidPerUid.update(
      b.participantId,
      (v) => v + b.totalPaid,
      ifAbsent: () => b.totalPaid,
    );
    totalOwedPerUid.update(
      b.participantId,
      (v) => v + b.totalOwed,
      ifAbsent: () => b.totalOwed,
    );
    // v6: capture event-scoped settlement adjustments via netBalance.
    // BalanceCalculator builds b.netBalance = (totalPaid + settlementAdj) - totalOwed;
    // settlementAdj is the *only* place event-scoped settlements land.
    netBalancePerUid.update(
      b.participantId,
      (v) => v + b.netBalance,
      ifAbsent: () => b.netBalance,
    );
  }
}

// (4) Apply group-scoped settlements at the user level. Event-scoped
//     settlements were already captured per-event via netBalancePerUid in step 3.
//     Group-scoped settlements have no event affinity, so apply at the end.
final groupScopedSettlementAdj = <String, Decimal>{};
final groupSettlements = groupSettlementsAsync.valueOrNull ?? const [];
for (final s in groupSettlements) {
  if (s.payerParticipantId != null) {
    groupScopedSettlementAdj.update(
      s.payerParticipantId!,
      (v) => v + s.amount,
      ifAbsent: () => s.amount,
    );
  }
  if (s.recipientParticipantId != null) {
    groupScopedSettlementAdj.update(
      s.recipientParticipantId!,
      (v) => v - s.amount,
      ifAbsent: () => -s.amount,
    );
  }
}

// (5) Compose final UserBalance list. Every UID that ever appeared as a
//     financial actor (live member, tombstone, or orphan) gets a row.
final allUids = <String>{
  ...liveMemberIds,
  ...allOrphansSeen,
  ...totalPaidPerUid.keys,
  ...totalOwedPerUid.keys,
  ...netBalancePerUid.keys,
  ...groupScopedSettlementAdj.keys,
};
final balances = allUids.map((uid) {
  final display = MemberNameResolver.resolveGroupScoped(
    uid: uid,
    members: members,
    fallbackName: uidToFallbackName[uid],
  );
  final totalPaid = totalPaidPerUid[uid] ?? Decimal.zero;
  final totalOwed = totalOwedPerUid[uid] ?? Decimal.zero;
  final eventNet = netBalancePerUid[uid] ?? Decimal.zero;
  final groupSettleAdj = groupScopedSettlementAdj[uid] ?? Decimal.zero;
  // v6: net = sum(event netBalance) + group-scoped settlements.
  // The event sum already includes event-scoped settlement adjustments;
  // we do NOT recompute net from totalPaid - totalOwed (that would drop
  // event-scoped settlements — the v5 bug codex flagged).
  final netBalance = eventNet + groupSettleAdj;
  return UserBalance(
    participantId: uid,
    // Formatted for display — see note in step 3 on why this is formatted, not raw.
    displayName: MemberNameResolver.format(display),
    totalPaid: totalPaid,
    totalOwed: totalOwed,
    netBalance: netBalance,
  );
}).toList();

// (6) Build the two name maps in one pass over allUids.
final memberNames = <String, String>{};
final memberRawNames = <String, String>{};
for (final uid in allUids) {
  final display = MemberNameResolver.resolveGroupScoped(
    uid: uid,
    members: members,
    fallbackName: uidToFallbackName[uid],
  );
  memberNames[uid] = MemberNameResolver.format(display);
  memberRawNames[uid] = display.rawName;
}

// (7) Return the extended record. memberRawNames is the new field.
return AsyncValue.data((
  balances: balances,
  totalSpent: BalanceCalculator.calculateTotalExpenses(allExpenses),
  eventCount: events.length,
  perEventBreakdown: perEventBreakdown,  // unchanged, still from _buildPerEventBreakdown
  memberNames: memberNames,
  memberRawNames: memberRawNames,
));
```

**Why this is correct math:**

Two worked examples — one on the participant-set axis (the v4 bug), one on the settlement axis (the v5 bug). Per the spec-verification checklist, examples must exercise axes orthogonal to the most recent fix; v6 adds settlements to expose the v5 [P1].

*Example 1 — participant-set scope (regression test for v4 bug):*
Event A: {Alice, Bob, Orphan}. Orphan paid $30 global expense. Event B: {Alice, Bob}. Bob paid $30 global expense. No settlements.

- Event A balances: Orphan totalPaid=$30 totalOwed=$10 net=+$20. Alice totalPaid=$0 totalOwed=$10 net=-$10. Bob totalPaid=$0 totalOwed=$10 net=-$10.
- Event B balances: Bob totalPaid=$30 totalOwed=$15 net=+$15. Alice totalPaid=$0 totalOwed=$15 net=-$15.
- Sum netBalancePerUid: Alice -$25, Bob +$5, Orphan +$20.
- Orphan is **not charged for Bob's Event-B expense** (Orphan wasn't in Event B's participant set). ✓

Compare to the v4 (broken) flat-list math which would charge Orphan $10 for Bob's Event-B expense.

*Example 2 — event-scoped settlements (regression test for v5 bug):*
Event A: {Alice, Bob}. Bob paid $20 global expense. Then Alice records a $10 event-scoped settlement to Bob (`payer=Alice`, `recipient=Bob`, `amount=10`). No Event B, no group-scoped settlements.

Per `BalanceCalculator.calculateBalances`:
- Splits: Alice owes $10, Bob owes $10, Bob paid $20.
- Settlement adjustment map: Alice +$10 (payer), Bob -$10 (recipient).
- Returned balances: Alice {totalPaid=$0, totalOwed=$10, netBalance=(0 + 10) - 10 = $0}, Bob {totalPaid=$20, totalOwed=$10, netBalance=(20 + (-10)) - 10 = $0}.

v6 aggregation: `netBalancePerUid` = Alice $0, Bob $0. Final net (no group settlements): Alice $0, Bob $0. ✓ (Alice and Bob are settled — Bob fronted $20, Alice owed $10 of it, Alice paid back $10 via settlement, net zero.)

v5 (broken) aggregation would have computed: Alice net = $0 (paid) - $10 (owed) = -$10, Bob net = $20 (paid) - $10 (owed) = +$10. The $10 settlement would be silently dropped because it lives in `BalanceCalculator.netBalance` only, not in `totalPaid`/`totalOwed`. The settle-up UI would then prompt Alice to pay Bob another $10 — double-charging her.

**Note on `_buildPerEventBreakdown`:** unchanged. It already does per-event balance with `event.participantIds` only. v5 does not add orphan expansion to `_buildPerEventBreakdown` because its job is the drill-down view ("how much did THIS member net in EACH event"), which uses live event-participant identity. The aggregate `balances` list is the authoritative source for who-shows-up-in-settle-up; the per-event breakdown is a slice. Slight asymmetry between the two views for the edge case of "UID paid in an event but is not in `event.participantIds`" is documented inline. For the production canary case, all orphan financial actors are also in `event.participantIds`, so the asymmetry is zero. Citation: `_buildPerEventBreakdown` body is at `lib/features/groups/providers/group_balance_provider.dart:224-264`.

### Edit — render leaves (corrected from v1's wrong file inventory)

The actual live render path is `LedgerScreen` → `LedgerDayCard` (inline `_ExpenseRow` + `LedgerSettleRow`). `ExpenseCard` and `SettlementRow` at `lib/features/ledger/widgets/` exist as files but are not referenced from the current ledger flow — they are not in scope.

- `lib/features/ledger/screens/ledger_screen.dart`
  - `:87-89` and `:166`: replace `expense.payerName ?? 'Member'` and similar resolutions with `MemberNameResolver.format(MemberNameResolver.resolveEventScoped(...))`. Inputs: `uid: expense.payerParticipantId`, `event`, `members: groupMembers`, `fallbackName: expense.payerName`. Current-user short-circuit (`'You'`) happens at the leaf, not here.
- `lib/features/ledger/widgets/ledger_day_card.dart`
  - `_ExpenseRow.build` payer-name line (currently `final payerName = isPayer ? 'You' : (expense.payerName ?? 'Member');`): keep the `isPayer` short-circuit, replace the else branch with a pre-formatted string passed in via a new widget prop `payerDisplayName` from the caller (ledger_screen does the resolution).
  - `LedgerSettleRow.build` (`payerName: settlement.payerName ?? 'Someone'`, `recipientName: settlement.recipientName ?? 'someone'`): same pattern — caller pre-formats and passes in.
- `lib/features/groups/widgets/settle_up_page_body.dart`
  - `:124-160` optimal-settlement tile builder: `fromName` / `toName` arguments to `GroupSettlementTile` use the *formatted* display string. The `onRecord` callback parameters at the *same lines* receive `rawName` (sourced from the new `memberRawNames` map). Two different shapes, intentionally — formatted for the tile, raw for the write.
  - `:432-433` settlement history tile: `final payerName = settlement.payerName ?? 'Unknown';` → resolver formatted output, using `settlement.payerName` as caller fallback.
- `lib/features/groups/widgets/group_settlement_tile.dart`
  - `:59-61`, `:168`, `:182`: widget receives pre-formatted strings, renders verbatim. No new logic in this widget.
- `lib/features/ledger/screens/settle_up_screen.dart`
  - **`:90-100` is the `participants` build** (which uses `event.participantIds` and `event.participantNames`). Rebuild this loop so each participant's `displayName` comes from `MemberNameResolver.resolveEventScoped(uid, event, members: groupMembers).rawName`. The participant set still derives from `event.participantIds` — event scope already includes orphan UIDs that are event participants.
  - **`:118` is the `userNames` map build** (NOT `:90-97` as v3 incorrectly said). Replace this single-map build with the dual-map construction from the "Concrete data contracts" section: build `userDisplayNames` (formatted, fed to `BalanceCalculator.calculateOptimalSettlements` at `:124-126`) AND `userRawNames` (raw, passed into `SettleUpPageBody.rawNames` constructor param) in one pass via `resolveEventScoped`.
  - `:274-275` settlement creation: persist `fromRawName` / `toRawName` from the `onRecord` callback (NOT from any formatted map). The callback signature change is the load-bearing fix — see "Concrete data contracts".
- `lib/features/groups/screens/group_settle_up_screen.dart`
  - **No local `userNames` build exists in this screen.** v3 said to "build dual map locally via `resolveGroupScoped`" — that was wrong. The screen at `:110-112` consumes `balancesData.memberNames` directly from `groupBalancesProvider`. v4: the screen consumes the new `memberNames` (formatted) AND `memberRawNames` (raw) fields from the provider's extended return record; both come pre-built. Pass `memberRawNames` into `SettleUpPageBody.rawNames`. No resolver invocation in this screen file.
  - `:339-340` settlement creation: persist `fromRawName` / `toRawName` from the `onRecord` callback.
- `lib/features/groups/screens/group_detail_screen.dart`
  - `:830-833` member-row name resolution (currently `balances[i].displayName ?? data.memberNames[balances[i].participantId] ?? 'Member'`): `data.memberNames` is now pre-formatted by the provider, so the second fallback already carries the suffix when relevant. Drop the `'Member'` literal — once orphan UIDs are in `memberNames`, that fallback is dead.
- `lib/features/ledger/widgets/ledger_search_sheet.dart`
  - `_ExpenseHit` and `_SettlementHit` are currently plain wrappers with computed getters that pull from `expense.payerName` / `settlement.payerName` directly. They have no access to `Event` or `List<GroupMember>`, so the getters cannot call the resolver as-is.
  - **Refactor:** make hits resolver-aware at construction time, not in getters. Change constructors to `_ExpenseHit(this.expense, this.payerDisplay)` and `_SettlementHit(this.settlement, this.payerDisplay, this.recipientDisplay)` where `payerDisplay` / `recipientDisplay` are pre-formatted strings (the resolver result + `.format()`). The hit-builder code (verify location at edit time — search uses `_buildHits` or similar) invokes the resolver once per hit using the enclosing event context, then constructs the hit with the resolved strings.
  - `:418` (`'Paid by ${expense.payerName}'`): becomes `'Paid by ${payerDisplay}'`.
  - `:434-440` (`_SettlementHit.title`): becomes `'$payerDisplay → $recipientDisplay'`.
  - If the search returns hits across multiple events in a single query, each hit is resolved against its own event — the resolver call is per-hit, not per-query.
- `lib/features/events/screens/event_command_center.dart`
  - `:733-735` payer-name line (`expense.payerParticipantId == currentUid ? 'You paid' : '${(participantNames[expense.payerParticipantId] ?? 'Someone').split(' ').first} paid`): preserve the `'You paid'` short-circuit. Replace the else branch with `MemberNameResolver.resolveEventScoped(...).rawName.split(' ').first + ' paid'`. **Operate on `rawName`, not the formatted string** — splitting the formatted string would produce `'Former paid'` when the only available source is the `'Former member'` last-resort literal, which is wrong. Operating on `rawName` produces `'Former member' → 'Former paid'`... wait — that's still wrong. So additionally: when `resolveEventScoped` returned the last-resort `'Former member'` raw name AND the call site is the compact `'X paid'` label, render `'Former member paid'` (no truncation). Implementation: `final display = resolveEventScoped(...); final firstName = display.rawName == MemberNameResolver.formerMemberLiteral ? display.rawName : display.rawName.split(' ').first; return '$firstName paid';`. Add an inline comment explaining why the literal short-circuits truncation.
  - `:1008` roster card name (`final name = event.participantNames[uid] ?? 'Someone';`): replace with `MemberNameResolver.format(resolveEventScoped(...))`. Roster cards have full-width room for the suffix, so use the formatted string.

### Edit — display name validator (mirror client + server)

The validator must reject `(former member)` as a trailing suffix in **both** the scalar display-name validator AND the map-value validator. The map-value path is what `event.participantNames` writes flow through (`security/firestore.rules:269`), so missing it would leave a hole: a malicious or buggy client could persist `'Aisha (former member)'` as an event participant name and the rendering pipeline would then double-suffix to `'Aisha (former member) (former member)'`.

- `lib/core/utils/name_validators.dart` — extend `isValidDisplayName` to reject any name that ends with `' (former member)'` (i.e. matches `MemberNameResolver.formerSuffix`). Implementation: add a final check `if (trimmed.endsWith(MemberNameResolver.formerSuffix)) return false;` (or inline the literal constant if the validator file shouldn't import the resolver — verify the import graph at edit time). Add a unit test asserting that `'Aisha (former member)'` → `false`, `'Aisha'` → `true`, `'(former member) Aisha'` → `true` (only trailing matches are rejected).
- `security/firestore.rules` — extend **both** `isValidDisplayName` (`:24-30`) AND `displayNameMapValuesAreValid` (`:38-43`) with the trailing-suffix rejection. For the scalar function, add `&& !s.matches('.* \\(former member\\)$')`. For the map function, extend the join+regex pattern so no map value matches `.* \\(former member\\)$`. Both client and server must reject the same set so the contract is enforceable end-to-end at every write surface (`isValidDisplayName` is "mirrored" per its docstring at `name_validators.dart:3`; `displayNameMapValuesAreValid` validates `event.participantNames` per `firestore.rules:269`).

**Product side-effect note (codex v5 [P3]):** `isValidDisplayName` is also used for group names (`security/firestore.rules:168, 182`), event names (`:261`), and the user's own display name (`:586, 599`). Rejecting trailing `(former member)` applies to all of these too — group named `'Camping Trip (former member)'` will be refused at creation. This is intentional product behaviour: the suffix is reserved system vocabulary. Document in the user-facing error path if any UI surfaces validator failures.

### Edit — tests that assert current fallback strings

Grep for `'Member'`, `'Someone'`, `'Unknown'` as render-fallback assertions in `test/`. For each:
- If the test's intent was to cover the orphan-UID case → update to assert `'<name> (former member)'`.
- If the test was using the literal incidentally (not the real assertion) → replace with `isNotEmpty` or drop.

### Edit — `GroupBalances` record extension breaks fixture-literal tests

Codex v4 review correctly flagged that adding `memberRawNames` to the `GroupBalances` typedef breaks every test that constructs a `GroupBalances` literal via `groupBalancesProvider.overrideWith(...)` with a record literal. These tests must be updated to include the new field. Enumerated impact (grep `groupBalancesProvider.overrideWith\|balancesData\.` confirms):

- `test/unit/cross_group_balance_test.dart` — 5 record-literal overrides
- `test/unit/profile_stats_provider_test.dart` — 2 record-literal overrides
- `test/unit/group_balance_provider_test.dart` — internal asserts on the provider's return; verify each test's expectations against v5 per-event math (some tests may have asserted the broken flat-list math; update them to assert the correct per-event-summed math)
- `test/features/home/home_screen_dashboard_test.dart` — 6 record-literal overrides
- `test/features/home/home_screen_quick_actions_test.dart`, `test/features/home/home_screen_groups_test.dart`, `test/features/home/widgets_test.dart`, `test/features/home/cross_group_activity_screen_test.dart` — verify each, update if they override
- `test/features/groups/group_settle_up_screen_test.dart`, `test/features/groups/group_detail_navigation_test.dart`, `test/features/groups/group_screens_test.dart`, `test/features/groups/group_settings_screen_test.dart`, `test/features/groups/create_join_group_test.dart` — same
- `test/features/group_detail_screen_test.dart`, `test/features/events/group_detail_events_test.dart` — same

For each fixture, add `memberRawNames: <Map<String, String>>{}` (or a fixture-appropriate populated map). The compile will fail loudly until every site is updated — that's the intended forcing function, not a regression.

Do not add widget tests for *every* render leaf touched — the three new widget/screen tests (above) plus the resolver unit test and the provider test cover the surface. Codex specifically flagged "no new widget tests" as inadequate in v1; v2 added three targeted ones, not eight near-duplicates.

## Files NOT to touch

- `lib/features/activity/` — activity logs are name-stable.
- `lib/features/groups/models/group_member_model.dart` — `isTombstone` exists at `:16`.
- `lib/features/events/models/event_model.dart` — `participantNames` exists at `:69`.
- `lib/features/ledger/models/expense_model.dart`, `settlement_model.dart` — name fields exist as nullable join artifacts.
- `BalanceCalculator` class (defined inline in `lib/features/ledger/providers/expense_provider.dart:163-450`, **not** in a separate `services/balance_calculator.dart` file as CLAUDE.md previously suggested) — operates on `Participant` records, name-agnostic. v4 callers pass an expanded participants list; the calculator itself is unchanged.
- `lib/features/ledger/widgets/expense_card.dart`, `settlement_row.dart` — not referenced from the current ledger flow (verified via grep). Their dead-code status is a separate cleanup decision, not this spec.
- `lib/features/auth/services/` — recovery + deletion flows already create tombstones where appropriate; this spec consumes their output.
- `functions/` — server-side untouched.
- `security/firestore.rules` — schema unchanged. **One small additive rule:** the display-name validator gets the same trailing-`(former member)` rejection as the client mirror (see "Edit — display name validator" above). No other Firestore rule changes.
- `lib/core/services/cache/` — SQLite cache repositories untouched; tombstones already round-trip via the v9 schema fix landed in the account-deletion PR.
- `pubspec.yaml`, `lib/firebase_options.dart`, goldens.

## Acceptance criteria

1. `MemberNameResolver` exists at `lib/features/groups/services/member_name_resolver.dart`, ≤ 110 lines, pure Dart, no Firebase or Riverpod imports. Exposes `stripFormerSuffix` alongside `resolveGroupScoped` / `resolveEventScoped` / `format` / `formerSuffix` / `formerMemberLiteral`.
2. `MemberNameResolver` exposes both `resolveGroupScoped` and `resolveEventScoped` with their documented resolution orders; returns `MemberDisplay { rawName, isFormer }`.
3. `groupBalancesProvider` computes balances per event (event-local participants + event-local financial orphans), sums per-user across events, then applies group-scoped settlements at the end. The single flat-list `BalanceCalculator.calculateBalances` call at the current `:189` is gone. The provider's return record includes both `memberNames` (formatted, for display) and `memberRawNames` (raw, for write paths).
4. Both `isValidDisplayName` (client + server) AND `displayNameMapValuesAreValid` (server, used by `event.participantNames`) reject any name (or map value) ending in `' (former member)'`. Unit tests cover both accept and reject cases for the client validator. Firestore-rules tests under `functions/test/` cover both server functions across these explicit cases (codex v6 [P3]): scalar name ending with suffix → rejected; scalar name with suffix as prefix or middle → accepted; map value ending with suffix → rejected; empty values still rejected; newline/control-char cases still rejected.
5. `flutter analyze` is clean.
6. `flutter test` passes the full suite. Coverage gate at 80% holds. All `GroupBalances` fixture-literal tests updated to include `memberRawNames`.
7. New tests pass:
   - `test/unit/member_name_resolver_test.dart` — all branches of both scopes, plus `stripFormerSuffix` round-trip.
   - `test/features/groups/group_balance_provider_orphan_uid_test.dart` — orphan UID becomes a balance participant; balance math correct in a two-event scenario (Orphan in Event A only, regular member in both events; assert Orphan is NOT charged for Event B's global expense).
   - `test/features/ledger/ledger_day_card_former_member_test.dart` — `LedgerDayCard` renders `'<name> (former member)'`.
   - `test/features/groups/settle_up_page_body_former_member_test.dart` — formatted in tile, raw in `onRecord` callback.
8. On the production group `78cb99b0…` (manual / device QA against prod): the dormant anon UID renders as `'<name> (former member)'` in:
   - The group settle-up sheet net-balances list (was: silently missing).
   - The expense card in the event ledger for the one expense it paid.
   - The settlement row for the one settlement it appears in.
9. **Net balance for the dormant UID matches expectation** when computed by hand from the 1 expense (+amount paid, -1/N share of that expense for N event-A participants) + 1 settlement. Critically: the dormant UID is **not** charged for any other event's expenses.
10. Recording a new settlement (event or group) against a former member persists the raw name in Firestore. Grep **both** `groups/{gid}/events/{eid}/settlements/` (event-scoped writes) AND `groups/{gid}/settlements/` (group-scoped writes via `GroupSettleUpScreen`) after recording: no `(former member)` string anywhere in either path's docs.
11. Live members render unchanged — no `(former member)` suffix appears for any UID with a non-tombstone `GroupMember` doc.
12. No new `Color(0xFF…)` literals, no new typography styles, no new shared widgets. Grep confirms `' (former member)'` appears exactly once outside the resolver test (in the resolver itself).

## Verification

```bash
# From inside the worktree:
flutter analyze
flutter test test/unit/member_name_resolver_test.dart
flutter test test/features/groups/group_balance_provider_orphan_uid_test.dart
flutter test test/features/ledger/ledger_day_card_former_member_test.dart
flutter test test/features/groups/settle_up_page_body_former_member_test.dart
flutter test
dart run tool/check_no_hardcoded_colors.dart    # should be clean
grep -rn "(former member)" lib/ | grep -v member_name_resolver.dart   # should be empty
```

Manual production verification (after merge, before tagging `+16`):
- Build a debug APK against prod Firebase, sign in as a member of group `78cb99b0…`.
- Open the group → settle-up sheet. Confirm the dormant UID's net balance now appears as a row with `(former member)` suffix.
- Open one of the 5 events the dormant UID created → ledger. Confirm the expense card payer renders `<name> (former member)`.
- Record a tiny test settlement against that former member. After saving, open Firebase console (or `firebase firestore:get`) on the new settlement doc and confirm `payerName` / `recipientName` have **no** `(former member)` substring.

## Out of scope (explicitly deferred)

- **Event creator attribution UI.** `Event.createdBy` remains unrendered. Separate UX decision.
- **Server-side tombstone backfill migration** for orphan UIDs. UI fallback is sufficient per `docs/REAL-DEVICE-QA.md:242`.
- **Arabic localisation of the `(former member)` suffix.** Constant exists for the AR pipeline to pick up (queued post-launch per memory).
- **Italic / colored treatment** for former members. Plain textual suffix is the v1 convention; revisit if user feedback warrants.
- **Activity log retroactive labelling.** Actor names are immutable and historically correct; do not relabel.
- **Removing `ExpenseCard` / `SettlementRow` widget files** that are not referenced from the current ledger flow. Separate dead-code cleanup decision.
- **`(former member)` suffix for the current user looking at their own old UID's history.** Edge case — resolver hits branch 4/5 and renders the formatted string. Acceptable; the suffix communicates correctly.

## Codex review history

- **2026-05-17 v1** — Codex flagged 4 [P1]: (1) participant-set entry point too late, (2) formatted-string leakage into Firestore writes, (3) wrong render-site inventory (`ExpenseCard`/`SettlementRow`/wrong path for `settle_up_page_body.dart`), (4) "no new widget tests" inadequate. Plus 3 [P2]: resolution-order policy ambiguity, `Expense.payerName` rarely populated, four missed surfaces. Session ID `019e33d0-b65a-7053-a08b-c5e8c4a3c136`.
- **v2 changes from v1:**
  - Participant-set expansion moved to the front, becomes the load-bearing change.
  - Added `MemberDisplay { rawName, isFormer }` return shape; raw vs formatted split conceptually.
  - Split resolution order into group-scoped vs event-scoped (historical-first for events per user pick).
  - Corrected render-site inventory (LedgerDayCard, not ExpenseCard/SettlementRow); corrected `settle_up_page_body.dart` path to `groups/widgets/`.
  - Added four missed surfaces (group detail, settle-up history, ledger search, event command center).
  - Three targeted widget/screen/provider tests on top of the resolver unit test.
  - Documented persistence-safety file:line for the three write paths.
- **2026-05-17 v2 codex re-review** — v2 closed P1 #1, #3, #4 and the resolution-order [P2]. Partially closed: P1 #2 (raw/format split conceptual but data shapes not specified — implementer would still leak) and [P2] `Expense.payerName` fallback (missed `event.participantNames` as the highest-priority source for the canary). Three new findings: [P1] raw/format data contract underspecified, [P1] group fallback misses `event.participantNames`, [P2] `SettleUpScreen` `memberRawNames` only exists on `groupBalancesProvider` not event provider, [P2] `event_command_center` `.split(' ').first` hack would render `'Former paid'` for the last-resort literal, [P2] per-event breakdown asymmetry.
- **v3 changes from v2:**
  - **Concrete data contracts** section added: explicit shape for the `groupBalancesProvider` return record (`memberNames` formatted + `memberRawNames` raw), explicit `SettleUpPageBody.onRecord` callback signature change (`fromName` → `fromRawName`, `toName` → `toRawName`), explicit dual-map pattern for `SettleUpScreen`.
  - **`event.participantNames` is now the primary group-scoped fallback source.** Rewrote "Fallback name pre-build" section as a priority-ordered first-write-wins build over events first, settlements second, expenses last.
  - **`SettleUpScreen` dual map pattern** spelled out — event-local `userDisplayNames` + `userRawNames` constructed in one pass, no dependency on `groupBalancesProvider`.
  - **`event_command_center` `.split(' ').first` fixed** to operate on `rawName` with a short-circuit for the last-resort literal (so `'Former member'` doesn't truncate to `'Former'`).
  - **`_ExpenseHit` / `_SettlementHit` refactor** spelled out: hits become resolver-aware at construction (constructor takes pre-formatted strings), not via computed getters.
  - **Per-event breakdown asymmetry** accepted as a known limitation with inline-comment plan and rationale (canary case unaffected).
- **2026-05-17 v3 codex re-review** — Closed all v2 findings. New [P1]: Step B's `events.expand((e) => e.participantIds)` would corrupt group-level balance math because `BalanceCalculator.calculateBalances` builds `splitRecipients = participants.map((p) => p.id).toSet()` for `global`-scope expenses with no event context — adding non-financial UIDs to the participants list dilutes every global expense's per-head split. New [P2]: `?? fromName` defensive fallback in the `onRecord` callsite would silently persist `(former member)` to Firestore. Two [P3]s (acceptable): `formerMemberLiteral` export is pragmatic; ledger-search-hit refactor is fine.
- **v4 changes from v3:**
  - **Step B narrowed** to financial-record UIDs only (drop `events.expand((e) => e.participantIds)`). Added explicit rationale citing `BalanceCalculator` semantics at `expense_provider.dart:232,248`. (Closed v3 [P1] for the obvious over-expansion case; codex v4 review then surfaced the deeper architectural [P1] that the single flat list still corrupts global splits.)
  - **`stripFormerSuffix` helper added** to the resolver API. The `onRecord` callsite's defensive fallback uses it instead of the bare formatted string. Paired with a debug-only `assert` for the missing-uid case. **Closes the v3 [P2] persistence-fallback bug.**
  - **Per-event breakdown asymmetry note** updated to reflect that v4's narrowing makes the asymmetry surface smaller.
  - **Four load-bearing corrections** caught by the in-session spec-verification checklist (NOT codex):
    - `BalanceCalculator` lives in `lib/features/ledger/providers/expense_provider.dart:163`, not in a separate `services/balance_calculator.dart` file (which doesn't exist). Fixed in "Files NOT to touch" + CLAUDE.md `Quick Nav` + `Where Things Live` table.
    - `settle_up_screen.dart` userNames build is at `:118`, not `:90-97`.
    - `group_settle_up_screen.dart` does NOT build its own userNames; it consumes `balancesData.memberNames` directly from `groupBalancesProvider` at `:112`.
    - `SettleUpPageBody` is `StatelessWidget` (at `:22`), not `StatefulWidget`.
- **2026-05-17 v4 codex sanity check** — Closed all v3 findings + verified all four file:line corrections. **New [P1]: Step B's narrowed financial-record-only expansion still uses one flat group-level `participants` list across all events.** `BalanceCalculator` builds `splitRecipients = participants.map((p) => p.id).toSet()` for `global`-scope expenses with no event context (`expense_provider.dart:248`). An orphan paying in Event A still ends up charged for `global`-scope expenses from Event B. Same class of money bug, narrower surface. Correct fix: per-event aggregation. New [P2]: `stripFormerSuffix` can corrupt a legit display name `'Aisha (former member)'` if `rawNames` is missing the uid in release. New [P2]: `GroupBalances` record extension breaks every test that constructs the record literally — must be enumerated. [P3]: creator-only orphan correctly gets no balance row. Minor: `_buildPerEventBreakdown` ends at `:264`, not `:280`.
- **v5 changes from v4:**
  - **Per-event balance aggregation in `groupBalancesProvider`.** The single aggregate `BalanceCalculator.calculateBalances` call at the current `:189` is replaced with the algorithm in the "Edit — provider layer (per-event aggregation, v5)" section above: iterate events, build event-local participants (event.participantIds + event-local financial orphans), call `calculateBalances` per event, sum `totalPaid` / `totalOwed` across events per user, apply group-scoped settlements once at the end. Mirrors what `_buildPerEventBreakdown` already does internally for the drill-down map. **Closes the v4 [P1] financial-correctness bug.** Worked example included in the section to make the correctness argument auditable.
  - **`stripFormerSuffix` provably safe via name-validator extension.** `lib/core/utils/name_validators.dart` `isValidDisplayName` (and its mirror in `security/firestore.rules`) now rejects any name ending in `' (former member)'`. Means no legitimate user-chosen name can end in the suffix, so `stripFormerSuffix` can never corrupt user data. **Closes the v4 [P2] display-name-corruption edge.**
  - **Test-fixture impact enumerated.** New explicit section "Edit — `GroupBalances` record extension breaks fixture-literal tests" lists ~14 test files that construct `GroupBalances` literals via `groupBalancesProvider.overrideWith(...)`. Each must add `memberRawNames` to the record. Plus a flag that `test/unit/group_balance_provider_test.dart` may have asserted the old broken flat-list math and needs expectations updated to the corrected per-event-summed math. **Closes the v4 [P2] test-fixture-impact gap.**
  - **Citation nit fixed:** `_buildPerEventBreakdown` body is `:224-264`, not `:224-280`.
  - **Two in-session workflow catches:**
    - The v4 spec said `GroupBalances` is a "record" but didn't show the typedef. v5 cross-references the typedef at `group_balance_provider.dart:75-81` so the implementer can see the exact field list they're extending.
    - **Adversarial re-read of v5's pseudocode caught a render-shadowing bug.** v5's first draft set `Participant.displayName = display.rawName`, on the principle of "raw everywhere, format() at render leaves." But `group_detail_screen.dart:831` reads `balances[i].displayName ?? data.memberNames[...] ?? 'Member'` — the raw name would have won the `??` chain and the `(former member)` suffix from `memberNames` would never have rendered. Fixed by passing the *formatted* string to `Participant.displayName` (and `UserBalance.displayName`); raw is exposed only via `memberRawNames` for write paths. Inline `NOTE:` comment explains the rationale at the assignment site so a future maintainer doesn't "fix" it back.
- **2026-05-17 v5 codex sanity check** — Closed all v4 findings + verified per-event aggregation + `stripFormerSuffix` validator extension + test-fixture enumeration + render-shadowing fix all hold. **New [P1]: event-scoped settlement adjustments dropped by the per-event sum.** v5 summed `b.totalPaid` and `b.totalOwed` across events, but `BalanceCalculator.calculateBalances` at `expense_provider.dart:298-314` builds `netBalance = (totalPaid + settlementAdj) - totalOwed` — settlements only land in `netBalance`, never in `totalPaid` or `totalOwed`. Discarding `b.netBalance` silently dropped event-settlement effects. New [P2]: validator extension covered `isValidDisplayName` but missed `displayNameMapValuesAreValid` (`firestore.rules:38`), which validates `event.participantNames` — leaving a hole. [P3]: validator scope is broader than display names (also gates group/event names). [P3]: acceptance #10 grep example covers only event-scoped settlements; should also cover group-scoped.
- **v6 changes from v5:**
  - **`netBalancePerUid` accumulator added to per-event loop.** Sums `b.netBalance` per UID alongside `totalPaid`/`totalOwed`. Final net = `eventNet + groupSettleAdj`. `totalPaid`/`totalOwed` kept as informational aggregates (they decompose cleanly because `BalanceCalculator` builds them only from splits, no settlement contribution). **Closes codex v5 [P1].**
  - **Second worked example added** exercising the settlement axis (Alice pays Bob $20 expense + Alice settles $10 → Bob). v5's worked example only covered the participant-set axis (same axis as the v4 fix), which is structurally why this bug slipped through in-session review. Per the updated spec-verification checklist (rule 6, orthogonal worked examples), v6's examples now cover both axes.
  - **`displayNameMapValuesAreValid` extended** in `security/firestore.rules:38` with the same trailing-suffix rejection. Both scalar and map-value validators now reject `(former member)` writes. **Closes codex v5 [P2].**
  - **Product side-effect note added** to the validator section: the suffix ban applies to group names, event names, and user display names too (all consumers of `isValidDisplayName`). Intentional — the suffix is reserved system vocabulary.
  - **Acceptance #10 extended** to grep both `groups/{gid}/events/{eid}/settlements/` AND `groups/{gid}/settlements/` (group-scoped settlement path via `GroupSettleUpScreen`).
  - **Acceptance #4 extended** to cover both server validator functions (`isValidDisplayName` + `displayNameMapValuesAreValid`).
  - **One in-session workflow catch:** the v5 [P1] caused two new rules to be codified in `CLAUDE.md` ("Verifying Plans and Specs") and the `feedback-spec-verification` memory: (rule 5) verify arithmetic decomposition when summing across function calls — read the function's output-construction lines, not the algorithm flow; (rule 6) worked examples must exercise axes orthogonal to the most recent fix. Both rules are anchored to this v5 → v6 transition as their canonical failure case.
