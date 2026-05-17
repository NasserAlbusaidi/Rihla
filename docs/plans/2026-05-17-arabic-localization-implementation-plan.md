# Arabic Localization PR1 — Foundation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.
>
> **Gate before implementation:** Run `/codex` against this plan before writing any code. Touches routing (MaterialApp wiring), money math surface (shared widgets), and schema-adjacent state (`AppSettings`). All Operating Contract Gate categories apply.

**Goal:** Wire AppLocalizations infrastructure into the Flutter app so Arabic translation can layer on top in subsequent PRs, with the Arabic toggle staying locked ("Coming soon") on `main` until PR2 actually translates user-visible surfaces.

**Architecture:** Add `flutter_localizations` + gen_l10n codegen via `flutter.generate: true`. ARB files in `lib/l10n/`. New `localeProvider` derived from the **existing** `settingsProvider`'s `languageCode` field (not a new `localeCode` — that was a design-doc mistake; the field already exists at `lib/core/models/app_settings_model.dart:9` and is fully wired with persistence). Test helper `pumpRihlaApp` shipped for any test that boots a translated widget. Arabic golden-path integration test + ARB completeness lint script guard regressions.

**Tech Stack:** Flutter ^3.10.1, `flutter_localizations` (SDK), `intl ^0.20.2` (already present), gen_l10n codegen, `google_fonts ^8.0.2` (Reem Kufi for Arabic wordmark).

---

## Source Context

- Original design doc (brainstorm, partially superseded): `docs/plans/2026-05-16-arabic-localization-design.md`
- Grill session decisions: this plan supersedes the design doc where they conflict.
- Memory: `~/.claude/projects/-Users-nasseralbusaidi-Desktop-Personal-Rihla/memory/project_arabic_localization.md`

---

## Locked Decisions (Grill 2026-05-17)

| # | Decision | Lock |
|---|---|---|
| 1 | Locale field | Reuse existing `AppSettings.languageCode` (do NOT add `localeCode`) |
| 2 | PR split | 4 PRs: PR1 infra → PR2 Settings+Profile+Ledger+unlock → PR3 Groups+Events+Home+Activity → PR4 polish |
| 3 | Shared-widget internal strings | Translated in PR1 (audit found only **2 internal strings** in `lib/shared/widgets/`: `offline_banner.dart:38` and `wordmark_logo.dart:44`) |
| 4 | CI verification | Golden-path Arabic integration test + custom `tool/check_arb_completeness.dart` lint |
| 5 | ARB key sharing | Hybrid: `common*` keys for atomic verb labels (`commonSave`, `commonOk`, …); per-feature keys for phrases. **PR1 introduces only `offlineBannerMessage`** (per-feature) since no `common*` keys have a consumer yet — add them lazily when their first caller needs them |
| 6 | Test helper | `pumpRihlaApp(tester, child, {locale, overrides})` shipped in PR1; **no churn migration** of the 491 existing `find.text(` assertions |
| 7 | Router transition flip | Deferred to PR4 polish — Material `SharedAxisTransition.horizontal` default acceptable until real-device QA says otherwise |
| 8 | Toggle reachability | `LanguagePickerSheet` "Coming soon" lock at `lib/features/settings/widgets/language_picker_sheet.dart:42–73` **stays in PR1**. PR2 unlocks. Prevents shipping a half-flipped Arabic state to `main` |
| 9 | Wordmark swap | Internal locale watch in `WordmarkLogo` (NOT an ARB key). Font: Reem Kufi via `google_fonts` |

## PR1 Explicit Non-Goals

- **Don't** translate Settings, Profile, or Ledger screens. Those are PR2.
- **Don't** modify `_sharedAxisTransition` or vertical slide transitions in `app_router.dart`. PR4.
- **Don't** unlock the `LanguagePickerSheet` "Coming soon" radio. PR2.
- **Don't** add unused `common*` ARB keys. Add lazily in the PR that first consumes them.
- **Don't** introduce digit grouping (`NumberFormat('#,##0.000')`) in `RAmount`. That's a separate non-localization concern the design doc bundled by mistake.

## Coverage Gate

CI enforces **80% raw line coverage** (`readiness_check.yml:87`) — design doc's "70%" figure is wrong. Each task below either adds tests proportional to code added or is pure config/scaffolding. Run `flutter test --coverage` after each commit if you suspect drift.

---

## Code-verification corrections (sweep 2026-05-17 ~14:13 GMT+4)

Five citation errors found in the initial draft and corrected below before the `/codex` gate. Logged here so reviewers can confirm the corrected plan matches code rather than re-greping from scratch.

| Was | Now | Source of truth |
|---|---|---|
| `OfflineBanner(isOffline: true)` constructor (Task 7 test) | `const OfflineBanner()` + `connectivityProvider` override in `pumpRihlaApp` | `lib/shared/widgets/offline_banner.dart:8-14` (ConsumerWidget, no params) |
| SharedPreferences seed key `'languageCode'` (Task 11) | `'settings_language'` (the constant is now made public as `SettingsService.languageKey` in Task 11 Step 1) | `lib/core/services/settings_service.dart:8` (`_languageKey = 'settings_language'`) |
| `Key('create_group_screen')` (Task 11) | `GroupKeys.createScreen` literal `Key('group_create_screen')` | `lib/features/groups/keys/group_keys.dart:6` |
| Task 11 skips chooser-sheet branch | Mirrors existing `golden_path_test.dart:117-123` `home_create_group_option` handling | `integration_test/golden_path_test.dart:117-123` |
| `dart run tool/check_no_hardcoded_colors.dart` (Task 12) | `bash tool/check_theme_purity.sh` | `tool/check_theme_purity.sh` (`check_no_hardcoded_colors.dart` does not exist) |

Also fixed: Task 9's `import 'package:safar_tool/...'` (no such package) → relative import from `test/tool/`.

---

## Task 1: Add `flutter_localizations` dependency + codegen flag

**Files:**
- Modify: `pubspec.yaml`

**Step 1: Inspect current pubspec**

Run: `grep -nE "dependencies:|flutter_localizations|flutter:|generate:" pubspec.yaml`

Confirm: `flutter_localizations` is absent; `flutter.generate` is absent or false.

**Step 2: Edit `pubspec.yaml`**

Under `dependencies:` (typically right after the `flutter: sdk: flutter` block), add:

```yaml
  flutter_localizations:
    sdk: flutter
```

In the existing `flutter:` block (toward bottom of file), add `generate: true` as the first key:

```yaml
flutter:
  generate: true
  uses-material-design: true
  # ... existing entries unchanged
```

