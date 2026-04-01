# Phase 26: Settings & Support - Research

**Researched:** 2026-04-01
**Domain:** Flutter profile screen extension — notification permissions, app info, URL launching
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** Grouped list tiles with uppercase section headers matching the established pattern (icon + uppercase label with `letterSpacing: 1.5`, `textMuted` color).
- **D-02:** Three sections below existing identity + stats: NOTIFICATIONS, ABOUT, SUPPORT — each with its own header.
- **D-03:** List tiles use the established pattern: 36px icon container with `inputFill` bg, `borderRadius: 10`.
- **D-04:** Section order top to bottom: Identity (existing) → Stats (existing) → Notifications → About → Support.
- **D-05:** Push notification toggle is a Switch widget integrated into a list tile. Flipping ON calls `NotificationService.initialize()` which triggers the OS permission dialog.
- **D-06:** If OS permission granted, toggle stays ON and `settingsProvider.setPushNotificationsEnabled(true)` persists the preference.
- **D-07:** If OS permission denied, toggle flips back to OFF with a brief explanation.
- **D-08:** If the user previously denied OS permission, toggle shows as OFF and disabled with subtitle text "Enable in device Settings" — tapping opens app settings via `openAppSettings()`.
- **D-09:** App version displayed as a non-tappable list tile showing version string (e.g., "v2.2.0") from `package_info_plus`.
- **D-10:** "Send Feedback" tile opens a mailto: link with a pre-filled to address and subject line.
- **D-11:** "Open-source Licenses" tile navigates to Flutter's built-in `showLicensePage()`.
- **D-12:** "Buy me a coffee" is a standard list tile with the same visual weight as other items — not highlighted or accent-colored.
- **D-13:** Tapping "Buy me a coffee" shows a SnackBar saying "Coming soon" since it's a placeholder.

### Claude's Discretion

- Specific icon choices (Iconsax variants) for each tile
- Entrance animation delays for new sections (continuing the stagger pattern)
- Feedback email address and subject line text
- SnackBar styling for "Coming soon" message
- Whether to use `app_settings` or `permission_handler` for `openAppSettings()`
- Exact spacing between sections

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| NOTIF-01 | User can view current push notification status | `notificationStatusProvider` (existing `StateProvider<NotificationStatus>`) surfaces `off/enabled/permissionDenied/error` — read directly in the toggle tile |
| NOTIF-02 | User can toggle push notifications on/off | `NotificationService.initialize()` (toggle ON) + `notificationService.removeToken()` (toggle OFF) + `settingsProvider.setPushNotificationsEnabled()` for persistence; `appBootstrapProvider` already syncs on settings change |
| INFO-01 | User can view app version number | `appMetadataProvider` (existing `FutureProvider<AppMetadata>`) already calls `PackageInfo.fromPlatform()` — expose `metadata.versionLabel` |
| INFO-02 | User can access feedback/support link | `url_launcher` (already installed v6.3.2) — `launchUrl(Uri(scheme:'mailto', path:'...', query:'...'))` with `LaunchMode.externalApplication` |
| INFO-03 | User can view open-source licenses | Flutter SDK built-in `showLicensePage(context: context, applicationName: 'Rihla', applicationVersion: metadata.version)` — zero dependencies |
| SUPP-01 | User sees "Buy me a coffee" placeholder on profile page | Standard list tile + `ScaffoldMessenger.of(context).showSnackBar(...)` with "Coming soon" text; SnackBar theme already configured globally |
</phase_requirements>

---

## Summary

Phase 26 adds three new sections (Notifications, About, Support) to the existing `ProfileScreen` built in Phase 25. All infrastructure is in place: `NotificationService`, `settingsProvider`, `appMetadataProvider`, and `url_launcher` are already installed and wired. No new screens are required.

The main implementation work is building three section widgets following the established tile pattern, adding semantic keys to `ProfileKeys`, wiring notification toggle state to `NotificationService`, and writing widget tests for each new requirement.

