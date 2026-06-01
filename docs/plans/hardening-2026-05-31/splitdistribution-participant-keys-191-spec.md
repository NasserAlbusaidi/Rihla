# Spec - #191 splitDistribution participant-key hardening

Issue: #191.

Risk surface: `security/firestore.rules`, expense write shape, money balance read path. Gate required before implementation.

## Concern

`splitDistribution` is an expense write field whose keys are participant IDs. Today rules only require it to be a map. A forged client can write a key that is not in the event's `participantIds`; the balance reader allocates across that key, then drops it because the owed map is seeded only for real participants. The payer still keeps the full `paid` amount, so ledger conservation breaks for visible members.

## Verification Report

Load-bearing current-state claims below were checked against code on branch
`fix/splitdistribution-participant-keys-191`. Rows explicitly marked
pre-change are historical evidence from `origin/main` at `f06d05f`, before the
#191 rule change.

| Claim | Command / path | Result |
|---|---|---|
| Rules have access to event participant IDs through `participants()` | `nl -ba security/firestore.rules | sed -n '430,515p'` | `participants()` returns `eventData(groupId, eventId).participantIds`; used by expense validators. |
| Pre-change: `validExpenseSplit` only validates mode and map-ness | `git show f06d05f:security/firestore.rules | nl -ba | sed -n '433,438p'` | It allows any map keys; no `.keys().hasOnly(participants())`. |
| Pre-change: `customSplitParticipants` already has a participant-subset guard | `git show f06d05f:security/firestore.rules | nl -ba | sed -n '470,472p'` | `data.customSplitParticipants.hasOnly(participants())` is the local pattern to mirror. |
| Pre-change: expense create and update both route through `validExpenseBase` | `git show f06d05f:security/firestore.rules | nl -ba | sed -n '482,520p'` | A single `validExpenseSplit` change covers create and update payloads. |
| Client add path writes `splitDistribution` directly from the editor payload after encoding values | `lib/features/ledger/services/expense_service.dart:85-131`, `:324-345` | OUTBOUND. Keys are whatever the caller supplied; service encodes values only. |
| Client update path writes `splitDistribution` directly when non-equal split mode is provided | `lib/features/ledger/services/expense_service.dart:235-274` | OUTBOUND. Same key trust boundary as add. |
| Stock UI builds split participants from event participant IDs or selected custom participant IDs | `lib/features/ledger/widgets/expense_editor_body.dart:336-383` | OUTBOUND producer is safe in stock UI, but forged clients can bypass it; rules remain the trust boundary. |
| Balance reader drops allocations for keys outside the participant universe | `lib/features/ledger/providers/expense_provider.dart:140-184` | `owedMap` is seeded from participants; allocations are applied only when `owedMap.containsKey(entry.key)`. |
| Allocation functions allocate over all `splitDistribution` keys before the drop | `expense_provider.dart:283-430` | Shares/exact/percent use distribution keys; fallback equal split can also use distribution keys. |
| Existing parity test pins current ghost-drop impact | `test/unit/delete_group_balance_parity_test.dart:112-150` | Current behavior is intentional for parity with `deleteGroup`, not a reason to allow new malformed writes. |
| Disposable emulator repro accepts the malformed write today | `RIHLA_FIREBASE_EMULATOR_TEST_COMMAND='node -e ...' bash tool/run_firebase_emulator_tests.sh` | Printed `RULES_ACCEPTED_GHOST_SPLIT`. |
| In-memory proposed rule probe allows valid keys and rejects a ghost key | same harness with rules string patched in memory | Printed `PROPOSED_RULE_REJECTS_GHOST_AND_ALLOWS_VALID`. |

## Gate Revision R1

Fresh-context Gate review found one [P1], now resolved in this spec:

