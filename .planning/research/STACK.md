# Stack Research

**Domain:** Flutter UI/UX overhaul — warm earthy design system, micro-interactions, rich dashboard, flatter navigation
**Researched:** 2026-03-28
**Milestone:** v2.0 Major UI/UX Overhaul
**Confidence:** HIGH for package versions (verified pub.dev), MEDIUM for Stitch workflow (new tool, limited integration docs)

---

## Context: What This Milestone Is NOT Doing

This is a UI/UX overhaul on top of a complete, shipping app (v1.0). The backend stack (Firebase, Riverpod 2.x, sqflite, GoRouter 17.x) is already locked and validated across 624 tests. This research covers **only new packages and changes needed for visual/UX work**. Do not re-research Firebase, Riverpod, or sqflite — those are settled.

### Already in pubspec.yaml (no action needed)

| Package | Version | Status |
|---------|---------|--------|
| `flutter_animate` | `^4.5.0` | Already installed — primary animation engine |
| `shimmer` | `^3.0.0` | Already installed — loading states |
| `google_fonts` | `^6.1.0` | Already installed — Plus Jakarta Sans |
| `material_symbols_icons` | Not yet in pubspec | Confirmed referenced in CLAUDE.md as "already in use" |
| `iconsax` | `^0.0.8` | Already installed |
| `cached_network_image` | `^3.3.1` | Already installed |
| `go_router` | `^17.1.0` (upgraded in v1.0) | Already installed — StatefulShellRoute available |

---

## Recommended Stack

### Animation System

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| `flutter_animate` | `^4.5.2` (upgrade from 4.5.0) | Micro-interactions, entrance animations, state transitions | Already installed. The standard for Flutter UI polish — chainable `.animate()` API on any widget, handles fade, slide, scale, shimmer. Version 4.5.2 is the latest stable (published November 2024). No API changes from 4.5.0 — safe upgrade. |
| `animations` | `^2.1.2` | M3 page transitions — container transform, shared axis, fade through | Flutter.dev maintained. Provides the exact Material motion patterns needed for flatter navigation: `ContainerTransformPageRoute` for hero-style screen transitions, `SharedAxisTransition` for horizontal tab transitions, `FadeScaleTransition` for FAB/modal entries. This is the correct package for M3 transitions — not roll-your-own `AnimatedSwitcher`. Published March 2026. |
| `lottie` | `^3.3.2` | JSON-based animations for empty states, loading spinners, onboarding illustrations | Use for pre-designed animations from LottieFiles (free library has 1000s of relevant travel/group assets). Pure Dart, no native code. Flutter 3.27+ required — confirmed compatible. Reserve for complex looping animations where `flutter_animate` is insufficient. |

**flutter_animate vs animations vs lottie — when to use each:**
- `flutter_animate`: Entrance/exit animations on existing widgets. Button tap feedback. List item stagger. Fast to implement, no asset files.
- `animations`: Screen-to-screen transitions with Material motion semantics. Dashboard → detail card expansions. Use `ContainerTransformPageRoute` as the drop-in for `AppPageRoute` in `page_transitions.dart`.
- `lottie`: Empty states with personality (e.g., "No trips yet" animated illustration). Onboarding animations. Loading states that need brand character. Requires a `.json` asset file — download from LottieFiles.

**Confidence:** HIGH — all three verified on pub.dev March 2026.

---

### Design Token System

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| Flutter `ThemeExtension` (built-in) | Flutter SDK (no package) | Typed design token carrier for custom tokens not covered by M3 ColorScheme | The correct approach for the earthy palette (terracotta, sand, olive) is to extend M3's ColorScheme with project-specific token classes. ThemeExtension allows strongly typed, lerp-aware, tree-propagated token sets. Zero package overhead. The existing `AppColors` class in `app_theme.dart` becomes input data for two new classes: `AppColorTokens extends ThemeExtension<AppColorTokens>` and `AppSpacingTokens extends ThemeExtension<AppSpacingTokens>`. |
| `ColorScheme.fromSeed` (built-in) | Flutter SDK | Generates M3 tonal palette from seed color | The terracotta seed (`Color(0xFFE2725B)`) will generate a full warm palette across primary/secondary/tertiary/error/surface roles. The existing `AppTheme.lightTheme` uses `useMaterial3: true` but a manually specified `ColorScheme.light()` — switch to `ColorScheme.fromSeed(seedColor: terracottaSeed, brightness: Brightness.light)` for the overhaul. Override specific roles that diverge from the generated palette (e.g., force olive for tertiary). |

