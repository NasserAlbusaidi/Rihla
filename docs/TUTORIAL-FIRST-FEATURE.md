# Tutorial: Your First Feature

A guided walk-through that takes you from a freshly-cloned Rihla repo
to a small, real feature you ship: **a "Sound feedback" toggle in
Profile → Notifications**. By the end you will:

- Understand how `AppSettings` + `SettingsService` + `SettingsNotifier`
  cooperate to persist user preferences across launches.
- Have added a new key to both ARB files and verified it renders in
  English and Arabic.
- Have written a widget test that pumps the Profile screen and toggles
  your switch.
- Be ready to navigate any feature in the codebase, because every
  feature uses the same layering you saw here.

This is a **tutorial**, not a recipe. It optimises for understanding
over speed. If you already know the codebase and just need the recipe,
read [DEVELOPMENT.md § Adding a New Feature](./DEVELOPMENT.md) instead.

Estimated time: 30-45 minutes if it's your first time touching the
codebase.

---

## What you'll need

- A working dev environment per [GETTING-STARTED.md](./GETTING-STARTED.md).
  Specifically: `flutter run --dart-define-from-file=config.json`
  succeeds and the app launches.
- An Android emulator or iOS simulator running.
- A code editor with Dart support (VS Code, Cursor, Android Studio).

If you haven't done the Getting Started walk-through yet, do that
first. The rest of this assumes the app launches when you press Run.

---

## What you're going to build

