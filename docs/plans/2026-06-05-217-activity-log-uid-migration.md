# #217 — Migrate activity-log `actorId`/`targetParticipantId`/`metadata` oldUid→newUid on anon recovery

Follow-up to #216 (PR #218, merged `a545509`). #216 migrated the **financial** ledger surface
(expense payer/split/customSplit + event & group settlements) inside `cleanupAnonUidArtifacts.processGroup`'s
per-group transaction. It deliberately scoped out **activity logs** to keep that PR on the balance-critical path.
#217 closes that gap with **migrate-not-scrub** semantics.

## 1. Problem

After email-link account recovery, `cleanupAnonUidArtifacts` repoints the recovered user's refs
`oldUid → newUid` and then deletes the `oldUid` Auth user. Two activity surfaces are NOT migrated, so they
keep pointing at a now-deleted UID:

- **Event activity:** `groups/{gid}/events/{eid}/activity_logs` — `actorId`, `targetParticipantId`, and
  UID-bearing values inside `metadata`.
- **Group activity:** `groups/{gid}/activity` — `actorId`, and UID-bearing values inside `metadata`.

This is the **same defect class as #216** (incomplete `oldUid` migration), but **non-balance-affecting**:
activity logs do not feed the balance engine and the feed renders the denormalized `actorName`/`logText`/
`description`, so a stale `actorId` is an **inert orphan** — not a visible ghost and not a money bug.

## 2. Exact field enumeration (from the models + live writers, not memory)

### 2a. Event `activity_logs` — `ActivityLog` (`lib/features/activity/models/activity_log_model.dart`)

Persisted keys (`toFirestore()` :85 + the two live writers): `id, eventId, category, eventType, logText,
actorId, actorName, metadata, createdAt` (model also reads `targetParticipantId` :71 and `actorAvatar` :78;
`targetParticipantId` IS written by some flows — see below).

UID-bearing fields:
| Field | Type | Migrate? |
|---|---|---|
| `actorId` | string UID | **YES** → newUid |
| `targetParticipantId` | string UID (nullable) | **YES (defensive)** → newUid |

