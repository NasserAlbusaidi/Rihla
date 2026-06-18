# #570 — Home hero: degrade a single unreadable group to per-group partial

**Date:** 2026-06-18 · **Base:** `main` @ `e97933b2` · **Issue:** #570 (P2, qa, bug)
**Category:** Gate (money-display / cross-group balance aggregation)

## Problem

`crossGroupHomeBalanceProvider` (`lib/features/groups/providers/group_balance_provider.dart:919-973`)
is the cross-group fold the home `BalanceHeroCard` consumes. It iterates the
user's groups and, for each, `ref.watch`es the per-group facade
`homeGroupBalanceProvider(group.id)`. At lines **947-952** a *single* group in
error state short-circuits the whole fold:

```dart
if (balanceAsync.hasError && !balanceAsync.hasValue) {
  return AsyncValue.error(balanceAsync.error!, balanceAsync.stackTrace!);
}
```

→ the hero renders `_ErrorCard` ("Balance unavailable") even when every *other*
group read fine. Real exposure (QA B6): right after leaving / being removed from
a group, that one group's subcollection read transiently `permission-denied`s
(cache lag before the `memberIds arrayContains uid` query re-syncs) → the whole
home balance blanks until it recovers. The number is never *wrong* (loud-safe),
but blanking an otherwise-correct multi-group balance is poor UX.

The asymmetry to close: line 957 already ORs in the **per-event** `partial` flag
(the #244 result — a failed *event* inside a group drops that event, sets
`partial`, and the hero shows the number + an "incomplete" notice). A failed
**group** is not afforded the same treatment — it hard-errors the aggregate.

## Fix (provider-only — no widget change)

Mirror the #244 per-event OR-drop at the **group** level in
`crossGroupHomeBalanceProvider`. On `balanceAsync.hasError && !balanceAsync.hasValue`:
drop that group from the fold, set `partial = true`, capture the error once (for
the all-fail guard below), and `continue` — instead of returning `AsyncValue.error`.

```dart
var partial = false;
var dropped = 0;
Object? firstError;
StackTrace? firstStack;
for (final group in groups) {
  final balanceAsync = ref.watch(homeGroupBalanceProvider(group.id));
  if (balanceAsync.hasError && !balanceAsync.hasValue) {
    partial = true;
    dropped++;
    firstError ??= balanceAsync.error;
    firstStack ??= balanceAsync.stackTrace;
    continue;                              // drop the unreadable group
  }
  if (balanceAsync.isLoading && !balanceAsync.hasValue) {
    return const AsyncValue.loading();     // UNCHANGED: still-loading group → skeleton
  }
  final balance = balanceAsync.requireValue;
  partial = partial || balance.partial;
  for (final entry in balance.userNet.entries) {
    _accumulateBucket(byCurrencyMap, entry.key, entry.value);
  }
}

// Total blackout guard: if EVERY group was unreadable, stay loud-safe — showing a
// zero "all settled · may be incomplete" hero would be a false negative. Only
// degrade to partial when at least one group's balance survived.
if (groups.isNotEmpty && dropped == groups.length) {
  return AsyncValue.error(firstError!, firstStack ?? StackTrace.current);
}

return AsyncValue.data((
  balance: (byCurrency: _sortedCurrencyBuckets(byCurrencyMap), groupCount: groups.length, isLoading: false),
  partial: partial,
));
```

Notes:
- **LOADING semantics unchanged** (lines 953-954): a group still loading keeps the
  whole hero on the skeleton (never a premature partial-zero). Only the *error*
  branch changes. A group that is BOTH loading-then-error resolves to error on a
  later frame; on the loading frame the hero shows the skeleton — correct.
- **`groupCount` stays `groups.length`** (the user's true group count), not the
  surviving count — the caption/legend semantics don't change, only the summed
  buckets drop the unreadable group's contribution. (Confirm no consumer divides
  by or asserts groupCount == number-of-summed-groups.)
- **Total-blackout guard** keeps the existing loud-safe behavior for the
  degenerate case (no readable data at all), so the fix only *adds* the
  partial-drop for the realistic 1-of-N case. `userGroupsProvider` itself erroring
  is still handled upstream (lines 937-938) and is untouched.
- **No widget change.** `balance_hero_card.dart` already threads `result.partial`
  into `_LoadedCard` (line 44) which renders `_IncompleteNotice`
  (`HomeKeys.balanceIncompleteNotice`, l10n `homeBalanceIncompleteNotice` —
  "Some data couldn't load — balance may be incomplete") for any `partial: true`.
- Update the provider docstring (lines 911-918) — the "ERROR if any group's source
  hard-errors" contract becomes "ERROR only if EVERY group hard-errors; otherwise
  drop the unreadable group(s) and flag `partial`."

## Why not the #366 aggregate / once-path facade

The blanking is one level UP from the facade's #366-aggregate-vs-#104-once-path
choice — it's the cross-group fan-out. A single group's facade reaches error
state in practice via the **#104 once-path** coarse list-read failure
(`groupBalancesOnceProvider` un-caught coarse awaits, events/members/group-settlements)
surfacing through `homeGroupBalanceProvider`'s `.whenData`. We do not touch the
facade, the once-path, or the aggregate read — only how the OUTER fold treats a
group that arrives in error. The within-group "coarse failure is too coarse to
silently drop" contract (#244) is unchanged; #570 is the strictly-outer layer.

## Tests (RED first)

Mirror `test/unit/home_balance_partial_244_test.dart`:
1. **RED regression:** two groups `g1` (healthy, net -10 in OMR) + `g2` (error).
   Override `g2`'s source to error (override `homeGroupBalanceProvider('g2')` or
   `groupBalancesOnceProvider('g2')` to error). Assert *currently* the cross-group
   result is `AsyncValue.error` (the bug). After the fix: `result.partial == true`
   and `result.balance.byCurrency` sums **g1 only** (-10 OMR), no error.
2. **All-fail guard:** both `g1` and `g2` error → result is still `AsyncValue.error`
   (loud-safe preserved).
3. **All-healthy unchanged:** no group errors → `partial == false`, both summed.
4. **Loading unchanged:** one group loading → whole result `loading` (skeleton).
5. Widget side already covered by `balance_hero_card_partial_test.dart` (notice
   renders for any `partial: true`) — no change needed; optionally add a hero test
   asserting number+notice when one group errors (reusing the partial override).

## Acceptance

- [ ] One unreadable group among ≥2 → hero shows surviving-group total + incomplete notice (not blank).
- [ ] Every group unreadable → hero still shows "Balance unavailable" (loud-safe).
- [ ] No group unreadable → no behavior change (`partial == false`).
- [ ] Loading group → skeleton (unchanged).
- [ ] RED test written first, fails for the right reason, then GREEN.
- [ ] `flutter analyze` clean; `group_balance_provider`/home-balance suites green.
