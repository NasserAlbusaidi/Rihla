# Architecture Research

**Domain:** Flutter mobile app — UI/UX overhaul (design system, navigation restructuring, visual redesign)
**Researched:** 2026-03-28
**Confidence:** HIGH (design token patterns, GoRouter shell routing) / MEDIUM (Stitch token extraction workflow, animation phasing)

---

## Context

This document covers the architectural decisions for the **v2.0 UI/UX overhaul** milestone only. The previous ARCHITECTURE.md (2026-03-26) documented the Firestore data layer — that layer is complete and stable. This document does not revisit backend architecture.

The overhaul touches three distinct systems:

1. **Design system** — replacing the current single-class `AppColors`/`AppTheme` file with a structured token system that can accept Stitch-sourced palette changes without ripple rewrites
2. **Navigation** — replacing imperative `Navigator.push` calls inside group/event sub-screens with GoRouter declarative routes, flattening the tap hierarchy
3. **Component library** — extracting repeated UI patterns into a versioned shared widget layer, simplifying the full-screen redesign phase

---

## System Overview

### Current State

```
┌──────────────────────────────────────────────────────────────────┐
│                         UI Layer                                  │
│                                                                   │
│  HomeScreen      GroupDetailScreen       EventCommandCenter       │
│  (GoRouter)      (Navigator.push)        (Navigator.push)         │
│       │               │                        │                  │
│       │        LedgerScreen GearScreen    LedgerScreen            │
│       │        (Navigator.push)           (Navigator.push)        │
└───────┴───────────────┴────────────────────────┴──────────────────┘
         │               │                        │
         └───────────────┴────────────────────────┘
                         │
              AppColors / AppTheme
              (single file, 63 files import it,
               direct token references in every screen)
```

Key problems driving the overhaul:

- `AppColors` is a static class with hardcoded hex values. Changing the palette (mint → terracotta) requires a global search-and-replace across 63 files.
- Navigation has two modes: GoRouter handles top-level routes; `Navigator.push` handles everything inside a group/event (7 files, ~41 imperative push calls). Deep linking to a ledger screen is impossible.
- `ModuleHeader`, `AppTabBar`, `SmartModuleCard` live in `lib/shared/widgets/` but are tightly coupled to `AppColors` constants, not to a theme context.
- The dark gradient header (`darkHeaderGradient`) appears in `GroupBalanceHero`, `ModuleHeader`, `EventCommandCenter`, and the splash screen — four separate places with no single source of truth.

### Target State

```
┌──────────────────────────────────────────────────────────────────┐
│                         UI Layer                                  │
│                                                                   │
│  HomeScreen (dashboard)                                           │
│  ├── GroupCard (inline, quick taps surface key info)              │
│  └── RecentActivity feed                                          │
│                                                                   │
│  GroupDetailScreen    →    EventCommandCenter                     │
│  (GoRouter /group/:id)     (GoRouter /group/:id/event/:eventId)   │
│                              ↓                                    │
│                    LedgerScreen, GearScreen, etc.                 │
│                    (GoRouter subroutes, not Navigator.push)       │
└──────────────────────────────────────────────────────────────────┘
         │
┌──────────────────────────────────────────────────────────────────┐
│                     Design Token Layer                            │
│                                                                   │
│  AppTokens (palette constants — warm earthy values)              │
│  AppColorScheme extends ThemeExtension<AppColorScheme>            │
│  AppSpacing extends ThemeExtension<AppSpacing>                    │
│  AppTypography (via AppTheme.lightTheme TextTheme)                │
│  AppTheme.lightTheme (assembles ThemeData from tokens)            │
└──────────────────────────────────────────────────────────────────┘
         │
┌──────────────────────────────────────────────────────────────────┐
│                   Component Library                               │
│                                                                   │
│  lib/shared/widgets/ — reads tokens via Theme.of(context)        │
│  No direct AppColors.* references — tokens only                   │
└──────────────────────────────────────────────────────────────────┘
```

---

## Design Token Architecture

### The Problem with the Current Approach

`AppColors` is a static class with hardcoded values accessed as `AppColors.primary`, `AppColors.space24`, etc. This works for a single palette but creates a coupling problem for redesign: every widget that writes `AppColors.primary` is hardcoded to the current neon mint color. Changing to terracotta requires touching all 63 importing files.

