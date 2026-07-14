# #1059 Stage 2 — Roster-change re-split disclosure activity entry

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** When a roster change (invite-code join or shadow-member add) fans a new member into
events whose balances actually re-split, write ONE server-authored `member_resplit` row to
`groups/{gid}/activity` so the shift is no longer silent (#1059, owner decision 2026-07-10:
Option 1, Stage 2).

**Architecture:** Detection + row write live server-side in the two (and only two) fan-in
callables — `joinGroupByInviteCode` and `addShadowMember` — as a shared post-commit helper.
The row is written AFTER the membership transaction commits (member_joined precedent: the only
failure mode is a LOST row, never a fabricated one). No `firestore.rules` change: the type
allow-list at `security/firestore.rules:1212-1216` is closed, so `member_resplit` is
client-unforgeable by default (pinned by the existing `'totally_made_up'` forge test). Old
clients render the row via the existing total-function fallbacks (description text, generic
glyph, group-root nav) — no client-compat gating needed.

**Tech Stack:** Cloud Functions (TS, Node 22) + Firestore Admin SDK; Flutter client display
(`activity_display.dart`, `activity_nav.dart`, filter chips); ARB l10n EN+AR; jest emulator
tests + flutter_test.

**Spec status:** Gate-category (Cloud Functions + new activity type = schema with read+write
path). MUST pass `/run-the-gate` before implementation.

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
   `isLiveDoc`) — the detection query must filter the same way.
6. **Rejoin is a no-op for this feature.** Leave/remove never prune `participantIds` (#1131),
   so a rejoiner's fan-in has `addParticipantId == false` everywhere → zero affected events →
   no row. (Their equal-split share never stopped accruing while departed — universe is
   `participantIds`-driven: `expense_provider.dart:157`, `groupNetBalance.ts` universe seed.)
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
   mixed), fallback `'Someone'` (:514-528); deterministic doc id.
9. **writeRateMonitor coupling.** `groupActivityWriteRateMonitor` skip-lists server-authored
   types (`writeRateMonitor.ts:145-151`, `SKIPPED_ACTIVITY_TYPES` + `expense_` prefix) —
   a server-authored row that is NOT skipped counts against the actor's rate budget.
   `member_resplit` must join the skip set in the same PR.
10. **Balance-aggregate refresh needs nothing new.** `eventBalanceAggregator` already fires on
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

## New data contract (exact)

Doc at `groups/{gid}/activity/{activityId}`:

| Field | Value |
|---|---|
| `id` | `resplit_${newMemberId}` (joiner uid / shadow uuid — fresh per add; rejoin writes no row, fact 6) |
| `type` | `'member_resplit'` |
| `actorId` | caller uid (join: the joiner; addShadowMember: the creator) |
| `actorName` | join: the free-typed join `displayName`; addShadowMember: creator's member-doc `displayName` matched by `userId` FIELD, `normalizeRequiredDisplayName`-wrapped, fallback `'Someone'` (fact 8 idiom) |
| `description` | EN fallback for old clients: single affected event → `` `${memberName} was added to ${eventName} — equal splits recalculated` ``; else `` `${memberName} was added to ${n} events — equal splits recalculated` `` (memberName/eventName ≤32 each → far under the 280 cap) |
| `metadata` | `{ memberName: string, affectedEventCount: int }` + when exactly ONE affected event: `{ eventId: string, eventName: string }`. `memberName`/`eventName` are already-typed keys in `validActivityMetadata` (rules :1173-1187); `affectedEventCount`/`eventId` ride the opaque-key allowance. Client reads ALL of them type-guarded (existing `_metadataString` pattern + a guarded int read). |
| `timestamp` | `new Date().toISOString()` — ISO string ONLY (fact 8) |

