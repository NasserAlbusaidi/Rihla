# Phase 21: Module Screens Redesign - Research

**Researched:** 2026-03-30
**Domain:** Flutter widget composition, design token application, UI redesign across 6 module screens + 4 form flows + onboarding/splash
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Ledger Screen**
- D-01: Expense cards show full detail: category icon (left), expense title + amount (line 1), payer name · date · participant count (line 2), balance status line (line 3). Three-line card.
- D-02: Balance line color-coded via text color only: green (`successText`) for "Owed to you", red (`errorText`) for "You owe", gray (`textSecondary`) for "Settled". Card background stays `surface`. No accent bars or tinted backgrounds.
- D-03: Balance summary hero card above the expense list: YOUR BALANCE (color-coded) + EVENT TOTAL on row 1, expense count + settlement count on row 2, two CTA buttons [+ Add Expense] [Settle Up] on row 3.
- D-04: Single scroll layout — no tabs. Hero → mixed chronological timeline of expenses and settlements. Removes current `AppTabBar`.
- D-05: Settlements appear in the timeline alongside expenses: checkmark icon, green accent, "Payer → Recipient" format.
- D-06: Add Expense button lives inside the hero card (inline CTA), not as a FAB.
- D-07: Tap expense card opens bottom sheet for editing (`EditExpenseSheet` pattern). No swipe actions, no long-press menus.

