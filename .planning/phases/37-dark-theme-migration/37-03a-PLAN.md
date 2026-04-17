---
phase: 37-dark-theme-migration
plan: 03a
type: execute
wave: 3
depends_on: [37-02]
files_modified:
  - lib/features/auth/**/*.dart
  - lib/features/onboarding/**/*.dart
  - lib/features/settings/**/*.dart
  - lib/features/home/**/*.dart
autonomous: true
requirements: [DARK-01, DARK-02, DARK-03, DARK-04]
task_ids: [37-03a-01, 37-03a-02, 37-03a-03, 37-03a-04]
tags: [theme, dark-mode, migration, features]

must_haves:
  truths:
    - "Every widget in lib/features/{auth,onboarding,settings,home}/ reads colors via context.colors.*"
    - "All textMuted references in these features are either migrated to textSecondary OR annotated with // textMuted-decorative-justified:"
    - "Standard spacing values in touched files use context.spacing.* tokens"
    - "onboarding_screen.dart gradient literals at lines 43, 50, 57 remain as literals pending Plan 04 gradient_tokens.dart — in this plan they get // design-token-justified: or are flagged for Plan 04 migration"
  artifacts:
    - path: "lib/features/auth/**, lib/features/onboarding/**, lib/features/settings/**, lib/features/home/**"
      provides: "Theme-aware widgets in all four feature folders"
  key_links:
    - from: "lib/features/{auth,onboarding,settings,home}/"
      to: "context.colors extension"
      pattern: "context\\.colors\\."
---

<objective>
Wave 3a migrates four feature folders in parallel with 03b, 03c, 03d. No file overlap with sibling waves.

- `lib/features/auth/` — 1 file, 0 AppColorTokens refs (still grep to confirm; trivial)
- `lib/features/onboarding/` — 2 files, 9 refs
- `lib/features/settings/` — 8 files, 57 refs
- `lib/features/home/` — 9 files, 48 refs, 3 textMuted

Per D-01 and D-02 these plans run concurrently with 03b-03d; `files_modified` is a feature-directory glob (no cross-feature touches).

Purpose: Wave 2 wired the shared layer. Wave 3 makes every feature screen render correctly in dark mode by routing color reads through `context.colors`.
Output: All four folders fully migrated; textMuted triage complete; spacing tokens adopted opportunistically.
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
Migration rule (per D-03):
```
s/AppColorTokens\.light\.(\w+)/context.colors.$1/g
```

textMuted triage (per D-11):
- Functional text (labels, amounts, hints, body) → `context.colors.textSecondary`
- Decorative only (•, faint chevron, divider glyph) → keep `context.colors.textMuted` + `// textMuted-decorative-justified: <element>` on prior line

Spacing rule (per D-20):
- Token set: {4, 8, 12, 16, 20, 24, 32}
- Only replace on files already touched for color migration
- Odd values (6, 10, 14, 18, 26) stay numeric

Gradient literals in onboarding_screen.dart at lines 43, 50, 57 (see grep output) — DO NOT promote to tokens in this plan; either (a) leave as-is with a `// TODO(phase-37-plan-04): promote to AppGradients.terracotta/.olive/.teal` comment, OR (b) add `// design-token-justified: onboarding gradient — pending Plan 04 gradient_tokens.dart` comment. Plan 04 will replace them.
</interfaces>
</context>

<threat_model>
## Trust Boundaries

No trust boundary changes.

## STRIDE Threat Register