The one discretionary choice is how to open app settings when notification permission is permanently denied (D-08). Research confirms `permission_handler` is not installed — the recommendation is to use `firebase_messaging`'s own `getNotificationSettings()` to check the permission state at startup, and `url_launcher` with `AppSettings.openAppSettings()` via `app_settings` package for the deep-link — or alternatively use `Permission.notification.status` from `permission_handler`. Both require a new package. The lighter `app_settings` package (single-purpose, v7.0.0) is the better fit since we only need `openAppSettings()`.

**Primary recommendation:** Add `app_settings: ^7.0.0` to pubspec.yaml. Use existing providers for all other functionality. Build three widget files: `profile_notifications_section.dart`, `profile_about_section.dart`, `profile_support_section.dart`.

---

## Standard Stack

### Core — All Already Installed
| Library | Installed Version | Purpose | Usage in Phase 26 |
|---------|-------------------|---------|-------------------|
| `flutter_riverpod` | `^2.4.9` | State management | Watch `notificationStatusProvider`, `appMetadataProvider`, `settingsProvider` |
| `firebase_messaging` | `^16.1.3` | FCM + permission query | `NotificationService.initialize()`, `getNotificationSettings()` to detect permissionDenied state |
| `package_info_plus` | `^8.2.1` (resolved 8.3.1) | App version | Read via existing `appMetadataProvider` |
| `url_launcher` | `^6.3.2` | mailto: links | `launchUrl(mailtoUri, mode: LaunchMode.externalApplication)` |
| `flutter_animate` | `^4.5.0` | Entrance animations | Stagger new sections at 300ms, 400ms, 500ms delays |
| `iconsax` | `^0.0.8` | Tile icons | Bell, info-circle, message-question, cup icons |
| `shared_preferences` | `^2.5.4` | Settings persistence | Via `settingsProvider` — already wired |

### New Dependency Required
| Library | Version | Purpose | Why |
|---------|---------|---------|-----|
| `app_settings` | `^7.0.0` | Open device app settings | Needed for D-08: when notification permission permanently denied, tile taps `AppSettings.openAppSettings()`. Lighter than `permission_handler` — single purpose. Not currently in pubspec. |

**Installation:**
```bash
flutter pub add app_settings
```

**Version verification:** `app_settings` 7.0.0 confirmed on pub.dev (published ~4 months ago, 2025-12).

### Existing Providers to Consume
| Provider | Type | What Phase 26 Uses |
|----------|------|--------------------|
| `notificationStatusProvider` | `StateProvider<NotificationStatus>` | Drive toggle ON/OFF/disabled state |
| `notificationServiceProvider` | `Provider<NotificationService>` | Call `initialize()` / `removeToken()` |
| `settingsProvider` | `StateNotifierProvider<SettingsNotifier, AppSettings>` | Read `pushNotificationsEnabled`, call `setPushNotificationsEnabled()` |
| `appMetadataProvider` | `FutureProvider<AppMetadata>` | Expose `version` in the version tile |
| `appBootstrapProvider` | `Provider<void>` | Already listens to `pushNotificationsEnabled` changes — no extra wiring needed for toggle |

---

## Architecture Patterns

### Recommended File Structure (new files only)
```
lib/features/settings/
├── screens/
│   └── profile_screen.dart          # EXISTING — extend Column children only
├── widgets/
│   ├── profile_notifications_section.dart   # NEW — NOTIF-01, NOTIF-02
│   ├── profile_about_section.dart           # NEW — INFO-01, INFO-02, INFO-03
│   └── profile_support_section.dart         # NEW — SUPP-01
└── keys/
    └── profile_keys.dart            # EXISTING — add 5 new keys
```

### Pattern 1: Section Widget Structure

Each section follows the same pattern as `ProfileStatsSection`:

```dart
// Source: lib/features/settings/widgets/profile_stats_section.dart (reference)
class ProfileNotificationsSection extends ConsumerWidget {
  const ProfileNotificationsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('NOTIFICATIONS', Iconsax.notification),
        const SizedBox(height: 12),
        _buildNotificationTile(context, ref),
      ],
    );
  }
}
```

### Pattern 2: Section Header (established, must match exactly)