**Unified Module Layout Template**
- D-08: All 6 modules: ModuleHeader (dark gradient) → Summary Hero Card → Section overline → Content list/grid.
- D-09: All ModuleHeaders use dark gradient variant (#2C1A0E → #3D2B1E) with white title text. No per-module accent headers.
- D-10: Standard content card: 16dp padding all sides, 24dp border radius, cardShadow (raised), `AppColors.surface` background, no border.

**Summary Hero Cards Per Module**
- D-11: Ledger hero: Balance + Total + [Add Expense] [Settle Up]
- D-12: Gear hero: Packed X/Y + Priority N items + [Add Item]
- D-13: Logistics hero: N groups · M members + unassigned count + [Create Group]
- D-14: Vault hero: N files + total size + [Upload]
- D-15: Memories hero: N photos + date range + [Add Photo]
- D-16: Activity hero: N entries + last update (no CTA — read-only feed)

**Empty States**
- D-17: Icon + warm gradient circle style: large icon (48dp) centered in 72dp circle with module accent color gradient.
- D-18: Module accent colors for empty state circles: Ledger = terracotta (#CC6B49), Gear = olive (#7A8C5E), Logistics = dusty teal (#5B7B8C), Vault = warm bronze (#8B7355), Memories = desert sand (#9B7A5C), Activity = caramel (#A67C5B).
- D-19: Module-specific CTA text: "Add Expense" (Ledger), "Add Gear Item" (Gear), "Create Sub-group" (Logistics), "Upload Document" (Vault), "Add Photo" (Memories), no CTA for Activity.

**Other Screen Decisions**
- D-20: Vault document cards: 52dp icon container (warm bronze accent), file type icon, title, file size · upload date · uploader.
- D-21: Activity timeline: date-grouped flat list with sticky section headers. No vertical connector line.
- D-22: Logistics sub-group card: member chips + 4dp capacity progress bar + dusty teal accent top border.
- D-23: Logistics drops tab bar — unified single-scroll template.
- D-24: Memories uses 3-column photo grid with 8dp gap, 8dp radius thumbnails. Exception to card-list template.
- D-25: Form flows: reskin + polish depth only. Keep existing flow logic unchanged. Add warm card containers around form sections.
- D-26: InputDecorationTheme in app_theme.dart: fillColor #F5EDE1, border #E5D5C0, focusedBorder #CC6B49, labelStyle #2C1A0E, hintStyle #A89888, errorBorder #EF4444, border radius 12dp.
- D-27: Add Expense step indicator: three terracotta dots — filled for current, outlined for upcoming, checked for complete.
- D-28: Settings screen uses section cards (iOS grouped table style): Profile, Preferences, About. Each with warm surface, 24dp radius, ListTile items.
- D-29: Onboarding: 3-page structure unchanged. Each page gets large icon in warm gradient circle, title in dark brown, subtitle in warm gray, terracotta dot indicators. Final page CTA in terracotta.
- D-30: Splash screen: warm sand (#F2E8D6) background, app logo/name in dark brown centered.

**Explicitly NOT in scope**
- No haptic feedback (Phase 22)
- No M3 motion patterns (Phase 22)
- No animated balance counters (Phase 22)
- No navigation structure changes (Phase 19 complete)
- No backend/logic changes

### Claude's Discretion

- Exact hero card layout composition (2-column stats vs stacked)
- Skeleton loading variants for modules currently lacking them (Ledger, Memories) — use Phase 17 primitives
- How to implement date-grouped sections in Activity (SliverStickyHeader or custom)
- Gear screen hero card adaptation (progress bar style, priority badge design)
- Whether SearchFilterBar is retained on Gear and Vault screens alongside the new hero card
- Animation choices for card entrance (FadeInList stagger delays, grid fade-in for Memories)
- Photo grid implementation details for Memories (GridView.builder vs SliverGrid)

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope.

</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| SCRN-03 | Ledger screen uses card-style expense rows with color-coded balance displays | D-01/D-02/D-03 locked; `successText`/`errorText`/`textSecondary` tokens verified in `color_tokens.dart`; `TransactionList` widget is the primary target for replacement with `ExpenseCard` + `SettlementRow` |
| SCRN-04 | Gear, Logistics, Vault, Memories, and Activity screens redesigned with new design tokens | All 5 screens use 100% AppColors tokens already; redesign adds hero cards (D-12–D-16), unified ModuleHeader, new empty state circle gradients (D-17/D-18) |
| SCRN-05 | Create/join group, create event, add expense, and settings flows use new design language | New `InputDecorationTheme` (D-26) in `app_theme.dart` covers all form fields globally; terracotta focus border, sand fill. New `DotStepIndicator` widget for Add Expense. |
| SCRN-06 | Onboarding flow and splash screen reflect warm earthy aesthetics | Onboarding background changes from dark (`AppColors.surfaceDark`) to light warm; terracotta dots (D-29); splash changes to warm sand scaffold (D-30). |

</phase_requirements>

---

## Summary

Phase 21 is the final visual sweep of the app — applying the monochrome+teal design language to every screen not yet redesigned. The technical work is almost entirely Flutter widget composition: building new hero cards, reskinning existing widgets, adding empty state upgrades, and updating the shared `InputDecorationTheme`. No new libraries are required. No provider or business logic changes.

The primary complexity is breadth, not depth. There are 6 module screens, 4 form flows, onboarding, and splash — each with its own hero card, empty state, loading state, and error state. The shared components (ModuleHeader, EmptyStateView, SkeletonLoader, FadeInList) already exist and most are ready to use. The main gaps are: (1) new `accentColor` parameter on `EmptyStateView`, (2) new `SkeletonLoader.expenseList` and `SkeletonLoader.photoGrid` factories, (3) new `DotStepIndicator` shared widget, and (4) the `InputDecorationTheme` update in `app_theme.dart`.

A critical token gap exists: `AppColors.sandLight`, `AppColors.terracotta`, and `AppColors.warmGray` are referenced throughout the UI-SPEC but do NOT exist in `app_theme.dart` or `color_tokens.dart`. These must be added as the Wave 0 prerequisite before any form field work can begin.

**Primary recommendation:** Plan in waves organized by dependency — Wave 0 adds missing tokens and upgrades shared widgets, Waves 1-3 tackle the 6 module screens in parallel, Wave 4 handles form flows and settings, Wave 5 handles onboarding/splash.

---

## Standard Stack

### Core (all already in pubspec.yaml — no new dependencies)

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `flutter_animate` | current | FadeInList, TapBounce, StaggeredGrid | Phase 17 animation library; all modules already use it |
| `iconsax` | current | Icon set | Universal icon library across app |
| `google_fonts` | current | Plus Jakarta Sans | App font; already in AppTheme |
| `shimmer` | current | SkeletonLoader shimmer effect | Phase 17 skeleton system |
| `flutter_riverpod` | `^2.4.9` | Provider state management | All screens use Riverpod 2.x |
| `decimal` | `^3.2.4` | Money math | OMR 3 decimal places — never doubles |

**No new packages needed.** This is a pure Flutter widget composition phase.

### Token Gap (MUST be resolved in Wave 0)

The UI-SPEC references three `AppColors` facade constants that do not currently exist:

| Missing Token | Hex | Used For |
|---------------|-----|---------|
| `AppColors.sandLight` | `#F5EDE1` | Form field fill (D-26, InputDecorationTheme) |
| `AppColors.terracotta` | `#CC6B49` | Form focused border, step dots, onboarding CTA, empty state circles |
| `AppColors.warmGray` | `#E5D5C0` | Form enabled border (D-26) |

These are constants on the `AppColors` facade class (`lib/core/theme/app_theme.dart`). They do NOT need to be added to `AppColorTokens` (the ThemeExtension) since they are phase-specific earthy accent values used only in empty state circles and form fields — not in the monochrome+teal token system. Add them as static `const Color` on `AppColors`.

Note: D-09 in CONTEXT.md says headers use `#2C1A0E → #3D2B1E` (warm brown gradient), but the existing `ModuleHeader` uses `AppColors.darkHeaderGradient` (`#111827 → #1F2937` gray gradient) and the UI-SPEC confirms gray-900/gray-800. The warm brown gradient cited in D-09 contradicts the actual locked token system. Use the gray header gradient (`AppColors.darkHeaderGradient`) as implemented — this matches UI-SPEC Color section which lists `headerGradientStart: #111827`.

---

## Architecture Patterns

### Recommended Project Structure

The phase follows the existing feature-first structure. New widget files are added within their respective feature's `widgets/` subdirectory.

```
lib/
├── core/theme/
│   └── app_theme.dart          # Add sandLight, terracotta, warmGray tokens
│                               # Update InputDecorationTheme (D-26)
├── shared/widgets/
│   ├── empty_state_view.dart   # Add accentColor gradient circle parameter (D-17)
│   ├── skeleton_loader.dart    # Add expenseList, photoGrid factories
│   └── dot_step_indicator.dart # NEW — terracotta dots (D-27, D-29)
├── features/ledger/
│   ├── screens/ledger_screen.dart    # Remove AppTabBar, add LedgerHeroCard
│   └── widgets/
│       ├── ledger_hero_card.dart     # NEW (D-03, D-11)
│       ├── expense_card.dart         # NEW (D-01, D-02)
│       └── settlement_row.dart       # NEW (D-05)
├── features/gear/
│   └── widgets/gear_hero_card.dart   # NEW (D-12)
├── features/logistics/
│   ├── screens/logistics_screen.dart # Remove TabController/AppTabBar (D-23)
│   └── widgets/logistics_hero_card.dart # NEW (D-13)
├── features/vault/
│   └── widgets/vault_hero_card.dart  # NEW (D-14)
├── features/memories/
│   ├── screens/memories_screen.dart  # Migrate custom header → ModuleHeader
│   └── widgets/memories_hero_card.dart # NEW (D-15)
├── features/activity/
│   └── widgets/
│       ├── activity_hero_card.dart   # NEW (D-16)
│       └── activity_entry_card.dart  # NEW (D-21)
├── features/onboarding/
│   └── screens/onboarding_screen.dart # Dark → light warm background (D-29)
└── features/splash/
    └── screens/splash_screen.dart    # Sand background (D-30)
```

### Pattern 1: Hero Card Widget Pattern

Every module gets a self-contained hero card widget. The pattern from `BalanceHeroCard` (Phase 18) applies: stateless widget taking pre-computed values, no provider reads inside the card itself.

```dart
// Source: Phase 18 BalanceHeroCard pattern, adapted for module heroes
class LedgerHeroCard extends StatelessWidget {
  final Decimal netBalance;
  final Decimal eventTotal;
  final int expenseCount;
  final int settlementCount;
  final String currency;
  final VoidCallback onAddExpense;
  final VoidCallback onSettleUp;

  const LedgerHeroCard({
    super.key,
    required this.netBalance,
    // ...
  });

  @override
  Widget build(BuildContext context) {
    // Three-row layout per D-03
    // Row 1: YOUR BALANCE (color-coded) + EVENT TOTAL
    // Row 2: expense count + settlement count
    // Row 3: [Add Expense] ElevatedButton + [Settle Up] OutlinedButton
    final balanceColor = switch (netBalance.compareTo(Decimal.zero)) {
      > 0 => AppColors.successText,   // owed to you
      < 0 => AppColors.errorText,     // you owe
      _ => AppColors.textSecondary,   // settled
    };
    // ...
  }
}
```

### Pattern 2: EmptyStateView Upgrade (D-17/D-18)

`EmptyStateView` needs a new optional `accentColor` parameter that changes the icon container from a flat tinted square to a gradient circle.

```dart
// Current EmptyStateView uses:
// Container(color: color.withValues(alpha: 0.08), borderRadius: radiusLarge)
//
// New pattern adds accentColor gradient circle:
// Container(gradient: LinearGradient([accentColor, accentColor.lighter]),
//           borderRadius: BorderRadius.circular(36))  // 72dp circle
//
// Backward compatible: when accentColor is null, fall back to current tinted square
```

Module earthy circle gradients (D-18 — earthy palette used only here):
```dart
// Ledger:     LinearGradient([Color(0xFFCC6B49), Color(0xFFE0896A)])
// Gear:       LinearGradient([Color(0xFF7A8C5E), Color(0xFF96A876)])
// Logistics:  LinearGradient([Color(0xFF5B7B8C), Color(0xFF7B9BAC)])
// Vault:      LinearGradient([Color(0xFF8B7355), Color(0xFFA89372)])
// Memories:   LinearGradient([Color(0xFF9B7A5C), Color(0xFFB89878)])
// Activity:   LinearGradient([Color(0xFFA67C5B), Color(0xFFC29A7A)])
```

### Pattern 3: Tab Bar Removal (Ledger + Logistics)

Ledger currently has no `AppTabBar` (was already removed — current screen uses `CustomScrollView` with `SliverToBoxAdapter` sections). However `MemberBalancesSection` and `SpendingSummarySection` components exist as separate widgets currently shown in the scroll body. The redesign collapses these into the new `LedgerHeroCard`.

Logistics (`logistics_screen.dart`, 696 LOC) has an active `TabController` and `AppTabBar` with "All"/"By Group" tabs (`SingleTickerProviderStateMixin`). Removing it means:
1. Remove `SingleTickerProviderStateMixin`
2. Remove `TabController` and associated `initState`/`dispose` calls
3. Replace `TabBarView` + `AppTabBar` with the unified scroll layout: `LogisticsHeroCard` → sub-group card list

### Pattern 4: Date-Grouped Activity Timeline (D-21, Claude's Discretion)

The UI-SPEC specifies date-grouped sections with "TODAY", "YESTERDAY", "Mar 28" sticky headers. Implementation options:

**Option A: SliverStickyHeader (requires new package `sliver_tools` or `flutter_sticky_header`)**
- Sticky behavior is ideal but introduces a new dependency
- The project has a policy of preferring existing libraries

**Option B: CustomScrollView with SliverList + SliverPersistentHeader**
- Flutter-native but verbose
- Each date group becomes its own SliverPersistentHeader + SliverList pair

**Option C: ListView.builder with conditional section header rows (non-sticky)**
- No new dependency
- Section headers scroll away — not truly sticky but simpler
- Consistent with the project's established `ListView.builder` + `FadeInList` patterns

Recommendation: Option C (non-sticky section headers). The UI-SPEC says "sticky overlines" but does not list any new package. Given the project's preference for no new dependencies, and that activity screens are typically short-lived reads, non-sticky headers deliver the visual grouping without the dependency cost. Flag as a low-risk decision.

### Pattern 5: Memories Photo Grid (D-24, Claude's Discretion)

3-column grid with 8dp gap:

```dart
// GridView.builder approach (recommended — simpler, avoids Sliver nesting)
GridView.builder(
  shrinkWrap: true,
  physics: const NeverScrollableScrollPhysics(),
  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: 3,
    crossAxisSpacing: 8,
    mainAxisSpacing: 8,
  ),
  itemCount: memories.length,
  itemBuilder: (context, index) {
    // ClipRRect with 8dp radius + CachedNetworkImage
  },
)
// Wrap in SliverToBoxAdapter if screen uses CustomScrollView
// Use StaggeredGrid animation for entrance
```

`GridView.builder` with `shrinkWrap: true` and `NeverScrollableScrollPhysics` inside a `CustomScrollView`'s `SliverToBoxAdapter` is the established pattern from Phase 18. Avoid `SliverGrid` directly — it requires separating the hero card into its own Sliver, adding complexity.

### Pattern 6: InputDecorationTheme Update (D-26)

The global `InputDecorationTheme` in `AppTheme.lightTheme` is updated. This affects ALL text fields app-wide immediately. No per-widget overrides needed.

```dart
// In AppTheme.lightTheme, replace current inputDecorationTheme with:
inputDecorationTheme: InputDecorationTheme(
  filled: true,
  fillColor: AppColors.sandLight,           // #F5EDE1 (new token)
  contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
  border: OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppColors.radiusMedium), // 12dp
    borderSide: BorderSide.none,
  ),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppColors.radiusMedium),
    borderSide: const BorderSide(color: AppColors.warmGray, width: 1.5), // #E5D5C0 (new token)
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppColors.radiusMedium),
    borderSide: const BorderSide(color: AppColors.terracotta, width: 2), // #CC6B49 (new token)
  ),
  errorBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppColors.radiusMedium),
    borderSide: const BorderSide(color: AppColors.error, width: 1.5),
  ),
  focusedErrorBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppColors.radiusMedium),
    borderSide: const BorderSide(color: AppColors.error, width: 2),
  ),
  labelStyle: GoogleFonts.getFont(
    AppTheme.fontFamily,
    color: const Color(0xFF2C1A0E), // dark brown per D-26
    fontSize: 14,
    fontWeight: FontWeight.w600,
  ),
  hintStyle: GoogleFonts.getFont(
    AppTheme.fontFamily,
    color: const Color(0xFFA89888), // sand gray per D-26
    fontSize: 15,
    fontWeight: FontWeight.w500,
  ),
  floatingLabelStyle: GoogleFonts.getFont(
    AppTheme.fontFamily,
    color: AppColors.terracotta, // #CC6B49
    fontSize: 12,
    fontWeight: FontWeight.w700,
  ),
),
```

**Side-effect audit:** Changing `InputDecorationTheme` globally affects all form fields simultaneously. Fields that currently override `decoration` locally with `InputDecoration(fillColor: ...)` will NOT be affected (local override wins). Fields that rely on the theme without override will immediately pick up the new style. No existing test asserts on input field fill colors directly — safe to change globally.

### Pattern 7: DotStepIndicator Widget (D-27, D-29)

New shared widget used in both Add Expense step indicator and onboarding page dots.

```dart
// lib/shared/widgets/dot_step_indicator.dart
class DotStepIndicator extends StatelessWidget {
  final int stepCount;
  final int currentStep;        // 0-indexed
  final Color accentColor;      // terracotta #CC6B49

  // Dot state:
  // - complete (index < currentStep): filled + check icon (small)
  // - active (index == currentStep): filled circle 8dp
  // - upcoming (index > currentStep): outlined ring 8dp
}
```

For onboarding (D-29), use `currentStep` as the page index with no "complete" state (only active/upcoming).

### Anti-Patterns to Avoid

- **Hardcoded Color hex values in widget code:** Always use `AppColors.*` facade constants or the new tokens. The CI lint rule (FOUND-04) blocks `Color(0xFF...)` outside the token system.
- **`textMuted` for functional text:** `#9CA3AF` is 2.86:1 contrast — below AA. Never use for expense titles, amounts, labels. Only timestamps and decorative overlines.
- **`double` for money amounts:** Always `Decimal`. Never pass `double` through expense calculations.
- **Mutating state objects:** Flutter widget state uses `setState()` / `ref.watch()`. Never mutate provider state directly.
- **CircularProgressIndicator for loading states:** Phase 17 mandate. Replace all `CircularProgressIndicator()` with `SkeletonLoader.*` factories.
- **Adding navigation logic to redesign work:** This phase is purely visual. No `context.push` route changes, no provider restructuring.
- **ListView.builder in unbounded parent:** Established Phase 17 pitfall. Use `FadeInList` (Column) wrapped in `SliverToBoxAdapter` for sliver scrolling contexts.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Shimmer loading animation | Custom animated shimmer | `SkeletonLoader.*` factories | Phase 17 system handles reduced-motion, shimmer theming, and content-aware layouts |
| Staggered list entrance | Manual `AnimationController` + stagger | `FadeInList` widget | Phase 17 standard, respects `MediaQuery.disableAnimations` |
| Photo grid animation | Manual stagger | `StaggeredGrid` widget | Phase 17, already handles grid cross-fade patterns |
| Tap feedback on cards | `GestureDetector` scale animation | `TapBounce` widget | Phase 17 standard tap bounce |
| Financial precision | `double` arithmetic | `Decimal` package | Float rounding errors on OMR 3-decimal amounts |
| Date formatting | Manual DateFormat strings | `AppFormatters` utility | Project-standard formatter, handles OMR + date locale |
| Empty state view | Custom centered column | `EmptyStateView` widget | Phase 14 semantic keys, Phase 17 animation, consistent structure |
| Back navigation in headers | Custom back button widget | `ModuleHeader(useDarkTheme: true)` | Phase 20 standard; already has accessibility `Semantics(label: 'Go back')` |

---

## Common Pitfalls

### Pitfall 1: Token Names That Don't Exist Yet

**What goes wrong:** Implementation writes `AppColors.sandLight` and gets a compile error. This blocks all form field work.
**Why it happens:** The UI-SPEC references `sandLight`, `terracotta`, and `warmGray` but these are not yet defined in `app_theme.dart`. They are earthy palette values deliberately excluded from the monochrome+teal `AppColorTokens` system.
**How to avoid:** Wave 0 task must add these three constants to the `AppColors` class before any form field or empty state circle code is written. They are `static const Color` fields — no ThemeExtension changes needed.
**Warning signs:** Compile error mentioning undefined identifier on `AppColors.sandLight` / `.terracotta` / `.warmGray`.

### Pitfall 2: InputDecorationTheme Global Impact on Tests

**What goes wrong:** Updating `InputDecorationTheme` globally causes tests that build `MaterialApp` with `AppTheme.lightTheme` to see form field styling changes. If any test asserts on `fillColor` or `borderSide` via widget properties, it will fail.
**Why it happens:** `InputDecorationTheme` flows down the widget tree globally. All `TextField` and `TextFormField` widgets that don't provide their own `InputDecoration` will reflect the new theme.
**How to avoid:** Check existing form field tests before changing the theme. No test currently asserts on input decoration colors (verified by reviewing test files). The change is safe, but run `flutter test` immediately after updating `app_theme.dart`.
**Warning signs:** Test failures in `create_join_group_test.dart`, `create_event_test.dart`, or `ledger_test.dart` after changing `app_theme.dart`.

### Pitfall 3: Logistics TabController State Management Removal

**What goes wrong:** Removing `SingleTickerProviderStateMixin` from `LogisticsScreen` causes a compile error if `_tabController` is referenced anywhere in the subtree, or a runtime error if `dispose()` still calls `_tabController.dispose()`.
**Why it happens:** `LogisticsScreen` uses `SingleTickerProviderStateMixin` as a vsync provider for `TabController`. Removing the tab bar requires removing both the mixin and all `_tabController` references.
**How to avoid:** Remove `SingleTickerProviderStateMixin`, `_tabController` field, `initState` initialization, `dispose` teardown, `AppTabBar` widget, and `TabBarView` widget together as an atomic change. Search for all `_tabController` usages before deleting.
**Warning signs:** `LateInitializationError` on `_tabController` if dispose is called on an uninitialized field.

### Pitfall 4: CircularProgressIndicator Still Used in Module Screens

**What goes wrong:** Ledger, Gear, Logistics, Vault, Memories, and Activity all still show `CircularProgressIndicator()` in their loading states (visible in the current code). The Phase 17 mandate requires skeleton loaders.
**Why it happens:** Phase 17 added skeleton infrastructure but did not backport it to all module screens. Phase 21 must complete this migration.
**How to avoid:** Each module screen's `isLoading` guard must be replaced with the appropriate `SkeletonLoader` factory. Ledger needs `SkeletonLoader.expenseList()` (already exists). Memories needs a new `SkeletonLoader.photoGrid()` factory.
**Warning signs:** Test asserting on `CircularProgressIndicator` still present after implementation.

### Pitfall 5: Memories Custom Header Orphan

**What goes wrong:** `MemoriesScreen` is the only module that does NOT use `ModuleHeader` — it uses a custom header. If the custom header is removed without migration, the back button disappears and the screen has no title.
**Why it happens:** Historical implementation choice; never migrated.
**How to avoid:** Add `ModuleHeader(title: 'Memories', subtitle: event.name.toUpperCase(), useDarkTheme: true)` as the first element in the scroll body, removing the custom header code. Verify the back button works post-change.

### Pitfall 6: Onboarding Screen Background Color Contract

**What goes wrong:** Onboarding currently uses `AppColors.surfaceDark` (#111827 dark gray) as its scaffold background. D-29 changes this to a light warm theme. If tests or integration checks assert on `surfaceDark` background, they will fail.
**Why it happens:** The redesign inverts the onboarding color scheme from dark to light warm.
**How to avoid:** The onboarding background in D-29 is warm gradient circle + light page, but the overall scaffold background is NOT specified as warm sand (that's only splash, D-30). Onboarding pages should use `AppColors.background` (#FFFFFF) as scaffold, with warm-tinted icon circles per D-17 style. The animated blob background should be removed or toned down.
**Warning signs:** `OnboardingKeys.screen` test finds a dark background where a light one is expected.

### Pitfall 7: Settlement Row Token Contract (D-05)

**What goes wrong:** Settlement rows need a left 3dp teal border accent but if implemented as a `Container` border directly, it wraps the entire card including the padding, making the border 3dp on all sides.
**Why it happens:** CSS-style `border-left` doesn't translate directly to Flutter. Flutter `BoxDecoration.border` applies to all sides unless a `Border()` object specifies individual sides.
**How to avoid:** Use `Border(left: BorderSide(color: AppColors.moduleLedger, width: 3))` explicitly. Or wrap content in a `Row` with a 3dp teal `Container` on the left as a visual bar (cleaner pattern from Phase 20 EventCard accent bar).

---

## Code Examples

### Standard Card Container Pattern

```dart
// Source: CONTEXT.md D-10 + Phase 20 established pattern
Container(
  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
  padding: const EdgeInsets.all(16),
  decoration: BoxDecoration(
    color: AppColors.surface,
    borderRadius: BorderRadius.circular(24), // radiusLarge = 16; D-10 says 24dp
    boxShadow: AppColors.cardShadow,
  ),
  child: /* content */,
)
// NOTE: D-10 specifies 24dp border radius for content cards.
// AppColors.radiusLarge = 16dp. Use 24 directly per locked decision.
```

### Three-State Balance Color (Dart 3 switch expression)

```dart
// Source: Phase 20 P01 established pattern
final balanceColor = switch (netBalance.compareTo(Decimal.zero)) {
  > 0 => AppColors.successText,    // owed to you — dark emerald
  < 0 => AppColors.errorText,      // you owe — dark red
  _ => AppColors.textSecondary,    // settled — gray
};
```

### Section Overline Style

```dart
// Source: UI-SPEC typography contract
const Text(
  'TRANSACTIONS',
  style: TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: AppColors.textMuted, // decorative — overlines are exempt from AA
    letterSpacing: 0.5,
  ),
)
```

### Settlement Row Left Accent Bar

```dart
// Source: Phase 20 EventCard accent bar pattern
Container(
  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
  decoration: BoxDecoration(
    color: AppColors.surface,
    borderRadius: BorderRadius.circular(24),
    boxShadow: AppColors.cardShadow,
    border: const Border(
      left: BorderSide(color: AppColors.moduleLedger, width: 3),
    ),
  ),
  child: Row(
    children: [
      const Icon(Iconsax.tick_circle, color: AppColors.moduleLedger, size: 18),
      const SizedBox(width: 8),
      // "Payer → Recipient" text + amount in successText
    ],
  ),
)
```

### Capacity Progress Bar (Logistics/Gear)

```dart
// Source: CONTEXT.md D-22 — 4dp thin bar
LinearProgressIndicator(
  value: filledCount / maxCapacity,
  minHeight: 4,
  backgroundColor: AppColors.border,
  valueColor: AlwaysStoppedAnimation<Color>(AppColors.moduleLogistics),
  borderRadius: BorderRadius.circular(2),
)
```

### SkeletonLoader photoGrid Factory (needs to be created)

```dart
// New factory for Memories loading state
factory SkeletonLoader.photoGrid({int count = 9}) {
  return SkeletonLoader(
    itemCount: 1,
    itemBuilder: (context, index) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemCount: count,
        itemBuilder: (_, __) => const SkeletonBlock(
          width: double.infinity,
          height: double.infinity,
          borderRadius: 8,
        ),
      ),
    ),
  );
}
```

---

## State of the Art

| Old Approach | Current Approach | Phase Changed | Impact |
|--------------|------------------|--------------|--------|
| Spinner loading | Skeleton loaders | Phase 17 | Must replace remaining spinners in module screens |
| `Navigator.push` | `context.push` (GoRouter) | Phase 19 | All navigation already migrated; maintain |
| Earthy palette (terracotta/sand) | Monochrome+teal | Phase 16 | Earthy colors now only in empty state circles (D-18) and form accents (D-26) |
| `AppTabBar` with Spending/Balances | Single scroll | Phase 21 (this phase) | Ledger and Logistics drop tab bar |
| Custom Memories header | `ModuleHeader` standard | Phase 21 (this phase) | Memories migration needed |

**Token conventions:**
- `AppColors.*` facade: 895 call sites — always use these, never raw `Color(0xFF...)`
- `AppColorTokens.light.*`: Used in widget code via `Theme.of(context).extension<AppColorTokens>()` — but in practice, `AppColors.*` is used directly since they are `const` values. Consistent with all prior phases.

---

## Environment Availability

Step 2.6: SKIPPED — Phase 21 is a pure Flutter widget composition phase with no external service or CLI dependencies beyond the existing Flutter SDK (verified: Flutter 3.41.5 stable). All 752 tests pass on current baseline.

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | flutter_test (Flutter 3.41.5) + mocktail ^1.0.4 |
| Config file | none (uses flutter test command directly) |
| Quick run command | `flutter test test/features/ledger_test.dart test/features/gear_screen_mutations_test.dart test/features/logistics_screen_mutations_test.dart -x` |
| Full suite command | `flutter test --no-pub` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| SCRN-03 | Ledger shows expense cards with color-coded balance | Widget | `flutter test test/features/ledger_test.dart` | ✅ (needs new assertions) |
| SCRN-03 | LedgerHeroCard renders YOUR BALANCE and EVENT TOTAL | Widget | `flutter test test/features/ledger_test.dart` | ❌ Wave 0 |
| SCRN-03 | ExpenseCard renders three-line format | Widget | `flutter test test/features/ledger_test.dart` | ❌ Wave 0 |
| SCRN-04 | Gear screen shows hero card with packed count | Widget | `flutter test test/features/gear_screen_mutations_test.dart` | ❌ Wave 0 |
| SCRN-04 | Activity screen shows date-grouped sections | Widget | `flutter test test/features/activity_screen_test.dart` | ❌ Wave 0 |
| SCRN-04 | Memories screen shows photo grid | Widget | `flutter test test/features/memories_screen_test.dart` | ❌ Wave 0 |
| SCRN-04 | EmptyStateView renders gradient circle when accentColor provided | Unit | `flutter test test/features/empty_state_view_test.dart` | ❌ Wave 0 |
| SCRN-05 | InputDecorationTheme uses sand fill color | Widget | `flutter test test/features/groups/create_join_group_test.dart` | ✅ (existing test; verify no regression) |
| SCRN-05 | DotStepIndicator renders correct dot states | Unit | `flutter test test/unit/dot_step_indicator_test.dart` | ❌ Wave 0 |
| SCRN-06 | OnboardingScreen scaffold is light (not dark) | Widget | `flutter test test/features/onboarding_screen_test.dart` | ❌ Wave 0 |
| SCRN-06 | SplashScreen background is warm sand | Widget | `flutter test test/features/splash_screen_test.dart` | ❌ Wave 0 |

### Sampling Rate
- **Per task commit:** `flutter test --no-pub` (752 tests, ~11s — fast enough for every commit)
- **Per wave merge:** `flutter test --no-pub`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps

- [ ] `test/features/ledger/ledger_hero_card_test.dart` — covers SCRN-03 hero card
- [ ] `test/features/ledger/expense_card_test.dart` — covers SCRN-03 three-line card
- [ ] `test/features/gear/gear_hero_card_test.dart` — covers SCRN-04 gear hero
- [ ] `test/features/activity/activity_screen_test.dart` — covers SCRN-04 activity timeline
- [ ] `test/features/memories/memories_screen_test.dart` — covers SCRN-04 photo grid
- [ ] `test/unit/empty_state_view_test.dart` — covers EmptyStateView gradient circle param
- [ ] `test/unit/dot_step_indicator_test.dart` — covers SCRN-05 step dots
- [ ] `test/features/onboarding/onboarding_screen_test.dart` — covers SCRN-06 light background
- [ ] `test/features/splash/splash_screen_test.dart` — covers SCRN-06 warm sand

---

## Open Questions

1. **D-09 Header Gradient Contradiction**
   - What we know: D-09 states "dark gradient variant (#2C1A0E → #3D2B1E)" but existing `AppColors.darkHeaderGradient` is `#111827 → #1F2937` (gray). The UI-SPEC Color section confirms gray-900/gray-800 headers.
   - What's unclear: Should implementors use D-09's warm brown gradient or the existing gray gradient?
   - Recommendation: Use existing `AppColors.darkHeaderGradient` (gray-900 → gray-800). The UI-SPEC is the final authority, and it specifies gray. D-09's warm brown values appear to be a leftover from the original earthy palette discussion before Phase 16 confirmed the monochrome+teal switch. If the user wants warm brown headers, this needs explicit re-confirmation before implementation.

2. **Ledger Screen — MemberBalancesSection and SpendingSummarySection Fate**
   - What we know: The current Ledger has `MemberBalancesSection` and `SpendingSummarySection` as separate widgets in the scroll body. D-03 specifies a hero card with only balance + total + CTAs.
   - What's unclear: Are `MemberBalancesSection` and `SpendingSummarySection` completely removed, or is their information surfaced in the new hero card or another format?
   - Recommendation: Remove both from the screen body. The hero card's "YOUR BALANCE" covers the balance display. `SpendingSummarySection` (category breakdown) is not mentioned in any D- decision — treat as removed for this phase. It can be restored as a collapsible section in Phase 22 polish if desired.

3. **Onboarding Background Clarity**
   - What we know: D-29 says "each page gets large icon in warm gradient circle, title in dark brown, subtitle in warm gray." D-30 says splash is warm sand.
   - What's unclear: D-29 does not specify the onboarding scaffold/page background color. Current implementation uses animated dark blobs on `surfaceDark`.
   - Recommendation: Use `AppColors.background` (#FFFFFF) as the onboarding scaffold background. The warm feel comes from the icon circles and terracotta dots, not the page background. The animated blob background should be removed (it used per-page accent colors that no longer exist in this design context).

---

## Project Constraints (from CLAUDE.md)

- **No hardcoded colors:** CI lint blocks `Color(0xFF...)` outside token files. New terracotta/sand/warmGray values must be added as `static const` on `AppColors`.
- **Immutability:** Never mutate existing state objects — create new copies.
- **TDD mandatory:** Write tests first. 80%+ coverage maintained.
- **No floating-point money:** `Decimal` package for all OMR amounts.
- **No new dependencies:** Phase is pure widget composition — no new packages.
- **Small files (<800 lines):** New hero card widgets should be separate files in `widgets/`. Screen files that grow beyond 800 lines after redesign should extract helper widgets.
- **Functions <50 lines:** Hero card `build()` methods should stay tight; extract sub-widgets if needed.
- **GSD workflow enforcement:** All edits through GSD execute-phase.

---

## Sources

### Primary (HIGH confidence)

- Source: `lib/core/theme/app_theme.dart` — verified AppColors facade, current InputDecorationTheme, missing sandLight/terracotta/warmGray
- Source: `lib/core/theme/tokens/color_tokens.dart` — verified AppColorTokens.light full palette
- Source: `lib/core/theme/tokens/spacing_tokens.dart` — verified AppSpacingTokens.standard token values
- Source: `lib/shared/widgets/empty_state_view.dart` — verified current widget structure, iconColor parameter
- Source: `lib/shared/widgets/skeleton_loader.dart` — verified existing factories, expenseList exists, photoGrid missing
- Source: `lib/shared/widgets/module_header.dart` — verified dark/light variants, useDarkTheme API
- Source: `lib/shared/animations/fade_in_list.dart` — verified Column/AnimateList pattern
- Source: `lib/features/ledger/screens/ledger_screen.dart` — verified current structure (417 LOC, CustomScrollView, no AppTabBar already)
- Source: `lib/features/logistics/screens/logistics_screen.dart` — verified TabController presence, AppTabBar usage
- Source: `lib/features/activity/screens/activity_feed_screen.dart` — verified minimal structure (79 LOC)
- Source: `lib/features/memories/screens/memories_screen.dart` — verified custom header, no ModuleHeader
- Source: `lib/features/onboarding/screens/onboarding_screen.dart` — verified dark background, animated blobs
- Source: `.planning/phases/21-module-screens-redesign/21-CONTEXT.md` — all locked decisions
- Source: `.planning/phases/21-module-screens-redesign/21-UI-SPEC.md` — visual contract, WCAG verification, copywriting contract, component inventory
- Source: `.planning/REQUIREMENTS.md` — SCRN-03/04/05/06 definitions
- Source: Flutter test run — confirmed 752 tests pass on current baseline

### Secondary (MEDIUM confidence)

- Phase 18/20 CONTEXT.md patterns — BalanceHeroCard, EventCard accent bar patterns used as implementation references

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all dependencies already in project, no new packages
- Token gaps: HIGH — directly verified by searching app_theme.dart for missing constants
- Architecture patterns: HIGH — based on verified existing code patterns from Phases 17-20
- Pitfalls: HIGH — based on reading actual current screen code
- Test gaps: HIGH — verified by listing test files and reading existing test structure

**Research date:** 2026-03-30
**Valid until:** 2026-04-30 (stable Flutter widget APIs, no version-sensitive library work)
