# How to Translate (Tutorial + Recipes)

Step-by-step recipes for the Arabic rollout (PR2b/PR3/PR4 …) and any
future language. For architecture and reference, read
[LOCALIZATION.md](./LOCALIZATION.md) first.

This doc has two parts:

1. **Tutorial** — translate your first screen end-to-end (15-30 min).
   Uses the actual PR2a workflow as the worked example.
2. **Recipes** — short how-tos for follow-up tasks (add a key, add a
   language, handle RTL, write a test).

---

## Part 1 — Tutorial: translate a screen end-to-end

You will translate one screen — pick a small one for the first pass.
By the end you will have:

- Replaced every hardcoded string with `context.l10n.<key>` calls.
- Added the new keys to both ARB files.
- Verified the screen renders in Arabic with no missing keys.
- Run `flutter analyze` and the relevant widget tests clean.

The example below uses a hypothetical `WelcomeScreen` with three
strings: a title, a subtitle, and a CTA button. Substitute your real
screen.

### Step 1 — Find the hardcoded strings

```bash
# From the repo root, list raw string literals in your target file
grep -nE "'[A-Z][^']{2,}'|\"[A-Z][^\"]{2,}\"" lib/features/welcome/screens/welcome_screen.dart
```

You're looking for user-facing prose. Skip log messages, route paths,
asset keys, and other non-UI strings. Make a short list:

```
welcome_screen.dart:42  "Welcome to Rihla"
welcome_screen.dart:48  "Split trip expenses with your friends."
welcome_screen.dart:71  "Get started"
```

### Step 2 — Add the keys to `app_en.arb`

Open `lib/l10n/app_en.arb`. Add three keys, each with a `@<key>`
description block. Group them under a feature comment so they're easy
to find later:

```jsonc
{
  "@@locale": "en",
  // ... existing keys ...

  "welcomeTitle": "Welcome to Rihla",
  "@welcomeTitle": {
    "description": "Hero title on the first-launch welcome screen."
  },
  "welcomeSubtitle": "Split trip expenses with your friends.",
  "@welcomeSubtitle": {
    "description": "One-line subtitle under the welcome title."
  },
  "welcomeGetStarted": "Get started",
  "@welcomeGetStarted": {
    "description": "Primary CTA on the welcome screen — routes to onboarding."
  }
}
```

Naming convention reminders:

- Prefix by surface (`welcome*`, `profile*`, `ledger*`, `settings*`).
- Use camelCase. No spaces, dots, or kebab-case.
- The description tells a translator (or future-you) what the string is
  for. Be specific: "Title of the X sheet" beats "Title".

### Step 3 — Run codegen

Save the file and run:

```bash
flutter pub get
```

This regenerates `lib/l10n/generated/app_localizations.dart` and
`app_localizations_en.dart` so the new keys are reachable as
`AppLocalizations.welcomeTitle` (and via `context.l10n.welcomeTitle`).

If `pub get` complains about an ARB parse error, you have malformed
JSON — usually a missing comma or trailing comma. Fix the JSON and
re-run.

### Step 4 — Wire the screen

Import the extension and replace each hardcoded string. Most screens
follow this shape:

```dart
import '../../../core/extensions/build_context_l10n.dart';
// ...

@override
Widget build(BuildContext context) {
  final l10n = context.l10n;
  return Scaffold(
    body: Column(
      children: [
        Text(l10n.welcomeTitle, style: titleStyle),
        Text(l10n.welcomeSubtitle, style: subtitleStyle),
        // ...
        ElevatedButton(
          onPressed: _onGetStarted,
          child: Text(l10n.welcomeGetStarted),
        ),
      ],
    ),
  );
}
```

Pulling `l10n` into a local variable at the top of `build` is the
project standard. It keeps each call site short and avoids re-reading
the inherited widget on every reference.

### Step 5 — Add the Arabic translations

Open `lib/l10n/app_ar.arb`. Append the same three keys with Arabic
values (descriptions are not duplicated):

```jsonc
{
  "@@locale": "ar",
  // ... existing keys ...

  "welcomeTitle": "مرحبًا بك في رحلة",
  "welcomeSubtitle": "اقسم مصاريف الرحلات مع أصدقائك.",
  "welcomeGetStarted": "ابدأ"
}
```

If you don't have translations on hand, leave the key out of `app_ar.arb`
for now — the generated Arabic binding falls back to English when a key
is missing. This is acceptable for an in-flight PR but every key must
have an Arabic value before the surface is considered "translated."

### Step 6 — Verify analyzer and tests

```bash
flutter analyze                      # must be clean
flutter test test/features/welcome/  # all tests pass
```

If your widget tests rendered text via `find.text('Welcome to Rihla')`,
they will fail in Arabic — switch to keys or wrap in a localized
assertion. See § Recipes → "Test a localized widget" below.

### Step 7 — Eyeball it in both locales

```bash
flutter run --dart-define-from-file=config.json
```

In the running app:

