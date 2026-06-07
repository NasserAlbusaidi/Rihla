# `expenseAuditLogger` Trigger + Activity-Logs Server-Lock — Implementation Plan (#248 — PR 2 of 5)

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.
> **Spec:** Gate-reviewed spec for #248 PR 2. Run `/run-the-gate` to a no-P1 verdict **before** writing code. `Refs #248` (does NOT close it).
> **Depends on:** PR 1 (#337, `lastEditedBy`). Branch PR 2 off `main` **after** PR 1 merges (avoids the stacked-base-deletion auto-close trap). The trigger reads `lastEditedBy` with a `createdBy` fallback, so it is forward-correct even before PR 1 deploys — see D6.

**Goal:** Move expense audit logging from the forgeable, CREATE-only, client-written path to a tamper-proof Firestore `onDocumentWritten` trigger (`expenseAuditLogger`) that logs CREATE/UPDATE/DELETE server-side, and lock event `activity_logs` so clients can no longer create (forge) audit entries. **Edit authorization is unchanged: still creator-only** (PR 4 opens it).

**Architecture:** A v2 `onDocumentWritten` trigger on `groups/{gid}/events/{eid}/expenses/{expenseId}` runs as Admin (no `request.auth`). It classifies the write from the before/after snapshots (CREATE / UPDATE / soft-DELETE), attributes it to the in-document actor (`after.lastEditedBy || after.createdBy`), resolves that UID to a display name via the group's `members` collection (matched by the `userId` **field**, never doc id — #294), and writes one audit entry to the event `activity_logs` subcollection in the established 9-key `ActivityLog` shape. The Admin SDK bypasses security rules, so the same change removes `validActivityCreate()` from the rules (deny all client creates to event `activity_logs`) and drops the client-side `_addExpenseCreatedActivity` write — the trigger becomes the sole writer. Loop-safe: it watches `expenses/*`, writes `activity_logs/*` (disjoint paths).

**Tech Stack:** Firebase Functions v2 (`firebase-functions@7.2.5`, Node 22, `us-central1`), `firebase-admin@13`, TypeScript; `firebase-functions-test` (offline) + Admin SDK against the Firestore emulator (Jest, Java 21); `@firebase/rules-unit-testing` (rules emulator); `fake_cloud_firestore` (Dart unit). Money rendering via the existing `functions/src/notifications/formatAmount.ts` (mirrors `MoneySerializer` scale byte-for-byte).

---

## Scope

**In (PR 2):**
- New trigger `functions/src/triggers/expenseAuditLogger.ts` (`onDocumentWritten` on the expenses path) + its `index.ts` re-export.
- `firestore.rules`: remove `|| validActivityCreate()` from the event-subcollection `allow create` OR-list **and delete** the now-dead `validActivityCreate()` function (no dead-but-kept rule — the `validEventSettlementUpdate` bear trap). Event `activity_logs` becomes fully server-only.
- Drop the client write: remove `_addExpenseCreatedActivity` + its call/try-catch in `addExpense`, and the now-unused `actorId`/`actorName` params (sole prod caller `add_expense_screen.dart`); remove the dead `ActivityService.addActivityLog` write method.
- Tests: trigger Jest (classification / attribution / name-resolution / idempotency / never-mutates-the-money-doc), rules emulator (client create now DENIED + server write via `withSecurityRulesDisabled` SUCCEEDS), Dart (addExpense no longer writes `activity_logs`; delete `addActivityLog` tests).

**Out (later PRs / named follow-ups — do NOT build here):**
- Activity-feed rendering of UPDATE/DELETE rows + money before/after display → **PR 3** (the trigger *writes* the before/after into `metadata` now so PR 3 can render it).
- Dropping `requesterIsRecordCreator()` (open editing) + CLAUDE.md B1 rewrite → **PR 4**.
- Editor creator-vs-payer affordance → **PR 5**.
- **Recovery migration of `lastEditedBy`** (oldUid→newUid in `cleanupAnonUidArtifacts.ts`) → named follow-up (the PR-1-deferred task). Without it, post-recovery audit entries attribute to a dead anon UID → name unresolved → "Someone". Graceful; pre-launch there are no users.
- **System-write attribution/suppression** (D5): admin writes to *live* expenses (recovery UID-migration, `deleteAccount` scrub) fire the trigger and log a MONEY/UPDATE attributed via the `createdBy` fallback. Mitigated here (already-deleted-skip guard) + moot pre-launch; full suppression = named follow-up.

---

## Load-bearing design decisions

### D1 — Watch the **specific** `expenses` path, not the `{module}` wildcard
Trigger path: `groups/{gid}/events/{eid}/expenses/{expenseId}`. **Not** `groups/{gid}/events/{eid}/{module}/{docId}` (which `eventWriteRateMonitor` uses, `writeRateMonitor.ts:104-110`). Watching the specific path guarantees the trigger's own `activity_logs` write cannot re-fire it (loop-safety by path disjointness — the `_writeCounters` precedent, `writeRateMonitor.ts:39-43`).
- **Known, accepted interaction:** the audit write *does* land in `activity_logs`, which **is** in `eventWriteRateMonitor`'s `COUNTED_EVENT_MODULES` (`writeRateMonitor.ts:26`), so each audit entry increments the editor's write-rate counter (keyed on the entry's `actorId`). The client's CREATE entry already did this; PR 2 also counts UPDATE/DELETE entries. The write-rate monitor is **flagging-only, not a hard gate** (CLAUDE.md: "Per-actor throttles … are friction, not a hard gate"), so double-counting is acceptable. Flagged for the Gate.

### D2 — Event-type classification from before/after (everything is soft-delete)
`onDocumentWritten` delivers `event.data.before` / `event.data.after` (each a `DocumentSnapshot` with `.exists` + `.data()`). On the expense path **there is no hard document delete** — `expense_service.dart` only `.set()` (create) and `.update()` (edit + soft-delete); the only `.delete()` is `FieldValue.delete()` clearing split keys (still an update). So:

| Op | Predicate | Logged |
|---|---|---|
| **CREATE** | `!before.exists && after.exists && after.isDeleted !== true` | MONEY / `CREATE` |
| **DELETE** (soft) | `before.exists && after.exists && before.isDeleted !== true && after.isDeleted === true` | MONEY / `DELETE` |
| **UPDATE** | `before.exists && after.exists && before.isDeleted !== true && after.isDeleted !== true && contentChanged(before, after)` | MONEY / `UPDATE` |
| **SKIP** | everything else | — |

`SKIP` covers: hard delete (`!after.exists` — never happens on this path), resurrection (`before.isDeleted && !after.isDeleted` — rules-blocked at `validExpenseUpdate`), **edits of an already-deleted doc** (`before.isDeleted === true` — only admin scrub/migration does this; a user can never edit a soft-deleted expense, the UI filters them out via `.where('isDeleted', isEqualTo: false)`), and no-op writes (no content change — D3 already prevents these client-side, this is defense-in-depth).

`contentChanged(before, after)` = any of these persisted keys differs (deep-equal for the map/list):
`amountFils`, `currency`, `payerParticipantId`, `description`, `note`, `scope`, `subGroupId`, `categoryId`, `splitMode`, `splitDistribution` (map deep-eq), `customSplitParticipants` (array eq). `isDeleted`/`deletedAt`/`lastEditedBy`/`createdBy`/`id`/`eventId`/`createdAt`/`receiptUrl` are **excluded** from `contentChanged` (deletion handled by the DELETE branch; `lastEditedBy`-only / metadata-only writes must not produce a phantom "edited" entry).

### D3 — Actor attribution: `lastEditedBy || createdBy` (both rule-pinned to `auth.uid` at the expense layer)
`const actorUid = (after.lastEditedBy as string) || (after.createdBy as string) || '';`
- `lastEditedBy` (PR 1) is the editor; empty (`''`) for legacy/pre-PR-1 docs → falls back to `createdBy` (the creator). Both are pinned `== request.auth.uid` by the expense rules at write time, so the trigger trusts them as the actor — **the trigger has no `request.auth`**, so the in-document field is the only actor signal.
- In PR 2 edit is **still creator-only**, so the editor is always the creator → `createdBy` alone is already correct; `lastEditedBy` only starts to *matter* once PR 4 opens editing. This is why PR 2 is correct even if PR 1 hasn't deployed (D6).
- If `actorUid` is empty (legacy test data with no `createdBy`) → write `actorId: ''` and `actorName: null` (entry still valid; feed shows the localized "Someone").

### D4 — Resolve the actor **display name** via `members.where('userId','==', actorUid)` (#294 keying)
Mirror `leaveGroup.ts:66-99` exactly — match member docs by the `userId` **field**, never `.doc(actorUid)` (joiners key by `{uid}` but the creator's doc is keyed by a random uuid with `userId:uid` — `.doc(uid)` misses creator docs, #294):
```ts
const memberSnap = await db.collection(`groups/${gid}/members`).where('userId', '==', actorUid).get();
const actorName = memberSnap.docs
  .map((d) => d.data().displayName)
  .find((n): n is string => typeof n === 'string' && n.length > 0) ?? null;
```
**Write `null` when unresolved — NOT the literal `'Someone'`.** The *event* feed localizes a null actor to `context.l10n.activitySomeone` at render (`activity_feed_screen.dart:333-340`); writing the English literal `'Someone'` would break Arabic/RTL. (This differs from `leaveGroup`/`removeMember`, which write `'Someone'` to the *group* `activity` feed — that feed does not localize the actor. Two feeds, two conventions; honor the event-feed one.) The trigger does one extra indexed read per logged write; it is off the user's critical path (fires after commit).

### D5 — System (admin) writes to *live* expenses are logged; suppression deferred
Both `cleanupAnonUidArtifacts.ts:413-435` (recovery UID-migration of `payerParticipantId`/`splitDistribution` on **live** expenses) and `deleteAccount.ts:499-504` (PII scrub of `description`/`note`) `.update()` expense docs via Admin → the trigger fires → classifies UPDATE (content changed) → logs an entry attributed via the `createdBy` fallback (admin code does not stamp `lastEditedBy`). This is imperfect (a recovery migration shows as "X edited the expense"). **PR 2 stance:** log it.
- **Partial mitigation in PR 2:** the `before.isDeleted === true → SKIP` guard (D2) drops scrubs/migrations of *already-soft-deleted* expenses (`cleanupAnonUidArtifacts` skips soft-deleted expenses entirely, `cleanupAnonUidArtifacts.ts:406`). **The guard does NOT cover live-expense system writes** — and there are two:
  - `cleanupAnonUidArtifacts` migrates **live** expense `payerParticipantId`/`splitDistribution` (`functions/src/callables/cleanupAnonUidArtifacts.ts:413-435`) → a MONEY/UPDATE entry on a live, visible expense.
  - `deleteAccount` scrubs **ALL** the user's expenses with no `isDeleted` filter (`functions/src/callables/deleteAccount.ts:499-506`), and only soft-deletes the *group* when there is no surviving real member (`functions/src/callables/deleteAccount.ts:588-591`). So when a user deletes their account in a **shared** group, the live-expense scrub fires the trigger → "edited" rows that **are visible** to surviving members. (The earlier "entries land in a hidden group" reasoning holds only for solo groups — corrected per Gate R1.)
- **Why it's still acceptable to defer:** these produce **no wrong money and no throw** — just a confusing, mis-attributed "edited" audit row. Attribution falls back to `after.createdBy` (admin writes don't stamp `lastEditedBy`). Two sub-cases: (a) the deleter IS the creator → their member doc is removed by `deleteAccount`, so `resolveActorName` returns `null` → "Someone edited an expense"; (b) the deleter is a **non-creator payer/split-party** → `after.createdBy` is the *original creator*, who is still a live member, so the row attributes the system scrub to the **innocent creator's real name** (Gate R2 P3). Both are cosmetic/confusing, not money-wrong, and the system-write sentinel follow-up resolves them.
- **Moot pre-launch:** recovery/deletion only run for real users; there are none ([[project_no_clients_deploy_freely]]).
- **Follow-up (named):** a system-write sentinel (have the admin callables stamp a reserved marker the trigger skips, or attribute to "System") once users exist. **The audit log is intentionally "every change to the doc" — logging system writes is more tamper-evident, not less; only attribution is imperfect.** Flagged prominently for the Gate.

### D6 — Soft dependency on PR 1; branch off `main` post-merge
The trigger code reads `after.lastEditedBy` defensively (`|| createdBy`), so it compiles and behaves correctly whether or not PR 1's Dart/rules are merged/deployed. The clean ordering is log-before-widen → PR 1 (the field) merges first, then PR 2. **Implementation gate:** confirm PR 1 (#337) is merged to `main` (`gh pr view 337 --json state,mergeCommitOid`), then `git worktree add ../Rihla-248-pr2 -b feat/248-pr2-audit-logger main`. Do **not** stack PR 2 on PR 1's branch (delete-on-merge would auto-close PR 2).

### D7 — Idempotent audit write keyed on the stable event id
Cloud Functions deliver **at-least-once**; a retry re-runs the handler. Write the audit doc with a **deterministic id derived from the trigger event id** so a retry overwrites the same doc instead of duplicating:
```ts
const auditDocId = event.id; // stable across retries of the same delivery
await db.doc(`groups/${gid}/events/${eid}/activity_logs/${auditDocId}`).set(auditEntry);
```
(The old client write used a random uuid — non-idempotent. This is a strict improvement.) `set` (not `create`) so a retry is a clean overwrite. Distinct deliveries (a later real edit) have distinct `event.id` → distinct rows, as intended.

### D8 — The trigger writes the established `ActivityLog` shape (reader stays unchanged)
Output doc keys = the **9 keys the existing client writer emits** (so `ActivityLog.fromFirestore` + `activity_feed_screen` render with **no client change**): `id, eventId, category, eventType, logText, actorId, actorName, metadata, createdAt`. The `ActivityLog` model `toFirestore` actually lists **10** keys — it also serializes `targetParticipantId` (`activity_log_model.dart:90`) — but that field is **nullable on read** (`:71`) and was never written by any producer (nor in the old client rule's `hasOnly`), so the trigger omits it exactly as the client did; `fromFirestore` does not throw on its absence.
- `category: 'MONEY'`, `eventType: 'CREATE' | 'UPDATE' | 'DELETE'`. The feed derives the displayed verb from `(category, eventType)` → l10n (`activity_display.dart:5-20`); the `MONEY/UPDATE` and `MONEY/DELETE` keys **already exist**. `logText` is only the non-localized fallback, but is **required-non-null** by `fromFirestore` — write a sensible server string.
- `id == auditDocId` (= `event.id`), `eventId == eid`, `createdAt = event.time` — **`CloudEvent.time` is already an ISO `string`** (`firebase-functions/lib/v2/core.d.ts`); do NOT call `.toISOString()` on it (it's not a `Date` — that's a `tsc` error). The Dart reader does `DateTime.parse(data['createdAt'] as String)` (`activity_log_model.dart:76`), so the raw ISO string is exactly right.
- `metadata` carries the money before/after for PR 3:
  ```ts
  metadata = {
    expenseId,                               // = the expense doc id (event.params.expenseId)
    before: before.exists ? moneySnap(beforeData) : null,   // null on CREATE
    after:  after.exists  ? moneySnap(afterData)  : null,    // present on CREATE/UPDATE/DELETE
  }
  // moneySnap(d) = { amountFils, currency, payerParticipantId, description, isDeleted }
  ```
  (`metadata` is `is map`-only in the old rule and is **not rendered today** — PR 3 renders it. No other reader depends on its shape.)

---

## Verification principles (run against this spec — reported out loud)

1. **Callsite classification (INBOUND/OUTBOUND/BOTH) on the `activity_logs` write path.** OUTBOUND writers today: client `_addExpenseCreatedActivity` (`expense_service.dart:221`, the only live one) + dead `ActivityService.addActivityLog` (`activity_service.dart:60`, zero `lib/` callers). Both are **removed**; the new **server trigger** (Admin) becomes the sole OUTBOUND writer. INBOUND reader: `activity_feed_screen.dart` via `activity_service.fetchActivityPageRaw` → `ActivityLog.fromFirestore` (unchanged). The trigger emits the **same 9-key shape** the reader consumes (D8) → no read-path break.
2. **Concrete claims re-verified against code** (this session): rule create-OR-list `firestore.rules:722-724` + `validActivityCreate` `:694-718` ✓; member name-resolution pattern `leaveGroup.ts:66-99` (`members.where('userId','==',uid)` → `displayName`) ✓; `release_workflow_gate_test.dart:588-623` pins **extractor parity** (`extracted == exported`), **not** a hardcoded count — a new re-export keeps parity, test stays green ✓; `tool/list_expected_functions.sh` awk auto-picks single+multi-line `export { … } from` ✓; admin expense writers `cleanupAnonUidArtifacts.ts:413-435` + `deleteAccount.ts:499-504` ✓; `formatAmount.ts` mirrors `MoneySerializer` ✓; `addExpense` `actorId`/`actorName` params (`expense_service.dart:107-108`) feed only the dropped write, sole prod caller `add_expense_screen.dart:55` ✓; existing triggers are all `onDocumentCreated` — `onDocumentWritten` + `makeChange` are new patterns (verified `makeDocumentSnapshot` is the only snapshot helper in use) ✓.
3. **Read-path per write-path.** Who reads the audit entries after the trigger writes them? `activity_feed_screen` (renders verb by `(category,eventType)`→l10n; DELETE already renders muted; UPDATE renders like CREATE until PR 3; `metadata` not yet rendered). The trigger's output is read-compatible. Who reads the *expense* doc the trigger observes? Unchanged — the trigger **never mutates the expense** (Task 2 asserts it; mirrors `writeRateMonitor.test.ts:192`).
4. **Fields enumerated from the type.** `ActivityLog` persisted keys (`activity_log_model.dart` `toFirestore`): `id, eventId, category, eventType, logText, actorId, actorName, metadata, createdAt`. Required-non-null on read (`fromFirestore`): `id, eventId, category, eventType, logText, createdAt`. `metadata` defaults `{}`; `actorId`/`actorName` nullable. The trigger writes all required keys.
5. **Data contracts (exact).** Trigger path `groups/{gid}/events/{eid}/expenses/{expenseId}`; audit doc id `event.id`; output doc shape + `metadata` per D8; classification predicates per D2; actor per D3; name-resolution contract per D4 (match `userId` field). Rule edit: delete `validActivityCreate` (`:694-718`) **and** its OR-branch (`:724`) → `allow create: if validExpenseCreate() || validEventSettlementCreate();`.
6. **Arithmetic decomposition.** N/A — the trigger performs **no balance math** (`BalanceCalculator`/`MoneySerializer` untouched). `amountFils` is stored verbatim into `metadata` as raw subunits; `formatAmount` is used only for the human `logText` fallback string. No allocator, no `splitDistribution` recomputation, no sum claim.
7. **Adversarial pass on an orthogonal axis (identity / forgery + blast radius).** The change is on the *attribution/ownership* axis; the adversarial cases exercise **forgery + the rule-deletion blast radius**: (a) a participant client forging a `MONEY/UPDATE` (or any) audit entry — *allowed today* (`validActivityCreate` only pins `actorId==auth.uid`, leaves `category`/`eventType`/`metadata` arbitrary) — is **now rejected** by the lock (Task 4 RED→GREEN); (b) deleting `validActivityCreate` does **not** widen any other surface — the group-level `activity` feed is a **separate** `match /activity/{activityId}` block (`validGroupActivityCreate`, ~`:800-844` — exact line shifts once PR 1's rules land), untouched, and `validActivityCreate`'s helpers (`isEventParticipant`/`eventAllowsClientWrites`/`isValidNullableDisplayName`) remain referenced elsewhere; (c) the trigger's `actorId` comes from the rule-pinned in-document `lastEditedBy`/`createdBy`, not forgeable client input; (d) loop-safety: watches `expenses/*`, writes `activity_logs/*` — disjoint, cannot self-refire (D1). Same-axis (money math) is deliberately not the example because the balance engine is provably untouched (principle 6).

---

## Tasks

> TDD throughout. Trigger Jest: `cd functions && npm run test:emulator` (boots the Firestore emulator on isolated ports + Jest, Java 21). Rules emulator: same command runs `firestore-rules-publish-readiness.test.ts`. Dart: `flutter test <file>`. `flutter analyze` clean before any commit. Atomic commits, all `Refs #248`. **Pre-req:** PR 1 merged to `main`; new worktree `../Rihla-248-pr2` off `main` (D6).

### Task 1: The `expenseAuditLogger` trigger — classification + write (logic-only, pure helpers first)

**Files:**
- Create: `functions/src/triggers/expenseAuditLogger.ts`
- Create (test): `functions/test/triggers/expenseAuditLogger.test.ts`

Build the trigger as a thin `onDocumentWritten` adapter over a pure `buildAuditEntry(before, after, params, eventId, eventTime)` helper + an async `resolveActorName(db, gid, actorUid)`, so classification is unit-testable without the emulator and the I/O is isolated (mirrors `settlementNotifier.ts`'s thin-adapter-over-handler shape).

**Step 1 — Write the failing test** (`expenseAuditLogger.test.ts`), mirroring `writeRateMonitor.test.ts:1-57` setup (`firebase-functions-test` offline + Admin SDK on the emulator + `clearFirestore`). Use `testEnv.makeChange(beforeSnap, afterSnap)` (new pattern) and `testEnv.firestore.makeDocumentSnapshot(data, path)`; model "before does not exist" with a non-existent snapshot (a `makeDocumentSnapshot` whose `.exists` is false — verify the exact `firebase-functions-test` idiom; if unavailable, construct via `makeDocumentSnapshot({}, path)` and assert on the create predicate). Cases (each `assertSucceeds`/read-back via Admin SDK):

```ts
// helper: seed a member so name resolution succeeds, incl. a CREATOR doc keyed by uuid (#294)
async function seedMember(gid: string, userId: string, displayName: string, docId = userId) {
  await getFirestore().doc(`groups/${gid}/members/${docId}`).set({ userId, displayName });
}
const EXP_PATH = 'groups/g1/events/e1/expenses/exp1';
function expData(o: Record<string, unknown> = {}) {
  return { id: 'exp1', eventId: 'e1', payerParticipantId: 'owner', amountFils: 10500,
    currency: 'OMR', scope: 'global', customSplitParticipants: [], isDeleted: false,
    deletedAt: null, createdAt: '2026-06-07T00:00:00.000Z', createdBy: 'owner',
    lastEditedBy: 'owner', ...o };
}
const params = { gid: 'g1', eid: 'e1', expenseId: 'exp1' };
const FIRE_TIME = '2026-06-07T00:00:00.000Z';

// firebase-functions-test 3.4.1 v2 contract: testEnv.wrap(fn) returns a fn taking
// a SINGLE CloudEvent-partial { data, params, id, time }. The field is `id` (CloudEvent.id),
// NOT `eventId`; `time` is an ISO STRING. (writeRateMonitor.test.ts:12 is the v2 template.)
const wrap = testEnv.wrap(expenseAuditLogger);
function fire(before: unknown, after: unknown, id: string) {
  return wrap({ data: testEnv.makeChange(before, after), params, id, time: FIRE_TIME });
}

test('CREATE logs one MONEY/CREATE entry attributed to the creator', async () => {
  await seedMember('g1', 'owner', 'Owner', 'member-uuid-not-owner'); // creator keyed by uuid (#294)
  const before = testEnv.firestore.makeDocumentSnapshot({}, EXP_PATH); // .exists === false
  const after = testEnv.firestore.makeDocumentSnapshot(expData(), EXP_PATH);
  await fire(before, after, 'evt-create-1');
  const logs = await getFirestore().collection('groups/g1/events/e1/activity_logs').get();
  expect(logs.size).toBe(1);
  const d = logs.docs[0].data();
  expect(d.category).toBe('MONEY'); expect(d.eventType).toBe('CREATE');
  expect(d.actorId).toBe('owner'); expect(d.actorName).toBe('Owner'); // resolved by userId field
  expect(d.metadata.expenseId).toBe('exp1');
  expect(d.metadata.before).toBeNull();
  expect(d.metadata.after.amountFils).toBe(10500);
});

test('UPDATE (amount change) logs MONEY/UPDATE with before/after money', async () => {
  await seedMember('g1', 'owner', 'Owner', 'member-uuid');
  const before = testEnv.firestore.makeDocumentSnapshot(expData(), EXP_PATH);
  const after = testEnv.firestore.makeDocumentSnapshot(expData({ amountFils: 12500 }), EXP_PATH);
  await fire(before, after, 'evt-update-1');
  const logs = await getFirestore().collection('groups/g1/events/e1/activity_logs').get();
  expect(logs.size).toBe(1);
  expect(logs.docs[0].data().eventType).toBe('UPDATE');
  expect(logs.docs[0].data().metadata.before.amountFils).toBe(10500);
  expect(logs.docs[0].data().metadata.after.amountFils).toBe(12500);
});

test('soft-DELETE (isDeleted false→true) logs MONEY/DELETE', async () => {
  const before = testEnv.firestore.makeDocumentSnapshot(expData(), EXP_PATH);
  const after = testEnv.firestore.makeDocumentSnapshot(
    expData({ isDeleted: true, deletedAt: '2026-06-07T01:00:00.000Z' }), EXP_PATH);
  await fire(before, after, 'evt-del-1');
  const logs = await getFirestore().collection('groups/g1/events/e1/activity_logs').get();
  expect(logs.size).toBe(1);
  expect(logs.docs[0].data().eventType).toBe('DELETE');
});

test('no content change writes nothing (D2 SKIP)', async () => {
  // identical before/after except a metadata-only / lastEditedBy-only delta
  const before = testEnv.firestore.makeDocumentSnapshot(expData(), EXP_PATH);
  const after = testEnv.firestore.makeDocumentSnapshot(expData({ lastEditedBy: 'owner' }), EXP_PATH);
  await fire(before, after, 'evt-noop-1');
  expect((await getFirestore().collection('groups/g1/events/e1/activity_logs').get()).size).toBe(0);
});

test('edit of an already-deleted expense writes nothing (admin scrub guard, D5)', async () => {
  const before = testEnv.firestore.makeDocumentSnapshot(expData({ isDeleted: true }), EXP_PATH);
  const after = testEnv.firestore.makeDocumentSnapshot(expData({ isDeleted: true, description: 'scrubbed' }), EXP_PATH);
  await fire(before, after, 'evt-scrub-1');
  expect((await getFirestore().collection('groups/g1/events/e1/activity_logs').get()).size).toBe(0);
});

test('actor falls back to createdBy when lastEditedBy empty (legacy doc)', async () => {
  await seedMember('g1', 'owner', 'Owner', 'm-uuid');
  const before = testEnv.firestore.makeDocumentSnapshot(expData({ lastEditedBy: '' }), EXP_PATH);
  const after = testEnv.firestore.makeDocumentSnapshot(expData({ lastEditedBy: '', amountFils: 9000 }), EXP_PATH);
  await fire(before, after, 'evt-legacy-1');
  expect((await getFirestore().collection('groups/g1/events/e1/activity_logs').get()).docs[0].data().actorId).toBe('owner');
});

test('actorName is null (not "Someone") when no member matches', async () => {
  // no seedMember
  const before = testEnv.firestore.makeDocumentSnapshot({}, EXP_PATH);
  const after = testEnv.firestore.makeDocumentSnapshot(expData(), EXP_PATH);
  await fire(before, after, 'evt-noname-1');
  expect((await getFirestore().collection('groups/g1/events/e1/activity_logs').get()).docs[0].data().actorName).toBeNull();
});

test('idempotent on retry: same event.id → exactly one entry (D7)', async () => {
  const before = testEnv.firestore.makeDocumentSnapshot({}, EXP_PATH);
  const after = testEnv.firestore.makeDocumentSnapshot(expData(), EXP_PATH);
  // SAME `id` on both calls models an at-least-once retry of one delivery → one doc.
  await fire(before, after, 'evt-dupe');
  await fire(before, after, 'evt-dupe'); // retry
  expect((await getFirestore().collection('groups/g1/events/e1/activity_logs').get()).size).toBe(1);
});

test('never mutates the expense doc (detection-only)', async () => {
  // mirror writeRateMonitor.test.ts:192 — the observed money doc is untouched
  const before = testEnv.firestore.makeDocumentSnapshot(expData(), EXP_PATH);
  const after = testEnv.firestore.makeDocumentSnapshot(expData({ amountFils: 12500 }), EXP_PATH);
  await fire(before, after, 'evt-immut-1');
  // the trigger writes activity_logs only; assert no write occurred to EXP_PATH (it never existed in the emulator)
  expect((await getFirestore().doc(EXP_PATH).get()).exists).toBe(false);
});
```
> The `fire()` helper encodes the **verified** `firebase-functions-test@3.4.1` v2 contract: `testEnv.wrap(fn)` → a fn taking a single CloudEvent-partial `{ data: Change, params, id, time }` (field is **`id`** = `CloudEvent.id`, **not** `eventId`; `time` is an ISO string). `writeRateMonitor.test.ts:12` is the v2 wrap template (it wraps `onDocumentCreated` with `{ data, params }`; `onDocumentWritten` adds the `before/after` `Change` via `makeChange`). The idempotency test reuses the same `id` to model an at-least-once retry. If a future `firebase-functions-test` bump changes the field name, only `fire()` changes; the assertions are the contract.

**Step 2 — Run, verify FAIL** (`cd functions && npm run test:emulator` — file/function does not exist). Paste the failure as RED evidence (#329).

**Step 3 — Implement** `expenseAuditLogger.ts`. Skeleton (mirror `settlementNotifier.ts` imports + thin-adapter shape):

```ts
import { getFirestore, DocumentData } from 'firebase-admin/firestore';
import { onDocumentWritten } from 'firebase-functions/v2/firestore';
import { logger } from 'firebase-functions/v2';
import '../admin';
import { formatAmount } from '../notifications/formatAmount';

const CONTENT_KEYS = ['amountFils','currency','payerParticipantId','description','note',
  'scope','subGroupId','categoryId','splitMode','splitDistribution','customSplitParticipants'] as const;

type AuditType = 'CREATE' | 'UPDATE' | 'DELETE';

// pure: returns the eventType to log, or null to SKIP (D2)
export function classify(before: DocumentData | undefined, after: DocumentData | undefined): AuditType | null {
  const beforeExists = before !== undefined;
  const afterExists = after !== undefined;
  if (!afterExists) return null;                              // hard delete — N/A on this path
  const wasDeleted = before?.isDeleted === true;
  const isDeleted = after!.isDeleted === true;
  if (!beforeExists) return isDeleted ? null : 'CREATE';      // create of a live doc
  if (wasDeleted) return null;                                // already-deleted edit (admin scrub) — SKIP (D5)
  if (isDeleted) return 'DELETE';                             // soft-delete
  return contentChanged(before!, after!) ? 'UPDATE' : null;  // real edit vs no-op
}

function contentChanged(b: DocumentData, a: DocumentData): boolean {
  return CONTENT_KEYS.some((k) => !deepEqual(b[k], a[k]));
}
// deepEqual: small structural compare for primitives/arrays/plain maps (no lib dep; or JSON-stable for maps).

function moneySnap(d: DocumentData) {
  return { amountFils: typeof d.amountFils === 'number' ? d.amountFils : 0,
    currency: typeof d.currency === 'string' ? d.currency : 'OMR',
    payerParticipantId: d.payerParticipantId ?? null,
    description: d.description ?? null,
    isDeleted: d.isDeleted === true };
}

async function resolveActorName(gid: string, actorUid: string): Promise<string | null> {
  if (!actorUid) return null;
  const snap = await getFirestore().collection(`groups/${gid}/members`).where('userId', '==', actorUid).get();
  return snap.docs.map((d) => d.data().displayName)
    .find((n): n is string => typeof n === 'string' && n.length > 0) ?? null;
}

export const expenseAuditLogger = onDocumentWritten(
  'groups/{gid}/events/{eid}/expenses/{expenseId}',
  async (event) => {
    const before = event.data?.before.exists ? event.data.before.data() : undefined;
    const after = event.data?.after.exists ? event.data.after.data() : undefined;
    const type = classify(before, after);
    if (!type) return;
    const { gid, eid, expenseId } = event.params;
    const afterData = after!;                                  // type !== null ⇒ after exists
    const actorUid = (afterData.lastEditedBy as string) || (afterData.createdBy as string) || '';
    const actorName = await resolveActorName(gid, actorUid);
    const createdAt = event.time;                             // ISO string commit time (D7)
    const entry = {
      id: event.id,
      eventId: eid,
      category: 'MONEY',
      eventType: type,
      logText: buildLogText(type, actorName, afterData),       // non-localized fallback (D8)
      actorId: actorUid,
      actorName,
      metadata: {
        expenseId,
        before: before ? moneySnap(before) : null,
        after: moneySnap(afterData),
      },
      createdAt,
    };
    await getFirestore().doc(`groups/${gid}/events/${eid}/activity_logs/${event.id}`).set(entry);
    logger.info('expenseAuditLogger logged', { gid, eid, expenseId, type, actorUid });
  },
);

function buildLogText(type: AuditType, name: string | null, d: DocumentData): string {
  const who = name ?? 'Someone';
  const money = formatAmount(typeof d.amountFils === 'number' ? d.amountFils : 0,
    typeof d.currency === 'string' ? d.currency : 'OMR');
  const label = (typeof d.description === 'string' && d.description.trim()) ? d.description.trim() : 'an expense';
  if (type === 'CREATE') return `${who} added ${label} for ${money} ${d.currency ?? 'OMR'}`;
  if (type === 'DELETE') return `${who} deleted ${label}`;
  return `${who} edited ${label}`;
}
```
Notes: `event.time` is the v2 event commit time (ISO string) — confirm its exact type and `.toISOString()` need against the installed `firebase-functions@7.2.5` types. `deepEqual` is a tiny local helper (arrays + plain maps + primitives) — do **not** add a dependency. Keep the file < 200 lines.

**Step 4 — Run, verify PASS** (`cd functions && npm run test:emulator`). Paste GREEN evidence.

**Step 5 — Commit:** `feat(functions): expenseAuditLogger trigger logs expense CRUD (#248)`.

---

### Task 2: Register the trigger in `index.ts` (deploy set 12 → 13)

**Files:**
- Modify: `functions/src/index.ts`
- Test (already exists, must stay green): `test/unit/release_workflow_gate_test.dart:588-623`

**Step 1 — Add the re-export** next to the other trigger blocks (after the `settlementNotifier` block, `index.ts:17-20`), in the `export { … } from` form (a bare `export const` is invisible to the deploy-drift extractor — CLAUDE.md):
```ts
export { expenseAuditLogger } from './triggers/expenseAuditLogger';
```

**Step 2 — Verify the extractor picks it up:**
Run: `bash tool/list_expected_functions.sh` → expect 13 lines including `expenseAuditLogger`.
Run: `flutter test test/unit/release_workflow_gate_test.dart` → expect PASS (the parity test `extracted == exported` holds — both extractors see the new re-export; no hardcoded count to bump).

**Step 3 — Commit:** `feat(functions): export expenseAuditLogger (#248)`.

---

### Task 3: Rules — lock event `activity_logs` to server-only (remove `validActivityCreate`)

**Files:**
- Modify: `security/firestore.rules`
- Test: `functions/test/firestore-rules-publish-readiness.test.ts` (do Task 3 + its tests as one RED→GREEN cycle — Task 4).

**Edits (exact):**
1. `allow create` OR-list (`firestore.rules:722-724`): remove the `|| validActivityCreate()` branch →
   ```
   allow create: if validExpenseCreate()
     || validEventSettlementCreate();
   ```
2. **Delete** the `validActivityCreate()` function (`:694-718`) entirely (no dead-but-kept rule — the `validEventSettlementUpdate` bear trap). Confirm via `rg 'validActivityCreate' security/firestore.rules` returns **zero** hits after the edit.
3. Add a server-only doc comment above the `allow create` block, mirroring the `_writeCounters`/`deletionAttempts` convention (`:907-911`):
   ```
   // #248: event activity_logs are written ONLY by the expenseAuditLogger trigger
   // via the Admin SDK (which bypasses rules). Clients may read but never create/
   // update/delete — a client cannot forge an audit entry. (update/delete already
   // denied: update is validExpenseUpdate() [module-gated to 'expenses'], delete is false.)
   ```
4. **Do not touch** `allow read` (`:720-721`, keeps `activity_logs`), `allow update`/`allow delete` (already effectively denied for `activity_logs`), or the group-level `validGroupActivityCreate` (separate `match /activity/` surface, ~`:800-844` depending on tree).

*(No code-only commit — rules land with their tests in Task 4.)*

---

### Task 4: Rules emulator tests — client create now DENIED, server write SUCCEEDS

**Files:**
- Modify: `functions/test/firestore-rules-publish-readiness.test.ts` (add an `activity_logs` server-lock block; reuse `seedBaseData`/`validEvent`/`assertSucceeds`/`assertFails`/`withSecurityRulesDisabled`, helpers `:38-155`).

**Step 1 — Write failing tests.** Build a `validActivityLog(overrides)` factory from the 9-key shape (see the existing live shape at `:652-662`), then:

```ts
function validActivityLog(o = {}) {
  return { id: 'aLE', eventId: 'e1', category: 'MONEY', eventType: 'CREATE',
    logText: 'x', actorId: 'member', actorName: 'Member', metadata: {},
    createdAt: new Date().toISOString(), ...o };
}

// RED before the lock (today's rule ALLOWS this), GREEN after (deny-all client create):
test('#248 participant can NO LONGER create an event activity_logs entry (server-only)', async () => {
  const member = testEnv.authenticatedContext('member').firestore();
  await assertFails(member.doc('groups/g1/events/e1/activity_logs/aLE').set(validActivityLog()));
});
test('#248 a forged MONEY/UPDATE audit entry from a client is rejected', async () => {
  const member = testEnv.authenticatedContext('member').firestore();
  await assertFails(member.doc('groups/g1/events/e1/activity_logs/aFake').set(
    validActivityLog({ id: 'aFake', eventType: 'UPDATE', metadata: { amountFils: 999999 } })));
});
// documents the trigger path: Admin SDK (rules-bypassing) write succeeds
test('#248 server (rules-disabled) CAN write an event activity_logs entry', async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await assertSucceeds(ctx.firestore().doc('groups/g1/events/e1/activity_logs/aSrv').set(
      validActivityLog({ id: 'aSrv', eventType: 'UPDATE' })));
  });
});
// reads still work for members (allow read unchanged)
test('#248 a group member can still READ event activity_logs', async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) =>
    ctx.firestore().doc('groups/g1/events/e1/activity_logs/aRead').set(validActivityLog({ id: 'aRead' })));
  const member = testEnv.authenticatedContext('member').firestore();
  await assertSucceeds(member.doc('groups/g1/events/e1/activity_logs/aRead').get());
});
```
The existing `#205 soft-deleted event rejects stale event writes` test (`:632-663`) — its `activity_logs` `assertFails` (`:652-662`) **stays green** (now denied by the lock rather than the deleted-event gate); add a one-line comment noting the lock now also covers it. No existing `assertSucceeds` activity_logs create test exists, so nothing else flips.

**Step 2 — Run, verify the new create/forge cases FAIL** against the **unmodified** rules (RED — the current rule *allows* a participant create). `cd functions && npm run test:emulator`.

**Step 3 — Apply Task 3 rule edits.**

**Step 4 — Run, verify all PASS** (new + the full existing rules suite stays green — paste RED→GREEN output into the PR per #329).

**Step 5 — Commit:** `feat(rules): lock event activity_logs to server-only (#248)` — Task 3 + 4 together.

---

### Task 5: Drop the client activity write (`expense_service` + dead `addActivityLog`)

**Files:**
- Modify: `lib/features/ledger/services/expense_service.dart` (remove `_addExpenseCreatedActivity` `:192-244` + its call/try-catch `:165-187` + unused `actorId`/`actorName` params `:107-108`)
- Modify: `lib/features/ledger/screens/add_expense_screen.dart` (drop the `actorId:`/`actorName:` args `:55`)
- Modify: `lib/features/activity/services/activity_service.dart` (remove dead `addActivityLog` `:49-71`; **keep** `fetchActivityPageRaw`/read path)
- Modify: `lib/features/activity/README.md:4` (documents `addActivityLog` as a live writer — update/remove that line so the doc doesn't outlive the method, Gate R1 P3)
- Test: `test/unit/expense_service_test.dart` (the activity-after-create assertion `:100`); delete `test/unit/activity_service_test.dart` `addActivityLog` group + `test/features/activity/activity_service_test.dart` `addActivityLog` tests

**Step 1 — Write/adjust the failing test** in `expense_service_test.dart`: assert that after `addExpense`, the event `activity_logs` collection is **empty** (the trigger — not the client — now owns the CREATE entry; `fake_cloud_firestore` doesn't run triggers, so no entry should appear):
```dart
test('addExpense no longer writes an activity_logs entry (trigger owns it, #248)', () async {
  final e = await service.addExpense(/* groupId, eventId, payerParticipantId, amount, createdBy */);
  final logs = await fake.collection('groups/g1/events/e1/activity_logs').get();
  expect(logs.docs, isEmpty);
});
```
(Replace/repurpose the existing `:100` assertion that checked the CREATE entry was written.)

**Step 2 — Run, verify FAIL** (`flutter test test/unit/expense_service_test.dart` — the old behavior still writes the entry).

**Step 3 — Implement** the removals. After deleting `_addExpenseCreatedActivity` and its call, remove the now-unused `actorId`/`actorName` params from `addExpense` and drop them at the sole prod caller (`add_expense_screen.dart:55`) and any test callers that pass them (`grep -rn "actorId:\|actorName:" test/unit/expense_service_test.dart`). Remove `ActivityService.addActivityLog`; delete its dedicated tests (`test/unit/activity_service_test.dart` + `test/features/activity/activity_service_test.dart` `addActivityLog` cases) — do **not** patch them (grep-and-delete obsolete assertions per CLAUDE.md).

**Step 4 — Run, verify PASS + `flutter analyze` clean** (no unused-import/param warnings from the removals). Run the full ledger + activity suites: `flutter test test/unit/expense_service_test.dart test/features/ledger/ test/features/activity/`.

**Step 5 — Commit:** `refactor(ledger): drop client activity write — expenseAuditLogger owns it (#248)`.

---

### Task 6: Full-suite green + analyze + PR

**Steps:**
1. `flutter analyze` → clean.
2. `flutter test` → full Dart suite green.
3. `cd functions && npm run test:emulator` → trigger + rules suites green (Java 21).
4. `cd functions && npm run build` → `tsc` clean (the predeploy step; catches type errors in the trigger).
5. Open the PR: `Refs #248` (NOT `Closes`), `Spec:` line → this file, paste RED→GREEN evidence (trigger + rules) per #329. `/automerge` review+refute at merge (Gate-category: Functions + rules).

---

## Deploy

PR 2 ships a **new trigger + rules lock + client write removal**. Per [[project_no_clients_deploy_freely]] (no real users), it deploys freely on merge — no client-compat ordering. After merge: `deploy-ceremony` skill / `tool/pending_deploy.sh` → deploys Functions (the new `expenseAuditLogger`) + rules, advances the `backend-deployed` tag, records `docs/DEPLOY-LEDGER.md`. The deployed-functions drift check expects **13** functions afterward (auto from `tool/list_expected_functions.sh`). No new index required (the trigger uses an equality query on `members.userId`, which is single-field auto-indexed). The client change (Task 5) rides in the same PR; old clients in the wild would have their `_addExpenseCreatedActivity` write silently rejected by the lock (fire-and-forget, swallowed) and the trigger writes the canonical entry → no double-log even mid-rollout.

## Done checklist (PR 2)
- [ ] `expenseAuditLogger` `onDocumentWritten` on `expenses/*`: CREATE/UPDATE(content-changed)/soft-DELETE logged; no-op + already-deleted edits SKIP (D2/D5); never mutates the expense doc.
- [ ] Actor = `lastEditedBy || createdBy`; name resolved by `members.where('userId','==',uid)` (#294), `null` (not "Someone") when unresolved (D3/D4).
- [ ] Idempotent on retry (audit doc id = `event.id`, D7); writes the 9-key `ActivityLog` shape + `metadata.before/after` money (D8).
- [ ] `index.ts` re-export → `list_expected_functions.sh` shows 13; `release_workflow_gate_test` green.
- [ ] Rules: `validActivityCreate` deleted + its OR-branch removed; `rg validActivityCreate` = 0; read unchanged; group `activity` untouched.
- [ ] Emulator: client create/forge now DENIED; `withSecurityRulesDisabled` server write SUCCEEDS; member read still works; existing suite green.
- [ ] Client: `_addExpenseCreatedActivity` + unused params + dead `addActivityLog` removed; `addExpense` no longer writes `activity_logs`; obsolete tests deleted.
- [ ] Money invariants reconfirmed untouched: no `BalanceCalculator`/`MoneySerializer`/allocator/`splitDistribution`-recompute change; trigger is detection-only.
- [ ] `flutter analyze` clean; full Dart + functions (trigger + rules) suites green; `tsc` build clean; RED→GREEN pasted in PR.
- [ ] Fresh-context Opus Gate to no-P1 (`/run-the-gate`) **before** code; `/automerge` review+refute at merge.
- [ ] PR body: `Refs #248` (NOT `Closes`), `Spec:` line → this file. PR 1 (#337) confirmed merged before implementation (D6).
