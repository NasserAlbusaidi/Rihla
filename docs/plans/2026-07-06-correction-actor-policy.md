# Correction-callable actor policy (Gate spec)

Base: `main` @ `49204448`. Status: spec — pre-implementation Gate review.

## Problem

`correctSettlement` and `correctLogicalSettleUp` authorize on group membership alone
(`functions/src/callables/correctSettlement.ts:92-95`,
`functions/src/callables/correctLogicalSettleUp.ts:102-105`), so **any group member can
reverse other people's settlements**. The Correct UI is live (event screen gates on
`canRecord` = event participant; group screen wires it unconditionally). The append-only
reverse mechanics (deterministic reverse ids, `tx.create`, `correctionOfSettlementId`
marker — `shared/settlementCorrection.ts`) are correct and are NOT touched.

## Policy (exact)

- `correctSettlement`: allow IFF
  `callerUid == group.createdBy`
  OR `callerUid == originalData.payerParticipantId`
  OR `callerUid == originalData.recipientParticipantId`
- `correctLogicalSettleUp`: allow IFF
  `callerUid == group.createdBy`
  OR callerUid is a party (payer OR recipient) on **EVERY** live tagged original
  (party-on-some-but-not-all → DENY)
- Shadow participants have no claimable uid: their participant id is a `randomUUID()`
  (`addShadowMember.ts` — uuid is both member-doc id and `userId`; there is no `shadow_`
  prefix convention anywhere). The party branch must never match null/absent/non-string
  fields; a shadow uuid can never equal an auth uid.

## Verified facts

- `groupData.createdBy` is on the group doc already loaded in both callables
  (`groupSnap.data()` at correctSettlement.ts:80 / correctLogicalSettleUp.ts:93) —
  zero extra reads.
- Settlement docs carry `payerParticipantId`/`recipientParticipantId` directly
  (correctSettlement.ts:133-134; logical per-original loop :145-146). For a real member,
  participantId == auth uid. Party matching = direct uid equality; no member-doc read.
- Party ids are only known after the settlement doc(s) load mid-transaction, so the actor
  gate sits after party extraction/validation — after correctSettlement.ts:157, after the
  logical per-original loop (:144-167).
- Existing callable tests: every call is OWNER (= seeded `createdBy`) except two MEMBER
  retries (correctSettlement test 14; correctLogicalSettleUp.test.ts:324) where MEMBER is
  the seeded payer → zero existing test breakage expected.
- UI: both screens already have `currentUid`, `group.createdBy`, and each settlement's
  party ids in scope. `SettleUpPageBody` (2 production callers) holds `currentUid` but
  doesn't thread it to `_PaymentHistorySection`/`_HistoryTile`; the existing null-hides
  pattern (`onCorrect: null`) is the composition point. `LogicalHistoryRow` carries only a
  `representative`, but every leg of a decomposed settle-up shares the same
  payer→recipient pair, so a representative-based UI predicate is sound (server still
  checks EVERY original). Six widget-test files construct `SettleUpPageBody` directly →
  the new param must default to ungated.

## Policy decisions

1. **The existing membership gate is KEPT** in both callables; the actor gate is added
   after it. Strictly narrowing — a departed payer stays denied (as today), outsiders
   keep `permission-denied` before any doc enumeration.
2. **Logical "every original" is evaluated over the full live tagged set**
   (`taggedOriginals`, pre-filtering) — deny-biased; reverses in the set carry the same
   two parties (inverted), so well-formed sets are unaffected.
3. **Shadow/null safety by construction:** party branch is
   `typeof p === 'string' && p === uid`. `uid` is a non-empty auth uid; a shadow's uuid or
   a null/absent field can never equal it. Pinned by unit tests anyway.
4. **Known UI asymmetry kept:** on the event screen `onCorrect` stays additionally gated
   by `canRecord` (participant-only), so a creator who isn't an event participant sees no
   Correct there even though the server would allow. UI stricter than server = fine; not
   widened in this PR.
5. **Recorder is NOT an authorized actor (acknowledged exclusion, Gate R1 adversary
   P2):** a member who recorded a settle-on-behalf settlement between two OTHER parties
   (`settlement.createdBy`) loses self-correct under this policy; and since a creator can
   leave via `leaveGroup` without `createdBy` reassignment, a settlement whose parties
   are both non-invokable (shadows/departed) becomes UI-uncorrectable once the creator
   departs. Deliberate — the ordered policy is exact (creator-or-party). Candidate
   follow-up if product wants it: add `settlement.createdBy` as a third actor branch.

## Changes

### Server (≤40 lines/callable — actual ~3 each + ~28-line helper)

1. **New** `functions/src/callables/shared/correctionActor.ts` — guard only:
   ```ts
   export function assertCorrectionActor(
     uid: string, createdBy: unknown, originals: ReadonlyArray<DocumentData>,
   ): void
   ```
   - creator branch: `typeof createdBy === 'string' && createdBy === uid`
   - party branch: `originals.length > 0 && originals.every(isParty)` where `isParty`
     type-guards both participant fields (never matches null/absent/shadow-uuid)
   - else `throw new HttpsError('permission-denied', 'Only the group creator or a party
     to this settlement can correct it.')`