1. Profile → Preferences → Language → English. Verify your screen reads naturally.
2. Profile → Preferences → Language → العربية. Verify:
   - All three strings render in Arabic.
   - Direction flips to RTL (text starts on the right, padding on the
     start edge mirrors).
   - No raw `welcomeTitle`-style key strings appear (those mean the
     key isn't in `app_ar.arb` AND the codegen hasn't seen it — fall
     back is to English, so a raw key indicates codegen wasn't re-run).

If you see hardcoded English under Arabic, you missed a string. Grep
the file again for any remaining literals.

### Step 8 — Commit

The conventional commit shape used by the rollout:

```bash
git add lib/l10n/app_en.arb lib/l10n/app_ar.arb \
        lib/l10n/generated/ \
        lib/features/welcome/screens/welcome_screen.dart \
        test/features/welcome/
git commit -m "feat(l10n): translate welcome screen to use localization"
```

Include the generated bindings in the commit — they're tracked.

You're done.

---

## Part 2 — Recipes

### Recipe A: Add a single new key

When you only need one string (e.g., a new snackbar message):

1. Add the key + `@<key>` description to `app_en.arb`.
2. Add the Arabic value to `app_ar.arb`.
3. Run `flutter pub get`.
4. Reference it as `context.l10n.<key>` in code.
5. Commit ARB + generated diff together.

### Recipe B: Add a placeholder

A placeholder lets you inject runtime values into a translated string.

`app_en.arb`:

```jsonc
"profileGreetingByName": "Hi, {name}",
"@profileGreetingByName": {
  "description": "Greeting at the top of the profile screen.",
  "placeholders": {
    "name": { "type": "String" }
  }
}
```

`app_ar.arb`:

```jsonc
"profileGreetingByName": "مرحبًا، {name}"
```

Call site:

```dart
Text(context.l10n.profileGreetingByName(settings.deviceName));
```

The generated function is strongly typed; pass the wrong type and
`flutter analyze` flags it.

### Recipe C: Compose Arabic-safe multi-span text

When you need emphasis or interpolation mid-sentence (e.g., bolded
email inside prose), do **not** rely on `{placeholder}` for the
emphasis. Use three keys + `Text.rich`:

```jsonc
// app_en.arb
"signOutContentPrefix": "Your data is saved to the cloud. To recover, enter ",
"signOutContentSuffix": " on any device.",
```

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

Arabic's word order then lives in the ARB:

```jsonc
// app_ar.arb
"signOutContentPrefix": "بياناتك محفوظة في السحابة. للاستعادة، أدخل ",
"signOutContentSuffix": " على أي جهاز.",
```

The translator decides where the emphasized run sits relative to the
prose.

### Recipe D: Mirror an Iconsax arrow in RTL

Replace plain `Icon(Iconsax.arrow_left)` with `DirectionalIcon`:

```dart
import '../../../shared/widgets/directional_icon.dart';

DirectionalIcon(Iconsax.arrow_left, size: 24, color: tokens.iconPrimary)
```

`DirectionalIcon` flips horizontally via `Transform.scale` when the
ambient `Directionality` is RTL. Only use it for **navigational**
glyphs — back arrows, chevrons, "next" indicators. Don't wrap
non-directional icons.

### Recipe E: Migrate `Alignment.center*` to `AlignmentDirectional`

Search for the LTR-bound forms:

```bash
grep -rn "Alignment\.\(centerLeft\|centerRight\)" lib/
grep -rn "EdgeInsets\.only(left:\|EdgeInsets\.only(right:" lib/
```

Replace:

| Before | After |
|---|---|
| `Alignment.centerLeft` | `AlignmentDirectional.centerStart` |
| `Alignment.centerRight` | `AlignmentDirectional.centerEnd` |
| `EdgeInsets.only(left: x)` | `EdgeInsetsDirectional.only(start: x)` |
| `EdgeInsets.only(right: x)` | `EdgeInsetsDirectional.only(end: x)` |
| `EdgeInsets.fromLTRB(l, t, r, b)` | `EdgeInsetsDirectional.fromSTEB(s, t, e, b)` |
| `Positioned(left: x)` | `Positioned.directional(start: x, textDirection: Directionality.of(context))` |

`Alignment.center`, `Alignment.topCenter`, etc. — those that don't
reference left/right — are direction-neutral and need no change.

### Recipe F: Add a new language (e.g., French)

The codebase has an existing rollout for Arabic; another locale follows
the same pattern.

1. **Create `lib/l10n/app_fr.arb`.** Start with the locale tag and copy
   key-by-key from `app_en.arb`, replacing values with French:

   ```jsonc
   {
     "@@locale": "fr",
     "commonCancel": "Annuler",
     // ...
   }
   ```

2. **Run `flutter pub get`.** Confirm `lib/l10n/generated/app_localizations_fr.dart`
   appears and `AppLocalizations.supportedLocales` now includes
   `Locale('fr')`.

3. **Add a picker option.** Open
   `lib/features/settings/widgets/language_picker_sheet.dart` and add a
   `RadioListTile<String>` for `'fr'` as a child of the existing
   `RadioGroup<String>`'s `Column`:

   ```dart
   RadioListTile<String>(
     value: 'fr',
     title: Text(context.l10n.languageFrench),
   ),
   ```

   The parent `RadioGroup<String>` already owns `groupValue` (the current
   `languageCode`) and `onChanged` (which calls `setLanguage`), so the new
   tile carries only `value:` and `title:` — do **not** add per-tile
   `groupValue`/`onChanged`.

4. **Add autonym keys** `languageFrench` (and any future-locale
   autonyms) to both `app_en.arb` and `app_ar.arb` (and `app_fr.arb`).
   Autonyms stay in their own script across all locales (English: "English",
   Arabic: "العربية", French: "Français").

5. **Update the rollout tests.** Any test asserting on
   `supportedLocales` length or on the picker option count needs to
   bump.

6. **RTL?** Only Arabic (and a handful of other languages — Hebrew,
   Persian, Urdu) flow right-to-left. French is LTR; no further
   direction work needed.

### Recipe G: Test a localized widget

Use `pumpRihlaApp` from `test/helpers/` — it registers the generated
delegates so `context.l10n` resolves.

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

import '../helpers/pump_rihla_app.dart';

testWidgets('welcome screen renders in English', (tester) async {
  await pumpRihlaApp(tester, const WelcomeScreen());

  expect(find.text('Welcome to Rihla'), findsOneWidget);
});

testWidgets('welcome screen renders in Arabic', (tester) async {
  await pumpRihlaApp(
    tester,
    const WelcomeScreen(),
    locale: const Locale('ar'),
  );

  expect(find.text('مرحبًا بك في رحلة'), findsOneWidget);
});
```

Asserting on the raw translated text is fragile if copy churns. For
structural assertions, prefer `find.byKey` and verify the key resolved
to *some* non-empty text:

```dart
final widget = tester.widget<Text>(find.byKey(WelcomeKeys.title));
expect(widget.data, isNotEmpty);
```

### Recipe H: Find untranslated strings before a PR

Scan your changed files for likely-hardcoded English:

```bash
git diff --name-only main...HEAD -- 'lib/features/**/*.dart' \
  | xargs grep -nE "(Text|TextSpan)\([\"'][A-Z]" 2>/dev/null
```

`Text("Some Title")` and `TextSpan(text: "Some prose")` are the usual
suspects. Some hits are false positives (e.g., `Text(amountString)` —
that's a variable, not a literal). Eyeball each one.

A common miss: snackbar messages, dialog titles, and `appBar.title`
strings. Grep for those specifically:

```bash
grep -nE "SnackBar\(content: Text\([\"']|title: const? Text\([\"']" lib/features/<feature>/
```

---

## Conventions cheat sheet

| Rule | Example |
|------|---------|
| All user-visible strings via `context.l10n` | `Text(l10n.welcomeTitle)` |
| Pull `l10n` once per `build` | `final l10n = context.l10n;` at top of build |
| Key prefix by feature/surface | `profileSection*`, `welcome*`, `commonCancel` |
| Description on every English key | `@<key>: { "description": "..." }` |
| Arabic word order via multi-span | `Text.rich(TextSpan(text: prefix, children: [...]))` |
| Nav glyphs in RTL | `DirectionalIcon(...)`, not `Icon(...)` |
| Directional spacing | `EdgeInsetsDirectional` / `AlignmentDirectional` |
| Locale flip tested | `pumpRihlaApp(tester, widget, locale: const Locale('ar'))` |
| Commit | `feat(l10n): ...` with ARB + generated + screen + tests together |

---

## When something breaks

| Symptom | Fix |
|---|---|
| `flutter pub get` says "Could not load ARB file" | Malformed JSON in `app_en.arb` or `app_ar.arb`. Validate with `python -m json.tool < lib/l10n/app_en.arb`. |
| `context.l10n.<key>` doesn't exist on `AppLocalizations` | Codegen didn't see your new key. Re-run `flutter pub get` and confirm `lib/l10n/generated/app_localizations.dart` was rewritten. |
| Screen shows raw `welcomeTitle` string | The key isn't in `app_en.arb` (English fallback misses). Add it. |
| Screen shows English while in Arabic | Key isn't in `app_ar.arb`. Add the translation. |
| Test fails with `Null check operator used on a null value` from `AppLocalizations.of` | Test harness missing delegates. Use `pumpRihlaApp` or wire the delegates directly. |
| Iconsax arrow doesn't flip in Arabic | `Icon(Iconsax.arrow_*)` instead of `DirectionalIcon(Iconsax.arrow_*)`. |
| Text aligns to the left in Arabic | Hardcoded `Alignment.centerLeft` or `EdgeInsets.only(left:)`. Migrate to `*Directional`. |

---

## Related docs

- [LOCALIZATION.md](./LOCALIZATION.md) — architecture, file layout, pipeline
- [TESTING.md](./TESTING.md) — testing patterns, `pumpRihlaApp` contract
- [DEVELOPMENT.md](./DEVELOPMENT.md) — feature-development workflow
