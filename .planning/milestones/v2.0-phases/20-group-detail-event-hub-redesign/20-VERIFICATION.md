---
phase: 20-group-detail-event-hub-redesign
verified: 2026-03-30T16:00:00Z
status: passed
score: 16/16 must-haves verified
re_verification: false
gaps: []
human_verification:
  - test: "Open app, navigate to a group with non-zero balance and tap a group card from HomeScreen"
    expected: "ContainerTransform animation plays (card expands to full screen GroupDetailScreen)"
    why_human: "OpenContainer animation is a motion effect — programmatic check only verifies widget presence, not visual quality of the transition"
  - test: "Open event hub, observe EventExpenseHero inner loading state while expenses load"
    expected: "A small CircularProgressIndicator appears while expense data loads, then transitions to the total amount — acceptable but inconsistent with skeleton pattern"
    why_human: "Internal data-loading spinner vs outer skeleton is an inconsistency the plan did not fully address; user should decide if this warrants fixing"
---

# Phase 20: Group Detail + Event Hub Redesign — Verification Report

**Phase Goal:** Redesign GroupDetailScreen (SCRN-01) and EventCommandCenter/event hub (SCRN-02) to match the v2.0 visual spec — stats grid, settle-up CTA, event card accent bars, 2x3 module grid, corrected module colors, light expense hero, ContainerTransform transition.
**Verified:** 2026-03-30T16:00:00Z
**Status:** PASSED
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Group detail shows 2x2 stats grid with YOUR BALANCE, GROUP TOTAL, ACTIVE MEMBERS, EVENTS above the fold | VERIFIED | `GroupStatsGrid` with `GroupKeys.statsGrid` rendered unconditionally in `_buildContent`; 4 `_StatCard` children keyed `statYourBalance`, `statGroupTotal`, `statActiveMembers`, `statEvents` |
| 2 | Stats grid YOUR BALANCE tile is color-coded: errorText when negative, successText when positive, textPrimary when zero | VERIFIED | Dart 3 switch expression at line 44 of `group_stats_grid.dart`: `< 0 => AppColors.errorText`, `> 0 => AppColors.successText`, `_ => AppColors.textPrimary` |
| 3 | Settle-up CTA button appears when any balance is non-zero; hidden when all settled | VERIFIED | `showSettleUpCta` condition at line 104 of `group_detail_screen.dart`; keyed `GroupKeys.settleUpCta`; confirmed by two passing tests |
| 4 | Section order below fold is Events then Member Balances then Recent Activity | VERIFIED | `_buildEventsSection` (line 176), `_buildMembersBalancesSection` (line 180), `_buildActivitySection` (line 188); section-order test passes with coordinate assertions |
| 5 | Event cards show left accent bar: teal for active events, gray for past events | VERIFIED | `Container(width: 3.0)` with `color: event.isPast ? AppColors.textMuted : AppColors.primary` in `event_card.dart` lines 72-81; `IntrinsicHeight` row ensures full-height bar |
| 6 | Event cards show inline personal balance text color-coded red/green/gray | VERIFIED | `_buildBalanceLine` method in `event_card.dart`; Dart 3 switch maps negative→errorText, positive→successText, zero→textSecondary |
| 7 | Past events render at 60% opacity | VERIFIED | `Opacity(opacity: 0.6, child: card)` wrapper at line 126 of `event_card.dart` |
| 8 | Loading state uses SkeletonLoader composites instead of CircularProgressIndicator | VERIFIED | `_buildLoading` in `group_detail_screen.dart` uses `SkeletonBlock`/`SkeletonBar`; `EventCommandCenter` loading uses `SkeletonLoader.dashboardHero()` + `SkeletonLoader.cardList(count: 6)` |
| 9 | Event hub renders modules in a 2x3 grid layout (not vertical column) | VERIFIED | `GridView.count(crossAxisCount: 2, childAspectRatio: 2.0)` keyed `EventKeys.moduleGrid` in `event_module_list.dart` |
| 10 | Module grid uses fixed order: Ledger, Gear, Logistics, Vault, Activity, Memories | VERIFIED | Build order in `EventModuleList.build`: `_addLedgerCard` → `_addGearCard` → `_addLogisticsCard` → `_addVaultCard` → `_addActivityCard` → `_addMemoriesCard`; `sort()` removed |
| 11 | Ledger module card uses `moduleLedger` color; all other modules use correct `module*` tokens | VERIFIED | `AppColorTokens.light.moduleLedger` (line 147), `.moduleGear` (183), `.moduleLogistics` (214), `.moduleVault` (240), `.moduleActivity` (256), `.moduleMemories` (271) |
| 12 | Expense hero card uses light `AppColors.surface` background with teal chip button, not dark gradient | VERIFIED | `event_expense_hero.dart` line 38: `color: AppColors.surface`, `border: Border.all(color: AppColors.border)`, `ActionChip` keyed `EventKeys.addExpenseChip` with `backgroundColor: AppColors.primary`; no gradient, no ClipRRect, no Stack |
| 13 | Activity module card always appears in the grid at position 5 (even when empty) | VERIFIED | `_addActivityCard` called unconditionally at line 81 (after vault, before memories); comment "Activity card always appears (position 5)"; test `module grid includes Activity card always` uses `EventType.nightDayOut` (minimal modules) and still finds `EventKeys.activityCard` |
| 14 | OpenContainer widget is present in HomeScreen group cards section | VERIFIED | `OpenContainer<void>` in `home_screen.dart` lines 164-183; `animations` package imported at line 1; `useRootNavigator: false`, `closedElevation: 0`, `transitionType: ContainerTransitionType.fade` |
| 15 | Modules with data show live summary; modules without data show description text | VERIFIED | Each `_add*Card` method in `EventModuleList` conditionally sets `summaryText` when data is non-empty; `SmartModuleCard` uses `summaryText` when set, falls back to `description`; `isEmpty` flag passed through |
| 16 | All 752 tests pass | VERIFIED | `flutter test` output: `+752: All tests passed!` |

