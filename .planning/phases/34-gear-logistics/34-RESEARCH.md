# Phase 34: Gear & Logistics - Research

**Researched:** 2026-04-05
**Domain:** Flutter visual refresh — GearScreen and LogisticsScreen
**Confidence:** HIGH

## Summary

Both GearScreen and LogisticsScreen are already fully refreshed. Direct inspection of the source files confirms both screens already have `ModuleHeader(useDarkTheme: true)`, `SkeletonLoader` loading states, and `AppColorTokens` throughout. The module header, earthy tokens, and skeleton states that the phase calls for are already in place.

The only actionable work in this phase is a narrow set of hardcoded `Color(0xFF...)` literals in the `accentGradient` parameters of `EmptyStateView` — one in each screen — and a duplicate `subgroup_card.dart` file (dead code) in the logistics widgets directory.

**Primary recommendation:** This phase is an audit + two targeted fixes, not a full refresh. Scope down to: replace the two hardcoded gradient colors with token-derived values, delete `lib/features/logistics/widgets/subgroup_card.dart` (dead code), and write/confirm test coverage. No structural screen changes are needed.

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Gear Screen**
- Dark ModuleHeader ("Gear" + event name subtitle) — if not already present
- Refresh gear item cards with earthy color tokens
- SkeletonLoader loading states (replace any CircularProgressIndicator)
- Keep existing add/claim/filter functionality unchanged

**Logistics Screen**
- Dark ModuleHeader ("Logistics" + event name subtitle) — if not already present
- Refresh sub-group cards with earthy tokens
- SkeletonLoader loading states
- Keep existing create/manage sub-group functionality unchanged

### Claude's Discretion
- All implementation details — this is a token refresh following the established Phase 28-33 pattern

### Deferred Ideas (OUT OF SCOPE)
- None
</user_constraints>

---

## What Already Exists (HIGH confidence)

Direct source inspection confirms the following are already implemented and require no changes:

### GearScreen (`lib/features/gear/screens/gear_screen.dart`)
| Feature | Status | Evidence |
|---------|--------|----------|
| Dark ModuleHeader | DONE | `ModuleHeader(title: 'Gear', subtitle: event.name.toUpperCase(), useDarkTheme: true)` at lines 109-113 |
| ModuleHeader on loading state | DONE | `ModuleHeader(title: 'Gear', useDarkTheme: true)` at line 70 |
| SkeletonLoader on event loading | DONE | `SkeletonLoader.cardList()` at line 71 |
| SkeletonLoader on gear loading | DONE | `loading: SkeletonLoader.cardList` at line 117 |
| No CircularProgressIndicator | DONE | Not present in file |
| AppColorTokens throughout | DONE | All card/chip/badge/icon colors use `AppColorTokens.light.*` |
| FadeInList entrance animation | DONE | `FadeInList` wraps gear item cards at line 242 |
| Scaffold background token | DONE | `AppColorTokens.light.scaffoldBackground` |

### LogisticsScreen (`lib/features/logistics/screens/logistics_screen.dart`)
| Feature | Status | Evidence |
|---------|--------|----------|
| Dark ModuleHeader | DONE | `ModuleHeader(title: 'Logistics', subtitle: event.name.toUpperCase(), useDarkTheme: true)` at lines 102-110 |
| ModuleHeader on loading state | DONE | `ModuleHeader(title: 'Logistics', useDarkTheme: true)` at line 65 |
| SkeletonLoader on event loading | DONE | `SkeletonLoader.groupList()` at line 67 |
| SkeletonLoader on sub-group loading | DONE | `loading: SkeletonLoader.groupList` at line 128 |
| No CircularProgressIndicator | DONE | Not present in file |
| AppColorTokens throughout | DONE | All card/chip/button colors use `AppColorTokens.light.*` |
| FadeInList entrance animation | DONE | `FadeInList` wraps SubGroupCard list at line 207 |
| ModuleHeader action button (Add) | DONE | `+` `IconButton` in `ModuleHeader(actions: [...])` at lines 113-125 |