Flutter's `ThemeExtension` API solves this cleanly. Custom token classes live in `ThemeData.extensions` and are read via `Theme.of(context).extension<T>()`. The widget code references semantic token names (`tokens.brandPrimary`), not raw hex values. The palette changes in one place — the `AppTheme` assembly — and propagates everywhere.

**Confidence:** HIGH — ThemeExtension is the official Flutter mechanism for design tokens. Sources confirm widespread adoption in 2025 design systems.

### Recommended Token Structure

```
lib/core/theme/
├── app_theme.dart          ← keep, but refactor: assembles ThemeData from tokens
├── app_tokens.dart         ← NEW: raw primitive values (hex constants, pt sizes)
├── extensions/
│   ├── app_color_scheme.dart    ← NEW: ThemeExtension for semantic colors
│   ├── app_spacing.dart         ← NEW: ThemeExtension for spacing scale
│   └── app_radii.dart           ← NEW: ThemeExtension for border radii (optional — small)
```

**`app_tokens.dart` — primitive layer (no Flutter dependencies):**

```dart
// Raw design primitives from Stitch/palette — never used directly by widgets
abstract class AppTokens {
  // Warm earthy palette
  static const Color terracotta    = Color(0xFFCC6B49);  // primary brand
  static const Color terracottaLight = Color(0xFFF5E6DE);
  static const Color sand          = Color(0xFFF2E8D6);
  static const Color sandDark      = Color(0xFFD4B896);
  static const Color olive         = Color(0xFF7A8C5E);
  static const Color oliveLight    = Color(0xFFEEF0E8);
  static const Color charcoal      = Color(0xFF2C2C2C);
  static const Color warmWhite     = Color(0xFFFAF8F5);
  static const Color errorRed      = Color(0xFFD94F3D);
  static const Color successGreen  = Color(0xFF5A8A5E);

  // Spacing scale
  static const double s4  = 4;
  static const double s8  = 8;
  static const double s12 = 12;
  static const double s16 = 16;
  static const double s20 = 20;
  static const double s24 = 24;
  static const double s32 = 32;
  static const double s48 = 48;

  // Border radii
  static const double rSmall  = 12;
  static const double rMedium = 16;
  static const double rLarge  = 20;
  static const double rXLarge = 28;
}
```

**`extensions/app_color_scheme.dart` — semantic layer (what widgets use):**

```dart
@immutable
class AppColorScheme extends ThemeExtension<AppColorScheme> {
  final Color brandPrimary;       // terracotta in light theme
  final Color brandPrimaryLight;  // terracottaLight
  final Color brandOnPrimary;     // white text on terracotta
  final Color surface;
  final Color surfaceVariant;     // sand
  final Color backgroundPage;     // warmWhite
  final Color textHeading;
  final Color textBody;
  final Color textMuted;
  final Color border;
  final Color debtRed;
  final Color creditGreen;

  const AppColorScheme({...required fields...});

  @override
  AppColorScheme copyWith({...}) {...}

  @override
  AppColorScheme lerp(ThemeExtension<AppColorScheme>? other, double t) {...}

  // Convenience accessor — avoids null check at every call site
  static AppColorScheme of(BuildContext context) =>
      Theme.of(context).extension<AppColorScheme>()!;
}
```

**Widget usage (before vs. after):**

```dart
// Before — coupled to static class
Container(color: AppColors.primary)
const EdgeInsets.all(AppColors.space24)

// After — reads from theme context
final colors = AppColorScheme.of(context);
Container(color: colors.brandPrimary)
EdgeInsets.all(AppSpacing.of(context).l)  // l = large = 24pt
```

### Migration Path for AppColors

`AppColors` has ~63 importing files. A single hard cutover would require touching every file in one phase. Instead:

1. Create the new token classes alongside `AppColors` (do not delete `AppColors`)
2. Update `AppTheme.lightTheme` to include the new `ThemeExtension` entries with the new palette values
3. Migrate screens progressively: each screen being redesigned switches from `AppColors.*` to `AppColorScheme.of(context).*`
4. After all screens are migrated, delete `AppColors`

