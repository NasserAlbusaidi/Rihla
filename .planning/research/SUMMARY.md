# Project Research Summary

**Project:** Rihla v2.0 — Major UI/UX Overhaul
**Domain:** Flutter mobile app — design system migration, navigation restructuring, visual redesign
**Researched:** 2026-03-28
**Confidence:** HIGH (stack, architecture, pitfalls verified) / MEDIUM (Stitch workflow, visual trend direction)

## Executive Summary

Rihla v2.0 is a visual and navigational overhaul of a fully functional, 624-test Flutter app. The backend (Firebase, Riverpod 2.x, sqflite, GoRouter 17.x) is stable and completely out of scope. The milestone delivers three things: a warm earthy design system (terracotta, sand, olive) replacing the current generic palette; a flatter information architecture that surfaces key data without deep tap hierarchies; and a rich dashboard home that makes the app feel alive rather than barren. Research confirms this combination — design token system + content surfacing + skeleton loading — is the standard playbook for group/social finance app redesigns in 2026, with Airbnb and Revolut as reference implementations for card richness and balance display respectively. Splitwise and Tricount, the direct competitors, use clinical blue/white palettes and flat list views — a genuine market gap that Rihla can own by committing to warmth and density.

The recommended approach is strictly outside-in and phased. The design token layer (ThemeExtension-based, two-layer palette/semantic split) must exist before any screen is touched. This is non-negotiable: without it, every screen change creates fresh hardcoded-value debt. Once tokens are in place, screens migrate progressively from the most-seen (Home) to the least-seen (module detail screens). Navigation flattening is achieved primarily through content surfacing — showing balance summaries, inline event data, and recent activity one level higher — not through structural navigation changes like adding a bottom tab bar. ARCHITECTURE.md research explicitly recommends against StatefulShellRoute for this app because the data model has a single hierarchy (Group → Event → Module), not parallel top-level sections.

The primary risks are all about the existing codebase's brittleness under visual change. The test suite has 257 `find.text()` calls that will cascade-fail on any label rename. The codebase has 895 direct `AppColors.*` references that will mass-compile-fail if the class is replaced rather than extended. The earthy palette itself is an accessibility risk — terracotta on sand fails WCAG AA at approximately 2.8:1 contrast ratio. All three are predictable, preventable, and must be addressed before any visual work begins.

---

## Key Findings

### Recommended Stack

The backend stack requires zero changes. UI work needs 7 new packages added to pubspec.yaml. The core additions are: `animations ^2.1.2` for Material 3 page transitions (ContainerTransform, SharedAxis), `skeletonizer ^2.1.3` for full-layout skeleton loading on the dashboard, `lottie ^3.3.2` for animated empty state illustrations, `flutter_svg ^2.2.4` for static SVG illustrations, `haptic_feedback ^0.6.4+3` for coordinated tactile micro-interactions, `smooth_page_indicator ^2.0.1` for onboarding carousels, and `material_symbols_icons ^4.2906.0` for variable-weight icons on new screens. Existing packages — `flutter_animate ^4.5.0` (upgrade to 4.5.2, patch-safe), `shimmer ^3.0.0`, `google_fonts ^6.1.0`, `iconsax ^0.0.8`, and `go_router ^17.1.0` — all stay unchanged. Google Stitch is a web design tool, not a package; its Flutter code export produces layout references and visual specs, not production-ready code.

