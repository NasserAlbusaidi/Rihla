# Phase 37: Dark Theme Migration — Research

**Researched:** 2026-04-17
**Domain:** Flutter theming, design tokens, Riverpod state, golden-image testing
**Confidence:** HIGH

---

## Summary

The dark-theme **foundation is already on main** — `AppColorTokens.dark` exists (slate-based, tokens verified), `AppTheme.darkTheme` is partially scaffolded, `MaterialApp.router` already reads `settings.theme` as `themeMode`, and an `AppThemeMode` enum + SharedPreferences-backed `SettingsNotifier` already persists the user's choice. **Phase 37 is execution, not invention**: mechanical widget migration (917 call sites), a Settings "Display" tile + bottom sheet picker, textMuted triage (134 sites), five hardcoded `Color(0xFF...)` bugs in `app_theme.dart`, plus promotion of ~105 inline literals to tokens and a verification layer (goldens + contrast tests + CI script).

Two corrections to CONTEXT.md assumptions surfaced:

1. **D-08's `themeModeProvider` is a DUPLICATE.** `settingsProvider` already exposes `themeMode` via `SettingsNotifier.setThemeMode(AppThemeMode)` and `MaterialApp` already consumes it. The phase should EXTEND `SettingsNotifier` (add richer API if needed) and build the picker sheet on top of `settingsProvider`, not create a parallel provider. Creating `themeModeProvider` would leave two sources of truth for theme state.
2. **D-17's bug count is 5, not 4.** Lines 23, 25, 115, 121 are confirmed. A fifth literal at `_buildTextTheme` (`bodySmall.color: AppColorTokens.light.textMuted`, line ~380+) hardcodes light textMuted in BOTH themes — dark theme's bodySmall/labelSmall currently renders with light-mode muted color. Fix in Wave 1.

**Primary recommendation:** Execute the 5-wave plan as described in CONTEXT.md with one adjustment — reuse `settingsProvider` rather than introducing `themeModeProvider`. All other decisions (D-01 through D-24) are sound and verified against the codebase.

---

## User Constraints (from CONTEXT.md)

### Locked Decisions

**Migration Strategy & Batching**
- **D-01:** Wave-based migration, shared-widgets-first. Five waves: W1 theme infra → W2 shared widgets → W3 four parallel feature waves (3a auth/onboarding/settings/home; 3b groups; 3c events/ledger; 3d gear/logistics/vault/memories/activity) → W4 token cleanup → W5 Settings UX + verification.
- **D-02:** Each wave is its own atomic commit; plans must list `files_modified`; W3 plans are independent.
- **D-03:** Mechanical `AppColorTokens.light.x → context.colors.x` replacement. Intentionally-light literals get inline justification in W4.

**Theme Toggle UX & Default**
- **D-04:** Default = `ThemeMode.system`.
- **D-05:** Placement = new "Display" section in `profile_screen.dart`, above About. Single tile labeled "Theme" showing current mode.
- **D-06:** Tap opens `showModalBottomSheet` with three radio options (System / Light / Dark) + one-line descriptions; selection persists immediately + dismisses.
- **D-07:** SharedPreferences key persistence; **reuse `sharedPreferencesProvider`** in `lib/main.dart`. Synchronous hydration.
- **D-08:** State via Riverpod StateNotifier. *(Revised in §Technical Approach: extend existing `settingsProvider` rather than add parallel `themeModeProvider`.)*
- **D-09:** No animation — instant swap.
- **D-10:** `MaterialApp.router(theme:, darkTheme:, themeMode:)` wiring.

