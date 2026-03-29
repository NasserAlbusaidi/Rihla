# Home Screen — Visual Specification

**Phase:** 16
**Status:** Stitch-reviewed
**Target:** ~390px width, single breakpoint
**Palette:** Monochrome neutral + teal — AppColorTokens.light
**Stitch Reference:** `/Users/nasseralbusaidi/Downloads/stitch 2/home_*_state/screen.png` (external; not committed to repo)

---

## Screen States

### State 1: Loaded (Primary)

The screen opens on a white scaffold. There is no gradient hero header — this is a root screen, so no back arrow and no `ModuleHeader`. The title "Your Groups" renders as a large bold heading (28px, weight 800, `AppColors.textPrimary`) in the top-left safe area, with a teal FAB (+) anchored in the top-right corner.

Below the title, a horizontal scrollable strip of three group cards is visible. Each group card sits on a cool-gray (`AppColors.surface`) rounded rectangle. The card shows the group name in `AppColors.textPrimary`, the member count in `AppColors.textSecondary`, and a net balance line: "You owe OMR X" in `AppColors.errorText` or "You are owed OMR X" in `AppColors.successText` or a settled chip with `AppColors.textSecondary`. Cards render with a very light border (1px `AppColors.border`) and no drop shadow — elevation is communicated through the card background against the white scaffold.

Below the group list, a "RECENT ACTIVITY" section label appears in all-caps small text (`AppColors.textMuted`, 11px, weight 600, letter-spacing 0.5) as a decorative-only overline. Beneath it, a flat list of activity rows: avatar circle (48dp), name + action text in `AppColors.textPrimary`/`AppColors.textSecondary`, and a relative timestamp in `AppColors.textMuted`. No dividers between rows — spacing creates separation.

At the very bottom, a weekly spending summary card renders in `AppColors.surface` with teal bar chart glyphs and body text in `AppColors.textSecondary`.

Bottom navigation bar: **Groups | Activity | Chats | Profile**. Active tab icon and label: `AppColors.primary`. Inactive: `AppColors.textMuted`. Bar background: white.

#### Token Mapping

| Visual Area | Token Reference | Hex | Notes |
|-------------|----------------|-----|-------|
| Scaffold background | `AppColors.background` | #FFFFFF | White page |
| "Your Groups" title | `AppColors.textPrimary` | #111827 | 17.15:1 AAA on white |
| FAB (+) background | `AppColors.primary` | #0D7B74 | Teal |
| FAB (+) icon | `AppColors.textOnPrimary` | #FFFFFF | 5.12:1 AA on teal |
| Group card background | `AppColors.surface` | #F8F9FA | Cool gray |
| Group card border | `AppColors.border` | #E5E7EB | 1px hairline |
| Group name | `AppColors.textPrimary` | #111827 | 17.15:1 AAA |
| Member count | `AppColors.textSecondary` | #6B7280 | 5.03:1 AA |
| "You owe" balance text | `AppColors.errorText` | #B91C1C | 6.57:1 AA |
| "You are owed" balance text | `AppColors.successText` | #047857 | 5.92:1 AA |
| "Settled up" balance text | `AppColors.textSecondary` | #6B7280 | 5.03:1 AA |
| Activity section overline | `AppColors.textMuted` | #9CA3AF | DECORATIVE ONLY |
| Activity row name | `AppColors.textPrimary` | #111827 | AAA |
| Activity row action | `AppColors.textSecondary` | #6B7280 | AA |
| Activity row timestamp | `AppColors.textMuted` | #9CA3AF | DECORATIVE ONLY |
| Weekly spending card bg | `AppColors.surface` | #F8F9FA | Lifted card feel |
| Spending chart accent | `AppColors.primary` | #0D7B74 | Teal bars |
| Spending card body text | `AppColors.textSecondary` | #6B7280 | AA |
| Bottom nav active | `AppColors.primary` | #0D7B74 | Groups tab |
| Bottom nav inactive | `AppColors.textMuted` | #9CA3AF | Decorative icon use |
| Bottom nav bar bg | `AppColors.background` | #FFFFFF | White |

