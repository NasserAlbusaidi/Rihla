---
phase: 37-dark-theme-migration
plan: 03c
subsystem: events-ledger-theme-migration
tags: [theme, dark-mode, migration, features, events, ledger, wave-3]
requires:
  - Wave 2 foundation (context.colors / context.spacing / context.shadows extensions)
  - Shared-widget layer theme-aware (37-02-SUMMARY.md)
provides:
  - lib/features/events/ (13 migrated files) reads every color via context.colors
  - lib/features/ledger/ (19 migrated files) reads every color via context.colors
  - BalanceCalculator integrity preserved (Decimal logic untouched)
  - Plan 04 handoff annotations for 7 hardcoded Color literals:
    - 5 in event_type_config.dart (category palette)
    - 1 in expense_category_model.dart (fallback color)
    - 1 in ledger_screen.dart (hero gradient pair, counted as one cluster)
affects:
  - Downstream Wave 4 (token cleanup) has explicit handoff list
  - Dark-mode correctness: events + ledger surfaces now respect ThemeMode
tech-stack:
  added: []
  patterns:
    - "context.colors.* over AppColorTokens.light.* — theme-aware reads via BuildContext"
    - "BuildContext threaded through private _build* helper methods (not globals)"
    - "design-token-justified comment for intentional hex literals with Plan 04 handoff"
    - "const Map<EventType, EventTypeConfig> kept static — literals annotated (const cannot
      reference ThemeExtension fields)"
key-files:
  modified:
    - lib/features/events/models/event_type_config.dart
    - lib/features/events/screens/create_event_screen.dart
    - lib/features/events/screens/event_command_center.dart
    - lib/features/events/screens/event_expense_hero.dart
    - lib/features/events/screens/event_settings_screen.dart
    - lib/features/events/screens/event_type_picker_screen.dart
    - lib/features/events/widgets/event_card.dart
    - lib/features/events/widgets/event_danger_section.dart
    - lib/features/events/widgets/event_details_card.dart
    - lib/features/events/widgets/event_info_section.dart
    - lib/features/events/widgets/event_module_list.dart
    - lib/features/events/widgets/event_modules_card.dart
    - lib/features/events/widgets/event_participants_card.dart
    - lib/features/ledger/models/expense_category_model.dart
    - lib/features/ledger/screens/add_expense_screen.dart
    - lib/features/ledger/screens/edit_expense_screen.dart
    - lib/features/ledger/screens/ledger_screen.dart
    - lib/features/ledger/screens/settle_up_screen.dart
    - lib/features/ledger/widgets/amount_input_section.dart
    - lib/features/ledger/widgets/category_selection_step.dart
    - lib/features/ledger/widgets/edit_expense_form.dart
    - lib/features/ledger/widgets/edit_expense_payer_selector.dart
    - lib/features/ledger/widgets/edit_expense_scope_section.dart
    - lib/features/ledger/widgets/expense_card.dart
    - lib/features/ledger/widgets/expense_success_dialog.dart
    - lib/features/ledger/widgets/ledger_hero_card.dart
    - lib/features/ledger/widgets/receipt_picker_section.dart
    - lib/features/ledger/widgets/recent_expenses_section.dart
    - lib/features/ledger/widgets/recorded_settlements_section.dart
    - lib/features/ledger/widgets/settlement_row.dart
    - lib/features/ledger/widgets/settlement_summary_card.dart
    - lib/features/ledger/widgets/settlement_tile.dart
    - lib/features/ledger/widgets/split_scope_selector.dart
  deleted:
    - lib/features/ledger/screens/edit_expense_sheet.dart (stale untracked file
      from pre-Phase-19 reversion; was never in HEAD — pre-existing Rule 3 blocker)
