# #382 PR-1 — Client bucketing core: `calculateBalances` → `Map<currency, List<UserBalance>>` Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Flip the client balance pipeline from flat single-currency lists to per-currency buckets, with Shim #1 keeping the #366 home facade flat, so PR-2/PR-3 can bucket the server against an already-bucketed client.

**Architecture:** `BalanceCalculator.calculateBalances` returns `Map<String currency, List<UserBalance>>`; `GroupBalances.balances`/`.totalSpent` bucket in place; the optimizer keeps its flat signature and is called once per bucket; every consumer either iterates buckets (settle-up sections, zero-gates) or selects one (single-currency display surfaces, the facade shim). The uniformity rules (`currencyMatchesGroup`) stay LIVE — every prod bucket map is empty or a singleton `{group.currency: …}`, so all UI is pixel-identical until PR-6.

**Tech Stack:** Flutter/Dart, Riverpod 2.x, `decimal`, `MoneySerializer`. No server/TS/rules changes (PR-2/PR-6).

**Issue:** #382 (epic, 7-PR ladder in body). **Gate category: YES — money math** (`BalanceCalculator` in `expense_provider.dart`).
**Base:** `origin/main` AFTER #464 (PR-0, `Settlement.currency` retention) merges — verify with `gh pr view 464 --json state,mergeCommit` before implementing. Worktree `../Rihla-382-pr1`, branch `feat/382-pr1-bucketing-core`.

---

## 0. Locked decisions (the data contract)

### D1 — `calculateBalances` return shape

```dart
static Map<String, List<UserBalance>> calculateBalances({
  required List<Expense> expenses,
  required List<Participant> participants,
  List<Settlement> settlements = const [],
})
```