**No external design token packages needed.** `design_tokens_builder`, `token_theme_kit`, and `mix` are all valid for larger teams with Figma exports, but add significant complexity. The correct architecture for this app is:

1. Define `AppColorTokens` and `AppSpacingTokens` as `ThemeExtension` subclasses
2. Register them in `AppTheme.lightTheme` via `ThemeData.extensions`
3. Access via `Theme.of(context).extension<AppColorTokens>()!`
4. The existing `AppColors` static constants become the raw values that populate these extensions

This keeps design tokens typed, tree-propagated, and animatable (lerp) without adding a dependency.

**Confidence:** HIGH — ThemeExtension pattern is official Flutter API, documented at api.flutter.dev.

---

### Navigation Enhancement

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| `go_router` | `^17.1.0` (already installed) | Add `StatefulShellRoute` for persistent bottom nav | GoRouter 17.x includes `StatefulShellRoute.indexedStack()` — the standard pattern for M3 `NavigationBar` with persistent tab state. The current app uses GoRouter for top-level routes + `Navigator.push` for sub-screens. The overhaul adds a persistent `NavigationBar` at the top shell level. **No version upgrade needed** — 17.1.0 is already the installed version. |
| Flutter `NavigationBar` widget (built-in) | Flutter SDK | M3 bottom navigation bar | Replaces any `BottomNavigationBar` usage. M3 `NavigationBar` is the current standard — taller container, indicator pill on active destination, `NavigationDestination` children, `onDestinationSelected` + `selectedIndex` API. No package needed. |

**Navigation overhaul pattern:**

The existing GoRouter config has top-level routes (`/home`, `/create-trip`, etc.) without persistent navigation. The overhaul introduces a `StatefulShellRoute` wrapping the top-level destinations (Home, Groups, Profile/Settings), with `NavigationBar` rendered in the shell's `builder`. Each branch maintains its own Navigator stack. The existing `Navigator.push`-based module screens (CommandCenter, Ledger, Gear, etc.) remain unchanged — they push on top of the branch navigator.

**go_router 17.x breaking change note:** `ShellRoute` now notifies GoRouter observers by default (`notifyRootObserver: true`). If `SentryNavigatorObserver` generates noise from tab switches, set `notifyRootObserver: false` on the `StatefulShellRoute`.

**Confidence:** HIGH for navigation pattern. HIGH for go_router version.

---

### Visual Richness — Icons

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| `material_symbols_icons` | `^4.2906.0` | Variable-weight icons for the new design language | 4177 icons with fill/weight/grade/optical size parameters. Recommended over `iconsax` for the overhaul because: (a) already referenced in the codebase per CLAUDE.md, (b) supports weight variations that match the earthy design language (lighter weight = more refined feel), (c) future-proof — Flutter will natively support Material Symbols, at which point the package import is the only removal needed. Published January 2026. |

**iconsax vs material_symbols_icons decision:**

Keep `iconsax` for any existing screens that already use it (to avoid churn). Use `material_symbols_icons` for all new screens in the overhaul. Do not rip out iconsax globally — that's unnecessary scope. The two can coexist.

**Confidence:** HIGH — version verified pub.dev 2026-01-31.

---

### Visual Richness — Illustrations & SVG

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| `flutter_svg` | `^2.2.4` | Render SVG illustrations (empty states, onboarding, event type icons) | The standard SVG renderer for Flutter. Version 2.2.4 published February 2026. For performance with many SVGs: pre-compile to `.vec` format using `vector_graphics_compiler`. `SvgPicture.asset('assets/illustrations/empty_trips.svg')` is the primary API. |

