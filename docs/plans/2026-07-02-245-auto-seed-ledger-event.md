# #245 Auto-Seed Default Ledger Event Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.
> **Gate:** This spec MUST pass `/run-the-gate` (fresh-context Opus review) BEFORE Task 2.1. PR1 is functions/** and PR2 is a group-create write-path change — both Gate-category.

**Goal:** A fresh group is born with one ledger event (named after the group), so the first-expense path collapses to `create group → add expense` — Splitwise parity (#245).

**Architecture:** Two PRs. **PR1 (server):** `addShadowMember` fans the new shadow into live events' `participantIds`/`participantNames` — exactly what `joinGroupByInviteCode` already does for joiners — via a shared fan-in helper both callables use. This closes the live Manage-Members gap AND makes seed ordering irrelevant (shadows added after group create land in the seeded event server-side). **PR2 (client):** `stageGroup` chains one event write after the member write (same #574 ordering rationale); return shape and post-create navigation unchanged (D-3).

**Tech Stack:** Flutter/Riverpod client (`group_provider.dart`), Firebase Cloud Functions TS (Node 22), Firestore rules emulator tests (Jest), `FakeFirebaseFirestore` unit tests.

---

## Decisions (recommended defaults — user was AFK at ask time; revisit before Task 2.1 if desired)

| # | Decision | Choice | Why | Rejected |
|---|---|---|---|---|
| D-1 | Shadow gap | **Server fan-in in `addShadowMember` (PR1)** | Mirrors the join callable's existing event fan-in (`joinGroupByInviteCode.ts:341-390`); fixes the live gap where a shadow added via Manage Members is absent from all existing events; makes client seed ordering irrelevant. No real users → server deploys freely. | Client-ordering only (seed after `_seedShadowMembers`): leaves the Manage-Members gap; branchier offline/partial-failure paths. |
| D-2 | Seed `EventType` | **`trip`** | Product is trip-centric (journey tickets, trip stamps, Trip Receipt); ~90% one-trip case per issue. Recap reads "Trip total" (`event_type_copy.dart`), travel-first category order. | `custom` ("Event total", neutral order) — never wrong but bland. NOTE: type is **immutable** after create (`validEventUpdateCommon` pins `type`), so this label sticks per event. |
| D-3 | Post-create nav | **Group detail (status quo)** — the seeded event is the single row, one tap in. | Gate round-1 resolution: the preferred "land in the seeded event" option required `EventCommandCenter` to degrade gracefully on a #574 transient `permission-denied` listen — verified it does NOT (`event_command_center.dart:74-76` renders a hard `_ErrorState`; a terminated listen never self-recovers, and only `GroupDetailScreen` carries the #574 bounded retries). Reviewer's ship-condition failed → rejected branch taken. | Land in seeded event (`/group/:gid/event/:eid`): deferred as follow-up polish, viable only after EventCommandCenter gains bounded staging retries (do NOT bolt retry machinery on in this PR). |

**Gate record:** round 1 (fresh-context Opus, 2026-07-02) — **0 P1 / 2 P2 / 2 P3**; stop condition met. Findings folded in: D-3 flipped to the fallback (above); `notification_prompt_wiring_test.dart` risk eliminated by keeping `stageGroup`'s return shape unchanged; join's >400-events tx guard mirrored in Task 1.3; "Go to group" label correction moot (nav task dropped — the share-sheet button is `commonDone` "Done", `create_group_screen.dart:847`).

## Verification notes (7 principles, run 2026-07-02 against `main`)

1. **Callsite classification:** the seed write is OUTBOUND (new event doc). Read-paths named in (3). The seeded `Event` returned from `stageGroup` is INBOUND (nav id only).
2. **Claims verified against code:**
   - `stageGroup` writes 3 docs, member chained on batch ack — `group_provider.dart:218-266`. ✔
   - Expense editor split roster = `event.participantIds` — `expense_editor_body.dart:635,642,676` (+ `participantNames` `:583`). Shadows absent from the event can never be split against. ✔
   - Join callable fans joiner into live events (`arrayUnion`, skips `isDeleted === true`, merges `participantNames`, bumps `updatedAt`) — `joinGroupByInviteCode.ts:341-390`. It does **not** skip closed events; PR1 mirrors that (harmless: closed events reject new expenses anyway, #723).
   - `addShadowMember` touches only `members/{uuid}` + `group.memberIds` — no event fan-in (`addShadowMember.ts:118-131`). ✔ (the gap)
   - Client has NO participant-add path: `EventService.updateEvent` = name/dates/description only (`event_service.dart:271-308`); rules would allow append-only growth (`validEventLightUpdate` `hasAll`) but nothing exercises it. ✔
   - Rules: `isGroupMember`/`groupMembers()` read **`groups/{gid}.memberIds`** (rules `:152-156,:393-395`), NOT member docs → event create is valid immediately after the group batch, member doc not required. Pinned by Task 2.9.
   - Event name = group name is safe: both validated by the same `isValidDisplayName` (rules `:320` group, `:428` event); client cap identical (`name_validators.dart`).
   - `validEventCreate` requires `createdBy == auth.uid`, `auth.uid in participantIds`, born-open close triple — the seed payload (creator-only, via `Event.toFirestoreMap()`) satisfies all; same serializer `create_event_screen` uses today.
3. **Read-paths for the write:** group-detail events list (`watchGroupEvents`), home journey tickets (`activeJourneysProvider`), balance once-path (`groupBalancesOnceProvider` iterates events — zero expenses ⇒ zero contribution), server oracle `recomputeNet` (same), Trip Receipt event enumeration. An empty ledger event is a supported N=1 shape everywhere (issue's re-verified claim).
4. **Fields enumerated from the type** (`event_model.dart:110-130`): seed sets `id,name,type,groupId,createdBy,participantIds,participantNames,modules,createdAt`; leaves `startDate/endDate/description=null`, `isDeleted=false,deletedAt=null`, close triple at born-open defaults. `spendingSnapshot` is excluded from `toFirestoreMap` by design (`:106-108`).
5. **Data contracts spelled out:** `stageGroup` return record is **unchanged** — `({Group group, Future<void> ack})` (no consumer needs the seeded event id once D-3 keeps nav at group detail; YAGNI — extend the record only when a nav consumer exists). `ack` = `batch.commit() → member.set() → event.set(toFirestoreMap())` — one linear chain; an event-leg failure rejects the whole ack, the SAME failure semantics the member leg has today (group exists, screen shows `groupCreateError`; empty-state remains the recovery path). No swallowed errors. Zero compile fallout at `stageGroup` callsites (mocks in `notification_prompt_wiring_test.dart:120`, `create_group_offline_412_test.dart`, etc. keep working).
6. **Arithmetic decomposition:** n/a — no money math. Balance effect of an expense-less event is zero on both oracles (verified: universe = `participantIds ∪ payers/settlement parties`, no docs ⇒ no contribution).
7. **Orthogonal adversarial axis (identity):** the failure this plan exists to avoid — creator seeds shadows at create; without PR1 the seeded event's roster is creator-only forever (no client grow-path), so "split 3 ways" is impossible in the seeded event. PR1 must land (or be in the same deploy) BEFORE PR2 is released; PR2 merges only after PR1 is merged.

**No `ledgerRevisionProvider` bump needed:** event *list* changes refresh live; only per-event money *content* needs the bump (CLAUDE.md). Seed writes no money docs.
**No activity log for the seed:** `event_created` activity is logged by the create-event *screen*, not the service; the seed is implicit in group creation — logging "created <group name>" twice (group + event) is noise. Deliberate omission.

---

## PR1 — feat(functions): addShadowMember fans the shadow into live events (Refs #245)

Branch: `feat/245-shadow-event-fanin` off `origin/main`.

### Task 1.1: RED — fan-in test on addShadowMember

**Files:**
- Modify: `functions/test/callables/addShadowMember.test.ts`

**Step 1: Write the failing tests** (mirror the join callable's pinned semantics; reuse this file's existing fixtures/harness — read its setup block first):

- `fans the new shadow into live events' participantIds and participantNames`: seed a group (creator member) + one live event (participants: creator only) → call `addShadowMember` → expect event `participantIds` contains the returned `memberId` AND `participantNames[memberId] == displayName` AND `updatedAt` bumped.
- `skips soft-deleted events`: seed a second event with `isDeleted: true` → expect it untouched.
- `fans into closed events (mirrors join)`: event with `isClosed: true` → expect fan-in applied.

**Step 2: Run to verify RED** (bare `npm test` HANGS — always scope via the emulator runner):

```bash
cd functions && npm run test:emulator -- addShadowMember.test.ts -t "fans the new shadow"
```
Expected: FAIL (participantIds does not contain memberId).

### Task 1.2: Extract the shared fan-in helper

**Files:**
- Create: `functions/src/callables/shared/eventFanIn.ts`
- Modify: `functions/src/callables/joinGroupByInviteCode.ts` (replace its inline loop `:341-390` with the helper; keep `getParticipantIds`/`getParticipantNames` malformed-data guards by moving them into the helper)

**Step 1:** Helper shape (collect inside the tx read phase, apply in the write phase — Firestore tx requires all reads before writes):

```ts
export interface EventFanInUpdate {
  ref: FirebaseFirestore.DocumentReference;
  addParticipantId: boolean;
  participantNames: Record<string, string>;
}

export function collectEventFanIn(
  eventsSnap: FirebaseFirestore.QuerySnapshot,
  userId: string,
  displayName: string,
): EventFanInUpdate[] { /* joinGroupByInviteCode.ts:341-361 logic, verbatim semantics */ }

