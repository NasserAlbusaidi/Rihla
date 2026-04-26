---
phase: 39
plan: 02
subsystem: filesystem
tags: [strip, deletion, orphaned-imports]
requires: [39-01]
provides: [cut-feature-source-removed, orphan-import-catalog]
affects: [lib/features, test/features, test/goldens]
tech-stack:
  added: []
  patterns: [destructive-rm]
key-files:
  created:
    - .planning/phases/39-strip-to-shippable-v1-remove-memories-vault-logistics-onboar/39-02-SUMMARY.md
  modified: []
  deleted:
    - lib/features/gear/
    - lib/features/logistics/
    - lib/features/memories/
    - lib/features/onboarding/
    - lib/features/vault/
    - test/features/gear/
    - test/features/logistics/
    - test/features/memories/
    - test/features/vault/
    - test/features/gear_screen_mutations_test.dart
    - test/features/logistics_screen_mutations_test.dart
    - test/features/memories_screen_mutations_test.dart
    - test/features/vault_screen_mutations_test.dart
    - test/goldens/onboarding_golden_test.dart
    - test/goldens/goldens/onboarding_light.png
    - test/goldens/goldens/onboarding_dark.png
    - test/goldens/memories_golden_test.dart
    - test/goldens/goldens/memories_light.png
    - test/goldens/goldens/memories_dark.png
decisions:
  - "Wave 2 is delete-only — no orphan-import fixes here, those are catalogued for 39-03 / 39-04"
metrics:
  completed: 2026-04-26
---

# Phase 39 Plan 02: Physical Deletion of Cut Feature Directories — Summary

Wave 2 of the strip phase: physically removed the five cut feature directories and their tests. After this plan, `flutter analyze` reports 265 errors across 29 files — those are catalogued below as input for plans 39-03 and 39-04.

## Deleted directories and files

### lib/features/ (Five feature directories — 51 files)

- `lib/features/gear/` — keys, models, providers, screens, services, widgets
- `lib/features/logistics/` — keys, models, providers, screens, services, widgets
- `lib/features/memories/` — keys, models, providers, screens, services, widgets
- `lib/features/onboarding/` — screens, widgets
- `lib/features/vault/` — keys, models, providers, screens, services, widgets

### test/features/ (Subtrees + four sibling files)

- `test/features/gear/`
- `test/features/logistics/`
- `test/features/memories/`
- `test/features/vault/`
- `test/features/gear_screen_mutations_test.dart`
- `test/features/logistics_screen_mutations_test.dart`
- `test/features/memories_screen_mutations_test.dart`
- `test/features/vault_screen_mutations_test.dart`

### test/goldens/ (Onboarding + memories goldens)

- `test/goldens/onboarding_golden_test.dart`
- `test/goldens/goldens/onboarding_light.png`
- `test/goldens/goldens/onboarding_dark.png`
- `test/goldens/memories_golden_test.dart` *(not in original plan — found via `find test -name "*memories*"`)*
- `test/goldens/goldens/memories_light.png` *(not in original plan)*
- `test/goldens/goldens/memories_dark.png` *(not in original plan)*

### Surviving lib/features/ (8 dirs)

`activity, auth, events, groups, home, ledger, settings, trip`

### Surviving test/features/ (7 dirs + 4 root tests)

`events, groups, home, ledger, profile, settings, shared_widgets` plus `group_balance_card_test.dart, group_detail_screen_test.dart, group_settle_up_screen_test.dart, ledger_test.dart`.

## Orphaned-import errors (265 total across 29 files)

Captured from `flutter analyze 2>&1 | grep "error •"`. Full output at `/tmp/post-delete-analyze.txt`.

### Production code (10 files)