**Core technologies:**
- `animations ^2.1.2`: M3 page transitions (ContainerTransform, SharedAxis) — Flutter.dev maintained, the correct package for Material motion semantics; never roll custom AnimatedSwitcher transitions for screen-level moves
- `skeletonizer ^2.1.3`: Full-layout skeleton loading — wraps the real widget layout and renders it as a skeleton automatically, eliminating duplicate skeleton widget code; coexists with existing `shimmer` which stays for simple loading bars
- `flutter_animate ^4.5.2` (upgrade from 4.5.0): Entry animations, list stagger, state transitions — already installed, chainable `.animate()` API on any widget; patch upgrade with zero API changes
- `lottie ^3.3.2`: Animated empty states and onboarding illustrations — for complex looping animations where flutter_animate is insufficient; requires a `.json` asset file from LottieFiles
- `haptic_feedback ^0.6.4+3`: Cross-platform tactile micro-interactions — provides iOS-style haptic patterns emulated consistently on Android API 26+, unlike the SDK's built-in 4-pattern `HapticFeedback` class
- Flutter `ThemeExtension` (built-in, no package): Typed design token carrier — strongly typed, lerp-aware, tree-propagated token sets with zero package overhead; the correct architecture for earthy palette tokens
- Flutter `ColorScheme.fromSeed` (built-in, no package): M3 tonal palette from terracotta seed — generates full warm palette across all M3 color roles from a single seed color

**What NOT to add:** `get`/GetX (routing conflict with GoRouter), `flutter_screenutil` (mid-project adoption requires touching 300+ spacing calls), `animate_do` (redundant with flutter_animate), `auto_route` (conflicts with GoRouter), `fluent_ui` or any third-party component library (resist customization, conflict with M3 + earthy token system), additional icon packages beyond `iconsax` + `material_symbols_icons`.

### Expected Features

Research benchmarked against Splitwise, Tricount, TripIt, Airbnb, Venmo, and Revolut. Key observation: Splitwise and Tricount are functionally mature but visually stagnant — clinical blue/white palettes, flat list views, spinners everywhere. This is a real market gap. Rihla can own warmth as a visual identity without looking derivative of any direct competitor.

**Must have (table stakes):**
- Balance summary visible on home screen without tapping — users open the app to answer "what do I owe?"; that answer must be instant; Venmo and Revolut both surface the primary number on first load
- Skeleton screens instead of spinners for content loads — perceived approximately 3x faster than spinners per NN/G research; "500ms skeleton feels fast; 500ms spinner feels slow"; currently missing across all data-fetching screens
- Context-specific illustrated empty states with a single clear CTA — "No expenses yet" with no guidance reads as broken; each empty screen must know WHY it is empty and what the user should do next
- Color-coded financial states — green (owed to you), red (you owe), gray (settled) is a universal fintech convention; violating it confuses users familiar with any finance app
- Readable typography hierarchy — H1/H2/body/caption clearly differentiated in weight and size; the "barren" look often comes entirely from uniform type weights
- Cards with visible elevation or border separation — content cards must visually separate from background; currently too much flat whitespace

**Should have (competitive differentiators):**
- Balance hero widget at top of home — net cross-group balance, color-coded, prominent above fold; Revolut reference
- Rich group cards with inline balance, member avatar row, last activity — bento-grid treatment vs. current flat name-only list; Airbnb reference for card richness
- Quick-action tray on home — Add Expense, Settle Up, Invite, Activity in one-tap reach; Revolut reference
- Warm earthy palette (terracotta/sand/olive) with grain/texture overlays — "tactile rebellion" against flat sterility; 2026 dominant trend; competitors own clinical blue/white so Rihla can own warmth without looking derivative
- Swipeable module tabs inside CommandCenter — replaces card-tap → push → back loop with horizontal swipe between Ledger, Gear, Logistics, Vault
- Event cards with type-specific color accent and inline financial summary — instant visual scanning; past events muted/desaturated, upcoming at full color
- Haptic feedback on all primary write actions — coordinated visual + haptic = premium feel; `HapticFeedback.lightImpact()` is a one-liner per action with high perceived quality lift

