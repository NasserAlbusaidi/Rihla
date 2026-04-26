---
phase: 37-dark-theme-migration
plan: 03b
subsystem: groups-feature-theme-migration
tags: [theme, dark-mode, migration, features, groups, wave-3]
requires:
  - Wave 1 foundation (AppTheme.darkTheme + AppColorTokens.dark + context.colors extension)
  - Wave 2 shared widgets migrated (shared-widget layer reads from context.*)
provides:
  - Groups feature (32 .dart files) fully theme-aware via context.colors
  - All standard shadow reads in groups/ migrated from
    AppShadowTokens.standard → context.shadows (opportunistic)
  - Seven opportunistic AppSpacingTokens.standard → context.spacing
    replacements in two touched files (group_detail_screen,
    group_member_balance_card)
  - group_card.dart avatar slot palette (5 literals) flagged with
    design-token-justified comments for Plan 04 handoff
  - textMuted decorative-kept call sites documented with
    textMuted-decorative-justified comments per D-11
affects:
  - Wave 3a/3c/3d parallel plans — groups/ done means dashboard and
    group-detail surfaces render correctly in dark mode without waiting
    on sibling features
  - Plan 04 (Wave 4 token cleanup) — 5 avatar slot literals in
    group_card.dart are pre-annotated, ready for
    AppGroupAvatarColors.lightSlots/darkSlots migration
tech-stack:
  added: []
  patterns:
    - "context.colors.* over AppColorTokens.light.* — theme-aware reads"
    - "context.shadows.raised over AppShadowTokens.standard.raised"
    - "context.spacing.spaceN over AppSpacingTokens.standard.spaceN"
    - "BuildContext parameter added to private color-resolving helpers"
    - "textMuted-decorative-justified comments for separator/affordance icons"
    - "design-token-justified comments for Plan 04 handoff literals"
key-files:
  created: []
  modified:
    - lib/features/groups/screens/create_group_screen.dart
    - lib/features/groups/screens/group_activity_screen.dart
    - lib/features/groups/screens/group_detail_screen.dart
    - lib/features/groups/screens/group_settings_screen.dart
    - lib/features/groups/screens/group_settle_up_screen.dart
    - lib/features/groups/screens/join_group_screen.dart
    - lib/features/groups/widgets/all_settled_state.dart
    - lib/features/groups/widgets/group_activity_tile.dart
    - lib/features/groups/widgets/group_balance_hero.dart
    - lib/features/groups/widgets/group_card.dart
    - lib/features/groups/widgets/group_danger_section.dart
    - lib/features/groups/widgets/group_info_section.dart
    - lib/features/groups/widgets/group_member_balance_card.dart
    - lib/features/groups/widgets/group_member_tile.dart
    - lib/features/groups/widgets/group_members_section.dart
    - lib/features/groups/widgets/group_settlement_summary.dart
    - lib/features/groups/widgets/group_settlement_tile.dart
    - lib/features/groups/widgets/group_spending_stats.dart
    - lib/features/groups/widgets/group_stats_grid.dart
    - lib/features/groups/widgets/invite_code_display.dart
    - lib/features/groups/widgets/record_payment_sheet.dart
    - lib/features/groups/widgets/settle_up_history_tab.dart
    - lib/features/groups/widgets/settlement_tab_content.dart