**Affected event** := fan-in update with `addParticipantId === true` whose event has ≥1
expense with `isDeleted === false` AND NOT
(`mode != null && mode !== 'equally' && distribution non-empty`) AND scope ∉ immune set
(fact 3: `personal`, or `custom` with non-empty `customSplitParticipants`).
Row written iff affected-event count ≥ 1. A shadow-add into an event-less or expense-less
group writes NO row (Stage 1's pre-submit copy already covers the prospective case).

## Task list

### Task 1 — Server: shared detection + row-write helper (RED first)

**Files:**
- Create: `functions/src/callables/shared/resplitDisclosure.ts`
- Modify: `functions/src/callables/groupNetBalance.ts` (export `decodeSplitMode`,
  `decodeDistribution` — reuse the oracle's decoders, do NOT re-implement; byte-parity is the
  whole point)
- Test: `functions/test/resplitDisclosure.emulator.test.ts` (new)

**Step 1 — failing tests** (`cd functions && npm run test:emulator -- resplitDisclosure -t "..."`
per #1157; NEVER bare jest). Seed via existing fixtures; table-driven (money-adjacent →
clean/warning/error rows):

- `detectResplitEvents` returns the event for: live global equal expense (no splitMode keys);
  live `custom`-scope with EMPTY `customSplitParticipants`; legacy `subGroup` scope; a CLOSED
  (non-deleted) event with a live equal expense.
- Returns nothing for: soft-deleted expense only (`isDeleted: true`); `exact`/`shares`/
  `percent` with non-empty distribution; `personal` scope; `custom` with non-empty
  `customSplitParticipants`; event with zero expenses; fan-in update with
  `addParticipantId === false`.
- `writeResplitActivity` writes the exact doc shape above (single-event metadata variant and
  multi-event variant); id is `resplit_<memberId>`; a second call with the same id does not
  throw (create-collision swallowed + logged).

**Step 2 — run, confirm RED** for the right reason (helper module absent).

**Step 3 — implement.** Sketch:

```ts
// functions/src/callables/shared/resplitDisclosure.ts
import { DocumentData, DocumentReference, Firestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';
import { decodeDistribution, decodeSplitMode } from '../groupNetBalance';

export interface FanInEventCapture { ref: DocumentReference; eventId: string; eventName: string }
export interface ResplitDetection { count: number; single: { eventId: string; eventName: string } | null }

// Mirror of foldEventNet's equal-split routing (groupNetBalance.ts:410-436).
// An expense re-splits over the universe iff it takes the equal branch AND its
// scope resolves recipients from the universe.
export function expenseResplits(e: DocumentData): boolean {
  const mode = decodeSplitMode(e.splitMode);
  const distribution = decodeDistribution(e.splitDistribution, mode, 'OMR'); // values unused; size only
  const stored = mode != null && mode !== 'equally' && distribution != null && distribution.size > 0;
  if (stored) return false;
  const scope = typeof e.scope === 'string' ? e.scope : 'global';
  if (scope === 'personal') return false;
  if (scope === 'custom') {
    const custom = Array.isArray(e.customSplitParticipants)
      ? e.customSplitParticipants.filter((v): v is string => typeof v === 'string')
      : [];
    return custom.length === 0;
  }
  return true; // global / subGroup / unknown → universe recipients
}

export async function detectResplitEvents(events: FanInEventCapture[]): Promise<ResplitDetection> {
  const flags = await Promise.all(events.map(async (ev) => {
    const snap = await ev.ref.collection('expenses')
      .where('isDeleted', '==', false)
      .select('splitMode', 'splitDistribution', 'scope', 'customSplitParticipants')
      .get();
    return snap.docs.some((d) => expenseResplits(d.data()));
  }));
  const affected = events.filter((_, i) => flags[i]);
  return { count: affected.length, single: affected.length === 1
    ? { eventId: affected[0].eventId, eventName: affected[0].eventName } : null };
}

export async function writeResplitActivity(db: Firestore, groupId: string, args: {
  memberId: string; memberName: string; actorId: string; actorName: string;
  detection: ResplitDetection;
}): Promise<void> {
  if (args.detection.count === 0) return;
  const { count, single } = args.detection;
  const description = single != null
    ? `${args.memberName} was added to ${single.eventName} — equal splits recalculated`
    : `${args.memberName} was added to ${count} events — equal splits recalculated`;
  try {
    await db.collection('groups').doc(groupId).collection('activity')
      .doc(`resplit_${args.memberId}`).create({
        id: `resplit_${args.memberId}`,
        type: 'member_resplit',
        actorId: args.actorId,
        actorName: args.actorName,
        description,
        metadata: {
          memberName: args.memberName,
          affectedEventCount: count,
          ...(single != null ? { eventId: single.eventId, eventName: single.eventName } : {}),
        },
        timestamp: new Date().toISOString(), // ISO STRING ONLY (#1140/Gate R2)
      });
  } catch (error) {
    // Post-commit cosmetic row: a failure (incl. already-exists on a raced retry)
    // must never surface as a join/add failure — the lost-row degrade IS the
    // pre-#1059 status quo for this one occurrence.
    logger.warn('resplit activity row not written', { groupId, memberId: args.memberId, error: String(error) });
  }
}
```

Detection reads are UNBOUNDED projection queries per affected event (the oracle itself reads
every expense unbounded; persona is small groups; `MAX_FAN_IN_EVENTS = 400` bounds the event
count). Detection runs POST-commit, OUTSIDE any lock — the row is not an oracle input and no
quiesce flag applies (deliberate; state in code comment).

**Step 4 — GREEN.** **Step 5 — commit** `feat(functions): #1059 resplit disclosure helper`.

### Task 2 — Server: wire into `addShadowMember`

**Files:** Modify `functions/src/callables/addShadowMember.ts`; test
`functions/test/resplitDisclosure.emulator.test.ts` (extend) or the existing addShadowMember
suite.

- RED: emulator test — creator adds shadow to a group whose one event holds a live global
  equal expense → `member_resplit` row exists with the single-event metadata shape and
  `actorName == creator's member displayName`; add-to-empty-group → NO row; the closed-event
  case fans in and discloses.
- Implement: inside the tx, capture to outer scope (join's `didJoin` last-run-wins pattern,
  `joinGroupByInviteCode.ts:210-214`): the fan-in captures
  (`{ref, eventId, eventName}` for updates with `addParticipantId === true`; eventName from
  the already-loaded `eventsSnap`, malformed name → `''` → forces the multi/count copy) and
  the creator's member-doc displayName (from the already-loaded `membersSnap`, `userId`-FIELD
  match). After the tx resolves: `detectResplitEvents` → `writeResplitActivity` — wrapped so
  no throw ever propagates (membership is already committed).