**Illustration sourcing approach:**

Do NOT add a heavy illustration package (e.g., `flutter_undraw`). Source SVG files from:
- **unDraw** (undraw.co) — free, open license, earthy color customizable, travel/group themed
- **LottieFiles** — for animated variants (loaded via `lottie` package)
- Custom SVG designed in Google Stitch export or Figma

Store SVGs in `assets/illustrations/`. Register in `pubspec.yaml` under `flutter: assets:`. The earthy terracotta color can be injected into unDraw SVGs before committing them as assets (unDraw supports color parameterization via URL or SVG editing).

**Confidence:** HIGH for flutter_svg version. MEDIUM for illustration sourcing workflow (standard practice, no single authoritative source).

---

### Loading States

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| `skeletonizer` | `^2.1.3` | Skeleton loading for dashboard cards, group lists, activity feeds | Upgrade from `shimmer ^3.0.0` for dashboard content. Skeletonizer wraps your real layout and renders it as a skeleton automatically — no duplicate skeleton widget needed. Correct choice for the rich dashboard home where content is structured (group cards, balance rows, activity items). Published February 2026. |

**shimmer vs skeletonizer — keep both, different roles:**

- `shimmer` (existing): Keep for `SkeletonLoader` in `lib/shared/widgets/` — it's already used for simple single-line loading bars
- `skeletonizer` (add): Use for full-screen skeleton states on the new dashboard, group detail, and event screens where the full card layout should animate

The two coexist cleanly. Add `skeletonizer` alongside `shimmer` rather than replacing it.

**Confidence:** HIGH — version verified pub.dev February 2026.

---

### Haptic Feedback

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| `haptic_feedback` | `^0.6.4+3` | Tactile micro-interactions for button taps, swipes, success states | The Flutter SDK's built-in `HapticFeedback` class provides only 4 patterns (lightImpact, mediumImpact, heavyImpact, selectionClick) with inconsistent Android behavior. `haptic_feedback` package provides iOS-style haptic patterns emulated consistently on Android API 26+. Use `HapticFeedback.mediumImpact()` from the package on primary CTAs, `HapticFeedback.selectionClick()` on tab switches and toggles. Published December 2025. |

**Confidence:** HIGH — version verified pub.dev December 2025.

---

### Page Indicators (Onboarding / Carousels)

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| `smooth_page_indicator` | `^2.0.1` | Animated dot indicators for onboarding PageView and dashboard carousels | The standard choice for page indicators in Flutter. Supports WormEffect, ExpandingDotsEffect, JumpingDotEffect — all relevant for the warm earthy design. The existing onboarding PageView uses a manual indicator — replace with this. Published December 2025. |

**Confidence:** HIGH — version verified pub.dev December 2025.

---

### Google Stitch Integration

Google Stitch is a Google Labs AI design tool at `stitch.withgoogle.com`. It generates UI screens from text prompts, image uploads, and existing design screenshots. As of March 2026, it supports Flutter code export.

**What Stitch actually does for Flutter:**

1. You design screens via prompt in Stitch (or upload screenshots to redesign)
2. Stitch generates Flutter widget code via its "Export" feature
3. The output is functional Flutter code using standard Material 3 widgets — not a custom DSL
4. You paste/adapt the output into the existing feature structure

**Stitch-to-Flutter workflow (correct approach for this app):**