**Defer to later:**
- Dark mode — doubles all visual work; earthy palette is inherently light-themed; ship a complete polished light theme first; dark mode as future milestone if user demand warrants
- Rive animations — use static Lottie/SVG illustrations to ship on time; Rive's state machines (60fps, 2KB, interactive) are a polish pass after initial launch
- Per-user theme customization — fractures visual identity; the earthy palette IS the brand; customization is for productivity tools, not social coordination apps
- Animated background / parallax header — high battery drain during scroll; 30fps risk on mid-range Android; static grain/texture overlay achieves warmth at near-zero CPU cost
- Infinite scroll on activity feed — fails for reference lookup (users scroll to find a specific expense); paginated "Load more" with clear position indicator is correct for expense history

### Architecture Approach

The overhaul touches three systems without touching any data or business logic. All services, repositories, providers, financial calculations, and testing infrastructure are explicitly out of scope and untouched. The three systems are: (1) design token layer replacing static `AppColors` with ThemeExtension-based two-layer system, (2) navigation flattening via GoRouter subroutes for event-level screens and progressive Navigator.push to context.push migration, (3) component library migration off direct AppColors references to theme context.

**Major components:**

1. **Design Token Layer** (`lib/core/theme/`) — `app_tokens.dart` with raw primitive palette values (no Flutter dependencies), `extensions/app_color_scheme.dart` as semantic ThemeExtension for all widgets to read, `extensions/app_spacing.dart` as spacing scale ThemeExtension. The structural rule: widgets reference semantic tokens (`colors.brandPrimary`), never raw hex values. The `AppColors` public API stays identical throughout the entire migration — only the palette values behind it change. 63 files import `AppColors`; they must all continue to compile throughout.

2. **Navigation Layer** (`lib/core/router/app_router.dart`) — Additive GoRouter subroutes for `/group/:groupId/event/:eventId` and its module sub-routes (ledger, gear, logistics, vault, memories). Existing `Navigator.push` calls migrated progressively to `context.push()` across 7 files with approximately 22 imperative push calls. No `StatefulShellRoute` or persistent bottom tab bar — the data model is a single hierarchy, not parallel top-level sections. Navigation flattening is achieved through content surfacing, not structural navigation changes.

3. **Component Library** (`lib/shared/widgets/` + 4 new dashboard widgets) — 8 existing shared widgets get one migration pass each (replace `AppColors.*` with `AppColorScheme.of(context).*`). `ModuleHeader` specifically gets the `useDarkTheme` boolean removed — replaced by semantic token `colors.headerGradient`. 4 new widgets added: `hero_balance_card.dart`, `balance_pill.dart`, `dashboard_section_header.dart`, `event_timeline_tile.dart`.

**Build order is strictly outside-in:** design tokens → splash/onboarding (zero visual test coverage) → home dashboard → group detail → event hub → module screens. Module screens (Ledger, Gear, Logistics, Vault, Memories) are redesigned last because they have the highest test density and the smallest first-impression impact.

**Key architectural decision against bottom nav:** ARCHITECTURE.md explicitly flags adding a persistent bottom nav with StatefulShellRoute as an anti-pattern for this app. The single-hierarchy data model (Group → Event → Module) does not map to parallel top-level tabs. Adding StatefulShellRoute would require significant routing overhaul, new animation coordination logic, and would confuse users who work within one event at a time rather than context-switching between sections.

### Critical Pitfalls

1. **257 `find.text()` calls cascade-fail on any label change** — Add semantic `Key` identifiers to all interactive widgets and structural landmarks before touching any screen. Convert structural test assertions to `find.byKey()` while keeping `find.text()` only for content correctness tests (not structural navigation). Do this in a dedicated Phase 1 before any visual changes. Without it, renaming a single tab label causes 10+ failures across unrelated test files.

2. **895 `AppColors.*` references break on palette swap** — Introduce a two-layer system: `AppPalette` (raw color values) and keep `AppColors` as semantic aliases delegating to `AppPalette`. Public `AppColors` API stays identical. All 895 references compile throughout. The palette values behind them change in one place. Never do a mass search-and-replace across 895 files; any PR touching more than 50 files just to change colors is the wrong approach.