decisions:
  - "Task 2 (providers/services/models) was a no-op — scout grep confirmed
    0 AppColorTokens refs and 0 textMuted refs across all non-UI subdirs
    of groups/. Verification ran clean; no commit created per 'no empty
    commits' rule."
  - "group_activity_tile._iconColorAndLabel refactored to accept
    BuildContext. The 5 'event_created/deleted/member_joined/left/_'
    arms share a single mutedTint local, making the justification comment
    apply to all 5 in one place."
  - "group_danger_section._buildSectionHeader and
    group_members_section._buildSectionHeader + _buildCreatorBadge all
    gained BuildContext parameters. These were previously bare methods
    on the widget class with no access to context."
  - "6 textMuted references kept as decorative (group_card event-type
    glyph, 2x settlement-tile arrow/chevron, 2x member-balance-card
    chevrons, 1x activity-tile icon-tint helper). The remaining 14+6=20
    original textMuted-on-functional-text refs all migrated to
    textSecondary. 6/6 decorative retentions have preceding
    textMuted-decorative-justified comments per D-11."
  - "group_card.dart avatar slot palette (5 Color(0xFF...) literals,
    lines 45-55 after migration) annotated with 5 matching
    design-token-justified comments pending Plan 04. Accent strip
    hash-assignment logic preserved unchanged — only the palette
    definition gained the handoff markers."
  - "Card radius in group_card.dart (originally BorderRadius.circular(16))
    mapped to context.spacing.radiusLarge (16dp) not radiusMedium (12dp)
    to preserve the visual design."
  - "Seven opportunistic AppSpacingTokens.standard.* → context.spacing.*
    replacements made in group_detail_screen.dart (5) and
    group_member_balance_card.dart (2). The 4 sites using
    `const spacing = AppSpacingTokens.standard;` local aliases
    (group_settlement_tile, record_payment_sheet, settle_up_history_tab
    [2x]) were left untouched — they're not color-theme reads, and per
    D-20 spacing adoption is opportunistic not mandatory."
metrics:
  tasks_completed: 3
  tasks_planned: 3
  files_modified_src: 23
  files_modified_tests: 0
  commits: 1
  duration_minutes: ~30
  color_refs_migrated: 231
  shadow_refs_migrated: 10
  spacing_refs_migrated: 7
  text_muted_migrated_to_secondary: 14
  text_muted_kept_with_justification: 6
  avatar_literals_annotated: 5
completed: 2026-04-18
---

# Phase 37 Plan 03b: Groups Feature Theme Migration Summary

Migrated every color, shadow, and opportunistic spacing read in
`lib/features/groups/` (32 .dart files, 23 with color/shadow refs and
17 touched for the color migration alone) from direct
`AppColorTokens.light.*` / `AppShadowTokens.standard.*` reads to
theme-aware `context.colors.*` / `context.shadows.*`. Heaviest
single-plan migration in the phase — originally 231 color refs, 28
textMuted refs, 5 avatar-slot literals.

## What Got Built

### Color Migration — screens/ (6 files, 51 refs)

| File | Refs migrated | textMuted in-file disposition |
| --- | --- | --- |
| `create_group_screen.dart` | 3 | n/a (no textMuted) |
| `group_activity_screen.dart` | 12 | 1 functional → textSecondary |
| `group_detail_screen.dart` | 19 | 5 functional → textSecondary |
| `group_settings_screen.dart` | 8 | n/a |
| `group_settle_up_screen.dart` | 7 | n/a |
| `join_group_screen.dart` | 2 | n/a |

### Color Migration — widgets/ (17 files, 180 refs)

| File | Refs migrated | textMuted in-file disposition |
| --- | --- | --- |
| `all_settled_state.dart` | 4 | 1 functional → textSecondary |
| `group_activity_tile.dart` | 12 | 1 functional → textSecondary + 1 decorative-kept (icon-tint helper, justified) |
| `group_balance_hero.dart` | 6 | n/a |
| `group_card.dart` | 17 | 1 decorative-kept (event-type glyph, justified) |
| `group_danger_section.dart` | 18 | n/a |
| `group_info_section.dart` | 27 | n/a |
| `group_member_balance_card.dart` | 18 | 1 functional → textSecondary + 2 decorative-kept (chevrons, justified) |
| `group_member_tile.dart` | 4 | n/a |
| `group_members_section.dart` | 8 | n/a |
| `group_settlement_summary.dart` | 6 | 2 functional → textSecondary |
| `group_settlement_tile.dart` | 21 | 2 decorative-kept (arrow + chevron, justified) |
| `group_spending_stats.dart` | 3 | n/a |
| `group_stats_grid.dart` | 9 | 1 functional → textSecondary |
| `invite_code_display.dart` | 2 | n/a |
| `record_payment_sheet.dart` | 12 | 1 functional → textSecondary |
| `settle_up_history_tab.dart` | 12 | 1 functional → textSecondary |
| `settlement_tab_content.dart` | 1 | n/a |

