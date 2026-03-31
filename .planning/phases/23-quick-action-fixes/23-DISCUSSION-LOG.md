# Phase 23: Quick Action Fixes - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-03-31
**Phase:** 23-quick-action-fixes
**Areas discussed:** Invite Friend flow, Activity destination, Group picker behavior, Edge cases

---

## Invite Friend Flow

### Share message content

| Option | Description | Selected |
|--------|-------------|----------|
| Simple text | "Join my group [name] on Rihla! Code: ABC123" — uses Share.share() like existing pattern | |
| Text with app link | "Join [group name] on Rihla! Code: ABC123 — Download: [store link]" — includes Play Store/App Store URL | ✓ |
| Code only | Just the invite code itself, no message wrapping | |

**User's choice:** Text with app link
**Notes:** None

### Single-group behavior

| Option | Description | Selected |
|--------|-------------|----------|
| Skip picker, share directly | Matches how Add Expense and Settle Up already behave — if 1 group, navigate directly | ✓ |
| Always show picker | Consistent UI regardless of group count, but adds an unnecessary tap | |

**User's choice:** Skip picker, share directly
**Notes:** None

### Post-share feedback

| Option | Description | Selected |
|--------|-------------|----------|
| No feedback | Share sheet dismisses silently — OS share sheet already confirms | ✓ |
| SnackBar confirmation | Show "Invite sent!" snackbar after share completes | |
| Haptic only | Light haptic on share, no visual feedback | |

**User's choice:** No feedback
**Notes:** None

---

## Activity Destination

### What Activity button should do

| Option | Description | Selected |
|--------|-------------|----------|
| New cross-group screen | Create a new screen that aggregates activity from all groups — shows recent actions across all groups | ✓ |
| Show group picker, then group activity | Reuse existing GroupActivityScreen — user picks a group first | |
| Keep scroll behavior but fix it | Fix the scroll and make the home page activity section more prominent | |

**User's choice:** New cross-group screen
**Notes:** None

### Data source

| Option | Description | Selected |
|--------|-------------|----------|
| Reuse dashboard provider | crossGroupActivityProvider already exists — route to a full-screen version | ✓ |
| New dedicated provider | Build a separate provider with pagination for all groups | |

**User's choice:** Reuse dashboard provider
**Notes:** None

### Visual style

| Option | Description | Selected |
|--------|-------------|----------|
| Match GroupActivityScreen | Full-screen with header, paginated list, GroupActivityTile tiles — add group name label | ✓ |
| Expanded home section | Same ActivityRow cards as the home page, but full-screen | |

**User's choice:** Match GroupActivityScreen
**Notes:** None

---

## Group Picker Behavior

### Picker style

| Option | Description | Selected |
|--------|-------------|----------|
| Same bottom sheet | Reuse existing _showGroupPicker bottom sheet pattern — consistent with Add Expense/Settle Up | ✓ |
| Dialog instead | Show a centered AlertDialog with group list | |
| Inline dropdown | Show a dropdown anchored to the Invite Friend button | |

**User's choice:** Same bottom sheet
**Notes:** None

### Post-pick action

| Option | Description | Selected |
|--------|-------------|----------|
| Share immediately | Pick group → share sheet opens with that group's invite code. One tap, done. | ✓ |
| Show code, then share | Pick group → show InviteCodeDisplay with copy/share buttons | |

**User's choice:** Share immediately
**Notes:** None

---

## Edge Cases

### 0 groups + Invite Friend

| Option | Description | Selected |
|--------|-------------|----------|
| Show SnackBar hint | "Create a group first to invite friends" — no navigation, just a message | ✓ |
| Navigate to Create Group | Automatically open /create-group | |
| Disable button | Gray out the Invite Friend icon when no groups exist | |

**User's choice:** Show SnackBar hint
**Notes:** None

### Apply to all group-dependent actions

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, add SnackBar to all | All 3 group-dependent actions show "Create a group first" if no groups exist | ✓ |
| No, only fix Invite Friend | Keep Add Expense and Settle Up as-is | |

**User's choice:** Yes, add SnackBar to all
**Notes:** None

### 0 groups + Activity

| Option | Description | Selected |
|--------|-------------|----------|
| Navigate anyway, show empty state | Open the cross-group activity screen, which shows an EmptyStateView | ✓ |
| Show SnackBar | Same "Create a group first" SnackBar | |
| No special handling | Let it navigate naturally | |

**User's choice:** Navigate anyway, show empty state
**Notes:** None

---

## Claude's Discretion

- Route path for the new cross-group activity screen
- Internal widget structure of the cross-group activity screen
- Exact SnackBar message wording for each 0-groups action
- Store link URL format

## Deferred Ideas

None — discussion stayed within phase scope
