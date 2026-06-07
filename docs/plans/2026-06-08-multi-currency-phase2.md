# Multi-currency #261 Phase 2 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make the deployed Phase-1 currency rules non-tautological by threading `group.currency` into every money write path (PR-A) and giving users a create-group currency picker plus a currency-aware cross-group home hero (PR-B).

**Architecture:** Model A (one currency per group, immutable after create) is already enforced server-side (rules deployed at `backend-deployed`=`edd6421`: `currencyMatchesGroup` on expense/settlement create + diff-gated update; `currency` dropped from the creator-metadata allow-list). Phase 2 is the **client** half. PR-A is pure correctness plumbing — a no-op while every group is OMR (reading `group.currency`='OMR' == today's hardcode), proven by the existing suite staying green plus new USD-group RED→GREEN tests. PR-B flips the switch (picker enables non-OMR groups) and fixes the one surface that goes money-wrong the instant a user holds two different-currency groups: the cross-group hero, which today sums `Decimal`s with no currency dimension. There is no FX source, so the hero becomes **per-currency buckets** (one net line per currency; degrades to today's single line when all groups share a currency).

**Tech Stack:** Flutter, Riverpod 2.x (no codegen), `decimal` package, `fake_cloud_firestore` + `mocktail` for tests. Money serialization via `MoneySerializer` (subunit scale per currency: OMR/KWD/BHD=1000, USD/EUR/GBP/SAR/AED/QAR=100, JPY=1).

---

## Hard constraint (deployed rules — do not violate)

For a group with `currency = X` (X ∈ `OMR USD EUR GBP SAR AED JPY KWD BHD QAR`):
- **Every** expense create AND every settlement create MUST write `currency == X` or Firestore returns `PERMISSION_DENIED`.
- Expense update is diff-gated: only an update that *touches* `currency` must match — but `amountFils` re-serialization makes currency load-bearing on every amount edit, so always pass the right currency.
- `group.currency` is **immutable** after create. No update path may change it.

Therefore PR-A's threading is what keeps writes legal once PR-B lets a group be non-OMR. Until PR-B ships, every group is OMR, so PR-A is observably a no-op.

## Supported currencies + scales (single source of truth)

`lib/core/services/money_serializer.dart` `_currencyScale`: `OMR/KWD/BHD = 1000`, `USD/EUR/GBP/SAR/AED/QAR = 100`, `JPY = 1`. `AppFormatters.currencyConfig[code].decimals` mirrors this for input/display. Rules allowlist (`firestore.rules` `validCurrency`, line 71) = the same 10 codes. The picker (PR-B) offers all 10.

---

# PR-A — Thread `group.currency` into write paths (no behaviour change)

**Branch:** `feat/261-phase2-plumbing` · **PR body:** `Refs #261` (epic stays open until PR-B).

**Scope (4 source files + tests):**
- `lib/features/ledger/widgets/expense_editor_body.dart` — replace `_tripCurrency => 'OMR'` getter with a required `currency` constructor param.
- `lib/features/ledger/screens/add_expense_screen.dart` — load `group.currency`, gate on it, thread into body + `addExpense()` + success dialog.
- `lib/features/ledger/screens/edit_expense_screen.dart` — pass `expense.currency` into the body (write path already correct since PR-0a).
- `lib/features/ledger/screens/settle_up_screen.dart` — load `group.currency`, thread into display + `addSettlement()`.

**Gate classification:** money write path → **Gate-mandatory** (run before implementation).

---

### Task A1: `ExpenseEditorBody` takes a `currency` param

**Files:**
- Modify: `lib/features/ledger/widgets/expense_editor_body.dart`
- Test: `test/features/ledger/expense_editor_body_currency_test.dart` (new) — or extend an existing editor widget test.

