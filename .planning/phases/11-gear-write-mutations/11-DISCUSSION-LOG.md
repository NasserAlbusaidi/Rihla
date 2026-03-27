# Phase 11: Gear Write Mutations - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-03-28
**Phase:** 11-gear-write-mutations
**Areas discussed:** Error handling UX, Optimistic updates, Claim/unclaim identity, Sequence ID, Delete confirmation UX, Activity logging

---

## Error Handling UX

| Option | Description | Selected |
|--------|-------------|----------|
| Snackbar | Brief toast at bottom, non-blocking, auto-dismiss | ✓ |
| Inline error on item | Red indicator on specific failed item | |
| Silent retry then snackbar | Auto-retry once, snackbar if second fails | |

**User's choice:** Snackbar
**Notes:** None

---

### Retry Button

| Option | Description | Selected |
|--------|-------------|----------|
| Inform only | No retry button, user re-taps action | ✓ |
| Retry button | Snackbar has RETRY button | |

**User's choice:** Inform only
**Notes:** None

---

### Loading Indicator

| Option | Description | Selected |
|--------|-------------|----------|
| No loading indicator | Fire-and-forget, Firestore fast enough | ✓ |
| Subtle per-item indicator | Brief opacity fade on mutated item | |
| Loading button for add only | LoadingButton for add, none for toggles | |

**User's choice:** No loading indicator
**Notes:** None

---

### Double-tap Prevention

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, disable briefly | Use gearLoadingProvider to gate add action | ✓ |
| No, allow rapid adds | Each tap creates separate item | |

**User's choice:** Yes, disable briefly
**Notes:** None

---

## Optimistic Updates

| Option | Description | Selected |
|--------|-------------|----------|
| Firestore snapshot only | Let snapshot listener handle UI updates | ✓ |
| Optimistic with rollback | Update local state immediately, roll back on fail | |
| Hybrid — toggles only | Packed checkbox instant, add/delete wait | |

**User's choice:** Firestore snapshot only
**Notes:** None

---

### Text Field Clear Timing

| Option | Description | Selected |
|--------|-------------|----------|
| Clear immediately | Clear on tap, snackbar on fail | ✓ |
| Clear after success | Wait for Firestore confirmation | |

**User's choice:** Clear immediately
**Notes:** None

---

### Offline Behavior

| Option | Description | Selected |
|--------|-------------|----------|
| Let Firestore queue it | Offline persistence queues writes, snapshot fires locally | ✓ |
| Block with offline banner | Show "You're offline" and prevent writes | |

**User's choice:** Let Firestore queue it
**Notes:** None

---

### Success Haptic

| Option | Description | Selected |
|--------|-------------|----------|
| Keep existing haptics only | No success-confirmation haptics | |
| Add success haptic on add | Light success haptic on addItem completion | ✓ |
| You decide | Claude picks | |

**User's choice:** Add success haptic on add
**Notes:** None

---

## Claim/Unclaim Identity

| Option | Description | Selected |
|--------|-------------|----------|
| Firebase UID | Store currentUser.uid | ✓ |
| Display name | Store user's display name | |
| Participant ID | Use participant record ID | |

**User's choice:** Firebase UID
**Notes:** None

---

### Cross-user Unclaim

| Option | Description | Selected |
|--------|-------------|----------|
| Own items only | Users can only unclaim items they claimed | ✓ |
| Anyone can unclaim anyone | Any group member can unclaim any item | |
| Owner + event creator | Claimant and event creator can unclaim | |

**User's choice:** Own items only
**Notes:** None

---

### Unclaim Value

| Option | Description | Selected |
|--------|-------------|----------|
| Null | Set assignedTo to null | ✓ |
| Empty string | Set assignedTo to '' | |

**User's choice:** Null
**Notes:** None

---

## Sequence ID

| Option | Description | Selected |
|--------|-------------|----------|
| Max existing + 1 | Read current items, add 1. New items at bottom | ✓ |
| Timestamp-based | Use millisecondsSinceEpoch | |
| You decide | Claude picks | |

**User's choice:** Max existing + 1
**Notes:** None

---

### Computation Location

| Option | Description | Selected |
|--------|-------------|----------|
| Client-side from list | GearScreen reads items, passes max+1 | ✓ |
| Service-side query | GearService queries Firestore for max | |

**User's choice:** Client-side from list
**Notes:** None

---

## Delete Confirmation UX

| Option | Description | Selected |
|--------|-------------|----------|
| Keep dialog only | Existing AlertDialog, wire to GearService | ✓ |
| Add swipe-to-delete too | Swipe gesture + dialog | |
| Replace dialog with swipe | Only swipe-to-delete | |

**User's choice:** Keep dialog only
**Notes:** None

---

## Activity Logging

| Option | Description | Selected |
|--------|-------------|----------|
| Not in this phase | Defer to dedicated cross-module phase | ✓ |
| Add basic logging now | Log add/delete to activity feed | |
| You decide | Claude decides based on other modules | |

**User's choice:** Not in this phase
**Notes:** Activity logging is a cross-cutting concern that should be consistent across all modules

---

## Claude's Discretion

- Exact snackbar styling and duration
- How to structure try/catch in screen methods
- Whether to extract a helper for eventRef construction
- Test structure and organization

## Deferred Ideas

- Activity logging for gear mutations — cross-module phase
- Swipe-to-delete gesture — future UX polish phase
- Drag-to-reorder gear items — separate phase
