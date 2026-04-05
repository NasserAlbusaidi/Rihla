---
phase: 31-event-command-center
plan: "03"
subsystem: events/ui
tags: [event-command-center, expense-hero, member-count, token-audit, tdd]
dependency_graph:
  requires: ["31-01"]
  provides: ["ECC-03"]
  affects: ["lib/features/events/screens/event_expense_hero.dart"]
tech_stack:
  added: []
  patterns: ["TDD RED-GREEN", "inline Row stats display", "participantIds.length member count"]
key_files:
  created: []
  modified:
    - lib/features/events/screens/event_expense_hero.dart
    - test/features/events/event_command_center_test.dart
decisions:
  - "Member count sourced from event.participantIds.length — no async call, event already in scope"
  - "Row layout with U+00B7 middle dot separator for inline expense + member stats"
  - "Token audit: both event_expense_hero.dart and smart_module_card.dart confirmed clean — no hardcoded Color(0xFF..) literals"
  - "EventModuleList ordering verified correct (Ledger→Gear→Logistics→Vault→Activity→Memories) — no code change needed"
metrics:
  duration: "~3 minutes"
  completed: "2026-04-05"
  tasks_completed: 1
  files_modified: 2
---

# Phase 31 Plan 03: EventExpenseHero Member Count + Token Audit Summary

**One-liner:** Member count row added to EventExpenseHero using participantIds.length with U+00B7 separator; token audit confirmed both files clean.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| TDD RED | Add failing ECC-03 tests | 770b5b2 | test/features/events/event_command_center_test.dart |
| TDD GREEN | Add member count + token audit | 85020ce | lib/features/events/screens/event_expense_hero.dart |

## What Was Built

### Member Count Row in EventExpenseHero

The standalone expense count `Text` widget was replaced with a `Row` showing both expense count and member count inline:

```
N expenses · N members
```

- Separator is U+00B7 (middle dot) with `textMuted` color
- Member count uses `event.participantIds.length` — synchronous, no async provider needed
- Only shown in the `data:` branch — loading and error branches unchanged
- Text style matches expense count (12sp / weight 600 / textSecondary)

### Token Audit Results

- `event_expense_hero.dart`: Zero `Color(0xFF..)` literals — all colors use `AppColorTokens.light.*`
- `smart_module_card.dart`: Zero `Color(0xFF..)` literals — pre-existing clean state confirmed

### EventModuleList Ordering Verified

Confirmed at lines 78–93: Ledger → Gear → Logistics → Vault → Activity → Memories. No code change needed.

## Test Results

- 22/22 tests pass in `event_command_center_test.dart`
- ECC-03 group: 3 new tests (singular/plural member count, co-presence with expense count)
- `flutter analyze lib/features/events/screens/event_expense_hero.dart`: 0 errors (1 pre-existing info: `prefer_const_constructors` in error branch — out of scope)

## Deviations from Plan

None — plan executed exactly as written.

## Known Stubs

None — all member count data is live from `event.participantIds`.

## Self-Check: PASSED

- [x] `lib/features/events/screens/event_expense_hero.dart` exists and modified
- [x] `test/features/events/event_command_center_test.dart` exists and modified
- [x] Commit 770b5b2 exists (TDD RED)
- [x] Commit 85020ce exists (TDD GREEN)
- [x] All 22 event_command_center tests pass
