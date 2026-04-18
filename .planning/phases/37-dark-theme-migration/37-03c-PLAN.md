---
phase: 37-dark-theme-migration
plan: 03c
type: execute
wave: 3
depends_on: [37-02]
files_modified:
  - lib/features/events/**/*.dart
  - lib/features/ledger/**/*.dart
autonomous: true
requirements: [DARK-01, DARK-03, DARK-04]
task_ids: [37-03c-01, 37-03c-02, 37-03c-03]
tags: [theme, dark-mode, migration, features, events, ledger]

must_haves:
  truths:
    - "Every widget in lib/features/events/ + lib/features/ledger/ reads colors via context.colors.*"
    - "All 52 combined textMuted refs triaged per D-11"
    - "event_type_config.dart hardcoded Color(0xFF...) literals (lines 42, 49, 57, 64, 71) have // design-token-justified: comments pending Plan 04 category token migration"
    - "expense_category_model.dart line 73 literal has // design-token-justified: pending Plan 04 token-sourced category colors"
    - "ledger_screen.dart:377 hero gradient literal has // design-token-justified: pending Plan 04 AppGradients"
    - "BalanceCalculator and financial logic untouched (Decimal precision preserved)"
  artifacts:
    - path: "lib/features/events/, lib/features/ledger/"
      provides: "Theme-aware events + ledger (50 combined files, 296 refs)"
  key_links:
    - from: "lib/features/{events,ledger}/"
      to: "context.colors extension"
      pattern: "context\\.colors\\."
---

<objective>
Wave 3c migrates `lib/features/events/` (18 files, 99 refs, 6 textMuted) + `lib/features/ledger/` (32 files, 197 refs, 46 textMuted) in parallel with 03a/03b/03d.

Ledger is the second-largest feature; events is medium. Both have hardcoded `Color(0xFF...)` literals that are candidates for Plan 04 token promotion — flag them with justification comments.

Purpose: Ledger is where BalanceCalculator runs and where the user sees financial state — dark-theme correctness here is table stakes. Events hosts the new v2 event-type templates (camping, day-out, dinner, etc.) whose category chips need correct theming.
Output: Both folders migrated; financial logic untouched; category/gradient literals flagged for Plan 04.
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
Standard W3 rules (see 03a).

Feature-specific handoff to Plan 04:
- `lib/features/events/models/event_type_config.dart` lines 42, 49, 57, 64, 71 — hardcoded category colors (teal, emerald, gray, gray, amber). Leave literal in this plan; add `// design-token-justified: event category color — pending Plan 04 promotion` comment.
- `lib/features/ledger/models/expense_category_model.dart` line 73 (Color(0xFF22C55E) and similar category mappings) — leave literal; add `// design-token-justified: expense category color — pending Plan 04 token-sourced mapping`.
- `lib/features/ledger/screens/ledger_screen.dart` line 377 `colors: [Color(0xFFCC6B49), Color(0xFFE0896A)]` terracotta hero gradient — leave literal; add `// design-token-justified: ledger hero gradient — pending Plan 04 AppGradients.terracotta`.

CRITICAL: The BalanceCalculator class uses `Decimal` for all money math. DO NOT refactor calculation signatures. Only modify the UI layer's Color consumption. If a financial-display widget currently shows `BalanceCalculator.compute(...).displayColor(AppColorTokens.light)` or similar, refactor the *display* function to accept `AppColorTokens` or `BuildContext` — not the calculator.
</interfaces>
</context>

<threat_model>
## Trust Boundaries

No trust boundary changes.

## STRIDE Threat Register

| Threat ID | Category | Component | Disposition | Mitigation Plan |
|-----------|----------|-----------|-------------|-----------------|
| T-37-03c-01 | Tampering | BalanceCalculator integrity | mitigate | This plan MUST NOT modify calculation logic. Acceptance criterion: `test/unit/balance_calculations_test.dart` exits 0 after every task. |
| T-37-03c-02 | Information Disclosure | Expense amounts displayed incorrectly | mitigate | Only UI color layer is touched; all Decimal-formatted money strings remain intact. |
| T-37-03c-03 | Tampering | Category color mapping drift | mitigate | Plan-04-bound literals get justification comments, not removed. Plan 04's migration is a test-protected substitution. |

Conclusion: LOW risk. Financial logic boundary is explicitly fenced.
</threat_model>

<tasks>

