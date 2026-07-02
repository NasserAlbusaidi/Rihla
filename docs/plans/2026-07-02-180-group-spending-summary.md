# #180 Group Spending Summary (Insights) Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Inline, display-only, per-currency spending insights on the group detail screen — group total, spend-by-event (+ highest-spending event), spend-by-category, top payer, top consumer.

**Architecture:** One pure aggregator (`computeGroupSpendingSummary`, no I/O) + one `Provider.family` sibling of `groupBalancesProvider` that reuses its exact fan-out (zero new Firestore listeners) + one inline `GroupSpendingSummarySection` widget on `group_detail_screen.dart`. Fully live-derived: no persistence, no Cloud Function, no schema/rules change.

**Tech Stack:** Flutter/Riverpod 2.x (no codegen), `decimal`, existing `BalanceCalculator` output (`GroupBalances`), category catalog `ledger_categories.dart`, l10n via ARB.

**Scope authority:** Issue #180 decision comment (2026-07-02) — GROUP lens only. The event lens shipped as `EventRecap` (#202/#721/#758); do NOT rebuild it.

**OUT of scope (locked):** event lens; any persistence/snapshot/Function/schema/rules change; `mixedCurrency` bool or grand-total suppression (superseded by per-currency bucketing); new route/deep-link; trends; CSV/PDF (#704); shareable PNG card.

---

## Verification (7 principles) — run against code 2026-07-02

1. **Callsite classification:** every new surface is INBOUND (display only). Aggregator reads `GroupBalances.balances` + per-event expense lists; widget renders. Nothing feeds a write. No OUTBOUND path exists in this feature.
2. **Concrete claims verified against code:**
   - `groupBalancesProvider = Provider.family<AsyncValue<GroupBalances>, String>` — `lib/features/groups/providers/group_balance_provider.dart:130`.
   - `GroupBalances` fields (typedef at `group_balance_provider.dart:95-102`): `balances: Map<String, List<UserBalance>>` (currency → per-member), `totalSpent: Map<String, Decimal>`, `eventCount`, `perEventBreakdown`, `memberNames`, `memberRawNames`. `expensesByEvent` is **internal** to `computeGroupBalances` (`:301-309`), NOT on the record — the provider rebuilds it from the same cached family instances (see 3).
   - Sibling zero-listener pattern exists twice: `groupFailedEventIdsProvider` (`:206`) and `groupTaggedEventSettlementsProvider` (`:237`) both loop `ref.watch(eventExpensesProvider/eventSettlementsProvider(...))` over the same `groupEventsProvider` list; `eventExpensesProvider`/`eventSettlementsProvider` are cached `StreamProvider.family` instances already held open by `groupBalancesProvider` while the group screen is mounted → re-watching adds NO listeners.
   - `UserBalance` (`lib/features/ledger/models/expense_model.dart:410`): `participantId`, `displayName?`, `totalPaid`, `totalOwed`, `netBalance`.
   - Settlement independence: `totalPaid`/`totalOwed` fold ONLY from event expense buckets (`group_balance_provider.dart:370-391`); group settlements adjust `netBalance` only (`:453-464`). CLAUDE.md landmine confirms: "`netBalance` folds settlements; `totalPaid` does not."
   - Currency fence: `calculateTotalExpensesByCurrency` (`expense_provider.dart:973`) uses `MoneySerializer.isSupported(e.currency) ? e.currency : 'OMR'`; `EventRecap.from` uses the same fence (`lib/features/events/models/event_recap.dart:164-165`). The aggregator MUST reuse it.
   - Category: `categoryName` is NEVER persisted (null on every Firebase expense); bucket by `categoryId ?? 'other'`, names/icons/colors via `ledger_categories.dart` catalog (`categoryNameForId` at `:53`). `EventRecap` does the identical fold (`event_recap.dart:176-180`).
   - Soft delete: excluded at the QUERY (`expense_service.dart:38` `where('isDeleted', isEqualTo: false)`), not in the calculator. Aggregator adds a defensive `!isDeleted` filter (it is a public pure fn; future callers may pass raw lists) — this makes the soft-delete table test test real behavior.
   - Group detail host verified: `lib/features/groups/screens/group_detail_screen.dart` `_ContentState.build` sliver list (`:197-267`); screen already watches `groupBalancesProvider` (balances feed `_BalanceCard`).
3. **Read-path per write-path:** no write path introduced. N/A (stated, not skipped).
4. **Fields enumerated from types:** `GroupBalances`, `UserBalance`, `Expense` (relevant: `id`, `tripId`, `amount`, `currency`, `categoryId?`, `isDeleted`, `payerParticipantId`) — read from model files, listed above.
5. **Data contracts spelled out:** exact aggregator signature, provider skip-semantics, and widget inputs below. No gestures.
6. **Arithmetic decomposition:** per currency, `sum(eventTotals) == sum(categoryTotals) == totalSpent` — holds **by construction** because all three fold from the same filtered input inside one function (the aggregator does NOT accept a separately-computed total). Superlatives are NOT a decomposition of anything (max, not sum). Pinned by a table test.
7. **Adversarial pass on orthogonal axes:** the feature axis is spending aggregation; tests exercise settlements (net ≠ paid−owed input → top payer still keyed on `totalPaid`), identity (departed member with `totalPaid` in balances → can be top payer), scope (group-level settlement never reaches the aggregator input), soft-delete, multi-currency.

**Gate:** mandatory (money aggregation, per issue). Run `/run-the-gate` on this spec BEFORE Task 1. Re-run with a fresh subagent per round until no [P1]s.

---

## Design

### Pure aggregator — `lib/features/ledger/utils/group_spending_summary.dart` (Create)

```dart
import 'package:decimal/decimal.dart';

import '../../../core/services/money_serializer.dart';
import '../models/expense_model.dart';

typedef GroupEventTotal = ({String eventId, Decimal total});
typedef GroupCategoryTotal = ({String categoryId, Decimal total});
typedef GroupPersonAmount = ({String participantId, Decimal amount});

/// Immutable, per-currency spending summary of one GROUP (#180). A pure
/// projection over the same inputs `groupBalancesProvider` already streams —
/// it adds no money arithmetic beyond per-currency sum/max. Display-only:
/// nothing here may feed a write path.
///
/// Money invariant: every field is a per-currency map; Decimals are NEVER
/// summed across currencies. Per currency, eventTotals and categoryTotals
/// each sum to totalSpentByCurrency (decomposition by construction).
class GroupSpendingSummary {
  final int expenseCount;

  /// Keyed by EXPENSE currencies (fence: unsupported → OMR, matching
  /// [BalanceCalculator.calculateTotalExpensesByCurrency]).
  final Map<String, Decimal> totalSpentByCurrency;

  /// Per currency: events with spend > 0 in that currency, desc by total,
  /// tie-broken by eventId asc. First entry = highest-spending event.
  final Map<String, List<GroupEventTotal>> eventTotalsByCurrency;

  /// Per currency: categoryId (`?? 'other'`) → summed amount, desc, tie
  /// categoryId asc. Sums to [totalSpentByCurrency] per currency.
  final Map<String, List<GroupCategoryTotal>> categoryTotalsByCurrency;

  /// Max UserBalance.totalPaid per EXPENSE currency (settlement-INDEPENDENT
  /// gross cash fronted). Absent when nobody paid > 0 in that bucket.
  /// Tie: participantId asc (deterministic).
  final Map<String, GroupPersonAmount> topPayerByCurrency;

  /// Max UserBalance.totalOwed per EXPENSE currency (biggest consumed share).
  /// Same absence/tie rules.
  final Map<String, GroupPersonAmount> topConsumerByCurrency;

  final bool isEmpty; // expenseCount == 0

  const GroupSpendingSummary({ /* all required */ });
}

GroupSpendingSummary computeGroupSpendingSummary({
  required Map<String, List<Expense>> expensesByEvent,
  required Map<String, List<UserBalance>> balances,
})
```

Fold (single pass over `expensesByEvent`, skipping `isDeleted`):
- `ccy = MoneySerializer.isSupported(e.currency) ? e.currency : 'OMR'`
- `total[ccy] += e.amount`; `event[ccy][eventId] += e.amount`; `cat[ccy][e.categoryId ?? 'other'] += e.amount`; `expenseCount++`.
- Sort slices desc, tie by id asc. Wrap results `List.unmodifiable` / `Map.unmodifiable` (match `EventRecap`).
- Superlatives: for each currency in `total.keys` only, scan `balances[ccy]` (absent → skip): max `totalPaid` where `> Decimal.zero`; max `totalOwed` where `> Decimal.zero`; tie participantId asc.
- **Superlative key-domain note:** `totalPaid/totalOwed > 0` in a bucket implies expenses exist in that currency, so restricting to expense currencies loses nothing; a settlement-only balance bucket has no meaningful "top payer".

### Provider — `lib/features/groups/providers/group_spending_summary_provider.dart` (Create)

```dart
final groupSpendingSummaryProvider =
    Provider.family<GroupSpendingSummary, String>((ref, groupId) {
  final events =
      ref.watch(groupEventsProvider(groupId)).valueOrNull ?? const <Event>[];
  final balances = ref.watch(groupBalancesProvider(groupId)).valueOrNull;

  final expensesByEvent = <String, List<Expense>>{};
  for (final event in events) {
    final eventRef = (groupId: groupId, eventId: event.id);
    final expensesAsync = ref.watch(eventExpensesProvider(eventRef));
    final settlementsAsync = ref.watch(eventSettlementsProvider(eventRef));
    // Mirrors groupBalancesProvider's OR-skip (:164-173) — an event skipped
    // there (either money stream loading/errored) is skipped here too, so the
    // summary's event universe can never disagree with the balances feeding
    // topPayer/topConsumer.
    if ((expensesAsync.isLoading && !expensesAsync.hasValue) ||
        (settlementsAsync.isLoading && !settlementsAsync.hasValue)) {
      continue;
    }
    if ((expensesAsync.hasError && !expensesAsync.hasValue) ||
        (settlementsAsync.hasError && !settlementsAsync.hasValue)) {
      continue;
    }
    expensesByEvent[event.id] = expensesAsync.valueOrNull ?? const <Expense>[];
  }

  return computeGroupSpendingSummary(
    expensesByEvent: expensesByEvent,
    balances: balances?.balances ?? const <String, List<UserBalance>>{},
  );
});
```

- Zero new listeners: every watched family instance is already alive on the group screen (same argument, documented precedent: `groupTaggedEventSettlementsProvider`, `groupFailedEventIdsProvider`).
- Keys `expensesByEvent` by the event whose stream returned the list (positional), NOT by `expense.tripId` matching — by-event slices sum to the total by construction.
- NOT a field on `GroupBalances` — keeps the money-critical record (dozens of construction sites in tests) out of scope. **Rejected alternative** (recorded): threading `expensesByEvent` out through the `GroupBalances` typedef.

### Widget — `lib/features/groups/widgets/group_spending_summary_section.dart` (Create)

`GroupSpendingSummarySection extends ConsumerWidget`, takes `groupId`. Watches `groupSpendingSummaryProvider(groupId)`, `groupBalancesProvider(groupId)` (for `memberNames` — the #196-disambiguated attribution map), `groupEventsProvider(groupId)` (id → name).

- The widget OWNS its `SectionHeader` (Gate R1 P2): `summary.isEmpty` → `SizedBox.shrink()` hides header AND content together — the host inserts exactly ONE sliver, so an empty group never shows a dangling "Insights" header.
- Per currency bucket (GCC-first order via `sortedGccFirst`), render a card: total (`RAmount`), highest-spending event row, top payer / top consumer rows (`RAvatar` + name), category chips/rows via `categoryNameForId`/`categoryColorForId`/`categoryIconForId`.
- All styling `context.colors|spacing|shadows`; `EdgeInsetsDirectional`; no hardcoded colors (theme purity).
- Host: `group_detail_screen.dart` — insert ONE `SliverToBoxAdapter(GroupSpendingSummarySection(...))` after the PEOPLE `_MembersCard` sliver (`:265`) and before the bottom spacer (header + padding live inside the widget). Insights render LAST (read-only garnish below actionable sections).
- Mockup: `docs/design/mockups/180-group-insights.html` (phone-frame, per design-mockup rule) — produced before the widget; flagged in PR for design sign-off.

### l10n

New keys in `lib/l10n/app_en.arb` + `app_ar.arb` (+ commit regenerated `lib/l10n/generated/*` — known trap): `groupInsightsTitle`, `insightsTotalSpent`, `insightsTopEvent`, `insightsTopPayer`, `insightsTopConsumer`, `insightsByCategory`. Category names already exist.

---

## Tasks

### Task 1: Pure aggregator — failing table tests first

**Files:**
- Test: `test/unit/group_spending_summary_test.dart` (Create)
- Create: `lib/features/ledger/utils/group_spending_summary.dart`

**Step 1: Write the failing table-driven tests** (money mandate: clean/edge/error rows)

Cases (fixture helpers may crib from `test/unit/group_balance_provider_test.dart` / `event_recap_test.dart`):
1. **empty** — no events / events with empty lists → `isEmpty: true`, every map empty, `expenseCount: 0`.
2. **single expense** — OMR 10 food, event E1, payer A, balances A paid 10/owed 5, B owed 5 → total {OMR:10}; eventTotals {OMR:[E1:10]}; categoryTotals {OMR:[food:10]}; topPayer A/10; topConsumer tie A,B at 5 → participantId asc.
3. **worked example (issue fixture, category ids adapted to `kCategoryIds` — the issue's "gear" is not a catalog id):** Jabal Shams = 40 (fuel 10, food 10, activities 10, groceries 10), Wahiba Sands = 60 (fuel 20, food 10, groceries 15, activities 5, sic — totals 50; use fuel 20, food 15, groceries 15, activities 10 = 60). Assert: total {OMR:100}; eventTotals desc = [Wahiba 60, Jabal 40] (first = top event); categoryTotals = fuel 30, food 25, groceries 25, activities 20 with tie food/groceries... **choose amounts so one deliberate tie exists** and assert categoryId-asc tie-break; decomposition: `sum(eventTotals[OMR]) == sum(categoryTotals[OMR]) == totalSpent[OMR]`.
4. **soft-deleted excluded** — one `isDeleted: true` expense in the input → absent from every slice and from `expenseCount`.
5. **multi-currency** — OMR + USD expenses in the same event → two buckets; nothing summed across; unsupported currency `XXX` folds into OMR bucket (fence parity).
6. **settlement orthogonality (adversarial, axis B)** — balances where `netBalance` ≠ `totalPaid - totalOwed` (settlement-folded): topPayer/topConsumer still read `totalPaid`/`totalOwed`, never `netBalance`.
7. **departed payer (identity axis)** — balances contain uid `departed-1` with the max `totalPaid`, no corresponding roster info → topPayer = `departed-1` (aggregator is identity-blind).
8. **zero-paid bucket** — balances bucket where all `totalPaid == 0` (consumption only) → `topPayerByCurrency` has no key for it; `topConsumerByCurrency` does.

**Step 2:** `flutter test test/unit/group_spending_summary_test.dart` → FAIL (file/function missing).

**Step 3:** Implement `group_spending_summary.dart` per Design (minimal, single fold).

**Step 4:** Re-run → PASS. Run `flutter analyze` → clean.

**Step 5:** Commit: `feat(insights): pure group spending summary aggregator (#180)`

### Task 2: Provider — wiring + skip-semantics tests

**Files:**
- Test: `test/features/groups/providers/group_spending_summary_provider_test.dart` (Create; harness pattern from `test/unit/group_balance_provider_test.dart` — override `groupEventsProvider`, `groupMembersProvider`, `groupSettlementsProvider`, `eventExpensesProvider`, `eventSettlementsProvider` family instances; NEVER let `groupDetailProvider`/real Firestore bind)
- Create: `lib/features/groups/providers/group_spending_summary_provider.dart`

**Step 1: Failing tests:**
1. two events with expenses → summary matches direct `computeGroupSpendingSummary` of the same inputs (wiring correctness).
2. one event's settlements stream ERRORS → that event excluded from `eventTotalsByCurrency` (OR-skip mirror), other event still present.
3. balances still loading (`groupBalancesProvider` loading) → superlative maps empty, spend maps still computed.

**Step 2:** Run → FAIL. **Step 3:** Implement provider per Design. **Step 4:** Run + `flutter analyze` → green/clean.

**Step 5:** Commit: `feat(insights): groupSpendingSummaryProvider — zero-new-listener fan-out reuse (#180)`

### Task 3: Mockup

**Files:** Create `docs/design/mockups/180-group-insights.html` (phone-frame before/after gallery per repo convention — see existing `docs/design/mockups/*.html`).

Render the worked-example data in the section design (per-currency card: total, top event, top payer/consumer rows, category rows). Commit: `docs(design): #180 group insights section mockup`

### Task 4: Widget + host wiring + l10n

**Files:**
- Create: `lib/features/groups/widgets/group_spending_summary_section.dart`
- Modify: `lib/features/groups/screens/group_detail_screen.dart` (insert section after `_MembersCard` sliver `:265`, before the 40px bottom spacer)
- Modify: `lib/l10n/app_en.arb`, `lib/l10n/app_ar.arb` (+ commit regenerated `lib/l10n/generated/*`)
- Test: `test/features/groups/widgets/group_spending_summary_section_test.dart` (Create)

**Step 1: Failing widget tests:**
1. empty summary → section absent (no header text found).
2. populated summary → total rendered via `RAmount`; top payer shows `memberNames`-resolved (disambiguated) name; top event shows event name.
3. multi-currency summary → one block per currency; no combined figure anywhere.

Use the standard boot helper + `sharedPreferencesProvider` override; override the same family providers as Task 2. Mind `EmptyStateView`-style pending-timer rules if an empty/error state is pumped.

**Step 2:** Run → FAIL. **Step 3:** Implement widget + screen insert + ARB keys, `flutter gen-l10n`. **Step 4:** Tests + `flutter analyze` + `bash tool/check_theme_purity.sh` → all clean.

**Step 5:** Commit: `feat(insights): inline group spending summary section (#180)`

### Task 5: Full verification + PR

- `flutter test` (full suite) green; `flutter analyze` clean; theme purity clean.
- Grep no `Navigator.push` / `goNamed` / hardcoded colors in new code.
- Security checklist: no secrets; display-only (no new input surface, no queries).
- PR body: `Closes #180`, `Spec: docs/plans/2026-07-02-180-group-spending-summary.md`, mockup link, note "no new Firestore listeners (reuses groupBalancesProvider fan-out — same argument as groupTaggedEventSettlementsProvider)".
- Merge via `/automerge` (Gate-category: touches `**/models/**`? No — but money-adjacent + provider; classifier fails toward GATE, which is correct).
