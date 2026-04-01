# Phase 26: Settings & Support - Context

**Gathered:** 2026-04-01
**Status:** Ready for planning

<domain>
## Phase Boundary

Add notification preferences, app info, and support options to the existing profile screen built in Phase 25. This phase delivers: notification status display (NOTIF-01), notification toggle (NOTIF-02), app version display (INFO-01), feedback/support link (INFO-02), open-source licenses access (INFO-03), and "Buy me a coffee" placeholder (SUPP-01).

No new screens — all content is added as new sections to the existing `ProfileScreen`.

</domain>

<decisions>
## Implementation Decisions

### Section Layout & Grouping
- **D-01:** Grouped list tiles with uppercase section headers matching the established pattern (icon + uppercase label with `letterSpacing: 1.5`, `textSecondary` color). *(Updated from `textMuted` — CLAUDE.md forbids textMuted for functional text, WCAG AA failure at 2.86:1. `textSecondary` matches ProfileStatsSection reference.)*
- **D-02:** Three sections below existing identity + stats: NOTIFICATIONS, ABOUT, SUPPORT — each with its own header.
- **D-03:** List tiles use the established pattern: 36px icon container with `inputFill` bg, `borderRadius: 10`.
- **D-04:** Section order top to bottom: Identity (existing) → Stats (existing) → Notifications → About → Support.

### Notification Toggle
- **D-05:** Push notification toggle is a Switch widget integrated into a list tile. Flipping ON calls `settingsProvider.setPushNotificationsEnabled(true)` — the `appBootstrapProvider` reacts and calls `NotificationService.initialize()` which triggers the OS permission dialog. *(Updated: widget persists preference only; bootstrap handles FCM. Prevents double permission dialog per Research Pitfall 1.)*
- **D-06:** If OS permission granted, toggle stays ON and `settingsProvider.setPushNotificationsEnabled(true)` persists the preference.
- **D-07:** If OS permission denied, toggle flips back to OFF with a brief explanation.
- **D-08:** If the user previously denied OS permission, toggle shows as OFF and disabled with subtitle text "Enable in device Settings" — tapping opens app settings via `openAppSettings()`.

### App Info
- **D-09:** App version displayed as a non-tappable list tile showing version string (e.g., "v2.2.0") from `package_info_plus`.
- **D-10:** "Send Feedback" tile opens a mailto: link with a pre-filled to address and subject line.
- **D-11:** "Open-source Licenses" tile navigates to Flutter's built-in `showLicensePage()`.

### Support
- **D-12:** "Buy me a coffee" is a standard list tile with the same visual weight as other items — not highlighted or accent-colored.
- **D-13:** Tapping "Buy me a coffee" shows a SnackBar saying "Coming soon" since it's a placeholder.

### Claude's Discretion
- Specific icon choices (Iconsax variants) for each tile
- Entrance animation delays for new sections (continuing the stagger pattern)
- Feedback email address and subject line text
- SnackBar styling for "Coming soon" message
- Whether to use `app_settings` or `permission_handler` for `openAppSettings()`
- Exact spacing between sections

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Profile Screen (Phase 25 output — being extended)
- `lib/features/settings/screens/profile_screen.dart` — Current profile screen with identity + stats sections. New sections are added below existing content.
- `lib/features/settings/keys/profile_keys.dart` — Semantic test keys for profile screen. Extend with new keys for Phase 26 tiles.
- `lib/features/settings/widgets/profile_stats_section.dart` — Stats section widget for reference on section structure.

### Notification Infrastructure
- `lib/core/services/notification_service.dart` — `NotificationService` with `initialize()`, `removeToken()`, `notificationStatusProvider`. D-05 calls `initialize()` on toggle ON.
- `lib/core/providers/settings_provider.dart` — `settingsProvider` with `setPushNotificationsEnabled()`. D-06 persists the toggle state.
- `lib/core/models/app_settings_model.dart` — `AppSettings` model with `pushNotificationsEnabled` field.

### Design Tokens
- `lib/core/theme/tokens/color_tokens.dart` — AppColorTokens for all colors
- `lib/core/theme/tokens/spacing_tokens.dart` — AppSpacingTokens for spacing
- `lib/core/theme/tokens/shadow_tokens.dart` — AppShadowTokens for card shadows

### Requirements
- `.planning/REQUIREMENTS.md` — NOTIF-01, NOTIF-02, INFO-01, INFO-02, INFO-03, SUPP-01

### Phase 25 Context (decisions to preserve)
- `.planning/phases/25-profile-screen-core/25-CONTEXT.md` — D-01 through D-16 for identity + stats sections. Phase 26 must not alter these sections.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `ProfileScreen` — existing screen to extend with new sections (SingleChildScrollView + Column layout)
- `NotificationService` — full FCM lifecycle: `initialize()`, `removeToken()`, permission handling, token save/refresh
- `notificationStatusProvider` — `StateProvider<NotificationStatus>` with `off/enabled/permissionDenied/error` states
- `settingsProvider` — `StateNotifierProvider<SettingsNotifier, AppSettings>` with `setPushNotificationsEnabled()`
- `SettingsService` — SharedPreferences persistence including `pushNotificationsEnabled`
- `HapticService` — for toggle/tap feedback
- `flutter_animate` — entrance animations already used on identity and stats sections

### Established Patterns
- Section headers: icon + uppercase label, `letterSpacing: 1.5`, `textMuted` color
- List tiles: 36px icon container, `inputFill` bg, `borderRadius: 10`
- Cards: `cardSurface` bg, `BorderRadius.circular(24)`, `shadowRaised`
- Entrance animations: `.animate().fadeIn(delay: Nms).slideY(begin: 0.1)` with staggered delays
- All colors via `AppColorTokens.light.*` — CI blocks hardcoded `Color(0xFF...)` literals

### Integration Points
- `profile_screen.dart` — add new section widgets to the Column children
- `profile_keys.dart` — add semantic keys for new tiles (notification toggle, version, feedback, licenses, coffee)
- `settings_keys.dart` — existing but minimal; Phase 26 keys go in `profile_keys.dart`
- `pubspec.yaml` — may need `package_info_plus` and potentially `app_settings` or `permission_handler` for openAppSettings

</code_context>

<specifics>
## Specific Ideas

- Grouped list tiles matching the existing section header pattern — not cards, not flat list
- Notification toggle triggers OS prompt directly — no intermediate explanation sheet
- Permission denied state: disabled toggle + "Enable in device Settings" subtitle + tap opens app settings
- Feedback via mailto: — simplest option for solo dev, no form infrastructure
- "Buy me a coffee" is deliberately understated — same visual weight as other tiles, SnackBar placeholder

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 26-settings-support*
*Context gathered: 2026-04-01*
