# #627 — Memoize `_SplitPreviewCard`'s name map + owed allocation

**Issue:** #627 `perf(ledger): _SplitPreviewCard recomputes name map + allocation on every amount keystroke`
**Branch:** `feat/627-split-preview-memo`
**Severity/effort:** P2 / small. Client-only. No server/rules/schema/deploy.
**Gate:** Gate-category — the memoized `owed` map is the output of `BalanceCalculator.allocateExpenseOwed` and drives the per-person figures shown in the split preview. A botched cache key could display a wrong owed figure. Display-only (no write path), but money-math read surface → Gate required.

---

## Problem (verified on `feat/627-split-preview-memo` @ origin/main `9827cf82`)

`_AmountHero.onChanged` → `setState(() => _amount = _sanitizeAmount(value))` (`expense_editor_body.dart:668-669`) rebuilds the entire `_ExpenseEditorBodyState.build()` on **every amount keystroke**, reconstructing `_SplitPreviewCard` (a plain `StatelessWidget`, `:1480`) with a fresh `amount`.

`_SplitPreviewCard.build()` then, on every rebuild:
- **(a)** calls `MemberNameResolver.disambiguateEventParticipants(widget.event)` unconditionally (`:1534-1536`). Helper (`member_name_resolver.dart:129-137`) iterates `participantIds`, builds a `Map<String,MemberDisplay>`, then `disambiguate()` runs a lowercase collision-counting pass and builds a second map. Depends **only on `event`**, which is constant while typing → **pure waste per digit**.
- **(b)** for shares/exact/percent (`_isNonEqual`, `:1505-1508`) calls `BalanceCalculator.allocateExpenseOwed(...)` (`:1546-1558`), a full per-mode `Decimal` allocation. Semantically required when the amount changes, but recomputed on **non-amount** rebuilds too (category tap, payer change, etc.).

## Fix (scoped to `_SplitPreviewCard` only)

Convert `_SplitPreviewCard` from `StatelessWidget` to `StatefulWidget`. Cache the two derived values in `State`, recomputed in `initState` and conditionally in `didUpdateWidget`; `build()` only reads them.