```
1. Design in Stitch:
   - Upload current app screenshots to Stitch
   - Prompt: "Redesign with warm earthy palette: terracotta #E2725B primary,
     sand #F5E6D3 background, olive #6B7C3A accent. Light theme only."
   - Generate all major screens (home dashboard, group detail, event screens)
   - Iterate in Stitch until design is correct

2. Extract design tokens from Stitch output:
   - Note the exact hex values Stitch uses (it will generate a consistent palette)
   - Map these to the AppColorTokens ThemeExtension classes
   - Extract spacing values, border radii, and font weights

3. Use Stitch code as reference, NOT copy-paste:
   - Stitch Flutter output often uses hardcoded colors and inline styles
   - Use it as a layout and visual reference
   - Re-implement using AppColors, AppTheme, and existing widget architecture
   - This keeps the codebase consistent with the design system

4. SVG illustrations: Stitch can generate placeholder illustrations
   - Export as SVG or describe for unDraw sourcing
```

**What Stitch is NOT:**

- It does not generate production-ready Flutter code. Community testing confirms it "works well for rapid prototyping and MVPs but requires developer review and refinement."
- It does not export design tokens as a `ThemeExtension` file — you extract them manually from its output
- The MCP/Antigravity pipeline (Stitch → Antigravity agent → Flutter code) is experimental and unreliable for complex state logic

**No package addition needed for Stitch.** It is a web tool, not a Flutter package. The workflow is design-tool → manual implementation using the existing Flutter stack.

**Confidence:** MEDIUM for Stitch export quality (Google Labs, actively improving, Flutter support confirmed but not deep). The design token extraction workflow is the practical approach — do not depend on Stitch code being production-ready.

---

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| `ThemeExtension` (built-in) | `mix` package (v2.0.1) | If the team wanted a full styling DSL with composable style objects. `mix` is excellent but adds significant conceptual overhead. For a single-developer project doing a targeted overhaul, ThemeExtension is less friction. |
| `animations` (Flutter.dev) | Roll-your-own `AnimatedSwitcher` | Never. `animations` provides tested M3 motion patterns. Custom AnimatedSwitcher for screen transitions adds maintenance burden with no benefit. |
| `flutter_svg` | `jovial_svg` | If SVG parsing performance is the bottleneck — jovial_svg pre-compiles to a binary format. The pre-compilation workflow for flutter_svg via `vector_graphics_compiler` achieves the same result; prefer the more widely used package. |
| `skeletonizer` | Keep `shimmer` only | `shimmer` requires you to build a duplicate skeleton layout. `skeletonizer` wraps real widgets. For the rich dashboard, `skeletonizer` saves meaningful implementation time. |
| `lottie` | `rive` (v0.14.4) | Use Rive if animations need to be interactive (respond to touch, have state machines). Lottie is simpler for one-shot or looping animations from a file. For empty states and onboarding, Lottie is appropriate. Rive is overkill unless an animation responds to user input. |
| `haptic_feedback` package | SDK `HapticFeedback` class | Use the SDK class for very simple cases (light impact only). The package is worth adding for more expressive haptic patterns across the full app. |
| `NavigationBar` (built-in) | `persistent_bottom_nav_bar_v2` or similar | Only if needing highly custom nav bar visuals that M3 NavigationBar cannot achieve. M3 NavigationBar supports indicator color, destination colors, and height customization — sufficient for the earthy design. Avoid external nav bar packages. |

---

## What NOT to Add

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| `get` / GetX | State management and routing conflict with Riverpod 2.x + GoRouter already in use. Mixing routing systems causes deep link and navigation observer conflicts. | GoRouter + Riverpod (already installed) |
| `flutter_screenutil` | Adaptive sizing package that requires `ScreenUtil.init()` and wraps the widget tree. The app already uses fixed spacing tokens (`space4`–`space32`) which are appropriate for a mobile-first OMR-focused app. Adding ScreenUtil mid-project requires updating all spacing references. | Existing `AppColors.space*` constants, `MediaQuery.of(context).size` for responsive checks |
| `auto_route` | Alternative router that conflicts with GoRouter. The GoRouter upgrade to 17.x with StatefulShellRoute covers the navigation overhaul requirements. | GoRouter 17.x (already installed) |
| `fluent_ui` / third-party component libraries | Add 200+ components with their own design language, conflicting with the M3 + earthy token system being built. These libraries resist customization. | Material 3 widgets + AppTheme overrides |
| `velocity_x` | Utility library that adds chainable Flutter widgets and extensions. Convenient but adds a dependency for what is essentially syntax sugar over Flutter APIs. | Standard Flutter widget API |
| Additional icon packages (e.g., `line_icons`, `font_awesome_flutter`) | The app already has `iconsax` + `material_symbols_icons`. Three icon libraries is already at the maximum. Additional icon packages add significant bundle size. | Use `material_symbols_icons` for new screens |
| `animate_do` | A second animation package redundant with `flutter_animate`. The app already has flutter_animate — it covers all the same animations. | `flutter_animate` (already installed) |

