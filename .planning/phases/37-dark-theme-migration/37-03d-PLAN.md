---
phase: 37-dark-theme-migration
plan: 03d
type: execute
wave: 3
depends_on: [37-02]
files_modified:
  - lib/features/gear/**/*.dart
  - lib/features/logistics/**/*.dart
  - lib/features/vault/**/*.dart
  - lib/features/memories/**/*.dart
  - lib/features/activity/**/*.dart
autonomous: true
requirements: [DARK-01, DARK-02, DARK-03, DARK-04]
task_ids: [37-03d-01, 37-03d-02, 37-03d-03, 37-03d-04]
tags: [theme, dark-mode, migration, features]

must_haves:
  truths:
    - "Every widget in lib/features/{gear,logistics,vault,memories,activity}/ reads colors via context.colors.*"
    - "All 27 combined textMuted refs triaged per D-11"
    - "activity_feed_screen.dart:150 hero gradient literal has // design-token-justified: pending Plan 04 AppGradients comment"
    - "Standard spacing values in touched files use context.spacing.*"
  artifacts:
    - path: "lib/features/{gear,logistics,vault,memories,activity}/"
      provides: "Theme-aware gear + logistics + vault + memories + activity (37 combined files, 146 refs)"
  key_links:
    - from: "lib/features/{gear,logistics,vault,memories,activity}/"
      to: "context.colors extension"
      pattern: "context\\.colors\\."
---

<objective>
Wave 3d migrates five remaining feature folders in parallel with 03a/03b/03c:
- `gear/` — 9 files, 45 refs, 8 textMuted
- `logistics/` — 9 files, 39 refs, 11 textMuted
- `vault/` — 6 files, 26 refs, 2 textMuted
- `memories/` — 7 files, 23 refs, 3 textMuted
- `activity/` — 6 files, 13 refs, 3 textMuted

Total: 37 files, 146 refs, 27 textMuted. Individual folders are small but cumulative size justifies a dedicated parallel plan.

activity_feed_screen.dart line 150 has a hardcoded gradient literal to flag for Plan 04.

Purpose: These are the trip-module features — without them migrated, dark mode has holes wherever a user opens gear, logistics, vault, or memories from the command center.
Output: All five folders migrated; activity hero gradient flagged for Plan 04.
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

<interfaces>
Standard W3 migration rules (see 03a).

Feature-specific handoff to Plan 04:
- `lib/features/activity/screens/activity_feed_screen.dart` line 150: `colors: [Color(0xFFA67C5B), Color(0xFFC29A7A)]` (warm-brown hero gradient). Leave literal; add `// design-token-justified: activity hero gradient — pending Plan 04 AppGradients` comment.

No other known hardcoded-color hotspots in these folders per scout grep.
</interfaces>
</context>

<threat_model>
## Trust Boundaries

No trust boundary changes.

## STRIDE Threat Register

| Threat ID | Category | Component | Disposition | Mitigation Plan |
|-----------|----------|-----------|-------------|-----------------|
| T-37-03d-01 | Tampering | Gear/logistics/vault/memories rendering | accept | Mechanical refactor; no new inputs. |
| T-37-03d-02 | Information Disclosure | Vault document display (file thumbnails, names) | accept | Only color theming changes; document data flow unchanged. |

Conclusion: LOW risk. Palette swap only; vault's document storage flow untouched.
</threat_model>

<tasks>

<task type="auto">
  <name>Task 37-03d-01: Migrate lib/features/gear/ + lib/features/logistics/ (18 files, 84 refs, 19 textMuted)</name>
  <read_first>
    - All .dart files under lib/features/gear/ and lib/features/logistics/
    - .planning/phases/37-dark-theme-migration/37-CONTEXT.md §D-11, §D-20
  </read_first>
  <action>
Standard W3 migration on every `.dart` file under `lib/features/gear/` and `lib/features/logistics/`:

**Step 1** — Color migration via `s/AppColorTokens\.light\.(\w+)/context.colors.$1/g`.

**Step 2** — `const` removal at constructor sites that now reference `context.colors`.

**Step 3** — textMuted triage per D-11. Gear/logistics surfaces typically show:
  - Item category labels (functional → textSecondary)
  - "Brought by X" attribution lines (functional → textSecondary)
  - Chevron icons in inactive state (decorative → keep+justify)
  - Separator dots between metadata (decorative → keep+justify)

**Step 4** — Spacing tokens (D-20, opportunistic).

**Step 5** — Import cleanup.

**Anti-patterns:**
- Do NOT touch `lib/features/vault/`, `memories/`, or `activity/` (separate tasks).
- Do NOT modify sync queue logic.
  </action>
  <verify>
    <automated>flutter analyze && grep -rn "AppColorTokens\.light\." lib/features/gear/ lib/features/logistics/ --include='*.dart' | grep -v "// design-token-justified:" | wc -l</automated>
  </verify>
  <acceptance_criteria>
    - `flutter analyze` exits 0
    - `grep -rn "AppColorTokens\.light\." lib/features/gear/ lib/features/logistics/ --include='*.dart' | grep -v "// design-token-justified:" | wc -l` returns 0
    - Every remaining `textMuted` in these folders has preceding `// textMuted-decorative-justified:`
    - `flutter test test/unit/gear_service_test.dart` exits 0
  </acceptance_criteria>
  <done>gear/ and logistics/ migrated.</done>
</task>

<task type="auto">
  <name>Task 37-03d-02: Migrate lib/features/vault/ + lib/features/memories/ (13 files, 49 refs, 5 textMuted)</name>
  <read_first>
    - All .dart files under lib/features/vault/ and lib/features/memories/
    - .planning/phases/37-dark-theme-migration/37-CONTEXT.md §D-11
  </read_first>
  <action>