### Shadow Migration

10 `AppShadowTokens.standard.raised` + 1 `AppShadowTokens.standard.floating`
reads migrated to `context.shadows.raised` / `context.shadows.floating`
across `group_card.dart`, `group_info_section.dart`,
`group_settlement_tile.dart` (2), `group_members_section.dart`,
`group_danger_section.dart`, `group_activity_tile.dart`,
`settle_up_history_tab.dart`, `group_settlement_summary.dart`,
`create_group_screen.dart`, `join_group_screen.dart`.

### Avatar Slot Palette Handoff (group_card.dart)

5 hardcoded `Color(0xFF...)` literals in the static `_accentColors`
list (lines 45-55) preserved for Plan 04 promotion. Each now has a
matching `// design-token-justified: avatar slot N — pending Plan 04
AppGroupAvatarColors.lightSlots[N]` comment directly above.

| Slot | Literal | Intended token |
| --- | --- | --- |
| 0 | `Color(0xFF0D7B74)` | AppGroupAvatarColors.lightSlots[0] — primary teal |
| 1 | `Color(0xFFCC6B49)` | AppGroupAvatarColors.lightSlots[1] — terracotta |
| 2 | `Color(0xFF10B981)` | AppGroupAvatarColors.lightSlots[2] — success emerald |
| 3 | `Color(0xFFF59E0B)` | AppGroupAvatarColors.lightSlots[3] — warning amber |
| 4 | `Color(0xFF7C6E5A)` | AppGroupAvatarColors.lightSlots[4] — warm umber |

### Helper Refactors (BuildContext parameter added)

- `group_activity_tile._iconColorAndLabel(BuildContext, String)` —
  previously `_iconColorAndLabel(String)`; now resolves 5 activity-type
  icon tints + the primary-teal settlement tint via context.colors.
- `group_danger_section._buildSectionHeader(BuildContext)` — previously
  bare; now reads errorText for the warning-2 icon + label.
- `group_members_section._buildSectionHeader(BuildContext)` + 
  `_buildCreatorBadge(BuildContext)` — previously bare; now read
  textSecondary + selectionFill + primary.

### Opportunistic Spacing Migration

7 inline `AppSpacingTokens.standard.*` refs → `context.spacing.*` in
`group_detail_screen.dart` (5 refs: 2×buttonHeight, 3×radiusMedium) and
`group_member_balance_card.dart` (2 refs: radiusLarge). Unused
`spacing_tokens.dart` imports dropped from both files.

Four files with `const spacing = AppSpacingTokens.standard;` local
aliases (`group_settlement_tile`, `record_payment_sheet`,
`settle_up_history_tab` at 2 lines) were left untouched — D-20
opportunistic rule, these aren't color reads.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 — Blocker] Private helpers referencing `context.colors` outside
`build()` scope**

- **Found during:** Task 1, after the mechanical `AppColorTokens.light.X
  → context.colors.X` substitution.
- **Issue:** Three widget files had private helper methods that read
  color tokens directly but had no BuildContext parameter. After the
  substitution, `context.colors.*` inside those methods failed to
  resolve (`Undefined name 'context'` errors from the analyzer).
  - `group_activity_tile._iconColorAndLabel(String type)` — 6 refs
  - `group_danger_section._buildSectionHeader()` — 2 refs
  - `group_members_section._buildSectionHeader()` + `_buildCreatorBadge()` — 4 refs
