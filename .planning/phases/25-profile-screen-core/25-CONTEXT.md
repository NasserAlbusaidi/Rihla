# Phase 25: Profile Screen Core - Context

**Gathered:** 2026-04-01
**Status:** Ready for planning

<domain>
## Phase Boundary

Users can view and manage their identity and see their cross-group stats in a new profile screen. This phase delivers: display name viewing (IDENT-01), display name editing with Firestore propagation (IDENT-02, IDENT-03), and cross-group stats — group count, event count, total spending (STATS-01, STATS-02, STATS-03).

Phase 26 will add settings sections (notifications, currency, language, theme) and about/support sections to this same screen.

</domain>

<decisions>
## Implementation Decisions

### Screen Architecture
- **D-01:** Replace the existing `SettingsScreen` at `/settings` with a new profile screen at `/profile`. Delete the old settings screen entirely.
- **D-02:** Single screen built across two phases: Phase 25 builds identity + stats sections. Phase 26 adds settings + about/support sections to the same screen.
- **D-03:** Route changes from `/settings` to `/profile`. Update any existing references.

### Identity Section
- **D-04:** Large initials circle (64px) showing first letter(s) of display name. Terracotta background, white text.
- **D-05:** Display name shown below the initials circle.
- **D-06:** Tapping the name (or an edit affordance) opens a bottom sheet with text field + Save button for name editing.
- **D-07:** Name edit bottom sheet matches the earthy design language (not a plain AlertDialog).

### Stats Section
- **D-08:** 3 compact stat cards in a horizontal row below the identity section.
- **D-09:** Each card: big number on top + label underneath. Cards use `cardSurface` background with earthy accent-colored numbers.
- **D-10:** Stats shown: Groups count (STATS-01), Events count (STATS-02), Total spending with "OMR" currency prefix e.g. "OMR 45.250" (STATS-03).

### Entry Point & Navigation
- **D-11:** Small initials circle (32px) in the top-right of the home dashboard header. Tapping navigates to `/profile`.
- **D-12:** Slide-right transition (standard `CustomTransitionPage` pattern matching all other module screens).

### Name Propagation UX
- **D-13:** When user saves a new display name, the Save button shows a spinner while Firestore batch writes complete, then a brief success indicator (checkmark).
- **D-14:** Firestore propagation: batch update `display_name` on all participant records across all groups the user belongs to.
- **D-15:** Offline behavior: save to SharedPreferences + sync queue. Propagate to Firestore on reconnect. No error shown to user.
- **D-16:** Also update local SharedPreferences `deviceName` so the app stays consistent immediately.

### Claude's Discretion
- Exact bottom sheet styling for name edit (spacing, button style, validation)
- Initials extraction logic (first letter of first name vs first+last)
- Stat card internal spacing, font sizes, and accent color choice
- Loading/skeleton state for stats while data loads
- How to compute total spending (sum across all groups from existing providers or new query)
- Screen layout details (padding, section spacing, scroll behavior)
- Whether to show "Not set" placeholder or prompt when no name exists

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Current Settings Screen (being replaced)
- `lib/features/settings/screens/settings_screen.dart` — Full screen being replaced. Contains name edit dialog, notification toggle, about section. Reference for what exists and what to preserve for Phase 26.
- `lib/features/settings/keys/settings_keys.dart` — Semantic test keys for settings screen

### Settings/Identity Data Layer
- `lib/core/providers/settings_provider.dart` — `settingsProvider` (StateNotifier), `setDeviceName()` method. Currently local-only — needs Firestore propagation added.
- `lib/core/models/app_settings_model.dart` — `AppSettings` model with `deviceName` field
- `lib/core/services/settings_service.dart` — SharedPreferences persistence for settings

### Group & Stats Data
- `lib/features/groups/providers/group_provider.dart` — `userGroupsProvider` for group list and count
- `lib/features/events/providers/event_provider.dart` — `groupEventsProvider` for events per group
- `lib/features/groups/providers/group_balance_provider.dart` — `crossGroupBalanceProvider` for cross-group balance data
- `lib/features/home/providers/dashboard_providers.dart` — `crossGroupActivityProvider`, `weeklyGroupSpendingProvider` — existing cross-group data aggregation patterns

### Participant Records (for name propagation)
- `lib/features/groups/models/group_member_model.dart` — Group member model with `displayName` field
- `lib/features/groups/providers/group_provider.dart` — Group member data access

### Navigation
- `lib/core/router/app_router.dart` — Route definitions. `/settings` route to be replaced with `/profile`.
- `lib/features/home/screens/home_screen.dart` — Home dashboard header where the profile entry point (initials avatar) will be added.

### Design Tokens
- `lib/core/theme/tokens/color_tokens.dart` — AppColorTokens (terracotta for initials circle, accent colors for stat numbers)
- `lib/core/theme/tokens/spacing_tokens.dart` — AppSpacingTokens for consistent spacing
- `lib/core/theme/tokens/shadow_tokens.dart` — AppShadowTokens for card shadows

### Requirements
- `.planning/REQUIREMENTS.md` — IDENT-01, IDENT-02, IDENT-03, STATS-01, STATS-02, STATS-03

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `SettingsScreen._buildProfileSection()` — existing name display + edit pattern (to be replaced but informative)
- `crossGroupBalanceProvider` — already computes cross-group balance data; can derive total spending
- `userGroupsProvider` — groups list; `.length` gives STATS-01
- `groupEventsProvider` per group — events per group; aggregate for STATS-02
- `AppColorTokens.light.primary` (teal) and terracotta tokens — for initials circle and stat accents
- `flutter_animate` — entrance animations (fadeIn + slideY) already used on all screens
- `HapticService` — for save/edit interactions
- `AppShadowTokens.standard.raised` — card shadow pattern

### Established Patterns
- Cards: `cardSurface` bg, `BorderRadius.circular(24)`, `shadowRaised`
- Section headers: icon + uppercase label with `letterSpacing: 1.5`, `textMuted` color
- List tiles: 36px icon container with `inputFill` bg, `borderRadius: 10`
- Entrance animations: `animate().fadeIn(delay: Nms).slideY(begin: 0.1)`
- All colors via `AppColorTokens.light.*` — CI blocks hardcoded `Color(0xFF...)` literals

### Integration Points
- `app_router.dart` — replace `/settings` route with `/profile`
- `home_screen.dart` — add initials avatar to dashboard header (top-right)
- `settings_provider.dart` — extend `setDeviceName()` to also trigger Firestore batch write
- New profile screen file in `lib/features/settings/screens/` (or rename feature folder)

</code_context>

<specifics>
## Specific Ideas

- Initials circle on profile screen: 64px, terracotta bg, white text — same visual identity as the 32px avatar in the home header
- Stat cards: 3-across row, big number + label, "OMR 45.250" format for spending (currency prefix on number, not in label)
- Name edit via bottom sheet (not dialog) — feels more intentional and matches earthy design language
- Save flow: tap Save → spinner → checkmark → close. Offline: save locally + queue, no error shown.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 25-profile-screen-core*
*Context gathered: 2026-04-01*