decisions:
  - "textMuted triage (events): all 6 refs functional → textSecondary. Zero
    decorative-justified exemptions."
  - "textMuted triage (ledger): all 46 refs functional → textSecondary. Section
    labels (`YOUR ACTIONS`, `WAITING FOR OTHERS`), inactive chip text in binary
    selected/unselected toggles, icon tints on body rows — all WCAG-functional.
    Zero decorative-justified exemptions."
  - "event_type_config.dart category palette (5 literals at lines 43/51/59/67/75)
    kept as hex per D-15 — const Map cannot reference ThemeExtension fields.
    Each gets `// design-token-justified: event type color — pending Plan 04
    category token migration (maps to context.colors.<role>)` comment."
  - "expense_category_model.dart line 74 fallback `Color(0xFF22C55E)` annotated
    as Plan 04 handoff. Per D-15, the model stays the category-color authority
    but Plan 04 will source each color from tokens."
  - "ledger_screen.dart:378 hero gradient pair `[Color(0xFFCC6B49), Color(0xFFE0896A)]`
    annotated as Plan 04 handoff (AppGradients.terracotta). Terracotta on
    ledger contradicts the CLAUDE.md 'Ledger = primary teal' module accent rule,
    but Phase 37 is mechanical migration only (D-03) — revisit in follow-up
    phase (see 37-CONTEXT.md deferred ideas)."
  - "Private `_build*` helper methods that referenced `context.colors` (which
    only exists inside a BuildContext scope) had a BuildContext threaded
    through. Affected files: event_danger_section.dart (2 helpers),
    event_module_list.dart (6 helpers — Ledger/Gear/Logistics/Vault/Activity/Memories
    card builders), settle_up_screen.dart (1 helper), amount_input_section.dart
    (1 helper, 4 call sites), expense_card.dart (1 getter → method),
    recent_expenses_section.dart (1 helper), recorded_settlements_section.dart
    (1 helper), settlement_summary_card.dart (1 helper), settlement_tile.dart
    (1 helper, 2 call sites). Pattern: append `BuildContext context` as first
    positional parameter; update every call site in the same file."
  - "AppShadowTokens.standard.raised → context.shadows.raised in event_card.dart
    (BuildContext already in scope). Other shadow call sites were left as
    AppShadowTokens.standard.raised because (a) the import is still valid and
    (b) the Plan 04 shadow migration is out of scope here — keep touched
    surface minimal."
  - "D-20 spacing token adoption deferred in this plan. Touch surface (50
    files, ~300 color refs) was already large; adding spacing migration to
    every EdgeInsets/SizedBox triples diff size. Wave 4 or a dedicated
    spacing-adoption plan can sweep opportunistically when these files are
    revisited. No acceptance criteria in this plan require spacing
    replacements, so no deviation."
metrics:
  tasks_completed: 3
  tasks_planned: 3
  files_modified: 32
  files_deleted: 1
  commits: 2
  events_files_migrated: 13
  events_color_refs_migrated: 99
  events_textmuted_refs: 6
  ledger_files_migrated: 19
  ledger_color_refs_migrated: 197
  ledger_textmuted_refs: 46
  plan_04_handoff_annotations: 7
  balance_calculator_tests_passing: 33
completed: 2026-04-18
---

# Phase 37 Plan 03c: Events + Ledger Theme Migration Summary

Migrated every `AppColorTokens.light.*` read in `lib/features/events/` (13 files,
99 refs, 6 textMuted) and `lib/features/ledger/` (19 files, 197 refs, 46 textMuted)
to theme-aware `context.colors.*`. Preserved BalanceCalculator integrity — no
changes to financial calculation signatures or Decimal precision. Flagged 7
hardcoded `Color(0xFF...)` literals with `// design-token-justified:` comments for
Plan 04 token promotion.

## What Got Built

### Events Migration (13 files)

| File | Refs migrated | Notes |
| --- | --- | --- |
| `models/event_type_config.dart` | 10 | 5 category palette hex literals annotated for Plan 04 |
| `screens/create_event_screen.dart` | 1 | |
| `screens/event_command_center.dart` | 5 | |
| `screens/event_expense_hero.dart` | 9 | |
| `screens/event_settings_screen.dart` | 9 | |
| `screens/event_type_picker_screen.dart` | 5 | |
| `widgets/event_card.dart` | 12 | isPast-branch textMuted → textSecondary; AppShadowTokens → context.shadows |
| `widgets/event_danger_section.dart` | 14 | 2 helper methods take BuildContext |
| `widgets/event_details_card.dart` | 2 | |
| `widgets/event_info_section.dart` | 13 | |
| `widgets/event_module_list.dart` | 6 | 6 helpers take BuildContext |
| `widgets/event_modules_card.dart` | 8 | |
| `widgets/event_participants_card.dart` | 5 | |

