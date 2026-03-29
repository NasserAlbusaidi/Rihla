# Deferred Items — Phase 17

## Pre-existing Test Failures (Out of Scope)

### gear_screen_mutations_test.dart failures (8 tests)

**Discovered during:** Phase 17-01 skeleton plan execution and confirmed by 17-02 investigation
**Root cause:** Commit `0e49c5b` (17-01 agent: "refactor SkeletonLoader with 6 named content-aware factories") introduced a RenderFlex overflow in gear screen tests.

**Evidence from 17-02 bisect:**
- Reverting `skeleton_loader.dart` to `e0ea2c7` state makes all 8 gear tests pass
- 17-02 animation/migration changes do NOT cause these failures
- The new named factory implementations in SkeletonLoader produce taller skeleton widgets that overflow the test viewport by 90px

**Affected tests (8 in gear_screen_mutations_test.dart):**
- `GearScreen — addItem calls addGearItem with correct itemName, groupId, eventId`
- `GearScreen — addItem does NOT call addGearItem when text field is empty`
- `GearScreen — deleteItem calls deleteGearItem after confirming delete dialog`
- `GearScreen — togglePacked calls togglePacked with isPacked=true when tapping unclaimed item checkbox`
- `GearScreen — priority calls updateGearItem with isHighPriority=true when toggling priority`
- `GearScreen — claim calls updateGearItem with assignedTo=currentUserUid when claiming`
- `GearScreen — unclaim calls unclaimGearItem with correct gearItemId when unclaiming`
- `GearScreen — error handling shows snackbar error when addGearItem throws`

**Fix required:** The 17-01 skeleton refactor's `SkeletonLoader.cardList()` (which delegates to `generic`) produces overflow in the gear screen test viewport. Fix by either:
1. Adding `SizedBox` constraints in the test setup for gear screen, or
2. Making `SkeletonLoader.generic` / delegating factories produce a bounded height