```dart
// Source: lib/features/settings/widgets/profile_stats_section.dart (lines 28-46)
Row(
  children: [
    Icon(Iconsax.notification, size: 16, color: AppColorTokens.light.textSecondary),
    const SizedBox(width: 6),
    Text(
      'NOTIFICATIONS',
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: AppColorTokens.light.textSecondary,
        letterSpacing: 1.5,
      ),
    ),
  ],
),
```

### Pattern 3: List Tile (36px icon container pattern, D-03)

```dart
// Established pattern from 26-CONTEXT.md D-03
Container(
  width: 36,
  height: 36,
  decoration: BoxDecoration(
    color: AppColorTokens.light.inputFill,
    borderRadius: BorderRadius.circular(10),
  ),
  child: Icon(Iconsax.notification, size: 18, color: AppColorTokens.light.textSecondary),
),
```

### Pattern 4: Notification Toggle Logic

The toggle has three visual states based on `notificationStatusProvider` + `settingsProvider`:

| Condition | Toggle State | Subtitle | Tap Behavior |
|-----------|-------------|----------|--------------|
| `pushNotificationsEnabled == true` | ON, enabled | none | Toggle OFF → `removeToken()` + persist false |
| `pushNotificationsEnabled == false` + status != `permissionDenied` | OFF, enabled | none | Toggle ON → `initialize()` → if granted persist true, else persist false |
| `status == permissionDenied` | OFF, disabled | "Enable in device Settings" | Tap anywhere → `AppSettings.openAppSettings()` |

**Key insight (from `appBootstrapProvider`):** The bootstrap provider already listens to `settingsProvider.pushNotificationsEnabled` and calls `initialize()` or `removeToken()` automatically. The toggle in the UI only needs to call `setPushNotificationsEnabled(value)` — the bootstrap provider handles the FCM side effect. No duplicate FCM calls needed from the widget.

Wait — re-reading `appBootstrapProvider`: it uses `ref.listen` which fires on changes. The toggle widget should call `setPushNotificationsEnabled()` and let bootstrap handle it, OR call the service directly. Given D-05 says "toggle ON calls `NotificationService.initialize()` directly", the widget should coordinate both for immediate feedback on the permission dialog. See pitfall 1 for the coordination pattern.

### Pattern 5: mailto URI Construction

```dart
// Source: url_launcher official docs + existing usage in vault_screen.dart
final Uri feedbackUri = Uri(
  scheme: 'mailto',
  path: 'support@rihla.app',           // Claude's discretion — placeholder
  query: Uri.encodeQueryComponent(     // Use encodeQueryParameters helper
    'subject=Rihla Feedback&body=App version: ${metadata.version}',
  ),
);
await launchUrl(feedbackUri, mode: LaunchMode.externalApplication);
```

Use the `encodeQueryParameters` helper (shown in url_launcher docs) rather than `encodeQueryComponent` directly — spaces need `%20` not `+` in mailto query strings.

### Pattern 6: Entrance Animations (stagger continuation)

```dart
// Source: lib/features/settings/screens/profile_screen.dart (lines 49-59)
// Identity: delay 100ms, Stats: delay 200ms
// Phase 26 continues the stagger:
ProfileNotificationsSection().animate().fadeIn(delay: 300.ms).slideY(begin: 0.1),
ProfileAboutSection().animate().fadeIn(delay: 400.ms).slideY(begin: 0.1),
ProfileSupportSection().animate().fadeIn(delay: 500.ms).slideY(begin: 0.1),
```

### Anti-Patterns to Avoid