3. **Earthy palette fails WCAG AA contrast (~2.8:1 on body text)** — Validate every text-on-background combination through a WCAG contrast checker before writing any screen code. Minimum requirements: 4.5:1 for body text (normal size), 3:1 for large text (24px+) and icons. Workable solution: use dark brown (`#2C1A0E`) for body text on sand backgrounds — achieves 8:1+ while remaining warm. Reserve terracotta for large display text and interactive elements (where 3:1 suffices), not body copy.

4. **Stitch output uses inline hardcoded values, not tokens** — Treat all Stitch Flutter export as layout reference only, never copypaste. Before generating in Stitch: export AppColors/AppPalette as Stitch design system tokens and import them into the Stitch project first. After generation: replace any residual `Color(0xFF...)` or magic `fontSize:` values with token references before committing. Add a CI lint step that fails on any `Color(0xFF` outside `app_theme.dart`.

5. **Dashboard `SingleChildScrollView > Column` renders all widgets eagerly** — Use `CustomScrollView` with `SliverList.builder` for the dashboard body from the start, not as a fix after jank is observed. Group cards that each watch a Firestore provider must be separate `ConsumerWidget` instances in the lazy builder. Measure with DevTools Performance view on a physical mid-range Android device (Snapdragon 665 class) before declaring performance acceptable. No frame should exceed 16ms during scroll.

---

## Implications for Roadmap

The phase structure is dictated by two hard constraints: (1) the token layer is a prerequisite for all screen work, and (2) the test suite must stay green throughout — requiring test hardening before visual changes begin. These constraints make Phases 1 and 2 non-negotiable. After that, the outside-in screen redesign order follows directly from ARCHITECTURE.md's build order recommendation.

### Phase 1: Test Hardening
**Rationale:** 257 `find.text()` calls will cascade-fail on any label rename. This is not optional prep work — it gates the entire overhaul. Without it, every subsequent phase creates unbounded test debugging that compounds across migrations.
**Delivers:** Semantic `Key` identifiers on all interactive widgets and structural landmarks across the existing test suite. Structural test assertions converted from `find.text()` to `find.byKey()`. Existing behavior tests (logic, services, unit tests) unaffected.
**Addresses:** Pitfall 1 (find.text cascade failures). Sets up all subsequent phases to work safely.
**Avoids:** Mid-milestone test cascade debt that accumulates across screen migrations and becomes impossible to bisect by regression source.

### Phase 2: Design Token System
**Rationale:** The token layer is the multiplier. Without it, every screen change is a debt-creation event. `AppColorScheme` ThemeExtension must exist before any screen is redesigned so that migrations write to tokens rather than hardcoded values. This phase also includes mandatory WCAG contrast validation — no screen code until every text/background combination is verified.
**Delivers:** `app_tokens.dart` with warm earthy palette constants (terracotta, sand, olive, charcoal, warmWhite). `AppColorScheme` and `AppSpacing` ThemeExtension classes. Updated `AppTheme.lightTheme` with warm earthy ColorScheme via `ColorScheme.fromSeed(seedColor: terracotta)`. WCAG contrast validation for every text/background combination. Public `AppColors` API preserved and unchanged.
**Uses:** Flutter ThemeExtension (built-in), ColorScheme.fromSeed (built-in). Zero new packages for this phase.
**Avoids:** Pitfall 2 (895 AppColors references breaking), Pitfall 3 (WCAG contrast failure discovered after implementation — the recovery cost is HIGH). Visual review checkpoint: `AppTheme.lightTheme` update changes global appearance; plan a visual inspection pass before proceeding.

### Phase 3: Stitch Workflow and Design Reference
**Rationale:** Stitch is the design specification source, not a code source. Establishing the workflow (token import into Stitch, code-as-reference protocol, CI lint rule) before generating any production screens prevents inline hardcoded value contamination from occurring at all.
**Delivers:** Stitch project with AppPalette tokens imported. Screen mockups for Home, GroupDetail, EventCommandCenter as visual specifications. CI lint step catching any `Color(0xFF` outside `app_theme.dart`. Post-generation checklist documented in CLAUDE.md. Palette hex values finalized from Stitch output (used to update AppTokens if needed from Phase 2 approximations).
**Avoids:** Pitfall 4 (Stitch inline values in production screens diverging silently from the token system).

