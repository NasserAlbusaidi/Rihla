# Event Recap — Full Money Summary (#721, Slice 2 of #202) Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Extend the live event-recap surface with the full closeout accounting picture — biggest expense, top payer, by-category & by-payer breakdowns, everyone's net, and a read-only settlement status — all per-currency.

**Architecture:** A pure display-only projection. The model `EventRecap` gains new per-currency fields assembled by the existing pure `EventRecap.from` factory; the `eventRecapProvider` feeds it the raw expense list + the disambiguated name maps it already computes in `ledgerViewProvider`. No new money math enters `BalanceCalculator`, no write path, no Firestore rules, no schema. Spending aggregates reuse the same memoized `calculateBalances` pass the ledger already ran.

**Tech Stack:** Dart, Flutter, Riverpod 2.x (no codegen), `decimal`, existing `BalanceCalculator`/`MoneySerializer`/`ledger_categories.dart`/`MemberNameResolver`, ARB l10n (en + ar).

**Design:** Approved canvas-first mockup `docs/design/mockups/721-event-recap-summary.html` (frames A outstanding / B settled / C multi-currency).

---

## Money invariants this slice MUST honor (Gate surface)

1. **Per-currency, never cross-summed.** Every new field is keyed by currency. No `Decimal` from one currency is ever added to another.
2. **Currency fence parity.** Expense-amount aggregation (category totals, biggest expense) buckets by `MoneySerializer.isSupported(e.currency) ? e.currency : 'OMR'` — byte-identical to `calculateTotalExpensesByCurrency`, so the breakdown sums to the displayed total.
3. **`categoryId`, never `categoryName`.** `categoryName`/`categoryIcon` are NEVER persisted (null for every Firebase expense). Bucket by `categoryId ?? 'other'` (null → `'other'`). The factory does **not** validate membership against `kCategoryIds` — importing that const drags `package:flutter`/`iconsax`/`app_localizations` into the previously-pure model (Gate P3 layering). Unknown non-null ids bucket under themselves and the **screen** renders them as Other via `categoryNameForId` (which folds unknown → Other). In practice the picker only ever emits ids in `kCategoryIds`, so every real expense buckets correctly; an unknown id is legacy/forged and merely shows as Other. Model imports stay `decimal` + `expense_model` + `money_serializer` (all Flutter-free).
4. **Two universes, on purpose.**
   - `participantCount` (Slice 1) = live roster (`participantIds.length`) — "who was on the trip."
   - New `participantNets` / `payerTotals` = the **full balance universe** (`balances` already folds departed members with residual balances, #249) — "who still has money outstanding / who fronted cash." A departed member's debt must NOT vanish from the recap. This divergence is intentional and documented inline.
5. **Exact-zero settlement, no tolerance.** `isSettledByCurrency[c] == balances[c].every((b) => b.netBalance == Decimal.zero)`. Matches `nonZeroNetsGccFirst` (exact `!= 0`), NOT `UserBalance.isSettled` (0.001 tolerance) — a sub-fils residual reads as outstanding, never silently even.
6. **Immutability.** All new collections wrapped `Map.unmodifiable` / `List.unmodifiable`. Factory stays pure (no Riverpod, no Firestore, no `BuildContext`).
7. **Deterministic ordering.** Category bars desc by total then `categoryId` asc (tie-break). Payer bars desc by paid then `participantId` asc. Participant nets: current user first, then net desc, then `participantId` asc. Biggest expense: max amount, tie-break by `expenseId` asc. (Determinism keeps tests stable and avoids map-iteration-order flake.)

8. **Settlement-only currency must not crash (Gate P1).** A currency can appear in `balances` (settlement parties) with **no expense** in it (e.g. Slice-1 test #6's EUR; multi-currency is fully supported, #382). For such a currency: `categoryTotalsByCurrency`/`biggestExpenseByCurrency` have **no key**, and `payerTotalsByCurrency[c]` is an **empty list** (every `totalPaid == 0`, zero-paid excluded). The screen MUST render each per-currency section only when its data is present (`map[c] != null && map[c]!.isNotEmpty`) and **never** call `.first` on an empty/absent collection. A settlement-only currency's block shows only *Who's up/down* + settlement status. Map keying: `participantNetsByCurrency`/`isSettledByCurrency`/`payerTotalsByCurrency` key over **balance** currencies; `categoryTotalsByCurrency`/`biggestExpenseByCurrency` key over **expense** currencies only.

---

## New public shapes (in `event_recap.dart`)

```dart
/// One expense surfaced as the largest in its currency (display-only).
typedef RecapExpenseRef = ({
  String expenseId,
  Decimal amount,
  String? description,
  String? categoryId,
  String payerId,
});

/// A person + a (positive) amount: a payer-breakdown / top-payer row.
typedef RecapPersonAmount = ({String participantId, Decimal amount});

/// A category + its summed amount.
typedef RecapCategoryTotal = ({String categoryId, Decimal total});

/// A person's net position in one currency.
typedef RecapNet = ({String participantId, Decimal net});
```

Display names are resolved at the WIDGET, not stored in the model: the factory carries only ids + amounts (keeps it pure and decoupled from `MemberNameResolver`). The screen looks names up in `rosterDisplayNames` (top payer, payer rows, nets) and `expensePayerDisplayNames` (biggest-expense payer), exactly as the ledger does.

**The new factory param `expenses` is OPTIONAL — `List<Expense> expenses = const []` (Gate P2).** There are FOUR inline `EventRecap.from(...)` calls in `test/features/events/event_recap_screen_test.dart` (~`:47,89,118,156`); a *required* param breaks their compile. The default `const []` means a recap built without expenses simply has empty category/biggest maps (those callers don't assert on them).

### Fields added to `EventRecap`

```dart
final Map<String, RecapExpenseRef> biggestExpenseByCurrency;        // expense currencies
final Map<String, List<RecapPersonAmount>> payerTotalsByCurrency;   // desc; totalPaid > 0 only
final Map<String, List<RecapCategoryTotal>> categoryTotalsByCurrency; // desc
final Map<String, List<RecapNet>> participantNetsByCurrency;        // you-first, then net desc
final Map<String, bool> isSettledByCurrency;                        // exact all-zero
```

`topPayer` is `payerTotalsByCurrency[c].first` (derived in UI — no separate field).

---

## Task 1: Pure factory — model fields + assembly (TDD, the Gate-critical core)

**Files:**
- Modify: `lib/features/events/models/event_recap.dart`
- Test: `test/features/events/event_recap_test.dart` (extend existing table)

**Step 1 — Write failing tests** (append to the existing `group('EventRecap.from')`). The `build()` helper gains `List<Expense> expenses = const []`. Add an `expense()` factory in the test for terse fixtures (amount, currency, categoryId, payerId, description).

Cases (each asserts ONE behavior):
- `biggest expense → max amount per currency`: two OMR expenses 180 & 45 → `biggestExpenseByCurrency['OMR'].amount == 180`, `.expenseId` correct.
- `biggest expense tie → lower expenseId wins` (determinism).
- `category totals bucket by categoryId, desc`: food 120.5, accommodation 180, transport 80 → list order accommodation, food, transport.
- `null categoryId → 'other' bucket`.
- `unsupported currency expense → OMR bucket (fence parity)`: an expense with currency `'XYZ'` lands in `categoryTotalsByCurrency['OMR']` and `biggestExpenseByCurrency['OMR']`, never `'XYZ'`.
- `category total sum == calculateTotalExpensesByCurrency per currency` (invariant cross-check inside the test).
- `payer totals desc, zero-paid excluded`: balances with totalPaid 250/90.5/0 → list has 2 entries, desc.
- `top payer = payerTotals.first`.
- `participant nets include departed universe member`: balances has `c` (∉ participantIds) with net −25 → `participantNetsByCurrency['OMR']` contains `c`. (Contrast Slice 1 test #8 where `participantCount` excludes `c`.)
- `participant nets: current user first`.
- `isSettled true iff all nets exactly zero`; `false on a 0.0005 residual` (sub-tolerance, exact check).
- `multi-currency: USD & OMR breakdowns isolated, no cross-sum`.
- `JPY (×1): integer-yen category totals, no fractional drift`.
- **`settlement-only currency (Gate P1): balance present, no expense → categoryTotals/biggestExpense have NO key for it, payerTotals[c] is empty, participantNets[c]/isSettledByCurrency[c] present`** (EUR settlement, OMR expense — Slice-1 test #6 shape). Asserts the maps key as specified in invariant 8 so the screen's presence guards are exercised.

**Step 2 — Run, verify RED**

Run (from worktree root):
`flutter test test/features/events/event_recap_test.dart`
Expected: FAIL — new fields/typedefs undefined.

**Step 3 — Implement** in `EventRecap.from`. Compute the five maps. Pseudocode for the expense-driven maps:

```dart
String _ccy(Expense e) =>
    MoneySerializer.isSupported(e.currency) ? e.currency : 'OMR';
// No kCategoryIds membership check — keeps the model Flutter-free (Gate P3).
// null → 'other'; unknown ids bucket under themselves and render as Other.
String _catId(Expense e) => e.categoryId ?? 'other';
// biggest + category, single pass over expenses:
final biggest = <String, Expense>{};
final cat = <String, Map<String, Decimal>>{};
for (final e in expenses) {
  final c = _ccy(e);
  final cur = biggest[c];
  if (cur == null || e.amount > cur.amount ||
      (e.amount == cur.amount && e.id.compareTo(cur.id) < 0)) {
    biggest[c] = e;
  }
  (cat[c] ??= {}).update(_catId(e), (v) => v + e.amount,
      ifAbsent: () => e.amount);
}
```

Balance-driven maps (payer totals, nets, settled) iterate `balances` per currency. Sort with the deterministic comparators (§ invariant 7). Wrap every result `Map.unmodifiable` with `List.unmodifiable` inner lists. `kCategoryIds` import from `ledger_categories.dart`; `MoneySerializer` from its existing location.

**Step 4 — Run, verify GREEN**
`flutter test test/features/events/event_recap_test.dart` → PASS (all old Slice-1 cases still pass).

**Step 5 — Commit**
`git commit -m "feat(recap): EventRecap full money-summary projection (#721)"`

---

## Task 2: Provider wiring

**Files:**
- Modify: `lib/features/events/providers/event_recap_provider.dart`
- Test: covered via screen test (Task 4) + factory test (Task 1); provider is a thin pass-through.

**Step 1** — Pass the raw expense list into the factory. The provider already reads `eventExpensesProvider` for the count; reuse that list (don't double-watch):

```dart
final expenses =
    ref.watch(eventExpensesProvider(eventRef)).valueOrNull ?? const <Expense>[];
...
return EventRecap.from(
  ...,
  expenseCount: expenses.length,
  expenses: expenses,
  ...
);
```

The empty/null-event branch gains the five new empty maps.

**Step 2** — `flutter analyze` clean; run factory + existing provider-touching tests.
**Step 3** — Commit `feat(recap): feed expense list to recap provider (#721)`.

---

## Task 3: l10n keys (en + ar)

**Files:** Modify `lib/l10n/app_en.arb`, `lib/l10n/app_ar.arb`. Then `flutter gen-l10n` (generated dir is git-tracked, #647).

> **Gate P3 — no `recapExpenseUnnamed`.** `categoryNameForId` returns a non-nullable `String` (folds null/unknown → "Other"), so a `?? recapExpenseUnnamed` branch is dead. Biggest-expense label chain is `description (if non-empty) else categoryNameForId(categoryId)` — a description-less expense shows its category ("Other" if uncategorized). Do NOT add `recapExpenseUnnamed`.

New keys (en):
- `recapTopPayer` "Top payer"
- `recapBiggestExpense` "Biggest expense"
- `recapByCategory` "By category"
- `recapWhoPaid` "Who paid"
- `recapWhoUpDown` "Who's up / down"
- `recapSettledTitle` "Everyone's settled up"
- `recapSettledSubtitle` "No outstanding balances in this event."
- `recapOutstandingTitle` "Outstanding balances"
- `recapOutstandingSubtitle` "{count, plural, =1{1 person still owes} other{{count} people still owe}}. Settle up from the ledger." (placeholder `count:int`)
- `recapSettledRow` "settled"
- `recapYouSuffix` "you" (rendered as "· you")
- `recapMultiCurrencyNote` "Balances are kept per currency — they're never added together."

ar.arb: provide Arabic for each (mirror existing recap* Arabic tone). Verify `flutter analyze`/build picks them up.

**Commit** `feat(recap): l10n for full money summary (#721)`.

---

## Task 4: Screen — render new sections (matches approved mockup)

**Files:**
- Modify: `lib/features/events/screens/event_recap_screen.dart`
- Test: `test/features/events/event_recap_screen_test.dart` (extend)

**Name resolution (Gate P2 — name the consumer).** The factory carries only ids; the screen resolves display names by also watching the memoized `ledgerViewProvider(eventRef)` (already in the graph — `eventRecapProvider` watches it too) and reading `view.rosterDisplayNames` (top payer, payer rows, nets — covers the full universe incl. departed members) and `view.expensePayerDisplayNames` (biggest-expense payer, **keyed by `ref.expenseId`** not payerId — Gate P3). Fallback when a uid is absent from the map: the raw uid is never shown — use `context.l10n.ledgerSomeone`.

> **Slice-1 "You" block is REPLACED, not appended to (Gate P2).** The approved mockup merges the user's position into the raised Total card (net headline + paid + share). This removes the Slice-1 standalone "You" section (`recapYouTitle` + `recapYouPaid`/`recapYourShare`/`recapSettlements`/`recapNet` rows). Per CLAUDE.md "Removing a UI element: grep tests for the removed label/key and delete obsolete assertions, don't patch them" — the FIVE existing screen-test assertions in `event_recap_screen_test.dart` that check `recapYouTitle` ('You'/'أنت'), `recapSettlements`, `recapYourShare`, `recapNet` ('الصافي') must be updated to the new merged layout (assert the in-card net/paid/share instead). The MODEL fields `user*ByCurrency` and their reconciliation tests in `event_recap_test.dart` are UNCHANGED (still proven at model level) — only the screen rendering moves. The explicit "Settlements" row is dropped (net already folds it; surface in a follow-up if wanted).

**Structure** (`_content`):
1. Title + `recapPeopleExpenses` (unchanged).
2. **Total spent** card: one row per `totalSpentByCurrency` entry, ordered `sortedGccFirst` (Gate P3 — match the per-currency sections' order). If exactly one currency AND user present → show your net/paid/share inside the raised card (frame A). If 2+ → show `recapMultiCurrencyNote` below the rows (frame C).
3. **Per currency** (iterate `currenciesForDisplay` = `sortedGccFirst(balanceCurrencies ∪ expenseCurrencies)`): a currency header when 2+ currencies; then, **each section guarded by data presence (Gate P1 — never `.first` unguarded):**
   - Highlights row — render the **Top payer** card iff `payerTotalsByCurrency[c]?.isNotEmpty == true` (then `.first`); render the **Biggest expense** card iff `biggestExpenseByCurrency[c] != null` (label = `(description != null && description.trim().isNotEmpty) ? description : categoryNameForId(categoryId)`; payer via `expensePayerDisplayNames[ref.expenseId]`). Skip the whole row if neither present.
   - By category bars — iff `categoryTotalsByCurrency[c]?.isNotEmpty == true` (width = `maxTotal > 0 ? total/maxTotal : 0` — **guard the divide (Gate P2):** a legacy/Admin-SDK doc can have `amount == 0` (`expense_model.dart` defaults missing `amountFils` to 0), so `maxTotal` can be 0 → `0/0 == NaN` crashes layout; color `categoryColorForId`).
   - Who paid bars — iff `payerTotalsByCurrency[c]?.isNotEmpty == true` (width = `maxPaid > 0 ? paid/maxPaid : 0`, same guard; neutral fill).
   - Who's up/down rows — `participantNetsByCurrency[c]` (always present for a balance currency); signed `RAmount`, current-user row soft-highlighted; zero-net row → `recapSettledRow`.
   - Settlement status card — `isSettledByCurrency[c]` → sage settled / amber outstanding. **Outstanding count = debtors only** (`participantNetsByCurrency[c].where((n) => n.net < Decimal.zero).length`), NOT non-zero nets (Gate P2 — a single a↔b debt has 2 non-zero nets but only 1 ower). Feeds `recapOutstandingSubtitle(count)`.

A settlement-only currency thus renders just *Who's up/down* + status — no highlights/category/who-paid (their maps lack the key). Verified by the settlement-only screen test below.

Use `context.colors|spacing`, `EdgeInsetsDirectional`, `RAmount`, `RAvatar`. Bars: themed containers (no hardcoded colors — `categoryColorForId` returns tokens; neutral payer bar uses `context.colors.textMuted` w/ justification comment or an existing token). **Run `bash tool/check_theme_purity.sh` before commit** (CI-only check, #615 trap).

**Tests** (widget, `pumpRihlaApp` helper; override `sharedPreferencesProvider`, `eventDetailProvider`, `eventRecapProvider`, **and `ledgerViewProvider`** with a fake `LedgerView` carrying the needed `rosterDisplayNames`/`expensePayerDisplayNames` — else its real Firebase-backed body runs in tests (Gate P2); `pumpAndSettle` for empty/error states only). **Also add the `ledgerViewProvider` override to the FIVE existing Slice-1 tests** (they currently override only `eventDetailProvider`+`eventRecapProvider`, so post-change they'd run `ledgerViewProvider`'s real body — it degrades to empty, but override it for hygiene) and update their assertions to the merged "You" card layout.
- outstanding event → "By category", "Who paid", "Who's up / down", outstanding status all render; a category name + a participant net amount findable; outstanding subtitle shows the **debtor** count, not 2× it.
- settled event (all nets 0) → settled status card + `recapSettledRow` rows.
- multi-currency event → two currency headers, multi-currency note, both buckets' sections.
- **settlement-only currency (Gate P1)** → the EUR block renders Who's-up/down + status but NO highlights/category/who-paid, and does NOT throw.
- **zero-amount expense (Gate P2)** → a single `amount == 0` expense in a currency renders the category bar without NaN/crash.
- empty event → existing empty state (unchanged).

**Commit** `feat(recap): full money-summary UI (#721)`.

---

## Task 5: Finalize

- `flutter analyze` clean.
- `flutter test test/features/events/` green; then full `flutter test`.
- `bash tool/check_theme_purity.sh` clean.
- PR body: `Closes #721`, `Spec:` line pointing at this plan, screenshots from the mockup, RED→GREEN note. One concern only.

---

## Explicitly OUT of scope (sibling slices — do not build here)

- Settle CTA buttons + event-vs-group scope explainer → **#717**.
- Closed/read-only lifecycle (`closedAt`/`closedBy`, frozen snapshot, 🔒 header) → **#723**.
- Shareable "wrapped" recap card + `shareText` → **#722**.
