# Arabic Localization PR2b — Ledger Surface

**Authored:** 2026-05-18
**Branch:** `feat/l10n-pr2b-ledger` (off `main` @ edfd385, PR2a merged via #35)
**Predecessors:** PR1 (#34) infrastructure, PR2a (#35) Settings + Profile + toggle unlock
**Successors:** PR3 (Groups/Events/Home/Activity), PR4 (Polish)

---

## Scope

Translate the entire Ledger surface to Arabic, including the shared settle-up widget cluster that lives under `lib/features/groups/widgets/` but is consumed by the Ledger route. User-visible delta: from Profile → Language → "العربية", Settings + Profile + the entire Ledger feature (list, expense editor, custom split, settle-up) all render in Arabic. Groups/Events/Home/Activity stay English until PR3.

### Surface (verified file-by-file, not from the PR1 sketch)

**4 screens:**
- `lib/features/ledger/screens/ledger_screen.dart` (765 LOC, ~18 strings)
- `lib/features/ledger/screens/settle_up_screen.dart` (376 LOC, ~12 strings)
- `lib/features/ledger/screens/add_expense_screen.dart` (109 LOC, thin shell)
- `lib/features/ledger/screens/edit_expense_screen.dart` (194 LOC, 11 strings)

**20 ledger widgets:**
- `widgets/expense_editor_body.dart` (1567 LOC, ~42 strings — imported by both add/edit screens; the real form)
- `widgets/custom_split_sheet.dart` (~1000 LOC, ~14 strings — launched from editor at L316)
- `widgets/category_picker_sheet.dart`, `widgets/ledger_search_sheet.dart`, `widgets/ledger_hero_block.dart`, `widgets/ledger_day_card.dart`, `widgets/split_scope_selector.dart`, `widgets/expense_success_dialog.dart`, `widgets/expense_card.dart`, `widgets/settlement_summary_card.dart`, `widgets/receipt_picker_section.dart`, `widgets/settlement_tile.dart`, `widgets/settlement_row.dart`, `widgets/amount_input_section.dart`, `widgets/recent_expenses_section.dart`, `widgets/recorded_settlements_section.dart`, `widgets/category_selection_step.dart`, `widgets/ledger_sticky_cta.dart`, `widgets/ledger_roster_strip.dart`, `widgets/ledger_category_strip.dart`

**5 shared settle-up widgets under `lib/features/groups/widgets/`** (acknowledged side effect: `lib/features/groups/screens/group_settle_up_screen.dart` will render Arabic earlier than rest of Groups surface):
- `settle_up_page_body.dart` (547 LOC, 15 strings) — imported by both `ledger/settle_up_screen.dart` and `groups/group_settle_up_screen.dart`
- `record_payment_sheet.dart` (571 LOC, 11 strings) — same two consumers
- `group_settlement_tile.dart` (356 LOC, 1 string)
- `all_settled_state.dart` (57 LOC, 2 strings)
- `group_settlement_summary.dart` (99 LOC, 0 strings — RTL audit only)

**2 utils:**
- `lib/features/ledger/utils/ledger_timeline.dart` — `Today`/`Yesterday` labels via ARB; month abbreviations via `intl` `DateFormat.MMM(localeTag)`; range separator via ARB
- `lib/features/ledger/utils/ledger_categories.dart` — substring-match → exact-match refactor in `ledgerCategoryBucket`; `ledgerCategoryName(int bucket)` gains `AppLocalizations` param

**1 new util:** `lib/features/ledger/utils/localized_category_name.dart`

**Totals:** ~33 implementation files. ~126 new ARB keys (combined en + ar). ARB total after PR2b: ~235.

**File-count math:** 4 screens + 20 ledger widgets + 5 groups widgets + 2 utils + 1 new util + 1 helper at `lib/core/utils/` (see Helpers section) = ~33.

---

## Decisions (locked 2026-05-18)

| # | Decision | Rationale |
|---|---|---|
| Q1 | One bundled PR (full Ledger), not split into PR2b-read + PR2c-write | Editor body and `custom_split_sheet.dart` are tightly coupled — split mid-flow means a half-Arabic editor. Volume ≈ PR2a. |
| Q2 | Strict defer of 4 pre-existing hardcoded-OMR money bugs | "Smaller change + follow-up" per Operating Contract. Codex gate is anchored on translation, not money-math. Bugs filed as follow-ups (see end). |
| Q3 | Default category names: translate at display, store English | Zero data migration. `ledgerCategoryBucket(expense.categoryName)` keeps English input. Switching languages stays consistent across users + sessions. |
| Q4 | Unify the two category-naming systems in PR2b | `ledger_categories.dart` substring-bucketing breaks for Arabic-entered custom names. Refactor to exact-match against seed names (same int return; internal logic only). Custom-CRUD is dead, so every expense has a seed name anyway. |
| Q5 | Write fresh Arabic golden-path integration test in PR2b, ledger-focused | Test PR1 promised (Task 11) and PR2a referenced does not exist in `test/integration/`. Closing the debt with a narrow ledger walk. |
| Q6 | Reuse `splitModeDisplayName` from PR2a; accept the 'Equally' → 'Equal' wording change in `custom_split_sheet.dart` | PR2a established 'Equal' as canonical. Shorter, chip-friendly. YAGNI on a separate `customSplitModeEqually` key. |
| Q7 | New `expenseScopeDisplayName(scope, l10n)` helper at `lib/core/utils/`; keys under `editor*` prefix | Mirror of `splitModeDisplayName` shape. `ExpenseScope` is editor-specific, not a `common*` cross-screen concern. |
| Q8 | `localizedCategoryName({String? id, String? fallbackName, required AppLocalizations l10n})` | id-keyed switch (matches Q4 unify direction). `ExpenseModel.categoryId` already exists at `expense_model.dart:39` — id is first-class. Fallback name covers legacy/custom data. |
| Q9 | Verb-interpolation policy: separate ARB keys per verb, no runtime composition | `expense_editor_body.dart:201` `'Failed to $verb expense: $e'` splits into `editorFailedToAddExpense` / `editorFailedToUpdateExpense` with `{error}` placeholder. Sets codebase-wide convention. |
| Q10 | `currencyDisplayName` stays in PR2a's picker boundary; not pulled into settle-up | Settle-up renders currency codes, not display names. Pulling the helper in needlessly crosses the hardcoded-OMR bug boundary. |

---

## Non-goals (deferred, gate-defensible)

- **4 pre-existing hardcoded-OMR money bugs** — `r_amount.dart:84`, `settle_up_screen.dart:221`, `ledger_hero_block.dart:262`, `expense_editor_body.dart:111`. Filed as follow-ups.
- **`transaction_model.dart` `'Expense'` (L37) and `'Settlement to Recipient'` (L49) fallback strings** — `Transaction.description` has zero consumers (verified: only set by `Transaction.fromExpense`/`fromSettlement` factories at `lib/features/ledger/providers/ledger_provider.dart:37-38`; no read sites anywhere in `lib/`). Dead code. Field cleanup is a separate follow-up.
- **Splitting `expense_editor_body.dart`** — 1567 LOC is 2× the 800 ceiling per coding style, but mixing refactor + translation is bad scope. Follow-up.
- **Direct `toStringAsFixed` callsites** in `expense_card.dart`, `ledger_roster_strip.dart`, `settlement_row.dart`, `ledger_hero_block.dart` — work as-is under Flutter BiDi. Leave.
- **Onboarding, Groups, Events, Home, Activity** — PR3.
- **Brand strings** (`'Rihla'`, `'RIHLA · BUILT FOR JOURNEYS'`) — per PR2a Q5.
- **Arabic-Indic digits** (`٠١٢٣`) — per PR2a Q3, Latin digits stay.

---

## Codex gate — REQUIRED, runs BEFORE Wave 0

Per Operating Contract: mandatory because PR2b touches money-math UI (RAmount surface in settle-up flow + balance displays). Spec-level review on this design doc + the implementation plan, NOT the implementation diff. Iterate until no [P1] findings; ~2 rounds typical, 3 means scope was wrong.

### Gate's anchor (state explicitly so the gate is bounded)

1. No `BalanceCalculator` line changes (`lib/features/ledger/providers/expense_provider.dart` untouched).
2. No `MoneySerializer` boundary crossed; Firestore serialization unchanged.
3. No `RAmount` line changes. Currency code stays ISO 4217. PR2b does NOT fix the OMR-only 3dp bug at `r_amount.dart:84`.
4. `ledgerCategoryBucket` substring → exact-match refactor preserves bucketing for every existing seed name. Extended unit tests cover this.
5. ARB plural for `PERSON/PEOPLE` (`ledger_screen.dart:426`) preserves count semantics. No off-by-one.
6. Verb-interpolation split preserves error-context — `{error}` placeholder still surfaces `$e`.
7. `localizedCategoryName` handles id-known (6 seeds) + id-unknown + null-id paths. No silent empty-string returns.
8. Shared-widget side effect on `group_settle_up_screen.dart` is acknowledged, not stealth scope creep.
9. No `app_router.dart` / route tree / deep-link changes. No `firestore.rules` changes. No Cloud Function changes. No `lib/firebase_options.dart` changes.

---

## ARB key inventory

### Convention (extending PR2a's precedent)

Screen/widget-prefixed; `common*` reserved for **true cross-screen actions/verbs only** (not domain phrases).

### Prefix buckets

| Prefix | Scope | Est. new keys |
|---|---|---|
| `ledger*` | `ledger_screen.dart` + small ledger widgets (day card, hero block, search sheet, sticky CTA, roster strip, category strip, settlement summary/row/tile, recent/recorded sections) | ~22 |
| `editor*` | `expense_editor_body.dart` form labels, dialog copy, scope titles, snack errors, hint/label text. Includes `editorScopeGlobal/SubGroup/Custom/Personal` | ~42 |
| `customSplit*` | `custom_split_sheet.dart` (sheet chrome, totals — SplitMode labels reuse PR2a's `splitMode*` keys) | ~10 |
| `categoryPicker*` | `category_picker_sheet.dart` chrome (title, search, no-results) | ~5 |
| `category*` | 6 default-seed names keyed by `ExpenseCategory.id`: `categoryFood`, `categoryTransport`, `categoryAccommodation`, `categoryActivities`, `categoryShopping`, `categoryOther` | 6 |
| `settleUp*` | `settle_up_screen.dart` + 5 shared groups widgets (page body, record payment sheet, settlement tile, all-settled state) | ~25 |
| `expenseSuccess*` | `expense_success_dialog.dart` | ~6 |
| `timeline*` | `timelineToday`, `timelineYesterday`, range separator. Month abbreviations via `intl` `DateFormat.MMM(localeTag)` — NOT ARB | ~3 |
| `common*` extensions | True cross-screen actions only: `commonApply`, `commonRetry`, `commonBack`, `commonClose`, `commonGoHome`. (`commonCancel`, `commonOK`, `commonSave`, `commonDelete` already exist from PR2a — reuse, not new.) | ~5 new |

**Estimated PR2b additions: ~126 keys.** Total after PR2b: ~235.

### Plural — first ARB plural in the codebase

`ledger_screen.dart:426` `'${count == 1 ? 'PERSON' : 'PEOPLE'}'`:

```json
"ledgerPeopleCount": "{count, plural, =1{PERSON} other{PEOPLE}}",
"@ledgerPeopleCount": {
  "placeholders": { "count": { "type": "int" } }
}
```

Arabic plural uses CLDR's 6 forms (`zero/one/two/few/many/other`). `app_ar.arb` supplies all needed forms or explicitly `other`-collapses. Codegen surfaces gaps.

### Verb-interpolation policy

`expense_editor_body.dart:201` `'Failed to $verb expense: $e'` splits into:

```json
"editorFailedToAddExpense": "Failed to add expense: {error}",
"editorFailedToUpdateExpense": "Failed to update expense: {error}",
"@editorFailedToAddExpense": { "placeholders": { "error": { "type": "String" } } },
"@editorFailedToUpdateExpense": { "placeholders": { "error": { "type": "String" } } }
```

Callsite picks the key; never composes the verb at runtime. **Codebase-wide convention.**

---

## Helpers — reuse vs new

**Reuse (unchanged, from PR2a):**
- `splitModeDisplayName(SplitMode mode, AppLocalizations l10n)` at `lib/core/utils/split_mode_display_name.dart` — covers `SplitMode.equally/shares/exact/percent`. Used at `expense_editor_body.dart:1144-1146` + `custom_split_sheet.dart:505-508`. Note: returns `'Equal'`, not `'Equally'` — Q6 accepts the wording change.
- `currencyDisplayName(String code, AppLocalizations l10n)` at `lib/core/utils/currency_display_name.dart` — **stays in PR2a picker boundary**. Not pulled into settle-up (Q10).

**New in PR2b:**

`lib/core/utils/expense_scope_display_name.dart`:
```dart
String expenseScopeDisplayName(ExpenseScope scope, AppLocalizations l10n) {
  return switch (scope) {
    ExpenseScope.global   => l10n.editorScopeGlobal,
    ExpenseScope.subGroup => l10n.editorScopeSubGroup,
    ExpenseScope.custom   => l10n.editorScopeCustom,
    ExpenseScope.personal => l10n.editorScopePersonal,
  };
}
```
Used at `expense_editor_body.dart:1058-1061` and `split_scope_selector.dart`.

`lib/features/ledger/utils/localized_category_name.dart`:
```dart
// Pseudocode signature, not final
String localizedCategoryName({
  String? id,
  String? fallbackName,
  required AppLocalizations l10n,
}) {
  switch (id) {
    case 'food':          return l10n.categoryFood;
    case 'transport':     return l10n.categoryTransport;
    case 'accommodation': return l10n.categoryAccommodation;
    case 'activities':    return l10n.categoryActivities;
    case 'shopping':      return l10n.categoryShopping;
    case 'other':         return l10n.categoryOther;
  }
  return (fallbackName != null && fallbackName.isNotEmpty)
      ? fallbackName     // legacy/custom names render as-typed
      : l10n.categoryOther;
}
```
Callsites:
- Expense object available → `id: expense.categoryId, fallbackName: expense.categoryName`
- `ExpenseCategory` object (picker sheet) → `id: category.id`
- Filter strip / day-card chip → resolved via refactored `ledgerCategoryName(bucket, l10n)` which switches internally on bucket index

**Refactored in PR2b:**

`lib/features/ledger/utils/ledger_categories.dart`:
- `ledgerCategoryBucket(String? name) -> int` — switch from substring-matching to **case-insensitive trim exact-match** against the 6 seed names. Same int return type; internal logic only. Unknown names → bucket 5 ("Other").
- `ledgerCategoryName(int bucket) -> String` becomes `ledgerCategoryName(int bucket, AppLocalizations l10n) -> String` — returns `l10n.categoryFood / Transport / …` keyed by bucket index.

---

## Implementation waves

Each wave is one (or two) atomic commits. ARB completeness lint stays green after every commit. `flutter analyze` clean after every wave; relevant tests pass.

### Wave 0 — Foundation (no UI changes)

- Add all ~126 new en + ar ARB keys in one bilingual commit. Lint green; UI still English everywhere (keys defined, not consumed).
- Add `lib/core/utils/expense_scope_display_name.dart` + unit test.
- Add `lib/features/ledger/utils/localized_category_name.dart` + unit test (covers all 6 known ids, null id, unknown id, empty fallback, populated fallback).
- Refactor `lib/features/ledger/utils/ledger_categories.dart`: substring → exact-match in `ledgerCategoryBucket`; add `AppLocalizations` param to `ledgerCategoryName`; update existing `ledger_categories_test.dart` for new contract + add seed-name + case/whitespace variant cases (R3 mitigation).

### Wave 1 — Small ledger widgets (low blast radius)

- `settlement_row.dart`, `settlement_tile.dart` (+ RTL: `Positioned(left: 20)` → `PositionedDirectional(start: 20)` at L97).
- `settlement_summary_card.dart`, `recorded_settlements_section.dart`, `recent_expenses_section.dart`.
- `ledger_sticky_cta.dart`, `ledger_roster_strip.dart`, `category_selection_step.dart`.
- `amount_input_section.dart`, `receipt_picker_section.dart`.

### Wave 2 — Hero/list visual widgets

- `ledger_hero_block.dart` (+ RTL: `EdgeInsets.only(right: 3)` → `EdgeInsetsDirectional.only(end: 3)` at L136).
- `expense_card.dart`, `ledger_day_card.dart`.
- `ledger_category_strip.dart` (consumes refactored `ledgerCategoryName(bucket, l10n)`).
- `expense_success_dialog.dart` (+ RTL: `Alignment.topRight` → `AlignmentDirectional.topEnd` at L36).

### Wave 3 — Sheets

- `category_picker_sheet.dart` (+ RTL fix at L70; consumes `localizedCategoryName`).
- `ledger_search_sheet.dart`.
- `custom_split_sheet.dart` (consumes `splitModeDisplayName`; wording shift 'Equally' → 'Equal' accepted per Q6).

### Wave 4 — Editor cluster (the big one)

- `expense_editor_body.dart` (+ 2 RTL fixes at L512/L529; verb-interpolation refactor at L201; consumes `expenseScopeDisplayName` + `splitModeDisplayName` + `localizedCategoryName`). One atomic commit.
- `add_expense_screen.dart`, `edit_expense_screen.dart` (thin shells).
- `split_scope_selector.dart` (consumes `expenseScopeDisplayName`).
- Post-wave grep audit (R1 mitigation): `grep -nE "'[A-Z][a-zA-Z][a-zA-Z ]{2,}'" lib/features/ledger/widgets/expense_editor_body.dart` should only surface debug/brand/sentinel strings.

### Wave 5 — Settle-up cluster

- `settle_up_screen.dart` (drops `const` from SnackBars; verify `prefer_const_constructors` clean via `flutter analyze`).
- `settle_up_page_body.dart` (+ RTL fix at L393).
- `record_payment_sheet.dart` (+ RTL fix at L469).
- `group_settlement_tile.dart`, `all_settled_state.dart`, `group_settlement_summary.dart` (RTL audit, no string changes for summary).

### Wave 6 — Top-level ledger screen + timeline utils

- `ledger_timeline.dart`: `Today` and `Yesterday` via ARB; month abbreviations via `intl` `DateFormat.MMM(locale.toLanguageTag())`; range separator via ARB.
- `ledger_screen.dart` (+ ARB plural `ledgerPeopleCount` at L426).

### Wave 7 — Tests + gate clearance

- Update widget tests per surface — minimum: each translated screen/widget renders at least one expected Arabic string when booted with `languageCode: 'ar'`.
- New integration test `test/integration/locale_arabic_ledger_test.dart`: boots in Arabic, walks Home → group → event → ledger (assert Arabic plural visible) → tap settle-up → assert Arabic settlement form visible. ~80–120 LOC. Uses `tester.runAsync` for GoogleFonts (R7 mitigation per `feedback_googlefonts_runasync`).
- `flutter analyze` clean.
- `flutter test` full suite green.
- `dart run tool/check_arb_completeness.dart` exit 0.

### Commit cadence

One commit per wave. Conventional: `feat(l10n): PR2b/wave-N — <scope>`. 8 commits total (Wave 0–7). PR title: `feat(l10n): PR2b — Ledger surface Arabic translation`.

---

## Test strategy

| Layer | Where | What |
|---|---|---|
| Unit | `test/unit/` | `expense_scope_display_name_test.dart`, `localized_category_name_test.dart`, extended `ledger_categories_test.dart` (exact-match refactor + ARB-returning `ledgerCategoryName`) |
| Widget | `test/features/ledger/`, `test/features/groups/` | Per translated surface, Arabic harness asserts ≥1 Arabic string. Uses `pumpRihlaApp` with `languageCode: 'ar'` override per `feedback_pump_rihla_app_contracts` |
| Integration | `test/integration/locale_arabic_ledger_test.dart` | Fresh file. Boots Arabic; walks ledger flows; uses `tester.runAsync` for fonts |
| Lint | `tool/check_arb_completeness.dart` (CI) | Already wired in `readiness_check.yml:58`. Stays green every commit |
| Money | `test/integration/firebase_money_roundtrip_test.dart` | Existing test — must stay green; proves l10n changes don't touch persistence |

---

## Risks

| # | Risk | Where | Mitigation |
|---|---|---|---|
| R1 | Missing strings in deep branches of 1567-LOC editor body | `expense_editor_body.dart` | Post-wave-4 grep audit |
| R2 | Widget tests asserting `'Equally'` break when helper returns `'Equal'` | `custom_split_sheet.dart` tests | Pre-flight grep `test/` for `'Equally'\|'Shares'\|'Exact'\|'Percent'` before Wave 3 |
| R3 | `ledgerCategoryBucket` exact-match misbuckets legacy data with case/whitespace variants | `ledger_categories.dart` refactor | Case-insensitive `.trim().toLowerCase()` in matcher; widen unit tests with variant inputs |
| R4 | First ARB plural — missing Arabic CLDR forms | `ledger_screen.dart:426` plural | Codegen surfaces gaps; verify `app_ar.arb` supplies all needed forms or `other`-collapses |
| R5 | `prefer_const_constructors` lint fail when SnackBar loses `const` | `settle_up_screen.dart:241` | `flutter analyze` immediately after Wave 5 |
| R6 | `intl DateFormat.MMM('ar')` data missing in CI environment | `ledger_timeline.dart` | `flutter_localizations` bundles ICU data; verify by running integration test in CI before merging Wave 6 |
| R7 | Integration test flakes on GoogleFonts async load | New `locale_arabic_ledger_test.dart` | `tester.runAsync` pattern per `feedback_googlefonts_runasync` |
| R8 | Translation tone mismatch between PR2a and PR2b | New 126 ARB Arabic values | Same translator/voice as PR2a; review formality before commit |
| R9 | Shared widget cascade translates Groups settle-up view ahead of rest of Groups surface | `group_settle_up_screen.dart` | Acknowledged design-time; documented in PR body |
| R10 | Someone pulls `currencyDisplayName` into settle-up during implementation | `record_payment_sheet.dart` | Codex gate item + this design doc explicitly forbid |

---

## Open questions (verify during implementation, not blocking)

- **`'EVENT DEFAULT'`** at `expense_editor_body.dart:1004` reads like a sentinel/badge label. Confirm user-facing before translating. If internal-only, leave English.
- **Empty-state prose** at `ledger_screen.dart:577,587-588` ("An empty page, ready to be written.", "The first OMR you log will set the trip total…") needs voice-matched Arabic translation, not literal machine output. Flag to translator.
- **Legacy `categoryName` variants** in Firestore — case/whitespace permutations from old custom-CRUD data. If sample shows variants beyond case/whitespace, the exact-match fallback bucket is "Other" per helper.
- **`intl.DateFormat.MMM('ar')` output** — Arabic month names from ICU (`يناير, فبراير…`) vs Latin-Arabic mix? Verify rendered output at Wave 6.

---

## Acceptance criteria

PR2b is shippable when:

- [ ] All in-scope files (33 listed above) no longer render user-visible English strings, except: brand strings, raw currency codes, and the 4 known hardcoded-OMR bugs (explicitly deferred).
- [ ] `dart run tool/check_arb_completeness.dart` exit 0.
- [ ] `flutter analyze` clean (zero new warnings vs baseline on `main` @ edfd385).
- [ ] `flutter test` exit 0 — full suite including new unit tests for helpers + new integration test.
- [ ] Coverage ≥80% per `readiness_check.yml`.
- [ ] `test/integration/locale_arabic_ledger_test.dart` passes.
- [ ] `git diff main...HEAD` shows **no changes** in: `lib/features/ledger/providers/expense_provider.dart`, `lib/core/services/money_serializer.dart`, `lib/shared/widgets/r_amount.dart`, `security/firestore.rules`, `functions/`, `lib/core/router/app_router.dart`, `lib/firebase_options.dart`.
- [ ] Codex gate concluded with no [P1] findings; round count ≤3.
- [ ] Branch `feat/l10n-pr2b-ledger` off `main` at edfd385.
- [ ] PR description references this design doc + lists the follow-up items below.

---

## Follow-ups (file as separate work, link from PR body)

1. **`r_amount.dart:84`** — extend 3dp rule to `{OMR, KWD, BHD}` (currently OMR-only). CLAUDE.md explicitly flags this landmine in the Financial Calculations section.
2. **`settle_up_screen.dart:221`** — replace hardcoded `const currency = 'OMR'` with group-currency lookup.
3. **`ledger_hero_block.dart:262`** — replace `Text('OMR ${...}')` with `RAmount` (consumes group currency).
4. **`expense_editor_body.dart:111`** — replace `_tripCurrency => 'OMR'` getter with event/group currency lookup.
5. **`transaction_model.dart`** — remove dead `description` field (no consumers, verified PR2b audit).
6. **`expense_editor_body.dart`** — split the 1567-LOC widget (2× the 800 ceiling). Separate refactor PR.
7. **`docs/REAL-DEVICE-QA.md` RD-09** — execute Arabic RTL pass on real Android device once PR2b merges. PR4 will add the row formally if not present.

---

# Gate Reminder

Before implementation: run `/codex` (or a fresh-context Claude instance with zero session history) against this design doc + the implementation plan. Apply findings, re-run, stop when verdict has no [P1]s. The gate is unconditional — "the design is already audited" is not an exemption.