#### Component Hierarchy

```
Scaffold(backgroundColor: AppColors.background)
  └── Column
        ├── SafeArea
        │     └── Padding(h: space24, v: space16)
        │           └── Row(mainAxisAlignment: spaceBetween)
        │                 ├── Text("Your Groups", 28px, w800, AppColors.textPrimary)
        │                 └── FloatingActionButton.small(
        │                       backgroundColor: AppColors.primary,
        │                       child: Icon(Icons.add, color: AppColors.textOnPrimary)
        │                     )
        └── Expanded
              └── CustomScrollView
                    ├── SliverToBoxAdapter
                    │     └── GroupCardsList (horizontal scroll or vertical list)
                    │           └── ListView.builder → GroupCard (per group)
                    │                 └── Container(color: AppColors.surface, radius: radiusLarge)
                    │                       └── Column [name, member count, balance line]
                    ├── SliverToBoxAdapter
                    │     └── ActivitySection
                    │           ├── Text("RECENT ACTIVITY", overline, AppColors.textMuted)
                    │           └── ListView.builder → ActivityRow (avatar + text + timestamp)
                    └── SliverToBoxAdapter
                          └── WeeklySpendingCard(color: AppColors.surface)
```

#### Spacing Spec

| Location | Token | Value |
|----------|-------|-------|
| Title horizontal padding | `space24` | 24dp |
| Title vertical padding | `space16` | 16dp |
| Between title bar and group list | `space8` | 8dp |
| Group card horizontal margin | `space16` | 16dp |
| Group card internal padding | `space16` | 16dp |
| Between group card elements (name → members) | `space4` | 4dp |
| Between group cards (vertical list) | `space12` | 12dp |
| Activity section top padding | `space24` | 24dp |
| Activity overline bottom margin | `space8` | 8dp |
| Activity row height (min tap target) | 48dp | per WCAG |
| Between activity rows | `space4` | 4dp |
| Bottom nav bar height | 56dp | OS standard |
| Card border radius | `radiusLarge` | 16dp |
| FAB border radius | 28dp | circular |

#### Interaction Notes

| Trigger | Action | Transition |
|---------|--------|-----------|
| Tap group card | Navigate to Group Detail | `AppPageRoute` (slide-right) |
| Tap FAB (+) | Open "Create Group" bottom sheet | `AppBottomSheetRoute` (slide-up) |
| Tap activity row (group mention) | Navigate to that group | `AppPageRoute` (slide-right) |
| Pull to refresh | Reload groups + activity | Standard RefreshIndicator |
| Tap "Groups" nav tab | Stay (already root screen) | No transition |
| Tap "Activity" nav tab | Navigate to activity feed | `AppPageRoute` or GoRouter push |
| Tap "Chats" nav tab | Navigate to chats | GoRouter push |
| Tap "Profile" nav tab | Navigate to profile | GoRouter push |

---

### State 2: Empty State

White scaffold. Same "Your Groups" title + teal FAB (+) header. No group cards visible.

Vertically centered in the remaining space, `EmptyStateView` renders: a circular gray icon container (72dp, `AppColors.surface`, icon in `AppColors.textMuted`), then "Create your first group" heading (18px, weight 700, `AppColors.textPrimary`), then body text "Plan trips, track expenses, and settle up with friends" (`AppColors.textSecondary`, 14px). Then a full-width teal CTA button "Create Group" (52dp height, `AppColors.primary` background, `AppColors.textOnPrimary` label).

Below the CTA, a social proof strip: overlapping user avatar circles + "+ 2K+ TRAVELERS" label in all-caps small text (`AppColors.textMuted`, decorative).

No activity strip. No spending card. Bottom nav remains visible.

#### Token Mapping