**Step 3: Run pub get and verify**

Run: `flutter pub get`
Expected: Completes with no errors. `flutter_localizations` resolves from SDK.

**Step 4: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "chore(l10n): add flutter_localizations dep and enable gen_l10n codegen"
```

---

## Task 2: ARB scaffolding + `l10n.yaml`

**Files:**
- Create: `l10n.yaml` (repo root)
- Create: `lib/l10n/app_en.arb`
- Create: `lib/l10n/app_ar.arb`

**Step 1: Create `l10n.yaml` at repo root**

```yaml
arb-dir: lib/l10n
template-arb-file: app_en.arb
output-localization-file: app_localizations.dart
output-dir: lib/l10n/generated
nullable-getter: false
```

Notes on what's intentionally absent:

- **No `synthetic-package` line.** The plan originally specified `synthetic-package: false`, but the spike (worktree `spike/l10n-codegen-check`, 2026-05-17 ~14:30) showed Flutter now prints `"The argument \"synthetic-package\" no longer has any effect and should be removed. See http://flutter.dev/to/flutter-gen-deprecation"` on `flutter pub get`. The modern default is non-synthetic, which is exactly what we want. Do not add this line back — it's noise in CI output and a confusion vector for future devs.
- **`output-dir: lib/l10n/generated`** keeps generated files out of hand-edited source paths and makes IDE navigation explicit (spike confirmed the three expected files land here).
- **`nullable-getter: false`** makes `AppLocalizations.of(context)` return non-nullable — assumes the app's localization delegates are always present (verified true in `pumpRihlaApp` and `MaterialApp.router` wiring).

**Step 2: Create `lib/l10n/app_en.arb`**

```json
{
  "@@locale": "en",
  "offlineBannerMessage": "You're offline — changes will sync later",
  "@offlineBannerMessage": {
    "description": "Banner shown when device is offline; reassures user that pending writes will be sent on reconnect."
  }
}
```

**Step 3: Create `lib/l10n/app_ar.arb`**

```json
{
  "@@locale": "ar",
  "offlineBannerMessage": "أنت غير متصل — ستتم مزامنة التغييرات لاحقًا"
}
```

(User reviews this Arabic string in the PR comment before merge per the locked review workflow.)

**Step 4: Trigger codegen**

Run: `flutter pub get`
Expected: Codegen runs as a pub side-effect. Verify the file exists:

```bash
ls lib/l10n/generated/app_localizations*.dart
```

Expected: Three files (`app_localizations.dart`, `app_localizations_en.dart`, `app_localizations_ar.dart`).

**Step 5: Run analyze**

Run: `flutter analyze`
Expected: Clean (no warnings or errors).

**Step 6: Confirm generated files are tracked (adjust `.gitignore` if not)**

**Decision:** Commit `lib/l10n/generated/*.dart` to the repo. Reasoning: the analyzer, tests, and IDE all import from them; not committing means every fresh checkout has to `pub get` before `flutter analyze` will pass, and CI's coverage step would not see them as instrumented source. Treat them as generated-but-tracked, like `lib/firebase_options.dart`. (The actual commit happens in Step 7 — this step is just the tracking-status check.)

Run:

```bash
git check-ignore lib/l10n/generated/app_localizations.dart && echo "BAD: gitignored" || echo "OK: tracked"
```

If gitignored (the project's `.gitignore` does ignore some `build/` and `.dart_tool/` paths but `lib/l10n/generated/` is not under either, so this should print `OK: tracked` without any change), add an exception in `.gitignore`:

```
!lib/l10n/generated/
```

**Step 7: Commit**

```bash
git add l10n.yaml lib/l10n/ .gitignore
git commit -m "feat(l10n): add ARB scaffolding with offlineBannerMessage key (en + ar)"
```

---

## Task 3: `context.l10n` extension

**Files:**
- Create: `lib/core/extensions/build_context_l10n.dart` (`lib/core/extensions/` is a new directory — there are no existing extension files under `lib/core/`; closest precedent is `extension AppThemeExtensions on BuildContext` in `lib/core/theme/tokens/domain_aliases.dart:21`, which is the pattern this file mirrors)
- Create: `test/core/extensions/build_context_l10n_test.dart`

**Step 1: Write the failing test**

```dart
// test/core/extensions/build_context_l10n_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/core/extensions/build_context_l10n.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

void main() {
  testWidgets('context.l10n returns AppLocalizations for current locale', (
    tester,
  ) async {
    late AppLocalizations captured;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            captured = context.l10n;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(captured.offlineBannerMessage, "You're offline — changes will sync later");
  });
}
```

**Step 2: Run test, expect failure**

Run: `flutter test test/core/extensions/build_context_l10n_test.dart`
Expected: FAIL — `build_context_l10n.dart` not found.

**Step 3: Create the extension**

```dart
// lib/core/extensions/build_context_l10n.dart
import 'package:flutter/widgets.dart';

import '../../l10n/generated/app_localizations.dart';

/// Shorthand for `AppLocalizations.of(context)`.
///
/// Throws if no [AppLocalizations] is registered above [context] (i.e., the
/// widget tree has no `localizationsDelegates` configured). All app-booting
/// production paths and `pumpRihlaApp` test helper wire delegates by default,
/// so a missing delegate indicates a misconfigured test.
extension BuildContextL10n on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}
```

**Step 4: Run test, expect pass**

Run: `flutter test test/core/extensions/build_context_l10n_test.dart`
Expected: PASS.

**Step 5: Commit**

```bash
git add lib/core/extensions/build_context_l10n.dart test/core/extensions/build_context_l10n_test.dart
git commit -m "feat(l10n): add context.l10n extension"
```

---

## Task 4: `localeProvider` derived from settings

**Files:**
- Modify: `lib/core/providers/settings_provider.dart`
- Modify: `test/unit/settings_notifier_test.dart` (add cases)

**Step 1: Write failing tests**

Add to `test/unit/settings_notifier_test.dart`:

```dart
group('localeProvider', () {
  test('returns Locale("en") when languageCode is "en"', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);
    expect(container.read(localeProvider), const Locale('en'));
  });

  test('returns Locale("ar") after setLanguage("ar")', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);
    await container.read(settingsProvider.notifier).setLanguage('ar');
    expect(container.read(localeProvider), const Locale('ar'));
  });
});
```

**Step 2: Run test, expect failure**

Run: `flutter test test/unit/settings_notifier_test.dart`
Expected: FAIL — `localeProvider` undefined.

**Step 3: Add provider to `lib/core/providers/settings_provider.dart`**

Append after existing providers (do not modify existing code):

```dart
/// Locale derived from [settingsProvider]'s `languageCode`.
///
/// Pass into `MaterialApp.locale`. Reuses the existing `languageCode` field on
/// [AppSettings] — there is no separate `localeCode`.
final localeProvider = Provider<Locale>((ref) {
  final code = ref.watch(
    settingsProvider.select((s) => s.languageCode),
  );
  return Locale(code);
});
```

Ensure the file imports `package:flutter/widgets.dart` for `Locale` (add if missing).

**Step 4: Run test, expect pass**

Run: `flutter test test/unit/settings_notifier_test.dart`
Expected: PASS.

**Step 5: Commit**

```bash
git add lib/core/providers/settings_provider.dart test/unit/settings_notifier_test.dart
git commit -m "feat(l10n): add localeProvider derived from settings.languageCode"
```

---

## Task 5: Wire delegates + locale into `MaterialApp.router`

**Files:**
- Modify: `lib/main.dart:181-189`

**Step 1: Read current state**

Run: `sed -n '173,192p' lib/main.dart`

Expected: `MaterialApp.router(...)` block with `title`, `debugShowCheckedModeBanner`, `scaffoldMessengerKey`, `theme`, `darkTheme`, `themeMode`, `routerConfig`.

**Step 2: Edit `MaterialApp.router` to add three properties**

Inside the existing `MaterialApp.router(...)`, add (alphabetical-ish where possible):

```dart
        locale: ref.watch(localeProvider),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
```

Add the import to top of file:

```dart
import 'l10n/generated/app_localizations.dart';
```

**Step 3: Regression check — existing golden_path_test still passes**

Run the existing iOS-sim integration test (no Arabic yet, just verifying the wiring doesn't break the LTR cold-boot flow):

```bash
firebase emulators:start --only auth,firestore,functions &
EMU_PID=$!
flutter test integration_test/golden_path_test.dart \
  -d <ios-sim-id-here> \
  --dart-define-from-file=config.test.json
kill $EMU_PID
```

Expected: PASS, same as the commit c05d3c6 baseline. If FAIL, the delegate wiring is misconfigured.

**Step 4: Run analyze**

Run: `flutter analyze`
Expected: Clean.

**Step 5: Commit**

```bash
git add lib/main.dart
git commit -m "feat(l10n): wire AppLocalizations delegates + locale into MaterialApp.router"
```

---

## Task 6: `pumpRihlaApp` test helper

**Files:**
- Create: `test/helpers/pump_rihla_app.dart`
- Create: `test/helpers/pump_rihla_app_test.dart`

**Step 1: Write failing test**

```dart
// test/helpers/pump_rihla_app_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safar/core/extensions/build_context_l10n.dart';

import 'pump_rihla_app.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('pumpRihlaApp defaults to English locale', (tester) async {
    String captured = '';
    await pumpRihlaApp(
      tester,
      Builder(
        builder: (context) {
          captured = context.l10n.offlineBannerMessage;
          return const SizedBox.shrink();
        },
      ),
    );
    expect(captured, "You're offline — changes will sync later");
  });

  testWidgets('pumpRihlaApp honors explicit locale override', (tester) async {
    String captured = '';
    await pumpRihlaApp(
      tester,
      Builder(
        builder: (context) {
          captured = context.l10n.offlineBannerMessage;
          return const SizedBox.shrink();
        },
      ),
      locale: const Locale('ar'),
    );
    expect(captured, "أنت غير متصل — ستتم مزامنة التغييرات لاحقًا");
  });
}
```

**Step 2: Run test, expect failure**

Run: `flutter test test/helpers/pump_rihla_app_test.dart`
Expected: FAIL — `pump_rihla_app.dart` not found.

**Step 3: Create the helper**

```dart
// test/helpers/pump_rihla_app.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safar/core/providers/settings_provider.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

/// Pumps [child] inside a minimal Rihla app shell:
/// `ProviderScope` (with `sharedPreferencesProvider` overridden by default)
/// → `MaterialApp` (with localization delegates and theme).
///
/// Defaults to English locale. Pass [locale] to force Arabic. Pass [overrides]
/// to inject additional Riverpod overrides on top of the SharedPreferences
/// default.
///
/// **Router-aware tests are NOT supported by this helper** — it wraps `child`
/// in a plain `MaterialApp`, not `MaterialApp.router`. PR1's translated
/// surfaces (`OfflineBanner`, `WordmarkLogo`) don't navigate, so the trade
/// is acceptable. When PR3 needs to widget-test a screen that calls
/// `context.go(...)` or asserts on a route guard, add a sibling
/// `pumpRihlaAppRouted` helper rather than overloading this one.
///
/// **Locale wiring drift, by design:** this helper passes [locale] directly
/// into `MaterialApp`, bypassing both `settingsProvider` and `localeProvider`.
/// Unit tests using this helper therefore CANNOT catch a regression where
/// `localeProvider` is wired wrong but `MaterialApp.locale` happens to be
/// hardcoded somewhere. The Arabic golden-path integration test (Task 11)
/// is the only PR1 coverage for the full `settings → localeProvider →
/// MaterialApp.router(locale)` chain.
Future<void> pumpRihlaApp(
  WidgetTester tester,
  Widget child, {
  Locale locale = const Locale('en'),
  List<Override> overrides = const [],
}) async {
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        ...overrides,
      ],
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: AppTheme.lightTheme,
        home: child,
      ),
    ),
  );
  await tester.pumpAndSettle();
}
```

**Step 4: Run test, expect pass**

Run: `flutter test test/helpers/pump_rihla_app_test.dart`
Expected: PASS.

**Step 5: Commit**

```bash
git add test/helpers/pump_rihla_app.dart test/helpers/pump_rihla_app_test.dart
git commit -m "feat(l10n): add pumpRihlaApp test helper with locale override"
```

---

## Task 7: Translate `OfflineBanner` internal string

**Files:**
- Modify: `lib/shared/widgets/offline_banner.dart`
- Create or modify: `test/shared/widgets/offline_banner_test.dart` (likely already exists; check first)

**Step 1: Check existing test**

Run: `ls test/shared/widgets/offline_banner_test.dart 2>/dev/null || echo "missing"`

If missing, create one. If exists, plan to add cases.

**Step 2: Write failing test (LTR + RTL render)**

`OfflineBanner` is a `ConsumerWidget` with no constructor params; it reads `connectivityProvider` (`StateNotifierProvider<ConnectivityNotifier, ConnectivityStatus>`). To force the offline render branch in tests, override the provider with a fake `StateNotifier` that skips `ConnectivityNotifier`'s real-network probe and timer (`lib/core/providers/connectivity_provider.dart:30-65` — the real notifier starts a periodic Firestore probe in its constructor, which we do not want in a widget test).

Add cases (whether new file or existing):

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/core/providers/connectivity_provider.dart';
import 'package:safar/shared/widgets/offline_banner.dart';

import '../../helpers/pump_rihla_app.dart';

class _FakeConnectivity extends StateNotifier<ConnectivityStatus> {
  _FakeConnectivity(super.initial);
}

void main() {
  testWidgets('OfflineBanner renders English offline message in en locale',
      (tester) async {
    await pumpRihlaApp(
      tester,
      const OfflineBanner(),
      overrides: [
        connectivityProvider.overrideWith(
          (ref) => _FakeConnectivity(ConnectivityStatus.offline),
        ),
      ],
    );
    expect(
      find.text("You're offline — changes will sync later"),
      findsOneWidget,
    );
  });

  testWidgets('OfflineBanner renders Arabic offline message in ar locale',
      (tester) async {
    await pumpRihlaApp(
      tester,
      const OfflineBanner(),
      locale: const Locale('ar'),
      overrides: [
        connectivityProvider.overrideWith(
          (ref) => _FakeConnectivity(ConnectivityStatus.offline),
        ),
      ],
    );
    expect(
      find.text("أنت غير متصل — ستتم مزامنة التغييرات لاحقًا"),
      findsOneWidget,
    );
  });
}
```

The English assertion uses `—` to match the source (line 38 of `offline_banner.dart` already uses the escape, not a literal em-dash). The Arabic side uses a literal em-dash to match the ARB file in Task 2 Step 3.

**Step 3: Run test, expect failure**

Run: `flutter test test/shared/widgets/offline_banner_test.dart`
Expected: FAIL — Arabic string not found (the widget still hardcodes English).

**Step 4: Edit `offline_banner.dart:38`**

Replace the hardcoded string:

```dart
// Before:
Text(
  "You're offline — changes will sync later",
  // ...
)

// After:
Text(
  context.l10n.offlineBannerMessage,
  // ...
)
```

Add import to top:

```dart
import '../../core/extensions/build_context_l10n.dart';
```

**Step 5: Run test, expect pass**

Run: `flutter test test/shared/widgets/offline_banner_test.dart`
Expected: PASS.

**Step 6: Run full analyze + suite**

Run: `flutter analyze && flutter test`
Expected: Clean + all green.

**Step 7: Commit**

```bash
git add lib/shared/widgets/offline_banner.dart test/shared/widgets/offline_banner_test.dart
git commit -m "feat(l10n): translate OfflineBanner via context.l10n.offlineBannerMessage"
```

---

## Task 8: `AppTypography.arabicDisplay()` + `WordmarkLogo` locale watch

**Decision (grill 2026-05-17 Q5):** Reem Kufi goes through `AppTypography.arabicDisplay()`, mirroring the existing `AppTypography.display()` for Instrument Serif. Two reasons: (1) WordmarkLogo would otherwise route English through `AppTypography` and Arabic inline — an asymmetry inside one widget that future readers would have to re-derive; (2) `display()` defaults `italic: true`, but Reem Kufi has no italic style, so shoehorning it into `display(arabic: true)` would force every Arabic caller to override the italic default. A dedicated `arabicDisplay()` keeps the API honest.

**Files:**
- Modify: `lib/core/theme/tokens/typography_tokens.dart` (add `arabicDisplay` static method)
- Create: `test/unit/typography_tokens_test.dart` (or extend existing if found)
- Modify: `lib/shared/widgets/wordmark_logo.dart:44`
- Create or modify: `test/shared/widgets/wordmark_logo_test.dart`

**Step 1: Verify google_fonts Reem Kufi support**

Run: `grep -r "ReemKufi\|reem_kufi" lib/ pubspec.yaml 2>/dev/null`

Expected: No existing usage. We'll be the first caller.

`google_fonts ^8.0.2` supports Reem Kufi via `GoogleFonts.reemKufi()`. No `pubspec.yaml` asset declaration needed — the package fetches at runtime in production. In tests, `test/flutter_test_config.dart:21` already disables runtime fetching (`GoogleFonts.config.allowRuntimeFetching = false`), so the test will fall back to the platform default Arabic font. That's correct test behavior — we're testing the locale-switch logic, not the font glyphs themselves.

**Step 2: Write failing typography test**

Create or extend `test/unit/typography_tokens_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/core/theme/tokens/typography_tokens.dart';

void main() {
  group('AppTypography.arabicDisplay', () {
    test('returns a TextStyle backed by Reem Kufi', () {
      final style = AppTypography.arabicDisplay(fontSize: 22);
      expect(style.fontSize, 22);
      // GoogleFonts assigns a synthetic family name; just confirm it set one.
      expect(style.fontFamily, isNotNull);
      // Reem Kufi has no italic; the helper must NOT default italic on.
      expect(style.fontStyle, isNot(FontStyle.italic));
    });

    test('honors color, weight, letterSpacing overrides', () {
      final style = AppTypography.arabicDisplay(
        fontSize: 60,
        color: const Color(0xFF112233),
        fontWeight: FontWeight.w600,
        letterSpacing: -2,
      );
      expect(style.color, const Color(0xFF112233));
      expect(style.fontWeight, FontWeight.w600);
      expect(style.letterSpacing, -2);
    });
  });
}
```

**Step 3: Run typography test, expect failure**

Run: `flutter test test/unit/typography_tokens_test.dart`
Expected: FAIL — `arabicDisplay` undefined.

**Step 4: Add `AppTypography.arabicDisplay()`**

In `lib/core/theme/tokens/typography_tokens.dart`, add after the existing `display()` method (~line 55) and add a `reemKufiFamily` constant alongside the other family constants:

```dart
/// Reem Kufi family name as used by `google_fonts.getFont`.
static const String reemKufiFamily = 'Reem Kufi';

/// Arabic display style — Reem Kufi.
///
/// Mirrors [display] for Latin script. Reem Kufi has no italic style and
/// Arabic typography doesn't mark emphasis this way, so this helper
/// intentionally does NOT expose an `italic` parameter.
///
/// Use in the Arabic branch of widgets that pick a script-specific display
/// face — currently only [WordmarkLogo]; expected callers in PR2 (Settings
/// header) and PR3 (group-name display) per Arabic localization plan.
static TextStyle arabicDisplay({
  required double fontSize,
  Color? color,
  FontWeight fontWeight = FontWeight.w400,
  double? letterSpacing,
  double? height,
}) {
  return GoogleFonts.getFont(
    reemKufiFamily,
    fontSize: fontSize,
    fontWeight: fontWeight,
    color: color,
    letterSpacing: letterSpacing,
    height: height,
  );
}
```

**Step 5: Run typography test, expect pass**

Run: `flutter test test/unit/typography_tokens_test.dart`
Expected: PASS.

**Step 6: Write failing WordmarkLogo test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:safar/shared/widgets/wordmark_logo.dart';

import '../../helpers/pump_rihla_app.dart';

void main() {
  testWidgets('WordmarkLogo renders "Rihla" in en locale', (tester) async {
    await pumpRihlaApp(tester, const WordmarkLogo());
    expect(find.text('Rihla'), findsOneWidget);
    expect(find.text('رحلة'), findsNothing);
  });

  testWidgets('WordmarkLogo renders "رحلة" in ar locale', (tester) async {
    await pumpRihlaApp(
      tester,
      const WordmarkLogo(),
      locale: const Locale('ar'),
    );
    expect(find.text('رحلة'), findsOneWidget);
    expect(find.text('Rihla'), findsNothing);
  });
}
```

**Step 7: Run WordmarkLogo test, expect failure**

Run: `flutter test test/shared/widgets/wordmark_logo_test.dart`
Expected: FAIL — Arabic version not rendered.

**Step 8: Edit `lib/shared/widgets/wordmark_logo.dart`**

Replace the hardcoded `'Rihla'` Text widget at line 43–51 with a locale-branched version. Both branches route through `AppTypography` for symmetry:

```dart
final locale = Localizations.localeOf(context);
final isArabic = locale.languageCode == 'ar';
final wordmarkText = isArabic ? 'رحلة' : 'Rihla';
final wordmarkStyle = isArabic
    ? AppTypography.arabicDisplay(
        fontSize: size,
        color: ink,
        // Preserve letterSpacing curve from the English path.
        letterSpacing: size > 60 ? -3 : -1.5,
        height: 1.0,
      )
    : AppTypography.display(
        fontSize: size,
        color: ink,
        letterSpacing: size > 60 ? -3 : -1.5,
        height: 1.0,
      );
```

Then wrap the result with `Semantics(label: 'Rihla', child: ...)` so screen readers consistently identify the brand regardless of locale (TalkBack/VoiceOver will read the Arabic glyph as "رحلة" by default, which is fine for Arabic users but obscures the brand name in en-with-Arabic-display contexts — `Semantics` overrides that).

Add import:

```dart
import '../../core/theme/tokens/typography_tokens.dart';
```

(No `google_fonts` import needed — `AppTypography.arabicDisplay` encapsulates it.)

**Step 9: Run WordmarkLogo test, expect pass**

Run: `flutter test test/shared/widgets/wordmark_logo_test.dart`
Expected: PASS.

**Step 10: Verify analyze**

Run: `flutter analyze`
Expected: Clean.

**Step 11: Commit (as two atomic commits)**

Per CLAUDE.md "smaller change + follow-up, don't bundle" — `arabicDisplay()` is a typography-system add and WordmarkLogo is a widget edit. Two commits keep the diff reviewable:

```bash
git add lib/core/theme/tokens/typography_tokens.dart test/unit/typography_tokens_test.dart
git commit -m "feat(l10n): add AppTypography.arabicDisplay() backed by Reem Kufi"

git add lib/shared/widgets/wordmark_logo.dart test/shared/widgets/wordmark_logo_test.dart
git commit -m "feat(l10n): WordmarkLogo swaps to Arabic glyph + Reem Kufi in ar locale"
```

---

## Task 9: ARB completeness lint script

**Files:**
- Create: `tool/check_arb_completeness.dart`
- Create: `test/unit/check_arb_completeness_test.dart`

**Note on test location (grill 2026-05-17 Q8b):** CI's `readiness_check.yml:60-72` runs `flutter test --coverage` against an explicit list of test dirs (`test/architecture test/core test/features test/helpers test/integration test/shared test/unit test/widget_test.dart`) — `test/tool` is NOT in that list. Putting the test in `test/unit/` ensures it runs in CI (and counts toward coverage in the unlikely event the tool migrates under `lib/`). The script itself stays in `tool/`; only the test moves.

**Step 1: Write failing test**

```dart
import 'package:flutter_test/flutter_test.dart';

// Tool scripts in `tool/` are not packaged — import relatively.
import '../../tool/check_arb_completeness.dart' as checker;

void main() {
  test('matching key sets pass', () {
    final result = checker.compare(
      en: {'@@locale': 'en', 'offlineBannerMessage': 'X'},
      ar: {'@@locale': 'ar', 'offlineBannerMessage': 'Y'},
    );
    expect(result.missingInAr, isEmpty);
    expect(result.extraInAr, isEmpty);
  });

  test('detects keys present in en but missing in ar', () {
    final result = checker.compare(
      en: {'@@locale': 'en', 'a': '1', 'b': '2'},
      ar: {'@@locale': 'ar', 'a': '1'},
    );
    expect(result.missingInAr, ['b']);
  });

  test('detects keys present in ar but missing in en', () {
    final result = checker.compare(
      en: {'@@locale': 'en', 'a': '1'},
      ar: {'@@locale': 'ar', 'a': '1', 'extra': 'x'},
    );
    expect(result.extraInAr, ['extra']);
  });

  test('ignores @-prefixed metadata keys', () {
    final result = checker.compare(
      en: {'@@locale': 'en', 'a': '1', '@a': {'description': 'doc'}},
      ar: {'@@locale': 'ar', 'a': '1'},
    );
    expect(result.missingInAr, isEmpty);
  });
}
```

(The plan originally used `package:safar_tool/...` — there is no such package; corrected to a relative import above. Files in `tool/` are run as scripts via `dart run tool/<name>.dart`, not as a library package.)

**Step 2: Run test, expect failure**

Run: `flutter test test/unit/check_arb_completeness_test.dart`
Expected: FAIL — file not found.

**Step 3: Create `tool/check_arb_completeness.dart`**

```dart
// tool/check_arb_completeness.dart
//
// Compares ARB key sets across locales. Run via:
//   dart run tool/check_arb_completeness.dart
//
// Exits 0 on match, 1 with a list of missing/extra keys on mismatch.
// Wired into readiness_check.yml CI.

import 'dart:convert';
import 'dart:io';

class CompareResult {
  CompareResult({required this.missingInAr, required this.extraInAr});
  final List<String> missingInAr;
  final List<String> extraInAr;
  bool get ok => missingInAr.isEmpty && extraInAr.isEmpty;
}

bool _isMetadata(String key) => key.startsWith('@');

CompareResult compare({
  required Map<String, dynamic> en,
  required Map<String, dynamic> ar,
}) {
  final enKeys = en.keys.where((k) => !_isMetadata(k)).toSet();
  final arKeys = ar.keys.where((k) => !_isMetadata(k)).toSet();
  return CompareResult(
    missingInAr: enKeys.difference(arKeys).toList()..sort(),
    extraInAr: arKeys.difference(enKeys).toList()..sort(),
  );
}

Future<void> main(List<String> args) async {
  final enPath = 'lib/l10n/app_en.arb';
  final arPath = 'lib/l10n/app_ar.arb';
  final enJson =
      jsonDecode(await File(enPath).readAsString()) as Map<String, dynamic>;
  final arJson =
      jsonDecode(await File(arPath).readAsString()) as Map<String, dynamic>;
  final result = compare(en: enJson, ar: arJson);
  if (result.ok) {
    stdout.writeln('ARB completeness: OK (${enJson.length - 1} keys matched)');
    exit(0);
  }
  if (result.missingInAr.isNotEmpty) {
    stderr.writeln('Keys present in en but missing in ar:');
    for (final k in result.missingInAr) {
      stderr.writeln('  - $k');
    }
  }
  if (result.extraInAr.isNotEmpty) {
    stderr.writeln('Keys present in ar but missing in en:');
    for (final k in result.extraInAr) {
      stderr.writeln('  - $k');
    }
  }
  exit(1);
}
```

**Step 4: Run test, expect pass**

Run: `flutter test test/unit/check_arb_completeness_test.dart`
Expected: PASS.

**Step 5: Run the script against current ARB**

Run: `dart run tool/check_arb_completeness.dart`
Expected: `ARB completeness: OK (1 keys matched)` (one key: `offlineBannerMessage`).

**Step 6: Commit**

```bash
git add tool/check_arb_completeness.dart test/unit/check_arb_completeness_test.dart
git commit -m "feat(l10n): add ARB completeness lint script"
```

---

## Task 10: Wire ARB lint into CI

**Files:**
- Modify: `.github/workflows/readiness_check.yml`

**Step 1: Read existing CI structure**

Run: `grep -n "name:\|run:" .github/workflows/readiness_check.yml`

Existing lint step (verified): `- name: Theme purity check` at line 54 with `run: bash tool/check_theme_purity.sh` at line 55. Insert the new ARB step right after Theme purity (and before "Firebase emulator rules and Functions tests" at line 57) so all repo-local static checks cluster together.

**Step 2: Add step adjacent to Theme purity check**

```yaml
      - name: ARB completeness check
        run: dart run tool/check_arb_completeness.dart
```

**Step 3: Verify locally**

Run: `act -j readiness_check 2>/dev/null || echo "skipping local act — verify in CI"`

(Or just inspect the YAML diff for correctness.)

**Step 4: Commit**

```bash
git add .github/workflows/readiness_check.yml
git commit -m "ci(l10n): run ARB completeness check in readiness gate"
```

---

## Task 11: Arabic golden-path integration test

**Files:**
- Modify: `lib/core/services/settings_service.dart` (prep — expose `languageKey` constant)
- Create: `integration_test/golden_path_arabic_test.dart`

**Step 1: Prep — expose `SettingsService.languageKey`**

The persistence key needs to be importable from the integration test so the seed and the read stay in lockstep. In `lib/core/services/settings_service.dart`, drop the leading underscore on `_languageKey` (line 8) so it becomes `static const String languageKey = 'settings_language';`. Update the one internal reference (line 27 + 57) to use the new name.

```bash
grep -n "_languageKey\|languageKey" lib/core/services/settings_service.dart
```

Run `flutter analyze` after — expect clean.

**Step 2: Read existing English golden-path test**

```bash
cat integration_test/golden_path_test.dart
```

Note the structure: cold-boot → optional-onboarding → home → skeleton-drain → FAB → optional-chooser-sheet → create-group. The chooser-sheet branch (`Key('home_create_group_option')`) exists at lines 117–123 and must be preserved in the Arabic mirror, since the chooser appears on the empty-state path that a fresh emulator user will hit.

**Step 3: Create Arabic variant**

The Arabic test forces locale to `ar` regardless of the (still-locked) Settings toggle by writing the correct key (`SettingsService.languageKey = 'settings_language'`) to SharedPreferences before `app.main()` runs. The settings notifier reads this on boot via `SharedPreferences.getInstance()` → `SettingsService.loadSettings()`.

```dart
// integration_test/golden_path_arabic_test.dart
//
// Mirror of golden_path_test.dart but boots the app in Arabic locale by
// pre-seeding SharedPreferences. Catches RTL render exceptions, missing
// ARB key fallbacks, and broken transition layouts in ar without unlocking
// the user-facing toggle (still "Coming soon" in PR1).
//
// Run with:
//   firebase emulators:start --only auth,firestore,functions  # other terminal
//   flutter test integration_test/golden_path_arabic_test.dart \
//     -d <ios-sim-id> \
//     --dart-define-from-file=config.test.json

import 'dart:io' show Platform;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:skeletonizer/skeletonizer.dart';

import 'package:safar/core/services/settings_service.dart';
import 'package:safar/main.dart' as app;

late IntegrationTestWidgetsFlutterBinding _binding;

void main() {
  _binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    // Seed via the SAME constant SettingsService.loadSettings reads.
    // Hard-coding 'settings_language' here would silently regress if the
    // constant is ever renamed (which is exactly the bug this seed-key
    // import prevents — see PR description's "code-verification corrections"
    // note).
    SharedPreferences.setMockInitialValues(<String, Object>{
      SettingsService.languageKey: 'ar',
    });
  });

  testWidgets('cold boot in ar → home → create group (no exceptions)',
      (tester) async {
    _log('--- TEST START (locale=ar) ---');
    app.main();

    // The empty-onboarding branch from golden_path_test.dart:33-77 applies
    // identically here — if onboarding is dead code today, we land on home
    // directly; if it's re-wired, we walk through it. The labels are still
    // English in PR1 because Settings/Onboarding aren't translated yet
    // (per PR1 non-goals); PR3 makes onboarding strings ARB-driven.
    await _waitFor(
      tester,
      label: 'onboarding-or-home',
      predicate: () =>
          find.text('Begin').evaluate().isNotEmpty ||
          find.byKey(const Key('home_screen')).evaluate().isNotEmpty,
      timeout: const Duration(seconds: 90),
    );

    if (find.byKey(const Key('home_screen')).evaluate().isEmpty) {
      // Onboarding path — copy the 3-tap walk from golden_path_test.dart.
      await tester.tap(find.text('Begin').first);
      await _settle(tester);
      await _waitFor(
        tester,
        label: 'onboarding-p2',
        predicate: () => find.text('Next').evaluate().isNotEmpty,
      );
      await tester.tap(find.text('Next').first);
      await _settle(tester);
      await _waitFor(
        tester,
        label: 'onboarding-p3',
        predicate: () => find.text('Open Rihla').evaluate().isNotEmpty,
      );
      await tester.tap(find.text('Open Rihla').first);
      await _settle(tester);
    }

    await _waitFor(
      tester,
      label: 'home_screen',
      predicate: () =>
          find.byKey(const Key('home_screen')).evaluate().isNotEmpty,
    );
    _log('CHECKPOINT: home rendered (ar)');

    // Same Skeletonizer drain pattern as golden_path_test.dart:91-96.
    await _waitFor(
      tester,
      label: 'skeleton cleared',
      predicate: () => find.byType(Skeletonizer).evaluate().isEmpty,
      timeout: const Duration(seconds: 30),
    );
    await tester.pump(const Duration(milliseconds: 1500));

    final fab = find.byKey(const Key('home_create_group_fab'));
    expect(fab, findsOneWidget,
        reason: 'home_create_group_fab missing after skeleton clear (ar)');
    await tester.ensureVisible(fab);
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await tester.tap(fab);
    await _settle(tester);

    // Mirror chooser-sheet branch from golden_path_test.dart:117-123 — the
    // empty-state path pops a "create vs join" chooser before the form.
    final createOption = find.byKey(const Key('home_create_group_option'));
    if (createOption.evaluate().isNotEmpty) {
      _log('CHECKPOINT: tapping create-group option in chooser sheet (ar)');
      await tester.tap(createOption);
      await _settle(tester);
    }

    // Real key from lib/features/groups/keys/group_keys.dart:6 —
    // GroupKeys.createScreen = Key('group_create_screen').
    await _waitFor(
      tester,
      label: 'group_create_screen',
      predicate: () =>
          find.byKey(const Key('group_create_screen')).evaluate().isNotEmpty,
    );

    _log('--- TEST PASSED (locale=ar) ---');
  });
}

// _waitFor / _settle / _log mirror the existing helpers in
// integration_test/golden_path_test.dart:159-209. Cross-test refactor into
// integration_test/_helpers.dart is deferred — out of scope for PR1.

Future<void> _waitFor(
  WidgetTester tester, {
  required String label,
  required bool Function() predicate,
  Duration timeout = const Duration(seconds: 20),
  Duration interval = const Duration(milliseconds: 250),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (predicate()) return;
    await tester.pump(interval);
  }
  fail('Timeout (${timeout.inSeconds}s) waiting for: $label');
}

Future<void> _settle(
  WidgetTester tester, {
  Duration timeout = const Duration(seconds: 8),
}) async {
  try {
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      timeout,
    );
  } catch (_) {
    // Live Firestore streams keep emitting; pumpAndSettle will time out.
    await tester.pump(const Duration(milliseconds: 500));
  }
}

void _log(String msg) {
  // ignore: avoid_print
  print('[golden_path_ar] $msg');
}
```

**Step 4: Run test**

```bash
firebase emulators:start --only auth,firestore,functions &
EMU_PID=$!
sleep 8

# Pick a booted iOS sim (memory note: iPhone 17 series booted on 2026-05-17)
SIM_ID=$(xcrun simctl list devices booted | grep "iPhone" | head -1 | grep -oE "[A-F0-9-]{36}")

flutter test integration_test/golden_path_arabic_test.dart \
  -d "$SIM_ID" \
  --dart-define-from-file=config.test.json

kill $EMU_PID
```

Expected: PASS — app boots in ar, home renders, FAB is reachable, create-group route mounts.

**Smoke check the seed actually took effect:** before the FAB tap, the `OfflineBanner` either renders the Arabic string (if the test device is offline at boot — unlikely in CI) or doesn't render at all. The most robust positive signal in this test is that the test PASSES end-to-end while `SettingsService.languageKey` is seeded to `'ar'` AND the `pump_rihla_app_test.dart` ar-locale assertion in Task 6 is green — together those prove the boot path picked up the seed and that Arabic glyphs render. If either fails, the seed didn't take.

**Step 5: Commit**

```bash
git add lib/core/services/settings_service.dart integration_test/golden_path_arabic_test.dart
git commit -m "test(l10n): add Arabic-locale golden-path integration test + expose languageKey"
```

---

## Task 12: Final verification + branch cap

**Step 1: Full test suite + coverage measurement**

```bash
rm -f coverage/lcov.info
flutter test --coverage \
  test/architecture \
  test/core \
  test/features \
  test/helpers \
  test/integration \
  test/shared \
  test/unit \
  test/widget_test.dart
lcov --summary coverage/lcov.info | tee coverage/summary.txt
```

(Test-dir list mirrors `readiness_check.yml:60-72` exactly so the local number matches CI.)

Expected: All green. Line coverage ≥ 80.0% (CI hard floor; current baseline ~82%). Estimate per grill 2026-05-17 Q8a: PR1 adds ~25 hand-written app lines (all covered TDD-style) and ~165 lines of generated `lib/l10n/generated/*.dart` (most exercised organically by `pumpRihlaApp`-using tests). Net effect should be flat or slight rise from baseline. If coverage drops below 80.5%, audit the generated file for uncovered branches before committing — usually `_AppLocalizationsDelegate.shouldReload` or fallback paths.

**Step 2: Analyze**

Run: `flutter analyze`
Expected: Clean.

**Step 3: ARB completeness gate**

Run: `dart run tool/check_arb_completeness.dart`
Expected: `OK`.

**Step 4: Theme purity gate (hardcoded colors / textMuted / direct token reads)**

Run: `bash tool/check_theme_purity.sh`
Expected: Clean (unchanged baseline). This is the actual CI-wired check (`readiness_check.yml:54-55`). The earlier draft of this plan referenced `tool/check_no_hardcoded_colors.dart`, which does not exist.

**Step 5: Inspect the branch diff**

Run: `git diff main...HEAD --stat`
Expected file changes (≈11 commits across these tasks):

```
.github/workflows/readiness_check.yml
.gitignore                                      (if edited in Task 2)
docs/plans/2026-05-17-arabic-localization-implementation-plan.md  (this file)
integration_test/golden_path_arabic_test.dart
l10n.yaml
lib/core/extensions/build_context_l10n.dart
lib/core/providers/settings_provider.dart
lib/core/services/settings_service.dart                (Task 11 Step 1 — _languageKey → languageKey)
lib/core/theme/tokens/typography_tokens.dart           (Task 8 — arabicDisplay)
lib/l10n/app_ar.arb
lib/l10n/app_en.arb
lib/l10n/generated/app_localizations.dart           (generated)
lib/l10n/generated/app_localizations_ar.dart        (generated)
lib/l10n/generated/app_localizations_en.dart        (generated)
lib/main.dart
lib/shared/widgets/offline_banner.dart
lib/shared/widgets/wordmark_logo.dart
pubspec.lock
pubspec.yaml
test/core/extensions/build_context_l10n_test.dart
test/helpers/pump_rihla_app.dart
test/helpers/pump_rihla_app_test.dart
test/shared/widgets/offline_banner_test.dart
test/shared/widgets/wordmark_logo_test.dart
test/unit/check_arb_completeness_test.dart
test/unit/settings_notifier_test.dart
test/unit/typography_tokens_test.dart                  (Task 8 — arabicDisplay test)
tool/check_arb_completeness.dart
```

**Step 6: Create PR**

```bash
gh pr create --title "feat(l10n): PR1 — Arabic localization foundation (toggle stays locked)" --body "$(cat <<'EOF'
## Summary

PR1 of the 4-PR Arabic localization rollout. Ships infrastructure only; the
Arabic toggle remains "Coming soon" in `LanguagePickerSheet` until PR2
translates Settings/Profile/Ledger.

- Add `flutter_localizations` + gen_l10n codegen
- ARB scaffolding (`app_en.arb` + `app_ar.arb`) with one key:
  `offlineBannerMessage`
- `localeProvider` derived from existing `AppSettings.languageCode`
- `MaterialApp.router` wired with delegates + locale
- `context.l10n` extension
- `pumpRihlaApp` test helper (no migration of existing 491 `find.text` calls)
- `OfflineBanner` + `WordmarkLogo` translated (only 2 shared widgets had
  hardcoded internal strings per audit)
- `WordmarkLogo` swaps to Reem Kufi font in `ar` locale
- ARB completeness lint (`tool/check_arb_completeness.dart`) wired into CI
- Arabic golden-path integration test

User-visible delta: **none on `main`** — the toggle is still locked. PR2 will
unlock and translate Settings/Profile/Ledger.

## Test plan

- [x] `flutter analyze` clean
- [x] `flutter test` all green
- [x] `dart run tool/check_arb_completeness.dart` OK
- [x] `integration_test/golden_path_test.dart` regression-passes on iOS sim
- [x] `integration_test/golden_path_arabic_test.dart` passes on iOS sim against Firebase emulator
- [x] Manual: cold-boot the release-mode build on Android — confirm no visible change vs prior baseline

## Notes

- Design doc (`docs/plans/2026-05-16-arabic-localization-design.md`) is
  partially superseded by the 2026-05-17 grill decisions captured in this
  PR's implementation plan.
- Memory updated: `project_arabic_localization.md`.
EOF
)"
```

---

# PR2 / PR3 / PR4 Scope (Plans to Be Written Separately)

These will get their own implementation plans authored at PR1 merge time. Sketch only:

## PR2 — Unlock toggle + translate Settings, Profile, Ledger

- Unlock `LanguagePickerSheet`: remove `enabled: false` on line 69 and `if (code == 'ar') return;` guard on line 45.
- Translate strings in:
  - `lib/features/settings/screens/profile_screen.dart`
  - `lib/features/settings/widgets/language_picker_sheet.dart`
  - Any other `lib/features/settings/`, `lib/features/profile/`
  - `lib/features/ledger/screens/ledger_screen.dart`
  - `lib/features/ledger/screens/add_expense_screen.dart`
  - `lib/features/ledger/screens/edit_expense_screen.dart`
  - `lib/features/ledger/screens/settle_up_screen.dart`
- Localize `_joinGroupErrorMessage` in `lib/features/groups/providers/group_provider.dart:226` and any analogous per-feature error helpers for Ledger.
- RTL audit for these screens: replace `Alignment.centerLeft/centerRight` with `AlignmentDirectional.centerStart/centerEnd`; `EdgeInsets.only(left/right)` → `EdgeInsetsDirectional.only(start/end)` where applicable.
- Add `common*` ARB keys as their consumers come online (Save, Cancel, etc.).
- Re-run Arabic golden-path test; widen to assert at least one translated string is found.

## PR3 — Translate Groups, Events, Home, Activity

- `lib/features/groups/screens/*`
- `lib/features/events/screens/*`
- `lib/features/home/screens/*`
- `lib/features/activity/screens/*`
- Cross-check shared widget consumers for any prop-driven strings still in English.
- RTL audit on all of the above.

## PR4 — Polish

- Decide `_sharedAxisTransition` flip: live with Material default or hand-roll RTL-aware variant (decide on real-device QA evidence).
- `LoadingButton` shimmer gradient direction (`centerLeft → centerRight`).
- `RouteMark` canvas `Offset(146, 60)` mirror (`canvas.scale(-1, 1, dx: size.width)`).
- **`WordmarkLogo._FlourishPainter` RTL mirror** (`wordmark_logo.dart:72-87`). The curl goes low-left → high-right; in RTL it reads as a backwards gesture under "رحلة". Per grill 2026-05-17 Q9, deferred from PR1 because mirroring is a design call wanting real-device-QA evidence, not a mechanical correctness fix. Fix is ~3 lines in `_FlourishPainter.paint`: `if (isArabic) { canvas.scale(-1, 1); canvas.translate(-size.width, 0); }`, with `isArabic` plumbed through the constructor. PR1 ships the wordmark glyph swap but leaves the flourish path direction-agnostic.
- `DotStepIndicator` LTR verification.
- `Icons.chevron_right` in `EventCommandCenter` (dead code per `app_router.dart:99` — leave or strip with broader dead-code cleanup; not a localization concern).
- Update `CLAUDE.md` Do/Don't with `EdgeInsetsDirectional` / `AlignmentDirectional` defaults.
- Add RD-09 row to `docs/REAL-DEVICE-QA.md` for Arabic RTL pass per release.

---

# Gate Reminder

Before any code from this plan is written:

```
/codex
```

Run the codex review against this plan. Surface findings, iterate up to ~2 rounds. The Gate is mandatory for routing + money-math-adjacent + schema-adjacent changes. Approval verdict has no [P1]s = clear to execute.
