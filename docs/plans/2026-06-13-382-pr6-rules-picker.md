# #382 PR-6 — The flip: rules relaxation + per-expense currency picker

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make mixed-currency data *creatable* — relax the four `currencyMatchesGroup` rule clauses to the already-present `validCurrency` floor, and add a per-expense currency picker (smart default + soft fat-finger warning) to the add-expense form. This is the **last rung** of #382; everything upstream (per-currency buckets client+server+aggregate, stepped settle) already bucketed and parity-tested. **Closes #382.**

**Architecture:** Two halves, one PR. (1) **Rules** = pure *deletions*: the `validCurrency(data.currency)` floor already runs in both base validators (`validExpenseBase:563`, `validSettlementCore:93`), so removing the four `currencyMatchesGroup`/group-equality clauses (+ the now-orphan helper) relaxes "must equal group currency" → "must be a supported code" with nothing else loosened. (2) **Client** = the add-expense editor gains a `_selectedCurrency` (reusing the existing `CurrencyPickerSheet`), a smart default (last-used-in-event → group default), and an inline soft warning when the pick diverges from the event's dominant currency. `group.currency` stays create-only-immutable, re-cast as the *default*. No Functions/oracle/aggregate change → deploy is **rules-only**.

**Tech Stack:** Firestore security rules; Flutter/Riverpod 2.x; Decimal-only money; `MoneySerializer` scale boundary; Jest+emulator rules tests (Java 21); `flutter_test`.

---

## Why this is small (the upstream did the hard part)

PRs 0–5 already shipped: `Settlement` retains `currency` (PR-0 `84dae4bd`), client+server+aggregate bucket per-currency, stepped settle walks non-zero buckets. The server oracle (`recomputeNet`/`foldEventNet`) already folds expenses **and** settlements by their own per-doc currency, and the gates already require **every bucket** to net zero. So once the rules let a non-group currency through, the entire stack already does the right thing with it. PR-6 only removes the last lock and gives the user a way to pick.

**Verified against live code (not the issue, not memory, not the scout):**
- `settlement_model.dart:34` **has** `final String currency;` — PR-0 retained it. The scout's "Settlement model drops currency / three-layer asymmetry" claim is **FALSE against `18209d86`**. No model change in PR-6.
- `validCurrency` (rules `:75-78`) is the 10-code allow-list and is already called in `validExpenseBase:563` and `validSettlementCore:93` — both base validators run on every create/update. So the floor is already enforced independently of `currencyMatchesGroup`.

---

## Locked decisions (L1–L14) — re-verify each in the Gate, do not re-litigate

