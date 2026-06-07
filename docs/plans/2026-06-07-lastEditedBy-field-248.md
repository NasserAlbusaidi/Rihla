# `lastEditedBy` Field Implementation Plan (#248 — PR 1 of 5)

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.
> **Spec:** This is the Gate-reviewed spec for #248 PR 1. Run `/run-the-gate` to a no-P1 verdict before writing code. `Refs #248` (does NOT close it).

**Goal:** Add a `lastEditedBy` (auth UID) field to the expense document — client-stamped on every create/edit/soft-delete, rule-pinned `== request.auth.uid` whenever the write touches it — laying the unforgeable, trigger-readable attribution that PR 2's `expenseAuditLogger` will consume. **Edit authorization is unchanged: still creator-only.**

**Architecture:** A Firestore `onDocumentWritten` trigger (PR 2) runs as admin with **no `request.auth`** — it cannot see who wrote a doc. So the actor must live *in* the document. `lastEditedBy` is that field. PR 1 adds it everywhere `createdBy` already lives (model + the three inline service write maps + rules) and pins it so a client can neither forge the blame (rule-pinned to `auth.uid`) nor — once PR 2 ships — skip the log. PR 1 ships the field **additively and backward-compatibly**: the pin only fires when the write actually carries `lastEditedBy`, so a pre-feature client that omits it still writes.

**Tech Stack:** Flutter/Dart (model + service + Riverpod screens), `decimal`, Firestore security rules, `@firebase/rules-unit-testing` emulator (Jest, `functions/test/`), `fake_cloud_firestore` (Dart unit, `test/unit/`).

---

## Scope

**In (PR 1):**
- `Expense.lastEditedBy` field (model: ctor, `fromFirestore`, `toFirestore`, `copyWith`).
- `ExpenseService` stamps it: `addExpense` (= `createdBy`), `updateExpense` (new optional arg), `deleteExpense` (new optional arg).
- `edit_expense_screen.dart` passes the current uid into `updateExpense`/`deleteExpense`.
- `firestore.rules`: permit the key, pin it `== auth.uid` diff-gated, loosen `validSoftDelete` to carry it.
- Tests: Dart unit (model round-trip + service stamping) + rules emulator (pin / forgery / legacy fallback / soft-delete-carries-it / settlement-still-denied).

**Out (later PRs — do NOT build here):**
- The `expenseAuditLogger` trigger + `validActivityCreate` server-only lock → **PR 2**.
- Activity-feed rendering of edit/delete entries → **PR 3**.
- Dropping `requesterIsRecordCreator()` (open editing) + CLAUDE.md B1 rewrite → **PR 4**.
- Editor creator-vs-payer affordance → **PR 5**.
- **Recovery migration of `lastEditedBy` (oldUid→newUid in `functions/src/callables/cleanupAnonUidArtifacts.ts`).** Named follow-up. `createdBy` is already migrated (`cleanupAnonUidArtifacts.ts:410-411`); `lastEditedBy` will want the same so the audit log doesn't attribute to a dead anon UID — but it has **no consumer until PR 2's trigger exists**, so it defers to PR 2 (or its own tiny PR). Tracked here so it isn't lost.

---

## Load-bearing design decisions

