# Phase 33: Ledger - Research

**Researched:** 2026-04-05
**Domain:** Flutter widget visual refresh — AppColorToken migration, dark ModuleHeader, test repair
**Confidence:** HIGH

## Summary

Phase 33 is a contained visual refresh of the ledger module's 4 screens and key widgets. All business logic, data providers, routing, and Firestore integration are fully functional and production-ready. The only work is styling: replacing any remaining raw color literals or misapplied tokens with the correct `AppColorTokens.light.*` values, and replacing the custom header in `SettleUpScreen` with a `ModuleHeader(useDarkTheme: true)`.

A critical pre-existing defect must be addressed first: `test/features/ledger_test.dart` fails to compile because it calls `LedgerScreen(event: ..., group: ...)` while the current constructor signature is `LedgerScreen(groupId: ..., eventId: ...)`. This blocks the test gate for the phase and must be repaired in Wave 0 before any visual work proceeds.

The screens are mostly already using `AppColorTokens.light.*` correctly. The main gaps are: (1) `SettleUpScreen._buildHeader` uses a bespoke inline header row — not `ModuleHeader`; (2) `SettleUpScreen` loading state uses bare `CircularProgressIndicator` — should use `SkeletonLoader`; (3) several `CircularProgressIndicator` calls remain in `EditExpenseScreen`, `SplitScopeSelector`, and `CategorySelectionStep` that need replacing with `SkeletonLoader.expenseList()` or `SkeletonLoader.card()`. The test file also uses an outdated `LedgerScreen` constructor — needs updating to `groupId`/`eventId` params with `eventDetailProvider` mock.

**Primary recommendation:** Wave 0 repairs the broken test file. Wave 1 applies visual changes (SettleUpScreen header replacement, CircularProgressIndicator replacements, minor token confirmations). Wave 2 updates tests to match new rendering.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

#### Ledger Screen & Expense List
- Dark ModuleHeader ("Ledger" + event name subtitle)
- Refresh ExpenseCard with earthy color tokens — keep existing card-style rows
- Refresh LedgerHeroCard with earthy tokens — keep YOUR BALANCE + EVENT TOTAL hero layout
- Keep EmptyStateView with "No expenses yet" + "Add Expense" CTA

#### Add/Edit Expense Forms
- Keep existing 3-step flow (category -> amount -> split) with earthy token refresh
- Dark ModuleHeader ("Add Expense" / "Edit Expense")
- Refresh AmountInputSection styling with tokens — keep existing OMR input behavior
- Refresh SplitScopeSelector styling — keep global/subgroup/custom functionality

#### Settle Up Screen
- Refresh with earthy tokens — keep existing optimization display (SettlementSummaryCard + SettlementRow)
- Dark ModuleHeader ("Settle Up" + event name subtitle)
- Keep existing settle button with earthy primary color
- Refresh MemberBalancesSection with earthy tokens — keep grid layout

### Claude's Discretion
- Exact spacing and padding within earthy token system
- Animation timing for any entrance effects
- Loading/error state presentation details
- Widget-level token mapping decisions

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope
</user_constraints>

## Standard Stack

Already installed. No new dependencies required for this phase.

### Core (already in pubspec.yaml)
| Library | Purpose | Notes |
|---------|---------|-------|
| `AppColorTokens.light` (in-project) | All color values | Access via `AppColorTokens.light.primary` etc. |
| `AppShadowTokens.standard` (in-project) | Box shadows | `raised`, `floating` variants |
| `ModuleHeader` (shared widget) | Dark/light header | `useDarkTheme: true` gives gray-900 gradient |
| `SkeletonLoader` (shared widget) | Loading states | `.expenseList()`, `.card()` factories |
| `AnimatedCurrencyText` (shared widget) | Animated balance display | Already used in LedgerHeroCard |
| `flutter_animate ^4.5.0` | Entrance animations | `.fadeIn()`, `.slideY()`, `.slideX()` |

**Installation:** No new packages needed.

## Architecture Patterns

### Established Module Refresh Pattern (Phase 28–32)

Every module screen follows this exact structure, verified across phases 28-32:

```
Scaffold(
  key: [ModuleKeys.screen],
  backgroundColor: AppColorTokens.light.scaffoldBackground,
  body: Column([
    ModuleHeader(title: '...', subtitle: event.name.toUpperCase(), useDarkTheme: true),
    OfflineBanner(),
    Expanded(child: [content]),
  ])
)
```

For scrollable content, `CustomScrollView` with `SliverToBoxAdapter` wrapping `ModuleHeader` at top.

### LedgerScreen (ALREADY CORRECT — no header work needed)

`LedgerScreen` already uses `ModuleHeader(useDarkTheme: true)` with `subtitle: event.name.toUpperCase()`. Confirmed from codebase. No header replacement needed.

### SettleUpScreen (NEEDS header replacement)

Current `SettleUpScreen._buildHeader()` is a custom inline row with a back button and plain `Text('Settle Up')`. This must be replaced with:
```dart
ModuleHeader(
  title: 'Settle Up',
  subtitle: event.name.toUpperCase(),
  useDarkTheme: true,
)
```
The `SafeArea` wrapping `_buildHeader()` must also be removed — `ModuleHeader._buildDark()` already calls `SafeArea(bottom: false)` internally.

### AddExpenseScreen (NEEDS header replacement)

`AddExpenseScreen._buildStepHeader()` renders an inline `Container` with `Row(IconButton, Text, SizedBox)` — not a `ModuleHeader`. Per locked decisions, this needs replacing with:
```dart
ModuleHeader(
  title: 'Add Expense',
  useDarkTheme: true,
)
```
The step navigation (back/close icon, step label, `DotStepIndicator`) should remain below the `ModuleHeader` as a sub-header row. The `ModuleHeader` provides the dark gradient header; the step controls remain separate below it.

### EditExpenseScreen (NEEDS header replacement)

Same pattern — has a custom inline header. Replace with:
```dart
ModuleHeader(
  title: 'Edit Expense',
  useDarkTheme: true,
)
```

### Token Access Pattern

All widgets use the singleton `AppColorTokens.light` directly (not via `Theme.of(context).extension<AppColorTokens>()`). This is the established project pattern — do not change it.

```dart
// CORRECT (project pattern)
color: AppColorTokens.light.textSecondary

// DO NOT use (even though ThemeExtension supports it)
color: Theme.of(context).extension<AppColorTokens>()!.textSecondary
```

### Token Mapping for Ledger Module

| Visual Role | Token | Hex |
|-------------|-------|-----|
| Module accent (teal) | `moduleLedger` | #0D7B74 |
| Module light tint | `moduleLedgerLight` | #E6F5F3 |
| Primary CTA | `primary` | #0D7B74 |
| Primary gradient CTA | `primaryGradient` | #0D7B74 → #0A6B65 |
| Card background | `cardSurface` | #F8F9FA |
| Scaffold background | `scaffoldBackground` | #FFFFFF |
| Amount positive | `successText` | #047857 |
| Amount negative | `errorText` | #B91C1C |
| Secondary text | `textSecondary` | #6B7280 |
| Muted labels | `textMuted` | #9CA3AF |
| Input fill (forms) | `inputFill` | #F3F4F6 |
| Warm input fill | `inputFillWarm` | #F5EDE1 |
| Warm focus border | `focusBorderWarm` | #CC6B49 |

### Loading State Pattern

Replace all bare `CircularProgressIndicator()` in ledger screens/widgets with `SkeletonLoader`:

| Location | Current | Replace with |
|----------|---------|--------------|
| `SettleUpScreen` loading | `CircularProgressIndicator()` | `SkeletonLoader.expenseList()` |
| `EditExpenseScreen` loading | `CircularProgressIndicator()` | `SkeletonLoader.expenseList()` |
| `CategorySelectionStep` loading | `CircularProgressIndicator()` | `SkeletonLoader.card()` |
| `SplitScopeSelector` loading | `CircularProgressIndicator()` | `SkeletonLoader.card()` |
| `AddExpenseScreen` split step loading | `CircularProgressIndicator()` | `SkeletonLoader.card()` |