- **Calling `NotificationService.initialize()` directly from the Switch `onChanged` without also calling `setPushNotificationsEnabled()`:** The bootstrap provider listens to `settingsProvider` — if you only call `initialize()` on the service, the persisted preference won't update. Always persist via `settingsProvider` first (or simultaneously).
- **Checking notification permission with `permission_handler` when `firebase_messaging` is already installed:** FCM's `getNotificationSettings()` returns the same `AuthorizationStatus` values. No additional package needed for status checking — only `app_settings` is needed for the deep-link.
- **Using `Navigator.push` for the licenses page:** `showLicensePage()` is an imperative API that pushes its own route. Don't wrap it in GoRouter — call it directly.
- **Accessing `context` inside async gap without `context.mounted` check:** The mailto and openAppSettings calls are async. Check `context.mounted` before showing error SnackBars after the await.
- **Using `AppColorTokens.light.textMuted` for functional text in the subtitle:** The CLAUDE.md explicitly states textMuted is decorative only (WCAG failure). Use `textSecondary` for the "Enable in device Settings" subtitle.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| App version string | Custom version reader | `appMetadataProvider` (already exists) | Already calls `PackageInfo.fromPlatform()`, wraps in `AppMetadata` with `versionLabel` getter |
| Notification permission check at startup | Manual FCM poll | `notificationStatusProvider` + `appBootstrapProvider` (already exist) | Bootstrap already runs `initialize()` if `pushNotificationsEnabled == true` on app start; status is already tracked |
| Open app settings deep-link | `Uri.parse('app-settings:...')` with platform-specific logic | `app_settings` package `AppSettings.openAppSettings()` | iOS vs Android URL schemes differ; the package handles both |
| Open-source licenses UI | Custom licenses screen | Flutter SDK `showLicensePage()` | Built-in, auto-populated from pubspec, no maintenance |
| Mailto URL construction | Raw string concatenation | `Uri(scheme: 'mailto', path: '...', query: encodeQueryParameters(...))` | Proper encoding — special chars in subject/body break raw strings |

---

## Common Pitfalls

### Pitfall 1: Double-Triggering FCM calls
**What goes wrong:** Widget calls `notificationService.initialize()` directly AND `settingsProvider.setPushNotificationsEnabled(true)` — then `appBootstrapProvider` hears the settings change and calls `initialize()` again, requesting permissions twice.
**Why it happens:** `appBootstrapProvider` uses `ref.listen` on `pushNotificationsEnabled` and calls `initialize()` on any change to `true`. If the widget also calls `initialize()`, there are two permission dialogs in sequence.
**How to avoid:** Only call `settingsProvider.setPushNotificationsEnabled(true)` from the widget. `appBootstrapProvider` handles the FCM call. The toggle gets immediate UI feedback via `notificationStatusProvider` which `NotificationService` updates internally.
**Warning signs:** Permission dialog appears twice; `_initialized` guard in `NotificationService` prevents the second dialog from showing but the second call still hits Firebase.