- **Fix:** Added `BuildContext context` as the first parameter to each
  helper and threaded it through from the `build(context)` caller.
  Zero callers outside `build()` exist, so the change is internal.
- **Files modified:** 3 (group_activity_tile, group_danger_section,
  group_members_section).
- **Commit:** Bundled with Task 1 commit `fff1363`.
- **Rationale:** This matches the pattern Wave 2 used for
  `AnimatedCurrencyText._colorForValue` (helper accepts tokens) — here
  we pass BuildContext because it's available at every call site.

**2. [Rule 2 — Critical] textMuted decorative-kept sites lacked
justification comments**

- **Found during:** Task 1 post-migration triage.
- **Issue:** 6 remaining `context.colors.textMuted` reads are
  legitimate decorative uses (separator arrows, expand/collapse
  chevrons, icon-tint helper in activity tile, event-type glyph in
  group card) but lacked the `// textMuted-decorative-justified:`
  preceding comment required by D-11 and checked by the Wave 5 CI
  guard.
- **Fix:** Added 5 preceding justification comments (group_card.dart
  already had one from the migration write; group_activity_tile.dart's
  3-line block comment covers the mutedTint local).
- **Files modified:** 4 (group_card, group_settlement_tile,
  group_member_balance_card, group_activity_tile).
- **Commit:** Bundled with Task 1 commit `fff1363`.

**3. [Rule 3 — Scope clarification] Task 2 is a no-op**

- **Found during:** Task 2 entry scouting.
- **Issue:** Plan describes a "Refactor pattern for stateless Color
  providers" for `providers/`, `services/`, `models/`, and mentions
  possible cascade compile errors. Scout grep showed
  `AppColorTokens.light.` count = 0, `textMuted` count = 0, and
  `material.dart` imports = 1 (keys file only). There is no
  Color-returning helper to refactor in these subdirs.
- **Fix:** Verification-only. No file changes, no commit created.
- **Files modified:** none.
- **Rationale:** Plan anticipated "typically ... FEWER color refs"; the
  actual count in this codebase is zero.

### textMuted Triage (per D-11)

| Disposition | Count | Files |
| --- | --- | --- |
| Functional → `textSecondary` | 14 | group_detail_screen (5), group_activity_screen (1), group_settlement_summary (2), all_settled_state (1), group_member_balance_card (1), group_stats_grid (1), record_payment_sheet (1), settle_up_history_tab (1), group_activity_tile (1) |
| Decorative kept + justified | 6 | group_settlement_tile (2: separator arrow, expand chevron), group_member_balance_card (2: expand + trailing chevrons), group_card (1: event-type glyph), group_activity_tile (1: mutedTint helper local) |
| **Total original refs** | **20** | — |

Note: The original "28 textMuted refs" count from the plan included 8
references inside comments / docstrings (e.g.
`/// - event_created: [Iconsax.calendar_add] (textMuted)` lines in
`group_activity_tile.dart`). Actual code call-site refs = 20. All 20
accounted for.

### design-token-justified exemptions added

| File | Count | Reason |
| --- | --- | --- |
| `group_card.dart` (static `_accentColors` list) | 5 | Avatar slot palette — Plan 04 handoff to AppGroupAvatarColors |

### textMuted-decorative-justified exemptions added

| File:line | Element | Reason |
| --- | --- | --- |
| `group_settlement_tile.dart:139` | ' → ' TextSpan | arrow glyph connecting payer → payee names, purely visual separator |
| `group_settlement_tile.dart:189` | `Iconsax.arrow_down_1` | expand/collapse chevron affordance — meaning carried by the state change |
| `group_card.dart:220` | event-type Icon | event type glyph in subtitle row, functional color carried by adjacent text |
| `group_member_balance_card.dart:200` | `Iconsax.arrow_down_1` | expand/collapse chevron affordance |
| `group_member_balance_card.dart:283` | `Iconsax.arrow_right_3` | trailing chevron indicating tappable row, redundant with the gesture handler |
| `group_activity_tile.dart:136-138` | `mutedTint` local (applies to 5 switch arms + a default) | activity-type glyph tint — semantic meaning carried by text + semanticsLabel, icon recedes visually |

