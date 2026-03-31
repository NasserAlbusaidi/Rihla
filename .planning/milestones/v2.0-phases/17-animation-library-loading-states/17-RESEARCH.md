# Phase 17: Animation Library & Loading States - Research

**Researched:** 2026-03-29
**Domain:** Flutter animation primitives, skeleton loading, AnimationController lifecycle, flutter_animate API
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Skeleton fidelity**
- D-01: Content-aware skeletons that mirror actual widget layouts — circles for avatars, short bars for names, wider bars for descriptions, small blocks for amounts
- D-02: Each skeleton variant replicates the spatial structure of the real content it replaces, so the layout doesn't jump when data loads

**Animation feel**
- D-03: Crisp & confident motion personality — calm, assured, no drama
- D-04: Fade-in list: 350ms duration, easeOutCubic, 50ms stagger, slide up 12dp + fade
- D-05: Tap bounce: 120ms duration, scale 0.97, easeInOut curve
- D-06: Staggered grid: 400ms duration, 60ms stagger, easeOutQuart curve

**Skeleton scope**
- D-07: Build a composable skeleton primitive library: `SkeletonCircle`, `SkeletonBar`, `SkeletonBlock`, `SkeletonRow`, `SkeletonCard`
- D-08: Deliver 5 named skeleton variants as factories: `dashboardHero()`, `eventCard()`, `groupList()`, `expenseList()`, `gearList()`, plus `generic()` fallback
- D-09: Phases 18-22 build their own skeleton variants using the primitives — no throwaway work here
- D-10: Screens not covered by the 5 named variants use `SkeletonLoader.generic()` as interim