### D1 — The pin is **diff-gated on update**, presence-gated on create
- **Create** (`validExpenseCreate`): `(!('lastEditedBy' in request.resource.data) || request.resource.data.lastEditedBy == request.auth.uid)`. On create `request.resource.data` *is* the new doc, so `in` is the right presence test. New clients set it (= `createdBy`, already pinned `== auth.uid`); old clients omit it → pin skipped.
- **Update** (`validExpenseUpdate`): `(!request.resource.data.diff(resource.data).affectedKeys().hasAny(['lastEditedBy']) || request.resource.data.lastEditedBy == request.auth.uid)`. **Diff-gated**, mirroring the existing `expenseFreeTextDiffOk()` pattern (`firestore.rules:517`) and the #194 lesson (gate value checks on the diff, not the full doc).
- **Why diff-gated, not `in`-gated, on update:** `request.resource.data` on an `.update()` is the *merged* doc — a stale `lastEditedBy` from a prior edit is preserved even when this write doesn't touch it. An `in`-based pin would then force every editor to match the *previous* editor. Diff-gating means: touch it → must be you; don't touch it → unconstrained. (In PR 1 the two are equivalent because edit is creator-only and `lastEditedBy` always equals the creator; diff-gating is chosen now so PR 4's open-editing world inherits a pin with no merge-preservation footgun.)

### D2 — `validSoftDelete()` must carry `lastEditedBy` (the sharp edit)
`validSoftDelete()` (`firestore.rules:584`) pins `affectedKeys().hasOnly(['isDeleted','deletedAt'])`. A new client's soft-delete stamps `lastEditedBy` too (so PR 2 can attribute the deleter), making `affectedKeys = {isDeleted, deletedAt, lastEditedBy}` — which the current `hasOnly` **rejects**. Fix: `hasOnly(['isDeleted','deletedAt','lastEditedBy'])`.
- **`validSoftDelete` has exactly two references** (verified `rg`): `:637`, inside `validExpenseUpdate` (LIVE — wired by `allow update: if validExpenseUpdate()` at `:725`), and `:690`, inside `validEventSettlementUpdate` — which is **DEAD CODE**: no `allow` clause references `validEventSettlementUpdate` (verified — its only occurrence is the `:677` definition). Event-settlement updates are hard-denied by the dedicated `match /settlements/{settlementId}` block's `allow update: if false` (`:735`), proven by the green test `event settlement creator cannot update own record` (`firestore-rules-publish-readiness.test.ts:1178` — a creator `update({note})` *fails*, which is impossible if `validEventSettlementUpdate`'s note-permitting branch were live).
- **Therefore loosening `validSoftDelete` touches ONLY the live expense path.** Settlements stay safe not because of any inner allowlist but because their update is dead-denied upstream — loosening a function they no longer reach cannot widen them. No settlement regression is possible from this edit.

