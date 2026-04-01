# Phase 26: Settings & Support - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-01
**Phase:** 26-settings-support
**Areas discussed:** Section layout & grouping, Notification toggle UX, Support & about styling

---

## Section Layout & Grouping

| Option | Description | Selected |
|--------|-------------|----------|
| Grouped list tiles | Sections with uppercase headers matching existing pattern. Each item is a list tile with 36px icon container. | ✓ |
| Cards per section | Each section gets its own cardSurface card with items inside. More visual separation but heavier. | |
| Flat list | All items in one continuous list with dividers. Minimal visual hierarchy. | |

**User's choice:** Grouped list tiles (Recommended)
**Notes:** Matches the established pattern in the codebase. Three sections: NOTIFICATIONS, ABOUT, SUPPORT.

---

## Notification Toggle UX

### First-time enable behavior

| Option | Description | Selected |
|--------|-------------|----------|
| Toggle triggers OS prompt | Flipping the switch calls NotificationService.initialize() which shows the OS permission dialog. | ✓ |
| Explanation first, then prompt | Show a bottom sheet explaining what notifications do before requesting OS permission. | |
| You decide | Claude picks the best approach. | |

**User's choice:** Toggle triggers OS prompt (Recommended)
**Notes:** Direct OS prompt on toggle — no intermediate explanation.

### Permission denied state

| Option | Description | Selected |
|--------|-------------|----------|
| Show 'Open Settings' hint | Toggle stays OFF and disabled. Subtitle says 'Enable in device Settings' — tapping opens app settings. | ✓ |
| Just show disabled toggle | Toggle is OFF and non-interactive. No guidance on how to re-enable. | |
| You decide | Claude picks based on platform best practices. | |

**User's choice:** Show 'Open Settings' hint (Recommended)
**Notes:** Helpful guidance for re-enabling after OS denial.

---

## Support & About Styling

### Feedback link target

| Option | Description | Selected |
|--------|-------------|----------|
| Email (mailto:) | Opens the user's email app with pre-filled to address and subject line. | ✓ |
| Google Form | Opens a Google Form URL in the browser. | |
| You decide | Claude picks the simplest approach. | |

**User's choice:** Email (mailto:) (Recommended)
**Notes:** Simplest option for solo dev project. No form infrastructure needed.

### Buy me a coffee prominence

| Option | Description | Selected |
|--------|-------------|----------|
| Standard list tile | Same visual weight as other items — just another row in SUPPORT section. Tapping shows SnackBar 'Coming soon'. | ✓ |
| Highlighted card | Accent-colored card that stands out from regular tiles. | |
| You decide | Claude decides based on design language. | |

**User's choice:** Standard list tile (Recommended)
**Notes:** Deliberately understated. Placeholder only — real payment is a separate milestone.

---

## Claude's Discretion

- Specific icon choices (Iconsax variants) for each tile
- Entrance animation delays for new sections
- Feedback email address and subject line text
- SnackBar styling for "Coming soon" message
- openAppSettings() implementation approach
- Exact spacing between sections

## Deferred Ideas

None — discussion stayed within phase scope