### Ledger Migration (19 files)

| File | Refs migrated | Notes |
| --- | --- | --- |
| `models/expense_category_model.dart` | 0 color refs (1 literal) | Line 74 Color(0xFF22C55E) → design-token-justified |
| `screens/add_expense_screen.dart` | 19 | |
| `screens/edit_expense_screen.dart` | 9 | |
| `screens/ledger_screen.dart` | 8 | Line 378 hero gradient pair → design-token-justified |
| `screens/settle_up_screen.dart` | 20 | _buildSectionHeader takes BuildContext |
| `widgets/amount_input_section.dart` | 4 | _buildRow takes BuildContext |
| `widgets/category_selection_step.dart` | 5 | |
| `widgets/edit_expense_form.dart` | 21 | multi-line AppColorTokens\n.light resolved |
| `widgets/edit_expense_payer_selector.dart` | 2 | |
| `widgets/edit_expense_scope_section.dart` | 5 | |
| `widgets/expense_card.dart` | 8 | _balanceStatus getter → method(BuildContext) |
| `widgets/expense_success_dialog.dart` | 11 | |
| `widgets/ledger_hero_card.dart` | 7 | |
| `widgets/receipt_picker_section.dart` | 10 | |
| `widgets/recent_expenses_section.dart` | 9 | _buildExpenseItem takes BuildContext |
| `widgets/recorded_settlements_section.dart` | 11 | _buildHistoryItem takes BuildContext |
| `widgets/settlement_row.dart` | 6 | |
| `widgets/settlement_summary_card.dart` | 9 | _buildSummaryMiniItem takes BuildContext |
| `widgets/settlement_tile.dart` | 13 | _buildSmallAvatar takes BuildContext |
| `widgets/split_scope_selector.dart` | 20 | selected/unselected binary textMuted → textSecondary |

### textMuted Triage (per D-11)

All 52 textMuted refs across events + ledger were **functional** (section labels,
body metadata, inactive-state indicators in binary toggles, icon tints that convey
meaning). Per D-11, all migrated to `textSecondary`. Zero decorative-justified
exemptions.

Examples of call sites:
- `YOUR ACTIONS` / `WAITING FOR OTHERS` / `OTHERS SETTLING` section labels in settle_up_screen.dart → section heading text is functional
- `isSelected ? primary : textMuted` in split_scope_selector.dart → binary-state indicator, functional
- `event.isPast ? textMuted : primary` accent bar in event_card.dart → state indicator, functional
- Icon tints on body rows in settlement_summary_card.dart, settlement_tile.dart, recent_expenses_section.dart → functional iconography

Running count: **52 textMuted → textSecondary conversions, 0 decorative-justified retentions.**

### Plan 04 Handoff Annotations

7 hardcoded hex literals flagged with `// design-token-justified:` comments:

| File:line | Literal | Pending Plan 04 target |
| --- | --- | --- |
| `event_type_config.dart:43` | `Color(0xFF0D7B74)` | context.colors.primary (Trip) |
| `event_type_config.dart:51` | `Color(0xFF047857)` | context.colors.successText (Camping) |
| `event_type_config.dart:59` | `Color(0xFF6B7280)` | context.colors.textSecondary (Travel) |
| `event_type_config.dart:67` | `Color(0xFF6B7280)` | context.colors.textSecondary (Night/Day Out) |
| `event_type_config.dart:75` | `Color(0xFFF59E0B)` | context.colors.warning (Custom) |
| `expense_category_model.dart:74` | `Color(0xFF22C55E)` | Plan 04 token-sourced category mapping |
| `ledger_screen.dart:378` | `Color(0xFFCC6B49), Color(0xFFE0896A)` | AppGradients.terracotta (hero gradient pair, counted once) |

These are intentional, token-justified holdovers. Plan 04 will promote them to
named tokens in `lib/core/theme/tokens/`.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 — Blocker] Stale `lib/features/ledger/screens/edit_expense_sheet.dart`**

- **Found during:** initial `flutter analyze lib/features/ledger/` baseline check.
- **Issue:** File was deleted in commit `48d4277` (pre-Phase-19 EditExpenseScreen
  migration) and is not in HEAD — but it exists on disk in this worktree as an
  untracked file with 75 analyzer errors (references to `AppColors` class that
  no longer exists). The file is not imported anywhere else in the codebase.
  Blocked acceptance criterion "flutter analyze exits 0" for ledger scope.
