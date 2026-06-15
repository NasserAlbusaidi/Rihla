# #517 — Profile tab reopens the #104 O(G×E) live-listener leak

**Date:** 2026-06-15 · **Branch:** `fix/517-profile-listener-leak` · baseline `origin/main` `7e1d268f`
**Severity:** P2 (performance) · **Scope:** client-only, 1 production line of substance · **Gate:** money-display-adjacent → run the fresh-context Opus Gate (faithful to the #518 treatment).

## Problem (verified against live code, not the issue text)

`profileStatsProvider` (`lib/features/settings/providers/profile_stats_provider.dart:97`) watches the **live** `groupBalancesProvider(group.id)` for every group. `groupBalancesProvider` (`group_balance_provider.dart:121`, a non-autoDispose `Provider.family`) `ref.watch`es `eventExpensesProvider` + `eventSettlementsProvider` — both live `StreamProvider.family` — for **every event of every group** (`:152-153`).

`BottomNavShell` lazy-builds the Profile tab on first visit and keeps it mounted forever (`bottom_nav_shell.dart` — opacity/IgnorePointer toggle, not a route swap). So the first Profile open opens a permanent per-event Firestore snapshot listener for every event in every group — the exact `O(G×E)` leak #104/#233 eliminated for the **home** dashboard but left on Profile. (Issue cited `lib/features/profile/...`; the real path is `lib/features/settings/...` — verified.)

## Fix

Route `profileStatsProvider` off the live provider onto the one-shot `groupBalancesOnceProvider` — the identical re-route #233 applied to home. `groupBalancesOnceProvider` (`group_balance_provider.dart:754`, `FutureProvider.autoDispose.family<GroupBalancesOnce,String>`) reads per-event expenses/settlements via one-shot `.get()` (`getExpenses`/`getSettlements`), holding **zero** per-event live listeners; its list inputs (events/members/group-settlements) stay live but are O(G), not the O(G×E) leak.

`profileStatsProvider` uses `groupBalancesProvider` for **exactly one field**: `balances.totalSpent` (`:107`). `eventCount` already comes from a separate `groupEventsProvider` watch (`:89`), untouched. So the swap is:

```dart
// :97
final balancesAsync = ref.watch(groupBalancesOnceProvider(group.id));
// :101-102 — unwrap the GroupBalancesOnce wrapper
final once = balancesAsync.valueOrNull;
final balances = once?.balances;
// :107 loop body unchanged — balances.totalSpent
```

`GroupBalancesOnce = ({GroupBalances balances, Set<String> failedEventIds})`; `.balances.totalSpent` is the same `Map<String,Decimal>` produced by the same `computeGroupBalances` the live path calls (`totalSpent = BalanceCalculator.calculateTotalExpensesByCurrency(allExpenses)`), so the displayed number is byte-identical — only the read mechanism (one-shot vs snapshot) differs.

### Why one-shot and not the #366 aggregate
The `homeGroupBalanceProvider` aggregate facade exposes only **net** balances (`GroupBalanceAggregate.netFor`); the aggregate doc carries **no** `totalSpent`. Profile needs **gross** per-currency spend. Reading Profile's spend from the server aggregate would require persisting `totalSpent` in `balanceAggregator.ts` + the aggregate model — a backend change + deploy. That is the issue's *secondary* concern ("two code paths for the same money") and is a **non-goal here**; this PR closes the *headline* leak only. (Follow-up note in the issue.)

## Verification principles (run while writing)

1. **Callsite classification** — `profileStatsProvider` is INBOUND (display only): it feeds the Profile stats card, never a write. `totalSpent` is gross-spend display. No OUTBOUND surface touched. The in-group OUTBOUND consumers of the live `groupBalancesProvider` (settle-up, danger-section) are **not** changed.
2. **Every concrete claim vs code** — path corrected to `lib/features/settings/`; `:97` watch, `:107` sole field use, `groupBalancesOnceProvider` at `:754`, aggregate has no `totalSpent` (only `netFor`) — all grepped/read this session.
3. **One read-path per write-path** — no write-path changes. Read-path after change: Profile card reads `spentByCurrency` ← `totalSpent` ← `computeGroupBalances` (one-shot inputs). Same function, same output.
4. **Fields from the type** — `GroupBalancesOnce{balances, failedEventIds}`; `GroupBalances{balances, totalSpent, eventCount, perEventBreakdown, memberNames, memberRawNames}`. Only `balances.totalSpent` consumed.
5. **Data contract** — `ref.watch(groupBalancesOnceProvider(gid))` returns `AsyncValue<GroupBalancesOnce>`; `.valueOrNull?.balances?.totalSpent` → `Map<String,Decimal>`. Loading handled by the existing `isLoading && !hasValue` branch (FutureProvider emits loading-first, unlike the live Provider — covered by the existing anyLoading logic).
6. **Arithmetic decomposition** — N/A (no aggregate reconstruction); `totalSpent` is computed whole per group, summed into per-currency buckets exactly as today.
7. **Adversarial / orthogonal axis** — fix is on the *listener-lifecycle* axis; the regression test must exercise the *money* axis too (correct per-currency totalSpent on the one-shot path), and the *identity/partial* axis is preserved (one-shot drops a failed event into `failedEventIds`, mirroring the live `hasError && !hasValue` skip — Profile's spend was already a partial-on-error sum; no behavior change, Profile has never shown a partial affordance).

## Tests (RED → GREEN)

**New — `test/unit/profile_stats_listener_leak_517_test.dart`** (mirrors `home_balance_once_104_test.dart` counting fakes):
- RED: subscribe `profileStatsProvider`; assert `expFake.activeWatchListeners == 0` and `expFake.getCount > 0`. Fails today (live path → `activeWatchListeners > 0`, `getCount == 0`).
- CONTRAST: keep the live `groupBalancesProvider(gid)` subscribed → `activeWatchListeners > 0` (proves the assertion discriminates).
- Money axis: seed an expense, assert `spentByCurrency` has the correct per-currency total on the one-shot path.

**Migrate — `test/unit/profile_stats_provider_test.dart`**: the 2 aggregation tests override `groupBalancesProvider(gid)` with an `AsyncValue<GroupBalances>`; change to `groupBalancesOnceProvider(gid).overrideWith((ref) async => (balances: <GroupBalances>, failedEventIds: <String>{}))` and pin the chain with `container.listen(profileStatsProvider, (_, _) {})` (autoDispose once-path disposes between microtasks without a listener). The currency-bucket assertions are unchanged.

**Untouched:** `profile_screen_test.dart` / `profile_account_card_test.dart` stub `profileStatsProvider` directly; `home/widgets_test.dart`'s `groupBalancesProvider` override is vestigial (empty-groups short-circuit at `:72` — `groupBalancesProvider` still exists, so it compiles and stays unused).

## Non-goals
- Aggregate-backed Profile spend (needs server `totalSpent` persistence + deploy) — issue's secondary concern, follow-up.
- A partial-spend affordance on Profile — never existed; out of scope.
- Touching the in-group live `groupBalancesProvider` consumers (settle-up etc.) — they are not always-mounted; #104 deliberately kept the live variant for them.

## Done
`flutter analyze` clean · `flutter test test/unit/profile_stats_listener_leak_517_test.dart test/unit/profile_stats_provider_test.dart` green · regression suite green · PR with `Closes #517` (commit body too) · ship via `/automerge` (review + refute).