**Score:** 16/16 truths verified

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `lib/features/groups/widgets/group_stats_grid.dart` | 2x2 stats grid widget with StatCard | VERIFIED | 141 lines; `GroupStatsGrid` + `_StatCard`; all 4 stat tiles keyed; Dart 3 switch for balance color |
| `lib/features/groups/screens/group_detail_screen.dart` | Redesigned group detail with stats grid, reordered sections, skeleton loading | VERIFIED | 589 lines; GroupStatsGrid above fold; settle-up CTA conditional; Events→Members→Invite→Activity order; SkeletonBlock/SkeletonBar loading |
| `lib/features/groups/keys/group_keys.dart` | New keys for stats grid and settle-up CTA | VERIFIED | All 6 keys present: `statsGrid`, `statYourBalance`, `statGroupTotal`, `statActiveMembers`, `statEvents`, `settleUpCta` (lines 42-47) |
| `lib/features/events/widgets/event_card.dart` | EventCard with left accent bar, inline personal balance, 60% past opacity | VERIFIED | 198 lines; `IntrinsicHeight` row with 3dp accent bar; `Decimal? personalBalance` param; `Opacity(0.6)` past wrapper; type badge/icon container removed |
| `lib/features/events/widgets/event_module_list.dart` | 2x3 GridView module layout with corrected colors and fixed order | VERIFIED | 325 lines; `GridView.count(crossAxisCount: 2)`; 6 modules in fixed order; all colors via `AppColorTokens.light.*`; `priority` field removed |
| `lib/features/events/screens/event_expense_hero.dart` | Light-themed expense hero with teal add-expense chip | VERIFIED | 148 lines; `AppColors.surface` bg; "TOTAL EXPENSES" overline; `ActionChip` teal chip; `TweenAnimationBuilder` counter retained |
| `lib/features/events/screens/event_command_center.dart` | Redesigned event hub using CustomScrollView with slivers | VERIFIED | 186 lines; `CustomScrollView` + slivers: ModuleHeader → OfflineBanner → EventExpenseHero → EventModuleList → spacing; screen-level loading uses `SkeletonLoader` |
| `lib/features/home/screens/home_screen.dart` | OpenContainer wrapping GroupCard for ContainerTransform | VERIFIED | `OpenContainer<void>` wraps `GroupCard` in group cards section; `animations.dart` imported; `GroupDetailScreen(groupId: group.id)` as `openBuilder` |
| `test/features/group_detail_screen_test.dart` | Updated tests for stats grid, section order, settle-up CTA | VERIFIED | 405 lines; tests for stats grid (4 tiles), settle-up CTA shown/hidden, section order (coordinate check), event card personalBalance |
| `test/features/events/event_command_center_test.dart` | Updated tests for grid layout, corrected colors, redesigned hero, OpenContainer presence | VERIFIED | Tests: 6-card grid, Activity card always, add-expense chip, TOTAL EXPENSES label |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `group_detail_screen.dart` | `group_stats_grid.dart` | `GroupStatsGrid` widget import | WIRED | Import at line 25; `GroupStatsGrid(...)` at line 135 |
| `group_detail_screen.dart` | `groupBalancesProvider` | `ref.watch` for stats grid data | WIRED | `balancesAsync = ref.watch(groupBalancesProvider(groupId))` at line 84; data flows to `GroupStatsGrid` and settle-up CTA |
| `event_command_center.dart` | `event_module_list.dart` | `EventModuleList` widget inside `CustomScrollView` | WIRED | Import at line 16; `EventModuleList(groupId:, eventId:, modules:)` at line 170 |
| `home_screen.dart` | `group_detail_screen.dart` | `OpenContainer` openBuilder returns `GroupDetailScreen` | WIRED | Import at line 15; `openBuilder: (context, closeContainer) => GroupDetailScreen(groupId: group.id)` at line 180 |
| `event_command_center.dart` | `event_expense_hero.dart` | `EventExpenseHero` widget | WIRED | Import at line 17; `EventExpenseHero(event: event, onTap: ...)` at line 153 |