## Authentication Gates

None. Plan 03b is a palette refactor — no auth / network code touched.

## Verification Results

Task 1 acceptance criteria:
- `flutter analyze` exits 0 — PASS (1 pre-existing unused-local warning
  in `group_balance_provider.dart:142`, out of scope)
- `grep -rn "AppColorTokens\.light\." lib/features/groups/screens/
  lib/features/groups/widgets/ --include='*.dart' | grep -v "//
  design-token-justified:" | wc -l` returns `0` — PASS
- `grep -B1 "Color(0xFF" lib/features/groups/widgets/group_card.dart |
  grep -c "design-token-justified"` returns `5` — PASS
- Every remaining textMuted reference has
  `// textMuted-decorative-justified:` comment on prior line — PASS (6/6)
- `flutter test test/unit/` exits 0 — PASS (578 pass, 3 skip)

Task 2 acceptance criteria:
- `flutter analyze` exits 0 — PASS
- `grep -rn "AppColorTokens\.light\." lib/features/groups/providers/
  lib/features/groups/services/ lib/features/groups/models/
  --include='*.dart'` returns `0` — PASS (was 0 from the start)
- `flutter test test/unit/` exits 0 — PASS

Task 3 plan-level regression gate:
- `flutter analyze` exits 0 — PASS (347 info/warning lints, all
  pre-existing; 0 errors)
- `flutter test` exits 0 — PASS (1056 pass, 3 skip, 0 fail)
- `grep -rn "AppColorTokens\.light\." lib/features/groups/
  --include='*.dart' | grep -v "// design-token-justified:" | wc -l`
  returns `0` — PASS
- `git diff --name-only HEAD~1 HEAD | grep "^lib/features/" | grep -v
  "^lib/features/groups/"` returns empty — PASS (no sibling-wave
  collision)
- `grep -rB1 "\.textMuted" lib/features/groups/ --include='*.dart' |
  grep -c "textMuted-decorative-justified"` = 5 via single-line check,
  6 via multi-line check (group_activity_tile's block comment spans
  3 lines above the local). All 6 decorative-kept sites have preceding
  justification.

## Commits

| Hash | Scope | Message |
| --- | --- | --- |
| fff1363 | refactor | migrate groups screens + widgets to context.colors (bundled Task 1 body + deviations 1 & 2) |

Task 2 produced no changes (scout confirmed 0 refs in non-UI subdirs);
Task 3 is a verification-only gate with no code output. Per plan "no
empty commits" rule, only one commit was created.

## Known Stubs

None. Every widget now resolves its full color palette from the active
theme at build time. The 5 avatar slot literals in `group_card.dart`
are intentional, plan-specified Plan 04 handoff markers — not stubs.

## Threat Flags

None. Plan 03b is purely a palette/token refactor — no network
endpoints, no auth paths, no new storage keys, no schema changes at
trust boundaries.

## Self-Check: PASSED

- Commits exist in `git log --all`:
  - `fff1363` FOUND
- `grep -rn "AppColorTokens\.light\." lib/features/groups/
  --include='*.dart' | grep -v "// design-token-justified:"` returns 0 — FOUND
- `grep -rn "AppShadowTokens" lib/features/groups/ --include='*.dart'`
  returns 0 — FOUND
- `flutter analyze` final status: 0 errors — FOUND
- `flutter test` final status: "All tests passed!" (1056 tests, 3 skip) — FOUND
- Final-metadata commit (SUMMARY + STATE + ROADMAP) is orchestrator's
  responsibility.