export function applyEventFanIn(
  tx: FirebaseFirestore.Transaction,
  updates: EventFanInUpdate[],
  userId: string,
): void { /* :381-390 logic: participantNames + updatedAt, arrayUnion when addParticipantId */ }
```

**Step 2: Prove no drift** — the join suite must stay green:

```bash
cd functions && npm run test:emulator -- joinGroupByInviteCode.test.ts
```
Expected: PASS (unchanged behavior through the extracted helper).

### Task 1.3: GREEN — wire fan-in into addShadowMember

**Files:**
- Modify: `functions/src/callables/addShadowMember.ts`

**Step 1:** Inside the existing transaction: add `const eventsSnap = await tx.get(groupRef.collection('events'));` alongside the members read (READ phase, before any `tx.set`/`tx.update`), then after the member-doc write + `memberIds` arrayUnion, `applyEventFanIn(tx, collectEventFanIn(eventsSnap, newId, displayName), newId)`. **Mirror join's tx-size guard** (`joinGroupByInviteCode.ts:293-298`): `if (eventsSnap.size > 400) throw new HttpsError('failed-precondition', ...)` — Firestore's 500-write-per-tx ceiling; without it a >400-event group makes `addShadowMember` blow up mid-tx where join fails cleanly.

**Step 2: Run to verify GREEN:**

```bash
cd functions && npm run test:emulator -- addShadowMember.test.ts
```
Expected: PASS (all, including pre-existing collision/throttle tests).

### Task 1.4: Build, commit, PR

- `cd functions && npm run build` (or the repo's lint script) — clean.
- Commit: `feat(functions): addShadowMember fans the shadow into live events (Refs #245)` — **`Refs` in the COMMIT body** (squash-merge closes from the commit message, not the PR body).
- PR body: `Refs #245` + RED evidence (pasted failing output from Task 1.1). Merge via `/automerge` (functions/** ⇒ Gate-category review path; spawn reviewer/refuter with `isolation: "worktree"`).
- **Deploy:** after merge, `tool/pending_deploy.sh` will show it pending; run the `deploy-ceremony` skill (may be bundled with any later pending Functions work — but MUST be deployed before PR2 ships to users; no real users today, so timing is flexible — do it right after merge to keep the ledger clean).

---

## PR2 — feat(groups): auto-seed a default ledger event on group creation (Closes #245)

Branch: `feat/245-auto-seed-event` off `origin/main`, **after PR1 merges**.

### Task 2.0: Run the Gate — ✅ DONE 2026-07-02

Round 1 fresh-context Opus verdict: **0 P1 / 2 P2 / 2 P3** (stop condition met); all findings folded into this revision (see Gate record above).

### Task 2.1: RED — stageGroup seeds one event

**Files:**
- Test: `test/features/groups/create_group_seed_event_test.dart` (new; model harness on `test/features/groups/create_join_group_test.dart` — FakeFirebaseFirestore + firebase_auth_mocks + `sharedPreferencesProvider` override)

**Step 1: Write the failing test:**

- `stageGroup seeds one ledger event named after the group`: call `stageGroup(name: 'Muscat Trip', currency: 'OMR')`, await `staged.ack`, then read `groups/{id}/events` → exactly 1 doc; assert `name == 'Muscat Trip'`, `type == 'trip'`, `participantIds == [uid]`, `participantNames == {uid: <deviceName>}`, `modules == {'ledger': true}`, `isDeleted == false`, `createdBy == uid` (read the id from the collection query — the return record is unchanged per D-3).
- `seeded event round-trips through Event.fromDoc` (guards serializer drift): `Event.fromDoc(snapshot)` parses with the same field values.

**Step 2: Run to verify RED:**

```bash
flutter test test/features/groups/create_group_seed_event_test.dart
```
Expected: FAIL — no `seededEvent` member / 0 event docs.

### Task 2.2: GREEN — implement the seed in stageGroup

**Files:**
- Modify: `lib/features/groups/providers/group_provider.dart:187-283`

**Step 1:** Build the seeded `Event` synchronously (mirror `event_service.dart:106-125` construction exactly — same `DateTime.now().toUtc()` createdAt, `List.unmodifiable`/`Map.unmodifiable`), write via `event.toFirestoreMap()` (ONE serializer — do not hand-roll the map), extend the chain and the return record:

```dart
final seededEvent = Event(
  id: uuid.v4(),
  name: name,
  type: EventType.trip,
  groupId: groupId,
  createdBy: uid,
  participantIds: List.unmodifiable([uid]),
  participantNames: Map.unmodifiable({uid: displayName}),
  modules: EventModules.forType(EventType.trip),
  isDeleted: false,
  createdAt: DateTime.now().toUtc(),
);

final ack = batch.commit().then((_) {
  return db.collection('groups').doc(groupId).collection('members').doc(memberId).set({ /* unchanged */ });
}).then((_) {
  // #245: seed the default ledger event AFTER the group doc exists — the
  // events rule reads groups/{gid}.memberIds (isGroupMember), same ordering
  // constraint as the member write. Shadows added post-create are fanned in
  // server-side by addShadowMember (PR1).
  return db.collection('groups').doc(groupId)
      .collection('events').doc(seededEvent.id)
      .set(seededEvent.toFirestoreMap());
});
```

Return record and `create_group_screen.dart` stay **unchanged** (D-3: nav remains group detail; no consumer needs the seeded id). Event-leg failure rejects the ack — identical semantics to today's member leg; do NOT catch/swallow. Adjust the Task 2.1 test to read the seeded id from the events collection query instead of the return record.

**Step 2: Run to verify GREEN:**

```bash
flutter test test/features/groups/create_group_seed_event_test.dart
```
Expected: PASS.

**Step 3:** `flutter analyze` clean (no callsite fallout expected — record unchanged; confirm with `grep -rn "stageGroup" lib test`).

**Step 4: Commit** `feat(groups): stageGroup seeds a default ledger event (#245)`.

### Task 2.3: DROPPED (Gate round 1) — post-create nav into the seeded event

`EventCommandCenter` hard-errors on a #574 transient listen denial (`event_command_center.dart:74-76`, no bounded retry). Follow-up polish once that screen gains staging retries; do not fold retry machinery into this PR.

### Task 2.4: DROPPED (Gate round 1) — see Task 2.3.

### Task 2.5: Teaching copy on the create-event screen

**Files:**
- Modify: `lib/features/events/screens/create_event_screen.dart`, `lib/l10n/app_en.arb`, `lib/l10n/app_ar.arb`

**Step 1:** Add one caption under the screen's header (exact slot: read the header build first): l10n key `createEventSecondEventHint`, EN: `"Events split one group's spending into separate trips or outings — most groups only need one."` AR: translate reusing the ARB's existing Arabic noun for "event" (grep `app_ar.arb` for the event noun — do NOT invent a new term). Style: `context.colors.textSecondary` (NOT `.textMuted` — theme-purity justification trap), directional padding.

**Step 2:** `flutter gen-l10n` (or the repo's generator — check `l10n.yaml`), `flutter analyze`, `bash tool/check_theme_purity.sh`.

**Step 3:** Extend the widget test: caption visible on CreateEventScreen. **Commit** `feat(events): teach when a second event is worth it (#245)`.

### Task 2.6: Update existing tests that pin the old flow

**Files (verify with grep, then fix assertions — don't patch blindly).** Record shape is unchanged (D-3), so expect little-to-no compile fallout; what CAN change is behavior visible through the real `GroupService` (tests that use FakeFirebaseFirestore rather than a mocked service now get a 4th write — the seeded event):
- `test/features/groups/create_join_group_test.dart` (share-sheet / post-create assertions; events-list assertions on a fresh group now see 1 event)
- `test/features/groups/create_group_offline_412_test.dart` (queued path unchanged; ack contract now includes the event leg — the never-completing-Completer harness must still hold)
- `test/features/groups/create_group_shadow_members_test.dart`
- `test/features/groups/notification_prompt_wiring_test.dart` (mocked-service stub keeps compiling; `find.text('group-landing')` nav assertion stays valid since D-3 keeps group-detail nav)
- `test/features/groups/gate_intent_prefill_test.dart`, `test/features/groups/durable_gate_wiring_test.dart` (sweep for FakeFirebaseFirestore-backed create assertions)

Run: `flutter test test/features/groups/` → PASS.

### Task 2.7: Rules pin — seed write is valid without a member doc

**Files:**
- Modify: `functions/test/firestore-rules-publish-readiness.test.ts`

Add: authed user creates group doc (memberIds=[uid]) + then immediately creates an event (creator-only participants, trip, born-open) **without any member doc** → ALLOWED. This pins the ordering assumption Task 2.2's chain rests on (`isGroupMember` reads the group doc, rules `:152-156`).

```bash
cd functions && npm run test:emulator -- firestore-rules-publish-readiness.test.ts -t "seed"
```

### Task 2.8: Full verification + PR

- [ ] `flutter analyze` clean
- [ ] `flutter test` full suite green
- [ ] `bash tool/check_theme_purity.sh` clean
- [ ] Security checklist (no secrets; rules untouched in PR2; input = group name already validated)
- Commit history: conventional, **`Closes #245` in the final commit body** (squash-merge trap — the PR body alone does not close).
- PR body: `Closes #245`, `Spec: docs/plans/2026-07-02-245-auto-seed-ledger-event.md`, RED evidence pasted (Task 2.1 + 2.3 failing output). Merge via `/automerge` (models/** + write-path ⇒ Gate-category).

### Out of scope (do not fold in)
- Hub-skip / single-event forwarding — delivered/obsoleted by #758.
- A client UI to grow `participantIds` on an existing event — rules allow it, no client path; separate issue if wanted.
- #364 persistent FAB — sequenced after this ships (its context-free target selection leans on the seeded single-event shape).
- Any `SplitMode`/money change — none here.