<task type="auto">
  <name>Task 37-03c-01: Migrate lib/features/events/ (18 files, 99 refs, 6 textMuted)</name>
  <read_first>
    - All .dart files under lib/features/events/
    - lib/features/events/models/event_type_config.dart (has 5 hardcoded Color literals at lines 42, 49, 57, 64, 71)
    - .planning/phases/37-dark-theme-migration/37-CONTEXT.md §D-11, §D-15 (category colors), §D-16
  </read_first>
  <action>
Standard W3 migration on every `.dart` file under `lib/features/events/`:

**Step 1-4** — color migration / const removal / textMuted triage / spacing tokens (standard).

**Step 5 — `event_type_config.dart` category color literals:**
Lines 42, 49, 57, 64, 71 each have `color: Color(0xFF...)` with a comment indicating the intended token (e.g., `// AppColorTokens.light.primary`). DO NOT migrate to tokens in this plan — Plan 04 handles category-color promotion per D-15. Instead, convert the existing comments to the CI-guard-friendly form:

```dart
// Before:
color: Color(0xFF0D7B74), // AppColorTokens.light.primary

// After:
// design-token-justified: event type color — pending Plan 04 category token migration (maps to context.colors.primary)
color: Color(0xFF0D7B74),
```

Do this for all 5 literals at lines 42, 49, 57, 64, 71.

**Step 6 — Import cleanup.**

**Anti-patterns:**
- Do NOT redesign event templates.
- Do NOT change event-type enum or schema.
- Do NOT touch `lib/features/ledger/` (Task 37-03c-02).
  </action>
  <verify>
    <automated>flutter analyze && grep -rn "AppColorTokens\.light\." lib/features/events/ --include='*.dart' | grep -v "// design-token-justified:" | wc -l</automated>
  </verify>
  <acceptance_criteria>
    - `flutter analyze` exits 0
    - `grep -rn "AppColorTokens\.light\." lib/features/events/ --include='*.dart' | grep -v "// design-token-justified:" | wc -l` returns 0
    - `grep -B1 "Color(0xFF" lib/features/events/models/event_type_config.dart | grep -c "design-token-justified"` >= 5 (one per category literal)
    - `flutter test test/unit/event_model_test.dart test/unit/event_service_test.dart` exits 0
  </acceptance_criteria>
  <done>events/ migrated; event_type_config.dart category palette flagged for Plan 04.</done>
</task>

<task type="auto">
  <name>Task 37-03c-02: Migrate lib/features/ledger/ (32 files, 197 refs, 46 textMuted) — largest textMuted triage</name>
  <read_first>
    - All .dart files under lib/features/ledger/screens/, widgets/, providers/, services/, models/, utils/
    - lib/features/ledger/models/expense_category_model.dart (line 73 hardcoded Color(0xFF22C55E) + similar)
    - lib/features/ledger/screens/ledger_screen.dart (line 377 hero gradient literal)
    - test/unit/balance_calculations_test.dart (read to ensure this plan's changes won't break it)
    - .planning/phases/37-dark-theme-migration/37-CONTEXT.md §D-11, §D-15, §D-16
  </read_first>
  <action>
Standard W3 migration pipeline on every `.dart` file under `lib/features/ledger/`.

**Key attention points:**

1. **46 textMuted refs** — largest concentration in the app. Ledger surfaces with textMuted typically show:
   - Secondary expense metadata (timestamp, category, paid-by) — **functional** → textSecondary
   - Balance sign indicators in neutral state — **functional** → textSecondary
   - Amount dividers / "of X members" fractions — usually **functional** → textSecondary
   - Decorative separators between list items — **decorative** → keep with justification
   - Inactive tab icons — **decorative** → keep with justification
   Apply the D-11 decision tree per call site. Err toward `textSecondary` when unclear.

2. **`expense_category_model.dart` line 73** (`return const Color(0xFF22C55E);`) and any similar category color literals — DO NOT migrate in this plan. Per D-15, Plan 04 keeps the category-color mapping local to this model but sources each color from tokens. Add `// design-token-justified: expense category color — pending Plan 04 token-sourced mapping` above each literal.

3. **`ledger_screen.dart` line 377 hero gradient** — DO NOT migrate. Add:
```dart
// design-token-justified: ledger hero gradient — pending Plan 04 AppGradients.terracotta
colors: [Color(0xFFCC6B49), Color(0xFFE0896A)],
```

