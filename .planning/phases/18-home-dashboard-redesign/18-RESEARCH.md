# Phase 18: Home Dashboard Redesign - Research

**Researched:** 2026-03-29
**Domain:** Flutter UI — custom scroll architecture, Riverpod provider aggregation, widget composition
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** Balance hero card at top of dashboard (below title, above quick actions) — net cross-group balance, color-coded red/green/gray
- **D-02:** Hero remains visible when all settled (gray card, "All settled up", "OMR 0.000", card does not hide)
- **D-03:** New `crossGroupBalanceProvider` aggregates `groupBalancesProvider` per-group results into a single net number
- **D-04:** Quick-action tray: 4 buttons (Add Expense, Settle Up, Invite Friend, Activity), horizontal Row below hero
- **D-05:** Add Expense + Settle Up open a group-picker bottom sheet
- **D-06:** Invite opens existing invite code flow; Activity scrolls to activity section
- **D-07:** Tray visible without scrolling on ~390px width
- **D-08:** GroupCard shows user's personal net balance (not total spent) — errorText/successText/textSecondary
- **D-09:** GroupCard keeps name + member count layout, replaces `totalSpent` with personal balance line
- **D-10:** Bottom nav shell with Groups/Activity/Chats/Profile tabs — Groups tab active
- **D-11:** Activity, Chats, Profile tabs show placeholder "Coming soon" screens
- **D-12:** Add `bottomNavBackground`, `bottomNavActiveIcon`, `bottomNavInactiveIcon` tokens to AppColorTokens
- **D-13:** Activity strip shows 5 most recent entries across all groups, merged chronologically
- **D-14:** Each activity row: avatar circle + member name + action description + group name tag + relative timestamp
- **D-15:** "RECENT ACTIVITY" overline in textMuted — DECORATIVE ONLY
- **D-16:** Weekly spending card with real Firestore expense data aggregated by day, teal bar chart
- **D-17:** Weekly spending card below activity strip; AppColors.surface background, AppColors.primary bars
- **D-18:** Loading: SkeletonLoader.dashboardHero() for hero, SkeletonLoader.groupList() for cards
- **D-19:** Empty: EmptyStateView with CTA "Create your first group"
- **D-20:** Error: OfflineBanner + EmptyStateView with "Retry" and "View Offline Data" CTAs
- **D-21:** CustomScrollView + SliverList.builder for main scroll
- **D-22:** FadeInList wraps group cards for staggered entrance
- **D-23:** TapBounce wraps all tappable cards and quick-action buttons
- **D-24:** Add `offlineBannerBackground: Color(0xFFF59E0B)` to AppColorTokens
- **D-25:** Add `bottomNavBackground`, `bottomNavActiveIcon`, `bottomNavInactiveIcon` to AppColorTokens

### Claude's Discretion

- Chart rendering approach for weekly spending (custom paint, fl_chart package, or simple Container bars)
- Cross-group balance aggregation provider implementation strategy
- Exact skeleton composition for the balance hero section
- Activity row widget internal layout details
- Whether to use SliverAppBar for the title or keep it in a fixed header

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope

</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| NAV-01 | Home screen shows a single-scroll dashboard with balance hero, inline group cards, quick-action tray, and recent activity | Confirmed: CustomScrollView + SliverList.builder is the correct Flutter pattern; all required widgets are designed and ready |
| NAV-02 | User can see net cross-group balance (color-coded green/red/gray) on home screen without tapping | Confirmed: `crossGroupBalanceProvider` aggregates per-group `groupBalancesProvider` results; `FirebaseConfig.currentUser?.uid` pattern established in codebase for personal balance extraction |
| NAV-04 | User can reach any module screen within 2 taps from home dashboard | Confirmed: group card tap → `/group/:id` (GoRouter) is 1 tap; event module is 1 additional tap from group detail. Phase 18 only needs to verify group card navigation works. |
| NAV-06 | All empty screens show contextual illustrations with a single clear CTA explaining what to do next | Confirmed: `EmptyStateView` supports icon, title, message, actionLabel, onAction — all needed props exist |

</phase_requirements>

---

## Summary

Phase 18 is a UI-heavy screen rewrite. The technical risk is concentrated in two areas: (1) the cross-group balance aggregation provider that derives a single net balance from multiple `groupBalancesProvider` family instances, and (2) the cross-group activity stream merger that combines per-group activity feeds chronologically. All the prerequisite infrastructure is in place — animation components, skeleton factories, token system, and design spec are verified complete.

The home screen rewrite replaces a simple `ListView.builder` inside an `Expanded` with a `CustomScrollView` + Sliver architecture. The existing `home_screen.dart` is 204 lines and already uses the correct provider pattern (`AsyncValue.when`), FAB bottom sheet, and `RefreshIndicator`. The rewrite preserves all of these patterns and adds the balance hero, quick-action tray, activity strip, weekly spending card, and bottom nav shell.