**Step 1 — Write the failing test.** Pump `ExpenseEditorBody(mode: add, currency: 'USD', groupId, eventId, onSubmit: ...)` inside the standard boot helper with a `FakeFirebaseFirestore` seeding a USD group + an event with the current uid as participant. Assert:
- the amount label renders `USD` (l10n `editorAmountLabel('USD')`), and
- entering `12.34` is accepted (USD = 2 decimals) — i.e. the input formatter uses 2-decimal precision, not OMR's 3.

```dart
testWidgets('editor body uses the passed currency for label + decimals', (tester) async {
  // boot helper + USD group/event fixtures (see test/helpers)
  await tester.pumpWidget(/* ExpenseEditorBody(currency: 'USD', ...) */);
  await tester.pumpAndSettle();
  expect(find.text(/* l10n editorAmountLabel('USD') */), findsOneWidget);
  // ... assert 2-decimal acceptance
});
```

**Step 2 — Run, expect FAIL** (`currency` is not a constructor param → compile error, then label shows OMR).
Run: `flutter test test/features/ledger/expense_editor_body_currency_test.dart`

**Step 3 — Implement.** In `expense_editor_body.dart`:
- Add `final String currency;` field to `ExpenseEditorBody` + `required this.currency` in the const constructor (after `mode`).
- Delete `String get _tripCurrency => 'OMR';` (line 141).
- Replace the 4 internal `_tripCurrency` references — lines **446, 528, 574** (`currency: _tripCurrency,`) and **620** (`AppFormatters.currencyConfig[_tripCurrency]?.decimals ?? 3`) — with `widget.currency`.

**Step 4 — Run, expect PASS.**

**Step 5 — Commit.** `feat(ledger): ExpenseEditorBody takes a currency param (#261 PR-A)`

> **NOTE — full compile blast radius of making `currency` required (keep it required; a default reintroduces the silent-OMR trap this plan forbids).** Adding `required this.currency` breaks every `ExpenseEditorBody(` construction site. There are **7 total** (`grep -rn 'ExpenseEditorBody(' lib/ test/` — excluding the ctor def @ `expense_editor_body.dart:96`): **2 in lib + 5 in tests** (and note `expense_editor_body_test.dart` has THREE, not one):
> - `lib/features/ledger/screens/add_expense_screen.dart:95` (fixed in A2)
> - `lib/features/ledger/screens/edit_expense_screen.dart:78` (fixed in A3)
> - `test/features/ledger/expense_editor_body_test.dart:87` — add `currency: 'OMR'`
> - `test/features/ledger/expense_editor_body_test.dart:205` — add `currency: 'OMR'`
> - `test/features/ledger/expense_editor_body_test.dart:555` — add `currency: 'OMR'`
> - `test/features/ledger/expense_editor_body_same_name_test.dart:61` — add `currency: 'OMR'`
> - `test/features/ledger/expense_editor_paid_by_picker_test.dart:60` — add `currency: 'OMR'`
>
> The 3 test FILES construct the body directly (not via a screen) and `ExpenseEditorBody` does NOT read `groupDetailProvider` (it watches event/participant/category providers only), so they need ONLY the constructor arg — no group override. The full suite cannot compile until all 7 carry `currency:`. Keep A1→A3 + these 5 test edits in one working session; the suite is green again only after all are done. (If the executor needs each step independently green, fold A1+A2+A3+the 5 test edits into one commit.)

---

### Task A2: `AddExpenseScreen` reads `group.currency`

**Files:**
- Modify: `lib/features/ledger/screens/add_expense_screen.dart`
- Test: `test/features/ledger/add_expense_currency_test.dart` (new)

**Step 1 — Write the failing test.** Boot the screen with a `FakeFirebaseFirestore` group `currency: 'USD'` + an event with the uid as participant. Fill amount `12.00`, submit. Read back the written expense doc and assert:
- `currency == 'USD'`
- `amountFils == 1200` (USD scale 100), NOT `12000` (OMR scale 1000).

**Step 2 — Run, expect FAIL** (writes `currency:'OMR'`, `amountFils:12000`).