4. **BalanceCalculator** (`lib/features/ledger/` — likely under `utils/` or `services/`) — DO NOT touch. Read it first to confirm it has no color references. If any service-layer function returns a `Color` based on calculation (e.g., "balance direction color"), refactor THE UI CALLER to pick the color based on the returned sign/enum, not the calculator.

5. **Apply spacing + const removal + import cleanup** as standard.

**Anti-patterns:**
- Do NOT touch `BalanceCalculator.compute` signatures.
- Do NOT change `Decimal` usages.
- Do NOT redesign expense card layouts.
  </action>
  <verify>
    <automated>flutter analyze && flutter test test/unit/balance_calculations_test.dart && grep -rn "AppColorTokens\.light\." lib/features/ledger/ --include='*.dart' | grep -v "// design-token-justified:" | wc -l</automated>
  </verify>
  <acceptance_criteria>
    - `flutter analyze` exits 0
    - `flutter test test/unit/balance_calculations_test.dart` exits 0 (financial logic untouched)
    - `grep -rn "AppColorTokens\.light\." lib/features/ledger/ --include='*.dart' | grep -v "// design-token-justified:" | wc -l` returns 0
    - Every remaining `textMuted` ref in `lib/features/ledger/` has `// textMuted-decorative-justified:` on prior line (check: `grep -rB1 "\.textMuted" lib/features/ledger/ --include='*.dart' | grep -c "textMuted-decorative-justified"` equals count of `\.textMuted\b` remaining)
    - `grep -B1 "Color(0xFF" lib/features/ledger/models/expense_category_model.dart | grep -c "design-token-justified"` matches literal count in that file
    - `grep -B1 "Color(0xFFCC6B49)" lib/features/ledger/screens/ledger_screen.dart | grep -c "design-token-justified"` >= 1
  </acceptance_criteria>
  <done>ledger/ migrated; BalanceCalculator untouched; category + gradient literals flagged for Plan 04.</done>
</task>

<task type="auto">
  <name>Task 37-03c-03: Plan-level regression gate for events/ + ledger/</name>
  <read_first>
    - .planning/phases/37-dark-theme-migration/37-03c-PLAN.md
  </read_first>
  <action>
Final gate across both feature folders:

**Step 1** — Full-scope grep:
```bash
grep -rn "AppColorTokens\.light\." lib/features/events/ lib/features/ledger/ --include='*.dart' | grep -v "// design-token-justified:" | wc -l
```
Must return 0.

**Step 2** — Cross-wave collision check:
```bash
git diff --name-only | grep "^lib/features/" | grep -v "^lib/features/\(events\|ledger\)/"
```
Must be empty.

**Step 3** — Full regression:
```bash
flutter analyze && flutter test
```

**Step 4** — Balance calculator integrity check:
```bash
flutter test test/unit/balance_calculations_test.dart test/unit/cross_group_balance_test.dart
```
Both must pass.

If ANY check fails, STOP and investigate. Do not reach into other wave 3 plans' scope.
  </action>
  <verify>
    <automated>flutter analyze && flutter test</automated>
  </verify>
  <acceptance_criteria>
    - `flutter analyze` exits 0
    - `flutter test` exits 0
    - `grep -rn "AppColorTokens\.light\." lib/features/events/ lib/features/ledger/ --include='*.dart' | grep -v "// design-token-justified:" | wc -l` returns 0
    - `git diff --name-only | grep "^lib/features/" | grep -v "^lib/features/\(events\|ledger\)/"` empty
    - `flutter test test/unit/balance_calculations_test.dart test/unit/cross_group_balance_test.dart` exits 0
  </acceptance_criteria>
  <done>Plan 03c complete; 2 feature folders migrated; BalanceCalculator intact; full suite green.</done>
</task>

</tasks>

<verification>
- `flutter analyze` → 0
- `flutter test` → 0
- 50 files, 296 combined color refs migrated or justified
- 52 textMuted refs triaged
- Plan 04 handoff annotations in event_type_config.dart, expense_category_model.dart, ledger_screen.dart
</verification>

<success_criteria>
Events + Ledger fully theme-aware. BalanceCalculator integrity verified. Plan 04 handoff explicit.
</success_criteria>

<output>
Create `.planning/phases/37-dark-theme-migration/37-03c-SUMMARY.md` with per-folder ref counts, textMuted triage breakdown, spacing replacements, full list of Plan 04 handoff items.
</output>
