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
| `useDarkTheme` | `bool` | Toggles the dark gradient variant; default false. |
| `actions` | `List<Widget>?` | Right-aligned icon buttons. |
| `bottom` | `PreferredSizeWidget?` | Tab bar slot. |

Back button uses `DirectionalIcon` so it mirrors in RTL. Wraps the
header in a `GoRouter`-aware pop fallback to `/home` for direct-entry
deep links.

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
| `SkeletonLoader.cardList()` | Generic card rows |
| `SkeletonLoader.generic()` | Plain fallback |

Use the variant that matches the screen you're loading.

`SkeletonLoader.gearList()`, `.photoGrid()`, and `.documentList()` are
dead-but-kept leftovers of the Gear / Memories / Documents modules
stripped in Phase 39 — don't use them.

### `SkeletonPrimitives`

Composable building blocks used by `SkeletonLoader`. Build a custom
skeleton when none of the named variants match:

| Class | Use |
|-------|-----|
| `SkeletonCircle` | Avatar / icon placeholders |
| `SkeletonBar` | Single line of text |
| `SkeletonBlock` | Generic rectangle |
| `SkeletonRow` | Horizontal group |
| `SkeletonCard` | Card placeholder |

Always wrap your composition in `Shimmer.fromColors` (or use the
`SkeletonLoader` wrapper) — the primitives only render fills.

### `RAmount`

The canonical money-display widget. Uses Geist Mono with currency-aware
tiered sizing: currency prefix at 0.42×, whole part at full size,
decimal part at 0.55×.

```dart
RAmount(
  value: Decimal.parse('10.500'),
  currency: 'OMR',
  size: 24,
  tone: AmountTone.auto, // auto | sage | rust | ink
  sign: true,
)
```

`tone: AmountTone.auto` defers to the sign of the value (sage positive,
rust negative, ink neutral). Override explicitly when the meaning isn't
tied to positivity (e.g., totals, where positive doesn't mean "good").
Also exposes `showCurrency` (default `true`) and `weight` (default
`FontWeight.w500`).

### `RAvatar`

Initials avatar with a stable per-name color slot drawn from the
journal-stamp palette. The name → slot mapping is deterministic (FNV-
style hash on `codeUnits`), so the same name always picks the same
color across upgrades.

```dart
RAvatar(name: 'Sarah', size: 40)
```

Falls back to a generic person glyph when `name` is empty.
Prefer this over building avatar circles by hand.

> **Invariant (DEC-3, design review 2026-05-30 — issue #149):** a user's identity
> color is name-derived and deterministic. The optional `hue` override exists for
> non-identity decoration only — never pass it to force a per-user color, and never
> randomize. One stable color per person, everywhere, is a protected design rule.

### `CoverArt`

Procedural two-band illustration used as the "scenery without photos"
cover for journey ticket cards, group covers, and event row
thumbnails. Sky gradient + sun + two land paths, all derived from the
event ID + type so the composition is stable across re-renders.

```dart
CoverArt(event: event, size: 96)
```

Pure paint — no asset roundtrip. Renders the same way offline.

### `WordmarkLogo`

The italic "Rihla" wordmark with a saffron underline flourish. Used on
splash, onboarding, and the top bar wordmark. Flourish width tracks
1.6× the type `size` so the proportion stays constant across scales.

```dart
WordmarkLogo(size: 32)
```

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

### `TapBounce`

Press-scale animation wrapper. D-05: 120ms easeInOut, scales to 0.97
on tap. Apply to anything tappable that should give kinesthetic
feedback (cards, large icons). Disposes its `AnimationController`
before `super.dispose()` to avoid ticker leaks.

```dart
TapBounce(
  onTap: _handleTap,
  child: Card(...),
)
```

When `onTap` is null or `enabled: false`, returns `child` unwrapped so
the bounce doesn't fire on disabled surfaces.

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
│   └── tap_bounce.dart                # TapBounce
└── widgets/
    ├── cover_art.dart                 # CoverArt
    ├── directional_icon.dart          # DirectionalIcon
    ├── empty_state_view.dart          # EmptyStateView
    ├── grain_overlay.dart             # GrainOverlay
    ├── loading_button.dart            # LoadingButton
    ├── module_header.dart             # ModuleHeader
    ├── offline_banner.dart            # OfflineBanner (ConsumerWidget)
    ├── r_amount.dart                  # RAmount
    ├── r_avatar.dart                  # RAvatar
    ├── section_header.dart            # SectionHeader
    ├── skeleton_loader.dart           # SkeletonLoader
    ├── skeleton_primitives.dart       # SkeletonCircle / Bar / Block / Row / Card
    └── wordmark_logo.dart             # WordmarkLogo
```

---

## 6. Related docs

- [ARCHITECTURE.md § Design System](./ARCHITECTURE.md) — tokens these widgets read
- [LOCALIZATION.md](./LOCALIZATION.md) — RTL handling, `DirectionalIcon`
- [DEVELOPMENT.md § Design System](./DEVELOPMENT.md) — token APIs, design workflow
- [TESTING.md § Widget tests](./TESTING.md) — testing patterns