---

## Dependency Delta for v2.0 UI/UX Milestone

Changes to `pubspec.yaml` for this milestone only:

**Add:**
```yaml
dependencies:
  animations: ^2.1.2         # M3 page transitions (ContainerTransform, SharedAxis)
  lottie: ^3.3.2             # Animated illustrations for empty states / onboarding
  material_symbols_icons: ^4.2906.0  # Variable-weight icons (if not already added)
  skeletonizer: ^2.1.3       # Dashboard skeleton loading states
  haptic_feedback: ^0.6.4+3  # Cross-platform haptic patterns
  smooth_page_indicator: ^2.0.1  # Onboarding and carousel dots
  flutter_svg: ^2.2.4        # SVG illustrations
```

**Upgrade:**
```yaml
dependencies:
  flutter_animate: ^4.5.2    # was ^4.5.0 — patch upgrade, no API changes
```

**Keep unchanged (already installed, no action):**
```yaml
  shimmer: ^3.0.0            # Keep alongside skeletonizer for simple loading bars
  google_fonts: ^6.1.0       # Plus Jakarta Sans
  iconsax: ^0.0.8            # Keep for existing screens, new screens use material_symbols_icons
  cached_network_image: ^3.3.1
  go_router: ^17.1.0         # StatefulShellRoute already available
```

**No removals** for this milestone. The existing packages remain valid.

---

## Version Compatibility

| Package A | Compatible With | Notes |
|-----------|-----------------|-------|
| `animations: ^2.1.2` | Flutter 3.27+ | Maintained by Flutter.dev — always compatible with current SDK |
| `lottie: ^3.3.2` | Flutter 3.27+ | Package page explicitly states Flutter 3.27 minimum requirement |
| `skeletonizer: ^2.1.3` | `shimmer: ^3.0.0` | These coexist — different widget types, no conflicts |
| `flutter_animate: ^4.5.2` | `animations: ^2.1.2` | No conflict — different use cases, can be applied to same widget tree |
| `material_symbols_icons: ^4.2906.0` | `iconsax: ^0.0.8` | Both provide icon constants — no runtime conflicts |
| `haptic_feedback: ^0.6.4+3` | Flutter services API | Wraps platform channels — no conflicts with existing packages |
| `smooth_page_indicator: ^2.0.1` | `flutter_animate: ^4.5.2` | No conflict — indicators can be animated with flutter_animate |

---

## Integration Points with Existing app_theme.dart

The overhaul requires extending `app_theme.dart` without breaking the existing `AppColors` and `AppTheme` classes. The migration path:

**Step 1 — Add earthy palette constants to AppColors:**
```dart
// New earthy palette (replace or extend the existing Neo-Outdoor colors)
static const Color terracotta = Color(0xFFE2725B);
static const Color sand = Color(0xFFF5E6D3);
static const Color sandLight = Color(0xFFFAF4EE);
static const Color olive = Color(0xFF6B7C3A);
static const Color oliveLight = Color(0xFFEDF2E0);
static const Color warmBrown = Color(0xFF8B5E3C);
static const Color warmGray = Color(0xFF8C7B6B);
```

**Step 2 — Switch ColorScheme.light() to ColorScheme.fromSeed():**
```dart
colorScheme: ColorScheme.fromSeed(
  seedColor: AppColors.terracotta,
  brightness: Brightness.light,
).copyWith(
  tertiary: AppColors.olive,      // Force olive for tertiary role
  surface: AppColors.sand,        // Warm sand surface
),
```