Open the Profile screen in the running app and find the
**Notifications** section. It currently renders one tile — the **Push
notifications** toggle backed by `pushNotificationsEnabled`. (A
`weeklyDigestEnabled` field also exists on `AppSettings` but is not yet
surfaced in the UI; we'll leave that alone.)

You're going to add a second toggle, **Sound feedback**
(`soundFeedbackEnabled`), which:

- Persists across app launches.
- Defaults to `false`.
- Renders in both English ("Sound feedback") and Arabic ("ردود الصوت").
- Is invisible to the rest of the app — turning it on doesn't yet
  *do* anything. That part is intentional: the goal is the plumbing,
  not the sound. You'll wire actual sound triggers as a follow-up if
  you want.

This is the right size to learn the codebase with. It touches every
layer below the network boundary but introduces no new architectural
shapes.

---

## The mental model (read once, refer to often)

Every user preference in Rihla flows through the same five-layer
sandwich. Here's the picture before we touch any code:

```
┌─────────────────────────────────────────────────────────────┐
│ 1. AppSettings (immutable value type)                       │
│    lib/core/models/app_settings_model.dart                  │
│    — Defines the fields. Has copyWith. No I/O.              │
└──────────────────────┬──────────────────────────────────────┘
                       │ owned by
┌──────────────────────▼──────────────────────────────────────┐
│ 2. SettingsNotifier (Riverpod StateNotifier)                │
│    lib/core/providers/settings_provider.dart                │
│    — Exposes setter methods. Calls SettingsService to       │
│      persist, then updates `state` with copyWith.           │
└──────────────────────┬──────────────────────────────────────┘
                       │ delegates persistence to
┌──────────────────────▼──────────────────────────────────────┐
│ 3. SettingsService (SharedPreferences adapter)              │
│    lib/core/services/settings_service.dart                  │
│    — Pure I/O. Reads/writes SharedPreferences keys.         │
└──────────────────────┬──────────────────────────────────────┘
                       │ stored in
┌──────────────────────▼──────────────────────────────────────┐
│ 4. SharedPreferences (platform key/value store)             │
│    — Survives app restarts. Per-app, not per-UID.           │
└─────────────────────────────────────────────────────────────┘

           ▲
           │
           │ reads via ref.watch(settingsProvider)
           │ writes via ref.read(settingsProvider.notifier).setFoo(...)
           │
┌──────────┴──────────────────────────────────────────────────┐
│ 5. ProfileScreen widgets (consumer)                         │
│    lib/features/settings/screens/profile_screen.dart        │
│    lib/features/settings/widgets/profile_*_section.dart     │
│    — Display the toggle. Wire the switch's onChanged.       │
└─────────────────────────────────────────────────────────────┘
```

Every preference toggle is some version of this stack. The
**existing** push-notifications field is your reference implementation
— search for `pushNotificationsEnabled` across the four files at any
point and you'll see the pattern.

You're going to add `soundFeedbackEnabled` to each layer in turn,
from the bottom up.

---

## Step 1 — Run the app and find the existing switch

Before you write any code, ground yourself in the existing UI.

```bash
flutter run --dart-define-from-file=config.json
```

Tap the **Profile** tab in the bottom nav. Scroll to **Notifications**.
You'll see one toggle tile — Push notifications. Toggle it and
observe:

- The switch animates.
- Restart the app (full restart, not hot reload). The toggle comes
  back the way you left it. That's persistence working — your value
  is in `SharedPreferences`.

Keep the app running. You'll come back to it.

---

## Step 2 — Add the field to `AppSettings`

Open `lib/core/models/app_settings_model.dart`. You'll see this near
the top:

```dart
class AppSettings {
  final AppThemeMode themeMode;
  final String languageCode;
  final String currencyCode;
  final bool pushNotificationsEnabled;
  final bool weeklyDigestEnabled;
  // ...
}
```

Add a new field next to `weeklyDigestEnabled`:

```dart
final bool soundFeedbackEnabled;
```

In the constructor, add a default:

```dart
const AppSettings({
  this.themeMode = AppThemeMode.system,
  this.languageCode = 'en',
  this.currencyCode = 'OMR',
  this.pushNotificationsEnabled = false,
  this.weeklyDigestEnabled = false,
  this.soundFeedbackEnabled = false,         // ← new
  // ...
});
```

In `copyWith`, add the parameter and the assignment:

```dart
AppSettings copyWith({
  // ... existing parameters ...
  bool? soundFeedbackEnabled,                 // ← new
}) {
  return AppSettings(
    // ... existing fields ...
    soundFeedbackEnabled:
        soundFeedbackEnabled ?? this.soundFeedbackEnabled,  // ← new
  );
}
```

That's it for the model. **Run `flutter analyze`** to confirm nothing
broke:

```bash
flutter analyze
```

Should report no issues. If it complains about `AppSettings.defaultSettings()`,
remember that constructor takes no arguments because every field has a
default — yours included.

### Why immutable + `copyWith`?

Immutable models prevent the "did something mutate this from under
me?" class of bug that haunts Flutter apps. Every field is `final`.
To "change" a value, you create a new `AppSettings` with `copyWith`.

`SettingsNotifier` will do this in the next step.

---

## Step 3 — Add the SharedPreferences key (SettingsService)

Open `lib/core/services/settings_service.dart`. You'll see a pattern
like:

```dart
class SettingsService {
  static const String _pushNotificationsKey = 'settings_push_notifications';
  static const String _weeklyDigestKey = 'settings_weekly_digest';

  // ...

  Future<void> savePushNotificationsEnabled(bool enabled) async {
    await _prefs.setBool(_pushNotificationsKey, enabled);
  }
}
```

Add the key constant near the others, matching the existing
`_<name>Key` private-constant + `'settings_<name>'` value convention:

```dart
static const String _soundFeedbackKey = 'settings_sound_feedback';
```

Add the matching saver:

```dart
Future<void> saveSoundFeedbackEnabled(bool enabled) async {
  await _prefs.setBool(_soundFeedbackKey, enabled);
}
```

And read the field in `loadSettings()`:

```dart
AppSettings loadSettings() {
  return AppSettings(
    // ... existing fields ...
    soundFeedbackEnabled: _prefs.getBool(_soundFeedbackKey) ?? false,
  );
}
```

Notice the `?? false` — when the key has never been written (fresh
install, or an existing user who hasn't toggled the new switch yet),
`getBool` returns `null` and we fall back to the default.

**Run `flutter analyze` again.** Still clean.

### Why one constant per key?

Stringly-typed keys (`'settings_push_notifications'` vs.
`'pushNotificationsEnabled'` vs. `'pushNotifs'`) are the classic
SharedPreferences foot-gun — one typo and you silently lose the
user's data on the next app launch. Constants give you `flutter
analyze` as a safety net.

---

## Step 4 — Expose the toggle in `SettingsNotifier`

Open `lib/core/providers/settings_provider.dart`. Add a setter
matching the pattern of `setPushNotificationsEnabled`:

```dart
Future<void> setSoundFeedbackEnabled(bool enabled) async {
  await _service.saveSoundFeedbackEnabled(enabled);
  state = state.copyWith(soundFeedbackEnabled: enabled);
}
```

The order matters: write to disk first, then update state. If the
write fails (rare for SharedPreferences but possible), the in-memory
state stays in sync with what was actually persisted.

**Run `flutter analyze` one more time.** Clean.

You now have a fully wired preference all the way to the keyboard —
you just can't see or touch it from the UI yet.

### Why this layering?

Flutter could let you write `_prefs.setBool('foo', true)` directly
from a button's `onTap`. The four-layer separation buys you:

- **Testability.** The notifier can be tested by injecting a
  `SettingsService` backed by a mock `SharedPreferences`.
- **Riverpod-friendly updates.** `state = state.copyWith(...)`
  triggers a rebuild of every widget that watched the relevant slice.
- **Single source of truth.** No widget reads SharedPreferences
  directly. The notifier's `state` is canonical.

---

## Step 5 — Add the ARB keys

Open `lib/l10n/app_en.arb`. Find the existing notification labels
(`profileNotificationsTitle` etc.) and add a pair for the new toggle:

```jsonc
"profileNotificationsSound": "Sound feedback",
"@profileNotificationsSound": {
  "description": "Toggle on Profile → Notifications for in-app sound feedback."
},
"profileNotificationsSoundSubtitle": "Plays a soft chime on settle-up",
"@profileNotificationsSoundSubtitle": {
  "description": "Subtitle under the Sound feedback toggle."
}
```

Open `lib/l10n/app_ar.arb` and add Arabic translations:

```jsonc
"profileNotificationsSound": "ردود الصوت",
"profileNotificationsSoundSubtitle": "ينبعث صوت خفيف عند التسوية"
```

Run `flutter pub get` to regenerate the bindings:

```bash
flutter pub get
```

Verify that `lib/l10n/generated/app_localizations.dart` now contains a
`profileNotificationsSound` getter. (You don't have to read the file —
trust that codegen ran if `pub get` returned 0.)

If you need a refresher on the ARB pipeline, see
[LOCALIZATION.md](./LOCALIZATION.md) and
[HOWTO-TRANSLATE.md](./HOWTO-TRANSLATE.md).

---

## Step 6 — Wire the switch into Profile

Open `lib/features/settings/widgets/profile_notifications_section.dart`.
This widget already renders the existing push-notifications tile. Read
the existing pattern carefully — at the top of `build` it watches
`settingsProvider` for the current value, and the toggle calls
`setPushNotificationsEnabled` on the notifier.

The existing tile uses a custom-styled `Container` wrapping a row
because it also handles a permission-denied state. For the tutorial
we'll use a plain `SwitchListTile` — match the styled shape as a
follow-up if you want consistency.

Inside the `Column` rendered by `build`, add a `SwitchListTile` below
the existing tile:

```dart
SwitchListTile(
  title: Text(context.l10n.profileNotificationsSound),
  subtitle: Text(context.l10n.profileNotificationsSoundSubtitle),
  value: settings.soundFeedbackEnabled,
  onChanged: (value) {
    HapticService.selection();
    ref
        .read(settingsProvider.notifier)
        .setSoundFeedbackEnabled(value);
  },
),
```

Three things to notice:

- **`settings` is the watched value**, not a fresh provider read. The
  outer widget already has `final settings = ref.watch(settingsProvider);`
  — reuse it.
- **`context.l10n`** comes from the extension. You don't need to
  import `AppLocalizations` directly.
- **`HapticService.selection()`** matches the existing two switches.
  Small consistency wins.

Save the file. The app has hot-reloaded.

In the running app, swipe over to Profile and look at the
Notifications section. You should now see three switches. Toggle the
new one — the animation runs. Restart the app (press `R` in the
Flutter console for full restart). The toggle's position is preserved.

**That's the feature.** Everything below is verification and polish.

---

## Step 7 — Verify in Arabic

Time to confirm RTL works.

1. In the app, Profile → Preferences → Language → **العربية**.
2. The interface flips to RTL. Scroll back to Notifications.
3. The new switch label reads **"ردود الصوت"** with the subtitle
   **"ينبعث صوت خفيف عند التسوية"**.
4. The switch itself is on the start (right) side of the row, which is
   correct in RTL.

If you see the English text instead of Arabic, you forgot to add the
keys to `app_ar.arb`. Add them and run `flutter pub get` again.

Switch back to English when you're done.

---

## Step 8 — Write a test

Open `test/features/settings/` and find the existing profile-screen
tests (or `profile_screen_test.dart` if it exists). The pattern uses
`pumpRihlaApp` (from `test/helpers/`) which registers Riverpod
overrides and localization delegates.

Add a new test:

```dart
testWidgets('sound feedback toggle persists through SettingsNotifier', (tester) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();

  await pumpRihlaApp(
    tester,
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
    ],
    child: const ProfileScreen(),
  );
  await tester.pumpAndSettle();

  // The new switch is initially off.
  final soundSwitch = find.byWidgetPredicate(
    (w) => w is SwitchListTile
        && (w.title as Text).data == 'Sound feedback',
  );
  expect(soundSwitch, findsOneWidget);
  expect(
    tester.widget<SwitchListTile>(soundSwitch).value,
    isFalse,
  );

  // Tap it.
  await tester.tap(soundSwitch);
  await tester.pumpAndSettle();

  // The switch is now on AND SharedPreferences was written.
  expect(
    tester.widget<SwitchListTile>(soundSwitch).value,
    isTrue,
  );
  expect(prefs.getBool('settings_sound_feedback'), isTrue);
});
```

Run it:

```bash
flutter test test/features/settings/
```

It should pass. If it fails:

- *"AppLocalizations.of returned null"* — you forgot to use
  `pumpRihlaApp`, or your test didn't register the delegates.
- *"SharedPreferences must be overridden"* — you didn't override
  `sharedPreferencesProvider`. See [TESTING.md § Common Pitfalls](./TESTING.md).
- *"finder couldn't find a widget matching predicate"* — the test
  ran before the UI settled, or your label spelling differs from
  the ARB value.

Don't ship without the test. Tests are how you prove the feature
behaves as documented — and how you'll find regressions when someone
later refactors the notifier.

---

## Step 9 — Run the full suite + analyzer

Before you call it done:

```bash
flutter analyze     # must be clean
flutter test        # all suites green
```

If analyze flags an unused import or missing field somewhere you
didn't expect, walk back through the layers — you may have missed a
spot in `copyWith` or `loadSettings`.

---

## Step 10 — Commit

Conventional commit format used across the project:

```bash
git add lib/core/models/app_settings_model.dart \
        lib/core/services/settings_service.dart \
        lib/core/providers/settings_provider.dart \
        lib/l10n/app_en.arb \
        lib/l10n/app_ar.arb \
        lib/l10n/generated/ \
        lib/features/settings/widgets/profile_notifications_section.dart \
        test/features/settings/