| # | Decision | Why / guard |
|---|---|---|
| **L1** | Rules change = **delete** the four currency-match clauses + the orphan helper. Sites: expense-create `:584` (`&& currencyMatchesGroup(request.resource.data)`); expense-update `:659-664` (the whole diff-gated `&& (!…hasAny(['currency']) \|\| currencyMatchesGroup(…))` clause incl. its `#261` comment); event-settlement `:707-711` (`&& currencyMatchesGroup(data)` + its comment); group-settlement `:896-903` (`&& data.currency == groupData(groupId).currency` + rewrite the comment). Then delete `currencyMatchesGroup` def `:496-506` (zero callers remain). | `validCurrency(data.currency)` already enforced in `validExpenseBase:563` (both create & update; `validExpenseBase` always checks it regardless of the `enforceParticipantKeys` arg) and in `validSettlementCore:93` (both settlement scopes). Removing the equality leaves the supported-code floor intact. **Do NOT replace with a redundant `&& validCurrency(...)`** — the base already has it; a second call is dead. |
| **L2** | `group.currency` stays **create-only-immutable**. Group create `:270` `validCurrency(...)` UNCHANGED; metadata-update allow-list `:284` (currency absent) UNCHANGED. Re-cast its *role* in comments from "the constraint every money doc must match" to "the **default** currency for new expenses." | The scalar-aggregation reason for immutability is gone (everything's bucketed now), but mutating a live group's default currency has no benefit and the immutability test pins it — leave it. |
| **L3** | Settle-flow currency constraint is **client-side only** post-PR-6: both settlement rule sites relax to the `validCurrency` floor (L1). The PR-5 stepped-settle UI already offers only currencies with a **non-zero bucket** (it walks `nonZeroNetsGccFirst`), so the client constraint is real; the server just validates a supported code. | A crafted settlement in a currency with no debt is acceptable: it's append-only (B3), creates a *visible* per-currency imbalance, and is correctable by an offsetting settlement. The aggregate doc is a display cache (`allow create,update,delete: if false`, `:854-863`) and **never** feeds a write/rules decision. No server bucket-existence check. |
| **L4** | **No `Settlement` model change.** It already retains `currency` (`settlement_model.dart:34`, PR-0). | Verified; the scout was wrong. |
| **L5** | Add-expense picker **reuses** `CurrencyPickerSheet` (`lib/features/groups/widgets/currency_picker_sheet.dart`) via `CurrencyPickerSheet.show(context, selected: effectiveCurrency)` → `Future<String?>`. Cross-feature import (ledger → groups widget). **No change to the picker widget.** Title key `currencySheetTitle` is reused as-is. | Already a clean, stateless, dependency-light, GCC-first (`kSupportedCurrencies`) sheet returning an ISO code. Option-B extraction is unnecessary for PR-6. |
| **L6** | `ExpenseEditorPayload` gains `final String currency;` (required). `AddExpenseScreen._handleSubmit` drops its separate `currency` arg and reads `payload.currency` (→ `stageExpense(currency: payload.currency)`). Host `onSubmit: (payload) => _handleSubmit(payload)`. | One contract widened end-to-end; the picker's choice must reach the write or it's dead code. |
| **L7** | **Smart default** = last-used-in-event, computed by a PURE helper `defaultExpenseCurrency(List<Expense> eventExpenses, String groupDefault)`: **single-pass** over the list tracking the `!isDeleted` expense with the greatest `createdAt` (`Expense.createdAt` is a non-null `DateTime`, `expense_model.dart:38`); **on a `createdAt` tie, first-encountered wins** (iteration = the provider's Firestore list order) — do NOT use `List.sort` (Dart's sort is not guaranteed stable). Return that expense's `currency`; empty/all-deleted → `groupDefault`. Recency, not frequency (matches "last-used"). | `eventExpensesProvider` (family `EventRef`) reads through the injectable `expenseServiceProvider` (verified `:67-71`) — so it's the same offline-warm stream the ledger uses, and test overrides of `expenseServiceProvider` flow through it. The single-pass max-fold is deterministic; pin the tie rule in the unit test. |
| **L8** | **Dominant** = PURE helper `dominantEventCurrency(List<Expense> eventExpenses)` → `String?`: among `!isDeleted` expenses, the currency with the **highest count** (mode); tie-break **GCC-first** (`currencyGccRank`); returns `null` iff there are no non-deleted expenses. | Frequency for the *warning* (catches "everything's OMR, you fat-fingered USD"); recency for the *default*. The two signals differ on purpose — the issue specifies both. |
| **L9** | **Soft warning** = inline, non-blocking, non-dismissible card rendered **below the amount hero, above the description**, shown iff `!isEdit && dominant != null && effectiveCurrency != dominant`. Reactive: picking the dominant currency makes it vanish; it never blocks submit. l10n `editorCurrencyMismatch(selected, dominant)` (two placeholders). | Mirrors the soft-notice idiom (`_CardShell` tint + icon + text); not a snackbar/dialog. |
| **L10** | **Edit mode = currency immutable.** No picker shown when `mode == edit`; `effectiveCurrency = widget.currency` (= `initial.currency`); no warning. | Changing a persisted expense's currency would strand any settlement recorded against the old bucket. Rules *do* permit a valid-code change on update post-L1 (the diff-gate now only requires `validCurrency`), but the client never exposes it → parity-safe because unexercised. Documented deferred; revisit only if edit-currency is ever offered. |
| **L11** | Picker lives in `ExpenseEditorBody` as a new currency row near the amount. Define `String get effectiveCurrency => _isEdit ? widget.currency : _selectedCurrency;` and **re-point EVERY consumer of `widget.currency` in the editor to `effectiveCurrency`** — there are exactly FOUR (grep-confirmed): `:453` `showCustomSplitSheet(currency:)`, `:536` `_AmountHero(currency:)`, `:582` `_SplitPreviewCard(currency:)`, `:628` `_sanitizeAmount`'s `AppFormatters.currencyConfig[…]?.decimals`. **All four, not just the hero** (Gate R1 P1s) — `:628` drives the input-decimal clamp (picking JPY=0dp/USD=2dp in an OMR=3dp group must clamp keystrokes to the picked scale, else a typed `100.5` JPY survives `_sanitizeAmount` and `toSubunits('100.5','JPY')`→`toBigInt()` silently truncates to `100`, losing 0.5 — the JPY=1 CLAUDE.md scale landmine); `:453`/`:582` drive an **EXACT** custom split's per-person amount entry/preview → `splitDistribution` must be entered and displayed in the same currency it's persisted under. Body seeds `_selectedCurrency` from `widget.currency` in `initState`; `didUpdateWidget` re-seeds from `widget.currency` while `!_currencyManuallyPicked` (so a late-arriving smart default still lands); the picker sets `_currencyManuallyPicked = true`. In **edit** mode `effectiveCurrency == widget.currency`, so all four sites are byte-identical → no edit-mode behavior change. | `widget.currency` carries the smart default (parent, L12). `didUpdateWidget` handles the provider-late case without gating the form (keeps it snappy). The four-site sweep is the OUTBOUND-precision contract — the picked currency must scale BOTH the amount and any exact-split distribution. |
| **L12** | The **parent** (`AddExpenseScreen`) computes the default + dominant. It watches `eventExpensesProvider(EventRef(groupId,eventId))` **without gating** the form on it: `.maybeWhen(data: …, orElse: …)` → `currency: defaultExpenseCurrency(expenses, group.currency)` and a new `dominantCurrency: dominantEventCurrency(expenses)` param on the body. While expenses load: `currency = group.currency`, `dominantCurrency = null` (no warning). `EditExpenseScreen` passes `dominantCurrency: null`. | Body stays presentational; data derivation in the parent. Does NOT gate → no skeleton delay. |
| **L13** | **Rules tests** (`functions/test/firestore-rules-publish-readiness.test.ts`): the four "divergent currency is **denied**" cases (`:1686` expense-create, `:1702` expense-update, `:1763` group-settlement, `:1771` event-settlement) flip to **allowed** (rename + invert assertion). The three "matches group → allowed" cases (`:1695`, `:1735`, `:1756`) stay green. The immutability case (`:754`) stays green. **ADD** one case per scope: a **divergent-but-invalid** code (`'XYZ'`) is still **DENIED** (proves the `validCurrency` floor still bites). | The flips ARE the rules-half RED→GREEN evidence. RED = the new "allowed" assertions fail against today's rules (divergence still denied); GREEN after L1. |
| **L14** | **No Functions/oracle/aggregate/index change.** Deploy = **rules-only** (`firestore:rules`) via the ceremony (`tool/pending_deploy.sh` → `tool/deploy_firebase_backend.sh`), advancing `backend-deployed`. "No real users → deploy freely" (no client-compat ordering). **Closes #382.** | `recomputeNet`/`balanceAggregator` already bucket per-currency and read settlement per-doc currency (PRs 2–3, deployed). Grep-confirm no `functions/src` change in the diff before deploying. |

---

## Verified seam contracts (re-grepped against `18209d86`; re-locate by symbol if lines drift)

**Rules — the four clauses to delete (all in `security/firestore.rules`):**
- `:504-506` `function currencyMatchesGroup(d) { return d.currency == groupData(groupId).currency; }` — **delete** (and its `:496-503` comment).
- `:584` inside `validExpenseCreate()`: `&& currencyMatchesGroup(request.resource.data)` — **delete the line**.
- `:659-664` inside `validExpenseUpdate()`: the `#261` comment + `&& (!request.resource.data.diff(resource.data).affectedKeys().hasAny(['currency']) || currencyMatchesGroup(request.resource.data))` — **delete the clause**. (Currency stays in the `hasOnly` allow-list `:642` and in `affectsExpenseAllocation` `:617`; `validExpenseBase:563` keeps the `validCurrency` floor.)
- `:711` inside `validEventSettlementBase()`: `&& currencyMatchesGroup(data)` — **delete the line** (and rewrite its `:707-710` comment).
- `:903` inside `validGroupSettlementBase()`: `&& data.currency == groupData(groupId).currency` — **delete the line** (and rewrite its `:896-902` comment). `validSettlementCore(data)` `:904` keeps the `validCurrency` floor.
- UNCHANGED: `validCurrency:75-78`, group-create `:270`, metadata-update allow-list `:284` (immutability), `validExpenseBase:563`, `validSettlementCore:93`.

**Client — `expense_editor_body.dart`:**
- `ExpenseEditorPayload` `:52-76` — add `final String currency;` (required ctor param). All payload constructions updated.
- `ExpenseEditorBody` `:83-120` — gains `final String? dominantCurrency;` (optional, default null). `currency` param keeps its meaning but now carries the smart default in add mode.
- `_ExpenseEditorBodyState` `:122+` — add `late String _selectedCurrency;` (seed `= widget.currency` in `initState` both branches) + `bool _currencyManuallyPicked = false;` + `didUpdateWidget` re-seed. `effectiveCurrency` getter = `_isEdit ? widget.currency : _selectedCurrency`.
- **Re-point ALL FOUR `widget.currency` consumers to `effectiveCurrency`** (grep-confirmed exhaustive): `:453` `showCustomSplitSheet(currency:)`, `:536` `_AmountHero(currency:)`, `:582` `_SplitPreviewCard(currency:)`, `:628` `_sanitizeAmount` (`AppFormatters.currencyConfig[effectiveCurrency]?.decimals ?? 3`). The bare `currency: currency` at `:1347` is `_SplitPreviewCard`'s own param forwarded to a child — it inherits `effectiveCurrency` once `:582` passes it, no separate edit. Add `String get effectiveCurrency`.
- Payload build (on submit, ~`:259-272`) — add `currency: effectiveCurrency`.
- New currency row widget + new soft-warning card; gated on `!_isEdit` and on the warning condition respectively.

**Client — `add_expense_screen.dart`:**
- `_handleSubmit(ExpenseEditorPayload payload, String currency)` `:41-44` → `_handleSubmit(ExpenseEditorPayload payload)`; the `stageExpense(currency: …)` `:70` reads `payload.currency`; comment `:67-69` rewritten (no longer "must match the group").
- `build` `:144-153` — watch `eventExpensesProvider(EventRef(groupId: …, eventId: …))` (`.maybeWhen`/`orElse`); pass `currency: defaultExpenseCurrency(expenses, group.currency)`, `dominantCurrency: dominantEventCurrency(expenses)`, `onSubmit: (payload) => _handleSubmit(payload)`.

**Client — `edit_expense_screen.dart`:** host already passes `currency: initial.currency`; add `dominantCurrency: null` (or omit — default null). Picker is hidden by the body's `!_isEdit` gate; **no behavior change**. `_save` `:120-127` keeps `currency: original.currency`.

**Helpers (new) — `lib/features/ledger/providers/expense_currency_default.dart`** (small pure file; or co-located in `expense_provider.dart` — pick the smaller-diff option; spec assumes a new file):
- `String defaultExpenseCurrency(List<Expense> eventExpenses, String groupDefault)` (L7).
- `String? dominantEventCurrency(List<Expense> eventExpenses)` (L8, GCC-first tie-break via `currencyGccRank` from `supported_currencies.dart`).

**Picker — `currency_picker_sheet.dart`:** `CurrencyPickerSheet.show(context, selected: String) → Future<String?>` — reuse verbatim.

---

## 7 verification principles — report (run again in the Gate)

1. **Callsite classification.** New OUTBOUND path: picker → `_selectedCurrency` → `payload.currency` → `stageExpense(currency:)` → Firestore `currency` field (scaled by `MoneySerializer.toSubunits(amount, currency)`). The picker returns a `kSupportedCurrencies` code (∈ `validCurrency`), so the OUTBOUND value is always a supported code — no display-formatted string reaches the write. Smart-default/dominant helpers are INBOUND (display/default only). The amount-hero currency is INBOUND (label).
2. **Concrete claims vs code.** All rule line numbers, `validCurrency`/base-validator placement, `ExpenseEditorPayload` shape, `eventExpensesProvider` service injection, `CurrencyPickerSheet.show` signature, and `settlement_model.dart:34` currency retention — **re-grepped against `18209d86`** (see seam contracts). The scout's `settlement_model` "drops currency" claim was refuted by code.
3. **One read-path per write-path.** The new write field is `expense.currency` with a per-expense value (was always group.currency). Readers after the change: `BalanceCalculator.calculateBalances` (buckets by `expense.currency` — already, PR-1), `MoneySerializer.fromSubunits(amountFils, currency)`, the server `recomputeNet`/`balanceAggregator` (bucket by per-doc currency — already, PRs 2–3), per-currency display surfaces (PR-1/5). Every reader already keys on per-doc currency; nothing assumes it equals `group.currency`. Settlement write-path currency → `recomputeNet` settlement fold (per-doc currency, already) + stepped-settle UI (offers non-zero buckets only).
4. **Fields from the type.** `ExpenseEditorPayload` enumerated (`:52-76`): amount, description, scope, categoryId, payerParticipantId, customSplitParticipants, splitMode, splitDistribution → **+ currency**. No other field of the payload is currency-dependent. `Expense.currency` already exists (`:67/:246`) — not added, just now driven by the picker.
5. **Data contracts at moved seams.** `onSubmit(ExpenseEditorPayload)` unchanged in arity; payload gains a required `currency`. `_handleSubmit` loses its 2nd positional arg. `ExpenseEditorBody` gains optional `dominantCurrency`. `defaultExpenseCurrency(List<Expense>, String) → String`; `dominantEventCurrency(List<Expense>) → String?`. l10n `editorCurrencyMismatch(String selected, String dominant)`.
6. **Arithmetic decomposition.** None introduced — PR-6 adds no aggregation. The only money touch is `MoneySerializer.toSubunits(amount, payload.currency)` at the write (existing call, now with a per-expense currency). Scale must be the picked currency's (OMR/KWD/BHD=1000, JPY=1, rest=100) — guaranteed because the same `currency` scales `amountFils` and is stored, so read-back `fromSubunits` uses the same scale.
7. **Adversarial pass (orthogonal axis = identity/settlement).** A USD expense created in an OMR group → `calculateBalances` yields an OMR bucket and a USD bucket. Settle-up (PR-5 stepped) walks both; a USD settlement is now **rules-allowed** (L3) and folds into the USD bucket server-side (`recomputeNet`, already). `deleteGroup`/`leaveGroup`/`removeMember` already require **every** bucket to net zero, so the new USD bucket correctly blocks deletion until settled. No same-axis (expense-only) re-proof.

**Open risks the Gate must probe:** (a) does deleting the `:663-664` diff-gate clause unintentionally let an *edit* change currency to a divergent code at the rules level? — yes, by design (L10), client doesn't expose it; confirm no parity test asserts the old denial. (b) the existing `add_expense_currency_test.dart` boots without an `eventExpensesProvider` override — confirm it still resolves (empty via the overridden `expenseServiceProvider`) so the smart default = group.currency keeps those 3 assertions green. (c) confirm no OTHER lib/test caller of `currencyMatchesGroup` exists (rules grep) before deleting the helper.

---

## Tasks

### Task 1: Rules tests RED — divergent currency must be ALLOWED (and invalid still DENIED)

**Files:** Modify `functions/test/firestore-rules-publish-readiness.test.ts`.

**Step 1 — flip the four denial cases + add invalid-code cases.** Rewrite `:1686` (expense-create divergent → **allowed**), `:1702` (expense-update to divergent code → **allowed**), `:1763` (group-settlement divergent → **allowed**), `:1771` (event-settlement divergent → **allowed**) to `assertSucceeds`. Keep `:1695/:1735/:1756` (match-group → allowed) and `:754` (currency immutable) unchanged. ADD three cases: expense-create / event-settlement-create / group-settlement-create with `currency:'XYZ'` → `assertFails` (validCurrency floor). Use the existing helpers/fixtures in the file; a divergent supported code = e.g. group is `OMR`, write `USD`.

**Step 2 — run, expect RED.** `cd functions && RIHLA_FIREBASE_EMULATOR_TEST_COMMAND=… npm run test:emulator` (the emulator runner; note `-- <file>` is NOT forwarded — scope via the env override per the #473 gotcha, or run the whole suite). Expected: the four flipped cases FAIL (today's rules still deny divergence); the `XYZ` cases already PASS (deny). Capture the failing output — it's the rules RED evidence.

**Step 3 — commit** the test changes. Message: `test(rules): divergent-currency expenses/settlements allowed, invalid still denied (#382 PR-6)` + body `Refs #382`.

### Task 2: Rules GREEN — delete the four currency-match clauses + the orphan helper

**Files:** Modify `security/firestore.rules`.

**Step 1.** Per L1/seam contracts: delete the line at `:584`; delete the `:659-664` clause; delete the `:711` line + rewrite `:707-710` comment; delete the `:903` line + rewrite `:896-902` comment; delete `currencyMatchesGroup` `:504-506` + its `:496-503` comment. Rewrite the group-create/immutability comments (`:278-281`) to re-cast `group.currency` as the *default* (L2). Grep-confirm zero remaining `currencyMatchesGroup` references.

**Step 2 — run the rules suite, expect GREEN.** Re-run Task-1's command. All flipped cases now PASS; `XYZ` cases still DENY; match-group + immutability cases unchanged.

**Step 3 — commit.** `fix(rules): per-expense currency — relax currencyMatchesGroup to the validCurrency floor (#382 PR-6)` + `Refs #382`.

### Task 3: Smart-default + dominant pure helpers (unit RED→GREEN)

**Files:** Create `lib/features/ledger/providers/expense_currency_default.dart`; create `test/unit/expense_currency_default_test.dart`.

**Step 1 — RED test.** Cover: empty → groupDefault; single OMR → OMR default, dominant OMR; `[OMR@t1, OMR@t2, AED@t3]` (createdAt asc) → default `AED` (most-recent), dominant `OMR` (count 2>1); soft-deleted excluded from both; tie count `[OMR, AED]` → dominant GCC-first (`OMR` ranks before `AED`); dominant null on all-deleted/empty. Reference `defaultExpenseCurrency` + `dominantEventCurrency` (don't exist yet → RED).

**Step 2 — run RED** (`flutter test test/unit/expense_currency_default_test.dart`), confirm "method not found".

**Step 3 — implement** both pure helpers (L7/L8); import `currencyGccRank` from `core/constants/supported_currencies.dart`.

**Step 4 — GREEN** + `flutter analyze`. **Step 5 — commit** `feat(ledger): per-expense currency default + dominant helpers (#382 PR-6)` + `Refs #382`.

### Task 4: Payload currency field + picker wiring in the editor (widget RED→GREEN)

**Files:** Modify `lib/features/ledger/widgets/expense_editor_body.dart`; modify/create `test/features/ledger/add_expense_currency_test.dart` (extend) or a new `add_expense_picker_test.dart`.

**Step 1 — RED widget test.** Three cases in an **OMR** group, empty event: (a) tap the new currency row (`LedgerKeys.expenseCurrencyField` — add the key), pick "US dollar", assert the amount-hero label flips to `AMOUNT · USD` and (on Add, via `FakeFirebaseFirestore`) the written `currency == 'USD'` + `amountFils == 1234` for input `12.34` (proves the *client* now creates a divergent-currency expense). (b) **JPY scale-clamp guard (Gate R1 P1):** pick "Japanese yen", enter `100.5`, assert the field renders `100` (no `.5`) and the persisted `amountFils == 100` — proves `_sanitizeAmount` uses `effectiveCurrency` (0dp), not the stale OMR 3dp that would let `100.5` survive and `toBigInt()`-truncate. (c) **exact-split currency guard (Gate R1 P1):** pick USD, switch to an EXACT custom split, assert the custom-split sheet / preview labels render under USD (not OMR). RED: no currency row → finders fail; before the four-site sweep, (b)/(c) fail on the OMR label/precision.

**Step 2 — run RED.** **Step 3 — implement** L6/L11: `ExpenseEditorPayload.currency`; `_selectedCurrency`+`_currencyManuallyPicked`+`didUpdateWidget`+`effectiveCurrency` getter; the currency row (reusing `CurrencyPickerSheet.show`), gated `!_isEdit`; **re-point all four `widget.currency` sites (`:453/:536/:582/:628`) to `effectiveCurrency`**; add `payload.currency: effectiveCurrency`. **Step 4 — GREEN** + analyze. **Step 5 — commit** `feat(ledger): per-expense currency picker in the add-expense editor (#382 PR-6)` + `Refs #382`.

### Task 5: Parent wiring — smart default + dominant + payload.currency write

**Files:** Modify `lib/features/ledger/screens/add_expense_screen.dart`; modify `lib/features/ledger/screens/edit_expense_screen.dart`.

**Step 1 — RED test.** New widget test: an OMR group whose event already has a **USD** expense (seed the fake / override `eventExpensesProvider`) → opening add-expense **defaults** the hero to `AMOUNT · USD` (last-used) with **no** warning if USD is also dominant; and a separate fixture `[OMR×2, USD×1]` → default USD **and** the soft warning visible. RED: parent still hardcodes group.currency → hero shows OMR.

**Step 2 — run RED.** **Step 3 — implement** L12: watch `eventExpensesProvider`, `.maybeWhen` default+dominant, pass to body, `_handleSubmit(payload)` reads `payload.currency`. Edit screen: pass `dominantCurrency: null`. **Step 4 — GREEN**; re-run the existing 3 `add_expense_currency_test.dart` cases (must stay green — empty event → default group.currency). **Step 5 — commit** `feat(ledger): smart per-expense currency default from event history (#382 PR-6)` + `Refs #382`.

### Task 6: Soft fat-finger warning + l10n (widget RED→GREEN)

**Files:** Modify `expense_editor_body.dart`; `lib/l10n/app_en.arb` + `app_ar.arb`; regen `lib/l10n/generated/`.

**Step 1 — RED test.** Event `[OMR×2]`, user picks `USD` → assert the warning card (`LedgerKeys.expenseCurrencyWarning`) is found with text naming USD and OMR; then pick `OMR` → assert it's gone; edit mode → never shown. RED: no warning widget.

**Step 2 — run RED.** **Step 3 — implement** L9: inline `_CardShell`-style card below the amount hero, gated `!_isEdit && widget.dominantCurrency != null && effectiveCurrency != widget.dominantCurrency`; add `editorCurrencyMismatch` (2 placeholders, EN with `@`-metadata incl. `#382`, AR value-only); `flutter gen-l10n`; commit generated files. **Step 4 — GREEN** + analyze + `dart run tool/check_arb_completeness.dart`. **Step 5 — commit** `feat(ledger): soft warning when an expense currency differs from the event's dominant (#382 PR-6)` + `Refs #382`.

### Task 7: Full sweep + grep-proof

**Files:** none (verification only).

- `flutter analyze` → clean. `flutter test` → all green (incl. the existing add-expense + ledger + group-detail suites). `cd functions && npm run test:emulator` → rules suite green.
- Grep-proof: `grep -rn currencyMatchesGroup security/ functions/ lib/ test/` → only test *names*/comments may mention currency, but the **rule function and its calls are gone** (zero in `security/firestore.rules`).
- Confirm **no `functions/src/**` change** in the branch diff (`git diff --name-only origin/main...HEAD | grep '^functions/src'` → empty) → deploy is rules-only.
- Verify every commit body carries `Refs #382`; the **final** PR will carry `Closes #382` (last rung) — but commit bodies stay `Refs` (the PR body / squash message closes it). Do NOT create the PR — just report.

---

## After the workflow (orchestrator, not a task)

1. Open PR with `Spec:` line → this file, body `Closes #382` (last rung — verify no residual #382 box first), paste the rules RED (Task 1) + the four MONEY-CREATABLE widget assertions.
2. `/automerge` — Gate-category (`firestore.rules` + `expense_provider`-adjacent + `models`-adjacent): fresh Opus diff review + refuter.
3. On merge → **deploy ceremony** (rules-only, L14): `tool/pending_deploy.sh` → `RIHLA_CONFIRM_FIREBASE_DEPLOY=yes RIHLA_CONFIRM_APP_CHECK_READY=yes RIHLA_FIREBASE_DEPLOY_APPROVED_SHA=<merge sha> bash tool/deploy_firebase_backend.sh rihla-safar` (hardcode the SHA — `$(git rev-parse HEAD)` line-wraps; run from the clean on-`main` checkout) → advances `backend-deployed` → record in `docs/DEPLOY-LEDGER.md`.
4. Update memory: #382 epic CLOSED.