### Phase 4: Animation Library and Loading States
**Rationale:** Animation components with correct lifecycle must be built as shared components before any screen uses them. Building them per-screen leads to `AnimationController` leaks accumulating silently. Skeleton screens are high-value, independent of visual redesign, and quick to build — highest ROI relative to effort in the overhaul.
**Delivers:** `lib/shared/animations/` with pre-tested micro-interaction components (tap bounce, fade in, slide up) with correct `SingleTickerProviderStateMixin`, `initState` initialization, and `dispose()`. Skeleton loader variants: `SkeletonLoader.dashboardHero()`, `SkeletonLoader.eventCard()`, `SkeletonLoader.groupList()` (extending existing shimmer-based SkeletonLoader). `skeletonizer` added for full-layout dashboard skeleton.
**Uses:** `flutter_animate ^4.5.2`, `skeletonizer ^2.1.3`, `shimmer ^3.0.0` (kept alongside skeletonizer for simple loading bars).
**Avoids:** Pitfall 5 (AnimationController leaks in new micro-interaction widgets — pre-built components prevent per-screen reimplementation errors).

### Phase 5: Home Dashboard Redesign
**Rationale:** Home is the highest first-impression impact screen and has only 1 test file. Redesigning it after token and animation infrastructure is in place delivers maximum value with manageable test risk.
**Delivers:** Single-scroll dashboard with: balance hero widget (net cross-group balance, color-coded green/red), rich group cards with inline balance pills and member avatar row using initials (no photos needed), quick-action tray (Add Expense, Settle Up, Invite, Activity in one tap), recent activity strip (last 5 items). `CustomScrollView` with `SliverList.builder` from the start, not `SingleChildScrollView > Column`.
**Uses:** `hero_balance_card.dart` (new), `balance_pill.dart` (new), `dashboard_section_header.dart` (new), `AppColorScheme` tokens, `haptic_feedback`, `flutter_animate` stagger animations (capped at 8 items per ARCHITECTURE.md performance rules).
**Implements:** Target state for HomeScreen from ARCHITECTURE.md.
**Avoids:** Pitfall 6 (dashboard eager render) — SliverList from the start. Requires DevTools performance validation on physical mid-range Android before phase is declared done.

### Phase 6: Navigation Restructuring
**Rationale:** Navigation changes must precede group/event screen redesigns. Redesigning those screens with old Navigator.push routing and then restructuring navigation would require touching them twice. Mapping all 22 Navigator.push calls explicitly before writing any routing code is mandatory.
**Delivers:** GoRouter subroutes for `/group/:groupId/event/:eventId` and module sub-routes (ledger, gear, logistics, vault, memories). 22 `Navigator.push`/`AppPageRoute` calls migrated to `context.push()` across 7 files. Updated CLAUDE.md navigation flow section (atomic with code change). Full navigation graph smoke test verifying hardware back button at every new screen depth.
**Avoids:** Pitfall 8 (Navigator.push + GoRouter inconsistency orphaning back-navigation). Documentation update is mandatory and must happen in the same commit as the routing code change.

### Phase 7: Group Detail and Event Hub Redesign
**Rationale:** GroupDetailScreen has 3 test files (highest risk among redesign screens) and is the gateway to all event content. EventCommandCenter redesign must happen in the same phase because navigation restructuring connects them directly.
**Delivers:** GroupDetailScreen with event cards showing inline financial summary and type-specific color accents, member avatar row, past/upcoming visual distinction (muted vs. full color). EventCommandCenter with earthy palette re-skin. `event_timeline_tile.dart` (new shared widget). Token migration for `GroupBalanceHero`, `EventModuleList`, `EventCard`, `EventSpendingHero`. `animations` package (ContainerTransform on group card → detail expansion).
**Uses:** `AppColorScheme` tokens, `lottie`/`flutter_svg` for empty states (Lottie for animated empty states, SVG from unDraw for static versions), `animations ^2.1.2`.
**Implements:** Phases D and E from ARCHITECTURE.md build order.
**Avoids:** Pitfall 7 (old/new screens coexisting without protocol) — compile-time flag (`bool.fromEnvironment('NEW_UI', defaultValue: false)`) must be in place before this phase begins; old tests pass without setting the flag.

