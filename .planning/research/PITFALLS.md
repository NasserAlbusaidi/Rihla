# Pitfalls Research

**Domain:** Flutter UI/UX overhaul — design system migration, navigation restructuring, animation, Stitch-to-Flutter, accessibility, phased rollout
**Researched:** 2026-03-28
**Confidence:** HIGH (Flutter performance/testing sources verified against official docs; Stitch export limitations verified from multiple sources; accessibility requirements from W3C WCAG specification)

---

## Critical Pitfalls

Mistakes that cause rewrites, test cascade failures, or permanent UX regressions.

---

### Pitfall 1: 257 `find.text()` Calls Break When Labels Change

**What goes wrong:**

The codebase has 257 `find.text()` calls across 20+ test files and only 4 `find.byKey()` calls. Every screen label, button text, tab name, and module title is a live tripwire. When the UI redesign renames "SPENDING" to something else, changes "Ledger" to "Expenses", relabels a tab, or restructures any text widget, those tests fail immediately — not because the logic broke, but because the presentation changed. This triggers a cascade of test failures across features that have nothing to do with the changed screen.

**Why it happens:**

Widget tests were written to verify behavior by asserting visible text. This is the path of least resistance in Flutter — `find.text('Ledger')` is faster to write than assigning and threading a `Key`. The existing test suite was optimized for coverage, not UI changeability.

**How to avoid:**

Before touching any screen, add semantic `Key` identifiers to interactive widgets and structural landmarks. For module cards in CommandCenter use `Key('module_card_ledger')`, for tabs use `Key('tab_spending')`, for primary action buttons use `Key('btn_add_expense')`. Update tests to use `find.byKey()` for structural assertions while keeping `find.text()` only for content correctness tests. Do this screen-by-screen in a dedicated phase before any visual changes.

**Warning signs:**

Running `flutter test` after a single label rename causes 10+ failures across unrelated test files. Any test that asserts `find.text('SPENDING')` or `find.text('Ledger')` is a ticking bomb.

**Phase to address:**

Phase 1 (Test Hardening) — must complete before any visual changes. Key the interactive widgets and structural landmarks, rewrite structural test assertions to use keys.

---

### Pitfall 2: Replacing AppColors with New Tokens Breaks 895 Direct References

**What goes wrong:**

`AppColors.mint`, `AppColors.emerald`, `AppColors.rose`, etc. are referenced directly 895 times across lib files and also in 2 test files. Switching to a new earthy palette (terracotta, sand, olive) by renaming or replacing the `AppColors` class creates a mass compile failure. Worse: if the new token names (`AppColors.terracotta`, `AppColors.sand`) are introduced alongside the old ones with a deprecation marker, developers will use whichever is convenient — the two systems will permanently coexist and both drift.

**Why it happens:**

The existing theme is a single static class with hardcoded constants. There is no separation between "semantic tokens" (what the color means: `primary`, `danger`, `surface`) and "palette tokens" (what the color is: `#13EC92`). Because everything references the palette directly, changing the palette requires touching every callsite.

**How to avoid:**

Introduce a two-layer token system. Layer 1: `AppPalette` — raw color values (terracotta, sand, olive, etc.). Layer 2: `AppColors` — semantic aliases that delegate to `AppPalette` (e.g., `static const Color primary = AppPalette.terracotta`). Keep the `AppColors` public API identical to today. All 895 existing references continue to compile. Only the palette behind them changes. Validate with `flutter analyze` after each swap — zero errors means zero breakage.

**Warning signs:**

Any attempt to do `sed -i 's/AppColors.mint/AppColors.terracotta/g'` across 895 files. Any PR that touches more than 50 files just to change colors.

**Phase to address:**

Phase 2 (Design Token System) — introduce AppPalette abstraction layer before any palette changes. The public AppColors API must remain stable throughout the overhaul.

---

### Pitfall 3: Earthy Palette Fails WCAG AA Contrast for Body Text

**What goes wrong:**

Terracotta (~`#C85C35`) on sand (~`#F5E6C8`) yields a contrast ratio around 2.8:1 — failing WCAG AA which requires 4.5:1 for normal text. Olive green (`#6B7C5C`) on sand similarly scores approximately 2.5:1. The design looks warm and appealing in mockups but becomes unreadable in bright light on mobile screens, and fails accessibility audits. Adding white text on terracotta surfaces also fails if the terracotta is mid-range (e.g., `#E2724A` against white gives ~3.2:1 — under the 4.5:1 threshold for body text).

