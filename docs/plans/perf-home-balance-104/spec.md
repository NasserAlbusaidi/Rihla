# Spec — #104 lazy / one-shot home balance aggregation

Issue: #104 (P2, perf, tech-debt). Spec rev 2 (post Gate Round 1).

**Risk surface:** `BalanceCalculator` / money math (`groupBalancesProvider` aggregation, `crossGroupBalanceProvider`), home routing-adjacent providers, a read-path-only change to how the home dashboard sources balances. **Gate required before implementation.**

> ⚠️ This change is money-adjacent. The home headline net and the in-group settle-up screen MUST stay numerically identical — settle-up is OUTBOUND (it directs real settlement writes). The single load-bearing safety constraint of this spec is: **the one-shot home path and the live in-group path call the exact same reduction code.** Everything else is plumbing.

All `lib/` paths below are dir-qualified. Note the reducer lives in **`lib/features/groups/providers/group_balance_provider.dart`** (the `groups/` feature, NOT `ledger/`); `lib/features/ledger/providers/expense_provider.dart` holds only the leaf streams.

---

## 1. Concern (verified, supersedes the issue body)

The issue body prescribes adding `.autoDispose` to the leaf families `eventExpensesProvider`/`eventSettlementsProvider`. That fix is **inert** and has been empirically disproven (issue comment 2026-06-03; PR #232 pins the pitfall in CLAUDE.md). Restated so this spec stands alone:

The home dashboard is permanently mounted (`BottomNavShell` stacks tabs via `AnimatedOpacity`+`IgnorePointer`; home→group is `context.push`, which retains home offstage). From that always-mounted tree, **`crossGroupBalanceProvider`** (a plain `Provider`, watched by `BalanceHeroCard`) loops **every** group and `ref.watch`es `groupBalancesProvider(gid)`, which in turn `ref.watch`es `eventExpensesProvider`/`eventSettlementsProvider` for **every event**. Because a provider with a live watcher never schedules disposal, this pins **O(G×E)** Firestore `.snapshots()` listeners open for the whole session, established eagerly at home load. `.autoDispose` on the leaves cannot fire while these roots hold them.

There is **no materialized per-group balance** — the headline net is computed by reading every event's expenses + settlements and reducing on-device. So the read volume at home-load is inherently O(G×E) **regardless of fix**. The leak is purely that the **per-event expense/settlement reads are permanent live listeners** rather than one-shot reads.

**The fix:** keep the cheap **O(G) list streams live** (user groups, per-group events, per-group members, per-group settlements) and convert only the **O(G×E) per-event expense/settlement reads** to one-shot `.get()` on the home path. This removes the O(G×E) permanent-listener leak, preserves liveness on everything the list streams already cover, and — because the list streams are reused as-is — needs **no** new one-shot read for groups/events/members/group-settlements (and so cannot reintroduce their in-memory filter/sort logic differently).

---

## 2. Verification Report

Checked against `main`. Commands reproducible; the PR branch re-cites.

| # | Claim | Path / command | Result |
|---|---|---|---|
| 1 | Leaf expense stream is a plain `StreamProvider.family`, no `.autoDispose` | `lib/features/ledger/providers/expense_provider.dart:48-52` | Confirmed plain. |
| 2 | Leaf settlement stream likewise | `lib/features/ledger/providers/expense_provider.dart:57-61` | Confirmed plain. |
| 3 | No `autoDispose`/`keepAlive` anywhere in lib | `grep -rn "autoDispose\|keepAlive" lib/` | Zero hits. |
| 4 | `groupBalancesProvider` is a plain `Provider.family`; the `ref.watch` fan-out loop over events is **lines 116-159** | `lib/features/groups/providers/group_balance_provider.dart:112,141-144` | Confirmed; loop at `:141-144` watches `eventExpensesProvider`/`eventSettlementsProvider`. |
| 5 | **Root 1 — unconditional O(G×E) pin:** `crossGroupBalanceProvider` loops ALL groups | `lib/features/groups/providers/group_balance_provider.dart:476,513-514`; watched by `lib/features/home/widgets/balance_hero_card.dart:25`; hero mounted at `lib/features/home/screens/home_screen.dart:101` | Confirmed. No active-window filter → every group's every event. Dominant offender. |
| 6 | **Root 2 — partially mitigated:** `activeJourneysProvider` only watches `groupBalancesProvider(gid)` for groups with ≥1 active event | `lib/features/home/providers/active_journeys_provider.dart:140-150` (`if (activeEvents.isEmpty) continue;` at `:148`) | Confirmed; also watches the LIVE `groupEventsProvider(gid)` at `:141` for the active-window filter. |
| 7 | **Root 3:** `_GroupRow` watches `groupBalancesProvider(gid)` per visible row | `lib/features/home/screens/home_screen.dart:585` | Confirmed; `SliverList` defaults `addAutomaticKeepAlives: true`. |
| 8 | Non-home consumers that MUST stay LIVE on `groupBalancesProvider` | `group_detail_screen.dart:91`, `group_settle_up_screen.dart:86,178` (**OUTBOUND**), `group_members_section.dart:151` (`ref.read`), `group_danger_section.dart:183,203,264` (`ref.read`), `profile_stats_provider.dart:63` | Confirmed. Untouched by this spec. |
| 9 | Leaf query: `watchExpenses` = `where(isDeleted=false).orderBy(createdAt desc).snapshots()`, no `.limit()` | `lib/features/ledger/services/expense_service.dart:34-46` | One-shot equivalent = same query `.get()`. |
| 10 | Leaf query: `watchSettlements` = `where(isDeleted=false).orderBy(settledAt desc).snapshots()` | `lib/features/ledger/services/settlement_service.dart:33-46` | Same. |
| 11 | **List streams kept live (NOT converted):** `userGroupsProvider` (in-memory `!isDeleted` filter, #190), `groupEventsProvider` (client null-date sort, D-25), `groupMembersProvider`, `groupSettlementsProvider` | `group_provider.dart:370-382,385-397,427-433,438-443`; `event_service.dart:34-54`; `group_balance_provider.dart:40-44` | Each is O(G) total, not the leak. Reused as-is → their filter/sort logic is **not** re-implemented, so divergence traps A/B cannot occur. |
| 12 | Reducer body to extract is **lines 161-360**, NOT 138-360 | `group_balance_provider.dart:138-159` is the impure `ref.watch` loop; `:161-164` builds `allSettlements`; `:166-360` is pure reduction | Confirmed. Extracting from 138 would drag `ref.watch` into a pure fn (won't compile, defeats the keystone). |
| 13 | The pure region still references `groupSettlementsAsync` twice — must become a param | `group_balance_provider.dart:163` (`...groupSettlementsAsync.valueOrNull ?? []` in `allSettlements`) and `:286` (`final groupSettlements = groupSettlementsAsync.valueOrNull ?? const []`) | Both swap to the `groupSettlements` function param. |
| 14 | `crossGroupBalanceProvider` owed/owes = **sign-split of each group's net scalar**, not summed slices | `group_balance_provider.dart:521-531`: takes user's `UserBalance.netBalance` per group, `if groupNet>0: owedToUser+=groupNet; elif <0: userOwes+=groupNet.abs()` | `netBalance` (`:328`) = `eventNet + groupSettlementNet` (settlements folded). Summing `totalPaid` slices would drop settlements (principle 6). Spelled as code in §5. |
| 15 | **All 5 money-write callsites (no choke-point — screens call services directly)** | `add_expense_screen.dart:52` (addExpense), `edit_expense_screen.dart:98` (updateExpense), `edit_expense_screen.dart:149` (deleteExpense), `settle_up_screen.dart:294` (addSettlement, event), `group_settle_up_screen.dart:348` (addGroupSettlement, group) | Confirmed by grep. Liveness contract in §5 enumerates which bump the revision. |
| 16 | Group settlements are read by the LIVE `groupSettlementsProvider` (kept live, claim 11) | `group_balance_provider.dart:134` | ∴ `addGroupSettlement` (`group_settle_up_screen.dart:348`) needs **no** revision bump — the live stream surfaces it. Only the 4 event-level writes bump. |
| 17 | Home pull-to-refresh already invalidates `userGroupsProvider` | `home_screen.dart:91-93` | Extend to invalidate the once-aggregates. |
| 18 | Existing money-math regression tests | `test/unit/balance_calculations_test.dart`, `cross_group_balance_test.dart`, `group_balance_provider_test.dart`, `delete_group_balance_parity_test.dart` | Phase 0 extraction keeps these green unchanged. |
| 19 | `.get()` default `GetOptions` serves the cache **including pending local writes** (`hasPendingWrites`) when offline | Firestore SDK semantics | A user's own just-recorded offline write is visible on the one-shot path. |
| 20 | `crossGroupActivityProvider` (also on home) watches only `groupActivityProvider`, not balance leaves | `lib/features/home/providers/dashboard_providers.dart:50` | Correctly out of scope. |

---

## 3. Considered alternatives (decision record)

- **(A) One-shot per-event reads behind live list streams — CHOSEN.** Kills the O(G×E) listener leak; keeps O(G) list liveness; identical read count at load; identical math via the shared reducer; no re-implementation of group/event filter/sort.
- **(B) Windowed/lazy streaming (only visible rows).** Rejected: the hero headline (dominant offender) needs ALL groups; cannot window without making the headline wrong.
- **(C) Documented won't-fix + `.limit()` cap.** Defensible (fixed baseline, insider-only, cache-served deltas, median solo user pays negligibly). Fallback if the Gate finds (A)'s liveness contract too invasive for a P2.
- **(D) Server-materialized `balanceSnapshot` (Function trigger).** The real long-term fix (home → O(G) doc reads). Out of scope: major backend change, eventual-consistency surface, no such triggers exist. Documented as the escalation if home balance becomes a measured bottleneck.

---

## 4. Required behavior

1. After home first render, the count of live `eventExpenses`/`eventSettlements` Firestore listeners attributable to the home tree returns toward baseline (≈0 between refreshes) instead of holding at O(G×E). Live listeners remaining from the home tree are O(G) (the list streams), not O(G×E).
2. The home headline net (`crossGroupBalanceOnceProvider`), per-group-row net, and active-journeys per-event balances are **numerically identical** to today's values for the same data.
3. In-group screens (group detail, **settle-up**, members, danger, profile stats) remain on the **live** `groupBalancesProvider` — unchanged.
4. Liveness on home (§5): a balance-changing money write the user makes, then returning to home, shows fresh numbers; pull-to-refresh refreshes; group/event/member/group-settlement **list** changes refresh automatically via the retained live streams.
5. Soft-deleted groups stay hidden and null-date event ordering preserved — **inherited unchanged** from the retained live list streams (not re-implemented).
6. `flutter analyze` clean; full suite green; 80% coverage gate holds.

---

## 5. Design

### Phase 0 — Extract the pure reducer (no behavior change; the safety keystone)

In `lib/features/groups/providers/group_balance_provider.dart`, extract **lines 161-360** into a pure top-level function:

```dart
GroupBalances computeGroupBalances({
  required List<Event> events,
  required List<GroupMember> members,
  required List<Expense> allExpenses,            // flattened across events
  required List<Settlement> allEventSettlements, // flattened across events
  required List<Settlement> groupSettlements,
});
```

- The function body is the current `:161-360`, with the two `groupSettlementsAsync.valueOrNull` reads (`:163`, `:286`) replaced by the `groupSettlements` param. It rebuilds `allSettlements = [...allEventSettlements, ...groupSettlements]` internally (current `:161-164`).
- `groupBalancesProvider` keeps its `ref.watch` block + per-event assembly (`:116-159`) and then `return AsyncValue.data(computeGroupBalances(events: events, members: members, allExpenses: allExpenses, allEventSettlements: allEventSettlements, groupSettlements: groupSettlementsAsync.valueOrNull ?? const []))`.
- **No math moves, only relocates.** Proven by the four balance tests (claim 18) staying green unmodified, plus a new test asserting `computeGroupBalances(fixture)` equals the value `groupBalancesProvider` produces for the same fixture.

### Phase 1 — One-shot per-event service reads (the only new reads)

Add two methods, each mirroring its `watch*` sibling's query exactly but with `.get()`:

- `ExpenseService.getExpenses(groupId, eventId) → Future<List<Expense>>` (mirror `expense_service.dart:34-46`).
- `SettlementService.getSettlements(groupId, eventId) → Future<List<Settlement>>` (mirror `settlement_service.dart:33-46`).

No `getUserGroups`/`getMembers`/`getGroupEvents`/`getGroupSettlements` — those stay on their live streams.

### Phase 2 — One-shot home aggregation providers (call the SAME reducer)

```dart
// liveness lever (Phase 3)
final ledgerRevisionProvider = StateProvider<int>((_) => 0);

final groupBalancesOnceProvider =
    FutureProvider.autoDispose.family<GroupBalances, String>((ref, groupId) async {
  // LIST inputs stay LIVE (O(G), not the leak) — auto-refresh on list change,
  // and reuse the existing isDeleted filter (#190) / null-date sort (D-25).
  final events  = await _awaitList(ref, groupEventsProvider(groupId));
  final members = await _awaitList(ref, groupMembersProvider(groupId));
  final groupSettlements =
      await _awaitList(ref, groupSettlementsProvider(groupId));
  ref.watch(ledgerRevisionProvider); // re-run when event-level money content changes

  final expenseSvc = ref.read(expenseServiceProvider);
  final settlementSvc = ref.read(settlementServiceProvider);
  final allExpenses = <Expense>[]; final allEventSettlements = <Settlement>[];
  for (final e in events) {
    allExpenses.addAll(await expenseSvc.getExpenses(groupId, e.id));        // ONE-SHOT
    allEventSettlements.addAll(await settlementSvc.getSettlements(groupId, e.id)); // ONE-SHOT
  }
  return computeGroupBalances(events: events, members: members,
      allExpenses: allExpenses, allEventSettlements: allEventSettlements,
      groupSettlements: groupSettlements);
});
```

`_awaitList` = `ref.watch(p.future)` (re-runs the future provider when the watched stream emits a new list). Implementer note: `ref.watch(streamProvider.future)` is the idiomatic "await the current value, re-run on emit" form.

`crossGroupBalanceOnceProvider` — owed/owes spelled as code (claim 14), mirroring `crossGroupBalanceProvider:508-548` exactly:

```dart
final crossGroupBalanceOnceProvider =
    FutureProvider.autoDispose<CrossGroupBalance>((ref) async {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) return (net: Decimal.zero, owedToUser: Decimal.zero,
      userOwes: Decimal.zero, groupCount: 0, isLoading: false);
  final groups = await ref.watch(userGroupsProvider.future); // LIVE list
  var net = Decimal.zero, owedToUser = Decimal.zero, userOwes = Decimal.zero;
  for (final g in groups) {
    final gb = await ref.watch(groupBalancesOnceProvider(g.id).future);
    final groupNet = gb.balances
        .where((b) => b.participantId == uid).firstOrNull?.netBalance ?? Decimal.zero;
    net += groupNet;
    if (groupNet > Decimal.zero) { owedToUser += groupNet; }
    else if (groupNet < Decimal.zero) { userOwes += groupNet.abs(); }
  }
  return (net: net, owedToUser: owedToUser, userOwes: userOwes,
      groupCount: groups.length, isLoading: false);
});
```

Repoint the three home consumers:
- `BalanceHeroCard` (`balance_hero_card.dart:25`) → `crossGroupBalanceOnceProvider`.
- `_GroupRow` (`home_screen.dart:585`) → `groupBalancesOnceProvider`.
- `activeJourneysProvider` (`active_journeys_provider.dart`) → becomes async, consuming `groupBalancesOnceProvider(gid).future` for the `perEventBreakdown`, **while still `ref.watch`ing the live `groupEventsProvider(gid)` (`:141`)** for the active-window filter — preserve BOTH inputs (Gate P2-1).

`crossGroupBalanceProvider` / `groupBalancesProvider` (streaming) remain **untouched** (claim 8).

### Phase 3 — Liveness contract (exhaustive, by callsite)

Event-level expense/settlement **content** changes are invisible to the one-shot path (no listener), so each balance-changing event-level write bumps `ledgerRevisionProvider` immediately after its successful `await`. The complete, enumerated set (claim 15/16):

| Callsite | Write | Bumps revision? |
|---|---|---|
| `lib/features/ledger/screens/add_expense_screen.dart:52` | `addExpense` | **Yes** |
| `lib/features/ledger/screens/edit_expense_screen.dart:98` | `updateExpense` | **Yes** |
| `lib/features/ledger/screens/edit_expense_screen.dart:149` | `deleteExpense` (soft-delete) | **Yes** |
| `lib/features/ledger/screens/settle_up_screen.dart:294` | `addSettlement` (event) | **Yes** |
| `lib/features/groups/screens/group_settle_up_screen.dart:348` | `addGroupSettlement` (group) | **No** — read by the live `groupSettlementsProvider` (claim 16) |

Bump form: `ref.read(ledgerRevisionProvider.notifier).state++` after the `await`. Pull-to-refresh (`home_screen.dart:91`) also `ref.invalidate(crossGroupBalanceOnceProvider)`.

**Maintenance guard (Gate P1-3):** the event-level money-write surface is exactly these four methods (`addExpense`/`updateExpense`/`deleteExpense`/`addSettlement`; settlements are append-only so no settlement update/delete exists). A regression test pins each of the four callsites to a revision bump, and a CLAUDE.md Pitfalls line records "any new event-level expense/settlement write must bump `ledgerRevisionProvider` or the home balance goes stale (money-wrong for settle-up)."

---

## 6. Test plan

- **Phase 0 parity:** the four existing balance tests stay green unmodified; add `computeGroupBalances(fixture) == groupBalancesProvider(fixture)` for a multi-group/multi-event/with-settlements fixture.
- **Listener-count regression (the issue's "Done when"):** `fakeAsync` + `ProviderContainer`; instrument `getExpenses`/`watchExpenses` create/cancel counters. After the home roots resolve via the once-providers, assert **no** live `eventExpenses`/`eventSettlements` listener remains attributable to the home roots (the streaming path leaves O(G×E) open). Mirror the 2026-06-03 empirical harness.
- **Numerical-equality:** `crossGroupBalanceOnceProvider` value == `crossGroupBalanceProvider` value; per-group `groupBalancesOnceProvider` == `groupBalancesProvider` — including a fixture where settlements flip a group's owed/owes sign (orthogonal axis: settlements, Gate principle 7).
- **Liveness per callsite:** four tests, one per event-level write callsite (claim 15), asserting the bump recomputes `crossGroupBalanceOnceProvider`. One test asserting `addGroupSettlement` refreshes via the live `groupSettlementsProvider` **without** a bump.
- **List-liveness:** adding/removing an event refreshes `groupBalancesOnceProvider` via the live `groupEventsProvider` (no bump needed — Gate P2-2 decided: watch the live list).
- `flutter analyze` clean; full `flutter test`; coverage ≥80%.

---

## 7. Out of scope

- `BalanceCalculator` internals, rounding remainder, `MoneySerializer` — untouched.
- In-group screen liveness — unchanged.
- Server-materialized snapshots (alternative D) — separate future issue.
- #113 (lazy-build unvisited *tabs*) — distinct; does not touch the home/Groups balance fan-out.

---

## Gate Round 1 (4 P1 / 2 P2 / 1 P3) — resolutions

- **[P1] wrong reducer file path** → all paths dir-qualified; reducer is `lib/features/groups/providers/group_balance_provider.dart` (claim header + §5).
- **[P1] reducer not pure over 138-360** → extraction range corrected to **161-360**; provider keeps the `ref.watch` loop `:116-159`; the two `groupSettlementsAsync` reads (`:163`,`:286`) become the param (claim 12/13, §5 Phase 0).
- **[P1] liveness misses update/soft-delete writes** → all five callsites enumerated in a table; the four event-level writes bump, group-settlement covered by the live stream; per-callsite tests + CLAUDE.md guard (claim 15/16, §5 Phase 3).
- **[P1] owed/owes decomposition as prose** → spelled as code: sign-split of each group's net scalar (claim 14, §5 `crossGroupBalanceOnceProvider`).
- **[P2] activeJourneys async must preserve both inputs** → §5 Phase 2 keeps the live `groupEventsProvider(gid)` watch alongside the async `groupBalancesOnceProvider`.
- **[P2] "open question" on watching the event list is load-bearing** → resolved to a **decision**: list streams stay live and are watched (claim 11, §5 Phase 2). This is the redesign that also removed traps A/B and 4 service methods.
- **[P3] table line-citations off by file move** → re-cited with dir qualification throughout §2.

## Gate Round 2 (0 P1 / 3 P2 / 1 P3) — PASSED (stop condition met)

Fresh-context reviewer confirmed: keystone holds (one-shot + live paths call identical `computeGroupBalances`); extraction boundary `161-360` exact (nothing in that range touches `ref` beyond the two `groupSettlementsAsync` reads at `:163`/`:286`); owed/owes sign-split matches `crossGroupBalanceProvider:508-531`; write-callsite table exhaustive; reviewer's own settlement-sign-flip worked example produced identical net on both paths. No structural change required. P2/P3 acknowledgements folded in:

- **[P2] dropped `anyLoading` partial branch** → final emitted `net`/`owedToUser`/`userOwes` are numerically identical to the live provider; only intermediate-frame timing differs, and no consumer reads `CrossGroupBalance.isLoading` (`balance_hero_card.dart:27-31,44-47` renders the spinner off `AsyncValue.loading`, never the field). The hardcoded `isLoading: false` is correct — **do not** reintroduce a partial branch expecting a consumer.
- **[P2] `.future` liveness is unprecedented in-repo** → confirmed correct for Riverpod 2.6.1 (`pubspec.lock:442`), but there is no existing `ref.watch(streamProvider.future)` or `FutureProvider.autoDispose.family` in `lib/`. The §6 **list-liveness test is therefore load-bearing, not optional** — it must assert an event add/remove on the live `groupEventsProvider` recomputes `groupBalancesOnceProvider` *without* a revision bump. Do not cut it.
- **[P2] keep the listener-count assertion scoped to event-leaf listeners** → the O(G) group/event/member/group-settlement *list* streams legitimately stay live (and on-screen `_GroupRow`s keep them alive under `SliverList` default `addAutomaticKeepAlives: true`, `home_screen.dart:136-150`). Required-behavior #1 is about `eventExpenses`/`eventSettlements` leaf listeners specifically — assert on those, not total listener count.
- **[P3] update `BalanceHeroCard` doc comment** (`balance_hero_card.dart:17,42-43`, the "#110 fan-out" note) when repointing to `crossGroupBalanceOnceProvider` so it doesn't lie.

**Implementation-ready.** Build order: Phase 0 (extract reducer, prove parity) → Phase 1 (`getExpenses`/`getSettlements`) → Phase 2 (once-providers + repoint) → Phase 3 (revision bumps). RED-first on the listener-count regression and the parity test.
