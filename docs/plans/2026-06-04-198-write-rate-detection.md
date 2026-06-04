# Spec: #198 — per-UID write-rate detection trigger (detection-only)

**Issue:** #198 — no per-UID rate limit on expense/settlement/activity writes (P2, security, backend).
**Decision (this session):** *Detection-only* — flag bursts, **never** delete/modify financial data.
**Why not prevention:** Expense/settlement/activity writes are **client-direct** (Firestore offline persistence + replay; CLAUDE.md forbids routing them through a callable/queue). A trigger fires *after* commit, so it cannot reject. Auto-deleting an over-threshold financial doc on a false positive is money-wrong. So the only safe real-time mechanism is detect-and-log.

## Threat (verbatim scope)

Authenticated co-member (insider griefing) creates unlimited writes → balloons a group's collections (storage/index cost, degraded query latency) and is the enabling primitive for read-amplification. NOT remote/unauth. App Check attests the app but does not throttle per-UID volume.

## Surfaces to count (verified against `security/firestore.rules`)

All five carry a deterministic actor UID stamped at create and pinned `== request.auth.uid` by rules:

| Path | Match in rules | Actor field |
|---|---|---|
| `groups/{gid}/events/{eid}/expenses/{xid}` | `match /{module}/{docId}` (469), `validExpenseCreate` (567) `module=='expenses'` | `createdBy` (574) |
| `groups/{gid}/events/{eid}/settlements/{sid}` | same wildcard, `validEventSettlementCreate` (661) `module=='settlements'` | `createdBy` (667) |
| `groups/{gid}/events/{eid}/activity_logs/{aid}` | same wildcard, `validActivityCreate` (689) `module=='activity_logs'` | `actorId` (706) |
| `groups/{gid}/settlements/{sid}` | `match /settlements/{settlementId}` (822), `validGroupSettlementCreate` (862) | `createdBy` (867) |
| `groups/{gid}/activity/{aid}` | `match /activity/{activityId}` (795) | `actorId` (809) |

## Trigger registration (verified wildcard-collection-segment support)

Firestore v2 triggers allow wildcard **collection** segments (`users/{u}/{coll}/{doc}` is valid; matches extracted into `event.params`). So:

- **T1 `groups/{gid}/events/{eid}/{module}/{docId}`** — one trigger covers all three event sub-collections. Inside, **filter `params.module ∈ {expenses, settlements, activity_logs}`**; ignore any other future sub-collection.
- **T2 `groups/{gid}/settlements/{settlementId}`** — group-level settlements (literal collection).
- **T3 `groups/{gid}/activity/{activityId}`** — group-level activity (literal collection).

All three call **one shared handler** `recordWrite(gid, uid)`.

**Self-trigger-loop guard (load-bearing):** the counter lives at `groups/{gid}/_writeCounters/{uid}`. None of T1/T2/T3 match `_writeCounters` (it is a direct group sub-collection, not under `events/`, and not named `settlements`/`activity`). So the counter write never re-fires a trigger. **Do NOT** broaden T2/T3 to `groups/{gid}/{collection}/{docId}` — that WOULD match `_writeCounters` → infinite loop (and would also fire on every member/event create).

## Actor extraction

`uid = data.createdBy ?? data.actorId`. If neither is a non-empty string → `logger.warn` + return (do not count). Rules guarantee the field on client writes; this guard only protects against malformed/abnormal docs.