---

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|--------------------|--------|
| `GroupStatsGrid` | `userNetBalance`, `groupTotal`, `eventCount` | `groupBalancesProvider` → Firestore via `GroupBalanceService` | Yes — queries Firestore `events` sub-collection, computes balances | FLOWING |
| `EventCard.personalBalance` | `userEventBreakdown[events[i].id]` | `groupBalancesProvider.perEventBreakdown` | Yes — real per-event breakdown computed from Firestore expense data | FLOWING |
| `EventExpenseHero` | `totalExpenses` | `eventExpensesProvider` → Firestore `expenses` collection | Yes — live stream from Firestore | FLOWING |
| `EventModuleList` | `summaryText` per card | `eventExpensesProvider`, `eventGearItemsProvider`, `eventSubGroupsProvider`, `eventDocumentsProvider` | Yes — all are live Firestore streams | FLOWING |

---

### Behavioral Spot-Checks

Step 7b: SKIPPED for visual/animated screens — cannot test ContainerTransform, opacity rendering, or animated TweenAnimationBuilder output without a running device. The test suite (752 tests, all passing) covers all programmatically verifiable behaviors.

---

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| SCRN-01 | 20-01-PLAN.md | Group detail screen shows event cards with type-specific color accents, inline financial summaries, and past/upcoming visual distinction | SATISFIED | Left accent bar (teal active/gray past), inline personalBalance with WCAG-safe color coding, `Opacity(0.6)` for past events — all wired and tested |
| SCRN-02 | 20-02-PLAN.md | Event hub (CommandCenter) uses the new design language with earthy palette and improved information density | SATISFIED | 2x3 module grid with correct `AppColorTokens.light.module*` colors, light expense hero, CustomScrollView layout, Activity card always present |

Both SCRN-01 and SCRN-02 are marked `[x]` in `.planning/REQUIREMENTS.md` Phase 20 row — consistent with implementation evidence.

---

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `event_expense_hero.dart` | 125-133 | `CircularProgressIndicator` in hero card's data-loading state | Info | Hero card shows a spinner while its internal expense stream loads; inconsistent with the skeleton pattern used everywhere else. Does NOT block goal — screen-level loading is properly skeletonized. The hero's internal async state is a secondary load. |
| `event_command_center.dart` | 132 | `// TODO(Phase 3+): Event options menu` | Info | Options menu `onPressed` is empty. Deliberate deferral, not a stub blocking goal achievement. |

No Blocker or Warning anti-patterns found. Both items are Info-level only.

---

### Human Verification Required

#### 1. ContainerTransform Animation Quality

**Test:** Launch the app, navigate to the HomeScreen showing at least one group, tap a GroupCard.
**Expected:** The group card expands fluidly into the full GroupDetailScreen using the ContainerTransform (fade) transition. Navigation works bidirectionally (back gesture or back button collapses the screen back into the card).
**Why human:** Animation fidelity, transition smoothness, and visual correctness cannot be assessed programmatically. The `OpenContainer` widget presence is verified by test; the rendered motion is not.

#### 2. EventExpenseHero Inner Loading Spinner

**Test:** Navigate to an event hub on a fresh session (cold start, expenses not yet loaded).
**Expected:** Brief `CircularProgressIndicator` appears inside the expense hero card while expense data loads, then transitions to the animated total.
**Why human:** This is an inconsistency with the skeleton-first design philosophy. The plan did not fully address the hero card's internal async loading state (only the screen-level loading was skeletonized). Decision needed: accept as-is, or replace with a `SkeletonBlock` for the hero's loading state.

---

### Gaps Summary

No gaps. All 16 must-have truths are verified against the actual codebase.

The two items flagged for human review are:
1. Animation quality (ContainerTransform) — inherently unverifiable programmatically
2. Hero card internal loading spinner — a minor inconsistency that does not block the SCRN-02 goal

Phase 20 goal is achieved: GroupDetailScreen and EventCommandCenter match the v2.0 visual spec. All 752 tests pass with no regressions.

---

_Verified: 2026-03-30T16:00:00Z_
_Verifier: Claude (gsd-verifier)_
