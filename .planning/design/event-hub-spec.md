# Event Hub Screen — Visual Specification

**Phase:** 16
**Status:** Stitch-reviewed
**Target:** ~390px width, single breakpoint
**Palette:** Monochrome neutral + teal — AppColorTokens.light
**Stitch Reference:** `/Users/nasseralbusaidi/Downloads/stitch 2/event_hub_*_state/screen.png` (external; not committed to repo)

---

## Reconciliation Notes

The Stitch empty state mockup showed incorrect module names: "Expenses", "Itinerary", "Checklist", "Location", "Documents", "Group Chat". The real feature module names (from CLAUDE.md) are: **Ledger, Gear, Logistics, Vault, Activity, Memories**. The spec locks to the real names throughout all states.

The Stitch empty state showed a vertical list layout for modules. The loaded state showed a 2-column grid. Per reconciliation_decisions, the **2x3 grid layout** is used in both loaded and empty states. The vertical list approach is discarded.

The Stitch loading state showed "Plan" as the active nav tab. This spec locks all four states to **Groups | Activity | Chats | Profile** nav, per reconciliation_decisions.

Module accent colors follow the new AppColorTokens.light system (see color_tokens.dart):
- **Ledger:** `AppColors.moduleLedger` (#0D7B74 teal) — primary module, teal accent
- **Gear, Logistics, Vault, Activity, Memories:** `AppColors.moduleGear` / etc. (#6B7280 gray-500) — neutral accent

This is a significant change from the earthy palette's distinct per-module colors (CC6B49, 7A8C5E, 5B7B8C, 8B7355, A67C5B, 9B7A5C). The new system uses teal only for Ledger (financial core) and neutral gray for all other modules. See Token Gaps for the color discrimination discussion.

---

## Screen States

### State 1: Loaded (Primary)

The screen opens with `ModuleHeader(useDarkTheme: true)`. The header has a dark gradient background (`AppColors.headerGradientStart` → `AppColors.headerGradientEnd`). Inside: back arrow (white, 44dp), event name as large display text (28px, weight 800, white), a metadata line below showing participant count and date range in white at 50% opacity, and a vertical-dots overflow menu on the right.

Below the header, an expense hero card sits in `AppColors.surface` (gray-50) with a rounded top. It shows "TOTAL EXPENSES" overline in `AppColors.textMuted` (decorative), the OMR amount in large text (36px, weight 800, `AppColors.textPrimary`). An "+ Add Expense" teal chip button sits below the amount.

The module grid occupies the main content area: a 2-column, 3-row grid of `SmartModuleCard` widgets. Each card sits on `AppColors.surface` background, rounded corners (`radiusLarge` 16dp). The layout is:
- Row 1: Ledger | Gear
- Row 2: Logistics | Vault
- Row 3: Activity | Memories

Each card: icon in a 44dp circle with module accent color fill (Ledger: `moduleLedgerLight` teal-10%, others: `moduleGearLight` gray-100). Icon itself in the accent color. Title in `AppColors.textPrimary` (15px, weight 800). Summary text in `AppColors.textSecondary` (13px, weight 600) if data exists, or description in `AppColors.textMuted` if empty.

A "NEXT DESTINATION" footer card may appear at the bottom of the scroll — a photographic card with a white label overlay showing a destination image (placeholder landscape) with the destination name in `AppColors.textPrimary`. This is a Phase-22 feature and is cosmetic-only in this spec.

A teal FAB ("+") is pinned to the bottom-right for quick expense entry.

#### Token Mapping

| Visual Area | Token Reference | Hex | Notes |
|-------------|----------------|-----|-------|
| Header gradient start | `AppColors.headerGradientStart` | #111827 | Gray-900 |
| Header gradient end | `AppColors.headerGradientEnd` | #1F2937 | Gray-800 |
| Header back arrow | `AppColors.textOnPrimary` | #FFFFFF | White on dark |
| Header overflow menu | `AppColors.textOnPrimary` | #FFFFFF | White on dark |
| Event name | `AppColors.textOnPrimary` | #FFFFFF | White on dark header |
| Header metadata (participants, dates) | `AppColors.textOnPrimary` at 50% opacity | rgba(255,255,255,0.5) | Decorative metadata on dark |
| Expense hero card bg | `AppColors.surface` | #F8F9FA | Gray-50 |
| "TOTAL EXPENSES" overline | `AppColors.textMuted` | #9CA3AF | DECORATIVE ONLY |
| Expense amount | `AppColors.textPrimary` | #111827 | AAA — large financial figure |
| "+ Add Expense" chip bg | `AppColors.primary` | #0D7B74 | Teal |
| "+ Add Expense" chip text | `AppColors.textOnPrimary` | #FFFFFF | 5.12:1 AA |
| Module grid background | `AppColors.background` | #FFFFFF | White scaffold |
| Module card background | `AppColors.surface` | #F8F9FA | Gray-50 |
| Ledger icon container | `AppColors.moduleLedgerLight` | #E6F5F3 | Teal 10% |
| Ledger icon | `AppColors.moduleLedger` | #0D7B74 | Teal |
| Gear icon container | `AppColors.moduleGearLight` | #F3F4F6 | Gray-100 |
| Gear icon | `AppColors.moduleGear` | #6B7280 | Gray-500 |
| Logistics icon container | `AppColors.moduleLogisticsLight` | #F3F4F6 | Gray-100 |
| Logistics icon | `AppColors.moduleLogistics` | #6B7280 | Gray-500 |
| Vault icon container | `AppColors.moduleVaultLight` | #F3F4F6 | Gray-100 |
| Vault icon | `AppColors.moduleVault` | #6B7280 | Gray-500 |
| Activity icon container | `AppColors.moduleActivityLight` | #F3F4F6 | Gray-100 |
| Activity icon | `AppColors.moduleActivity` | #6B7280 | Gray-500 |
| Memories icon container | `AppColors.moduleMemoriesLight` | #F3F4F6 | Gray-100 |
| Memories icon | `AppColors.moduleMemories` | #6B7280 | Gray-500 |
| Module card title | `AppColors.textPrimary` | #111827 | 17.15:1 AAA |
| Module summary text | `AppColors.textSecondary` | #6B7280 | 5.03:1 AA |
| Module empty description | `AppColors.textMuted` | #9CA3AF | DECORATIVE ONLY (SmartModuleCard description) |
| Module card border (default) | `AppColors.border` | #E5E7EB | 1px hairline (via SmartModuleCard borderLight) |
| Module card border (alert) | `AppColors.moduleLedger` at 30% opacity | rgba(13,123,116,0.3) | Alert state — Ledger only |
| FAB background | `AppColors.primary` | #0D7B74 | Teal |
| FAB icon | `AppColors.textOnPrimary` | #FFFFFF | White |

#### Component Hierarchy

```
Scaffold(backgroundColor: AppColors.background)
  └── Column
        ├── ModuleHeader(
        │     useDarkTheme: true,
        │     title: eventName,          // e.g., "Trip A"
        │     subtitle: "$N members",
        │     actions: [OverflowMenuButton()],
        │     bottom: Text("$date1 – $date2", style: white 50% opacity),
        │   )
        └── Expanded
              └── CustomScrollView
                    ├── SliverToBoxAdapter
                    │     └── ExpenseHeroCard(
                    │           bg: AppColors.surface,
                    │           radius: radiusLarge,
                    │           child: Column[
                    │             Text("TOTAL EXPENSES", AppColors.textMuted, overline),
                    │             Text(amount, 36px w800, AppColors.textPrimary),
                    │             OutlinedButton.icon(
                    │               icon: Icon(Icons.add, color: AppColors.textOnPrimary),
                    │               label: Text("Add Expense"),
                    │               style: filled teal (AppColors.primary),
                    │             ),
                    │           ]
                    │         )
                    └── SliverPadding(padding: space16)
                          └── SliverGrid(
                                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  crossAxisSpacing: space12,
                                  mainAxisSpacing: space12,
                                  childAspectRatio: ~1.4,  // tuned to content
                                ),
                                children: [
                                  SmartModuleCard(
                                    icon: Iconsax.receipt_1,
                                    title: "Ledger",
                                    description: "Settle balances",
                                    color: AppColors.moduleLedger,     // #0D7B74
                                    summaryText: "3 expenses, OMR 45.500",
                                    isEmpty: false,
                                    onTap: () => navigateToLedger(),
                                  ),
                                  SmartModuleCard(
                                    icon: Iconsax.bag_2,
                                    title: "Gear",
                                    description: "Packing checklist",
                                    color: AppColors.moduleGear,        // #6B7280
                                    summaryText: "12 items",
                                    isEmpty: false,
                                    onTap: () => navigateToGear(),
                                  ),
                                  SmartModuleCard(
                                    title: "Logistics",
                                    description: "Routes & trips",
                                    color: AppColors.moduleLogistics,   // #6B7280
                                    onTap: () => navigateToLogistics(),
                                  ),
                                  SmartModuleCard(
                                    title: "Vault",
                                    description: "Documents",
                                    color: AppColors.moduleVault,       // #6B7280
                                    onTap: () => navigateToVault(),
                                  ),
                                  SmartModuleCard(
                                    title: "Activity",
                                    description: "Timeline logs",
                                    color: AppColors.moduleActivity,    // #6B7280
                                    onTap: () => navigateToActivity(),
                                  ),
                                  SmartModuleCard(
                                    title: "Memories",
                                    description: "Captions",
                                    color: AppColors.moduleMemories,    // #6B7280
                                    onTap: () => navigateToMemories(),
                                  ),
                                ],
                              )
        └── FloatingActionButton(
              backgroundColor: AppColors.primary,
              child: Icon(Icons.add, color: AppColors.textOnPrimary),
              onPressed: () => openAddExpenseSheet(),
            )
```

#### Spacing Spec

| Location | Token | Value |
|----------|-------|-------|
| Header horizontal padding | `space24` | 24dp |
| Header top safe area | `space12` | 12dp |
| Header bottom padding | `space32` | 32dp |
| Expense hero card margin | `space16` | 16dp horizontal, `space16` vertical |
| Expense hero card internal padding | `space20` | 20dp |
| Expense hero overline bottom margin | `space4` | 4dp |
| Expense amount bottom margin | `space16` | 16dp |
| Module grid padding | `space16` | 16dp all sides |
| Grid column gap | `space12` | 12dp |
| Grid row gap | `space12` | 12dp |
| Module card internal padding | `space16` | 16dp (via SmartModuleCard) |
| Module icon container size | 44dp | Fixed (via SmartModuleCard) |
| Module icon container radius | 14dp | Fixed (via SmartModuleCard) |
| FAB bottom padding | `space20` | 20dp above bottom nav |
| FAB right padding | `space20` | 20dp |

#### Interaction Notes

| Trigger | Action | Transition |
|---------|--------|-----------|
| Tap back arrow | Pop to Group Detail | Slide-left |
| Tap "Ledger" card | Navigate to Ledger module screen | `AppPageRoute` (slide-right) |
| Tap "Gear" card | Navigate to Gear module screen | `AppPageRoute` (slide-right) |
| Tap "Logistics" card | Navigate to Logistics module screen | `AppPageRoute` (slide-right) |
| Tap "Vault" card | Navigate to Vault module screen | `AppPageRoute` (slide-right) |
| Tap "Activity" card | Navigate to Activity module screen | `AppPageRoute` (slide-right) |
| Tap "Memories" card | Navigate to Memories module screen | `AppPageRoute` (slide-right) |
| Tap "+ Add Expense" chip | Open add expense bottom sheet | `AppBottomSheetRoute` (slide-up) |
| Tap FAB (+) | Open add expense bottom sheet | `AppBottomSheetRoute` (slide-up) |
| Tap overflow menu (⋮) | Show event options menu | MaterialMenu or bottom sheet |
| Pull to refresh | Reload event data | Standard RefreshIndicator |

---

### State 2: Empty State

Dark gradient header is preserved (consistent across all states). Header shows event name, participant count (e.g., "0 participants"), and date range.

Below the header, the expense hero card shows "OMR 0.000" in `AppColors.textPrimary` (not `errorText` — zero is neutral, not negative) and a prominent "+ Add Expense" teal chip button.

The 2x3 module grid renders with all six `SmartModuleCard` widgets in their `isEmpty: true` state. In empty state, each card shows the `description` text in `AppColors.textMuted` instead of `summaryText`. The icon container uses a lighter opacity fill (6% vs 12% when has data). No alert dots. The grid layout and card structure are identical to the loaded state — only the data inside differs.

No FAB or a FAB is still shown for quick expense entry.

**Stitch reconciliation:** The Stitch empty state showed a vertical list of modules and incorrect names. Both are overridden: grid layout and real module names are canonical.

#### Token Mapping

| Visual Area | Token Reference | Hex | Notes |
|-------------|----------------|-----|-------|
| Header (gradient) | Same as loaded state | #111827 → #1F2937 | Consistent |
| Expense amount (zero) | `AppColors.textPrimary` | #111827 | Zero is neutral — not error |
| "+ Add Expense" chip | `AppColors.primary` | #0D7B74 | Always visible |
| Module card bg | `AppColors.surface` | #F8F9FA | Same as loaded |
| Module icon container (empty) | module*Light at 6% opacity | — | SmartModuleCard(isEmpty: true) halves opacity |
| Module icon (empty) | `AppColors.moduleGear` or `moduleLedger` | #6B7280 or #0D7B74 | Same color, lighter container |
| Module title | `AppColors.textPrimary` | #111827 | AAA — unchanged |
| Module description (empty state text) | `AppColors.textMuted` | #9CA3AF | DECORATIVE per SmartModuleCard |
| Module card border (default) | `AppColors.border` at base opacity | #E5E7EB | Via SmartModuleCard borderLight |

#### Component Hierarchy

```
Scaffold(backgroundColor: AppColors.background)
  └── Column
        ├── ModuleHeader(useDarkTheme: true, title: eventName, ...)
        └── Expanded
              └── CustomScrollView
                    ├── SliverToBoxAdapter → ExpenseHeroCard(amount: "OMR 0.000")
                    └── SliverPadding(space16)
                          └── SliverGrid(crossAxisCount: 2, ...)
                                → SmartModuleCard x6 (all isEmpty: true)
                                  // descriptions shown instead of summaryText
        └── FloatingActionButton(bg: AppColors.primary, ...)
```

#### Spacing Spec

| Location | Token | Value |
|----------|-------|-------|
| Same grid layout as loaded state | — | — |
| All spacing identical to loaded state | — | Grid and card padding unchanged |

#### Interaction Notes

| Trigger | Action | Transition |
|---------|--------|-----------|
| Tap any module card | Navigate to that module | `AppPageRoute` (slide-right) |
| Tap "+ Add Expense" | Open add expense sheet | `AppBottomSheetRoute` (slide-up) |
| Tap FAB | Open add expense sheet | `AppBottomSheetRoute` (slide-up) |

---

### State 3: Loading / Skeleton

Dark gradient header renders immediately (event name is a navigation parameter). Back arrow and overflow menu are active.

Below the header, the expense hero area shows a skeleton: a wide shimmer bar (80% width, 24dp height) for the amount, and a narrower bar (40% width, 16dp) below for the Add Expense chip area. Both bars use `AppColors.border` (#E5E7EB) shimmer on `AppColors.surface` (#F8F9FA) background.

The module grid shows 6 skeleton module cards in the same 2x3 layout. Each skeleton card: a 44dp circle placeholder for the icon, two bars for title and subtitle — all in `AppColors.surface` / `AppColors.border`.

**Stitch reconciliation:** The loading mockup showed individual large 2-column skeleton cards. This matches the intended 2x3 grid skeleton pattern — consistent with the loaded layout.

#### Token Mapping

| Visual Area | Token Reference | Hex | Notes |
|-------------|----------------|-----|-------|
| Header (gradient) | Renders immediately | #111827 → #1F2937 | Name available from nav params |
| Expense hero skeleton bg | `AppColors.surface` | #F8F9FA | Card container |
| Skeleton shimmer bars | `AppColors.border` | #E5E7EB | Gray-200 |
| Module card skeleton bg | `AppColors.surface` | #F8F9FA | Same as loaded |
| Icon circle skeleton | `AppColors.border` | #E5E7EB | 44dp circle |

#### Component Hierarchy

```
Scaffold(backgroundColor: AppColors.background)
  └── Column
        ├── ModuleHeader(useDarkTheme: true, title: eventName, ...)
        └── Expanded
              └── CustomScrollView
                    ├── SliverToBoxAdapter
                    │     └── SkeletonExpenseHero()
                    │           └── Container(AppColors.surface, radius: radiusLarge)
                    │                 > Column[
                    │                     SkeletonBar(0.8, 24),  // amount
                    │                     SkeletonBar(0.4, 16),  // chip
                    │                   ]
                    └── SliverPadding(space16)
                          └── SliverGrid(crossAxisCount: 2, ...)
                                → SkeletonModuleCard x6
                                  └── Container(AppColors.surface, radius: radiusLarge)
                                        > Column[
                                            Circle(44dp, AppColors.border),
                                            SkeletonBar(0.7, 14),
                                            SkeletonBar(0.5, 10),
                                          ]
```

#### Spacing Spec

| Location | Token | Value |
|----------|-------|-------|
| Same grid layout as loaded state | — | — |
| Skeleton bar internal heights | fixed | 24dp amount, 16dp chip, 14dp title, 10dp subtitle |

#### Interaction Notes

| Trigger | Action | Transition |
|---------|--------|-----------|
| Data loads | Crossfade skeleton to content | Fade 300ms |
| Load error | Transition to Error state | Immediate |

---

### State 4: Error State

`OfflineBanner` pinned at top (amber #F59E0B). Dark gradient header renders with back arrow and event name.

Below the header, a large vertical whitespace, then `EmptyStateView` in error configuration: cloud-slash icon, "Couldn't load event" title in `AppColors.textPrimary`, body text "Check your connection and try again." in `AppColors.textSecondary`, and a teal "Retry" button with a circular refresh icon prefix.

No module grid, no expense card shown.

#### Token Mapping

| Visual Area | Token Reference | Hex | Notes |
|-------------|----------------|-----|-------|
| OfflineBanner background | amber (#F59E0B) | #F59E0B | See Token Gaps |
| OfflineBanner text | `AppColors.textOnPrimary` | #FFFFFF | White on amber |
| Header (gradient) | `AppColors.headerGradientStart` → End | #111827 → #1F2937 | Consistent |
| Error icon | `AppColors.error` | #EF4444 | Display-only icon in container |
| Error icon container | `AppColors.surface` | #F8F9FA | Gray-50 |
| "Couldn't load event" heading | `AppColors.textPrimary` | #111827 | AAA |
| Error body | `AppColors.textSecondary` | #6B7280 | AA |
| "Retry" button bg | `AppColors.primary` | #0D7B74 | Teal |
| "Retry" button icon | `AppColors.textOnPrimary` | #FFFFFF | White refresh icon |
| "Retry" button text | `AppColors.textOnPrimary` | #FFFFFF | 5.12:1 AA |

#### Component Hierarchy

```
Scaffold(backgroundColor: AppColors.background)
  └── Column
        ├── OfflineBanner()
        ├── ModuleHeader(useDarkTheme: true, title: eventName, ...)
        └── Expanded
              └── EmptyStateView(
                    icon: Iconsax.cloud_cross,
                    iconColor: AppColors.error,
                    title: "Couldn't load event",
                    message: "Check your connection and try again.",
                    actionLabel: "Retry",
                    onAction: () => ref.refresh(eventProvider(eventRef)),
                  )
```

#### Spacing Spec

| Location | Token | Value |
|----------|-------|-------|
| OfflineBanner height | 44dp | Fixed |
| EmptyStateView padding | `space32` | 32dp all sides |

#### Interaction Notes

| Trigger | Action | Transition |
|---------|--------|-----------|
| Tap "Retry" | Refresh `eventProvider(eventRef)` | Loading → Loaded or Error |
| Tap back | Pop to Group Detail | Slide-left |
| Connection restored | OfflineBanner fades, reload auto-triggers | Fade 300ms |

---

## Stitch Image References

All Stitch output images are stored externally at:
- `/Users/nasseralbusaidi/Downloads/stitch 2/event_hub_loaded_state/screen.png`
- `/Users/nasseralbusaidi/Downloads/stitch 2/event_hub_empty_state/screen.png`
- `/Users/nasseralbusaidi/Downloads/stitch 2/event_hub_loading_state/screen.png`
- `/Users/nasseralbusaidi/Downloads/stitch 2/event_hub_error_state/screen.png`

These files are NOT committed to the repository. Reference by path for local design review only.

---

## Token Gaps Identified

| Gap Description | Structural or Cosmetic? | Recommended Action |
|----------------|------------------------|-------------------|
| `OfflineBanner` amber (#F59E0B) has no token in AppColorTokens.light | Structural — needed by OfflineBanner today | Add `offlineBannerBackground: Color(0xFFF59E0B)` to AppColorTokens in Phase 18 |
| Module color discrimination — all non-Ledger modules share gray (#6B7280) making them visually indistinguishable by color alone | Structural — significant UX concern for a 6-module grid | Decision required in Phase 20: (a) differentiate by distinct neutral shades per module, or (b) rely on icon shape + label as primary differentiator. If (a): add `moduleGearAlt`, `moduleLogisticsAlt`, etc. in AppColorTokens. |
| Expense amount at zero uses `textPrimary` but loaded state might use `errorText` for negative / `successText` for positive net — the hero amount color logic is underspecified | Structural — needed for correct implementation | Define rule: hero shows total spent (always positive or zero) → always `textPrimary`. Per-person net balance in member rows → errorText/successText. Document this as a semantic constraint. |
| "NEXT DESTINATION" photographic footer card in loaded state has no token mapping — uses natural photography overlay | Cosmetic — Phase 22 feature, not needed in Phase 20/21 | Defer entirely to Phase 22. Do not implement in Phase 20. |
| SmartModuleCard chevron color (`AppColors.textMuted` when empty, `AppColors.textSecondary` when has data) — this distinction exists in current code and should be preserved | Cosmetic — already implemented in SmartModuleCard | No change needed; document that the existing SmartModuleCard behavior is correct |
| Header metadata white at 50% opacity — this requires `Colors.white.withValues(alpha: 0.5)` which is not a named token | Cosmetic — common pattern already used in ModuleHeader dark build | Use existing pattern `Colors.white.withValues(alpha: 0.5)` inline; no new token needed |

---

## Post-Generation Checklist Applied

- [x] Check 1 — Color Token Mapping: All module accent colors map to AppColorTokens.light (moduleLedger = teal, all others = gray-500). Module names corrected to real feature names. OfflineBanner amber flagged as gap.
- [x] Check 2 — Spacing Consistency: 2x3 grid layout with space12 gaps. Card padding space16. All values on 4dp grid.
- [x] Check 3 — Component Reuse: SmartModuleCard used for all 6 module slots. ModuleHeader(useDarkTheme: true) for header. EmptyStateView for error state. SkeletonLoader pattern for loading state. OfflineBanner in error state.
- [x] Check 4 — Accessibility: All body text uses textPrimary/textSecondary on white/gray — WCAG AA. Expense amount uses textPrimary (AAA). Module titles use textPrimary (AAA). Module description/empty text uses textMuted — DECORATIVE ONLY in SmartModuleCard (not functional text). FAB and chip text use textOnPrimary on primary — 5.12:1 AA.

**Reconciliation applied:** Module names corrected (Expenses→Ledger, Itinerary→Logistics, Checklist→Gear, Location→Vault, Documents→Vault conflict resolved — Vault for documents per CLAUDE.md, Group Chat dropped — Chats is a separate nav tab, not an event module). Layout changed from vertical list to 2x3 grid in all states. Nav config locked to Groups/Activity/Chats/Profile.