**Why it happens:**

Warm earthy palettes are low-contrast by nature. Terracotta, sand, and olive sit in the mid-luminance range where neither pure white nor pure black provides the required contrast without looking wrong. Designers optimizing for warmth and feel often defer the contrast check to "later" and then discover that meeting contrast requires shifting colors so far they lose the original warmth.

**How to avoid:**

Before committing any palette values, run every text-on-background combination through a WCAG contrast checker. Minimum requirements: 4.5:1 for body text (normal size), 3:1 for large text (24px+) and icons. Use the `Accessible Palette` methodology — choose colors in CIELAB or LCh color space where you can set equal luminance across a scale. A viable approach: use dark brown (`#2C1A0E`) for body text on sand/cream backgrounds — this achieves 8:1+ while remaining warm. Reserve terracotta for large display text and interactive elements (where 3:1 suffices), not body copy.

**Warning signs:**

Any mockup where body text is terracotta-colored on a sand background. Any design that uses olive green text on off-white. Any palette where the text color is a warm hue rather than a dark neutral.

**Phase to address:**

Phase 2 (Design Token System) — finalize and validate all palette combinations before implementation. Do not write widget code until every text combination is contrast-checked.

---

### Pitfall 4: Stitch-Generated Code Uses Hardcoded Values, Not Design Tokens

**What goes wrong:**

Stitch generates visually correct Flutter widgets but uses inline values: `Color(0xFFE2724A)`, `fontSize: 18`, `padding: EdgeInsets.all(16)`. Developers paste this output directly into screens without extracting to tokens. Six months later the codebase has the new token system in `AppColors` and the design tokens from Stitch as inline magic numbers scattered across new screens. The two systems diverge silently — changing a token in `AppColors` no longer affects the Stitch-generated components.

**Why it happens:**

Stitch's March 2026 update can import existing design tokens, but only if you provide them upfront as a design system import before generation. If the tokens are not imported into the Stitch project first, the export defaults to inline values. The workflow of "generate in Stitch → paste into Flutter" skips the token-binding step.

**How to avoid:**

Establish the Stitch workflow before using it: (1) Export final `AppColors` / `AppPalette` values as Stitch design system tokens, (2) Import into Stitch project so all generations reference these tokens, (3) In the generated Flutter output, find and replace any residual inline values with their token equivalents before committing. Treat Stitch output as a design reference/scaffold, not production-ready code. Designate a linting rule (or code review checklist item) that flags any hardcoded color hex or magic-number font size outside of `app_theme.dart`.

**Warning signs:**

Any generated file containing `Color(0xFF...)` directly in widget build methods. Any `fontSize:` value that isn't a reference to a text style from `AppTheme`.

**Phase to address:**

Phase 3 (Stitch Workflow Setup) — establish token import into Stitch before generating any production screens. Create a post-generation checklist.

---

### Pitfall 5: AnimationController Leaks in New Micro-Interaction Widgets

**What goes wrong:**

New screens add tap-bounce, shimmer, slide-in, and fade animations using `AnimationController` in `StatefulWidget`. If `dispose()` is not called before `super.dispose()`, the controller's `Ticker` keeps running after the widget leaves the tree. On complex screens with 5+ animated elements, this accumulates into: dropped frames on scroll, memory growth over long sessions, and `"A Timer was registered but not disposed"` debug warnings that mask real issues.

**Why it happens:**

Micro-interaction patterns look simple. A developer adds `AnimationController` inline in a build method or initializes it without the `SingleTickerProviderStateMixin`. The code works in happy-path testing but leaks in real navigation where widgets are disposed and rebuilt. The existing codebase already has this pattern correct in `ShimmerPlaceholder` (verified in tests) but each new widget starts fresh.

**How to avoid:**

Use implicit animations (`AnimatedContainer`, `AnimatedOpacity`, `TweenAnimationBuilder`) for simple transitions — they handle their own lifecycle. Only reach for explicit `AnimationController` when you need precise timing control. When explicit controllers are required, mandate `SingleTickerProviderStateMixin`, `late final AnimationController _controller`, initialization in `initState`, and `_controller.dispose()` as the first line of `dispose()`. Create a micro-interaction pattern library in `lib/shared/animations/` with pre-built, pre-tested animation components that new screens pull from rather than reimplementing.

