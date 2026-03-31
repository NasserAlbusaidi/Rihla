---
phase: 22-polish-pass-token-cleanup
plan: "04"
subsystem: ui-polish
tags: [grain-texture, hero-cards, visual-warmth, two-tier-hierarchy]
dependency_graph:
  requires: [22-01, 22-02, 22-03]
  provides: [grain-texture-on-hero-cards, grain-texture-on-module-header, grain-texture-on-scaffold]
  affects: [balance_hero_card, ledger_hero_card, event_expense_hero, event_spending_hero, group_balance_hero, gear_hero_card, vault_hero_card, logistics_hero_card, memories_hero_card, activity_hero_card, module_header, bottom_nav_shell]
tech_stack:
  added: []
  patterns: [DecorationImage-in-BoxDecoration, GrainOverlay-widget-wrapper]
key_files:
  created: []
  modified:
    - lib/features/home/widgets/balance_hero_card.dart
    - lib/features/ledger/widgets/ledger_hero_card.dart
    - lib/features/events/screens/event_expense_hero.dart
    - lib/features/events/widgets/event_spending_hero.dart
    - lib/features/groups/widgets/group_balance_hero.dart
    - lib/features/gear/widgets/gear_hero_card.dart
    - lib/features/vault/widgets/vault_hero_card.dart
    - lib/features/logistics/widgets/logistics_hero_card.dart
    - lib/features/memories/widgets/memories_hero_card.dart
    - lib/features/activity/widgets/activity_hero_card.dart
    - lib/shared/widgets/module_header.dart
    - lib/features/home/widgets/bottom_nav_shell.dart
decisions:
  - "DecorationImage added inline to existing BoxDecoration (not GrainOverlay widget) for hero cards — avoids extra widget layer"
  - "GrainOverlay widget wrapper used for BottomNavShell (scaffold body) — only location where GrainOverlay widget pattern is appropriate"
  - "ModuleHeader grain at 2% opacity (not 3.5%) — lower opacity on dark gradient backgrounds for subtle depth without competing with white text"
  - "Both gradient and solid-color hero cards receive grain — DecorationImage renders on top of gradient (desired: grain over gradient = textured surface)"
  - "Error card in BalanceHeroCard also receives grain — consistent within the hero tier"
metrics:
  duration_minutes: 3
  tasks_completed: 3
  files_modified: 12
  completed_date: "2026-03-31"
---

# Phase 22 Plan 04: Grain Texture on Hero Cards and Scaffold Summary

**One-liner:** Paper grain texture (3.5% hero cards, 2% module headers) applied via DecorationImage inline to all 10 hero cards and ModuleHeader, plus GrainOverlay wrapper on BottomNavShell scaffold body — creating a warm two-tier visual hierarchy.

## What Was Built

Satisfies PLSH-05: grain/texture overlays for visual warmth. Creates a clear two-tier visual hierarchy:
- **Tier 1 (textured):** Hero/summary cards, ModuleHeaders, scaffold background
- **Tier 2 (flat/clean):** Content list cards (ExpenseCard, SettlementRow, GearItem rows, etc.)

### Task 1: All 10 Hero Cards — grain at 3.5% opacity

Applied `DecorationImage` inline to existing `BoxDecoration` in each hero card:

| Hero Card | File | Background Type |
|-----------|------|----------------|
| BalanceHeroCard (main + error) | home/widgets/balance_hero_card.dart | AppColors.surface (white) |
| LedgerHeroCard | ledger/widgets/ledger_hero_card.dart | AppColors.surface (white) |
| EventExpenseHero | events/screens/event_expense_hero.dart | AppColors.surface + border |
| EventSpendingHero | events/widgets/event_spending_hero.dart | darkHeaderGradient |
| GroupBalanceHero | groups/widgets/group_balance_hero.dart | darkHeaderGradient |
| GearHeroCard | gear/widgets/gear_hero_card.dart | AppColors.surface (white) |
| VaultHeroCard | vault/widgets/vault_hero_card.dart | AppColors.surface (white) |
| LogisticsHeroCard | logistics/widgets/logistics_hero_card.dart | AppColors.surface (white) |
| MemoriesHeroCard | memories/widgets/memories_hero_card.dart | AppColors.surface (white) |
| ActivityHeroCard | activity/widgets/activity_hero_card.dart | AppColors.surface (white) |

### Task 2: ModuleHeader dark variant — grain at 2% opacity

The `_buildDark` method in `module_header.dart` received a `DecorationImage` at 0.02 opacity. The dark gradient background gains a subtle canvas/leather texture. Light variant unchanged.

### Task 3: BottomNavShell scaffold body — GrainOverlay wrapper

The `IndexedStack` in `_buildBody()` is wrapped in `GrainOverlay(opacity: 0.035)`. This single wrapper covers all 4 tabs from one location.

## Deviations from Plan

None — plan executed exactly as written.

## Known Stubs

None. All grain changes are complete and production-ready.

## Commits

| Task | Commit | Description |
|------|--------|-------------|
| Task 1 | 7ade100 | feat(22-04): apply grain texture to all 10 hero cards |
| Task 2 | 264c76e | feat(22-04): apply grain texture to ModuleHeader dark variant |
| Task 3 | a44a502 | feat(22-04): wrap BottomNavShell body in GrainOverlay for scaffold texture |

## Test Results

- 216 feature + shared widget tests: all passed
- 0 analyze errors in modified files (1 pre-existing info-level lint in event_spending_hero.dart: unrelated `(_, __)` pattern)

## Self-Check: PASSED

- [x] balance_hero_card.dart — grain in main + error card BoxDecoration
- [x] ledger_hero_card.dart — grain in BoxDecoration
- [x] event_expense_hero.dart — grain in BoxDecoration
- [x] event_spending_hero.dart — grain in BoxDecoration (gradient card)
- [x] group_balance_hero.dart — grain in BoxDecoration (gradient card)
- [x] gear_hero_card.dart — grain in BoxDecoration
- [x] vault_hero_card.dart — grain in BoxDecoration
- [x] logistics_hero_card.dart — grain in BoxDecoration
- [x] memories_hero_card.dart — grain in BoxDecoration
- [x] activity_hero_card.dart — grain in BoxDecoration
- [x] module_header.dart — grain at 0.02 opacity in dark BoxDecoration
- [x] bottom_nav_shell.dart — GrainOverlay wrapping IndexedStack
- [x] 3 commits exist: 7ade100, 264c76e, a44a502
- [x] 13 files contain grain references (>= 12 required)
- [x] ModuleHeader opacity is 0.02
- [x] Hero card opacity is 0.035
- [x] No content list cards contain grain