- **Do not revalidate stale historical distributions on unrelated updates.** The first draft added a participant-key guard inside `validExpenseSplit(data)` for every call to `validExpenseBase(request.resource.data)`. Because `validExpenseUpdate()` calls `validExpenseBase` for every update, a valid expense could become unwritable after an event admin removes a participant. Example: owner creates a split over `{owner, member}`, event creator later removes `member` from `participantIds`, then owner tries to soft-delete or edit the note. The first-draft rule would reject because the unchanged old `splitDistribution` still includes `member`. R1 resolution: create writes are always strict; updates enforce participant-key validation only when the update touches balance/allocation fields. Unrelated metadata edits and soft-delete remain available for stale docs.

## Gate Revision R2

Fresh-context Gate review found no [P1]s. It raised one [P2] and two [P3]s, resolved here:

- **P2 wording fix:** stale-doc preservation is scoped to stale `splitDistribution` keys only. `validExpenseBase` still revalidates `payerParticipantId in participants()` and `customSplitParticipants.hasOnly(participants())` on every update. This spec does not broaden stale payer/custom-participant handling.
- **P3 test-order fix:** the stale-distribution regression test checks allocation-field rejection before soft-delete, then separately checks soft-delete success.
- **P3 comment fix:** update the #190 parity-test comment that currently says rules never constrain `splitDistribution`, because after #191 rules reject new malformed writes while the parity assertion still documents legacy/read-path behavior.

## Gate Revision R3

PR review found no correctness defect in #191, but noted that the stale-doc
regression test could be read as a general stale-participant guarantee. Added a
negative test for the current limitation: if the participant removed from the
event is still the expense payer, soft-delete remains denied by the existing
unconditional `payerParticipantId in participants()` guard. That limitation is
pre-existing and out of scope for #191.

## Required Behavior

1. Expense creates with a non-empty `splitDistribution` whose keys are all event participants must continue to pass.
2. Expense updates changing `splitDistribution` to participant-only keys must continue to pass.
3. Expense creates with any `splitDistribution` key outside the event's `participantIds` must fail rules validation.
4. Expense updates that introduce outside keys or change balance/allocation fields while retaining outside keys must fail rules validation.
5. Expense updates that touch only non-balance metadata (`description`, `receiptUrl`, `categoryId`, `note`) must not become blocked solely because an unchanged historical `splitDistribution` references a participant who was later removed from the event. This exemption is only for stale `splitDistribution` keys; it does not relax existing payer/custom-participant validation.
6. Expense soft-delete updates (`isDeleted`, `deletedAt`) must not become blocked solely because an unchanged historical `splitDistribution` references a participant who was later removed from the event. This exemption is only for stale `splitDistribution` keys.
7. Expenses with no `splitDistribution` field must keep their existing behavior for equal/legacy split paths.
8. This issue does not change `BalanceCalculator`, `deleteGroup`, `ExpenseService`, or editor UI behavior.

## Design

Modify only `security/firestore.rules`.

```rules
function validExpenseSplit(data, enforceParticipantKeys) {
  return (!data.keys().hasAny(['splitMode'])
      || data.splitMode in ['equally', 'shares', 'exact', 'percent'])
    && (!data.keys().hasAny(['splitDistribution'])
      || (data.splitDistribution is map
        && (!enforceParticipantKeys
          || data.splitDistribution.keys().hasOnly(participants()))));
}
```

Add a parameter to `validExpenseBase(data, enforceParticipantKeys)` and pass it through to `validExpenseSplit`.

Create writes call `validExpenseBase(request.resource.data, true)`.

Update writes compute whether the update touches fields that can change balances or allocation semantics:

```rules
function affectsExpenseAllocation() {
  return request.resource.data.diff(resource.data).affectedKeys().hasAny([
    'payerParticipantId',
    'amountFils',
    'currency',
    'scope',
    'subGroupId',
    'customSplitParticipants',
    'splitMode',
    'splitDistribution'
  ]);
}
```

Then `validExpenseUpdate()` calls:

```rules
validExpenseBase(request.resource.data, affectsExpenseAllocation())
```

This rejects new or reworked malformed split distributions without stranding stale docs for note/description/category/receipt edits or soft delete.

