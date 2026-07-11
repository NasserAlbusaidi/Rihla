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

Issue #1135 claimed `requesterIsParticipant()` was the only membership-related gate on `validEventLightUpdate()`. Live code at `origin/main` `6cc3e67959fd7dec48423e960ad0903a626b277d` disproves that claim:

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
7. **Orthogonal axes:** Identity: leave/remove state is reproduced exactly. Money: no participant pruning or oracle change in this branch; the distinct post-departure balance-input and removal-serialization bug is tracked as #1144. Time: #723 close/reopen remains on its separate admin path and its existing departed-participant allow test stays green. Offline: a queued light update replayed after departure remains denied by replay-time state. Locale/derived surfaces: this branch changes no user-facing copy, export, notification, activity, or l10n behavior. Gate review found PRE-EXISTING stale-participant side effects outside this branch: independently queued mutations can leave phantom activity (#1140), and membership-scoped pushes can target users after revocation (#1141). All are tracked separately rather than hidden or bundled here.

## Known Adjacent Behavior, Out of Scope

Because `validEventBase()` validates the whole post-write participant list, an event retaining any departed participant also blocks ordinary light metadata edits by remaining participants. The rules would admit a current-admin update that removes every stale participant, but the current `EventService` and event settings UI expose no participant-add/remove method. Practical in-app recovery is therefore limited to every stale real member rejoining (fan-in restores current membership); otherwise repair needs an out-of-band Admin SDK write or a future participant-management feature. `validEventCloseToggle()` deliberately bypasses `validEventBase()` so close/reopen still works with departed participants. This is the inverse of #1135's security claim and may deserve a separate product decision, but changing that coupling would require a new rule that admits existing departed IDs while constraining only newly-added IDs to current members. That is not a safe side effect for this PR.

Three adjacent consequences discovered by the Gate are also real but independent of this tests/docs resolution:

- **#1140:** event create/delete and event/group-settlement flows write user-visible activity separately from the primary mutation. A queued or denied primary write can therefore leave a successful phantom history row. The follow-up inventories every mutation-adjacent logger and requires atomic/deduplicated primary-write-plus-activity semantics across online, offline replay, and retry.
- **#1141:** membership-scoped event, expense, event/group-settlement, and member-join senders use committed/pre-transaction recipient snapshots without a fresh delivery-time membership intersection. The follow-up requires a fail-closed current-membership lookup immediately before those sends, preserves intentionally cross-membership claim flows, and explicitly acknowledges the remaining leave-after-final-lookup race.
- **#1144:** departure keeps historical event participants for balance conservation, but steady-state expense/event-settlement writes can still give those UIDs fresh deltas. Independently, `leaveGroup`/`removeMember` compute zero before their membership transaction, so any balance-oracle input can race into the gap—including expense/settlement/correction rows and event `participantIds`/`isDeleted` mutations that redistribute or remove existing expenses. The follow-up requires a dependency matrix over both oracles and fences every client/Admin producer (including join fan-in and recovery/rekey paths) through a recoverable lock or revision protocol.

All three predate this branch, remain behaviorally unchanged by it, and require their own focused specs/tests. Folding any of them into #1135 would violate the one-concern rule and turn a rules-refutation PR into unrelated client and Cloud Functions changes.

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

- [ ] **Step 3: Prove the tests discriminate the existing guard in three states**

Record all three states separately; do not combine two mutations into one unexplained rerun:

1. **Unchanged rules:** both denial tests pass.
2. **Light-only allow, guard present:** temporarily narrow event `allow update` to `validEventLightUpdate()` only; both denial tests still pass. This removes the OR-chain expression-ceiling confound.
3. **Light-only allow, guard absent:** while state 2 is active, temporarily remove this one conjunct from `validEventBase()`:

```rules
&& data.participantIds.hasOnly(groupMembers())
```

Expected in state 3: both tests FAIL with `Expected request to fail, but it succeeded.` Restore the subset guard, verify state 2 passes again, then restore the full OR-chain and verify state 1 passes. Use `git diff -- security/firestore.rules` after each restoration and commit no rules change.

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

Change the section introduction from “two update paths” to **three**: light, admin, and close-toggle. After “Any current event participant,” state that current group membership is enforced by composition: caller in existing `participantIds`, additive post-write list, and `validEventBase()` requiring the post-write list to contain only current `group.memberIds`. State that a separate `isGroupMember()` conjunct is intentionally omitted because it is redundant on the #723 near-ceiling OR-chain.

- [ ] **Step 3: Document the stale-participant consequence without fixing it here**

State that retaining a departed UID makes ordinary light metadata updates fail. Clarify that the rules could admit a current-admin cleanup but no current client service/UI exposes participant removal; rejoin or out-of-band/future repair is required. Close/reopen remains available through `validEventCloseToggle()`'s deliberate base-validation bypass. Label any redesign of this coupling as separate scope.

- [ ] **Step 4: Document the close-toggle path as a first-class third path**

Add a close-toggle subsection with its exact allow-list (`isClosed`, `closedAt`, `closedBy`, `updatedAt`, optional bounded `spendingSnapshot`), current-member event/group creator authority, and explicit reason for bypassing `validEventBase()` when historical participants remain.

- [ ] **Step 5: Correct the event-create key contract**

Replace the existing contradictory “must contain exactly these keys” wording with two explicit sets: the required event-create base keys, and the optional allowlisted close keys `isClosed`, `closedAt`, and `closedBy`. State that each close key is optional on create, but when present the only valid birth state is `isClosed: false`, `closedAt: null`, `closedBy: null`, matching `Event.toFirestoreMap()` and `validEventCreate()`.

- [ ] **Step 6: Commit the documentation correction**

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