- GREEN → commit `feat(functions): #1059 addShadowMember writes resplit disclosure row`.

### Task 3 — Server: wire into `joinGroupByInviteCode`

Same shape as Task 2. actorId = joiner uid; actorName = the free-typed join `displayName`
already normalized in the callable. RED cases: fresh join over a re-splittable event → row;
idempotent REJOIN (already in `participantIds`) → no row; join into stored-distribution-only
group → no row. Commit `feat(functions): #1059 join writes resplit disclosure row`.

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
  text arm in `localizedGroupActivityText`:
  - metadata `memberName` (type-guarded, non-empty) + `eventName` present → `l10n.activityGroupResplitSingle(bidiIsolate(memberName), bidiIsolate(eventName))`
  - `memberName` + guarded-int `affectedEventCount >= 1` → `l10n.activityGroupResplitMulti(bidiIsolate(memberName), count)`
  - anything missing/forged → existing `bidiIsolate(log.description)` fallback (NEVER crash — the metadata map is opaque to rules for server rows too).
- Modify `lib/features/groups/screens/group_activity_screen.dart:372` and
  `lib/features/home/screens/cross_group_activity_screen.dart:682` — Members bucket gains
  `|| type == 'member_resplit'`.
- Modify `lib/features/activity/utils/activity_nav.dart` — arm: `eventId` present →
  `/group/$groupId/event/$eventId/ledger` (the re-split money lives in the ledger), else
  group root.
- Tests: extend `test/unit/activity_display_test.dart` (all three text outcomes + glyph +
  forged non-string metadata degrade), `test/unit/activity_nav_test.dart`, the filter tests
  (`group_activity_filter_memo_test.dart` / cross-group filter test) pinning Members-bucket
  membership, and one widget render in `group_activity_screen_test.dart`.

RED → GREEN → `flutter analyze` clean → commit `feat(activity): render member_resplit rows (#1059)`.

### Task 6 — l10n EN+AR

**Files:** `lib/l10n/app_en.arb`, `lib/l10n/app_ar.arb` (+ regenerate), extend
`test/unit/generated_l10n_surface_test.dart` (the key-enumeration surface — lib/-only greps
lie about l10n deadness).

```json
"activityGroupResplitSingle": "{memberName} was added to {eventName} — equal splits recalculated",
"activityGroupResplitMulti": "{memberName} was added to {count, plural, =1{1 event} other{{count} events}} — equal splits recalculated"
```

AR per `docs/HOWTO-TRANSLATE.md` (full Arabic plural categories for `count`). Names are
FSI/PDI-isolated at the call site (#1216b pattern — already in Task 5's arms). Follow the
existing `activityGroup*` placeholder metadata blocks. Commit `feat(l10n): member_resplit copy EN+AR (#1059)`.

### Task 7 — Full suites + PR

- `cd functions && npm run test:emulator` (full), `flutter test`, `flutter analyze`,
  `tool/check_theme_purity.sh` (no new widgets styled, should be trivially clean).
- PR body: `Refs #1059` — **partial** (closes Stage 2's activity entry; the issue stays open
  only if the owner wants a Stage-3; otherwise `Closes #1059` — decide at PR time: Stage 1
  merged in #1082, so this PR completes the decided scope → default `Closes #1059`, commit
  message carries the same line, squash-merge inherits it).
- `/automerge` (Gate-category: functions/**) — fresh review + refuter.
- **Deploy rides the next release** (real users live): merged-but-undeployed delta tracked by
  `tool/pending_deploy.sh`; NO rules deploy in this PR; old clients degrade per fact 7, so no
  client-first gating. Note `⚠️ NOT deployed` applies until the next deploy ceremony.

## Acceptance boxes

- [ ] Shadow-add over a live global equal expense (open AND closed event cases) produces
      exactly one `member_resplit` row; empty/immune groups produce none.
- [ ] Join produces the row on first join only; rejoin produces none.
- [ ] Row is ISO-string-timestamped, deterministic-id'd, and survives a raced duplicate
      create without failing the callable.
- [ ] Client renders localized copy (single + plural EN/AR), Members filter bucket, ledger
      deep-link when single-event; forged/missing metadata degrades to description.
- [ ] Old-client degrade paths re-pinned (description fallback text arm test includes
      `member_resplit`-shaped doc WITHOUT the new switch arm? — no: pin via the existing
      `'some_future_type'` tests staying green + new-type tests).
- [ ] Client cannot forge `member_resplit` (explicit rules-test pin).
- [ ] `member_resplit` skipped by `groupActivityWriteRateMonitor`.
- [ ] No `firestore.rules` diff in the PR.