This means `AppColors` and the new token classes coexist during the redesign. Screens that have not yet been redesigned continue to compile and run correctly with the old tokens.

**Important:** Keep `AppColors.space*` constants available until migrated. The spacing constants are referenced in ~300+ widget padding/margin calls. A spacing `ThemeExtension` is correct architecturally but is a separate migration from color.

### Stitch → Flutter Token Workflow

Google Stitch (stitch.withgoogle.com) exports Flutter widget code directly as of 2026. However, the integration is a design reference workflow, not a codegen pipeline:

1. Use Stitch to generate UI mockups with the warm earthy palette
2. Export to Figma or as Flutter widget code (Stitch generates Scaffold, Column, Row structures)
3. Extract the color hex values and typography choices as `AppTokens` constants
4. Implement screens manually using the exported code as reference

Stitch's Flutter code export quality is production-adjacent but not production-ready — it generates correct widget composition but lacks Riverpod providers, proper error handling, and navigation wiring. Treat Stitch output as a wireframe reference, not a copypaste source.

**Confidence:** MEDIUM — Stitch's Flutter export is real and functional (confirmed 2026), but automated token extraction into ThemeExtension classes is not supported. Manual extraction is the current workflow.

---

## Navigation Architecture

### Current Navigation Map

```
/                   → auto-redirect (GoRouter)
/onboarding         → GoRouter
/home               → GoRouter (HomeScreen)
  └─ FAB tap        → Navigator.push (not in GoRouter)
       ├─ /create-group  → GoRouter (but entered via push in HomeScreen FAB)
       └─ /join-group    → GoRouter
/group/:id          → GoRouter (GroupDetailScreen)
  └─ FAB tap        → Navigator.push → EventTypePickerScreen
  └─ event card tap → Navigator.push → EventCommandCenter
       └─ module tap → Navigator.push → LedgerScreen / GearScreen / LogisticsScreen
/group/:id/settings → GoRouter (nested subroute)
/settings           → GoRouter
```

Tap depth to reach ledger: Home → Group → Event → Ledger = 4 taps. EventCommandCenter and all module screens are invisible to GoRouter — deep links and back-stack management are fragile.

### Recommended Navigation Restructuring

**Phase 1 (low risk): Add event-level routes to GoRouter**

Add routes to `AppRoutes` and `app_router.dart` without changing any existing `Navigator.push` calls yet. This creates the deep-link infrastructure:

```dart
// New routes in app_router.dart
static const String eventDetail  = '/group/:groupId/event/:eventId';
static const String eventLedger  = '/group/:groupId/event/:eventId/ledger';
static const String eventGear    = '/group/:groupId/event/:eventId/gear';
static const String eventLogistics = '/group/:groupId/event/:eventId/logistics';
static const String eventVault   = '/group/:groupId/event/:eventId/vault';
static const String eventMemories = '/group/:groupId/event/:eventId/memories';
```

**Phase 2 (medium risk): Replace Navigator.push with context.push in event screens**

Replace the 7 files using `Navigator.of(context).push(AppPageRoute(...))` in the events/groups feature area with `context.push(AppRoutes.eventDetail(...))`. This is the primary navigation flattening work.

The `AppPageRoute` slide transition is preserved by using GoRouter's `pageBuilder` with `CustomTransitionPage` (same pattern already used for `/group/:id` in the current router).

**Phase 3 (flatter dashboard): Rich home screen using GoRouter**

The new home dashboard is a single-scroll view. Group cards remain tappable to `context.push('/group/:id')`. The dashboard does not require a bottom navigation bar — the app is still single-stack. `StatefulShellRoute` is not needed because there are no parallel top-level sections.

**Confidence:** HIGH — GoRouter nested routes with `parentNavigatorKey` are well-established for this pattern. The existing router already uses `CustomTransitionPage` for transitions; extending it to event sub-routes is straightforward.

### Navigation Flattening Strategy

The "reduce tap depth" goal is partially achieved via navigation restructuring, but primarily via UI redesign:

| Tap reduction | How |
|---------------|-----|
| Balance summary on home dashboard | User sees cross-group debt/credit without entering any group |
| Recent activity on home dashboard | Latest 5 activity items visible without entering a group |
| Quick-add expense from group card | Long-press or swipe reveals add expense shortcut |
| Event cards on group detail show balance | No need to enter EventCommandCenter just to see "how much did this trip cost?" |

Navigation flattening is content surfacing, not route elimination. The routes still exist — but common answers (how much do I owe?) appear one level higher.

---

## Component Library Architecture

### Current Shared Widgets

```
lib/shared/widgets/
├── app_tab_bar.dart       — gradient pill tab bar
├── empty_state_view.dart  — consistent empty states
├── loading_button.dart    — button with loading spinner
├── module_header.dart     — dark/light header with back button (light/dark variants)
├── offline_banner.dart    — connectivity strip
├── search_filter_bar.dart — expandable search + filter
├── skeleton_loader.dart   — loading placeholders
└── smart_module_card.dart — event module cards in CommandCenter
```

All import `AppColors` directly. None read from `ThemeData`. This must change before the palette can be swapped.

### Recommended Component Evolution

**Keep and migrate (all 8 shared widgets):**
Each shared widget needs one pass: replace `AppColors.*` references with `Theme.of(context).*` or `AppColorScheme.of(context).*`. No structural changes needed for most — this is a mechanical token substitution.

`ModuleHeader` is an exception. Its `useDarkTheme` boolean toggle creates a dual-implementation widget. The new design system should use a single `ModuleHeader` that reads semantic tokens (the "dark header" becomes `backgroundGradient: colors.headerGradient` rather than a hardcoded dark gradient). This simplifies the widget from ~200 LOC to ~120 LOC.

**Add for dashboard:**

```
lib/shared/widgets/
├── ...existing widgets...
├── dashboard_section_header.dart   — NEW: "Your Groups" / "Recent Activity" section headers
├── balance_pill.dart               — NEW: compact debt/credit indicator used on cards
├── event_timeline_tile.dart        — NEW: timeline entry for group activity feed
└── hero_balance_card.dart          — NEW: full-width balance summary for home dashboard
```

**Component library structure (atomic design, light version):**

The full atomic-design hierarchy is overkill for a 130-file codebase. Apply a simplified two-level model:

| Level | Location | Examples |
|-------|----------|---------|
| Tokens | `lib/core/theme/` | Colors, spacing, radii |
| Atoms | `lib/shared/widgets/` | BalancePill, LoadingButton, EmptyStateView |
| Organisms | `lib/features/*/widgets/` | GroupBalanceHero, EventModuleList, GroupCard |
| Screens | `lib/features/*/screens/` | GroupDetailScreen, HomeScreen |

Feature-specific widgets stay in `lib/features/{feature}/widgets/`. Cross-feature reusable atoms go to `lib/shared/widgets/`. The line is: "would two different features use this widget?" If yes → shared. If no → keep in feature.

---

## Animation Architecture

### Existing Animation Stack

The codebase already uses `flutter_animate ^4.5.0` and `shimmer ^3.0.0`. The home screen and several feature screens use `.animate().fadeIn().slideY()` chains. This is the right approach — do not introduce a second animation package.

### Recommended Animation Patterns

**Pattern 1: Entry animations via flutter_animate**

Already in use on HomeScreen list items. Extend to all redesigned screens:

```dart
// Standard enter animation — apply to any card entering a list
Widget card = SomeCard(...)
  .animate()
  .fadeIn(duration: 300.ms)
  .slideY(begin: 0.04, end: 0, curve: Curves.easeOutCubic,
          delay: Duration(milliseconds: 40 * index.clamp(0, 8)));
```

The `clamp(0, 8)` cap is important — stagger should stop after 8 items. Beyond that, users have already scrolled and the animation adds delay without delight.

**Pattern 2: Implicit animations for state changes**

For color/size changes on interaction (balance pill changing from red to green on settle up, buttons changing state), use Flutter's built-in implicit animation widgets:

```dart
AnimatedContainer(
  duration: const Duration(milliseconds: 200),
  curve: Curves.easeInOut,
  color: isOwed ? colors.debtRed : colors.creditGreen,
)
```

This is lighter than `flutter_animate` and sufficient for micro-interactions.