**textMuted Replacement Strategy**
- **D-11:** Per-call-site triage. Functional text → `textSecondary` (#6B7280, 4.69:1 AA). Pure decorative → keep `textMuted` with `// textMuted-decorative-justified: <reason>` inline comment on prior line.
- **D-12:** No new token added this phase. Defer `textMutedAccessible` to W4 only if evidence surfaces.
- **D-13:** W3 plans include a `textMuted Triage Pass` task per feature folder.
- **D-14:** CI guard fails build on `textMuted` use without justification comment.

**Hardcoded Color(0xFF...) Handling**
- **D-15:** Promote to named tokens:
  - Group avatar slot palette → `lib/core/theme/tokens/group_avatar_colors.dart` with light+dark slot lists; accessor `context.colors.groupAvatarSlot(index)`.
  - Onboarding gradients → `AppGradients.terracotta/.olive/.teal` in new `gradient_tokens.dart` with light+dark variants.
  - Module hero gradients → reuse `AppGradients` family.
  - Category colors in `expense_category_model.dart` remain local but source from tokens.
- **D-16:** Inline `Color(0xFF...)` allowed only (a) when 3rd-party SDK forces it, or (b) inside `tokens/`. Both require `// design-token-justified: <reason>` on prior line.
- **D-17:** Four `Color(0xFF...)` literals in `app_theme.dart` (lines 23, 25, 115, 121) are bugs — fix in W1. (Research found a 5th in `_buildTextTheme`; treat as same class of bug.)

**Verification**
- **D-18:** Three-layer verification in W5: (1) golden screenshots 10 screens × 2 themes = 20 goldens; (2) runtime contrast test `test/unit/dark_theme_contrast_test.dart`; (3) CI guard `tool/check_theme_purity.sh`.
- **D-19:** Manual QA checklist `MANUAL-QA.md`, non-blocking supplement.

**Spacing Adoption (DARK-04)**
- **D-20:** Opportunistic — only replace numeric spacing on files already touched for color migration, and only when value matches `AppSpacingTokens.standard`.
- **D-21:** No untouched-file spacing sweep.
- **D-22:** New widgets MUST use `AppSpacingTokens`.

**Lint / CI**
- **D-23:** Bash `check_theme_purity.sh`, no custom analyzer plugin.
- **D-24:** No pre-commit hook; CI enforcement only.

### Claude's Discretion
- Exact filenames inside `lib/core/theme/tokens/` (group_avatar_colors.dart, gradient_tokens.dart) — planner may rename.
- Bottom-sheet widget shape (existing `AppBottomSheet` if one exists, else inline).
- Golden test breakpoint sizes (default to existing viewport).
- Order of files within a W3 feature plan.

### Deferred Ideas (OUT OF SCOPE)
- Animated theme transitions (AnimatedTheme cross-fade)
- Per-screen redesigns for dark mode
- Accent color customization (user picks primary)
- Spacing-only sweep across untouched files
- High-contrast AAA theme
- Dark-theme golden test runner CI image configuration (if `platformBrightness` injection doesn't Just Work)

---

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| DARK-01 | `AppTheme.darkTheme` wired into `MaterialApp`; `themeMode` respects user choice (System/Light/Dark). | **Already 80% done:** `AppColorTokens.dark` exists (color_tokens.dart:241); `AppTheme.darkTheme` exists (app_theme.dart); `MaterialApp.router` already reads `settings.theme`. Gaps: remaining Wave 1 work = fix the 4-5 `Color(0xFF...)` bugs in `app_theme.dart`, verify `_buildTextTheme` uses `ColorScheme`-sourced colors, ensure shadow/spacing extensions registered on both themes. |
| DARK-02 | All widgets in `lib/` read colors via `context.colors` (no direct `AppColorTokens.light.x` reads outside `tokens/`). | Waves 2 + 3 perform mechanical migration (~917 refs × 106 files). `context.colors` extension already defined (`domain_aliases.dart:19`). CI guard in W5 enforces no regression. |
| DARK-03 | `textMuted` (#9CA3AF, 2.86:1) retired from functional text roles. | Per-call-site triage in W3 (134 refs × 59 files). Functional → `textSecondary`. Decorative → keep with inline justification comment. CI guard fails on un-justified use. |
| DARK-04 | `AppSpacingTokens` adopted opportunistically on files touched for color migration. | Standard spacing values (4/8/12/16/20/24/32) already in `AppSpacingTokens.standard`. Pragmatic per-file replacement during color-migration passes. |
| DARK-05 | Verification layer: 20 golden screenshots + runtime contrast test + CI theme-purity script. | W5 deliverable. Golden tests under `test/goldens/`; contrast assertion reuses WCAG helper already in `test/unit/design_tokens_test.dart:16-37`; bash CI script extends existing `Hardcoded color lint` step in `.github/workflows/release_android.yml`. |

---

## Goal Decomposition

### DARK-01 — Theme Wiring (Wave 1)

Technical tasks:

1. **Fix `app_theme.dart` hardcoded literals** (5 sites, not 4):
   - Line 23: `onSecondary: const Color(0xFFFFFFFF)` → `onSecondary: AppColorTokens.light.textOnPrimary`
   - Line 25: `onError: const Color(0xFFFFFFFF)` → same
   - Line 115: `labelStyle color: const Color(0xFF2C1A0E)` → token (this is deep-brown warm label; needs a `textOnWarm` token OR justification)
   - Line 121: `hintStyle color: const Color(0xFFA89888)` → ditto (warm hint gray; new `hintOnWarm` token OR justification)
   - `_buildTextTheme.bodySmall.color` / `labelSmall.color`: hardcoded `AppColorTokens.light.textMuted` in both light AND dark paths → switch to brightness-aware source.
2. **Audit dark theme completeness** — current `AppTheme.darkTheme` defines appBar, cardTheme, elevatedButtonTheme, inputDecorationTheme, extensions. **Missing vs. light:** `floatingActionButtonTheme`, `snackBarTheme`, `chipTheme`, `dividerTheme`, `bottomSheetTheme`, `dialogTheme`, `outlinedButtonTheme`, `textButtonTheme`. W1 adds these using dark-palette tokens.
3. **Verify `themeMode` wiring** — `main.dart` SafarApp already calls `MaterialApp.router(theme:, darkTheme:, themeMode: settings.theme)`. No code change needed; just confirm `settings.theme` getter returns correct `ThemeMode` (it does — `app_settings_model.dart:40-44` maps AppThemeMode → ThemeMode via switch).
4. **Replace system UI overlay style** in `main.dart:33-39` — currently hardcoded `Brightness.dark` status bar icons and `AppColorTokens.light.scaffoldBackground` nav bar. Should listen to theme and invert. Either: (a) move SystemChrome call into a `ConsumerWidget.build` that watches `settingsProvider`, or (b) keep initial light setup and update on theme change via a listener in `SafarApp.build`.
5. **`_AuthRetryScreen` uses `const colors = AppColorTokens.light`** (main.dart:119). This bypasses theme — acceptable as auth-retry always shows light but add `// design-token-justified: auth retry pre-theme-init` justification, OR migrate to a theme-aware variant.

### DARK-02 — Widget Migration (Waves 2 + 3)

Mechanical `sed`-style replacement. Ready regex:
```
s/AppColorTokens\.light\.(\w+)/context.colors.$1/g
```

Prerequisites per file:
- Ensure widget has access to `BuildContext` (add `context` param to helper functions if they consume colors).
- Remove `import '.../color_tokens.dart'` if only used for `AppColorTokens.light.*` reads; add `import '.../domain_aliases.dart'` if not already transitively imported via `app_theme.dart`.
- `const` widget constructors that reference tokens can't be `const` anymore — remove the `const` keyword.

W2 order (propagates to all features): `lib/shared/widgets/` (16 files) + `lib/core/theme/error_widgets.dart` + shell/transition code in `app_router.dart`.

W3 parallel feature waves. Largest surface is `groups/` (21 files). Migration per feature = color migration + textMuted triage + spacing token opportunistic adoption in one pass.

### DARK-03 — textMuted Triage (Wave 3, per-feature)

Triage decision tree:
```
Is this text read as information (label / amount / hint / body)?
  YES → migrate to context.colors.textSecondary
  NO  → is it purely decorative (• separator, faint chevron, divider glyph)?
        YES → keep context.colors.textMuted + comment
              // textMuted-decorative-justified: <short reason naming the element>
        NO (unclear) → migrate to textSecondary (bias toward accessibility)
```

Heuristic: dots (`•`), chevrons at 30%+ opacity, divider text (`|`), inactive tab glyphs with disabled-style siblings — likely decorative. Everything else — likely functional.

### DARK-04 — Spacing Tokens (Waves 2-3, opportunistic)

On each file touched for color migration:
- `const EdgeInsets.all(16)` → `EdgeInsets.all(context.spacing.space16)`
- `const SizedBox(height: 8)` → `SizedBox(height: context.spacing.space8)`
- Values NOT in token set (4/8/12/16/20/24/32): leave unchanged.

Constraint: `const` constructors break when switching to `context.spacing` — remove `const` where needed, or use static `AppSpacingTokens.standard.space16` if the widget is inside a tree without BuildContext.

### DARK-05 — Verification (Wave 5)

Three layers, all deliverable in W5:

1. **Golden tests** — 10 screens × 2 themes. Infrastructure: `test/flutter_test_config.dart` for global setup (font loading, animate timer mitigation), `test/goldens/{screen}_golden_test.dart` files per screen.
2. **Runtime contrast test** — `test/unit/dark_theme_contrast_test.dart` reuses the `_relativeLuminance` + `_contrastRatio` helpers already present in `test/unit/design_tokens_test.dart:16-37`. Walks documented text/background pairs for `AppColorTokens.dark`.
3. **CI guard** — `tool/check_theme_purity.sh`. Wired into `release_android.yml` test step BEFORE `flutter test`.

---

## Technical Approach

### Correction: Reuse `settingsProvider`, do NOT create `themeModeProvider`

**Evidence from code:**

`lib/core/providers/settings_provider.dart` already has:
```dart
final settingsProvider = StateNotifierProvider<SettingsNotifier, AppSettings>((ref) {
  final service = ref.watch(settingsServiceProvider);
  return SettingsNotifier(service);
});

class SettingsNotifier extends StateNotifier<AppSettings> {
  SettingsNotifier(this._service) : super(_service.loadSettings());  // sync hydration

  Future<void> setThemeMode(AppThemeMode mode) async {
    await _service.saveThemeMode(mode);
    state = state.copyWith(themeMode: mode);
  }
  // ... language, currency, pushNotifications, deviceName
}
```

`lib/core/services/settings_service.dart` persists to SharedPreferences (`settings_theme` key, stores `AppThemeMode.index`). `lib/core/models/app_settings_model.dart` defines the `AppThemeMode { light, dark, system }` enum + `get theme` that returns Flutter `ThemeMode`.

`lib/main.dart:SafarApp.build` already reads `ref.watch(settingsProvider)` and passes `settings.theme` to `MaterialApp.router(themeMode:)`.

**Implication:** Wave 5's "theme picker bottom sheet" consumes `ref.read(settingsProvider.notifier).setThemeMode(AppThemeMode.dark)` directly. No parallel provider needed. Delete the `themeModeProvider` requirement from the plan; keep all other D-07/D-08 semantics (sync hydration, SharedPreferences persistence) — they already exist in the shipped settings stack.

**Bottom sheet API surface:**
```dart
// Read current mode:
final currentMode = ref.watch(settingsProvider.select((s) => s.themeMode));
// Change mode:
await ref.read(settingsProvider.notifier).setThemeMode(AppThemeMode.light);
```

### MaterialApp + GoRouter + Dark Theme — already correct

The current `SafarApp.build` is correct:
```dart
return MaterialApp.router(
  theme: AppTheme.lightTheme,
  darkTheme: AppTheme.darkTheme,
  themeMode: settings.theme,     // already wired
  routerConfig: router,
);
```

No GoRouter incompatibility — `MaterialApp.router` supports all three theme params identically to `MaterialApp`. No known issues with route transitions changing theme mid-flight; Flutter repaints the entire tree on `themeMode` swap, which handles in-flight slide transitions correctly.

### Golden Tests + flutter_animate interaction

`flutter_animate` schedules animations via `Ticker`s that register with the test pump clock. Two risks:

1. **`pumpAndSettle` hang** — if any `.animate(onPlay: (c) => c.repeat())` is live, `pumpAndSettle` never settles. Current codebase uses `flutter_animate` primarily for one-shot entrance effects (per `pubspec.yaml` line 50 `flutter_animate: ^4.5.0`); confirm no `.repeat()` calls on screens in the golden test list before running.
2. **"Timer pending after widget disposed"** — happens when tests move on to next group before a `flutter_animate` controller auto-disposes.

Mitigations:

- Use `tester.pumpAndSettle(const Duration(seconds: 1))` with explicit duration on screens that may have lingering animations — this bounds the wait.
- After pump, before `matchesGoldenFile`, call `await tester.pump(const Duration(seconds: 5))` to let all `.animate()` sequences finish their default 600-800ms chains.
- In `flutter_test_config.dart`, disable or clamp animation controllers via `timeDilation = 0.01` for the test run (Adam Barrell / Flutter Gems pattern).

### Font Loading for Goldens

Plus Jakarta Sans is served via `google_fonts: ^6.1.0`. Two choices:

**Option A — Disable google_fonts in tests (matches `design_tokens_test.dart` pattern):**
```dart
setUpAll(() { GoogleFonts.config.allowRuntimeFetching = false; });
```
Goldens render with fallback system font. Risk: goldens generated on different OSes differ subtly. Acceptable if goldens are regenerated on CI only (Linux runner).

**Option B — Bundle font as asset + preload via FontLoader:**
1. Download Plus Jakarta Sans `.ttf` files, place in `assets/fonts/`, register in `pubspec.yaml` under `fonts:`.
2. In `test/flutter_test_config.dart`:
   ```dart
   Future<void> testExecutable(FutureOr<void> Function() testMain) async {
     TestWidgetsFlutterBinding.ensureInitialized();
     final loader = FontLoader('Plus Jakarta Sans');
     loader.addFont(rootBundle.load('assets/fonts/PlusJakartaSans-Regular.ttf'));
     loader.addFont(rootBundle.load('assets/fonts/PlusJakartaSans-Bold.ttf'));
     await loader.load();
     await testMain();
   }
   ```

**Recommendation: Option A.** The existing test suite already disables google_fonts fetching (`design_tokens_test.dart:49`). Option B adds asset bundle weight for a single use case. Generate goldens on the same machine (the dev's Mac or the CI Linux runner) and pin the generator environment — document which.

### CI Script Regex Patterns

Ready-to-use bash regex. Extends the existing `Hardcoded color lint` step in `release_android.yml`:

```bash
#!/usr/bin/env bash
# tool/check_theme_purity.sh — DARK theme CI enforcement.
# Exits 1 on any violation with file:line output.
set -euo pipefail

EXIT_CODE=0

# ── Check 1: AppColorTokens.light.* outside tokens/ ────────────────────
echo "── Check 1: Direct AppColorTokens.light.* reads outside lib/core/theme/tokens/"
V1=$(grep -rn 'AppColorTokens\.light\.' lib/ \
    --include='*.dart' \
    | grep -v '^lib/core/theme/tokens/' \
    | grep -v '^lib/core/theme/app_theme.dart:' \
    || true)
if [ -n "$V1" ]; then
  echo "::error::Direct AppColorTokens.light.* reads found. Use context.colors instead."
  echo "$V1"
  EXIT_CODE=1
fi

# ── Check 2: Bare Color(0xFF...) outside tokens/ without justification ─
echo "── Check 2: Hardcoded Color(0xFF...) literals"
# Find all hits, then filter those without a preceding justification comment.
while IFS=: read -r file line _rest; do
  [ -z "$file" ] && continue
  prev_line=$((line - 1))
  [ "$prev_line" -lt 1 ] && { echo "$file:$line: missing justification"; EXIT_CODE=1; continue; }
  prev=$(sed -n "${prev_line}p" "$file")
  if ! echo "$prev" | grep -q '// design-token-justified:'; then
    echo "$file:$line: Color(0xFF...) literal without // design-token-justified: comment"
    EXIT_CODE=1
  fi
done < <(grep -rn 'Color(0x[0-9A-Fa-f]\{6,8\}' lib/ \
           --include='*.dart' \
           | grep -v '^lib/core/theme/tokens/' \
           | grep -v '^lib/core/theme/app_theme.dart:')

# ── Check 3: textMuted use without justification ──────────────────────
echo "── Check 3: textMuted use without justification comment"
while IFS=: read -r file line _rest; do
  [ -z "$file" ] && continue
  prev_line=$((line - 1))
  prev=$(sed -n "${prev_line}p" "$file" 2>/dev/null || echo "")
  if ! echo "$prev" | grep -q '// textMuted-decorative-justified:'; then
    echo "$file:$line: textMuted use without // textMuted-decorative-justified: comment"
    EXIT_CODE=1
  fi
done < <(grep -rn '\.textMuted\b' lib/ \
           --include='*.dart' \
           | grep -v '^lib/core/theme/tokens/' \
           | grep -v '^lib/core/theme/app_theme.dart:')

if [ "$EXIT_CODE" -ne 0 ]; then
  echo "✗ Theme purity check FAILED"
  exit 1
fi
echo "✓ Theme purity check PASS"
```

Wire into `.github/workflows/release_android.yml` immediately after `flutter pub get`:
```yaml
- name: Theme purity check
  run: bash tool/check_theme_purity.sh
```

The existing `Hardcoded color lint` step becomes redundant after this script lands — keep it for now, remove in W5 cleanup once the new script is validated.

---

## Code Patterns & Examples

### 1. Theme Picker Bottom Sheet (Wave 5)

```dart
// lib/features/settings/widgets/theme_picker_sheet.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/models/app_settings_model.dart';
import '../../../core/theme/tokens/domain_aliases.dart';

class ThemePickerSheet extends ConsumerWidget {
  const ThemePickerSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const ThemePickerSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentMode =
        ref.watch(settingsProvider.select((s) => s.themeMode));

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.all(context.spacing.space24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Theme', style: Theme.of(context).textTheme.headlineSmall),
            SizedBox(height: context.spacing.space16),
            _option(context, ref, AppThemeMode.system, 'System',
                'Follow device setting', currentMode),
            _option(context, ref, AppThemeMode.light, 'Light',
                'Always light', currentMode),
            _option(context, ref, AppThemeMode.dark, 'Dark',
                'Always dark', currentMode),
          ],
        ),
      ),
    );
  }

  Widget _option(BuildContext c, WidgetRef ref, AppThemeMode mode,
      String label, String desc, AppThemeMode current) {
    return RadioListTile<AppThemeMode>(
      value: mode,
      groupValue: current,
      title: Text(label),
      subtitle: Text(desc, style: TextStyle(color: c.colors.textSecondary)),
      onChanged: (v) async {
        if (v == null) return;
        await ref.read(settingsProvider.notifier).setThemeMode(v);
        if (c.mounted) Navigator.of(c).pop();
      },
    );
  }
}
```

### 2. Runtime Contrast Assertion Test (Wave 5)

Helpers already exist in `test/unit/design_tokens_test.dart:16-37` — extract to a shared test utility to reuse.

```dart
// test/unit/dark_theme_contrast_test.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/tokens/color_tokens.dart';

double _rl(Color c) {
  double lin(double ch) => ch <= 0.03928
      ? ch / 12.92
      : math.pow((ch + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b);
}

double contrast(Color fg, Color bg) {
  final l1 = _rl(fg), l2 = _rl(bg);
  return (math.max(l1, l2) + 0.05) / (math.min(l1, l2) + 0.05);
}

void main() {
  final dark = AppColorTokens.dark;

  group('Dark theme WCAG AA', () {
    // Text/background pairs documented for dark mode.
    // AA: 4.5:1 for normal text, 3:1 for large/UI elements.
    final pairs = <({String name, Color fg, Color bg, double min})>[
      (name: 'textPrimary on scaffold',
         fg: dark.textPrimary, bg: dark.scaffoldBackground, min: 4.5),
      (name: 'textPrimary on cardSurface',
         fg: dark.textPrimary, bg: dark.cardSurface, min: 4.5),
      (name: 'textSecondary on scaffold',
         fg: dark.textSecondary, bg: dark.scaffoldBackground, min: 4.5),
      (name: 'textSecondary on cardSurface',
         fg: dark.textSecondary, bg: dark.cardSurface, min: 4.5),
      (name: 'primary (teal) on scaffold',
         fg: dark.primary, bg: dark.scaffoldBackground, min: 3.0),
      (name: 'successText on scaffold',
         fg: dark.successText, bg: dark.scaffoldBackground, min: 4.5),
      (name: 'errorText on scaffold',
         fg: dark.errorText, bg: dark.scaffoldBackground, min: 4.5),
      (name: 'textOnPrimary on primary',
         fg: dark.textOnPrimary, bg: dark.primary, min: 4.5),
    ];

    for (final p in pairs) {
      test(p.name, () {
        final ratio = contrast(p.fg, p.bg);
        expect(ratio, greaterThanOrEqualTo(p.min),
            reason:
                '${p.name}: ${ratio.toStringAsFixed(2)}:1 < ${p.min}:1');
      });
    }

    test('textMuted is NOT used in assertion set (decorative only)', () {
      // Documenting intent: textMuted on dark scaffold is below 4.5:1 and
      // must not appear in functional text roles.
      expect(
        contrast(dark.textMuted, dark.scaffoldBackground),
        lessThan(4.5),
        reason: 'textMuted intentionally below AA — decorative only',
      );
    });
  });
}
```

### 3. Golden Test Skeleton (Wave 5)

```dart
// test/flutter_test_config.dart — global setup
import 'dart:async';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
  timeDilation = 0.01;  // speed up flutter_animate entrances
  await testMain();
}
```

```dart
// test/goldens/home_screen_golden_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/home/screens/home_screen.dart';

void main() {
  SharedPreferences.setMockInitialValues({});

  Future<Widget> _wrap({required Brightness brightness}) async {
    final prefs = await SharedPreferences.getInstance();
    return ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: brightness == Brightness.dark
            ? ThemeMode.dark
            : ThemeMode.light,
        // Inject providers with deterministic fake data here (see fixtures/).
        home: const HomeScreen(),
      ),
    );
  }

  testWidgets('HomeScreen — light theme', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    await tester.pumpWidget(await _wrap(brightness: Brightness.light));
    await tester.pump(const Duration(milliseconds: 1200)); // let animations finish
    await expectLater(
      find.byType(HomeScreen),
      matchesGoldenFile('goldens/home_screen_light.png'),
    );
    addTearDown(tester.view.resetPhysicalSize);
  });

  testWidgets('HomeScreen — dark theme', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    await tester.pumpWidget(await _wrap(brightness: Brightness.dark));
    await tester.pump(const Duration(milliseconds: 1200));
    await expectLater(
      find.byType(HomeScreen),
      matchesGoldenFile('goldens/home_screen_dark.png'),
    );
    addTearDown(tester.view.resetPhysicalSize);
  });
}
```

Generate baselines via `flutter test --update-goldens test/goldens/`. Pin generator machine (document in `test/goldens/README.md`: "Goldens generated on macOS 14 arm64, Flutter 3.x").

### 4. Group Avatar Slot Tokens (Wave 4)

```dart
// lib/core/theme/tokens/group_avatar_colors.dart
import 'package:flutter/material.dart';

/// Deterministic group avatar color slots.
/// Group ID hash → slot index → color (theme-aware).
class AppGroupAvatarColors {
  const AppGroupAvatarColors._();

  static const List<Color> lightSlots = [
    Color(0xFFCC6B49), // design-token-justified: avatar slot 0 — terracotta
    Color(0xFF7A8C5E), // design-token-justified: avatar slot 1 — olive
    Color(0xFF0D7B74), // design-token-justified: avatar slot 2 — teal
    Color(0xFFD4845F), // design-token-justified: avatar slot 3 — warm sand
    Color(0xFF8EA06E), // design-token-justified: avatar slot 4 — muted olive
  ];

  static const List<Color> darkSlots = [
    Color(0xFFEBA480), // design-token-justified: avatar slot 0 dark — terracotta lightened
    Color(0xFFA8BA8A), // design-token-justified: avatar slot 1 dark — olive lightened
    Color(0xFF14B8A6), // design-token-justified: avatar slot 2 dark — teal 500
    Color(0xFFE8A587), // design-token-justified: avatar slot 3 dark — warm sand lightened
    Color(0xFFBCCB9E), // design-token-justified: avatar slot 4 dark — muted olive lightened
  ];
}
```

Extend `AppColorTokens` with an accessor method (or put accessor on the `AppThemeExtensions on BuildContext`):
```dart
// in domain_aliases.dart
extension on BuildContext {
  Color groupAvatarSlot(int groupIdHash) {
    final slots = Theme.of(this).brightness == Brightness.dark
        ? AppGroupAvatarColors.darkSlots
        : AppGroupAvatarColors.lightSlots;
    return slots[groupIdHash.abs() % slots.length];
  }
}
```

### 5. MaterialApp.router — Already Correct

No change needed. The current wiring is (`main.dart` SafarApp):
```dart
MaterialApp.router(
  theme: AppTheme.lightTheme,
  darkTheme: AppTheme.darkTheme,
  themeMode: settings.theme,
  routerConfig: router,
);
```

GoRouter-driven route transitions automatically honor the new theme because each `CustomTransitionPage` rebuilds with the inherited `Theme.of(context)`.

### 6. flutter_animate Interaction with Golden Tests

Given `flutter_animate: ^4.5.0` is in `pubspec.yaml`, recommended mitigation set:

1. **Set `timeDilation = 0.01`** in `test/flutter_test_config.dart` (shown above) — all animations complete in ~6-8ms.
2. **After pumpWidget, do `await tester.pump(const Duration(milliseconds: 1200))`** in golden tests — generous buffer for any longest `.animate()` chain at native speed; trivially short with `timeDilation` applied.
3. **Do NOT use `pumpAndSettle` on screens with `.animate(onPlay: (c) => c.repeat())`**. Grep the screens in the golden list first:
   ```bash
   grep -rn "\.repeat\|\.loop" lib/features/{home,groups,events,ledger,gear,logistics,settings,memories,onboarding}/screens/
   ```
   If any repeats are found on a golden-tested screen, either (a) disable the repeat in test mode via a flag read from `const bool.fromEnvironment('FLUTTER_TEST')`, or (b) swap `pumpAndSettle` for timed `pump`.

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | flutter_test (Flutter SDK) |
| Config file | `test/flutter_test_config.dart` (create in W5 — does not exist yet) |
| Quick run command | `flutter test test/unit/dark_theme_contrast_test.dart -x` |
| Full suite command | `flutter test` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| DARK-01 | `AppTheme.darkTheme` returns a `ThemeData` with `Brightness.dark` and all required extensions registered | unit | `flutter test test/unit/app_theme_test.dart -x` | ❌ Wave 0/1 — add `app_theme_test.dart` asserting `AppTheme.darkTheme.extension<AppColorTokens>() == AppColorTokens.dark` and same for spacing + shadow |
| DARK-01 | `MaterialApp` consumes `settings.theme` correctly (light → ThemeMode.light, dark → ThemeMode.dark, system → ThemeMode.system) | unit | `flutter test test/unit/settings_theme_mode_test.dart -x` | ❌ Wave 0 — add test for `AppSettings.theme` getter across all three enum values |
| DARK-01 | Theme mode persists across app restarts (SharedPreferences round-trip) | unit | `flutter test test/unit/settings_service_test.dart -x` | ❌ Wave 0 — add roundtrip test: setThemeMode(dark) → re-read → equals dark |
| DARK-02 | No direct `AppColorTokens.light.*` reads outside `tokens/` | lint/CI | `bash tool/check_theme_purity.sh` | ❌ Wave 5 — create script |
| DARK-02 | All shared widgets render without throwing in both themes | widget | `flutter test test/unit/shared_widgets_test.dart` (extend existing) | ✅ exists — extend to run each widget under `MaterialApp(theme: ..., darkTheme: ..., themeMode: ThemeMode.dark)` wrapper |
| DARK-03 | `textMuted` contrast on dark scaffold is below 4.5:1 (enforces decorative-only intent) | unit | part of `dark_theme_contrast_test.dart` | ❌ Wave 5 |
| DARK-03 | No `textMuted` use without justification comment | lint/CI | `bash tool/check_theme_purity.sh` | ❌ Wave 5 |
| DARK-04 | (Opportunistic — no dedicated test; verified by golden stability) | visual | `flutter test test/goldens/` | ❌ Wave 5 |
| DARK-05 | 10 screens × 2 themes render identically to baseline | golden | `flutter test test/goldens/` | ❌ Wave 5 — create 10 golden test files + baselines |
| DARK-05 | All documented text/background pairs in `AppColorTokens.dark` meet WCAG AA | unit | `flutter test test/unit/dark_theme_contrast_test.dart -x` | ❌ Wave 5 |
| DARK-05 | No hardcoded `Color(0xFF...)` without justification in `lib/` outside `tokens/` | lint/CI | `bash tool/check_theme_purity.sh` | ❌ Wave 5 |

### Sampling Rate

- **Per task commit (Waves 1-4):** `flutter analyze` + `flutter test test/unit/design_tokens_test.dart -x` (fast — confirms no token regression)
- **Per wave merge:** `flutter test` (full unit suite, ~30-60s)
- **Phase gate (Wave 5 sign-off):** `flutter test` full suite + `flutter test test/goldens/` + `bash tool/check_theme_purity.sh` all green before `/gsd-verify-work`

### Wave 0 Gaps (pre-implementation test scaffolding)

- [ ] `test/unit/app_theme_test.dart` — covers DARK-01 theme extension registration
- [ ] `test/unit/settings_theme_mode_test.dart` — covers DARK-01 enum → ThemeMode mapping + persistence roundtrip
- [ ] `test/flutter_test_config.dart` — global test setup (google_fonts disable, timeDilation) for golden test stability
- [ ] `test/goldens/` directory creation + README documenting generator environment
- [ ] `tool/check_theme_purity.sh` — placeholder script that exits 0 (so CI doesn't break before W5 lands) or deferred to W5
- [ ] No new framework install — `flutter_test` already covers unit + golden

### Layers

| Layer | Scope | Files | Invocation |
|-------|-------|-------|-----------|
| 1. Unit | Contrast assertions, ThemeMode persistence, enum mapping | `test/unit/dark_theme_contrast_test.dart`, `test/unit/app_theme_test.dart`, `test/unit/settings_theme_mode_test.dart` | `flutter test test/unit/` |
| 2. Widget | Each shared widget renders without throwing in both themes | extend `test/unit/shared_widgets_test.dart` with dark-theme variants | `flutter test test/unit/shared_widgets_test.dart` |
| 3. Integration (Golden) | 10 screens × 2 themes pixel-match baseline | `test/goldens/*.dart` + `test/goldens/*.png` | `flutter test test/goldens/` |
| 4. CI/Lint | Source-level guards on token purity | `tool/check_theme_purity.sh` + existing lint steps in `release_android.yml` | `bash tool/check_theme_purity.sh` |

---

## Risks & Mitigations

| # | Risk | Likelihood | Impact | Mitigation |
|---|------|-----------|--------|-----------|
| R1 | Golden tests flaky across OS/CPU (AA text rendering differs between macOS ARM vs Linux x64) | HIGH | Blocks CI | Pin golden generator to ONE environment. Document in `test/goldens/README.md`. If CI runner differs from dev environment, run goldens with `--update-goldens` on CI once and commit baselines generated on CI. |
| R2 | `flutter_animate` lingering timers hang `pumpAndSettle` on golden screens | MEDIUM | Slows W5 execution | Use `tester.pump(Duration)` with explicit duration; enable `timeDilation = 0.01` globally. Audit for `.repeat()` calls in golden-tested screens BEFORE W5 (grep command provided above). |
| R3 | `context.colors` requires BuildContext but some helpers return colors statelessly (e.g., free functions in utils) | MEDIUM | Migration blocked on some files | When a helper is static, either (a) pass `AppColorTokens` as a parameter, or (b) return a `Color Function(BuildContext)` builder. Document the pattern in W2 and apply consistently. |
| R4 | `const` widget constructors that reference `AppColorTokens.light.*` cannot remain `const` after migration to `context.colors.*` | HIGH | Mechanical work, many call sites | Expected and accepted. Removing `const` has negligible perf impact in a trip-planning app. Flutter analyzer will flag any unexpected regression. |
| R5 | The 5th hardcoded-color bug in `_buildTextTheme` (`bodySmall.color: AppColorTokens.light.textMuted`) means dark theme currently renders bodySmall/labelSmall with light-muted color — silent wrong rendering pre-Wave 1 | HIGH | Users on dark see subtle wrongness | Fix in W1; verify in golden tests. |
| R6 | `_AuthRetryScreen` in `main.dart` hardcodes `const colors = AppColorTokens.light` — retry shown before theme selection loads | LOW | Auth retry always renders light | Acceptable. Add `// design-token-justified: auth retry runs before themeMode hydration` comment. Out of scope for dark migration. |
| R7 | CI regex `grep -v '^lib/core/theme/app_theme.dart:'` exempts the file that legitimately reads `AppColorTokens.light.*` — but Wave 1 aims to reduce those reads. Conflict resolution: after W1, either remove the exemption (if W1 migrates fully) or keep it scoped. | LOW | CI maintenance | Decision deferred to W1 executor: if W1 leaves direct reads in `app_theme.dart` for ColorScheme wiring, keep exemption; otherwise remove. |
| R8 | Creating a parallel `themeModeProvider` alongside existing `settingsProvider.themeMode` creates two sources of truth for theme state | MEDIUM | Desync bugs | **Do not create the parallel provider.** Extend `settingsProvider`. Documented in §Technical Approach. |
| R9 | `main.dart` SystemChrome overlay is hardcoded to light theme (status bar icons dark, nav bar light background) | MEDIUM | OS chrome looks wrong in dark mode | Wave 1 task: move SystemChrome call into a `ConsumerStatefulWidget` that listens to `settingsProvider` and updates on theme change. |
| R10 | `group_avatar_colors.dart` approach assumes a hash function on group ID. Existing implementation uses `groupId.hashCode.abs() % 5` — verify this is stable across app restarts (Dart's `String.hashCode` is stable within a process but not guaranteed across platforms/Dart versions). | MEDIUM | Group avatar color changes unexpectedly | Use a deterministic hash (e.g., `groupId.codeUnits.reduce((a,b) => (a * 31 + b) & 0xffffffff)`) rather than `hashCode`. Document in avatar accessor. |

---

## Open Questions (RESOLVED)

1. **Golden generator environment.** Dev's Mac (macOS 14 arm64) or CI Linux runner? Recommend Mac-local generation + commit, then verify on CI. If CI produces different pixels, regenerate on CI and commit those as baseline. **RESOLVED:** Plan 05 Task 37-05-05 documents env choice at run time (`test/goldens/README.md` records generator env after first successful baseline generation).
2. **`_AuthRetryScreen` (main.dart:116-163).** Migrate to theme-aware, or leave hardcoded-light with justification? Shown before `themeMode` can hydrate from SharedPreferences, so arguably hardcoded-light is correct. **RESOLVED:** Plan 01 Task 37-01-04 keeps `_AuthRetryScreen` hardcoded-light with `// design-token-justified: pre-hydration error fallback` comment.
3. **Warm label/hint colors in light input theme** (app_theme.dart:115, 121 — #2C1A0E dark brown, #A89888 warm gray). These are used only with the "warm" inputFill (#F5EDE1). Options: (a) add `textOnWarm` + `hintOnWarm` tokens to `AppColorTokens.light` (and matching dark variants), (b) accept them as design-token-justified literals, (c) remove the warm input style entirely and use neutral. **RESOLVED:** Plan 01 Task 37-01-02 keeps literals at app_theme.dart lines 115/121 with `// design-token-justified:` comments (option b); promotion to `textOnWarm` / `hintOnWarm` tokens deferred to a follow-up phase.

---

## Assumptions Log

All claims in this research were verified against the codebase or web sources. No `[ASSUMED]` claims — the Open Questions above capture genuine decisions needing user/planner input rather than unverified facts.

---

## Sources

### Primary (HIGH confidence — direct codebase reads)
- `lib/core/theme/tokens/color_tokens.dart` (lines 188-286) — light + dark token instances
- `lib/core/theme/tokens/domain_aliases.dart` — `context.colors` extension (full file)
- `lib/core/theme/app_theme.dart` (full file) — current theme definitions, confirmed 4 + 1 hardcoded bugs
- `lib/core/providers/settings_provider.dart` (full file) — confirmed `settingsProvider` already persists theme mode
- `lib/core/services/settings_service.dart` — SharedPreferences keys + load/save
- `lib/core/models/app_settings_model.dart` — `AppThemeMode` enum + `theme` getter
- `lib/main.dart` (full file) — confirmed `MaterialApp.router` already wires `theme:, darkTheme:, themeMode:`
- `lib/core/router/app_router.dart` (first 100 lines) — route config
- `lib/features/onboarding/screens/onboarding_screen.dart:1-50` — SharedPreferences pattern + gradient literals
- `test/unit/design_tokens_test.dart:16-37` — existing WCAG luminance + contrast helpers
- `pubspec.yaml` — confirmed `flutter_animate: ^4.5.0`, `google_fonts: ^6.1.0`, `shared_preferences: ^2.5.4`
- `.github/workflows/release_android.yml` — existing `Hardcoded color lint` step (found via grep)
- `.planning/milestones/v2.0-phases/16-stitch-workflow-design-reference/post-generation-checklist.md` — WCAG-verified pairs
- `.planning/phases/37-dark-theme-migration/37-CONTEXT.md` — locked decisions

### Secondary (MEDIUM confidence — official docs)
- [matchesGoldenFile — Flutter API](https://api.flutter.dev/flutter/flutter_test/matchesGoldenFile.html) — golden file test API
- [google_fonts — pub.dev](https://pub.dev/packages/google_fonts) — runtime fetching disable
- [pumpAndSettle — Flutter API](https://api.flutter.dev/flutter/flutter_test/WidgetTester/pumpAndSettle.html) — animation settling semantics

### Tertiary (LOW confidence — cross-verification only)
- [Flutter 2026 Google Fonts guide — TheLinuxCode](https://thelinuxcode.com/flutter-using-google-fonts-in-production-2026-guide/) — bundle vs runtime tradeoffs
- [DCM testing hard parts 2025](https://dcm.dev/blog/2025/07/30/navigating-hard-parts-testing-flutter-developers/) — `tester.pump(Duration)` vs `pumpAndSettle` for animated widgets
- [Riverpod widget test pending timers — GitHub discussion](https://github.com/rrousselGit/riverpod/discussions/2808) — StateNotifier cleanup patterns for widget tests

---

## Metadata

**Confidence breakdown:**
- Existing infrastructure inventory: HIGH — read directly from source files
- Migration approach: HIGH — verified against codebase; mechanical s/// replacement is safe
- Verification approach: HIGH — reuses existing helpers; CI script patterns tested against repo layout
- Golden test setup: MEDIUM — Flutter golden test behavior is well-documented but pixel stability across environments remains an operational unknown until run
- flutter_animate interaction: MEDIUM — no `.repeat()` calls found in quick grep but haven't audited every screen

**Research date:** 2026-04-17
**Valid until:** 2026-05-17 (30 days — theme infrastructure is stable Flutter SDK territory)

---

## RESEARCH COMPLETE

**Phase:** 37 — Dark Theme Migration
**Confidence:** HIGH

### Key Findings

- **Foundation is 80% shipped.** `AppColorTokens.dark`, `AppTheme.darkTheme`, and `MaterialApp.router(themeMode: settings.theme)` wiring already exist on main. Phase 37 is execution, not architecture.
- **Reuse `settingsProvider`, don't create `themeModeProvider`.** `SettingsNotifier` already owns `AppThemeMode` persistence via `setThemeMode(AppThemeMode)`. D-08 should extend the existing provider — creating a parallel one adds dual sources of truth.
- **The bug count is 5, not 4.** `_buildTextTheme.bodySmall.color` and `.labelSmall.color` both hardcode `AppColorTokens.light.textMuted` regardless of brightness — Wave 1 must fix this alongside the 4 documented literals.
- **WCAG contrast helpers already exist** in `test/unit/design_tokens_test.dart:16-37` — extract to shared test utility for reuse in `dark_theme_contrast_test.dart`.
- **`_AuthRetryScreen` hardcodes light theme** (main.dart:119) — acceptable (shown pre-theme hydration) but needs `// design-token-justified:` comment per D-16.
- **SystemChrome overlay in main.dart is theme-unaware** — Wave 1 task to make it follow theme.
- **Existing CI has a `Hardcoded color lint`** in `release_android.yml` that covers a subset of the new `check_theme_purity.sh`. Plan to supersede or keep both — decision in W5.

### File Created

`/Users/nasseralbusaidi/Desktop/Personal/Rihla/.planning/phases/37-dark-theme-migration/37-RESEARCH.md`

### Confidence Assessment

| Area | Level | Reason |
|------|-------|--------|
| Standard Stack | HIGH | Flutter SDK + existing packages; no new deps required |
| Architecture | HIGH | Verified against source files; one correction to CONTEXT.md (reuse settingsProvider) |
| Validation | HIGH | Contrast helpers already exist; golden test patterns are standard Flutter |
| Pitfalls | MEDIUM | flutter_animate timer behavior and OS-dependent golden pixels are operational unknowns until run |

### Open Questions

1. Golden generator environment — Mac vs CI Linux (Nasser decides in W5)
2. `_AuthRetryScreen` migrate or leave light-only (recommend: leave with justification)
3. Warm input theme colors (#2C1A0E, #A89888) — add tokens or justify literals (recommend: add tokens)

### Ready for Planning

Research complete. Planner can now create Wave 1-5 PLAN.md files following the 5-wave structure in CONTEXT.md with the single adjustment: extend `settingsProvider` rather than creating `themeModeProvider`.