### D3 — Client stamps only on a *real* change (no no-op writes)
`updateExpense` keeps its `if (updates.isNotEmpty)` guard and adds `lastEditedBy` **inside** that guard (after it's confirmed non-empty). A "save with nothing changed" stays a no-op — it does **not** write `{lastEditedBy}` alone, so PR 2's trigger won't emit a spurious "edited" entry for a no-op save. `addExpense`/`deleteExpense` always represent a real change, so they always stamp.

### D4 — Field defaults to `''`, mirrors `createdBy` exactly
`fromFirestore` reads `data['lastEditedBy'] as String? ?? ''` (legacy docs → `''`). PR 2's trigger falls back to `createdBy` when `lastEditedBy` is empty (matches AC "legacy no-`lastEditedBy` falls back to `createdBy`"). `toFirestore` writes it unconditionally — **safe because `Expense.toFirestore()` has zero `lib/` callers** (round-trip/test helper only; verified). No production write path persists a default-empty doc through it; the three service write maps are built inline and are the only OUTBOUND paths.

---

## Verification principles (run against this spec — reported out loud)

1. **Callsite classification (INBOUND/OUTBOUND/BOTH).** Three OUTBOUND write maps, all inline (not via `toFirestore`): `addExpense` data map `:130-155` (`.set` at `:157`), `updateExpense` `updates` map (signature `:251`, `.update` at `:296-311`), `deleteExpense` soft-delete map `:326-329` (signature `:316`). One INBOUND read: `fromFirestore:160`. `toFirestore` = neither (no `lib/` caller). Legacy `toJson`/`fromJson` (Supabase) = dead for Firestore — untouched (they don't even carry `createdBy`).
2. **Concrete claims re-verified against code:** `firestore.rules:584` `validSoftDelete` `hasOnly(['isDeleted','deletedAt'])` ✓; `:531` `validExpenseBase` key allowlist ✓; `:606` `validExpenseUpdate` ✓; `:572` `validExpenseCreate` ✓ (pins `createdBy == auth.uid`); `currentUserIdProvider = Provider<String?>` (`group_balance_provider.dart:483`) ✓ nullable; `expense_service.dart` builds all write maps inline ✓; `edit_expense_screen.dart:56` already reads `currentUserIdProvider` ✓; `add_expense_screen.dart:68` passes `createdBy: currentUid` ✓; rules tested via `functions/test/firestore-rules-publish-readiness.test.ts` emulator ✓.
3. **Read-path per write-path.** Who reads `lastEditedBy` after it changes? In PR 1: **nobody yet** (the consumer — PR 2's trigger — doesn't exist; recovery migration deferred, named above). This is why PR 1 is safe to ship alone: a new field with no reader, gated additively. The model round-trips it (`fromFirestore`↔`toFirestore`) but no balance/display path consumes it.
4. **Fields enumerated from the type** (`expense_model.dart:26-60`): id, tripId, payerParticipantId, amount, description, scope, subGroupId, customSplitParticipants, splitMode, splitDistribution, receiptUrl, createdAt, categoryId, note, **createdBy**, categoryName, categoryIcon, payerName, payerAvatarUrl, isDeleted, deletedAt, _currency. `lastEditedBy` is added adjacent to `createdBy`. The *persisted* Firestore key set (`validExpenseBase:531`) is the authoritative allowlist — `lastEditedBy` joins it.
5. **Data contracts (exact):** Firestore key `lastEditedBy: string`. Service signatures: `updateExpense({..., String? lastEditedBy})`, `deleteExpense({..., String? lastEditedBy})`, `addExpense` unchanged (derives `lastEditedBy = createdBy`). Rule pin clauses verbatim in D1/D2. `validExpenseBase` allowlist gains the literal `'lastEditedBy'`. `validExpenseUpdate` affectedKeys allowlist (`:612-628`) gains `'lastEditedBy'`.
6. **Arithmetic decomposition:** N/A — `lastEditedBy` carries no money; balance math (`BalanceCalculator`, `MoneySerializer`) is untouched. (Explicitly confirmed: no allocator, no `splitDistribution`, no `amountFils` change.)
7. **Adversarial pass on an orthogonal axis (identity).** The fix is on the *schema/attribution* axis; the adversarial case exercises **identity-forgery + the shared-function blast radius**: (a) a participant forging `lastEditedBy: <someone-else>` on their own create/update is rejected (Task 5 cases); (b) loosening the *shared* `validSoftDelete` does NOT widen settlements — settlement updates are dead-denied at `allow update: if false` (`:735`) and no longer reach `validSoftDelete` (D2), so the loosening's blast radius is the expense path alone; (c) a non-creator still cannot edit at all in PR 1 (the existing `requesterIsRecordCreator()` deny stays green — regression-pinned by the untouched `expense non-creator cannot update peer record` test `:1101`). Same-axis (money) is deliberately not the example because money is provably untouched.

---

## Tasks

> TDD throughout. Rules emulator tests: `cd functions && npm run test:emulator` (boots emulator + Jest). Dart: `flutter test <file>`. `flutter analyze` clean before any commit. Atomic commits, all `Refs #248`.

### Task 1: Add `lastEditedBy` to the `Expense` model

**Files:**
- Modify: `lib/features/ledger/models/expense_model.dart`
- Test: `test/unit/expense_service_test.dart` (model round-trip is exercised here via `fromFirestore`/`toFirestore`) — or add to an existing model test if present.

**Step 1 — Write the failing test** (add to the model/round-trip group in `test/unit/expense_service_test.dart`):

```dart
test('lastEditedBy round-trips through Firestore serialization', () {
  final e = Expense(
    id: 'e1',
    tripId: 'ev1',
    payerParticipantId: 'p1',
    amount: Decimal.parse('10.5'),
    scope: ExpenseScope.global,
    createdAt: DateTime.parse('2026-06-07T00:00:00.000Z'),
    createdBy: 'uidA',
    lastEditedBy: 'uidB',
  );
  final map = e.toFirestore();
  expect(map['lastEditedBy'], 'uidB');
  final back = Expense.fromFirestore({...map});
  expect(back.lastEditedBy, 'uidB');
});

test('lastEditedBy defaults to empty string for legacy docs', () {
  final back = Expense.fromFirestore({
    'id': 'e1', 'eventId': 'ev1', 'payerParticipantId': 'p1',
    'amountFils': 10500, 'currency': 'OMR', 'scope': 'global',
    'customSplitParticipants': <String>[], 'isDeleted': false,
    'createdAt': '2026-06-07T00:00:00.000Z', 'createdBy': 'uidA',
    // no lastEditedBy
  });
  expect(back.lastEditedBy, '');
});
```

**Step 2 — Run, verify it fails** (`lastEditedBy` not a parameter / getter):
`flutter test test/unit/expense_service_test.dart -p vm` → FAIL.

**Step 3 — Implement** in `expense_model.dart`, mirroring `createdBy` exactly:
- After the `createdBy` field (~line 45) add:
  ```dart
  /// Auth UID of the user who last wrote this record (create or edit).
  /// Client-stamped on every write; Firestore rules pin it to the caller's
  /// UID when the write touches it. Read by the server audit trigger (#248).
  /// Empty string means "unknown" (legacy docs predating this field).
  final String lastEditedBy;
  ```
- Constructor: add `this.lastEditedBy = '',` (next to `this.createdBy`).
- `fromFirestore`: add `lastEditedBy: data['lastEditedBy'] as String? ?? '',`.
- `toFirestore`: add `'lastEditedBy': lastEditedBy,` (next to `'createdBy'`).
- `copyWith`: add `String? lastEditedBy,` param and `lastEditedBy: lastEditedBy ?? this.lastEditedBy,`.

**Step 4 — Run, verify pass.** **Step 5 — Commit:** `feat(ledger): add Expense.lastEditedBy field (#248)` / `Refs #248`.

---

### Task 2: `ExpenseService` stamps `lastEditedBy`

**Files:**
- Modify: `lib/features/ledger/services/expense_service.dart`
- Test: `test/unit/expense_service_test.dart`

**Step 1 — Write failing tests:**

```dart
test('addExpense stamps lastEditedBy = createdBy', () async {
  final e = await service.addExpense(
    groupId: 'g1', eventId: 'e1', payerParticipantId: 'p1',
    amount: Decimal.parse('5'), createdBy: 'uidA',
  );
  // read raw doc back
  final doc = await fake.doc('groups/g1/events/e1/expenses/${e.id}').get();
  expect(doc.data()!['lastEditedBy'], 'uidA');
});

test('updateExpense stamps lastEditedBy when a field changes', () async {
  final e = await service.addExpense(/* ...createdBy: 'uidA'... */);
  await service.updateExpense(
    groupId: 'g1', eventId: 'e1', expenseId: e.id,
    amount: Decimal.parse('9'), lastEditedBy: 'uidA',
  );
  final doc = await fake.doc('groups/g1/events/e1/expenses/${e.id}').get();
  expect(doc.data()!['lastEditedBy'], 'uidA');
});

test('updateExpense with no field changes writes nothing (no lastEditedBy-only write)', () async {
  final e = await service.addExpense(/* ... */);
  final before = (await fake.doc('groups/g1/events/e1/expenses/${e.id}').get()).data();
  await service.updateExpense(
    groupId: 'g1', eventId: 'e1', expenseId: e.id, lastEditedBy: 'uidA',
    // all content args null
  );
  final after = (await fake.doc('groups/g1/events/e1/expenses/${e.id}').get()).data();
  expect(after, before); // unchanged — D3
});

test('deleteExpense stamps lastEditedBy on the soft-delete write', () async {
  final e = await service.addExpense(/* ... */);
  await service.deleteExpense(
    groupId: 'g1', eventId: 'e1', expenseId: e.id, lastEditedBy: 'uidA',
  );
  final doc = await fake.doc('groups/g1/events/e1/expenses/${e.id}').get();
  expect(doc.data()!['isDeleted'], true);
  expect(doc.data()!['lastEditedBy'], 'uidA');
});
```
(Match the existing test's fake-Firestore accessor + `addExpense` arg style — read the current file's setup before writing.)

**Step 2 — Run, verify fail** (no `lastEditedBy` param / not written).

**Step 3 — Implement:**
- `addExpense` inline `data` map (`:130-155`): add `'lastEditedBy': createdBy,` (next to `'createdBy': createdBy`).
- `updateExpense` signature: add `String? lastEditedBy,`. Inside the existing `if (updates.isNotEmpty) { ... }` block, **before** the `.update(updates)` call:
  ```dart
  if (lastEditedBy != null && lastEditedBy.isNotEmpty) {
    updates['lastEditedBy'] = lastEditedBy;
  }
  ```
  (Placed inside the guard so a no-op edit stays a no-op — D3.)
- `deleteExpense` signature: add `String? lastEditedBy,`. In the soft-delete update map add:
  ```dart
  if (lastEditedBy != null && lastEditedBy.isNotEmpty) 'lastEditedBy': lastEditedBy,
  ```

**Step 4 — Run, verify pass.** **Step 5 — Commit:** `feat(ledger): ExpenseService stamps lastEditedBy on write (#248)`.

---

### Task 3: Client screens pass the current uid

**Files:**
- Modify: `lib/features/ledger/screens/edit_expense_screen.dart`
- Test: `test/features/ledger/edit_expense_screen_test.dart`

`add_expense_screen.dart` needs **no change** — it already passes `createdBy: currentUid`, and the service derives `lastEditedBy = createdBy`.

**Step 1 — Write failing test:** in `edit_expense_screen_test.dart`, assert the mocked `updateExpense`/`deleteExpense` are called with `lastEditedBy: <signed-in uid>`. (The suite already mocks the service and verifies call args — extend the existing verify with a `lastEditedBy` matcher.)

**Step 2 — Run, verify fail.**

**Step 3 — Implement:** in `_save` and `_delete`, read the uid and pass it:
```dart
final currentUid = ref.read(currentUserIdProvider);
// _save → updateExpense(..., lastEditedBy: currentUid);
// _delete → deleteExpense(..., lastEditedBy: currentUid);
```
(`currentUid` is `String?`; the service skips the field when null/empty — backward-safe.)

**Step 4 — Run, verify pass + `flutter analyze`.** **Step 5 — Commit:** `feat(ledger): edit screen stamps lastEditedBy (#248)`.

---

### Task 4: Firestore rules — permit + pin + soft-delete carry

**Files:**
- Modify: `security/firestore.rules`

**Edits (exact):**
1. `validExpenseBase` key allowlist (`:531-550`): add `'lastEditedBy'` to the `hasOnly([...])` list. *(Permits the key; does not require it — backward compat.)*
2. `validExpenseCreate` (`:572-582`): add
   ```
   && (!('lastEditedBy' in request.resource.data)
       || request.resource.data.lastEditedBy == request.auth.uid)
   ```
3. `validExpenseUpdate` (`:606-639`):
   - add `'lastEditedBy'` to the `affectedKeys().hasOnly([...])` list (`:612-628`).
   - add the diff-gated pin (D1):
     ```
     && (!request.resource.data.diff(resource.data).affectedKeys().hasAny(['lastEditedBy'])
         || request.resource.data.lastEditedBy == request.auth.uid)
     ```
4. `validSoftDelete` (`:584-590`): change `hasOnly(['isDeleted', 'deletedAt'])` → `hasOnly(['isDeleted', 'deletedAt', 'lastEditedBy'])` (D2).

*(No code-only commit — rules land with their tests in Task 5. Do Task 4 + Task 5 as one RED→GREEN cycle.)*

---

### Task 5: Rules emulator tests

**Files:**
- Modify: `functions/test/firestore-rules-publish-readiness.test.ts` (extend the expense block ~`:1081-1153`).

**Step 1 — Write failing tests** (new `test(...)` cases; reuse `validExpense`, `seedExpense`, `withoutField`):

```ts
// --- new-client happy paths (pin satisfied) ---
test('expense create with lastEditedBy == auth.uid is allowed', async () => {
  const member = testEnv.authenticatedContext('member').firestore();
  await assertSucceeds(member.doc('groups/g1/events/e1/expenses/expLE').set(
    validExpense({ id: 'expLE', createdBy: 'member', lastEditedBy: 'member' }),
  ));
});
test('creator update setting lastEditedBy == auth.uid is allowed', async () => {
  await seedExpense(); // createdBy: 'owner'
  const owner = testEnv.authenticatedContext('owner').firestore();
  await assertSucceeds(owner.doc('groups/g1/events/e1/expenses/exp1').update({
    amountFils: 12500, lastEditedBy: 'owner',
  }));
});
test('creator soft-delete carrying lastEditedBy is allowed (validSoftDelete loosened)', async () => {
  await seedExpense();
  const owner = testEnv.authenticatedContext('owner').firestore();
  await assertSucceeds(owner.doc('groups/g1/events/e1/expenses/exp1').update({
    isDeleted: true, deletedAt: new Date().toISOString(), lastEditedBy: 'owner',
  }));
});

// --- forgery rejected (identity axis) ---
test('expense create with forged lastEditedBy is rejected', async () => {
  const member = testEnv.authenticatedContext('member').firestore();
  await assertFails(member.doc('groups/g1/events/e1/expenses/expForge').set(
    validExpense({ id: 'expForge', createdBy: 'member', lastEditedBy: 'owner' }),
  ));
});
test('creator update forging lastEditedBy != auth.uid is rejected', async () => {
  await seedExpense(); // createdBy: 'owner'
  const owner = testEnv.authenticatedContext('owner').firestore();
  await assertFails(owner.doc('groups/g1/events/e1/expenses/exp1').update({
    amountFils: 12500, lastEditedBy: 'member',
  }));
});

// --- backward compat (legacy / old client omits the field) ---
test('legacy create WITHOUT lastEditedBy still allowed', async () => {
  const member = testEnv.authenticatedContext('member').firestore();
  await assertSucceeds(member.doc('groups/g1/events/e1/expenses/expLegacy').set(
    validExpense({ id: 'expLegacy', createdBy: 'member' }), // no lastEditedBy
  ));
});
test('old-client update WITHOUT touching lastEditedBy still allowed', async () => {
  await seedExpense(); // createdBy: 'owner', no lastEditedBy
  const owner = testEnv.authenticatedContext('owner').firestore();
  await assertSucceeds(owner.doc('groups/g1/events/e1/expenses/exp1').update({
    amountFils: 12500, // diff doesn't touch lastEditedBy → pin skipped
  }));
});

// --- PR-1 regression: edit is STILL creator-only ---
test('non-creator still cannot update even with a valid own lastEditedBy', async () => {
  await seedExpense(); // createdBy: 'owner'
  const member = testEnv.authenticatedContext('member').firestore();
  await assertFails(member.doc('groups/g1/events/e1/expenses/exp1').update({
    amountFils: 12500, lastEditedBy: 'member',
  }));
});

// --- B3 append-only contract guard. NOTE: this stays green regardless of the
// validSoftDelete loosening, because settlement updates are dead-denied at
// `allow update: if false` (:735) — it does NOT detect drift in validSoftDelete
// (that's guarded by validSoftDelete's sole LIVE reference being the expense
// path at :637). Kept because it pins B3 against any future re-wiring of
// validEventSettlementUpdate. ---
test('settlement soft-delete carrying lastEditedBy is still denied', async () => {
  await seedEventSettlement(); // createdBy: 'owner'
  const owner = testEnv.authenticatedContext('owner').firestore();
  await assertFails(owner.doc('groups/g1/events/e1/settlements/set1').update({
    isDeleted: true, deletedAt: new Date().toISOString(), lastEditedBy: 'owner',
  }));
});
```

**Step 2 — Run, verify the new cases fail** against the *unmodified* rules (RED — `cd functions && npm run test:emulator`). The forgery/soft-delete-carry cases must fail for the *right reason* (rule rejects the new key) before Task 4's edits.

**Step 3 — Apply Task 4 rule edits.**

**Step 4 — Run, verify all pass** (new + the existing untouched expense/settlement cases stay green — paste output into the PR as RED→GREEN evidence per #329).

**Step 5 — Commit:** `feat(rules): pin expense lastEditedBy == auth.uid (#248)` — Task 4 + 5 together.

---

## Deploy

PR 1 ships **rules-only** backend (no trigger yet). Additive + backward-compatible → deploys freely (no real users; [[project_no_clients_deploy_freely]]). After merge: `deploy-ceremony` skill / `tool/pending_deploy.sh` → advances the `backend-deployed` tag, records `docs/DEPLOY-LEDGER.md`. The new field requires no index. Client (Tasks 1–3) can release any time after; old clients keep working (pin is diff/presence-gated).

## Done checklist (PR 1)
- [ ] `Expense.lastEditedBy` round-trips; legacy docs → `''`.
- [ ] `addExpense` stamps `= createdBy`; `updateExpense`/`deleteExpense` stamp the passed uid; no-op edit writes nothing.
- [ ] Edit screen passes `currentUserIdProvider` uid; add screen unchanged.
- [ ] Rules: key permitted, pin diff-gated (update) / presence-gated (create), `validSoftDelete` carries it.
- [ ] Emulator: happy / forgery-rejected / legacy-allowed / soft-delete-carries / **non-creator-still-denied** / **settlement-still-denied**.
- [ ] Money invariants reconfirmed untouched: `createdBy` immutable, `splitValuesNonNegative`, `validSoftDelete` false→true only, no balance-path change.
- [ ] `flutter analyze` clean; functions + flutter suites green; RED→GREEN output pasted in PR.
- [ ] Fresh-context Opus Gate to no-P1 (`/run-the-gate`) **before** code; `/automerge` review+refute at merge.
- [ ] PR body: `Refs #248` (NOT `Closes`), `Spec:` line → this file.
