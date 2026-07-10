# #1099 — deleteAccount: Bounded Re-Query Loop Before the Auth Delete

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** a membership created concurrently during the deleteAccount cascade must never become a permanent ghost — it either gets scrubbed in the same run or lands in the existing `cascadeFailed` → `deletionAudit` → `deletionReaper` convergence loop.

**Architecture:** `runAccountDeletionCascade` (`functions/src/callables/deleteAccount.ts:769-919`) takes ONE membership snapshot (S0, `:804-806`) and never re-checks before `getAuth().deleteUser(uid)` (`:893`). The fix: after the per-group scrub loop and BEFORE the auth-delete gate, run a bounded **re-query loop** (max 3 passes): re-run the same `memberIds arrayContains uid` query; any group NOT already processed gets the same `processGroup()` treatment; repeat until a pass finds zero new groups. If the final pass still finds unscrubbed groups (pathological churn), push them into `cascadeFailed` — the existing machinery then blocks the auth delete, writes the `deletionAudit` marker, and the 24h `deletionReaper` (`deletionReaper.ts:24-60`) re-runs the cascade to convergence. Single file; no rules change, no new marker collection, no auth-disable.

**Issue:** #1099 (P3, backend). Scout-mapped 2026-07-10; all line cites verified against `deleteAccount.ts` read in full. Gate round 1: 1 P1 resolved (monotonic exclude-set discarded a re-joined group). Gate round 2: 3 P1s resolved — (a) the loop now SKIPS groups already in `cascadeFailed` this run (re-processing S0-failed groups self-healed the bounded failure injections in the pinned tests at `:664`/`:777`, breaking them; failed groups are the reaper's job by design); (b) placement is MANDATED loop-last (immediately before the `:885` gate, AFTER the claim/FCM/joinAttempts scrubs — `decideClaimRequest.ts:328-330` re-adds `requesterUid` to `memberIds`, so an early-placed final check leaves the whole `:852-880` window as a permanent-ghost path); (c) tombstone reuse re-keys money maps via `mergeUidMapKey` (SUM), never `renameMapKey` (OVERWRITE) — a re-joined member's `splitDistribution` can hold BOTH the tombstone and the uid, and rename silently drops the tombstone's slice.

---

## Verified mechanics the fix builds on

- S0 at `:804-806`; sequential per-group scrub `:811-844` (each group isolated in try/catch, failures → `cascadeFailed` via the `addCascadeFailure` pattern at `:837,:854,:866,:875`); auth delete at `:893` gated on `cascadeFailed` empty (`:885-907`); `deletionAudit` marker written ONLY on failure (`:909-916`) — which is exactly why the reaper is structurally blind to this race today: a "successful" run that missed a concurrent join writes NO marker.
- `processGroup` (`:646-671`) is idempotent and self-guarding (re-checks `memberIds.includes(uid)` at Phase A `:460` and Phase C `:576`), so feeding it a freshly-discovered group is architecturally identical to a retry — the file's own comment at `:808-810` frames the gate this way.
- The reaper re-invokes `runAccountDeletionCascade` itself, so anything pushed into `cascadeFailed` converges within 24h with zero new plumbing.

## Deliberate decisions (do not re-litigate)

1. **Option (a), not the per-uid marker (b), not the sweeper (c).** The marker option's "disable-auth-first" half is near-inert (a live ID token passes `onCall` verification regardless of `disabled` unless the callable does an explicit `getUser()` check, and Firestore rules can NEVER see `disabled` — they only see token claims), so (b) reduces to a new marker collection checked in `joinGroupByInviteCode` AND a new `get()` in `validGroupCreate` (`firestore.rules:317-349`) — two files, one of them rules, for a P3. The sweeper (c) has no bounded scaffold to extend and leaves an hours-wide live-ghost window anyway. (a) is one file, reuses proven machinery, and closes both the JOIN and CREATE variants symmetrically (both land in the same `arrayContains` result set).
2. **Documented residuals — accepted, not hidden:**
   - A write landing in the one-round-trip sliver between the final clean re-query and `deleteUser` remains possible (snapshot-then-act, structurally). Bounded and tiny vs today's whole-cascade window.
   - **A valid ID token OUTLIVES the auth deletion** (up to token TTL, ~1h): a deleted user's still-valid token can pass rules validation for a client group-create — and, worse variant (r3 adversary), can join + `requestClaimShadow` + get creator-approved, inheriting a shadow's BALANCE (a money-bearing ghost, not just an empty orphan group). No variant of (a) or (b) closes this; only a reconciliation sweeper (c) could — deferred, name BOTH variants in the issue close-out note.
