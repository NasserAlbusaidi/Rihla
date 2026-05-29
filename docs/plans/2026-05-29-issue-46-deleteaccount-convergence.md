# Spec — #46 residual: make `deleteAccount` convergent on retry (server-only)

**Authored:** 2026-05-29 · **Status:** GATE PASSED (codex, round 5 — `PASS (no [P1] in scope)`). 5 rounds applied: r1 visibility-ordering, r2 originalName+collision-divergence, r3 concurrent-join lost-update (→ transactional Phase C), r4 `joinGroupByInviteCode`/`isDeleted` (carved out, pre-existing) + tombstone-free guard. Ready to implement (TDD).

## Ground truth (reconciliation — code wins over the issue)

Issue #46 was filed against the abandoned `codex/auth-release-hardening-fix-pass` branch. Verified against `main` (HEAD `f833fd1`) by a 5-investigator sweep + direct read:

- ❌ `AccountJobCoordinator`, `deletionJobs/{uid}`, `advanceDeleteAccountJob`, `startOrResumeDeleteAccountJob`, one-group-per-call, client-driven resume — **zero hits repo-wide.** Never merged.
- ❌ "`deleteAccount` uses `enforceAppCheck: true`" — **inverted.** Main is `false` (deliberate, #73/PR#74) + per-UID rate limit. #46's "some devices can't delete" worry is **already closed.**
- ❌ "`/delete-data` routes through the callable" — it's an external web URL (`app_links.dart:13`).
- ✅ **The one surviving concern:** no server backstop, **and the existing retry path is not provably convergent.**
- `#52` ("duplicate privileged callables") is **obsolete** — exactly one of each callable on main.

## What deletion is on main (so we don't regress it)

`deleteAccount` (`functions/src/callables/deleteAccount.ts`): one awaited callable. Queries `groups where memberIds array-contains uid`, loops **all** groups in one invocation, stages every write into **one shared `BatchWriter`** (commits at the 450-write boundary or the single post-loop `flush()` at `:570`), deletes `fcm_tokens`/`joinAttempts`, then `getAuth().deleteUser` **last** (`:576`). Soft App Check + rate limit (#73). `enforceAppCheck:false`, `timeoutSeconds:540`, `memory:'1GiB'`.

Client (`data_deletion_service.dart:38-50`): `await callable(); await signOut(); return ok` — **ignores the return payload**; **any throw → `DeletionResult.error`, no sign-out** (user can retry). `FirebaseFunctionsService().deleteAccount()` returns `Future<void>`, discards the result. **⇒ The only signal the client has is throw-vs-not.**

## The genuine defects (all verified against code)

- **D1 — No per-group isolation (the convergence-killer).** The group loop (`:552-568`) has **no try/catch**. One group throwing (transient Firestore error, a `not-found`/`failed-precondition` from `:365`/`:372`, malformed data) aborts the whole handler → groups after it never process and `deleteUser` never runs. On retry the same "poison" group fails at the same point → **never converges past it.** (Today's *saving grace* is only that this throw correctly denies the client a sign-out; but it also blocks the other groups.)
- **D2 — Shared `BatchWriter` cross-group tearing.** All groups share one writer; what's committed on failure is non-atomic and hard to reason about. A per-group commit boundary makes "this group is done" a clean unit.
- **D3 — Random tombstone accumulation.** `generateTombstoneId()` uses `Math.random()` (`:126-131`), minted fresh per `processGroup`, `set` unconditionally (`:402`). Any reprocessing of a group mints **another** "Deleted member" doc.
- **D4 — Throw-on-already-done.** `:365` (`not-found`) and `:372` (`failed-precondition` "no longer contains uid") throw on benign already-scrubbed/vanished groups. Combined with D1, a race can abort the whole cascade.
- **D5 (test gap) — the `internal` "scrubbed but Auth user could not be deleted" branch (`:587`) has no test.**

> **Rejected fix (synthesis was wrong here):** "wrap each group in a Firestore transaction" (as `cleanupAnonUidArtifacts` does). `deleteAccount` scrubs *all* events × expenses + settlements + activity_logs per group — a large group **exceeds Firestore's 500-write transaction cap** and would break accounts that work today. `cleanupAnonUidArtifacts` does far less per group, so its transaction is safe. We port its **resilience pattern (per-group isolation + `cascadeFailed` gating)**, *not* its transaction.

## Scope — IN (this PR, server-only)

Port the proven `cleanupAnonUidArtifacts` resilience shape onto `deleteAccount` + idempotency hardening:

1. **[Gate P1 — rounds 1+2+3] Two-phase `processGroup`: idempotent child scrubs, then a *transactional* identity-retirement.** The retry query is `where memberIds array-contains uid`, and child name-scrubbing depends on `originalName` read from the old member doc (`findOriginalName` `:382`). So **none** of the identity-visibility writes may land before child scrubs are durable; and because the visibility window is now long, the final step must be **isolated** against concurrent membership changes, not merely atomic. Restructure `processGroup`:
   - **Phase A (reads + id):** group, members (incl. old member → `originalName`, `joinedAt`, `isShadow`), events. Derive the deterministic tombstone id **once** here (item 4), incl. any collision suffix, and reuse it verbatim in B and C (never re-derive in C — that was the [P1.2] divergence).
     - **[Gate P2a] `originalName` fallback:** if `members/{uid}` is absent (corrupted group: `memberIds` has `uid` but no member doc), derive a fallback name from the first event's `participantNames[uid]`. If still unresolved, proceed with uid-keyed scrubs and **log** that free-text name residue may remain — do **not** fail the whole group (failing would block GDPR erasure on corrupted data, a worse outcome).
   - **Phase B (child scrubs — idempotent, may span auto-flush batches):** events, expenses, settlements, activity_logs, group activity — all referencing the Phase-A tombstone id. **[Gate P2b]** event `participantIds`/`participantNames` stay full array/map replaces (idempotent on retry). A merge-safe transform isn't cleanly available: `arrayRemove`+`arrayUnion` can't touch the same field in one write (and a batch bans two writes to one doc), and dotted-key `participantNames` updates can't encode tombstone/uid keys (they contain hyphens, illegal in dotted field paths without `FieldPath` escaping). The residual race — a concurrent edit to *this specific event* during the owner's own deletion — is low-severity and **documented + accepted**, same class as the expense field-rewrite residual. Flush.
   - **Phase C (identity retirement — ONE `db.runTransaction`, after B is flushed):** re-read the group doc + members **inside the transaction**; if the group is gone or `memberIds` no longer contains `uid`, **skip** (no-op). Otherwise recompute from *current* state: `memberIds` removal (remove `uid`, add the Phase-A tombstone id), `createdBy` reassignment, `oldestRealMemberUid`/orphan-soft-delete decision. Write tombstone-member `set` + old-member `delete` + `groups/{gid}` update. Mirrors `cleanupAnonUidArtifacts.ts:150`'s per-group transaction; it's a handful of writes, far under the 500-write tx cap. **[Gate P3 r4] Defensive guard:** inside the tx, before `tx.set` of the tombstone member, assert the fixed Phase-A id is either free or an existing `isTombstone` doc — never overwrite a real member (defends a future chosen-UID/import path; with generated Firebase UIDs the collision is unrealistic, but the guard is one line).
   - **Why this converges a torn huge group AND is concurrency-safe:** if B fails, Phase C never runs ⇒ group stays query-visible, old member survives (`originalName` intact, fixes [P1.1]), no tombstone committed (retry re-derives the same id, no suffix divergence, fixes [P1.2]). And because C re-reads inside a transaction, a `joinGroupByInviteCode` (`arrayUnion`, `joinGroupByInviteCode.ts:268`) landing during the long Phase-B window is **included** in C's fresh `memberIds`/survivor computation instead of being clobbered by a stale full-array overwrite (fixes [P1 round 3] — dropped joiner / wrongful group soft-delete).
2. **Per-group isolation + `cascadeFailed: string[]`.** Wrap each `processGroup` call in try/catch; on failure push `groupId`, log, **continue** to the next group (attempt all groups). Mirror `cleanupAnonUidArtifacts.ts:278-299`.
3. **Per-group commit boundary.** One `BatchWriter` **per group** for Phase B (constructed inside the loop, flushed before C); Phase C is its own `runTransaction`. A group's failure (in B or C) discards only its own un-committed writes; prior groups stay committed.
4. **Deterministic tombstone id** keyed by `uid`: `deleted-` + first 8 lowercase hex of `crypto.createHash('sha1').update(uid).digest('hex')`. Keep the `deleted-` prefix (tests + downstream readers depend on it). **[Gate P2] Collision guard** against the group's full `memberIds` array **and** existing member doc ids (incl. any `isTombstone` docs); on collision append a **deterministic** numeric suffix (`-2`, `-3`, …) — never `Math.random()`. **The suffix path never triggers on a retry** of our own torn deletion, because a tombstone doc is only ever committed in Phase C (when the whole group is done); a half-done retry sees no partial tombstone. The guard exists solely for the (astronomically rare) genuine collision with a pre-existing real member id.
5. **Skip-not-throw** in `processGroup` for the benign cases: group `!exists` or `memberIds` no longer contains `uid` ⇒ return a `skipped` result (counts as processed-noop, **not** a `cascadeFailed`), do not throw.
6. **Gate `getAuth().deleteUser` on `cascadeFailed.length === 0`** (also run `fcm_tokens`/`joinAttempts` deletes before the gate and fold their failures into `cascadeFailed`, mirroring cleanup `:301-344`).
7. **Failure signaling — THROW on partial.** If `cascadeFailed.length > 0` after the loop+globals: do **not** delete the Auth user; **throw `HttpsError('internal', 'Account deletion did not finish; please try again.', output)`** (output carries `cascadeFailed`). This is the deliberate divergence from cleanup: cleanup's client *reads* `cascadeFailed`; deleteAccount's client only sees throw-vs-not, so a partial cascade **must** throw to deny sign-out and prompt retry. The existing `:587` `internal` (deleteUser failed after full scrub) is preserved.
8. **Add `cascadeFailed: string[]` to `DeleteAccountOutput`.** Client-safe: the Dart client discards the payload (`data_deletion_service.dart:39`); no consumer reads `.details`.
9. **Test seam for the 450 boundary.** Make `batchLimit` injectable (e.g. `BatchWriter` constructor arg defaulting to 450, or a module override) so the convergence test below can force a mid-group auto-flush with a handful of docs instead of 450+.
10. **Tests (TDD, RED first)** — clean / partial / error, per the money-safety testing rule:
   - **A. Isolation + throw-on-partial.** Two groups; force group 1's commit to fail once (`jest.spyOn(WriteBatch.prototype, 'commit')` rejecting for the first call, or a per-path seam mirroring cleanup's `DocumentReference.prototype.delete` spy). Assert: handler **throws** `internal`; `cascadeFailed` contains the failed group; the **other** group is fully scrubbed (isolation); Auth user **still alive**.
   - **B. Retry converges.** Clear the spy, re-invoke. Assert: remaining group scrubbed, `cascadeFailed` empty, Auth user deleted. (Headline convergence proof.)
   - **C. Auth-delete-failure branch (`:587`, currently untested).** Spy `getAuth().deleteUser` to reject non-`not-found`. Assert throws `internal`, Firestore fully scrubbed, payload present; then un-spy + retry → converges (no groups, deleteUser → success/not-found).
   - **D. Deterministic tombstone.** Two groups, same uid → identical tombstone id (proves non-random); reprocessing the same group does **not** create a second `isTombstone` member doc; **forced-collision** seed (a real member already holding the derived id) → deterministic `-2` suffix, no merge.
   - **E. [Gate P1] Huge-group / multi-batch convergence.** With `batchLimit` lowered via the seam, seed one group whose Phase-B writes span ≥2 batches, **including an activity_log / metadata doc whose only `deletedUid` trace is the old display name** (name-only residue, no uid field) so the `originalName`-dependent rewrite is exercised. Force a failure **after** the first auto-flush, **before** Phase C. Assert: (1) first attempt throws `internal`; (2) the group is **still query-visible** (`memberIds` still contains `uid`) and `members/{uid}` **still exists** (so `originalName` survives for retry); (3) **no committed tombstone doc** yet. Then retry → assert: **zero `oldName` / `uid` residue anywhere** in the group's child docs, **every** scrubbed participant reference equals the **single** tombstone id now present in `group.memberIds` (no divergent `-2` identity), and auth deleted. This is the regression test for [P1.1] (name residue) + [P1.2] (identity divergence) + visibility ordering.
   - All **existing tests must stay green** (currently 7 by direct read; Codex counted 6 — verify the count at implementation). They use `toMatchObject`; tombstone assertions only require the `deleted-` prefix and `tombstoneIds.length===2`.

### Accepted tradeoff (Gate P2)

`enforceDeletionRateLimit` counts **every** invocation (5/hr/UID) before the cascade, so repeated partial retries consume the budget and can hit `resource-exhausted` before convergence. **Accepted:** transient failures converge within a few retries (well under 5); a *persistent* poison-group won't converge by retry anyway and is what the deferred server backstop (below) is for. Not a reason to resolve-on-partial. Documented here so it isn't rediscovered as a bug.

## Scope — OUT (deferred, tracked)

- **Scheduler / `onSchedule` server backstop** for the "user uninstalls and never returns" tail → **new follow-up issue.** No standing infra at current scale; gated on a real abandonment/timeout signal. (User: "don't overengineer.")
- **Client retry UX** — distinct `DeletionResult` variant for the partial/zombie-auth case + a guaranteed retry affordance in `profile_screen.dart` → **fast follow-up PR.** (User chose "server convergence only" for this PR.)
- **Recovery-path settlement/activity migration** in `cleanupAnonUidArtifacts` (known divergence, ties to #48) — not this PR.
- **Token revocation** before `deleteUser` (replay window) — note as a follow-up; rate limit is the current bound.
- **[Gate P1 r4] `joinGroupByInviteCode` accepts soft-deleted groups** — it checks only `groupSnap.exists`, not `isDeleted` (`joinGroupByInviteCode.ts:243`), so a join racing an orphan-soft-delete can land in a dead group. **Pre-existing on `main`** (orphan soft-delete already lives at `deleteAccount.ts:396-400`; this PR neither introduces nor widens it) and lives in a *different callable* → **separate follow-up issue** (reject `isDeleted===true` in the join transaction and/or invalidate the invite code on orphan). Not bundled here per "one PR does one thing."
- **TTL policy verification** (`deletionAttempts`, `recoveryCleanupIntents`) — ops check, out-of-band.

## Behavior-preservation argument

- Happy path (no failures): `cascadeFailed` empty → `deleteUser` runs → identical output (`authUserDeleted:true`). Deterministic tombstone still `startsWith('deleted-')`; two groups same uid → `tombstoneIds.length===2`. ✅
- Idempotent second run: query returns 0 groups → `groupsProcessed:0`, `deleteUser`→`not-found` swallowed → `authUserDeleted:false`. ✅
- No-groups / rate-limit tests: untouched. ✅

## Execution order

1. Write tests A–D (RED) → run emulator suite, confirm they fail for the right reason.
2. Implement 1–7 minimally → GREEN.
3. `cd functions && npm run build && npm run lint && npm test` (Jest + emulator, **Java 21**). Full suite green.
4. PR (one concern: deleteAccount convergence). Then: close #52 (obsolete), reframe #46 to the surviving scope + link follow-ups, open scheduler + client-UX follow-ups.

## Open questions for the Gate

- Is throwing `internal` on partial-cascade the right contract, vs a more specific code (`aborted`/`unavailable`)? Client maps all non-ok to one snackbar, so the *code* is cosmetic today — but it sets the contract the deferred client-UX PR will read.
- Deterministic tombstone derived from `uid` leaks nothing (uid is already the doc-id space), and the member doc stores no PII (`displayName:'Deleted member'`). Confirm sha1(uid)→8 hex has acceptable in-group collision odds (guarded anyway).
- Per-group `BatchWriter`: any cross-group invariant that relied on the single shared batch committing together? (None found — counters are per-group; orphan/`createdBy` logic is intra-group.)