| Visual Area | Token Reference | Hex | Notes |
|-------------|----------------|-----|-------|
| Scaffold background | `AppColors.background` | #FFFFFF | White |
| "Your Groups" title | `AppColors.textPrimary` | #111827 | AAA |
| FAB (+) | `AppColors.primary` | #0D7B74 | Teal |
| Empty state icon container | `AppColors.surface` | #F8F9FA | Gray-50 |
| Empty state icon | `AppColors.textMuted` | #9CA3AF | Decorative icon use |
| "Create your first group" title | `AppColors.textPrimary` | #111827 | AAA |
| Body message | `AppColors.textSecondary` | #6B7280 | AA |
| "Create Group" CTA background | `AppColors.primary` | #0D7B74 | Teal button |
| "Create Group" CTA text | `AppColors.textOnPrimary` | #FFFFFF | 5.12:1 AA on teal |
| Social proof label | `AppColors.textMuted` | #9CA3AF | DECORATIVE ONLY |

#### Component Hierarchy

```
Scaffold(backgroundColor: AppColors.background)
  └── Column
        ├── [Same title + FAB header as Loaded state]
        └── Expanded
              └── EmptyStateView(
                    icon: Iconsax.people,
                    title: "Create your first group",
                    message: "Plan trips, track expenses, and settle up with friends",
                    actionLabel: "Create Group",
                    onAction: () => openCreateGroupSheet(),
                  )
                  // EmptyStateView internally renders:
                  // Container(72dp, AppColors.surface, radius: radiusLarge)
                  // > Icon(color: AppColors.textMuted)
                  // Text(title, AppColors.textPrimary)
                  // Text(message, AppColors.textMuted)
                  // SizedBox(buttonHeight) > ElevatedButton
```

#### Spacing Spec

| Location | Token | Value |
|----------|-------|-------|
| EmptyStateView outer padding | `space32` | 32dp (all sides) |
| Icon container to title gap | `space20` | 20dp |
| Title to message gap | `space8` | 8dp |
| Message to CTA gap | `space24` | 24dp |
| CTA button height | `buttonHeight` | 52dp |
| CTA border radius | `radiusMedium` | 12dp |

#### Interaction Notes

| Trigger | Action | Transition |
|---------|--------|-----------|
| Tap "Create Group" CTA | Open "Create Group" bottom sheet | `AppBottomSheetRoute` (slide-up) |
| Tap FAB (+) | Open "Create Group" bottom sheet | `AppBottomSheetRoute` (slide-up) |

---

### State 3: Loading / Skeleton

White scaffold. No header back arrow. Title area shows "Your Groups" text in `AppColors.textPrimary` (title is rendered immediately; only content skeletons). Three group card skeletons stack vertically — each a `AppColors.surface` rounded rectangle with two skeleton bars inside: a wide one (70% width, `AppColors.border` shimmer) for the group name and a narrower one (40% width) for the balance line. Heights: name bar 14dp, balance bar 10dp.

Below the cards, the "RECENT ACTIVITY" overline skeleton bar (30% width, 8dp height), followed by three activity row skeletons: each row is 48dp tall with a 40dp circle placeholder on the left and two stacked bars on the right.

Bottom nav visible and interactive. No OfflineBanner.

**Reconciliation fix:** The Stitch loading mockup showed "Rihla" as the title and a back arrow — both incorrect for the root screen. The spec locks to "Your Groups" (no back arrow) per reconciliation_decisions.

#### Token Mapping

| Visual Area | Token Reference | Hex | Notes |
|-------------|----------------|-----|-------|
| Scaffold background | `AppColors.background` | #FFFFFF | White |
| "Your Groups" title | `AppColors.textPrimary` | #111827 | Rendered immediately |
| Skeleton card background | `AppColors.surface` | #F8F9FA | Gray-50 container |
| Skeleton shimmer bars | `AppColors.border` | #E5E7EB | Gray-200 placeholder |
| Skeleton avatar circles | `AppColors.border` | #E5E7EB | Gray-200 |

