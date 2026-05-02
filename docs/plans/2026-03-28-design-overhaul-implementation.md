# Clean Slate Design Overhaul — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Swap the earthy palette (terracotta/sand/olive) to a monochrome neutral + teal (`#0D7B74`) design system, update typography weights/sizes, tighten border radii, and update shared widget visuals.

**Architecture:** Value swap on the existing Phase 15 token infrastructure. `AppColorTokens`, `AppSpacingTokens`, and `AppShadowTokens` ThemeExtension classes keep their structure — only the hex values, sizes, and weights change. The `AppColors` facade (895 references) updates in lockstep. Three shared widgets need structural edits (AppTabBar gradient→solid, LoadingButton gradient→solid, ModuleHeader default variant background).

**Tech Stack:** Flutter, Dart, ThemeExtension, Plus Jakarta Sans (Google Fonts), mocktail (tests)

**Design doc:** `docs/plans/2026-03-28-design-overhaul-clean-slate.md`

---

### Task 1: Update Design Token Test Expectations (RED)

Update test assertions to expect the new palette values. Tests will fail until implementation catches up.

**Files:**
- Modify: `test/unit/design_tokens_test.dart`

**Step 1: Update color token test assertions**

Change lines 62-67 (primary test):
```dart
test('light.primary equals teal #0D7B74', () {
  expect(
    AppColorTokens.light.primary,
    equals(const Color(0xFF0D7B74)),
  );
});
```

Change lines 69-74 (scaffold test):
```dart
test('light.scaffoldBackground equals white #FFFFFF', () {
  expect(
    AppColorTokens.light.scaffoldBackground,
    equals(const Color(0xFFFFFFFF)),
  );
});
```

Update immutability test at line 111:
```dart
expect(original.primary, equals(const Color(0xFF0D7B74)));
```

Update lerp test at line 149:
```dart
expect(lerped.primary, equals(AppColorTokens.light.primary));
```

Update `_testTheme()` at line 44:
```dart
AppColorTokens.light,
```

Update extension registration test at line 289:
```dart
expect(tokens.primary, equals(const Color(0xFF0D7B74)));
```

Update context.colors test at line 328:
```dart
expect(colors.primary, equals(const Color(0xFF0D7B74)));
```

**Step 2: Update spacing token test assertions**

Change lines 226-229 (radii test):
```dart
test('standard has correct border radii', () {
  final s = AppSpacingTokens.standard;
  expect(s.radiusSmall, equals(8.0));
  expect(s.radiusMedium, equals(12.0));
  expect(s.radiusLarge, equals(16.0));
});
```

**Step 3: Update shadow token test assertions**

Change lines 253-260 (shadow base color test):
```dart
test('raised shadows use neutral gray-900 base #111827', () {
  final raised = AppShadowTokens.standard.raised;
  for (final shadow in raised) {
    expect(shadow.color.r, closeTo(const Color(0xFF111827).r, 0.01));
    expect(shadow.color.g, closeTo(const Color(0xFF111827).g, 0.01));
    expect(shadow.color.b, closeTo(const Color(0xFF111827).b, 0.01));
  }
});
```

**Step 4: Update WCAG contrast tests**