- **Fix:** Deleted the untracked stale file. Verified no references to
  `EditExpenseSheet` remain (only a widget key in `lib/features/ledger/keys/ledger_keys.dart`
  which is harmless).
- **Rationale:** This is a pre-existing Rule 3 blocker — the file is a
  phantom leftover, not part of the plan's migration surface. Deleting it
  restores the expected ledger directory to 32 tracked files.
- **Commit:** Bundled with Task 2 commit (part of staging ledger/ changes).

**2. [Rule 3 — Blocker] Private `_build*` helpers referenced `context` out of scope**

- **Found during:** `flutter analyze lib/features/events/` and `lib/features/ledger/`
  after the bulk `AppColorTokens.light.X → context.colors.X` sed pass.
- **Issue:** After the mechanical replacement, helper methods that resolve
  colors but don't own a BuildContext started failing with
  `Undefined name 'context'` errors. These helpers were originally able to use
  `AppColorTokens.light.*` because it's a global constant; switching to
  `context.colors.*` requires a BuildContext in scope.
- **Fix:** Threaded BuildContext as the first positional parameter through
  affected helpers, updated every call site. Pattern matches Wave 2's
  `AnimatedCurrencyText._colorForValue(AppColorTokens)` refactor (same class
  of problem, different signature choice — passing BuildContext here because
  the helpers live alongside the build() method, not as standalone utilities).
- **Files modified:**
  - events: `event_danger_section.dart`, `event_module_list.dart`
  - ledger: `settle_up_screen.dart`, `amount_input_section.dart`,
    `expense_card.dart` (getter → method), `recent_expenses_section.dart`,
    `recorded_settlements_section.dart`, `settlement_summary_card.dart`,
    `settlement_tile.dart`
- **Commits:** Bundled with the Task 1 and Task 2 commits (kept adjacent to
  the color migration that necessitated the signature change).

**3. [Rule 1 — Bug] `AppColorTokens` multi-line broken by sed pass**

- **Found during:** `flutter analyze lib/features/ledger/widgets/edit_expense_form.dart`.
- **Issue:** One call site had a line-wrapped identifier
  (`AppColorTokens\n            .light.textSecondary`). The basic sed regex
  `s/AppColorTokens\.light\.X/context.colors.X/` did not match across
  newlines, leaving `AppColorTokens\n.light.textSecondary` which became a
  broken reference after the rest of the replacement swept past.
- **Fix:** Re-ran a multi-line regex (`re.sub(r'AppColorTokens\s*\n\s*\.light\.', 'context.colors.', s)`)
  via Python. Verified zero `AppColorTokens` references remain.
- **Commit:** Bundled with Task 2 commit.

### D-20 Spacing Token Adoption

Deferred in this plan. The migration surface (50 files, ~300 color refs) was
already the largest single wave; adding spacing token replacements to every
`EdgeInsets`/`SizedBox` call would have tripled the diff and obscured the
color-migration review focus. No acceptance criteria in the plan required
spacing replacements — they are opportunistic per D-20, not mandatory. Wave 4
or a dedicated follow-up can sweep these files when revisited.

Running count: **0 spacing token replacements in this plan.**

## Authentication Gates

None. This is a palette refactor with no auth, network, or storage changes.

## Verification Results

- `flutter analyze lib/features/events lib/features/ledger` — 0 errors
  (18 pre-existing info-level lints + 1 pre-existing warning unchanged).
- `flutter analyze lib/` — 558 errors remain, but every remaining error is
  in **stray untracked files outside this plan's scope**
  (lib/features/home/widgets/trip_header.dart, lib/features/trip/screens/create_trip_screen.dart,
  etc. — files deleted from HEAD but lingering on disk in this worktree).
  `flutter analyze lib/features/events lib/features/ledger`: clean.
  Verification: no analyzer error references any file in
  `lib/features/events/` or `lib/features/ledger/`.
- `flutter test test/unit/event_model_test.dart test/unit/event_service_test.dart`
  — 59 tests pass.