### Phase 8: Module Screens Redesign
**Rationale:** Module screens (Ledger, Gear, Logistics, Vault, Memories, Activity) have the highest test density but the smallest first-impression impact. Redesigning them last means all infrastructure is proven before touching the most complex widget trees. LedgerScreen has 15 widget files — the largest module — and goes last within this phase.
**Delivers:** Token migration and visual polish for all 6 module screens. Card-style expense rows, color-coded balance displays, skeleton loading on all data-fetching screens (using skeletonizer for full-layout screens), context-specific illustrated empty states with CTAs for all empty scenarios (home/groups, events, expenses, gear, activity, members).
**Uses:** All packages from previous phases. `flutter_svg ^2.2.4` for SVG illustrations from unDraw (earthy color palette injected into SVGs before committing to assets). `smooth_page_indicator ^2.0.1` if any module introduces a carousel.
**Implements:** Phase F from ARCHITECTURE.md build order.

### Phase 9: Polish Pass and Token Cleanup
**Rationale:** Micro-interactions, haptic feedback, spring physics, grain/texture overlays, and animated balance counters are high-value but fully additive. Doing them last means they are added to finalized widget trees without rework risk. Token cleanup (`AppColors` deletion, dark theme support removal from `AppTheme`) happens here once all screens are confirmed migrated with zero remaining `AppColors.*` references.
**Delivers:** Haptic feedback on all primary write actions (expense add, settlement record, group join). Animated balance counter on update via `TweenAnimationBuilder`. Grain/texture overlay on home background and card surfaces via `CustomPaint` semi-transparent PNG. Soft gradient treatment on group and event cards via `LinearGradient`. Spring physics on card presses via `SpringDescription`. Swipe-to-settle gesture on balance rows via `Dismissible`. `AppColors` class deleted. Dark theme code path removed from `AppTheme`. Compile-time feature flags cleaned up.
**Uses:** `haptic_feedback ^0.6.4+3`, `flutter_animate` (spring physics), `CustomPaint`.
**Avoids:** Remaining technical debt from Pitfall 2 (final grep confirms zero `AppColors.*` remaining).

### Phase Ordering Rationale

- **Phases 1 and 2 are non-negotiable prerequisites.** Test hardening and token system are not optional prep — they are structural foundations. Skipping either and proceeding to screen redesigns creates a debt spiral that compounds with each subsequent phase and eventually requires a rewrite of already-redesigned screens.
- **Phases 3 and 4 build shared infrastructure before it is needed.** Stitch workflow and animation library are created before the first screen that uses them, preventing the per-screen implementation errors they are designed to avoid.
- **Home (Phase 5) before navigation (Phase 6)** because navigation restructuring requires knowing what the destination screens look like, and Home does not depend on GoRouter subroutes to be redesigned.
- **Navigation (Phase 6) before group/event screens (Phase 7)** because redesigning GroupDetailScreen and EventCommandCenter with old Navigator.push routing and then restructuring later would require a second pass over the same files.
- **Module screens (Phase 8) last** — highest test density, lowest first-impression impact, most complex widget trees. All infrastructure is proven before the most risk-bearing screen work begins.
- **Polish pass (Phase 9) last** — micro-interactions and texture are additive and independent. Adding them to finalized widget trees avoids rework. Token cleanup requires all screens to be migrated first.

### Research Flags

