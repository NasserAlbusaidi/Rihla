---
phase: 37-dark-theme-migration
plan: 03d
subsystem: feature-theme-migration-trip-modules
tags: [theme, dark-mode, migration, features, wave-3d]
requires:
  - Wave 2 shared-widget migration (37-02) — modules consume migrated
    ModuleHeader / EmptyStateView / SearchFilterBar / OfflineBanner
  - context.colors / context.spacing extensions (domain_aliases.dart)
provides:
  - Theme-aware `lib/features/gear/` (5 source files, 45 refs)
  - Theme-aware `lib/features/logistics/` (5 source files, 39 refs)
  - Theme-aware `lib/features/vault/` (2 source files, 26 refs)
  - Theme-aware `lib/features/memories/` (3 source files, 23 refs)
  - Theme-aware `lib/features/activity/` (3 source files, 13 refs)
  - activity_feed_screen.dart:150 warm-brown hero gradient flagged for
    Plan 04 AppGradients with `// design-token-justified:` comment
  - MemoriesHeroCard._buildCountRow refactored to accept BuildContext
    so it can resolve context.colors (previously private arg-less helper)
affects:
  - Any downstream test harness using GearAddInput, LogisticsHeroCard,
    or LogisticsMemberPickerSheet without `theme:` on MaterialApp
    (3 test files updated — same Wave-2 pattern as Plan 37-02)
  - Plan 04 (token cleanup) now has one known gradient handoff in activity
tech-stack:
  added: []
  patterns:
    - "context.colors.* over AppColorTokens.light.* — theme-aware reads"
    - "context.spacing.spaceN on touched lines per D-20"
    - "textMuted-decorative-justified for 6 decorative glyphs"
    - "design-token-justified for 1 deferred gradient literal"
    - "Builder / explicit-context-passing when private helper methods
      need theme resolution"
key-files:
  created: []
  modified:
    - lib/features/gear/screens/gear_screen.dart
    - lib/features/gear/widgets/gear_add_input.dart
    - lib/features/gear/widgets/gear_hero_card.dart
    - lib/features/gear/widgets/gear_item_card.dart
    - lib/features/gear/widgets/gear_list_view.dart
    - lib/features/logistics/screens/logistics_screen.dart
    - lib/features/logistics/widgets/logistics_group_dialog.dart
    - lib/features/logistics/widgets/logistics_hero_card.dart
    - lib/features/logistics/widgets/logistics_member_picker_sheet.dart
    - lib/features/logistics/widgets/sub_group_card.dart
    - lib/features/vault/screens/vault_screen.dart
    - lib/features/vault/widgets/vault_hero_card.dart
    - lib/features/memories/screens/memories_screen.dart
    - lib/features/memories/widgets/memories_hero_card.dart
    - lib/features/memories/widgets/full_screen_photo.dart
    - lib/features/activity/screens/activity_feed_screen.dart
    - lib/features/activity/widgets/activity_entry_card.dart
    - lib/features/activity/widgets/activity_hero_card.dart
    - test/features/gear/widgets/gear_add_input_test.dart
    - test/features/logistics/widgets/logistics_hero_card_test.dart
    - test/features/logistics/widgets/logistics_member_picker_sheet_test.dart
