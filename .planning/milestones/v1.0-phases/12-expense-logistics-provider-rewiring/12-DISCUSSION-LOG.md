# Phase 12: Expense & Logistics Provider Rewiring - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-03-28
**Phase:** 12-expense-logistics-provider-rewiring
**Areas discussed:** Currency fallback chain, Logistics stub scope, Error handling consistency, Provider cleanup, Capacity passthrough

---

## Currency Fallback Chain

| Option | Description | Selected |
|--------|-------------|----------|
| Event.currency only | Simple replacement: swap userTripsProvider lookup for widget.event.currency. Group currency adds complexity for no clear gain. | ✓ |
| Event → Group fallback | Try event.currency first, then fetch group.currency. Adds a provider dependency. | |
| You decide | Claude picks simplest approach. | |

**User's choice:** Event.currency only (Recommended)
**Notes:** None

---

## Logistics Stub Scope (Round 1)

| Option | Description | Selected |
|--------|-------------|----------|
| Wire both (add+remove) | addMember and removeMember are in the same callbacks, same SubGroupService. Half-working screen otherwise. | ✓ |
| removeMember only | Stick to exactly what success criteria say. | |
| Wire all logistics stubs | Fix every remaining debugPrint stub in logistics_screen.dart. | |

**User's choice:** Wire both (Recommended)
**Notes:** Initial selection before full stub inventory was taken.

---

## Error Handling Consistency

| Option | Description | Selected |
|--------|-------------|----------|
| Same pattern (Phase 11) | Snackbar on failure, no retry button, auto-dismiss. Consistent across gear and logistics. | ✓ |
| Silent failures | debugPrint only. Less intrusive but user won't know why action didn't work. | |
| You decide | Claude picks per operation. | |

**User's choice:** Same pattern (Recommended)
**Notes:** None

---

## Logistics Stub Scope (Round 2 — expanded)

After discovering 6 total stubs (not 2), re-asked:

| Option | Description | Selected |
|--------|-------------|----------|
| All 6 stubs | Wire all. 5 have existing service methods. updateSubGroup needs a new method. No debugPrint stubs left. | ✓ |
| 5 stubs (skip rename) | Wire 5 that have service methods. Keep phase purely mechanical. | |
| Just add+remove members | Only addMember (2 locations) and removeMember. | |

**User's choice:** All 6 stubs (Recommended)
**Notes:** None

---

## Edit Expense Screen

| Option | Description | Selected |
|--------|-------------|----------|
| Fix both screens | Both add_expense_screen.dart and edit_expense_sheet.dart have identical bugs. | ✓ |
| Add screen only | Only fix add_expense_screen.dart. | |

**User's choice:** Fix both screens (Recommended)
**Notes:** None

---

## Provider Cleanup (userTripsProvider)

| Option | Description | Selected |
|--------|-------------|----------|
| Delete in this phase | Once all consumers rewired, it's dead code. Remove immediately. | ✓ |
| Defer to Phase 13 | Phase 13 is explicitly about removing orphaned providers. | |

**User's choice:** Delete in this phase (Recommended)
**Notes:** None

---

## Capacity Passthrough

| Option | Description | Selected |
|--------|-------------|----------|
| Pass it through | SubGroupService already accepts capacity param. Dialog already has field. Stop discarding. | ✓ |
| Ignore for now | Keep capacity hardcoded at default 4. | |

**User's choice:** Pass it through (Recommended)
**Notes:** None

---

## Claude's Discretion

- Exact snackbar wording and duration for logistics errors
- try/catch structure in logistics screen methods
- Whether to extract eventRef helper in logistics screen
- Test structure and organization
- SubGroupService.updateSubGroup() implementation details

## Deferred Ideas

None — discussion stayed within phase scope