3. **Loop bound = 3 passes.** Convergence pressure: each pass scrubs everything it finds; a genuinely-active adversary re-joining in a loop lands in `cascadeFailed` → marker → reaper, which is the designed slow path. Do not make the bound configurable.
4. **No client changes.** The client deleteAccount flow is untouched; `permission-denied`/UX unchanged.

---

### Task 1: Regression test (RED)

**Files:** Modify `functions/test/callables/deleteAccount.test.ts`

Use the file's own deterministic mid-cascade injection pattern (`failFirstPhaseBCommit` at `:838-846` — `jest.spyOn` + `mockImplementation` WITH a call counter). **Injection point (Gate r1 P2): seeding inside a `deleteUser` spy lands in the irreducible post-loop sliver and the test could never go green.** Harness shape (r2 rubric P3): `jest.spyOn(db, 'collection')` filtered on `'groups'` with a call counter — `db.collection('groups')` is called ONLY at S0/re-query/finalCheck (mirror the existing `collectionGroup` spy at `:538`); call #1 (S0) resolves normally, then the spy seeds the concurrent group/membership BEFORE call #2 resolves. **Seed via `db.doc('groups/<gid>')` paths, never `db.collection('groups')` — the seeding itself must not re-enter the counter.**

Test 1 (the core — new-group join/create mid-cascade): seed between S0 and the first re-query. Post-fix GREEN: the new group is scrubbed in the same run (uid absent from `memberIds`, tombstone present) — or, acceptably, `deletionAudit/{uid}` exists and the auth user was NOT deleted. Pre-fix RED: auth user deleted AND ghost membership intact.
Test 1b (the r1-P1 case — RE-join after scrub): a co-membered group scrubbed in S0 gets the uid re-added to `memberIds` post-scrub (hook the same counter spy at the appropriate call). Post-fix: re-scrubbed with exactly ONE tombstone doc (reuse, not `-2`), or marker + no auth delete. Pre-fix (with any exclude-set design) this is the permanent-ghost case.
Test 2: churn termination — seed on EVERY re-query pass → after the bound, the FINAL re-query's ids land in `cascadeFailed`, marker written, auth user NOT deleted.
Test 3 (existing-behavior pin): no concurrent write → re-queries return empty, auth user deleted, no marker (happy path unchanged).

Run under the emulator harness (`cd functions && npm run test:emulator -- deleteAccount.test.ts -t "<name>"`). Capture RED verbatim.

### Task 2: The re-query loop (GREEN)

**Files:** Modify `functions/src/callables/deleteAccount.ts`

**Placement is MANDATORY, not a choice (Gate r2 P1-b): the loop + final check run LAST — immediately before the `:885` gate, AFTER `scrubClaimStateForDeletingUid` and the fcm/joinAttempts deletions (`:846-880`).** Rationale: those scrubs take several round-trips; a `joinGroupByInviteCode` (freeze already cleared by Phase C `:599-601`) or a creator-approved claim (the actual `memberIds` mutation is `claimShadow.ts:431`, driven from `decideClaimRequest`) committing during that window would land AFTER an early-placed final check → clean gate → `deleteUser` → no marker → permanent ghost. Loop-last also means the claim scrub has already deleted the uid's pending requests before the final check, closing the claim variant. The only remaining unguarded window is the one-round-trip sliver in residual #1.

**The re-query result is AUTHORITATIVE — no exclude-set (Gate r1 P1).** A successfully-scrubbed group drops out of the `arrayContains uid` result by construction (Phase C removes the uid from `memberIds`), so any group the re-query returns — S0-processed or not — currently holds a live membership and must be (re-)processed. A monotonic `processedGroupIds` filter would discard a RE-JOINED group (scrub clears `accountDeletionInProgress` at `:598-602`, making the group joinable again; `joinGroupByInviteCode:235` only blocks while the freeze is set) → auth deleted with no marker → permanent ghost the reaper never sees.

```ts
for (let pass = 0; pass < 3; pass++) {
  const requery = await db
    .collection('groups')
    .where('memberIds', 'array-contains', uid)
    .get();
  // Gate r2 P1-a: groups that FAILED this run stay the reaper's job — they
  // already block the gate. Re-processing them here would self-heal the
  // bounded failure injections the pinned tests (:664/:777) rely on and
  // muddy the failure contract. The loop owns only UNACCOUNTED groups.
  const fresh = requery.docs.filter((d) => !cascadeFailed.includes(d.id));
  if (fresh.length === 0) break;
  for (const groupDoc of fresh) {
    // same isolation contract as the S0 loop (:811-844): try/catch per group,
    // addCascadeFailure (:716, dedupes) on error
    <processGroup with identical try/catch>
  }
}
// FINAL authoritative check: anything still holding a membership and not
// already accounted for goes to cascadeFailed — the reaper re-queries fresh
// and converges (its marker's group list is observability-only, :683-684).
const finalCheck = await db.collection('groups')
  .where('memberIds', 'array-contains', uid).get();
for (const doc of finalCheck.docs) addCascadeFailure(cascadeFailed, doc.id);
```

