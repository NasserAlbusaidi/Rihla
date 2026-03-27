# Phase 12: Expense & Logistics Provider Rewiring - Context

**Gathered:** 2026-03-28
**Status:** Ready for planning

<domain>
## Phase Boundary

Replace broken `userTripsProvider` (SQLite/Trip-based) dependencies with Firestore Event-based equivalents. Three fix areas: (1) payer-override visibility in expense forms, (2) currency derivation in expense forms, (3) all logistics screen write stubs. After rewiring, delete the now-dead `userTripsProvider`. Add `updateSubGroup` method to SubGroupService. All fixes must have corresponding tests.

</domain>

<decisions>
## Implementation Decisions

### Currency Source
- **D-01:** Use `Event.currency` directly — no group fallback. Event already has a `currency` field (defaults to `'OMR'`). Replace `userTripsProvider` lookup with `widget.event.currency` (or equivalent).
- **D-02:** Fix both `add_expense_screen.dart` and `edit_expense_sheet.dart` — both have identical `_tripCurrency` bugs reading from dead `userTripsProvider`.

### Payer Override (isLeader)
- **D-03:** Derive `isLeader` from `event.createdBy == currentUser?.uid` — replaces `trip?.leaderId == currentUser?.uid` via `userTripsProvider`. Fix in both `split_scope_selector.dart` (`_PayerSelector`) and `edit_expense_sheet.dart`.

### Logistics Stubs — Wire All 6
- **D-04:** Wire all 6 debugPrint stubs in `logistics_screen.dart` to `SubGroupService` methods:
  1. `removeMember` (line 158) → `SubGroupService.removeMember()`
  2. `addMember` via onDrop (line 165) → `SubGroupService.addMember()`
  3. `addMember` via member picker (line 320) → `SubGroupService.addMember()`
  4. `deleteSubGroup` (line 361) → `SubGroupService.deleteSubGroup()`
  5. `updateSubGroup` / rename (line 482) → new `SubGroupService.updateSubGroup()` method (must be created)
  6. `createSubGroup` (line 489) → `SubGroupService.createSubGroup()`
- **D-05:** Pass capacity value from create dialog to `SubGroupService.createSubGroup()` — stop discarding the captured value (`final _ = ...`).

### Error Handling
- **D-06:** Follow Phase 11 gear pattern: snackbar on write failure, no retry button, auto-dismiss. Apply to all logistics write operations (add/remove member, create/update/delete subgroup).
- **D-07:** Payer/currency fixes are read-path changes — no error handling needed there.

### Provider Cleanup
- **D-08:** Delete `userTripsProvider` in this phase after all consumers are rewired. Dead code should not survive to Phase 13.

### Claude's Discretion
- Exact snackbar wording and duration for logistics errors
- How to structure try/catch in logistics screen methods
- Whether to extract a helper for eventRef construction in logistics screen
- Test structure and organization
- Implementation of `SubGroupService.updateSubGroup()` — follow existing service method patterns

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Expense Screens (Payer + Currency)
- `lib/features/ledger/screens/add_expense_screen.dart` — `_tripCurrency` getter (lines 63-75) and `_selectedPayerId` usage
- `lib/features/ledger/screens/edit_expense_sheet.dart` — `_tripCurrency` getter (lines 51-58) and isLeader check (line 361)
- `lib/features/ledger/widgets/split_scope_selector.dart` — `_PayerSelector` widget (lines 365-410+), isLeader derivation (line 394)
- `lib/features/ledger/providers/expense_provider.dart` — `userTripsProvider` definition (to be deleted)

### Logistics Screen
- `lib/features/logistics/screens/logistics_screen.dart` — All 6 debugPrint stubs at lines 158, 165, 320, 361, 482, 489
- `lib/features/logistics/services/sub_group_service.dart` — Has 4 methods (createSubGroup, addMember, removeMember, deleteSubGroup); needs new updateSubGroup

### Models
- `lib/features/events/models/event_model.dart` — Event model with `createdBy` (line 159) and `currency` (line 165) fields
- `lib/features/trip/models/trip_model.dart` — Trip model (legacy, for understanding what's being replaced)

### Architecture Decisions
- `.planning/phases/04-firestore-repository-layer/04-CONTEXT.md` — D-05 (per-feature services), D-07 (service names), D-10 (subcollection paths)
- `.planning/phases/11-gear-write-mutations/11-CONTEXT.md` — D-01/D-02 (snackbar error pattern), D-05 (no optimistic updates), D-07 (offline writes)

### Milestone Audit
- `.planning/v1.0-MILESTONE-AUDIT.md` — Integration #2 (isLeader), #3 (currency), #4 (removeMember), Flow #2 (payer-override)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `SubGroupService` — 4 of 5 needed write methods exist (createSubGroup, addMember, removeMember, deleteSubGroup); updateSubGroup must be added
- `Event.createdBy` and `Event.currency` — Already on the model, ready for direct access
- `widget.event` — Available in all target screens (logistics_screen, add_expense_screen gets event via constructor, edit_expense_sheet has event)
- `eventRef` record — Already constructed in logistics_screen at line 52: `(groupId: widget.event.groupId, eventId: widget.event.id)`
- `subGroupServiceProvider` — Already exposes SubGroupService instance
- Phase 11 snackbar pattern — Reusable error handling approach

### Established Patterns
- `_PayerSelector` receives `event` param but redundantly looks up Trip via `userTripsProvider` — event has all needed fields
- `add_expense_screen.dart` receives `eventId` via constructor, plus `event` object is passed from parent
- `edit_expense_sheet.dart` receives `expense` and watches `userTripsProvider` for trip context
- SubGroupService follows `FirestoreRepository` pattern with `eventSubcollection(groupId, eventId, collection)` helper

### Integration Points
- `_PayerSelector.build()` — Replace Trip lookup with event.createdBy check
- `_tripCurrency` getter in both expense screens — Replace with event.currency access
- 6 debugPrint callbacks in logistics_screen.dart — Each wires to a SubGroupService method
- `userTripsProvider` — Delete after all consumers removed

</code_context>

<specifics>
## Specific Ideas

No specific requirements — open to standard approaches

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 12-expense-logistics-provider-rewiring*
*Context gathered: 2026-03-28*
