---
phase: 14-test-hardening
plan: "01"
subsystem: test-infrastructure
tags: [keys, widget-testing, find-byKey, test-hardening]
dependency_graph:
  requires: []
  provides: [semantic-widget-keys, rename-resilient-tests]
  affects: [test/unit, test/features/events, test/features/groups]
tech_stack:
  added: []
  patterns: [abstract-final-class-keys, find-byKey-structural-assertions]
key_files:
  created:
    - lib/core/keys/shared_keys.dart
    - lib/features/events/keys/event_keys.dart
    - lib/features/groups/keys/group_keys.dart
    - lib/features/home/keys/home_keys.dart
    - lib/features/ledger/keys/ledger_keys.dart
    - lib/features/gear/keys/gear_keys.dart
    - lib/features/logistics/keys/logistics_keys.dart
    - lib/features/memories/keys/memories_keys.dart
    - lib/features/onboarding/keys/onboarding_keys.dart
    - lib/features/settings/keys/settings_keys.dart
    - lib/features/vault/keys/vault_keys.dart
    - lib/features/activity/keys/activity_keys.dart
  modified:
    - lib/features/events/screens/event_command_center.dart
    - lib/features/events/screens/create_event_screen.dart
    - lib/features/events/screens/event_type_picker_screen.dart
    - lib/features/events/screens/event_expense_hero.dart
    - lib/features/events/widgets/event_module_list.dart
    - lib/features/groups/screens/group_detail_screen.dart
    - lib/features/groups/screens/create_group_screen.dart
    - lib/features/groups/screens/join_group_screen.dart
    - lib/features/groups/screens/group_settle_up_screen.dart
    - lib/features/groups/screens/group_settings_screen.dart
    - lib/features/groups/screens/group_activity_screen.dart
    - lib/features/groups/widgets/group_balance_hero.dart
    - lib/features/groups/widgets/invite_code_display.dart
    - lib/features/groups/widgets/group_settlement_tile.dart
    - lib/features/home/screens/home_screen.dart
    - lib/features/ledger/screens/ledger_screen.dart
    - lib/features/ledger/screens/add_expense_screen.dart
    - lib/features/ledger/screens/edit_expense_sheet.dart
    - lib/features/ledger/screens/settle_up_screen.dart
    - lib/features/gear/screens/gear_screen.dart
    - lib/features/logistics/screens/logistics_screen.dart
    - lib/features/memories/screens/memories_screen.dart
    - lib/features/onboarding/screens/onboarding_screen.dart
    - lib/features/settings/screens/settings_screen.dart
    - lib/features/vault/screens/vault_screen.dart
    - lib/features/activity/screens/activity_feed_screen.dart
    - lib/shared/widgets/app_tab_bar.dart
    - lib/shared/widgets/module_header.dart
    - lib/shared/widgets/offline_banner.dart
    - lib/shared/widgets/empty_state_view.dart
    - test/unit/widget_coverage_test.dart
    - test/features/events/event_command_center_test.dart
    - test/features/groups/group_settle_up_screen_test.dart
decisions:
  - "abstract final class with static const Key fields for zero-runtime-cost namespaced keys"
  - "Screen-level keys on Scaffold root (or root Container for bottom sheets) — unconditional"
  - "Module card keys applied at SmartModuleCard call site in event_module_list.dart via widgetKey parameter"
  - "Structural assertions use find.byKey(); content assertions (formatted amounts, validation messages, fixture data) keep find.text()"
  - "create_join_group_test.dart had no structural conversions — all assertions test content (labels, values, validation errors)"
metrics:
  duration: "~90 minutes (across two sessions)"
  completed: "2026-03-28"
  tasks_completed: 2
  files_modified: 33
---

# Phase 14 Plan 01: Semantic Widget Keys and Test Migration Summary

Semantic widget key infrastructure established across all 22 screens and key feature widgets; 3 of 4 test files migrated from structural `find.text()` to `find.byKey()`. 624 tests pass.

## Objective

Establish rename-resilient test infrastructure before Phase 14's visual UI changes. Tests that rely on `find.text('Ledger')` break when text is renamed to 'Expenses' — `find.byKey(EventKeys.ledgerCard)` does not.

## What Was Built

### Task 1: Key Class Files and Widget Annotations

12 key class files created using the `abstract final class` pattern with `static const Key` fields:

- `lib/core/keys/shared_keys.dart` — shared widgets (module header back button, offline banner, empty state, group balance hero, invite code display, app tab bar tabs, loading button)
- `lib/features/events/keys/event_keys.dart` — EventCommandCenter screen, create/picker screens, 6 module cards, FAB, spending hero, module list, event card
- `lib/features/groups/keys/group_keys.dart` — 6 group screens, section keys, 8 action buttons, input keys, parameterized member/tile keys
- 9 remaining feature key files (home, ledger, gear, logistics, memories, onboarding, settings, vault, activity)

All 22 screens received `key:` on their root Scaffold (or Container for bottom sheets). Key feature widgets annotated: SmartModuleCard instances via `widgetKey` parameter, GroupBalanceHero, InviteCodeDisplay, AppTabBar tabs, OfflineBanner, EmptyStateView, ModuleHeader back button, GroupSettlementTile record button.

### Task 2: Test Migration

Classified all structural `find.text()` calls across 4 test files per the D-01 through D-14 decision rules:

| File | Structural Conversions | Content Kept |
|------|----------------------|--------------|
| `widget_coverage_test.dart` | AppTabBar tab tap, InviteCodeDisplay copy/share buttons, GroupBalanceHero settle up button | Amount text, hint text, fixture labels |
| `event_command_center_test.dart` | 5 module card presence/absence checks (ledgerCard, gearCard, etc.), FAB presence/tap | Event names, group names, SPENDING label |
| `group_settle_up_screen_test.dart` | Bottom sheet Mark as Paid and Not Now buttons | Screen title, section labels, content text, Retry button |
| `create_join_group_test.dart` | None (all assertions are content-based: form labels, validation messages, fixture values) | All kept as find.text() |

## Decisions Made

1. `abstract final class` with `static const Key` — zero runtime cost, compile-time constants, can be used in `const` widget constructors
2. Screen-level keys are unconditional: every screen's root Scaffold gets its key regardless of state
3. Dual-Scaffold screens (memories, vault) apply the same key to both branches — safe because only one renders at any time
4. Module card keys live at the `SmartModuleCard` call site in `event_module_list.dart`, not inside `smart_module_card.dart` itself — this keeps the key at the semantic boundary
5. `recordSettlementButton` key in `group_settlement_tile.dart` is conditional (`isYourAction ? key : null`) — `find.text('Record Settlement')` kept in tests because the key is not always set
6. `create_join_group_test.dart` required zero structural conversions — all its assertions validate form content, not structural navigation

## Deviations from Plan

None — plan executed exactly as written. The plan listed `create_join_group_test.dart` as a migration target, but after analysis all its assertions were content-based (Group Name label, validation error messages, dropdown values, fixture data). This is correct behavior per the classification rules — no forced conversions.

## Commits

- `e80901b` — `feat(14-01): create 12 key class files and apply keys to all screens and widgets`
- `7fffea5` — `test(14-01): migrate widget_coverage_test from find.text to find.byKey`
- `0d28118` — `test(14-01): migrate event and group tests from find.text to find.byKey`

## Known Stubs

None. All keys are real widget annotations, not placeholders.

## Self-Check: PASSED