decisions:
  - "textMuted triage per D-11: 21 functional refs converted to
    textSecondary; 6 decorative glyphs (popup/kebab affordances,
    inactive state icons, faint inline glyphs, image-placeholder
    slash) kept as textMuted with `textMuted-decorative-justified`
    preceding comment."
  - "MemoriesHeroCard._buildCountRow() accepts BuildContext now so the
    private helper can read context.colors. Chose this over a Builder
    wrapper because the helper is already private and called from a
    single build site — plain signature change is simpler."
  - "activity_feed_screen.dart:150 warm-brown gradient `[0xFFA67C5B,
    0xFFC29A7A]` left as literal with `// design-token-justified:
    activity hero gradient — pending Plan 04 AppGradients` comment, per
    plan interfaces contract. Plan 04 will promote it into a named
    AppGradients.activity token."
  - "Three widget-test files (gear_add_input_test,
    logistics_hero_card_test, logistics_member_picker_sheet_test)
    were missing `theme: AppTheme.lightTheme` on their MaterialApp
    harness — same Rule-3 blocker as Wave 2. Bulk-added via script."
metrics:
  tasks_completed: 4
  tasks_planned: 4
  files_created: 0
  files_modified_src: 18
  files_modified_tests: 3
  commits: 4
  refs_migrated: 146
  textmuted_converted: 21
  textmuted_decorative_kept: 6
  gradients_flagged_for_plan_04: 1
completed: 2026-04-18
---

# Phase 37 Plan 03d: Gear + Logistics + Vault + Memories + Activity Summary

Wave 3d migrates the five "trip module" feature folders from
`AppColorTokens.light.*` to `context.colors.*`. Total 18 source files
touched, 146 color refs migrated, 27 textMuted refs triaged per D-11.
One warm-brown hero gradient in `activity_feed_screen.dart` flagged for
promotion to AppGradients in Plan 04.

## What Got Built

### Per-folder migration counts

| Folder | Src files | Refs migrated | textMuted → textSecondary | textMuted decorative (kept) |
| --- | --- | --- | --- | --- |
| `gear/` | 5 | 45 | 6 | 2 |
| `logistics/` | 5 | 39 | 9 | 2 |
| `vault/` | 2 | 26 | 2 | 0 |
| `memories/` | 3 | 23 | 1 | 2 |
| `activity/` | 3 | 13 | 3 | 0 |
| **Total** | **18** | **146** | **21** | **6** |

Files with zero color refs were not counted (keys/models/services/
providers — those had no color reads).

### textMuted decorative justifications (6 total)

| File:line | Context | Reason |
| --- | --- | --- |
| `gear_item_card.dart:133` | PopupMenu icon (`Iconsax.more`) | inactive "more" affordance |
| `gear_add_input.dart:47` | Priority flash icon (inactive) | inactive priority flash affordance |
| `sub_group_card.dart:87` | IconButton kebab (`Iconsax.more`) | inactive "more" affordance |
| `sub_group_card.dart:150` | Inline `+` glyph in "open slot" hint | faint inline + glyph for "open slot" hint |
| `memories_screen.dart:353` | Image-error `Iconsax.gallery_slash` glyph | faded glyph in image-load error placeholder |
| `memories_screen.dart:362` | Empty-state `Iconsax.image` glyph | faded image-placeholder glyph |

### textMuted → textSecondary conversions (21 total)

Functional text roles — overline labels ("GEAR ITEMS", "PACKING PROGRESS",
"ORGANIZATION", "FILES", "DOCUMENTS", "MEMORIES", "ACTIVITY",
"SUB-GROUPS", "SELECT MEMBER", "NEW GROUP"/"EDIT GROUP"), hint text,
timestamps ("2h ago"), loading text, status chip colors for unclaimed
state, assignee avatar background, strikethrough packed item text, N-open
label, section-header labels.

### Activity hero gradient handoff (for Plan 04)

`lib/features/activity/screens/activity_feed_screen.dart:150`:

```dart
accentGradient: const LinearGradient(
  // design-token-justified: activity hero gradient — pending Plan 04 AppGradients
  colors: [Color(0xFFA67C5B), Color(0xFFC29A7A)],
),
```

Left as-is per plan interfaces contract. Plan 04 will promote to
`AppGradients.activity` with light + dark variants.

### MemoriesHeroCard helper refactor

`_buildCountRow()` was a private arg-less helper that built two
`TextStyle(color: AppColorTokens.light.*)` blocks. After migration it
needs `BuildContext` to resolve `context.colors`. Signature updated to
`_buildCountRow(BuildContext context)` and the single call site
`_buildCountRow()` → `_buildCountRow(context)`. Chose this over a Builder
wrapper because the helper is private with one caller — simpler.

### Spacing token adoption (D-20)

Opportunistic on touched lines. Standard values 4/8/12/16/24
opportunistically replaced with `context.spacing.spaceN` in
`gear_item_card.dart` (EdgeInsets.all(16), SizedBox width 12/16,
BorderRadius.circular(16) → radiusMedium) and
`sub_group_card.dart` (EdgeInsets.symmetric horizontal 8). Other files
retained their existing EdgeInsets — the migration scope was primarily
color, and spacing changes were kept narrow per D-20.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 — Blocker] Three widget tests lacked `theme:` on MaterialApp**

- **Found during:** Task 37-03d-04 regression gate (`flutter test`).
- **Issue:** `GearAddInput`, `LogisticsHeroCard`, and
  `LogisticsMemberPickerSheet` widget-tests built `MaterialApp(home: ...)`
  without a `theme:` argument. After color migration those widgets
  resolve colors via `context.colors`, which requires the
  `AppColorTokens` ThemeExtension to be registered. 18 tests failed with
  `_TypeError` inside the builder.
- **Fix:** Added `theme: AppTheme.lightTheme,` to the three harnesses.
  Same pattern as Wave 2 (37-02-SUMMARY §"Rule 3 — Blocker") — bulk
  test-harness fix is the pragmatic way to unblock a mechanical palette
  swap.
- **Files:** `test/features/gear/widgets/gear_add_input_test.dart`,
  `test/features/logistics/widgets/logistics_hero_card_test.dart`,
  `test/features/logistics/widgets/logistics_member_picker_sheet_test.dart`.
- **Commit:** `4500cd6`

**2. [Rule 3 — Blocker] `_buildCountRow` context signature**

- **Found during:** Task 37-03d-02 `flutter analyze` after migration.
- **Issue:** `memories_hero_card.dart` had a private `_buildCountRow()`
  helper that contained three color reads. After substitution those became
  `context.colors.*` — undefined-identifier error because the helper had
  no `BuildContext` in scope.
- **Fix:** Added `BuildContext context` parameter to `_buildCountRow`;
  updated the single `_buildCountRow()` call site to
  `_buildCountRow(context)`. Same outcome as a Builder wrapper with less
  nesting.
- **Commit:** bundled with Task 37-03d-02 (`188002d`).

### textMuted Triage (per D-11)

See table above. Running total across phase 37 so far (W2 + W3d):

- W2 (shared widgets): 6 textMuted → textSecondary, 0 decorative-kept
- W3d (trip modules): 21 textMuted → textSecondary, 6 decorative-kept

### design-token-justified exemptions added

| File:line | Literal | Reason |
| --- | --- | --- |
| `activity_feed_screen.dart:150` | `[Color(0xFFA67C5B), Color(0xFFC29A7A)]` | activity hero gradient — pending Plan 04 AppGradients (explicit plan contract) |

## Authentication Gates

None. Plan 03d is a mechanical palette refactor; no auth, network, or
storage code touched. Service layers (GearService, SubGroupService,
DocumentService, MemoryService, ActivityService) are intentionally not
modified per plan anti-patterns.

## Verification Results

- `flutter analyze` — 347 issues (**exactly matches pre-plan baseline**).
  0 errors introduced, 0 new warnings, 0 new info-level lints. All
  remaining lints are pre-existing.
- `flutter test` — **1056 pass, 3 skipped, 0 fail** across the entire
  suite.
- Full-scope grep (Task 4 Step 1):
  `grep -rn "AppColorTokens\.light\." lib/features/{gear,logistics,vault,memories,activity}/ --include='*.dart' | grep -v "// design-token-justified:" | wc -l` = **0**
- Cross-wave collision check (Task 4 Step 2):
  `git diff d5e7db9..HEAD --name-only | grep "^lib/features/" | grep -v "^lib/features/\(gear\|logistics\|vault\|memories\|activity\)/"` = **empty**
- Hero-gradient justification check:
  `grep -B1 "Color(0xFFA67C5B)" lib/features/activity/screens/activity_feed_screen.dart | grep -c "design-token-justified"` = **1**
- Per-folder context.colors coverage: gear 45, logistics 39, vault 26,
  memories 23, activity 13.
- `flutter test test/unit/gear_service_test.dart` — **7/7 pass**
- `flutter test test/unit/document_service_test.dart` — **7/7 pass**
- `flutter test test/unit/activity_service_test.dart` — **4/4 pass**

## Commits

| Hash | Scope | Message |
| --- | --- | --- |
| 628fa6a | refactor | migrate gear + logistics to context.colors |
| 188002d | refactor | migrate vault + memories to context.colors |
| 4374a10 | refactor | migrate activity + flag hero gradient for Plan 04 |
| 4500cd6 | test | add theme to MaterialApp harness in 3 widget tests |

## Known Stubs

None. All 18 source files now resolve every color from the active theme
via `context.colors`. The one deferred gradient (activity hero) is
explicitly tracked by the `// design-token-justified:` comment and will
be resolved in Plan 04.

## Threat Flags

None. Plan 03d is a palette refactor. Storage (`trip-documents`,
`trip-memories` buckets), sync queue, Firestore reads/writes, and
signed-URL flows in service layers are untouched per plan anti-patterns.
No new network endpoints, auth paths, or schema changes.

## Self-Check: PASSED

- `grep -rn "AppColorTokens\.light\." lib/features/{gear,logistics,vault,memories,activity}/ --include='*.dart' | grep -v "// design-token-justified:" | wc -l` → **0** FOUND
- Cross-wave collision check → **empty** FOUND
- `flutter analyze` → 347 (baseline match) FOUND
- `flutter test` → 1056/3/0 FOUND
- All commits exist in `git log`:
  - 628fa6a FOUND
  - 188002d FOUND
  - 4374a10 FOUND
  - 4500cd6 FOUND
- `design-token-justified` comment present on
  `activity_feed_screen.dart:150` FOUND
- Each of the 6 decorative textMuted refs has preceding
  `// textMuted-decorative-justified:` comment FOUND
