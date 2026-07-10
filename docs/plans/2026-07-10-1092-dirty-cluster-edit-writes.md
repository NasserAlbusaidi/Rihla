# #1092 — Edit-Expense Saves Write Only User-Dirtied Field Clusters

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** an edit-expense save must never write a field the user did not touch in this editor session — so a concurrent edit by another participant to an untouched field survives instead of being silently reverted to the stale form value.

**Architecture:** `ExpenseEditorBody` already snapshots a pristine per-field baseline at open (`_pristine*`, #818 discard guard, frozen in `initState`, never re-seeded — `expense_editor_body.dart:209-241,301-316`). The fix exposes that knowledge to the save path: `ExpenseEditorPayload` gains five **dirty flags** computed from the pristine baseline (`moneyDirty`, `explanationDirty`, `descriptionDirty`, `categoryDirty`, `payerDirty`), and `_save` (`edit_expense_screen.dart:110-180`) gates each write-map block on its flag. The ARITHMETIC money cluster (amount, scope, customSplitParticipants, splitMode, splitDistribution) shares ONE flag because `sum(splits)==amount` couples them; `splitExplanation` gets its OWN flag (round-2 P1 — it is display-only, so riding the money flag would let a cosmetic relabel open the money gate and revert a concurrent money edit). The inner per-field diff-vs-fresh ternaries stay, which is safe by the internal-consistency argument below. All flags false → pop without writing. No schema change, no rules change, no service change, no transaction.

**Tech stack:** Flutter/Dart, Riverpod 2.x; regression harness = `StreamController<List<Expense>>` through the `eventExpensesProvider` override (scaffold precedent: `edit_expense_offline_412_test.dart`).

**Issue:** #1092 (P2, money, data-integrity). Verified surface map by scout 2026-07-10; claims re-verified in-session (main @ ea7bce7c; round-1 reviewers re-confirmed at 7d4a086c — line numbers identical). Gate round 1: 1 P1 + 2 P2 resolved (scope mask, early-return pop). Gate round 2: 1 P1 resolved (splitExplanation decoupled from the money gate into its own `explanationDirty` flag) + rubric P3s (trimmed description compare, OCC-claim precision, adjustments note). Gate round 3: BOTH reviewers 0 P1 — **Gate PASSED**; P3 wording/test-robustness folded (identity-engine parse note, NavigatorObserver pop spy, payer-axis Test F).

---

## Bug mechanics (verified file:line)

- `EditExpenseScreen.build` watches the LIVE `eventExpensesProvider` (`edit_expense_screen.dart:41`); every remote emission rebuilds and re-captures `expense` into the `onSubmit` closure (`:102`) as `_save`'s `original`.
- `_ExpenseEditorBodyState` seeds form state ONCE in `initState` (`expense_editor_body.dart:263-292`) and NEVER re-seeds from `widget.initial` (`didUpdateWidget:322-333` only adopts the add-mode currency smart default). So mid-edit, form fields hold OPEN-TIME values while `original` is the FRESHEST doc.
- `_save` writes `payload.X != original.X ? payload.X : null` per field (`edit_expense_screen.dart:147-178`). Failure: A opens the editor (form = v1); B's edit lands (stream → v2 → `original` = v2); A saves having touched only, say, the category → for the amount, `payload.amount` (v1) `!= original.amount` (v2) → the write-map REVERTS the amount to v1. Silent, no error, B's edit gone.

## Why cluster-gating is sufficient and safe (the arithmetic-decomposition argument — principle 6)

The editor validates `sum(splitDistribution) ≈ amount` within `_splitTolerance` at submit (the guard at `expense_editor_body.dart:406-415`; the tolerance constant at `:203-205` mirrors #250), so the PAYLOAD is always internally consistent across the money cluster. In `_save`, each money field is either written to its payload value or left equal to it (that is what `payload.X != original.X ? payload.X : null` means) — therefore whenever the money block is passed at all, the post-write doc equals the payload on the ENTIRE cluster, which is consistent. When `moneyDirty == false`, NO money field is passed, and the post-write doc keeps the concurrent editor's cluster, which that editor's own validated save made consistent. There is no partial-cluster outcome in either branch. (This is also why per-field dirty flags for amount vs split would be WRONG — a lone `amountDirty` write against B's new distribution could break the sum; the single cluster flag forbids that state.)

## Deliberate decisions (do not re-litigate)

1. **Same-field concurrency stays last-write-wins.** True OCC needs a version/timestamp token: `Expense` has none (`toFirestore` enumerated — no `updatedAt`, `lastEditedBy` is an unstamped UID; `SplitExplanation.version` is opaque display metadata), adding one is a `models/**` + `security/firestore.rules` change (`validExpenseUpdate` today compares resource-vs-request only for immutability pins — `createdBy:839`, soft-delete fields `:885-886` — it has NO version/timestamp OCC token comparison, `firestore.rules:828-889`), and `lib/` contains ZERO client-side `runTransaction` precedent. That full-OCC design belongs with the #1093 decision fork, not this fix. Documented residual: two users editing the SAME field concurrently → later save wins — vastly better than today, where a save reverts fields the user never touched.
2. **Dirty flags come from the editor's pristine baseline, not from `_save` re-deriving.** The baseline already exists per-field with exactly the right freeze semantics (#818: "a remote open-edit swap must not retroactively change what counts as the user's own edits"). A user who edits a field and manually reverts it to the open-time value reads as clean → no write — an improvement, not a regression.
3. **`payerDirty` is separate from the money cluster.** Payer moves `paidMap`, not the `sum(splits)==amount` invariant.
4. **`splitExplanation` gets its OWN `explanationDirty` flag — it must NOT ride the money cluster (round-2 P1).** The killed trace: A opens an itemized expense (total 10); B concurrently re-itemizes to 25; A relabels one item (cosmetic) and saves. Had the explanation term lived in `moneyDirty`, the whole money block would pass and the inner ternaries would fire against the FRESH original — `payload.amount(10) != original.amount(25)` writes 10, reverting B's money via a DISPLAY-ONLY edit. `splitExplanation` has no arithmetic coupling to `sum(splits)==amount` (INBOUND/display-only for money: never read by `recomputeNet` or `balanceAggregator` — verified; note the identity engines `claimShadow.ts:264` / `deleteAccount.ts:250` DO parse it to re-key participant ids, identity not amounts, so don't describe it as fully server-inert), so it gates independently: `splitExplanation:`/`clearExplanation:` pass only when `payload.explanationDirty`, with the inner `explanationChanged` logic (`edit_expense_screen.dart:128-131,166-171`) intact. **Accepted residual:** in the same race, A's relabel-only save lands A's stale explanation over B's re-itemized money — a recoverable display mismatch on next editor open, never wrong money; strictly less severe than the revert it prevents. A relabel-only save writes `{splitExplanation, lastEditedBy}`, a shape rules already accept (#203 S2).
5. **Nothing dirty → pop the editor and skip the service call entirely.** Corrected premise (round-1 P3): a truly-pristine save is ALREADY a server-side no-op today — `currency` only enters the service's `updates` map alongside `amount` (`expense_service.dart:342-348`) and `lastEditedBy` only when `updates` is non-empty (`:382-391`), so no byline re-attribution happens today. The early return's real value: it makes "nothing user-dirty" structurally incapable of producing the concurrent-doc revert, and skips the redundant call/ack-race. (The body's `_submit` fires its success haptic BEFORE `onSubmit` — `expense_editor_body.dart:430` — so a nothing-dirty save still buzzes; accepted, not worth restructuring the body for.) **It must still pop:** the ONLY success-path pop lives in `_save` (`edit_expense_screen.dart:194-201`); the body's `_submit` never pops after `onSubmit` (round-1 P2, found by both reviewers). The early return runs the same mounted-guarded pop the success path uses, then returns — skipping the write AND the `ledgerRevision` bump (intentional: no write happened, nothing to refresh).
6. **`currency` and `lastEditedBy` are passed exactly when any flag is true** — currency is immutable-by-preservation (#261, always `original.currency`), lastEditedBy is the unforgeable editor pin (#248) and must accompany every real edit (`firestore.rules:881` requires it on every update).
7. **Add mode: all flags `true`.** `_save` exists only on the edit screen; the add screen ignores the flags, but honest values keep the payload self-describing.
8. **No editor re-seed / no conflict UI.** Live-merging remote edits into an open form (or a "this expense changed underneath you" banner) is a UX feature with its own design questions — out of scope, and the #818 freeze doc explicitly rejects retroactive baseline changes.

---

### Task 1: Regression tests (RED)

**Files:**
- Modify: `test/features/ledger/edit_expense_screen_test.dart` (or a new focused `edit_expense_concurrent_1092_test.dart` if the existing harness doesn't take a StreamController — check first; the offline-412 file shows the mocked-service capture pattern)

**Step 1: Write the failing tests.** Harness: override the `eventExpensesProvider`-feeding service (mock `watchExpenses` — that is the actual method name, `expense_provider.dart:70`; round-1 correction) with a `StreamController<List<Expense>>`; capture `updateExpense` named args via mocktail `captureAny(named: ...)`.

Test A — **the #1092 revert case**: seed v1 (amount 10.000, category 'food'); open editor; emit v2 (amount 25.000 — the concurrent edit); user changes ONLY the category (tap a different chip); save. Assert `updateExpense` captured with `categoryId` non-null AND `amount: null` AND `splitMode: null` AND `splitDistribution: null` AND `clearSplit: false` (the amount write is ABSENT — B's 25.000 survives).

Test B — money edit still writes: same two-phase setup; user edits the amount field; save. Assert `amount` captured non-null (equals the user's input, not v2's).

Test C — pristine save writes nothing AND pops: open editor, touch nothing, save. Assert `updateExpense` never called (`verifyNever`) AND the pop actually happened — use a `NavigatorObserver` didPop spy, NOT key-absence (`LedgerKeys.editExpenseSheet` sits on the route-level `KeyedSubtree`, `edit_expense_screen.dart:88`; in a single-route harness key-absence can false-green — round-3 rubric P3). Pre-fix this is RED on the verifyNever (the call always fires today, even though the service internally no-ops an empty map).

Test D — scope round-trip does not false-dirty (the round-1 P1 case): seed v1 global-scope; open editor; emit v2 (concurrent amount edit); user toggles scope global→custom→global, changes NOTHING else, saves. Assert `amount: null` captured (no revert). Note the round-trip also runs `_resetSplitToEqual` — with an equal-split seed that's a no-op vs pristine, so `moneyDirty` must read false through the scope mask.

Test F — payer axis (round-3 rubric): B concurrently changes the payer (v2); A edits ONLY the description; save. Assert `payerParticipantId: null` captured (B's payer survives) and `description` non-null.

Test E — relabel-only does not open the money gate (the round-2 P1 case): seed v1 itemized (exact split + splitExplanation); open editor; emit v2 (concurrent amount/re-itemization edit); user changes ONLY the explanation (relabel — simulate by driving the itemized editor or constructing the payload path that changes `_splitExplanation` value-wise while distribution stays pristine); save. Assert captured `amount: null`, `splitMode: null`, `splitDistribution: null`, `clearSplit: false`, AND `splitExplanation` non-null.

**Step 2: Run — RED.** Test A fails with a captured non-null `amount` (the revert, failing for the right reason); Test C fails on the unconditional write. Save output verbatim.

### Task 2: Dirty flags in the payload (GREEN half 1)

**Files:**
- Modify: `lib/features/ledger/widgets/expense_editor_body.dart`

**Step 1:** `ExpenseEditorPayload` (:69-106) gains five `required final bool` fields: `moneyDirty`, `explanationDirty`, `descriptionDirty`, `categoryDirty`, `payerDirty`.

**Step 2:** At the submit site (`:~435`, where the payload is constructed), compute from the existing pristine fields — the `_isDirty` (:231-241) comparisons, partitioned, with TWO deliberate deviations from `_isDirty` (round-1 fixes):

```dart
final moneyDirty =
    _amount != _pristineAmount ||
    _scope != _pristineScope ||
    // #1092 Gate r1 [P1]: scope-masked — a custom→global round-trip leaves an
    // inert _customSplitParticipants set (_handleScopeChange never clears it,
    // seedCustomSplitOnScopeChange returns `current` for non-custom), and the
    // payload only carries the set when scope==custom, so comparing it while
    // scope!=custom false-dirties the money cluster and re-opens the revert.
    (_scope == ExpenseScope.custom &&
        !setEquals(_customSplitParticipants, _pristineCustomSplit)) ||
    _splitMode != _pristineSplitMode ||
    !mapEquals(_splitDistribution, _pristineSplitDistribution);

final explanationDirty = !_explanationValueEquals(
  _splitExplanation,
  _pristineSplitExplanation,
);
```

`_explanationValueEquals` is a small private helper mirroring `_explanationEquals` (`edit_expense_screen.dart:220-249`) — VALUE equality, not `identical` as `_isDirty:240` uses (round-1 P3: an itemized-editor reopen that changes nothing creates a fresh instance with identical values; `identical` would false-dirty). Mirror it fully (items AND adjustments) even though only items are load-bearing — any adjustment change also folds into `_splitDistribution` and is caught by `!mapEquals`; the adjustments compare is belt-and-braces, not a bug (round-2 rubric P3). `_isDirty` itself stays untouched (its `identical` is fine for a discard prompt — over-prompting is safe; over-WRITING is not). `descriptionDirty` compares TRIMMED both sides (`_noteController.text.trim() != _pristineNote.trim()`) so a trailing-whitespace-only edit doesn't produce a spurious `{lastEditedBy}`-only write (round-2 rubric P3).

`categoryDirty` = `_selectedCategoryId != _pristineCategoryId`; `payerDirty` = `_selectedPayerId != _pristinePayerId`. In add mode (`widget.initial == null` / `!_isEdit`) pass `true` for all five. Keep the `_isDirty` getter untouched (it additionally carries the add-mode currency term).

**Step 3:** `flutter analyze` — the add screen's payload consumer compiles unchanged (flags are new fields, not breaking; verify the add screen constructs no payload of its own — only the editor constructs it).

### Task 3: Gate the write-map in `_save` (GREEN half 2)

**Files:**
- Modify: `lib/features/ledger/screens/edit_expense_screen.dart` (:110-180)

**Step 1:** Early return when nothing dirty — MUST pop first (round-1 P2, both reviewers: the body's `_submit` never pops; the only success pop is `_save`'s at `:194-201`, so a bare `return` would strand the editor open with Save re-enabled):

```dart
final anyDirty = payload.moneyDirty ||
    payload.explanationDirty ||
    payload.descriptionDirty ||
    payload.categoryDirty ||
    payload.payerDirty;
if (!anyDirty) {
  // #1092: nothing user-dirty — pop without writing so a stale form can
  // never clobber a concurrent edit. No ledgerRevision bump: no write.
  <the same mounted-guarded pop the success path runs at :194-201>
  return;
}
```

(Copy the exact pop shape from the success path — same context source, same `mounted` guard.)

**Step 2:** Gate each block, keeping the inner ternaries byte-identical:
- `amount:` → `payload.moneyDirty && payload.amount != original.amount ? payload.amount : null`
- `scope`, `customSplitParticipants`, `splitMode`, `splitDistribution`, `clearSplit` (`goingEqual` and `splitChanged` computed only when `moneyDirty`, else `false`) — all inside the `moneyDirty` gate the same way.
- `splitExplanation:` / `clearExplanation:` gated on `payload.explanationDirty` (round-2 P1: NOT on moneyDirty), inner `explanationChanged` logic intact.
- `description:` gated on `payload.descriptionDirty`; `categoryId:` on `payload.categoryDirty`; `payerParticipantId:` on `payload.payerDirty`.
- `currency: original.currency` and `lastEditedBy:` stay unconditional (the early return already guarantees a real edit).

**Step 3:** Task 1 tests green. Run the neighboring suites: `flutter test test/features/ledger/` (the #248 byline tests, offline-412, editor-body suite must stay green).

**Step 4: Commit** `fix(ledger): edit saves write only user-dirtied field clusters` (body: `Refs #1092` + one line on last-write-wins residual).

### Task 4: Full verification + ship

- [ ] `flutter test` full suite; `flutter analyze` clean; `bash tool/check_theme_purity.sh` (editor widget touched).
- [ ] PR: title `fix(ledger): stale edit no longer reverts concurrent edits (#1092)`; body: summary, `Closes #1092` in FINAL commit body, `Spec: docs/plans/2026-07-10-1092-dirty-cluster-edit-writes.md`, Test plan, RED evidence (Task 1 output), residual note (same-field last-write-wins; full OCC deferred to the #1093 decision track).
- [ ] `/automerge <PR>` — money write-path = Gate-category; fresh review + refuter.
