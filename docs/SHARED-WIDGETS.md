# Shared Widgets and Animations

Reference catalog for everything under `lib/shared/`. These are
project-level building blocks reused across features. Reach for them
before writing a custom equivalent — if you find yourself needing a
shape that isn't here, consider whether the new shape belongs in
`shared/` rather than inside a feature.

For deeper design context, see `lib/shared/README.md` (this catalog
supersedes it). For the design tokens these widgets read, see
[ARCHITECTURE.md § Design System](./ARCHITECTURE.md).

---

## 1. How to use shared widgets

Three rules:

- **Read tokens through `context.colors` / `context.spacing` / `context.shadows`** (extensions provided by `lib/core/theme/tokens/domain_aliases.dart`). Never hardcode hex values; CI rejects them.
- **Localize text via `context.l10n`** (see [LOCALIZATION.md](./LOCALIZATION.md)). Pass already-resolved strings *into* shared widgets when the label is feature-specific.
- **Pass `Key` constants from `lib/core/keys/`** so widget tests can find your usage by key, not by text.

Most widgets are stateless and accept their data through constructor
parameters. Anything that watches a provider is a `ConsumerWidget` and
is marked as such below.

---

## 2. Widget catalog (`lib/shared/widgets/`)

### `ModuleHeader`

Standard dark-gradient header for every module screen (Ledger,
GroupSettings, EventSettings, …). Provides a back button, title,
optional subtitle, and an action slot.

| Property | Type | Notes |
|----------|------|-------|
| `title` | `String` | Required. Display text. |
| `subtitle` | `String?` | Optional uppercase overline (e.g. event name). |
| `useDarkTheme` | `bool` | Toggles the dark gradient variant; default true. |
| `actions` | `List<Widget>?` | Right-aligned icon buttons. |
| `bottom` | `PreferredSizeWidget?` | Tab bar slot. Use `AppTabBar`. |

Back button uses `DirectionalIcon` so it mirrors in RTL. Wraps the
header in a `GoRouter`-aware pop fallback to `/home` for direct-entry
deep links.

### `AppTabBar`

Pill-indicator tab bar tuned to the saffron palette. Requires a
`TabController` from the parent.

```dart
AppTabBar(
  controller: _tabController,
  tabs: const ['Unpacked', 'Packed'],
  activeColor: context.colors.moduleLedger, // optional accent override
)
```

Triggers `HapticService.selection()` on tab change.

### `OfflineBanner` (ConsumerWidget)

Amber connectivity banner. Watches `connectivityProvider` and renders
its own visibility — drop it at the top of any `Scaffold.body` and it
self-manages.

```dart
Scaffold(
  body: Column(children: [
    const OfflineBanner(),
    // ...
  ]),
)
```

Reads `context.l10n.offlineBannerMessage`.

### `EmptyStateView`

Consistent empty state with icon, title, message, and optional CTA.

```dart
EmptyStateView(
  icon: Iconsax.box,
  title: 'No expenses yet',
  message: 'Add the first shared expense for this event.',
  actionLabel: 'Add Expense',
  onAction: () { /* ... */ },
  accentGradient: context.colors.primaryGradient, // optional colored icon background
)
```

### `SearchFilterBar` (StatefulWidget)

Expandable search input plus a filter chip row. Stateful because it
manages its own expand/collapse, the text controller, and chip
selection.

| Property | Type | Notes |
|----------|------|-------|
| `hintText` | `String` | Field placeholder. |
| `onQueryChanged` | `void Function(String)` | Debounced via the field controller. |
| `filterChips` | `List<String>` | Optional chip labels. |
| `selectedFilter` | `String?` | Controlled selection. |
| `onFilterSelected` | `void Function(String?)?` | Chip-tap callback. |

Triggers `HapticService.selection()` on chip taps.

### `SmartModuleCard`

Module card used on `EventCommandCenter`. Renders three states from
the same surface: data summary, empty hint, or "needs attention." Wraps
its content in `TapBounce` for press feedback.

```dart
SmartModuleCard(
  icon: Iconsax.receipt,
  title: 'Ledger',
  summaryText: '5 expenses · OMR 24.300',
  description: 'Track shared spending and settle up.',
  actionText: null,
  color: context.colors.moduleLedger,
  onTap: () => context.push('/group/$gid/event/$eid/ledger'),
)
```

`EventCommandCenter` itself is dead-but-kept code (UI bypasses to the
ledger). `SmartModuleCard` survives because anything else in the app
that ever needs a module-shaped card should reuse it.

### `LoadingButton`

52dp primary button with a spinner state. The label collapses to a
spinner when `isLoading` is true.

```dart
LoadingButton(
  label: l10n.commonSave,
  isLoading: ref.watch(expenseSavingProvider),
  onPressed: _handleSave,
  gradient: context.colors.primaryGradient, // optional
)
```