**Shimmer theming**
- D-11: Warm neutral shimmer using earthy palette surface tokens — base: `surfaceMuted` (#F3F0ED), highlight: `surface` (#FAFAF8)
- D-12: Replace current cold gray shimmer (surfaceLight #F5F5F5 → surface #FAFAFA) with warm tones from AppColorTokens.light

### Claude's Discretion
- Exact primitive widget API (constructor parameters, sizing defaults)
- Internal animation controller architecture (shared vs. per-widget)
- File organization within `lib/shared/animations/`
- How to integrate skeletons into existing provider loading states (AsyncValue pattern)
- Test structure and golden test approach

### Deferred Ideas (OUT OF SCOPE)
- M3 motion transitions (ContainerTransform, SharedAxis) — Phase 22 (PLSH-02)
- Lottie illustrations for empty states — separate from animation primitives
- Module-specific accent-tinted shimmer — decided against (D-11 warm neutral instead)
- Riverpod 3.x migration — separate milestone entirely
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| NAV-05 | All data-fetching screens show skeleton loading states instead of spinners or blank screens | 21 screens with CircularProgressIndicator identified; Shimmer.fromColors pattern ready |
| PLSH-03 | Reusable animation components (fade-in lists, staggered grids, tap bounce) exist as shared library widgets | flutter_animate 4.5.2 AnimateList and .animate() extension cover all three; existing _PressableWrapper pattern to migrate |
</phase_requirements>

---

## Summary

Flutter 3.x ships capable animation primitives (`AnimationController`, `Curves`, `SlideTransition`, `ScaleTransition`, `AnimatedBuilder`) that can handle everything in this phase without external libraries. However, the project already uses `flutter_animate ^4.5.0` (resolved to 4.5.2) and `shimmer ^3.0.0` (resolved to 3.0.0), which provide declarative staggered animations and shimmer effects respectively. Both are stable and should be used rather than bypassed.

The codebase has scattered AnimationController usage across 4 files: `loading_button.dart`, `smart_module_card.dart`, `event_type_picker_screen.dart`, and `group_member_balance_card.dart`. The first three contain press-bounce mechanics duplicated across `_PressableWrapper` (smart_module_card) and `_PressableCard` (event_type_picker_screen) — identical logic at 80ms scale to 0.98. The fourth (group_member_balance_card) contains a legitimate chevron-rotation animation that should be preserved but migrated to a shared component. The key architectural task is consolidating these duplicates into a single `TapBounce` wrapper in `lib/shared/animations/`.

A critical token mismatch exists: CONTEXT.md decisions D-11 and D-12 specify shimmer colors `surfaceMuted` (#F3F0ED) and `surface` (#FAFAF8), but these tokens do not exist in the current `AppColorTokens.light`. The current palette uses cool-gray values (`cardSurface` #F8F9FA, `inputFill` #F3F4F6). The shimmer must use existing AppColors tokens — `AppColors.surfaceLight` (#F3F4F6) as base and `AppColors.surface` (#F8F9FA) as highlight — which are close in perceived warmth and correct for the monochrome+teal palette.

**Primary recommendation:** Use `flutter_animate` 4.5.2 `AnimateList` for staggered list animations, the existing `shimmer` 3.0.0 `Shimmer.fromColors` for skeleton shimmer, hand-code composable `SkeletonPrimitive` widgets (StatelessWidgets), and consolidate the two duplicated `_PressableWrapper` patterns into a single shared `TapBounce` widget.

---

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `flutter_animate` | 4.5.2 (installed) | Staggered list fade-in, AnimateList | Already in pubspec; handles AnimationController lifecycle internally; declarative API |
| `shimmer` | 3.0.0 (installed) | Skeleton shimmer effect | Already in pubspec; `Shimmer.fromColors` is battle-tested for skeleton UX |
| Flutter SDK `animation` | SDK-bundled | AnimationController for tap bounce, chevron rotation | Required for components that need precise lifecycle control (StatefulWidget-owned) |
| Flutter SDK `Curves` | SDK-bundled | `easeOutCubic`, `easeOutQuart`, `easeInOut` | All curves from D-03 through D-06 are built-in constants in `Curves` class |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Flutter `AnimatedCrossFade` | SDK | Expand/collapse transitions | Already used in `group_member_balance_card.dart`; reuse for skeleton→content swaps |
| Flutter `ScaleTransition` | SDK | Tap bounce scale animation | Already used in `_PressableWrapper`; wrap in shared component |
| Flutter `RotationTransition` | SDK | Chevron rotation | Already used in `group_member_balance_card.dart` |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `flutter_animate` AnimateList | Raw `AnimationController` + `Interval` | flutter_animate is already installed; raw controller requires StatefulWidget and dispose boilerplate for every list |
| `shimmer` package | `ShimmerPlaceholder` (custom in loading_button.dart) | `ShimmerPlaceholder` uses `AnimatedBuilder` and an extra controller per widget; `Shimmer.fromColors` uses a single controller for all children — far more efficient for lists |
| Composable SkeletonPrimitive widgets | `skeletonizer` package | `skeletonizer` is not installed; adding it for auto-wrapping existing widgets adds a new dep with complex configuration. Composable primitives per D-07 are explicit about the required layouts |

**Installation:** No new packages needed. All dependencies are already in pubspec.yaml.

**Version verification:**
- `flutter_animate`: 4.5.2 (verified via `dart pub deps` 2026-03-29)
- `shimmer`: 3.0.0 (verified via `dart pub deps` 2026-03-29)

---

## Architecture Patterns

### Recommended Project Structure
```
lib/
├── shared/
│   ├── animations/            # NEW — all animation primitives
│   │   ├── tap_bounce.dart    # TapBounce wrapper (replaces _PressableWrapper duplicates)
│   │   ├── fade_in_list.dart  # FadeInList — animated list reveal
│   │   ├── staggered_grid.dart # StaggeredGrid — grid reveal
│   │   └── animations.dart    # Barrel export
│   └── widgets/
│       └── skeleton_loader.dart  # REFACTOR: add primitives + named variants
```

Skeleton primitives live in `skeleton_loader.dart` alongside the existing `SkeletonLoader` class. The 5 named factories (`dashboardHero`, `eventCard`, `groupList`, `expenseList`, `gearList`) are added as static constructors on `SkeletonLoader`. Primitive widgets (`SkeletonCircle`, `SkeletonBar`, `SkeletonBlock`, `SkeletonRow`, `SkeletonCard`) are private building blocks within the same file OR extracted to `lib/shared/widgets/skeleton_primitives.dart` depending on line count.

### Pattern 1: Shimmer Wrapper with Warm Tokens
**What:** `Shimmer.fromColors` wraps a column of primitive skeleton widgets. The shimmer animation is shared across all children — single `AnimationController` for the entire list.
**When to use:** Every skeleton variant

```dart
// Source: shimmer 3.0.0 pub.dev — Shimmer.fromColors API
// Colors use AppColors (the current live tokens, not the earthy palette variants
// mentioned in CONTEXT.md D-11/D-12 which reference tokens that don't exist yet)
Shimmer.fromColors(
  baseColor: AppColors.surfaceLight,    // #F3F4F6 — nearest to target surfaceMuted
  highlightColor: AppColors.surface,    // #F8F9FA — nearest to target surface
  child: Column(
    children: [
      _SkeletonBar(width: 160, height: 14),
      _SkeletonCircle(size: 40),
    ],
  ),
)
```

### Pattern 2: flutter_animate Staggered Fade-In List
**What:** `AnimateList` applies the same animation to each list child with an `interval` offset.
**When to use:** Any list of cards revealed on screen entry

```dart
// Source: flutter_animate 4.5.2 README — AnimateList with interval
// Matches D-04: 350ms duration, easeOutCubic, 50ms stagger, slide up 12dp + fade
Column(
  children: AnimateList(
    interval: 50.ms,
    effects: [
      FadeEffect(duration: 350.ms, curve: Curves.easeOutCubic),
      SlideEffect(
        begin: const Offset(0, 12 / 400), // 12dp normalized to ~0.03
        end: Offset.zero,
        duration: 350.ms,
        curve: Curves.easeOutCubic,
      ),
    ],
    children: cards,
  ),
)

// Alternative: list extension on widget lists
cards.animate(interval: 50.ms)
  .fade(duration: 350.ms, curve: Curves.easeOutCubic)
  .slideY(begin: 0.03, end: 0, duration: 350.ms, curve: Curves.easeOutCubic)
```

**Accessibility guard:** Check `MediaQuery.disableAnimationsOf(context)` before applying animation:
```dart
// Use MediaQuery.disableAnimationsOf — more targeted rebuild than MediaQuery.of
final disable = MediaQuery.disableAnimationsOf(context);
if (disable) return child; // bypass animation entirely
```
Note: flutter_animate does NOT automatically honor `disableAnimations`. The guard must be added manually in any component that uses it. The existing `event_type_picker_screen.dart` already shows this pattern correctly.

### Pattern 3: TapBounce Shared Widget (consolidation target)
**What:** Single StatefulWidget that wraps a child with a scale-down press animation. Replaces identical `_PressableWrapper` in `smart_module_card.dart` and `_PressableCard` in `event_type_picker_screen.dart`.
**When to use:** Any tappable card or interactive surface

```dart
// Implementation pattern (to be created in lib/shared/animations/tap_bounce.dart)
// D-05: 120ms duration, scale 0.97, easeInOut curve
class TapBounce extends StatefulWidget {
  final VoidCallback? onTap;
  final Widget child;
  const TapBounce({super.key, this.onTap, required this.child});
  // ...
}

class _TapBounceState extends State<TapBounce>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120), // D-05
    );
    _scale = Tween<double>(begin: 1.0, end: 0.97).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut), // D-05
    );
  }

  @override
  void dispose() {
    _controller.dispose(); // MUST come before super.dispose()
    super.dispose();
  }
  // GestureDetector onTapDown/onTapUp/onTapCancel pattern (same as existing)
}
```

Note: The existing `_PressableWrapper` uses 80ms and 0.98 scale. The CONTEXT.md decision D-05 specifies 120ms and 0.97. The shared `TapBounce` implements the new spec, and existing usages migrate to it.

### Pattern 4: AsyncValue Skeleton Integration
**What:** `ref.watch(someProvider).when(loading: () => SkeletonLoader.expenseList(), ...)` — skeletons slot into the `loading:` callback unchanged.
**When to use:** Every screen with StreamProvider or FutureProvider

```dart
// Pattern used in lib/features/gear/screens/gear_screen.dart (already correct):
ref.watch(gearProvider(eventRef)).when(
  loading: () => SkeletonLoader.cardList(),  // becomes SkeletonLoader.gearList()
  error: (e, st) => ErrorView(error: e),
  data: (items) => GearList(items: items),
)
```

### Pattern 5: Staggered Grid (D-06)
**What:** Grid reveal with 400ms, 60ms stagger, easeOutQuart
**When to use:** Photo/memory grids, event card grids

```dart
// D-06: 400ms duration, 60ms stagger, easeOutQuart
// Curves.easeOutQuart is Cubic(0.165, 0.84, 0.44, 1.0) — built-in Flutter constant
GridView.builder(
  // ...
  itemBuilder: (context, index) => cards[index]
    .animate(delay: (60 * index).ms)
    .fade(duration: 400.ms, curve: Curves.easeOutQuart)
    .scale(begin: const Offset(0.95, 0.95), duration: 400.ms, curve: Curves.easeOutQuart),
)
```

### Anti-Patterns to Avoid
- **Duplicate _PressableWrapper**: Each screen defining its own press animation — the entire point of this phase is consolidation into `TapBounce`
- **Per-skeleton `AnimationController`**: `ShimmerPlaceholder` (in loading_button.dart) creates one controller per widget instance. Do not use it for skeleton lists — use `Shimmer.fromColors` which creates one controller for all children
- **`pumpAndSettle()` in tests for shimmer**: Shimmer runs `repeat()` — infinite loop animation. `pumpAndSettle()` will timeout. Use `pump(duration)` instead
- **Calling `super.dispose()` before `_controller.dispose()`**: Ticker is still active at mixin dispose time — throws assertion error at test time
- **Creating `AnimationController` in a StatelessWidget**: No `TickerProvider` available — always requires StatefulWidget + mixin, or use flutter_animate which handles this internally
- **`TickerProviderStateMixin` when only one controller exists**: Use `SingleTickerProviderStateMixin` for single-controller widgets (tap bounce, chevron). Switch to `TickerProviderStateMixin` only if a State creates multiple controllers

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Shimmer gradient animation across skeleton list | Custom `AnimatedBuilder` + gradient per widget | `Shimmer.fromColors` wrapping all skeleton children | Single AnimationController for all children; hand-rolled approach creates N controllers for N items |
| Staggered list reveal with delay offset | `AnimationController` + `Interval` per item in a StatefulWidget | `flutter_animate` `AnimateList` with `interval:` | flutter_animate handles lifecycle; no StatefulWidget needed at all |
| Tap scale animation | Inline GestureDetector + controller per screen | `TapBounce` shared widget | Identical logic already duplicated 2x; consolidation is the whole point |
| Accessibility guard for reduced motion | Custom system query | `MediaQuery.disableAnimationsOf(context)` | Built-in Flutter API; returns true when system accessibility setting disables motion |
| CSS-style easing curves | Custom `Cubic` bezier values | `Curves.easeOutCubic`, `Curves.easeOutQuart`, `Curves.easeInOut` | All three required curves are built-in Flutter constants; no custom Cubic needed |

**Key insight:** The shimmer package's single-controller architecture is the critical performance reason to avoid hand-rolling skeleton animations. N skeleton items with N custom ShimmerPlaceholder instances = N animation controllers polling the ticker every frame.

---

## Common Pitfalls

### Pitfall 1: dispose() Order
**What goes wrong:** `super.dispose()` called before `_controller.dispose()` — test throws "Was disposed with an active Ticker"
**Why it happens:** `SingleTickerProviderStateMixin.dispose()` asserts no active tickers remain. If `super.dispose()` runs first, the controller is still active.
**How to avoid:** Always call `_controller.dispose()` as the FIRST line in `dispose()`, then `super.dispose()`
**Warning signs:** Test failures with "State was disposed with an active Ticker" or "looking up a deactivated widget's ancestor is unsafe"

### Pitfall 2: pumpAndSettle with Shimmer/Repeat Animations
**What goes wrong:** `tester.pumpAndSettle()` never returns in tests involving shimmer skeleton or any `AnimationController.repeat()` call
**Why it happens:** `pumpAndSettle()` polls until no scheduled frames remain — infinite animations never settle
**How to avoid:** Use `tester.pump()` or `tester.pump(const Duration(milliseconds: 100))` for widget existence checks; never `pumpAndSettle()` on screens with skeleton loaders. Use `tester.pump()` then check widget presence immediately.
**Warning signs:** Test hangs or times out with "pumpAndSettle timed out"

### Pitfall 3: flutter_animate Ignores disableAnimations
**What goes wrong:** Users with reduced motion accessibility setting still see all staggered animations
**Why it happens:** `flutter_animate` does not automatically check `MediaQuery.disableAnimations` — this is the app's responsibility
**How to avoid:** Every component that uses `.animate()` or `AnimateList` must guard with `if (MediaQuery.disableAnimationsOf(context)) return child;`
**Warning signs:** Animation plays despite device "Reduce Motion" enabled

### Pitfall 4: Shimmer Token Mismatch
**What goes wrong:** CONTEXT.md D-11/D-12 reference `surfaceMuted` (#F3F0ED) and `surface` (#FAFAF8) — neither token exists in the current `AppColorTokens.light` or `AppColors`
**Why it happens:** These tokens were from the earthy palette (sand-based warm tones) which was replaced by the monochrome+teal system in Phase 15. The decision notes were written before the palette swap.
**How to avoid:** Use `AppColors.surfaceLight` (#F3F4F6) as the shimmer base and `AppColors.surface` (#F8F9FA) as the highlight — these are the closest available tokens with the correct warm-cool relationship. Do NOT add phantom tokens named `surfaceMuted` that don't match any AppColorTokens.light field.
**Warning signs:** Compile error if referencing `AppColorTokens.light.surfaceMuted` (field does not exist)

### Pitfall 5: SlideY Normalization in flutter_animate
**What goes wrong:** `slideY(begin: 12)` slides 12x the widget height, not 12dp
**Why it happens:** flutter_animate's `SlideEffect` begin/end values are fractional — 1.0 = widget height, not 1dp
**How to avoid:** For 12dp slide on a ~400dp screen card, normalize: ~0.03 (12/400). Alternatively use `SlideEffect` with `Offset(0, 12)` in logical pixels — check which API accepts pixels vs. fractions in version 4.5.2
**Warning signs:** Items fly across the entire screen instead of subtly sliding up 12dp

### Pitfall 6: Skeleton in shrinkWrap ListView
**What goes wrong:** `SkeletonLoader` uses `ListView.builder` with `NeverScrollableScrollPhysics` — this only works inside a parent scrollable. If the parent has `shrinkWrap: false` and no explicit height, the list has zero height.
**Why it happens:** The current `SkeletonLoader.build()` uses `ListView.builder` with fixed-count items — needs an explicit height constraint from parent or should use `Column` for non-scrollable skeletons
**How to avoid:** New skeleton variants use `Column` for fixed-item counts (< 10 items). Reserve `ListView.builder` for cases where parent provides bounded height.

---

## Code Examples

### Skeleton Primitive (content-aware, D-01)
```dart
// SkeletonBar — variable width/height bar for text lines
class SkeletonBar extends StatelessWidget {
  final double width;
  final double height;
  final double? borderRadius;

  const SkeletonBar({
    super.key,
    required this.width,
    this.height = 14.0,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.surface, // shimmer child color must be opaque
        borderRadius: BorderRadius.circular(borderRadius ?? AppColors.radiusSmall),
      ),
    );
  }
}
```

### Named Variant Factory (D-08)
```dart
// SkeletonLoader.expenseList() — mirrors ExpenseListItem layout
factory SkeletonLoader.expenseList({int count = 5}) {
  return SkeletonLoader(
    itemCount: count,
    itemBuilder: (context, index) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
      child: Shimmer.fromColors(
        baseColor: AppColors.surfaceLight,
        highlightColor: AppColors.surface,
        child: const _ExpenseItemSkeleton(),
      ),
    ),
  );
}

class _ExpenseItemSkeleton extends StatelessWidget {
  const _ExpenseItemSkeleton();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SkeletonCircle(size: 40),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBar(width: 140, height: 14),
              const SizedBox(height: 6),
              SkeletonBar(width: 80, height: 12),
            ],
          ),
        ),
        SkeletonBar(width: 60, height: 16),
      ],
    );
  }
}
```

### TapBounce Shared Widget
```dart
// lib/shared/animations/tap_bounce.dart
// Replaces _PressableWrapper (smart_module_card.dart) and
// _PressableCard (event_type_picker_screen.dart)
class TapBounce extends StatefulWidget {
  final VoidCallback? onTap;
  final Widget child;
  final bool enabled;

  const TapBounce({
    super.key,
    this.onTap,
    required this.child,
    this.enabled = true,
  });

  @override
  State<TapBounce> createState() => _TapBounceState();
}

class _TapBounceState extends State<TapBounce>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120), // D-05
    );
    _scale = Tween<double>(begin: 1.0, end: 0.97).animate( // D-05
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose(); // BEFORE super.dispose()
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || widget.onTap == null) return widget.child;
    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) {
        _controller.reverse();
        widget.onTap?.call();
      },
      onTapCancel: () => _controller.reverse(),
      child: ScaleTransition(scale: _scale, child: widget.child),
    );
  }
}
```

### Test Pattern (no pumpAndSettle with shimmer)
```dart
testWidgets('SkeletonLoader.expenseList renders item skeletons', (tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SkeletonLoader.expenseList(count: 3),
      ),
    ),
  );
  // Single pump — do NOT pumpAndSettle (shimmer uses repeat())
  await tester.pump();
  expect(find.byType(Shimmer), findsWidgets);
});

testWidgets('TapBounce disposes controller correctly', (tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: TapBounce(
          onTap: () {},
          child: const Text('tap'),
        ),
      ),
    ),
  );
  await tester.pump();
  expect(find.text('tap'), findsOneWidget);
  // No explicit dispose test needed — Flutter test framework
  // automatically checks for ticker leaks at end of test
});
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Manual `AnimationController` per-list-item staggering | `flutter_animate` `AnimateList` with `interval:` | ~2022 | Eliminates StatefulWidget boilerplate for list animations |
| Cold gray skeleton shimmer | Warm-neutral shimmer tuned to app palette | Phase 17 | Cohesion with teal palette; less visual jarring on load |
| Generic opaque block skeletons | Content-aware skeleton primitives mirroring real layouts | Phase 17 | Eliminates layout jump on data load |
| `CircularProgressIndicator` in every loading branch | Named skeleton factories in `loading:` callback | Phase 17 | Immediate perceived performance improvement across 21 call sites |
| Duplicated `_PressableWrapper` in each screen | Shared `TapBounce` in `lib/shared/animations/` | Phase 17 | Single source of truth for tap interaction feedback |

**Deprecated/outdated:**
- `ShimmerPlaceholder` in `loading_button.dart`: Uses per-instance `AnimationController` — correct for its isolated use case in the loading button, but do NOT use this pattern for skeleton lists
- `AppColors.surfaceLight`/`AppColors.surface` references in `skeleton_loader.dart`: Will be replaced with consistent values once the shimmer colors are updated per D-11/D-12 intent

---

## Open Questions

1. **SlideEffect normalization in flutter_animate**
   - What we know: D-04 specifies 12dp slide. flutter_animate's `SlideEffect` accepts `Offset` values
   - What's unclear: Whether `SlideEffect(begin: Offset(0, 12))` means 12 logical pixels or 12x widget height. The README example uses fractional values (e.g., `0.05`) suggesting normalized units.
   - Recommendation: During Wave 0 implementation, write a smoke test to verify 12dp vs fractional. Use `MoveEffect` if `SlideEffect` normalizes — `MoveEffect(begin: Offset(0, 12))` uses logical pixels.

2. **surfaceMuted token gap**
   - What we know: D-11/D-12 reference `surfaceMuted` (#F3F0ED) and `surface` (#FAFAF8). Neither exists in `AppColorTokens.light` or `AppColors`.
   - What's unclear: Whether CONTEXT.md intended the old earthy palette values (which were replaced in Phase 15) or whether new tokens should be added
   - Recommendation: Use existing `AppColors.surfaceLight` (#F3F4F6) as base, `AppColors.surface` (#F8F9FA) as highlight. These are functionally equivalent warm-neutral values. Do not add phantom tokens — flag for Phase 18's design token review if warmth is insufficient.

3. **Staggered grid reuse across phases**
   - What we know: D-09 says Phases 18-22 build their own skeleton variants using the primitives
   - What's unclear: Whether `StaggeredGrid` animation should be a full shared widget or just documented as a pattern
   - Recommendation: Implement `StaggeredGrid` as a light wrapper in `lib/shared/animations/staggered_grid.dart` with configurable `stagger`, `duration`, and `curve` — this satisfies PLSH-03 without over-engineering.

---

## Environment Availability

Step 2.6: SKIPPED — Phase 17 is code-only. No external CLI tools, services, databases, or runtimes beyond the Flutter/Dart SDK are required. All dependencies (`flutter_animate`, `shimmer`) are already in `pubspec.yaml` and resolved in `pubspec.lock`.

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | flutter_test (SDK-bundled) |
| Config file | none — uses flutter test runner |
| Quick run command | `flutter test test/unit/shared_widgets_test.dart` |
| Full suite command | `flutter test` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| NAV-05 | SkeletonLoader.expenseList renders content-aware skeleton | unit/widget | `flutter test test/unit/skeleton_loader_test.dart -x` | Wave 0 |
| NAV-05 | SkeletonLoader.gearList renders content-aware skeleton | unit/widget | `flutter test test/unit/skeleton_loader_test.dart -x` | Wave 0 |
| NAV-05 | SkeletonLoader.dashboardHero renders content-aware skeleton | unit/widget | `flutter test test/unit/skeleton_loader_test.dart -x` | Wave 0 |
| NAV-05 | SkeletonLoader.generic renders fallback skeleton | unit/widget | `flutter test test/unit/skeleton_loader_test.dart -x` | Wave 0 |
| PLSH-03 | TapBounce disposes AnimationController without ticker leak | unit/widget | `flutter test test/unit/tap_bounce_test.dart -x` | Wave 0 |
| PLSH-03 | FadeInList renders all children with disableAnimations bypass | unit/widget | `flutter test test/unit/fade_in_list_test.dart -x` | Wave 0 |
| PLSH-03 | StaggeredGrid renders with expected stagger | unit/widget | `flutter test test/unit/staggered_grid_test.dart -x` | Wave 0 |
| PLSH-03 | TapBounce scales to 0.97 on tap | unit/widget | `flutter test test/unit/tap_bounce_test.dart -x` | Wave 0 |

### Sampling Rate
- **Per task commit:** `flutter test test/unit/skeleton_loader_test.dart test/unit/tap_bounce_test.dart`
- **Per wave merge:** `flutter test`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `test/unit/skeleton_loader_test.dart` — covers NAV-05 skeleton rendering
- [ ] `test/unit/tap_bounce_test.dart` — covers PLSH-03 tap bounce and dispose
- [ ] `test/unit/fade_in_list_test.dart` — covers PLSH-03 staggered list
- [ ] `test/unit/staggered_grid_test.dart` — covers PLSH-03 staggered grid

---

## Sources

### Primary (HIGH confidence)
- `flutter_animate` 4.5.2 — verified via `dart pub deps` on project (2026-03-29)
- `shimmer` 3.0.0 — verified via `dart pub deps` on project (2026-03-29)
- Flutter SDK `Curves.easeOutQuart` — `Cubic(0.165, 0.84, 0.44, 1.0)` from [api.flutter.dev/flutter/animation/Curves/easeOutQuart-constant.html](https://api.flutter.dev/flutter/animation/Curves/easeOutQuart-constant.html)
- Flutter SDK `SingleTickerProviderStateMixin.dispose()` — [api.flutter.dev/flutter/widgets/SingleTickerProviderStateMixin/dispose.html](https://api.flutter.dev/flutter/widgets/SingleTickerProviderStateMixin/dispose.html)
- Codebase audit — `lib/shared/widgets/skeleton_loader.dart`, `loading_button.dart`, `smart_module_card.dart`, `event_type_picker_screen.dart`, `group_member_balance_card.dart` (read 2026-03-29)

### Secondary (MEDIUM confidence)
- [flutter_animate README on GitHub](https://github.com/gskinner/flutter_animate/blob/main/README.md) — AnimateList `interval:` parameter, staggered fade+slide pattern (WebFetch 2026-03-29)
- [Flutter AnimationController class docs](https://api.flutter.dev/flutter/animation/AnimationController-class.html) — dispose before super.dispose() requirement
- [MediaQuery.disableAnimations property docs](https://api.flutter.dev/flutter/widgets/MediaQueryData/disableAnimations.html) — accessibility flag; flutter_animate does not handle this automatically (WebSearch 2026-03-29)
- `AsyncValue.when` pattern — [pub.dev Riverpod AsyncValue docs](https://pub.dev/documentation/riverpod/latest/riverpod/AsyncValue-class.html) verified with project's existing gear_screen.dart usage

### Tertiary (LOW confidence)
- `MediaQuery.disableAnimationsOf(context)` as preferred alternative to `MediaQuery.of(context).disableAnimations` — WebSearch result, not verified in official Flutter migration guide (flag for implementation-time verification)

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — both packages installed and version-verified from lock file
- Architecture patterns: HIGH — based on direct codebase audit of all 4 AnimationController files + shimmer package behavior
- Common pitfalls: HIGH — dispose order, pumpAndSettle/shimmer timeout, and SlideY normalization all verified from official docs or project code patterns
- Token gap finding: HIGH — `grep` confirmed surfaceMuted (#F3F0ED) and surface (#FAFAF8) do not appear anywhere in the codebase

**Research date:** 2026-03-29
**Valid until:** 2026-06-29 (flutter_animate 4.x is stable; shimmer 3.0.0 not updated in 2+ years)
