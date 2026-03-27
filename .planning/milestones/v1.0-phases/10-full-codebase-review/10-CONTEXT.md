# Phase 10: Full Codebase Review - Context

**Gathered:** 2026-03-27
**Status:** Ready for planning

<domain>
## Phase Boundary

Comprehensive codebase audit AND fix pass for quality, consistency, security, performance, and architectural alignment. This is the final quality gate before closing milestone v1.0. All issues found are fixed in this phase — no separate follow-up.

</domain>

<decisions>
## Implementation Decisions

### Audit & Fix Scope
- **D-01:** Audit and fix in a single phase. No audit-only report — every issue found gets resolved in this phase to keep milestone closure tight.
- **D-02:** Error handling: verify existing try/catch blocks handle errors well, add error handling where missing at system boundaries (Firestore calls, auth, storage). Don't wrap internal code that can't fail. Leave read-path errors to Riverpod's AsyncValue.error where appropriate.

### Large File Refactoring
- **D-03:** Split ALL 5 files over 800 lines to under 800. Extract widget methods into separate files, move dialogs/sheets into their own widgets. Target files:
  - `lib/features/ledger/screens/settle_up_screen.dart` (1062 lines)
  - `lib/features/ledger/screens/ledger_screen.dart` (1059 lines)
  - `lib/features/groups/screens/group_settle_up_screen.dart` (1021 lines)
  - `lib/features/logistics/screens/logistics_screen.dart` (887 lines)
  - `lib/features/memories/screens/memories_screen.dart` (783 lines)

### Lint & Analysis
- **D-04:** Target zero warnings from `flutter analyze`. Ignore info-level issues (mostly `prefer_const_constructors` and naming in test files). Current state: 26 warnings to fix, 172 infos to leave alone.

### Naming Consistency
- **D-05:** Document naming conventions (event* for new code, trip* only for intentional legacy shims still in use), audit for violations, and fix them. Add conventions section to CLAUDE.md. Keep intentional trip* shims where they're still needed by existing screens.

### Claude's Discretion
- Security review depth: Claude determines appropriate depth based on what the codebase exposes (Firestore rules, auth flows, storage access patterns)
- Performance review: code-level pattern review for obvious inefficiencies, not benchmarking
- Hardcoded values: Claude judges which values need extraction to constants vs which are fine inline

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project Standards
- `CLAUDE.md` — Project architecture, conventions, testing requirements, key technical details
- `.planning/PROJECT.md` — Core value, requirements, constraints, key decisions

### Prior Phase Artifacts
- `.planning/phases/09-dead-code-cleanup/09-VERIFICATION.md` — Dead code already removed (phase 9 complete)
- `.planning/phases/08-integration-correctness-fixes/08-VERIFICATION.md` — Integration fixes verified
- `.planning/phases/06-testing-and-coverage/06-VERIFICATION.md` — Test coverage status

### Codebase References
- `lib/core/theme/app_theme.dart` — Design tokens, spacing constants, border radii
- `lib/shared/widgets/` — Shared widget library (ModuleHeader, AppTabBar, etc.)
- `analysis_options.yaml` — Lint rules configuration

</canonical_refs>

<code_context>
## Existing Code Insights

### Current Issues Found (from scout)
- 26 flutter analyze warnings: unused imports (event_ref.dart across ~8 screens), unnecessary casts, null comparisons
- 5 files over 800 lines, 3 over 1000 (all ledger/settle-up/logistics screens)
- 108 Dart files in lib/, ~24k lines total
- Zero Supabase references remaining (clean migration)

### Established Patterns
- Feature-first structure: `lib/features/{feature}/screens/`, `widgets/`, `providers/`, `services/`, `models/`
- Shared widgets in `lib/shared/widgets/` — ModuleHeader, AppTabBar, EmptyStateView, etc.
- Riverpod 2.x manual providers (no code-gen)
- Page transitions via `AppPageRoute` and `AppBottomSheetRoute`

### Integration Points
- Splitting large screen files will produce new widget files in the feature's `widgets/` directory
- Naming convention documentation goes into CLAUDE.md `## Conventions` section
- Error handling additions go into existing service and provider files

</code_context>

<specifics>
## Specific Ideas

No specific requirements — open to standard approaches for the audit and refactoring.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 10-full-codebase-review*
*Context gathered: 2026-03-27*