### GearHeroCard (`lib/features/gear/widgets/gear_hero_card.dart`)
- `AppColorTokens.light.cardSurface`, `.textMuted`, `.textPrimary`, `.border`, `.moduleLedger`, `.error`, `.errorText` — all token-based
- Grain texture overlay present (`assets/textures/grain.png`)
- No hardcoded colors

### SubGroupCard (`lib/features/logistics/widgets/sub_group_card.dart`)
- `AppColorTokens.light.moduleLogistics` top-border accent (3dp, per D-22)
- `AppColorTokens.light.cardSurface`, `.textPrimary`, `.textSecondary`, `.textMuted`, `.border`, `.selectionFill` — all tokens
- No hardcoded colors

---

## Actual Gaps Found (HIGH confidence)

### Gap 1: Hardcoded gradient colors in EmptyStateView accentGradient

**File:** `lib/features/gear/screens/gear_screen.dart`, line 209
```dart
accentGradient: const LinearGradient(
  colors: [Color(0xFF7A8C5E), Color(0xFF96A876)],
),
```
`Color(0xFF7A8C5E)` is olive — there is no `moduleGear` olive token; `moduleGear` is gray-500 (`#6B7280`). This gradient was designed for Gear's earthy character but uses a hardcoded olive. The fix options are:
- Replace with `AppColorTokens.light.moduleGear` (gray, no personality) — technically correct but flat
- Replace with a token-derived olive via a `LinearGradient` using existing `AppColorTokens` values — closest available is none (olive is not a token)
- Keep as-is with a comment explaining it is an intentional design choice (the CI rule blocks `Color(0xFF...)` literals)

**File:** `lib/features/logistics/screens/logistics_screen.dart`, line 181
```dart
accentGradient: const LinearGradient(
  colors: [Color(0xFF5B7B8C), Color(0xFF7B9BAC)],
),
```
`Color(0xFF5B7B8C)` is dusty-teal — likewise no direct token. The nearest token is `moduleLogistics` (gray-500).

