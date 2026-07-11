# #1144 Post-Departure Ledger Integrity — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make the leave/remove exact-zero departure invariant durable — no write may create or move a departed party's balance after (or concurrently with) their departure.

**Architecture:** Two independent mechanisms, two PRs. **PR1 (departure fence, failure mode B):** `leaveGroup`/`removeMember` adopt `deleteGroup`'s existing lock pattern — acquire a `departureInProgress` group-doc lock transactionally, run `recomputeNet` *under* the lock, mutate-and-clear in one final transaction; the lock joins `groupAllowsClientWrites` (rules) and every Admin writer's quiesce checklist; a stale-lock reaper mirrors `deleteGroupLockReaper`. **PR2 (current-party policy, failure mode A):** rules gate the *parties* of new/edited expense allocations and event settlements to current `group.memberIds` — which includes shadow uuids AND deleteAccount tombstone ids (`deleteAccount.ts:616` *swaps* uid→tombstoneId in `memberIds`, it never removes), so ghost-debt cleanup settlements keep working with no carve-out while leave/remove-departed identities (hard-removed from `memberIds`) are blocked; `correctSettlement`/`correctLogicalSettleUp` mirror the same policy server-side. **The balance oracle is untouched on both sides** — no universe change, no participantIds pruning, no migration (issue decision 5; preserves client↔server parity and the claimShadow lock-step contract at `groupNetBalance.ts:586-591`).

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

