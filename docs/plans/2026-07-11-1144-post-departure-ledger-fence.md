# #1144 Post-Departure Ledger Integrity — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make the leave/remove exact-zero departure invariant durable — no write may create or move a departed party's balance after (or concurrently with) their departure.

**Architecture:** Two independent mechanisms, two PRs. **PR1 (departure fence, failure mode B):** `leaveGroup`/`removeMember` adopt `deleteGroup`'s existing lock pattern — acquire a `departureInProgress` group-doc lock transactionally, run `recomputeNet` *under* the lock, mutate-and-clear in one final transaction; the lock joins `groupAllowsClientWrites` (rules) and every Admin writer's quiesce checklist; a stale-lock reaper mirrors `deleteGroupLockReaper`. **PR2 (current-party policy, failure mode A):** rules gate the *parties* of new/edited expense allocations and event settlements to current `group.memberIds` (shadow uuids included), with a tombstoned-identity carve-out for settlements (deleteAccount departs without a zero-gate; its residual debt must stay settleable); `correctSettlement`/`correctLogicalSettleUp` mirror the same policy server-side. **The balance oracle is untouched on both sides** — no universe change, no participantIds pruning, no migration (issue decision 5; preserves client↔server parity and the claimShadow lock-step contract at `groupNetBalance.ts:586-591`).

**Tech Stack:** Firestore security rules, Cloud Functions (TS, Node 22), Jest + rules-unit-testing under the emulator (`npm run test:emulator`).

