# Localization

How Rihla wires Flutter `gen-l10n` codegen, ARB translation files, and
RTL/LTR direction together. Reference for the multi-PR Arabic rollout
(PR1 → PR2a → PR2b → PR3 → PR4) and any future language addition.

For the step-by-step recipe ("translate this screen", "add a new
language"), see [HOWTO-TRANSLATE.md](./HOWTO-TRANSLATE.md). For deeper
design rationale, see CLAUDE.md § OPERATING CONTRACT and `docs/plans/`
for the in-flight l10n plan.

---

## 1. The pipeline at a glance

```
lib/l10n/app_en.arb          ← template (every key lives here first)
lib/l10n/app_ar.arb          ← Arabic translations (RTL)
        │
        ▼
flutter pub get / flutter run   (l10n.yaml triggers gen-l10n)
        │
        ▼
lib/l10n/generated/
  app_localizations.dart         ← AppLocalizations + delegates + supportedLocales
  app_localizations_en.dart      ← English values
  app_localizations_ar.dart      ← Arabic values
        │
        ▼
context.l10n.<key>              ← in widget code
```

Three things make codegen run:

| File | Setting | Effect |
|------|---------|--------|
| `pubspec.yaml` | `flutter: generate: true` | Tells the Flutter tool to invoke `gen-l10n` on `pub get` / `run` / `build`. |
| `l10n.yaml` (repo root) | `arb-dir`, `template-arb-file`, `output-localization-file`, `output-dir`, `nullable-getter: false` | Configures source/destination paths and emits non-nullable `AppLocalizations.of(context)`. |
| `lib/main.dart:182-188` | `MaterialApp.router(locale, localizationsDelegates, supportedLocales)` | Hooks the generated bindings into the app shell. |

The generated files under `lib/l10n/generated/` are **committed** to the
repo so cold clones build without re-running codegen. If you edit an
ARB file, `flutter pub get` (or any `flutter run`) regenerates them in
place; commit both the ARB and the generated diff together.

---

## 2. Configuration files

### `l10n.yaml` (root)

```yaml
arb-dir: lib/l10n
template-arb-file: app_en.arb
output-localization-file: app_localizations.dart
output-dir: lib/l10n/generated
nullable-getter: false
```

`nullable-getter: false` is load-bearing — it makes `AppLocalizations.of(context)`
return a non-null instance and throws if no delegate is registered. The
`context.l10n` extension (next section) relies on this contract.

### `pubspec.yaml`

The relevant lines:

```yaml
dependencies:
  flutter:
    sdk: flutter
  flutter_localizations:
    sdk: flutter
  intl: ^0.20.2

flutter:
  generate: true
```

`flutter_localizations` ships the Material/Cupertino localization
delegates that `AppLocalizations.localizationsDelegates` chains onto.
`intl` is pulled in transitively for `Locale` parsing and date/number
formatting.

---

## 3. ARB files

### Location and shape

```
lib/l10n/
├── app_en.arb       ← template; every key starts here
└── app_ar.arb       ← Arabic translation; mirrors the keys present in English
```

Every ARB entry in `app_en.arb` has a paired `@<key>` block describing
intent for translators. Arabic does not duplicate the descriptions.

```jsonc
// lib/l10n/app_en.arb
{
  "@@locale": "en",

  "commonCancel": "Cancel",
  "@commonCancel": {
    "description": "Generic Cancel action label for dialogs and sheets."
  },
  // ...
}

// lib/l10n/app_ar.arb
{
  "@@locale": "ar",
  "commonCancel": "إلغاء",
  // ...
}
```

### Current coverage

PR2a (the most recently shipped localization PR) brought Arabic up to
parity with English on the Settings + Profile surfaces. Other surfaces
(Ledger, Groups, Home, Auth) still hardcode English; they land in
PR2b / PR3 / PR4 per the active rollout plan.

The Arabic file enables only what has been translated — adding a new
key to `app_en.arb` does **not** automatically translate it. If a key
exists in `app_en.arb` but not `app_ar.arb`, the generated Arabic
binding falls back to the English value at runtime.

### Naming conventions (locked)

- Use camelCase keys grouped by feature: `profileSection*`, `currencySheetTitle`, `languageSheetTitle`, `signOutTitle` …
- Generic action labels are prefixed `common*` (`commonCancel`, `commonSave`, `commonDelete`, `commonOK`) and are reused across surfaces.
- Currency display names are prefixed `currency<ISO>` and listed in `currencyDisplayName` (see § 5).
- Split-mode display names are prefixed `splitMode<Variant>` and listed in `splitModeDisplayName` (see § 5).
- Locale autonyms — `languageEnglish` ("English"), `languageArabic` ("العربية") — are intentionally identical across both ARBs so the picker shows each language in its own script.

### Intentionally English (do not localize)

- **Settings footer brand lockup** — `RIHLA · v<version> · BUILT FOR JOURNEYS` (`_VersionStamp` in `profile_screen.dart`) is a **brand lockup**, not copy. It stays English in every locale, including Arabic, by decision (#162). It is deliberately *not* routed through `context.l10n`. Pinned by `profile_screen_test.dart` ("#162") — if you decide to localize the tagline, reopen that decision and update the test, don't silently flip it.

### Placeholders

Single-value substitution uses `{}` and an `@<key>.placeholders` block:

```jsonc
"profileAboutFallbackEmail": "Email: {email}",
"@profileAboutFallbackEmail": {
  "description": "Fallback contact line when no email app is available.",
  "placeholders": {
    "email": { "type": "String" }
  }
}
```

At call sites the generated binding becomes a typed function:
`context.l10n.profileAboutFallbackEmail('hello@example.com')`.

---

## 4. App wiring (main.dart)

```dart
// lib/main.dart:24
import 'l10n/generated/app_localizations.dart';

// lib/main.dart:182-194
return MaterialApp.router(
  title: 'Rihla',
  scaffoldMessengerKey: appMessengerKey,
  locale: ref.watch(localeProvider),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  // ...
);
```

Three things must be set together for translations to take effect:

| MaterialApp property | Source |
|---|---|
| `locale` | `localeProvider` derived from `settingsProvider.languageCode` (see § 6) |
| `localizationsDelegates` | `AppLocalizations.localizationsDelegates` — generated; chains Material/Cupertino/Widgets delegates plus the app's own |
| `supportedLocales` | `AppLocalizations.supportedLocales` — generated from the present ARB files (`[Locale('en'), Locale('ar')]`) |

Tests must register the same delegates. See [TESTING.md](./TESTING.md)
and the `pumpRihlaApp` helper for the canonical wiring.

---

## 5. Accessing translations in code

### `context.l10n` extension

Every widget should read translations through the shorthand at
`lib/core/extensions/build_context_l10n.dart`:

```dart
extension BuildContextL10n on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}
```

Usage:

```dart
import '../../../core/extensions/build_context_l10n.dart';
// ...
Text(context.l10n.languageSheetTitle);
```

Because the project sets `nullable-getter: false`, `context.l10n`
throws when no `AppLocalizations` delegate is registered above the
widget. In production this cannot happen — `SafarApp` always supplies
delegates. In tests, a missing delegate indicates a misconfigured test
harness; fix by using `pumpRihlaApp` or registering the delegates
manually.

### Currency display names

`lib/core/utils/currency_display_name.dart`:

```dart
String currencyDisplayName(String code, AppLocalizations l10n) {
  switch (code) {
    case 'OMR': return l10n.currencyOMR;
    case 'AED': return l10n.currencyAED;
    case 'SAR': return l10n.currencySAR;
    case 'USD': return l10n.currencyUSD;
    case 'EUR': return l10n.currencyEUR;
    case 'GBP': return l10n.currencyGBP;
    case 'QAR': return l10n.currencyQAR;
    case 'KWD': return l10n.currencyKWD;
    case 'BHD': return l10n.currencyBHD;
    case 'JPY': return l10n.currencyJPY;
    default:    return code;
  }
}
```

Adding a currency to the picker requires three coordinated edits: the
ARB pair, this switch, and (if it should appear in the picker UI) the
`CurrencyPickerSheet` option list. See HOWTO-TRANSLATE.md.

### Split-mode display names

`lib/core/utils/split_mode_display_name.dart`:

```dart
String splitModeDisplayName(SplitMode mode, AppLocalizations l10n) {
  return switch (mode) {
    SplitMode.equally => l10n.splitModeEqually,
    SplitMode.shares  => l10n.splitModeShares,
    SplitMode.exact   => l10n.splitModeExact,
    SplitMode.percent => l10n.splitModePercent,
  };
}
```

`SplitModeX.label` on the model itself stays English-only so the model
file does not import `AppLocalizations`. UI code must use this helper.

---

## 6. The locale provider

`lib/core/providers/settings_provider.dart:148-153`:

```dart
final localeProvider = Provider<Locale>((ref) {
  final code = ref.watch(
    settingsProvider.select((s) => s.languageCode),
  );
  return Locale(code);
});
```

`localeProvider` derives from a single field on `AppSettings`. There is
**no separate `localeCode` field** — `languageCode` is the source of
truth, persisted through `SharedPreferences` by `SettingsService`.

To switch language at runtime, call `SettingsNotifier.setLanguage`:

```dart
// lib/core/providers/settings_provider.dart:35-38
Future<void> setLanguage(String languageCode) async {
  await _service.saveLanguage(languageCode);
  state = state.copyWith(languageCode: languageCode);
}
```

That triggers a rebuild of any widget watching `localeProvider`, which
includes `MaterialApp.router`. The language change is therefore
instant — no app restart needed.

Default value: `'en'` (see `AppSettings` constructor at
`lib/core/models/app_settings_model.dart:19`).

---

## 7. The Language Picker sheet

`lib/features/settings/widgets/language_picker_sheet.dart`:

```dart
class LanguagePickerSheet extends ConsumerWidget {
  // Bottom sheet shown from Profile → Preferences → Language.
  // Renders a Material RadioGroup<String> with two options: 'en' and 'ar'.
  // On selection, calls SettingsNotifier.setLanguage and pops itself.
}
```

This sheet is the only UI surface that flips `languageCode`. It is
fully translated (uses `context.l10n.languageSheetTitle` etc.) and
respects RTL out of the box because `RadioListTile` is a Material
widget aware of `Directionality`.

To unlock a new language in the picker, add a `RadioListTile<String>`
for it and ensure `AppLocalizations.supportedLocales` includes the
matching `Locale(code)`.

---

## 8. RTL handling

When the active locale is Arabic, Flutter sets the inherited
`Directionality` to RTL for the entire widget tree below
`MaterialApp.router`. Most layouts handle this automatically. The
exceptions:

### 8.1 `Alignment` vs `AlignmentDirectional`

Hardcoded `Alignment.centerLeft` / `Alignment.centerRight` do **not**
flip in RTL. Use `AlignmentDirectional.centerStart` /
`AlignmentDirectional.centerEnd` instead. The codebase migrated
`profile_screen.dart` to the directional form in PR2a (commit
`3c77602`).

```dart
// Wrong — stays left even in Arabic
Align(alignment: Alignment.centerLeft, child: ...)

// Right — becomes right-aligned in Arabic
Align(alignment: AlignmentDirectional.centerStart, child: ...)
```

The same rule applies to `EdgeInsets.only(left:)` → `EdgeInsetsDirectional.only(start:)`.

### 8.2 Iconsax glyphs and `DirectionalIcon`

Iconsax ships `IconData` without `matchTextDirection: true`, so the
plain `Icon` widget cannot auto-flip Iconsax arrows and chevrons in
Arabic. `lib/shared/widgets/directional_icon.dart` wraps the icon and
applies a horizontal flip when the ambient `Directionality` is RTL:

```dart
class DirectionalIcon extends StatelessWidget {
  const DirectionalIcon(this.icon, {super.key, this.size, this.color});
  final IconData icon;
  final double? size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final iconWidget = Icon(icon, size: size, color: color);
    if (Directionality.of(context) != TextDirection.rtl) return iconWidget;
    return Transform.scale(scaleX: -1, child: iconWidget);
  }
}
```

**Use `DirectionalIcon` for:** navigation arrows (`Iconsax.arrow_left`,
`Iconsax.arrow_right`), row chevrons (`Iconsax.arrow_right_3`), any
glyph whose meaning depends on left/right orientation.

**Do not use it for:** non-directional icons (`Iconsax.heart`,
`Iconsax.setting`, `Iconsax.box`, category icons). Mirroring those
makes them look broken.

PR2a migrated nine call sites to `DirectionalIcon`: the back button in
`_GhostIcon`, six row chevrons in `profile_screen.dart`, and one
chevron each in `profile_display_section.dart`,
`profile_about_section.dart`, and `profile_support_section.dart`
(commit `9e40ebe`).

### 8.3 What you do **not** need to do

- `Row`, `Column`, `Padding(EdgeInsetsDirectional.*)`, `Positioned.directional`, and Material widgets handle RTL automatically.
- `Text` aligns to the start edge by default (left in LTR, right in RTL). No manual flip needed.
- Bottom sheets, dialogs, and snackbars inherit the app's directionality through `MaterialApp` — no extra wiring.

---

## 9. Multi-text-span composition (Arabic word order)

Some UI strings combine static prose with dynamic data:

> "Your data is saved to the cloud. To recover, enter **your email** on any device."

English flows left-to-right with the email in the middle. Arabic flows
right-to-left and word order shifts. A single
`Text.rich(TextSpan(text: '...', children: [...]))` with three children
keeps the structure flexible: each span gets its own ARB key, and the
translator decides the final order in `app_ar.arb`.

PR2a uses this for the sign-out dialog (commit `815a86c`). Look at
`SignOutConfirmDialog` for the live pattern. New strings that need
mid-sentence emphasis or interpolation should follow the same shape:

```dart
Text.rich(
  TextSpan(
    text: l10n.signOutContentPrefix,
    children: [
      TextSpan(text: linkedEmail, style: emphasisStyle),
      TextSpan(text: l10n.signOutContentSuffix),
    ],
  ),
)
```

`app_ar.arb` then expresses prefix/suffix in whatever order Arabic
reads naturally — `signOutContentPrefix` is "بياناتك محفوظة في السحابة. للاستعادة، أدخل ",
`signOutContentSuffix` is " على أي جهاز.".

---

## 10. Testing localized widgets

Every test that pumps a widget reading `context.l10n` must register the
generated delegates. The repo standard is the `pumpRihlaApp` helper
(`test/helpers/`), which wires:

- `AppLocalizations.localizationsDelegates`
- `AppLocalizations.supportedLocales`
- A locale override (defaulting to `'en'`; pass `'ar'` to assert Arabic rendering)

For tests that need to verify both locales, the canonical pattern is:

```dart
testWidgets('settings screen renders in Arabic', (tester) async {
  await pumpRihlaApp(
    tester,
    locale: const Locale('ar'),
    child: const ProfileScreen(),
  );
  expect(find.text('الملف الشخصي'), findsOneWidget); // profileTitle in Arabic
});
```

PR2a's Arabic widening of the golden test (commit `be3e9fa`) shows the
pattern for richer assertion. See [TESTING.md § Common Pitfalls](./TESTING.md)
for the `sharedPreferencesProvider` override requirement that interacts
with this.

---

## 11. Files at a glance

| File | Purpose |
|------|---------|
| `pubspec.yaml` (`flutter: generate: true`) | Triggers gen-l10n on every build |
| `l10n.yaml` | gen-l10n configuration |
| `lib/l10n/app_en.arb` | Template; every key starts here |
| `lib/l10n/app_ar.arb` | Arabic translations |
| `lib/l10n/generated/app_localizations*.dart` | Generated bindings; committed |
| `lib/main.dart:182-188` | `MaterialApp.router` locale + delegates + supportedLocales |
| `lib/core/extensions/build_context_l10n.dart` | `context.l10n` shorthand |
| `lib/core/providers/settings_provider.dart:148` | `localeProvider` derived from `languageCode` |
| `lib/core/providers/settings_provider.dart:35` | `SettingsNotifier.setLanguage` |
| `lib/core/models/app_settings_model.dart:9` | `AppSettings.languageCode` (default `'en'`) |
| `lib/core/utils/currency_display_name.dart` | ISO 4217 → localized name switch |
| `lib/core/utils/split_mode_display_name.dart` | `SplitMode` → localized name switch |
| `lib/shared/widgets/directional_icon.dart` | RTL flip wrapper for Iconsax glyphs |
| `lib/features/settings/widgets/language_picker_sheet.dart` | The only UI that flips `languageCode` |

---

## 12. Related docs

- [HOWTO-TRANSLATE.md](./HOWTO-TRANSLATE.md) — step-by-step recipes
- [ARCHITECTURE.md](./ARCHITECTURE.md) — overall app architecture
- [TESTING.md](./TESTING.md) — `pumpRihlaApp` and localized widget tests
- [PRODUCT.md](./PRODUCT.md) — product framing (group/event/expense model)
