# Phase 6: Testing and Coverage - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-03-27
**Phase:** 06-testing-and-coverage
**Areas discussed:** Coverage gaps & priorities, Offline scenario testing, Coverage enforcement, Widget test depth

---

## Coverage Gaps & Priorities

| Option | Description | Selected |
|--------|-------------|----------|
| Financial logic first | BalanceCalculator cross-event scenarios, settlement optimization edge cases, MoneySerializer boundaries first. Then services, then widget tests. | ✓ |
| Screen coverage first | Widget tests for untested screens to catch UI regressions. | |
| Even spread | Distribute test writing evenly across layers until 80%. | |

**User's choice:** Financial logic first
**Notes:** None

---

| Option | Description | Selected |
|--------|-------------|----------|
| Skip legacy code | Don't test Supabase-specific code. It's being removed in Phase 7. | ✓ |
| Test everything | Even legacy code gets tests — 80% means 80% of ALL code. | |

**User's choice:** Skip legacy code
**Notes:** None

---

| Option | Description | Selected |
|--------|-------------|----------|
| Core scenarios (~15-20 tests) | All 4 scopes + cross-event aggregation + settlement optimization. | |
| Exhaustive edge cases (~40+ tests) | Core scenarios PLUS zero amounts, single-member, 50+ expenses stress, mixed currencies, over-settlement, concurrent modifications. | ✓ |
| You decide | Claude picks depth. | |

**User's choice:** Exhaustive edge cases
**Notes:** None

---

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, Firestore round-trip tests | Test toFirestore/fromFirestore for all models. | ✓ |
| Skip — service tests cover implicitly | Service tests exercise serialization already. | |
| You decide | Claude determines which models need tests. | |

**User's choice:** Yes, Firestore round-trip tests
**Notes:** None

---

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, dedicated provider tests | Test key providers in isolation with mock services. | ✓ |
| Skip — widget tests enough | Providers exercised through widget tests. | |
| Only complex providers | Only test providers with non-trivial logic. | |

**User's choice:** Yes, dedicated provider tests
**Notes:** None

---

| Option | Description | Selected |
|--------|-------------|----------|
| AppFormatters yes, rest no | AppFormatters has critical money formatting. Theme/transitions not worth testing. | ✓ |
| Test all utilities | Every utility file gets tests. | |
| You decide | Claude picks utilities to test. | |

**User's choice:** AppFormatters yes, rest no
**Notes:** None

---

| Option | Description | Selected |
|--------|-------------|----------|
| Audit + fill gaps | Review existing tests for weak assertions, then write new tests. | ✓ |
| New tests only | Don't touch existing tests, just write new ones. | |
| Quick audit, then new tests | 20% audit, 80% new tests. | |

**User's choice:** Audit + fill gaps
**Notes:** None

---

| Option | Description | Selected |
|--------|-------------|----------|
| Mirror existing | Keep test/unit/, test/features/, test/integration/ structure. | ✓ |
| Reorganize by feature | Move all tests into feature subdirectories. | |

**User's choice:** Mirror existing
**Notes:** None

---

| Option | Description | Selected |
|--------|-------------|----------|
| Critical error paths only | Test Firestore write failures for financial ops, malformed money, auth expiry. | ✓ |
| All error paths | Every service method gets a failure test case. | |
| You decide | Claude picks error paths to test. | |

**User's choice:** Critical error paths only
**Notes:** None

---

| Option | Description | Selected |
|--------|-------------|----------|
| Skip — framework handles it | Riverpod lifecycle is well-tested by the framework. | ✓ |
| Test key lifecycle scenarios | Test invalidation triggers fresh Firestore fetch. | |

**User's choice:** Skip — framework handles it
**Notes:** None

---

## Offline Scenario Testing

| Option | Description | Selected |
|--------|-------------|----------|
| SQLite-only verification | Write expense -> verify SQLite -> verify Firestore document. Tests side-write pipeline. | ✓ |
| Mock-based offline simulation | MockFirestore that throws when 'offline'. | |
| Firebase Emulator integration test | Real emulator with disableNetwork/enableNetwork. | |