Phases likely needing deeper research during planning:
- **Phase 4 (Animation Library):** The `lib/shared/animations/` shared component pattern is recommended but not yet established in this codebase. Research needed on which animation components to pre-build vs. implement inline per screen. Rive vs. Lottie decision for empty states needs a prototype evaluation — FEATURES.md and STACK.md disagree on the right tool (FEATURES.md: Rive for interactive state machines; STACK.md: Lottie for simplicity).
- **Phase 6 (Navigation Restructuring):** 22 Navigator.push calls need explicit mapping before implementation begins. GoRouter `parentNavigatorKey` behavior for full-screen routes within shell routes has known edge cases. This phase needs a detailed route map as a planning artifact — list every screen, its current routing method, and its target routing method — before any code is written.
- **Phase 8 (Module Screens):** LedgerScreen has 15 widget files and is the largest module in the codebase. Its redesign may surface widget tree complexities not visible from high-level research. Consider a sub-planning pass for Ledger specifically before Phase 8 begins.

Phases with standard patterns (can skip research-phase):
- **Phase 1 (Test Hardening):** Entirely mechanical — add Keys to widgets, update test assertions to find.byKey. Well-understood Flutter testing pattern, zero ambiguity.
- **Phase 2 (Design Token System):** ThemeExtension is official Flutter API, fully documented at api.flutter.dev. Implementation is mechanical once palette hex values are finalized.
- **Phase 5 (Home Dashboard):** SliverList.builder + CustomScrollView + Riverpod StreamProvider/ConsumerWidget per list item is an established Flutter pattern. The existing codebase already uses this in several screens.
- **Phase 9 (Polish Pass):** All packages are in place. Micro-interactions are additive one-liners per action. Token cleanup is a mechanical grep-and-delete.

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | All 7 new package versions verified on pub.dev March 2026. All existing packages confirmed compatible with new additions. "What NOT to add" rationale is clear and well-sourced. One MEDIUM item: Stitch token import capability is confirmed from a third-party source, not official Google documentation. |
| Features | HIGH (table stakes) / MEDIUM (differentiators) | Table stakes — skeleton screens, illustrated empty states, color-coded finance, balance on home — are backed by NN/G research, Eleken UX guides, and multi-app competitive analysis. Differentiators — earthy palette, grain overlays, bento grid — are validated as 2026 design trends by Creative Bloq and Envato, but trends are inherently subjective. |
| Architecture | HIGH (token system, navigation) / MEDIUM (Stitch workflow) | ThemeExtension two-layer token pattern is official Flutter API from api.flutter.dev. GoRouter subroute pattern with parentNavigatorKey is well-established. The Stitch-to-Flutter token import workflow is real (confirmed multiple sources, March 2026) but early-stage — "manual extraction is the current workflow" caveat confirmed. |
| Pitfalls | HIGH | The two most critical pitfall metrics (257 find.text calls, 895 AppColors references) are measured directly from the actual codebase source files, not inferred. WCAG contrast math is deterministic. AnimationController leak pattern and SingleChildScrollView eager render pitfall are confirmed in Flutter official docs and community sources. |

**Overall confidence:** HIGH for the approach and phase structure. The risks are specific, well-understood, and their mitigations are actionable. No phase depends on novel or unproven techniques.

### Gaps to Address

- **WCAG contrast validation with final hex values:** Research gives approximate palette values (terracotta ~`#CC6B49`, sand ~`#F2E8D6`, olive ~`#7A8C5E`). Stitch may generate slightly different hex values when the palette is finalized. Contrast validation in Phase 2 must be performed against the finalized Stitch-sourced values, not the approximate research values. Do not write Phase 2 screen code before running every text/background combination through a contrast checker (WCAG AA: 4.5:1 for body, 3:1 for large text).

- **Stitch token import capability:** PITFALLS.md rates this LOW confidence (sourced from tech-insider.org, not official Google documentation). The Phase 3 plan assumes Stitch can import existing design tokens. If this does not work, the fallback is manual token extraction from Stitch's visual output — workable but more tedious. Validate Stitch token import capability as the first action in Phase 3 before planning the full workflow.