**Warning signs:**

Any `AnimationController` initialized outside `initState`. Any widget class with animation that doesn't call `dispose()`. The Flutter DevTools memory timeline showing a growing widget count that doesn't decrease after navigation.

**Phase to address:**

Phase 4 (Animation Library) — build the shared animation components with correct lifecycle before any screen uses them.

---

### Pitfall 6: Dashboard ScrollView Renders All Widgets Eagerly

**What goes wrong:**

The new rich home dashboard ("single-scroll with balance summary, inline group cards, recent activity, quick actions") is built as `SingleChildScrollView > Column > [widget1, widget2, widget3...]`. Flutter renders all children at once, regardless of whether they're visible. A dashboard with 5 group cards, a balance hero, a recent activity feed, and quick actions hits the frame budget immediately — especially on the first build when Firestore streams emit their initial data and trigger multiple `setState`/provider rebuilds simultaneously.

**Why it happens:**

`SingleChildScrollView` is the intuitive choice for a vertically scrolling page. It works fine for short content. For dashboards with 10+ children including cards with their own streams (each group card watching `groupBalancesProvider`), the eager rendering hits 60ms+ frame times on mid-range Android devices.

**How to avoid:**

Use `CustomScrollView` with `SliverList` or `SliverToBoxAdapter` for the dashboard body. Group cards must use `ListView.builder` (or `SliverList.builder`) — never a `Column` of expanded cards. The balance hero section can be a `SliverToBoxAdapter`. Measure with Flutter DevTools Performance view before and after — the frame timeline should show no raster frames exceeding 16ms during scroll. If a section must use `SingleChildScrollView`, cap its child count to 5 or fewer simple widgets.

**Warning signs:**

Any `Column` with more than 5 children that includes stream-subscribed widgets. Any `SingleChildScrollView` wrapping more than 100 lines of widget code. Scroll jank on first navigation to HomeScreen on a mid-range device.

**Phase to address:**

Phase 5 (Home Dashboard) — design the scroll architecture with SliverList from the start, not as a fix after jank is observed.

---

### Pitfall 7: Parallel Old/New Screens Without Explicit Coexistence Protocol

**What goes wrong:**

During phased rollout, both old and new screens exist simultaneously. A developer navigating to a group detail screen pushes the old screen in some flows and the new screen in others. Tests that import `group_detail_screen.dart` pass against the old version while the new version diverges. More critically, provider overrides in tests become ambiguous — a test importing `new_group_detail_screen.dart` may fail because it was written against the old screen's widget tree. When the old screen is eventually deleted, half the tests break.

**Why it happens:**

Phased migration creates file naming ambiguity (`group_detail_screen.dart` vs `group_detail_screen_v2.dart`) and import confusion. Without an explicit protocol, different developers navigate to different versions inconsistently.

**How to avoid:**

