---
phase: 34-gear-logistics
plan: "01"
subsystem: features/gear, features/logistics
tags: [token-compliance, offline-banner, skeleton-loader, dead-code-cleanup]
dependency_graph:
  requires: [34-00]
  provides: [GEAR-OFFLINE, GEAR-TOKENS, LOGISTICS-OFFLINE, LOGISTICS-TOKENS, DEAD-CODE-CLEANUP]
  affects: [lib/features/gear/screens/gear_screen.dart, lib/features/logistics/screens/logistics_screen.dart]
tech_stack:
  added: []
  patterns: [OfflineBanner-after-ModuleHeader, AppColorTokens-module-gradient]
key_files:
  created: []
  modified:
    - lib/features/gear/screens/gear_screen.dart
    - lib/features/logistics/screens/logistics_screen.dart
  deleted:
    - lib/features/logistics/widgets/subgroup_card.dart
    - lib/features/logistics/widgets/logistics_hero_card.dart
decisions:
  - Token gradients use AppColorTokens.light.moduleGear/moduleGearLight and moduleLogistics/moduleLogisticsLight (gray-500 + gray-100) — not custom olive/teal hex values
  - OfflineBanner placed immediately after ModuleHeader in the loaded Scaffold only — pre-event loading Scaffold excluded (consistent with Phase 28-33 pattern)
  - SkeletonLoader.gearList used instead of cardList for semantic match with gear item layout (checkbox + name + assignee)
  - subgroup_card.dart deleted — production code uses sub_group_card.dart; lowercase variant was a leftover duplicate
  - logistics_hero_card.dart deleted — referenced only in a code comment, not imported anywhere
metrics:
  duration: 185s
  completed_date: "2026-04-05"
  tasks_completed: 3
  files_changed: 4
---

# Phase 34 Plan 01: Gear + Logistics Token Compliance and OfflineBanner Summary

Token-compliant GearScreen and LogisticsScreen with OfflineBanner, gearList skeleton, and two dead code files deleted.

## What Was Built

Applied four targeted fixes to GearScreen and LogisticsScreen:

1. **GearScreen token gradient** — Replaced `Color(0xFF7A8C5E)` / `Color(0xFF96A876)` with `AppColorTokens.light.moduleGear` / `AppColorTokens.light.moduleGearLight` in EmptyStateView accentGradient.

2. **GearScreen OfflineBanner** — Added `const OfflineBanner()` between ModuleHeader and Expanded in the main Scaffold body. Pre-event loading Scaffold excluded per established pattern.

3. **GearScreen skeleton upgrade** — Both loading states changed from `SkeletonLoader.cardList` to `SkeletonLoader.gearList` (checkbox + name + assignee layout matches actual gear items).

4. **LogisticsScreen token gradient** — Replaced `Color(0xFF5B7B8C)` / `Color(0xFF7B9BAC)` with `AppColorTokens.light.moduleLogistics` / `AppColorTokens.light.moduleLogisticsLight`.

5. **LogisticsScreen OfflineBanner** — Added `const OfflineBanner()` between ModuleHeader and Expanded in the main Scaffold body.

6. **Dead code deletion** — Removed `subgroup_card.dart` (lowercase duplicate of `sub_group_card.dart`) and `logistics_hero_card.dart` (comment-only reference, not imported anywhere).

## Commits

| Hash | Message |
|------|---------|
| 04c6daa | feat(34-01): fix GearScreen — token gradient, OfflineBanner, gearList skeleton |
| 4fc1e1d | feat(34-01): fix LogisticsScreen + delete dead code files |

## Test Results

- `gear_screen_mutations_test.dart` — 8/8 tests pass including `GearScreen — OfflineBanner renders in body`
- `logistics_screen_mutations_test.dart` — 8/8 tests pass including `LogisticsScreen — OfflineBanner renders in body`
- Full suite: 864 passing, 3 skipped, 3 failing (pre-existing failures in `happy_path_test.dart`, `ledger/payer_currency_rewiring_test.dart`, `group_settle_up_screen_test.dart` — caused by `add_expense_screen.dart` compile errors unrelated to this plan)

## Verification

```
grep -r "Color(0xFF" lib/features/gear/ lib/features/logistics/ → no results (PASS)
grep OfflineBanner lib/features/gear/screens/gear_screen.dart → import + usage
grep OfflineBanner lib/features/logistics/screens/logistics_screen.dart → import + usage
grep cardList lib/features/gear/screens/gear_screen.dart → no results
grep gearList lib/features/gear/screens/gear_screen.dart → 2 results (both loading states)
ls lib/features/logistics/widgets/ → sub_group_card.dart, unassigned_pool.dart (dead files gone)
```

## Deviations from Plan

None — plan executed exactly as written.

## Known Stubs

None. All changes are functional token replacements and structural widget additions.

## Self-Check: PASSED

- `lib/features/gear/screens/gear_screen.dart` — exists, modified
- `lib/features/logistics/screens/logistics_screen.dart` — exists, modified
- `lib/features/logistics/widgets/subgroup_card.dart` — deleted (confirmed absent)
- `lib/features/logistics/widgets/logistics_hero_card.dart` — deleted (confirmed absent)
- Commits 04c6daa and 4fc1e1d — both present in git log