| File | Cause |
|------|-------|
| `lib/core/services/cache/gear_cache_repository.dart` | imports `gear/models/gear_item_model.dart` (deleted) |
| `lib/core/services/cache/sub_group_cache_repository.dart` | imports `logistics/models/sub_group_model.dart` (deleted) |
| `lib/features/events/services/event_service.dart` | (verify — may import cut models) |
| `lib/features/ledger/providers/expense_provider.dart` | references cut providers/types |
| `lib/features/ledger/screens/add_expense_screen.dart` | references cut providers/types |
| `lib/features/ledger/screens/ledger_screen.dart` | references cut providers/types |
| `lib/features/ledger/screens/settle_up_screen.dart` | references cut providers/types |
| `lib/features/ledger/widgets/edit_expense_payer_selector.dart` | references cut providers/types |
| `lib/features/ledger/widgets/edit_expense_scope_section.dart` | references cut providers/types |
| `lib/features/ledger/widgets/split_scope_selector.dart` | references cut providers/types |

### Tests (19 files)

| File | Cause |
|------|-------|
| `test/features/events/event_command_center_test.dart` | imports cut providers/types |
| `test/features/events/event_module_list_test.dart` | imports cut providers/types |
| `test/features/ledger_test.dart` | imports cut providers/types |
| `test/features/ledger/payer_currency_rewiring_test.dart` | imports cut providers/types |
| `test/features/ledger/widgets/edit_expense_form_test.dart` | imports cut providers/types |
| `test/features/ledger/widgets/edit_expense_payer_selector_test.dart` | imports cut providers/types |
| `test/features/ledger/widgets/edit_expense_scope_section_test.dart` | imports cut providers/types |
| `test/integration/happy_path_test.dart` | imports cut providers/types |
| `test/unit/balance_calculations_test.dart` | imports cut models |
| `test/unit/document_service_test.dart` | imports cut services |
| `test/unit/event_model_test.dart` | references EventModules cut fields |
| `test/unit/event_service_test.dart` | imports cut services |
| `test/unit/firebase_model_roundtrip_test.dart` | imports cut models |
| `test/unit/firestore_repository_test.dart` | imports cut services |
| `test/unit/gear_service_test.dart` | imports cut services |
| `test/unit/memory_service_test.dart` | imports cut services |
| `test/unit/model_coverage_test.dart` | imports cut models |
| `test/unit/provider_swap_test.dart` | imports cut providers |
| `test/unit/sub_group_service_test.dart` | imports cut services |

## Files needing edits in plans 39-03 / 39-04

The 29 files above are the input list for Wave 3. Plans 39-03 (Thawani + currency picker + orphan cleanup) and 39-04 (TripModules pruning) divide them up roughly:

**Plan 39-03 (orphan cleanup + currency strip):**
- All 10 production-code files
- All 19 test files (delete tests for cut features outright; surviving tests get import fixes only)

**Plan 39-04 (TripModules pruning):**
- `lib/features/trip/models/trip_model.dart` (TripModules class — not in error list because no consumer is broken yet, but listed in 39-04 frontmatter)
- `lib/core/services/cache/trip_cache_repository.dart` (consumes TripModules.fromJson)
- `test/unit/trip_model_back_compat_test.dart` (new)

## Notes on extra deletions

The plan's catalog called out only `onboarding_golden_test.dart` + 2 PNGs under `test/goldens/`. A `find test -name "*memories*"` after deletion turned up `memories_golden_test.dart` + 2 PNGs as well — these were also dead-weight after the memories feature was removed. Deleted in the same commit as Tasks 1 + 2.

## Commits

- `(Wave 2 single commit)` — feat(39-02): delete five cut feature directories and their tests

## Self-Check: PASSED

- [x] `! test -d lib/features/{memories,vault,logistics,gear,onboarding}` — all five absent
- [x] All eight surviving features present in `lib/features/`
- [x] No `*onboarding*`, `*memories*`, `*vault*`, `gear*`, `logistics*` test files remain
- [x] `39-02-SUMMARY.md` exists with all three required sections (Deleted, Orphaned-imports, Files-needing-edits)

## Handoff to Wave 3

Plan 39-03 reads this SUMMARY's "Files needing edits" section as its work list — no re-grepping required. Plan 39-04 reads it for the TripModules audit input.