Exception: The receipt upload spinner in `ReceiptPickerSection` uses a `CircularProgressIndicator` inside a small icon button — keep that as-is (it's a correct micro-indicator, not a full-page loading state).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead |
|---------|-------------|-------------|
| Dark gradient header | Custom Container with gradient + SafeArea | `ModuleHeader(useDarkTheme: true)` |
| Animated currency counter | Custom AnimationController + Tween | `AnimatedCurrencyText` (already exists in shared/widgets/) |
| Loading skeleton | Custom grey boxes | `SkeletonLoader.expenseList()` or `.card()` |
| Box shadows | Manual `BoxShadow` lists | `AppShadowTokens.standard.raised` / `.floating` |
| Step navigation animations | Custom `AnimationController` | `SharedAxisTransition` + `PageTransitionSwitcher` (already used in AddExpenseScreen) |

## Common Pitfalls

### Pitfall 1: Removing `SafeArea` from SettleUpScreen body
**What goes wrong:** When replacing `_buildHeader()` with `ModuleHeader`, the existing `SafeArea` wrapping the Column body remains. `ModuleHeader._buildDark()` already calls `SafeArea(bottom: false)` internally — double-wrapping causes extra top padding.
**How to avoid:** Remove the outer `SafeArea` from `SettleUpScreen.build()` when adding `ModuleHeader`. The `Scaffold` body does not need an explicit `SafeArea` — `ModuleHeader` handles it.
**Warning signs:** Header appears with extra padding at top on devices with notch.

### Pitfall 2: Breaking AddExpenseScreen step navigation
**What goes wrong:** The `_buildStepHeader()` handles both the back/close navigation and the `DotStepIndicator`. If the whole method is naively replaced with just `ModuleHeader`, the step controls disappear.
**How to avoid:** Add `ModuleHeader(title: 'Add Expense', useDarkTheme: true)` as a new top element, then keep the existing step controls row (back/close icon + step label + `DotStepIndicator`) directly below it. The module header provides the dark band; the step bar remains separate.
**Warning signs:** `DotStepIndicator` is missing from the build; back button doesn't work.

### Pitfall 3: test/features/ledger_test.dart compile failure blocks all tests
**What goes wrong:** `ledger_test.dart` calls `LedgerScreen(event: mockEvent, group: mockGroup)` — `LedgerScreen` constructor no longer has these parameters. Compilation failure means the entire test binary fails.
**Why it happens:** `LedgerScreen` was refactored to take `groupId` + `eventId` (GoRouter pattern), but the test file was never updated.
**How to avoid:** Fix this in Wave 0 before any other work. The test fix requires: update constructor calls to `LedgerScreen(groupId: 'group-1', eventId: 'evt-123')`, add `eventDetailProvider(_eventRef)` override to each test's `ProviderScope`, and remove the `eventUnifiedLedgerProvider` override (no longer exists).
**Warning signs:** `flutter test test/features/ledger_test.dart` fails with compile errors.

### Pitfall 4: textMuted on functional labels
**What goes wrong:** `AppColorTokens.light.textMuted` (#9CA3AF) fails WCAG AA at 2.86:1 on white backgrounds. Several overline labels (`'TRANSACTIONS'`, `'YOUR ACTIONS'`, etc.) use `textMuted`.
**How to avoid:** Per post-generation checklist rule — `textMuted` is decorative only. Use `textSecondary` (#6B7280, 5.74:1) for any overline that contains actionable information. Decorative separators and purely ornamental labels may keep `textMuted`.
**Warning signs:** Section headers that a user needs to read (e.g., `'YOUR ACTIONS'`) use `textMuted`.

### Pitfall 5: Hardcoded color literals in SettleUpScreen confirm sheet
**What goes wrong:** `SettleUpScreen._confirmPayment()` modal sheet uses `Colors.transparent` and `Colors.white` directly. These should use token equivalents.
**How to avoid:** `Colors.transparent` is acceptable for `backgroundColor: Colors.transparent` on modal sheets (standard Flutter pattern). `Colors.white` for `foregroundColor` on gradient buttons is also acceptable — it's a contrast constant, not a semantic color choice. Flag these as intentional, not bugs.

### Pitfall 6: Mutable Set used in AddExpenseScreen state
**What goes wrong:** `final Set<String> _customSplitParticipants = {};` is mutated in-place via `.clear()` and `.addAll()`. This violates the project immutability rule.
**How to avoid:** This is pre-existing code — Phase 33 scope is visual refresh only. Do not fix this during the visual pass; it would expand scope. Note it exists; leave it.

## Code Examples

### Dark ModuleHeader — Settle Up (canonical replacement)
```dart
// Replace _buildHeader() and SafeArea wrapping with:
ModuleHeader(
  title: 'Settle Up',
  subtitle: event.name.toUpperCase(),
  useDarkTheme: true,
),
// Source: lib/shared/widgets/module_header.dart + Phase 28-32 pattern
```

### Dark ModuleHeader — Add/Edit Expense
```dart
// Replace _buildStepHeader() top portion with ModuleHeader, keep DotStepIndicator below:
Column(
  children: [
    ModuleHeader(title: 'Add Expense', useDarkTheme: true),
    // Step controls remain:
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(icon: Icon(...), onPressed: ...),
              Text(['ENTER AMOUNT', ...][_currentStep], style: ...),
              const SizedBox(width: 48),
            ],
          ),
          DotStepIndicator(stepCount: 3, currentStep: _currentStep, ...),
        ],
      ),
    ),
  ],
)
// Source: Phase 28-32 pattern + existing AddExpenseScreen step structure
```

### LedgerHeroCard CTA buttons — earthy primary gradient
```dart
// Add Expense button (primary gradient, not plain ElevatedButton):
Container(
  decoration: BoxDecoration(
    gradient: AppColorTokens.light.primaryGradient,
    borderRadius: BorderRadius.circular(16),
    boxShadow: [
      BoxShadow(
        color: AppColorTokens.light.primary.withValues(alpha: 0.3),
        blurRadius: 12,
        offset: const Offset(0, 4),
      ),
    ],
  ),
  child: ElevatedButton.icon(
    onPressed: onAddExpense,
    icon: const Icon(Iconsax.add, size: 18),
    label: const Text('Add Expense'),
    style: ElevatedButton.styleFrom(
      backgroundColor: Colors.transparent,
      foregroundColor: AppColorTokens.light.textOnPrimary,
      shadowColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
  ),
),
// Source: SettlementSummaryCard.build() — same pattern already in use
```

### Test fix — LedgerScreen constructor
```dart
// OLD (broken):
child: MaterialApp(home: LedgerScreen(event: mockEvent, group: mockGroup)),

// NEW (correct):
ProviderScope(
  overrides: [
    eventDetailProvider(_eventRef).overrideWith(
      (ref) => Stream.value(mockEvent),
    ),
    eventExpensesProvider(_eventRef).overrideWith(
      (ref) => Stream.value(expenses),
    ),
    eventSettlementsProvider(_eventRef).overrideWith(
      (ref) => Stream.value(settlements),
    ),
    eventSubGroupsProvider(_eventRef).overrideWith(
      (ref) => Stream.value(subGroups),
    ),
  ],
  child: MaterialApp(
    home: LedgerScreen(groupId: _mockGroupId, eventId: _mockEventId),
  ),
),
// Source: LedgerScreen constructor in ledger_screen.dart lines 60-65
```

## State of the Art

| Old Approach | Current Approach | Impact |
|--------------|------------------|--------|
| Custom inline header rows | `ModuleHeader(useDarkTheme: true)` (Phase 28+) | Consistent dark gradient across all modules |
| Bare `CircularProgressIndicator` | `SkeletonLoader.*` | Maintains layout during load (no content jump) |
| `ElevatedButton` without gradient container | `Container(gradient) + ElevatedButton(backgroundColor: transparent)` | Earthy primary gradient on CTAs |
| `LedgerScreen(event: ..., group: ...)` (old) | `LedgerScreen(groupId: ..., eventId: ...)` (current) | GoRouter-compatible deep linking |

**Deprecated/outdated in ledger module:**
- `SettleUpScreen._buildHeader()`: Custom inline header — replaced by `ModuleHeader`
- `AddExpenseScreen._buildStepHeader()` top section: Custom gradient-less header area — add `ModuleHeader` above
- `EditExpenseScreen` header: Same pattern as AddExpenseScreen
- `CircularProgressIndicator` as full-screen loading: Replaced by `SkeletonLoader` across all modules since Phase 28

## Open Questions

1. **SplitScopeSelector complexity**
   - What we know: `split_scope_selector.dart` is the largest widget in the module (~16,000 chars per CONTEXT.md). It has its own internal `CircularProgressIndicator`.
   - What's unclear: The CONTEXT.md says "keep global/subgroup/custom functionality" — should we replace the internal spinner with `SkeletonLoader.card()` or leave it?
   - Recommendation: Replace with `SkeletonLoader.card()` for consistency. It's a loading state, not a micro-indicator. Low-risk change scoped to one line.

2. **MemberBalancesSection usage**
   - What we know: `MemberBalancesSection` is defined in `lib/features/ledger/widgets/member_balances_section.dart` but is NOT imported by `LedgerScreen`. After Phase 28+, it was removed from the timeline view. CONTEXT.md says "refresh MemberBalancesSection with earthy tokens" but the widget is not currently rendered in any screen.
   - What's unclear: Is this widget still used elsewhere, or is it orphaned?
   - Recommendation: Refresh its token usage regardless (it exists and may be rendered via SettleUpScreen's content). Do not add it to LedgerScreen if it isn't there — that would be out of scope.

## Environment Availability

Step 2.6: SKIPPED — phase is purely code/styling changes with no external dependencies beyond the project's own code. Flutter SDK already confirmed available (`flutter test` runs successfully).

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | flutter_test (Flutter SDK) + mocktail |
| Config file | none — standard `flutter test` |
| Quick run command | `flutter test test/features/ledger_test.dart` |
| Full suite command | `flutter test` |

### Phase Requirements → Test Map

| Behavior | Test Type | Automated Command | File Exists? |
|----------|-----------|-------------------|-------------|
| LedgerScreen renders ModuleHeader dark gradient | widget | `flutter test test/features/ledger_test.dart --name "renders event name"` | Yes (needs constructor fix) |
| LedgerScreen shows expense list | widget | `flutter test test/features/ledger_test.dart --name "renders expenses"` | Yes (needs constructor fix) |
| LedgerScreen empty state | widget | `flutter test test/features/ledger_test.dart --name "empty state"` | Yes (needs constructor fix) |
| OMR 3 decimal formatting | widget | `flutter test test/features/ledger_test.dart --name "3 decimal"` | Yes (needs constructor fix) |
| LedgerHeroCard CTA buttons present | widget | `flutter test test/features/ledger_test.dart` | Wave 0 gap |
| SettleUpScreen ModuleHeader "Settle Up" | widget | `flutter test test/features/ledger_test.dart` | Wave 0 gap |

### Sampling Rate
- **Per task commit:** `flutter test test/features/ledger_test.dart`
- **Per wave merge:** `flutter test`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `test/features/ledger_test.dart` — fix constructor calls from `(event, group)` to `(groupId, eventId)` with `eventDetailProvider` mock
- [ ] `test/features/ledger_test.dart` — add test: `SettleUpScreen renders ModuleHeader with 'Settle Up' title`
- [ ] `test/features/ledger_test.dart` — add test: `LedgerHeroCard shows Add Expense and Settle Up buttons`

## Sources

### Primary (HIGH confidence)
- Direct codebase inspection — all 4 screens read in full
- `lib/features/ledger/widgets/*.dart` — all 15 widget files inspected
- `lib/shared/widgets/module_header.dart` — `ModuleHeader` API confirmed
- `lib/core/theme/tokens/color_tokens.dart` — full token palette confirmed
- `test/features/ledger_test.dart` — compile failures confirmed via `flutter test`
- Phase 32 PLAN.md — canonical pattern for ModuleHeader replacement tasks

### Secondary (MEDIUM confidence)
- Phase 28-31 patterns observed from CONTEXT.md + STATE.md history

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — no new packages, all tools confirmed in codebase
- Architecture: HIGH — patterns verified from Phase 28-32 implementations in codebase
- Pitfalls: HIGH — compile errors confirmed by running `flutter test`, SafeArea trap confirmed by reading `ModuleHeader._buildDark()`
- Token mapping: HIGH — all tokens read from `color_tokens.dart` directly

**Research date:** 2026-04-05
**Valid until:** 2026-05-05 (stable palette — no external dependencies)