| Threat ID | Category | Component | Disposition | Mitigation Plan |
|-----------|----------|-----------|-------------|-----------------|
| T-37-03a-01 | Tampering | Settings screen rendering | accept | Mechanical color refactor; no new inputs. |
| T-37-03a-02 | Information Disclosure | Settings screen (user's theme choice) | accept | Already persisted via settingsProvider (Plan 01 analysis). No PII. |

Conclusion: LOW risk. Palette-swap only.
</threat_model>

<tasks>

<task type="auto">
  <name>Task 37-03a-01: Migrate lib/features/auth/ + lib/features/onboarding/</name>
  <read_first>
    - lib/features/auth/**/*.dart (find via glob; verify 0 color refs grep)
    - lib/features/onboarding/screens/onboarding_screen.dart (has gradient literals at lines 43, 50, 57)
    - lib/features/onboarding/providers/ (if exists — verify no color usage)
    - .planning/phases/37-dark-theme-migration/37-CONTEXT.md §D-11, §D-20
  </read_first>
  <action>
Apply the standard W3 migration pipeline to every `.dart` file under `lib/features/auth/` and `lib/features/onboarding/`:

**Step 1 — Color migration:** `s/AppColorTokens\.light\.(\w+)/context.colors.$1/g` — only inside widgets that have BuildContext. If a helper class doesn't have context, refactor to accept it.

**Step 2 — `const` keyword removal** from constructors that now reference `context.colors`.

**Step 3 — textMuted triage** per D-11 (onboarding has 0 textMuted per grep, but re-verify).

**Step 4 — Spacing tokens** per D-20 (only on files touched; only for token-matching values).

**Step 5 — Gradient literal handling in `onboarding_screen.dart` (lines 43, 50, 57):**
DO NOT migrate the `Color(0xFFCC6B49), Color(0xFFD4845F)` etc. literals in this task — they become `AppGradients.terracotta/.olive/.teal` in Plan 04. BUT to prevent CI failure when Plan 05 lands, add a placeholder justification comment directly above each literal:

```dart
// design-token-justified: onboarding gradient — pending Plan 04 promotion to AppGradients.terracotta
gradientColors: [Color(0xFFCC6B49), Color(0xFFD4845F)],
```

After Plan 04, these literals will be replaced with `AppGradients.terracotta.colors` (or equivalent accessor) and the justification comment removed.

**Step 6 — Import cleanup:** Drop `import '.../color_tokens.dart'` if no remaining direct references (other than inside `// design-token-justified:` blocks, which import stays).

**Anti-patterns:**
- Do NOT touch files outside auth/ or onboarding/.
- Do NOT create new tokens.
- Do NOT redesign the onboarding flow visually.
  </action>
  <verify>
    <automated>flutter analyze && grep -rn "AppColorTokens\.light\." lib/features/auth/ lib/features/onboarding/ --include='*.dart' | grep -v "// design-token-justified:" | wc -l</automated>
  </verify>
  <acceptance_criteria>
    - `flutter analyze` exits 0
    - `grep -rn "AppColorTokens\.light\." lib/features/auth/ lib/features/onboarding/ --include='*.dart' | grep -v "// design-token-justified:" | wc -l` returns 0
    - `grep -B1 "Color(0xFF" lib/features/onboarding/screens/onboarding_screen.dart | grep -c "design-token-justified\|TODO(phase-37-plan-04)"` >= 3 (one per gradient literal)
    - `flutter test test/unit/` exits 0 (no regression)
  </acceptance_criteria>
  <done>Both folders migrated; gradient literals in onboarding have justification/TODO comments for Plan 04 handoff.</done>
</task>

<task type="auto">
  <name>Task 37-03a-02: Migrate lib/features/settings/ (8 files, 57 refs)</name>
  <read_first>
    - lib/features/settings/screens/profile_screen.dart
    - All other .dart files under lib/features/settings/
    - lib/core/providers/settings_provider.dart (reference — do NOT modify)
    - .planning/phases/37-dark-theme-migration/37-CONTEXT.md §D-05 (Plan 05 will add Display section — do NOT add it here)
  </read_first>
  <action>
Standard W3 migration on every `.dart` file under `lib/features/settings/`:

**Step 1** — color migration via `s/AppColorTokens\.light\.(\w+)/context.colors.$1/g`.

**Step 2** — `const` removal where needed.

**Step 3** — textMuted triage (per D-11). Settings surfaces like "Theme: System · Following device" subtitles are functional text → textSecondary.

**Step 4** — Spacing tokens opportunistic (D-20).

**Step 5 — Import cleanup.**

**IMPORTANT (boundary with Plan 05):**
- Do NOT add the new "Display" section to `profile_screen.dart` — that is Plan 05 Task 37-05-02.
- Do NOT create `lib/features/settings/widgets/theme_picker_sheet.dart` — that is Plan 05 Task 37-05-01.
- Do NOT modify `settings_provider.dart` or `settings_service.dart` — those are already correct per research correction #1.

**Current file set (verify via `find lib/features/settings -name '*.dart'`):**
- `screens/profile_screen.dart` — main target, most refs
- Other tiles/widgets/providers under this directory — migrate all

If a profile-section tile widget uses `textMuted` for a secondary line like "v1.2.0 (42)" version info — that's functional → textSecondary. If it uses textMuted for a decorative dot between list items → keep with justification.
  </action>
  <verify>
    <automated>flutter analyze && grep -rn "AppColorTokens\.light\." lib/features/settings/ --include='*.dart' | grep -v "// design-token-justified:" | wc -l</automated>
  </verify>
  <acceptance_criteria>
    - `flutter analyze` exits 0
    - `grep -rn "AppColorTokens\.light\." lib/features/settings/ --include='*.dart' | grep -v "// design-token-justified:" | wc -l` returns 0
    - `grep -rn "context\.colors\." lib/features/settings/ --include='*.dart' | wc -l` >= 40 (vs. 57 original refs — accounts for some dropped via refactor)
    - Every `.textMuted` reference in `lib/features/settings/` has preceding `// textMuted-decorative-justified:` comment OR was removed/migrated
    - `flutter test test/unit/` exits 0
    - `profile_screen.dart` does NOT yet contain "Display" string or "ThemePickerSheet" reference (boundary preserved for Plan 05)
  </acceptance_criteria>
  <done>Settings folder migrated; boundary with Plan 05 preserved.</done>
</task>

<task type="auto">
  <name>Task 37-03a-03: Migrate lib/features/home/ (9 files, 48 refs, 3 textMuted)</name>
  <read_first>
    - All .dart files under lib/features/home/
    - .planning/phases/37-dark-theme-migration/37-CONTEXT.md §D-11, §D-20
  </read_first>
  <action>
Standard W3 migration pipeline on every `.dart` file under `lib/features/home/`:

**Step 1** — color migration.
**Step 2** — `const` removal.
**Step 3** — textMuted triage. 3 textMuted refs in home/ — apply the decision tree per D-11:
- In home_screen balance/stats cards → functional → textSecondary.
- In decorative separators → keep with justification.
**Step 4** — Spacing tokens.
**Step 5** — Import cleanup.

**Anti-patterns:**
- Do NOT redesign the home dashboard.
- Do NOT touch `lib/features/groups/` (that's Plan 03b).
- Do NOT add new card variants or widgets.
  </action>
  <verify>
    <automated>flutter analyze && grep -rn "AppColorTokens\.light\." lib/features/home/ --include='*.dart' | grep -v "// design-token-justified:" | wc -l</automated>
  </verify>
  <acceptance_criteria>
    - `flutter analyze` exits 0
    - `grep -rn "AppColorTokens\.light\." lib/features/home/ --include='*.dart' | grep -v "// design-token-justified:" | wc -l` returns 0
    - All 3 original `textMuted` refs either migrated to `textSecondary` OR kept with `// textMuted-decorative-justified:` comment
    - `flutter test test/unit/` exits 0
  </acceptance_criteria>
  <done>Home folder migrated; textMuted triaged; analyze clean.</done>
</task>

<task type="auto">
  <name>Task 37-03a-04: Run regression test suite + verify sibling-wave non-collision</name>
  <read_first>
    - `.planning/phases/37-dark-theme-migration/37-03a-PLAN.md` (this plan)
    - `.planning/phases/37-dark-theme-migration/37-03b-PLAN.md`, `37-03c-PLAN.md`, `37-03d-PLAN.md` (verify no overlap)
  </read_first>
  <action>
Final plan-level gate:

**Step 1** — Re-grep to confirm migration completeness across 03a scope:
```bash
grep -rn "AppColorTokens\.light\." lib/features/auth/ lib/features/onboarding/ lib/features/settings/ lib/features/home/ --include='*.dart' | grep -v "// design-token-justified:" | wc -l
```
Must return 0.

**Step 2** — Run full regression suite:
```bash
flutter analyze
flutter test
```
Both must pass. Note: goldens and CI-guard tests haven't been added yet (Plan 05) — but every existing unit/widget test must still pass.

**Step 3** — Verify no accidental cross-wave file touches:
```bash
git diff --name-only | grep -v "^lib/features/\(auth\|onboarding\|settings\|home\)/"
```
Should return no lib/features/... paths outside 03a's scope.

**Step 4** — If regression test finds theme-rendering errors that require changes to shared widgets or core/, STOP — those changes belong in Plan 02's followup, not this task. Report the issue and defer.
  </action>
  <verify>
    <automated>flutter analyze && flutter test</automated>
  </verify>
  <acceptance_criteria>
    - `flutter analyze` exits 0
    - `flutter test` exits 0 (full suite)
    - `grep -rn "AppColorTokens\.light\." lib/features/auth/ lib/features/onboarding/ lib/features/settings/ lib/features/home/ --include='*.dart' | grep -v "// design-token-justified:" | wc -l` returns 0
    - `git diff --name-only | grep "^lib/features/" | grep -v "^lib/features/\(auth\|onboarding\|settings\|home\)/"` returns empty (no sibling-wave touches)
  </acceptance_criteria>
  <done>Plan 03a complete; 4 feature folders migrated; full suite green; no cross-wave collisions.</done>
</task>

</tasks>

<verification>
- `flutter analyze` → 0
- `flutter test` → 0
- Zero un-justified `AppColorTokens.light.*` in auth/onboarding/settings/home
- Plan 05's Display section + theme picker NOT yet added (boundary preserved)
</verification>

<success_criteria>
4 feature folders migrated with textMuted triaged and spacing tokens adopted opportunistically. No sibling-wave file collisions. Full test suite remains green.
</success_criteria>

<output>
Create `.planning/phases/37-dark-theme-migration/37-03a-SUMMARY.md` documenting per-folder file count, ref count before/after, textMuted triage breakdown, spacing replacements, and any `// design-token-justified:` exemptions added.
</output>
