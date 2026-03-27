# Phase 2: Groups - Context

**Gathered:** 2026-03-26
**Status:** Ready for planning

<domain>
## Phase Boundary

Users can create a persistent group, share an invite code, and see all their groups on the home screen. Group detail shows members, stats, and an event timeline placeholder. No events yet (Phase 3). No cross-event financials yet (Phase 5). No Supabase migration — this is greenfield Firestore.

</domain>

<decisions>
## Implementation Decisions

### Home Screen Layout
- **D-01:** Groups-first home screen. The home screen IS the groups list. No tabs, no split with legacy trips.
- **D-02:** No legacy trip section needed — starting fresh, no existing trip data to bridge.
- **D-03:** Group cards show: group name, member count, and user's net balance in the group (shows "0.000 OMR" until Phase 5 populates balances).
- **D-04:** FAB (Floating Action Button) for create/join actions. Tap opens bottom sheet with "Create Group" and "Join Group" options.

### Member Identity
- **D-05:** Self-naming. No pre-populated name list. Each person who joins enters the group with their profile name.
- **D-06:** Profile name is the existing device name in `settingsProvider` (SharedPreferences). One name, one place. Automatically used when creating or joining any group.
- **D-07:** Members can change their display name in a group at any time from the group members screen.

### Group Creation Flow
- **D-08:** Create group form: group name + currency selection. Creator's display name pulled automatically from device settings.
- **D-09:** On creation, creator is automatically added as a member with role CREATOR.
- **D-10:** Invite code generated on creation (6-char alphanumeric, same generation logic as existing trips, excluding confusing chars O/0/I/l).
- **D-11:** After creation, show the group with a share prompt for the invite code.

### Group Join Flow
- **D-12:** Enter 6-char invite code. On valid code, joiner is added to the group with their device profile name and role MEMBER.
- **D-13:** No name claiming step (unlike trips). Joiner's identity comes from their device settings name.

### Group Detail Screen
- **D-14:** Dashboard style. Group name + stats header (member count, creation date) + member list + empty event timeline placeholder.
- **D-15:** Creator can rename the group from a group settings screen.
- **D-16:** Group settings screen available: rename group, change currency.
- **D-17:** No member leaving in Phase 2. Once joined, you're in. (Leaving to be discussed in a future phase.)
- **D-18:** No group deletion. Groups are persistent constructs (`allow delete: if false` already in security rules).

### Invite Code Lifecycle
- **D-19:** Same 6-char alphanumeric format as existing trip codes. One pattern for the whole app.
- **D-20:** Permanent code — cannot be regenerated. One code per group, forever.
- **D-21:** No hard member limit. UI designed/optimized for small friend groups (5-15 people).
- **D-22:** Two sharing mechanisms: copy to clipboard (with toast) AND native OS share sheet with pre-written message.

### Claude's Discretion
- Group card visual design and layout
- Empty state when user has no groups
- Group detail screen exact layout and spacing
- Event timeline placeholder design
- Settings screen layout
- Share sheet message text
- Error handling and validation UX
- Firestore write batching for group creation (group doc + inviteCode doc + member doc)
- GoRouter route structure for new group screens

</decisions>

<specifics>
## Specific Ideas

- Group cards should show net balance even before Phase 5 populates real data — shows "0.000 OMR" to establish the pattern early.
- The FAB pattern (tap to reveal create/join) keeps the groups list clean — no action cards eating screen space.
- Since there are no legacy trips, the home screen can be purely groups-focused with no transition awkwardness.

</specifics>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Group data model
- `.planning/phases/01-data-foundation/1-CONTEXT.md` — Phase 1 decisions: memberIds array (D-14), group delete blocked, inviteCodes public read
- `lib/core/services/local_database.dart` lines 204-281 — SQLite v6 groups/group_members/group_ledger table schemas
- `security/firestore.rules` — Existing Firestore security rules for groups collection and inviteCodes collection

### Existing patterns to mirror
- `lib/features/trip/screens/create_trip_screen.dart` — Trip creation form pattern (ConsumerStatefulWidget, form sections, invite code generation)
- `lib/features/trip/screens/join_trip_screen.dart` — Trip join flow (code entry, haptic feedback, two-step process — simplify to one-step for groups)
- `lib/features/home/screens/home_screen.dart` — Current home screen (will be replaced with groups-first layout)
- `lib/core/router/app_router.dart` — GoRouter configuration (add /create-group, /join-group routes)

### Firestore and offline
- `lib/core/config/firebase_config.dart` — FirebaseConfig initialization and anonymous auth
- `lib/core/services/money_serializer.dart` — MoneySerializer for group ledger amounts (Phase 5 will use, but schema uses subunits now)
- `lib/core/services/offline_repository.dart` — OfflineRepository watch/save pattern to extend for groups

### Shared UI
- `lib/shared/widgets/` — Reusable widgets: EmptyStateView, OfflineBanner, LoadingButton, SkeletonLoader
- `lib/core/theme/app_theme.dart` — Design tokens: spacing, radii, shadows, colors
- `lib/core/utils/page_transitions.dart` — AppPageRoute and AppBottomSheetRoute for navigation

### Settings / profile name
- `lib/core/providers/settings_provider.dart` — settingsProvider with device name (used as profile name for groups)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `CreateTripScreen` form pattern (ConsumerStatefulWidget + form sections + loading/error providers) — mirror for CreateGroupScreen
- `JoinTripScreen` two-step flow — simplify to one-step for groups (no name claiming, just enter code)
- `HomeScreen` trip list with sorting — replace with groups list
- Invite code generation in TripService (`_generateInviteCode()` 6-char alphanumeric) — extract or duplicate for GroupService
- `SmartModuleCard` widget — reuse in group detail for module sections
- `EmptyStateView` — use for empty groups list and empty member list
- `AppPageRoute` / `AppBottomSheetRoute` — navigation transitions

### Established Patterns
- `StreamProvider` for reactive data lists (`userTripsProvider` pattern → `userGroupsProvider`)
- `StreamProvider.family` for parameterized data (`tripParticipantsProvider` → `groupMembersProvider`)
- `StateProvider` for loading/error state in create/join flows
- `OfflineRepository.watch*()` returns streams, `save*()` writes locally + enqueues sync
- Feature-first directory structure: `lib/features/groups/{models,providers,screens,services,widgets}/`

### Integration Points
- `app_router.dart` — add GoRouter routes: `/create-group`, `/join-group`
- `home_screen.dart` — replace trip list with groups list
- `offline_repository.dart` — add `watchGroups()`, `saveGroup()`, `watchGroupMembers()`, `saveGroupMember()`
- `local_database.dart` — SQLite groups tables already exist (v6), need cache read/write methods in CacheService
- `settings_provider.dart` — read device name for auto-populating creator/joiner display name

</code_context>

<deferred>
## Deferred Ideas

- Member leaving groups — needs product discussion on what happens to their financial history. Future phase.
- D-15 (group delete blocked) revisit — user flagged this for future discussion. May need soft-delete or archive.
- Group admin roles beyond CREATOR — the schema supports roles but Phase 2 only uses CREATOR and MEMBER.
- Invite code regeneration — kept permanent for simplicity, revisit if code leaking becomes a real problem.
- Group avatar/icon selection — not in Phase 2, could add personality to group cards.
- Deep linking to groups — ENH-03 in requirements, separate from Phase 2.

</deferred>

---

*Phase: 02-groups*
*Context gathered: 2026-03-26*