Replace lines 363-401 with new palette pairs:
```dart
group('WCAG AA contrast compliance', () {
  const scaffold = Color(0xFFFFFFFF); // white scaffold

  test('primary text (#111827) on scaffold (#FFFFFF) >= 4.5:1', () {
    const textPrimary = Color(0xFF111827);
    final ratio = _contrastRatio(textPrimary, scaffold);
    expect(ratio, greaterThanOrEqualTo(4.5),
        reason: 'Primary text contrast: ${ratio.toStringAsFixed(2)}:1');
  });

  test('secondary text (#6B7280) on scaffold (#FFFFFF) >= 4.5:1', () {
    const textSecondary = Color(0xFF6B7280);
    final ratio = _contrastRatio(textSecondary, scaffold);
    expect(ratio, greaterThanOrEqualTo(4.5),
        reason: 'Secondary text contrast: ${ratio.toStringAsFixed(2)}:1');
  });

  test('successText (#047857) on scaffold (#FFFFFF) >= 4.5:1', () {
    const successText = Color(0xFF047857);
    final ratio = _contrastRatio(successText, scaffold);
    expect(ratio, greaterThanOrEqualTo(4.5),
        reason: 'Success text contrast: ${ratio.toStringAsFixed(2)}:1');
  });

  test('errorText (#B91C1C) on scaffold (#FFFFFF) >= 4.5:1', () {
    const errorText = Color(0xFFB91C1C);
    final ratio = _contrastRatio(errorText, scaffold);
    expect(ratio, greaterThanOrEqualTo(4.5),
        reason: 'Error text contrast: ${ratio.toStringAsFixed(2)}:1');
  });

  test('white (#FFFFFF) on teal (#0D7B74) >= 4.5:1 (AA normal text)', () {
    const white = Color(0xFFFFFFFF);
    const teal = Color(0xFF0D7B74);
    final ratio = _contrastRatio(white, teal);
    expect(ratio, greaterThanOrEqualTo(4.5),
        reason: 'White on teal contrast: ${ratio.toStringAsFixed(2)}:1');
  });
});
```

**Step 5: Update AppColors facade tests**

Replace lines 406-426:
```dart
group('AppColors facade', () {
  test('AppColors.primary equals teal #0D7B74', () {
    expect(AppColors.primary, equals(const Color(0xFF0D7B74)));
  });

  test('AppColors.textOnPrimary equals white #FFFFFF', () {
    expect(AppColors.textOnPrimary, equals(const Color(0xFFFFFFFF)));
  });

  test('AppColors.background equals white #FFFFFF', () {
    expect(AppColors.background, equals(const Color(0xFFFFFFFF)));
  });

  test('AppColors.textPrimary equals gray-900 #111827', () {
    expect(AppColors.textPrimary, equals(const Color(0xFF111827)));
  });

  test('AppColors.surface equals cool gray #F8F9FA', () {
    expect(AppColors.surface, equals(const Color(0xFFF8F9FA)));
  });
});
```

**Step 6: Run tests to verify they fail**