The critical data flow gap is that `groupBalancesProvider` returns `GroupBalances` which contains `List<UserBalance>` per group. To display the user's personal net balance in the hero card and in each `GroupCard`, the current user's `UserBalance` must be extracted by UID. `FirebaseConfig.currentUser?.uid` is the established pattern for this (verified in `group_detail_screen.dart` line 98). A new `crossGroupBalanceProvider` must implement this extraction and summation.

**Primary recommendation:** Build the cross-group aggregation provider first (it feeds both the hero card and GroupCard), then implement the 5 new widget files, then rewrite `home_screen.dart` last once all dependencies are in place.

---

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `flutter_riverpod` | ^2.4.9 (pinned) | Provider state management | Already in use across ~100 files; all data flows through Riverpod |
| `cloud_firestore` | ^6.2.0 (pinned) | Weekly spending queries | Expense data is Firestore; `eventExpensesProvider` already exists |
| `flutter_animate` | ^4.5.0 (in use) | `FadeInList` depends on it | Used by `fade_in_list.dart` via `AnimateList` |
| `shimmer` | ^3.0.0 (in use) | `SkeletonLoader` shimmer | `SkeletonLoader.build()` wraps in `Shimmer.fromColors` |
| `iconsax` | ^0.0.8 (in use) | All icons in Phase 18 | Already established; icons specified in UI-SPEC |
| `timeago` | ^3.6.1 (in use) | Relative timestamps in `ActivityRow` | Already in pubspec — `timeago.format(activity.timestamp)` |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `go_router` | ^13.2.0 (pinned) | Bottom nav tab navigation | Placeholder tab routes push via `context.push` |
| `intl` | ^0.20.2 (in use) | Date arithmetic for weekly spend | `DateFormat` for day-of-week labels in chart |
| `decimal` | ^3.2.4 (pinned) | All money arithmetic | `Decimal.zero` comparisons in balance hero |

### No New Packages Required