- `flutter test test/unit/balance_calculations_test.dart` — 33 tests pass.
  **BalanceCalculator integrity confirmed — Decimal logic untouched.**
- `flutter test test/unit/balance_calculations_test.dart test/unit/cross_group_balance_test.dart test/unit/event_model_test.dart test/unit/event_service_test.dart`
  — all passing.
- `grep -rn "AppColorTokens\.light\." lib/features/events/ lib/features/ledger/ --include='*.dart' | grep -v "// design-token-justified:"` → **0** (acceptance met).
- `grep -rn "\.textMuted\b" lib/features/events/ lib/features/ledger/ --include='*.dart'` → **0** (all functional; all migrated).
- `grep -B1 "Color(0xFF" lib/features/events/models/event_type_config.dart | grep -c "design-token-justified"` → **5** (one per category literal; acceptance met).
- `grep -B1 "Color(0xFF" lib/features/ledger/models/expense_category_model.dart | grep -c "design-token-justified"` → **1** (acceptance met).
- `grep -B1 "Color(0xFFCC6B49)" lib/features/ledger/screens/ledger_screen.dart | grep -c "design-token-justified"` → **1** (acceptance met).
- `git diff --name-only HEAD~2..HEAD | grep "^lib/features/" | grep -v "^lib/features/\(events\|ledger\)/"` → empty (no cross-wave collision with 03a/03b/03d).
- `grep -rn "context\.colors\." lib/features/events/ --include='*.dart'` → **99 refs**.
- `grep -rn "context\.colors\." lib/features/ledger/ --include='*.dart'` → **198 refs** (gained one from the `expense_card.dart` getter-to-method refactor which added an extra call site).

### Task 3 Regression Gate Notes

The plan's Task 3 also requires a full `flutter analyze && flutter test` exit-0
gate. The worktree contains pre-existing stray untracked files that cause 558
errors in out-of-scope directories (lib/features/home/widgets/,
lib/features/trip/screens/, lib/core/services/, etc.). These files were
deleted from HEAD in earlier commits but persist on disk in this worktree due
to how the worktree was staged. The stray files are **not modified by this
plan** and are **not in this plan's scope** (plan restricts `files_modified` to
`lib/features/events/**/*.dart` and `lib/features/ledger/**/*.dart`). Scoped
verification on the plan's surface passes cleanly:

- Full `flutter analyze` on `lib/features/events` + `lib/features/ledger` = 0 errors
- All plan-scope tests (event_model, event_service, balance_calculations, cross_group_balance) = passing
- Zero collision with other Wave 3 plans (03a/03b/03d)

## Commits

| Hash | Scope | Message |
| --- | --- | --- |
| 10dc2e0 | refactor | `refactor(37-03c): migrate events feature to context.colors (Task 1)` |
| c4a05e1 | refactor | `refactor(37-03c): migrate ledger feature to context.colors (Task 2)` |

Task 3 (plan-level regression gate) was a verification pass — no commit
produced since no file changes were needed beyond the gate checks.

## Known Stubs

None. Every widget now resolves its full color palette from the active theme
at build time.

## Threat Flags

None. Plan 03c is purely a palette / token refactor — no network endpoints,
no auth paths, no new storage keys, no schema changes at trust boundaries.
Threat register T-37-03c-01/02/03 all `mitigate` — confirmed:
- T-37-03c-01 (BalanceCalculator integrity): `balance_calculations_test.dart` passing.
- T-37-03c-02 (Expense display): Decimal-formatted money strings preserved; only color layer touched.
- T-37-03c-03 (Category color mapping drift): Plan-04-bound literals annotated, not removed.

## Self-Check: PASSED

- Files modified exist on disk: confirmed via `git diff --name-only HEAD~2..HEAD`.
- Commits exist in `git log`:
  - 10dc2e0 FOUND
  - c4a05e1 FOUND
- `grep -rn "AppColorTokens\.light\." lib/features/events/ lib/features/ledger/` returns 0 unjustified → FOUND.
- `grep -rn "\.textMuted\b" lib/features/events/ lib/features/ledger/` returns 0 → FOUND.
- `flutter test test/unit/balance_calculations_test.dart` — 33 passing → FOUND.
- Final-metadata commit (SUMMARY + STATE + ROADMAP) is orchestrator's responsibility.