Expected: every suite exits 0. The rules blob stays byte-identical, but the combined runner stream's exact substring count is expected to rise by **exactly 2** because each new denied write reaches the existing fail-closed OR-chain ceiling. Use this exact counting contract (combined stdout/stderr from the wrapper; one increment per output line containing the literal phrase):

```bash
set -o pipefail
npm run test:emulator -- firestore-rules-publish-readiness.test.ts 2>&1 \
  | awk '/maximum of 1000 expressions/{n++} /Test Suites:|Tests:|Script exited successfully/{print} END{print "expression_ceiling_artifacts=" n+0}'
```

Gate round 1 and an independent controller run both measured `expression_ceiling_artifacts=49` on the pre-test suite. Verify `51` after implementation. A different delta requires investigation. Do not use the warning count as a rules-equivalence claim; `git diff --exit-code origin/main -- security/firestore.rules` is the direct proof.

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

## Gate Record

Round 1 (2026-07-11): rubric `1 P1 / 0 P2 / 0 P3`; adversary `2 P1 / 1 P2 / 0 P3`.

- Rubric P1 resolved: the plan no longer claims raw expression-warning count is unchanged. Each added denied write contributes one existing ceiling artifact; expected delta is +2, while a byte-identical rules diff is the rules-equivalence proof.
- Adversary P1s resolved without scope bundling: the phantom `event_deleted` side effect is tracked as #1140 and departed-recipient money pushes as #1141. Both are explicitly pre-existing, behaviorally untouched, and assigned focused fixes.
- Adversary P2 resolved: Task 2 now corrects the documentation's “two update paths” statement and adds the close-toggle path as the third live path.

Round 2 (2026-07-11): rubric `0 P1 / 0 P2 / 1 P3`; adversary `1 P1 / 1 P2 / 0 P3`.

- Adversary P1 resolution at this round: #1141 was expanded to expense-created and event-settlement pushes. Its attempted group-settlement exemption was later refuted in round 3 because trigger delivery is asynchronous.
- Adversary P2 resolved: the stale-participant section no longer implies a current UI/service recovery path. It distinguishes the rules-admissible admin repair from actual in-app recovery (rejoin) and out-of-band/future participant management.
- Rubric P3 resolved: the branch rebased onto current `origin/main` `6cc3e679`, and the investigation baseline SHA above now matches it.

Round 3 (2026-07-11): rubric `0 P1 / 3 P2 / 0 P3`; adversary `1 P1 / 0 P2 / 0 P3`.

- Adversary P1 resolved: #1141 now covers all three money-notification paths. Group-settlement membership is rechecked at delivery time because commit-time validity does not survive the commit-to-trigger delay; lookup failure must send nothing.
- Rubric P2 mutation isolation resolved: Task 1 records unchanged-rules deny, light-only-with-guard deny, and light-only-without-guard allow as three distinct states.
- Rubric P2 counting ambiguity resolved: Task 3 specifies the exact combined stream, substring, and `awk` counting command that produced baseline 49 and expects post-test 51.
- Rubric P2 documentation gap resolved: Task 2 corrects the event-create close triple and its optional-but-pinned `false/null/null` birth state.

Round 4 (2026-07-11): rubric `0 P1 / 0 P2 / 0 P3`; adversary `2 P1 / 0 P2 / 0 P3`.

- Adversary P1 future-debt finding isolated: #1144 now tracks the distinction between retaining historical parties for balance conservation and excluding departed parties from future expense-recipient eligibility. It is a separate money/rules decision and does not alter #1135's authorization proof.
- Adversary P1 notification boundary expanded: #1141 now covers every verified membership-scoped sender (event, expense, event/group settlement, and member join), while preserving intentionally cross-membership claim flows. It requires a fail-closed fresh membership filter immediately before send and records the unavoidable leave-after-final-lookup race.

Round 5 (2026-07-11): rubric `1 P1 / 0 P2 / 0 P3`; adversary `0 P1 / 0 P2 / 0 P3`.

- Rubric P1 resolved: #1144 was expanded beyond new owed recipients to cover departed payers and every allocation-affecting create/update of a historical expense. Its acceptance contract now protects metadata-only edits and the existing soft-delete/correction path instead of revalidating unchanged historical party fields indiscriminately.

Round 6 (2026-07-11): rubric `2 P1 / 1 P2 / 0 P3`; adversary `2 P1 / 0 P2 / 0 P3`.

- Shared settlement P1 resolved: #1144 now covers event-settlement creates that name departed historical participants and requires an explicit server-authoritative correction route for legitimate former-party adjustments. Group settlements are already current-party-gated but are included in the departure race fence.
- Shared serialization P1 resolved: #1144 now requires every balance-changing client/Admin writer to honor a recoverable membership-mutation lock or money-revision fence. Its tests cover both commit orderings, offline replay, both departure callables, and failure recovery.
- Rubric P2 resolved: Task 2 must replace the event-create documentation's “exact keys” sentence with distinct required-base and optional-close allowlists, preventing the close triple from remaining self-contradictory.

Round 7 (2026-07-11): rubric `1 P1 / 0 P2 / 0 P3`; adversary `2 P1 / 0 P2 / 0 P3`.

- Shared balance-input P1 resolved: #1144 now derives its fence coverage from a reviewed client/server oracle dependency matrix rather than a ledger-document list. It explicitly includes event `participantIds` and `isDeleted`, light/admin updates, join fan-in, recovery/rekey, every other Admin producer, both commit orderings, and offline replay.
- Adversary activity P1 resolved: #1140 now covers independently queued event create/delete and event/group-settlement activity, requires atomic/deduplicated mutation-plus-history semantics, and inventories every remaining mutation-adjacent `logGroupEvent` callsite.