### `SkeletonLoader`

Named-factory skeletons that mirror real layouts so the screen doesn't
jump when data lands. All variants wrap children in `Shimmer.fromColors`.

| Factory | Approximates |
|---------|--------------|
| `SkeletonLoader.dashboardHero()` | Home balance hero + stats row |
| `SkeletonLoader.expenseList()` | Ledger expense rows with trailing amount |
| `SkeletonLoader.eventCard()` | Event cards on group detail |
| `SkeletonLoader.groupList()` | Group rows with avatar |
| `SkeletonLoader.generic()` | Plain fallback |

Use the variant that matches the screen you're loading.

### `SkeletonPrimitives`

Composable building blocks used by `SkeletonLoader`. Build a custom
skeleton when none of the named variants match:

| Class | Use |
|-------|-----|
| `SkeletonCircle` | Avatar / icon placeholders |
| `SkeletonBox` | Generic rectangle |
| `SkeletonLine` | Single line of text |
| `SkeletonStack` | Vertical group |

Always wrap your composition in `Shimmer.fromColors` (or use the
`SkeletonLoader` wrapper) — the primitives only render fills.

### `AnimatedCurrencyText`

Smoothly lerps between two `Decimal` values over 600ms (easeOutCubic).
Color snaps based on the animated value's sign — sage for positive,
rust for negative, neutral ink for zero. Used on the Home balance hero
and group balance cards.

```dart
AnimatedCurrencyText(
  value: balance.netBalance,
  currency: 'OMR',
  size: 32,
)
```

Tracks the previous value internally so each transition starts from
the old number, not zero.

### `RAmount`

The canonical money-display widget. Uses Geist Mono with currency-aware
tiered sizing: currency prefix at 0.42×, whole part at full size,
decimal part at 0.55×.

```dart
RAmount(
  amount: Decimal.parse('10.500'),
  currency: 'OMR',
  size: 24,
  tone: RAmountTone.auto, // auto | positive | negative | neutral
  showSign: true,
)
```

`tone: auto` defers to the sign of the value. Override explicitly when
the meaning isn't tied to positivity (e.g., totals, where positive
doesn't mean "good").

### `RAvatar`

Initials avatar with a stable per-name color slot drawn from the
journal-stamp palette. The name → slot mapping is deterministic (FNV-
style hash on `codeUnits`), so the same name always picks the same
color across upgrades.

```dart
RAvatar(displayName: 'Sarah', size: 40)
```

Falls back to a generic person glyph when `displayName` is empty.
Prefer this over building avatar circles by hand.

### `CoverArt`

Procedural two-band illustration used as the "scenery without photos"
cover for journey ticket cards, group covers, and event row
thumbnails. Sky gradient + sun + two land paths, all derived from the
event ID + type so the composition is stable across re-renders.

```dart
CoverArt(event: event, size: 96)
```

Pure paint — no asset roundtrip. Renders the same way offline.

### `RouteMark`

Rihla's chosen brand mark — a dashed S-curve from a small origin (filled
ink dot) to a saffron destination pin with cream center. Reads as
"trip" without spelling it out. Renders inside a square box of `size`;
defaults pull from the active palette.

```dart
RouteMark(size: 24)
RouteMark(size: 96, monochrome: true) // for themed Android icons
```

Set `monochrome` for Android themed icon contexts where a second color
isn't available.

### `WordmarkLogo`

The italic "Rihla" wordmark with a saffron underline flourish. Used on
splash, onboarding, and the top bar wordmark. Flourish width tracks
1.6× the type `size` so the proportion stays constant across scales.

```dart
WordmarkLogo(size: 32)
```

### `DotStepIndicator`

Dot-based step indicator. Three states per dot — completed, active,
upcoming. Set `showCheckmarks: true` to fill completed dots with a
check icon.

```dart
DotStepIndicator(
  stepCount: 3,
  currentStep: _step,
  showCheckmarks: true, // D-27 on Add Expense; false for onboarding (D-29)
)
```

Used on the Add Expense multi-step flow and the onboarding pager.

### `SectionHeader`

Small uppercase mono caption for grouping list sections (e.g.,
"ACTIVE JOURNEYS", "GROUPS", "RECENTLY"). Optional action link on the
right for "See all" affordances.

```dart
SectionHeader(
  title: 'GROUPS',
  actionLabel: 'See all',
  onActionTap: () => context.push('/groups'),
)
```

### `GrainOverlay`

Applies a subtle paper-grain noise texture to its child. Uses a
tileable 32×32 PNG repeated across the surface. Default opacity 3.5%
(hero cards, scaffold backgrounds); use 2% for dark headers per D-11.

```dart
GrainOverlay(
  child: Container(color: paperFill, child: heroContent),
)
GrainOverlay(opacity: 0.02, child: darkHeader)
```

