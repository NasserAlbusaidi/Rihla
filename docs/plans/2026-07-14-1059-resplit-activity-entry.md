# #1059 Stage 2 — Roster-change re-split disclosure activity entry

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** When a roster change (invite-code join or shadow-member add) fans a new member into
events whose balances actually re-split, write ONE server-authored `member_resplit` row to
`groups/{gid}/activity` so the shift is no longer silent (#1059, owner decision 2026-07-10:
Option 1, Stage 2).

**Architecture:** Detection + row write live server-side in the two (and only two) fan-in
callables — `joinGroupByInviteCode` and `addShadowMember` — as a shared post-commit helper.
The row is written AFTER the membership transaction commits, so its only failure mode is a
LOST row, never a fabricated one (the same property the client's best-effort `member_joined`
row accepts per #1140 — note that row is CLIENT-written; the server-row idiom this spec
copies is `recordSettlement`'s). No `firestore.rules` change: the type allow-list at
`security/firestore.rules:1212-1216` is closed, so `member_resplit` is client-unforgeable by
default (pinned by the existing `'totally_made_up'` forge test). Old clients render the row
via the existing total-function fallbacks (description text, generic glyph, group-root nav) —
no client-compat gating needed.

**Tech Stack:** Cloud Functions (TS, Node 22) + Firestore Admin SDK; Flutter client display
(`activity_display.dart`, `activity_nav.dart`, filter chips); ARB l10n EN+AR; jest emulator
tests + flutter_test.

**Spec status: GATE-CLEAN (r2, 2026-07-14).** Round 2 verdicts: rubric 0 P1 / 1 P2 / 2 P3,
adversary 0 P1 / 0 P2 / 2 P3 — both P1-clean in the same round; the non-P1s are folded as
implementation notes below (currency-free `SplitRouting`, `_navMetadataString` in the nav
arm, "1 event" grammar in the description fallback, double-row non-goal named in the PR).
Round 1 verdicts: rubric 1 P1 / 1 P2 / 2 P3, adversary 1 P1 / 0 P2 / 1 P3 — ALL folded into
r2. Changes from r1:
- **[r1-adversary P1]** Copy is now actor-prepended PREDICATES with a
  `metadata.memberAction: 'added' | 'joined'` discriminator (`ActivityRow` renders
  `actorName + ' ' + description` as one paragraph — `activity_row.dart:76-100`; every
  existing ARB string is a predicate). Four l10n keys, two description variants.
- **[r1-rubric P1]** Former "fact 6" (rejoin is a no-op) was FALSE: `collectEventFanIn` runs
  unconditionally on every join, and an event created while a member was departed seeds
  `participantIds` from the active roster WITHOUT them (`create_event_screen.dart:115-124,
  295-310`; `leaveGroup.ts:27` removes the uid from `memberIds`) — so a rejoin re-splits
  those events and MUST disclose. Doc id now keys on (memberId + affected-event-set hash) so
  distinct occasions get distinct rows; the rejoin case is a POSITIVE test.
- **[r1-rubric P2]** Detection no longer hand-mirrors `foldEventNet`'s scope routing — one
  shared classification helper in `groupNetBalance.ts` is used by BOTH (Task 1).
- **[r1-rubric P3 ×2]** member_joined precedent citation corrected (above);
  `FanInEventCapture` construction spelled out (Tasks 2/3).
- **[r1-adversary P3]** metadata carries `eventId`+`eventName` iff count==1 AND the event
  name is a valid non-empty string; the Single text variant fires iff `eventName` is present
  and the nav deep-link iff `eventId` is present — text and nav can no longer disagree.

---

## Verified code facts the design rests on

Every claim below was re-verified against `main` (0323bc65) this session; file:line cited.

1. **Fan-in writers are exactly two.** `collectEventFanIn`/`applyEventFanIn`
   (`functions/src/callables/shared/eventFanIn.ts:70-114`) are called only from
   `joinGroupByInviteCode.ts` (:328, :364) and `addShadowMember.ts` (:152). Both run one
   `db.runTransaction` and already load the full `eventsSnap`. `claimShadow.ts` and
   `deleteAccount.ts` mutate `participantIds` only as 1:1 `replaceUid` swaps paired with
   money-map re-keys (balance-preserving by construction — claimShadow's simNet==actualNet
   backstop) — they must NOT and, being separate code paths, structurally CANNOT trigger this
   disclosure. `removeMember`/`leaveGroup` never touch `participantIds` (#1131).
2. **No client path grows an existing event's `participantIds`.**
   `EventService.updateEvent` (`lib/features/events/services/event_service.dart:341-381`)
   writes only name/dates/description; `participantIds` is set once at `stageEvent` create
   (:134). So the server callables are the complete Stage-2 write surface.
3. **Re-split predicate (the "shifts balances" condition), from the oracle.**
   `foldEventNet` (`functions/src/callables/groupNetBalance.ts:410-436`) routes an expense to
   the read-time equal split iff NOT
   (`mode != null && mode !== 'equally' && distribution != null && distribution.size > 0`),
   then picks recipients by scope: `personal` → `[payerId]` (immune to roster growth);
   `custom` with non-empty `customSplitParticipants` → that fixed list (immune); everything
   else (global / legacy subGroup / custom-with-empty-list / absent scope) → the FULL universe
   (**re-splits when `participantIds` grows**). Client mirror:
   `expense_provider.dart:418-453`. Settlements never re-split (fixed directed pair,
   `expense_provider.dart:340-354`; `settlement_model.dart` has no split field).
4. **Every app-created equal-split expense has NO stored distribution — current writes, not
   just legacy.** `stageExpense` omits both keys for `SplitMode.equally`
   (`expense_service.dart:268-300`); editing back to equal `FieldValue.delete()`s both
   (:356-358); the model's `toFirestore` gates both keys on `splitMode != null`
   (`expense_model.dart:289-295`, "omitted for an `equally` split").
5. **Balance scope uses strict `isDeleted === false`** (`groupNetBalance.ts:297-302`
   `isLiveDoc`) — the detection query must filter the same way (live expense writes persist
   `isDeleted: false` explicitly, `expense_service.dart:293`).
6. **Rejoin CAN re-split — and must disclose.** `collectEventFanIn` runs unconditionally on
   every join, idempotent rejoins included (`joinGroupByInviteCode.ts:328-329`, comment
   :348-352); `addParticipantId = !participantIds.includes(userId)`
   (`eventFanIn.ts:83`). Leave/remove never prune EXISTING events' `participantIds`
   (#1131), but `leaveGroup` removes the uid from `memberIds` (`leaveGroup.ts:27`) and a
   NEW event created during the departure window seeds `participantIds` from the eligible
   active roster only (`create_event_screen.dart:115-124, 295-310` — #1159 WYSIWYG prune) —
   the departed member is not in it. On rejoin, fan-in adds them to exactly those events →
   real re-split → a row MUST be written. Hence the doc id must distinguish disclosure
   occasions (see contract) — a bare `resplit_<uid>` would permanently swallow every
   disclosure after the first (r1-rubric P1).
7. **Old-client degrade is total and partly test-pinned.**
   `localizedGroupActivityText` default arm → `bidiIsolate(log.description)`
   (`activity_display.dart:140`); glyph default → `ActivityGlyph.generic` (:24, pinned by
   `test/unit/activity_display_test.dart:432-438` with literal `'some_future_type'`);
   `activityRowTarget` default → `/group/$groupId` (`activity_nav.dart:56-60`, widget-pinned
   by `cross_group_activity_screen_test.dart:1193-1218`); `GroupActivityLog.fromFirestore`
   does not enum-validate `type` (`group_activity_log_model.dart:63`); no query filters by
   type (`group_activity_service.dart:44-116`). Filter chips are exact-match — an unknown type
   shows under 'All' only (`group_activity_screen.dart:366-375`,
   `cross_group_activity_screen.dart:676-685`) — accepted degrade for old clients.
8. **Server-row idiom to copy** (`recordSettlement.ts`): ISO-string timestamp only
   (`new Date().toISOString()`, :465-469 — a Firestore `Timestamp` type-buckets apart in
   orderBy); actorName from the caller's member doc matched by the `userId` FIELD (keying is
   mixed), `normalizeRequiredDisplayName`-wrapped, fallback `'Someone'` (:514-528).
9. **Row chrome prepends the actor.** Every feed surface renders one paragraph as
   `bidiIsolate(actorName) + ' ' + description` (`lib/shared/widgets/activity_row.dart:76-100`;
   call sites `group_activity_screen.dart:344-347`, `cross_group_activity_screen.dart:654-655`,
   home RECENTLY). Every ARB activity string is therefore a PREDICATE
   ("joined the group", "paid {toName}", "created {eventName}" — `app_en.arb:1503,1524,1537`).
   The new copy must be predicates too, and the `description` fallback likewise.
10. **`memberAction` metadata discriminator has precedent and is rules-typed.** `member_left`
    rows branch display on `metadata.memberAction == 'removed'`
    (`activity_display.dart:118-123`); `memberAction` is one of the 11 typed keys in
    `validActivityMetadata` (`firestore.rules:1181`).
11. **writeRateMonitor coupling.** `groupActivityWriteRateMonitor` skip-lists server-authored
    types (`writeRateMonitor.ts:145-151`, `SKIPPED_ACTIVITY_TYPES` + `expense_` prefix) —
    a server-authored row that is NOT skipped counts against the actor's rate budget.
    `member_resplit` must join the skip set in the same PR.
12. **Balance-aggregate refresh needs nothing new.** `eventBalanceAggregator` already fires on
    any `participantIds` diff (`balanceAggregator.ts:277-281`, keys
    `['participantIds','isDeleted']`), and both callables are online-only, so the home
    aggregate path self-heals. No `ledgerRevision` bump involved (no client write path here).

## Deliberate non-goals (name them in the PR)

- **No per-event rows.** One summary row per roster change; per-event granularity would spam
  a 10-event group's feed on every join.
- **No claim / deleteAccount rows.** Balance-preserving 1:1 swaps by construction (fact 1);
  activity-row-silent by design (D7 precedent).
- **No detection of the live-member split-key "resurrection" mechanism.** Code-real
  (`expense_provider.dart:152-155`: a live member's own stored split key enters the universe
  only via `participantIds`) but unreachable via rules-compliant flows for a genuinely-new
  participant (fan-in is arrayUnion-only; a rules-compliant write can only reference keys that
  were participants at write time — `expense_provider.dart:104-106`). Documented residual.
- **No rules change, no new client-writable type.** Server-authored only.
- **No departure-side disclosure** (split-key drops when a member's docs are removed) — out of
  #1059's scope (ADD-side); departures are fenced separately (#1144).
- **No new l10n for old clients** — the English `description` fallback IS the old-client copy.
- **The fresh-join DOUBLE row is intentional** (Gate r2 adversary P3): the client's
  best-effort `member_joined` ("joined the group") AND the server's `member_resplit`
  ("joined N events — equal splits recalculated") both appear for one join. They carry
  different information — do NOT "dedupe" them.

## New data contract (exact)

Doc at `groups/{gid}/activity/{activityId}`:

| Field | Value |
|---|---|
| `id` | `` `resplit_${memberId}_${occHash}` `` where `occHash` = first 12 hex chars of `sha256(sortedAffectedEventIds.join(','))` (Node `crypto.createHash`). Distinct disclosure occasions (different affected-event sets — e.g. a rejoin hitting events created during the departure window) get distinct ids; a raced duplicate of the SAME occasion dedups via `.create()` already-exists (r1-rubric P1 fix). |
| `type` | `'member_resplit'` |
| `actorId` | caller uid (join: the joiner; addShadowMember: the creator) |
| `actorName` | join: the free-typed join `displayName`; addShadowMember: creator's member-doc `displayName` matched by `userId` FIELD, `normalizeRequiredDisplayName`-wrapped, fallback `'Someone'` (fact 8 idiom) |
| `description` | PREDICATE (row chrome prepends actorName — fact 9). EN fallback for old clients: `memberAction == 'added'` → `` `added ${memberName} to ${eventName} — equal splits recalculated` `` / `` `added ${memberName} to ${n} events — equal splits recalculated` ``; `memberAction == 'joined'` → `` `joined ${eventName} — equal splits recalculated` `` / `` `joined ${n} events — equal splits recalculated` `` (≤32-char names → far under the 280 cap) |
| `metadata` | `{ memberAction: 'added' \| 'joined', memberName: string, affectedEventCount: int }` + iff exactly ONE affected event AND its name is a valid non-empty string: `{ eventId: string, eventName: string }` (both or neither — keeps text/nav consistent, r1-adversary P3). `memberAction`/`memberName`/`eventName` are typed keys in `validActivityMetadata` (rules :1173-1187); `affectedEventCount`/`eventId` ride the opaque-key allowance. Client reads ALL type-guarded (`_metadataString` + a guarded int read). |
| `timestamp` | `new Date().toISOString()` — ISO string ONLY (fact 8) |

**Affected event** := fan-in update with `addParticipantId === true` whose event has ≥1
expense with `isDeleted === false` AND the shared classification (Task 1) says it splits over
the universe. Row written iff affected-event count ≥ 1. A shadow-add into an event-less or
expense-less group writes NO row (Stage 1's pre-submit copy already covers the prospective
case).

**Rendered examples (actorName prepended by the row chrome):**
- addShadowMember, creator Alice adds shadow Bob, 1 affected event "Trip":
  **Alice** added Bob to Trip — equal splits recalculated
- join, Bob joins, 3 affected events: **Bob** joined 3 events — equal splits recalculated

## Task list

### Task 1 — Server: shared split classification + detection/row helper (RED first)

**Files:**
- Modify: `functions/src/callables/groupNetBalance.ts` — extract the equal-branch routing
  into ONE shared, exported classification used by BOTH `foldEventNet` and the new detection
  (r1-rubric P2 — decoders alone are not enough; the scope routing must not drift either):

```ts
// The single source of truth for "does this expense's owed side re-split when
// the event's participant universe grows?" — foldEventNet routes through the
// same classification, so detection can never drift from the oracle.
export type SplitRouting =
  | { kind: 'stored' }                              // mode allocator, fixed keys
  | { kind: 'fixed'; recipients: string[] }         // personal / custom non-empty
  | { kind: 'universe' };                           // equal over the full universe

export function classifyExpenseSplit(e: DocumentData): SplitRouting { ... }
export function expenseSplitsOverUniverse(e: DocumentData): boolean {
  return classifyExpenseSplit(e).kind === 'universe';
}
```

  `foldEventNet`'s expense loop becomes a switch over `classifyExpenseSplit` with IDENTICAL
  outputs (behavior-preserving refactor of money code — the existing parity suites
  `delete_group_balance_parity_test.dart` + the full functions emulator suite are the proof;
  run them BEFORE and AFTER the refactor). `personal` with a non-string payer keeps its
  current `recipients = []` behavior (`groupNetBalance.ts:427-428`) via
  `{kind:'fixed', recipients: []}`.

  **`SplitRouting` MUST stay currency-free — kind/keys only, NEVER decoded distribution
  values (Gate r2 rubric P2).** Detection's projection omits `currency` (safe: routing only
  needs `distribution.size`, which is currency-invariant — `decodeSplitValue` changes values,
  not key count, `groupNetBalance.ts:110-123`). If classification carried decoded values,
  detection's dummy-currency decode would leak dummy-OMR-scaled amounts into non-OMR
  allocations — a money P1. `foldEventNet`'s `stored` case therefore RE-derives
  mode/distribution itself with the real per-doc `currency` (:411) for the allocator; the
  `{kind:'stored'}` variant deliberately carries no payload.
- Create: `functions/src/callables/shared/resplitDisclosure.ts`
- Test: `functions/test/resplitDisclosure.emulator.test.ts` (new)

**Step 1 — failing tests** (`cd functions && npm run test:emulator -- resplitDisclosure -t "..."`
per #1157; NEVER bare jest). Table-driven (money-adjacent → clean/warning/error rows):

- `expenseSplitsOverUniverse` truth table: live global equal (no split keys) → true;
  `custom` + EMPTY `customSplitParticipants` → true; legacy `subGroup` → true; absent scope →
  true; `personal` → false; `custom` + non-empty list → false; `exact`/`shares`/`percent`
  with non-empty distribution → false; stored mode with EMPTY distribution → true (mirrors
  the oracle's fall-through).
- `detectResplitEvents` returns the event for a live universe-splitting expense, INCLUDING a
  CLOSED (non-deleted) event; skips: soft-deleted-expense-only events, zero-expense events,
  updates with `addParticipantId === false`.
- `writeResplitActivity` writes the exact doc shape above (single-event metadata variant,
  multi-event variant, malformed-event-name variant → count copy + NO eventId/eventName);
  id = `resplit_<memberId>_<occHash>`; same-occasion duplicate create does not throw;
  DIFFERENT affected-event sets for the same member produce DIFFERENT ids (two rows).

**Step 2 — run, confirm RED** for the right reason (helper module absent).

**Step 3 — implement.** Sketch:

```ts
// functions/src/callables/shared/resplitDisclosure.ts
import { createHash } from 'crypto';
import { DocumentData, DocumentReference, Firestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';
import { expenseSplitsOverUniverse } from '../groupNetBalance';

export interface FanInEventCapture { ref: DocumentReference; eventId: string; eventName: string }
export interface ResplitDetection {
  count: number;
  affectedEventIds: string[];
  single: { eventId: string; eventName: string } | null; // null unless count==1 AND name valid
}

export async function detectResplitEvents(events: FanInEventCapture[]): Promise<ResplitDetection> {
  const flags = await Promise.all(events.map(async (ev) => {
    const snap = await ev.ref.collection('expenses')
      .where('isDeleted', '==', false)
      .select('splitMode', 'splitDistribution', 'scope', 'customSplitParticipants', 'payerParticipantId')
      .get();
    return snap.docs.some((d) => expenseSplitsOverUniverse(d.data()));
  }));
  const affected = events.filter((_, i) => flags[i]);
  const one = affected.length === 1 ? affected[0] : null;
  return {
    count: affected.length,
    affectedEventIds: affected.map((e) => e.eventId).sort(),
    single: one != null && one.eventName.length > 0
      ? { eventId: one.eventId, eventName: one.eventName } : null,
  };
}

export async function writeResplitActivity(db: Firestore, groupId: string, args: {
  memberId: string; memberName: string; actorId: string; actorName: string;
  memberAction: 'added' | 'joined'; detection: ResplitDetection;
}): Promise<void> {
  const { count, single, affectedEventIds } = args.detection;
  if (count === 0) return;
  const occHash = createHash('sha256').update(affectedEventIds.join(',')).digest('hex').slice(0, 12);
  const activityId = `resplit_${args.memberId}_${occHash}`;
  // PREDICATES — the row chrome prepends actorName (activity_row.dart:76-100).
  // "1 event" grammar (Gate r2 rubric P3): the count variant can fire with
  // count==1 when the sole event's name is malformed (legacy/Admin docs only).
  const eventsPhrase = count === 1 ? '1 event' : `${count} events`;
  const description = args.memberAction === 'joined'
    ? (single != null
        ? `joined ${single.eventName} — equal splits recalculated`
        : `joined ${eventsPhrase} — equal splits recalculated`)
    : (single != null
        ? `added ${args.memberName} to ${single.eventName} — equal splits recalculated`
        : `added ${args.memberName} to ${eventsPhrase} — equal splits recalculated`);
  try {
    await db.collection('groups').doc(groupId).collection('activity').doc(activityId).create({
      id: activityId,
      type: 'member_resplit',
      actorId: args.actorId,
      actorName: args.actorName,
      description,
      metadata: {
        memberAction: args.memberAction,
        memberName: args.memberName,
        affectedEventCount: count,
        ...(single != null ? { eventId: single.eventId, eventName: single.eventName } : {}),
      },
      timestamp: new Date().toISOString(), // ISO STRING ONLY (#1140/Gate R2)
    });
  } catch (error) {
    // Post-commit cosmetic row: a failure (incl. already-exists on a raced
    // duplicate of the SAME occasion) must never surface as a join/add failure —
    // the lost-row degrade IS the pre-#1059 status quo for that occurrence.
    logger.warn('resplit activity row not written', { groupId, memberId: args.memberId, error: String(error) });
  }
}
```

Detection reads are UNBOUNDED projection queries per affected event (the oracle itself reads
every expense unbounded; persona is small groups; `MAX_FAN_IN_EVENTS = 400` bounds the event
count). Detection runs POST-commit, OUTSIDE any lock — the row is not an oracle input and no
quiesce flag applies (deliberate; state in code comment). The oracle/`recomputeNet` must
NEVER read `member_resplit` rows (same contract as `splitExplanation`).

**Step 4 — GREEN + parity suites** (`delete_group_balance_parity_test.dart`, full functions
emulator suite) — the refactor is proven behavior-preserving. **Step 5 — commit**
`feat(functions): #1059 shared split classification + resplit disclosure helper`.

### Task 2 — Server: wire into `addShadowMember`

**Files:** Modify `functions/src/callables/addShadowMember.ts`; test
`functions/test/resplitDisclosure.emulator.test.ts` (extend) or the existing addShadowMember
suite.

- RED: creator adds shadow to a group whose one event holds a live global equal expense →
  `member_resplit` row exists with `memberAction: 'added'`, single-event metadata, and
  `actorName == creator's member displayName`; add-to-empty-group → NO row; CLOSED-event
  case fans in and discloses.
- Implement: inside the tx, capture to outer scope (join's `didJoin` last-run-wins pattern,
  `joinGroupByInviteCode.ts:210-214`):
  - `fanInCaptures: FanInEventCapture[]` — from the `collectEventFanIn` result, updates with
    `addParticipantId === true` only, correlated `ref.id → eventsSnap` doc for the name
    (`typeof data.name === 'string' ? data.name.trim() : ''`; malformed → `''`, which forces
    the count copy and suppresses eventId/eventName — r1-rubric P3 / r1-adversary P3);
  - `creatorName: string` — from the already-loaded `membersSnap`, `userId`-FIELD match on
    the caller uid, `normalizeRequiredDisplayName`-wrapped, fallback `'Someone'`.
  After the tx resolves: `detectResplitEvents(fanInCaptures)` →
  `writeResplitActivity(db, groupId, { memberId: newId, memberName: displayName,
  actorId: uid, actorName: creatorName, memberAction: 'added', detection })` — the whole
  post-commit block wrapped so no throw ever propagates (membership is already committed).
- GREEN → commit `feat(functions): #1059 addShadowMember writes resplit disclosure row`.

### Task 3 — Server: wire into `joinGroupByInviteCode`

Same capture shape as Task 2 (`eventFanoutUpdates` is already a tx-scoped variable at
:327-329; hoist the captures alongside `didJoin`). `memberAction: 'joined'`,
`memberId`/`actorId` = joiner uid, `actorName`/`memberName` = the normalized free-typed join
`displayName`. RED cases:
- fresh join over a re-splittable event → row with `memberAction: 'joined'`;
- **rejoin-after-departure-window disclosure (the r1-rubric P1 case):** U joins → row 1;
  U leaves (at zero); a new event E2 with a live equal expense is created (U not in
  `participantIds`); U rejoins → fan-in adds U to E2 ONLY → row 2 with a DIFFERENT id
  (different affected-set hash) and E2's single-event metadata. Both rows exist.
- idempotent same-state rejoin (already in every event's `participantIds`) → no new row;
- join into a stored-distribution-only group → no row.
Commit `feat(functions): #1059 join writes resplit disclosure row`.

### Task 4 — Server: writeRateMonitor skip + forge pin

**Files:** Modify `functions/src/triggers/writeRateMonitor.ts:145` (add `'member_resplit'` to
`SKIPPED_ACTIVITY_TYPES`; update the comment's type list); modify
`functions/test/firestore-rules-publish-readiness.test.ts:3018-3026` (add `'member_resplit'`
to the client-forge `assertFails` loop — explicit pin, not just `'totally_made_up'`); extend
the monitor's test if one covers the skip set (grep `functions/test` for
`SKIPPED_ACTIVITY_TYPES`/`writeRateMonitor`).

RED → GREEN → commit `feat(functions): #1059 member_resplit is server-authored — monitor skip + forge pin`.

### Task 5 — Client: display, filter, nav

**Files:**
- Modify `lib/features/activity/utils/activity_display.dart` — glyph arm
  `'member_resplit' => ActivityGlyph.memberJoined` (roster-change family; no new enum value);
  text arm in `localizedGroupActivityText` (all reads type-guarded; metadata is opaque to
  rules for server rows too — anything missing/forged degrades to the existing
  `bidiIsolate(log.description)` fallback, NEVER a crash):
  - `memberAction == 'joined'`: `eventName` present →
    `l10n.activityGroupResplitJoined(bidiIsolate(eventName))`; else guarded-int
    `affectedEventCount >= 1` → `l10n.activityGroupResplitJoinedMulti(count)`; else fallback.
  - `memberAction == 'added'` AND `memberName` non-empty: `eventName` present →
    `l10n.activityGroupResplitAdded(bidiIsolate(memberName), bidiIsolate(eventName))`; else
    count ≥ 1 → `l10n.activityGroupResplitAddedMulti(bidiIsolate(memberName), count)`; else
    fallback.
  - any other `memberAction` → fallback.
- Modify `lib/features/groups/screens/group_activity_screen.dart:372` and
  `lib/features/home/screens/cross_group_activity_screen.dart:682` — Members bucket gains
  `|| type == 'member_resplit'`.
- Modify `lib/features/activity/utils/activity_nav.dart` — arm: `eventId` present →
  `/group/$groupId/event/$eventId/ledger` (the re-split money lives in the ledger), else
  group root. (Metadata contract guarantees `eventId` ⟺ Single text variant.) Read via the
  file's own `_navMetadataString` (empty-guarded), NOT the display util's `_metadataString`
  (Gate r2 adversary P3).
- Tests: extend `test/unit/activity_display_test.dart` (all five text outcomes — joined
  single/multi, added single/multi, fallback — + glyph + forged non-string metadata
  degrade), `test/unit/activity_nav_test.dart`, the filter tests
  (`group_activity_filter_memo_test.dart` / cross-group filter test) pinning Members-bucket
  membership, and one widget render in `group_activity_screen_test.dart` asserting the full
  rendered paragraph (actor prepend + predicate — pins the r1-adversary P1 fix).

RED → GREEN → `flutter analyze` clean → commit `feat(activity): render member_resplit rows (#1059)`.

### Task 6 — l10n EN+AR

**Files:** `lib/l10n/app_en.arb`, `lib/l10n/app_ar.arb` (+ regenerate), extend
`test/unit/generated_l10n_surface_test.dart` (the key-enumeration surface — lib/-only greps
lie about l10n deadness).

PREDICATES (fact 9 — the row chrome supplies the actor):

```json
"activityGroupResplitAdded": "added {memberName} to {eventName} — equal splits recalculated",
"activityGroupResplitAddedMulti": "added {memberName} to {count, plural, =1{1 event} other{{count} events}} — equal splits recalculated",
"activityGroupResplitJoined": "joined {eventName} — equal splits recalculated",
"activityGroupResplitJoinedMulti": "joined {count, plural, =1{1 event} other{{count} events}} — equal splits recalculated"
```

AR per `docs/HOWTO-TRANSLATE.md` (full Arabic plural categories for `count`). Names are
FSI/PDI-isolated at the call site (#1216b pattern — already in Task 5's arms). Follow the
existing `activityGroup*` placeholder metadata blocks. Commit `feat(l10n): member_resplit copy EN+AR (#1059)`.

### Task 7 — Full suites + PR

- `cd functions && npm run test:emulator` (full), `flutter test`, `flutter analyze`,
  `tool/check_theme_purity.sh` (no new widgets styled, should be trivially clean).
- PR body: Stage 1 merged in #1082, this PR completes the decided scope → `Closes #1059`
  (commit message carries the same line; squash-merge inherits it).
- `/automerge` (Gate-category: functions/**) — fresh review + refuter.
- **Deploy rides the next release** (real users live): merged-but-undeployed delta tracked by
  `tool/pending_deploy.sh`; NO rules deploy in this PR; old clients degrade per fact 7, so no
  client-first gating. Note `⚠️ NOT deployed` applies until the next deploy ceremony.

## Acceptance boxes

- [ ] Shadow-add over a live global equal expense (open AND closed event cases) produces
      exactly one `member_resplit` row (`memberAction: 'added'`); empty/immune groups
      produce none.
- [ ] Join produces the row (`memberAction: 'joined'`); the rejoin-after-departure-window
      case produces a SECOND row with a distinct id; a same-occasion duplicate does not.
- [ ] Row is ISO-string-timestamped; id = `resplit_<memberId>_<occHash>`; raced duplicate
      create never fails the callable.
- [ ] Rendered paragraph is `actorName + predicate` on all three surfaces — no doubled or
      colliding names (widget-pinned).
- [ ] Client renders localized copy (joined/added × single/multi, EN+AR), Members filter
      bucket, ledger deep-link iff single-event metadata; forged/missing metadata degrades
      to description.
- [ ] `foldEventNet` refactor is behavior-preserving: parity + full emulator suites green
      before and after; detection and oracle share `classifyExpenseSplit`.
- [ ] Client cannot forge `member_resplit` (explicit rules-test pin).
- [ ] `member_resplit` skipped by `groupActivityWriteRateMonitor`.
- [ ] No `firestore.rules` diff in the PR.