> **`targetParticipantId` is defensive/forged-data-only — NO live writer emits it.** Only the uncalled
> `ActivityLog.toFirestore()` (:90) lists it and nothing calls it (both producers build their map inline);
> `fromFirestore` (:71) reads it and `deleteAccount` defensively scrubs it (:367). We migrate it for
> byte-parity with the scrub, but no live flow produces it (Gate R1 P2 correction — the earlier "written by
> some flows" claim was wrong).
| `metadata.payerParticipantId` | string UID (expense CREATE writer, `expense_service.dart:233`) | **YES** (value) |
| `metadata.customSplitParticipants` | array of string UIDs (`expense_service.dart`) | **YES** (entries) |
| `actorName`, `logText` | denormalized display strings | **NO** — same person, name unchanged on recovery |
| `metadata.{expenseId,amount,amountFils,currency,description,scope,subGroupId,categoryId}` | non-UID | **NO** |

Live writers: `activity_service.dart:60` (`addActivityLog`, currently no live callers) and the inline
`_addExpenseCreatedActivity` at `expense_service.dart:221` (the real producer; metadata block at :228+).

### 2b. Group `activity` — `GroupActivityLog` (`lib/features/groups/models/group_activity_log_model.dart`)

Persisted keys (`logGroupEvent`, `group_activity_service.dart:124`): `id, type, actorId, actorName,
description, metadata, timestamp`.

UID-bearing fields (all **7** `logGroupEvent` callsites enumerated — two distinct `member_left` writers:
`group_members_section.dart:180` with `{memberAction, memberName}` and `group_danger_section.dart:233` with
no metadata at all; both UID-free):
| Field | Type | Migrate? |
|---|---|---|
| `actorId` | string UID | **YES** → newUid |
| `metadata.recipientId` | string UID (`group_settlement` only, `group_settle_up_screen.dart:421`) | **YES** (value) |
| `actorName`, `description` | denormalized display strings | **NO** — same person |
| `metadata.{amount,groupId,eventId,eventName,memberName,memberAction}` | non-UID | **NO** |

The other 5 callers (`member_joined` `{groupId}`, `member_left` `{memberAction,memberName}` ×2,
`event_created`/`event_deleted` `{eventId,eventName}`) carry **no** UID in metadata.

**No live writer ever uses a UID as a metadata KEY.** Every metadata key is a descriptive label. So the
recursive walk's key-collision branch is forged-data-only (and inert — see §6).

## 3. Read-path tracing (principle 3) — every write has a named reader

- `activity_logs.actorId` ← read by `ActivityLog.fromFirestore` (`activity_log_model.dart:70`) → rendered in
  the event activity feed (`activity_service.fetchActivityPageRaw`) for **display only**.
- `group activity.actorId` ← read by `GroupActivityLog.fromFirestore` (`group_activity_log_model.dart:63`) →
  group activity feed + cross-group feed (`group_activity_service.watchRecentActivity`/`fetchActivityPage`),
  **display only**.
- `metadata.*` ← read by the feed screens for display (e.g. `metadata.amount`); UID values
  (`payerParticipantId`/`recipientId`/`customSplitParticipants`) are **not currently rendered** but migrated
  for completeness/consistency with the scrub.

**No OUTBOUND consumer.** The balance engine never reads activity: `group_balance_provider.dart` imports the
group-activity model **only** for a co-located *recent-activity display* provider (:51-54); the balance math
(`computeGroupBalances`, `groupBalancesProvider`, the event balance providers) reads expenses/settlements
exclusively. The `writeRateMonitor` triggers (#198) are `onDocumentCreated` — they do **not** fire on our
`tx.update`, and are detection-only regardless. → migrating activity cannot move any number. (Principle 1:
all callsites INBOUND/display; principle 7 money axis: clean.)

## 4. Design — mirror #216's settlement migration, migrate-not-scrub

Add two pure helpers to `cleanupAnonUidArtifacts.ts`, parallel to the existing `settlementMigrationUpdate`
(:133) and `mergeUidMapKey` (:103):

```ts
// #217: recursively repoint oldUid -> newUid inside an activity metadata blob —
// string VALUES that equal oldUid (metadata.payerParticipantId / recipientId),
// array entries (metadata.customSplitParticipants), and (defensively) map KEYS
// that equal oldUid. Mirrors deleteAccount's rewriteMetadata MINUS the
// name-scrubbing (recovery keeps the person's name). Pure substitution — does
// NOT sum (contrast mergeUidMapKey for splitDistribution, which sums because
// those values are money; metadata values are display-only, never aggregated).
function migrateMetadataValue(value: unknown, oldUid: string, newUid: string): unknown {
  if (typeof value === 'string') return value === oldUid ? newUid : value;
  if (Array.isArray(value)) return value.map((e) => migrateMetadataValue(e, oldUid, newUid));
  if (value && typeof value === 'object') {
    const next: Record<string, unknown> = {};
    for (const [key, entryValue] of Object.entries(value)) {
      next[key === oldUid ? newUid : key] = migrateMetadataValue(entryValue, oldUid, newUid);
    }
    return next;
  }
  return value;
}

// #217: migrate the UID-bearing attribution fields of one activity-log doc.
// eventScoped=true also migrates targetParticipantId (group activity has none).
// Returns null when nothing matched (so we never write an unchanged doc).
function activityMigrationUpdate(
  data: DocumentData,
  oldUid: string,
  newUid: string,
  eventScoped: boolean,
): Record<string, unknown> | null {
  const update: Record<string, unknown> = {};
  if (data.actorId === oldUid) update.actorId = newUid;
  if (eventScoped && data.targetParticipantId === oldUid) update.targetParticipantId = newUid;
  if (data.metadata !== undefined) {
    const migrated = migrateMetadataValue(data.metadata, oldUid, newUid);
    if (JSON.stringify(migrated) !== JSON.stringify(data.metadata)) update.metadata = migrated;
  }
  return Object.keys(update).length > 0 ? update : null;
}
```

`actorName`/`logText`/`description`/`timestamp`/`createdAt` are intentionally **never** in the update map —
migrate-not-scrub (the person and their name persist; only the UID identity moves).

### 4a. Wiring into `processGroup` (read-phase reads + write-phase loops)

Firestore's all-reads-before-writes rule (the existing #216 comment at :238-240) means the activity reads
MUST be added to the **read phase**, before the first `tx.update(groupRef)` at :255:

```ts
// added alongside eventSettlementSnaps (:241) / groupSettlementsSnap (:244), still in the read phase:
const eventActivitySnaps = await Promise.all(
  activeEventSnaps.map((e) => tx.get(e.ref.collection('activity_logs'))),
);
const groupActivitySnap = await tx.get(groupRef.collection('activity'));
```

Write-phase loops, added after the settlement loops (after :379), mirroring them exactly:

```ts
activeEventSnaps.forEach((eventSnap, index) => {
  for (const activitySnap of eventActivitySnaps[index].docs) {
    const update = activityMigrationUpdate(activitySnap.data() ?? {}, oldUid, newUid, true);
    if (update) { tx.update(activitySnap.ref, update); actions.push(`activity_logs.${eventSnap.id}.${activitySnap.id}`); }
  }
});
for (const activitySnap of groupActivitySnap.docs) {
  const update = activityMigrationUpdate(activitySnap.data() ?? {}, oldUid, newUid, false);
  if (update) { tx.update(activitySnap.ref, update); actions.push(`activity.${activitySnap.id}`); }
}
```

The `tx.update` writes THROUGH the activity `allow update: if false` rule via the Admin SDK (rules-bypassing) —
identical to #216's settlement note (:353-355). Clients still cannot mutate activity; only this server
identity-migration can. (Rules confirmed: event `activity_logs` has `allow create` only, no `allow update`
— `firestore.rules:689-718`; group `activity` likewise from `:795`.)

### 4b. Active-events-only (consistency within `cleanupAnonUidArtifacts`)

Event `activity_logs` is migrated only for `activeEventSnaps` — the SAME active-only policy #216 applies to
expenses (:309) and event settlements (:356), with the same rationale: a soft-deleted event's activity is an
inert residual (the feed never surfaces it). This deliberately **diverges** from `deleteAccount`'s scrub,
which processes ALL events (`deleteAccount.ts:456`) because PII deletion must reach everywhere. Migration is
not deletion: leaving an inert oldUid ref in a soft-deleted event's activity is acceptable and matches #216.

## 5. Transaction-limit interaction — the load-bearing risk (decision + open question for review)

**Verified fact** (Firebase docs, fetched 2026-06-05): a single Firestore transaction has a hard limit of
**500 writes**, and each `FieldValue.serverTimestamp()` counts as an extra write. Reads have no documented
count limit (bounded by 270 s / 10 MiB).

`cleanupAnonUidArtifacts.processGroup` does ALL its work in **one `db.runTransaction` per group** (:212).
#216 already placed every expense + event-settlement + group-settlement write into that transaction. #217
adds activity-log writes. So the 500-write cliff **pre-exists** (#216); #217 increases the constant factor —
activity is the highest-volume, *unbounded* collection (one entry per expense add/edit/delete + group events).

Mitigating facts:
- Writes are **guarded**: `tx.update` only fires for docs that actually reference `oldUid`
  (`activityMigrationUpdate` returns null otherwise). So the write count is bounded by **oldUid's own
  footprint** in the group, not the whole collection. Reads scan the collection but reads have no count cap.
- For the median recovering user (a few groups, tens of docs) this is far below 500.
- The failure mode if a dense, long-lived account *does* exceed 500 writes in one group: that group's
  transaction throws → pushed to `cascadeFailed` → `oldUid` Auth user preserved → client retries → **same
  transaction throws again → never converges** for that group (data stays safe; cleanup never completes).

**Decision for #217: stay in-transaction (issue-directed), accept the worsened-but-pre-existing constant,
and file a follow-up** to migrate the *entire* `cleanupAnonUidArtifacts` cascade to the chunked `BatchWriter`
pattern that `deleteAccount` **already uses** (`deleteAccount.ts:451`, "batched, may span auto-flushes") —
that auto-flushes at ≤500 and removes the cliff for the whole cascade (expenses + settlements + activity
together), which is the correct scope. Doing it in #217 would (a) re-architect #216's transaction (scope
creep; one-PR-one-thing) and (b) fix only activity's contribution, leaving the financial contribution's cliff.

**Open question for the reviewer:** is "worsening a non-convergent cliff for exactly the heavy-account
recovery population" severe enough to force the chunked `BatchWriter` rewrite *into* #217 rather than a
follow-up? If yes, the fallback is: migrate activity via a chunked `BatchWriter` pass (idempotent,
best-effort, failures → `cascadeFailed`) — the deleteAccount-proven pattern — accepting that activity then
migrates non-atomically vs the money transaction (acceptable: activity is inert + the migration is idempotent
so retry converges).

## 6. Collision semantics on recovery (newUid may pre-exist — the both-members case)

Unlike `deleteAccount`'s scrub (where the tombstone id is freshly minted and never collides), recovery's
`newUid` may already appear. Two activity collision shapes, both **inert** (activity is display-only, never
aggregated — contrast #216's `splitDistribution` which **sums** subunits because it is money):

1. **metadata array value dup** — `metadata.customSplitParticipants: [oldUid, newUid]` →
   `[newUid, newUid]`. A duplicate, NOT a sum. Inert: this array lives only in metadata (the balance engine
   reads the *expense doc's* top-level `customSplitParticipants`, which #216 dedups via `replaceUid` :326).
   The activity feed never renders it. We deliberately do **not** dedup here (mirrors the scrub's non-dedup
   `rewriteMetadata` recursive `.map()`); documenting it as known-inert.
2. **metadata object key collision** — forged-data-only (no writer uses a UID as a metadata key, §2).
   Last-write-wins drops one branch. Inert + unreachable via the live write paths.

Top-level `actorId`/`targetParticipantId` are scalars — no collision possible (single value → single value).

**Must NOT** apply `mergeUidMapKey`'s summing to metadata — that helper is for money subunits only. Verified:
`migrateMetadataValue` does pure substitution (principle 6: no false `aggregate = sum(slices)` decomposition;
metadata has no money to conserve).

## 7. Test plan (RED → GREEN; Jest, emulator) — `functions/test/callables/cleanupAnonUidArtifacts.test.ts`

Mirror the #216 settlement tests (:367-433). New seed helper for activity docs (event + group). Cases:

1. **Event activity_logs top-level migrate** — `actorId === oldUid → newUid`; `targetParticipantId ===
   oldUid → newUid`; `actorName`/`logText` UNCHANGED. A non-oldUid actor doc is untouched (no write).
2. **Event activity_logs metadata migrate** — `metadata.payerParticipantId` value migrated;
   `metadata.customSplitParticipants` entry migrated; non-UID metadata (`expenseId`, `amount`) untouched.
3. **Group activity migrate** — `actorId` migrated; `metadata.recipientId` (group_settlement) migrated;
   `actorName`/`description` untouched; a `member_joined` doc with `{groupId}` metadata and a non-oldUid
   actor is untouched.
4. **Active-only (scope axis)** — a soft-deleted event's `activity_logs` actorId === oldUid is NOT migrated
   (inert residual), mirroring the #216 soft-deleted-expense test (:437).
5. **Both-members collision (identity axis, adversarial / principle 7)** — newUid already a member;
   `metadata.customSplitParticipants: [oldUid, newUid]` → `[newUid, newUid]` (dup, not sum); doc does not
   throw; assert NO money field anywhere is altered (there is none on an activity doc) and the parallel
   expense's `splitDistribution` (if seeded) still SUMS per #216 — proving the two paths use different
   semantics on the same collision.
6. **cascadeFailed gate** — the existing per-group-failure test (:486) throws at `getStringArray` during the
   **read phase**, BEFORE any activity write loop, so it does NOT exercise an activity-write failure. Add a
   focused test that spies `Transaction.prototype.update` (or `WriteBatch.prototype.update`) to reject on the
   activity doc ref, asserting the group enters `cascadeFailed`, the Auth user is preserved, and the intent is
   NOT consumed (Gate R1 P3 correction — `:486` reuse would not cover the new code's failure surface).
7. **No-op cleanliness** — a group whose activity never referenced oldUid produces no `activity*` entries in
   the logged `actions` (proves guarded writes don't churn).

Plus: `tsc` clean, `eslint src` clean, full functions emulator suite green (currently 253/253 → +N).

## 8. Out of scope / not touched

- `firestore.rules`, `firestore.indexes.json` — unchanged (no new collection, no new field). #217 is pure
  Functions logic + tests (+ docs). Independent of the #170/#76 stack; branches off `main`.
- The financial migration (#216) — untouched.
- The transaction→BatchWriter rewrite — **follow-up issue** (see §5).
- `docs/CLOUD-FUNCTIONS.md` — add a one-line note that recovery cleanup also migrates activity attribution.

## 9. Verification principles checklist (run while writing)

1. **Callsite classification:** all activity readers INBOUND/display (§3). ✓
2. **Concrete claims vs code:** models, writers (incl. inline expense writer), scrub mirror, rules lines,
   transaction structure, 500-limit, test helpers — all read + cited. ✓
3. **Read-path per write-path:** every migrated field has a named display reader; no OUTBOUND/money reader. ✓
4. **Fields from the type:** enumerated exhaustively from both models + all writers (§2). ✓
5. **Data contracts:** exact helper signatures, exact metadata keys, exact `actions` strings (§4). ✓
6. **Arithmetic decomposition:** metadata is NOT summed (no money); summing is splitDistribution-only (§6). ✓
7. **Adversarial orthogonal axis:** money axis (balance engine never reads activity), scope axis (active-only
   soft-delete test), identity-collision axis (both-members dup-not-sum test) (§3,§4b,§6,§7). ✓