**Partially closed already — with one asymmetric escape (Gate R2 correction):** `validEventBase` runs on *every* light+admin event update (via `validEventUpdateCommon`, L571-577) and unconditionally requires the POST-state `data.participantIds.hasOnly(groupMembers())` (L474). The **light** path is additionally additive-only (`hasAll`, L600-601), so a departed-roster event is frozen for every light update, and roster *injection* of a departed uid is impossible on any path. Event **soft-delete** of a departed-roster event is also frozen (the roster is unchanged in post-state, so L474 denies). The escape: `validEventAdminUpdate` (L609-630) has NO additivity guard — an admin roster **removal** of the departed key itself produces an all-current post-state that passes L474, dropping the departed party from that event's balance universe and re-dividing its equal splits (a post-departure balance move; concrete conserving-but-stranding example in D9). No client UI writes roster removals today (`event_service.dart` `updateEvent` sends only name/dates/description) — it is a rules-permitted forged-write hole, exactly the class PR2 exists to close → **D9**. The issue's "Carol adds Bob to E1" scenario remains only a *pre-departure race* (PR1's fence closes it). The only event-update branch that skips `validEventBase` is `validEventCloseToggle` (L660-681, `isClosed` triple only — not an oracle input); a reopened departed-roster event accepts new expense writes, which PR2's party policy then gates.

## 2. Dependency matrix — oracle inputs × writers (acceptance box 3)

Oracle reads (`loadGroupBalanceSnapshot`, `groupNetBalance.ts:552-582`; pure compute L592-741). Client mirror `computeGroupBalances`/`eventBalanceUniverse` (`group_balance_provider.dart:322-546`, `expense_provider.dart:106-151`) reads the same inputs via streams; parity pinned.

| Input (collection.field) | Effect on net | Client writers (rules path) | Server/Admin writers |
|---|---|---|---|
| `groups/{gid}`.`deletingInProgress`,`deleteLockedAt` | delete-resume event scope | — (rules deny roster/flag writes; `validMemberIdsRefresh` L397-403 forbids memberIds change) | `deleteGroup`, reapers |
| `members/*`.`userId`,`isTombstone` | `liveMemberIds`/`allMemberIds` → universe fold gates | member create (`validMemberCreate` L1040), self-rename (no oracle fields), member delete (L1089, rides Admin roster update) | `joinGroupByInviteCode`, `addShadowMember`, `claimShadowEngine`, `deleteAccount` (tombstone doc + uid→tombstoneId SWAP in `memberIds`, `deleteAccount.ts:616` — ghosts stay IN the roster), `leaveGroup`/`removeMember` (hard-delete + arrayRemove) |
| `events/*`.`participantIds` | universe seed + equal-split divisor | event create (`hasOnly(groupMembers())` L562); light update (additive `hasAll` L600-601 + post-state L474); **admin update may REMOVE keys** (no additivity guard, L609-630 — D9 gates removals to current members) | join/addShadow fan-in (`eventFanIn.ts:109-112`, arrayUnion), `claimShadowEngine` re-key, `deleteAccount.ts:502` uid→tombstoneId swap |
| `events/*`.`isDeleted`,`deletedAt` | event in/out of aggregation | admin update (soft-delete branch L625-629; frozen for departed-roster events via L474) | `deleteGroup` cascade |
| `expenses/*`.`payerParticipantId`,`amountFils`,`currency`,`scope`,`customSplitParticipants`,`splitMode`,`splitDistribution`,`isDeleted` | paid/owed folds | expense create/update/soft-delete (`validExpenseCreate` L807, `validExpenseUpdate` L864, soft-delete OR-branch L920-925) | `claimShadowEngine` re-key, `deleteAccount` scrub (`claimRekeyAt`/`deleteAccountScrubAt` markers) |
| `events/*/settlements/*`.`payerParticipantId`,`recipientParticipantId`,`amountFils`,`currency`,`isDeleted` | adj folds (event universe) | event-settlement create (`validEventSettlementCreate` L965; update/delete `if false`) | `correctSettlement`, `correctLogicalSettleUp` (reverse rows), `claimShadowEngine` re-key |
| `groups/{gid}/settlements/*` (same fields) | global fold, no universe gate | group-settlement create (`validGroupSettlementCreate` L1239; parties already `in memberIds` L1225-1226) | `correctSettlement`, `correctLogicalSettleUp`, `claimShadowEngine` re-key |

Non-writers (verified): `balanceAggregator` (display cache only, skips on quiesce flags `:75-84`), `expenseAuditLogger` (activity only), `balanceReconciler` (cache), `requestClaimShadow` (claimRequests doc only), `groupNetBalance.ts` (pure read).

Quiesce infrastructure today: `groupAllowsClientWrites` (rules L140-149, four absent-or-false flags) reached by every oracle-input client path (directly, or via `eventAllowsClientWrites` L195 / `eventAcceptsExpenseWrites` L213); each Admin writer mirrors the same four flags in code. `leaveGroup`/`removeMember` **read** the flags but **set none** — the concrete B hole.

## 3. Design decisions

**D1 — Fence = fifth quiesce flag, `deleteGroup` lock pattern (PR1).** Group-doc fields `departureInProgress: bool`, `departureLockedAt: Timestamp`, `departureLockedBy: string` (actor uid). Acquire transactionally (refuse if any of the existing four flags, or a live departure lock); `recomputeNet` under the lock; final transaction verifies the lock is *ours* (`timestampMillis(departureLockedAt)` equality) and clears it atomically with the membership mutation. Failure paths clear own-invocation-only (mirror `clearDeleteGroupLockForFailure` semantics: a concurrent observer never clears a peer's live lock). Crash → lock lingers → new hourly `departureLockReaper` clears stale locks (unlike deleteGroup's reaper there is nothing to *resume*: mutation and clear are atomic, so a lingering lock proves the mutation never committed — clearing is always safe).
**Error-code contract (Gate R1):** lock contention at acquire AND a lost/reaped lock at the final transaction throw **`aborted`**, never `failed-precondition` — both client handlers map any `failed-precondition` from these callables to the settle-up snackbar + CTA (`group_danger_section.dart:250-253`, `group_members_section.dart:255`), so a square user losing a lock race would be told they owe money. `failed-precondition` stays reserved exclusively for the unsettled-balance refusal.
*Soundness:* any oracle-input write committed before the lock-set is visible to the under-lock recompute (Firestore strong consistency); any attempt after is denied — client via rules, Admin via honor-checks. Both commit orderings are safe.
*Rejected — recompute inside the membership transaction:* the snapshot read is unbounded in group history (every event × expenses × settlements), turning any concurrent unrelated ledger write into transaction contention, and gives no protection against Admin writers that don't share the transaction. The flag matches five shipped precedents.
*Rejected — `ledgerRevision` counter echoed by every writer:* every client money write would need a batched group-doc bump (contention hotspot + batch-budget cost on every write) — strictly worse than a rare short freeze.

**D2 — Coarse freeze via `groupAllowsClientWrites`, not per-surface.** One absent-or-false clause covers every client oracle-input path (plus member/activity/meta writes — over-blocking for a sub-second-to-seconds window, matching `claimingInProgress` semantics exactly). Offline replays landing in the window are denied and silently dropped — the documented, accepted posture (#1131 plan §7; CLAUDE.md #929 note). Budget risk is the event update OR-chain (#723, near-ceiling): the clause adds ~4 expressions to paths that already call `groupAllowsClientWrites`; Task 1.2 mandates the emulator run as the verdict, with the #1134 ceiling-analysis fallback (inline/reorder) if any test reports `maximum of 1000 expressions`.

**D3 — Admin honor-checks: acquire-time mutual exclusion.** Add `departureInProgress === true` to the existing flag checklists at: `joinGroupByInviteCode.ts:231-238`, `addShadowMember.ts:71-77`, `decideClaimRequest.ts` lock acquire (~L211-289), `deleteAccount.ts` lock acquire (~L383-414), `deleteGroup.ts:161-163` + `finalizeGroupDeletion` L271-273, `correctSettlement.ts:85-92`, `correctLogicalSettleUp.ts:95-101`, `requestClaimShadow.ts:75-82` (defense-only), and `balanceAggregator.ts:75-84`+`:145-154` skip set (display-only; `balanceReconciler` self-heals staleness). Each site throws whatever it already throws for `claimingInProgress` (site-local consistency). **The real invariant (Gate R3): the flag-check must sit INSIDE each writer's write transaction.** Only deleteGroup/deleteAccount/claim exclude the departure lock by holding locks of their own; join/addShadow/correctSettlement/correctLogicalSettleUp are safe because they read the group doc inside the same transaction that writes the oracle input — Firestore transaction serializability against the departure lock's group-doc write forces a conflict-retry that re-sees the flag. Never relocate the check outside the transaction as an "optimization." Reapers need no cross-checks: a resumed cascade holds a lock that *predates* any departure lock, so overlap is impossible by construction — but `departureLockReaper` must skip groups holding one of the other three locks, mirroring `deleteGroupLockReaper`'s freeze-respect (its L99 pattern).

**D4 — Party policy: current members only, for allocation-bearing expense writes (PR2).** New rules fn `expensePartiesAreCurrentMembers(data)` (complete code in Task 2.2): payer ∈ `groupMembers()`, `customSplitParticipants`/`splitDistribution` keys ⊆ `groupMembers()`, and — because equal/global/sub_group/custom-empty splits divide over the roster-seeded universe (`allocateExpenseOwed`, `expense_provider.dart:430-446`; server L425-434) — roster-derived writes additionally require `participants().hasOnly(groupMembers())`. Applied at: create (always), update (only when `affectsExpenseAllocation()` — on **both** post-state and pre-state, so an edit can neither introduce a departed party nor change a doc that already references one), soft-delete (pre-state — removing a departed party's expense from aggregation moves their net). **Metadata-only edits stay untouched** (acceptance box 2): the fn is diff-gated behind the existing allocation/soft-delete branches, never in the unconditional `validExpenseBase`. All referenced docs (group, event) are already fetched on these paths — zero new document accesses (#929-safe), moderate expression cost (Task D headroom assessment; emulator is the verdict).
*Why memberIds is the right set:* shadow uuids are arrayUnion'd into `memberIds` (`addShadowMember.ts:136`) — shadow expenses keep working.
*Stated plainly (Gate R1 P2 — the product consequence):* once ANY member departs via leave/remove, every event they participated in **permanently rejects new equal/global/sub_group/custom-empty expense creates** (the roster clause), and every existing expense referencing them becomes un-editable (allocation) and un-soft-deletable (R6). Exact/shares/percent splits among current members remain available on those events (Task 2.1 case 12). This is the deliberate frozen-history principle — rewriting a departed party's history creates phantom debt nobody can settle — but it is a real UX cliff that surfaces as raw `permission-denied` until the client mirroring lands (D8). Pre-launch with no real users this is acceptable; D8 is near-mandatory before launch.

**D5 — Event-settlement parties: current `memberIds` — which already contains tombstoned ghosts (Gate R1 correction).** Verified model of the persistence layer: `deleteAccount` departs *without* a zero-gate, but it **swaps** uid→tombstoneId in `memberIds` (`deleteAccount.ts:616`, `replaceUid` in `mapReKey.ts:79-91` — replace, never remove), re-keys every historical money doc to the tombstoneId (`payerParticipantId`/`splitDistribution` keys/settlement parties, `deleteAccount.ts:216-297`), and writes the tombstone member doc keyed by `tombstoneId` with `isTombstone: true` (`:631-639`, the only `isTombstone` writer). So a ghost's party id **is** in `memberIds`, and the sanctioned debt-cleanup settlement passes a plain membership gate — group settlements against ghosts already work today via L1225-1226 for exactly this reason. Leave/remove-departed parties are the opposite: hard-removed from `memberIds`, member docs deleted, departed at exact zero — any settlement naming them *creates* exposure, so blocking them strands nothing. Policy therefore: event-settlement parties must each be `in groupMembers()` — byte-for-byte the same gate group settlements already use, zero new document accesses (group doc already fetched; decomposed settle-up batch keeps `2·N+1 ≤ 20`, N=9).
*Rejected — a tombstone-doc `exists()/get()` carve-out (this spec's own v1):* dead code — arm 1 (`in memberIds`) already catches every production tombstone; the carve-out was derived from a false model (tombstones absent from memberIds) and tested a state that cannot occur.
*Rejected — free departed-party settlements (status quo):* any member can mint arbitrary exposure for a zero-departed ghost — the issue's core complaint.

**D6 — `correctSettlement`/`correctLogicalSettleUp` mirror D5 server-side.** Event-scope corrections add: each party must be in the group's current `memberIds` (`memberIds.includes(party)` — tombstoned ghosts pass because their id is in `memberIds`; leave/remove-departed parties fail). Rationale: a leave/remove-departed party's zero-gate folded the settlement being corrected; reversing it post-departure breaks the invariant. Ghost corrections stay possible (cleanup path). Both callables also gain the D3 fence check.

**D7 — Oracle, universe, and drill-down untouched.** No change to `computeNetFromSnapshot`, `eventBalanceUniverse`, participantIds semantics, or any historical document. Parity tests stay byte-identical; the claimShadow footprint pre-scan contract (`groupNetBalance.ts:586-591`) is not triggered.

**D9 — Admin roster removals may not drop a non-current-member key (Gate R2).** `validEventAdminUpdate` gains a diff-gated guard:

```
&& (!request.resource.data.diff(resource.data).affectedKeys().hasAny(['participantIds'])
  || resource.data.participantIds.toSet()
      .difference(request.resource.data.participantIds.toSet())
      .hasOnly(groupMembers()))
```

Removed roster keys must all be current members — removing a leave/remove-departed key (the R2 adversary's stranding example: departed-at-zero D removed from an event where they owed an equal share → phantom credit `+share` nobody can settle) is denied; removing a *current* member stays allowed (they can see and re-settle the shift); removing a ghost (tombstoneId ∈ `memberIds`) passes and joins the R5 residual class (rules cannot distinguish ghosts; forge-only surface — no client UI writes roster removals, `event_service.dart` `updateEvent` sends only name/dates/description). The first conjunct short-circuits for every admin update that doesn't touch `participantIds` (soft-deletes, renames), keeping the common path's expression count flat — but this sits on the #723 near-ceiling event OR-chain, `.toSet()/.difference()` have no precedent in this ruleset, and reorder tricks can't shrink a set-difference's own cost. **Named fallback (Gate R3):** if the emulator reports the ceiling on any legitimate admin update, DO NOT ship a broken admin path to close a forge-only hole — drop D9 from PR2 and move it to the R1/R5 rules-hardening follow-up (where an `activeMemberIds` field closes R5 AND makes this guard a cheap `hasOnly`). The emulator verdict decides which branch ships.

**D8 — Client UX mirroring is PR3: a named, near-mandatory-before-launch follow-up (not bundled into PR1/PR2).** Rules are the boundary; until mirrored, four surfaces degrade to raw error snackbars: (a) add-expense pickers offering departed universe members and tombstoned ghosts as payer/split parties; (b) settle-up pair lists offering leave/remove-departed counterparties (event settle-up has no membership pre-gate — `settle_up_screen.dart:375-376` gates only the writer); (c) edit/soft-delete affordances on frozen departed-party expenses (R6) with no explanation; (d) the Correct-settlement affordance on departed-party settlements (D6 newly denies it with `failed-precondition`; the button's visibility logic, `settlement_correction_affordance.dart`, keys only on already-corrected rows — reachable from `settle_up_screen.dart:435` and `group_settle_up_screen.dart:278/286`, degrades via `classifySettlementWriteError` → `settleUpRecordFailedDenied`, honest but unexplained). PR3 scope: filter (a) to current non-tombstone members for NEW expenses, hide (b) pairs whose parties fail the D5 gate, show a "history with a departed member is read-only" explanation for (c), and hide (d) for parties absent from `memberIds`; also exclude transient `aborted` from the Sentry capture in the leave/remove handlers, and give `aborted` a retry-inviting copy (the generic "Something went wrong" doesn't suggest the race is transient). Filed as its own issue at PR2 ship time with this paragraph as the spec seed. This keeps PR2 reviewable and keeps money-policy and UX concerns in separate PRs.

## 4. Deliberately unchanged (do not "fix" while in here)

- `participantIds` never pruned; departed identities stay in the balance universe (#249 conservation; issue decision 5).
- Event light-update writer gate (`requesterIsParticipant`, L588) — #1135's axis, tracked there. **Evidence for #1135 triage** (surfaced, not acted on): a departed writer is by definition on the roster, so every light/admin update they attempt already fails `validEventBase`'s `hasOnly(groupMembers())` (L474) — #1135's vandalism/injection surface appears already closed on `main`; recommend re-verifying and re-scoping that issue.
- Group-settlement party gate (L1225-1226) — already correct; not loosened for tombstones (R3).
- The #929 `kMaxDecomposeLegsAtomic = 9` carve-out and the single-group-write fallback path.
- `validEventCloseToggle` skipping `validEventBase` (#723 budget) — safe once PR2 gates expense creates.
- deleteAccount's no-zero-gate tombstone departure (deliberate: account deletion can't be hostage to debt).

## 5. Residual risks → follow-up issues (file at ship time)

- **R1 (acceptance box 1, narrow carve-out):** a departed *universe-only* actor (ex-payer/settlement-party who was never an event participant — paid-on-behalf, then left) still gains/loses share from a new roster-derived expense or an event soft-delete on that event: rules cannot see subcollections, so `participants().hasOnly(groupMembers())` cannot detect them. Requires paid-on-behalf history + departure — rare. Follow-up options: trigger-stamped event-level "has departed financial history" marker, or server-authoritative expense creates for flagged events. PR2 therefore carries `Refs #1144`; the issue stays open re-scoped to R1+R5 after merge.
- **R2:** tombstoned-ghost settlements can overshoot zero (direction/magnitude unenforceable in rules) — bounded to deleteAccount ghosts, append-only, correctable, author is a current member. Accepted; documented in SECURITY-RULES.md.
- **R3 (corrected in Gate R1 — the spec's v1 claim here was FALSE):** group-scope ghost debt IS settleable today: the tombstoneId sits in `memberIds` (`deleteAccount.ts:616`), so the L1225-1226 gate passes by design. Do NOT "fix" this by loosening L1225-1226, and do NOT tighten it to exclude tombstones — both directions are money-policy changes needing their own decision.
- **R4:** stuck departure lock write-freezes the group up to the reaper interval (~1h) — same failure mode and remedy as the three existing locks.
- **R5 (ghost gap — the D5 model's cost, expense + roster axes):** because tombstone ids live in `memberIds` and rules cannot iterate `splitDistribution` keys for per-key doc lookups, rules cannot exclude ghosts anywhere `memberIds` is the gate — a new expense can still name a deleteAccount tombstone as payer/split-party, and a D9 roster removal of a ghost key still passes (both move the ghost's balance). Bounded: requires deliberately picking a "Deleted user" identity (or forging a write); conservation holds; PR3 filters ghosts from pickers client-side. Durable rules fix (if ever needed): an `activeMemberIds` group-doc field (memberIds minus tombstones) maintained by every roster writer — deferred, goes in the R1/R5 follow-up issue. Pinned by an explicit ALLOWED test (Task 2.1 case 16) so the behavior is documented, not accidental.
- **R6 (frozen departed-party expenses):** any expense referencing a leave/remove-departed party becomes permanently un-editable (allocation) and un-soft-deletable — deliberate fail-closed (either write moves the departed net). This also closes the documented "legacy/forged doc stays soft-deletable" escape hatch (rules L708-712/724-726 deliberately exempt soft-delete from value checks) for departed-party docs specifically — Admin-SDK cleanup remains possible, and pre-launch no such legacy docs exist. Surfaced as `permission-denied` until PR3's explanation lands. Document both halves in SECURITY-RULES.md. **Offline corollary (Gate R2):** PR2 makes the replay-drop condition *permanent*, not just fence-transient — a roster-derived expense queued offline while every roster member was current is silently dropped at replay if any roster member departs before reconnect. Same #1131-accepted class, wider window; say so in SECURITY-RULES.md alongside the freeze.

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
3. **Lock lifecycle:** cleared after success (all three fields); cleared after zero-gate refusal; cleared when recompute throws; mutual exclusion (second leave/remove while lock held → **`aborted`** — assert the CODE, not just rejection: `failed-precondition` here would trigger the client's settle-up snackbar contract, D1 — and no mutation).
4. **Roster/event orderings (acceptance):** pre-fence event-roster add (target added to an event, redistributing an equal split) → recompute under lock sees it → refused if non-zero; pre-fence event soft-delete likewise.

Run: `cd functions && npm run test:emulator -- departureFence.test.ts` — expect FAIL (no lock exists). Commit RED.

### Task 1.4: GREEN — shared lock helper + callable restructure

**Files:** Create: `functions/src/callables/shared/departureLock.ts`. Modify: `functions/src/callables/leaveGroup.ts`, `removeMember.ts`.

`departureLock.ts` (mirror `deleteGroup.ts:121-216` shapes):
- `acquireDepartureLock(db, groupRef, uid)` — transaction: group must exist and pass the existing four-flag check (`not-found`, matching leave/remove's current semantics); `departureInProgress === true` → **`aborted`** ("Another membership change is in progress. Try again.") — NOT `failed-precondition`, which the client reserves for the unsettled-balance snackbar (D1 error-code contract); else set the triple + `updatedAt`, return `{ lockedAtMs }`.
- `clearDepartureLock(db, groupRef, lockedAtMs)` — transaction: clear the triple **only if** `timestampMillis(departureLockedAt) === lockedAtMs` (own-invocation-only; a peer's live lock is never cleared).

Callable flow (both files; keep the existing pre-reads and the lock-free idempotent short-circuit):
1. existing pre-checks/authz → 2. `acquireDepartureLock` → 3. `try { recomputeNet; zero-gate } catch/refusal { clearDepartureLock; rethrow }` → 4. final transaction: re-read group; verify quiesce flags AND `departureInProgress === true && timestampMillis(departureLockedAt) === lockedAtMs` (else **`aborted`** — lock reaped mid-flight; same code-contract note as acquire); removeMember re-verifies #1132 authz (keep L178-185); perform the existing mutation **plus clear the lock triple in the same `tx.update`**; the `alreadyLeft/alreadyRemoved` in-txn branch also clears before returning → 5. any throw after acquire → `clearDepartureLock` in a `finally`-style guard (only when the mutation txn did not commit).

Re-run Task 1.3 (green) + `leaveGroup.test.ts`, `removeMember.test.ts`, `memberRemovalDeleteLockRace.test.ts`. Commit: `fix(functions): #1144 leave/remove acquire a departure lock across the zero-check (Refs #1144)`.

### Task 1.5: Admin honor-checks (RED per site, then GREEN)

**Files:** Modify the nine D3 sites + their test files (`joinGroupByInviteCode.test.ts`, `addShadowMember.test.ts`, `claimRequest.test.ts`, `deleteAccount.test.ts`, `deleteGroup.test.ts`, `correctSettlement.test.ts` / logical twin, `requestClaimShadow` coverage, `balanceAggregator.test.ts`).

Per site: RED test "callable refuses / trigger skips while `departureInProgress: true`" (assert the same error the site throws for `claimingInProgress`); GREEN by appending `|| groupData.departureInProgress === true` to the existing flag list. One commit per logical site group.

### Task 1.6: `departureLockReaper`

**Files:** Create: `functions/src/scheduled/departureLockReaper.ts`, `functions/test/scheduled/departureLockReaper.test.ts` (RED first). Modify: `functions/src/index.ts` — **`export { departureLockReaper } from './scheduled/departureLockReaper';` re-export form** (a bare `export const` is invisible to `tool/list_expected_functions.sh`).

Mirror `deleteGroupLockReaper.ts` (hourly `onSchedule`, same stale threshold, same freeze-respect: skip groups where another of the four locks is live — its L99 pattern). Difference: no resume — clear the triple only (a lingering lock proves the mutation never committed; Task 1.4 makes clear-with-mutation atomic). Tests: stale lock cleared; fresh lock left; other-lock-frozen group skipped. Commit.

### Task 1.7: PR1 wrap

`flutter analyze`. ONE deliberate Dart change (Gate R3): `group_members_section.dart:276-279`'s generic branch interpolates the raw server string (`e.message ?? e.code`), so an Arabic user losing a lock race would see untranslated English — route it through `friendlyMessageFor(context, e)`, mirroring `group_danger_section.dart:270`; with that, both callables' `aborted` codes fall through to localized generic snackbars. Note the fall-through also hits `unawaited(Sentry.captureException(e))` (`group_danger_section.dart:266`), so lock-contention retries emit Sentry noise — acceptable for the sub-second window; exclude transient `aborted` from Sentry in PR3. full `npm run test:emulator` suite, docs sweep: CLAUDE.md Key Invariants (flag family gains `departureInProgress`; leave/remove now lock), `docs/SECURITY-RULES.md`, `docs/CLOUD-FUNCTIONS.md` (new scheduled fn — count from `index.ts:38-41`, which already re-exports FOUR scheduled fns; `departureLockReaper` makes 5; the docs' "3 scheduled" baseline is stale, fix it in the same sweep). PR body: `Refs #1144` (also in the squash-inherited commit body), RED evidence pasted, `Spec:` line → this doc. Reviews via `/automerge` (Gate-category). Deploy after merge via `deploy-ceremony` (rules + functions together; callable sets the flag only rules+admins honor — same-deploy is safe, and pre-launch ordering is unconstrained).

# PR2 — Current-party policy (`Refs #1144`, branch `fix/1144-current-party-policy`, after PR1 merges)

### Task 2.1: RED — rules party-policy tests

**Files:** Modify: `functions/test/firestore-rules-publish-readiness.test.ts` (nested `describe('#1144 current-party policy', ...)`).

Fixtures: group with members A, C; departed D (in `events/*.participantIds`, absent from `memberIds`, no member doc — the leave/remove post-state); ghost T (**in `memberIds` AND in the event's `participantIds`** — production post-`deleteAccount` state: `deleteAccount.ts:616` swaps uid→tombstoneId in `memberIds` and `:502` swaps it into every event's `participantIds` — with member doc keyed T, `userId: T`, `isTombstone: true`; without the participantIds entry the ALLOW cases would fail the existing `in participants()` conjunct, not the new gate). Writer always current member A. Deny cases (RED — all currently allowed): 1. expense create, payer D; 2. exact-mode create, split key D; 3. custom-scope create, `customSplitParticipants` ∋ D; 4. equal-mode create on the departed-roster event; 5. allocation edit (amount change) of an existing expense whose payer is D; 6. allocation edit that *removes* D's split key (pre-state fail-closed); 7. soft-delete of an expense with D as payer; 8. equal-mode-expense soft-delete on the departed-roster event; 9. event-settlement create, party D. Allow cases (regression, must stay green): 10. metadata-only edit (note/category) of the payer-D expense; 11. equal-mode create on an all-current-roster event; 12. exact-mode create with member-only keys **on the departed-roster event** (frozen-roster events stay usable for current-member exact splits); 13. event-settlement with ghost T as recipient (passes via `memberIds` — the debt-cleanup path); 14. event-settlement between two live members; 15. shadow-member (uuid ∈ memberIds) as payer and split key; 16. expense create with ghost T as split key — ALLOWED, with a comment pinning residual R5 (rules cannot exclude ghosts from `memberIds`; PR3 filters client-side) so the behavior is documented, not accidental; 17. **admin event update removing departed D from `participantIds`** (post-state all-current) — DENIED (D9; RED — currently allowed); 18. admin event update removing *current* member C from the roster — ALLOWED (regression); 19. admin event soft-delete of the departed-roster event — DENIED (existing L474 behavior, pin it). Run with `-t "#1144 current-party policy"` — deny cases FAIL. Commit RED.

### Task 2.2: GREEN — rules functions + integration

**Files:** Modify: `security/firestore.rules` (module scope, next to `participants()` L691-693).

```
// #1144: parties of a NEW or allocation-edited expense must be in the CURRENT
// memberIds — which includes unclaimed-shadow uuids (addShadowMember.ts) AND
// deleteAccount tombstone ids (deleteAccount.ts uid→tombstoneId SWAP), so this
// blocks leave/remove-departed parties but NOT ghosts (residual R5; rules
// cannot iterate splitDistribution keys to exclude tombstones — PR3 filters
// them client-side). Roster-derived splits (equal/global/sub_group/
// custom-empty) divide over the participantIds-seeded universe, so they
// additionally require the roster itself to be all-current. Diff-gated by
// callers — metadata-only edits never evaluate this (acceptance: historical
// metadata stays editable).
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

```

(No settlement helper fn: the party gate is a plain `in groupMembers()` — deleteAccount ghosts pass because `deleteAccount.ts:616` swaps their tombstoneId INTO `memberIds`; leave/remove-departed parties fail because departure hard-removes them. Same gate group settlements already use at L1225-1226. Zero new document accesses; #929 decompose budget untouched.)

Integration (exact points; do NOT touch `validExpenseBase` — it runs unconditionally on every update, and an unconditional placement breaks case 10):
- `validExpenseCreate` (L807-832): `&& expensePartiesAreCurrentMembers(request.resource.data)`.
- `validExpenseUpdate` (L864-926): **there is no "allocation branch" to hook** — `affectsExpenseAllocation()` is only passed as the `enforceParticipantKeys` parameter (L896). Add an explicit new conjunct: `&& (!affectsExpenseAllocation() || (expensePartiesAreCurrentMembers(request.resource.data) && expensePartiesAreCurrentMembers(resource.data)))`, and attach the soft-delete check to the `validSoftDelete()` ARM only — `|| (validSoftDelete() && expensePartiesAreCurrentMembers(resource.data))` — NOT to the enclosing block, or metadata-only edits of departed-party docs break (case 10 catches it).
- `validEventSettlementCreate` (L965-987): `&& request.resource.data.payerParticipantId in groupMembers() && request.resource.data.recipientParticipantId in groupMembers()` (existing `in participants()` conjuncts stay — parties must be both). Update the L975-977 comment: the departed-party allowance is now scoped to identities still in `memberIds` (i.e. deleteAccount ghosts), cite #1144.
- `validEventAdminUpdate` (L609-630): the D9 roster-removal guard verbatim (diff-gated `participantIds` clause). This is the #723 near-ceiling OR-chain — run the full rules suite and treat any `maximum of 1000 expressions` failure as the ceiling, not test logic (#1134 mitigation template).

Re-run Task 2.1 (green) + the four rules suites, `decomposed-settleup-batch.test.ts` specifically (N=9 budget must hold), and watch for the #723 ceiling on the expense-update path (moderate slack per the headroom survey; emulator is the verdict). Commit: `fix(rules): #1144 expense/settlement parties must be current members (Refs #1144)`.

### Task 2.3: `correctSettlement` + `correctLogicalSettleUp` (RED → GREEN)

**Files:** Modify: `functions/src/callables/correctSettlement.ts` (~L140-149), `correctLogicalSettleUp.ts` (~L151-161), their test files.

RED: event-scope correction whose party departed-via-leave (absent from `memberIds`) → expect `failed-precondition`; ghost party (tombstoneId ∈ `memberIds`) → allowed; both-live → allowed (regression). GREEN: after the existing event-participant check, require `memberIds.includes(party)` for each party — no tombstone query needed (ghost ids are IN `memberIds` per `deleteAccount.ts:616`). Keep the group-scope branch unchanged (it already checks `memberIds`). Commit.

### Task 2.4: PR2 wrap

Full emulator suite + `flutter analyze` + full `flutter test` (no client code changed — confirm both stay green). Docs: CLAUDE.md Financial landmines (party policy + ghost-in-memberIds model, pointer here), `docs/SECURITY-RULES.md` (party policy; R5 expense-to-ghost gap; R6 frozen departed-party expenses incl. the forged/legacy-doc soft-delete collision). File follow-up issues: R1+R5 (rules-inexpressible residuals), PR3 client UX mirroring (D8 paragraph as spec seed). Re-scope #1144 to R1+R5 (`Refs #1144` in PR body AND squash commit body — #447 lesson). Update #1135 with the §4 mootness evidence. `/automerge`; `deploy-ceremony` after merge.

---

## Verification principles — run during authoring (reported per the contract)

1. **Callsite classification:** every surface in §2's matrix is OUTBOUND or BOTH; INBOUND-only surfaces confirmed untouched: `aggregates/balance` doc (display cache, `balanceAggregator.ts:16-18`), `homeGroupBalanceProvider` (write-forbidden, `group_balance_provider.dart:1002-1003`), `perEventNet` drill-down, `splitExplanation`.
2. **Concrete claims re-grepped this session (first-hand):** `leaveGroup.ts:99/124`, `removeMember.ts:139/164/178-185`, rules L140-149, L419-421 (`groupMembers`), L474 (`hasOnly` in `validEventBase`), L571-606 (light path calls `validEventUpdateCommon`), L788/L794/L700-701 (expense party gates), L953-955 + L975-977 (settlement parties + #752 comment), L1225-1226 (group-settlement gate), `groupNetBalance.ts:552-582/592-741` (oracle reads + universe L683-689), `addShadowMember.ts:136` (shadow uuids ∈ memberIds), `deleteGroup.ts:121-179/264-280` (lock-then-recompute), `correctSettlement.ts:85-92/140-155` (quiesce + event-scope party check), `deleteGroupLockReaper.ts:76-77` (hourly). Reader-sourced with quoted code (spot-checks passed): `eventFanIn.ts:109-112`, `deleteAccount.ts` lock ~L400-414, `memberRemovalDeleteLockRace.test.ts` harness.
3. **Read-path per write-path:** `departureInProgress` → read by `groupAllowsClientWrites`, nine Admin honor sites, the final-txn ownership check, and the reaper. Party-policy conjuncts → evaluated by the three rules integration points; server mirror in the two correction callables. No new field is written that nothing reads.
4. **Fields enumerated from source:** expense fields from the `validExpenseBase` allowlist (L759-805, read); oracle input fields from `loadGroupBalanceSnapshot`/`computeNetFromSnapshot` (read); settlement fields from `validEventSettlementBase` allowlist (read).
5. **Data contracts spelled:** lock triple `departureInProgress: bool` / `departureLockedAt: Timestamp` / `departureLockedBy: string(uid)`; ownership test = `timestampMillis(departureLockedAt) === lockedAtMs`; helper signatures in Task 1.4; rules fn bodies in Task 2.2 verbatim.
6. **Arithmetic decomposition:** no money math changes. Access-budget math: decompose batch stays `2·N+1` — the settlement party gate reuses the already-fetched group doc, adding zero accesses — pinned by re-running `decomposed-settleup-batch.test.ts`, not by reasoning alone.
7. **Adversarial orthogonal-axis pass (fix axis = membership/time; adversary axes = money-flow, identity, offline):** money-flow raised the tombstoned-debt question; this spec's v1 answered it with a WRONG persistence model (tombstones assumed absent from `memberIds`) and Gate R1 corrected it against `deleteAccount.ts:616` — D5/D6/R3/R5 now carry the verified model. Identity found shadow-uuid party legitimacy → verified `memberIds` includes shadows. Offline found replay-drop semantics → matches the #1131-accepted posture. Scope adversary found the already-existing L474 event freeze → §1 correction narrowing mode A. Residual R1 (universe-only actors) found by asking "which universe member is NOT in participantIds?" — documented, not silently dropped.

## Gate record

- Round 1: rubric 1 P1 / 2 P2 / 2 P3; adversary 2 P1 / 0 P2 / 1 P3. Union applied: (a) tombstone model inverted — `deleteAccount` SWAPS uid→tombstoneId in `memberIds` (both reviewers, independently) → D5/D6 simplified to plain `memberIds` gates, R3 corrected (v1 claim was false), R5 added (expense-to-ghost gap), fixtures fixed, item-7 claim re-grounded; (b) `failed-precondition` collision with the client settle-up snackbar contract → `aborted` error-code contract in D1/Tasks 1.3-1.4; (c) P2s: equal-split UX cliff stated plainly in D4 + PR3 elevated (near-mandatory pre-launch); soft-delete vs forged/legacy-doc cleanup collision documented in R6; (d) P3s: scheduled-fn count corrected (4→5, count from index.ts), Task 2.2 integration made explicit (`!affectsExpenseAllocation() || (...)` conjunct — no "allocation branch" exists), R6 entry added.
- Round 2: rubric 0 P1 / 0 P2 / 2 P3 (ghost fixture must also sit in event `participantIds` per `deleteAccount.ts:502`; Sentry noise on `aborted` fall-through — both folded in); adversary 1 P1 / 1 P2 / 2 P3. Union applied: (a) P1 — `validEventAdminUpdate` has no additivity guard, so an admin roster REMOVAL of a departed key passes post-state L474 and re-divides equal splits (post-departure balance move; §1 overclaim corrected) → new D9 set-difference guard + Task 2.1 cases 17-19; (b) P2 — Correct-settlement affordance added as PR3 surface (d); (c) P3s — Sentry `aborted` noise noted for PR3; permanent offline replay-drop widening documented in R6.
- Round 3: rubric 0 P1 / 1 P2 / 2 P3; adversary 0 P1 / 1 P2 / 1 P3 — **BOTH P1-CLEAN IN THE SAME ROUND → Gate passed.** Non-P1 union folded in: (a) rubric P2 — D9's ceiling fallback named (defer to the R1/R5 follow-up if the emulator reports the #723 ceiling; never break legitimate admin updates for a forge-only hole); (b) adversary P2 — `group_members_section.dart:276-279` raw-English `aborted` leak → owned as PR1's one deliberate Dart change (`friendlyMessageFor`); (c) P3s — soft-delete check attached to the `validSoftDelete()` arm explicitly; D3's real invariant stated (flag-check inside the write transaction, serializability not "acquire"); retry-inviting `aborted` copy → PR3.
- Round-count note: 3 rounds, but the protocol's "3 = over-scoped" signal is soft here — round 3's union contained zero P1s; the two P1 rounds each found a distinct real defect (inverted tombstone model; admin roster-removal escape), not re-litigation.
