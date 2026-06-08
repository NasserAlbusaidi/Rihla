# Multi-currency #261 Phase 2 — PR-B (currency picker + app-wide currency-aware display)

> **For Claude:** REQUIRED SUB-SKILL: `superpowers:executing-plans` to implement this task-by-task.
> Authored 2026-06-08 against `main`/worktree HEAD `c868d056` (PR-A merged). All line numbers verified against current code (post-PR-A). This is the **executable** PR-B spec; the design contract lives in `2026-06-08-multi-currency-phase2.md` §PR-B.

## Goal

Flip Model A from a deployed-but-tautological state (every group is OMR) to a real user-facing feature: a **create-group currency picker** (the switch that lets a group be non-OMR) plus an **app-wide currency-aware display sweep** so a non-OMR group renders its own currency + decimal precision *everywhere*, and a **per-currency cross-group home hero** (the one truly cross-currency surface). Closes #261.

## Scoping decisions (locked with the user 2026-06-08)

- **One PR**, `Closes #261`, **ordered commits**: the no-op display sweep + hero land first (commits 1–5), the picker — the only observable behaviour change — lands **last** (commit 6). Each commit leaves the tree green.
- **Full sweep of net-balance / settle-up / ledger / activity money displays** incl. activity/audit feeds — a non-OMR group renders the right code + decimals everywhere a *balance or transaction amount* is shown, before the picker exists. **One conscious exception:** the profile *lifetime "Spent"* stat (next bullet) stays currency-blind — so "full sweep" is not literally total.
- **Hero render** = rich stacked per-currency blocks (net + owed/owe split + bar per currency). Single-currency (today's reality) renders byte-identically to now.
- **Profile "Spent" lifetime stat = OUT of scope** → follow-up issue (user-chosen 2026-06-08: "scope out", over "make honest" / "fix per-currency"). It is a cross-group currency-blind *lifetime-spend* aggregate (`profile_stats_provider.dart:69` sums `balances.totalSpent` across groups; rendered `profile_screen.dart:532` `currency:'OMR'`) — different axis from net, compact grid cell. **Honest disclosure (Gate R1 [P2]):** this is all-OMR-correct *today*, but the picker (the same PR's last commit) makes it **reachable-wrong** the moment a user creates a 2nd-currency group (shows `10 USD + 10 OMR = "20"`). Accepted as low-risk *informational vanity stat* (not a settle-up amount anyone pays against), NOT a money-correctness path. **The spec must not claim it is fixed.** File the follow-up as **higher-priority once a real non-OMR user exists**: "profile lifetime Spent stat is currency-blind across groups — reachable-wrong post-picker (#261 follow-up)".
- **Dead code excluded** (one-PR-one-thing → separate dead-code PR): `event_card.dart` (4 OMR/3dp sites, **zero `lib/` callers** — verified `grep 'EventCard('`), `Settlement.toFirestore()`/`Expense.toFirestore()` (zero `lib/` callers; live writes build the map inline). File: "delete dead event_card.dart + toFirestore() OMR-hardcoded methods (#261 follow-up)".
- **`expense_provider.dart:328` `'OMR'` is the intentional #47 defensive fallback** for unsupported-currency in `calculateBalances` — do NOT touch.

## Hard constraints (deployed rules — do not violate)

- For a group with `currency = X`, every expense+settlement create MUST write `currency == X` (rules-enforced since `edd6421`). `group.currency` is **immutable** after create. PR-A already threads X into the write paths. PR-B is the **read/display** half + the picker that sets X at create.
- Within ONE group/event there is exactly ONE currency = `group.currency` (rules pin every `expense.currency == group.currency`). So per-group aggregation is currency-safe; **only the cross-group hero is genuinely multi-currency.**

## Supported currencies + scale (single source of truth)

10 codes. `money_serializer.dart` `_currencyScale` and `formatters.dart` `currencyConfig` both list them; `currencyDisplayName()` switches them; rules `validCurrency` allows them. Scales: OMR/KWD/BHD = 1000 (3dp), USD/EUR/GBP/SAR/AED/QAR = 100 (2dp), JPY = 1 (0dp).
**There is NO ordered list const today** (the only order is the `currencyDisplayName` switch + ARB key order). PR-B adds one (Task 0). GCC-first canonical order: **`OMR AED SAR USD EUR GBP QAR KWD BHD JPY`**.

## Load-bearing facts (verified)

- `RAmount(value:, currency:, showCurrency:)` already handles BOTH the ISO code label AND per-currency decimal precision (`r_amount.dart:85` reads `currencyConfig[currency].decimals`). **`currency` drives precision EVEN when `showCurrency:false`.** So every `RAmount` that omits `currency` silently renders OMR 3dp — that is the core bug. The fix is almost always "pass `currency:`", no widget change.
- `AppFormatters.formatCurrency(amount, code)` is code-first (`'CODE 12.345'`) with currency-correct decimals — use it to replace hand-formatted `'OMR ${x.toStringAsFixed(3)}'`.
- **`groupDetailProvider` binds REAL Firestore in tests** (`groupServiceProvider = Provider(GroupService.new)`). Any test booting a screen that *newly* watches it hangs unless it adds `groupDetailProvider(gid).overrideWith((ref) => Stream.value(Group(...)))`. Seeding a doc is inert. (Project #1 currency-test trap.)
- 3 screens (`group_detail`, `event_command_center`, `group_activity`) **already** watch `groupDetailProvider` and already override it in tests → **no new trap** there; currency threads along the path that already carries `group`/`group.name`. **`LedgerScreen` does NOT** watch it → adding the watch is a **new trap** for its 5 tests.

---

## Task 0 — Canonical currency ordering const + guard test

**Files:** new `lib/core/constants/supported_currencies.dart`; new `test/unit/supported_currencies_test.dart`.

```dart
// lib/core/constants/supported_currencies.dart
/// Canonical display order for the 10 supported currencies (GCC-first).
/// Single source of truth for the create-group picker (B1) and the
/// per-currency hero bucket sort (B2). Must stay in sync with
/// MoneySerializer supported codes (guarded by supported_currencies_test).
const List<String> kSupportedCurrencies = [
  'OMR', 'AED', 'SAR', 'USD', 'EUR', 'GBP', 'QAR', 'KWD', 'BHD', 'JPY',
];
```

**Guard test (RED first):** assert `kSupportedCurrencies.toSet()` equals the set of codes `MoneySerializer.isSupported` accepts (iterate the 10 + assert a junk code is rejected) AND equals `AppFormatters.currencyConfig.keys.toSet()` — so adding a code later without updating all three fails CI. Also assert `kSupportedCurrencies.first == 'OMR'` (default) and no duplicates.

**Commit:** `feat(core): canonical kSupportedCurrencies order + drift guard (#261 PR-B)`

---

## Task 1 — B2: per-currency cross-group hero (the load-bearing data-contract change)

This is the one Gate-critical structural change. Today's `CrossGroupBalance` (`group_balance_provider.dart:500-507`) sums every group's net into ONE currency-blind triple. Replace the scalar money fields with per-currency buckets.

### 1a. New contract

```dart
/// One currency's slice of the cross-group balance.
typedef CurrencyBalance = ({
  String currency,
  Decimal net,
  Decimal owedToUser,
  Decimal userOwes,
});

/// Cross-group balance, BUCKETED per currency (#261). [byCurrency] holds one
/// entry per currency the user has ACTIVE balance in (owedToUser != 0 ||
/// userOwes != 0), sorted GCC-first ([kSupportedCurrencies] order; unknown
/// codes appended, never dropped). Empty ⇒ all settled / no groups.
/// NEVER sum across entries — there is no FX.
typedef CrossGroupBalance = ({
  List<CurrencyBalance> byCurrency,
  int groupCount,
  bool isLoading,
});
```

`CrossGroupBalanceOnce = ({CrossGroupBalance balance, bool partial})` and `GroupBalancesOnce` **unchanged** (the `#244` partial/failedEventIds flags are currency-independent — do NOT bucket them).

**Field rationale (verified):** `groupCount` and `isLoading` have **no widget reader** (profile groupCount is `ProfileStats.groupCount`, a different type); kept for parity + existing-test shape. The 3 scalar money fields (`net/owedToUser/userOwes`) are **removed** — every reader migrates to `byCurrency`.

### 1b. Bucketing in BOTH providers (keep byte-for-byte parallel)

`crossGroupBalanceProvider` (live, `528-601`) and `crossGroupBalanceOnceProvider` (once, `708-755`). In each loop, the loop var is the full `Group` → `group.currency` is in hand. Replace the three scalar accumulators with a `Map<String, ({Decimal net, owedToUser, userOwes})>`:

```dart
final byCurrencyMap = <String, ({Decimal net, Decimal owedToUser, Decimal userOwes})>{};
for (final group in groups) {
  // ... existing groupNet derivation (UNCHANGED: per-user netBalance scalar) ...
  final code = group.currency;
  final prev = byCurrencyMap[code] ??
      (net: Decimal.zero, owedToUser: Decimal.zero, userOwes: Decimal.zero);
  byCurrencyMap[code] = (
    net: prev.net + groupNet,
    owedToUser: groupNet > Decimal.zero ? prev.owedToUser + groupNet : prev.owedToUser,
    userOwes: groupNet < Decimal.zero ? prev.userOwes + groupNet.abs() : prev.userOwes,
  );
}
final byCurrency = _sortedBuckets(byCurrencyMap); // see helper below
```

Helper (top-level private in the file): include a bucket iff `owedToUser != 0 || userOwes != 0`; sort by index in `kSupportedCurrencies` (unknown codes → `kSupportedCurrencies.length`, then by code) so an off-list legacy code sorts last but is **never dropped** (dropping money is the project's cardinal sin):

```dart
List<CurrencyBalance> _sortedBuckets(Map<String, ({Decimal net, Decimal owedToUser, Decimal userOwes})> m) {
  final list = <CurrencyBalance>[];
  for (final e in m.entries) {
    if (e.value.owedToUser != Decimal.zero || e.value.userOwes != Decimal.zero) {
      list.add((currency: e.key, net: e.value.net, owedToUser: e.value.owedToUser, userOwes: e.value.userOwes));
    }
  }
  int rank(String c) { final i = kSupportedCurrencies.indexOf(c); return i < 0 ? kSupportedCurrencies.length : i; }
  list.sort((a, b) { final r = rank(a.currency).compareTo(rank(b.currency)); return r != 0 ? r : a.currency.compareTo(b.currency); });
  return list;
}
```

Return-record literals (4 sites in live: `533/551/586/594`; 2 in once: `712/745`) change from `(net:.., owedToUser:.., userOwes:.., groupCount:.., isLoading:..)` to `(byCurrency: <list or const []>, groupCount:.., isLoading:..)`. The `anyLoading && net == Decimal.zero` early-data branch (live `585`) → guard on `byCurrency.isEmpty` instead of `net == Decimal.zero`.

**`computeGroupBalances` / `GroupBalances` / `groupBalancesProvider` — DO NOT TOUCH.** Per-group is single-currency by rules; the currency is a property of the `Group` the caller holds, applied only at the cross-group fold. (Verified: `computeGroupBalances` takes no Group/currency arg; adding one would be redundant.)

### 1c. `BalanceHeroCard` — rich stacked per-currency blocks

`balance_hero_card.dart`. Today `_LoadedCard` reads `balance.net/owedToUser/userOwes` and renders: header (`HomeKeys.balanceHeroCard` container) → `'Across all journeys'` + **hardcoded `'OMR'` mono label (113)** → big `RAmount(currency:'OMR', showCurrency:false)` (123) → caption → `_SplitBar` → `_SplitLegend` → optional `_IncompleteNotice` (partial).

Refactor: extract the **net + caption + split bar + legend** into a private `_CurrencyBlock({required CurrencyBalance bucket})` that reads `bucket.currency/net/owedToUser/userOwes` and:
- header currency label = `bucket.currency` (was hardcoded `'OMR'`),
- `RAmount(value: bucket.net, currency: bucket.currency, showCurrency: false, ...)`,
- `_SplitBar(owedToUser: bucket.owedToUser, userOwes: bucket.userOwes)`,
- `_SplitLegend(...)` with each `_LegendLine` `RAmount` passing `currency: bucket.currency` (fixes the default-OMR legend at `318`).

`_LoadedCard.build`:
- `byCurrency.isEmpty` → the **settled state**: keep one block rendering caption `homeAllSettledAcrossJourneys`, full-width sage `_SplitBar` (the `!hasAny` branch already does this), legend 0/0; **suppress the per-currency code label** (no currency to denominate). Net is `Decimal.zero`.
- `byCurrency.length == 1` → one `_CurrencyBlock` → **visually identical to today** for an all-OMR user (header shows `'OMR'`, same big amount, same split). This is the parity guarantee.
- `byCurrency.length > 1` → the `'Across all journeys'` header once, then a `_CurrencyBlock` per bucket separated by a thin divider (`SizedBox(height: 18)` + `Divider`), GCC-first (already sorted).
- `_IncompleteNotice` (partial) stays appended **once** at the bottom (currency-independent).

Keep `HomeKeys.balanceHeroCard` on the outer container in all states. `_ErrorCard` unchanged.

### 1d. Test migration (enumerated readers — Gate principle "enumerate from the type")

Unit tests reading the removed scalar fields → migrate to `byCurrency.single.X` (single-currency) + add multi-currency cases:
- `test/unit/cross_group_balance_test.dart` (live provider; `.net/.owedToUser/.userOwes` at `306-308,327-329,347-348,375-376`).
- `test/unit/home_balance_once_104_test.dart` (`result.balance.owedToUser/userOwes` at `197-198,257-258`).
- `test/unit/home_balance_partial_244_test.dart` (`result.balance.userOwes/net` at `267,352`).

Widget/screen tests overriding `crossGroupBalanceProvider` or `crossGroupBalanceOnceProvider` with the old literal → update to the new shape `(byCurrency: [(currency:'OMR', net:.., owedToUser:.., userOwes:..)], groupCount:.., isLoading:false)`. **Enumerated by `grep -rln "owedToUser:" test/` = 8 files (Gate R1 [P1]: the first draft missed 3).** Exact conversions:
- `test/features/home/balance_hero_card_test.dart`, `balance_hero_card_partial_test.dart`, `balance_hero_card_tap_test.dart` — `_LoadedCard`/once overrides → single OMR bucket (or `const []` where all-zero).
- `test/features/home/home_screen_dashboard_test.dart` — overrides the live `crossGroupBalanceProvider`; convert its literal. (Also breaks on the Task 3 `_toEntry` record — see Task 3.)
- `test/features/home/home_screen_quick_actions_test.dart` (`_baseOverrides`, `crossGroupBalanceProvider`, all-zero @32-37) → `byCurrency: const []`.
- `test/features/home/home_screen_groups_test.dart` (`_overrides`, `crossGroupBalanceProvider`, all-zero @32-37) → `byCurrency: const []`.
- `test/features/home/home_hero_scroll_to_journeys_test.dart` (`crossGroupBalanceOnceProvider`, net 12.5/owed 12.5/owes 0 @62-67) → `byCurrency: [(currency:'OMR', net: Decimal.parse('12.500'), owedToUser: Decimal.parse('12.500'), userOwes: Decimal.zero)]`.
- `test/features/home/cross_group_activity_screen_test.dart` (overrides `crossGroupBalanceProvider` all-zero @73-76) → `byCurrency: const []`. (Also needs the Task 3 `_makeEntry` `currency` field.)
- Re-grep `grep -rln "owedToUser:" test/` after migration → must return **0** (no old-shape literal survives).
- **Do NOT over-edit** `home_screen_dashboard_test.dart:122-126` — that override *bridges* `crossGroupBalanceOnceProvider` off the live `crossGroupBalanceProvider` passing the value straight through (shape-agnostic), so it auto-adapts once the live override literal is converted. Only the live-provider literal in that file needs editing (Gate R2 [P3]).

**New multi-currency tests (RED→GREEN, make the no-op provable):** table-driven over `{OMR}`, `{USD}`, `{OMR+USD}`, `{OMR+USD+JPY}` → assert `byCurrency` has N entries with the right per-currency net/owed/owes, **GCC-first order**, and **no cross-currency sum** (e.g. OMR +10 & USD −10 ⇒ two buckets, never net 0). Hero widget test: 2-currency override ⇒ two `_CurrencyBlock`s with the right code labels + 2dp/3dp precision; settled (empty) ⇒ no code label; all-OMR single ⇒ unchanged.

**Commit:** `feat(home): per-currency cross-group hero buckets (#261 PR-B)` *(no-op for all-OMR: single bucket renders identically)*

---

## Task 2 — Ledger display sweep (new `groupDetailProvider` watch in `LedgerScreen`)

**Currency source:** `LedgerScreen` adds `ref.watch(groupDetailProvider(widget.groupId))`, folds it into the existing `eventAsync.when` gate (loading if either loads; error/not-found if group null — **never default `'OMR'`**, mirroring `add_expense_screen.dart:108`/`settle_up_screen.dart:54`), then threads `group.currency` into `_Body` and down. `eventTotal` (`ledger_view_provider.dart:122`, currency-blind sum) is **correct** under single-currency-per-group — do NOT touch it; just pass `group.currency` to display widgets. Add this load-bearing-invariant note as a code comment.

| # | Site | Change |
|---|------|--------|
| 2a | `ledger_hero_block.dart` `LedgerHeroStatement._inlineMoney` (`120` precision, `140` `'${sign}OMR'`) | New `required String currency` on `LedgerHeroStatement`; pass into both `_inlineMoney` calls; `'$sign$currency'` (140); `toStringAsFixed(currencyConfig[currency]?.decimals ?? 3)` (120). `import formatters.dart`. |
| 2b | `ledger_hero_block.dart` `LedgerTripCaption` (`268`) | New `required String currency`; line 268 → `Text(AppFormatters.formatCurrency(total, currency), …)`. |
| 2c | `ledger_day_card.dart` `_ExpenseRow` (`252`, `259`) | `currency: expense.currency` (already in hand — `_ExpenseRow` has the `Expense`). No new param. |
| 2d | `ledger_day_card.dart` `LedgerSettleRow` (`422`) | New `required String currency` on `LedgerDayCard` + `LedgerSettleRow`; settlement branch (`160`) passes it; RAmount `currency: currency`. (Settlement has no currency field → group.currency.) |
| 2e | `ledger_roster_strip.dart` `_Chip` (`256`) | New `required String currency` threaded `LedgerRosterStrip→_RosterTile→_Chip`; `toStringAsFixed(currencyConfig[currency]?.decimals ?? 3)`. **Precision-only** — chip intentionally shows no code (keep compact; see Open Q resolution). |
| 2f | `ledger_search_sheet.dart` `_SettlementHit.currency` (`491`) | Add `required String currency` to `showLedgerSearchSheet` + `_LedgerSearchSheet`; thread into `_filter` (`497`) which constructs `_SettlementHit` at `534` (positional ctor `468` — add the currency arg); `_SettlementHit.currency` returns it. `_ExpenseHit` (`462`) already uses `expense.currency`. Caller `ledger_screen.dart:236` passes `group.currency`. |
| 2g | `ledger_screen.dart:579` empty copy | Parameterize ARB `ledgerEmptyStateFirstExpenseBody` → `({currency})` in `app_en.arb:528` + `app_ar.arb:179` (+ `@`-metadata placeholder block); regen l10n; `_EmptyStateBody` gains `required String currency` (drop `const` at `301`); call `ledgerEmptyStateFirstExpenseBody(currency)`. |
| 2h | `ledger_screen.dart:332` END-OF-LEDGER `'0.000'` | Replace literal with `Decimal.zero.toStringAsFixed(currencyConfig[group.currency]?.decimals ?? 3)`. Low severity, include for completeness. |

**Already-correct (verify, no change):** `custom_split_sheet.dart` (threads `currency` end-to-end from `expense_editor_body.widget.currency`), `expense_editor_body.dart`, `expense_success_dialog.dart`, `add_expense_screen.dart`, `edit_expense_screen.dart`, `settle_up_screen.dart`.

**Test impact (all 5 boot `LedgerScreen`, 0 current `groupDetailProvider` overrides → MUST add it):** `ledger_filter_recompute_test`, `ledger_screen_same_name_test`, `ledger_back_arrow_rtl_test`, `ledger_activity_entry_test`, `ledger_screen_overflow_test`. Plus widgets constructed directly gain required `currency`: `ledger_hero_block_rtl_test` (`LedgerHeroStatement`+`LedgerTripCaption`), `ledger_day_card_former_member_test` (`LedgerDayCard`), `ledger_split_ways_test` (if it builds `LedgerDayCard`), `test/unit/ledger_search_filter_test` (`_filter`/`_SettlementHit` gain `currency`). Override currency `'OMR'` keeps existing literal assertions valid; **add at least one non-OMR (USD or JPY) variant asserting 2dp/0dp** so the sweep is provable.

**Commit:** `feat(ledger): thread group.currency into all ledger money displays (#261 PR-B)` *(no-op for all-OMR)*

---

## Task 3 — Home + activity sweep

| # | Site | Change |
|---|------|--------|
| 3a | `home_screen.dart` `_GroupRow` RAmount (`679`) | `currency: group.currency` (`_GroupRow` already has `final Group group`). No new param/trap. |
| 3b | `journey_ticket_card.dart` RAmount (`125`) | Add `final String currency` (`required`) to **`ActiveJourneyEntry`** class (`active_journeys_provider.dart:12-22`); populate `currency: group.currency` at construction (`160`, inside `for (final group in groups)` — verified in scope); widget passes `currency: entry.currency`. No test constructs `ActiveJourneyEntry` directly (grep=0), so only the provider construction breaks. |
| 3c | `cross_group_activity_screen.dart` RAmount (`389-393`) | Add `String currency` to **`CrossGroupActivityEntry`** record typedef (`dashboard_providers.dart:15-19`); populate `currency: group.currency` at construction (`57`, group in scope); RAmount `currency: entry.currency`; drop the `toStringAsFixed(3)` quantization (parse the metadata value without forcing 3dp; RAmount applies currency decimals). |
| 3d | `group_activity_screen.dart` RAmount (`461`, `465`) | Screen already watches `groupDetailProvider` (`114`). Capture `final currency = groupAsync.valueOrNull?.currency ?? 'OMR'` in `build`; thread through `_buildBody → _DaySection → _ActivityRow` (new `required String currency`); both RAmounts `currency: currency` (`showCurrency:false` stays — precision-only). |
| 3e | `group_activity_screen.dart` `_coerceAmount` num branch (`500`) | Replace `Decimal.parse(raw.toDouble().toStringAsFixed(3))` → `Decimal.parse(raw.toString())` (drop OMR 3dp assumption; the String path — the common case — is already precision-neutral; RAmount reformats per currency). |

**Already-correct (no change):** `lib/features/activity/widgets/expense_audit_detail.dart` (`181`, reads `snap.currency` from audit metadata; cross-currency before→after already handled `114/119`; tested). *(Note the path: `activity/widgets/`, not `ledger/widgets/`.)* `balance_hero_card.dart` literals (`113/123/318`) are **subsumed by Task 1** (the per-currency hero) — verify Task 1 replaced the badge AND the legend, not just the headline net.

**Adjacent bug (FLAG, do NOT fix here):** `cross_group_activity_screen.dart:326-327` only coerces the metadata amount on the `num` path — a settlement amount stored as a stringified `Decimal` renders **nothing** in the cross-group feed today (pre-existing, currency-independent; present for OMR too). File follow-up: "cross-group activity feed drops string-encoded settlement amounts (#261 follow-up)". Not in PR-B scope (not a currency bug).

**Test impact (Gate R1 [P2] corrected — `grep "ActiveJourneyEntry(" test/` = 0: NO test constructs `ActiveJourneyEntry` directly, so adding its `required currency` field breaks only the provider's own construction at `active_journeys_provider.dart:160`, handled in 3b):**
- `home_screen_dashboard_test.dart` — breaks on `_toEntry` (`:160`, builds `CrossGroupActivityEntry`), NOT `ActiveJourneyEntry`. Add `currency: 'OMR'` to the `_toEntry` record `(log:.., groupName:.., groupId:.., currency: 'OMR')`. (`_GroupRow` reads `group.currency` directly — no trap. This file also needs the Task 1d balance-shape conversion.)
- `dashboard_providers_test.dart` — `CrossGroupActivityEntry` record gains `currency`; update any in-test literal + the provider now reads `group.currency`.
- `cross_group_activity_screen_test.dart` — `_makeEntry` (`:41`) record literal needs `currency: 'OMR'`; add a non-OMR row test asserting per-row currency (USD 2dp). (Also Task 1d balance conversion.)
- `active_journeys_provider_test.dart` — does NOT construct `ActiveJourneyEntry`; reads provider output. Add a `entries.single.currency == 'OMR'` assertion (proves the new field is populated). No compile break.
- `group_activity_screen_test.dart` — already overrides `groupDetailProvider`; add a non-OMR `_testGroup` + settlement-amount dp assertion (proves the `_ActivityRow` currency threading + `_coerceAmount` fix).

**Commit:** `feat(home): currency-aware group rows, journey tickets, activity feeds (#261 PR-B)` *(no-op for all-OMR)*

---

## Task 4 — Groups + events sweep (no new trap — screens already watch `groupDetailProvider`)

| # | Site | Change |
|---|------|--------|
| 4a | `group_detail_screen.dart` `_BalanceCard` RAmount (`545`) | `currency: group.currency` (`_BalanceCard` has `final Group group`). |
| 4b | `group_detail_screen.dart` `_EventRow` RAmount (`758`) | New `required String currency` on `_EventRow`; thread via `_eventsSliver` (new param) from `_Content.build` where `group` is in scope (`147`); `currency: group.currency`. |
| 4c | `group_detail_screen.dart` `_MemberRow` RAmount (`966`) | New `required String currency` on `_MemberRow`; `_MembersCard` has `final Group group` → pass `currency: group.currency` to each `_MemberRow`. |
| 4d | `event_command_center.dart` `_BalanceWithBreakdown` RAmount (`417`) | Screen watches `groupDetailProvider` (`63`), passes `group?.name` to `_Content` (`82`). Add a parallel `currency: group?.currency ?? 'OMR'` → `_Content` (new field) → `_BalanceHero` (new field) → `_BalanceWithBreakdown` (new field); RAmount `currency: currency`. |
| 4e | `event_command_center.dart` `_BreakdownRow` RAmount (`548`) | `_BreakdownRow` new `required String currency`; pass in the `_BalanceWithBreakdown` breakdown loop; RAmount `currency: currency`. |
| 4f | `event_command_center.dart` `_LedgerSummaryStrip` RAmount (`611`) | `_LedgerSummaryStrip` new `required String currency`; pass from `_Content.build`; RAmount `currency: currency`. **`showCurrency` defaults true here** → a USD group's label flips `OMR`→`USD` (desired, matches home hero). |

**Already-correct (verify, no change):** `group_settle_up_screen.dart` (the precedent — `group.currency` @ `125/316/345/405/420`), `settle_up_page_body.dart`, `group_settlement_tile.dart`, `group_settlement_summary.dart`, `groups/widgets/record_payment_sheet.dart` (already JPY-tested), `event_command_center.dart:839` (uses `expense.currency`).

**Test impact (overrides already exist — recompile + prove):** `group_detail_screen_test`, `events/group_detail_events_test`, `groups/group_screens_test`, `group_detail_navigation_test`, `group_detail_invite_share_test`, `event_command_center_test`, `event_command_center_same_name_test`, `group_activity_screen_test`. All `_EventRow/_MemberRow/_BreakdownRow/_LedgerSummaryStrip/_ActivityRow` are **file-private** → no external direct construction (only via the screen) → internal threading recompiles. **Add ≥1 non-OMR `_testGroup` (USD or JPY) per money-asserting screen test + assert dp count** so the sweep is provable, not a silent no-op.

**Commit:** `feat(groups): currency-aware group-detail + event-command-center money (#261 PR-B)` *(no-op for all-OMR)*

---

## Task 5 — B1: create-group currency picker (THE SWITCH — last commit)

**Files:** new `lib/features/groups/widgets/currency_picker_sheet.dart`; modify `create_group_screen.dart`; ARB (new key); `test/features/groups/create_join_group_test.dart`.

### 5a. `CurrencyPickerSheet` (clone the live `language_picker_sheet.dart` pattern)
A `StatelessWidget` (or `ConsumerWidget`) bottom sheet — `showModalBottomSheet(isScrollControlled, surface bg, rounded top 20)`. Title `context.l10n.currencySheetTitle` ('Currency', exists). Iterate **`kSupportedCurrencies`** (all 10, GCC-first) as `RadioListTile<String>` with `title: Text(currencyDisplayName(code, context.l10n))` and `subtitle: Text(code)` (name + ISO code). `groupValue` = the currently-selected code passed in. **`onChanged` returns the picked code to the caller (callback / `Navigator.pop(code)`) — it must NOT call `settingsProvider.setCurrency`** (this is a per-group write-once choice, not a user default). `HapticService.selection()` on pick. Add a correct subtitle below the title: new ARB key `createGroupCurrencyHint` = EN "This group's currency. It can't be changed later." / AR equivalent — **do NOT reuse `currencySheetSubtitle`** ("Default for new trips. Existing trips keep their currency.") which is wrong copy for an immutable per-group choice.

### 5b. `create_group_screen.dart`
- `_CreateGroupScreenState`: add `String _selectedCurrency = 'OMR';` (literal default — NOT seeded from `settingsProvider.currencyCode`; that re-couples to dead #61 infra and there's no per-user currency concept).
- Replace `const _ReadOnlyCurrencyField()` (`182`) + the widget (`439-466`, hardcoded `'OMR'` text `455`) with a **tappable** field (same `_FieldLabel(groupDefaultCurrency)` + underlined `Container`) that on tap opens `CurrencyPickerSheet` with `selected: _selectedCurrency` and `setState`s the result; renders `_selectedCurrency` (via `currencyDisplayName` or bare code — match existing code-only displays: `group_info_section`/`group_settings` show bare ISO, so **show the bare code** for consistency, optionally with the name).
- `createGroup(...)` call (`63`): `currency: _selectedCurrency` (was `'OMR'`). `createGroup` already takes `required String currency` — no service change.

### 5c. Tests
- `create_join_group_test.dart:108-109`: keep `find.text('Default currency')`; the default still shows OMR. **Add** a flow test: tap the currency field → sheet opens (assert `currencySheetTitle`) → pick USD → assert the field shows USD AND (using the existing `GroupService.withFirestore(fakeDb)` override) `createGroup` writes a group doc with `currency: 'USD'`. (No `groupDetailProvider` trap — create-group doesn't read it.)
- **Integration (the payoff):** create a USD group via the picker → add an expense in it → assert the expense doc persists `currency:'USD'` + `amountFils` scaled ×100 (proves PR-A plumbing + B1 picker end-to-end). Reuse `add_expense_currency_test` fixtures.
- `profile_screen_test.dart` "currency removed (#61)" pin — **leave intact** (picker is on create-group, not profile; `find.text('Currency'), findsNothing` on Profile stays green).

**Commit:** `feat(groups): create-group currency picker — enable non-OMR groups (#261 PR-B)`

---

## Task 6 — Regression sweep + analyze + follow-ups

1. `grep -rn "'OMR'\|\"OMR\"\|\${sign}OMR\|OMR \|toStringAsFixed(3)" lib/features lib/shared` — every remaining hit is justified (write-path defaults, model defaults, #47 fallback, dead code, scoped-out profile Spent). No live display surface left hardcoded.
2. `flutter analyze` clean (watch `prefer_const_constructors` — new `currency` params de-const several constructions).
3. `flutter test test/features/ledger test/features/home test/features/groups test/features/events test/unit` green; then full `flutter test` green (the no-op proof: nothing outside the swept surfaces moves for all-OMR).
4. File the 3 follow-up issues: profile Spent currency-blindness; dead `event_card`/`toFirestore` removal; cross-group activity string-amount coercion gap.

---

## Verification principles report (run while authoring)

1. **Classify every callsite INBOUND/OUTBOUND/BOTH.** All swept sites are **INBOUND (display-only)** — verified each feeds only `RAmount`/`Text`/`formatCurrency`, none feeds a write (`addExpense`/`addSettlement`/`createGroup` write paths are PR-A/B1, already correct). The picker (5b `createGroup(currency:)`) is the sole **OUTBOUND** site — gated on local picked state, write-once, rules-enforced. No display string is persisted.
2. **Every concrete claim verified against code, not docs.** Line numbers re-read post-PR-A. **Two doc/map claims falsified:** `event_card` is dead (0 `lib/` callers) — excluded; `profile Spent` is a cross-group aggregate not a per-record relabel — scoped out. Two surfaces the map missed (own grep): `ledger_hero_block:140` (interpolated `${sign}OMR`), `ledgerEmptyStateFirstExpenseBody` copy.
3. **One read-path per write-path.** No new write paths except the picker (5b). Its read-back is the create-USD→add-expense integration test (5c).
4. **Fields enumerated from the type.** `CrossGroupBalance` enumerated (`net/owedToUser/userOwes/groupCount/isLoading`); every reader located across `lib/` (only `balance_hero_card`) AND `test/` (5 files). `ActiveJourneyEntry`/`CrossGroupActivityEntry` opened and confirmed to lack `currency` before adding it.
5. **Data contracts spelled out.** New `CurrencyBalance`/`CrossGroupBalance` shapes given exactly; bucket inclusion rule (`owed||owes != 0`), sort (GCC-first, unknown-last, never-drop), empty→settled, single→identical.
6. **Arithmetic decomposition.** The cross-group net does NOT decompose across currencies (the whole bug). Buckets keep each currency's `net = sum(groupNet)` and `net == owedToUser - userOwes` **per bucket** (pinned by the table test). Per-group `computeGroupBalances` is currency-safe (rules: one currency/group) and untouched.
7. **Adversarial pass on an orthogonal axis.** The fix is on the **currency** axis; the worked tests exercise **settlement folding** (a settled OMR group + an unsettled USD group → OMR bucket dropped, USD bucket shown — proves bucket inclusion respects net-zero-after-settlement) and **identity** (same user across 3 currencies → 3 buckets, GCC-ordered). The `#244 partial` flag is exercised cross-currency (a partial USD read must still flag partial without polluting the OMR bucket).

## Landmines

- **Never default `'OMR'` when the group hasn't loaded** (LedgerScreen gate). A non-OMR group rendering OMR mis-scales 10× and (on a write) is rules-rejected.
- **`currency` drives RAmount precision even when `showCurrency:false`** — a `showCurrency:false` callsite still needs the right `currency` or a JPY/USD amount shows 3dp.
- **Keep both cross-group providers byte-for-byte parallel** (live + once) even though only the once-variant is rendered — the project convention; drift = silent home/in-group divergence.
- **Don't bucket `partial`/`failedEventIds`** — they're per-event-read-failure flags, currency-independent.
- **Never drop a currency bucket with activity** (unknown legacy code sorts last, not dropped).
- **`prefer_const_constructors`** — new `currency` params de-const constructions; fix analyze.
- **`EmptyStateView` flutter_animate ticker** — ledger/activity tests landing on empty/error must `pumpAndSettle()`.
- **`pumpRihlaApp`** — never `pumpAndSettle` after the boot helper (ConnectivityNotifier timer).
- **Picker must NOT call `setCurrency`** — local state only; currency is per-group write-once.

## Done-check

- [ ] Task 0 ordering const + drift guard green.
- [ ] Hero buckets per currency, no FX sum; all-OMR single-bucket renders identically; settled = no code; multi-currency table test green.
- [ ] Every `CrossGroupBalance` reader migrated (enumerated from the type: 1 lib + 5 test).
- [ ] Full display sweep: ledger / home / activity / groups / events all currency-aware; regression grep clean (only justified OMR remains).
- [ ] ≥1 non-OMR (USD/JPY) assertion per swept screen proving dp + code (sweep is provable, not silent).
- [ ] Picker offers 10 codes (GCC-first), writes the chosen currency; create-USD→add-expense-USD integration green.
- [ ] `flutter analyze` clean; full `flutter test` green.
- [ ] 3 follow-up issues filed (profile Spent; dead-code; cross-group string-amount coercion).
- [ ] PR body: `Closes #261`; commits ordered no-op-sweep-first, picker-last; `Spec:` line → this file.
