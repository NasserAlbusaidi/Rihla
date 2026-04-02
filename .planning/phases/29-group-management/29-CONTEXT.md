# Phase 29: Group Management - Context

**Gathered:** 2026-04-02
**Status:** Ready for planning

<domain>
## Phase Boundary

Visual refresh and functional additions to GroupSettingsScreen: apply Phase 26 ProfileScreen design pattern (grouped sections, uppercase headers, card containers, stagger animations), add members section with creator badge and remove capability, add leave group (any member) and delete group (creator-only) actions. Invite code display already exists in settings — gets visual polish only.

</domain>

<decisions>
## Implementation Decisions

### Settings Screen Scope
- **D-01:** Visual polish of existing settings (name, currency, invite code) plus two new actions: leave group and delete group. No module toggles this phase.
- **D-02:** Leave group available to any member. Delete group available to creator only.
- **D-03:** Both leave and delete require confirmation dialog before executing.

### Member Management
- **D-04:** Members section lives inside GroupSettingsScreen as a new section — not a separate screen.
- **D-05:** Creator gets a visible "Creator" badge/chip next to their name in the member list.
- **D-06:** Creator can remove members from the group via the member list.
- **D-07:** Leave/remove is blocked if the member has a non-zero balance. User must settle up first. Show a clear message explaining why and link to settle-up.

### Visual Refresh
- **D-08:** Follow Phase 26 ProfileScreen pattern exactly: grouped sections as separate widgets, uppercase section headers (icon + `letterSpacing: 1.5` + `textSecondary`), card containers with `cardSurface` bg + `raised` shadow + `borderRadius: 24`, staggered `.animate().fadeIn().slideY()` entrance.
- **D-09:** Horizontal padding 24px (matching ProfileScreen, not 16px from GroupDetailScreen).
- **D-10:** Skeleton loading on initial load, inline error with retry on failure (same pattern as Phase 28).

### Invite Code Display
- **D-11:** Invite code section already exists in GroupSettingsScreen — visual polish only (apply card container pattern from D-08). No functional changes to copy/share behavior.

### Claude's Discretion
- Specific icon choices for section headers and member list items
- Exact layout of the member list within the card (ListTile vs custom Row)
- Confirmation dialog styling (AlertDialog vs BottomSheet)
- Animation delay values for stagger entrance
- How the "settle up first" blocking message is presented (inline text vs dialog)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 26 Pattern Reference (visual pattern to follow)
- `lib/features/settings/screens/profile_screen.dart` — Layout structure, section ordering, stagger animation pattern
- `lib/features/settings/widgets/profile_notifications_section.dart` — Section widget pattern: header + card container
- `lib/features/settings/widgets/profile_stats_section.dart` — Section widget with card container and shadow
- `lib/features/settings/widgets/profile_about_section.dart` — Section with list tiles inside card
- `lib/features/settings/keys/profile_keys.dart` — Key naming pattern for test keys

### Group Feature (being modified)
- `lib/features/groups/screens/group_settings_screen.dart` — Current screen to refresh (plain ListView with ListTiles)
- `lib/features/groups/providers/group_provider.dart` — GroupService (updateGroup, joinGroup), groupDetailProvider, groupMembersProvider
- `lib/features/groups/providers/group_balance_provider.dart` — groupBalancesProvider for checking non-zero balances before leave/remove
- `lib/features/groups/models/group_model.dart` — Group model with createdBy, memberIds, inviteCode
- `lib/features/groups/models/group_member_model.dart` — GroupMember model
- `lib/features/groups/keys/group_keys.dart` — Existing keys (settingsScreen, settingsTitle, settingsGroupNameTile, settingsCurrencyTile, settingsInviteCodeTile)
- `lib/features/groups/widgets/invite_code_display.dart` — Invite code widget (may be reusable)

### Design Tokens
- `lib/core/theme/tokens/color_tokens.dart` — AppColorTokens.light palette
- `lib/core/theme/tokens/spacing_tokens.dart` — AppSpacingTokens.standard
- `lib/core/theme/tokens/shadow_tokens.dart` — AppShadowTokens.standard.raised

### Phase 28 Context (prior decisions)
- `.planning/phases/28-group-detail/28-CONTEXT.md` — D-05: invite code removed from GroupDetailScreen, deferred to Phase 29 settings

### Routing
- `lib/core/router/app_router.dart` — GoRoute for /group/:gid/settings

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `ProfileNotificationsSection` / `ProfileAboutSection` / `ProfileSupportSection` — Section widget pattern to replicate for group settings sections
- `GroupService.updateGroup()` — Already supports name and currency updates
- `groupBalancesProvider` — Can check if a member has non-zero balance (for settle-up gate)
- `groupMembersProvider` — StreamProvider.family for member list
- `InviteCodeDisplay` widget — Existing invite code display, can be wrapped in new card container
- `HapticService` — Already used throughout for feedback on actions
- `LoadingButton` — Used in JoinGroupScreen, available for destructive action buttons

### Established Patterns
- Section widgets as separate files under `widgets/` directory
- `ConsumerWidget` for sections that need provider access
- `GroupKeys` static const keys for all testable elements
- `FirestoreRepository` base class for all Firestore operations
- WriteBatch for atomic multi-doc writes (pattern for leave/delete)

### Integration Points
- GroupSettingsScreen receives `groupId` from GoRouter path parameter
- Navigation: GroupDetailScreen settings icon → `/group/$groupId/settings`
- After delete group: navigate to `/home` (group no longer exists)
- After leave group: navigate to `/home` (user no longer a member)
- Settle-up link: `/group/$groupId/settle-up`

</code_context>

<specifics>
## Specific Ideas

- Follow ProfileScreen section pattern exactly — the group settings should feel like the same app as the profile screen
- "Creator" badge should be subtle (small chip, not a full row of color)
- Settle-up gate message should clearly link to the settle-up screen, not just explain the rule

</specifics>

<deferred>
## Deferred Ideas

- **Module toggles** — Let creator enable/disable event modules at group level. Belongs in a future phase.
- **Share invite via sheet** — Deep links, QR codes, or share sheet for invite codes. Keep copy-to-clipboard for now.

</deferred>

---

*Phase: 29-group-management*
*Context gathered: 2026-04-02*