#### Component Hierarchy

```
Scaffold(backgroundColor: AppColors.background)
  └── Column
        ├── [Same title + FAB header — rendered immediately]
        └── Expanded
              └── ListView(
                    padding: EdgeInsets.symmetric(horizontal: space16),
                    children: [
                      // 3x group card skeletons
                      SkeletonGroupCard(),
                      SkeletonGroupCard(),
                      SkeletonGroupCard(),
                      // Activity header skeleton
                      SkeletonBar(width: 0.3, height: 10),
                      // 3x activity row skeletons
                      SkeletonActivityRow(),
                      SkeletonActivityRow(),
                      SkeletonActivityRow(),
                    ]
                  )
                  // SkeletonGroupCard = Container(AppColors.surface, radius: radiusLarge)
                  //   > Column[ SkeletonBar(0.7, 14), SkeletonBar(0.4, 10) ]
                  // SkeletonActivityRow = Row[ Circle(40dp), Column[Bar(0.6, 12), Bar(0.4, 10)] ]
                  // All shimmer bars use SkeletonLoader base widget
```

#### Spacing Spec

| Location | Token | Value |
|----------|-------|-------|
| Card horizontal padding | `space16` | 16dp |
| Card internal padding | `space16` | 16dp |
| Between skeleton bars within card | `space8` | 8dp |
| Between skeleton cards | `space12` | 12dp |
| Activity section top margin | `space24` | 24dp |
| Activity row height | 48dp | touch target |
| Between activity rows | `space4` | 4dp |

#### Interaction Notes

| Trigger | Action | Transition |
|---------|--------|-----------|
| Data loads | Animated crossfade from skeleton to content | Fade 300ms |
| Timeout / error | Transition to Error state | Immediate |

---

### State 4: Error State