### Pitfall 2: `permissionDenied` State Not Initialized on App Start
**What goes wrong:** App launches, user had previously denied notifications, but `notificationStatusProvider` starts as `NotificationStatus.off` — the disabled tile state never shows because status was never set to `permissionDenied`.
**Why it happens:** `notificationStatusProvider` is a `StateProvider` initialized to `off`. Nothing hydrates it from the OS on cold start.
**How to avoid:** On `ProfileScreen` build (or in `ProfileNotificationsSection`'s `initState` / an `initProvider`), call `FirebaseMessaging.instance.getNotificationSettings()` once and update `notificationStatusProvider` if the result is `denied`. Alternatively, expose a `checkPermissionStatus()` method on `NotificationService` that queries FCM settings and updates the provider.
**Warning signs:** Disabled tile never shows; "Enable in device Settings" subtitle never appears; users who denied are shown an enabled toggle that silently fails.

### Pitfall 3: `showLicensePage` and Context Validity
**What goes wrong:** `showLicensePage()` is called after an async gap (e.g., after awaiting `appMetadataProvider`) — Flutter throws "Looking up a deactivated widget's ancestor is unsafe."
**Why it happens:** Widget rebuilds or navigates during the async gap; context is stale.
**How to avoid:** Read metadata synchronously via `ref.watch(appMetadataProvider).valueOrNull` in `build()`. Call `showLicensePage()` in an `onTap` callback with no async gap — all data needed (version string) is already in scope from the synchronous `watch`.
**Warning signs:** Assertion error in debug mode when tapping the licenses tile.

### Pitfall 4: mailto on iOS Simulator
**What goes wrong:** `launchUrl` with mailto scheme throws `PlatformException: Could not launch` on iOS Simulator.
**Why it happens:** iOS Simulator has no Mail app. `canLaunchUrl` returns false.
**How to avoid:** Wrap `launchUrl` with a `canLaunchUrl` check. Show a SnackBar with the email address as fallback. This is test environment only — real devices work.
**Warning signs:** Only fails in simulator; passes on device.

---

## Code Examples

Verified patterns from existing codebase + official sources:

### Reading App Version (appMetadataProvider)
```dart
// Source: lib/core/config/app_metadata.dart — already exists
final metadataAsync = ref.watch(appMetadataProvider);
final versionText = metadataAsync.when(
  data: (m) => 'v${m.version}',
  loading: () => '—',
  error: (_, __) => '—',
);
```

### Notification Toggle — Recommended Wiring
```dart
// Toggle onChanged — widget only persists preference; bootstrap handles FCM
Future<void> _onToggleChanged(bool value, WidgetRef ref) async {
  HapticService.selection();
  await ref.read(settingsProvider.notifier).setPushNotificationsEnabled(value);
  // appBootstrapProvider reacts and calls initialize() or removeToken()
}
```

### Notification Toggle — Reading Disabled State
```dart
// Source: lib/core/services/notification_service.dart (NotificationStatus enum)
final status = ref.watch(notificationStatusProvider);
final settings = ref.watch(settingsProvider);

final isPermDenied = status == NotificationStatus.permissionDenied;
final isOn = settings.pushNotificationsEnabled && !isPermDenied;
```

### Open App Settings (D-08)
```dart
// Requires: app_settings: ^7.0.0 in pubspec.yaml
import 'package:app_settings/app_settings.dart';

await AppSettings.openAppSettings();
```

### Mailto Launch (D-10)
```dart
// Source: url_launcher official docs + vault_screen.dart pattern
import 'package:url_launcher/url_launcher.dart';

String _encodeQueryParameters(Map<String, String> params) =>
    params.entries
        .map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .join('&');

final uri = Uri(
  scheme: 'mailto',
  path: 'support@rihla.app',
  query: _encodeQueryParameters({
    'subject': 'Rihla Feedback',
    'body': 'App version: v${metadata.version}',
  }),
);
if (await canLaunchUrl(uri)) {
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}
```

### showLicensePage (D-11)
```dart
// Source: Flutter SDK — no package needed
showLicensePage(
  context: context,
  applicationName: 'Rihla',
  applicationVersion: metadata.version,
  applicationLegalese: '© 2026 Rihla',
);
```

### SnackBar "Coming soon" (D-13)
```dart
// SnackBar theme already configured globally in app_theme.dart (line 138-148)
ScaffoldMessenger.of(context).showSnackBar(
  const SnackBar(content: Text('Coming soon')),
);
```

### Semantic Keys to Add to ProfileKeys
```dart
// Add to lib/features/settings/keys/profile_keys.dart
static const notificationToggleTile = Key('profile_notification_toggle_tile');
static const notificationSwitch = Key('profile_notification_switch');
static const versionTile = Key('profile_version_tile');
static const feedbackTile = Key('profile_feedback_tile');
static const licensesTile = Key('profile_licenses_tile');
static const coffeeTile = Key('profile_coffee_tile');
```

### permissionDenied Startup Hydration
```dart
// Call once in ProfileNotificationsSection or ProfileScreen build (via ref.listen / init)
// Requires no additional package — firebase_messaging already installed
Future<void> _hydrateNotificationStatus(WidgetRef ref) async {
  final messaging = FirebaseMessaging.instance;
  final settings = await messaging.getNotificationSettings();
  if (settings.authorizationStatus == AuthorizationStatus.denied) {
    ref.read(notificationStatusProvider.notifier).state =
        NotificationStatus.permissionDenied;
  }
}
```

---

## Environment Availability

Step 2.6: No new external services required. All packages are existing dependencies except `app_settings`. No runtime services to probe.

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| `package_info_plus` | INFO-01 | Yes | 8.3.1 (resolved) | — |
| `url_launcher` | INFO-02 | Yes | 6.3.2 | — |
| `firebase_messaging` | NOTIF-01, NOTIF-02 | Yes | 16.1.3 | — |
| `app_settings` | D-08 (openAppSettings) | No | — | Use `url_launcher` with `app-settings:` URI scheme (fragile, not recommended) |
| Flutter SDK `showLicensePage` | INFO-03 | Yes | SDK built-in | — |

**Missing dependencies with no fallback:**
- `app_settings` — needed for D-08. Must add to pubspec.yaml.

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | flutter_test (SDK) + mocktail 1.0.4 |
| Config file | flutter_test block in pubspec.yaml |
| Quick run command | `flutter test test/features/profile/profile_screen_test.dart` |
| Full suite command | `flutter test` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| NOTIF-01 | Toggle tile shows correct ON/OFF state based on `settingsProvider.pushNotificationsEnabled` | widget | `flutter test test/features/profile/profile_screen_test.dart` | ❌ — new tests in existing file |
| NOTIF-01 | Disabled tile + subtitle when `notificationStatusProvider == permissionDenied` | widget | `flutter test test/features/profile/profile_screen_test.dart` | ❌ — new tests in existing file |
| NOTIF-02 | Toggle ON calls `settingsProvider.setPushNotificationsEnabled(true)` | widget | `flutter test test/features/profile/profile_screen_test.dart` | ❌ — new tests in existing file |
| NOTIF-02 | Toggle OFF calls `settingsProvider.setPushNotificationsEnabled(false)` | widget | `flutter test test/features/profile/profile_screen_test.dart` | ❌ — new tests in existing file |
| INFO-01 | Version tile shows version string from `appMetadataProvider` | widget | `flutter test test/features/profile/profile_screen_test.dart` | ❌ — new tests in existing file |
| INFO-02 | Feedback tile is present and tappable | widget | `flutter test test/features/profile/profile_screen_test.dart` | ❌ — new tests in existing file |
| INFO-03 | Licenses tile is present | widget | `flutter test test/features/profile/profile_screen_test.dart` | ❌ — new tests in existing file |
| SUPP-01 | Coffee tile is present and tapping shows "Coming soon" SnackBar | widget | `flutter test test/features/profile/profile_screen_test.dart` | ❌ — new tests in existing file |

**Note on mocking:** Tests for NOTIF-02 must mock `notificationServiceProvider` with a `mocktail` mock to avoid real FCM calls. The `appMetadataProvider` must be overridden with a sync value — use `appMetadataProvider.overrideWith((ref) => Future.value(AppMetadata.fallback()))` or a concrete version string.

### Sampling Rate
- **Per task commit:** `flutter test test/features/profile/profile_screen_test.dart`
- **Per wave merge:** `flutter test`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] New test groups in `test/features/profile/profile_screen_test.dart` — covers NOTIF-01, NOTIF-02, INFO-01, INFO-02, INFO-03, SUPP-01
- [ ] Mock for `notificationServiceProvider` (mocktail class `MockNotificationService`)
- [ ] Override for `appMetadataProvider` returning known version string
- [ ] Override for `notificationStatusProvider` to simulate permissionDenied state

