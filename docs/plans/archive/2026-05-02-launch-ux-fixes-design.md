# Rihla v1 Launch UX Fixes

**Date:** 2026-05-02  
**Status:** Approved  
**Scope:** 5 targeted frontend fixes to close UX gaps before launch

---

## Product Summary

Rihla is Splitwise organized by groups and events. Friends create a persistent group, spin up events (camping, trip, night out, etc.), add expenses inside those events, and settle up at the group level across all events.

**Market:** Oman/GCC first.  
**Auth:** Anonymous, frictionless. No login — session created silently on first launch.  
**Currency:** OMR.

---

## User Roles

| Action | Creator | Member |
|---|---|---|
| Create group | ✓ | — |
| Share invite code | ✓ | — |
| Create events | ✓ | — |
| Remove members | ✓ | — |
| Add expenses | ✓ | ✓ |
| Settle up | ✓ | ✓ |
| View balances | ✓ | ✓ |

---

## User Flows

### Creator
```
Home → FAB → Create Group (group name + your name)
→ invite code shown → share via system sheet
→ GroupDetail → [creator-only FAB] → EventTypePicker → CreateEvent
→ event card → LedgerScreen → add expenses / settle up
```

### Member
```
Home → FAB → Join Group (your name + 6-char code)
→ GroupDetail → event card → LedgerScreen → add expenses / settle up
```

---

## Changes

### 1. Gate event creation FAB to creator only

**File:** `lib/features/groups/screens/group_detail_screen.dart`

The FAB that navigates to `/group/:gid/create-event` is currently visible to all members. The server already rejects non-creator creation. Hide the FAB in the UI.

**Logic:**
```dart
// Show FAB only when current user is the group creator
final isCreator = currentUserId == group.createdBy;
// Conditionally render the FAB (or return null)
```

The `createdBy` field is already on the `Group` model. The current user's Firebase UID is available via `FirebaseAuth.instance.currentUser?.uid`.

---

### 2. Remove Chats tab from bottom nav

**File:** `lib/features/home/widgets/bottom_nav_shell.dart`

Remove the Chats tab entirely. Shift from 4-tab to 3-tab layout.

**Before:** Groups | Activity | Chats | Profile  
**After:** Groups | Activity | Profile

- Remove the `_PlaceholderTab` entry for Chats from the `tabs` list
- Remove the `BottomNavigationBarItem` for Chats from the nav bar items
- No index remapping needed — Profile moves from index 3 to index 2

---

### 3. Wire Activity tab to CrossGroupActivityScreen

**File:** `lib/features/home/widgets/bottom_nav_shell.dart`

Tab index 1 (Activity) currently shows `_PlaceholderTab`. Replace with `CrossGroupActivityScreen`.

```dart
// Tab 1: Activity
const CrossGroupActivityScreen(),
```

Import: `lib/features/home/screens/cross_group_activity_screen.dart`

---

### 4. Event card navigates directly to Ledger

**File:** `lib/features/groups/screens/group_detail_screen.dart`

Event card taps currently navigate to `/group/:gid/event/:eid` (EventCommandCenter). After Phase 39, EventCommandCenter only has one module (Ledger), making it a pointless passthrough.

Change the tap destination:

```dart
// Before
context.push('/group/$groupId/event/$eventId');

// After
context.push('/group/$groupId/event/$eventId/ledger');
```

EventCommandCenter remains in the router (not deleted) in case it's needed later, but users never land on it from normal navigation.

---

### 5. Add event settings + activity access from Ledger header

**File:** `lib/features/ledger/screens/ledger_screen.dart`

Since EventCommandCenter is bypassed, users need a path to event settings and event activity. Add an overflow menu (three-dot icon) to the ModuleHeader in LedgerScreen.

**Menu items:**
- "Event activity" → `context.push('/group/$groupId/event/$eventId/activity')`
- "Event settings" → `context.push('/group/$groupId/event/$eventId/settings')`

The `ModuleHeader` widget accepts an `actions` parameter. Pass the `PopupMenuButton` there.

---

## Constraints

- No new screens — all changes are within existing files
- No router changes — existing routes stay as-is
- No model or service changes — pure UI layer
- EventCommandCenter is not deleted, just unreachable from normal flow

---

## Files Changed

| File | Change |
|---|---|
| `lib/features/groups/screens/group_detail_screen.dart` | Gate FAB to creator; change event tap destination |
| `lib/features/home/widgets/bottom_nav_shell.dart` | Remove Chats tab; wire Activity tab |
| `lib/features/ledger/screens/ledger_screen.dart` | Add overflow menu for event settings + activity |
