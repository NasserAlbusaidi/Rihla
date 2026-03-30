# Phase 20: Group Detail & Event Hub Redesign - Research

**Researched:** 2026-03-30
**Domain:** Flutter UI redesign — screens, widgets, ContainerTransform animation, design token application
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Event Card Design**
- D-01: Event cards show amount + status line inline: personal balance ("You owe OMR 12.500") in errorText/successText, expense count ("· 3 expenses"), and date range. Uses the same color-coding as home dashboard balance hero (red/green/gray).
- D-02: Past events render at 60% opacity with the accent bar switching from teal (AppColors.primary) to gray (AppColors.textMuted). Same card layout, just visually receded. Upcoming/active events render at full color with teal accent bar.
- D-03: Event cards retain the left accent bar from the spec. All event types use teal (per Phase 16 D-80 — event-type color discrimination deferred).

**ContainerTransform Transition**
- D-04: Single ContainerTransform transition only — group card on HomeScreen morphs into GroupDetailScreen. All other transitions remain as `_slideRightTransition`. Phase 22 handles broader M3 motion.
- D-05: Use Google's official `animations` package (`OpenContainer` widget) for the ContainerTransform implementation. Handles clipping, elevation, and material motion automatically. New dependency to add.
- D-06: The OpenContainer wraps the GroupCard in HomeScreen. The `openBuilder` returns GroupDetailScreen. GoRouter's `context.push('/group/$groupId')` must be reconciled with OpenContainer's navigation — research should investigate how OpenContainer coexists with GoRouter (it may need to bypass GoRouter for the transition and let GoRouter handle the route state).