**Pattern 3: Page transitions via GoRouter pageBuilder**

All existing route transitions use `CurvedAnimation(curve: Curves.easeOutCubic)` with 300ms duration. Keep this as the universal transition spec. The redesign does not require hero animations or shared element transitions — they would add complexity without commensurate value in a list → detail app.

**Pattern 4: SkeletonLoader for loading states**

`SkeletonLoader.groupList()` is already implemented via shimmer. Extend with `SkeletonLoader.dashboardHero()` and `SkeletonLoader.eventCard()` for new dashboard shapes.

### Animation Performance Rules

- Never animate more than 8 list items simultaneously (stagger cap above)
- Use `MediaQuery.of(context).disableAnimations` guard (already used in HomeScreen — keep this pattern on all new screens)
- Avoid `flutter_animate` on widgets that rebuild frequently (e.g., providers watching balance streams). Wrap animating widget in `AnimatedSwitcher` keyed to the data state instead
- Prefer 200–400ms durations. Under 200ms feels abrupt on the earthy warm aesthetic; over 400ms feels sluggish

---

## Phased Redesign Strategy

### The Core Constraint

63 files import `AppColors`. All 14 feature areas have screens. A "redesign everything at once" approach creates an unboundable phase with high regression risk across the 624-test suite.

The correct strategy is **outside-in**: redesign from the first screen users see to the deepest, migrating the design token layer once per screen rather than globally.

### Recommended Build Order

**Phase A — Design foundation (no screen changes)**

1. Create `app_tokens.dart` with the new warm earthy palette constants
2. Create `AppColorScheme` and `AppSpacing` ThemeExtension classes
3. Update `AppTheme.lightTheme` to register the new extensions AND apply the new `ColorScheme` values
4. Update `AppTheme.lightTheme` with new warm palette colors (this changes the global appearance — plan a visual review checkpoint)
5. Write token tests: verify `AppColorScheme.of(context)` resolves on a pumped MaterialApp

**Why Phase A comes first:** If the token architecture is not in place before screen redesign starts, each screen redesign is a debt-creation event (new hardcoded values that will need another migration pass).

**Phase B — Splash + onboarding (2 screens, no test dependencies)**

6. Redesign `_SplashScreen` in `app_router.dart` — warm background, terracotta logo
7. Redesign `OnboardingScreen` — warm earthy illustration backgrounds

These screens have zero widget test coverage for their visual layout (tests check completion state via SharedPreferences). Safe to redesign freely.

**Phase C — Home dashboard (1 screen, 1 test file)**

8. Redesign `HomeScreen` as rich single-scroll dashboard: balance summary hero, group cards with inline balance pills, recent activity strip
9. Migrate `GroupCard` widget to new tokens
10. Migrate `OfflineBanner` to new tokens
11. Update `test/features/home/home_screen_groups_test.dart` — find widgets by semantics/key, not by color

**Phase D — Group detail (1 screen, 3 test files)**

12. Redesign `GroupDetailScreen` — restructured layout per new information hierarchy
13. Migrate `GroupBalanceHero`, `GroupMemberBalanceCard`, `GroupSpendingStats`, `InviteCodeDisplay` to new tokens
14. Add `/group/:id/event/:eventId` route to GoRouter (Phase 1 of navigation restructuring)
15. Update `group_detail_screen_test.dart`, `group_screens_test.dart`, `group_settle_up_screen_test.dart`

**Phase E — Event hub (1 screen, implicitly tested via group tests)**

16. Redesign `EventCommandCenter` — keep the dark header concept but re-skin with earthy palette
17. Replace `Navigator.push` in `GroupDetailScreen` → `context.push(AppRoutes.eventDetail(...))`
18. Replace `Navigator.push` in `EventCommandCenter` → `context.push(...)` for module routes
19. Migrate `EventModuleList`, `EventSpendingHero`, `EventCard` to new tokens

**Phase F — Module screens (6 screens, highest test density)**

20. Redesign `LedgerScreen` and its widgets (15 widget files — the largest module)
21. Redesign `GearScreen`
22. Redesign `LogisticsScreen`
23. Redesign `VaultScreen`
24. Redesign `MemoriesScreen`
25. Redesign `ActivityFeedScreen`

