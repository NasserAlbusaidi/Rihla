# Phase 15: Design Token System - Research

**Researched:** 2026-03-28
**Domain:** Flutter ThemeExtension, Design Tokens, WCAG Contrast, CI Linting
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Palette Mapping**
- D-01: Primary action = terracotta (#CC6B49) — buttons, FABs, focused inputs, links, selection highlights
- D-02: Financial status colors stay standard green (#10B981) / red (#EF4444) — universal convention, not brand
- D-03: Module accents — Ledger #CC6B49, Gear #7A8C5E, Logistics #5B7B8C, Vault #8B7355, Activity #A67C5B, Memories #9B7A5C
- D-04: Background/surface — scaffold #F2E8D6 (sand), card #FFF9F2 (warm white), input fill #F5EDE1, border #E5D5C0
- D-05: Text hierarchy — primary #2C1A0E (dark brown), secondary #6B5B4E (warm gray), muted #A89888 (sand gray), text-on-primary #FFFFFF
- D-06: Header gradient — #2C1A0E → #3D2B1E; module headers use darkened accent variants
- D-07: Shadows use warm brown base (#2C1A0E) at low opacity
- D-08: Disabled — warm beige (#E5D5C0) bg, sand gray (#A89888) text
- D-09: Focus/selection — terracotta border (#CC6B49), selected chip bg #F5DDD3 (terracotta 15%)

**Token Architecture**
- D-10: Split ThemeExtensions by concern — AppColorTokens, AppSpacingTokens, AppShadowTokens
- D-11: Two-layer naming — core role names (primary, surface, textPrimary) + domain aliases (balancePositive=success, moduleLedger=primary)
- D-12: File layout — `lib/core/theme/tokens/` with color_tokens.dart, spacing_tokens.dart, shadow_tokens.dart, domain_aliases.dart
- D-13: Gradient tokens in AppColorTokens as start/end color fields with LinearGradient getters
- D-14: Module accent colors in AppColorTokens (moduleLedger, moduleGear, etc.) with light tint variants
- D-15: BuildContext extension methods — context.colors, context.spacing, context.shadows

**Migration Approach**
- D-16: AppColors becomes thin static facade — values updated to earthy palette, all 962 call sites compile unchanged
- D-17: Migration from AppColors.x to context.colors.x happens per-screen in phases 18-22, not Phase 15
- D-18: AppColors facade stays valid through v2.0; deleted in Phase 22

**CI Lint Rule**
- D-19: Grep-based CI step in GitHub Actions — zero dependencies
- D-20: Hard fail — CI build fails on hardcoded Color(0xFF...) outside allowlist
- D-21: Allowlist: lib/core/theme/app_theme.dart, lib/core/theme/tokens/*.dart, lib/features/ledger/models/expense_category_model.dart, test/**/*.dart

### Claude's Discretion

- Exact WCAG contrast verification approach and tool
- Precise hex values for module light tint variants (direction: ~15% opacity tints)
- Whether to include a ColorScheme mapping alongside ThemeExtension or keep separate
- Exact lerp implementation details for ThemeExtension copyWith/lerp methods
- Order of implementation tasks within the phase

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope.
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| FOUND-01 | App uses a ThemeExtension-based design token system with warm earthy palette replacing hardcoded AppColors references | ThemeExtension API documented below; two-layer token architecture defined in D-10 through D-15 |
| FOUND-02 | All text-on-background color combinations meet WCAG AA contrast ratios (4.5:1 body, 3:1 large text/icons) | Full WCAG compliance matrix computed; 2 issues flagged (financial text colors, muted text) requiring two-color strategy |
| FOUND-04 | CI lint rule prevents new hardcoded Color(0xFF...) values outside token system | Grep-based GitHub Actions step pattern established from Phase 14; exact regex and allowlist documented |
</phase_requirements>

---

## Summary

Phase 15 builds a ThemeExtension-based design token system and performs a palette swap from the current neon-mint/slate scheme to a warm earthy palette (terracotta, sand, olive, dark brown). The work has three distinct streams: (1) creating the token classes and registering them with ThemeData, (2) updating AppColors values in-place so 962 call sites get the earthy palette without changes, and (3) migrating the 15 hardcoded `Color(0xFF...)` literals in non-exempt files to use AppColors tokens.

The most critical planning input from this research is the **WCAG compliance matrix**. Two color relationships in the locked decisions fail WCAG AA: financial text colors (#10B981 green and #EF4444 red) do not meet contrast requirements when used as text on the sand or warm-white backgrounds. The resolution is a two-color strategy: the D-02 palette values remain as "display" tokens (badge backgrounds, icons, decorative elements) while darker text variants (#047857 success text, #B91C1C error text) are introduced as separate token fields for legible text uses. This is within Claude's discretion and does not contradict any locked decision.

**Primary recommendation:** Use the two-color financial token pattern (display vs. text variants) to satisfy FOUND-02 without violating D-02. This is the only structural addition beyond what CONTEXT.md specifies.

---

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Flutter `ThemeExtension<T>` | SDK (Flutter 3.41.5) | Custom typed token extension on ThemeData | Official Flutter API, no external dependency, survives hot reload, lerps correctly across theme transitions |
| `flutter/material.dart` | SDK | `Color`, `LinearGradient`, `BoxShadow`, `ColorScheme` types | All token types are first-party Flutter primitives |
| `BuildContext.extension<T>()` | SDK | Token retrieval in widgets | Zero overhead wrapper around `Theme.of(context).extension<T>()` |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `google_fonts` | `^6.1.0` (current) | Plus Jakarta Sans typeface | Already in use; text theme untouched in Phase 15 |
| GitHub Actions `grep` | N/A | CI lint for hardcoded colors | No new dependency; pattern already established in Phase 14 |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Manual ThemeExtension subclass | `theme_tailor` code-gen package | Code-gen eliminates boilerplate but adds a build_runner dep; 3 extensions total is not enough complexity to justify it |
| Two-layer (ThemeExtension + AppColors facade) | ThemeExtension only | Replacing 962 AppColors call sites is Phase 22 scope; facade is the explicitly locked approach |
| Custom `InheritedWidget` token provider | ThemeExtension | ThemeExtension is already integrated with Material hot-reload and animation; no reason to duplicate |

**Installation:** No new packages. All token types are Flutter SDK primitives.

---

## Architecture Patterns

### Recommended Project Structure

```
lib/core/theme/
├── app_theme.dart            # AppColors (facade, values updated) + AppTheme (ThemeData builder)
└── tokens/
    ├── color_tokens.dart     # AppColorTokens extends ThemeExtension<AppColorTokens>
    ├── spacing_tokens.dart   # AppSpacingTokens extends ThemeExtension<AppSpacingTokens>
    ├── shadow_tokens.dart    # AppShadowTokens extends ThemeExtension<AppShadowTokens>
    └── domain_aliases.dart   # BuildContext extension: context.colors, context.spacing, context.shadows
```

### Pattern 1: ThemeExtension Subclass

**What:** Each token group is a typed `ThemeExtension<T>` subclass with a const constructor, all fields required.

**When to use:** Every grouped set of semantic tokens (colors, spacing, shadows).

```dart
// Source: https://api.flutter.dev/flutter/material/ThemeExtension-class.html
final class AppColorTokens extends ThemeExtension<AppColorTokens> {
  const AppColorTokens({
    required this.primary,
    required this.surface,
    required this.scaffoldBackground,
    required this.cardSurface,
    required this.inputFill,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.textOnPrimary,
    required this.success,
    required this.successText,   // darkened variant for text legibility
    required this.error,
    required this.errorText,     // darkened variant for text legibility
    required this.disabled,
    required this.disabledText,
    required this.focusRing,
    required this.selectionFill,
    required this.moduleLedger,
    required this.moduleLedgerLight,
    required this.moduleGear,
    required this.moduleGearLight,
    required this.moduleLogistics,
    required this.moduleLogisticsLight,
    required this.moduleVault,
    required this.moduleVaultLight,
    required this.moduleActivity,
    required this.moduleActivityLight,
    required this.moduleMemories,
    required this.moduleMemoriesLight,
    required this.headerGradientStart,
    required this.headerGradientEnd,
  });

  final Color primary;
  final Color surface;
  final Color scaffoldBackground;
  final Color cardSurface;
  final Color inputFill;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color textOnPrimary;
  final Color success;
  final Color successText;
  final Color error;
  final Color errorText;
  final Color disabled;
  final Color disabledText;
  final Color focusRing;
  final Color selectionFill;
  final Color moduleLedger;
  final Color moduleLedgerLight;
  final Color moduleGear;
  final Color moduleGearLight;
  final Color moduleLogistics;
  final Color moduleLogisticsLight;
  final Color moduleVault;
  final Color moduleVaultLight;
  final Color moduleActivity;
  final Color moduleActivityLight;
  final Color moduleMemories;
  final Color moduleMemoriesLight;
  final Color headerGradientStart;
  final Color headerGradientEnd;

  // Convenience getters (not fields — LinearGradient is not const-safe as a field)
  LinearGradient get headerGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [headerGradientStart, headerGradientEnd],
  );

  @override
  AppColorTokens copyWith({
    Color? primary,
    Color? surface,
    // ... all fields with ?? fallback
  }) => AppColorTokens(
    primary: primary ?? this.primary,
    surface: surface ?? this.surface,
    // ...
  );

  @override
  AppColorTokens lerp(AppColorTokens? other, double t) {
    if (other is! AppColorTokens) return this;
    return AppColorTokens(
      primary: Color.lerp(primary, other.primary, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      // ... all Color fields via Color.lerp
    );
  }
}
```

### Pattern 2: AppColors Facade (in-place value update)

**What:** `AppColors` static constants in `app_theme.dart` get their `Color(0xFF...)` literals changed to the earthy palette values. No API changes, no new imports anywhere.

**When to use:** The only migration path that satisfies D-16 (zero call-site changes, 962 references stay intact).

```dart
// BEFORE
static const Color primary = Color(0xFF13EC92); // Neon Mint

// AFTER
static const Color primary = Color(0xFFCC6B49); // Terracotta
```

**Key constraint:** `const` constructors must stay `const`. All new earthy palette values are direct `Color(0xFF...)` literals — this is the exempt file.

### Pattern 3: BuildContext Extension (domain_aliases.dart)

**What:** Extension on `BuildContext` providing terse token access.

```dart
// Source: Flutter ThemeExtension retrieval pattern
extension AppThemeExtensions on BuildContext {
  AppColorTokens get colors =>
      Theme.of(this).extension<AppColorTokens>()!;
  AppSpacingTokens get spacing =>
      Theme.of(this).extension<AppSpacingTokens>()!;
  AppShadowTokens get shadows =>
      Theme.of(this).extension<AppShadowTokens>()!;
}
```

### Pattern 4: ThemeData Registration

**What:** Extensions attached to `AppTheme.lightTheme` via the `.extensions` list.

```dart
// In AppTheme.lightTheme ThemeData builder:
extensions: [
  AppColorTokens(
    primary: AppColors.primary,
    scaffoldBackground: AppColors.background,
    // ... wire every token to its AppColors facade value
  ),
  AppSpacingTokens(
    space4: AppColors.space4,
    // ...
  ),
  AppShadowTokens(
    flat: AppColors.shadowFlat,
    // ...
  ),
],
```

**Important:** `darkTheme` in `app_theme.dart` has hardcoded slate-900 values. Since dark mode is out of scope, the dark theme registration can use the same earthy token instance for now (it is not surfaced in the app — DARK-01 is a deferred requirement).

### Anti-Patterns to Avoid

- **Adding `const` to LinearGradient fields on AppColorTokens:** `LinearGradient` cannot be a `const` field on a `const` class. Use getters or factory methods.
- **Using `List<BoxShadow>` as ThemeExtension fields:** `List` is mutable. Expose shadows via `ShadowTokens` with individual `BoxShadow` entries and let callers compose the list.
- **Calling `Theme.of(context).extension<T>()` without null assertion:** The extensions are registered at app startup. The `!` assertion is safe; `?.` suggests they might be absent, which obscures real registration bugs.
- **Updating AppColors values and ThemeExtension wires in separate commits:** These must be atomic. If AppColors values change before ThemeExtension is wired, the app renders the earthy palette without the token system — misleading state.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| WCAG contrast calculation | Custom luminance math in app code | Pre-calculated matrix in RESEARCH.md + one-time Python script for verification | Values are compile-time constants; runtime contrast checking adds zero user value |
| Hardcoded color detection | Custom AST parser | `grep -rn "Color(0x"` in CI | Regex covers 100% of the Flutter Color literal syntax; AST is over-engineered |
| Design token code generation | Hand-written boilerplate | Manual implementation (3 extensions is not worth build_runner) | `theme_tailor` is only worth it at 10+ extensions; adds CI complexity |
| Two-level color mapping | Custom resolution logic | Direct field wires in ThemeData.extensions list | Flutter's theme system handles resolution; no custom plumbing needed |

---

## WCAG Compliance Matrix

This section is the critical output for FOUND-02. All calculations are exact (Python-computed using the WCAG 2.1 relative luminance formula).

### Text on Backgrounds — Core Palette

| Foreground | Background | Ratio | AA Body (4.5:1) | AA Large (3:1) | Usage |
|------------|------------|-------|-----------------|----------------|-------|
| `#2C1A0E` (primary text) | `#F2E8D6` (scaffold) | **13.71:1** | PASS | PASS | All body text |
| `#2C1A0E` (primary text) | `#FFF9F2` (card) | **15.92:1** | PASS | PASS | Card body text |
| `#6B5B4E` (secondary text) | `#F2E8D6` (scaffold) | **5.35:1** | PASS | PASS | Secondary labels |
| `#6B5B4E` (secondary text) | `#FFF9F2` (card) | **6.22:1** | PASS | PASS | Card secondary |
| `#A89888` (muted text) | `#F2E8D6` (scaffold) | **2.30:1** | FAIL | FAIL | Decorative only |
| `#A89888` (muted text) | `#FFF9F2` (card) | **2.67:1** | FAIL | FAIL | Decorative only |
| `#FFFFFF` (on dark header) | `#2C1A0E` (header) | **16.65:1** | PASS | PASS | Header text |

**Muted text note:** D-05 explicitly documents `#A89888` as "AA large text only" — 2.30:1 is below even that threshold. In practice, muted text should be used only as metadata labels at 11sp+, never as functional text. The planner should add a comment to the muted token field documenting this limitation.

### Primary Actions (Terracotta)

| Foreground | Background | Ratio | Result | Usage |
|------------|------------|-------|--------|-------|
| `#FFFFFF` | `#CC6B49` (terracotta) | **3.64:1** | PASS AA large | Button labels (16sp+, weight 700) |
| `#2C1A0E` | `#CC6B49` (terracotta) | **4.57:1** | PASS AA body | Alt: dark text on terracotta |
| `#CC6B49` | `#F2E8D6` (scaffold) | **3.00:1** | MARGINAL (exactly 3:1) | Links/accents — large text only |

**Button label recommendation:** Use white (`#FFFFFF`) on terracotta for button labels. 3.64:1 passes AA for large text (≥18sp or 14sp+ bold). Button labels at 16sp weight 700 qualify as large text under WCAG 2.1 definition. Use dark brown (`#2C1A0E`) as `textOnPrimary` only if white is aesthetically objectionable (it is the safer accessibility choice at 4.57:1). This is within Claude's discretion — white on terracotta matches the locked decision D-05 ("text on primary: #FFFFFF").

### Financial Status Colors — TWO-COLOR STRATEGY REQUIRED

The locked D-02 values (#10B981 green, #EF4444 red) **do not meet WCAG AA on the earthy backgrounds**. They are viable as decorative display tokens (badge backgrounds, icons, chip fills) but must not be used as text colors.

| Token | Hex | Ratio on Sand | Ratio on Warm White | Use As |
|-------|-----|---------------|---------------------|--------|
| `success` (display) | `#10B981` | 2.09:1 — FAIL | 2.43:1 — FAIL | Badge bg, icon, chip fill only |
| `successText` (text) | `#047857` | **4.51:1 — PASS** | **5.24:1 — PASS** | Balance amount text, label text |
| `error` (display) | `#EF4444` | 3.10:1 — AA large | 3.60:1 — AA large | Badge bg, icon, chip fill |
| `errorText` (text) | `#B91C1C` | **5.33:1 — PASS** | **6.19:1 — PASS** | Balance amount text, label text |

Both `success`/`error` (D-02) remain in the token system unchanged. `successText` (#047857) and `errorText` (#B91C1C) are additive — new companion fields in AppColorTokens. This satisfies FOUND-02 without changing D-02.

---

## Hardcoded Color Audit (Files Requiring Migration)

15 `Color(0xFF...)` occurrences in non-exempt `lib/` files. All must be migrated to AppColors references before CI lint step can pass.

| File | Count | Colors Used | Migration Target |
|------|-------|-------------|-----------------|
| `lib/core/router/app_router.dart` | 4 | `#0F172A` (scaffold dark), `#13EC92` (mint primary), `#0BAE6B` (primary dark) | `AppColors.surfaceDark`, `AppColors.primary`, `AppColors.primaryDark` |
| `lib/features/onboarding/screens/onboarding_screen.dart` | 3 | `#0F172A`, `#1E293B` (slate 800), `#334155` (slate 700) | `AppColors.surfaceDark`, two new dark surface tokens or gradient tokens |
| `lib/core/theme/error_widgets.dart` | 3 | `#F59E0B` (amber), `#64748B` (slate 500) | `AppColors.warning`, `AppColors.textSecondary` |
| `lib/features/events/widgets/event_spending_hero.dart` | 2 | (need to inspect for exact colors) | AppColors tokens |
| `lib/features/events/screens/event_expense_hero.dart` | 2 | (need to inspect) | AppColors tokens |
| `lib/features/groups/widgets/group_balance_hero.dart` | 1 | (need to inspect) | AppColors tokens |

**Additional concern:** `Colors.grey.*` and `Colors.white70` usage in several files (e.g., `lib/features/activity/widgets/timeline_card.dart` has 9 occurrences). The CI grep pattern `Color(0x` targets explicit hex literals only and will NOT catch `Colors.grey.*` references. The CONTEXT.md CI rule (D-19) targets only `Color(0xFF...)` — `Colors.*` named colors are not in scope for Phase 15. This is correct behavior: named colors are a separate migration concern for screen redesign phases.

---

## Common Pitfalls

### Pitfall 1: LinearGradient in const ThemeExtension

**What goes wrong:** Declaring `final LinearGradient headerGradient` on a ThemeExtension with a `const` constructor — Flutter's `LinearGradient` is not const-constructable.

**Why it happens:** Developers mirror the existing `AppColors.darkHeaderGradient = const LinearGradient(...)` pattern. The `const` works there because it's a static field, not an instance field on a const class.

**How to avoid:** Store gradient endpoint colors as `Color` fields (`headerGradientStart`, `headerGradientEnd`) and expose a `LinearGradient get headerGradient =>` getter. Getters do not need to be const.

**Warning signs:** `The constructor being called isn't a const constructor.` compile error on the ThemeExtension definition.

### Pitfall 2: ThemeExtension Not Registered Before First Build

**What goes wrong:** `Theme.of(context).extension<AppColorTokens>()!` throws a null dereference during tests because the test's `MaterialApp` does not pass `theme: AppTheme.lightTheme`.

**Why it happens:** Widget tests often use bare `MaterialApp()` without theme — the extensions list is empty.

**How to avoid:** Create a `testTheme()` helper that returns `AppTheme.lightTheme` and use it in every widget test `MaterialApp(theme: testTheme(), ...)`. Alternatively, wrap test pumps in a helper that always injects the theme.

**Warning signs:** `Null check operator used on a null value` in widget tests after Phase 15.

### Pitfall 3: AppColors Facade const-ness broken by withValues calls

**What goes wrong:** `AppColors.shadowRaised` uses `const Color(0xFF0F172A).withValues(alpha: 0.03)` — `withValues()` returns a non-const value. After updating to the earthy shadow color `#2C1A0E`, the same `withValues()` pattern is fine as long as the base color is declared `const`. Shadows are `List<BoxShadow> get` (not `const`), so this is already safe.

**Why it happens:** Someone tries to add `const` to a shadow getter after the palette update — `withValues()` is not const.

**How to avoid:** Keep shadow getters as non-const getters (`static List<BoxShadow> get shadowRaised => [...]`). Do not attempt to make them const.

### Pitfall 4: CI Grep Pattern Matches Its Own Definition

**What goes wrong:** The CI grep script scanning for `Color(0x` matches the grep pattern string itself if stored in a shell variable that echoes to stdout.

**Why it happens:** Naive `grep -rn "Color(0x"` in a YAML multi-line run block can self-match if the script is in a file inside the repo.

**How to avoid:** The allowlist exclusion pattern must include `.github/` directory. Use:
```bash
grep -rn "Color(0x" lib/ \
  --include="*.dart" \
  --exclude-dir=".git" \
| grep -v "lib/core/theme/app_theme.dart" \
| grep -v "lib/core/theme/tokens/" \
| grep -v "lib/features/ledger/models/expense_category_model.dart"
```
Scoping to `lib/` only eliminates the self-match risk entirely.

### Pitfall 5: Dark Theme Still Uses Hardcoded Slate Values

**What goes wrong:** `AppTheme.darkTheme` (currently unused in the app) still has `const Color(0xFF0F172A)` and `Color(0xFF1E293B)` inline. The CI lint step will flag these.

**Why it happens:** The dark theme is in the same exempt file (`app_theme.dart`) as the rest of the token definitions — so the CI exemption covers it. But it is still worth noting for clarity.

**How to avoid:** Since dark mode is deferred (DARK-01, DARK-02 are explicitly out of scope), the dark theme body is left as-is. The allowlist covers the entire `app_theme.dart` file. Document this in a comment.

### Pitfall 6: ColorScheme Not Updated to Earthy Palette

**What goes wrong:** `AppTheme.lightTheme` has an explicit `ColorScheme.light(primary: AppColors.primary, ...)` wiring. After updating `AppColors.primary` from mint to terracotta, the `ColorScheme.primary` automatically reflects the change — but other `ColorScheme` fields (`secondary`, `onPrimary`) may be semantically wrong with the new palette.

**Why it happens:** `ColorScheme.onPrimary` is `AppColors.textOnPrimary` which is currently black (`#000000` — designed for neon mint). After switching to terracotta, black on terracotta has 4.57:1 contrast (passes AA) but white has 3.64:1 (passes AA large). The current `textOnPrimary = Color(0xFF000000)` should become `Color(0xFFFFFFFF)` (white) per D-05.

**How to avoid:** Update `textOnPrimary` in AppColors from `#000000` to `#FFFFFF` as part of the palette swap. This is a semantic fix, not just a value change.

---

## Code Examples

### Canonical ThemeExtension Implementation (Verified Pattern)

```dart
// Source: https://api.flutter.dev/flutter/material/ThemeExtension-class.html
// color_tokens.dart

import 'package:flutter/material.dart';

final class AppColorTokens extends ThemeExtension<AppColorTokens> {
  const AppColorTokens({
    required this.primary,
    required this.scaffoldBackground,
    required this.cardSurface,
    required this.inputFill,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.textOnPrimary,
    required this.success,
    required this.successText,
    required this.error,
    required this.errorText,
    required this.disabled,
    required this.disabledText,
    required this.focusRing,
    required this.selectionFill,
    required this.moduleLedger,
    required this.moduleLedgerLight,
    required this.moduleGear,
    required this.moduleGearLight,
    required this.moduleLogistics,
    required this.moduleLogisticsLight,
    required this.moduleVault,
    required this.moduleVaultLight,
    required this.moduleActivity,
    required this.moduleActivityLight,
    required this.moduleMemories,
    required this.moduleMemoriesLight,
    required this.headerGradientStart,
    required this.headerGradientEnd,
  });

  final Color primary;
  final Color scaffoldBackground;
  final Color cardSurface;
  final Color inputFill;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  /// Decorative use only — 2.30:1 contrast, below AA threshold.
  /// Use textSecondary for any functional text label.
  final Color textMuted;
  final Color textOnPrimary;
  /// Bright display green for badges, icons, chip fills (not text).
  final Color success;
  /// Darkened green for balance amount text — 4.51:1 on scaffold, 5.24:1 on card.
  final Color successText;
  /// Bright display red for badges, icons, chip fills.
  final Color error;
  /// Darkened red for balance amount text — 5.33:1 on scaffold, 6.19:1 on card.
  final Color errorText;
  final Color disabled;
  final Color disabledText;
  final Color focusRing;
  final Color selectionFill;
  final Color moduleLedger;
  final Color moduleLedgerLight;
  final Color moduleGear;
  final Color moduleGearLight;
  final Color moduleLogistics;
  final Color moduleLogisticsLight;
  final Color moduleVault;
  final Color moduleVaultLight;
  final Color moduleActivity;
  final Color moduleActivityLight;
  final Color moduleMemories;
  final Color moduleMemoriesLight;
  final Color headerGradientStart;
  final Color headerGradientEnd;

  // Computed getters — NOT fields (LinearGradient is not const-constructable)
  LinearGradient get headerGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [headerGradientStart, headerGradientEnd],
  );

  @override
  AppColorTokens copyWith({
    Color? primary,
    Color? scaffoldBackground,
    Color? cardSurface,
    Color? inputFill,
    Color? border,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? textOnPrimary,
    Color? success,
    Color? successText,
    Color? error,
    Color? errorText,
    Color? disabled,
    Color? disabledText,
    Color? focusRing,
    Color? selectionFill,
    Color? moduleLedger,
    Color? moduleLedgerLight,
    Color? moduleGear,
    Color? moduleGearLight,
    Color? moduleLogistics,
    Color? moduleLogisticsLight,
    Color? moduleVault,
    Color? moduleVaultLight,
    Color? moduleActivity,
    Color? moduleActivityLight,
    Color? moduleMemories,
    Color? moduleMemoriesLight,
    Color? headerGradientStart,
    Color? headerGradientEnd,
  }) => AppColorTokens(
    primary: primary ?? this.primary,
    scaffoldBackground: scaffoldBackground ?? this.scaffoldBackground,
    cardSurface: cardSurface ?? this.cardSurface,
    inputFill: inputFill ?? this.inputFill,
    border: border ?? this.border,
    textPrimary: textPrimary ?? this.textPrimary,
    textSecondary: textSecondary ?? this.textSecondary,
    textMuted: textMuted ?? this.textMuted,
    textOnPrimary: textOnPrimary ?? this.textOnPrimary,
    success: success ?? this.success,
    successText: successText ?? this.successText,
    error: error ?? this.error,
    errorText: errorText ?? this.errorText,
    disabled: disabled ?? this.disabled,
    disabledText: disabledText ?? this.disabledText,
    focusRing: focusRing ?? this.focusRing,
    selectionFill: selectionFill ?? this.selectionFill,
    moduleLedger: moduleLedger ?? this.moduleLedger,
    moduleLedgerLight: moduleLedgerLight ?? this.moduleLedgerLight,
    moduleGear: moduleGear ?? this.moduleGear,
    moduleGearLight: moduleGearLight ?? this.moduleGearLight,
    moduleLogistics: moduleLogistics ?? this.moduleLogistics,
    moduleLogisticsLight: moduleLogisticsLight ?? this.moduleLogisticsLight,
    moduleVault: moduleVault ?? this.moduleVault,
    moduleVaultLight: moduleVaultLight ?? this.moduleVaultLight,
    moduleActivity: moduleActivity ?? this.moduleActivity,
    moduleActivityLight: moduleActivityLight ?? this.moduleActivityLight,
    moduleMemories: moduleMemories ?? this.moduleMemories,
    moduleMemoriesLight: moduleMemoriesLight ?? this.moduleMemoriesLight,
    headerGradientStart: headerGradientStart ?? this.headerGradientStart,
    headerGradientEnd: headerGradientEnd ?? this.headerGradientEnd,
  );

  @override
  AppColorTokens lerp(AppColorTokens? other, double t) {
    if (other is! AppColorTokens) return this;
    return AppColorTokens(
      primary: Color.lerp(primary, other.primary, t)!,
      scaffoldBackground: Color.lerp(scaffoldBackground, other.scaffoldBackground, t)!,
      cardSurface: Color.lerp(cardSurface, other.cardSurface, t)!,
      inputFill: Color.lerp(inputFill, other.inputFill, t)!,
      border: Color.lerp(border, other.border, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      textOnPrimary: Color.lerp(textOnPrimary, other.textOnPrimary, t)!,
      success: Color.lerp(success, other.success, t)!,
      successText: Color.lerp(successText, other.successText, t)!,
      error: Color.lerp(error, other.error, t)!,
      errorText: Color.lerp(errorText, other.errorText, t)!,
      disabled: Color.lerp(disabled, other.disabled, t)!,
      disabledText: Color.lerp(disabledText, other.disabledText, t)!,
      focusRing: Color.lerp(focusRing, other.focusRing, t)!,
      selectionFill: Color.lerp(selectionFill, other.selectionFill, t)!,
      moduleLedger: Color.lerp(moduleLedger, other.moduleLedger, t)!,
      moduleLedgerLight: Color.lerp(moduleLedgerLight, other.moduleLedgerLight, t)!,
      moduleGear: Color.lerp(moduleGear, other.moduleGear, t)!,
      moduleGearLight: Color.lerp(moduleGearLight, other.moduleGearLight, t)!,
      moduleLogistics: Color.lerp(moduleLogistics, other.moduleLogistics, t)!,
      moduleLogisticsLight: Color.lerp(moduleLogisticsLight, other.moduleLogisticsLight, t)!,
      moduleVault: Color.lerp(moduleVault, other.moduleVault, t)!,
      moduleVaultLight: Color.lerp(moduleVaultLight, other.moduleVaultLight, t)!,
      moduleActivity: Color.lerp(moduleActivity, other.moduleActivity, t)!,
      moduleActivityLight: Color.lerp(moduleActivityLight, other.moduleActivityLight, t)!,
      moduleMemories: Color.lerp(moduleMemories, other.moduleMemories, t)!,
      moduleMemoriesLight: Color.lerp(moduleMemoriesLight, other.moduleMemoriesLight, t)!,
      headerGradientStart: Color.lerp(headerGradientStart, other.headerGradientStart, t)!,
      headerGradientEnd: Color.lerp(headerGradientEnd, other.headerGradientEnd, t)!,
    );
  }
}
```

### Canonical Token Values (Earthy Palette)

```dart
// The earthy palette instance — passed to ThemeData.extensions
// AND mirrors of each value are set in AppColors (facade)
static AppColorTokens get earthyLight => const AppColorTokens(
  primary: Color(0xFFCC6B49),           // terracotta
  scaffoldBackground: Color(0xFFF2E8D6), // sand
  cardSurface: Color(0xFFFFF9F2),        // warm white
  inputFill: Color(0xFFF5EDE1),          // sand light
  border: Color(0xFFE5D5C0),            // warm gray
  textPrimary: Color(0xFF2C1A0E),        // dark brown — 13.71:1 on sand
  textSecondary: Color(0xFF6B5B4E),      // warm gray — 5.35:1 on sand
  textMuted: Color(0xFFA89888),          // sand gray — 2.30:1 (decorative only)
  textOnPrimary: Color(0xFFFFFFFF),      // white — 3.64:1 on terracotta (AA large)
  success: Color(0xFF10B981),            // bright emerald (display: badges, icons)
  successText: Color(0xFF047857),        // dark emerald (text: 4.51:1 on sand)
  error: Color(0xFFEF4444),             // bright red (display: badges, icons)
  errorText: Color(0xFFB91C1C),          // dark red (text: 5.33:1 on sand)
  disabled: Color(0xFFE5D5C0),           // warm beige
  disabledText: Color(0xFFA89888),       // sand gray
  focusRing: Color(0xFFCC6B49),          // terracotta
  selectionFill: Color(0xFFF5DDD3),      // terracotta 15%
  moduleLedger: Color(0xFFCC6B49),
  moduleLedgerLight: Color(0xFFECD5C0),  // terracotta 15% on sand
  moduleGear: Color(0xFF7A8C5E),
  moduleGearLight: Color(0xFFE0DAC4),    // olive 15% on sand
  moduleLogistics: Color(0xFF5B7B8C),
  moduleLogisticsLight: Color(0xFFDBD7CA), // dusty teal 15% on sand
  moduleVault: Color(0xFF8B7355),
  moduleVaultLight: Color(0xFFE2D6C2),   // warm bronze 15% on sand
  moduleActivity: Color(0xFFA67C5B),
  moduleActivityLight: Color(0xFFE6D7C3), // caramel 15% on sand
  moduleMemories: Color(0xFF9B7A5C),
  moduleMemoriesLight: Color(0xFFE4D7C3), // desert sand 15% on sand
  headerGradientStart: Color(0xFF2C1A0E),
  headerGradientEnd: Color(0xFF3D2B1E),
);
```

### Updated AppColors Facade (critical value changes)

```dart
// lib/core/theme/app_theme.dart — values to change
// BEFORE -> AFTER (semantic role preserved, value updated)

// Primary: mint -> terracotta
static const Color primary = Color(0xFFCC6B49);          // was 0xFF13EC92
static const Color primaryLight = Color(0xFFF5DDD3);     // was 0xFFD1FAE5 (terracotta 15%)
static const Color primaryDark = Color(0xFFB85E3D);      // was 0xFF0BAE6B

// Accent: same semantic, earthy flavor
static const Color accent = Color(0xFFCC6B49);            // was mint
static const Color accentSecondary = Color(0xFF7A8C5E);   // was teal -> olive

// Backgrounds
static const Color background = Color(0xFFF2E8D6);        // was 0xFFEFF2F7
static const Color surface = Color(0xFFFFF9F2);           // was 0xFFFFFFFF
static const Color surfaceLight = Color(0xFFF5EDE1);      // was 0xFFF1F5F9
static const Color surfaceCard = Color(0xFFFFF9F2);       // was 0xFFFFFFFF

// Text
static const Color textPrimary = Color(0xFF2C1A0E);       // was 0xFF0F172A
static const Color textSecondary = Color(0xFF6B5B4E);     // was 0xFF475569
static const Color textMuted = Color(0xFFA89888);         // was 0xFF94A3B8
static const Color textOnPrimary = Color(0xFFFFFFFF);     // was 0xFF000000 (BLACK!) -- FIX REQUIRED

// Borders
static const Color border = Color(0xFFE5D5C0);            // was 0xFFE2E8F0
static const Color borderLight = Color(0xFFF0E4D3);       // was 0xFFF1F5F9

// Gradients — update endpoint values
static const LinearGradient darkHeaderGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF2C1A0E), Color(0xFF3D2B1E)],  // was slate 900 -> 800
);
```

### CI Lint Step (GitHub Actions)

```yaml
# Add after "find.text() regression warning" step in release_android.yml
- name: Hardcoded color lint
  run: |
    VIOLATIONS=$(grep -rn "Color(0x" lib/ \
      --include="*.dart" \
      | grep -v "lib/core/theme/app_theme.dart" \
      | grep -v "lib/core/theme/tokens/" \
      | grep -v "lib/features/ledger/models/expense_category_model.dart" \
      | wc -l | tr -d ' ')
    if [ "$VIOLATIONS" -gt "0" ]; then
      echo "::error::$VIOLATIONS hardcoded Color(0xFF...) literal(s) found outside the token system."
      grep -rn "Color(0x" lib/ \
        --include="*.dart" \
        | grep -v "lib/core/theme/app_theme.dart" \
        | grep -v "lib/core/theme/tokens/" \
        | grep -v "lib/features/ledger/models/expense_category_model.dart"
      exit 1
    fi
    echo "Hardcoded color lint: PASS ($VIOLATIONS violations)"
```

**Baseline during development:** Phase 15 starts with 15 violations (6 files). The CI step is added last, after all 15 are migrated to AppColors references.

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Global static class (`AppColors.*`) | ThemeExtension + static facade shim | Flutter 3.0+ ThemeExtension stable | Typed tokens survive tree shaking; hot-reload aware; lerp-capable |
| `Theme.of(context).primaryColor` | `Theme.of(context).colorScheme.primary` | Material 3 adoption | Old API still works but deprecated |
| Hardcoded `Colors.X` | AppColors named constants | v1.0 Phase 2 | Already done in this codebase |
| ThemeExtension manually implemented | Code-gen via `theme_tailor` | 2023+ | Code-gen viable at 10+ extensions; overkill here |

**Deprecated/outdated:**
- `primaryColor`, `accentColor`, `backgroundColor` ThemeData top-level fields: deprecated in M3. Use `colorScheme.*` instead. Phase 15 updates `ColorScheme` to match earthy tokens.

---

## Environment Availability

Step 2.6: External dependencies for Phase 15 are Flutter SDK only.

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Flutter SDK | ThemeExtension API | Yes | 3.41.5 (stable) | — |
| Dart SDK | const Color constructors | Yes | ^3.10.1 | — |
| `grep` | CI lint step | Yes (ubuntu-latest) | system | — |
| `wc` | CI lint step | Yes (ubuntu-latest) | system | — |
| `python3` | WCAG verification | Yes (local, not in CI) | local | Use pre-computed matrix in this doc |

No missing dependencies.

---

## Validation Architecture

nyquist_validation is enabled in .planning/config.json.

### Test Framework

| Property | Value |
|----------|-------|
| Framework | flutter_test (SDK) |
| Config file | none (pubspec.yaml `flutter_test` dep) |
| Quick run command | `flutter test test/unit/ --no-pub` |
| Full suite command | `flutter test --no-pub` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| FOUND-01 | ThemeExtension registered and accessible via context.colors | unit | `flutter test test/unit/design_tokens_test.dart -x` | ❌ Wave 0 |
| FOUND-01 | AppColors facade values equal earthy palette constants | unit | `flutter test test/unit/design_tokens_test.dart -x` | ❌ Wave 0 |
| FOUND-01 | context.colors, context.spacing, context.shadows extensions available | unit widget | `flutter test test/unit/design_tokens_test.dart -x` | ❌ Wave 0 |
| FOUND-02 | Contrast ratios for all PASS combinations meet thresholds | unit | `flutter test test/unit/design_tokens_test.dart -x` | ❌ Wave 0 |
| FOUND-02 | successText and errorText are darker variants (not #10B981 / #EF4444) | unit | `flutter test test/unit/design_tokens_test.dart -x` | ❌ Wave 0 |
| FOUND-04 | CI step exits 1 when Color(0xFF...) literal in a non-exempt lib/ file | manual CI | N/A (CI-only check) | ❌ verified in CI only |
| FOUND-01 | No compilation errors — `flutter analyze` passes with 0 errors | static | `flutter analyze` | existing |
| FOUND-01 | Hot restart renders app without RangeError or null assertions from token lookup | smoke | `flutter test test/unit/design_tokens_test.dart::token_registration` | ❌ Wave 0 |

**FOUND-04 test note:** The CI grep step can only be verified end-to-end in CI. Locally, the same grep command can be run manually (`grep -rn "Color(0x" lib/ --include="*.dart" | grep -v ...`) to validate the current count is 0 after migration. No automated Dart test is appropriate for this.

### Sampling Rate

- **Per task commit:** `flutter test test/unit/design_tokens_test.dart --no-pub`
- **Per wave merge:** `flutter test --no-pub`
- **Phase gate:** Full suite green + `flutter analyze` zero errors before `/gsd:verify-work`

### Wave 0 Gaps

- [ ] `test/unit/design_tokens_test.dart` — covers FOUND-01 (token registration, field values, context extension access) and FOUND-02 (contrast ratio assertions for all PASS combinations)
- [ ] No new `conftest` or fixture files needed — tests use `MaterialApp(theme: AppTheme.lightTheme)`

---

## Open Questions

1. **textOnPrimary: white or dark brown on terracotta buttons?**
   - What we know: White (#FFFFFF) on terracotta is 3.64:1 (AA large, passes for 16sp+ bold labels). Dark brown (#2C1A0E) is 4.57:1 (AA body). CONTEXT.md D-05 says "Text on primary: #FFFFFF (white on terracotta)".
   - What's unclear: Whether existing button labels at 16sp bold weight count as "large text" under WCAG 2.1 (they do — 14sp+ bold qualifies).
   - Recommendation: Use white per D-05. It is within the locked decision. Note the 3.64:1 ratio in a code comment.

2. **Module light tints: blend on sand (#F2E8D6) or blend on warm white (#FFF9F2)?**
   - What we know: Module accents appear in card contexts (warm white) and hero banners (sand-ish). 15% opacity on sand yields slightly more muted tints.
   - What's unclear: Which background the planner assumes for the light tint card chip fills.
   - Recommendation: Use the sand-blended variants computed in this document. They are more conservative and universal. If a specific card context needs the warm-white variant, the planner can add both.

3. **ColorScheme update scope in AppTheme.lightTheme**
   - What we know: `ColorScheme.light(...)` wires `primary`, `secondary`, `surface`, `error`, `onPrimary`, `onSurface`. After the palette swap, `onPrimary` changes from black to white (critical — see Pitfall 6).
   - What's unclear: Whether updating ColorScheme (beyond just the AppColors facade change) causes any widget test regression due to theme-dependent text styles.
   - Recommendation: Update ColorScheme wires along with AppColors values. Run `flutter test` after the change before proceeding. This is low risk — 624 tests use mocked providers, not real theme colors.

---

## Project Constraints (from CLAUDE.md)

- **TDD mandatory:** Test file (`design_tokens_test.dart`) must be created BEFORE token implementation. Write RED tests first.
- **Immutability:** ThemeExtension fields are all `final` — immutable by construction. `copyWith` returns new instance. This is already the correct pattern.
- **File size limit:** `app_theme.dart` is currently 519 lines. Adding token wiring will push it toward the 800-line limit. Token classes should live in `lib/core/theme/tokens/` (separate files per D-12), keeping `app_theme.dart` lean.
- **No mutation:** Token instances are `const` where possible. The `AppColorTokens.earthyLight` factory is `static ... get` returning a new instance each call — acceptable because ThemeData.extensions is built once at app startup.
- **Feature-first:** Token files go in `lib/core/theme/tokens/` not in any feature directory.
- **80%+ coverage:** The token system is pure logic (field values + arithmetic in lerp). It is straightforwardly testable. Coverage target is achievable.
- **No hardcoded values:** The token definition file (`color_tokens.dart`) is on the allowlist — it is the canonical source for hardcoded Color literals. All other files use AppColors references.
- **Commit format:** `feat(theme): implement earthy design token system` / `fix(tokens): migrate hardcoded colors in router` / `test(tokens): add WCAG contrast and token registration tests`

---

## Sources

### Primary (HIGH confidence)

- [Flutter ThemeExtension class — api.flutter.dev](https://api.flutter.dev/flutter/material/ThemeExtension-class.html) — copyWith/lerp API, registration pattern, retrieval via Theme.of(context).extension<T>()
- WCAG 2.1 relative luminance formula (IEC 61966-2-1) — contrast ratios computed directly in Python using the spec formula
- `lib/core/theme/app_theme.dart` (local) — all 35 existing AppColors constants and AppTheme builder
- `.github/workflows/release_android.yml` (local) — CI pipeline structure, Phase 14 grep pattern

### Secondary (MEDIUM confidence)

- [apparencekit.dev — Custom Colors in Flutter Theme](https://apparencekit.dev/flutter-tips/flutter-create-custom-color-theme/) — ThemeExtension implementation patterns, BuildContext extension access
- [vibe-studio.ai — Building Design System with Theme Extensions](https://vibe-studio.ai/insights/building-a-reusable-design-system-in-flutter-with-theme-extensions) — multi-extension architecture patterns

### Tertiary (LOW confidence)

- None — all critical claims verified against Flutter SDK docs and direct calculation.

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — ThemeExtension is official Flutter API, no external dependencies
- Architecture: HIGH — two-layer facade pattern verified against codebase structure; token field list derived from existing AppColors API
- Pitfalls: HIGH — LinearGradient const constraint is verified Flutter behavior; CI pattern mirrors Phase 14 implementation
- WCAG matrix: HIGH — exact Python calculation using WCAG 2.1 spec formula, not estimates
- Module light tints: MEDIUM — calculated at 15% opacity on sand per D-14 direction; exact values within Claude's discretion

**Research date:** 2026-03-28
**Valid until:** 2026-06-28 (stable; ThemeExtension API has been stable since Flutter 3.0)