**Step 3 — Implement.** In `add_expense_screen.dart`:
- Add import `../../groups/providers/group_provider.dart` (for `groupDetailProvider`).
- Delete the screen's own `String get _tripCurrency => 'OMR';` (line 33).
- Wrap `build()` in `ref.watch(groupDetailProvider(widget.groupId)).when(...)`:
  - `loading:` → a skeleton scaffold (reuse `SkeletonLoader.expenseList()` like `edit_expense_screen`).
  - `error:` / `data: null` → an error scaffold (mirror `edit_expense_screen._ErrorScaffold`, l10n `editorCouldNotLoadExpense*`).
  - `data: group!` → the existing `KeyedSubtree(ExpenseEditorBody(... currency: group.currency, onSubmit: (p) => _handleSubmit(p, group.currency)))`.
  - **Preserve `LedgerKeys.addExpenseScreen`** (currently @94 on the data subtree). Put it on the outer scaffold of ALL THREE branches (or keep it on the data `KeyedSubtree` only — no test asserts it today, but keeping the key contract on every branch is the safe choice).
- Change `_handleSubmit(ExpenseEditorPayload payload)` → `_handleSubmit(ExpenseEditorPayload payload, String currency)` and pass `currency: currency` to `addExpense(...)`.
- Success dialog (line 78): `currency: expense.currency` (the created expense already carries it).

**Step 4 — Fix existing add-expense tests (REQUIRED — they hang otherwise).** The new `.when(loading:)` gate reads `groupDetailProvider(groupId)`, which resolves through `groupServiceProvider` = `Provider(GroupService.new)` (`group_provider.dart:405`) — bound to the **real** `FirebaseFirestore.instance`, NOT the test fake. So in a unit test `groupDetailProvider` never emits and the screen hangs on the loader forever. **Seeding a Firestore doc is INERT.** The fix: every existing add-expense test (`test/features/ledger/add_expense_screen_test.dart`, ~14 tests, ProviderScope @~293) must add to its overrides:
```dart
groupDetailProvider(groupId).overrideWith(
  (ref) => Stream.value(Group(
    id: groupId, name: 'Trip', inviteCode: 'ABC123',
    createdBy: 'uid-yasmin', memberIds: const ['uid-yasmin'],
    currency: 'OMR', createdAt: DateTime(2026),
  )),
),
```
(import `package:safar/features/groups/models/group_model.dart` + `.../providers/group_provider.dart`). The RED test in Step 1 uses the same override with `currency: 'USD'`.

**Step 5 — Run, expect PASS.** Then **Commit.** `feat(ledger): add-expense writes group.currency, not hardcoded OMR (#261 PR-A)`

---

### Task A3: `EditExpenseScreen` feeds `expense.currency` to the body

**Files:**
- Modify: `lib/features/ledger/screens/edit_expense_screen.dart`
- Test: `test/features/ledger/edit_expense_currency_test.dart` (new)

**Step 1 — Write the failing test.** Seed a USD group + a USD expense (`currency:'USD'`, `amountFils:1200`). Open edit, change amount to `15.00`, save. Assert the updated doc keeps `currency:'USD'` and `amountFils == 1500` (not 15000). Also assert the editor amount label shows `USD` while editing (proves display threading).

