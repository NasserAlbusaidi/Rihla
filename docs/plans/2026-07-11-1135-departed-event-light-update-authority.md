# #1135 Departed Event Light-Update Authority Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Resolve #1135 without adding a redundant expression to Firestore's near-ceiling event-update path: pin the existing departed-participant denial in emulator tests and document the actual authorization proof.

**Architecture:** `validEventLightUpdate()` already composes two predicates whose conjunction implies current membership: `requesterIsParticipant()` proves `request.auth.uid ∈ resource.data.participantIds`, while `validEventUpdateCommon()` → `validEventBase(request.resource.data)` proves the unchanged/additive post-write participant list is a subset of `group.memberIds`. Because light updates cannot remove the caller from `participantIds`, a departed caller cannot satisfy both. Keep the rules byte-identical, add behavioral regression coverage, and make this indirect but load-bearing contract explicit in `docs/SECURITY-RULES.md`.

**Tech Stack:** Firestore Rules v2, `@firebase/rules-unit-testing` v5, Jest/TypeScript, Firebase Firestore emulator.

## Global Constraints

- Do not change `security/firestore.rules`; the current authorization set already excludes departed participants, and the event update OR-chain is at the documented #723 near-1000-expression ceiling.
- Do not prune departed UIDs from event `participantIds`; leave/remove intentionally preserve that balance universe.
- Preserve C-Hierarchy: a current group member who is an event participant may still rename, shift dates, edit description, and add current group members; participant removal and destructive changes remain admin-only.
- Build the denial fixture from the real leave/remove state: drop the UID from `groups/{gid}.memberIds`, delete its member doc, and leave it in the event's `participantIds`/`participantNames`.
- The PR is tests/docs only. It closes the false-positive security claim without silently broadening into the separate stale-participant metadata-lockout behavior.

---

## Investigation Result

Issue #1135 claimed `requesterIsParticipant()` was the only membership-related gate on `validEventLightUpdate()`. Live code at `origin/main` `b566cd62564ec330b99236922185b9545b61b1d0` disproves that claim:

- `security/firestore.rules:423-425`: `requesterIsParticipant()` requires the caller UID in the existing event `participantIds`.
- `security/firestore.rules:579-605`: every light update ends in `validEventUpdateCommon()`.
- `security/firestore.rules:571-576`: `validEventUpdateCommon()` validates the post-write event with `validEventBase()`.
- `security/firestore.rules:467-485`: `validEventBase()` requires `data.participantIds.hasOnly(groupMembers())`.
- `security/firestore.rules:600-604`: the light path is additive-only, so it cannot remove the departed caller's stale UID to evade the subset check.
- `functions/src/callables/leaveGroup.ts:154-161` and `functions/src/callables/removeMember.ts:210-217`: departure/removal shrinks `memberIds` and deletes member docs but leaves event participants unchanged.

The same proof holds on the issue's cited baseline `50d96847`. A clean emulator probe against that commit denied both claimed attacks:

```text
PASS test/issue-1135-probe.test.ts
  #1135 issue-baseline probe at 50d96847
    ✓ departed stale participant cannot rename event
    ✓ departed stale participant cannot add a current member
Tests: 2 passed, 2 total
```

A mutation probe isolated the load-bearing predicate. With the event `allow update` temporarily narrowed to `validEventLightUpdate()` alone, both writes still denied. Removing only `validEventBase()`'s `participantIds.hasOnly(groupMembers())` then made both attacks succeed:

```text
FAIL test/issue-1135-probe.test.ts
  ✕ departed stale participant cannot rename event
  ✕ departed stale participant cannot add a current member
Expected request to fail, but it succeeded.
Tests: 2 failed, 2 total
```

This is a logical implication, not accidental fail-closed behavior:

```text
caller ∈ existing participantIds
existing participantIds ⊆ post-write participantIds       (light updates are additive)
post-write participantIds ⊆ current group.memberIds        (validEventBase)
therefore caller ∈ current group.memberIds
```

## Options Considered

### 1. Add `isGroupMember(groupId)` to `validEventLightUpdate()`

Reject. It does not change the allowed set, adds redundant `signedIn()`/`exists()`/membership expressions, and the adjacent #1132 work already proved that the full helper can tip legitimate event-admin allow paths over the 1000-expression ceiling.

### 2. Add only `request.auth.uid in groupData(groupId).memberIds`

Reject. The inline form is cheaper but still behaviorally redundant. No behavioral regression can distinguish it while `requesterIsParticipant()` and `validEventBase()` retain their current contracts, so this would spend expression budget for documentation value alone.