2. **`correctSettlement.ts`** — after the party-scope validation block (:139-157):
   `assertCorrectionActor(uid, groupData.createdBy, [originalData]);` + import.
3. **`correctLogicalSettleUp.ts`** — after the per-original validation loop (:144-167):
   `assertCorrectionActor(uid, groupData.createdBy, taggedOriginals.map((o) => o.data));`
   + import.

### UI (≤30 lines total — affordance hiding only; server is the boundary)

4. **`settle_up_page_body.dart`** — add optional `final String? groupCreatorId;` to
   `SettleUpPageBody` (default null = ungated, keeps the 6 direct-constructing test files
   green); thread `currentUid` + `groupCreatorId` into `_PaymentHistorySection`; one
   private predicate `_canCorrect(Settlement s)` =
   `groupCreatorId == null || (currentUid != null && (currentUid == groupCreatorId ||
   s.payerParticipantId == currentUid || s.recipientParticipantId == currentUid))`;
   apply at the three `_HistoryTile` sites via the existing null-hides pattern:
   - both solo sites: `onCorrect: _canCorrect(settlement) ? onCorrect : null`
   - logical site: fold `!_canCorrect(row.representative)` into the existing
     `affordanceCorrected` ternary
   Composes with (never replaces) `soloCorrectionHidden`, `groupSettleUpId == null`,
   `affordanceCorrected`. `_HistoryTile` itself unchanged.
5. **`settle_up_screen.dart`** (~:345) and **`group_settle_up_screen.dart`** (~:216):
   pass `groupCreatorId: group.createdBy` (group already in scope in both builders).

## Tests (RED first for every DENY; ALLOW tests are green pre-change — the RED evidence
is carried by the DENY cases)

Functions — new describe blocks in the existing emulator suites (reusing their seeds;
`OWNER`=creator, `MEMBER`, add `THIRD` to `memberIds`):

- `functions/test/callables/correctSettlement.test.ts`:
  - RED: DENY third member (settlement MEMBER→OWNER, caller THIRD) → `permission-denied`
  - ALLOW payer (MEMBER); ALLOW recipient (THIRD on a MEMBER→THIRD settlement); ALLOW
    creator-not-party (OWNER on MEMBER→THIRD)
  - Shadow: settlement `<uuid>`→MEMBER (uuid in memberIds/participantIds): MEMBER
    (recipient) allowed; THIRD denied — shadow party never opens the door
- `functions/test/callables/correctLogicalSettleUp.test.ts`:
  - RED: DENY third member → `permission-denied`
  - RED: DENY party-on-some-but-not-all (originals MEMBER→OWNER + THIRD→OWNER, caller
    MEMBER)
  - ALLOW all-party caller (MEMBER, all originals MEMBER→OWNER); ALLOW creator (OWNER)
- **New** `functions/test/callables/shared/correctionActor.test.ts` (pure unit, mirrors
  `settlementCorrection.test.ts`): null/absent participant fields never match; uuid party
  vs different uid → throw; creator match; empty originals → throw.

Flutter widget tests (mirror `settle_up_screen_test.dart:1010-1096` participant gating;
`group_settle_up_correct_test.dart` `_wrap(currentUid: …)`):

- Event screen: participant-but-not-party/creator → `settleUpCorrectButton` findsNothing
  (RED); party → findsOneWidget; creator → findsOneWidget (creator MUST be seeded as an
  event participant — the kept `canRecord` gate hides the button for non-participant
  creators; Gate R1 P3).
- Group screen: third member (`uid-carol` added to fixtures) → no solo Correct, no
  logical Correct (RED); party and creator → visible.
- Shadow emulator test: the shadow uuid must be seeded into `memberIds` AND the event's
  `participantIds`, else the pre-existing participant-validation loop throws
  `failed-precondition` before the actor gate is exercised (Gate R1 P3).

## Gate log

- Round 1 (2026-07-06): rubric reviewer 0 P1 / 0 P2 / 3 P3; orthogonal adversary
  0 P1 / 1 P2 / 1 P3 — **P1-clean in the same round, Gate passed.** P2 (recorder
  exclusion / departed-creator dead-end) recorded as Policy decision #5; P3s folded into
  the test notes above.

## Fence

- Allowlist only: the two callables (guard insertion), new shared helper, functions
  tests, `settle_up_screen.dart` / `group_settle_up_screen.dart` /
  `settle_up_page_body.dart`, widget tests.
- Blocklist: `settlementCorrection.ts` untouched; `security/firestore.rules` untouched;
  no balance/aggregate/recompute changes; no 9-leg-cap or money-math edits.
- Deploy: functions change → post-merge backend deploy pending (`tool/pending_deploy.sh`
  / deploy-ceremony; no real users → deploys freely).
