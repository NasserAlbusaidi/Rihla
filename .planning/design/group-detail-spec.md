# Group Detail Screen — Visual Specification

**Phase:** 16
**Status:** Stitch-reviewed
**Target:** ~390px width, single breakpoint
**Palette:** Monochrome neutral + teal — AppColorTokens.light
**Stitch Reference:** `/Users/nasseralbusaidi/Downloads/stitch 2/group_detail_*_state/screen.png` (external; not committed to repo)

---

## Reconciliation Notes

The Stitch loaded state and empty state mockups have different header treatments — the loaded state shows a compact dark-header with stat chips, while the empty state shows a white editorial header with large display text. Per reconciliation_decisions:
- **All four states use the dark gradient header** (`ModuleHeader(useDarkTheme: true)`) for visual hierarchy consistency.
- The editorial display text approach from the empty state is incorporated into the dark header as the group name.
- The stats grid from the empty state appears in the loaded state below the header.
- Bottom navigation for Group Detail is locked to **Groups | Expenses | Activity | Profile** (as seen in loaded and empty state mockups). Do NOT use the Home screen nav tabs here.

---

## Screen States

### State 1: Loaded (Primary)

The screen opens with `ModuleHeader(useDarkTheme: true)`. The header renders a dark gradient background (`AppColors.headerGradientStart` #111827 → `AppColors.headerGradientEnd` #1F2937). Inside the header: a back arrow (white, 44dp touch target) on the left, a settings gear icon on the right. Below the back row, a small label chip in `AppColors.primary` teal reading "GROUP" (or the group type). Then the group name as large display text (28px, weight 800, white). Below the name, an overlapping avatar stack of member circles with a "+N" overflow chip, followed by an invite code chip (teal background, white label).

Below the header, the content area begins. A 2x2 stats grid shows four stats in `AppColors.surface` (gray-50) cards: "YOUR BALANCE" with amount in `AppColors.errorText`/`AppColors.successText`, "GROUP TOTAL" in `AppColors.textPrimary`, "ACTIVE MEMBERS" count in `AppColors.textPrimary`, "DAYS LEFT" count in `AppColors.textPrimary`. Stat card borders use `AppColors.border`.

A "Settle Up" CTA button (`AppColors.primary`, 52dp, full-width) follows if any balance is non-zero.

The "Member Balances" section renders as a flat list (no card, no dividers — spacing creates separation). Each member row: avatar circle (40dp) on left, name in `AppColors.textPrimary`, balance amount right-aligned in `AppColors.errorText`/`AppColors.successText`/`AppColors.textSecondary` (for zero).

The "EVENTS" section shows event cards. Each event card has a left accent bar in the event-type color (all map to `AppColors.primary` teal per token system — see Token Gaps for color discrimination discussion), event name in `AppColors.textPrimary`, date range in `AppColors.textSecondary`, and expense count in `AppColors.textMuted` (decorative metadata).

The "RECENT ACTIVITY" section at the bottom follows the same flat list pattern as Home.

#### Token Mapping

| Visual Area | Token Reference | Hex | Notes |
|-------------|----------------|-----|-------|
| Header background start | `AppColors.headerGradientStart` | #111827 | Gray-900 |
| Header background end | `AppColors.headerGradientEnd` | #1F2937 | Gray-800 |
| Header back arrow | `AppColors.textOnPrimary` | #FFFFFF | White on dark |
| Header settings icon | `AppColors.textOnPrimary` | #FFFFFF | White on dark |
| Group type chip background | `AppColors.primary` | #0D7B74 | Teal |
| Group type chip text | `AppColors.textOnPrimary` | #FFFFFF | 5.12:1 AA |
| Group name | `AppColors.textOnPrimary` | #FFFFFF | White on dark header |
| Invite code chip bg | `AppColors.selectionFill` | #E6F5F3 | Teal 10% |
| Invite code chip text | `AppColors.primary` | #0D7B74 | AA on teal-10% tint |
| Content area background | `AppColors.background` | #FFFFFF | White scaffold |
| Stats grid card bg | `AppColors.surface` | #F8F9FA | Gray-50 |
| Stats grid card border | `AppColors.border` | #E5E7EB | Gray-200 |
| Stats overline label | `AppColors.textMuted` | #9CA3AF | DECORATIVE ONLY |
| Stats value (neutral) | `AppColors.textPrimary` | #111827 | AAA |
| Stats value (owed) | `AppColors.errorText` | #B91C1C | 6.57:1 AA |
| Stats value (positive) | `AppColors.successText` | #047857 | 5.92:1 AA |
| "Settle Up" button bg | `AppColors.primary` | #0D7B74 | Teal |
| "Settle Up" button text | `AppColors.textOnPrimary` | #FFFFFF | 5.12:1 AA |
| Member row name | `AppColors.textPrimary` | #111827 | AAA |
| Member balance (owed) | `AppColors.errorText` | #B91C1C | 6.57:1 AA |
| Member balance (owes you) | `AppColors.successText` | #047857 | 5.92:1 AA |
| Member balance (zero) | `AppColors.textSecondary` | #6B7280 | AA |
| Event card background | `AppColors.surface` | #F8F9FA | Gray-50 |
| Event card accent bar | `AppColors.primary` | #0D7B74 | Teal (all types; see Token Gaps) |
| Event name | `AppColors.textPrimary` | #111827 | AAA |
| Event date | `AppColors.textSecondary` | #6B7280 | AA |
| Event expense count | `AppColors.textMuted` | #9CA3AF | DECORATIVE ONLY |
| Activity section overline | `AppColors.textMuted` | #9CA3AF | DECORATIVE ONLY |
| Activity row name | `AppColors.textPrimary` | #111827 | AAA |
| Activity row action | `AppColors.textSecondary` | #6B7280 | AA |
| Activity timestamp | `AppColors.textMuted` | #9CA3AF | DECORATIVE ONLY |

#### Component Hierarchy

```
Scaffold(backgroundColor: AppColors.background)
  └── Column
        ├── ModuleHeader(
        │     useDarkTheme: true,
        │     title: groupName,
        │     subtitle: "GROUP",      // or event type label
        │     actions: [SettingsIconButton()],
        │     bottom: Row[
        │       AvatarStack(),
        │       InviteCodeChip(color: AppColors.selectionFill),
        │     ],
        │   )
        └── Expanded
              └── CustomScrollView
                    ├── SliverToBoxAdapter
                    │     └── StatsGrid (2x2 GridView)
                    │           └── StatCard x4 (bg: AppColors.surface, border: AppColors.border)
                    │                 ├── Text(overline, AppColors.textMuted)
                    │                 └── Text(value, AppColors.textPrimary / errorText / successText)
                    ├── SliverToBoxAdapter
                    │     └── Padding(h: space16, v: space12)
                    │           └── SizedBox(buttonHeight: 52)
                    │                 └── ElevatedButton("Settle Up", bg: AppColors.primary)
                    ├── SliverToBoxAdapter
                    │     └── MemberBalancesSection
                    │           ├── Text("Member Balances", AppColors.textPrimary, 16px w700)
                    │           └── Column → MemberRow x N
                    │                 └── Row[ Avatar(40dp), Text(name), Text(balance) ]
                    ├── SliverList
                    │     └── EventCard x N
                    │           └── Container(bg: AppColors.surface, radius: radiusLarge)
                    │                 └── Row[
                    │                       AccentBar(color: AppColors.primary, width: 3dp),
                    │                       Column[name, date, expense count]
                    │                     ]
                    └── SliverToBoxAdapter
                          └── ActivitySection (same pattern as Home)
```

#### Spacing Spec

| Location | Token | Value |
|----------|-------|-------|
| Header horizontal padding | `space24` | 24dp |
| Header top safe area | `space12` | 12dp |
| Header bottom padding | `space32` | 32dp |
| Stats grid horizontal padding | `space16` | 16dp |
| Stats grid top margin | `space16` | 16dp |
| Stats grid gap | `space8` | 8dp |
| Stats card internal padding | `space12` | 12dp |
| Stats card border radius | `radiusSmall` | 8dp |
| "Settle Up" section padding | `space16` | 16dp horizontal, `space12` vertical |
| "Settle Up" button height | `buttonHeight` | 52dp |
| "Member Balances" label top margin | `space24` | 24dp |
| Member row height (min) | 56dp | exceeds 48dp target |
| Between member rows | `space4` | 4dp |
| Event card padding | `space16` | 16dp |
| Between event cards | `space8` | 8dp |
| Event card border radius | `radiusLarge` | 16dp |
| Event accent bar width | 3dp | No token — inline value |
| Activity section top margin | `space24` | 24dp |
| Avatar size | 40dp | No token — inline value |
| Avatar overlap | -8dp | Negative margin for stack |

#### Interaction Notes

| Trigger | Action | Transition |
|---------|--------|-----------|
| Tap back arrow | Pop to Home | `AppPageRoute` reverse (slide-left) |
| Tap "Settle Up" button | Open settle-up bottom sheet | `AppBottomSheetRoute` (slide-up) |
| Tap event card | Navigate to Event Hub for that event | `AppPageRoute` (slide-right) |
| Tap member row | Open member detail bottom sheet | `AppBottomSheetRoute` (slide-up) |
| Tap invite code chip | Copy invite code to clipboard | Toast notification |
| Tap settings icon | Navigate to group settings | `AppPageRoute` (slide-right) |
| Tap "Create Event" FAB (if no events yet) | Open create event flow | `AppBottomSheetRoute` (slide-up) |
| Pull to refresh | Reload group data | Standard RefreshIndicator |

---

### State 2: Empty State

The dark gradient header is preserved (visual consistency across all states). The header shows back arrow, group name as display text (28px, weight 800, white), and settings icon.

Below the header, the 2x2 stats grid shows all four stats with zero/empty values ("$0.00", "0 members" etc.) in their appropriate token colors.

A disabled-style "Settle Up" button appears grayed out (background `AppColors.disabled`, text `AppColors.disabledText`) since there is nothing to settle.

The "Member Balances" section renders three member rows (populated from actual members, even if no expenses yet) with all balances showing "$0.00" in `AppColors.textSecondary`.

In the events section, `EmptyStateView` renders centered: icon, "Create your first event" title, body text "Add a trip, dinner, or any occasion to track together.", and a teal "Create Event" CTA.

Recent Activity section shows "No activity yet" in `AppColors.textMuted` (decorative placeholder).

#### Token Mapping

| Visual Area | Token Reference | Hex | Notes |
|-------------|----------------|-----|-------|
| Header (gradient) | Same as loaded state | #111827 → #1F2937 | Consistent across states |
| Stats values (zero) | `AppColors.textPrimary` | #111827 | Zero balance shows primary |
| "Settle Up" disabled bg | `AppColors.disabled` | #E5E7EB | Gray-200 |
| "Settle Up" disabled text | `AppColors.disabledText` | #9CA3AF | Below AA — disabled state only |
| Member balance (zero) | `AppColors.textSecondary` | #6B7280 | AA |
| EmptyStateView icon | `AppColors.textMuted` | #9CA3AF | Decorative icon |
| "Create your first event" title | `AppColors.textPrimary` | #111827 | AAA |
| Event empty body text | `AppColors.textSecondary` | #6B7280 | AA |
| "Create Event" CTA bg | `AppColors.primary` | #0D7B74 | Teal |
| "Create Event" CTA text | `AppColors.textOnPrimary` | #FFFFFF | 5.12:1 AA |
| "No activity yet" placeholder | `AppColors.textMuted` | #9CA3AF | DECORATIVE ONLY |

#### Component Hierarchy

```
Scaffold(backgroundColor: AppColors.background)
  └── Column
        ├── ModuleHeader(useDarkTheme: true, title: groupName, ...)
        └── Expanded
              └── CustomScrollView
                    ├── SliverToBoxAdapter → StatsGrid (zeros)
                    ├── SliverToBoxAdapter → ElevatedButton("Settle Up", disabled state)
                    ├── SliverToBoxAdapter → MemberBalancesSection (all $0.00)
                    ├── SliverToBoxAdapter
                    │     └── EmptyStateView(
                    │           icon: Iconsax.calendar_add,
                    │           title: "Create your first event",
                    │           message: "Add a trip, dinner, or any occasion to track together.",
                    │           actionLabel: "+ Create Event",
                    │           onAction: () => openCreateEventFlow(),
                    │         )
                    └── SliverToBoxAdapter
                          └── Text("No activity yet", AppColors.textMuted, centered)
```

#### Spacing Spec

| Location | Token | Value |
|----------|-------|-------|
| Same as loaded state for header and stats | — | — |
| EmptyStateView container padding | `space32` | 32dp all sides |
| EmptyStateView icon to title gap | `space20` | 20dp |
| EmptyStateView title to body gap | `space8` | 8dp |
| EmptyStateView body to CTA gap | `space24` | 24dp |

#### Interaction Notes

| Trigger | Action | Transition |
|---------|--------|-----------|
| Tap "+ Create Event" | Open create event flow | `AppBottomSheetRoute` (slide-up) |
| Tap "Settle Up" (disabled) | No action — button inert | — |
| Tap back | Pop to Home | Slide-left |

---

### State 3: Loading / Skeleton

Dark gradient header renders immediately (group name is available from navigation parameters before async load). The back arrow and settings icon are active.

Below the header, the stats grid area shows 4 skeleton placeholders in `AppColors.surface` cards with `AppColors.border` shimmer bars. The "Settle Up" button area shows a full-width skeleton bar (52dp height, `AppColors.surface` background, `AppColors.border` shimmer).

The "Members" section shows the label text "Members" rendered (it's static), followed by 3 skeleton member rows: each row has a 40dp circle placeholder and two bars (name and balance).

Event cards section shows 2 skeleton cards. Activity section shows 2 skeleton rows.

#### Token Mapping

| Visual Area | Token Reference | Hex | Notes |
|-------------|----------------|-----|-------|
| Header (gradient) | Same as loaded state | #111827 → #1F2937 | Renders immediately |
| Skeleton card/container bg | `AppColors.surface` | #F8F9FA | Gray-50 |
| Skeleton shimmer bars | `AppColors.border` | #E5E7EB | Gray-200 |
| "Members" section label | `AppColors.textPrimary` | #111827 | Static — rendered immediately |

#### Component Hierarchy

```
Scaffold(backgroundColor: AppColors.background)
  └── Column
        ├── ModuleHeader(useDarkTheme: true, title: groupName, ...)
        └── Expanded
              └── ListView(
                    children: [
                      SkeletonStatsGrid(),         // 2x2 grid of SkeletonStatCard
                      SkeletonBar(full-width, 52), // "Settle Up" placeholder
                      Text("Members", AppColors.textPrimary),
                      Container(AppColors.surface, radius: radiusLarge)
                        > Column[ SkeletonMemberRow x3 ],
                      SkeletonEventCard x2,
                      SkeletonActivityRow x2,
                    ]
                  )
```

#### Spacing Spec

| Location | Token | Value |
|----------|-------|-------|
| Horizontal padding | `space16` | 16dp |
| Stats grid gap | `space8` | 8dp |
| Between sections | `space24` | 24dp |
| Skeleton bar height (name) | 14dp | Fixed |
| Skeleton bar height (subtitle) | 10dp | Fixed |

#### Interaction Notes

| Trigger | Action | Transition |
|---------|--------|-----------|
| Data loads | Crossfade from skeleton to content | Fade 300ms |
| Load error | Transition to Error state | Immediate |

---

### State 4: Error State

`OfflineBanner` pinned at top (amber #F59E0B). Dark gradient header renders with back arrow and group name (name known from navigation). Below the header, a large empty space, then `EmptyStateView` with error configuration: cloud-slash icon, "Couldn't load group" title in `AppColors.textPrimary`, body "Check your connection and try again. Your shared expenses and itineraries are safely stored on your device." in `AppColors.textSecondary`, and a teal "Retry" button.

No stats grid, no member list, no event cards shown — data may be stale.

#### Token Mapping

| Visual Area | Token Reference | Hex | Notes |
|-------------|----------------|-----|-------|
| OfflineBanner background | amber (#F59E0B) | #F59E0B | See Token Gaps |
| OfflineBanner text | `AppColors.textOnPrimary` | #FFFFFF | White on amber |
| Header (gradient) | `AppColors.headerGradientStart` → End | #111827 → #1F2937 | Consistent |
| Error icon | `AppColors.error` | #EF4444 | Display-only icon |
| Error icon container | `AppColors.surface` | #F8F9FA | Gray-50 |
| "Couldn't load group" heading | `AppColors.textPrimary` | #111827 | AAA |
| Error body | `AppColors.textSecondary` | #6B7280 | AA |
| "Retry" button bg | `AppColors.primary` | #0D7B74 | Teal |
| "Retry" button text | `AppColors.textOnPrimary` | #FFFFFF | 5.12:1 AA |

#### Component Hierarchy

```
Scaffold(backgroundColor: AppColors.background)
  └── Column
        ├── OfflineBanner()
        ├── ModuleHeader(useDarkTheme: true, title: groupName, ...)
        └── Expanded
              └── EmptyStateView(
                    icon: Iconsax.cloud_cross,
                    iconColor: AppColors.error,
                    title: "Couldn't load group",
                    message: "Check your connection and try again. Your shared expenses and itineraries are safely stored on your device.",
                    actionLabel: "Retry",
                    onAction: () => ref.refresh(groupProvider(groupId)),
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
| Tap "Retry" | Refresh `groupProvider(groupId)` | Loading → Loaded or Error |
| Tap back | Pop to Home | Slide-left |
| Connection restored | OfflineBanner fades, reload auto-triggers | Fade 300ms |

---

## Stitch Image References

All Stitch output images are stored externally at:
- `/Users/nasseralbusaidi/Downloads/stitch 2/group_detail_loaded_state/screen.png`
- `/Users/nasseralbusaidi/Downloads/stitch 2/group_detail_empty_state/screen.png`
- `/Users/nasseralbusaidi/Downloads/stitch 2/group_detail_loading_state/screen.png`
- `/Users/nasseralbusaidi/Downloads/stitch 2/group_detail_error_state/screen.png`

These files are NOT committed to the repository. Reference by path for local design review only.

---

## Token Gaps Identified

| Gap Description | Structural or Cosmetic? | Recommended Action |
|----------------|------------------------|-------------------|
| `OfflineBanner` amber (#F59E0B) has no token | Structural — needed by OfflineBanner today | Add `offlineBannerBackground` token in Phase 18 |
| Event type color discrimination — all event types (Trip, Camping, Day Out, Dinner, Custom) map to single teal (`AppColors.primary`). The earthy palette had 5 distinct event-type colors; the new palette's module tokens are all gray (#6B7280) except Ledger. This loses event-type visual differentiation | Structural — significant UX regression if events are indistinguishable | Decision required: (a) Add 5 event-type tokens to AppColorTokens in Phase 18, or (b) Use icon shapes + labels as the primary differentiator and accept monochrome event cards. Defer to Phase 20 (Group Detail implementation). |
| Avatar circle size (40dp) and overlap (-8dp) have no token | Cosmetic — inline values are acceptable | Document as standard; consider adding `avatarSize` and `avatarOverlap` constants in shared widget |
| Event accent bar width (3dp) has no spacing token | Cosmetic — not a standard spacing unit | Use inline value `3.0`; no token needed |
| Invite code chip uses `selectionFill` (#E6F5F3) — primary teal action interpretation may confuse (it looks interactive but is a display chip) | Cosmetic — clearly labeled, chip shape communicates copy action | No change; document intent that chip tap = copy to clipboard |
| Bottom navigation for Group Detail shows "Groups | Expenses | Activity | Profile" — different from Home's "Groups | Activity | Chats | Profile" | Structural — nav inconsistency across screens is a UX risk | Nav configuration must be locked in Phase 19 (Navigation Restructuring). Flag for Phase 19 plan. |
