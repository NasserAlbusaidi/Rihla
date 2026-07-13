# Spec D — #1210: removing a shadow must retire its pending claim requests (rev 2, post-Gate-round-1)

Issue: #1210 (P3, membership-lifecycle). Branch: `fix/1210-removed-shadow-claim`. Commit body:
`Closes #1210`. Spec ships in PR as `docs/plans/2026-07-13-1210-removed-shadow-claim.md`. Server-only.

## Problem (verified 2026-07-13 against main @2ce0891c)

`removeMember` hard-deletes a shadow's member docs and never touches `claimRequests`, so a pending
`requestClaimShadow` doc survives the removal as a live actionable row in the creator's list. Approving
it runs `claimShadowEngine` Phase A: no member doc (`claimShadow.ts:597-598`) → #558 Hole-2 torn-cascade
scan → `snapshotReferencesShadow` true from `participantIds` residue (:493) → false
`'prior cascade torn'` P0 log (:609) + `HttpsError('internal', …)` (:614-617); `decideClaimRequest`'s
catch resets the reservation to pending (:336) → re-approve loops forever; only Decline clears it.

## Design decision (Gate round-1: both reviewers killed the v1 pre-flight leg)

v1 proposed a decideClaimRequest pre-flight: "shadow member doc absent → auto-decline + shadowRemoved
response". REJECTED: member-doc absence cannot distinguish a REMOVED shadow from a shadow legitimately
CLAIMED by another requester (duplicate-name groups hold multiple pending requests per shadow —
decideClaimRequest.ts:345-349; existing tests D12/D13/D14, claimRequest.test.ts:~564/593/624, pin
approve-of-claimed-shadow → `failed-precondition` "This member has already been claimed."). A pre-flight
auto-decline would flip that contract from throw to resolved-success and show wrong copy. The engine
(claimShadow.ts:597-630) also stays untouched — torn-vs-removed is equally undecidable there (a zero-net
shadow payer passes removeMember's gate, so legit removals can leave payer/split refs).

**The fix is prevention at the source: a shadow's pending claim requests are declined ATOMICALLY with
its removal.** After this, the #1210 state cannot arise: the row vanishes from the creator's list the
moment the shadow is removed, and a stale-UI Approve on the already-declined request hits the existing
clean short-circuit `failed-precondition` "This claim request has already been decided."
(decideClaimRequest.ts, the already-decided guard — cite by behavior, line drifts) — correct copy, no
P0 log, nothing stuck. No Flutter-client change needed.

**Derived surface the sweep MUST own (Gate round-2 P1, both reviewers): `claimRequestNotifier`.** The
trigger's Branch B (`functions/src/triggers/claimRequestNotifier.ts:~118-145`, deliberately UNFENCED
per #1141 — reaches pre-join requesters) fires on `status: pending/claiming → declined` and would push
the requester "Your claim for {shadow}'s spot was declined." — misrepresenting a member REMOVAL as an
explicit creator rejection, deep-linking into a claim flow that dead-ends. Decision: **suppress the
push for this sweep.** Branch B additionally checks `autoDeclineReason == 'shadow-removed'` on the
after-state and returns without sending (a content-based skip, NOT a membership fence — #1141's
"Branch B never fenced" rule is about membership, untouched). A bespoke "placeholder was removed" push
is deliberately NOT built (new copy/strings/AR for a rare admin action) — record as a named follow-up
option in the PR body, don't build it. Normal creator-tapped declines keep pushing exactly as today.

## Fix — `functions/src/callables/removeMember.ts` + one trigger skip

1. **Main removal transaction**: in the reads phase, `tx.get(groupRef.collection('claimRequests')
   .where('shadowMemberId', '==', targetUserId).where('status', '==', 'pending'))`; in the writes phase,
   `tx.update` each to `status: 'declined'` plus the SAME decided-fields shape the decline path of
   `decideClaimRequest` writes (builder copies the exact field set — decidedBy/decidedAt/whatever exists
   — plus `autoDeclineReason: 'shadow-removed'`, which is ALSO the notifier-skip marker, see below).
   Respect Admin-SDK reads-before-writes ordering. Builder verifies the collection path + field names
   from `requestClaimShadow.ts` / `decideClaimRequest.ts` (statuses observed: 'pending', 'declined',
   'claimed', 'claiming') and confirms claimRequests docs are callable-only surfaces (grep
   firestore.rules) so no rules change is needed for the new field.
2. **EVERY exit path sweeps** (round-2 P2: there are TWO idempotent early returns): (a) the pre-tx
   idempotent short-circuit AND (b) the IN-TRANSACTION idempotent early-return (removeMember.ts ~:236-239)
   must also decline pending rows for the target before returning. **Reads-before-writes trap on (b)
   (round-3): that early-return branch already WRITES (`tx.update(groupRef, departureLockClearFields())`)
   before returning — the claimRequests query read must be placed in the tx's READS phase ABOVE that
   branch, shared by both the early-return and the main path; adding the read after that write throws.**
   The pre-tx path uses a small standalone update. Self-heals legacy/raced orphan rows on a retry.
3. Only shadow targets can have claim requests, but scoping the sweep by `shadowMemberId ==
   targetUserId` makes it a safe no-op for real-member removals — no target-type branch needed.
4. **`claimRequestNotifier.ts` Branch B skip**: return without sending when the after-state carries
   `autoDeclineReason == 'shadow-removed'` (see Design decision). Keep every other branch byte-identical;
   the #1141 membership-fence rules are untouched.

`requestClaimShadow`'s open/reopen guard — VERIFY BOTH PATHS SEPARATELY (round-2 found the two prior
reviews disagreed here): the fresh-open path has a shadow-existence refusal ("That member can't be
claimed.", ~:110); the declined→pending REOPEN block (~:132-141) may have NO local check — builder
determines by reading whether the reopen block is reachable without passing the open-path guard. If the
reopen path is guarded (shared earlier check), document file:line in the PR body + add a pinning test;
if unguarded, add the same field-matched existence refusal there. Assert the ACTUAL error code/message.

## Non-goals

- `claimShadow.ts` (engine, torn scan, #714 reaper semantics) — diff must be EMPTY.
- `decideClaimRequest.ts` — diff must be EMPTY (the already-decided short-circuit and D12/D13/D14
  already-claimed contract are the desired behavior).
- No Flutter-client change, no l10n change, no new claimRequest status value, no participantIds pruning.
- No bespoke "shadow removed" push notification (named follow-up option, PR body only).
- In `claimRequestNotifier.ts`: nothing beyond the single Branch-B `autoDeclineReason` skip.

## Accepted residual (document in PR body)

A pending row for an absent shadow that PREDATES this deploy (or slips through a Firestore
query-phantom race between requestClaimShadow's tx and removeMember's tx) still routes Approve → engine
`internal` + P0 log. Accepted because: no real users yet ⇒ no legacy rows in prod; the phantom race is
rare (though wider than a single commit — don't overstate); Decline remains the escape hatch and a
removeMember RETRY now heals the row (fix leg 2). Do not build discrimination logic for it. One wording
note for the auto-decline fields: `decidedBy: <remover uid>` on an automatic sweep reads like an
explicit decision — harmless (declined rows never surface in the pending-only list; the notifier skip
keys on `autoDeclineReason`), but say so in the code comment.

## Tests (RED first — functions emulator; `npm run test:emulator -- <file>`, never bare jest #1157)

1. RED repro of the source: add shadow → requestClaimShadow (pending) → removeMember(shadow) → assert
   the request doc: TODAY still `status: 'pending'` (observe & paste); AFTER: `status: 'declined'` +
   `autoDeclineReason: 'shadow-removed'`, written in the same commit as the removal (assert no
   intermediate pending-after-removal state on the fixed path).
2. End-to-end UX pin: same sequence, then decideClaimRequest(approve) → `failed-precondition`
   "already been decided" short-circuit — NOT `internal`, and assert NO 'prior cascade torn' log fired.
3. Idempotent-path heal: Admin-seed a pending request for an already-absent shadow → removeMember
   pre-tx short-circuit → request declined. (The IN-TX early-return branch is NOT deterministically
   reachable in a single-threaded emulator test — it needs a concurrent removal between the pre-tx read
   and the tx re-read; cover it by code inspection + a test-file comment, do not write a flaky test.)
4. Real-member removal regression: removeMember of a non-shadow with zero pending requests — sweep is a
   no-op, existing behavior unchanged.
5. D12/D13/D14 (claimRequest.test.ts — locate by test NAME, cited lines have drifted) green UNCHANGED;
   engine test suite green UNCHANGED.
6. Reopen-guard pin (see above): removed shadow → requestClaimShadow (fresh open AND declined→reopen) →
   asserted actual refusal (or document the existing test that already pins it).
7. **Notifier pair (extend claimRequestNotifier.test.ts):** (a) shadow-removed auto-decline
   (`autoDeclineReason: 'shadow-removed'`) → NO send; (b) a normal creator decline (no reason field) →
   sends exactly as today (regression pin for the skip's scoping).

## Acceptance

- [ ] RED evidence for test 1 pasted (pending survives removal on main), green after.
- [ ] `git diff` touches removeMember.ts + claimRequestNotifier.ts (Branch-B skip only) +
      requestClaimShadow.ts (only if the reopen guard is genuinely missing) + test files + this spec
      doc; claimShadow.ts and decideClaimRequest.ts diffs are EMPTY.
- [ ] Notifier pair tests green (skip on shadow-removed, send on normal decline).
- [ ] Reopen-guard verification documented (file:line) in PR body.
- [ ] Full functions suite green.
- [ ] PR body + squash commit body: `Closes #1210`; note "functions NOT deployed — pending deploy
      ceremony"; accepted-residual paragraph + named follow-up (bespoke removal push) included.
