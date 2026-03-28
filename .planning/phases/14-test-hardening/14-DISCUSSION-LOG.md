# Phase 14: Test Hardening - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-03-28
**Phase:** 14-test-hardening
**Areas discussed:** Key naming convention, Migration scope, Key granularity, Test validation

---

## Key Naming Convention

### Q1: How should semantic keys be organized in the codebase?

| Option | Description | Selected |
|--------|-------------|----------|
| Central constants class | Single AppKeys class (or per-feature classes) with static const Key fields. All keys discoverable in one place. | |
| Per-widget inline keys | Keys defined where they're used (key: const Key('...')). Simpler, no extra files. | |
| You decide | Claude picks during planning | |
| **Central constants class** | **Selected** | ✓ |

**User's choice:** Central constants class
**Notes:** None

### Q2: One top-level AppKeys class or per-feature key classes?

| Option | Description | Selected |
|--------|-------------|----------|
| Per-feature classes | Each feature directory gets its own keys file. Scales better with 11 features. | ✓ |
| Single AppKeys class | All keys in one file with section comments. | |
| You decide | Claude picks | |

**User's choice:** Per-feature classes
**Notes:** None

### Q3: What naming pattern for the Key string values?

| Option | Description | Selected |
|--------|-------------|----------|
| feature_widget_role | e.g., 'ledger_expense_list', 'gear_add_button'. Flat, greppable. | ✓ |
| dot.separated.path | e.g., 'ledger.expense.list'. More hierarchical. | |
| You decide | Claude picks | |

**User's choice:** feature_widget_role
**Notes:** None

### Q4: Should parameterized keys use ValueKey with item ID?

| Option | Description | Selected |
|--------|-------------|----------|
| ValueKey with ID | Factory methods returning Key('feature_widget_$id'). | ✓ |
| Static keys only | Only static const keys. Lists identified by container. | |
| You decide | Claude picks | |

**User's choice:** ValueKey with ID
**Notes:** None

---

## Migration Scope

### Q1: Which of the 257 find.text() calls get converted?

| Option | Description | Selected |
|--------|-------------|----------|
| Structural only | Convert navigation/structure assertions, keep content assertions. ~180-200 of 257. | ✓ |
| All 257 calls | Replace every find.text() with find.byKey(). | |
| You decide | Claude categorizes each call | |

**User's choice:** Structural only
**Notes:** None

### Q2: What about the 90 find.byType() calls?

| Option | Description | Selected |
|--------|-------------|----------|
| Convert structural byType too | Convert byType(LedgerScreen) style calls. Keep genuine type checks. | ✓ |
| Skip byType entirely | Focus only on find.text(). | |
| You decide | Claude decides per-call | |

**User's choice:** Convert structural byType too
**Notes:** None

### Q3: Should tap targets get converted too?

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, convert taps too | Convert tester.tap(find.text(...)) to tester.tap(find.byKey(...)). | ✓ |
| Only assertions, not taps | Convert expect() calls but leave tester.tap() as-is. | |

**User's choice:** Yes, convert taps too
**Notes:** None

---

## Key Granularity

### Q1: Which widgets get semantic keys?

| Option | Description | Selected |
|--------|-------------|----------|
| Test-driven | Only add keys to widgets that tests actually reference. No speculative keys. | ✓ |
| Comprehensive upfront | Add keys to ALL interactive widgets and structural landmarks. ~300+ keys. | |
| You decide | Claude determines | |

**User's choice:** Test-driven
**Notes:** None

### Q2: Should screen-level keys be added to every screen?

| Option | Description | Selected |
|--------|-------------|----------|
| All screens get a key | Every screen widget gets a .screen key. ~25 screens. | ✓ |
| Only tested screens | Strictly test-driven — only screens in tests get keys. | |
| You decide | Claude decides | |

**User's choice:** All screens get a key
**Notes:** None

---

## Test Validation

### Q1: How should the migration be validated?

| Option | Description | Selected |
|--------|-------------|----------|
| Feature-by-feature with green runs | Migrate one feature at a time. flutter test after each. Atomic commits. | ✓ |
| Big bang conversion | Convert all 257 calls at once, run tests once at the end. | |
| You decide | Claude picks | |

**User's choice:** Feature-by-feature with green runs
**Notes:** None

### Q2: Add a rename resilience verification test?

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, add a smoke test | Rename a label, run suite, confirm only content tests fail, revert. | ✓ |
| No extra verification | Feature-by-feature green runs are sufficient. | |
| You decide | Claude decides | |

**User's choice:** Yes, add a smoke test
**Notes:** None

### Q3: Add CI lint rule for find.text()?

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, add a CI check | Grep-based CI warning on new find.text() calls in PRs. Non-blocking. | ✓ |
| No lint rule | Rely on code review discipline. | |
| Defer to Phase 15 | Bundle with Phase 15's Color literal lint rule. | |

**User's choice:** Yes, add a CI check
**Notes:** None

### Q4: Commit strategy?

| Option | Description | Selected |
|--------|-------------|----------|
| Per test file | Each test file conversion is its own commit. ~23 commits. | ✓ |
| Per feature directory | Group all test files for a feature into one commit. ~8-10 commits. | |
| You decide | Claude picks | |

**User's choice:** Per test file
**Notes:** None

---

## Claude's Discretion

- Exact categorization of each find.text() call as structural vs content
- Migration order within the heaviest-first strategy
- Exact CI warning script implementation details
- Whether to group very small test files into a single commit

## Deferred Ideas

None — discussion stayed within phase scope