## Tests

Modify `functions/test/firestore-rules-publish-readiness.test.ts`.

Add RED-first tests under the existing expense rules section:

```ts
test('#191 expenses reject splitDistribution keys outside event participants', async () => {
  const member = testEnv.authenticatedContext('member').firestore();

  await assertSucceeds(member.doc('groups/g1/events/e1/expenses/expShares').set(
    validExpense({
      id: 'expShares',
      splitMode: 'shares',
      splitDistribution: { owner: 1, member: 1 },
    }),
  ));

  await assertFails(member.doc('groups/g1/events/e1/expenses/expGhostCreate').set(
    validExpense({
      id: 'expGhostCreate',
      splitMode: 'shares',
      splitDistribution: { owner: 1, ghost: 1 },
    }),
  ));

  const ref = member.doc('groups/g1/events/e1/expenses/expUpdateGhost');
  await assertSucceeds(ref.set(validExpense({ id: 'expUpdateGhost' })));
  await assertFails(ref.update({
    splitMode: 'percent',
    splitDistribution: { owner: 50000, ghost: 50000 },
  }));
});

test('#191 stale splitDistribution after participant removal can still be archived', async () => {
  const owner = testEnv.authenticatedContext('owner').firestore();
  const ref = owner.doc('groups/g1/events/e1/expenses/expStale');

  await assertSucceeds(ref.set(validExpense({
    id: 'expStale',
    createdBy: 'owner',
    splitMode: 'shares',
    splitDistribution: { owner: 1, member: 1 },
  })));
  await assertSucceeds(owner.doc('groups/g1/events/e1').update({
    participantIds: ['owner'],
    updatedAt: new Date(),
  }));

  await assertFails(ref.update({
    amountFils: 24000,
  }));
  await assertSucceeds(ref.update({
    note: 'archival note',
  }));
  await assertSucceeds(ref.update({
    isDeleted: true,
    deletedAt: new Date().toISOString(),
  }));
});
```

Run RED:

```bash
RIHLA_FIREBASE_EMULATOR_TEST_COMMAND="npx --yes node@20 node_modules/jest/bin/jest.js --runInBand test/firestore-rules-publish-readiness.test.ts --testNamePattern '#191'" bash tool/run_firebase_emulator_tests.sh
```

Expected RED: the create assertion for `expGhostCreate` succeeds unexpectedly, so the test fails with an `assertFails` failure.

Run GREEN after the rule change:

```bash
RIHLA_FIREBASE_EMULATOR_TEST_COMMAND="npx --yes node@20 node_modules/jest/bin/jest.js --runInBand test/firestore-rules-publish-readiness.test.ts --testNamePattern '#191'" bash tool/run_firebase_emulator_tests.sh
```

Expected GREEN: the #191 test passes.

Broaden verification:

```bash
RIHLA_FIREBASE_EMULATOR_TEST_COMMAND="npx --yes node@20 node_modules/jest/bin/jest.js --runInBand test/firestore-rules-publish-readiness.test.ts" bash tool/run_firebase_emulator_tests.sh
flutter test test/unit/delete_group_balance_parity_test.dart --plain-name "case 2: out-of-universe ghost share is DROPPED"
git diff --check
```

Expected: publish-readiness rules suite passes; parity test still passes; no whitespace errors.

## Out Of Scope

- #192 value-domain validation for negative shares, negative exact values, and percent sums.
- Rewriting malformed historical docs. Existing bad docs remain readable and balance behavior stays as currently pinned.
- Changing `BalanceCalculator` fallback behavior. That is a separate compatibility/remediation decision because the server `deleteGroup` parity tests intentionally mirror the current client behavior.
- Adding Cloud Functions or server-side write counters.

## Gate Status

- R0 author checklist complete from current code and issue #191.
- R1 fresh-context Gate review: one [P1], resolved in this spec.
- R2 fresh-context Gate review: no [P1]s; [P2]/[P3] wording/test-comment cleanups incorporated.
