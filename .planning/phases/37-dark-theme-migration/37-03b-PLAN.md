---
phase: 37-dark-theme-migration
plan: 03b
type: execute
wave: 3
depends_on: [37-02]
files_modified:
  - lib/features/groups/**/*.dart
autonomous: true
requirements: [DARK-01, DARK-02, DARK-03, DARK-04]
task_ids: [37-03b-01, 37-03b-02, 37-03b-03]
tags: [theme, dark-mode, migration, features, groups]

must_haves:
  truths:
    - "Every widget in lib/features/groups/ reads colors via context.colors.*"
    - "All 28 textMuted references in groups/ are migrated to textSecondary OR annotated with justification"
    - "group_card.dart avatar slot literals (lines 38-42) have `// design-token-justified: pending Plan 04 AppGroupAvatarColors` comment (Plan 04 replaces them with context.colors.groupAvatarSlot)"
    - "Standard spacing values in touched files use context.spacing.* tokens"
  artifacts:
    - path: "lib/features/groups/"
      provides: "Theme-aware groups feature (largest surface at 32 files, 231 refs)"
  key_links:
    - from: "lib/features/groups/"
      to: "context.colors extension"
      pattern: "context\\.colors\\."
---

<objective>
Wave 3b migrates the single largest feature — `lib/features/groups/` (32 files, 231 `AppColorTokens.light.*` refs, 28 `textMuted` refs). This is the heaviest single-plan migration in the phase but also the most mechanical (same substitution rule; no new widgets).

Runs parallel to 03a, 03c, 03d — `files_modified` is restricted to `lib/features/groups/**/*.dart` so no sibling-wave collision is possible.

Purpose: Groups is the dashboard of the app — the largest visible surface. Without dark-theming this feature correctly, the "dark mode" claim is cosmetic.
Output: Groups folder fully migrated; textMuted triaged; group_card.dart avatar palette flagged for Plan 04.
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
@$HOME/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/phases/37-dark-theme-migration/37-CONTEXT.md
@.planning/phases/37-dark-theme-migration/37-RESEARCH.md
@.planning/phases/37-dark-theme-migration/37-02-SUMMARY.md
@lib/core/theme/tokens/domain_aliases.dart
@lib/core/theme/tokens/color_tokens.dart

<interfaces>
Standard Wave 3 rules (see 03a for full detail):
- Color: `s/AppColorTokens\.light\.(\w+)/context.colors.$1/g` on every file
- textMuted triage per D-11 (functional → textSecondary; decorative → keep+justify)
- Spacing opportunistic per D-20 (set {4,8,12,16,20,24,32})
- `const` keyword removal where needed
- Import cleanup

Groups-specific constraint — `lib/features/groups/widgets/group_card.dart` lines 38-42 contain 5 hardcoded avatar slot colors (terracotta/teal/emerald/amber/umber). Do NOT migrate in this plan — they become `context.colors.groupAvatarSlot(index)` in Plan 04. Add `// design-token-justified: avatar slot palette — pending Plan 04 AppGroupAvatarColors` comment above each literal.
</interfaces>
</context>

<threat_model>
## Trust Boundaries

No trust boundary changes.

## STRIDE Threat Register

| Threat ID | Category | Component | Disposition | Mitigation Plan |
|-----------|----------|-----------|-------------|-----------------|
| T-37-03b-01 | Tampering | Group rendering | accept | Mechanical refactor; no new inputs. |
| T-37-03b-02 | Denial of Service | Large-file refactor causing build breakage | mitigate | Incremental task splits (3 tasks); full `flutter analyze` after each task. |

Conclusion: LOW risk. Largest file count but lowest risk — pure substitution.
</threat_model>

<tasks>

<task type="auto">
  <name>Task 37-03b-01: Migrate lib/features/groups/screens/ + lib/features/groups/widgets/ color refs</name>
  <read_first>
    - All .dart files under lib/features/groups/screens/ (find: `find lib/features/groups/screens -name '*.dart'`)
    - All .dart files under lib/features/groups/widgets/
    - lib/features/groups/widgets/group_card.dart (SPECIFICALLY lines 35-50 for avatar palette)
    - .planning/phases/37-dark-theme-migration/37-CONTEXT.md §D-11, §D-15, §D-20
  </read_first>
  <action>