**Step 2 — Run, expect FAIL** (body currently shows OMR label; without A1 the constructor wouldn't compile — this test depends on A1).

**Step 3 — Implement.** In `edit_expense_screen.dart` `build()` data branch (line 78), add `currency: expense.currency,` to the `ExpenseEditorBody(...)` call. The write path (`_save` → `updateExpense(currency: original.currency)`) is already correct (PR-0a).

**Step 4 — Run, expect PASS.**

**Step 5 — Commit.** `feat(ledger): edit-expense editor displays the expense's own currency (#261 PR-A)`

---

### Task A4: `SettleUpScreen` reads `group.currency`

**Files:**
- Modify: `lib/features/ledger/screens/settle_up_screen.dart`
- Test: `test/features/ledger/settle_up_currency_test.dart` (new)

**Step 1 — Write the failing test.** Seed a USD group + event + an expense that creates a debt. Open settle-up, record a payment, read back the settlement doc and assert `currency == 'USD'` and `amountFils` scaled by 100. Also assert the displayed suggested amount formats as USD.

**Step 2 — Run, expect FAIL** (`const currency = 'OMR'` at line 243; display `'OMR'` at line 169).

**Step 3 — Implement.** In `settle_up_screen.dart` (already imports `../../groups/providers/group_provider.dart` @16). Mirror the working `group.currency` precedent in `lib/features/groups/screens/group_settle_up_screen.dart` (@57-83 three-branch handling; @125/316/405 `group.currency` reads):
- **Read the group at the TOP of `build()`**, alongside `eventAsync` @49: `final groupAsync = ref.watch(groupDetailProvider(widget.groupId));`.
- **Three branches, mirroring the precedent — do NOT fold null into the loader** (a missing/deleted group emits `Group? == null`, which would infinite-spin):
  1. **loading** — `if (eventAsync.isLoading || groupAsync.isLoading)` → the existing spinner @51-63.
  2. **null group** — `final group = groupAsync.valueOrNull; if (group == null)` → an error branch reusing the existing `event == null` EmptyStateView pattern @67-88 (Go-Home action). (This also covers `groupAsync.hasError`.)
  3. **data** — `final groupCurrency = group.currency;` (non-null), then the existing body.
- Do NOT silently default to `'OMR'` — a non-OMR group must never write OMR (rules reject → PERMISSION_DENIED, and the subunits mis-scale 10×).
- **Display literal @169** (`currency: 'OMR',`, passed to `SettleUpPageBody`) → `currency: groupCurrency!` (non-null past the gate).
- **The OUTBOUND `const currency = 'OMR';` is @243 inside `_showRecordPaymentSheet`** (method spans 234-292), NOT `_recordSettlement`. That single literal is the sole source: it feeds the display `formatCurrency` @274 AND is passed to `_recordSettlement(currency: currency)` @291 (which already takes `currency` as a required param and writes it via `addSettlement`). Replace just `const currency = 'OMR';` @243 with `final currency = groupCurrency!;` — both the display and the write inherit it. `_recordSettlement` needs no change.

**Step 4 — Fix existing settle-up tests (REQUIRED — same hang as A2).** `settle_up_screen_test.dart` (@~54-75) overrides `eventDetailProvider`/`eventExpensesProvider`/`groupMembersProvider`/`settlementServiceProvider` but NOT `groupDetailProvider` — the new top-of-build read hangs the loader (`groupCurrency == null` forever). Add to the override list (and `settle_up_screen_same_name_test.dart`):
```dart
groupDetailProvider(groupId).overrideWith(
  (ref) => Stream.value(Group(
    id: groupId, name: 'Trip', inviteCode: 'ABC123',
    createdBy: 'bob', memberIds: const [], currency: 'OMR',
    createdAt: DateTime(2026),
  )),
),
```
`createdBy` is a literal (`'bob'`), NOT the helper's `String? currentUid = 'bob'` param — `Group.createdBy` is non-nullable required (`group_model.dart:31`), so reusing the nullable param would NPE a future `currentUid: null` test variant. The RED test (Step 1) uses `currency: 'USD'`. Add this override to the shared `buildScreen` helper (`settle_up_screen_test.dart:54`) so the "missing event state" (@134) and "loading while event loading" (@121) tests keep passing under the new `eventAsync.isLoading || groupCurrency == null` gate.

**Step 5 — Run, expect PASS.** Then **Commit.** `feat(ledger): event settle-up writes group.currency, not hardcoded OMR (#261 PR-A)`

---

### Task A5: Regression sweep + analyze

**Step 1 — `groupDetailProvider`-override sweep.** Before running the suite, grep for every app-booting ledger test that lands on `AddExpenseScreen`/`SettleUpScreen` and confirm each now overrides `groupDetailProvider(groupId)` (per A2 Step 4 / A4 Step 4). Any test that boots one of these screens WITHOUT the override hangs (real-Firestore trap). Files known to need it: `add_expense_screen_test.dart`, `settle_up_screen_test.dart`, `settle_up_screen_same_name_test.dart` — plus any integration test that drives these screens.
**Step 2.** `flutter analyze` — must be clean (watch `prefer_const_constructors`: the new `currency` param makes some previously-`const` widget constructions non-const; remove stray `const`).
**Step 3.** `flutter test test/features/ledger/ test/unit/` — green.
**Step 4.** Full `flutter test` — green (the no-op proof: nothing outside ledger should move).
**Step 5 — Commit** any test-harness updates: `test(ledger): override groupDetailProvider for currency-threaded screens (#261 PR-A)`.

**PR-A done-check:**
- [ ] No `'OMR'` literal remains in the 4 write-path files (grep).
- [ ] USD-group RED tests written first, watched fail, now pass.
- [ ] Full suite green = no-op for OMR confirmed.
- [ ] `flutter analyze` clean.
- [ ] PR body: `Refs #261` + the unmet box (picker + hero) named.

---

# PR-B — Currency picker + currency-aware cross-group hero (enables non-OMR)

**Branch:** `feat/261-phase2-picker` (off `main` after PR-A merges). Own Gate pass before implementation — **not** specced to executable granularity here; this section is the design contract the PR-B spec must satisfy.

### B1: Create-group currency picker
- Replace `_ReadOnlyCurrencyField` (`create_group_screen.dart:439-466`, hardcoded `'OMR'` text at line 455) with a tappable field that opens a bottom-sheet picker offering all 10 codes (GCC-first order: `OMR AED SAR USD EUR GBP QAR KWD BHD JPY`). Localized names via `currencyDisplayName()` (l10n `currencyOMR`…). Selection stored in `_CreateGroupScreenState` (`String _selectedCurrency = 'OMR'`; default may seed from `settingsProvider.currencyCode`).
- Thread the selection into `createGroup(name: ..., currency: _selectedCurrency)` (replace the hardcoded `'OMR'` at line 63).
- Optionally revive `CurrencyPickerSheet` from git (`git show bb2dc773^:lib/features/settings/widgets/currency_picker_sheet.dart`) but retarget it from settings → the create-group form (it must set local state, not `AppSettings.currencyCode`). Reuse l10n `currencySheetTitle`.
- Update `profile_screen_test.dart` only if it asserts the *settings* currency row stays removed — leave that pin intact (the picker lives on create-group, not profile).

### B2: Currency-aware cross-group hero (the load-bearing change)
The hard surface. Today `crossGroupBalanceProvider` / `crossGroupBalanceOnceProvider` (`group_balance_provider.dart:528,708`) sum every group's `netBalance` as one `Decimal` with no currency dimension; `CrossGroupBalance` (typedef line 500) is a single `{net, owedToUser, userOwes, groupCount, isLoading}`. `BalanceHeroCard` hardcodes the `'OMR'` label (lines 113, 125).

**Contract change:** aggregate **per currency**. Each group contributes its `netBalance` to the bucket keyed by `group.currency` (the group carries currency; `userGroupsProvider` already yields `Group`). New shape (illustrative): `Map<String, ({Decimal net, Decimal owedToUser, Decimal userOwes})>` keyed by currency code, plus `groupCount`/`isLoading`/`partial`. `BalanceHeroCard` renders one `RAmount` line per currency (sorted, GCC-first), each labelled with its own code — **never** sum across keys (no FX). When the map has exactly one key (today's all-OMR reality), the card is visually identical to current.
- The one-shot variant (`groupBalancesOnceProvider`/`crossGroupBalanceOnceProvider`) must keep its #244 `partial`/`failedEventIds` semantics per currency bucket.
- `profile_stats_provider` — VERIFY what it actually sums before PR-B (it only *references* crossGroup in a comment today). If lifetime stats sum across currencies, apply the same per-currency treatment or scope stats to a single currency.
- Re-Gate: this changes a data contract consumed by ≥2 widgets → enumerate every `CrossGroupBalance` field reader from the type.

### B4: Display-sweep — remaining hardcoded-OMR INBOUND surfaces (Gate R1 [P3]s)
These render `'OMR'` regardless of the record's stored currency; harmless while all-OMR, wrong the instant PR-B lets a group be non-OMR. Fix each to read the record/group currency in PR-B (NOT PR-A — they are display-only, no write boundary):
- `lib/features/home/widgets/balance_hero_card.dart:113,125` — hero label/`RAmount` (folded into B2's per-currency render).
- `lib/features/ledger/widgets/ledger_search_sheet.dart:491` — `_SettlementHit.currency => 'OMR'`; `Settlement` carries `currency` (`settlement_model.dart:99`) → use `settlement.currency`.
- `lib/features/events/widgets/event_card.dart:159,166` — event-card amount label.
- `lib/features/settings/screens/profile_screen.dart:532` — profile stat label.
- `lib/features/ledger/models/settlement_model.dart:137` — `Settlement.toFirestore()` hardcodes `const currency='OMR'` ignoring `this.currency`. **Test-only today** (no lib write path calls it; the live write path is `SettlementService.addSettlement`), so not a PR-A blocker — but it is the exact bear-trap shape; fix it to `this.currency` and add a regression so it can never be wired to a write that silently writes OMR.

### B3: Tests
- Table-driven: a user in {OMR-only}, {USD-only}, {OMR+USD}, {OMR+USD+JPY} → assert the hero shows N lines with correct per-currency nets and **no cross-currency sum**.
- create-group: pick USD → group doc has `currency:'USD'`; then add-expense in that group writes USD (integration with PR-A).
- Regression: all-OMR hero unchanged (golden/widget).

**PR-B done-check:**
- [ ] Picker offers 10 codes; create writes the chosen currency.
- [ ] Hero buckets per currency, no FX sum; all-OMR unchanged.
- [ ] `CrossGroupBalance` readers all updated (enumerated from type).
- [ ] `Closes #261` (epic closes when PR-B lands).

---

## Landmines (carried from Phase 1 + this round)

- **`groupDetailProvider` binds REAL Firestore in tests.** `groupServiceProvider = Provider(GroupService.new)` (`group_provider.dart:405`) → real `FirebaseFirestore.instance`. So `groupDetailProvider(groupId)` does NOT route through a `FakeFirebaseFirestore` even when a test seeds one elsewhere. The ONLY way to make the new group-load gate resolve in a unit test is to `groupDetailProvider(groupId).overrideWith((ref) => Stream.value(Group(...)))`. Seeding a doc is inert. (Gate R1 [P1].)
- **Never default to `'OMR'` when the group hasn't loaded.** A non-OMR group writing OMR is silently money-wrong AND rules-rejected (PERMISSION_DENIED). Gate the write on the group being resolved.
- **`amountFils` is currency-scaled.** Passing the wrong currency to `addExpense`/`addSettlement` mis-scales the stored subunits by 10× (OMR↔USD). The service uses one `currency` arg for both the field and `MoneySerializer.toSubunits` — pass the right one.
- **`fake_cloud_firestore` cursor order** (`.startAfterDocument` before `.limit`) — irrelevant here but don't regress pagination tests.
- **`EmptyStateView` flutter_animate ticker** — any test landing on an empty/error state must `pumpAndSettle()`.
- **`prefer_const_constructors`** — adding the `currency` param de-consts some constructions; fix analyze.
- **edit-expense write currency is `original.currency`, not `group.currency`** — under Model A they're equal, but the invariant is "preserve the expense's stored currency" (PR-0a). Do not switch edit to read group.currency.
- **No real users yet** — server is already deployed; no client-compat gating needed. PR-A/B are client-only, no deploy.