**Server-written creates are not double-counted as abuse:** `deleteAccount`/`joinGroupByInviteCode` only *update* expenses/settlements/activity or create *member*/*tombstone* docs (not counted). `deleteGroup` — confirm in the Gate it creates no activity/settlement docs under these paths; if it does, those fire under the acting uid (low-volume server action, benign).

## Counter doc — `groups/{gid}/_writeCounters/{uid}`

Mirrors the established `deletionAttempts`/`deleteGroupAttempts` pattern (server-only + TTL). Single-underscore prefix is a legal Firestore id (reserved pattern is `__.*__`).

Fields:
- `count: number` — writes in the current window.
- `windowStart: Timestamp` — start of the active window.
- `expiresAt: Timestamp` — `windowStart + WINDOW_MS + buffer`; drives Firestore TTL self-reap.
- `lastFlaggedAt: Timestamp | absent` — set when a burst is flagged (observability: query flagged groups).

### Handler logic (transactional read-modify-write)

**Snapshot guard (v7):** `onDocumentCreated`'s `event.data` is typed `QueryDocumentSnapshot | undefined`. Each trigger must `const snap = event.data; if (!snap) return;` before `snap.data()`. `event.params` is `ParamsOf<path>` (e.g. `{ gid, eid, module, docId }` for T1). Derive `gid` from `event.params.gid` (not the snapshot ref).

```
recordWrite(gid, uid):
  ref = groups/{gid}/_writeCounters/{uid}
  runTransaction(tx):
    now = Timestamp.now()
    data = tx.get(ref).data() ?? {}
    inWindow = data.windowStart is Timestamp && now - windowStart < WINDOW_MS
    count = inWindow ? (data.count ?? 0) : 0
    windowStart = inWindow ? data.windowStart : now
    next = count + 1
    crossed = (count < LIMIT && next > LIMIT)   // only the crossing fire flags
    set(ref, {
      count: next,
      windowStart,
      expiresAt: windowStart + WINDOW_MS + WINDOW_BUFFER_MS,
      ...(crossed ? { lastFlaggedAt: now } : {}),
    }, merge)
    return { crossed, next, windowStart }
  if crossed: logger.warn('write-rate burst flagged', { gid, uid, count: next, windowMs: WINDOW_MS, limit: LIMIT })
```

Transaction (not bare `FieldValue.increment`) because window-reset needs read-modify-write and the threshold check must see the post-increment value atomically. Burst contention on one doc causes tx retries — acceptable for detection (that *is* the abuse case); never blocks the original write (the create already committed).

### Constants (test seam, env-overridable like `DELETE_ACCOUNT_BATCH_LIMIT`)

- `WRITE_RATE_WINDOW_MS = 60_000` (1 min).
- `WRITE_RATE_LIMIT = Number(process.env.WRITE_RATE_LIMIT) || 100` per window. Rationale: normal manual use is a few/min; **offline replay** of a heavy user (the SDK flushes queued creates in a burst on reconnect) can legitimately spike — 100/min comfortably clears that while scripted ballooning does thousands/min. Read at handler construction so a test can set a low value.
- `WINDOW_BUFFER_MS = 60_000` — TTL grace so a doc isn't reaped mid-window.

**Offline-replay false flags are acceptable** precisely because this is detection-only: a benign flag is one `warn` log line + one `lastFlaggedAt`, never a blocked or deleted write.

## Firestore rules — append

```
match /groups/{groupId}/_writeCounters/{uid} {
  allow read, write: if false;   // server-only (Admin SDK trigger bypasses rules)
}
```
**Note (P3):** the recursive default-deny `match /{document=**} { allow read, write: if false }` (rules:159) ALREADY denies clients this path, so this explicit match is defense-in-depth / documentation only — but it matches the convention of the other explicit `if false` counter matches (`joinAttempts` etc.), so keep it for readability/consistency. Place under the existing `match /groups/{groupId}` block, after the other group sub-collection matches.

## firestore.indexes.json — append TTL fieldOverride

```
{ "collectionGroup": "_writeCounters", "fieldPath": "expiresAt", "ttl": true,
  "indexes": [ {ASC,COLLECTION},{DESC,COLLECTION},{CONTAINS,COLLECTION} ] }
```
Same override SHAPE as `deletionAttempts`/`deleteGroupAttempts`, but note this is the project's **first per-group SUBcollection TTL** (the existing three are top-level collections). Firestore TTL keys on the `collectionGroup` id across all nesting depths, so a subcollection `_writeCounters` under every group is covered by one override — no top-level doc path involved.

## Files

- **New** `functions/src/triggers/writeRateMonitor.ts` — shared `recordWrite` + exported T1/T2/T3 (`onDocumentCreated`).
- `functions/src/index.ts` — `export { eventWriteRateMonitor, groupSettlementWriteRateMonitor, groupActivityWriteRateMonitor } from './triggers/writeRateMonitor';`
- `security/firestore.rules` — `_writeCounters` server-only match.
- `firestore.indexes.json` — `_writeCounters` TTL override.
- **New** `functions/test/triggers/writeRateMonitor.test.ts`.

## Tests (TDD — emulator jest)

**No trigger-test precedent exists in `functions/test/` — every existing `testEnv.wrap` is a callable.** A v2 trigger wraps differently: `wrap(trigger)` returns a `WrappedV2Function` called with a partial CloudEvent, and the snapshot is built with `makeDocumentSnapshot`:

```ts
const wrapped = testEnv.wrap(eventWriteRateMonitor);
const snap = testEnv.firestore.makeDocumentSnapshot(
  { createdBy: 'eve', amountFils: 1000, /* ... */ },
  'groups/g1/events/e1/expenses/x1',
);
await wrapped({ data: snap, params: { gid: 'g1', eid: 'e1', module: 'expenses', docId: 'x1' } });
```

Do NOT copy the callable `{ data, auth }` shape — that yields `undefined` `event.data`/`event.params`. RED first. Use a low `WRITE_RATE_LIMIT` via env to trip the threshold cheaply.

1. **counts a single event-expense create** → counter doc `count == 1`, `windowStart` set, `expiresAt` ≈ windowStart + window + buffer.
2. **event settlement + activity_log both counted** (T1 covers all three modules; actor resolved from `createdBy` vs `actorId`).
3. **group-level settlement (T2) and group activity (T3) counted** under the right uid.
4. **crossing the limit logs a warn exactly once + sets `lastFlaggedAt`**; staying under does neither (spy on `logger.warn`).
5. **window reset**: a create after `windowStart + WINDOW_MS` resets `count` to 1 and advances `windowStart`.
6. **actor resolution**: activity doc with `actorId` (no `createdBy`) is attributed to `actorId`; expense with `createdBy` to `createdBy`.
7. **malformed doc** (neither `createdBy` nor `actorId` a non-empty string) → no counter write, warn logged, no throw.
8. **never mutates the financial doc** — after the trigger, the created expense/settlement/activity doc is byte-identical (detection-only).
9. **unknown `params.module`** (e.g. a doc under `events/{eid}/somethingelse/{id}`) → ignored, no counter write.
10. **per-group isolation**: same uid writing in two groups increments two separate `_writeCounters` docs.

## Out of scope / documented residuals

- **No prevention** (writes are client-direct; can't reject post-commit). Hard-rejection would require a callable write-path → breaks offline replay → explicitly forbidden.
- **`count` is total write-rate across the 5 collections, not "number of expenses"** — an expense-add that also writes an activity_log increments by 2. That is fine: it is a write-rate signal, not an expense count.
- **Per-write function-invocation cost** on every money write — negligible at consumer scale; accepted in the decision.
- Response to a flag is **manual** (ops sees the `warn`/`lastFlaggedAt`, then intervenes). Auto-quarantine is a deliberate non-goal for 1.0.

## Gate checklist mapping

- **Callsite classification:** the trigger is OUTBOUND-only (writes `_writeCounters`); it never feeds back into a money read-path. The counter doc is read by nobody in-app (server-only).
- **One read-path per write-path:** `_writeCounters` is written by the trigger, read by ops/queries only — no app read path, so no staleness/`ledgerRevisionProvider` concern (unlike home aggregation).
- **No money math touched:** counter is an integer write-rate, not currency; `Decimal`/`MoneySerializer` untouched.
- **Adversarial axis (identity):** actor extraction across `createdBy` vs `actorId`, server-written docs, malformed docs, and self-trigger-loop avoidance are the failure axes exercised above.
