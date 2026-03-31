# Phase 14: Test Hardening - Context

**Gathered:** 2026-03-28
**Status:** Ready for planning

<domain>
## Phase Boundary

Convert structural test assertions to semantic Key identifiers so the existing test suite (624 tests) survives any label rename or visual structural change without cascade failures. This is the prerequisite gate for all v2.0 visual work.

</domain>

<decisions>
## Implementation Decisions

### Key naming convention
- **D-01:** Per-feature key classes in `lib/features/{feature}/keys/{feature}_keys.dart`, plus `lib/core/keys/shared_keys.dart` for shared widgets
- **D-02:** Key string values use `feature_widget_role` pattern (e.g., `'ledger_expense_list'`, `'home_balance_hero'`, `'gear_add_button'`)
- **D-03:** Classes are `abstract final class` with `static const Key` fields
- **D-04:** Parameterized keys for list items use factory methods returning `Key('feature_widget_$id')` (e.g., `LedgerKeys.expenseCard(String id)`)

### Migration scope
- **D-05:** Convert structural `find.text()` calls to `find.byKey()` — calls that check navigation, screen presence, section headers, widget structure. Keep `find.text()` for genuine content assertions (formatted amounts, label text validation)
- **D-06:** Convert structural `find.byType()` calls to `find.byKey()` — calls like `find.byType(LedgerScreen)`. Keep `find.byType()` for genuine type checks (CircularProgressIndicator, SnackBar)
- **D-07:** Convert `tester.tap(find.text(...))` targets to `tester.tap(find.byKey(...))` — tap-by-text is the most fragile pattern and highest value to convert
- **D-08:** Estimated scope: ~180-200 of 257 `find.text()` conversions, plus structural subset of 90 `find.byType()` conversions

### Key granularity
- **D-09:** Test-driven key placement — only add keys to widgets that tests actually reference. No speculative keys for untested widgets
- **D-10:** Exception: every screen widget gets a `.screen` key regardless of current test coverage (~25 screens). Screen keys are cheap and high-value for future navigation testing

### Test validation
- **D-11:** Feature-by-feature migration with green `flutter test` runs after each file conversion. Heaviest files first (widget_coverage_test 35 calls, create_join_group_test 30, etc.)
- **D-12:** One atomic commit per test file: keys added to widgets + test updated + green run. ~23 commits total
- **D-13:** Rename resilience verification: after full migration, temporarily rename one UI label (e.g., 'Ledger' to 'Treasury'), run full suite, confirm only content-validation tests fail, revert. Documents proof of success criterion #3
- **D-14:** Add CI warning check for new `find.text()` calls in PRs — grep-based, non-blocking warning (not hard fail since content tests still need find.text)

### Claude's Discretion
- Exact categorization of each find.text() call as structural vs content
- Migration order within the heaviest-first strategy
- Exact CI warning script implementation details
- Whether to group very small test files into a single commit

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Test infrastructure
- `.github/workflows/release_android.yml` — existing CI pipeline; CI warning check for find.text() will be added here
- `test/` — all test directories (unit/, features/, integration/) containing the 257 find.text() calls to migrate

### Requirements
- `.planning/REQUIREMENTS.md` §FOUND-05 — "Test suite uses semantic Key identifiers instead of find.text() for structural assertions"
- `.planning/ROADMAP.md` §Phase 14 — success criteria defining rename resilience and zero-modification constraint

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- No existing semantic key system — this phase creates it from scratch
- `lib/shared/widgets/` contains reusable widgets (ModuleHeader, AppTabBar, OfflineBanner, EmptyStateView, SmartModuleCard) that will need shared keys

### Established Patterns
- Feature-first directory structure: `lib/features/{feature}/` — key classes follow the same pattern with a `keys/` subdirectory
- `abstract final class` pattern used in the codebase for utility classes — same pattern for key classes
- Existing `Key` usage is minimal: only `ValueKey` in onboarding animations and vault list items

### Integration Points
- Keys are added to widget `build()` methods in `lib/features/*/screens/` and `lib/features/*/widgets/`
- Tests in `test/features/` and `test/unit/` import key classes and use `find.byKey()`
- CI pipeline in `.github/workflows/` gets the new find.text() warning step

### Current find.text() hotspots (by count)
- `test/unit/widget_coverage_test.dart` — 35 calls
- `test/features/groups/create_join_group_test.dart` — 30 calls
- `test/features/events/event_command_center_test.dart` — 23 calls
- `test/features/groups/group_settle_up_screen_test.dart` — 20 calls
- `test/features/groups/group_screens_test.dart` — 19 calls
- `test/features/events/create_event_test.dart` — 18 calls
- `test/features/events/event_module_list_test.dart` — 15 calls
- `test/features/events/group_detail_events_test.dart` — 14 calls

</code_context>

<specifics>
## Specific Ideas

- Key classes preview exactly as discussed: `abstract final class LedgerKeys { static const expenseList = Key('ledger_expense_list'); ... }`
- Parameterized keys: `static Key expenseCard(String id) => Key('ledger_expense_card_$id');`
- CI check is a warning, not a blocker — content tests legitimately need find.text()
- Verification protocol: rename 'Ledger' to 'Treasury', run suite, confirm only content tests fail, revert

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 14-test-hardening*
*Context gathered: 2026-03-28*
