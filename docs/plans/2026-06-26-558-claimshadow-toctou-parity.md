# #558 — claimShadow post-commit parity TOCTOU (both holes)

**Status:** spec for Gate · **Issue:** #558 (P2, money, backend, cluster:money-trust) · **Milestone:** 1.6.3
**Files:** `functions/src/callables/claimShadow.ts` (only). No oracle / rules / client / `decideClaimRequest` change.
**Spec:** fully close #558 (both named holes) — chosen scope.

---

## 1. The bug — two holes in the post-commit TOCTOU backstop

`claimShadowEngine` (PR7, #557) re-keys a placeholder ("shadow") member's uuid identity onto a real joiner's auth uid across every money doc. It is two-phase: **Phase B** batched child re-keys (flushed, durable — `BatchWriter`), then **Phase C** transactional identity retirement (memberIds + member doc, shadow doc deleted). After Phase C it runs `assertExactParity` — `recomputeNet` → assert `simNet == actualNet` AND shadow absent. A mismatch ⇒ a concurrent write landed between the Phase-A snapshot and the commit (TOCTOU) ⇒ throw `internal`.

Two structural defects (both deliberately deferred at PR7 — see test 19's note):

**Hole 1 — post-commit throw, no rollback, AND false-rejects benign edits.** The assert runs *after* Phase B (flushed) and Phase C (committed) are durable — there is nothing to roll back. Worse, its discriminant (`simNet != actualNet`) fires on *any* concurrent edit, including an honest one whose `actualNet` is correct. A legitimate concurrent admin edit to an event's `participantIds` (or an honest member add) makes `actualNet` diverge from the stale `simNet` → throw `internal` on a **correct** claim → `decideClaimRequest` leaves the request `pending`, the creator sees an error, and on re-approval the requester is told "already claimed."

**Hole 2 — idempotent retry blesses un-verified.** On retry, the shadow member doc is gone (`shadowMembers.length === 0`, `claimShadow.ts:357`) → the engine returns `{alreadyClaimed:true}` (`:363`) **before** any verification. A torn/corrupt prior cascade is silently accepted.

### 1a. Corruption is REACHABLE (not a false alarm) — the deciding scenario

Verified line-by-line against `groupNetBalance.ts:635-675`:

- Seed: `g.memberIds=[OWNER,SHADOW]`; event `e1.participantIds=[OWNER,SHADOW]`; expense `x1` OWNER pays 12.000 equally. CLAIMER brand-new (∉ every slot at Phase-A snapshot → passes the 3-term pre-scan).
- **Interleave:** between Phase B's `eventDoc.ref.collection('expenses').get()` (`claimShadow.ts:436`) and Phase C, a participant (expenses are OPEN-edit) **adds a new expense `x2`** to `e1`: `payerParticipantId:OWNER, amountFils:10000, splitMode:'exact', splitDistribution:{OWNER:5000, SHADOW:5000}`. `x2` is past enumeration → **never re-keyed**. Phase C deletes the SHADOW member doc + swaps `memberIds`.
- **Post-commit fold of `x2`:** `e1.participantIds` is now `[OWNER,CLAIMER]` → universe `{OWNER,CLAIMER}`. `x2.splitDistribution` keys SHADOW, mode `exact` → SHADOW ∈ `splitRecipientKeys`, but the member-gate (`:673-674`, `allMemberIds.has(uid) && !liveMemberIds.has(uid)`) requires SHADOW to still be a member doc — it was **deleted** → SHADOW ∉ `allMemberIds` → **dropped from the universe**. SHADOW is not a payer either.
- Owed-fold drops SHADOW's 5000 (`:428` `.has()` gate); only OWNER's 5000 is credited. `x2` nets OWNER `+5.000`, CLAIMER `0`. **5.000 OMR vanished; the bucket no longer sums to zero.** And `netHasUid(actualNet, SHADOW)` is **FALSE** — the member-gate hid the residue.

**Consequences that kill the two "obvious" fixes:**
- A "throw only if `netHasUid(net, shadow)`" guard **misses** this (residue hidden by the member-gate). `shadowSurvived` is false on exactly the corrupting case.
- A "throw if `actualNet` doesn't conserve (per-bucket-sum ≠ 0)" guard **false-throws** on honest #249 drops. Confirmed against **test 24**: an admin-shrunk custom split is an honest state where the net legitimately sums to `+8.000` (CLAUDE.md: the #249 conservation gap is *intentional* drop semantics). Absolute conservation would throw on a clean claim in any group carrying such a state — and **permanently block** it (retry re-throws). Unsafe.

---

## 2. The sound discriminant — a lingering-*shadow*-reference scan

The money-correctness invariant a finalized claim must satisfy: **the shadow uuid must not appear in any identity field the balance oracle reads.** That is exactly the set whose presence either (a) gives the shadow a live net position, or (b) causes the shadow's slice to be dropped (money vanish, hidden from `net`). Scan it directly on the live snapshot, **mode/scope-gated to mirror the oracle's identity reads exactly** (Gate R1 [P1-1]: an un-gated scan is a fail-safe *superset* — it never misses money, but it would spuriously throw `internal` on a balance-inert equally-mode `splitDistribution` residue the oracle ignores; gate it so the scan == the oracle's read set):

```ts
// Exported for test. Reads EXACTLY the identity fields computeNetFromSnapshot reads —
// the same gating as the oracle's universe build (groupNetBalance.ts:636-668):
//   • member.userId (liveMemberIds/allMemberIds)        — unconditional
//   • event.participantIds (universe seed)              — unconditional, live event
//   • expense.payerParticipantId (paid credit + financial fold :391/:636) — unconditional
//   • expense.customSplitParticipants  ONLY when scope === 'custom'  (oracle :663)
//   • expense.splitDistribution keys   ONLY when non-equally          (oracle :653-655)
//   • settlement payer/recipient (event + group, financial fold + adj) — unconditional, live
// Excludes balance-INERT fields (participantNames keys, createdBy, activity logs): a residue
// there loses no money and Phase B re-keys them best-effort (activity test 18 must not trip).
// LIVE docs only — the scan mirrors the oracle's NORMAL (non-delete-lock) scope, isLiveDoc
// (isDeleted===false). The oracle widens to include soft-deleted events ONLY under a delete
// lock (deletingInProgress===true → includeSoftDeletedSinceMs). The claim path refuses to
// START under a lock (Phase A throws not-found on deletingInProgress, claimShadow.ts:350), so
// the only way assertExactParity's reload sees a lock is an extreme claim-vs-deleteGroup race
// (lock acquired AFTER our Phase A); deleteGroup's finalizeGroupDeletion itself REFUSES to
// proceed on any non-zero balance (deleteGroup.ts:271), so a torn claim + a delete cannot both
// finalize. Aligning the scan with the delete-lock scope is therefore unnecessary. Use
// `isDeleted !== false` (NOT `!== true`) to stay byte-aligned with isLiveDoc — the #-trap.
export function snapshotReferencesShadow(snapshot: GroupBalanceSnapshot, shadowId: string): boolean {
  if (snapshot.members.some((m) => m.data.userId === shadowId)) return true;
  for (const ev of snapshot.events) {
    if (ev.data.isDeleted !== false) continue;
    if (asStringArray(ev.data.participantIds).includes(shadowId)) return true;
    for (const e of ev.expenses) {
      if (e.isDeleted !== false) continue;
      if (e.payerParticipantId === shadowId) return true;
      if (e.scope === 'custom'
          && asStringArray(e.customSplitParticipants).includes(shadowId)) return true;
      const nonEqually = e.splitMode === 'shares' || e.splitMode === 'exact' || e.splitMode === 'percent';
      const dist = e.splitDistribution;
      if (nonEqually && dist != null && typeof dist === 'object' && !Array.isArray(dist)
          && Object.prototype.hasOwnProperty.call(dist, shadowId)) return true;       // ← the BREAK-1 x2 case
    }
    for (const s of ev.settlements) {
      if (s.isDeleted !== false) continue;
      if (s.payerParticipantId === shadowId || s.recipientParticipantId === shadowId) return true;
    }
  }
  for (const s of snapshot.groupSettlements) {
    if (s.isDeleted !== false) continue;
    if (s.payerParticipantId === shadowId || s.recipientParticipantId === shadowId) return true;
  }
  return false;
}
```

Properties:
- **Catches BREAK-1** (`x2` is `exact` → non-equally → `splitDistribution[SHADOW]` → true) where `netHasUid` is blind.
- **Field set == the oracle's identity-read set** (now genuinely the dual of the Part-2 pre-scan `claimerInLiveEventSlot`, which gates the same two fields the same way, plus payer/settlements which the oracle reads unconditionally). No oracle identity input is under-scanned → **no money escapes**; no inert field is over-scanned → **no spurious throw** on equally-mode residue.
- **#249-robust** — honest admin-shrink drops reference *other* uids (claimer / departed members), never the shadow, so it never false-throws on the conservation gap.
- **No false-positive on a clean claim** — Phase B re-keys exactly these fields (`expenseRekey`/`settlementRekey`/Phase-B `participantIds`); a clean cascade leaves zero shadow refs.

---

## 3. The fix — two edits in `claimShadow.ts` (+ one helper, + a small refactor of `assertExactParity` to reuse one snapshot read)

### Edit A — `assertExactParity` (Hole 1): discriminate on reference-scan, demote mismatch to advisory

Replace the body. Load the snapshot **once** (was `recomputeNet`, which loads + computes; now `loadGroupBalanceSnapshot` + `computeNetFromSnapshot` + the scan — same single read):

```ts
async function assertExactParity(db, groupRef, simNet, shadowId, claimerUid): Promise<void> {
  const snapshot = await loadGroupBalanceSnapshot(db, groupRef);
  const shadowReferenced = snapshotReferencesShadow(snapshot, shadowId);
  const { net: actualNet } = computeNetFromSnapshot(snapshot);
  if (shadowReferenced) {                              // genuine corruption: torn cascade / concurrent shadow write
    logger.error('claimShadow parity FAILED — shadow still referenced in a balance field post-commit', {
      groupId: groupRef.id, shadowId, claimerUid, shadowReferenced,
    });
    throw new HttpsError('internal', 'Claim produced an inconsistent balance and was not finalized.');
  }
  const mismatch = netMismatch(simNet, actualNet);
  if (mismatch != null) {                              // shadow gone + drift ⇒ benign concurrent edit
    logger.warn('claimShadow parity drifted post-commit (concurrent edit; actualNet authoritative)', {
      groupId: groupRef.id, shadowId, claimerUid, mismatch,
    });
  }
}
```

Why blessing a `mismatch` (shadow-gone) is safe: the only corruption mechanisms are (1) money-vanish via a dropped shadow slice — requires a shadow reference → excluded by the scan; (2) divisor-collapse merging the claimer's *pre-existing* distinct slot — caught by the Part-2 pre-scan at snapshot, and a concurrent edit cannot retroactively give a brand-new claimer a prior distinct balance; (3) a genuine concurrent edit → `actualNet` is the deterministic live oracle truth → authoritative. A shadow-gone mismatch is therefore always an authoritative reallocation, never a vanish/create.

### Edit B — idempotent Phase-A return (Hole 2): scan the already-loaded snapshot (zero extra reads)

At `claimShadow.ts:357-364`, the snapshot is **already in scope** (loaded `:347`). Add the scan before returning:

```ts
if (shadowMembers.length === 0) {
  if (snapshotReferencesShadow(snapshot, shadowMemberId)) {
    logger.error('claimShadow idempotent path: shadow still referenced in a balance field despite no member doc — prior cascade torn', {
      groupId, shadowMemberId, claimerUid,
    });
    throw new HttpsError('internal', 'A prior claim left an inconsistent balance and was not finalized.');
  }
  return { groupId, shadowMemberId, claimerUid, alreadyClaimed: true };
}
```

A clean double-claim (tests 6, 16) leaves zero shadow refs → `alreadyClaimed` unchanged. A torn prior cascade (shadow doc gone, but a live doc still keys the shadow) throws loudly instead of blessing. **Convergence note:** this surfaces a torn state for retry/operator; it does **not** self-heal (the engine only re-keys when the shadow member doc exists — Phase A). That is correct and matches the issue's candidate (2): stop the *silent* bless; loud surfacing + a future reaper (cf. `deleteGroupLockReaper`) is the recovery path. Out of scope here.

### Edit C — second idempotent return (`:511-513`, Phase-C-already-retired): scan a fresh snapshot

Gate R1 [P1-2] corrected my false rationale: `decideClaimRequest` does **not** serialize two *different* requests for one shadow — its CAS (`decideClaimRequest.ts:76-101`) serializes each request's *own* `pending→` transition only, and `:124-128` explicitly contemplates "two requesters can each hold a pending request for one shadow." So a creator double-approve runs two engines on one shadow concurrently; the Phase-C-race loser hits `:511` (`retired===false`) and returns `{alreadyClaimed:true}` **before** any verification — a third silent-bless path. `:511` is only ever reached under concurrency (a single-threaded engine that passed Phase A always retires). Add the same scan (fresh read — the Phase-A snapshot is stale post-Phase-B):

```ts
if (!retired) {
  const fresh = await loadGroupBalanceSnapshot(db, groupRef);
  if (snapshotReferencesShadow(fresh, shadowMemberId)) {
    logger.error('claimShadow Phase-C-already-retired path: shadow still referenced — torn cascade', {
      groupId, shadowMemberId, claimerUid,
    });
    throw new HttpsError('internal', 'A prior claim left an inconsistent balance and was not finalized.');
  }
  return { groupId, shadowMemberId, claimerUid, alreadyClaimed: true };
}
```

**Honest residual (NOT closed here):** in a true two-engine race both engines re-key the shadow *away* (onto claimer-A and claimer-B respectively, last-writer-per-doc), so the result is a claimer-A/claimer-B torn mix with **no surviving shadow reference** — the scan passes and still blesses it. The shadow-reference scan is the wrong tool for that; the real fix is a per-shadow lock (cf. `deleteGroupLockReaper`) or engine-level idempotency under concurrency. **Filed as a follow-up** (linked from the PR); out of scope for #558, which is the single-claim TOCTOU + idempotent-retry. Edit C still strictly improves `:511` (catches a torn *shadow* residue that the current code blesses). **Loud-surfacing note (Gate R2 [P2]):** for that no-shadow-ref two-engine torn mix, today's success-path assert *accidentally* `throw internal`s (its `mismatch != null` arm), whereas Edit A demotes it to `logger.warn`+resolve (shadow gone, no ref). This is a small loss of accidental loud-surfacing on that race — accepted: the current throw is unreliable and doesn't heal (re-approve → `:511` → `decideClaimRequest` declines), the warn still carries the `mismatch` payload, and the per-shadow-lock follow-up is the real fix.

### Helper + export prerequisite (Gate R1 [P2-3])

Add `snapshotReferencesShadow` (§2). First, as a no-behavior step, `export` it **and** `assertExactParity` **and** `simulateClaim` from `claimShadow.ts` (currently only `claimShadowEngine` + `ClaimShadowOutput` are exported) so the tests can import them; then write the RED tests against the current bodies.

### Considered & deferred
- **No transactional fold / pre-commit re-validation** — PR7 rejected it (tx read budget / breaks `BatchWriter`'s >500-write scaling); the residual concurrent-edit window stays (a *correct*-but-flagged claim self-corrects on retry).
- **No rollback** — impossible post-commit, unnecessary (a shadow-gone result is authoritative; a referenced result is surfaced for retry).
- **No oracle / drop-semantics / universe / pre-scan / rules change** (CLAUDE.md lock-step, non-negotiable).

---

## 4. Tests (RED-first) — all in `test/callables/claimShadow.test.ts` (no module mock; uses exported seams)

Import `assertExactParity`, `snapshotReferencesShadow`, `simulateClaim`. A TOCTOU is modeled by a `simNet` (pre-state) disagreeing with the seeded live (post-state) Firestore — exactly what the backstop sees. The clean behavioral RED→GREEN tests are **T29** (Hole 1 false-reject) and **T30** (Hole 2 bless); the pure-function units (**U1–U6**) are RED because the functions/exports don't exist yet.

- **U1–U6 — `snapshotReferencesShadow` + `simulateClaim` pure units** (no Firestore; build `GroupBalanceSnapshot` literals):
  - (U1) live **non-equally** expense `splitDistribution[SHADOW]` → true **and** `netHasUid(computeNetFromSnapshot(snap).net, SHADOW)===false` (pins the soundness core / Defect-C: the net hides the residue, the scan does not).
  - (U2) live `participantIds` / `payer` / `customSplit`(scope custom) / event-settlement / **group-settlement** party each → true (keep the group-settlement case — the test-22 axis).
  - (U3) member `userId===SHADOW` → true.
  - (U4) clean snapshot → false.
  - (U5) **soft-deleted**-only shadow ref → false (live-only).
  - (U5b) **equally-mode** expense whose `splitDistribution` keys SHADOW but SHADOW ∉ participantIds → **false** (the [P1-1] gate: oracle ignores equally-mode `splitDistribution`, so this is balance-inert and must NOT throw); same for a **non-custom** scope `customSplitParticipants[SHADOW]` → false.
  - (U6 — sim-fidelity, Gate R1 [P2-2]) `simulateClaim` over the test-26 remainder-hop fixture (3-way equally, non-divisible, shadow alphabetically-last pre-claim) → `computeNetFromSnapshot(simulateClaim(snap, SHADOW, CLAIMER)).net` equals the expected post-claim net (claimer −3.333, owner absorbs the relocated remainder). Pins sim fidelity **independently** of the now-advisory post-commit `mismatch` (which no longer throws on a sim drift).

- **T28 — `★[#558] genuine corruption (shadow-referenced post-commit) → assertExactParity THROWS (not warn-blessed)`** — soundness guard against the tempting "demote mismatch→warn" simplification. Seed the *post-commit* live state: shadow member doc absent, `memberIds=[OWNER,CLAIMER]`, `e1.participantIds=[OWNER,CLAIMER]`, a live `x2` `exact {OWNER:5000, SHADOW:5000}` (the BREAK-1 residue). Build `simNet` from a clean pre-state (no `x2`). `await expect(assertExactParity(db, ref, simNet, SHADOW, CLAIMER)).rejects.toMatchObject({code:'internal'})` + assert the `logger.error` payload carries `shadowReferenced:true`. **Honest note (Gate R1 [P2-1]):** current code *also* throws here (via the mismatch arm), so the behavioral RED is weak — the strong soundness pin is **U1** (`scan===true` while `netHasUid===false`, a pure RED) and the guard value of T28 is against a *naive* warn-only fix (which would resolve). The `shadowReferenced:true` payload assertion is the RED-against-current discriminator.

- **T29 — `★[#558] benign concurrent edit (shadow gone, net conserves) → assertExactParity RESOLVES`** — Hole 1's headline RED. Seed a live conserving 3-way post-state: shadow gone, `e1.participantIds=[OWNER,CLAIMER,dave]` (+ `dave` member doc + memberIds), `x1` 12.000 equally → OWNER +8, CLAIMER −4, dave −4. Build a 2-way `simNet` (pre-edit: OWNER +6, CLAIMER −6). `await expect(assertExactParity(...)).resolves.toBeUndefined()`. (RED on current: `netMismatch` ≠ null → throws `internal`. GREEN after: no shadow ref → warn, resolve.)

- **T30 — `★[#558] idempotent retry on a torn (shadow-referenced) cascade → engine THROWS, not alreadyClaimed-bless`** — Hole 2's headline RED. Seed the torn end-state via Admin writes: no shadow member doc + shadow ∉ memberIds (→ `:357` idempotent branch), `e1.participantIds=[OWNER,CLAIMER]`, an un-re-keyed live `x1` `exact {OWNER:6000, SHADOW:6000}` (shadow slice mis-keyed; member-gate drops it → net loses 6.000; `netHasUid(net,SHADOW)===false`). `await expect(call({groupId:'g', shadowMemberId:SHADOW, claimerUid:CLAIMER})).rejects.toMatchObject({code:'internal'})`; also assert `netHasUid(...,SHADOW)===false` to document why `netHasUid` was rejected. (RED on current: returns `{alreadyClaimed:true}`. GREEN after: scan true → throws.)

- **T31 — `★[#558] clean idempotent double-claim still returns alreadyClaimed (no false-throw)`** — regression guard that Edit B doesn't break tests 6/16's contract: a clean prior claim (no shadow refs) → `{alreadyClaimed:true}`. (`:511`/Edit C is guarded by the same unit-tested helper; a deterministic `:511` integration test needs a two-engine race and is impractical in the emulator — covered by the U-tests + the trivial wiring.)

Existing 4–27 stay green: none seed a concurrent edit, so post-commit `actualNet == simNet` and no shadow ref → neither branch fires; 6/16 hit Edit B's scan on a clean state → `alreadyClaimed`. Tests 26/26b (sim-fidelity) still assert the committed nets directly (the money), independent of the now-advisory `mismatch`; update their comment to note the post-commit assert no longer throws on a pure-relabel drift (the sim-fidelity tripwire moved to **U6** + the pre-commit `:405 netHasUid(simNet, shadow)` sanity).

Run: `cd functions && RIHLA_FIREBASE_EMULATOR_TEST_COMMAND="npx --yes node@22 node_modules/jest/bin/jest.js --runInBand test/callables/claimShadow.test.ts" npm run test:emulator`.

---

## 5. The 7 verification principles

1. **Classify callsites.** `assertExactParity` is the post-commit backstop (INBOUND — reads live, throws/warns, no write). The idempotent return is a control-flow gate (no write). `snapshotReferencesShadow` is a pure predicate (read-only). No OUTBOUND/write surface added — the fix never writes.
2. **Verify claims against code.** `claimShadow.ts:347` loads the snapshot; `:357-364` Phase-A idempotent return; `:436` Phase-B per-event expense enumeration; `:449` flush; `:452-509` Phase C (shadow member doc deleted `:500-506`, memberIds swap `:507`); `:516` assertExactParity. Oracle member-gate `groupNetBalance.ts:673-674`; owed-drop `:428`. All re-checked this session.
3. **Trace one read-path per write-path.** The fix adds NO write-path. The read it adds (`snapshotReferencesShadow`) is consumed only by the throw/warn decision in the same function; Edit B reuses the Phase-A snapshot (no new read). Hole 1's read replaces `recomputeNet` with `loadGroupBalanceSnapshot`+`computeNetFromSnapshot` (identical I/O, one snapshot).
4. **Enumerate fields from the type.** `GroupBalanceSnapshot` (`groupNetBalance.ts:519-531`): `groupExists, groupData, members[{docId,data}], events[{id,ref,data,expenses[],settlements[]}], groupSettlements[]`. The scan reads exactly the oracle's identity inputs: member `userId`; event `participantIds`; expense `payerParticipantId`/`customSplitParticipants`/`splitDistribution` keys; settlement `payerParticipantId`/`recipientParticipantId` (event + group). It deliberately omits `participantNames`/`createdBy`/`activity_logs` (display/best-effort/inert) — enumerated against the re-key set in `expenseRekey`/`settlementRekey`/Phase B.
5. **Data contracts.** `assertExactParity(db, groupRef, simNet, shadowId, claimerUid)` signature unchanged. `snapshotReferencesShadow(snapshot, shadowId): boolean`. Throw contract unchanged (`HttpsError('internal', …)`), so `decideClaimRequest`'s `internal`-is-retryable handling (`:108-117`) and `alreadyClaimed` handling (`:134-150`) are untouched and still correct.
6. **Arithmetic decomposition.** The fix asserts a STRUCTURAL invariant (shadow-absence from identity fields), not a net equality — so it sidesteps the conservation-decomposition trap (the #249 gap means `bucket-sum != 0` is a valid honest state; absolute conservation would be wrong, §1a). `actualNet` is used only for the advisory `mismatch`, never as a correctness gate.
7. **Adversarial orthogonal axis.** The fix is on the *reference/identity* axis; the worked tests exercise the *money-flow* axis (T28 expense add — vanish; T30 mis-keyed exact slice — vanish) **and** the *settlement* axis (U2 settlement party). The benign axis (T29 honest participant add — authoritative reallocation) proves no false-reject. Multi-currency: the scan is currency-blind (identity only) so it is correct per-currency by construction.

---

## 6. Gate checklist (R2 — post R1 [P1]/[P2] fixes)
- [ ] Reference-scan is the throw discriminant (not `netHasUid`/conservation); §1a proves both alternatives unsound.
- [ ] `snapshotReferencesShadow` field set == the oracle's identity-read set, **mode/scope-gated to match** (R1 [P1-1]): `splitDistribution` only non-equally, `customSplitParticipants` only custom scope, payer/settlements unconditional. LIVE-only (`isDeleted !== false`), excludes inert fields → no money under-scanned, no spurious throw on inert residue, no #249/test-18 false-positive. Pinned by U1/U5b.
- [ ] Hole 1 demotes `mismatch`→warn ONLY when shadow is absent; §3 proves shadow-gone-mismatch is always authoritative.
- [ ] Hole 2 (`:357`) reuses the Phase-A snapshot (zero extra reads); throws on torn, `alreadyClaimed` on clean.
- [ ] **Edit C (`:511`)** scans a fresh snapshot (R1 [P1-2]: the two-request-per-shadow race is reachable — `decideClaimRequest` does NOT serialize it); the two-engine claimer-A/B torn-mix residual is honestly out-of-scope → **follow-up filed**.
- [ ] Sim-fidelity moved to U6 (`simulateClaim` direct unit) since `mismatch` no longer throws (R1 [P2-2]).
- [ ] Exports added as a no-behavior first step: `assertExactParity`, `snapshotReferencesShadow`, `simulateClaim` (R1 [P2-3]).
- [ ] RED-first: T29 (resolve) + T30 (throw) fail on current code; U1/U5b/U6 are pure RED; T28 pins the warn-not-bless soundness (weak behavioral RED acknowledged).
- [ ] No oracle/rules/client/`decideClaimRequest` change; diff confined to `claimShadow.ts` + its test.