Module screens are redesigned last because: they have the most test coverage, the most complex widget trees, and the smallest user-facing impact on first impression. Getting the home → group → event flow right matters more for the "eye-catching" goal than perfecting the add-expense form.

**Phase G — Token cleanup**

26. Grep for remaining `AppColors.*` references
27. Delete `AppColors` class (final cleanup)
28. Remove dark theme support from `AppTheme` (light-only per product spec)

### Test Preservation Strategy

The 624-test suite must stay green throughout. Rules for redesign phases:

| Test type | Impact of redesign | Mitigation |
|-----------|-------------------|------------|
| Unit tests (logic, services) | None — no UI dependency | No changes needed |
| Widget tests finding widgets by `Text('string')` | Safe — label text preserved | No changes needed |
| Widget tests finding by `Icon(Iconsax.some_icon)` | Safe if icons preserved | Keep icon selections during redesign |
| Widget tests checking specific colors | Breaking | Refactor: find by Key or semantics label |
| Widget tests checking `ModuleHeader` dark theme | May break if `useDarkTheme` removed | Refactor header test before removing bool |

The only risky tests are ones that check specific colors or rely on widget tree structure that changes (e.g., tests finding the back button by traversing from `AppBar`). These should be refactored to use `Key` or `Semantics` labels as each screen is redesigned — not all at once.

---

## Integration Points: New vs. Modified

### Modified Files

| File | Type of Change | Risk |
|------|---------------|------|
| `lib/core/theme/app_theme.dart` | Extend with new ColorScheme, register ThemeExtension instances, remove dark theme | MEDIUM — 63 importers |
| `lib/shared/widgets/module_header.dart` | Replace `AppColors.*` with `AppColorScheme.of(context)`, remove `useDarkTheme` bool | MEDIUM — used in 5+ screens |
| `lib/core/router/app_router.dart` | Add event-level routes, add `parentNavigatorKey` for full-screen routes | LOW — additive |
| `lib/features/home/screens/home_screen.dart` | Full redesign | MEDIUM — 1 test file |
| `lib/features/groups/screens/group_detail_screen.dart` | Full redesign, token migration | HIGH — 3 test files |
| `lib/features/events/screens/event_command_center.dart` | Full redesign, Navigator.push → GoRouter | MEDIUM — covered via group tests |

### New Files

| File | Purpose |
|------|---------|
| `lib/core/theme/app_tokens.dart` | Raw primitive palette values |
| `lib/core/theme/extensions/app_color_scheme.dart` | Semantic color ThemeExtension |
| `lib/core/theme/extensions/app_spacing.dart` | Spacing scale ThemeExtension |
| `lib/shared/widgets/hero_balance_card.dart` | Home dashboard balance hero |
| `lib/shared/widgets/balance_pill.dart` | Compact debt/credit indicator |
| `lib/shared/widgets/dashboard_section_header.dart` | Section headers for dashboard scroll |
| `lib/shared/widgets/event_timeline_tile.dart` | Activity feed timeline entry |

### Preserved Unchanged

- All services, repositories, providers — the data layer is untouched
- `BalanceCalculator`, `MoneySerializer`, `Decimal` usage — financial logic is untouched
- `LocalDatabase`, `OfflineRepository`, `FirestoreRepository` — backend layer is untouched
- Test helper patterns (fake providers, `FakeFirebaseFirestore`, `MockFirebaseAuth`) — testing infrastructure is untouched

---

## Scaling Considerations

This is a UI architecture, not a distributed systems concern. The relevant scaling dimension is **codebase scale** — how the design system stays maintainable as screens grow.

| Concern | Current (14 screens) | Future (20+ screens) |
|---------|---------------------|----------------------|
| Token drift | Medium risk — `AppColors` changes might miss files | Low risk with ThemeExtension — token resolution is compile-time safe |
| Shared widget consistency | Medium risk — 8 widgets use direct color constants | Low risk once token migrated — widget tree reads theme |
| Navigation spaghetti | Growing — 41 imperative push calls | Resolved with GoRouter subroutes |
| Test fragility | Medium — color-based finders will break on palette change | Low once tests use Key/semantics |

---