### `DirectionalIcon`

RTL-aware icon wrapper. Mirrors its `IconData` horizontally when the
ambient `Directionality` is RTL. Required for Iconsax-sourced
navigational glyphs (arrows, chevrons) because Iconsax ships
`IconData` without `matchTextDirection: true`.

```dart
DirectionalIcon(Iconsax.arrow_left, size: 24, color: context.colors.iconPrimary)
```

Use it for nav arrows and row chevrons. Don't wrap non-directional
icons (gear, heart, box) — mirroring them looks broken. See
[LOCALIZATION.md § RTL handling](./LOCALIZATION.md#8-rtl-handling).

---

## 3. Animations (`lib/shared/animations/`)

### `FadeInList`

Staggered fade-in for list children. D-04: 350ms easeOutCubic with a
50ms stagger, 12dp slide-up plus opacity.

```dart
FadeInList(
  children: expenses.map((e) => ExpenseTile(expense: e)).toList(),
)
```

Honors `MediaQuery.disableAnimations` — when the user has reduced
motion enabled (or the test harness disables animations), the children
render in a plain `Column` with no `Animate` wrappers.

### `StaggeredGrid`

Same idea for grid layouts. D-06: 400ms with a 60ms stagger,
easeOutQuart. Used on the event-type picker grid.

```dart
StaggeredGrid(
  children: eventTypes.map((t) => EventTypeCard(type: t)).toList(),
)
```

Also honors `disableAnimations`.

### `TapBounce`

Press-scale animation wrapper. D-05: 120ms easeInOut, scales to 0.97
on tap. Apply to anything tappable that should give kinesthetic
feedback (cards, large icons). Disposes its `AnimationController`
before `super.dispose()` to avoid ticker leaks.

```dart
TapBounce(
  onTap: _handleTap,
  child: SmartModuleCard(...),
)
```

When `onTap` is null or `enabled: false`, returns `child` unwrapped so
the bounce doesn't fire on disabled surfaces.

### `animations.dart`

Barrel export for the three animations above. Import this when a file
uses two or more.

---

## 4. When to add a new shared widget

Promote to `lib/shared/widgets/` when **all** of these hold:

- The shape is used (or will be used) in **two or more features**.
- It has a clear, single responsibility you can name in one sentence.
- It reads styling via tokens, not literals.
- A widget test can exercise it in isolation (no feature-specific providers required).

Otherwise keep it in the feature directory. Once a second feature
copies it, refactor up.

When you do promote a widget:

1. Move the file to `lib/shared/widgets/`.
2. Update its imports to relative paths from `shared/`.
3. Replace any feature-token shortcuts with `context.colors` / `context.spacing` / `context.shadows`.
4. Add a doc comment matching the style of the others above.
5. Add a row to this catalog and to `lib/shared/README.md`.
6. Add a widget test under `test/shared/widgets/`.

---

## 5. Files at a glance

```
lib/shared/
├── README.md                          # Short index (this doc supersedes it)
├── animations/
│   ├── animations.dart                # Barrel export
│   ├── fade_in_list.dart              # FadeInList
│   ├── staggered_grid.dart            # StaggeredGrid
│   └── tap_bounce.dart                # TapBounce
└── widgets/
    ├── animated_currency_text.dart    # AnimatedCurrencyText
    ├── app_tab_bar.dart               # AppTabBar
    ├── cover_art.dart                 # CoverArt
    ├── directional_icon.dart          # DirectionalIcon
    ├── dot_step_indicator.dart        # DotStepIndicator
    ├── empty_state_view.dart          # EmptyStateView
    ├── grain_overlay.dart             # GrainOverlay
    ├── loading_button.dart            # LoadingButton
    ├── module_header.dart             # ModuleHeader
    ├── offline_banner.dart            # OfflineBanner (ConsumerWidget)
    ├── r_amount.dart                  # RAmount
    ├── r_avatar.dart                  # RAvatar
    ├── route_mark.dart                # RouteMark
    ├── search_filter_bar.dart         # SearchFilterBar (StatefulWidget)
    ├── section_header.dart            # SectionHeader
    ├── skeleton_loader.dart           # SkeletonLoader
    ├── skeleton_primitives.dart       # SkeletonCircle / Box / Line / Stack
    ├── smart_module_card.dart         # SmartModuleCard
    └── wordmark_logo.dart             # WordmarkLogo
```

---

## 6. Related docs

- [ARCHITECTURE.md § Design System](./ARCHITECTURE.md) — tokens these widgets read
- [LOCALIZATION.md](./LOCALIZATION.md) — RTL handling, `DirectionalIcon`
- [DEVELOPMENT.md § Design System](./DEVELOPMENT.md) — token APIs, design workflow
- [TESTING.md § Widget tests](./TESTING.md) — testing patterns