Run: `flutter test test/unit/design_tokens_test.dart`
Expected: Multiple FAIL (old values don't match new expectations)

**Step 7: Commit**

```bash
git add test/unit/design_tokens_test.dart
git commit -m "test: update design token assertions for clean slate palette"
```

---

### Task 2: Update Color Tokens (GREEN)

Swap all 30 color values in the token file. Rename `earthyLight` → `light`.

**Files:**
- Modify: `lib/core/theme/tokens/color_tokens.dart`

**Step 1: Rename and update the static instance**

Replace the `earthyLight` instance (lines 145-177) with:
```dart
static const AppColorTokens light = AppColorTokens(
  primary: Color(0xFF0D7B74),
  scaffoldBackground: Color(0xFFFFFFFF),
  cardSurface: Color(0xFFF8F9FA),
  inputFill: Color(0xFFF3F4F6),
  border: Color(0xFFE5E7EB),
  textPrimary: Color(0xFF111827),
  textSecondary: Color(0xFF6B7280),
  textMuted: Color(0xFF9CA3AF),
  textOnPrimary: Color(0xFFFFFFFF),
  success: Color(0xFF10B981),
  successText: Color(0xFF047857),
  error: Color(0xFFEF4444),
  errorText: Color(0xFFB91C1C),
  disabled: Color(0xFFE5E7EB),
  disabledText: Color(0xFF9CA3AF),
  focusRing: Color(0xFF0D7B74),
  selectionFill: Color(0xFFE6F5F3),
  moduleLedger: Color(0xFF0D7B74),
  moduleLedgerLight: Color(0xFFE6F5F3),
  moduleGear: Color(0xFF6B7280),
  moduleGearLight: Color(0xFFF3F4F6),
  moduleLogistics: Color(0xFF6B7280),
  moduleLogisticsLight: Color(0xFFF3F4F6),
  moduleVault: Color(0xFF6B7280),
  moduleVaultLight: Color(0xFFF3F4F6),
  moduleActivity: Color(0xFF6B7280),
  moduleActivityLight: Color(0xFFF3F4F6),
  moduleMemories: Color(0xFF6B7280),
  moduleMemoriesLight: Color(0xFFF3F4F6),
  headerGradientStart: Color(0xFF111827),
  headerGradientEnd: Color(0xFF1F2937),
);
```

**Step 2: Update doc comments**

Update the class-level doc comment and field comments to reference "neutral + teal" instead of "warm earthy palette." Key changes:
- Line 1 class doc: `/// Typed color token set for the neutral + teal palette.`
- Line 9: `/// Use [AppColorTokens.light] for the default light palette instance.`
- Line 45: `/// Teal — primary action color`
- Line 48: `/// White — scaffold/page background (#FFFFFF)`
- Line 51: `/// Cool gray — card surface (#F8F9FA)`
- Line 54: `/// Gray-100 — input fill (#F3F4F6)`
- Line 57: `/// Gray-200 — dividers and borders (#E5E7EB)`
- Line 60: `/// Gray-900 — primary body text, 17.15:1 on white (#111827)`
- Line 63: `/// Gray-500 — secondary text, 5.03:1 on white (#6B7280)`
- Line 66: `/// Decorative use only — 2.86:1 contrast, below AA.`
- Line 69: `/// White on teal — 5.12:1 AA (#FFFFFF)`

**Step 3: Run tests to verify color assertions pass**

Run: `flutter test test/unit/design_tokens_test.dart --name "AppColorTokens"`
Expected: PASS (new values match new expectations)

**Step 4: Commit**

```bash
git add lib/core/theme/tokens/color_tokens.dart
git commit -m "feat: swap color tokens from earthy to neutral + teal palette"
```

---

### Task 3: Update Shadow Tokens (GREEN)

Swap base shadow color from warm brown to neutral gray-900.

**Files:**
- Modify: `lib/core/theme/tokens/shadow_tokens.dart`

**Step 1: Update shadow colors and opacities**

Replace `Color(0xFF2C1A0E)` with `Color(0xFF111827)` in all 4 positions (lines 28, 33, 40, 45).

Update raised shadow opacities for white background:
- Layer 1: `alpha: 0.03` → `alpha: 0.04`
- Layer 2: keep `alpha: 0.02`

Update floating shadow opacities:
- Layer 1: `alpha: 0.06` → `alpha: 0.07`
- Layer 2: `alpha: 0.03` → keep `alpha: 0.03`

Update doc comment (line 7): `/// Typed shadow token set — elevation shadow levels using neutral gray-900 base.`
Update comment (line 23): `/// Default standard shadow instance using neutral gray-900 base (#111827).`

**Step 2: Run shadow tests**

Run: `flutter test test/unit/design_tokens_test.dart --name "AppShadowTokens"`
Expected: PASS

**Step 3: Commit**

```bash
git add lib/core/theme/tokens/shadow_tokens.dart
git commit -m "feat: update shadow tokens to neutral gray-900 base"
```

---

### Task 4: Update Spacing Tokens — Radii (GREEN)

Tighten border radii from 12/16/20 to 8/12/16.

**Files:**
- Modify: `lib/core/theme/tokens/spacing_tokens.dart`

**Step 1: Update radii values and comments**

Change the `.standard` instance (lines 57-69):
- `radiusSmall: 12,` → `radiusSmall: 8,`
- `radiusMedium: 16,` → `radiusMedium: 12,`
- `radiusLarge: 20,` → `radiusLarge: 16,`

Update doc comments:
- Line 44: `/// Small border radius — 8dp (chips, tags)`
- Line 47: `/// Medium border radius — 12dp (buttons, inputs)`
- Line 50: `/// Large border radius — 16dp (cards, sheets)`

**Step 2: Run spacing tests**

Run: `flutter test test/unit/design_tokens_test.dart --name "AppSpacingTokens"`
Expected: PASS

**Step 3: Commit**

```bash
git add lib/core/theme/tokens/spacing_tokens.dart
git commit -m "feat: tighten border radii from 12/16/20 to 8/12/16"
```

---

### Task 5: Update AppColors Facade + AppTheme

Sync the `AppColors` static constants and `AppTheme` with the new token values. Update typography weights and sizes.

**Files:**
- Modify: `lib/core/theme/app_theme.dart`

**Step 1: Update AppColors static color constants**

Replace all earthy hex values with neutral + teal equivalents. Key changes:

```dart
class AppColors {
  static const Color mint = Color(0xFF0D7B74); // teal
  static const Color rose = Color(0xFFEF4444); // unchanged
  static const Color emerald = Color(0xFF10B981); // unchanged
  static const Color amber = Color(0xFFF59E0B); // unchanged
  static const Color indigo = Color(0xFF6B7280); // gray-500
  static const Color sky = Color(0xFF6B7280); // gray-500

  static const Color primary = Color(0xFF0D7B74);
  static const Color primaryLight = Color(0xFFE6F5F3); // teal-50
  static const Color primaryDark = Color(0xFF0A6B65); // dark teal

  static const Color accent = Color(0xFF0D7B74);
  static const Color accentSecondary = Color(0xFF6B7280); // gray-500
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFEF4444);
  static const Color info = Color(0xFF6B7280);
  static const Color success = Color(0xFF10B981);

  static const Color background = Color(0xFFFFFFFF);
  static const Color surface = Color(0xFFF8F9FA);
  static const Color surfaceLight = Color(0xFFF3F4F6);
  static const Color surfaceCard = Color(0xFFF8F9FA);
  static const Color surfaceDark = Color(0xFF111827);

  static const Color textPrimary = Color(0xFF111827);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color textMuted = Color(0xFF9CA3AF);
  static const Color textOnPrimary = Color(0xFFFFFFFF);

  static const Color border = Color(0xFFE5E7EB);
  static const Color borderLight = Color(0xFFF3F4F6);
```

Update radii constants:
```dart
  static const double radiusSmall = 8;
  static const double radiusMedium = 12;
  static const double radiusLarge = 16;
```

Update shadow base colors (4 spots) from `Color(0xFF2C1A0E)` to `Color(0xFF111827)`. Update raised opacity to 0.04/0.02 and floating to 0.07/0.03.

Update surface aliases:
```dart
  static const Color mintSurface = Color(0xFFE6F5F3); // teal tint
  static const Color mintSurfaceDark = Color(0xFF0A6B65); // dark teal
```

Update gradients:
```dart
  static const LinearGradient darkHeaderGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF111827), Color(0xFF1F2937)],
  );

  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0D7B74), Color(0xFF0A6B65)],
  );

  static const LinearGradient backgroundGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFF8F9FA), Color(0xFFFFFFFF)],
  );
```

**Step 2: Update ThemeData to reference `AppColorTokens.light`**

In `lightTheme` getter, change the extensions list:
```dart
extensions: <ThemeExtension>[
  AppColorTokens.light,  // was earthyLight
  AppSpacingTokens.standard,
  AppShadowTokens.standard,
],
```

Update `bottomSheetTheme` top radius:
```dart
borderRadius: BorderRadius.vertical(top: Radius.circular(20)), // was 28
```

Update `dialogTheme` radius:
```dart
shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), // was radiusLarge + 4 = 24
```

**Step 3: Update typography in `_buildTextTheme`**

Apply the new type scale (sizes, weights, letter-spacing):

```dart
displayLarge: GoogleFonts.getFont(fontFamily, fontSize: 44, fontWeight: FontWeight.w800, color: color, letterSpacing: -1.0),
displayMedium: GoogleFonts.getFont(fontFamily, fontSize: 36, fontWeight: FontWeight.w700, color: color, letterSpacing: -0.5),
displaySmall: GoogleFonts.getFont(fontFamily, fontSize: 28, fontWeight: FontWeight.w700, color: color, letterSpacing: -0.3),
headlineLarge: GoogleFonts.getFont(fontFamily, fontSize: 24, fontWeight: FontWeight.w700, color: color, letterSpacing: -0.3),
headlineMedium: GoogleFonts.getFont(fontFamily, fontSize: 20, fontWeight: FontWeight.w600, color: color),
headlineSmall: GoogleFonts.getFont(fontFamily, fontSize: 18, fontWeight: FontWeight.w600, color: color),
titleLarge: GoogleFonts.getFont(fontFamily, fontSize: 17, fontWeight: FontWeight.w600, color: color),
titleMedium: GoogleFonts.getFont(fontFamily, fontSize: 15, fontWeight: FontWeight.w600, color: color),
titleSmall: GoogleFonts.getFont(fontFamily, fontSize: 13, fontWeight: FontWeight.w600, color: color),
bodyLarge: GoogleFonts.getFont(fontFamily, fontSize: 16, fontWeight: FontWeight.w400, color: secondaryColor),
bodyMedium: GoogleFonts.getFont(fontFamily, fontSize: 14, fontWeight: FontWeight.w400, color: secondaryColor),
bodySmall: GoogleFonts.getFont(fontFamily, fontSize: 12, fontWeight: FontWeight.w400, color: AppColors.textMuted),
labelLarge: GoogleFonts.getFont(fontFamily, fontSize: 14, fontWeight: FontWeight.w600, color: color),
labelMedium: GoogleFonts.getFont(fontFamily, fontSize: 12, fontWeight: FontWeight.w500, color: secondaryColor),
labelSmall: GoogleFonts.getFont(fontFamily, fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.textMuted, letterSpacing: 0.3),
```

**Step 4: Update class-level doc comment**

```dart
/// App color palette - Neutral + teal theme
class AppColors {
```

**Step 5: Run all design token tests**

Run: `flutter test test/unit/design_tokens_test.dart`
Expected: ALL PASS

**Step 6: Run static analysis**

Run: `flutter analyze`
Expected: No new issues (existing issues may remain)

**Step 7: Commit**

```bash
git add lib/core/theme/app_theme.dart
git commit -m "feat: update AppColors facade and typography to neutral + teal palette"
```

---

### Task 6: Update AppTabBar — Solid Teal Pill

Remove the gradient indicator and replace with a solid teal pill.

**Files:**
- Modify: `lib/shared/widgets/app_tab_bar.dart`

**Step 1: Replace gradient indicator with solid color**

Replace lines 35-47 (the `indicator` property):
```dart
indicator: BoxDecoration(
  color: color,
  borderRadius: BorderRadius.circular(AppColors.radiusSmall),
  boxShadow: [
    BoxShadow(
      color: color.withValues(alpha: 0.2),
      blurRadius: 8,
      offset: const Offset(0, 2),
    ),
  ],
),
```

**Step 2: Run flutter analyze**

Run: `flutter analyze lib/shared/widgets/app_tab_bar.dart`
Expected: No issues

**Step 3: Commit**

```bash
git add lib/shared/widgets/app_tab_bar.dart
git commit -m "feat: replace gradient tab indicator with solid teal pill"
```

---

### Task 7: Update LoadingButton — Solid Teal

Remove gradient, use solid primary color with flat style matching the design.

**Files:**
- Modify: `lib/shared/widgets/loading_button.dart`

**Step 1: Update LoadingButton to use solid color**

Replace the Container decoration (lines 24-36):
```dart
return Container(
  height: AppColors.buttonHeight,
  decoration: BoxDecoration(
    color: AppColors.primary,
    borderRadius: BorderRadius.circular(AppColors.radiusMedium),
  ),
```

Remove the `gradient` parameter from the constructor (line 11, line 19) and the `gradient` field. If other callers pass gradient, keep the param but default to null and ignore it (check callers first).

Update ElevatedButton radius (line 43):
```dart
borderRadius: BorderRadius.circular(AppColors.radiusMedium),
```

**Step 2: Update GlassCard radius**

Change line 77: `this.borderRadius = 16,` (was 20, matches new radiusLarge).

Update padding at line 83: `padding ?? const EdgeInsets.all(16),` (was 20).

**Step 3: Update GradientContainer radius**

Change line 106: `this.borderRadius = 16,` (was 20).

Update padding at line 112: `padding ?? const EdgeInsets.all(16),` (was 20).

**Step 4: Run flutter analyze**

Run: `flutter analyze lib/shared/widgets/loading_button.dart`
Expected: No issues

**Step 5: Commit**

```bash
git add lib/shared/widgets/loading_button.dart
git commit -m "feat: update LoadingButton, GlassCard, GradientContainer to solid teal + tighter radii"
```

---

### Task 8: Update ModuleHeader — Default Variant

Change the light variant to use white background (blends into scaffold) instead of surface color with bottom border.

**Files:**
- Modify: `lib/shared/widgets/module_header.dart`

**Step 1: Update _buildLight background**

Change line 30-34 (Container decoration) to blend with scaffold:
```dart
decoration: const BoxDecoration(
  color: Colors.white,
  border: Border(
    bottom: BorderSide(color: AppColors.border, width: 0.5),
  ),
),
```

Border width thinned from 1 → 0.5 for subtlety on white background.

**Step 2: Simplify _LightBackButton**

Replace the contained button with a plain icon (lines 156-165):
```dart
child: Container(
  width: 44,
  height: 44,
  alignment: Alignment.center,
  child: const Icon(Iconsax.arrow_left, color: AppColors.textPrimary, size: 20),
),
```

Remove the `decoration` (no background, no border) — just a tappable icon.

**Step 3: Run flutter analyze**

Run: `flutter analyze lib/shared/widgets/module_header.dart`
Expected: No issues

**Step 4: Commit**

```bash
git add lib/shared/widgets/module_header.dart
git commit -m "feat: simplify ModuleHeader light variant — white bg, plain back icon"
```

---

### Task 9: Final Verification

Run the full test suite and static analysis to confirm nothing is broken.

**Files:**
- None (verification only)

**Step 1: Run all tests**

Run: `flutter test`
Expected: ALL PASS. If any test fails, investigate whether it asserts old color values that were missed in Task 1.

**Step 2: Run static analysis**

Run: `flutter analyze`
Expected: No new errors or warnings introduced by this change.

**Step 3: Run the app on a device/simulator**

Run: `flutter run --dart-define-from-file=config.json`
Expected: App launches with white background, teal accent color, gray text. Visually verify:
- Home screen: white scaffold, gray cards with border + shadow
- A module screen: teal tab indicator, gray-900 text
- Ledger (if accessible): dark header gradient uses gray-900
- Buttons: solid teal, white text

**Step 4: Commit if any fixes were needed**

```bash
git add -A
git commit -m "fix: resolve test/analysis issues from palette swap"
```

---

## Summary

| Task | Files | What |
|------|-------|------|
| 1 | `test/unit/design_tokens_test.dart` | Update test assertions (RED) |
| 2 | `lib/core/theme/tokens/color_tokens.dart` | Swap 30 color values (GREEN) |
| 3 | `lib/core/theme/tokens/shadow_tokens.dart` | Swap shadow base color |
| 4 | `lib/core/theme/tokens/spacing_tokens.dart` | Tighten radii 12/16/20 → 8/12/16 |
| 5 | `lib/core/theme/app_theme.dart` | AppColors facade + typography |
| 6 | `lib/shared/widgets/app_tab_bar.dart` | Gradient → solid pill |
| 7 | `lib/shared/widgets/loading_button.dart` | Gradient → solid button + radius |
| 8 | `lib/shared/widgets/module_header.dart` | White default variant |
| 9 | (verification) | Full test suite + analyze + visual check |

**Total: 7 files modified, 1 test file updated, ~9 commits.**