Standard W3 migration on every `.dart` file under `lib/features/vault/` and `lib/features/memories/`.

**Vault-specific attention:**
- Document thumbnails, upload progress indicators, signed-URL cache entries render in these widgets — color refs are typically for metadata text and action buttons. Standard migration applies.
- The FullScreenPhoto overlay (per CLAUDE.md still uses `opaque:false PageRouteBuilder` inside MemoriesScreen) — if it reads `AppColorTokens.light.*`, migrate.

**Memories-specific attention:**
- Photo grid tiles, upload state indicators → standard migration.

**Apply steps 1-5** (color / const / textMuted / spacing / imports) per standard.

**Anti-patterns:**
- Do NOT change signed-URL logic or storage bucket references.
- Do NOT modify file upload/download services.
  </action>
  <verify>
    <automated>flutter analyze && grep -rn "AppColorTokens\.light\." lib/features/vault/ lib/features/memories/ --include='*.dart' | grep -v "// design-token-justified:" | wc -l</automated>
  </verify>
  <acceptance_criteria>
    - `flutter analyze` exits 0
    - `grep -rn "AppColorTokens\.light\." lib/features/vault/ lib/features/memories/ --include='*.dart' | grep -v "// design-token-justified:" | wc -l` returns 0
    - Every remaining `textMuted` has preceding `// textMuted-decorative-justified:`
    - `flutter test test/unit/document_service_test.dart` exits 0 (if file exists)
  </acceptance_criteria>
  <done>vault/ and memories/ migrated; storage logic untouched.</done>
</task>

<task type="auto">
  <name>Task 37-03d-03: Migrate lib/features/activity/ (6 files, 13 refs, 3 textMuted) + flag activity_feed_screen.dart:150 gradient</name>
  <read_first>
    - All .dart files under lib/features/activity/
    - lib/features/activity/screens/activity_feed_screen.dart (specifically line 150 gradient literal)
    - .planning/phases/37-dark-theme-migration/37-CONTEXT.md §D-11, §D-15 (gradient promotion)
  </read_first>
  <action>
Standard W3 migration on every `.dart` file under `lib/features/activity/`.

**Specific handoff to Plan 04 — `activity_feed_screen.dart` line 150:**
Leave the gradient literal; add justification:
```dart
// design-token-justified: activity hero gradient — pending Plan 04 AppGradients
colors: [Color(0xFFA67C5B), Color(0xFFC29A7A)],
```

**Apply steps 1-5** per standard. Activity screens surface activity log entries — textMuted is typically used for timestamps ("2h ago") which are **functional** → textSecondary.

**Anti-patterns:**
- Do NOT touch activity log service or Firestore queries.
  </action>
  <verify>
    <automated>flutter analyze && grep -rn "AppColorTokens\.light\." lib/features/activity/ --include='*.dart' | grep -v "// design-token-justified:" | wc -l</automated>
  </verify>
  <acceptance_criteria>
    - `flutter analyze` exits 0
    - `grep -rn "AppColorTokens\.light\." lib/features/activity/ --include='*.dart' | grep -v "// design-token-justified:" | wc -l` returns 0
    - `grep -B1 "Color(0xFFA67C5B)" lib/features/activity/screens/activity_feed_screen.dart | grep -c "design-token-justified"` >= 1
    - Every remaining `textMuted` has preceding `// textMuted-decorative-justified:`
    - `flutter test test/unit/activity_service_test.dart` exits 0
  </acceptance_criteria>
  <done>activity/ migrated; hero gradient flagged for Plan 04.</done>
</task>

<task type="auto">
  <name>Task 37-03d-04: Plan-level regression gate for all 5 folders</name>
  <read_first>
    - .planning/phases/37-dark-theme-migration/37-03d-PLAN.md
  </read_first>
  <action>
Final gate:

**Step 1** — Full-scope grep:
```bash
grep -rn "AppColorTokens\.light\." lib/features/gear/ lib/features/logistics/ lib/features/vault/ lib/features/memories/ lib/features/activity/ --include='*.dart' | grep -v "// design-token-justified:" | wc -l
```
Must return 0.

**Step 2** — Cross-wave collision check:
```bash
git diff --name-only | grep "^lib/features/" | grep -v "^lib/features/\(gear\|logistics\|vault\|memories\|activity\)/"
```
Empty.

**Step 3** — Full regression:
```bash
flutter analyze && flutter test
```
  </action>
  <verify>
    <automated>flutter analyze && flutter test</automated>
  </verify>
  <acceptance_criteria>
    - `flutter analyze` exits 0
    - `flutter test` exits 0
    - Final grep returns 0
    - `git diff --name-only | grep "^lib/features/" | grep -v "^lib/features/\(gear\|logistics\|vault\|memories\|activity\)/"` empty
  </acceptance_criteria>
  <done>Plan 03d complete; 5 feature folders migrated; full suite green.</done>
</task>

</tasks>

<verification>
- `flutter analyze` → 0
- `flutter test` → 0
- 37 combined files migrated
- 146 combined refs migrated or justified
- 27 textMuted triaged
- activity_feed_screen.dart:150 gradient flagged for Plan 04
</verification>

<success_criteria>
All 5 "trip module" features theme-aware. Storage/sync/service layers untouched.
</success_criteria>

<output>
Create `.planning/phases/37-dark-theme-migration/37-03d-SUMMARY.md` with per-folder counts, triage breakdown, and the activity gradient handoff annotation.
</output>
