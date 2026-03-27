# Phase 11: Gear Write Mutations - Context

**Gathered:** 2026-03-28
**Status:** Ready for planning

<domain>
## Phase Boundary

Wire all 6 `debugPrint` stubs in `gear_screen.dart` to call `GearService` methods (Firestore). The mutations are: add item, delete item, toggle packed, toggle priority, claim, and unclaim. GearService already has all required write methods. No new UI, no new features — just connecting existing stubs to existing service methods.

</domain>

<decisions>
## Implementation Decisions

### Error Handling UX
- **D-01:** Snackbar on write failure. Brief toast at bottom: "Couldn't add item — try again". Non-blocking, auto-dismiss.
- **D-02:** Inform-only snackbar — no retry button. User re-taps the action themselves.
- **D-03:** No loading indicator on any write operation. Fire-and-forget feel.
- **D-04:** Add button disabled briefly while write is in flight (use `gearLoadingProvider`) to prevent duplicate items from rapid tapping. No visual spinner.

### Optimistic Updates
- **D-05:** No optimistic updates. Let Firestore snapshot listener handle all UI updates. Writes land in ~100-300ms. Simpler, consistent with how the screen already reads data.
- **D-06:** Text field clears immediately on add-item tap (current behavior preserved). If write fails, snackbar informs.
- **D-07:** Offline writes allowed — Firestore queues them automatically. Snapshot listener fires locally. Matches MIG-03 decision.

### Haptic Feedback
- **D-08:** Add light success haptic on addItem completion. Existing haptics on tap remain unchanged for other actions.

### Claim/Unclaim Identity
- **D-09:** Store Firebase UID (`currentUser.uid`) in `assignedTo` field when claiming.
- **D-10:** Only the claimant can unclaim their own items. No cross-user unclaim.
- **D-11:** Unclaim sets `assignedTo` to `null` (not empty string). Matches Firestore convention.

### Sequence ID
- **D-12:** New items get `sequenceId = max(existing sequenceIds) + 1`. Computed client-side from the current items list.
- **D-13:** GearScreen passes the computed sequenceId to `GearService.addGearItem()`.

### Delete Confirmation
- **D-14:** Keep existing AlertDialog confirmation. Wire it to `GearService.deleteGearItem()` on confirm. No swipe-to-delete.

### Activity Logging
- **D-15:** No activity logging in this phase. Deferred to a dedicated cross-module phase.

### Claude's Discretion
- Exact snackbar styling and duration
- How to structure try/catch in screen methods
- Whether to extract a helper for eventRef construction
- Test structure and organization

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Gear Feature
- `lib/features/gear/screens/gear_screen.dart` — Contains all 6 debugPrint stubs to replace
- `lib/features/gear/services/gear_service.dart` — Has all write methods: addGearItem, togglePacked, updateGearItem, deleteGearItem
- `lib/features/gear/providers/gear_provider.dart` — Exposes gearServiceProvider, eventGearItemsProvider, gearLoadingProvider
- `lib/features/gear/models/gear_item_model.dart` — GearItem model with status enum

### Architecture Decisions
- `.planning/phases/04-firestore-repository-layer/04-CONTEXT.md` — D-05 (per-feature services), D-07 (service names), D-10 (subcollection paths), D-13 (snapshot listeners)

### Milestone Audit
- `.planning/v1.0-MILESTONE-AUDIT.md` — Integration #1 (gear_screen → GearService) gap definition

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `GearService` — All 4 write methods ready (addGearItem, togglePacked, updateGearItem, deleteGearItem)
- `gearServiceProvider` — Already exposes GearService instance
- `gearLoadingProvider` / `gearErrorProvider` — State providers for loading/error tracking
- `HapticService` — Already imported in gear_screen.dart with selection/warning methods
- `eventGearItemsProvider` — Already wired for reads, snapshot listener will update UI after writes

### Established Patterns
- GearScreen is a `ConsumerStatefulWidget` with access to `ref` for providers
- `widget.event.groupId` and `widget.event.id` provide groupId and eventId
- `eventRef` record already constructed at line 45: `(groupId: widget.event.groupId, eventId: widget.event.id)`
- Other services (ExpenseService) follow same pattern: try/catch with rethrow on FirebaseException

### Integration Points
- 6 debugPrint stubs at lines 578, 582, 586, 623, 632, 642
- `_handleMenuAction` switch cases for priority/claim/unclaim
- `_confirmDelete` method for delete
- `_addItem` method for add
- `_togglePacked` method for toggle packed
- `currentUserProvider` already watched at line 47 — provides UID for claim operations

</code_context>

<specifics>
## Specific Ideas

No specific requirements — open to standard approaches

</specifics>

<deferred>
## Deferred Ideas

- Activity logging for gear mutations — should be consistent across all modules, defer to dedicated cross-module phase
- Swipe-to-delete gesture — could add in a future UX polish phase
- Drag-to-reorder gear items — would need sequenceId updates, separate phase

</deferred>

---

*Phase: 11-gear-write-mutations*
*Context gathered: 2026-03-28*
