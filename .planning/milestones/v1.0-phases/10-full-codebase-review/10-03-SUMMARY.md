---
phase: 10-full-codebase-review
plan: "03"
subsystem: groups, logistics, memories
tags: [refactor, file-size, widget-extraction]
dependency_graph:
  requires: ["10-01"]
  provides: ["group_settlement_tile", "group_settlement_summary", "subgroup_card", "unassigned_pool", "memories_photo_grid", "full_screen_photo"]
  affects: ["groups", "logistics", "memories"]
tech_stack:
  added: []
  patterns: ["widget extraction", "callback delegation", "StatelessWidget decomposition"]
key_files:
  created:
    - lib/features/groups/widgets/group_settlement_summary.dart
    - lib/features/groups/widgets/group_settlement_tile.dart
    - lib/features/logistics/widgets/subgroup_card.dart
    - lib/features/logistics/widgets/unassigned_pool.dart
    - lib/features/memories/widgets/photo_grid.dart
    - lib/features/memories/widgets/full_screen_photo.dart
  modified:
    - lib/features/groups/screens/group_settle_up_screen.dart
    - lib/features/logistics/screens/logistics_screen.dart
    - lib/features/memories/screens/memories_screen.dart
decisions:
  - "GroupSettlementTile accepts onRecord as nullable VoidCallback — no button rendered when null (avoids isYourAction/isCurrentUser logic in widget)"
  - "UnassignedPool is StatelessWidget receiving pre-computed unassigned list — screen computes unassigned from provider, avoiding nested ref in widget"
  - "SubgroupCard receives all mutation callbacks — screen retains provider access, widget delegates via callbacks"
  - "FullScreenPhoto made public (removed _ prefix) per plan spec"
metrics:
  duration: 9 min
  completed: "2026-03-27T18:14:43Z"
  tasks_completed: 2
  files_created: 6
  files_modified: 3
---

# Phase 10 Plan 03: File Size Reduction — Groups, Logistics, Memories Summary

Split three oversized screen files to under 800 lines by extracting self-contained widget classes: group settlement cards, logistics subgroup cards, and memories photo grid.

## What Was Built

### Task 1: group_settle_up_screen.dart (1021 -> 712 lines)

Extracted two widget files from `_GroupSettleUpScreenState`:

**`group_settlement_summary.dart`** — `GroupSettlementSummaryCard` StatelessWidget. Renders the gradient summary card at the top of the settle-up screen showing total pending amount and event count. Takes `totalPending`, `currency`, `eventCount`.

**`group_settlement_tile.dart`** — two classes:
- `GroupSettlementTile` StatelessWidget: renders a single settlement row (payer/payee/amount, per-event breakdown, optional action button). `onRecord` is nullable — button only appears when non-null.
- `GroupSettlementGroupCard` StatelessWidget: wraps a list of tiles in a styled container card.

The screen retains scroll controller, tile key management, pre-selected member auto-scroll, section headers, settlement confirmation bottom sheet, and `_recordSettlement`.

### Task 2: logistics_screen.dart (886 -> 528 lines) + memories_screen.dart (782 -> 427 lines)

**Logistics — `subgroup_card.dart`** — `SubgroupCard` StatelessWidget. Renders a full `DragTarget<Participant>` card with header (icon, name, capacity badge, delete button) and a member slot grid. All mutations (`onDeleteGroup`, `onAddMember`, `onRemoveMember`, `onDrop`) delegated via callbacks to the screen.

**Logistics — `unassigned_pool.dart`** — `UnassignedPool` StatelessWidget. Horizontal drag-and-drop pool of unassigned participants. Screen computes `unassigned` list and passes it as constructor param — avoids nested `ref.watch` in widget.

**Memories — `photo_grid.dart`** — `MemoriesPhotoGrid` StatelessWidget. Scrollable list grouped by date with staggered 2-column layout. Accepts `onTap(Memory)` and `onRefresh()` callbacks.

**Memories — `full_screen_photo.dart`** — `FullScreenPhoto` StatelessWidget (was `_FullScreenPhoto` private class in same file). Full-screen photo viewer with pinch-to-zoom, delete confirmation, and uploader attribution.

## Decisions Made

- `GroupSettlementTile.onRecord` is nullable `VoidCallback` — tile renders no button when null, avoiding conditional `isYourAction || _isCurrentUser(toUserId)` logic leaking into the widget.
- `UnassignedPool` is `StatelessWidget` not `ConsumerWidget` — the parent `_LogisticsScreenState._buildGroupList` already has `ref` access and computes the unassigned list, avoiding a second `ref.watch` inside the widget for the same provider.
- `SubgroupCard` receives all four callbacks — this keeps the legacy `debugPrint` stubs in one place (the screen) and makes the widget fully reusable when the EventRef write flow is implemented.
- `FullScreenPhoto` made public by removing `_` prefix per plan spec, matching the file name.

## Deviations from Plan

None — plan executed exactly as written.

## Verification

```
group_settle_up_screen.dart:  712 lines (< 800) PASS
logistics_screen.dart:        528 lines (< 800) PASS
memories_screen.dart:         427 lines (< 800) PASS
flutter analyze:              No issues found PASS
flutter test:                 599/599 passed PASS
```

## Commits

| Task | Commit | Description |
|------|--------|-------------|
| 1 | ecb4df3 | refactor(10-03): split group_settle_up_screen to under 800 lines |
| 2 | cee07f7 | refactor(10-03): split logistics_screen and memories_screen to under 800 lines |

## Self-Check: PASSED