### Cache 1 — `_displayNames: Map<String,String>`
- Recompute via `MemberNameResolver.disambiguateEventParticipants(widget.event)`.
- **Invalidation key: `!identical(widget.event, oldWidget.event)`.**
- **TRAP (#106): must NOT key on `Event ==` / `event.id`.** `Event.operator==` is **id-only** (`event_model.dart:220-222`, `hashCode => id.hashCode`). A same-id rename or member add/remove produces a new `Event` instance but `==`-true; keying on `==` would show a **stale name**. `eventDetailProvider` (a Firestore `StreamProvider`) deserializes a fresh `Event` on *any* change, so **instance identity** is a correct, conservative key: same instance ⇒ truly unchanged; different instance ⇒ recompute (covers both `participantNames` and `participantIds`).

### Cache 2 — `_owed: Map<String,Decimal>?`
- Recompute via `_isNonEqual ? BalanceCalculator.allocateExpenseOwed(...) : null`.
- **Invalidation key = every input that flows into `allocateExpenseOwed`** (enumerated from the callsite `:1546-1558`, principle 4):

  | `allocateExpenseOwed` arg | source in widget | compare in `didUpdateWidget` |
  |---|---|---|
  | `amount` | `widget.amount` (`Decimal`) | `widget.amount != oldWidget.amount` (value ==) |
  | `splitMode` | `widget.splitMode` (enum) | `!=` |
  | `splitDistribution` | `widget.splitDistribution` (`Map<String,Decimal>?`) | `!mapEquals(...)` (deep — `Decimal` has value `==`) |
  | `scope` | `widget.scope` (enum) | `!=` |
  | `customSplitParticipants` | `widget.customSplitParticipants` (`Set<String>`) | `!setEquals(...)` (deep) |
  | `payerId` | `widget.payerId` (`String?`) | `!=` |
  | `participantIds` | `widget.event.participantIds` | covered by `!identical(widget.event, oldWidget.event)` |
  | `currency` | `widget.currency` (`String`) | `!=` |
  | `onFallback` | constant `null` | n/a |

  If **any** differ, recompute `_owed` from scratch (the `_isNonEqual` gate inside the recompute handles the null/non-null transition when `splitMode`/`splitDistribution` change). `mapEquals`/`setEquals` are from `package:flutter/foundation.dart` (re-exported by the existing `material.dart` import).

`build()` keeps the existing `each` (equal-split per-head), `count`, scope-label, and tile-rendering logic unchanged — it just reads `_displayNames` and `_owed` instead of computing them inline. The `_isNonEqual` and `_splitParticipantIds` getters stay (used in `build` for the `each`/recipient path and as inputs to the owed recompute).

### Perf seam (proves the win + guards correctness)
Add two library-level counters, mirroring the `debugCalculateBalancesCount` precedent in `expense_provider.dart`:

```dart
@visibleForTesting int debugSplitPreviewNameComputes = 0;
@visibleForTesting int debugSplitPreviewOwedComputes = 0;
```

Incremented inside the State's recompute paths. A test can then assert a pure amount edit increments `owed` but **not** `name`.

## Callsite classification (principle 1)

`_SplitPreviewCard` is **INBOUND (display only)**. The preview reads State (`_amount`, `_splitMode`, `_splitDistribution`, `_customSplitParticipants`, `_scope`, payer) and renders figures. It has **no callback upward** and feeds **no write**. The persisted split is built in `_submit` from the editor's State fields, *not* from the preview or `_owed`. So even a (prevented) stale cache could only mis-*display*, never mis-*persist* — there is no OUTBOUND path and no oracle/parity surface touched. `allocateExpenseOwed` itself is unchanged; we only memoize its call.

## Verification principles

1. **Callsite classification** — done above: INBOUND only.
2. **Concrete claims vs code** — all line refs verified on the branch (preview `:1480-1672`, amount source `:668-669`, resolver `:129-137`, `Event==` `:220-222`, `allocateExpenseOwed` `:455-481`).
3. **One read-path per write-path** — n/a (no write path). The read path: State fields → `_SplitPreviewCard` → tiles. Unchanged except memoized.
4. **Fields from the type** — `allocateExpenseOwed` inputs enumerated from the callsite (table above), not memory.
5. **Data contracts** — cache-invalidation predicates spelled out exactly (table). No map-key/callback shape changes; `_SplitPreviewCard`'s constructor params are unchanged.
6. **Arithmetic decomposition** — n/a. We do not change any allocation/summation; `_owed` is the verbatim output of the same `allocateExpenseOwed` call, just cached. WYSIWYG parity with the ledger (#242) is preserved because the inputs and the helper are identical.
7. **Adversarial pass (orthogonal axis = identity/time)** — the #106 same-id rename: emit a new `Event` (same `id`, a participant renamed) → the name map **must** refresh. This is the axis the `Event==` trap lives on; the regression test (T2) exercises it. Time axis: rapid keystrokes (amount A→B→A) must always show the live amount's figures — covered by the owed-honesty test (T1).

## TDD plan (RED first)

New file `test/features/ledger/expense_editor_split_preview_memo_test.dart`, pumping `ExpenseEditorBody` in edit mode (mirrors `expense_editor_split_preview_test.dart`). `setUp` resets the two debug counters to 0.

- **T1 — owed honesty on amount change (catches stale `_owed`):** seed shares 2:1 @ 9.000 → tiles show `OMR 6.000` / `OMR 3.000`. `enterText` `12.000` into the amount field, pump. Expect `OMR 8.000` / `OMR 4.000`; `OMR 6.000`/`OMR 3.000` gone. Asserts `debugSplitPreviewOwedComputes` increased.
- **T2 — name map not stale on same-id rename (catches `Event==` key, #106):** drive `eventDetailProvider` via a `StreamController`. Emit event with two participants; assert displayed name. Emit a **new `Event` instance, same `id`**, one participant renamed; pump. Expect the new name; old name gone. (Would pass with a buggy `==`-key only if identity is used.)
- **T3 — name map memoized across amount keystroke (proves the win):** seed non-equal split. Record `debugSplitPreviewNameComputes` (==1). `enterText` a new amount, pump. Expect `debugSplitPreviewNameComputes` **unchanged** (==1) while `debugSplitPreviewOwedComputes` incremented.
- **T4 — equal split still skips owed:** seed equal split. Type a new amount. Expect `debugSplitPreviewOwedComputes == 0` throughout and the uniform "each" figure updates.

Existing tests that must stay green unchanged: `expense_editor_split_preview_test.dart` (#242 WYSIWYG), `expense_editor_body_same_name_test.dart` (#289 disambiguation).

## Out of scope (named follow-ups, do not bundle)

- `_PaidByCard` (`:1448-1453`) recomputes the **same** `disambiguateEventParticipants(event)` per keystroke. Leaving it means one name-map recompute per keystroke survives. Sibling perf work (#490 / a dedicated follow-up) can hoist a single shared name map to the parent and pass it to both cards. #627 is scoped to `_SplitPreviewCard` per its title.
- The other 3 `disambiguateEventParticipants` sites in this file (`:536`, `:1215`, `:2065`) live in pickers/sheets built on-demand, not per keystroke — no per-keystroke cost.

## Done

- [ ] T1–T4 written, RED for the right reason, then GREEN.
- [ ] `expense_editor_split_preview_test.dart` + `expense_editor_body_same_name_test.dart` still green.
- [ ] `flutter analyze` clean; full `test/features/ledger/` green.
- [ ] PR `Closes #627` (commit body), `Spec:` line, RED evidence; `/automerge`.