White scaffold. `OfflineBanner` is pinned below the status bar in amber (#F59E0B) with white text "No connection — showing cached data". Below the banner, the "Your Groups" title and FAB (+) render normally. The rest of the screen center shows `EmptyStateView` in error configuration: red error icon (Iconsax.wifi_square or similar, displayed at 36dp within the 72dp container), "Something went wrong" title in `AppColors.textPrimary`, body text "Check your connection and try again. Your travel groups are safely synced, but we need the internet to fetch latest updates." in `AppColors.textSecondary`.

Two CTAs: primary teal "Retry" button (52dp, `AppColors.primary`) and a secondary text link "View Offline Data" in `AppColors.primary` (teal, no background).

#### Token Mapping

| Visual Area | Token Reference | Hex | Notes |
|-------------|----------------|-----|-------|
| OfflineBanner background | amber (#F59E0B) | #F59E0B | Not in token system — see Token Gaps |
| OfflineBanner text | `AppColors.textOnPrimary` | #FFFFFF | White on amber |
| Scaffold background | `AppColors.background` | #FFFFFF | White |
| "Your Groups" title | `AppColors.textPrimary` | #111827 | AAA |
| Error icon container | `AppColors.surface` | #F8F9FA | Gray-50 |
| Error icon | `AppColors.error` | #EF4444 | Display-only icon |
| "Something went wrong" heading | `AppColors.textPrimary` | #111827 | AAA |
| Error body text | `AppColors.textSecondary` | #6B7280 | AA |
| "Retry" button background | `AppColors.primary` | #0D7B74 | Teal |
| "Retry" button text | `AppColors.textOnPrimary` | #FFFFFF | 5.12:1 AA |
| "View Offline Data" link | `AppColors.primary` | #0D7B74 | 5.12:1 AA |

#### Component Hierarchy

```
Scaffold(backgroundColor: AppColors.background)
  └── Column
        ├── OfflineBanner()  // watches connectivityProvider
        ├── [Same title + FAB header]
        └── Expanded
              └── EmptyStateView(
                    icon: Iconsax.wifi_square,
                    iconColor: AppColors.error,
                    title: "Something went wrong",
                    message: "Check your connection and try again...",
                    actionLabel: "Retry",
                    onAction: () => ref.refresh(userGroupsProvider),
                  )
              // Below EmptyStateView CTA, add secondary TextButton:
              // TextButton(
              //   child: Text("View Offline Data", style: TextStyle(color: AppColors.primary)),
              //   onPressed: () => navigateToOfflineData(),
              // )
```

#### Spacing Spec

| Location | Token | Value |
|----------|-------|-------|
| OfflineBanner height | 44dp | Fixed banner height |
| OfflineBanner padding | `space16` | 16dp horizontal |
| Between "Retry" CTA and secondary link | `space12` | 12dp |
| Secondary link touch target | 48dp min | per WCAG |

#### Interaction Notes

| Trigger | Action | Transition |
|---------|--------|-----------|
| Tap "Retry" | Refresh `userGroupsProvider` | Loading state → Loaded or Error |
| Tap "View Offline Data" | Navigate to cached groups view | `AppPageRoute` (slide-right) |
| Connection restored | OfflineBanner fades out | Fade 300ms |

---

## Stitch Image References

All Stitch output images are stored externally at:
- `/Users/nasseralbusaidi/Downloads/stitch 2/home_loaded_state/screen.png`
- `/Users/nasseralbusaidi/Downloads/stitch 2/home_empty_state/screen.png`
- `/Users/nasseralbusaidi/Downloads/stitch 2/home_loading_state/screen.png`
- `/Users/nasseralbusaidi/Downloads/stitch 2/home_error_state/screen.png`

These files are NOT committed to the repository. Reference by path for local design review only.

---

## Token Gaps Identified

| Gap Description | Structural or Cosmetic? | Recommended Action |
|----------------|------------------------|-------------------|
| `OfflineBanner` amber color (#F59E0B) has no token in AppColorTokens.light | Structural — needed by OfflineBanner widget today | Add `offlineBannerBackground: Color(0xFFF59E0B)` to AppColorTokens in Phase 18 |
| Bottom navigation bar component not defined in token system | Structural — needed for Phase 18/19 nav rebuild | Add `bottomNavBackground`, `bottomNavActiveIcon`, `bottomNavInactiveIcon` tokens in Phase 18 |
| "Zero balance / settled" state uses `textSecondary` — same as member count metadata | Cosmetic — distinct enough in context | No action needed; document intent |
| Weekly spending card bar chart color — teal (#0D7B74) used as chart bar accent | Cosmetic — maps to `AppColors.primary` | Use `AppColors.primary` directly; no new token needed |
| DESIGN.md primary #006a64 vs token #0D7B74 | Cosmetic — DESIGN.md drafted a different shade | Locked to token #0D7B74 (WCAG 5.12:1 verified). DESIGN.md #006a64 is a candidate only |
| DESIGN.md on-primary #dbfffa vs token #FFFFFF | Cosmetic | Locked to #FFFFFF (cleaner, already verified). #dbfffa noted as candidate |

---

## Post-Generation Checklist Applied

- [x] Check 1 — Color Token Mapping: All colors resolve to AppColorTokens.light tokens. OfflineBanner amber flagged as gap.
- [x] Check 2 — Spacing Consistency: All spacing uses token names (space4–space32). Card radius uses radiusLarge (16dp).
- [x] Check 3 — Component Reuse: EmptyStateView used for both empty and error states. SkeletonLoader used for loading state. OfflineBanner included in error state.
- [x] Check 4 — Accessibility: All text-on-background pairs in WCAG-verified set. textMuted used decoratively only (overlines, timestamps, social proof). Error text uses errorText (#B91C1C) not error (#EF4444).

**Reconciliation applied:** Loading state title changed from "Rihla" to "Your Groups"; back arrow removed (root screen has no back). Nav configuration locked to Groups/Activity/Chats/Profile.