Standard W3 migration on every `.dart` file under `lib/features/groups/screens/` and `lib/features/groups/widgets/`:

**Step 1 — Color migration.** `s/AppColorTokens\.light\.(\w+)/context.colors.$1/g`.

**Step 2 — `const` removal** at constructor sites.

**Step 3 — textMuted triage per D-11** — 28 refs across the folder. Groups features have many legitimate functional text roles (member counts, relative timestamps, balance subtitles) — most will migrate to textSecondary. Separator dots between member avatars and chevron-in-inactive-tab glyphs are decorative.

**Step 4 — Spacing tokens opportunistic** (D-20).

**Step 5 — group_card.dart avatar palette (lines 38-42):** DO NOT migrate the 5 avatar slot literals. Add justification comment directly above each:
```dart
// design-token-justified: avatar slot 0 — pending Plan 04 AppGroupAvatarColors.lightSlots[0]
Color(0xFF0D7B74),
// design-token-justified: avatar slot 1 — pending Plan 04 AppGroupAvatarColors.lightSlots[1]
Color(0xFFCC6B49),
// design-token-justified: avatar slot 2 — pending Plan 04 AppGroupAvatarColors.lightSlots[2]
Color(0xFF10B981),
// design-token-justified: avatar slot 3 — pending Plan 04 AppGroupAvatarColors.lightSlots[3]
Color(0xFFF59E0B),
// design-token-justified: avatar slot 4 — pending Plan 04 AppGroupAvatarColors.lightSlots[4]
Color(0xFF7C6E5A),
```

**Step 6 — Import cleanup.**

**Anti-patterns:**
- Do NOT redesign group cards visually.
- Do NOT migrate the avatar slot literals to tokens in this plan.
- Do NOT touch providers or services (Task 37-03b-02).
  </action>
  <verify>
    <automated>flutter analyze && grep -rn "AppColorTokens\.light\." lib/features/groups/screens/ lib/features/groups/widgets/ --include='*.dart' | grep -v "// design-token-justified:" | wc -l</automated>
  </verify>
  <acceptance_criteria>
    - `flutter analyze` exits 0
    - `grep -rn "AppColorTokens\.light\." lib/features/groups/screens/ lib/features/groups/widgets/ --include='*.dart' | grep -v "// design-token-justified:" | wc -l` returns 0
    - `grep -B1 "Color(0xFF" lib/features/groups/widgets/group_card.dart | grep -c "design-token-justified"` >= 5 (one per avatar literal)
    - Every remaining `textMuted` reference in these subdirs has `// textMuted-decorative-justified:` comment on prior line
    - `flutter test test/unit/` exits 0
  </acceptance_criteria>
  <done>screens/ and widgets/ subdirs migrated; group_card avatar palette flagged for Plan 04.</done>
</task>

<task type="auto">
  <name>Task 37-03b-02: Migrate lib/features/groups/providers/ + lib/features/groups/services/ + lib/features/groups/models/</name>
  <read_first>
    - All .dart files under lib/features/groups/providers/, services/, models/
  </read_first>
  <action>
Standard W3 migration on remaining subdirs of `lib/features/groups/`. Typically models/services/providers have FEWER color refs (grep will show) because they're logic-heavy. But some providers return `Color` directly (e.g., computed avatar colors, category tinting) — those need refactor:

**Refactor pattern for stateless Color providers:**
If a function/getter returns a `Color` and currently reads `AppColorTokens.light.*` statelessly, change signature to accept `BuildContext` (preferred) OR `AppColorTokens`:

```dart
// Before:
Color categoryColor(String category) =>
    category == 'food' ? AppColorTokens.light.primary : AppColorTokens.light.textMuted;

// After (option A — BuildContext):
Color categoryColor(BuildContext context, String category) =>
    category == 'food' ? context.colors.primary : context.colors.textSecondary;
// ^^ note: also triaged textMuted → textSecondary per D-11

// After (option B — tokens parameter, if BuildContext unavailable):
Color categoryColor(AppColorTokens colors, String category) =>
    category == 'food' ? colors.primary : colors.textSecondary;
```

Every caller of the refactored function must also be updated — that may cascade to screen files (which were migrated in Task 37-03b-01). Re-run `flutter analyze` and fix cascade compile errors.

**Apply textMuted triage + spacing + const-removal + import cleanup as standard.**

**Anti-patterns:**
- Do NOT change business logic (balance calculations, soft-delete flags, sync queue logic).
- Do NOT touch `lib/features/groups/screens/` or `widgets/` (done in Task 37-03b-01).
  </action>
  <verify>
    <automated>flutter analyze && grep -rn "AppColorTokens\.light\." lib/features/groups/providers/ lib/features/groups/services/ lib/features/groups/models/ --include='*.dart' 2>/dev/null | grep -v "// design-token-justified:" | wc -l</automated>
  </verify>
  <acceptance_criteria>
    - `flutter analyze` exits 0
    - `grep -rn "AppColorTokens\.light\." lib/features/groups/providers/ lib/features/groups/services/ lib/features/groups/models/ --include='*.dart' 2>/dev/null | grep -v "// design-token-justified:" | wc -l` returns 0
    - `flutter test test/unit/` exits 0 (no business-logic regression)
  </acceptance_criteria>
  <done>Non-UI subdirs of groups/ migrated; any Color-returning helpers refactored to take context or tokens.</done>
</task>

<task type="auto">
  <name>Task 37-03b-03: Plan-level regression gate for groups/</name>
  <read_first>
    - git diff (of this plan's changes so far)
  </read_first>
  <action>
**Step 1** — Final grep across entire groups folder:
```bash
grep -rn "AppColorTokens\.light\." lib/features/groups/ --include='*.dart' | grep -v "// design-token-justified:" | wc -l
```
Must return 0.

**Step 2** — Confirm no sibling-wave collision:
```bash
git diff --name-only | grep "^lib/features/" | grep -v "^lib/features/groups/"
```
Should return empty.

**Step 3** — Run full regression suite:
```bash
flutter analyze && flutter test
```

**Step 4** — Re-run the textMuted triage check on groups/:
```bash
grep -rB1 "\.textMuted" lib/features/groups/ --include='*.dart' | grep -c "textMuted-decorative-justified"
```
Should equal the total remaining textMuted reference count (each remaining one has a preceding justification comment).

If any check fails — STOP. Investigate the specific failure. Do NOT reach into other plans' scope.
  </action>
  <verify>
    <automated>flutter analyze && flutter test</automated>
  </verify>
  <acceptance_criteria>
    - `flutter analyze` exits 0
    - `flutter test` exits 0
    - `grep -rn "AppColorTokens\.light\." lib/features/groups/ --include='*.dart' | grep -v "// design-token-justified:" | wc -l` returns 0
    - `git diff --name-only | grep "^lib/features/" | grep -v "^lib/features/groups/"` is empty
  </acceptance_criteria>
  <done>groups/ fully migrated; full suite green; no cross-wave collision.</done>
</task>

</tasks>

<verification>
- `flutter analyze` → 0
- `flutter test` → 0
- All 231 original light-refs migrated or justified
- All 28 textMuted refs triaged
- 5 avatar literals in group_card.dart have `design-token-justified` comments pending Plan 04
</verification>

<success_criteria>
Groups feature (largest surface in phase) fully dark-theme-aware. Avatar palette handoff to Plan 04 clearly annotated.
</success_criteria>

<output>
Create `.planning/phases/37-dark-theme-migration/37-03b-SUMMARY.md` with per-subdir file/ref counts before/after, textMuted triage breakdown (migrated vs kept-with-justification), spacing replacements, and the avatar palette handoff checklist.
</output>