- **Rive vs. Lottie decision:** FEATURES.md recommends Rive (60fps, 2KB, interactive state machines) over Lottie (17fps, 24KB). STACK.md recommends Lottie (simpler integration, appropriate for one-shot/looping animations). Resolution for now: start with Lottie in Phase 4 (simpler, static-first, and the FEATURES.md MVP definition explicitly defers Rive). Add Rive only if interactive animation state machines are needed for the onboarding flow. Revisit in Phase 7 when empty states are being built.

- **Physical device performance baseline:** Pitfall 6 requires testing on a "mid-range Android device (Snapdragon 665)" but no specific test device is identified in the codebase. Establish the target physical device or emulator configuration before Phase 5 begins, so performance validation has a consistent benchmark.

- **`ModuleHeader` `useDarkTheme` test coverage:** ARCHITECTURE.md notes that removing the `useDarkTheme` boolean from `ModuleHeader` may break tests that check for the dark header variant. Audit these tests before Phase 7 and refactor them to use semantic token assertions rather than checking for specific gradient colors, as part of Phase 1 (test hardening) or Phase 7 planning.

---

## Sources

### Primary (HIGH confidence)
- Flutter official docs: ThemeExtension API, ColorScheme.fromSeed, NavigationBar, SliverList, AnimationController — design token architecture, animation lifecycle, scroll performance
- W3C WCAG 2.1 Contrast Minimum specification — 4.5:1 for body text, 3:1 for large text and icons; deterministic accessibility requirements
- pub.dev package pages for all 7 recommended packages — versions confirmed March 2026: animations 2.1.2, lottie 3.3.2, flutter_animate 4.5.2, flutter_svg 2.2.4, skeletonizer 2.1.3, haptic_feedback 0.6.4+3, smooth_page_indicator 2.0.1, material_symbols_icons 4.2906.0
- Codebase direct analysis — 257 `find.text()` calls, 895 `AppColors.*` references, 22 `Navigator.push` calls measured from actual source and test files

### Secondary (MEDIUM confidence)
- NN/G: Skeleton Screens 101 — "500ms skeleton feels fast; 500ms spinner feels slow"; skeleton vs. spinner perception authority
- Eleken: Empty State UX best practices — illustrated empty states, single CTA rule, context-specific copy standard
- LeanCode: Building a Design System in Flutter — two-level atomic design for Flutter scale (tokens, atoms, organisms, screens)
- codewithandrea.com: GoRouter StatefulShellRoute nested navigation — parentNavigatorKey patterns and shell route state preservation
- DEV Community: Stitch + Flutter workflow 2026 — "production-adjacent but not production-ready" caveat for Stitch code export, confirmed from multiple sources
- Callstack: Lottie vs. Rive — Rive 60fps vs. Lottie 17fps, 2KB vs. 24KB performance metrics
- Envato: Mobile app color scheme trends 2026 — earthy warm neutrals, bento grid layouts, Soft Gradients 2.0 trend validation
- Creative Bloq: Texture warmth 2026 graphic design trends — "tactile rebellion" against flat sterility, humanized digital interfaces
- Flutter Performance Best Practices (official) — RepaintBoundary correct usage, SliverList over Column, animation performance rules
- Eleken, ProCreator, DesignStudioUX: Multiple UX sources confirming bottom navigation (4-5 tabs), 2-tap depth goal, skeleton loading adoption in 2025-2026 mobile apps

### Tertiary (LOW confidence)
- tech-insider.org: Google Stitch design token import capability (March 2026 update) — needs validation in Phase 3; not from official Google documentation
- Third-party Stitch Flutter code generation analysis — "production-adjacent but not production-ready" caveat; consistent with DEV Community source

---
*Research completed: 2026-03-28*
*Ready for roadmap: yes*
