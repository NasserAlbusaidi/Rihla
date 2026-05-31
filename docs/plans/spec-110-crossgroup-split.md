# Spec: #110 — fold owed/owes split into `CrossGroupBalance`

Repo: `/Users/nasseralbusaidi/Desktop/Personal/Rihla-perf` (worktree, branch off `main` @ 5dd963a).

## Goal
`balance_hero_card.dart` `_LoadedCard.build` re-walks every group's `groupBalancesProvider` (lines 47–62) to split the user's net into `owedToUser`/`userOwes` for the split bar + legend — duplicating the O(G) fan-out `crossGroupBalanceProvider` already runs (`group_balance_provider.dart:496–508`). Fold the split into the provider's existing loop; read it off the record in the widget.

## Changes

### 1. `lib/features/groups/providers/group_balance_provider.dart`
- **Typedef (`:444`):** `typedef CrossGroupBalance = ({Decimal net, Decimal owedToUser, Decimal userOwes, int groupCount, bool isLoading});`
- **Declare (near `var net = Decimal.zero;`, `:493`):** `var owedToUser = Decimal.zero; var userOwes = Decimal.zero;`
- **In the loop (`:507`)** accumulate from the SAME per-group value that feeds `net`:
  ```dart
  final groupNet = userBalance?.netBalance ?? Decimal.zero;
  net = net + groupNet;
  if (groupNet > Decimal.zero) {
    owedToUser += groupNet;
  } else if (groupNet < Decimal.zero) {
    userOwes += groupNet.abs();
  }
  ```
- **4 return sites:** uid==null (`:470`) → `owedToUser: Decimal.zero, userOwes: Decimal.zero`; groups empty (`:486`) → zeros; anyLoading&&net==0 (`:511`) → accumulated `owedToUser`/`userOwes`; final (`:517`) → accumulated.

### 2. `lib/features/home/widgets/balance_hero_card.dart`
- Delete the re-walk loop (`:47–62`); replace with `final owedToUser = balance.owedToUser; final userOwes = balance.userOwes;`
- Remove `final uid = ref.watch(currentUserIdProvider);`, `final groupsAsync = ref.watch(userGroupsProvider);`, `final groups = …`.
- Convert `_LoadedCard` ConsumerWidget → StatelessWidget (no longer uses `ref`).
- Remove `import '../../groups/providers/group_provider.dart';` (confirm nothing else in the file uses it). `flutter_riverpod` import stays (BalanceHeroCard is ConsumerWidget). `_SplitBar`/`_SplitLegend` unchanged.

### 3. Tests — add `owedToUser`/`userOwes` to EVERY `crossGroupBalanceProvider` record literal:
`balance_hero_card_test.dart` (5 literals), `home_screen_dashboard_test.dart` (`_loadedOverrides`), `home_screen_quick_actions_test.dart`, `home_screen_groups_test.dart`, `cross_group_activity_screen_test.dart`. Plus a NEW `balance_hero_card_test` case: record with `owedToUser`/`userOwes` non-zero → assert legend shows both amounts (proves split now comes from the record, not the deleted walk).

## Arithmetic invariant
`net == owedToUser − userOwes` since `Σ_g net_g = Σ_{net_g>0} net_g − Σ_{net_g<0}|net_g|`. Exact partition of the SAME `userBalance.netBalance` per group. No MoneySerializer / Firestore boundary touched; all `Decimal`.

## Behavior parity
Provider loop and old widget walk skip the identical group set (null/loading `valueOrNull` skipped in both). Early returns (uid null / empty groups) → zero split, matching the old walk over zero contributing groups.