**Decision required (Claude's discretion):** Both `accentGradient` values should be replaced. Best approach: use `AppColorTokens.light.moduleGear` / `AppColorTokens.light.moduleLogistics` as the gradient start, and the corresponding light tint (`moduleGearLight` / `moduleLogisticsLight`) as the gradient end. This is token-compliant and consistent with the sub-group card's use of `moduleLogistics`.

Corrected replacements:
```dart
// GearScreen — replace Color(0xFF7A8C5E) / Color(0xFF96A876)
accentGradient: LinearGradient(
  colors: [AppColorTokens.light.moduleGear, AppColorTokens.light.moduleGearLight],
),

// LogisticsScreen — replace Color(0xFF5B7B8C) / Color(0xFF7B9BAC)
accentGradient: LinearGradient(
  colors: [AppColorTokens.light.moduleLogistics, AppColorTokens.light.moduleLogisticsLight],
),
```
Note: `const` must be removed since `LinearGradient` containing `Color` instances is not const-constructable in this pattern.

### Gap 2: Dead-code widget file

`lib/features/logistics/widgets/subgroup_card.dart` — a `SubgroupCard` class (note lowercase 'g') that is NOT the `SubGroupCard` used in `logistics_screen.dart`. The active import in `logistics_screen.dart` is:
```dart
import '../widgets/sub_group_card.dart';
```
`subgroup_card.dart` is an older version and is not imported anywhere in production code. It should be deleted.

### Gap 3: OfflineBanner absent from both screens

Neither `gear_screen.dart` nor `logistics_screen.dart` includes `OfflineBanner`. All refreshed module screens in phases 28-33 (LedgerScreen, SettleUpScreen) include it. The pattern is `const OfflineBanner()` placed as a `SliverToBoxAdapter` or direct child after the `ModuleHeader`.

```dart
import '../../../shared/widgets/offline_banner.dart';
// ...
body: Column(
  children: [
    ModuleHeader(...),
    const OfflineBanner(),  // <-- add this
    Expanded(child: ...),
  ],
),
```

### Gap 4: LogisticsHeroCard widget not used

`lib/features/logistics/widgets/logistics_hero_card.dart` exports `LogisticsHeroCard` but `logistics_screen.dart` has its hero card inlined (`_buildHeroCard` method). `LogisticsHeroCard` is likely dead code from a prior refactor. It can be deleted or the screen updated to use it — both are acceptable. Deleting dead code is cleaner. **Note:** Only delete if confirmed not imported anywhere.

---

## Standard Stack

No new packages needed. All required components are already present:

| Component | Source | Factory/API |
|-----------|--------|-------------|
| `ModuleHeader` | `lib/shared/widgets/module_header.dart` | `ModuleHeader(title, subtitle, useDarkTheme: true)` |
| `SkeletonLoader` (gear) | `lib/shared/widgets/skeleton_loader.dart` | `SkeletonLoader.gearList()` — dedicated gear variant available |
| `SkeletonLoader` (logistics) | `lib/shared/widgets/skeleton_loader.dart` | `SkeletonLoader.groupList()` — already in use |
| `OfflineBanner` | `lib/shared/widgets/offline_banner.dart` | `const OfflineBanner()` |
| `AppColorTokens` | `lib/core/theme/tokens/color_tokens.dart` | `AppColorTokens.light.*` |
| `FadeInList` | `lib/shared/animations/fade_in_list.dart` | Already in both screens |

**Key insight:** `SkeletonLoader.cardList()` is the current factory used by GearScreen's loading state. The `SkeletonLoader.gearList()` factory (checkbox + name + assignee bars) is more semantically correct and should be swapped in — it mirrors the actual gear item card layout.

---

## Architecture Patterns

### Established Phase 28-33 Refresh Pattern

```
Scaffold(
  backgroundColor: AppColorTokens.light.scaffoldBackground,
  body: Column(
    children: [
      ModuleHeader(title: '...', subtitle: event.name.toUpperCase(), useDarkTheme: true),
      const OfflineBanner(),   // <-- present in all 28-33 screens
      Expanded(
        child: dataAsync.when(
          data: (data) => _buildContent(data),
          loading: SkeletonLoader.{content-aware-variant},
          error: (e, _) => ...,
        ),
      ),
    ],
  ),
)
```

Loading-only state (before event loads):
```dart
if (eventAsync.isLoading) {
  return Scaffold(
    backgroundColor: AppColorTokens.light.scaffoldBackground,
    body: Column(
      children: [
        ModuleHeader(title: '...', useDarkTheme: true),
        // OfflineBanner omitted on pre-event loading — consistent with existing screens
        Expanded(child: SkeletonLoader.{variant}()),
      ],
    ),
  );
}
```

### SafeArea Rule

`ModuleHeader._buildDark()` calls `SafeArea(bottom: false)` internally. **Never wrap the screen body in a separate `SafeArea`** when `ModuleHeader` is present. Both GearScreen and LogisticsScreen correctly omit an outer `SafeArea`.

### Token Compliance

All colors must come from `AppColorTokens.light.*`. The two `const LinearGradient(colors: [Color(0xFF...)])` literals in EmptyStateView `accentGradient` parameters are the only remaining violations. `const` must be dropped when using `AppColorTokens` in a `LinearGradient` — `LinearGradient` is not const-constructable.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead |
|---------|-------------|-------------|
| Loading states | Custom shimmer or spinner | `SkeletonLoader.gearList()`, `SkeletonLoader.groupList()` |
| Module header | Custom gradient header row | `ModuleHeader(useDarkTheme: true)` |
| Offline indicator | Custom connectivity widget | `const OfflineBanner()` |
| Staggered entrance | Custom AnimationController | `FadeInList` |
| Empty states | Custom empty placeholder | `EmptyStateView` |

---

## Common Pitfalls

### Pitfall 1: Accidentally breaking gear item `const` declarations
**What goes wrong:** Removing `const` from `LinearGradient` but leaving a `const` modifier on the enclosing widget or method call produces a compile error.
**How to avoid:** When replacing `const LinearGradient(colors: [Color(0xFF...)])` with a token-based gradient, remove `const` from the `LinearGradient` only, and confirm the containing widget (e.g., `EmptyStateView`) does not have a `const` constructor call relying on it.

### Pitfall 2: SkeletonLoader factory name mismatch breaking tests
**What goes wrong:** `SkeletonLoader.cardList()` is the current factory in `gear_screen.dart`. Tests that `find.byType(SkeletonLoader)` will still pass regardless of which factory is used — but `SkeletonLoader.gearList()` is the correct semantic variant.
**How to avoid:** Upgrade `cardList()` to `gearList()` only in the gear-specific loading state. `cardList()` is a backward-compatible delegate — no test expects it by name, so swapping is safe.

### Pitfall 3: Deleting `subgroup_card.dart` without confirming zero import sites
**What goes wrong:** Deleting a file that has an import somewhere causes a compile error.
**How to avoid:** Before deletion, run `grep -r "subgroup_card" lib/` (lowercase, no underscore variant). Confirmed: only `sub_group_card.dart` (with underscore) is imported in `logistics_screen.dart`.

### Pitfall 4: `LogisticsHeroCard` deletion side effects
**What goes wrong:** `LogisticsHeroCard` could theoretically be imported in a test or another widget.
**How to avoid:** Confirm with `grep -r "LogisticsHeroCard\|logistics_hero_card" lib/ test/` before deleting. The `logistics_screen.dart` uses the inlined `_buildHeroCard` method — `LogisticsHeroCard` is likely unused.

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | flutter_test (built-in) + mocktail |
| Config file | none — standard `flutter test` |
| Quick run command | `flutter test test/features/gear_screen_mutations_test.dart test/features/logistics_screen_mutations_test.dart` |
| Full suite command | `flutter test` |

### Existing Tests
Both test files exist and are comprehensive:

**`test/features/gear_screen_mutations_test.dart`** (HIGH confidence — file read)
- `GearScreen — addItem` (2 tests)
- `GearScreen — deleteItem` (1 test)
- `GearScreen — togglePacked` (1 test)
- `GearScreen — priority` (1 test)
- `GearScreen — claim` (1 test)
- `GearScreen — unclaim` (1 test)
- `GearScreen — error handling` (1 test)

**`test/features/logistics_screen_mutations_test.dart`** (HIGH confidence — file read)
- `LogisticsScreen — removeMember` (1 test)
- `LogisticsScreen — deleteSubGroup` (1 test)
- `LogisticsScreen — createSubGroup` (1 test)
- `LogisticsScreen — error handling` (3 tests)

### Phase Requirements → Test Map
| Requirement | Behavior | Test Type | Command | File Exists? |
|-------------|----------|-----------|---------|--------------|
| Gear: no hardcoded colors | `Color(0xFF...)` absent in gear files | lint/grep | `grep -r "Color(0xFF" lib/features/gear/` | N/A — grep check |
| Logistics: no hardcoded colors | `Color(0xFF...)` absent in logistics files | lint/grep | `grep -r "Color(0xFF" lib/features/logistics/` | N/A — grep check |
| Gear: OfflineBanner present | OfflineBanner rendered in gear screen body | widget | add to gear_screen_mutations_test | ❌ Wave 0 |
| Logistics: OfflineBanner present | OfflineBanner rendered in logistics screen body | widget | add to logistics_screen_mutations_test | ❌ Wave 0 |
| All existing mutation tests pass | No regression | widget | `flutter test test/features/gear_screen_mutations_test.dart test/features/logistics_screen_mutations_test.dart` | ✅ |

### Wave 0 Gaps
- [ ] `test/features/gear_screen_mutations_test.dart` — add test: `GearScreen — OfflineBanner renders in body`
- [ ] `test/features/logistics_screen_mutations_test.dart` — add test: `LogisticsScreen — OfflineBanner renders in body`

---

## Code Examples

### Replace hardcoded gradient in GearScreen EmptyStateView
```dart
// Source: color_tokens.dart AppColorTokens.light constants
// Before (line 209 of gear_screen.dart):
accentGradient: const LinearGradient(
  colors: [Color(0xFF7A8C5E), Color(0xFF96A876)],
),

// After:
accentGradient: LinearGradient(
  colors: [AppColorTokens.light.moduleGear, AppColorTokens.light.moduleGearLight],
),
```

### Replace hardcoded gradient in LogisticsScreen EmptyStateView
```dart
// Source: color_tokens.dart AppColorTokens.light constants
// Before (line 181 of logistics_screen.dart):
accentGradient: const LinearGradient(
  colors: [Color(0xFF5B7B8C), Color(0xFF7B9BAC)],
),

// After:
accentGradient: LinearGradient(
  colors: [AppColorTokens.light.moduleLogistics, AppColorTokens.light.moduleLogisticsLight],
),
```

### Add OfflineBanner to GearScreen
```dart
// After the ModuleHeader in the main Scaffold body (gear_screen.dart ~line 107)
// Also add import: '../../../shared/widgets/offline_banner.dart'
body: Column(
  children: [
    ModuleHeader(
      title: 'Gear',
      subtitle: event.name.toUpperCase(),
      useDarkTheme: true,
    ),
    const OfflineBanner(),    // <-- add
    Expanded(
      child: gearAsync.when(...),
    ),
  ],
),
```

### Upgrade SkeletonLoader factory in GearScreen loading state
```dart
// gear_screen.dart line 71 — eventAsync loading state
// Before:
Expanded(child: SkeletonLoader.cardList()),
// After:
Expanded(child: SkeletonLoader.gearList()),

// gear_screen.dart line 117 — gearAsync loading callback
// Before:
loading: SkeletonLoader.cardList,
// After:
loading: SkeletonLoader.gearList,
```

---

## Environment Availability

Step 2.6: SKIPPED — purely code/config changes, no external dependencies.

---

## Open Questions

1. **olive gradient for GearScreen empty state**
   - What we know: `Color(0xFF7A8C5E)` (olive) has design intent — it evokes the gear/outdoors module character. No olive token exists in `AppColorTokens.light`.
   - What's unclear: Should the empty state gradient use the gray `moduleGear` token (correct but flat), or should an olive token be added?
   - Recommendation: Use `moduleGear` / `moduleGearLight` for now — consistent with CLAUDE.md rule "all colors via AppColorTokens." Adding a new token requires a design decision beyond this phase's scope.

2. **`LogisticsHeroCard` cleanup**
   - What we know: `logistics_hero_card.dart` exists but `logistics_screen.dart` uses an inlined `_buildHeroCard` method instead.
   - What's unclear: Is `LogisticsHeroCard` imported anywhere in tests or planned for future reuse?
   - Recommendation: Verify with grep before deleting. If unused, delete to reduce dead code. Not blocking.

---

## Sources

### Primary (HIGH confidence)
- Direct file read: `lib/features/gear/screens/gear_screen.dart` — full 726-line audit
- Direct file read: `lib/features/logistics/screens/logistics_screen.dart` — full 688-line audit
- Direct file read: `lib/features/gear/widgets/gear_hero_card.dart` — token audit
- Direct file read: `lib/features/logistics/widgets/sub_group_card.dart` — token audit
- Direct file read: `lib/shared/widgets/skeleton_loader.dart` — factory inventory
- Direct file read: `lib/core/theme/tokens/color_tokens.dart` — token values
- Direct file read: `test/features/gear_screen_mutations_test.dart` — test coverage baseline
- Direct file read: `test/features/logistics_screen_mutations_test.dart` — test coverage baseline
- Direct file read: `.planning/phases/33-ledger/33-01-PLAN.md` — established refresh pattern

### Secondary (MEDIUM confidence)
- `grep Color(0xFF` output on gear and logistics directories — confirmed two hardcoded violations

---

## Metadata

**Confidence breakdown:**
- Current state audit: HIGH — files read directly, no inference
- Gap identification: HIGH — `grep` confirmed exact line numbers
- Architecture patterns: HIGH — established from Phase 28-33 PLAN.md review
- Token replacement values: HIGH — read from `AppColorTokens.light` source

**Research date:** 2026-04-05
**Valid until:** 2026-05-05 (stable — no external dependencies)
