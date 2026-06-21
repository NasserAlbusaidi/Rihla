# Itemized Split — Bill-Level Adjustments (#605) Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Layer service charge / tax / tip / discount onto the per-item itemized split (#203), folding each into the same exact `splitDistribution` so the per-person shares still sum to the bill — to the last subunit.

**Architecture:** Purely additive on top of #203. Adjustments are typed display metadata living in the already-reserved `splitExplanation.adjustments[]`; balance truth stays in `splitDistribution` (persisted AS `SplitMode.exact`). The existing write-time producer `BalanceCalculator.allocateItemizedDistribution` is extended to fold adjustments **in integer subunits**, preserving conservation (`Σ owed == bill`) and whole-subunit values (#596). **No schema version bump. No `firestore.rules` change. No server/oracle change** (`splitExplanation` is never read by `recomputeNet`; the persisted artifact is a normal exact split).

**Tech Stack:** Flutter, Riverpod 2.x, `decimal` package, `MoneySerializer` (Decimal↔integer subunits at the Firestore boundary only).

---

## Context — verified live surface (code wins over memory; re-verified 2026-06-21 in worktree `wf-605` @ `e76da07e`)

Eight touch-points, each confirmed by `Read`/`grep`:

1. **Model** `lib/features/ledger/models/split_explanation.dart`
   - `SplitItem{label, amountFils, quantity, participantIds, allocation}` — lenient `fromMap`, strict producer.
   - `SplitExplanation{type, version, items, adjustments}` — `adjustments` is currently **`List<dynamic>?`** (reserved by #203 Slice 1, round-tripped opaquely). `toMap` writes `if (adjustments != null) 'adjustments': adjustments`; `fromMap` reads `map['adjustments'] as List?`.
   - **#605:** introduce typed `SplitAdjustment` model; change `adjustments` → `List<SplitAdjustment>?`; map `.toMap()`/`.fromMap()` on round-trip. *(No persisted #605 data exists yet. ONE existing test — `split_explanation_model_test.dart:51-65` — constructs a raw-`Map` `adjustments` literal and asserts `.first as Map`; it MUST be rewritten to the typed model in Task 1. No `lib/` code constructs `adjustments` — the Gate confirmed this is the only caller.)*

2. **`SplitResult`** `custom_split_sheet.dart:31-46` — `{mode, distribution, items}`. **#605:** add `adjustments`.

3. **Allocator** `expense_provider.dart:531-567` — `allocateItemizedDistribution({required List<SplitItem> items, required String currency})`. Integer-subunit; per-item `base = amountFils ~/ n`, remainder → alphabetically-last assignee. **#605:** add optional `adjustments` + `participantIds` (full table); fold adjustments in subunits.

4. **Sheet state** `_CustomSplitSheetState` (`custom_split_sheet.dart`):
   - `_buildItemizedResult()` (396-407) — builds items + `allocateItemizedDistribution`, returns `SplitResult(mode: exact, distribution, items)`.
   - `_itemizedPreview` (315-325) — live per-person owed from valid drafts.
   - `_itemizedRemainder` (310) = `widget.total - _itemizedSum` (items only).
   - `_itemizedCanApply` (327-332) = all drafts valid && `|remainder| ≤ tolerance`.
   - **#605:** add `_AdjustmentDraft` state + `initialAdjustments` seed; fold adjustments into preview, remainder, reconcile, and the built result.

5. **Itemized UI part** `custom_split_sheet_itemized.dart` — `_ItemDraft`, `_ItemizedBody`, `_AssignSheet`, etc. **#605:** add the Adjustments section + add-adjustment sheet here (sibling part).

6. **Footer** `custom_split_sheet_chrome.dart:68-203` — `_Footer{itemized, itemizedSum, itemizedRemainder, …}` drives the "Items match total / N left" status. **#605:** the threaded `itemizedSum`/`itemizedRemainder` must become adjustments-inclusive (computed in sheet state; footer signature unchanged).

7. **Bridge** `expense_editor_body.dart`:
   - `561-576` `showCustomSplitSheet(... initialItems: _splitExplanation?.items, initialItemized: _splitExplanation != null)` — **#605:** add `initialAdjustments: _splitExplanation?.adjustments`.
   - `585-586` `_splitExplanation = result.items == null ? null : SplitExplanation(items: result.items!)` — **DROPS adjustments today.** **#605:** `SplitExplanation(items: result.items!, adjustments: result.adjustments)`.

8. **Edit-screen equality** `edit_expense_screen.dart:210-225` `_explanationEquals` — compares items only. **#605:** also compare `adjustments` (order-sensitive list of value-equal adjustments) so an adjustment-only edit (e.g. add a discount) persists.

**Rules — confirmed NO change** (`security/firestore.rules:542-544`): `splitExplanationBounded(d)` = `splitExplanation is map && size() <= 64` (top-level keys). Adding the `adjustments` key keeps top-level count well under 64; `splitDistribution` is the folded exact map and already passes `splitValuesNonNegative` (529-531). The fold never emits a negative (proof below), so the existing non-negative rule is satisfied.

---

## The fold — money math (the crux; integer subunits throughout)

`allocateItemizedDistribution` gains two optional params and three phases. **All arithmetic is in integer subunits; `MoneySerializer.fromSubunits` converts at the very end** (keeps every owed whole-subunit, #596).

```
allocateItemizedDistribution({items, currency, adjustments = const [], participantIds = const []}):
  owed : Map<id,int> = {}

  # ── Phase 1 — items (UNCHANGED from #203) ──
  for item in items:
    assert item.amountFils >= 0 (throw); assignees = sorted(unique(item.participantIds)); assert non-empty (throw)
    base = item.amountFils ~/ n ; rem = item.amountFils - base*n
    each assignee += base ; alphabetically-last assignee += rem

  if adjustments empty: return owed→Decimal       # EARLY RETURN: byte-identical to #203 (participantIds untouched)

  assert participantIds nonEmpty (throw ArgumentError)   # adjustments ⇒ caller MUST pass the whole table (reuse-safety)
  equalBase = sorted(set(participantIds))          # the whole table — for 'equal' allocation
  itemSubtotal : Map<id,int> = copy(owed)          # per-person item subtotal snapshot

  # ── Phase 2 — additive adjustments (service / tax / tip): each ADDS ──
  for adj in adjustments where type != 'discount':
    assert adj.amountFils >= 0 and adj.type in ADDITIVE_TYPES {service,tax,tip} (throw)
    shares = adj.allocation == 'proportional'
               ? spreadProportional(adj.amountFils, itemSubtotal, fallbackBase: equalBase)
               : spreadEqual(adj.amountFils, equalBase)
    owed += shares                                 # per-person

  # ── Phase 3 — discounts: SUBTRACT, re-allocate the REMAINING bill proportional to pre-discount owed ──
  # discount.allocation is IGNORED (always proportional to pre-discount owed — this is what guarantees
  # non-negativity; the field is normalized to 'proportional' on write, Task 4).
  preDiscount = copy(owed) ; preTotal = Σ preDiscount.values
  totalDiscount = Σ (adj.amountFils for adj where type == 'discount', each asserted type=='discount' & >= 0)
  if totalDiscount > 0:
    remaining = preTotal - totalDiscount
    assert remaining >= 0 (throw)                  # OUTBOUND only — reconcile gate guarantees it; preview catches (Task 3)
    owed = spreadProportional(remaining, preDiscount, fallbackBase: equalBase)   # REPLACES owed entirely

  return { id: MoneySerializer.fromSubunits(v, fenced) for id,v in owed }

spreadEqual(amount, baseSorted):                   # base = amount ~/ n ; remainder → alphabetically-last
  n = len(baseSorted); if n==0 return {}
  out = {} ; base = amount ~/ n ; rem = amount - base*n
  for i,k in baseSorted: out[k] = base + (i==n-1 ? rem : 0)
  return out

spreadProportional(amount, weights:Map<id,int>, fallbackBase:List<id>):   # floor by weight; remainder → alphabetically-last weighted
  keys = sorted(k for k in weights where weights[k] > 0) ; total = Σ weights[keys]
  if keys empty or total == 0: return spreadEqual(amount, fallbackBase)   # NO positive weight ⇒ equal over the whole table (never drop `amount`)
  out = {} ; used = 0
  for k in keys: s = (amount * weights[k]) ~/ total ; out[k] = s ; used += s
  out[keys.last] += (amount - used)
  return out
```

**Why this is correct (the Gate will check each):**

- **Conservation — `Σ owed == Σitems + Σadditive − Σdiscount`, exactly.** Phase 1 sums exactly to `Σ item.amountFils` (remainder dumped). Each additive `spread*` sums exactly to its `amountFils` (empty-weight proportional falls back to an equal spread over the whole table — the amount is never dropped). Phase 3 *replaces* owed with `spreadProportional(remaining, …)` summing exactly to `remaining = preTotal − totalDiscount`. The UI reconcile gate (Decimal, ±0.001) guarantees that folded subtotal is within one subunit of the entered `bill` — **the same tolerance contract as Exact mode**. So persisted-total≈bill is exactly as tight as items-only #203; the exact identity the tests pin is the folded-subtotal sum, not `== bill` to the subunit.
- **Whole-subunit.** Every op is integer; conversion to `Decimal` is the last step. Mirrors #596.
- **Non-negative — provably, no clamp.** Items ≥ 0; additive only adds. Phase 3 sets `owed = spreadProportional(remaining, preDiscount)` with `remaining ≥ 0` and weights `≥ 0` ⇒ every floor share ≥ 0 and the alphabetically-last remainder is **added** to a non-negative floor ⇒ every owed ≥ 0. (This is why discount is modelled as *re-allocating the remaining bill proportionally*, **not** as subtracting a per-person discount with a remainder dump — the latter can go negative in small-subunit cases, e.g. `{A:1,B:1,C:1}` total 3, discount 2 → naive dump gives C = −1. Re-allocating `remaining=1` proportionally gives `{C:1}`, all ≥ 0. This edge is a Gate adversarial case below.)
- **Discount > bill is impossible from the UI** (reconcile blocks it) and **throws** if a forged/legacy doc reaches the producer (strict, like the existing negative-`amountFils` throw). The editor re-validates on reopen (lenient `fromMap` → strict re-feed), so a forged doc displays but cannot resave a bad fold.
- **Preview (INBOUND) never throws; build (OUTBOUND) is reconcile-gated.** `_itemizedPreview` recomputes every keystroke and must not hit the Phase-3 `remaining < 0` throw mid-typing (e.g. a 5.000 discount entered before items are finished). The preview **drops discount adjustments from the fold whenever `Σdiscount > Σitems + Σadditive`** (would-be `remaining < 0`) — a Decimal pre-check, mirroring how it already excludes invalid item drafts — so it only ever feeds the allocator a reconcilable, non-negative fold. It does **NOT** blanket-`catch ArgumentError`: an empty-`participantIds`/unknown-type error is a genuine bug that must still surface in tests. The strict Phase-3 throw stays live on the OUTBOUND build path, which `_itemizedCanApply` has already reconciled. (Task 3.)
- **Whole-table = the persisted split universe (oracle-parity invariant).** The `participantIds` passed for equal allocation MUST equal the expense's split universe for the chosen scope — `widget.participants` == `_splitParticipantIds(event)` (custom scope ⇒ `customSplitParticipants`). This holds today (both derive from the same source at Apply). It is load-bearing because a zero-item adjustment-bearer's folded owed key must sit inside the per-event oracle universe (`participantIds ∪ payers/settlement-parties`, **not** split recipients) or `calculateBalances`/`recomputeNet` would DROP it on read-back and break conservation (Σnet≠0). A future *assigned* adjustment must not let `equalBase` diverge from the persisted universe.

**Verification principles applied:**
1. *Callsite classification.* `allocateItemizedDistribution` callers: `_buildItemizedResult` (OUTBOUND — feeds the persisted `splitDistribution`) and `_itemizedPreview` (INBOUND — display preview). Same fold function for both ⇒ preview == persisted. `SplitExplanation.toMap` is OUTBOUND (write path via `expense_service`); `fromMap` is INBOUND (reopen). `_explanationEquals` is the OUTBOUND change-detector.
2. *Concrete claims verified* — every path/line above re-grepped in the worktree (see Context).
3. *Read-path per write-path.* Write `splitExplanation.adjustments` → read by `SplitExplanation.fromMap` → `_initAdjustmentDrafts` (reopen) and by nothing on the balance side (oracle never reads it). Write `splitDistribution` (folded) → read by `BalanceCalculator.calculateBalances` + server `recomputeNet` as a normal exact split.
4. *Fields from the type.* `SplitAdjustment` = `{type, amountFils, allocation}` (no `participantIds` in v1 — assigned-discount deferred). `SplitItem` unchanged.
5. *Data contracts.* `SplitResult.adjustments : List<SplitAdjustment>?` (null for non-itemized; possibly empty for itemized-without-adjustments). Map keys persisted: exactly `{type, amountFils, allocation}`.
6. *Arithmetic decomposition.* `splitDistribution` here is NOT a decomposable aggregate — it is the single folded truth; per-line per-person breakdown is intentionally not persisted (display rebuilds item+adjustment rows from `items`/`adjustments`, not from `splitDistribution`).
7. *Adversarial axis.* Fix axis = money fold; adversarial cases exercise **identity/currency/rounding** axes: JPY (×1, no subunits), the negative-discount edge `{1,1,1}−2`, a zero-item participant bearing an equal charge, and a multi-currency expense (per-doc currency).

---

## Locked design decisions (approved canvas — "Itemized Split - Bill Adjustments", 2026-06-21)

- **Four types:** service, tax, tip (ADD); discount (SUBTRACT). One shape each.
- **Default allocation for a new additive adjustment = `equal`** ("Split equally"), with `proportional` ("By item share") as the opt-in. *(User's canvas edit set service/tax/tip all `equal`; this is the demonstrated default.)*
- **Equal = the whole table** — spread across **all** participants, even someone on no item. Proportional follows item subtotal (zero-item person pays nothing there).
- **Discount is always `proportional`** to each person's pre-discount owed (UI hides the alloc toggle) — guarantees non-negativity.
- **Fixed-amount entry only** (type the figure off the receipt). % helper deferred.
- **Assigned discount** (pick who bears it) deferred to fast-follow → would add `SplitAdjustment.participantIds` (additive, lenient `fromMap`).
- **Reconcile is client-owned:** Apply disabled until `items + additive − discount == bill` (±0.001, same tolerance as Exact).
- **Reopen round-trips adjustments:** `_explanationEquals` compares adjustments; the editor rebuilds item AND adjustment rows.

---

## Out of scope (do not build)
- `%`-based entry, `SplitAdjustment.participantIds` / assigned-discount, any `firestore.rules` change, any server/oracle change, any `splitExplanation` version bump, #485 (collapse the 3-section split editor) — separate concern on the same surface.
- **Unsupported-currency fractional truncation** (the Decimal reconcile gate keeps fractions; `toAdjustment`/`_ItemDraft.toItem` truncate via `toBigInt()` for an unsupported currency, so gate-sum and fold-sum can diverge): inherited #203 behavior, intentionally mirrored — NOT a #605 regression. All 7 production currencies are `MoneySerializer`-supported (exact), so this is unreachable in practice.

---

## Tasks

> Branch: `feat/605-itemized-adjustments` (worktree `wf-605`). TDD throughout: RED → GREEN → refactor → commit. Run `flutter analyze` clean before each commit. Money tests are table-driven (clean / warning / error) per the money-code rule.

### Task 1: `SplitAdjustment` model + typed `adjustments` round-trip

**Files:**
- Modify: `lib/features/ledger/models/split_explanation.dart`
- Test: `test/unit/split_explanation_model_test.dart`

**Step 1 — RED:** add/replace tests:
- **Rewrite the EXISTING obsolete test** `test/unit/split_explanation_model_test.dart:51-65` ("round-trips it opaquely"): it constructs a raw `List<Map>` `adjustments` literal and asserts `.first as Map` — both break under the typed model (won't compile / the cast throws). Replace with the typed round-trip below; delete the opaque-`Map` assertions, keep "omits key when null/empty". Use canonical type `'service'` (not the old `'service_charge'`). *(Gate-caught: this is the only existing constructor of `adjustments`; the spec's earlier "no other constructor" note was wrong.)*
- `SplitAdjustment.fromMap` lenient: missing keys → `type:'service', amountFils:0, allocation:'equal'`; an unknown type string (e.g. `'service_charge'`) does NOT throw on read (display stays lenient); never throws.
- `SplitAdjustment.toMap` round-trips `{type, amountFils, allocation}` exactly.
- `SplitExplanation.fromMap` parses `adjustments` into `List<SplitAdjustment>` (skips non-map entries via `whereType<Map>()`).
- `SplitExplanation.toMap` emits `adjustments` as a list of maps **only when non-null & non-empty**; omits the key otherwise (keeps top-level count minimal; `null`/`[]` ⇒ no key).
- Full round-trip: explanation with 1 item + 2 adjustments → `toMap` → `fromMap` → equal. **`SplitAdjustment` has no value `==` (like `SplitItem`) — assert field-by-field (`type`/`amountFils`/`allocation`) per element, NEVER `expect(list, list)` / `==` (identity-based → false RED).**

**Step 2:** Run `flutter test test/unit/split_explanation_model_test.dart` → FAIL (SplitAdjustment undefined).

**Step 3 — GREEN:** add `SplitAdjustment` (fields `type`/`amountFils`/`allocation`, default `allocation='equal'`, lenient `fromMap`, `toMap`); define canonical type constants `const kAdjustmentTypes = {'service','tax','tip','discount'}` (additive = `type != 'discount'`) — the allocator allow-list, the l10n labels, and the tests all reference this one set. Change `SplitExplanation.adjustments` to `List<SplitAdjustment>?`; update `fromMap` mirroring the items wrap — `(map['adjustments'] as List?)?.whereType<Map>().map((e) => SplitAdjustment.fromMap(Map<String, dynamic>.from(e))).toList()` — and `toMap` (`if (adjustments != null && adjustments!.isNotEmpty) 'adjustments': [for (final a in adjustments!) a.toMap()]`).

**Step 4:** Run → PASS. `flutter analyze` clean.

**Step 5:** Commit `feat(ledger): SplitAdjustment model + typed splitExplanation.adjustments round-trip (#605)`.

---

### Task 2: Fold adjustments in `allocateItemizedDistribution` (money crux)

**Files:**
- Modify: `lib/features/ledger/providers/expense_provider.dart:531-567`
- Test: `test/unit/itemized_split_allocator_test.dart`

**Step 1 — RED (table-driven):** add cases — currency OMR (×1000) unless noted:
- *clean / additive equal:* items {N:2000(mixed-grill share), S:6000, K:8000, H:4000}=20000, participants all 4, +service 2000 equal +tax 1000 equal +tip 1000 equal → each +1000 ⇒ {N:3000,S:7000,K:9000,H:5000}, Σ=24000 (the approved scenario).
- *additive proportional:* items {A:5000,B:15000}=20000, +service 4000 proportional ⇒ A:1000,B:3000 ⇒ {A:6000,B:18000}.
- *equal across whole table incl. zero-item person:* items {A:10000} only, participants {A,B}, +tax 1000 equal ⇒ spreadEqual(1000,[A,B]) = {A:500,B:500} ⇒ owed {A:10500, B:500}, Σ=11000 (B owes the tax despite no item).
- *discount re-allocation:* items {A:5000,B:15000}, +service 4000 proportional (A:6000,B:18000, pre=24000), discount 6000 → remaining 18000 proportional ⇒ A:floor(18000·6000/24000)=4500, B:13500 (+rem 0) ⇒ {A:4500,B:13500}, Σ=18000, none negative.
- *negative-edge (adversarial):* items {A:1,B:1,C:1}=3 (subunits), discount 2 → remaining 1 proportional over {1,1,1}: floors 0,0,0 used 0 rem 1 → C:1 ⇒ {A:0,B:0,C:1}, Σ=1, **none negative** (the naive-dump trap).
- *equal additive on a zero-item person, THEN discount (adversarial):* items {A:10000} only, participants {A,B}, +service 1000 equal (→ A:10500, B:500; pre=11000), discount 2000 → remaining 9000 proportional over {A:10500, B:500}: A=floor(9000·10500/11000)=8590, B=floor(9000·500/11000)=409, used 8999, +rem 1 → alphabetically-last positive-weight key (B) ⇒ {A:8590, B:410}, Σ=9000, none negative (proves the equal-additive→discount path conserves).
- *JPY (×1):* items {A:100,B:300}=400 JPY, +tip 100 equal ⇒ each +50 ⇒ {A:150,B:350}; whole-yen, Σ=500.
- *additive proportional, empty items (reuse/forged backstop):* items {}, +service 1000 proportional, participantIds {A,B} ⇒ `spreadProportional` falls back to equal over the whole table ⇒ {A:500,B:500}, Σ=1000 (amount NOT dropped — the conservation-hole fix).
- *no adjustments:* byte-identical to current output (regression pin); `participantIds` not required on this early-return path.
- *error:* discount 100 with empty items+additive (preTotal 0, remaining<0) → `ArgumentError`. Unknown `type:'gratuity'` → `ArgumentError`. Negative `amountFils` → `ArgumentError`. **adjustments non-empty + empty `participantIds`** → `ArgumentError` (whole-table required).
- *conservation property:* for each case `Σ values (subunits) == Σitems+Σadditive−Σdiscount` **exactly** (the real guarantee — within ±0.001 of the entered bill via the UI gate, same as Exact mode); every value whole-subunit; every value ≥ 0.

**Step 2:** Run `flutter test test/unit/itemized_split_allocator_test.dart` → FAIL.

**Step 3 — GREEN:** implement the three-phase fold + `spreadEqual`/`spreadProportional` private statics exactly as the pseudocode above. Keep Phase-1 path returning early (byte-identical) when `adjustments` empty.

**Step 4:** Run → PASS (incl. the no-adjustments regression). `flutter analyze` clean.

**Step 5:** Commit `feat(ledger): fold bill-level adjustments into itemized exact distribution (#605)`.

---

### Task 3: `SplitResult.adjustments` + sheet state, preview, reconcile, build

**Files:**
- Modify: `lib/features/ledger/widgets/custom_split_sheet.dart`
- Test: `test/features/ledger/custom_split_sheet_itemized_test.dart`

**Step 1 — RED:** widget tests — (a) adding a service adjustment changes the live "Each person owes" rows and the footer to reconciled; (b) Apply disabled while `items ± adjustments ≠ total`, enabled when reconciled; (c) `_buildItemizedResult` returns `SplitResult` with `mode: exact`, a folded `distribution`, and `adjustments` populated; (d) **typing a discount larger than the current items does NOT crash the preview** — `_itemizedPreview` drops the discount from the render (no `ArgumentError` in `build()`); Apply stays disabled until reconciled; (e) **an adjustment entered with zero item rows renders non-zero owed rows** (whole-table spread), not an empty preview.

**Step 2:** Run → FAIL.

**Step 3 — GREEN:**
- `SplitResult`: add `final List<SplitAdjustment>? adjustments;` (ctor optional). Update doc comment (non-null only for itemized).
- `showCustomSplitSheet` + `CustomSplitSheet`: add `List<SplitAdjustment>? initialAdjustments`.
- State: `late List<_AdjustmentDraft> _adjDrafts; void _initAdjustmentDrafts()` (seed from `initialAdjustments` or empty). `_addAdjustment`/`_removeAdjustment`. Dispose any controllers.
- `_adjAdditiveSum`/`_adjDiscountSum` (Decimal); `_itemizedRemainder` → `widget.total - (_itemizedSum + _adjAdditiveSum - _adjDiscountSum)`.
- `_itemizedPreview` (INBOUND) and `_buildItemizedResult` (OUTBOUND): pass `adjustments: [valid drafts → SplitAdjustment]` and `participantIds: widget.participants.map((p)=>p.id).toList()` into `allocateItemizedDistribution`. **In `_itemizedPreview`: (i) relax the existing `if (items.isEmpty) return const {}` guard to `if (items.isEmpty && validAdjustments.isEmpty) return const {}` so an adjustment entered before any item still renders the whole-table spread; (ii) drop the discount adjustments from the preview fold whenever `_adjDiscountSum > _itemizedSum + _adjAdditiveSum` (would-be `remaining<0`), so the allocator never hits the Phase-3 throw mid-typing.** Do NOT blanket-`catch ArgumentError` — an empty-`participantIds`/unknown-type throw is a real bug that must surface. `_buildItemizedResult` passes everything unguarded (`_itemizedCanApply` already reconciled at Apply-time).
- `_itemizedCanApply`: all item drafts valid **and** all adjustment drafts valid (amount > 0, type set) **and** `|_itemizedRemainder| ≤ tolerance`.
- Footer call passes the adjustments-inclusive `_itemizedSum`-equivalent + `_itemizedRemainder` (footer signature unchanged).

**Step 4:** Run → PASS. `flutter analyze` clean.

**Step 5:** Commit `feat(ledger): thread bill-level adjustments through the split sheet (#605)`.

---

### Task 4: Adjustments UI — section + add-adjustment sheet + l10n

**Files:**
- Modify: `lib/features/ledger/widgets/custom_split_sheet_itemized.dart`
- Modify: `lib/l10n/app_en.arb`, `lib/l10n/app_ar.arb`
- Test: `test/features/ledger/custom_split_sheet_itemized_test.dart`

**Step 1 — RED:** test the add-adjustment flow: tap "+ Add" under Adjustments → type chips (Service/Tax/Tip/Discount) → enter amount → choose allocation (default "Split equally"; discount hides the toggle) → Done → row appears with signed amount; the live owed updates.

**Step 2:** Run → FAIL.

**Step 3 — GREEN:**
- `_AdjustmentDraft` (mutable: type, amount controller, allocation; default `allocation:'equal'`; selecting **discount forces `allocation:'proportional'`** and hides the toggle, so the persisted discount field never lies about behavior). `toAdjustment(currency)` converts the typed amount to `amountFils` **byte-for-byte like `_ItemDraft.toItem`** (`MoneySerializer.isSupported(currency) ? toSubunits(parse, currency) : parse.toBigInt().toInt()`) so preview==persisted even for an unsupported currency (the allocator's `fenced='OMR'` path).
- `_AdjustmentsSection` (reuse `_ItemizedSectionHeader`; rows show type icon, label, signed amount `+`/`−`, remove).
- `_AddAdjustmentSheet` modal: type chip-row, amount field (`LocalizedDecimalTextInputFormatter`, per-currency decimals), allocation radios ("By item share" / "Split equally"), discount note. Mirror existing sheet chrome.
- Wire the section into `_ItemizedBody` between Items and "Each person owes".
- l10n keys (en + ar): `adjustmentsHeader`, `adjustmentAdd`, `adjustmentRemove`, `adjustmentTypeService/Tax/Tip/Discount`, `adjustmentAmount`, `adjustmentAllocEqual` ("Split equally"), `adjustmentAllocProportional` ("By item share"), `adjustmentDiscountNote`, `adjustmentSpreadHeader` ("How to spread it"). Keep ARB placeholder discipline; mirror `itemized*` naming.

**Step 4:** Run → PASS. `flutter analyze` clean. `flutter gen-l10n` (or build) regenerates `app_localizations`.

**Step 5:** Commit `feat(ledger): add-adjustment sheet + adjustments section UI + l10n (#605)`.

---

### Task 5: Bridge threading + reopen round-trip

**Files:**
- Modify: `lib/features/ledger/widgets/expense_editor_body.dart:574-586`
- Modify: `lib/features/ledger/screens/edit_expense_screen.dart:210-225`
- Test: `test/features/ledger/expense_editor_itemized_test.dart`

**Step 1 — RED:** (a) create an itemized expense with a discount → assert the persisted payload's `splitExplanation.adjustments` is present AND `splitDistribution` is the folded exact map; (b) reopen → the adjustment rows rebuild and Apply stays reconciled; (c) **adjustment-only edit** (add a discount to an items-only itemized expense) → the folded `splitDistribution` persists via the existing `splitChanged` gate (distribution diff), AND `_explanationEquals` returns false so the new `splitExplanation` metadata persists too ⇒ on reopen the adjustment rows rebuild. *(Gate note: the money was never at risk — `splitChanged` already drives the folded-distribution write independently; the `_explanationEquals` fix is load-bearing specifically for the display-metadata round-trip.)*

**Step 2:** Run → FAIL (adjustments dropped at `expense_editor_body.dart:585-586`; `_explanationEquals` ignores adjustments so the metadata round-trip silently regresses).

**Step 3 — GREEN:**
- `expense_editor_body.dart`: add `initialAdjustments: _splitExplanation?.adjustments` to `showCustomSplitSheet`; change line 585-586 to `SplitExplanation(items: result.items!, adjustments: result.adjustments)`.
- `edit_expense_screen.dart` `_explanationEquals`: after the items loop, compare `adjustments` (both null ⇒ equal; one null ⇒ not; length differs ⇒ not; element-wise hand-compare `type/amountFils/allocation` — **`SplitAdjustment` has no `==`, so never use list `==`**, exactly as the existing `SplitItem` loop does). Order-sensitive (display order is meaningful, matches the items list contract — items are order-sensitive too). *(This gate only drives the `splitExplanation` metadata write; the folded `splitDistribution` already rides the independent `splitChanged` gate at `edit_expense_screen.dart:107`.)*

**Step 3b — read-back parity (custom scope):** add a test that a custom-scope itemized expense with an equal adjustment on a zero-item participant folds to a distribution whose keys ⊆ the custom split universe, and that `BalanceCalculator.calculateBalances` reads it back with NO key dropped and `Σnet == 0` (guards the oracle-universe invariant — a folded owed key outside the universe would be silently dropped).

**Step 4:** Run → PASS. Full ledger suite green (`flutter test test/features/ledger/`). `flutter analyze` clean.

**Step 5:** Commit `feat(ledger): round-trip bill-level adjustments on save/reopen (#605)`.

---

### Task 6: Whole-suite verify + Gate-prep

- Run `flutter analyze` (clean) and `flutter test` (full). Confirm coverage on the new money path.
- Re-read the diff (`git diff main...HEAD`) — one concern (#605), no opportunistic refactors, no rules/server change.
- Confirm `splitExplanation` top-level key count still ≤ 64 with adjustments (it is — `type, version, items, adjustments` = 4).
- **PR slicing decision:** ship as one PR `Closes #605` (commit body too, per squash-auto-close rule), Gate-category → `/automerge` (Opus diff-review + refuter). If the diff is large, split model+allocator (Tasks 1-2) from UI+bridge (Tasks 3-5) into two PRs, the second `Closes #605`.

---

## Done means
- [ ] Service/tax/tip/discount fold into one exact `splitDistribution`; `Σ owed == Σitems+Σadditive−Σdiscount` exactly (≈ bill within ±0.001, same as Exact mode), every value whole-subunit and ≥ 0.
- [ ] Default new-adjustment allocation = equal; discount always proportional; equal spans the whole table.
- [ ] Reconcile gate includes adjustments; Apply blocked until `items ± adjustments == bill`.
- [ ] Reopen rebuilds items + adjustments; adjustment-only edits persist.
- [ ] Table-driven money tests (clean/warning/error incl. JPY, zero-item, negative-edge) green; full suite + analyze clean.
- [ ] No schema bump, no `firestore.rules` change, no server/oracle change.
- [ ] Gate (fresh-context Opus) → no [P1]; `/automerge` review + refuter cleared.
