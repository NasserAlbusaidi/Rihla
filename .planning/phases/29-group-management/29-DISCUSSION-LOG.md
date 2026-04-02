# Phase 29: Group Management - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-02
**Phase:** 29-group-management
**Areas discussed:** Settings screen scope, Member management, Visual refresh

---

## Settings Screen Scope

| Option | Description | Selected |
|--------|-------------|----------|
| Just visual polish | Keep 3 existing settings, apply earthy design language | |
| Add module toggles | Let creator enable/disable event modules at group level | |
| Add leave/delete | Leave group (any member) + delete group (creator-only) with confirmation | |
| Polish + leave/delete | Visual refresh plus leave and delete actions, no module toggles | ✓ |

**User's choice:** Options 1, 3, 4 — visual polish + leave/delete (equivalent to option 4)
**Notes:** No module toggles this phase.

### Follow-up: Data handling on leave/remove

| Option | Description | Selected |
|--------|-------------|----------|
| Keep all data | Expenses stay, balances remain, member loses access | |
| Settle first | Block leave/remove if non-zero balance, force settle-up | ✓ |
| You decide | Claude picks cleanest approach | |

**User's choice:** Settle first
**Notes:** Clean books before departure.

---

## Member Management

| Option | Description | Selected |
|--------|-------------|----------|
| Members section in settings | List all members in GroupSettingsScreen, creator can remove | ✓ |
| Dedicated members screen | Separate screen with roles and remove action | |
| Inline on group detail | Remove action on member balance cards (long-press/swipe) | |

**User's choice:** Members section in settings
**Notes:** Simple, no separate screen.

### Follow-up: Creator distinction

| Option | Description | Selected |
|--------|-------------|----------|
| Creator badge | Small "Creator" chip/icon next to name | ✓ |
| Listed first | Creator at top, no badge | |
| Both | Listed first with subtle badge | |
| No distinction | Flat list | |

**User's choice:** Creator badge

---

## Visual Refresh

| Option | Description | Selected |
|--------|-------------|----------|
| Full earthy treatment | ModuleHeader, card sections, haptics, skeleton, inline error | |
| Light polish | Keep ListView, swap to design tokens, add haptics | |
| Match settings screen | Follow Phase 26 ProfileScreen pattern for consistency | ✓ |

**User's choice:** Match Phase 26 ProfileScreen pattern
**Notes:** Grouped sections, uppercase headers, card containers with cardSurface + raised shadow + borderRadius 24, stagger fadeIn+slideY, 24px horizontal padding.

---

## Claude's Discretion

- Icon choices for section headers and member list items
- Member list layout (ListTile vs custom Row)
- Confirmation dialog styling (AlertDialog vs BottomSheet)
- Animation delay values
- Settle-up blocking message presentation

## Deferred Ideas

- Module toggles for group-level event module control
- Share invite via sheet / deep links / QR codes
