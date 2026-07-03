# Add/edit-expense discard guard (#818 Wave 3.2)

**Refs #818.** From the first-impressions review: `add_expense_screen.dart` has no
`PopScope`/dirty-check anywhere — one tap on the X (or system back) silently discards a
fully-typed expense, including a full itemized receipt. Gate-category: back-guard.

## Verified terrain (all re-checked against origin/main @ `b09f4354`, 2026-07-03)

- **Both screens share one chokepoint.** `AddExpenseScreen` and `EditExpenseScreen` are
  thin hosts around the shared `lib/features/ledger/widgets/expense_editor_body.dart`
  (1827 lines). The only close affordance is `_ExpenseTopBar.onClose`, wired at
  `expense_editor_body.dart:699-701` to an unconditional `HapticService.lightClick();
  context.pop();`. `grep -rn "PopScope" lib/` returns exactly one hit —
  `group_detail_screen.dart:66` (the top-level home-fallback pattern, NOT applicable
  here). Guarding the shared body covers add AND edit for free.
- **Route shape.** `/group/:gid/event/:eid/ledger/add` (`app_router.dart:334-344`) and
  `.../ledger/edit/:expId` (`:345-356`) — nested 4 deep, always pushed (`context.push`
  from `ledger_screen.dart:442-444`, `event_command_center.dart:266-269`,
  `add_expense_fab.dart:34-37`), so `canPop()` is always true on entry. Neither screen is
  a `BottomNavShell` tab → the #666 dual-mode trap does not apply.
- **go_router 13.2.5 `pop()` is imperative and bypasses `PopScope.canPop`.** Verified in
  the resolved package (`~/.pub-cache/hosted/pub.dev/go_router-13.2.5/lib/src/delegate.dart:96-111`):
  it calls `NavigatorState.pop(result)` directly, never `maybePop`. Consequences:
  1. the post-save `context.pop()` in the screen hosts (`add_expense_screen.dart:120,223`,
     `edit_expense_screen.dart:200,290,312`) pops WITHOUT consulting the guard — a
     successful save never sees the discard dialog;
  2. the X button's raw `context.pop()` would ALSO bypass the guard — it must be rerouted
     through the guard method;
  3. only system back / Android predictive back goes through `maybePop` and respects
     `canPop`.
- **Amount keystrokes already rebuild the parent** (`onChanged: setState` at
  `expense_editor_body.dart:717-718`; the #627 name-map memo exists precisely to make
  per-keystroke rebuilds cheap). **Note keystrokes do NOT** — `_noteController` (:149) is
  passed to `_DescriptionField` (:742) whose internal `setState` (:1114-1125) is local to
  that child. A `canPop` computed in the parent's `build` would be stale for note-only
  edits unless the parent listens to `_noteController`.