**Step 3 — Create AppColorTokens ThemeExtension:**
```dart
class AppColorTokens extends ThemeExtension<AppColorTokens> {
  final Color terracotta;
  final Color sand;
  final Color olive;
  // ... project-specific tokens beyond M3 ColorScheme

  @override
  ThemeExtension<AppColorTokens> copyWith({...}) { ... }

  @override
  ThemeExtension<AppColorTokens> lerp(AppColorTokens? other, double t) { ... }
}
```

**Step 4 — Register in AppTheme.lightTheme:**
```dart
ThemeData(
  extensions: [AppColorTokens(terracotta: ..., sand: ..., olive: ...)],
  ...
)
```

**Step 5 — Access in widgets:**
```dart
final tokens = Theme.of(context).extension<AppColorTokens>()!;
Container(color: tokens.sand, ...)
```

The existing `AppColors` constants remain for backward compatibility. New screens use `Theme.of(context).extension<AppColorTokens>()`. Old screens continue using `AppColors.primary`, `AppColors.textPrimary`, etc.

---

## Sources

- [pub.dev: animations 2.1.2](https://pub.dev/packages/animations) — version confirmed March 2026
- [pub.dev: lottie 3.3.2](https://pub.dev/packages/lottie) — version confirmed September 2025
- [pub.dev: flutter_animate 4.5.2](https://pub.dev/packages/flutter_animate) — version confirmed November 2024
- [pub.dev: flutter_svg 2.2.4](https://pub.dev/packages/flutter_svg) — version confirmed February 2026
- [pub.dev: skeletonizer 2.1.3](https://pub.dev/packages/skeletonizer) — version confirmed February 2026
- [pub.dev: haptic_feedback 0.6.4+3](https://pub.dev/packages/haptic_feedback) — version confirmed December 2025
- [pub.dev: smooth_page_indicator 2.0.1](https://pub.dev/packages/smooth_page_indicator) — version confirmed December 2025
- [pub.dev: material_symbols_icons 4.2906.0](https://pub.dev/packages/material_symbols_icons) — version confirmed January 2026
- [pub.dev: go_router 17.1.0](https://pub.dev/packages/go_router) — version confirmed, StatefulShellRoute available
- [pub.dev: rive 0.14.4](https://pub.dev/packages/rive) — version confirmed (alternative to lottie, not recommended for this milestone)
- [Flutter API: ThemeExtension](https://api.flutter.dev/flutter/material/ThemeExtension-class.html) — design token architecture
- [Flutter API: ColorScheme.fromSeed](https://api.flutter.dev/flutter/material/ColorScheme/ColorScheme.fromSeed.html) — M3 tonal palette generation
- [Flutter API: NavigationBar](https://api.flutter.dev/flutter/material/NavigationBar-class.html) — M3 bottom navigation
- [Google Stitch](https://stitch.withgoogle.com/) — AI UI design tool, Flutter export capability confirmed
- [Stitch + Flutter workflow (DEV Community)](https://dev.to/techwithsam/stitch-antigravity-flutter-build-apps-with-ai-agents-in-2026-2pei) — MEDIUM confidence, practical workflow details
- [Google Developers Blog: Stitch announcement](https://developers.googleblog.com/stitch-a-new-way-to-design-uis/) — official announcement
- [Rive vs Lottie comparison 2025](https://dev.to/uianimation/rive-vs-lottie-which-animation-tool-should-you-use-in-2025-p4m) — recommendation rationale
- [vector_graphics_compiler SVG optimization](https://pub.dev/packages/vector_graphics_compiler) — flutter_svg performance path
- [unDraw open source illustrations](https://undraw.co/) — free SVG illustration source

---
*Stack research for: Rihla v2.0 UI/UX Overhaul (Flutter)*
*Researched: 2026-03-28*