## Anti-Patterns to Avoid

### Anti-Pattern 1: Big Bang Token Migration

**What people do:** Create `AppColorScheme` and immediately replace all `AppColors.*` references in one commit across 63 files.

**Why it's wrong:** Creates an unreviable PR, breaks the test suite in unpredictable ways, and makes bisecting regressions nearly impossible.

**Do this instead:** Coexist `AppColors` and the new token system. Migrate one feature at a time, screen by screen. Each phase compiles and tests pass.

### Anti-Pattern 2: Stitch Code Copypaste

**What people do:** Export Flutter code from Stitch and paste it directly into screen files, replacing existing widget trees.

**Why it's wrong:** Stitch output has no Riverpod providers, no error states, no navigation wiring, and uses Material 3 defaults that clash with the existing typography setup. It also does not respect the immutability coding style requirement — Stitch generates `setState` in `StatefulWidget` trees.

**Do this instead:** Use Stitch output as a layout and color reference. Manually implement the widget tree using the Stitch design as a visual spec.

### Anti-Pattern 3: Adding Bottom Navigation for Navigation Depth

**What people do:** Add a persistent bottom navbar with tabs (Home, Groups, Activity, Settings) to solve the "too many taps" problem.

**Why it's wrong:** The app has one primary content hierarchy: Group → Event → Module. A tab bar adds a navigation paradigm that does not match the data model. Users do not context-switch between "Ledger mode" and "Gear mode" — they work within an event. A bottom nav would require `StatefulShellRoute` with 4 branches, a significant routing overhaul, and new animation coordination logic.

**Do this instead:** Surface key information higher in the existing hierarchy (balance summary on home, event balances on group detail). Reduce taps through content density, not through navigation architecture changes.

### Anti-Pattern 4: Animating Riverpod-Provided Data Directly

**What people do:** Apply `.animate().fadeIn()` directly to a `Consumer` widget that watches a `StreamProvider`, causing the animation to re-fire every time the stream emits a new value (including server-pushed updates).

**Why it's wrong:** Real-time Firestore listeners can fire 5-10 times per second during active use. The animation would fire repeatedly, creating visual noise.

**Do this instead:** Wrap in `AnimatedSwitcher` keyed to a stable value (e.g., `key: ValueKey(expenses.length)`), or animate only on the initial mount using `AnimationController` with `vsync` and `animateTo(1.0)` in `initState`.

---

## Sources

- [Flutter ThemeExtension API](https://api.flutter.dev/flutter/material/ThemeExtension-class.html) — official design token extension mechanism
- [Creating Reusable Design System Tokens in Flutter with Theme Extensions](https://vibe-studio.ai/insights/creating-reusable-design-system-tokens-in-flutter-with-theme-extensions) — ThemeExtension implementation patterns
- [Building a Design System in Flutter — LeanCode](https://leancode.co/blog/building-a-design-system-in-flutter-app) — atomic design adapted for Flutter
- [Google Stitch Flutter export — DEV Community](https://dev.to/safiullahkorai/how-flutter-developers-can-use-stitch-to-build-client-apps-faster-in-2026-32g) — Stitch → Flutter workflow, manual implementation caveat
- [GoRouter StatefulShellRoute — codewithandrea](https://codewithandrea.com/articles/flutter-bottom-navigation-bar-nested-routes-gorouter/) — nested navigation with state preservation
- [GoRouter nested routes with parentNavigatorKey](https://github.com/flutter/flutter/issues/131091) — full-screen routes inside shell routes
- [flutter_animate 2025 guide — Medium](https://medium.com/@arshadhp98/flutter-animate-the-easiest-way-to-bring-your-ui-to-life-2025-edition-ac7a0f9cb9dd) — animation chaining patterns
- [Flutter animations micro-interactions guide — Medium](https://medium.com/@flutter-app/animations-micro-interactions-in-flutter-make-your-ui-delightful-592fb9da6e11) — implicit animation best practices
- [Material 3 for Flutter — m3.material.io](https://m3.material.io/develop/flutter) — ColorScheme integration, ThemeData assembly

---

*Architecture research for: Flutter UI/UX overhaul — design system, navigation, component library*
*Researched: 2026-03-28*