**Wrap the re-query and finalCheck `get()`s (r3 rubric P2):** a transient query failure must DEGRADE, not throw — catch it and `addCascadeFailure(cascadeFailed, 'requeryUnavailable')` so the gate blocks and the marker is written (mirroring the wrapped claim/fcm blocks at `:851-880`); an unwrapped throw would exit markerless and the reaper would never converge that run.

Loop-exit invariant, stated precisely: at the `:886` gate (unchanged), every group holding a live membership is EITHER in `cascadeFailed` (S0 failure, loop failure, or final-check catch) OR was scrubbed (absent from the final re-query). A late join successfully scrubbed in-pass does not enter `cascadeFailed`; the user-visible failure path is reserved for genuinely-unresolved state. (The r2-adversary P3 — an S0-failed group that would have succeeded on retry stays failed this run — is the deliberate cost of preserving the failure contract; the client's immediate retry self-heals it.)

**Tombstone reuse on re-scrub (Gate r1 P2, hardened by r2 P1-c):** re-processing a re-joined group must NOT mint `deleted-<hash>-2`. When the existing doc at the deterministic id (`deterministicTombstoneId` `:117-124`) is a tombstone (`isTombstone == true`), REUSE it; the suffix-advance stays for genuine collisions with other members' REAL docs (the pinned tests at `:740,:764-771` keep passing — their occupant is a real member). Two hard conditions ride the reuse:
- **Money maps re-key via `mergeUidMapKey` (SUM — `mapReKey.ts:1-20`, the claim engine's collision-safe helper), NEVER `renameMapKey` (OVERWRITE, `deleteAccount.ts:240-249`).** Reachable collision: pass-1 scrub puts tombstone T into the event's `participantIds` (`:483-485`); the re-join fans the uid back in (`joinGroupByInviteCode.ts:317`); a new expense then holds `splitDistribution {T: a, U: b}`; rename would set `T=b` and DROP `a` — conservation broken. Merge sums to `T: a+b`. With an absent target key, merge behaves as rename, so switching the cascade's money-map re-key to `mergeUidMapKey` is safe for first scrubs too (existing test `:428`/#710 yields identical output). **Scope: `splitDistribution` (`:240-249`) ONLY.** Settlements re-key SCALAR payer/recipient fields (`:265-291`) — no map, no hazard, leave them. **`participantNames` at `:492` STAYS `renameMapKey`** (r3 adversary): `mergeUidMapKey` coerces values via `toFiniteNumber`, which would corrupt a NAME map to a number and later throw 'malformed'. `participantIds`-style arrays already dedupe via `replaceUid` (`mapReKey.ts:88`).
Implementation sentence for the reuse (r3 adversary): `deterministicTombstoneId` only sees a `Set<string>` — the CALLER builds `taken` (`:463-465`); on re-scrub, drop the base deterministic id from `taken` when its occupant doc has `isTombstone === true`, so the function returns the base id unchanged; genuine collisions (occupant is a real member) keep advancing. `output.tombstoneIds` may then carry a duplicate entry across passes — observability-only, acceptable.
- **Ownership caveat, documented not solved:** the tombstone stores `userId: tombstoneId` (`:615`), so a same-group sha1-prefix collision between two deleted uids (~2^-32, the class the code already accepts at `:113-116`) would merge two anonymized "Deleted member" ledgers under reuse. Accepted as inherited risk; note it in the code comment.
Regression: the re-join test asserts exactly ONE tombstone doc AND money conservation (the `splitDistribution` sum over the expense is unchanged across the re-scrub; `T`'s slice equals `a+b`).

Tests 1-3 green; full `npm run test:emulator` (all 21+ existing deleteAccount cases must stay green — especially idempotent-second-run `:401`, partial-cascade `:664`, torn Phase B `:777`).

### Task 3: Ship

- [ ] `cd functions && npm run lint` (or the repo's TS lint step) clean; full emulator suite green.
- [ ] NO deploy in this PR — `backend-deployed` tag advances only via `tool/deploy_firebase_backend.sh` (deploy ceremony is a separate step; note `tool/pending_deploy.sh` will show this as pending).
- [ ] PR: title `fix(backend): deleteAccount re-queries memberships before the auth delete (#1099)`; body: summary, `Closes #1099` in FINAL commit body, `Spec: docs/plans/2026-07-10-1099-deleteaccount-requery.md`, Test plan, RED evidence, the two documented residuals (sliver + post-deletion token TTL, with the sweeper named as the deferred structural answer).
- [ ] `/automerge <PR>` — `functions/**` = Gate-category; fresh review + refuter.