The UI-SPEC explicitly states: "All packages already in pubspec.yaml — no new packages required for this phase." `fl_chart` is explicitly out — use `Container` bars for the weekly spending chart (Claude's Discretion).

**Version verification:** All packages confirmed present in `pubspec.yaml` — no version changes needed.

---

## Architecture Patterns

### Recommended Project Structure

New files for this phase:

```
lib/features/home/
├── keys/
│   └── home_keys.dart             # Existing — ADD new keys for new widgets
├── screens/
│   └── home_screen.dart           # REWRITE — full dashboard
├── widgets/                       # All NEW files
│   ├── balance_hero_card.dart
│   ├── quick_action_tray.dart
│   ├── activity_row.dart
│   ├── weekly_spending_card.dart
│   └── bottom_nav_shell.dart
lib/features/groups/
├── providers/
│   └── group_balance_provider.dart # MODIFY — add crossGroupBalanceProvider
├── widgets/
│   └── group_card.dart             # MODIFY — replace totalSpent with personal balance
lib/core/theme/tokens/
│   └── color_tokens.dart           # MODIFY — add 4 new tokens
```

### Pattern 1: CustomScrollView + Sliver Architecture

**What:** The home screen scroll uses `CustomScrollView` with `SliverToBoxAdapter` for fixed sections and `SliverList.builder` for the group card list.

**When to use:** Any screen that mixes a variable-length list with non-list sections (hero cards, section headers, chart cards).

**Why not `Expanded` + `ListView`:** A `ListView` inside `Expanded` cannot be combined with other sections in a unified scroll — sections above/below the list don't scroll with it. This causes the "dashboard eager render risk" noted in STATE.md.

```dart
// Source: CONTEXT.md D-21, UI-SPEC Screen Layout Contract
CustomScrollView(
  slivers: [
    SliverToBoxAdapter(child: BalanceHeroCard(...)),
    SliverToBoxAdapter(child: QuickActionTray(...)),
    SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: AppColors.space16),
      sliver: SliverList.builder(
        itemCount: groups.length,
        itemBuilder: (context, index) => Padding(
          padding: const EdgeInsets.only(bottom: AppColors.space8),
          child: TapBounce(
            onTap: () => context.push('/group/${groups[index].id}'),
            child: GroupCard(group: groups[index]),
          ),
        ),
      ),
    ),
    SliverToBoxAdapter(child: _ActivitySection(...)),
    SliverToBoxAdapter(child: WeeklySpendingCard()),
  ],
)
```

**FadeInList placement:** `FadeInList` wraps the group cards as a list but is incompatible inside `SliverList.builder` (it is a Column, not a sliver). Use `SliverToBoxAdapter` wrapping a `FadeInList` for the group cards, not `SliverList.builder`, when item count is small (< 50). This is consistent with the UI-SPEC, which shows `SliverPadding > SliverList.builder > FadeInList`.

**Clarification on FadeInList + Slivers:** `FadeInList` produces a `Column`. To use it inside a `CustomScrollView`, wrap it in `SliverToBoxAdapter`. Alternatively, use `SliverList.builder` for the list and apply `flutter_animate` `.animate().fadeIn()` per item, as the existing `home_screen.dart` does. Choose the approach that avoids adding all `N` group cards to a single `Column` widget tree at once if groups can be numerous.

### Pattern 2: Cross-Group Balance Aggregation Provider

**What:** A new `Provider.family`-style or simple `Provider` that watches all per-group `groupBalancesProvider` results and sums the current user's net balance across groups.

**When to use:** Balance hero card and GroupCard (both need personal net balance).

**Implementation strategy (Claude's Discretion):**

The `groupBalancesProvider` already returns `AsyncValue<GroupBalances>` which contains `List<UserBalance>`. Each `UserBalance` has `participantId` (= Firebase UID) and `netBalance` (Decimal). The current user's UID is `FirebaseConfig.currentUser?.uid`.

```dart
// Source: group_detail_screen.dart pattern (lines 98-119) + group_balance_provider.dart
final crossGroupBalanceProvider = Provider.family<AsyncValue<CrossGroupBalance>, String>(
  (ref, currentUserId) {
    final groupsAsync = ref.watch(userGroupsProvider);
    if (groupsAsync.isLoading && !groupsAsync.hasValue) return const AsyncValue.loading();
    if (groupsAsync.hasError) return AsyncValue.error(groupsAsync.error!, groupsAsync.stackTrace!);
    final groups = groupsAsync.valueOrNull ?? [];
    if (groups.isEmpty) return const AsyncValue.data((net: Decimal.zero, groupCount: 0, isLoading: false));

    var net = Decimal.zero;
    var loadingAny = false;

    for (final group in groups) {
      final balancesAsync = ref.watch(groupBalancesProvider(group.id));
      if (balancesAsync.isLoading && !balancesAsync.hasValue) { loadingAny = true; continue; }
      final balances = balancesAsync.valueOrNull;
      if (balances == null) continue;
      final userBalance = balances.balances
          .where((b) => b.participantId == currentUserId)
          .firstOrNull;
      net = net + (userBalance?.netBalance ?? Decimal.zero);
    }

    if (loadingAny && net == Decimal.zero) return const AsyncValue.loading();
    return AsyncValue.data((net: net, groupCount: groups.length, isLoading: loadingAny));
  },
);

typedef CrossGroupBalance = ({Decimal net, int groupCount, bool isLoading});
```

**Key insight:** `Provider.family` (not `StreamProvider.family`) is the correct pattern here — the same reason `groupBalancesProvider` uses it. `ref.watch` inside a loop over a variable-length list is only safe in `Provider` bodies.

### Pattern 3: AsyncValue.when with Crossfade

**What:** The `AsyncValue.when(data:, loading:, error:)` pattern is the Riverpod standard for state-dependent rendering. All four screen states (loading, data+empty, data+groups, error) must be handled.

```dart
// Source: existing home_screen.dart pattern, verified
groupsAsync.when(
  data: (groups) => groups.isEmpty
      ? _buildEmptyState(context, ref)
      : _buildLoadedDashboard(context, ref, groups),
  loading: () => _buildSkeletonState(),
  error: (e, st) => _buildErrorState(context, ref),
)
```

**Note on error vs offline:** The error callback covers both network errors and Firestore failures. The `OfflineBanner` is driven by `connectivityProvider` (separate stream) — it shows amber banner regardless of whether `userGroupsProvider` is in error state.

### Pattern 4: Bottom Navigation Shell (Visual-Only)

**What:** A `Scaffold` with `bottomNavigationBar` using `BottomNavigationBar` widget. The `BottomNavShell` wraps the entire `HomeScreen` so the nav bar persists across all 4 states.

**When to use:** Phase 18 is visual-only — no `StatefulShellRoute`. The nav bar switches between a "live" Home content area and placeholder screens.

```dart
// Source: UI-SPEC D-10 through D-12, CONTEXT.md decisions
class BottomNavShell extends StatefulWidget {
  // ...
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _buildBody(), // switches on _currentIndex
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: _onTap,
        backgroundColor: AppColors.bottomNavBackground,
        selectedItemColor: AppColors.bottomNavActiveIcon,
        unselectedItemColor: AppColors.bottomNavInactiveIcon,
        type: BottomNavigationBarType.fixed, // required for 4 tabs — fixed shows all labels
        items: const [
          BottomNavigationBarItem(icon: Icon(Iconsax.people), label: 'Groups'),
          BottomNavigationBarItem(icon: Icon(Iconsax.activity), label: 'Activity'),
          BottomNavigationBarItem(icon: Icon(Iconsax.message), label: 'Chats'),
          BottomNavigationBarItem(icon: Icon(Iconsax.profile_circle), label: 'Profile'),
        ],
      ),
    );
  }
}
```

**CRITICAL DETAIL:** `BottomNavigationBarType.fixed` is required when there are 4 tabs. The default `shifting` type only works well for 3 tabs and hides labels — `fixed` shows labels for all tabs at all times, matching the design spec.

### Pattern 5: GroupCard Personal Balance Replacement

**What:** `GroupCard` currently shows `balancesAsync.when(data: (b) => Text(AppFormatters.formatCurrency(b.totalSpent, ...)))`. Replace `totalSpent` with the current user's personal net balance.

**Implementation:** `GroupCard` is a `ConsumerWidget` that already watches `groupBalancesProvider(group.id)`. Add a `currentUserId` parameter OR read `FirebaseConfig.currentUser?.uid` internally.

```dart
// Source: existing group_card.dart + group_detail_screen.dart pattern
balancesAsync.when(
  data: (balances) {
    final uid = FirebaseConfig.currentUser?.uid;
    final userBalance = balances.balances
        .where((b) => b.participantId == uid)
        .firstOrNull;
    final net = userBalance?.netBalance ?? Decimal.zero;
    final (String label, Color color) = switch (net.compareTo(Decimal.zero)) {
      < 0 => ('You owe ${AppFormatters.formatCurrency(net.abs(), group.currency)}', AppColors.errorText),
      > 0 => ('You are owed ${AppFormatters.formatCurrency(net, group.currency)}', AppColors.successText),
      _ => ('Settled', AppColors.textSecondary),
    };
    return Text(label, style: TextStyle(color: color));
  },
  loading: () => const Text('...', style: TextStyle(color: AppColors.textMuted)),
  error: (_, __) => const Text('Settled', style: TextStyle(color: AppColors.textSecondary)),
)
```

**CRITICAL:** `AppColors.errorText` and `AppColors.successText` are NOT in `AppColors` static class yet — they only exist in `AppColorTokens.light`. The planner must add `errorText` and `successText` to the `AppColors` facade before `GroupCard` can use them. This is a prerequisite task.

### Pattern 6: Weekly Spending Chart (Container Bars Approach)

**What:** Simple proportional-height `Container` bars for each day of the current week, using `AppColors.primary` fill. No `fl_chart` dependency.

**When to use:** The UI-SPEC says "use Container bars as default approach; avoid fl_chart unless native bars fail within 16ms budget." This avoids adding a new dependency.

```dart
// Source: UI-SPEC Performance Contract + Claude's Discretion
Row(
  crossAxisAlignment: CrossAxisAlignment.end,
  children: days.map((day) {
    final dayAmount = spendingByDay[day] ?? Decimal.zero;
    final maxAmount = spendingByDay.values.fold(Decimal.zero, (a, b) => a > b ? a : b);
    final heightFraction = maxAmount > Decimal.zero
        ? (dayAmount / maxAmount).toDouble()
        : 0.0;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Container(
              height: 60 * heightFraction,  // max bar height 60dp
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
              ),
            ),
            const SizedBox(height: 4),
            Text(dayLabel, style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
          ],
        ),
      ),
    );
  }).toList(),
)
```

**Weekly expenses provider:** The weekly spending data needs expenses aggregated by day across all groups' events. This is the most complex new provider. One approach: watch `userGroupsProvider` → for each group, watch `groupEventsProvider` → for each event, watch `eventExpensesProvider` → filter by `createdAt >= startOfWeek`. This is feasible but creates a deep watch chain. Alternative: use the existing `groupBalancesProvider` which already aggregates all expenses into `allExpenses` — but that provider doesn't expose raw expenses. **Recommended:** Create a new `weeklyGroupSpendingProvider(String userId)` that re-uses the existing watch-chain pattern from `groupBalancesProvider`.

### Anti-Patterns to Avoid

- **Nested `ListView` inside `Expanded`:** Phase 18 explicitly uses `CustomScrollView` + Slivers (D-21). Never put `ListView.builder` inside `Expanded` inside the main scroll.
- **`BottomNavigationBarType.shifting` with 4 tabs:** Loses labels. Use `fixed`.
- **Using `AppColors.textMuted` for functional balance text:** `textMuted` is decorative only (2.86:1 contrast, fails WCAG AA). Use `errorText`, `successText`, or `textSecondary` for balance amounts.
- **Using `double` for balance comparisons:** Use `Decimal.compareTo(Decimal.zero)` for net balance sign detection.
- **`StreamProvider.family` for multi-stream aggregation:** Use `Provider.family` when you need `ref.watch` inside a loop. This is the `groupBalancesProvider` lesson explicitly documented in the codebase.
- **Calling `FirebaseConfig.currentUser?.uid` in a `StatelessWidget` `build`:** It returns the value at build time. In `ConsumerWidget`, use it directly — it's synchronous and safe since auth is initialized before app starts.
- **`FadeInList` inside `SliverList.builder`:** `FadeInList` outputs a `Column`, not a `SliverList`. Use `SliverToBoxAdapter(child: FadeInList(...))` or use per-item `flutter_animate` animation directly.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Relative timestamps | Custom duration formatter | `timeago` package (already in pubspec) | `timeago.format(activity.timestamp)` — handles all edge cases (just now, 2h ago, 3d ago) |
| Skeleton loading | Custom shimmer | `SkeletonLoader.dashboardHero()` + `SkeletonLoader.groupList()` | Phase 17 built these exactly for this screen |
| Press animation | Custom `GestureDetector` + `AnimationController` | `TapBounce` widget | Phase 17 built this; has correct dispose() call |
| Staggered list entrance | Custom `AnimationController` per item | `FadeInList` widget | Phase 17 built this; respects `MediaQuery.disableAnimations` |
| Empty/error states | Custom empty state widgets | `EmptyStateView` with `actionLabel` + `onAction` params | Shared widget with CTA support and fade-in animation |
| Offline detection | Custom network check | `connectivityProvider` (existing) | `OfflineBanner` already watches this |
| Currency formatting | Custom OMR formatter | `AppFormatters.formatCurrency()` | Already handles 3 decimal places and currency code |
| Bottom sheet | Custom modal | `showModalBottomSheet` | Already used in `home_screen.dart` for FAB menu — reuse pattern |

**Key insight:** Phase 17 and Phase 16 were explicitly designed to prepare for Phase 18. Nearly every visual component needed is already built. The work is primarily integration (connecting providers to widgets) and rewriting the scroll architecture.

---

## Common Pitfalls

### Pitfall 1: AppColors Missing errorText and successText

**What goes wrong:** `GroupCard` and `BalanceHeroCard` need `AppColors.errorText` (#B91C1C) and `AppColors.successText` (#047857). These tokens exist in `AppColorTokens.light` but are NOT in the `AppColors` static class in `app_theme.dart`. Using `AppColors.error` (#EF4444) by mistake would use the display-only error color which fails WCAG for text.

**Why it happens:** The `AppColors` facade was preserved as-is during Phase 15 — new semantic text tokens were added to `AppColorTokens` but the facade was not extended.

**How to avoid:** Wave 0 task: add `errorText` and `successText` static constants to `AppColors` before any widget work.

**Warning signs:** `AppColors.error` being used for balance text labels; `find.text('You owe')` appearing in red (#EF4444) instead of dark red (#B91C1C).

### Pitfall 2: Provider.family vs StreamProvider.family for Multi-Stream Aggregation

**What goes wrong:** Using `StreamProvider.family` for `crossGroupBalanceProvider` compiles but crashes at runtime with "StreamProvider cannot call ref.watch inside a loop" because `ref.watch` inside a `StreamProvider` body that calls async generators is invalid.

**Why it happens:** `StreamProvider` bodies are generators — `ref.watch` in a loop over a dynamic list creates an indeterminate number of watch subscriptions per evaluation.

**How to avoid:** Use `Provider.family` (not `StreamProvider.family`) for any provider that needs `ref.watch` inside a loop. The existing `groupBalancesProvider` is `Provider.family<AsyncValue<GroupBalances>, String>` — the new cross-group provider must follow the same pattern.

**Warning signs:** "Bad state: Tried to use ref.watch inside a StreamProvider" or similar Riverpod assertion errors at runtime.

### Pitfall 3: BottomNavShell + GoRouter Conflict

**What goes wrong:** The `/home` route renders `HomeScreen`. If `BottomNavShell` is placed as a wrapper widget inside `HomeScreen`, tapping non-Groups tabs tries to push routes from inside `HomeScreen`, but `/home` is the root GoRouter route. Using `context.push('/activity')` from within `HomeScreen` will fail since that route doesn't exist.

**Why it happens:** Phase 18 is visual-only — GoRouter is NOT restructured (that's Phase 19). The placeholder tabs must use `Navigator.push` (or inline state switching) rather than GoRouter routes.

**How to avoid:** `BottomNavShell` is a `StatefulWidget` that switches between widgets based on `_currentIndex`. Inactive tabs show a `PlaceholderScreen` widget — no GoRouter route needed. Only the Groups tab renders the actual dashboard content.

**Warning signs:** `GoException: No route found for /activity` at runtime when tapping bottom nav tabs.

### Pitfall 4: SliverList.builder + FadeInList Incompatibility

**What goes wrong:** `FadeInList` produces a `Column`, not a Sliver. Passing it directly inside `SliverList.builder` or inside `sliver:` parameter causes a type error.

**Why it happens:** The UI-SPEC shows `SliverPadding > SliverList.builder > FadeInList` but `SliverList.builder` expects a `itemBuilder` returning a `Widget`, not a nested `FadeInList`. The intent is that `FadeInList` contains the group card children in a `Column`.

**How to avoid:** Use `SliverToBoxAdapter(child: FadeInList(children: groupCards))` for the group list, OR use `SliverList.builder` with per-item `flutter_animate` animation. Do not mix `SliverList.builder` with `FadeInList`.

**Warning signs:** Compile-time type error `FadeInList is not a Widget subtype of SliverChildDelegate` or similar.

### Pitfall 5: Weekly Spending Provider — Empty vs No Expenses

**What goes wrong:** The weekly spending chart renders with `maxAmount == Decimal.zero` (all days have 0 expenses), causing a division-by-zero when computing bar height fractions.

**Why it happens:** New groups with no events or expenses are a valid state. The chart computation must guard `maxAmount > Decimal.zero` before dividing.

**How to avoid:** Use `heightFraction = maxAmount > Decimal.zero ? (dayAmount / maxAmount).toDouble() : 0.0`. Display a "No spending yet this week" message when all days are zero.

**Warning signs:** `Decimal` division by zero throws `DecimalRangeError` at runtime.

### Pitfall 6: Scroll-to-Activity Section for Quick-Action "Activity" Button

**What goes wrong:** D-06 says the "Activity" quick-action button "scrolls to or navigates to the activity section." Scrolling to a specific child of `CustomScrollView` requires a `ScrollController` with `animateTo` — but the target position is not known at button-press time.

**Why it happens:** Arbitrary scroll positions inside `CustomScrollView` are not trivially known without measuring. The simplest approach is to give the `CustomScrollView` a `ScrollController` and use `GlobalKey` on the activity section `SliverToBoxAdapter`, then use `Scrollable.ensureVisible`.

**How to avoid:** Use `Scrollable.ensureVisible(activitySectionKey.currentContext!, ...)` with a `GlobalKey` on the activity section widget. This works correctly with `CustomScrollView`.

**Warning signs:** `RenderObject.hitTest() returned false` or no scroll happening when "Activity" quick-action is tapped.

---

## Code Examples

### Cross-Group Balance Provider (Pattern from groupBalancesProvider)

```dart
// Source: lib/features/groups/providers/group_balance_provider.dart (Provider.family pattern)
// Pattern: Provider.family with ref.watch in loop — safe for variable-length data
final crossGroupBalanceProvider =
    Provider.family<AsyncValue<CrossGroupBalance>, String>((ref, currentUserId) {
  final groupsAsync = ref.watch(userGroupsProvider);
  if (groupsAsync.isLoading && !groupsAsync.hasValue) return const AsyncValue.loading();
  if (groupsAsync.hasError) {
    return AsyncValue.error(groupsAsync.error!, groupsAsync.stackTrace!);
  }
  final groups = groupsAsync.valueOrNull ?? [];

  var net = Decimal.zero;
  var anyLoading = false;

  for (final group in groups) {
    final balancesAsync = ref.watch(groupBalancesProvider(group.id));
    if (balancesAsync.isLoading && !balancesAsync.hasValue) {
      anyLoading = true;
      continue;
    }
    final balances = balancesAsync.valueOrNull;
    if (balances == null) continue;
    final userBalance = balances.balances
        .where((b) => b.participantId == currentUserId)
        .firstOrNull;
    net = net + (userBalance?.netBalance ?? Decimal.zero);
  }

  if (anyLoading && net == Decimal.zero) return const AsyncValue.loading();
  return AsyncValue.data((
    net: net,
    groupCount: groups.length,
    isLoading: anyLoading,
  ));
});

typedef CrossGroupBalance = ({Decimal net, int groupCount, bool isLoading});
```

### BalanceHeroCard State Switching

```dart
// Source: UI-SPEC Balance Hero Card States table + D-01/D-02
final (String label, Color amountColor, IconData icon) = switch (
  net.compareTo(Decimal.zero)
) {
  < 0 => (
      'You owe OMR ${AppFormatters.formatCurrency(net.abs(), 'OMR')} across $groupCount groups',
      AppColors.errorText,   // #B91C1C — WCAG AA
      Iconsax.warning_2,
    ),
  > 0 => (
      'You are owed OMR ${AppFormatters.formatCurrency(net, 'OMR')} across $groupCount groups',
      AppColors.successText, // #047857 — WCAG AA
      Iconsax.tick_circle,
    ),
  _ => (
      'All settled up',
      AppColors.textSecondary, // #6B7280 — WCAG AA
      Iconsax.tick_circle,
    ),
};
```

### Activity Row Relative Timestamp

```dart
// Source: timeago package (already in pubspec ^3.6.1)
import 'package:timeago/timeago.dart' as timeago;

// Usage in ActivityRow:
Text(
  timeago.format(activity.timestamp),
  style: const TextStyle(
    fontSize: 12,
    color: AppColors.textMuted,  // decorative timestamp — WCAG rule from Phase 16
  ),
)
```

### Token Addition Pattern (Wave 0)

```dart
// Source: lib/core/theme/app_theme.dart AppColors class
// Add these constants to the AppColors static class:
static const Color errorText = Color(0xFFB91C1C);   // Dark red, 6.57:1 on white
static const Color successText = Color(0xFF047857);  // Dark emerald, 5.92:1 on white
static const Color offlineBannerBackground = Color(0xFFF59E0B); // Amber (D-24)
static const Color bottomNavBackground = Color(0xFFFFFFFF);     // White (D-25)
static const Color bottomNavActiveIcon = Color(0xFF0D7B74);     // Teal = primary (D-25)
static const Color bottomNavInactiveIcon = Color(0xFF9CA3AF);   // Decorative only (D-25)
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `ListView.builder` inside `Expanded` | `CustomScrollView` + Slivers | Phase 18 (this phase) | Enables mixed-content scrolling without nested scrollables |
| `totalSpent` display in GroupCard | Personal net balance display | Phase 18 (this phase) | Answers "what do I owe?" per-group |
| Simple group list home screen | Full dashboard with hero + tray + activity + chart | Phase 18 (this phase) | Satisfies NAV-01, NAV-02 |
| `BottomNavigationBarType.shifting` | `BottomNavigationBarType.fixed` | Phase 18 (this phase) | Required for 4 tabs to show labels |

---

## Environment Availability

Step 2.6: SKIPPED (no external dependencies — all packages already in pubspec.yaml, no new installs required).

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | flutter_test (SDK built-in) + mocktail ^1.0.4 + fake_cloud_firestore ^4.1.0+1 |
| Config file | none — pubspec.yaml dev_dependencies |
| Quick run command | `flutter test test/features/home/` |
| Full suite command | `flutter test` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| NAV-01 | Dashboard renders with hero + tray + group cards + activity strip | Widget | `flutter test test/features/home/home_screen_dashboard_test.dart -x` | ❌ Wave 0 |
| NAV-02 | Balance hero shows color-coded net balance without tapping | Widget | `flutter test test/features/home/balance_hero_card_test.dart -x` | ❌ Wave 0 |
| NAV-04 | Group card tap navigates to `/group/:id` | Widget | `flutter test test/features/home/home_screen_groups_test.dart::tapping GroupCard navigates` | ✅ (existing test) |
| NAV-06 | Empty state shows EmptyStateView with CTA "Create your first group" | Widget | `flutter test test/features/home/home_screen_groups_test.dart::shows empty state` | ✅ (existing — needs CTA text update) |
| NAV-06 (error) | Error state shows OfflineBanner + EmptyStateView | Widget | `flutter test test/features/home/home_screen_dashboard_test.dart -x` | ❌ Wave 0 |
| NAV-01 | Quick-action tray visible in loaded state | Widget | included in dashboard test | ❌ Wave 0 |
| D-12/D-24/D-25 | New color tokens exist in AppColorTokens | Unit | `flutter test test/unit/color_tokens_test.dart -x` | ❌ Wave 0 |
| D-03 | crossGroupBalanceProvider aggregates per-group net balances | Unit | `flutter test test/unit/cross_group_balance_test.dart -x` | ❌ Wave 0 |

### Sampling Rate

- **Per task commit:** `flutter test test/features/home/`
- **Per wave merge:** `flutter test`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps

- [ ] `test/features/home/home_screen_dashboard_test.dart` — covers NAV-01, NAV-06 (error), quick-action tray visibility
- [ ] `test/features/home/balance_hero_card_test.dart` — covers NAV-02 (color-coded balance states: owe / owed / settled)
- [ ] `test/unit/cross_group_balance_test.dart` — covers D-03 (aggregation logic with fake data)
- [ ] `test/unit/color_tokens_test.dart` — covers D-12/D-24/D-25 (verify new tokens exist in AppColorTokens.light)

*(Existing `home_screen_groups_test.dart` needs update: empty state CTA text changes from "No groups yet" to "Create your first group")*

---

## Key Implementation Notes for Planner

### Task Sequencing Constraint

There is a strict dependency chain within Phase 18:

1. **Wave 0 (foundation):** Add `errorText`, `successText`, `offlineBannerBackground`, `bottomNavBackground`, `bottomNavActiveIcon`, `bottomNavInactiveIcon` to `AppColors` AND to `AppColorTokens` (both places). Create new test files. This must land before any widget work.

2. **Wave 1 (new providers):** Create `crossGroupBalanceProvider` and a new weekly spending aggregation provider. Both depend on the token additions (for compile-time constants in tests) and must be in place before widgets that consume them.

3. **Wave 2 (new widgets):** Create `BalanceHeroCard`, `QuickActionTray`, `ActivityRow`, `WeeklySpendingCard`, `BottomNavShell`. These depend on Wave 1 providers and Wave 0 tokens.

4. **Wave 3 (modifications):** Rewrite `home_screen.dart` + enrich `GroupCard`. Depend on all Wave 2 widgets being complete.

### GroupCard Breaking Change

`GroupCard` currently shows `totalSpent` (not user-specific). Replacing this with personal balance changes the widget's visual contract — any existing tests that assert on the `totalSpent` text will need updating. The existing test file `home_screen_groups_test.dart` uses `find.byType(GroupCard)` (safe) but also `find.text('Desert Crew')` (content text). Check for any tests that assert on `GroupCard`'s balance display before modifying.

### HomeKeys Expansion Needed

`HomeKeys` currently has 5 keys. Phase 18 adds new interactive widgets requiring semantic keys for testing:
- `HomeKeys.balanceHeroCard`
- `HomeKeys.quickActionTray`
- `HomeKeys.addExpenseAction`
- `HomeKeys.settleUpAction`
- `HomeKeys.inviteAction`
- `HomeKeys.activityAction`
- `HomeKeys.activitySection`
- `HomeKeys.weeklySpendingCard`
- `HomeKeys.bottomNavGroups`
- `HomeKeys.bottomNavActivity`
- `HomeKeys.bottomNavChats`
- `HomeKeys.bottomNavProfile`

### OfflineBanner Behavior Clarification

The current `OfflineBanner` uses `AppColors.warning` with 0.12 alpha for background (amber tinted). The design spec says solid amber (#F59E0B) with white text. The banner may need updating in this phase to use the new `offlineBannerBackground` token as a solid color, not the alpha-blended `warning` color.

### `ActivityRow` Data: group name tag requirement

`GroupActivityLog` model does NOT contain a `groupName` field — it only has `groupId` via the Firestore path. The `ActivityRow` needs to display a group name tag (D-14). Options:
1. Pass `groupName` to `ActivityRow` as a constructor param (simplest)
2. Watch `userGroupsProvider` inside `ActivityRow` to look up the name by id

Option 1 is simpler and avoids nested provider watches. The parent that builds the activity list already has access to the groups list.

---

## Open Questions

1. **Weekly spending provider scope**
   - What we know: `eventExpensesProvider` streams expenses per event. Getting all expenses across all groups requires nested loops: groups → events → expenses.
   - What's unclear: Whether the `crossGroupBalanceProvider` pattern (which already collects `allExpenses`) can be reused for weekly filtering, or whether a separate provider is needed.
   - Recommendation: Build a separate `weeklyGroupSpendingProvider(String userId)` that reuses the same Provider.family + ref.watch-in-loop pattern. Filter `allExpenses` for `createdAt >= startOfWeek`.

2. **`crossGroupBalanceProvider` parameter strategy**
   - What we know: The provider needs the current user's UID. It could be `Provider<AsyncValue<CrossGroupBalance>>` (reads UID internally) or `Provider.family<..., String>` (UID passed as parameter).
   - What's unclear: Using a plain `Provider` (no family) that reads UID internally is simpler but means the provider is global — any UID change would require manual invalidation.
   - Recommendation: Use `Provider<AsyncValue<CrossGroupBalance>>` (not family) since there is only ever one current user. Read `FirebaseConfig.currentUser?.uid` inside the provider body.

3. **`ActivityRow` showing `groupId` or `groupName`**
   - What we know: `GroupActivityLog` has no `groupName` field. Resolved above: pass `groupName` as constructor param.
   - What's unclear: None — resolved.
   - Recommendation: See "Key Implementation Notes" above.

---

## Sources

### Primary (HIGH confidence)

- `lib/features/home/screens/home_screen.dart` — Current 204-line implementation, verified patterns
- `lib/features/groups/providers/group_balance_provider.dart` — Provider.family + ref.watch-in-loop pattern
- `lib/features/groups/screens/group_detail_screen.dart` — FirebaseConfig.currentUser?.uid pattern for personal balance extraction
- `lib/core/theme/tokens/color_tokens.dart` — AppColorTokens.light — token gap confirmed (errorText/successText exist here, not in AppColors facade)
- `lib/core/theme/app_theme.dart` — AppColors facade — confirmed missing errorText, successText, offlineBannerBackground, bottomNav tokens
- `lib/shared/widgets/skeleton_loader.dart` — SkeletonLoader.dashboardHero() and .groupList() verified present
- `lib/shared/animations/tap_bounce.dart` + `fade_in_list.dart` — Animation components verified present
- `lib/shared/widgets/empty_state_view.dart` — EmptyStateView signature verified (supports actionLabel + onAction)
- `lib/shared/widgets/offline_banner.dart` — Uses AppColors.warning with alpha; will need token update
- `lib/features/groups/models/group_activity_log_model.dart` — Confirmed no groupName field
- `lib/features/groups/services/group_activity_service.dart` — watchRecentActivity(groupId, limit: 5) verified
- `pubspec.yaml` — timeago ^3.6.1 confirmed; no new packages needed
- `.planning/phases/18-home-dashboard-redesign/18-CONTEXT.md` — All 25 locked decisions
- `.planning/phases/18-home-dashboard-redesign/18-UI-SPEC.md` — Full visual + interaction contract
- `.planning/design/home-screen-spec.md` — Primary visual target with 4 states
- `test/features/home/home_screen_groups_test.dart` — Existing tests that must remain green

### Secondary (MEDIUM confidence)

- Flutter `BottomNavigationBarType.fixed` requirement for 4+ tabs — inferred from Flutter docs knowledge; use `type: BottomNavigationBarType.fixed` to avoid shifting mode hiding labels
- `Scrollable.ensureVisible` for scroll-to-activity — standard Flutter pattern for programmatic scroll to a `GlobalKey` target

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all packages verified in pubspec.yaml; no new dependencies
- Architecture patterns: HIGH — verified from existing code in codebase; Provider.family pattern confirmed in group_balance_provider.dart
- Cross-group provider: HIGH — pattern is identical to existing groupBalancesProvider; implementation strategy clear
- Token gaps: HIGH — verified by reading AppColors and AppColorTokens directly
- Pitfalls: HIGH — all verified against actual code (errorText not in AppColors confirmed; StreamProvider restriction confirmed; BottomNavType.fixed confirmed)
- Weekly spending provider: MEDIUM — approach is clear but implementation complexity depends on how many events exist per group; could create many parallel watches

**Research date:** 2026-03-29
**Valid until:** 2026-05-29 (stable Flutter/Riverpod stack; no breaking changes expected)