Use a single entry point with a compile-time or runtime feature flag. Never create `_v2.dart` files alongside originals. Instead, maintain the original filename and swap the implementation inside it. During coexistence, use `const bool _useNewLayout = bool.fromEnvironment('NEW_UI', defaultValue: false)` — this is a zero-overhead compile-time flag that runs the old path in all existing tests (which don't set the flag) while the new path can be tested explicitly. When the new layout is stable, remove the flag and the old path in one commit.

**Warning signs:**

Any PR that creates a file named `*_v2.dart` or `*_new.dart` alongside an existing screen file. Any test that imports a screen file with a version suffix.

**Phase to address:**

Phase 6 (Phased Screen Migration) — establish the compile-time flag protocol before migrating the first screen. Document it in CLAUDE.md.

---

### Pitfall 8: Navigation Restructuring Orphans Navigator.push Flows

**What goes wrong:**

The app has 22 `Navigator.push` / `AppPageRoute` calls and only 6 `context.push` / `context.go` calls. The redesign moves to a flatter navigation model where group dashboards and event hubs are top-level destinations. If the new navigation is added to GoRouter while the old `Navigator.push` calls remain, users hit broken back-navigation: the hardware back button pops a GoRouter route but the `Navigator.push` stack underneath has already been cleared. Deep linking to event screens fails silently.

**Why it happens:**

The mixed navigation model (GoRouter for top-level, `Navigator.push` for sub-screens) was a deliberate architectural choice in v1.0. The UI overhaul wants to flatten navigation but the documentation in CLAUDE.md still says CommandCenter "is NOT in GoRouter — this is intentional." Changing this without updating the documentation and all call sites creates silent inconsistency.

**How to avoid:**

Before restructuring navigation: (1) Map every `Navigator.push` call and the screen it pushes. (2) Decide explicitly which screens move into GoRouter and which stay as imperative pushes. (3) Update `CLAUDE.md` Navigation Flow section atomically with the code change. (4) Write a smoke test that navigates the new flow end-to-end before deleting any old route. For GoRouter's `StatefulShellRoute`, verify that tab state is preserved correctly across the flat navigation — this requires `ShellRoute` not independent top-level routes.

**Warning signs:**

Back button on a redesigned screen navigates to an unexpected screen. Any `Navigator.push` call that pushes a screen that is also a GoRouter route. `CLAUDE.md` navigation flow description that doesn't match the actual routing code.

**Phase to address:**

Phase 5 (Navigation Restructuring) — map and explicitly choose every route before writing any navigation code. Update documentation first.

---

## Technical Debt Patterns

Shortcuts that seem reasonable but create long-term problems.

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Inline animation parameters (`duration: Duration(ms: 300)` everywhere) | Faster to write each animation | Duration inconsistency across screens; impossible to globally adjust motion speed | Never — always use `AppMotion.fast/medium/slow` constants |
| Copy-pasting Stitch output without token substitution | Screen built faster | Two color systems diverge silently within weeks | Never in production screens |
| `SingleChildScrollView` for new dashboard | Simple to build | Eager render of all widgets; frame budget exceeded on load | Only for screens with ≤5 simple, non-stream children |
| Adding `_v2.dart` files during migration | Avoids touching existing tests | Import confusion, orphaned tests, eventual mass delete | Never — use compile-time flags instead |
| Wrapping entire screen in `RepaintBoundary` "for performance" | Appears to fix jank | GPU memory cost; only works if content is static; if content changes each frame, it increases cost | Only around truly static, non-animated subtrees |
| Using `setState` for animation state instead of `AnimationController` | Less boilerplate | Full widget rebuild on every animation frame; causes parent rebuilds to cascade | Never for animations running faster than 1fps |
| Testing new screen design only on simulator | Faster development loop | Mid-range Android (Snapdragon 665) reveals frame drops that simulator hides | Never for release candidates — always test on real device |

---

## Integration Gotchas

Common mistakes when connecting design changes to existing systems.

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| Firestore stream + animated dashboard | Letting the stream trigger full dashboard rebuilds on every snapshot | Use `select()` on providers to watch only the field that changes; use `keepAlive: true` on group balance providers to prevent re-fetching on tab switch |
| AppTheme + new color tokens | Adding new semantic colors to `AppTheme.lightTheme` `ColorScheme` without verifying Material3 color roles | Use `ThemeExtension<AppTokens>` for custom semantic tokens; only override Material3 ColorScheme for the slots that Material widgets actually read |
| GoRouter + Navigator.push coexistence | Using `context.push` for GoRouter routes inside a screen that was navigated to via `Navigator.push` | Decide one navigation system per screen depth; screens below CommandCenter use `Navigator.push` only; screens above use GoRouter only |
| Google Fonts + new font family | Loading a new font family at app start without caching | Use `GoogleFonts.config.allowRuntimeFetching = false` in release builds; pre-load font via `precachePicture` or include font assets locally to avoid first-frame flash |
| SQLite balance cache + new dashboard widget | Dashboard widget reading balance data directly from Firestore (bypassing SQLite) | All balance display must go through `BalanceCacheRepository` — it's the source of truth for fast local reads; the dashboard's balance hero widget must watch the same cache provider as the ledger screen |

---

## Performance Traps

Patterns that work in testing but degrade on real devices.

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Column of stream-subscribed cards | Scroll jank on HomeScreen; frame times 30-60ms on first load | Use `SliverList.builder`; each card is a separate widget with its own provider watch | Any screen with 3+ cards that each watch a Firestore provider |
| Over-applying `RepaintBoundary` | Memory usage climbs; GPU spikes during scroll; the boundary doesn't help because content changes each frame | Profile first; only add `RepaintBoundary` where DevTools shows a paint cascade problem | When wrapping frequently-updating widgets (balance numbers, timers) |
| Animating `Opacity` with full rebuilds | Jank during fade transitions; parent widgets rebuild alongside | Use `FadeTransition` (reads from `Animation<double>` without setState) instead of `AnimatedOpacity` for controller-driven animations | Any screen with simultaneous fade + slide animations |
| Hero animations between Navigator screens | Navigation stutter on first transition to CommandCenter | Assign consistent `heroTag` and wrap hero widget in `RepaintBoundary`; avoid using `Hero` for widgets with complex children | Any screen using `Hero` with a child that has shadows, gradients, or `ClipRRect` |
| Google Fonts loading on first build | Text briefly appears in fallback font before the custom font loads; visible flash on HomeScreen | Bundle "Plus Jakarta Sans" as a local font asset in pubspec.yaml; remove runtime Google Fonts fetching | Every app launch in a fresh install scenario |

---

## UX Pitfalls

Common user experience mistakes in this domain.

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| Flattening navigation but keeping 6+ module cards on one screen | Users are overwhelmed; no hierarchy to guide focus | Prioritize 3-4 primary actions on the dashboard; secondary modules behind a "More" reveal or secondary screen |
| Animations that can't be interrupted | User taps "back" during a page transition; the transition ignores the input and completes first | Every animation must respect user interruption; `AnimationController.reverse()` on back gesture before completing forward |
| Earthy palette without clear affordance hierarchy | Users can't distinguish tappable cards from decorative containers | Use shadow elevation and a subtle interactive tint on hover/press; never use color alone to indicate interactivity |
| Loading states that show skeleton screens but then jump to content | Visual "pop" when data loads; disorienting | Use `AnimatedSwitcher` or `crossFadeState` transitions when skeleton → content; minimum 200ms transition to mask the snap |
| Offline banner during normal operation | Banner flash on every app launch (Firestore initial handshake takes ~500ms) | Debounce the offline state: only show offline banner after 2+ seconds of no connectivity, not on first connectivity check |

---

## "Looks Done But Isn't" Checklist

Things that appear complete in the simulator but are missing critical pieces.

- [ ] **New color palette:** Verify every text-on-background combination against WCAG AA (4.5:1 for body, 3:1 for large) — simulator makes colors look better than they are on actual screens
- [ ] **Stitch screen export:** Replace every `Color(0xFF...)` inline value with the corresponding `AppColors.*` token before committing
- [ ] **Animation components:** Confirm `AnimationController.dispose()` is called in every `StatefulWidget` that creates one — add `flutter_lints` rule or `dispose_controllers` analysis option
- [ ] **Dashboard performance:** Test on a physical mid-range Android device (not simulator); verify frame times in DevTools Profile mode; no frame should exceed 16ms during scroll
- [ ] **Navigation restructuring:** Verify hardware back button behaves correctly at every new screen depth after GoRouter changes; test the full navigation graph, not just happy path
- [ ] **Test suite green:** Run `flutter test` after every screen replacement — do not accumulate test debt across multiple screen migrations
- [ ] **Font loading:** Verify "Plus Jakarta Sans" is bundled as a local asset (not fetched at runtime) and no font flash occurs on HomeScreen first load
- [ ] **Offline banner debounce:** Verify the offline banner does NOT flash on app launch when the device is online; test with airplane mode toggle
- [ ] **Compile-time flag removal:** When a screen migration is complete, verify the old code path is removed and the feature flag is deleted — do not leave dead code paths

---

## Recovery Strategies

When pitfalls occur despite prevention, how to recover.

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Test cascade from text label changes | MEDIUM | Run `flutter test 2>&1 \| grep FAILED`; for each failure, identify if it's a label change (fix the test) or a behavior regression (fix the code); systematically convert failing `find.text()` to `find.byKey()` as you go |
| Stitch inline values already in production screens | MEDIUM | Write a one-time `grep -r "Color(0xFF" lib/features` script to find all violations; replace batch by batch with AppColors references; add a CI lint step that fails on any `Color(0xFF` outside `app_theme.dart` |
| Animation controller leak discovered late | LOW | `flutter run --profile` + DevTools Memory tab shows widget count growth; identify leaking widget class by name; add `dispose()` call; the fix is always 1-2 lines |
| Dashboard jank on real device | MEDIUM | Profile in DevTools Performance view; identify the heavy-build widget in the frame graph; convert the `Column` to a `SliverList`; each group card that watched a provider becomes a separate `ConsumerWidget` in the list |
| WCAG contrast failure discovered after implementation | HIGH | Shift text color to a darker warm neutral (dark brown instead of terracotta); may require global search-replace of token references if the semantic token name didn't distinguish between text-on-light and text-on-dark contexts |
| Navigation stack broken after GoRouter restructuring | HIGH | Restore original routing from git; re-map all affected routes against the new navigation diagram before re-implementing; never restructure navigation and redesign screens in the same commit |

---

## Pitfall-to-Phase Mapping

How roadmap phases should address these pitfalls.

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| 257 `find.text()` calls break on label change | Phase 1: Test Hardening | `flutter test` passes after renaming 3 arbitrary UI labels |
| 895 direct AppColors references break on palette swap | Phase 2: Design Token System | Swap `AppPalette.primary` value and confirm zero compile errors |
| Earthy palette fails WCAG AA contrast | Phase 2: Design Token System | Every text/background combination checked in contrast tool before writing screen code |
| Stitch output with hardcoded values | Phase 3: Stitch Workflow Setup | CI lint step catches any `Color(0xFF` outside `app_theme.dart` |
| AnimationController leaks in micro-interactions | Phase 4: Animation Library | All animation components in `lib/shared/animations/` have passing dispose tests |
| Dashboard SliverList vs Column | Phase 5: Home Dashboard | DevTools Performance view shows no frames >16ms during scroll on physical device |
| Old/new screens coexisting without protocol | Phase 6: Phased Screen Migration | Compile-time flag in place; all existing tests pass without setting the flag |
| Navigator.push + GoRouter inconsistency | Phase 5: Navigation Restructuring | Full navigation graph test: back-button behavior at every screen depth |

---

## Sources

- [Flutter Performance Best Practices](https://docs.flutter.dev/perf/best-practices) — official, HIGH confidence
- [Flutter Improving Rendering Performance](https://docs.flutter.dev/perf/rendering-performance) — official, HIGH confidence
- [RepaintBoundary class - Flutter API](https://api.flutter.dev/flutter/widgets/RepaintBoundary-class.html) — official, HIGH confidence
- [SingleChildScrollView hidden costs](https://medium.com/norsys-octogone/the-hidden-costs-of-using-singlechildscrollview-a4722db29311) — MEDIUM confidence
- [Flutter GoRouter Bottom Navigation Stateful](https://codewithandrea.com/articles/flutter-bottom-navigation-bar-nested-routes-gorouter/) — MEDIUM confidence
- [AnimationController dispose patterns](https://www.oneclickitsolution.com/centerofexcellence/flutter/handling-animation-controller-leaks-in-flutter) — MEDIUM confidence
- [Building Design Systems in Flutter - ThemeExtension pitfalls](https://vibe-studio.ai/insights/creating-reusable-design-system-tokens-in-flutter-with-theme-extensions) — MEDIUM confidence
- [Flutter 2025 Performance Optimization](https://itnext.io/flutter-performance-optimization-10-techniques-that-actually-work-in-2025-4def9e5bbd2d) — MEDIUM confidence
- [WCAG 2.1 Contrast Minimum - W3C](https://www.w3.org/WAI/WCAG21/Understanding/contrast-minimum.html) — official, HIGH confidence
- [Google Stitch design token limitations](https://tech-insider.org/google-stitch-ai-design-tool-march-2026-update/) — LOW confidence (external review, not official documentation)
- [Google Stitch Flutter code generation](https://medium.com/@vignarajj/google-i-o-2025-flutter-3-32-shines-with-new-tools-and-stitch-ai-magic-06a1dc927calabria) — LOW confidence (third-party analysis)
- [Firestore UI thread blocking issue](https://github.com/firebase/flutterfire/issues/294) — MEDIUM confidence (verified issue in FlutterFire repo)
- [Flutter widget testing pitfalls - quickcoder](https://quickcoder.org/a-short-excursion-into-the-pitfalls-of-flutter-widget-testing/) — MEDIUM confidence
- [Building Design Systems in Flutter at Scale - LeanCode](https://leancode.co/blog/building-a-design-system-in-flutter-app) — MEDIUM confidence
- Codebase analysis: 257 `find.text()` / 4 `find.byKey()` ratio measured directly from test suite; 895 `AppColors.*` direct references measured directly from lib source

---
*Pitfalls research for: Flutter UI/UX overhaul — Rihla v2.0*
*Researched: 2026-03-28*