---

## Sources

### Primary (HIGH confidence)
- Existing codebase — `notification_service.dart`, `settings_provider.dart`, `app_metadata.dart`, `app_bootstrap_provider.dart`, `profile_screen.dart`, `profile_stats_section.dart` — read directly
- Flutter SDK `showLicensePage` — built-in, no version concerns
- `package_info_plus` pub.dev — version 8.3.1 confirmed in pubspec.lock
- `url_launcher` pub.dev — version 6.3.2 confirmed in pubspec.yaml; existing usage in vault_screen.dart
- `firebase_messaging` `getNotificationSettings()` / `AuthorizationStatus` — confirmed in notification_service.dart

### Secondary (MEDIUM confidence)
- `app_settings` 7.0.0 — pub.dev page fetched 2026-04-01; `AppSettings.openAppSettings()` confirmed
- `permission_handler` 12.0.1 — pub.dev page fetched 2026-04-01; confirmed NOT installed, `app_settings` preferred

### Tertiary (LOW confidence)
- None

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all packages verified in pubspec.yaml/pubspec.lock or pub.dev
- Architecture: HIGH — established patterns read directly from codebase
- Pitfalls: HIGH (pitfalls 1-3) / MEDIUM (pitfall 4 — simulator behavior well-known but not tested here)

**Research date:** 2026-04-01
**Valid until:** 2026-05-01 (stable packages; flutter_animate and notification APIs rarely change)
