# Phase 23: Quick Action Fixes - Context

**Gathered:** 2026-03-31
**Status:** Ready for planning

<domain>
## Phase Boundary

Wire all 4 home screen quick action buttons to their correct destinations. Currently "Invite Friend" navigates to the join-group screen (wrong) and "Activity" tries to scroll the home page (silently fails). Fix both, plus add 0-groups edge case handling to all group-dependent actions.

</domain>

<decisions>
## Implementation Decisions

### Invite Friend Flow
- **D-01:** "Invite Friend" opens a native share sheet via `Share.share()` (share_plus already installed) with the selected group's invite code
- **D-02:** Share message format: "Join my group [name] on Rihla! Code: ABC123 — Download: [store link]" — includes app store URL
- **D-03:** Single group: skip picker, share directly (matches Add Expense/Settle Up behavior)
- **D-04:** Multiple groups: show group picker bottom sheet first, then share immediately after selection (no intermediate invite code display)
- **D-05:** No confirmation feedback after share sheet dismisses — OS share sheet already confirms

### Activity Destination
- **D-06:** "Activity" button navigates to a new cross-group activity screen (not scroll behavior)
- **D-07:** Data source: reuse existing `crossGroupActivityProvider` from `dashboard_providers.dart` — full-screen version of the same data
- **D-08:** Visual style: match `GroupActivityScreen` pattern (full-screen with header, paginated list, activity tiles) with a group name label on each tile

### Group Picker Behavior
- **D-09:** Invite Friend uses the same bottom sheet pattern as `_showGroupPicker` in home_screen.dart — consistent with Add Expense and Settle Up
- **D-10:** After selecting a group in picker: share sheet opens immediately with that group's invite code (one tap flow)

### Edge Cases
- **D-11:** 0 groups + Invite Friend/Add Expense/Settle Up: show SnackBar "Create a group first to invite friends" (or similar per action). Apply consistently to all 3 group-dependent actions.
- **D-12:** 0 groups + Activity: navigate to cross-group activity screen anyway, let the screen show its own EmptyStateView

### Claude's Discretion
- Route path for the new cross-group activity screen (e.g., `/activity` at top level)
- Internal structure of the cross-group activity screen widget
- Exact SnackBar message wording for each 0-groups action
- Store link URL format (Play Store vs universal link)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Quick Action Implementation
- `lib/features/home/widgets/quick_action_tray.dart` — QuickActionTray widget with 4 action callbacks
- `lib/features/home/screens/home_screen.dart` — Wires callbacks; contains `_showGroupPicker`, `_scrollToActivity`, and the activity section

### Share/Invite Code Pattern
- `lib/features/groups/screens/create_group_screen.dart` — Existing `Share.share()` usage for invite codes
- `lib/features/groups/screens/group_detail_screen.dart` — Existing `Share.share()` usage for invite codes
- `lib/features/groups/widgets/invite_code_display.dart` — InviteCodeDisplay widget (not used directly but reference for code formatting)

### Activity Screens
- `lib/features/groups/screens/group_activity_screen.dart` — GroupActivityScreen (per-group, paginated) — visual pattern to match
- `lib/features/activity/screens/activity_feed_screen.dart` — Event-level ActivityFeedScreen (different scope but similar structure)
- `lib/features/home/providers/dashboard_providers.dart` — `crossGroupActivityProvider` — data source for cross-group activity

### Routing
- `lib/core/router/app_router.dart` — All route definitions; new cross-group activity route goes here

### Group Data
- `lib/features/groups/providers/group_provider.dart` — `userGroupsProvider`, group model with `inviteCode` field
- `lib/features/groups/models/group_model.dart` — Group model with `inviteCode` property

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `Share.share()` from `share_plus` package — already used in create_group_screen and group_detail_screen for invite code sharing
- `_showGroupPicker()` in home_screen.dart — bottom sheet group picker, can be generalized for Invite Friend
- `crossGroupActivityProvider` in dashboard_providers.dart — aggregates activity from all user groups
- `GroupActivityScreen` — visual template for the new cross-group screen (header + paginated list + skeleton + empty state)
- `GroupActivityTile` widget — renders individual activity entries
- `EmptyStateView` — consistent empty state with optional CTA

### Established Patterns
- Group-dependent actions use `ref.read(userGroupsProvider).valueOrNull` to check group count
- Single group bypasses picker and navigates directly
- Bottom sheet picker uses `showModalBottomSheet` with `AppColorTokens.light.cardSurface` background
- All screens use `AppColorTokens.light.scaffoldBackground` background
- Activity screens use ModuleHeader or custom header with back button

### Integration Points
- `home_screen.dart` QuickActionTray callback wiring — main change point
- `app_router.dart` — new route registration for cross-group activity screen
- `lib/features/activity/` — new cross-group activity screen file goes here (or `lib/features/home/screens/`)

</code_context>

<specifics>
## Specific Ideas

- Share message must include app download link (Play Store / App Store URL)
- Group picker → share is a one-tap flow: pick group, share sheet opens immediately (no intermediate code display)
- All group-dependent quick actions (not just Invite Friend) get 0-groups SnackBar handling for consistency

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 23-quick-action-fixes*
*Context gathered: 2026-03-31*