git commit -m "feat(settings): add sound feedback toggle in profile notifications"
```

(If your settings change is large, split into a `feat(l10n):` for the
ARB changes and a `feat(settings):` for the wiring. Small features
like this one are fine as one commit.)

---

## What you built

Walk through the changes one more time and notice what you now know:

1. **You added a preference end-to-end.** Model field → SharedPreferences key
   → notifier method → ARB pair → UI switch → test. Every layer.
2. **You used `context.l10n`** and **understand why** — the codebase
   localizes via that extension so locale changes propagate everywhere
   without restart.
3. **You used `HapticService`** — the codebase calls this on tappable
   surfaces for consistency. Search for it across the repo to see
   where else it's used.
4. **You wrote a widget test** with `pumpRihlaApp`. Every widget test
   in `test/features/` uses the same harness.
5. **You verified RTL** by flipping the locale. Every PR that adds UI
   should be eyeballed in both directions.

This is the loop you'll run for almost every feature: identify the
layers, follow the existing pattern at each layer, test it, eyeball
both locales, commit.

---

## Where to go next

Pick a project that exercises a layer you didn't touch here:

- **Add a route.** Touch `app_router.dart`. Read
  [DEVELOPMENT.md § Navigation](./DEVELOPMENT.md) first.
- **Add a Firestore-backed feature.** Touch a service that extends
  `FirestoreRepository` and a `StreamProvider.family`. Read
  [ARCHITECTURE.md § State Management](./ARCHITECTURE.md) and
  [DEVELOPMENT.md § State Management Patterns](./DEVELOPMENT.md).
- **Translate another surface.** Pick a screen still showing English
  under Arabic and follow [HOWTO-TRANSLATE.md](./HOWTO-TRANSLATE.md).
- **Touch the backend.** Add a callable in `functions/src/callables/`
  or modify a rule in `security/firestore.rules`. Read
  [CLOUD-FUNCTIONS.md](./CLOUD-FUNCTIONS.md) and
  [SECURITY-RULES.md](./SECURITY-RULES.md).

You now have enough mental model to navigate any of them.

---

## Related docs

- [GETTING-STARTED.md](./GETTING-STARTED.md) — environment setup
- [DEVELOPMENT.md](./DEVELOPMENT.md) — full developer reference
- [ARCHITECTURE.md](./ARCHITECTURE.md) — system overview
- [LOCALIZATION.md](./LOCALIZATION.md) — l10n reference
- [HOWTO-TRANSLATE.md](./HOWTO-TRANSLATE.md) — translating screens
- [TESTING.md](./TESTING.md) — test patterns and harnesses
- [SHARED-WIDGETS.md](./SHARED-WIDGETS.md) — UI building blocks