### 3. Keep rules unchanged; pin and document the existing proof

Choose. Emulator tests protect the actual deny behavior, a mutation check proves the tests discriminate the load-bearing subset guard, and documentation makes the indirect authorization contract reviewable without weakening the #723 ceiling margin.

## Verification Principles

1. **Callsite classification:** `requesterIsParticipant()`, `validEventLightUpdate()`, `validEventUpdateCommon()`, and `validEventBase()` are OUTBOUND authorization/validation gates on Firestore event writes. `EventService.updateEvent()` is the named client producer for metadata writes. `joinGroupByInviteCode`/`addShadowMember` use the Admin SDK and bypass peer rules.
2. **Concrete claims:** Every path, function, line, and write-map claim above was re-read from live code in this worktree. The issue text and #1132 spec were treated as hypotheses, not proof.
3. **Read path per write path:** No data shape changes. A successful metadata write would flow through `EventService.watchGroupEvents()`/`watchEvent()` into `Event.fromDoc()`; the tested departed writes are denied before persistence, so those readers see no mutation.
4. **Fields from the type:** `Event` carries `id`, `name`, `type`, `groupId`, `createdBy`, `participantIds`, `participantNames`, `modules`, `startDate`, `endDate`, `isDeleted`, `deletedAt`, `createdAt`, `updatedAt`, `description`, `isClosed`, `closedAt`, `closedBy`, and `spendingSnapshot`. This plan changes none.
5. **Data contracts:** The metadata attack uses the exact `EventService.updateEvent()` partial-map shape: `name` plus `updatedAt`. The additive attack uses the rule's exact light allow-list shape: `participantIds`, `participantNames`, and `updatedAt`. The departure fixture changes group `memberIds` and deletes `groups/g1/members/member`, while event `e1` retains `member` in both participant fields.
6. **Arithmetic decomposition:** N/A. Money algorithms and persisted monetary fields do not change. Keeping `participantIds` untouched preserves the existing balance-universe contract.
7. **Orthogonal axes:** Identity: leave/remove state is reproduced exactly. Money: no participant pruning or oracle change. Time: #723 close/reopen remains on its separate admin path and its existing departed-participant allow test stays green. Offline: a queued light update replayed after departure remains denied by replay-time state. Locale/derived surfaces: no user-facing copy, export, notification, activity, or l10n change.

## Known Adjacent Behavior, Out of Scope

Because `validEventBase()` validates the whole post-write participant list, an event retaining any departed participant also blocks ordinary light metadata edits by remaining participants until a current admin removes the stale participant in the same update. `validEventCloseToggle()` deliberately bypasses `validEventBase()` so close/reopen still works with departed participants. This is the inverse of #1135's security claim and may deserve a separate product decision, but changing that coupling would require a new rule that admits existing departed IDs while constraining only newly-added IDs to current members. That is not a safe side effect for this PR.

---

### Task 1: Pin the Existing Denial in the Rules Emulator

**Files:**
- Modify: `functions/test/firestore-rules-publish-readiness.test.ts`

**Interfaces:**
- Consumes: `seedBaseData()`, `addGroupMember()`, `testEnv`, `assertFails()`.
- Produces: the `#1135 departed event participant light-update authority` regression block.

- [ ] **Step 1: Add the exact departure fixture and two behavioral tests**

```ts
describe('#1135 departed event participant light-update authority', () => {
  async function departMember(remainingMemberIds: string[]): Promise<void> {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await db.doc('groups/g1').update({
        memberIds: remainingMemberIds,
        updatedAt: new Date(),
      });
      await db.doc('groups/g1/members/member').delete();
    });
  }

  test('departed participant cannot rename an event', async () => {
    await departMember(['owner']);
    const departed = testEnv.authenticatedContext('member').firestore();
    await assertFails(departed.doc('groups/g1/events/e1').update({
      name: 'Hijacked Camp',
      updatedAt: new Date(),
    }));
  });

  test('departed participant cannot add a current member to an event', async () => {
    await addGroupMember('guest', 'Guest');
    await departMember(['owner', 'guest']);
    const departed = testEnv.authenticatedContext('member').firestore();
    await assertFails(departed.doc('groups/g1/events/e1').update({
      participantIds: ['owner', 'member', 'guest'],
      participantNames: { owner: 'Owner', member: 'Member', guest: 'Guest' },
      updatedAt: new Date(),
    }));
  });
});
```

- [ ] **Step 2: Run the focused tests against unchanged rules**

Run:

```bash
cd functions
npm run test:emulator -- firestore-rules-publish-readiness.test.ts -t '#1135'
```

Expected: 2 passed. Passing immediately is the investigation result: production behavior already denies the attack; this task adds missing coverage rather than a new behavior.

- [ ] **Step 3: Prove the tests discriminate the existing guard**

In the isolated worktree only, temporarily remove this one conjunct from `validEventBase()`:

```rules
&& data.participantIds.hasOnly(groupMembers())
```

Also temporarily narrow the event update allow to `validEventLightUpdate()` only, so the OR-chain's fail-closed expression ceiling cannot mask the light-path result. Re-run the focused command.

Expected: both tests FAIL with `Expected request to fail, but it succeeded.` Restore both temporary mutations with `git diff` as the source of truth, then re-run and expect 2 passed. Commit no rules change.

- [ ] **Step 4: Commit the behavioral coverage**

```bash
git add functions/test/firestore-rules-publish-readiness.test.ts
git commit -m "test(rules): pin departed event light-update denial (#1135)"
```

### Task 2: Correct the Rules Documentation

**Files:**
- Modify: `docs/SECURITY-RULES.md`

**Interfaces:**
- Consumes: the live helper composition above.
- Produces: an explicit current-membership proof for event light updates.

- [ ] **Step 1: Tighten the quick-reference row**

Change the event update cell from `event participants (light)` to `current-member event participants (light, #1135)` while retaining the current-member admin wording.

- [ ] **Step 2: Explain the indirect membership proof in the light-path section**

After “Any current event participant,” state that current group membership is enforced by composition: caller in existing `participantIds`, additive post-write list, and `validEventBase()` requiring the post-write list to contain only current `group.memberIds`. State that a separate `isGroupMember()` conjunct is intentionally omitted because it is redundant on the #723 near-ceiling OR-chain.

- [ ] **Step 3: Document the stale-participant consequence without fixing it here**

State that retaining a departed UID makes ordinary light metadata updates fail until an admin removes the stale participant, while close/reopen remains available through `validEventCloseToggle()`'s deliberate base-validation bypass. Label any redesign of this coupling as separate scope.

- [ ] **Step 4: Commit the documentation correction**

```bash
git add docs/SECURITY-RULES.md
git commit -m "docs(rules): clarify event light-update membership proof (#1135)"
```

### Task 3: Verify and Publish

**Files:**
- Verify: `security/firestore.rules` remains byte-identical to `origin/main`.
- Verify: `functions/test/firestore-rules-publish-readiness.test.ts`.
- Verify: `docs/SECURITY-RULES.md`.
- Verify: this plan.

- [ ] **Step 1: Run focused and rules regression suites**

```bash
cd functions
npm run test:emulator -- firestore-rules-publish-readiness.test.ts
npm run test:emulator -- firestore-rules-cut-modules.test.ts
npm run test:emulator -- settlementIdempotency.rules.test.ts
npm run test:emulator -- decomposed-settleup-batch.test.ts
```

Expected: every suite exits 0. Compare the full readiness suite's “maximum of 1000 expressions” artifact count to the unchanged baseline; a tests/docs-only diff must not change it.

- [ ] **Step 2: Run repository checks**

```bash
bash tool/check_theme_purity.sh
flutter analyze
flutter test --reporter compact
git diff --check origin/main...HEAD
git diff --exit-code origin/main -- security/firestore.rules
```

Expected: every command exits 0; the final command prints no rules diff.

- [ ] **Step 3: Review the whole branch diff**

Review `git diff origin/main...HEAD`, then dispatch a zero-history code reviewer against this plan and the full commit range. Resolve every Critical/Important finding before publish.

- [ ] **Step 4: Push and open a draft PR**

Use a conventional commit and a draft PR. The PR body must include the live reproduction, mutation proof, Gate verdicts, verification commands, and `Closes #1135`. It must say explicitly that no rules expression changed and that backend deployment is unnecessary for this tests/docs-only resolution.

## Acceptance Checklist

- The committed emulator tests deny both the metadata-vandalism and additive-injection shapes from a departed participant whose UID remains in the event.
- Mutation proof shows those tests fail if the existing participant-subset invariant is removed.
- Existing current-participant rename/add tests and #723 close-with-departed-participant test remain green.
- `security/firestore.rules` has no branch diff.
- Documentation describes the actual composed authorization proof and the adjacent stale-participant metadata lockout.
- The hardened Gate reaches a same-round pair with zero P1 findings before implementation.
- The final draft PR carries `Closes #1135` and does not claim a production rules change.
