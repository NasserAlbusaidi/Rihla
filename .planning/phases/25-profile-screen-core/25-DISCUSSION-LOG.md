# Phase 25: Profile Screen Core - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-01
**Phase:** 25-profile-screen-core
**Areas discussed:** Screen architecture, Entry point & navigation, Stats presentation, Name propagation UX

---

## Screen Architecture

### Screen relationship

| Option | Description | Selected |
|--------|-------------|----------|
| Replace SettingsScreen | Delete existing SettingsScreen. Phase 25 builds new profile screen with identity + stats. Phase 26 adds settings sections. One screen, two build phases. | ✓ |
| Keep both screens | New /profile for identity + stats only. Existing /settings stays for preferences + about. Two separate screens. | |
| Redesign SettingsScreen in-place | Keep /settings route but gut and rebuild the screen. | |

**User's choice:** Replace SettingsScreen (Recommended)
**Notes:** Route changes from /settings to /profile. Single screen built across two phases.

### Identity visual element

| Option | Description | Selected |
|--------|-------------|----------|
| Initials circle | Large 64px circle with user's initials in terracotta bg, white text. No photo upload needed. | ✓ |
| Icon only | Simple user icon in a circle, no initials. | |
| No avatar | Just the name as text with an edit button. | |

**User's choice:** Initials circle (Recommended)
**Notes:** Terracotta background, white text. Consistent with anonymous auth (no persistent profile image).

---

## Entry Point & Navigation

### Home screen access

| Option | Description | Selected |
|--------|-------------|----------|
| Initials avatar in header | Small 32px initials circle in top-right of home dashboard header. Tapping opens /profile. | ✓ |
| Gear icon in header | Settings gear icon in top-right corner. | |
| Quick action button | Add a 5th quick action 'Profile' in the quick actions tray. | |

**User's choice:** Initials avatar in header (Recommended)
**Notes:** Ties home and profile screens together visually with matching initials circles.

### Transition

| Option | Description | Selected |
|--------|-------------|----------|
| Slide right | Standard slide-right transition matching all other module screens. | ✓ |
| Fade through | M3 FadeThrough transition for top-level navigation changes. | |
| You decide | Claude picks based on existing patterns. | |

**User's choice:** Slide right (Recommended)
**Notes:** Consistent with existing GoRouter CustomTransitionPage pattern.

---

## Stats Presentation

### Layout

| Option | Description | Selected |
|--------|-------------|----------|
| Stat cards row | 3 compact cards in a horizontal row. Big number + label underneath. | ✓ |
| Single stats card | One card with 3 rows in list-tile style. | |
| Hero numbers | Large numbers directly on scaffold background, no cards. | |

**User's choice:** Stat cards row (Recommended)
**Notes:** cardSurface bg, earthy accent numbers. Clean and scannable.

### Spending format

| Option | Description | Selected |
|--------|-------------|----------|
| "OMR 45.250" with currency | Full currency prefix on the number. | ✓ |
| "45.250" + "Spent (OMR)" label | Number clean, currency noted in label below. | |
| You decide | Claude picks based on available space. | |

**User's choice:** "OMR 45.250" with currency
**Notes:** Currency prefix on the stat card number, label says "Spent".

---

## Name Propagation UX

### Save experience

| Option | Description | Selected |
|--------|-------------|----------|
| Inline loading + success | Save button shows spinner while Firestore batch writes complete, then success indicator. Offline: save locally + queue. | ✓ |
| Confirmation dialog first | "This will update your name in N groups. Continue?" before writing. | |
| Silent save | No loading indicator, fire-and-forget. | |

**User's choice:** Inline loading + success (Recommended)
**Notes:** Spinner → checkmark → close. Offline saves to SharedPrefs + sync queue, no error shown.

### Edit interaction

| Option | Description | Selected |
|--------|-------------|----------|
| Bottom sheet | Slide-up bottom sheet with text field + Save button. Matches earthy design language. | ✓ |
| Dialog (keep current) | AlertDialog like current SettingsScreen pattern. | |
| Inline edit | Tap name text directly, becomes editable field in-place. | |

**User's choice:** Bottom sheet
**Notes:** More intentional feel, better match for earthy design language than plain AlertDialog.

---

## Claude's Discretion

- Bottom sheet styling details (spacing, button style, validation)
- Initials extraction logic
- Stat card internal spacing, font sizes, accent colors
- Loading/skeleton state for stats
- Total spending computation approach
- Screen layout details, section spacing, scroll behavior
- Empty name placeholder behavior

## Deferred Ideas

None — discussion stayed within phase scope
