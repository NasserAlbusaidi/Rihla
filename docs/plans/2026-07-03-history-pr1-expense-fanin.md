# History PR1 — Expense Fan-In to the Group Activity Feed (#808 PR1)

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** `expenseAuditLogger` also emits group-level `expense_added` / `expense_edited` / `expense_deleted` entries into `groups/{gid}/activity`, so the group and cross-group Activity surfaces finally see money history (the audit's "Activity tab never shows expenses" gap).

**Architecture:** Extend the existing trigger (one `classify()` pass, shared actor resolution, shared `claimRekeyAt` suppression) with a second idempotent write to the group activity collection, in the exact `GroupActivityLog` client shape. Harden `validGroupActivityCreate` with a type allow-list so clients cannot forge server-only entries, and teach the write-rate monitor to skip the derivative server writes.

**Tech Stack:** Cloud Functions v2 (Node 22/TS), firebase-functions-test 3.4.1 + Firestore emulator (Jest), Firestore security rules.

**Scope law:** Server + rules only. Zero Dart behavior change (one Dart *pinning* test only). PR is `Refs #808` (PR1 of 3) — in the COMMIT BODY too, not just the PR body (squash-merge auto-close trap, #447).

---

## Verified ground truth (all re-checked against live code 2026-07-03)

**Write paths into `groups/{gid}/activity` today:**
- Client `GroupActivityService.logGroupEvent` (fire-and-forget). Complete type enumeration from every callsite:
  - `event_created` — `lib/features/events/screens/create_event_screen.dart:195`
  - `event_deleted` — `lib/features/events/widgets/event_danger_section.dart:488`
  - `group_settlement` — `lib/features/groups/screens/group_settle_up_screen.dart:886,1025`
  - `member_joined` — `lib/features/groups/screens/join_group_screen.dart:204`
- Server (Admin SDK, bypasses rules): `member_left` — `functions/src/callables/leaveGroup.ts:165`, `functions/src/callables/removeMember.ts:216`.
- Rules today (`security/firestore.rules:993-1018`): any group member may create with **`type is string` — no allow-list**. A client can forge `member_left` or (post-PR1) `expense_added` audit-looking entries. Update/delete already `false`.

**Read paths (all INBOUND / display-only — classified per verification principle 1):**
- `watchRecentActivity` (group screen recent-5; cross-group #804 window 15/group, 30 merged)
- `fetchActivityPage`/`fetchActivityPageRaw` (group_activity_screen, 50/page cursor)
- `cross_group_activity_screen.dart:336` + `home/widgets/activity_row.dart:32` render via `localizedGroupActivityText`, which falls back to **`log.description` for unknown types** (`activity_display.dart:44`) and renders `actorName` separately in `Text.rich`. → New types render readably TODAY with zero client change; PR2 adds l10n + icons + pagination.
- No OUTBOUND path reads this collection (nothing feeds a write or money math from it). The #366 aggregate and oracle are untouched.

**Deserialization contract** (`group_activity_log_model.dart` — fields enumerated from the type, principle 4):
`id` (must equal doc id), `type` (string), `actorId` (string, required), `actorName` (string? → `'Unknown'` fallback), `description` (**required non-null String** — `data['description'] as String` throws on null), `metadata` (map, default `{}`), `timestamp` (ISO-8601 string OR Timestamp; ordered by lexicographic string sort — Dart client writes `DateTime.now().toUtc().toIso8601String()`).
Server parity model: `leaveGroup.ts:163-171` writes `{id: ref.id, type, actorId, actorName, description: 'left the group', metadata: {}, timestamp: new Date().toISOString()}` — **description is a verb phrase WITHOUT the actor name** (the row renders `actorName` separately; the per-event `logText` convention of embedding "who" would double-print the name here).

**Trigger invariants that must extend to the new write** (`expenseAuditLogger.ts`):
- Idempotency: doc id = `event.id`, `.set` (stable across at-least-once retries).
- `claimRekeyAt` suppression (`:168`) must gate BOTH writes (a shadow-claim re-key produces neither an event log nor a group entry).
- Loop safety: the group activity write fires only `groupActivityWriteRateMonitor` (whose counter lives at `_writeCounters`, not a watched path) — no re-fire loop.

**Collateral systems checked:**
- `claimShadow.ts:718` `rekeyActivityLogs` re-keys `actorId` + metadata identity values on group activity — new entries carry `actorId` (re-keyed) and **no uid-keyed metadata maps** (deliberate: metadata is ids + money scalars only).
- `deleteAccount.ts:553-565` scrubs group activity via field-matching `activityUpdates(...)` — keying-agnostic, covers new entries with no change.
- `writeRateMonitor.ts` T3 (`groupActivityWriteRateMonitor`) counts every activity create per `resolveActorUid` (createdBy → actorId). The fan-in entry would **double-count** the actor (their expense create is already counted by T1 `eventWriteRateMonitor`). Must skip `expense_*` — safe ONLY because the rules allow-list (Task 2) makes `expense_*` server-only, so a client can't use the skip to evade counting. Mirrors the #526 `activity_logs` filter rationale.
- Timestamp interleaving: `event.time` (millisecond ISO) vs Dart microsecond ISO sort lexicographically; divergence only within the same millisecond — irrelevant for a display feed.
- `metadata.currency` follows the #382 PR-4 `activityAmountCurrency` contract; amount is `amountFils` (integer subunits, copied verbatim from the expense doc — no arithmetic, principle 6 N/A). The legacy `metadata['amount']` decimal-string key used by settlement rows is deliberately NOT reused.

**Decided trade-off (do not re-litigate in review):** new expense entries will dominate the #804 30-entry cross-group window until PR2 paginates and renders them properly. Interim readable-via-description rendering was accepted when shape A was decided (2026-07-02). No backfill (no real users; server deploys freely).

**Gate rd-1 P3 clarifications (0 P1 / 0 P2, 2026-07-03):**
- "Verb phrase" descriptions embed the live expense label when present — `edited Hotel`, `deleted Dinner`, falling back to `an expense` only when the description is blank. That's intended (more informative), not a deviation.
- The cross-group screen's filter chips (`cross_group_activity_screen.dart` `_Filter`: All/Settlements/Events/Members) have no `expense_*` bucket — new entries appear only under "All" until PR2 adds the expense rendering + filter. Deferred to PR2 on purpose.

---

### Task 1: Fan-in write in `expenseAuditLogger` (TDD)

**Files:**
- Modify: `functions/src/triggers/expenseAuditLogger.ts`
- Test: `functions/test/triggers/expenseAuditLogger.test.ts`

**Step 1: Write the failing tests** — new `describe('group activity fan-in')` in the existing file, reusing `fire`/`snap`/`expData`/`seedMember` helpers. Group collection const: `const GROUP_ACTIVITY = 'groups/g1/activity';`

```ts
describe('group activity fan-in (#808 PR1)', () => {
  test('CREATE also writes one expense_added group entry in GroupActivityLog shape', async () => {
    await seedMember('owner', 'Owner', 'member-uuid-not-owner');
    await getFirestore().doc('groups/g1/events/e1').set({ name: 'Muscat trip' });
    await fire(absent(), snap(expData({ description: 'Dinner' })), 'evt-1');
    const group = await getFirestore().collection(GROUP_ACTIVITY).get();
    expect(group.size).toBe(1);
    const d = group.docs[0].data();
    expect(group.docs[0].id).toBe('evt-1');
    expect(d).toMatchObject({
      id: 'evt-1',
      type: 'expense_added',
      actorId: 'owner',
      actorName: 'Owner',
      description: 'added Dinner (10.500 OMR)',
      timestamp: FIRE_TIME,
      metadata: {
        expenseId: 'exp1',
        eventId: 'e1',
        eventName: 'Muscat trip',
        amountFils: 10500,
        currency: 'OMR',
      },
    });
  });

  test('UPDATE → expense_edited; DELETE → expense_deleted (verb-only descriptions)', async () => {
    await getFirestore().doc('groups/g1/events/e1').set({ name: 'Muscat trip' });
    await fire(snap(expData()), snap(expData({ amountFils: 9000 })), 'evt-2');
    await fire(snap(expData()), snap(expData({ isDeleted: true, description: 'Dinner' })), 'evt-3');
    const group = await getFirestore().collection(GROUP_ACTIVITY).get();
    const byId = Object.fromEntries(group.docs.map((x) => [x.id, x.data()]));
    expect(byId['evt-2'].type).toBe('expense_edited');
    expect(byId['evt-2'].description).toBe('edited an expense');
    expect(byId['evt-3'].type).toBe('expense_deleted');
    expect(byId['evt-3'].description).toBe('deleted Dinner');
  });

  test('no-op edit and claimRekeyAt re-key write neither entry', async () => {
    await fire(snap(expData()), snap(expData()), 'evt-4');
    await fire(snap(expData()), snap(expData({ payerParticipantId: 'uid9', claimRekeyAt: 't1' })), 'evt-5');
    expect((await getFirestore().collection(GROUP_ACTIVITY).get()).size).toBe(0);
    expect((await logs()).size).toBe(0);
  });

  test('at-least-once retry collapses to one group doc', async () => {
    await fire(absent(), snap(expData()), 'evt-6');
    await fire(absent(), snap(expData()), 'evt-6');
    expect((await getFirestore().collection(GROUP_ACTIVITY).get()).size).toBe(1);
  });

  test('missing event doc → eventName empty string, unresolved actor → actorName null', async () => {
    await fire(absent(), snap(expData()), 'evt-7');
    const d = (await getFirestore().collection(GROUP_ACTIVITY).get()).docs[0].data();
    expect(d.metadata.eventName).toBe('');
    expect(d.actorName).toBeNull();
  });
});
```

**Step 2: Run to verify RED**

Run: `cd functions && bash ../tool/run_firebase_emulator_tests.sh triggers/expenseAuditLogger.test.ts -t "group activity fan-in"`
Expected: FAIL — group collection empty (`Expected: 1, Received: 0`).

**Step 3: Minimal implementation** — in `expenseAuditLogger.ts`:

```ts
export type GroupExpenseActivityType =
  | 'expense_added'
  | 'expense_edited'
  | 'expense_deleted';

const GROUP_TYPE: Record<AuditType, GroupExpenseActivityType> = {
  CREATE: 'expense_added',
  UPDATE: 'expense_edited',
  DELETE: 'expense_deleted',
};

// Group-feed description is a VERB PHRASE without the actor name — the activity
// row renders actorName separately (leaveGroup.ts parity: 'left the group');
// embedding "who" here would double-print the name. English-only fallback:
// current clients render unknown types via activity_display.dart's
// `_ => log.description`; PR2 localizes by type.
export function buildGroupDescription(type: AuditType, d: DocumentData): string {
  const label =
    asString(d.description).trim().length > 0
      ? asString(d.description).trim()
      : 'an expense';
  if (type === 'CREATE') {
    const currency = asString(d.currency) || 'OMR';
    const money = formatAmount(
      typeof d.amountFils === 'number' ? d.amountFils : 0,
      currency,
    );
    return `added ${label} (${money} ${currency})`;
  }
  if (type === 'DELETE') return `deleted ${label}`;
  return `edited ${label}`;
}
```

In the handler, after the event-log `.set` (and inside the same suppression flow — the `claimRekeyAt` early-return at :168 already precedes everything):

```ts
    let eventName = '';
    try {
      const eventSnap = await getFirestore().doc(`groups/${gid}/events/${eid}`).get();
      const rawName = eventSnap.data()?.name;
      if (typeof rawName === 'string') eventName = rawName;
    } catch (error) {
      logger.warn('expenseAuditLogger: event name lookup failed', {
        gid, eid, error: String(error),
      });
    }

    // #808 PR1 — fan the same audit event into the group activity feed, in the
    // exact GroupActivityLog client shape (group_activity_log_model.dart):
    // description non-null, timestamp ISO string (lexicographic sort with the
    // client's toIso8601String), doc id == data.id == event.id (idempotent).
    // Metadata carries ids + money scalars only — no uid-keyed maps, so the
    // claimShadow rekey (actorId) and deleteAccount scrub cover it unchanged.
    await getFirestore()
      .doc(`groups/${gid}/activity/${event.id}`)
      .set({
        id: event.id,
        type: GROUP_TYPE[type],
        actorId: actorUid,
        actorName,
        description: buildGroupDescription(type, afterData),
        metadata: {
          expenseId,
          eventId: eid,
          eventName,
          amountFils: typeof afterData.amountFils === 'number' ? afterData.amountFils : 0,
          currency: asString(afterData.currency) || 'OMR',
        },
        timestamp: event.time,
      });
```

Note: `DELETE` snapshots money from `afterData` (the soft-deleted doc still carries amount/currency — soft delete keeps content).

**Step 4: Run to verify GREEN** — same command. Then the full trigger file: `bash ../tool/run_firebase_emulator_tests.sh triggers/expenseAuditLogger.test.ts` (existing event-log tests must stay green — they assert on the event collection only, unaffected by the extra write; any `logs().size` assertions are per-collection and remain valid).

**Step 5: Commit** — `feat(functions): fan expense audit events into the group activity feed (#808 PR1)` (body: `Refs #808`).

---

### Task 2: Rules — type allow-list on `validGroupActivityCreate` (TDD)

**Files:**
- Modify: `security/firestore.rules:1008` (the `request.resource.data.type is string` line)
- Test: `functions/test/firestore-rules-publish-readiness.test.ts`

**Step 1: Failing tests** — in the group-activity describe block (find via `grep -n "activity" functions/test/firestore-rules-publish-readiness.test.ts`; add one if absent). Table:
- each of `event_created`, `event_deleted`, `group_settlement`, `member_joined` → **accepted** (member-authored, full valid shape)
- `expense_added`, `member_left`, `totally_made_up` → **rejected** (`permission-denied`)

**Step 2: RED run**: `cd functions && bash ../tool/run_firebase_emulator_tests.sh firestore-rules-publish-readiness.test.ts -t "<new describe name>"`. The three reject cases FAIL today (any string passes) — that failing output is the PR's RED evidence.

**Step 3: Implementation** — replace `&& request.resource.data.type is string` with:

```
&& request.resource.data.type in ['event_created', 'event_deleted', 'group_settlement', 'member_joined']
```

(`member_left` is Admin-only — leaveGroup/removeMember bypass rules; excluding it closes an existing forgery hole. `expense_*` become server-only like the #248 event logs.) Expression-count risk: none — this path is flat, nowhere near the event-update OR-chain ceiling (#723).

**Step 4: GREEN run** — same command, then the full rules file.

**Step 5: Commit** — `fix(rules): allow-list client group-activity types (#808 PR1)`.

---

### Task 3: Write-rate monitor skips server fan-in entries (TDD)

**Files:**
- Modify: `functions/src/triggers/writeRateMonitor.ts` (T3 handler, ~:127)
- Test: `functions/test/triggers/writeRateMonitor.test.ts`

**Step 1: Failing test** — mirror the existing T3 test pattern: a `groups/{gid}/activity` create with `type: 'expense_added'` + `actorId` must NOT increment `_writeCounters` (today it does — RED); a `type: 'event_created'` create still counts.

**Step 2: RED run**: `bash ../tool/run_firebase_emulator_tests.sh triggers/writeRateMonitor.test.ts -t "<test name>"`.

**Step 3: Implementation:**

```ts
// #808 PR1 — expense_* entries are server-written fan-ins of an expense create
// that T1 already counted; counting them would double-bill the actor. Safe to
// key the skip on type: the rules allow-list makes expense_* un-forgeable by
// clients (same rationale as the #526 activity_logs filter).
export const groupActivityWriteRateMonitor = onDocumentCreated(
  'groups/{gid}/activity/{activityId}',
  (event) => {
    const type = event.data?.data()?.type;
    if (typeof type === 'string' && type.startsWith('expense_')) {
      return Promise.resolve();
    }
    return countCreate(event.params.gid, event.data);
  },
);
```

**Step 4: GREEN run** — file-scoped, then commit: `fix(functions): rate monitor skips server fan-in activity entries (#808 PR1)`.

---

### Task 4: Dart pin — unknown group-activity types render via description

**Files:**
- Test only: extend the existing activity-display unit test (find via `grep -rln "localizedGroupActivityText" test/`; create `test/features/activity/activity_display_test.dart` if absent).

**Step 1:** Test that `localizedGroupActivityText` returns `log.description` for `type: 'expense_added'` (pins the PR1-interim rendering contract so a PR2-era refactor can't silently break old entries).

**Step 2:** Run: `flutter test <file>` — passes immediately (pin, not RED; this is not a bug fix).

**Step 3: Commit** — `test(activity): pin description fallback for expense_* group activity types (#808 PR1)`.

---

### Task 5: Verify, ship

- [ ] `cd functions && npm run lint && npm run build`
- [ ] Full functions emulator suite: `bash tool/run_firebase_emulator_tests.sh`
- [ ] `flutter analyze` clean; `flutter test test/features/activity/ test/unit/`
- [ ] Branch `feat/808-pr1-expense-fanin`; PR body: `Refs #808` + Spec: line pointing at this file + RED evidence from Tasks 2/3 pasted
- [ ] Commit body carries `Refs #808` (NOT `Closes` — PR1 of 3)
- [ ] After merge: deploy ceremony (`deploy-ceremony` skill — functions + rules together; the monitor skip is only safe once the rules allow-list is live, same deploy)
