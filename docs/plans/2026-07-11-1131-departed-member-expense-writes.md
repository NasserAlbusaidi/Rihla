# #1131 Departed-Member Expense Write Authority Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Close the authz bypass where a departed/removed group member retains expense create/edit/soft-delete authority via never-pruned event `participantIds` — by adding a current-membership conjunct (`isGroupMember`) to the expense write gates in `security/firestore.rules`.

**Architecture:** Rules-only change: two one-line conjuncts in `validExpenseCreate()` / `validExpenseUpdate()`, mirrored by emulator rules tests (RED first). No Functions change, no client change, no schema change. The counterparty universe (`participants()`) is deliberately untouched — #249 oracle-parity contract.

**Tech Stack:** Firestore security rules, `@firebase/rules-unit-testing` under the emulator (`npm run test:emulator`).

**Issue:** #1131 (P2, security/money/data-integrity). Verified against `main` @ `50d96847`.

---

## Context (all declarations re-read this session at `50d96847`)

- `security/firestore.rules:779-796` `validExpenseCreate()` — gates on `isEventParticipant(groupId, eventId)` + `eventAcceptsExpenseWrites(groupId, eventId)`. **No membership term.**
- `security/firestore.rules:828-889` `validExpenseUpdate()` — same two gates; OPEN-edit (#248 PR4). **No membership term.**
- `security/firestore.rules:969-970` read gate — `isGroupMember(groupId)`. This is the read/write asymmetry.
- `security/firestore.rules:219-223` `isEventParticipant()` — `request.auth.uid in eventData(...).participantIds`; `participantIds` is never pruned on departure.
- `functions/src/callables/leaveGroup.ts:19` — comment: "leave never touches event participantIds"; `:156` removes uid from `memberIds` only.
- `functions/src/callables/removeMember.ts:30` — "remove never touches event participantIds" (balance-universe preservation).
- Only `participantIds` writers in `functions/src`: `eventFanIn.ts` (additive `arrayUnion` join fan-in) and `claimShadow.ts` (uuid→uid re-key). Nothing prunes on `memberIds` shrink.
- Precedent **in the same file**: `validEventSettlementCreate()` (`:928-950`) already gates on `isGroupMember(groupId)` (#752).

So: a departed member keeps `participantIds` forever → passes `isEventParticipant` → can forge/edit/soft-delete expenses via raw SDK writes while being read-blind.

## Fix shape (decided)

Add `isGroupMember(groupId)` as a conjunct in BOTH expense write gates, immediately after the `module == 'expenses'` term (mirrors `validEventSettlementCreate`'s ordering):

```
function validExpenseCreate() {
  return module == 'expenses'
    // #1131: leave/remove never prune event participantIds (balance-universe
    // preservation), so participation alone is NOT current membership — a
    // departed member would retain write authority forever. Require live
    // memberIds too. The counterparty universe (participants()) is deliberately
    // untouched: current members must keep writing expenses that REFERENCE
    // departed participants (#249 parity contract).
    && isGroupMember(groupId)
    && isEventParticipant(groupId, eventId)
    && eventAcceptsExpenseWrites(groupId, eventId)
    ...unchanged...
}

function validExpenseUpdate() {
  return module == 'expenses'
    && isGroupMember(groupId)   // #1131 — see validExpenseCreate
    && isEventParticipant(groupId, eventId)
    && eventAcceptsExpenseWrites(groupId, eventId)
    ...unchanged...
}
```

**Rejected alternative:** pruning `participantIds` on leave/remove — would perturb the balance universe that `leaveGroup`/`removeMember` deliberately preserve (per-event drill-down, equal-split divisors, oracle parity). The rules conjunct is strictly narrower.

**Expression-ceiling risk (#723):** the expense-update path is near the ~1000-expression rules ceiling. `isGroupMember` adds ~5 expressions (`signedIn` + `exists(groupPath)` + `in memberIds`); the group doc is ALREADY read by `groupAllowsClientWrites` (inside `eventAcceptsExpenseWrites`), so document-access count is unchanged (same-doc access bills once) — batch budgets (#929) unaffected; no batch writes multiple expenses anyway. **Fallback if any rules test trips "maximum of 1000 expressions":** inline the single term `request.auth.uid in groupData(groupId).memberIds` instead of calling `isGroupMember` (drops the redundant `signedIn()`/`exists()` — both already established by `isEventParticipant`/`groupAllowsClientWrites` on every reachable path).

## Verification principles report (run while authoring)

1. **Callsite classification** — this changes a WRITE gate, not data. Client writers hitting it: `ExpenseService.stageExpense`/`addExpense` (create), `edit_expense_screen.dart` (update + soft-delete). All are reachable only by users who can READ the event (already `isGroupMember`-gated), so no legitimate client flow loses authority. Admin-SDK writers (`claimShadowEngine` re-key, `deleteAccount` scrub, `expenseAuditLogger`) bypass rules — unaffected.
2. **Concrete claims verified against code** — every line number above re-read this session (not taken from the issue); fixture names (`seedExpense`, `validExpense`, `updateSeedGroup`, `addGroupMember`) grepped in `functions/test/firestore-rules-publish-readiness.test.ts:41-260`.
3. **Read-path per write-path** — no data-shape change. The "readers" of the gate are the emulator rules tests; the departed-member deny + remaining-member allow are both asserted below.
4. **Fields from the type** — no field changes; `validExpense()` fixture (`:170-190`) already produces a doc valid under every OTHER conjunct, so the new tests isolate the membership term.
5. **Data contracts spelled out** — exact rules fn names (`validExpenseCreate`, `validExpenseUpdate`, `isGroupMember`), exact seed state (g1 `memberIds: ['owner','member']`, e1 `participantIds: ['owner','member']`), exact departure mutation (`memberIds: ['owner']` + delete `groups/g1/members/member` — mirrors what `leaveGroup`/`removeMember` actually write).
6. **Arithmetic decomposition** — N/A (no money math). Oracle universe (`participants()`, counterparty gates, `splitDistribution.keys().hasOnly(participants())`) untouched; parity contract intact.
7. **Adversarial orthogonal axis** — checked axes beyond WHO-writes-expenses:
   - **Founding batch (#874):** `eventAcceptsExpenseWrites → groupAllowsClientWrites → exists(groupPath)` already requires the group to exist in BEFORE-state, so an expense could never ride the founding batch even today; the new before-state `isGroupMember` adds no new batch constraint.
   - **Settlements:** create already `isGroupMember` (#752); updates dead-denied (`allow update: if false`). No change.
   - **Departed member as COUNTERPARTY:** current member editing an expense whose payer/split includes a departed participant still passes — `participants()` (event `participantIds`) untouched, and the remaining-member test below pins it (seeded expense has `createdBy: 'owner'`, split across owner+member, edited by owner AFTER member departs).
   - **Offline replay:** a member with a queued expense write who is removed before reconnect now gets the replay silently discarded (SDK drops denied replays). Correct — matches their simultaneous read loss; no UI gating change needed (they can't see the group anymore anyway).
   - **Shadow members:** uuid-keyed, never authenticate, never write — unaffected.
   - **Event-doc / group-settlement / activity_logs write paths:** out of scope (activity_logs client-create already impossible; event-update authz is a different surface — no known hole; group-settlement create already member-gated).

## Tasks

### Task 1: RED — regression tests for the departed-member hole

**Files:**
- Modify: `functions/test/firestore-rules-publish-readiness.test.ts` (append a new describe after the `#248 PR4` block, near line 2160)

**Step 1: Write the failing tests**

```ts
describe('#1131 departed member loses expense write authority', () => {
  // leaveGroup/removeMember drop the uid from memberIds + delete the member
  // doc but NEVER prune event participantIds (balance-universe preservation),
  // so participation alone must not grant writes: the gate requires CURRENT
  // membership too. Read access was always membership-gated; these pin the
  // write side to the same boundary.
  async function departMember(): Promise<void> {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await db.doc('groups/g1').update({ memberIds: ['owner'], updatedAt: new Date() });
      await db.doc('groups/g1/members/member').delete();
    });
  }

  test('departed member (still in participantIds) cannot CREATE an expense', async () => {
    await departMember();
    const departed = testEnv.authenticatedContext('member').firestore();
    await assertFails(departed.doc('groups/g1/events/e1/expenses/expDeparted').set(
      validExpense({ id: 'expDeparted', createdBy: 'member', payerParticipantId: 'member' }),
    ));
  });

  test('departed member cannot UPDATE an expense', async () => {
    await seedExpense(); // createdBy 'owner'
    await departMember();
    const departed = testEnv.authenticatedContext('member').firestore();
    await assertFails(departed.doc('groups/g1/events/e1/expenses/exp1').update({
      amountFils: 12500,
      lastEditedBy: 'member',
    }));
  });

  test('departed member cannot SOFT-DELETE an expense', async () => {
    await seedExpense();
    await departMember();
    const departed = testEnv.authenticatedContext('member').firestore();
    await assertFails(departed.doc('groups/g1/events/e1/expenses/exp1').update({
      isDeleted: true,
      deletedAt: new Date().toISOString(),
      lastEditedBy: 'member',
    }));
  });

  // Over-blocking guard: the remaining member keeps full write authority —
  // including on an expense whose split still references the departed
  // participant (participants() untouched, #249 parity).
  test('remaining member still creates and edits normally after a departure', async () => {
    await seedExpense(); // split references both owner and member
    await departMember();
    const owner = testEnv.authenticatedContext('owner').firestore();
    await assertSucceeds(owner.doc('groups/g1/events/e1/expenses/exp1').update({
      amountFils: 12500,
      lastEditedBy: 'owner',
    }));
    await assertSucceeds(owner.doc('groups/g1/events/e1/expenses/expOwner').set(
      validExpense({ id: 'expOwner', createdBy: 'owner', payerParticipantId: 'owner' }),
    ));
  });
});
```

**Step 2: Run to verify RED for the right reason**

Run: `cd functions && npm run test:emulator -- firestore-rules-publish-readiness.test.ts -t "#1131"`

Expected: the three departed-member tests FAIL with "Expected request to fail, but it succeeded" (proving the vuln is live); the remaining-member guard PASSES.

**Step 3: Commit the RED suite**

```bash
git add functions/test/firestore-rules-publish-readiness.test.ts
git commit -m "test(rules): RED — departed member retains expense write authority (#1131)"
```

### Task 2: GREEN — add the membership conjunct

**Files:**
- Modify: `security/firestore.rules:779-796` (`validExpenseCreate`) and `:828-838` (`validExpenseUpdate`)

**Step 1:** Insert `&& isGroupMember(groupId)` after the `module == 'expenses'` term in both functions, with the #1131 comment (full text in "Fix shape" above; short pointer comment on the update fn).

**Step 2:** Update the now-stale test-file comment above `'#248 PR4 group-member who is NOT an event participant cannot update expense'` (~line 2135): the boundary is now BOTH `isGroupMember` AND `isEventParticipant`; that test pins the participation half, #1131's pin the membership half.

**Step 3: Run the targeted tests**

Run: `cd functions && npm run test:emulator -- firestore-rules-publish-readiness.test.ts -t "#1131"`
Expected: all 4 PASS.

**Step 4: Full rules suites (regression + #723 expression-ceiling check)**

Run: `cd functions && npm run test:emulator -- firestore-rules-publish-readiness.test.ts` then `npm run test:emulator -- firestore-rules-cut-modules.test.ts` then `npm run test:emulator -- settlementIdempotency.rules.test.ts` then `npm run test:emulator -- decomposed-settleup-batch.test.ts`
Expected: all green. **If any test dies with "maximum of 1000 expressions": apply the documented fallback (inline `request.auth.uid in groupData(groupId).memberIds`), re-run.**

**Step 5: Commit**

```bash
git add security/firestore.rules functions/test/firestore-rules-publish-readiness.test.ts
git commit -m "fix(rules): require current group membership for expense writes (#1131)"
```

### Task 3: Docs truth sweep

**Files:**
- Modify: `CLAUDE.md` — Key Invariants B1 bullet: "any event participant may edit/soft-delete any non-deleted expense — `validExpenseUpdate` gates on `isEventParticipant` alone" → gates on `isGroupMember` + `isEventParticipant` (#1131); keep the `ledgerEditPolicy` future note intact.
- Modify: `docs/SECURITY-RULES.md` — expense rows/sections describing the write gate as "event participants" (lines ~29, 59, 79, 95, 108, 370, 461-485): add the current-membership conjunct. Do NOT touch settlement rows (out of scope; note any staleness as follow-up).

**Step: Commit**

```bash
git add CLAUDE.md docs/SECURITY-RULES.md
git commit -m "docs(rules): expense write gate now requires current membership (#1131)"
```

### Task 4: Ship

**Steps:**
1. Commit this plan file (`docs/plans/2026-07-11-1131-departed-member-expense-writes.md`).
2. Push `-u origin fix/1131-departed-member-expense-writes`; open PR — body: summary + test plan + `Closes #1131` + `Spec:` line pointing at this plan; full-branch diff review (`git diff main...HEAD`).
3. `/automerge` (Gate-category: `security/firestore.rules` → fresh Opus diff review + refuter).
4. Post-merge: rules deploy is pending until the deploy ceremony (`tool/pending_deploy.sh` / `deploy-ceremony`); no client-compat gating (no real users).

## Out of scope (follow-ups, not bundled)

- `docs/SECURITY-RULES.md:30` describes event-settlement create as "event participants" — stale since #752 (now `isGroupMember`). File a docs follow-up if confirmed.
- Departed-member authority on OTHER surfaces (event-doc updates, group-doc writes) — #1132 territory (departed-creator authority), separately tracked.
