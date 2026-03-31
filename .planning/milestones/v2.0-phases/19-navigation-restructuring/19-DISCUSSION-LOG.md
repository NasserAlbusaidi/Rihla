# Phase 19: Navigation Restructuring - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-03-30
**Phase:** 19-navigation-restructuring
**Areas discussed:** Route URL structure, Transition animations, Bottom nav tab wiring, CommandCenter fate, Create/Join event flows, Add Expense / Settle Up entry, Parameter passing strategy, AppPageRoute cleanup, Memory detail navigation, Error/404 routes, CLAUDE.md routing diagram, Test migration strategy, Screen constructor refactoring, Activity screen from CommandCenter

---

## Route URL Structure

| Option | Description | Selected |
|--------|-------------|----------|
| Fully nested | /group/:gid/event/:eid/ledger — mirrors data hierarchy, self-describing URLs | ✓ |
| Semi-nested | Module URLs lose group context (/event/:eid/ledger) | |
| Flat with params | All top-level routes with query params | |

**User's choice:** Fully nested
**Notes:** None

---

## Transition Animations

| Option | Description | Selected |
|--------|-------------|----------|
| Preserve slide-right for all | Same SlideTransition as AppPageRoute via CustomTransitionPage | ✓ |
| Direction-aware transitions | Slide-right forward, slide-up modals | |
| Defer to Phase 22 | Default MaterialPage transitions now, M3 motion later | |

**User's choice:** Preserve slide-right for all
**Notes:** None

---

## Bottom Nav Tab Wiring

| Option | Description | Selected |
|--------|-------------|----------|
| Keep all placeholders | Phase 19 is routing only, tabs stay "Coming soon" | ✓ |
| Wire Settings to Profile tab | Profile tab shows SettingsScreen | |
| Wire Activity + Profile | Both Activity and Profile get real screens | |

**User's choice:** Keep all placeholders
**Notes:** None

---

## CommandCenter Fate

| Option | Description | Selected |
|--------|-------------|----------|
| Become a GoRouter subroute | /group/:gid/event/:eid with module subroutes | ✓ |
| Keep imperative inside GoRouter | Navigator.push stays for CommandCenter and modules | |
| Hybrid — GoRouter route, imperative modules | CommandCenter is a route, modules stay push | |

**User's choice:** Become a GoRouter subroute
**Notes:** None

---

## Create/Join Event Flows

| Option | Description | Selected |
|--------|-------------|----------|
| GoRouter routes | /group/:gid/create-event and /create-event/:type | ✓ |
| Keep as modal flow | Transient flow stays imperative | |
| Hybrid — type picker modal, form route | Picker is bottom sheet, form is route | |

**User's choice:** GoRouter routes
**Notes:** None

---

## Form Screens (Add Expense / Settle Up)

| Option | Description | Selected |
|--------|-------------|----------|
| GoRouter routes | /ledger/add, /ledger/edit/:expId, /settle-up | ✓ |
| Keep as bottom sheets / modals | Transient forms stay imperative | |
| Mixed — settle-up route, forms modal | Only settle-up gets a route | |

**User's choice:** GoRouter routes
**Notes:** None

---

## Parameter Passing Strategy

| Option | Description | Selected |
|--------|-------------|----------|
| Path params + provider lookup | Screens take string IDs, fetch data via providers | ✓ |
| GoRouter extra for objects | Pass full objects via state.extra | |
| Mix — IDs in path, extra as cache hint | IDs required, extra as optimization | |

**User's choice:** Path params + provider lookup
**Notes:** None

---

## AppPageRoute Cleanup

| Option | Description | Selected |
|--------|-------------|----------|
| Delete in Phase 19 | Remove dead code immediately after migration | ✓ |
| Defer to Phase 22 | Clean up alongside legacy AppColors | |
| Keep but deprecate | @Deprecated annotation, delete later | |

**User's choice:** Delete in Phase 19
**Notes:** None

---

## Memory Detail Navigation

| Option | Description | Selected |
|--------|-------------|----------|
| GoRouter route | /group/:gid/event/:eid/memories/:memId | ✓ |
| Keep as overlay/dialog | Ephemeral gallery UI | |
| Route for sharing, overlay for browsing | Dual behavior based on entry point | |

**User's choice:** GoRouter route
**Notes:** None

---

## Error/404 Routes

| Option | Description | Selected |
|--------|-------------|----------|
| In-screen error state | Screen renders but shows "not found" with Go Home button | ✓ |
| Redirect to home | GoRouter redirect on missing content | |
| Custom 404 screen | Dedicated NotFoundScreen | |

**User's choice:** In-screen error state
**Notes:** Same pattern as Phase 18 error state

---

## CLAUDE.md Routing Diagram

| Option | Description | Selected |
|--------|-------------|----------|
| Text tree | Plain text route hierarchy | ✓ |
| Both text tree + mermaid | Text + visual flowchart | |
| Table format | Route/Screen/Params table | |

**User's choice:** Text tree
**Notes:** Matches existing CLAUDE.md style

---

## Test Migration Strategy

| Option | Description | Selected |
|--------|-------------|----------|
| Real GoRouter with test routes | testRouter helper with all routes registered | ✓ |
| MockGoRouter from go_router | Built-in mock, lighter but doesn't test real paths | |
| Mixed — mock for units, real for integration | Different strategies per test type | |

**User's choice:** Real GoRouter with test routes
**Notes:** None

---

## Screen Constructor Refactoring

| Option | Description | Selected |
|--------|-------------|----------|
| Big bang in Phase 19 | All constructors change from objects to string IDs at once | ✓ |
| Incremental — one file at a time | Migrate screens one by one | |
| Dual constructors temporarily | Add .fromIds alongside existing, remove old later | |

**User's choice:** Big bang in Phase 19
**Notes:** None

---

## Activity Screen from CommandCenter

| Option | Description | Selected |
|--------|-------------|----------|
| Yes — module route | /group/:gid/event/:eid/activity as sibling of /ledger | ✓ |
| No — stays inline in CommandCenter | Activity is a tab/section, not a route | |

**User's choice:** Yes — module route
**Notes:** Consistent treatment with all other modules

---

## Claude's Discretion

- Route transition timing (duration, curve fine-tuning)
- GoRouter redirect logic extensions
- Order of migration (which files first)

## Deferred Ideas

None — discussion stayed within phase scope.