**Group Detail Data Density**
- D-07: Above the fold (visible without scrolling on ~390px): dark header with group name/avatar stack/invite code, 2x2 stats grid, and settle-up CTA button. Member balances and events scroll below.
- D-08: Stats grid shows 4 tiles: YOUR BALANCE (color-coded), GROUP TOTAL, ACTIVE MEMBERS, EVENTS (count). The spec's "DAYS LEFT" is replaced with event count — always available, always meaningful regardless of group state.
- D-09: Section ordering below the fold: Events → Member Balances → Recent Activity. Events come first (what's happening), then member balances (who owes what), then activity (recent changes). This reorders from the spec which had Members before Events.
- D-10: Settle-up CTA button: full-width teal button, 52dp height, shown when any balance is non-zero. Hidden when all settled.

**Event Hub Module Grid**
- D-11: Modules with no data show description text in textMuted (e.g., "Track shared equipment"). Modules with data show live count + key metric summary. SmartModuleCard already supports this description/summary pattern.
- D-12: Live summary format per module:
  - Ledger: "N expenses · OMR X.XXX"
  - Gear: "N items · M unchecked"
  - Logistics: "N groups"
  - Vault: "N files"
  - Memories: "N photos"
  - Activity: "N entries"
- D-13: 2x3 grid layout in both loaded and empty states (per spec reconciliation). Modules are always visible — never hidden when empty.
- D-14: Expense hero card above the module grid showing total expenses with "+ Add Expense" chip button.

### Claude's Discretion
- How to reconcile OpenContainer with GoRouter navigation (may need custom transition page or navigation bypass)
- Whether the expense hero card in event hub uses the same BalanceHeroCard pattern from Phase 18 or a simplified version
- Exact skeleton composition for group detail and event hub loading states
- Activity strip widget layout — can reuse ActivityRow from Phase 18 home dashboard
- How to determine "past" vs "upcoming" events (date-based: endDate < now, or status-based)

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| SCRN-01 | Group detail screen shows event cards with type-specific color accents, inline financial summaries, and past/upcoming visual distinction | EventCard already has `isPast` + `Opacity(0.6)` pattern (D-26). Research confirms left-accent-bar + balance inline approach. Token mapping fully documented in group-detail-spec.md. |
| SCRN-02 | Event hub (CommandCenter) uses the new design language with earthy palette and improved information density | EventModuleList currently renders a vertical Column; spec requires 2x3 SliverGrid. SmartModuleCard already supports summary/description modes. AppColorTokens.light has all module accent tokens. |
</phase_requirements>

---

## Summary

Phase 20 redesigns two screens: `GroupDetailScreen` (609 lines, heavy widgets already present but layout doesn't match spec) and `EventCommandCenter` (144 lines, simpler but module grid needs structural change from Column to SliverGrid). Both screens have full visual specs in `.planning/design/`. The design token system is complete and correct in `AppColorTokens.light`. All shared widgets (`ModuleHeader`, `SmartModuleCard`, `BalanceHeroCard` pattern, `ActivityRow`, `EmptyStateView`, `SkeletonLoader`, `FadeInList`, `TapBounce`) exist and work — this phase is composition and layout work, not widget creation.

The single technically novel element is the ContainerTransform (OpenContainer) transition on the HomeScreen's GroupCard. Research confirms a significant constraint: OpenContainer from the `animations` package uses Flutter's native `Navigator.push()` internally and does not integrate with GoRouter's declarative route tree. The URL bar will not update during the OpenContainer transition. The practical resolution (Claude's discretion per D-06) is to use OpenContainer for the visual transition but immediately call `context.replace('/group/$groupId')` inside `onClosed` or allow OpenContainer to handle the push while GoRouter's route remains in sync through careful use of `useRootNavigator: false`.

The EventModuleList currently renders a vertical `Column` of `SmartModuleCard` instances with priority sorting. The spec requires a 2x3 `SliverGrid`. This is the largest structural change in the event hub — converting from a Column to a SliverGrid means abandoning priority sorting (locked order per spec) and changing the grid delegate's `childAspectRatio` to accommodate the card height.

**Primary recommendation:** Treat the phase as three discrete waves: (1) group detail screen layout rebuild, (2) event hub module grid rebuild, (3) OpenContainer transition on HomeScreen GroupCard.

---

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `animations` | `^2.1.2` | `OpenContainer` ContainerTransform transition | Google's official M3 motion package. Only new dependency. D-05 locked. |
| `flutter_animate` | `^4.5.0` (already in pubspec) | FadeIn/slideY stagger on module cards | Already used in EventModuleList; continue pattern. |
| `shimmer` | `^3.0.0` (already in pubspec) | Skeleton shimmer bars | Already used via SkeletonLoader. |

### Supporting (all already in pubspec, no new additions except `animations`)
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `flutter_riverpod` | `^2.4.9` | Provider state for groupBalancesProvider, eventExpensesProvider, etc. | All data watching |
| `go_router` | `^13.2.0` | Declarative routing, context.push navigation | All non-OpenContainer navigation |
| `decimal` | `^3.2.4` | OMR balance formatting | All financial display |
| `iconsax` | `^0.0.8` | Module icons (wallet_3, bag_2, car, document_text, gallery, etc.) | Module cards |
| `intl` | `^0.20.2` | Date formatting for event date ranges | EventCard date display |

### Installation (new dependency only)
```bash
flutter pub add animations
```

### Version verification
`animations` 2.1.2 was published 2026-03-28 per pub.dev. Compatible with Flutter SDK ^3.10.1 (confirmed).

---

## Architecture Patterns

### Recommended Project Structure

No new directories needed. All work is modifications to existing files plus adding one new small widget file:

```
lib/features/groups/screens/
  group_detail_screen.dart       # Primary redesign (609 → ~450 lines)
lib/features/groups/widgets/
  group_stats_grid.dart          # NEW: 2x2 stats grid extracted as widget
lib/features/events/screens/
  event_command_center.dart      # Primary redesign (144 → ~160 lines)
lib/features/events/widgets/
  event_module_grid.dart         # RENAME/REPLACE: event_module_list.dart → grid layout
lib/features/home/screens/
  home_screen.dart               # GroupCard → OpenContainer wrapper
lib/features/home/widgets/
  group_card.dart                # Unchanged internally; OpenContainer wraps it
```

### Pattern 1: 2x2 Stats Grid (GroupDetailScreen)

**What:** Four `StatCard` widgets in a 2-column GridView. Data from `groupBalancesProvider`.
**When to use:** Above-the-fold summary for GroupDetailScreen.
**Example:**
```dart
// Source: .planning/design/group-detail-spec.md token mapping
GridView.count(
  crossAxisCount: 2,
  shrinkWrap: true,
  physics: const NeverScrollableScrollPhysics(),
  crossAxisSpacing: AppColors.space8,
  mainAxisSpacing: AppColors.space8,
  childAspectRatio: 1.6,  // tuned for 2-line stat card content
  children: [
    StatCard(
      overline: 'YOUR BALANCE',
      value: 'OMR 12.500',
      valueColor: AppColors.errorText,  // or successText or textPrimary
    ),
    StatCard(overline: 'GROUP TOTAL', value: 'OMR 45.500'),
    StatCard(overline: 'ACTIVE MEMBERS', value: '4'),
    StatCard(overline: 'EVENTS', value: '3'),
  ],
)
```
Cards use `AppColors.surface` background, `AppColors.border` border, `AppColors.textMuted` overline (decorative), `AppColors.textPrimary`/`errorText`/`successText` for values. Border radius `AppColors.radiusSmall` (12dp).

### Pattern 2: Event Card with Left Accent Bar + Inline Balance (D-01, D-02, D-03)

**What:** The existing `EventCard` already has `isPast` + `Opacity(0.6)` (confirmed in `event_card.dart` line 152). The card needs to be updated to show:
- Left accent bar: `AppColors.primary` (active) or `AppColors.textMuted` (past)
- Personal balance inline: "You owe OMR 12.500" in errorText, or "You are owed OMR 5.000" in successText
- Expense count + date range

The existing `EventCard` currently shows:
- Icon container (48x48) — to be replaced with left accent bar
- name, type badge, meta text, total spent

**Example (redesigned EventCard structure):**
```dart
// Source: .planning/design/group-detail-spec.md Component Hierarchy
Container(
  decoration: BoxDecoration(
    color: AppColors.surface,
    borderRadius: BorderRadius.circular(AppColors.radiusLarge),
    boxShadow: AppColors.shadowRaised,
  ),
  child: IntrinsicHeight(
    child: Row(
      children: [
        // Left accent bar — 3dp wide, full height
        Container(
          width: 3.0,
          decoration: BoxDecoration(
            color: event.isPast ? AppColors.textMuted : AppColors.primary,
            borderRadius: const BorderRadius.horizontal(
              left: Radius.circular(AppColors.radiusLarge),
            ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(AppColors.space16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(event.name, style: textPrimary),
                Text(dateRange, style: textSecondary),
                Text(personalBalance, style: TextStyle(color: balanceColor)),
                Text('· $expenseCount expenses', style: textMuted),
              ],
            ),
          ),
        ),
      ],
    ),
  ),
)
// Wrap in Opacity(opacity: 0.6) when event.isPast
```

**Past/upcoming determination:** `event.isPast` is already computed on the `Event` model (confirmed in `event_card.dart` line 152: `if (event.isPast)`). No new logic needed.

**Personal balance per card:** Requires watching `groupBalancesProvider(groupId)` in `GroupDetailScreen`, then looking up the current user's `perEventBreakdown` for each eventId. The `GroupBalances` typedef already includes `perEventBreakdown: Map<String, Map<String, Decimal>>` keyed by `participantId → eventId → amount`. The screen already watches this provider.

### Pattern 3: 2x3 Module Grid (EventCommandCenter)

**What:** Replace the vertical `Column` in `EventModuleList` with a `SliverGrid` in `EventCommandCenter`.
**When to use:** Event hub module area.

The current `EventModuleList` widget:
- Uses priority sorting (highest priority first)
- Returns a `Column` of `SmartModuleCard` with staggered `flutter_animate` FadeIn

The spec requires:
- Fixed 2x3 grid layout: Row 1 = Ledger/Gear, Row 2 = Logistics/Vault, Row 3 = Activity/Memories
- `SliverGrid(delegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: space12, mainAxisSpacing: space12, childAspectRatio: ~1.4))`
- Module colors must use `AppColors.moduleLedger` (#0D7B74) for Ledger, `AppColors.moduleGear` (#6B7280) for all others

**Critical gap:** The current `EventModuleList` passes hardcoded colors that do not match `AppColorTokens.light`:
- Ledger uses `AppColors.accentSecondary` (NOT `AppColors.moduleLedger`)
- Gear uses `AppColors.accentSecondary` OR `AppColors.amber` (NOT `AppColors.moduleGear`)
- Logistics uses `AppColors.sky` (NOT `AppColors.moduleLogistics`)
- Vault uses `AppColors.indigo` (NOT `AppColors.moduleVault`)
- Memories uses `AppColors.mint` (NOT `AppColors.moduleMemories`)

All of these must be corrected to match AppColorTokens in the new grid implementation.

**Recommended approach:** Replace `EventModuleList` (the Column-based widget) with an inline `SliverGrid` inside `EventCommandCenter`. The module card data (summaries, empty states) can be computed in the same place. The `_ModuleCardConfig` internal class can be repurposed.

**Example grid structure:**
```dart
// Source: .planning/design/event-hub-spec.md Component Hierarchy
SliverPadding(
  padding: const EdgeInsets.all(AppColors.space16),
  sliver: SliverGrid(
    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 2,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.4,  // adjust to content
    ),
    delegate: SliverChildListDelegate([
      SmartModuleCard(
        icon: Iconsax.wallet_3,
        title: 'Ledger',
        description: 'Settle balances',
        color: AppColors.moduleLedger,  // #0D7B74
        summaryText: ledgerSummary,     // "3 expenses · OMR 45.500"
        isEmpty: expenses.isEmpty,
        onTap: () => context.push('.../ledger'),
      ),
      SmartModuleCard(
        icon: Iconsax.bag_2,
        title: 'Gear',
        description: 'Track shared equipment',
        color: AppColors.moduleGear,    // #6B7280
        ...
      ),
      // ... 4 more
    ]),
  ),
)
```

**SmartModuleCard childAspectRatio note:** SmartModuleCard renders as a `Row` (horizontal layout: icon + text + chevron). At `childAspectRatio: 1.4`, each cell is approximately 160x114dp on a 390px screen (with 16dp padding each side + 12dp gap). This may be tight — the planner should note that `childAspectRatio` needs empirical tuning during implementation. A value of 2.0–2.5 may work better for a horizontal Row card.

### Pattern 4: OpenContainer + GoRouter Coexistence (D-04, D-05, D-06)

**What:** ContainerTransform from GroupCard (HomeScreen) to GroupDetailScreen.

**The constraint (HIGH confidence):** `OpenContainer` uses `Navigator.push()` internally and does NOT integrate with GoRouter's declarative routing. The URL will NOT update when OpenContainer fires. This is a documented, unresolved limitation (GitHub issue #135975, issue #51399, multiple community reports from 2023–2026).

**Recommended resolution (Claude's discretion per D-06):**

Option A — OpenContainer as visual-only, bypass GoRouter for this transition:
```dart
// In HomeScreen group cards list:
OpenContainer<void>(
  closedColor: AppColors.surface,
  openColor: AppColors.background,
  closedElevation: 0,
  openElevation: 0,
  closedShape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(AppColors.radiusLarge),
  ),
  openShape: const RoundedRectangleBorder(),
  transitionDuration: const Duration(milliseconds: 400),
  tappable: true,
  closedBuilder: (context, openContainer) => GroupCard(
    group: group,
    onTap: openContainer,  // OpenContainer fires, not context.push
  ),
  openBuilder: (context, closeContainer) => GroupDetailScreen(groupId: group.id),
  // No GoRouter involvement — this route bypasses GoRouter
)
```

**Risk:** Deep-link back to `/group/:gid` will use the normal _slideRightTransition via GoRouter. Only the tap-from-home uses OpenContainer. This is acceptable since deep links are rare in practice and the GroupDetail route still exists in GoRouter's route tree for back-navigation and sub-route resolution.

Option B — Custom ContainerTransform using flutter_animate (avoids the `animations` package entirely, stays within GoRouter):
```dart
// In app_router.dart, for groupDetail route:
pageBuilder: (context, state) => CustomTransitionPage(
  key: state.pageKey,
  child: GroupDetailScreen(groupId: state.pathParameters['gid']!),
  transitionsBuilder: (context, animation, secondary, child) {
    return ScaleTransition(
      scale: Tween(begin: 0.95, end: 1.0).animate(
        CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
      ),
      child: FadeTransition(opacity: animation, child: child),
    );
  },
)
```
This stays within GoRouter, URL updates correctly, but lacks the true "card morphs into screen" visual of ContainerTransform.

**Recommendation:** Use Option A. D-05 locks `animations` package use. Accept that the URL doesn't update during the OpenContainer transition. The GoRouter route for `groupDetail` remains intact for all other navigation paths (deep links, back navigation from sub-routes). The `useRootNavigator: false` parameter on `OpenContainer` ensures it uses the nearest Navigator (inside ProviderScope + GoRouter's navigator layer) rather than the root, which avoids conflicts with GoRouter's route management.

### Pattern 5: Expense Hero Card Redesign (D-14)

**What:** The current `EventExpenseHero` (in `event_expense_hero.dart`) uses a dark gradient card (AppColors.darkHeaderGradient, 140dp height) with white text. The spec requires a light `AppColors.surface` card with `AppColors.textPrimary` amount and teal chip button.

The spec says: expense hero on `AppColors.surface` background, "TOTAL EXPENSES" overline in `textMuted`, OMR amount in 36px/w800 `textPrimary`, "+ Add Expense" chip in `AppColors.primary`.

This is a visual redesign of `EventExpenseHero` — the data source (`eventExpensesProvider`) stays the same.

### Pattern 6: Group Detail Skeleton (Loading State)

Per spec, loading state uses:
- `SkeletonLoader` primitives from Phase 17 (`SkeletonBar`, `SkeletonCircle`, `SkeletonBlock`)
- Stats grid: 4 `SkeletonBlock` in a 2x2 grid (AppColors.surface bg, AppColors.border shimmer)
- Settle-up area: `SkeletonBar` full-width 52dp
- Member rows: 3 rows of `SkeletonCircle(40dp)` + two `SkeletonBar`s
- Event cards: 2 `SkeletonBlock` cards (surface bg, border shimmer, ~80dp height)
- Activity: 2 `SkeletonBar` rows

The current loading state (`_buildLoading`) renders `CircularProgressIndicator`. This must be replaced.

### Anti-Patterns to Avoid

- **Using `AppColors.accentSecondary`, `AppColors.sky`, `AppColors.indigo`, `AppColors.mint` for module card colors:** These are not in the canonical AppColorTokens.light. Use `AppColors.moduleLedger`, `AppColors.moduleGear`, etc.
- **Using `textMuted` for functional text (balances, labels, expense counts that users must read):** textMuted (#9CA3AF) fails WCAG AA at 2.86:1 on white. Use `textSecondary` for readable secondary info.
- **Nesting ListView inside CustomScrollView:** Use SliverToBoxAdapter to wrap non-sliver widgets inside CustomScrollView. FadeInList is a Column — wrap in SliverToBoxAdapter (established in Phase 18 P03).
- **Passing `state.extra` objects across routes:** Screens take string IDs only, load via providers inside the screen (Phase 19 D-14 rule).
- **Priority-sorting in the module grid:** The 2x3 grid has a fixed visual order (Ledger/Gear/Logistics/Vault/Activity/Memories). Priority sorting was a vertical-list pattern — discard it for the grid layout.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Shimmer skeleton loading | Custom shimmer animation | `SkeletonLoader` (Phase 17, `lib/shared/widgets/skeleton_loader.dart`) | Already built with correct token colors and shimmer |
| Left accent bar on event card | Custom ClipPath or BoxDecoration tricks | `Container(width: 3.0)` + `IntrinsicHeight` row pattern | Simple and correct; IntrinsicHeight makes the bar fill card height |
| Avatar stack (member circles) | Custom stack widget | Standard `Stack` with negative `Padding` margin pattern | 40dp circles, -8dp overlap; straightforward inline |
| Personal balance color logic | Custom color function | Dart 3 switch expression on `net.compareTo(Decimal.zero)` | Already established in BalanceHeroCard and GroupCard |
| Module card grid | New grid widget | `SliverGrid` + existing `SmartModuleCard` | SmartModuleCard already handles summary/description/empty states |
| ContainerTransform | Custom hero animation | `OpenContainer` from `animations: ^2.1.2` | D-05 locked |
| Date-based past/future event detection | New logic | `event.isPast` (already on `Event` model) | Already computed; no new code |

---

## Common Pitfalls

### Pitfall 1: OpenContainer URL Desync
**What goes wrong:** After OpenContainer fires, the browser/deep-link URL remains at `/home` instead of `/group/:gid`. Back navigation from sub-routes within GroupDetailScreen may behave unexpectedly.
**Why it happens:** OpenContainer uses `Navigator.push()` directly, bypassing GoRouter's route tree.
**How to avoid:** Accept that the OpenContainer push is URL-agnostic. Ensure all sub-routes within GroupDetailScreen still use `context.push('/group/$groupId/...')` via GoRouter. The GroupDetail GoRoute entry in `app_router.dart` remains unchanged — it's still valid for all direct navigation paths.
**Warning signs:** `context.canPop()` returns false at unexpected times; back button behavior inconsistency.

### Pitfall 2: SmartModuleCard childAspectRatio Overflow
**What goes wrong:** Module cards overflow their grid cells, causing RenderFlex errors or visual clipping.
**Why it happens:** SmartModuleCard is a Row layout (icon + text + chevron). Its intrinsic height is ~76dp. At crossAxisCount: 2 on a 390px screen (minus 32dp padding and 12dp gap = ~171dp per column), `childAspectRatio: 1.4` gives cell height ≈ 122dp. This should be fine, but title text wrapping or font scaling can overflow.
**How to avoid:** Set `maxLines: 1` and `overflow: TextOverflow.ellipsis` on all Text widgets inside SmartModuleCard (already done). Test with accessibility font scale 1.3x. Consider `childAspectRatio: 2.0` as a safer default.
**Warning signs:** "A RenderFlex overflowed" during hot reload.

### Pitfall 3: Section Reorder Breaking Existing Tests
**What goes wrong:** Tests that find widgets by `GroupKeys.membersAndBalancesSection` or `GroupKeys.eventsSection` may break due to the D-09 reorder (Events first, then Members).
**Why it happens:** The existing GroupDetailScreen renders Members before Events. Tests may assert ordering.
**How to avoid:** Check `group_detail_screen_test.dart` before implementing — update test assertions to reflect the new section order.
**Warning signs:** Test failures citing "expected widget not found at expected position."

### Pitfall 4: GroupBalances `perEventBreakdown` Key Mismatch
**What goes wrong:** Per-event personal balance shows zero or crashes for all events.
**Why it happens:** `perEventBreakdown` is keyed by `participantId → eventId → amount`. If the `currentUid` lookup fails (Firebase not initialized in test, or anonymous auth hasn't resolved), `currentUserBalance` is null and all event balances show as neutral.
**How to avoid:** Use the same null-safe pattern as the current screen: `try { currentUid = FirebaseConfig.currentUser?.uid; } catch (_) { currentUid = null; }`. Test with explicit provider override for `currentUserIdProvider`.
**Warning signs:** Balance line shows "Settled" for all events even when expenses exist.

### Pitfall 5: EventExpenseHero Visual Regression
**What goes wrong:** Ledger tests that key on `EventKeys.spendingHero` break because the hero card visual is changed.
**Why it happens:** `EventExpenseHero` is keyed with `EventKeys.spendingHero`. Tests in `ledger_test.dart` or `events/` feature tests may look for the dark gradient card's specific content.
**How to avoid:** Preserve `EventKeys.spendingHero` Key on the redesigned hero. Review `test/features/ledger_test.dart` for any assertions about the hero card's appearance.
**Warning signs:** Ledger tests fail after event hub redesign.

### Pitfall 6: Module Grid Priority Sorting vs Fixed Order
**What goes wrong:** Module cards appear in the wrong visual positions (e.g., Gear appears before Ledger due to priority score).
**Why it happens:** The existing `EventModuleList` sorts by `priority` score. The new 2x3 grid spec has a fixed visual order.
**How to avoid:** Remove priority sorting in the new grid implementation. Use a fixed-order list: [Ledger, Gear, Logistics, Vault, Activity, Memories].
**Warning signs:** Module grid shows Gear or Logistics in the top-left position.

---

## Code Examples

### Inline Balance Text for EventCard (D-01)
```dart
// Source: established in GroupCard (lib/features/groups/widgets/group_card.dart)
// Pattern: Dart 3 switch on net.compareTo(Decimal.zero)
final (String label, Color color) = switch (userBalance.netBalance.compareTo(Decimal.zero)) {
  < 0 => (
      'You owe OMR ${userBalance.netBalance.abs().toStringAsFixed(3)}',
      AppColors.errorText,
    ),
  > 0 => (
      'You are owed OMR ${userBalance.netBalance.toStringAsFixed(3)}',
      AppColors.successText,
    ),
  _ => ('Settled', AppColors.textSecondary),
};
```

### Past Event Opacity (D-02) — already implemented
```dart
// Source: lib/features/events/widgets/event_card.dart line 151-155
// event.isPast is already computed on the Event model
if (event.isPast) {
  return Opacity(opacity: 0.6, child: card);
}
return card;
```

### StatCard Widget (for 2x2 stats grid, D-08)
```dart
// Source: .planning/design/group-detail-spec.md token mapping
class StatCard extends StatelessWidget {
  final String overline;
  final String value;
  final Color valueColor;

  const StatCard({
    super.key,
    required this.overline,
    required this.value,
    this.valueColor = AppColors.textPrimary,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppColors.space12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppColors.radiusSmall),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            overline,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: AppColors.textMuted,  // DECORATIVE: overline label only
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}
```

### OpenContainer wrapping GroupCard (D-05, D-06)
```dart
// Source: pub.dev/packages/animations — OpenContainer class
// useRootNavigator: false is critical in GoRouter apps
OpenContainer<void>(
  closedColor: Colors.transparent,  // GroupCard has its own bg
  openColor: AppColors.background,
  closedElevation: 0,
  openElevation: 0,
  closedShape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(AppColors.radiusLarge),
  ),
  openShape: const RoundedRectangleBorder(),
  transitionDuration: const Duration(milliseconds: 400),
  transitionType: ContainerTransitionType.fade,
  useRootNavigator: false,
  tappable: true,
  closedBuilder: (context, openContainer) => GroupCard(
    group: group,
    onTap: openContainer,
  ),
  openBuilder: (context, closeContainer) => GroupDetailScreen(
    groupId: group.id,
  ),
)
```

### Module grid corrected colors (SCRN-02)
```dart
// Source: lib/core/theme/tokens/color_tokens.dart AppColorTokens.light
// WRONG (current):   color: AppColors.accentSecondary, AppColors.sky, etc.
// CORRECT (spec):
// Ledger:     color: AppColors.moduleLedger      // Color(0xFF0D7B74)
// Gear:       color: AppColors.moduleGear        // Color(0xFF6B7280)
// Logistics:  color: AppColors.moduleLogistics   // Color(0xFF6B7280)
// Vault:      color: AppColors.moduleVault       // Color(0xFF6B7280)
// Activity:   color: AppColors.moduleActivity    // Color(0xFF6B7280)
// Memories:   color: AppColors.moduleMemories    // Color(0xFF6B7280)
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| EventModuleList: vertical Column, priority-sorted | Phase 20: 2x3 SliverGrid, fixed order | Phase 20 | Spec compliance; visual information density improves |
| GroupDetailScreen: spinner loading state | Phase 20: SkeletonLoader composites | Phase 20 | NAV-05 compliance (already required, not yet done on this screen) |
| EventExpenseHero: dark gradient card | Phase 20: light surface card per spec | Phase 20 | Palette consistency; SCRN-02 compliance |
| GroupCard onTap: context.push() | Phase 20: OpenContainer.openContainer callback | Phase 20 | ContainerTransform for group card tap only |

**Items unchanged by this phase:**
- EventCard.isPast logic (already correct since Phase 18)
- SmartModuleCard widget (no changes needed)
- ModuleHeader widget (no changes needed)
- GoRouter route tree (no new routes, no route changes)
- All module screens (Phase 21 scope)

---

## Open Questions

1. **childAspectRatio for SliverGrid with SmartModuleCard**
   - What we know: SmartModuleCard renders as a horizontal Row (~76dp intrinsic height). On 390px with 32dp padding and 12dp gap, each cell is ~171dp wide.
   - What's unclear: Exact `childAspectRatio` value before device testing. Spec says ~1.4 but this is visual estimate.
   - Recommendation: Start with `childAspectRatio: 2.0` (gives ~85dp height for 171dp width), test at runtime, adjust.

2. **OpenContainer test strategy**
   - What we know: OpenContainer uses Navigator.push internally. Widget tests using `MaterialApp.router()` (the pattern established in Phase 19 P03) may have trouble with OpenContainer since it fires a native push.
   - What's unclear: Whether `MaterialApp(home:)` vs `MaterialApp.router()` affects OpenContainer test behavior.
   - Recommendation: Test the GroupCard-level unit independently (OpenContainer wrapping); use `MaterialApp(home:)` in that specific test file. The HomeScreen integration test can use `MaterialApp.router()` but may skip the OpenContainer transition assertion.

3. **Activity count for module summary (D-12: "N entries")**
   - What we know: No `eventActivityProvider` returning a count exists in the current EventModuleList (Activity card is always `isEmpty: true`, `priority: 10`).
   - What's unclear: Whether Activity count should be wired in Phase 20 or remain empty/deferred.
   - Recommendation: Keep Activity module card as `isEmpty: true` with description "Timeline logs" for Phase 20. Activity count wiring deferred to Phase 21 when the Activity module screen is redesigned.

4. **Memories count for module summary (D-12: "N photos")**
   - What we know: Same as Activity — current Memories card is always `isEmpty: true`.
   - Recommendation: Same as Activity; defer wiring to Phase 21.

---

## Environment Availability

Step 2.6: SKIPPED — this phase involves no external tool dependencies beyond the existing project stack. The only new package (`animations: ^2.1.2`) is a pub.dev Flutter dependency handled by `flutter pub add`.

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | flutter_test (built-in SDK) |
| Config file | none — standard flutter test runner |
| Quick run command | `flutter test test/features/group_detail_screen_test.dart` |
| Full suite command | `flutter test` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| SCRN-01 | Group detail shows event cards with left accent bar (teal/gray) | widget | `flutter test test/features/group_detail_screen_test.dart` | ✅ (needs new test cases) |
| SCRN-01 | Past events render at 60% opacity | widget | `flutter test test/features/group_detail_screen_test.dart` | ✅ (needs new test cases) |
| SCRN-01 | Stats grid shows 4 tiles: YOUR BALANCE, GROUP TOTAL, ACTIVE MEMBERS, EVENTS | widget | `flutter test test/features/group_detail_screen_test.dart` | ✅ (needs new test cases) |
| SCRN-01 | Settle-up CTA shown when balance non-zero, hidden when all settled | widget | `flutter test test/features/group_detail_screen_test.dart` | ✅ (needs new test cases) |
| SCRN-01 | Section order: Events → Members → Activity below fold | widget | `flutter test test/features/group_detail_screen_test.dart` | ✅ (needs new test cases) |
| SCRN-02 | Event hub renders 2x3 SliverGrid with 6 SmartModuleCards | widget | `flutter test test/features/events/` | ❌ Wave 0 |
| SCRN-02 | Module colors match AppColorTokens (moduleLedger for Ledger, moduleGear for others) | widget | `flutter test test/features/events/` | ❌ Wave 0 |
| SCRN-02 | Expense hero card uses light surface bg with teal chip | widget | `flutter test test/features/events/` | ❌ Wave 0 |
| D-04 | ContainerTransform OpenContainer renders GroupDetailScreen | widget | `flutter test test/features/home/` | ❌ Wave 0 |

### Sampling Rate
- **Per task commit:** `flutter test test/features/group_detail_screen_test.dart test/features/ledger_test.dart`
- **Per wave merge:** `flutter test`
- **Phase gate:** `flutter test` — all 744+ tests green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `test/features/events/event_command_center_test.dart` — covers SCRN-02 (event hub grid layout, module colors, expense hero)
- [ ] `test/features/home/home_screen_open_container_test.dart` — covers D-04 (OpenContainer wrapping GroupCard)
- [ ] New test cases in existing `test/features/group_detail_screen_test.dart` — covers SCRN-01 (stats grid, settle-up CTA visibility, section order, event card accent bar)

**Existing test files that need assertion updates due to redesign:**
- `test/features/group_detail_screen_test.dart` — GroupBalanceHero assertion (`GroupKeys.groupBalancesLabel`) will break when stats grid replaces the old hero; test must be updated
- `test/features/ledger_test.dart` — EventExpenseHero (`EventKeys.spendingHero`) tests that assert "SPENDING" label text — will break when hero redesign changes label to "TOTAL EXPENSES"; must update

---

## Project Constraints (from CLAUDE.md)

The following directives from CLAUDE.md are binding on this phase:

| Directive | Impact on Phase 20 |
|-----------|-------------------|
| Immutability — always create new objects, never mutate | All `copyWith` patterns on models; never modify existing provider state in-place |
| 200-400 lines typical per file, 800 max | GroupDetailScreen at 609 lines is near limit; refactor stats grid and event card into extracted widgets |
| Functions < 50 lines | `_buildContent`, `_buildEventsSection` etc. should delegate to extracted widget classes |
| Minimum 80% test coverage; TDD mandatory | Write failing tests for SCRN-01/SCRN-02 assertions before implementing. Wave 0 test files listed above. |
| No hardcoded `Color(0xFF...)` outside token system | Use `AppColors.*` constants only. CI lint rule enforces this (FOUND-04). |
| No imperative Navigator.push() except OpenContainer | OpenContainer's internal push is an accepted exception (D-05 locks it). No other Navigator.push allowed. |
| All screens take string IDs from GoRouter; no state.extra | GroupDetailScreen and EventCommandCenter already comply. GroupDetailScreen in OpenContainer's `openBuilder` receives groupId from closure, not from GoRouter path params — this is acceptable since GoRouter is bypassed for this transition. |
| Financial amounts: Decimal package, OMR 3 decimal places | All balance displays use `toStringAsFixed(3)` and `Decimal` arithmetic |
| textMuted (#9CA3AF) is decorative only, never functional text | Stats overline labels (decorative) can use textMuted. Balance amounts, expense counts, module summaries must use textSecondary or higher. |

---

## Sources

### Primary (HIGH confidence)
- `.planning/design/group-detail-spec.md` — full token mapping, component hierarchy, all 4 states
- `.planning/design/event-hub-spec.md` — full token mapping, component hierarchy, module grid layout
- `lib/core/theme/tokens/color_tokens.dart` — canonical AppColorTokens.light values (verified all module accent tokens)
- `lib/features/events/widgets/event_card.dart` — confirmed `event.isPast` + `Opacity(0.6)` pattern exists
- `lib/features/events/widgets/event_module_list.dart` — confirmed current colors are wrong (accentSecondary, sky, indigo, mint)
- `lib/features/groups/screens/group_detail_screen.dart` — full existing implementation audit (609 lines)
- `lib/features/events/screens/event_command_center.dart` — full existing implementation audit (144 lines)
- `lib/shared/widgets/smart_module_card.dart` — confirmed summary/description/empty state behavior
- `pubspec.yaml` — confirmed `animations` package is NOT yet a dependency; `flutter_animate` IS present

### Secondary (MEDIUM confidence)
- [pub.dev/packages/animations](https://pub.dev/packages/animations) — version 2.1.2 confirmed, OpenContainer constructor parameters verified
- [GitHub flutter/flutter #135975](https://github.com/flutter/flutter/issues/135975) — OpenContainer + GoRouter incompatibility confirmed (issue closed without resolution)
- [GitHub flutter/flutter #51399](https://github.com/flutter/flutter/issues/51399) — OpenContainer + named routes incompatibility, same root cause

### Tertiary (LOW confidence)
- Community workarounds for OpenContainer + GoRouter — multiple Stack Overflow posts suggest `useRootNavigator: false` as partial mitigation; not officially documented

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all packages verified in pubspec.yaml and pub.dev; `animations` version confirmed
- Architecture: HIGH — design specs are canonical and fully token-mapped; existing widgets confirmed via code reading
- Pitfalls: HIGH for OpenContainer/GoRouter (multiple confirmed sources); MEDIUM for childAspectRatio (runtime tuning needed)

**Research date:** 2026-03-30
**Valid until:** 2026-04-30 (stable packages, internal codebase)