- **Bucket keys** = fence-validated currencies appearing in the money records:
  - expense key: `MoneySerializer.isSupported(e.currency) ? e.currency : 'OMR'` (the existing #47 fence at `expense_provider.dart:327-329` — it becomes the bucket key as well as the precision source).
  - settlement key: `MoneySerializer.isSupported(s.currency) ? s.currency : 'OMR'`. Post-#464 `Settlement.currency` is already fence-validated in `fromFirestore`; the calculator re-fences anyway (defense-in-depth — test-constructed objects bypass the model fence; cheap, never throws).
- **Every bucket contains EVERY entry of `participants`, in `participants` order, zeros included.** This makes the sole bucket of a single-currency input **element-for-element identical to today's flat return** — the backward-equivalence property every mechanical test edit relies on.
- **No money records → `{}` (empty map).** There is no currency to key on (the calculator deliberately has no `defaultCurrency` param — it stays a pure oracle whose shape PR-2 mirrors in `recomputeNet`). The zero-money boundary consumers are handled in D10/D11.
- Per-bucket processing is byte-for-byte today's logic: paid/owed/settlement-adjustment maps move from `Map<uid, Decimal>` to per-currency maps; allocators, remainder-to-alphabetically-last, equal-split fallbacks, `_splitTolerance` — ALL unchanged (they're already per-expense-currency, #270).
- **Per-bucket conservation:** for a complete universe, `sum(netBalance) == 0` within each bucket independently. Settlements adjust ONLY their own currency's bucket — a settlement in a currency with no expense activity still creates/joins that bucket (it's real money flow; matches the server's per-doc-currency read at `groupNetBalance.ts:580`).
- Preserved seams: `debugCalculateBalancesCount` (#106) increments once per CALL (not per bucket); `onSplitFallback` (#250) unchanged.

### D2 — `GroupBalances` (record typedef, `group_balance_provider.dart:81-88`)

```dart
typedef GroupBalances = ({
  Map<String, List<UserBalance>> balances,   // was List<UserBalance>
  Map<String, Decimal> totalSpent,           // was Decimal
  int eventCount,
  Map<String, Map<String, Decimal>> perEventBreakdown,  // UNCHANGED (D5)
  Map<String, String> memberNames,
  Map<String, String> memberRawNames,
});
```

- `computeGroupBalances` fold (`:322-338`) re-keys to (currency → uid): each event's bucketed result folds per currency; group-settlement adjustments (`:341-359`) fold into **the settlement's own fenced `s.currency` bucket** (this ANSWERS the Model-B deferral — a legacy OMR settlement in any group lands in the OMR bucket, the original obligation). Final per-bucket `List<UserBalance>` is built over `allUids` (all of them, zeros included, `allUids` order) for every bucket key.
- Group-level bucket keys = union of event-level bucket keys ∪ group-settlement fenced currencies. No money → `balances: {}`.
- `totalSpent`: new `BalanceCalculator.calculateTotalExpensesByCurrency(List<Expense>) → Map<String, Decimal>` (fence-keyed sum; replaces `calculateTotalExpenses`, whose only caller is `group_balance_provider.dart:410` — the old symbol is deleted).
- `eventCount`, `memberNames`, `memberRawNames`: untouched (currency-independent; `memberRawNames` keeps feeding settlement writes).

### D3 — Optimizer: signature UNCHANGED, called once per bucket

`calculateOptimalSettlements({required List<UserBalance> balances, Map<String,String>? userNames}) → List<Map<String,dynamic>>` (keys `fromUserId/toUserId/fromUserName/toUserName/amount`) stays exactly as-is. Callers iterate buckets and call it per bucket. Cross-currency netting is impossible by construction.

### D4 — Bucket selection helper (single-currency display surfaces)

New top-level function in `expense_provider.dart` (same library as the calculator):

```dart
/// Interim single-bucket selection for display surfaces that stay
/// single-currency until #382 PR-5. Under the live uniformity rules every
/// prod bucket map is empty or a singleton {group.currency: …}.
/// - [preferred] non-null → that bucket (empty list when absent);
/// - [preferred] null (group still loading) → the sole bucket if exactly one
///   exists (its own key becomes the display currency), else ('OMR', const []).
({String currency, List<UserBalance> balances}) selectCurrencyBucket(
  Map<String, List<UserBalance>> buckets,
  String? preferred,
)
```

Used by: `event_command_center` (preferred = `group?.currency`, null-while-loading handled by sole-bucket), `ledger_screen` (preferred = `group.currency`, load-gated non-null), `group_detail_screen` (userNet + members card lookup), the facade shim (D9). NOT used by settle-up surfaces (they render ALL buckets, D7) or zero-gates (they iterate ALL buckets, D10).

### D5 — `perEventBreakdown` stays FLAT in PR-1 (deviation from the issue draft — comment on #382)

Shape stays `Map<memberId, Map<eventId, Decimal>>`. It has three consumers (`group_detail_screen:239`, `group_settle_up_screen:258-259`, the facade once-path `:848`) — bucketing it would force three collapse points; keeping it flat needs exactly one, inside its single construction site `_buildPerEventBreakdown` (`:434-473`, the second `calculateBalances` callsite at `:461`):

- per event: `calculateBalances` now returns buckets. **Empty map (no money) → emit `Decimal.zero` for each of the event's `participantIds`** (zero is currency-free; preserves today's zero rows exactly).
- exactly one bucket (every prod event under Model A) → that bucket's nets, byte-for-byte today's values.
- \>1 buckets (mixed event — prod-unreachable until PR-6, fixture-reachable): take the **GCC-first-ranked bucket** (`kSupportedCurrencies` rank, unknown codes last, ties alphabetical — the codebase's standard ordering). Deterministic, documented as interim; PR-3 buckets the breakdown properly (aggregate v2 `perEventNetMilliByCurrency`). The drill-down is already documented non-decomposing (CLAUDE.md #366 entry), so an interim single-currency view of a mixed event is display-degraded, never money-wrong (no write reads it).

### D6 — `eventBalancesProvider` + `LedgerView`

- `eventBalancesProvider` (`expense_provider.dart:94`) → `Provider.family<AsyncValue<Map<String, List<UserBalance>>>, ({EventRef eventRef, Event event})>`. Family key, #249 universe, loading/error plumbing untouched.
- `LedgerView` (`ledger_view_provider.dart:23-30`): `balances` → `Map<String, List<UserBalance>>`; `eventTotal` → `Map<String, Decimal>` (bucket the `:122-125` fold by fenced `e.currency`). Defensive-empty return (`:69-77`) → `const {}` for both. Provider stays group-currency-free (no new `groupDetailProvider` dep — selection happens in `ledger_screen`, which already has load-gated `group.currency` at `:104`; this dodges the known real-Firestore-binding test trap).

### D7 — Settle-up surfaces render per-bucket SECTIONS (PR-6 readiness; stepped-settle flow itself is PR-5)

`SettleUpPageBody` contract change (`settle_up_page_body.dart`):

```dart
/// One currency bucket's settle-up data. balances + optimalSettlements MUST
/// come from the same bucket; currency labels every amount in the section.
typedef SettleBucket = ({
  String currency,
  List<UserBalance> balances,
  List<Map<String, dynamic>> optimalSettlements,
});
```

- Props: `currency`/`balances`/`optimalSettlements` are replaced by `required List<SettleBucket> buckets`. All other props (`subjectName`, `rawNames`, `settlementsAsync`, `currentUid`, `tileKeys`, `onRecord`, `buildBreakdown`, `preSelectedMemberId`) unchanged in meaning.
- Render: for each bucket (GCC-first order, callers pre-sort) — summary card (`totalPending` summed within the bucket, labeled with the bucket currency), transfer tiles, net-balance rows. With one bucket (all prod data) the render is pixel-identical to today; with >1, sections repeat with a currency label. Empty `buckets` → the existing all-settled empty state.
- **`onRecord` gains `required String currency`** (the bucket currency). This is the OUTBOUND change: both callers' record-payment sheets and writes use the bucket currency instead of `group.currency`:
  - `settle_up_screen.dart` `addSettlement(... currency: <bucket currency>)` (`:364`),
  - `group_settle_up_screen.dart` `addGroupSettlement(... currency: <bucket currency>)` (`:417-427`) and the `logGroupEvent` description formatting (`:443-450`).
  - Under live uniformity rules the bucket currency == `group.currency` for every recordable bucket, so prod behavior is identical. If a forged/legacy foreign-currency bucket is recorded against, rules refuse the write (event settlements: `currencyMatchesGroup` at `firestore.rules:711`; group settlements: `data.currency == groupData(groupId).currency` at `:903` inside `validGroupSettlementBase` — both verified) — the correct outcome (today's code would have written a MISLABELED `group.currency` settlement against it, which is worse). PR-6 relaxes the rules; this code is then already correct.
  - `ledgerRevision` bump (`:379`) and `awaitServerAck` wrapping: unchanged.
- Both callers build `List<SettleBucket>` by iterating the bucketed balances (event screen: `calculateBalances` output at `:193`; group screen: `balancesData.balances` from `groupBalancesProvider`), calling the optimizer per bucket, sorting GCC-first. `userNames`/`rawNames` maps stay universe-spanning (the existing `:168-175` asserts and the nullable-`fromUserName` cast at `:136-137` both demand it — pass the same full maps to every per-bucket optimizer call).
- `buildBreakdown(fromUserId, toUserId) → Map<eventId, Decimal>` stays flat/currency-free in PR-1 (Gate R1 P3) — it reads the flat `perEventBreakdown` (D5), is called per tile across all buckets, and is correct for single-currency prod data; a mixed fixture sees the D5 GCC-first interim view. Display-only; no write reads it; PR-3 buckets the breakdown.

### D8 — `crossGroupBalanceProvider` (live, `:590-642`)

Has ZERO production consumers (verified — only doc-comment references outside its file; the hero is facade-based since #366) but ~10 test files reference it (mostly as provider overrides; the bucket-shape asserts live in `cross_group_balance_test` + `cross_group_currency_buckets_test` — Gate R1 P3). PR-1 adapts it minimally and honestly: replace the flat read + `group.currency` key (`:630-634`) with a per-bucket fold —

```dart
for (final entry in balances.balances.entries) {
  final userNet = entry.value
      .where((b) => b.participantId == uid)
      .firstOrNull?.netBalance ?? Decimal.zero;
  _accumulateBucket(byCurrencyMap, entry.key, userNet);  // BUCKET key, not group.currency
}
```

Deletion of the dead provider is a follow-up issue, not PR-1 (one PR, one thing).

### D9 — Shim #1: the #366 facade stays flat (removed in PR-3)

`HomeGroupBalance` (`:780-786`) keeps `userNet: Decimal` + `userPerEventNet: Map<String, Decimal>` — NO type change. `homeGroupBalanceProvider`'s aggregate path (`:828-836`) untouched (server doc is flat v1; the `currencies.length <= 1` chooser stays). The once-path collapse (`:840-854`):

```dart
// Shim #1 (#382 PR-1, removed in PR-3): under the live uniformity rules every
// bucket map is empty or a singleton {group.currency: …}; collapse to the flat
// facade shape by selecting the group's currency bucket.
final groupCurrency = ref
    .watch(userGroupsProvider)
    .valueOrNull
    ?.where((g) => g.id == groupId)
    .firstOrNull
    ?.currency;
// inside whenData:
final selected = selectCurrencyBucket(balances.balances, groupCurrency);
userNet: selected.balances
        .where((b) => b.participantId == uid)
        .firstOrNull?.netBalance ?? Decimal.zero,
userPerEventNet: balances.perEventBreakdown[uid] ?? const {},  // unchanged (D5)
```

`userGroupsProvider` is already live for the home surface (no new listener class). `partial` semantics unchanged (events-dropped only — no overloading). Foreign-currency buckets on the once-path are prod-unreachable in PR-1; the shim drops them from the flat home number by construction, documented at the shim comment. `crossGroupHomeBalanceProvider`, `_accumulateBucket`, `_sortedCurrencyBuckets`, `settledDisplayCurrencyProvider`, `groupFailedEventIdsProvider`, `balance_hero_card`, `home_screen`, `active_journeys_provider`: **zero changes** (all read the flat facade or group lists).

### D10 — Zero-balance gates: every-bucket-zero, exact `!= Decimal.zero` (never `isSettled`)

| Site | Predicate after PR-1 |
|---|---|
| leave gate `group_danger_section.dart:211-217` | block iff `balances.balances.values.any((bucket) => bucket.any((b) => b.participantId == uid && b.netBalance != Decimal.zero))` |
| delete gate `group_danger_section.dart:290-295` | `hasOutstanding = balances.balances.values.any((bucket) => bucket.any((b) => b.netBalance != Decimal.zero))` |
| remove gate `group_members_section.dart:150-182` | block iff any bucket has the TARGET (`b.participantId == member.userId`) with `netBalance != Decimal.zero` |

- Empty map / uid absent from all buckets ⇒ settled (vacuously true — correct).
- Null/loading fall-through to the server callable: unchanged (UX-only gates; server recomputes — #190/#290/#318).
- The dangerous failure direction is wrong-RESTRICTIVE (false block has NO server fallback — early return). Regression-test the false-block case (D12).
- `memberCount` (`group_danger_section.dart:188`): `.balances.length` would silently become BUCKET count. Use `balances.memberNames.length` (== `allUids.length` == today's list length, including former actors — and immune to the empty-map zero-money case).

### D11 — Single-currency display surfaces (selection, not sections)

- **`group_detail_screen`**: userNet (`:112-118`) — select `group.currency` bucket, then the existing uid lookup. `_BalanceCard.userNet` stays `Decimal`. Members card (`:869-925`): row source switches from the balances list to `data.memberNames.entries` (same key set `allUids`, same insertion order; name = `memberNames[uid]`, keep the `?? l10n.groupFormerMember` fallback) with net looked up in the selected bucket (`?? Decimal.zero`); empty-check becomes `data == null || data.memberNames.isEmpty` (same semantic as today — memberNames is empty iff allUids is empty iff the old list was empty). This fixes the zero-money-group regression the map shape would otherwise cause (empty map ≠ no members).
- **`event_command_center`**: `_Content` selects via `selectCurrencyBucket(buckets, group?.currency)` — hero, breakdown, roster dots all operate on the selected bucket; display currency = the SELECTED bucket's key (better than today's transient wrong-'OMR' formatting while the group doc loads). Total-spent strip (`:129-132` fold): bucket by fenced `e.currency` → `_LedgerSummaryStrip` renders one line per currency, GCC-first (singleton ⇒ identical UI).
- **`ledger_screen`**: select `group.currency` bucket for hero / roster chips / `isSettled` gate (`:200` — selected bucket only; per-currency hero lines are PR-5). `LedgerTripCaption` (`ledger_hero_block.dart:216-230`): `total: Decimal` → per-currency entries (`List<({String currency, Decimal total})>`, pre-sorted GCC-first by the caller from `LedgerView.eventTotal`); renders one line per currency.
- **`profile_stats_provider`** (`:103-104`): scalar-add-keyed-by-`group.currency` → map-merge keyed by the BUCKET currency: `for (final e in balances.totalSpent.entries) { spentMap[e.key] = (spentMap[e.key] ?? Decimal.zero) + e.value; }`. Behavior-identical today; honest for legacy/forged mixed docs. Do NOT collapse back to `group.currency` (that re-introduces the #378 cross-currency sum).

### D12 — Test strategy

- **RED first — new mixed-currency fixtures** (prod can't create them; the rules fence is server-side, fixtures are in-memory): in `balance_calculations_test.dart` (calculator) + `group_balance_provider_test.dart` (group fold):
  1. One event, OMR + AED expenses → exactly 2 buckets; per-bucket conservation (`sum(net)==0` each); per-bucket totals match per-currency hand-computed values; all participants present in both buckets.
  2. Settlement folds into its OWN currency bucket (AED settlement leaves the OMR bucket untouched); a settlement in a third currency creates its own bucket.
  3. Remainder contract per bucket (alphabetically-last absorbs, per currency precision — OMR 3dp vs AED 2dp in one event).
  4. Single-currency input → sole bucket element-for-element equal to the pre-flip expectation (the backward-equivalence pin).
  5. No money → `{}`.
  6. `totalSpent` buckets per fenced currency; unsupported code lands in `'OMR'`.
  7. Zero-gate false-block regression: a group settled in BOTH of two buckets must allow leave/remove/delete (widget tests, seeded provider before tap).
  8. Per-event breakdown: zero rows preserved for no-money events; sole-bucket values unchanged; mixed event picks GCC-first deterministically.
- **SEMANTIC reworks** (flagged by inventory):
  - `delete_group_balance_parity_test.dart` — interim parity statement: all existing cases are single-currency; the client's sole `'OMR'` bucket must equal the pinned flat server values (PR-2 buckets the server and adds mixed parity cases). State this in a comment at the top of the parity group.
  - `balance_aggregate_parity_test.dart` — same: v1 flat `netMilli` mirrors the sole bucket for single-currency fixtures.
  - `group_balance_provider_test.dart` — "totalSpent sums all expenses" (`:425`) becomes per-currency assertions; #112 decomposition + #249 conservation restated per-bucket.
  - `home_group_balance_provider_test.dart` — NO symbol-grep hits but pins the facade chooser incl. mixed→once-path (`:228`); assertions adjust to the shim's collapse (group-currency bucket net). Must be in the edit set explicitly.
  - `cross_group_currency_buckets_test.dart` — fixture expresses currency IN the balance record (proves the new bucket-key derivation in D8).
- **MECHANICAL** (~30 files): single-bucket fixture wraps `{'OMR': [...]}` / `{'OMR': Decimal}` and bucket-indexing of reads. `settlement_optimization_test.dart`: the `:560` integration line (optimizer signature unchanged) PLUS the `group('calculateTotalExpenses')` at `:582-680` (4 calls to the deleted symbol — re-point to `calculateTotalExpensesByCurrency` with bucket-indexed assertions; Gate R1 P3). `ledger_filter_recompute_test.dart` + `group_settle_up_screen_same_name_test.dart`: NO-EDIT (the latter doubles as a free end-to-end smoke through the real bucketed chain).
- The issue's "196 errors / 31 files" was an estimate — re-measure with `flutter analyze` after the type flip; the real edit set is ~36 files.

### Explicitly OUT of scope

- Server TS (`recomputeNet`, gates, aggregator) — PR-2/PR-3. Aggregate doc stays v1; chooser stays `currencies.length <= 1`.
- `firestore.rules` — untouched; uniformity rules stay LIVE (the epic's safety property).
- Stepped multi-bucket settle flow, per-currency hero lines on intra-group surfaces — PR-5.
- Currency picker / rules relaxation — PR-6.
- Activity-log currency — PR-4 (`logGroupEvent` description string keeps formatting with the now-bucket currency at the settle write site, D7; the metadata schema is untouched).
- Deleting the dead `crossGroupBalanceProvider` — follow-up issue.
- Extracting a shared test fixture builder (the `expense()` helper is re-declared in 6+ test files — pre-existing; follow-up).
- `UserBalance` — no currency field (currency is the bucket key); `isSettled`'s currency-blind 0.001 tolerance noted as a pre-existing wart (gates don't use it).

---

## Verification-principles run (reported, per the contract)

1. **Callsite classification** — all five `calculateBalances` callers classified: `eventBalancesProvider:144` INBOUND, `computeGroupBalances:316` BOTH (feeds settle-up writes via `groupBalancesProvider`), `_buildPerEventBreakdown:461` INBOUND, `settle_up_screen:193` BOTH (optimizer → `addSettlement`), `ledger_view_provider:116` INBOUND. OUTBOUND surfaces: the two settlement writes (`addSettlement:364`, `addGroupSettlement:417`) — both now carry the bucket currency (D7); `memberRawNames` relay unchanged. The #366 aggregate stays INBOUND-only (display cache, untouched).
2. **Claims verified against code** — every line anchor in this spec was re-read in the worktree at `dc4bd8e4` (5-agent map + direct reads of `expense_provider.dart`, `group_balance_provider.dart`, members card, `supported_currencies.dart`, `settlement_model.dart`); the #464 delta comes from the PR diff itself. Corrections found en route: `UserBalance` lives in `expense_model.dart:378` (not a separate file), its name field is `displayName`, `profile_stats_provider` is under `features/settings/`, the remove-member gate is in `group_members_section.dart` (not the danger section), `crossGroupBalanceProvider` is consumer-dead, and `totalSpent` has exactly ONE lib display consumer (profile_stats).
3. **Read-path per write-path** — bucket-currency settlement writes: read back by `groupSettlementsProvider`/`eventSettlementsProvider` → `calculateBalances` settlement fold (buckets by the same per-doc currency — closed loop); by the payment-history tiles (post-#464 per-doc currency — agrees); by the server oracle (`groupNetBalance.ts:580` per-doc — agrees, PR-2 buckets it).
4. **Fields enumerated from types** — `GroupBalances` six fields (D2), `UserBalance` five fields + three getters, `HomeGroupBalance` five fields (D9), `LedgerView` six fields (D6), `SettleUpPageBody` full prop list (D7), optimizer's five map keys (D3).
5. **Data contracts spelled out** — bucket-key fencing rule, all-participants-per-bucket, `{}`-on-no-money, `SettleBucket`, `selectCurrencyBucket` semantics, `onRecord` + `currency`, breakdown's GCC-first interim collapse.
6. **Arithmetic decomposition** — per-bucket `net = paid + settlementAdj − owed` preserved; cross-bucket sums NEVER taken (no code path sums across map entries); `totalSpent` decomposes per currency; per-bucket conservation pinned by new tests; the breakdown explicitly does NOT decompose the aggregate (unchanged contract).
7. **Adversarial pass on an orthogonal axis (settlements/identity)** — the fix axis is currency; the orthogonal checks: (a) settlements-only bucket creation (money flow with zero expenses — D1 covers, test 2); (b) former-member identity: `allUids`/universe construction is currency-independent and appears in every bucket, so the #249 orphaned-owed conservation holds per bucket (restated in tests); (c) the leave/remove gates' uid-absent-everywhere ⇒ settled vacuous case (test 7).

---

## Tasks

Commit after every GREEN step (`feat(ledger):`/`refactor(groups):`/`test(...)` conventional). `flutter analyze` must be clean at each commit boundary — the type flip makes the tree red in one step, so Tasks 1–3 land as ONE commit sequence executed together (test-first within it), then consumers follow compile-error-driven.

### Task 0: Preflight
1. `gh pr view 464 --json state,mergeCommit` → MERGED; `cd ../Rihla-382-pr1 && git fetch origin && git rebase origin/main` (branch must contain `Settlement.currency`).
2. `grep -n "currency" lib/features/ledger/models/settlement_model.dart` → field present.
3. `flutter test test/unit/balance_calculations_test.dart` → green baseline.

### Task 1: RED — calculator bucket tests
Write the D12 tests 1–6 in `test/unit/balance_calculations_test.dart` (new `group('bucketing (#382 PR-1)')`) against the NEW return shape. Run: `flutter test test/unit/balance_calculations_test.dart` → expect COMPILE FAILURE (return type) — that is the RED for a type flip; capture output.

### Task 2: GREEN — flip `calculateBalances` + `calculateTotalExpensesByCurrency`
`expense_provider.dart`: per-D1 bucketed implementation (internal maps `Map<String, Map<String, Decimal>>` keyed currency→uid; build per-bucket lists over `participants` order); add `selectCurrencyBucket` (D4); replace `calculateTotalExpenses` with `calculateTotalExpensesByCurrency`; flip `eventBalancesProvider` value type (D6). Run Task-1 tests → PASS. Mechanical edits to the 5 pure-unit calculator suites (`balance_calculations`, `split_rounding`, `issue_195`, `issue_250`, `settlement_optimization:560`) — single-bucket indexing. Run them → PASS.

### Task 3: GREEN — `GroupBalances` + fold + breakdown + facade shim + cross-group adapt
`group_balance_provider.dart` per D2/D5/D8/D9. RED-first within the step: add D12 group-fold bucket tests (mixed event, settlement-own-bucket, per-bucket conservation) to `group_balance_provider_test.dart`, watch them fail to compile, implement, then mechanical/semantic edits to that file + `cross_group_balance_test`, `cross_group_currency_buckets_test`, `home_balance_once_104_test`, `home_balance_partial_244_test`, `home_group_balance_provider_test`, `active_journeys_provider_test`, `profile_stats_provider_test` (+ `profile_stats_provider.dart` map-merge, D11). Run `flutter test test/unit/` → PASS.

### Task 4: Parity tests — interim statements
`delete_group_balance_parity_test.dart` + `balance_aggregate_parity_test.dart` per D12 (sole-bucket indexing + top-of-group comment pinning the interim single-currency parity contract). Run both → PASS (values must be UNCHANGED — any value drift is a bucketing bug, stop and investigate).

### Task 5: Ledger surfaces
`ledger_view_provider.dart` (D6) → `ledger_screen.dart` + `ledger_hero_block.dart` caption (D11) → `event_command_center.dart` (D11). Edit `ledger_view_provider_test` (untyped `.balances` reads), `event_command_center_test`, ledger widget tests. Run `flutter test test/features/ledger/ test/features/events/` → PASS.

### Task 6: Settle-up surfaces (OUTBOUND — most care)
`settle_up_page_body.dart` `SettleBucket` + sections + `onRecord` currency (D7); `settle_up_screen.dart` + `group_settle_up_screen.dart` per-bucket build + bucket-currency writes. RED-first: widget test asserting the recorded settlement write carries the BUCKET currency (mock service, two-bucket fixture → record on AED section → `addSettlement(currency: 'AED')`). Then single-bucket mechanical edits (`group_settle_up_screen_test` etc.). Run `flutter test test/features/groups/ test/features/ledger/` → PASS. Verify `group_settle_up_screen_same_name_test` stays green WITHOUT edits (the end-to-end smoke).

### Task 7: Gates + detail + remaining widget tests
`group_danger_section.dart`, `group_members_section.dart`, `group_detail_screen.dart` (D10/D11) + D12 test 7 (false-block regression) + members-card zero-money row test. Then the remaining mechanical widget-test fixture wraps (home/*, groups/* per inventory). Run `flutter test` (FULL) → PASS.

### Task 8: Final verification + ship
1. `flutter analyze` → clean. 2. `flutter test` → all green. 3. Re-grep for stragglers: `grep -rn "calculateTotalExpenses\b" lib/ test/` (old symbol gone), `grep -rn "\.balances\.where\|\.balances\.length\|\.balances\.any\|\.balances\.isEmpty" lib/` (no flat-list reads on bucketed types survive), `grep -rn "totalSpent" lib/` (no scalar uses). 4. PR: `Spec: docs/plans/2026-06-12-382-pr1-client-bucketing.md`, `Refs #382` (in the COMMIT body too — partial epic delivery), RED evidence pasted. 5. `/automerge` Gate-category path. 6. Comment on #382: PR-1 up; deviations from the draft ladder — perEventBreakdown kept flat (D5 rationale), settle writes carry bucket currency (D7).