**Verified against:** `origin/main` @ `e49daf7d` (post-#1131 `c36d0533`, #1132 `b566cd62`, #1143). Every line reference below re-verified in this worktree.

---

## 1. Problem (verified)

**B — zero-check-to-removal race.** `leaveGroup.ts:99` and `removeMember.ts:139` run `recomputeNet` (the shared oracle) *before* their membership transaction (`leaveGroup.ts:124`, `removeMember.ts:164`). The transaction re-reads only quiesce flags + membership/authz — never the balance. Their own comments say "No separate mutation lock" (`leaveGroup.ts:25`, `removeMember.ts:35`). Any balance-input write committing in the gap departs a member at non-zero. Contrast `deleteGroup.ts`: `acquireDeleteGroupLock` (L121) sets `deletingInProgress`+`deleteLockedAt`+`deleteLockedBy` transactionally *before* its `recomputeNet` at L275 — leave/remove are the only two heavy oracle-input writers without this pattern.

**A — departed parties remain write-eligible.** Post-#1131/#1132 the *writer* of every money path must be a current member, but the *parties* need only be event participants, and `participantIds` are never pruned on departure:
- Expense payer: `data.payerParticipantId in participants()` (`firestore.rules:788`); split keys: `splitDistribution.keys().hasOnly(participants())` (L700-701); custom: `customSplitParticipants.hasOnly(participants())` (L794).
- Event settlement parties: both `in participants()` (L954-955), explicitly documented as allowing departed parties (#752 comment, L975-977) — a judgment this issue revisits.
- `correctSettlement.ts:140-149` / `correctLogicalSettleUp.ts:151-161` (Admin SDK): event-scope correction parties checked against event `participantIds` only.
- Group settlements are the existing counter-precedent: parties gated to `groupData(groupId).memberIds` (L1225-1226).

**Already closed — narrower than the issue text implies (verified first-hand):** `validEventBase` runs on *every* light+admin event update (via `validEventUpdateCommon`, L571-577) and unconditionally requires `data.participantIds.hasOnly(groupMembers())` (L474). With additive-only rosters (`hasAll`, L600-601), an event whose roster contains a departed member is **already frozen for all light/admin updates** — no roster injection, no roster-driven redistribution, no event soft-delete, post-departure. The issue's "Carol adds Bob to E1" scenario is therefore only a *pre-departure race* (PR1's fence closes it), not a steady-state hole. The only event-update branch that skips `validEventBase` is `validEventCloseToggle` (L660-681, `isClosed` triple only — not an oracle input); a reopened departed-roster event accepts new expense writes, which PR2's party policy then gates.

## 2. Dependency matrix — oracle inputs × writers (acceptance box 3)

Oracle reads (`loadGroupBalanceSnapshot`, `groupNetBalance.ts:552-582`; pure compute L592-741). Client mirror `computeGroupBalances`/`eventBalanceUniverse` (`group_balance_provider.dart:322-546`, `expense_provider.dart:106-151`) reads the same inputs via streams; parity pinned.

| Input (collection.field) | Effect on net | Client writers (rules path) | Server/Admin writers |
|---|---|---|---|
| `groups/{gid}`.`deletingInProgress`,`deleteLockedAt` | delete-resume event scope | — (rules deny roster/flag writes; `validMemberIdsRefresh` L397-403 forbids memberIds change) | `deleteGroup`, reapers |
| `members/*`.`userId`,`isTombstone` | `liveMemberIds`/`allMemberIds` → universe fold gates | member create (`validMemberCreate` L1040), self-rename (no oracle fields), member delete (L1089, rides Admin roster update) | `joinGroupByInviteCode`, `addShadowMember`, `claimShadowEngine`, `deleteAccount` (tombstones), `leaveGroup`/`removeMember` (hard-delete) |
| `events/*`.`participantIds` | universe seed + equal-split divisor | event create (`hasOnly(groupMembers())` L562); light/admin update (additive, `hasOnly(groupMembers())` via L474) | join/addShadow fan-in (`eventFanIn.ts:109-112`, arrayUnion), `claimShadowEngine` re-key |
| `events/*`.`isDeleted`,`deletedAt` | event in/out of aggregation | admin update (soft-delete branch L625-629; frozen for departed-roster events via L474) | `deleteGroup` cascade |
| `expenses/*`.`payerParticipantId`,`amountFils`,`currency`,`scope`,`customSplitParticipants`,`splitMode`,`splitDistribution`,`isDeleted` | paid/owed folds | expense create/update/soft-delete (`validExpenseCreate` L807, `validExpenseUpdate` L864, soft-delete OR-branch L920-925) | `claimShadowEngine` re-key, `deleteAccount` scrub (`claimRekeyAt`/`deleteAccountScrubAt` markers) |
| `events/*/settlements/*`.`payerParticipantId`,`recipientParticipantId`,`amountFils`,`currency`,`isDeleted` | adj folds (event universe) | event-settlement create (`validEventSettlementCreate` L965; update/delete `if false`) | `correctSettlement`, `correctLogicalSettleUp` (reverse rows), `claimShadowEngine` re-key |
| `groups/{gid}/settlements/*` (same fields) | global fold, no universe gate | group-settlement create (`validGroupSettlementCreate` L1239; parties already `in memberIds` L1225-1226) | `correctSettlement`, `correctLogicalSettleUp`, `claimShadowEngine` re-key |

Non-writers (verified): `balanceAggregator` (display cache only, skips on quiesce flags `:75-84`), `expenseAuditLogger` (activity only), `balanceReconciler` (cache), `requestClaimShadow` (claimRequests doc only), `groupNetBalance.ts` (pure read).

Quiesce infrastructure today: `groupAllowsClientWrites` (rules L140-149, four absent-or-false flags) reached by every oracle-input client path (directly, or via `eventAllowsClientWrites` L195 / `eventAcceptsExpenseWrites` L213); each Admin writer mirrors the same four flags in code. `leaveGroup`/`removeMember` **read** the flags but **set none** — the concrete B hole.

## 3. Design decisions

**D1 — Fence = fifth quiesce flag, `deleteGroup` lock pattern (PR1).** Group-doc fields `departureInProgress: bool`, `departureLockedAt: Timestamp`, `departureLockedBy: string` (actor uid). Acquire transactionally (refuse if any of the existing four flags, or a live departure lock); `recomputeNet` under the lock; final transaction verifies the lock is *ours* (`timestampMillis(departureLockedAt)` equality) and clears it atomically with the membership mutation. Failure paths clear own-invocation-only (mirror `clearDeleteGroupLockForFailure` semantics: a concurrent observer never clears a peer's live lock). Crash → lock lingers → new hourly `departureLockReaper` clears stale locks (unlike deleteGroup's reaper there is nothing to *resume*: mutation and clear are atomic, so a lingering lock proves the mutation never committed — clearing is always safe).
*Soundness:* any oracle-input write committed before the lock-set is visible to the under-lock recompute (Firestore strong consistency); any attempt after is denied — client via rules, Admin via honor-checks. Both commit orderings are safe.
*Rejected — recompute inside the membership transaction:* the snapshot read is unbounded in group history (every event × expenses × settlements), turning any concurrent unrelated ledger write into transaction contention, and gives no protection against Admin writers that don't share the transaction. The flag matches five shipped precedents.
*Rejected — `ledgerRevision` counter echoed by every writer:* every client money write would need a batched group-doc bump (contention hotspot + batch-budget cost on every write) — strictly worse than a rare short freeze.

**D2 — Coarse freeze via `groupAllowsClientWrites`, not per-surface.** One absent-or-false clause covers every client oracle-input path (plus member/activity/meta writes — over-blocking for a sub-second-to-seconds window, matching `claimingInProgress` semantics exactly). Offline replays landing in the window are denied and silently dropped — the documented, accepted posture (#1131 plan §7; CLAUDE.md #929 note). Budget risk is the event update OR-chain (#723, near-ceiling): the clause adds ~4 expressions to paths that already call `groupAllowsClientWrites`; Task 1.2 mandates the emulator run as the verdict, with the #1134 ceiling-analysis fallback (inline/reorder) if any test reports `maximum of 1000 expressions`.

**D3 — Admin honor-checks: acquire-time mutual exclusion.** Add `departureInProgress === true` to the existing flag checklists at: `joinGroupByInviteCode.ts:231-238`, `addShadowMember.ts:71-77`, `decideClaimRequest.ts` lock acquire (~L211-289), `deleteAccount.ts` lock acquire (~L383-414), `deleteGroup.ts:161-163` + `finalizeGroupDeletion` L271-273, `correctSettlement.ts:85-92`, `correctLogicalSettleUp.ts:95-101`, `requestClaimShadow.ts:75-82` (defense-only), and `balanceAggregator.ts:75-84`+`:145-154` skip set (display-only; `balanceReconciler` self-heals staleness). Each site throws whatever it already throws for `claimingInProgress` (site-local consistency). Reapers need no cross-checks: a resumed cascade holds a lock that *predates* any departure lock (each side's acquire refuses while the other's flag is up), so overlap is impossible by construction — but `departureLockReaper` must skip groups holding one of the other three locks, mirroring `deleteGroupLockReaper`'s freeze-respect (its L99 pattern).

**D4 — Party policy: current members only, for allocation-bearing expense writes (PR2).** New rules fn `expensePartiesAreCurrentMembers(data)` (complete code in Task 2.2): payer ∈ `groupMembers()`, `customSplitParticipants`/`splitDistribution` keys ⊆ `groupMembers()`, and — because equal/global/sub_group/custom-empty splits divide over the roster-seeded universe (`allocateExpenseOwed`, `expense_provider.dart:430-446`; server L425-434) — roster-derived writes additionally require `participants().hasOnly(groupMembers())`. Applied at: create (always), update (only when `affectsExpenseAllocation()` — on **both** post-state and pre-state, so an edit can neither introduce a departed party nor change a doc that already references one), soft-delete (pre-state — removing a departed party's expense from aggregation moves their net). **Metadata-only edits stay untouched** (acceptance box 2): the fn is diff-gated behind the existing allocation/soft-delete branches, never in the unconditional `validExpenseBase`. All referenced docs (group, event) are already fetched on these paths — zero new document accesses (#929-safe), moderate expression cost (Task D headroom assessment; emulator is the verdict).
*Why memberIds is the right set:* shadow uuids are arrayUnion'd into `memberIds` (`addShadowMember.ts:136`) — shadow expenses keep working.

**D5 — Event-settlement parties: current member OR tombstoned identity.** `deleteAccount` tombstones member docs *without* a zero-gate — departed-with-debt identities exist by design, and event settlements against them are the sanctioned cleanup path (the #752/#249 comment's true core). Leave/remove-departed parties passed the exact-zero gate with member docs hard-deleted — any settlement naming them *creates* exposure, so blocking them strands nothing. New rules fn `isSettleableParty(partyId)`: `partyId in groupMembers() || (exists(members/$(partyId)) && get(...).isTombstone == true)`. The `||` short-circuits: live parties cost zero extra accesses (decomposed settle-up batch keeps its `2·N+1 ≤ 20`, N=9 — the #752 client pre-gate guarantees both parties live on that path); the tombstone case costs 1 extra access per departed party on a single write (10-access budget, fine). Doc-id lookup is sound for every identity class that can be tombstoned today: uid-keyed real users (post-#524) and uuid-keyed shadows both key member docs by the same id used as a party id; legacy pre-#524 uuid-keyed real-user docs are the one miss — none exist in prod (no real users). Group settlements keep their existing stricter `memberIds` gate (loosening it is a separate decision; group-scope tombstoned debt is residual R3).
*Rejected — parties ∈ memberIds, period:* strands tombstoned debt; the counterparty could then never zero out and never leave.
*Rejected — free departed-party settlements (status quo):* any member can mint arbitrary exposure for a zero-departed ghost — the issue's core complaint.

**D6 — `correctSettlement`/`correctLogicalSettleUp` mirror D5 server-side.** Event-scope corrections add: each party current (`memberIds.includes`) or tombstoned (Admin query `members.where('userId','==',party)` → any doc `isTombstone === true` — field-match, keying-agnostic, strictly better than the rules approximation). Rationale: a leave/remove-departed party's zero-gate folded the settlement being corrected; reversing it post-departure breaks the invariant. Tombstoned corrections stay possible (cleanup path). Both callables also gain the D3 fence check.

**D7 — Oracle, universe, and drill-down untouched.** No change to `computeNetFromSnapshot`, `eventBalanceUniverse`, participantIds semantics, or any historical document. Parity tests stay byte-identical; the claimShadow footprint pre-scan contract (`groupNetBalance.ts:586-591`) is not triggered.

**D8 — Client UX mirroring is a named follow-up, not part of PR1/PR2.** Rules are the boundary; the pickers/settle screens offering departed parties (event settle-up has no membership pre-gate — `settle_up_screen.dart:375-376` gates only the writer) will surface `permission-denied` snackbars until mirrored. Pre-launch, no real users; filed at ship time (see §5). This keeps PR2 reviewable and keeps money-policy and UX concerns in separate PRs.

## 4. Deliberately unchanged (do not "fix" while in here)

- `participantIds` never pruned; departed identities stay in the balance universe (#249 conservation; issue decision 5).
- Event light-update writer gate (`requesterIsParticipant`, L588) — #1135's axis, tracked there. **Evidence for #1135 triage** (surfaced, not acted on): a departed writer is by definition on the roster, so every light/admin update they attempt already fails `validEventBase`'s `hasOnly(groupMembers())` (L474) — #1135's vandalism/injection surface appears already closed on `main`; recommend re-verifying and re-scoping that issue.
- Group-settlement party gate (L1225-1226) — already correct; not loosened for tombstones (R3).
- The #929 `kMaxDecomposeLegsAtomic = 9` carve-out and the single-group-write fallback path.
- `validEventCloseToggle` skipping `validEventBase` (#723 budget) — safe once PR2 gates expense creates.
- deleteAccount's no-zero-gate tombstone departure (deliberate: account deletion can't be hostage to debt).

## 5. Residual risks → follow-up issues (file at ship time)

- **R1 (acceptance box 1, narrow carve-out):** a departed *universe-only* actor (ex-payer/settlement-party who was never an event participant — paid-on-behalf, then left) still gains/loses share from a new roster-derived expense or an event soft-delete on that event: rules cannot see subcollections, so `participants().hasOnly(groupMembers())` cannot detect them. Requires paid-on-behalf history + departure — rare. Follow-up options: trigger-stamped event-level "has departed financial history" marker, or server-authoritative expense creates for flagged events. PR2 therefore carries `Refs #1144`; the issue stays open re-scoped to R1 after merge.
- **R2:** tombstoned-party settlements can overshoot zero (direction/magnitude unenforceable in rules) — bounded to deleteAccount ghosts, append-only, correctable, author is a current member. Accepted; documented in SECURITY-RULES.md.
- **R3:** group-scope tombstoned debt has no client settle path (pre-existing; parties gate L1225-1226). Not worsened by this change.
- **R4:** stuck departure lock write-freezes the group up to the reaper interval (~1h) — same failure mode and remedy as the three existing locks.

---

# PR1 — Departure fence (`Refs #1144`, branch `fix/1144-departure-fence`)

### Task 1.1: RED — rules deny oracle-input writes while `departureInProgress`

**Files:** Modify: `functions/test/firestore-rules-publish-readiness.test.ts` (append nested `describe('#1144 departure fence quiesces client writes', ...)` following the #1131/#1132 describe pattern).

Cases (all with a seeded group where `departureInProgress: true`, `departureLockedAt: Timestamp.now()`, `departureLockedBy: '<uid>'`; writer is a current member who passes every other gate):
1. expense create → denied; 2. expense metadata update → denied; 3. event-settlement create → denied; 4. group-settlement create → denied; 5. event light update (rename) → denied; 6. member self-rename → denied; 7. control: same six writes with `departureInProgress: false` → allowed (reuse existing fixtures). Run: `cd functions && npm run test:emulator -- firestore-rules-publish-readiness.test.ts -t "#1144 departure fence"` — expect the deny cases to FAIL (writes currently allowed). Paste the RED output into the PR body (#329).

### Task 1.2: GREEN — fifth clause in `groupAllowsClientWrites`

**Files:** Modify: `security/firestore.rules:140-149`.

```
&& (!groupData(groupId).keys().hasAny(['departureInProgress'])
  || groupData(groupId).departureInProgress == false);
```

Re-run Task 1.1 (green), then the FULL rules suites: `firestore-rules-publish-readiness.test.ts`, `firestore-rules-cut-modules.test.ts`, `settlementIdempotency.rules.test.ts`, `decomposed-settleup-batch.test.ts`. **Any previously-green test failing with `maximum of 1000 expressions` is the #723 ceiling** — mitigate per the #1134 template (reorder cheap term first / inline) — reduce expressions, don't chase test logic. Commit: `test+fix(rules): #1144 departure fence flag quiesces client writes (Refs #1144)`.

### Task 1.3: RED — callable race + lock-lifecycle tests

**Files:** Create: `functions/test/callables/departureFence.test.ts` (template: `functions/test/callables/memberRemovalDeleteLockRace.test.ts` — its `jest.mock('../../src/callables/groupNetBalance')` + per-test `mockMutateGroup` injection at the recompute call site is the deterministic mid-gap hook).

Both callables (`leaveGroup`, `removeMember`), both commit orderings:
1. **Write-before-fence:** seed the leaver at non-zero *before* calling → `failed-precondition`, memberIds/member doc/activity unchanged (exists today — keep as regression).
2. **Write-in-gap (the bug):** real `recomputeNet`; the injection hook fires *at the recompute call site* and writes a settlement flipping the leaver non-zero, simulating a commit landing mid-window. RED expectation post-fix: the callable must either see the write (recompute under lock) or the final transaction must abort — the member must NOT be removed while netting non-zero. Currently FAILS: member is removed non-zero. Also assert the hook observes `departureInProgress == true` on the group doc at recompute time (proves lock-before-recompute ordering).
3. **Lock lifecycle:** cleared after success (all three fields); cleared after zero-gate refusal; cleared when recompute throws; mutual exclusion (second leave/remove while lock held → `failed-precondition`, no mutation).
4. **Roster/event orderings (acceptance):** pre-fence event-roster add (target added to an event, redistributing an equal split) → recompute under lock sees it → refused if non-zero; pre-fence event soft-delete likewise.

Run: `cd functions && npm run test:emulator -- departureFence.test.ts` — expect FAIL (no lock exists). Commit RED.

### Task 1.4: GREEN — shared lock helper + callable restructure

**Files:** Create: `functions/src/callables/shared/departureLock.ts`. Modify: `functions/src/callables/leaveGroup.ts`, `removeMember.ts`.

`departureLock.ts` (mirror `deleteGroup.ts:121-216` shapes):
- `acquireDepartureLock(db, groupRef, uid)` — transaction: group must exist and pass the existing four-flag check (`not-found`, matching leave/remove's current semantics); `departureInProgress === true` → `failed-precondition` ("Another membership change is in progress. Try again."); else set the triple + `updatedAt`, return `{ lockedAtMs }`.
- `clearDepartureLock(db, groupRef, lockedAtMs)` — transaction: clear the triple **only if** `timestampMillis(departureLockedAt) === lockedAtMs` (own-invocation-only; a peer's live lock is never cleared).

Callable flow (both files; keep the existing pre-reads and the lock-free idempotent short-circuit):
1. existing pre-checks/authz → 2. `acquireDepartureLock` → 3. `try { recomputeNet; zero-gate } catch/refusal { clearDepartureLock; rethrow }` → 4. final transaction: re-read group; verify quiesce flags AND `departureInProgress === true && timestampMillis(departureLockedAt) === lockedAtMs` (else `aborted` — lock reaped mid-flight); removeMember re-verifies #1132 authz (keep L178-185); perform the existing mutation **plus clear the lock triple in the same `tx.update`**; the `alreadyLeft/alreadyRemoved` in-txn branch also clears before returning → 5. any throw after acquire → `clearDepartureLock` in a `finally`-style guard (only when the mutation txn did not commit).

Re-run Task 1.3 (green) + `leaveGroup.test.ts`, `removeMember.test.ts`, `memberRemovalDeleteLockRace.test.ts`. Commit: `fix(functions): #1144 leave/remove acquire a departure lock across the zero-check (Refs #1144)`.

### Task 1.5: Admin honor-checks (RED per site, then GREEN)

**Files:** Modify the nine D3 sites + their test files (`joinGroupByInviteCode.test.ts`, `addShadowMember.test.ts`, `claimRequest.test.ts`, `deleteAccount.test.ts`, `deleteGroup.test.ts`, `correctSettlement.test.ts` / logical twin, `requestClaimShadow` coverage, `balanceAggregator.test.ts`).

Per site: RED test "callable refuses / trigger skips while `departureInProgress: true`" (assert the same error the site throws for `claimingInProgress`); GREEN by appending `|| groupData.departureInProgress === true` to the existing flag list. One commit per logical site group.

### Task 1.6: `departureLockReaper`

**Files:** Create: `functions/src/scheduled/departureLockReaper.ts`, `functions/test/scheduled/departureLockReaper.test.ts` (RED first). Modify: `functions/src/index.ts` — **`export { departureLockReaper } from './scheduled/departureLockReaper';` re-export form** (a bare `export const` is invisible to `tool/list_expected_functions.sh`).

Mirror `deleteGroupLockReaper.ts` (hourly `onSchedule`, same stale threshold, same freeze-respect: skip groups where another of the four locks is live — its L99 pattern). Difference: no resume — clear the triple only (a lingering lock proves the mutation never committed; Task 1.4 makes clear-with-mutation atomic). Tests: stale lock cleared; fresh lock left; other-lock-frozen group skipped. Commit.

### Task 1.7: PR1 wrap

`flutter analyze` (no Dart changes expected — confirm), full `npm run test:emulator` suite, docs sweep: CLAUDE.md Key Invariants (flag family gains `departureInProgress`; leave/remove now lock), `docs/SECURITY-RULES.md`, `docs/CLOUD-FUNCTIONS.md` (new scheduled fn: 3→4). PR body: `Refs #1144` (also in the squash-inherited commit body), RED evidence pasted, `Spec:` line → this doc. Reviews via `/automerge` (Gate-category). Deploy after merge via `deploy-ceremony` (rules + functions together; callable sets the flag only rules+admins honor — same-deploy is safe, and pre-launch ordering is unconstrained).

# PR2 — Current-party policy (`Refs #1144`, branch `fix/1144-current-party-policy`, after PR1 merges)

### Task 2.1: RED — rules party-policy tests

**Files:** Modify: `functions/test/firestore-rules-publish-readiness.test.ts` (nested `describe('#1144 current-party policy', ...)`).

Fixtures: group with members A, C; departed D (in `events/*.participantIds`, absent from `memberIds`, no member doc); tombstoned T (absent from `memberIds`, member doc `isTombstone: true` keyed by T). Writer always current member A. Deny cases (RED — all currently allowed): 1. expense create, payer D; 2. exact-mode create, split key D; 3. custom-scope create, `customSplitParticipants` ∋ D; 4. equal-mode create on the departed-roster event; 5. allocation edit (amount change) of an existing expense whose payer is D; 6. allocation edit that *removes* D's split key (pre-state fail-closed); 7. soft-delete of an expense with D as payer; 8. equal-mode-expense soft-delete on the departed-roster event; 9. event-settlement create, party D. Allow cases (regression, must stay green): 10. metadata-only edit (note/category) of the payer-D expense; 11. equal-mode create on an all-current-roster event; 12. exact-mode create with member-only keys **on the departed-roster event** (frozen-roster events stay usable for current-member exact splits); 13. event-settlement with tombstoned T as recipient; 14. event-settlement between two live members; 15. shadow-member (uuid ∈ memberIds) as payer and split key. Run with `-t "#1144 current-party policy"` — deny cases FAIL. Commit RED.

### Task 2.2: GREEN — rules functions + integration

**Files:** Modify: `security/firestore.rules` (module scope, next to `participants()` L691-693).

```
// #1144: parties of a NEW or allocation-edited expense must be CURRENT
// members (memberIds includes unclaimed-shadow uuids, addShadowMember.ts).
// Roster-derived splits (equal/global/sub_group/custom-empty) divide over the
// participantIds-seeded universe, so they additionally require the roster
// itself to be all-current. Diff-gated by callers — metadata-only edits
// never evaluate this (acceptance: historical metadata stays editable).
function expensePartiesAreCurrentMembers(data) {
  return data.payerParticipantId in groupMembers()
    && (!data.keys().hasAny(['customSplitParticipants'])
      || data.customSplitParticipants.hasOnly(groupMembers()))
    && (!data.keys().hasAny(['splitDistribution'])
      || data.splitDistribution.keys().hasOnly(groupMembers()))
    && (data.scope == 'personal'
      || (data.scope == 'custom'
        && data.keys().hasAny(['customSplitParticipants'])
        && data.customSplitParticipants.size() > 0)
      || (data.keys().hasAny(['splitMode'])
        && data.splitMode in ['shares', 'exact', 'percent']
        && data.keys().hasAny(['splitDistribution'])
        && data.splitDistribution.size() > 0)
      || participants().hasOnly(groupMembers()));
}

// #1144: a settlement party is a current member, or a TOMBSTONED identity
// (deleteAccount departs without a zero-gate — its residual debt must stay
// settleable; leave/remove-departed identities passed the exact-zero gate,
// so blocking them strands nothing). || short-circuits: live parties cost
// zero extra document accesses (#929 decompose budget preserved).
function isSettleableParty(partyId) {
  return partyId in groupMembers()
    || (exists(/databases/$(database)/documents/groups/$(groupId)/members/$(partyId))
      && get(/databases/$(database)/documents/groups/$(groupId)/members/$(partyId)).data.isTombstone == true);
}
```

Integration (exact points; do NOT touch `validExpenseBase` — it runs unconditionally on every update):
- `validExpenseCreate` (L807-832): `&& expensePartiesAreCurrentMembers(request.resource.data)`.
- `validExpenseUpdate` (L864-926): inside the allocation-affecting branch (where `affectsExpenseAllocation()` already gates `enforceParticipantKeys`): `&& expensePartiesAreCurrentMembers(request.resource.data) && expensePartiesAreCurrentMembers(resource.data)`; inside the soft-delete OR-branch (L920-925): `&& expensePartiesAreCurrentMembers(resource.data)`.
- `validEventSettlementCreate` (L965-987): `&& isSettleableParty(request.resource.data.payerParticipantId) && isSettleableParty(request.resource.data.recipientParticipantId)` (existing `in participants()` conjuncts stay — parties must be both). Update the L975-977 comment: the departed-party allowance is now tombstone-scoped, cite #1144.

Re-run Task 2.1 (green) + the four rules suites, `decomposed-settleup-batch.test.ts` specifically (N=9 budget must hold), and watch for the #723 ceiling on the expense-update path (moderate slack per the headroom survey; emulator is the verdict). Commit: `fix(rules): #1144 expense/settlement parties must be current members (tombstone settle carve-out) (Refs #1144)`.

### Task 2.3: `correctSettlement` + `correctLogicalSettleUp` (RED → GREEN)

**Files:** Modify: `functions/src/callables/correctSettlement.ts` (~L140-149), `correctLogicalSettleUp.ts` (~L151-161), their test files.

RED: event-scope correction whose party departed-via-leave (no member doc) → expect `failed-precondition`; tombstoned party → allowed; both-live → allowed (regression). GREEN: after the existing event-participant check, for each party: `memberIds.includes(party) || (await tombstonedMember(groupRef, party))` where `tombstonedMember` queries `members.where('userId','==',party)` and accepts any doc with `isTombstone === true` (field-match — keying-agnostic, per the #294 lesson). Keep the group-scope branch unchanged. Commit.

### Task 2.4: PR2 wrap

Full emulator suite + `flutter analyze` + full `flutter test` (no client code changed — confirm both stay green). Docs: CLAUDE.md Financial landmines (party policy + tombstone carve-out, pointer here), `docs/SECURITY-RULES.md`. File follow-up issues: R1 (universe-only departed actors), client UX mirroring (D8: filter departed parties from add-expense pickers and settle-up pair lists; event settle screen additionally lacks any membership pre-gate). Re-scope #1144 to R1 (`Refs #1144` in PR body AND squash commit body — #447 lesson). Update #1135 with the §4 mootness evidence. `/automerge`; `deploy-ceremony` after merge.

---

## Verification principles — run during authoring (reported per the contract)

1. **Callsite classification:** every surface in §2's matrix is OUTBOUND or BOTH; INBOUND-only surfaces confirmed untouched: `aggregates/balance` doc (display cache, `balanceAggregator.ts:16-18`), `homeGroupBalanceProvider` (write-forbidden, `group_balance_provider.dart:1002-1003`), `perEventNet` drill-down, `splitExplanation`.
2. **Concrete claims re-grepped this session (first-hand):** `leaveGroup.ts:99/124`, `removeMember.ts:139/164/178-185`, rules L140-149, L419-421 (`groupMembers`), L474 (`hasOnly` in `validEventBase`), L571-606 (light path calls `validEventUpdateCommon`), L788/L794/L700-701 (expense party gates), L953-955 + L975-977 (settlement parties + #752 comment), L1225-1226 (group-settlement gate), `groupNetBalance.ts:552-582/592-741` (oracle reads + universe L683-689), `addShadowMember.ts:136` (shadow uuids ∈ memberIds), `deleteGroup.ts:121-179/264-280` (lock-then-recompute), `correctSettlement.ts:85-92/140-155` (quiesce + event-scope party check), `deleteGroupLockReaper.ts:76-77` (hourly). Reader-sourced with quoted code (spot-checks passed): `eventFanIn.ts:109-112`, `deleteAccount.ts` lock ~L400-414, `memberRemovalDeleteLockRace.test.ts` harness.
3. **Read-path per write-path:** `departureInProgress` → read by `groupAllowsClientWrites`, nine Admin honor sites, the final-txn ownership check, and the reaper. Party-policy conjuncts → evaluated by the three rules integration points; server mirror in the two correction callables. No new field is written that nothing reads.
4. **Fields enumerated from source:** expense fields from the `validExpenseBase` allowlist (L759-805, read); oracle input fields from `loadGroupBalanceSnapshot`/`computeNetFromSnapshot` (read); settlement fields from `validEventSettlementBase` allowlist (read).
5. **Data contracts spelled:** lock triple `departureInProgress: bool` / `departureLockedAt: Timestamp` / `departureLockedBy: string(uid)`; ownership test = `timestampMillis(departureLockedAt) === lockedAtMs`; helper signatures in Task 1.4; rules fn bodies in Task 2.2 verbatim.
6. **Arithmetic decomposition:** no money math changes. Access-budget math: decompose batch stays `2·N+1` because `isSettleableParty`'s `||` short-circuits for live parties (client pre-gate guarantees liveness on that path) — pinned by re-running `decomposed-settleup-batch.test.ts`, not by reasoning alone.
7. **Adversarial orthogonal-axis pass (fix axis = membership/time; adversary axes = money-flow, identity, offline):** money-flow found the tombstoned-debt strand → D5 carve-out. Identity found shadow-uuid party legitimacy → verified `memberIds` includes shadows. Offline found replay-drop semantics → matches the #1131-accepted posture. Scope adversary found the already-existing L474 event freeze → §1 correction narrowing mode A. Residual R1 (universe-only actors) found by asking "which universe member is NOT in participantIds?" — documented, not silently dropped.

## Gate record

- Round 1: pending (two fresh parallel reviewers: rubric + orthogonal adversary).