- **Add-mode currency is re-seeded WITHOUT user action.** `didUpdateWidget`
  (#382 PR-6) adopts a late-arriving smart default while `!_currencyManuallyPicked`. So
  currency dirtiness must be `_currencyManuallyPicked == true`, never a value compare —
  otherwise the async default false-dirties a pristine screen.
- **Payer only mutates via user tap** (`:520 setState(() => _selectedPayerId = selected)`)
  or edit-mode init (`:225`). Add-mode default payer is resolved at submit time from
  `currentEventParticipantProvider` (`:340-348`) without writing `_selectedPayerId` — safe
  for a null baseline.
- **No discard l10n keys exist** (`commonDiscard`/`KeepEditing` grep: only unrelated
  conflict-switch prose at `app_en.arb:2425,2429`). New keys required, EN + AR.
- **House confirm idiom** = `_confirmDelete` in the SAME file (:396-428): `showDialog<bool>`,
  `AlertDialog` with `radiusCard` shape, two `TextButton`s returning `Navigator.pop(context,
  bool)`, destructive action in `context.colors.error`.

## Design

All edits in `expense_editor_body.dart` + ARB files + tests. No routing-table, provider,
schema, rules, or server changes. Client-only → no deploy ceremony.

### 1. Pristine baseline, captured once in `initState`

Capture a snapshot at open; dirty ⇔ current state differs from the snapshot. Snapshot
fields (all `late final`, set at the END of `initState` after both mode branches):

| Baseline field | Add mode value | Edit mode value |
|---|---|---|
| `_pristineAmount` (String) | `'0'` | `initial.amount.toString()` |
| `_pristineNote` (String) | `''` | `initial.description ?? ''` |
| `_pristineScope` | `ExpenseScope.global` | `initial.scope` |
| `_pristineCategoryId` | `null` | `initial.categoryId` |
| `_pristinePayerId` | `null` | `initial.payerParticipantId` |
| `_pristineCustomSplit` (Set) | `const <String>{}` | copy of `initial.customSplitParticipants` |
| `_pristineSplitMode` | the `initState`-read `settingsProvider` default | `initial.splitMode ?? SplitMode.equally` |
| `_pristineSplitDistribution` (Map?) | `null` | copy of `initial.splitDistribution` |
| `_pristineSplitExplanation` (object ref) | `null` | `initial.splitExplanation` |

Implementation shortcut: since `initState` already assigns the working fields from exactly
these values, the snapshot is taken from the working fields after the existing init block —
no duplicated mode logic. **Exception (Gate r1 [P2]): the Set and Map baselines MUST be
defensive copies** — `_pristineCustomSplit = Set.of(_customSplitParticipants)` and
`_pristineSplitDistribution = _splitDistribution == null ? null :
Map.of(_splitDistribution!)` — never shared references. All current mutations are
replace-only (verified :458/:473/:480/:617), but a shared ref means any future in-place
mutation would mutate the pristine too → predicate reads clean → silent discard, the exact
loss the guard exists to prevent.

Why a snapshot instead of re-deriving from `widget.initial`/providers in the getter:
(a) `settingsProvider.defaultSplitMode` could change mid-session; (b) edit mode's
`widget.initial` can be swapped by a remote edit while the form is open (open-edit policy,
#248) — the dirty question is "did THIS user change anything since opening", so the
baseline must be frozen at open.

### 2. The dirty predicate

```dart
bool get _isDirty =>
    _amount != _pristineAmount ||
    _noteController.text != _pristineNote ||
    _scope != _pristineScope ||
    _selectedCategoryId != _pristineCategoryId ||
    _selectedPayerId != _pristinePayerId ||
    !setEquals(_customSplitParticipants, _pristineCustomSplit) ||
    _splitMode != _pristineSplitMode ||
    !mapEquals(_splitDistribution, _pristineSplitDistribution) ||
    !identical(_splitExplanation, _pristineSplitExplanation) ||
    (!_isEdit && _currencyManuallyPicked);
```

- `setEquals`/`mapEquals` resolve without a new import (Gate r1: `material.dart`
  re-exports foundation; the file already has a private `_setEquals` at :649 that may be
  reused for the set compare).
- `_splitExplanation` compares by identity: the itemized sheet only ever *replaces* the
  object on Apply (`custom_split_sheet_itemized.dart` folds drafts into a new
  `SplitExplanation`), so identity change ⇔ user action. No deep-equality needed.
- Currency: `_currencyManuallyPicked` only, per the `didUpdateWidget` re-seed above.
  Edit mode's currency is immutable (`effectiveCurrency`), so the flag is add-only.
- `_categoryError`, `_isSubmitting`, focus/memo fields are NOT dirty signals — excluded.
- Symmetric consequence: typing `5` then deleting back to `0` reads clean. Accepted.

### 3. Note-controller listener (the stale-`canPop` fix)

In `initState`: `_noteController.addListener(_onNoteChanged);` where
`_onNoteChanged() => setState(() {});` — rebuilds the parent so `PopScope.canPop` tracks
note-only edits (system back consults the *widget's* `canPop` value from the last build).
Remove the listener in `dispose` before the existing `_noteController.dispose()` (:265).
Amount needs no listener — its `onChanged` already `setState`s.

### 4. The guard

Wrap the `Scaffold` at `expense_editor_body.dart:686`:

```dart
return PopScope(
  canPop: !_isDirty,
  onPopInvokedWithResult: (didPop, result) {
    if (didPop) return;
    _confirmDiscard();
  },
  child: Scaffold(...),
);
```

- Pristine screen keeps `canPop: true` → Android predictive-back preview stays alive
  (the repo's documented concern with blanket `canPop: false`).
- `_confirmDiscard()` (new, async, `void`-returning fire-and-forget from the handler):
  shows the discard dialog (house idiom, §6); on `true` → `if (mounted) context.pop();`
  — the imperative pop bypasses `canPop`, verified above. On `false`/dismiss → nothing.

### 5. Reroute the X through the guard

Replace the `onClose` closure (:699-701) with `_handleClose`:

```dart
void _handleClose() {
  HapticService.lightClick();
  if (!_isDirty) {
    context.pop();
    return;
  }
  _confirmDiscard();
}
```

Both dismissal paths now converge on `_isDirty` → `_confirmDiscard()`. The post-save and
error-dialog pops in the screen hosts are untouched (imperative, bypass the guard by
design).

### 6. The dialog

Mirror `_confirmDelete` (:396-428) exactly — `showDialog<bool>`, `AlertDialog`,
`RoundedRectangleBorder(radiusCard)`, two `TextButton` actions:

- Keep editing (returns `false`) — default/safe action, plain `TextButton`.
- Discard (returns `true`) — `TextStyle(color: context.colors.error)`.

No icon row (delete's trash icon signals destruction of a *persisted* record; discarding a
draft is lighter). All colors via `context.colors` — theme purity holds.

### 7. l10n (EN + AR, both ARBs, regenerate + commit generated files)

| Key | EN |
|---|---|
| `editorDiscardAddTitle` | `Discard this expense?` |
| `editorDiscardEditTitle` | `Discard your changes?` |
| `editorDiscardBody` | `You'll lose what you've entered.` |
| `editorDiscardKeepEditing` | `Keep editing` |
| `editorDiscardConfirm` | `Discard` |

Title picked by `_isEdit`. AR translations authored in the same PR (ARB parity is
CI-enforced). Generated `app_localizations*.dart` committed (repo convention, #245 note).

## Non-goals

- No draft persistence / restore-on-reopen.
- No guard on the custom-split or itemized SHEET itself (separate modal route; its
  transient drafts fold into `_splitExplanation` only on Apply — by design).
- No change to submit-in-flight behavior (X during `_isSubmitting` behaves as today,
  modulo the dirty check).
- No routing-table changes; `app_router.dart` untouched.

## Accepted over-prompt edges (Gate r1 [P3]s — known, not bugs)

- Reopening the itemized sheet and tapping Apply without changes replaces the
  `SplitExplanation` object → reads dirty → over-prompt on close. Safe direction.
- Backing out of the post-save success dialog lands on the still-dirty editor; a further
  back over-prompts on already-saved data. Pre-existing duplicate-on-re-save shape, no
  data loss introduced; out of scope.
- Three additional edit-route push sites exist beyond those listed above
  (`settle_up_screen.dart:101`, `ledger_search_sheet.dart:294`,
  `group_settle_up_screen.dart:93`) — all `.push`, so the nested/canPop reasoning holds
  for them unchanged.

## Tests (new feature → RED first, then implement)

New file `test/features/ledger/expense_editor_discard_guard_test.dart`. The existing
`_pumpAddExpenseScreen` harness wraps a plain `MaterialApp` (no router) and cannot
exercise pops — build a local `MaterialApp.router` harness (a two-entry stack: a stub home
+ the add route pushed) following `group_detail_navigation_test.dart`'s pattern, incl. its
direct `PopScope` invocation idiom (`tester.widget<PopScope>(...)` then
`popScope.onPopInvokedWithResult!(false, null)` — :217-225). Override
`sharedPreferencesProvider` (settings default split mode is read in `initState`).

1. **Pristine add** → the `PopScope` above the editor has `canPop == true`; tapping X pops
   (stub home visible), no dialog.
2. **Amount-dirty add** → enter `5`; `canPop == false`; tap X → dialog visible; tap Keep
   editing → editor still present; tap X again → tap Discard → popped.
3. **Note-only dirty** (the listener regression): enter text in the description field
   ONLY; assert `canPop == false` and simulated system back
   (`onPopInvokedWithResult(false, null)`) shows the dialog. This test FAILS if the
   note listener is dropped.
4. **Pristine edit** → pump edit mode with an `initial` expense, change nothing;
   `canPop == true`; X pops without dialog.
5. **Late currency re-seed stays clean**: pump `ExpenseEditorBody` directly (widget-level)
   with `currency: 'OMR'`, rebuild with `currency: 'USD'` (simulating the async smart
   default), assert `canPop` still `true`.
6. **Edit-dirty** → change the note on an `initial`-loaded editor → system back shows
   dialog; Discard pops.

Traps honored: bounded `tester.pump()`s (never `pumpAndSettle` after `pumpRihlaApp`-style
boots; the editor screen has no `EmptyStateView`), `fake_cloud_firestore` not needed
(providers mocked/overridden as in `add_expense_screen_test.dart`'s override list).

## Verification principles — run at spec time

1. **Callsite classification**: the guard is INBOUND-only — it reads form state and gates
   navigation; nothing it touches feeds a write. The write path (`_submit` →
   `widget.onSubmit`) is untouched.
2. **Concrete claims verified in-session**: PopScope single-hit grep; onClose site read
   (:686-707); l10n key absence grep; payer assignment sites (:225, :520);
   `didUpdateWidget` re-seed read; amount `onChanged` setState read (:717-718); go_router
   13.2.5 `delegate.dart` pop read from pub cache; post-save pop sites grep'd in both
   screen hosts.
3. **Read-path per write-path**: N/A (no persisted write). The guard's "read path" is
   `PopScope.canPop`, and every mutation source that must reach it is enumerated —
   the note listener is the one missing rebuild trigger, now specified.
4. **Fields enumerated from the type**: dirty predicate built from the full
   `_ExpenseEditorBodyState` field list (:148-245), each field explicitly included or
   excluded with reason.
5. **Data contracts spelled out**: exact baseline table, exact predicate, exact l10n keys,
   exact dialog return contract (`bool`).
6. **Arithmetic decomposition**: N/A.
7. **Adversarial pass on an orthogonal axis** (spec is about form-dirtiness; the pass
   exercises the *navigation* axis): (a) programmatic pops — post-save `context.pop(true)`
   at `add_expense_screen.dart:120` carries a result through an imperative pop, which
   go_router routes straight to `NavigatorState.pop` → unaffected by `canPop`; (b) the
   offline-ack dialog flow (#412) pops its own dialogContext then the screen — both
   imperative → unaffected; (c) predictive back on a pristine screen — `canPop: true`
   keeps the system animation; (d) the custom-split sheet is its own route — system back
   inside it pops the sheet, never the editor.

## Acceptance

- [ ] Dirty add/edit editor: X and system back both show the discard dialog; Discard pops,
      Keep editing stays.
- [ ] Pristine editor: X and system back pop immediately, no dialog, predictive back intact.
- [ ] Post-save pop never shows the dialog.
- [ ] Note-only edits are guarded (listener wired + regression test).
- [ ] Late add-mode currency re-seed does not dirty the form.
- [ ] EN+AR keys added, generated l10n committed, `flutter analyze` clean, theme purity
      clean, full ledger test dir green.
- [ ] Commit body carries `Refs #818` (not `Closes` — sprint issue stays open).