**User's choice:** SQLite-only verification
**Notes:** None

---

| Option | Description | Selected |
|--------|-------------|----------|
| 3 core scenarios | Expense write, settlement write, multiple writes. | ✓ |
| 5+ scenarios with all modules | Core 3 plus gear, group settlement, activity log. | |
| You decide | Claude determines scenario count. | |

**User's choice:** 3 core scenarios
**Notes:** None

---

| Option | Description | Selected |
|--------|-------------|----------|
| test/integration/ | Tests interaction between Firestore services and SQLite. | ✓ |
| test/unit/ | Uses fake dependencies, technically unit tests. | |

**User's choice:** test/integration/
**Notes:** None

---

## Coverage Enforcement

| Option | Description | Selected |
|--------|-------------|----------|
| CI only | GitHub Actions fails build if below 80%. No local hook. | ✓ |
| CI + local pre-commit hook | CI + git pre-commit hook runs coverage locally. | |
| Local only | Manual coverage checks, no automation. | |

**User's choice:** CI only
**Notes:** None

---

| Option | Description | Selected |
|--------|-------------|----------|
| Generated + bootstrap only | Exclude: firebase_options.dart, *.g.dart, *.freezed.dart, main.dart, app.dart. | ✓ |
| Generated + Supabase legacy | Same plus all Supabase-specific files. | |
| Minimal exclusions | Only truly generated files. | |

**User's choice:** Generated + bootstrap only
**Notes:** None

---

| Option | Description | Selected |
|--------|-------------|----------|
| Project-wide 80% | Single number for whole codebase. | ✓ |
| Per-feature minimums | Each feature directory must independently hit 80%. | |
| Project-wide + financial floor | 80% overall, 95% for financial code. | |

**User's choice:** Project-wide 80%
**Notes:** None

---

| Option | Description | Selected |
|--------|-------------|----------|
| lcov + CI comment | Generate lcov.info, CI posts summary on PRs. | ✓ |
| lcov only — check locally | Generate lcov.info, developers view HTML locally. | |
| You decide | Claude picks reporting approach. | |

**User's choice:** lcov + CI comment
**Notes:** None

---

## Widget Test Depth

| Option | Description | Selected |
|--------|-------------|----------|
| Render + key interactions | Verify render + key data + primary interactions. ~5-8 tests per screen. | ✓ |
| Render only | Just verify screens build without throwing. ~2-3 tests per screen. | |
| Full interaction flows | Complete user journeys. ~15-20 tests per screen. | |

**User's choice:** Render + key interactions
**Notes:** None

---

| Option | Description | Selected |
|--------|-------------|----------|
| High-traffic screens | Add HomeScreen, GroupSettleUpScreen, LedgerScreen, EventCommandCenter. 7 total. | ✓ |
| All screens | Every screen gets widget tests (~26 files). | |
| Required three only | Only group dashboard, event creation, balance toggle. | |

**User's choice:** High-traffic screens
**Notes:** None

---

| Option | Description | Selected |
|--------|-------------|----------|
| Skip — tested through screens | Shared widgets exercised through screen tests. | ✓ |
| Test shared widgets separately | Each shared widget gets a dedicated test file. | |

**User's choice:** Skip — tested through screens
**Notes:** None

---

| Option | Description | Selected |
|--------|-------------|----------|
| Verify tap triggers — skip destination | Assert Navigator.push called, don't verify destination renders. | ✓ |
| Full navigation chain | Tap -> verify destination screen renders with correct data. | |

**User's choice:** Verify tap triggers — skip destination
**Notes:** None

---

## Claude's Discretion

- Test grouping and ordering within test files
- Exact mock setup patterns for new provider tests
- Balance between test readability and DRY
- Which existing test files need the most audit attention
- CI workflow YAML structure
- lcov report formatting

## Deferred Ideas

- Firebase Emulator integration tests with real offline/online transitions
- Per-feature coverage minimums
- Visual regression testing
- Performance benchmarks as tests
