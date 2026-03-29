# Phase 17: Animation Library & Loading States - Context

**Gathered:** 2026-03-29
**Status:** Ready for planning

<domain>
## Phase Boundary

Reusable animation components (fade-in list, staggered grid, tap bounce) and layout-matching skeleton loading variants as tested shared widgets. All animation primitives live in `lib/shared/animations/`. Skeleton loaders are upgraded in `lib/shared/widgets/`. No screen redesigns — this phase builds the library that Phases 18-22 consume.

</domain>

<decisions>
## Implementation Decisions

### Skeleton fidelity
- **D-01:** Content-aware skeletons that mirror actual widget layouts — circles for avatars, short bars for names, wider bars for descriptions, small blocks for amounts
- **D-02:** Each skeleton variant replicates the spatial structure of the real content it replaces, so the layout doesn't jump when data loads

### Animation feel
- **D-03:** Crisp & confident motion personality — calm, assured, no drama
- **D-04:** Fade-in list: 350ms duration, easeOutCubic, 50ms stagger, slide up 12dp + fade
- **D-05:** Tap bounce: 120ms duration, scale 0.97, easeInOut curve
- **D-06:** Staggered grid: 400ms duration, 60ms stagger, easeOutQuart curve

### Skeleton scope
- **D-07:** Build a composable skeleton primitive library: `SkeletonCircle`, `SkeletonBar`, `SkeletonBlock`, `SkeletonRow`, `SkeletonCard`
- **D-08:** Deliver 5 named skeleton variants as factories: `dashboardHero()`, `eventCard()`, `groupList()`, `expenseList()`, `gearList()`, plus `generic()` fallback
- **D-09:** Phases 18-22 build their own skeleton variants using the primitives — no throwaway work here
- **D-10:** Screens not covered by the 5 named variants use `SkeletonLoader.generic()` as interim

### Shimmer theming
- **D-11:** Warm neutral shimmer using earthy palette surface tokens — base: `surfaceMuted` (#F3F0ED), highlight: `surface` (#FAFAF8)
- **D-12:** Replace current cold gray shimmer (surfaceLight #F5F5F5 → surface #FAFAFA) with warm tones from AppColorTokens.light

### Claude's Discretion
- Exact primitive widget API (constructor parameters, sizing defaults)
- Internal animation controller architecture (shared vs. per-widget)
- File organization within `lib/shared/animations/`
- How to integrate skeletons into existing provider loading states (AsyncValue pattern)
- Test structure and golden test approach

</decisions>

<specifics>
## Specific Ideas

- Motion should match the earthy/professional palette personality — not playful or bouncy, not invisible
- Existing `ShimmerPlaceholder` in `loading_button.dart` has a good `AnimationController.dispose()` pattern — use as reference
- Existing `AppPageRoute` uses easeOutCubic at 300ms — new animations should feel like the same family
- Skeleton variants should be drop-in replacements for the current `CircularProgressIndicator` loading states — same spot in the widget tree, wrapped in the same provider loading branch

</specifics>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Existing animation/loading code
- `lib/shared/widgets/skeleton_loader.dart` — Current skeleton implementation (3 generic factories, `shimmer` package). Must be refactored, not replaced from scratch
- `lib/shared/widgets/loading_button.dart` — Contains `ShimmerPlaceholder` with proper AnimationController pattern, `LoadingButton`, `GlassCard`, `GradientContainer`
- `lib/core/utils/page_transitions.dart` — `AppPageRoute` (300ms, easeOutCubic) and `AppBottomSheetRoute` — timing reference for animation consistency

### Design tokens
- `lib/core/theme/tokens/color_tokens.dart` — `AppColorTokens.light` has `surfaceMuted` (#F3F0ED) and `surface` (#FAFAF8) for shimmer theming
- `lib/core/theme/tokens/spacing_tokens.dart` — `AppSpacingTokens.standard` for skeleton layout spacing
- `lib/core/theme/app_theme.dart` — `AppColors` constants, radii, shadows, button heights

### Requirements
- `.planning/REQUIREMENTS.md` — PLSH-03 (reusable animation components), NAV-05 (skeleton loading states)
- `.planning/ROADMAP.md` — Phase 17 success criteria and scope

### Prior phase context
- `.planning/phases/15-design-token-system/15-CONTEXT.md` — Token architecture decisions (D-10 split by concern, D-15 BuildContext extensions)
- `.planning/phases/16-stitch-workflow-design-reference/16-CONTEXT.md` — Visual design workflow, Stitch-to-Flutter pipeline

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `SkeletonLoader` (skeleton_loader.dart): Refactor to add primitive system and content-aware factories. Keep `shimmer` package dependency
- `ShimmerPlaceholder` (loading_button.dart): Good dispose pattern. Consider extracting to shared animations or keeping alongside shimmer-based approach
- `AppPageRoute` (page_transitions.dart): 300ms + easeOutCubic is the timing baseline — new animations should feel like kin

### Established Patterns
- Provider loading: `AsyncValue.when(loading: () => skeleton, error: ..., data: ...)` — skeletons slot into the `loading` branch
- Widget organization: shared widgets in `lib/shared/widgets/`, one widget per file
- Factory constructors: `SkeletonLoader.cardList()` pattern is already in use — extend with new named factories

### Integration Points
- Every screen with `StreamProvider`/`FutureProvider` that currently shows `CircularProgressIndicator` in its `loading:` callback
- `SmartModuleCard` in CommandCenter — uses `AnimationController` directly, candidate for tap bounce migration
- `GroupMemberBalanceCard`, `LogisticsScreen`, `EventTypePickerScreen` — all use `AnimationController` directly, candidates for shared animation migration

</code_context>

<deferred>
## Deferred Ideas

- M3 motion transitions (ContainerTransform, SharedAxis) — Phase 22 (PLSH-02)
- Lottie illustrations for empty states — separate from animation primitives
- Module-specific accent-tinted shimmer — considered but decided against (D-11 warm neutral instead)
- Riverpod 3.x migration — separate milestone entirely

</deferred>

---

*Phase: 17-animation-library-loading-states*
*Context gathered: 2026-03-29*
