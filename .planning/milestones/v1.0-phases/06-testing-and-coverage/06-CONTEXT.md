# Phase 6: Testing and Coverage - Context

**Gathered:** 2026-03-27
**Status:** Ready for planning

<domain>
## Phase Boundary

The codebase meets the 80%+ coverage requirement with unit tests for all financial logic, widget tests for key screens, and offline scenario tests. This phase writes tests and configures CI enforcement — no new features, no refactoring, no architectural changes.

</domain>

<decisions>
## Implementation Decisions

### Coverage Gaps & Priorities
- **D-01:** Financial logic first priority order: BalanceCalculator cross-event scenarios and edge cases, settlement optimization, MoneySerializer boundaries. Then services, then widget tests for key screens.
- **D-02:** Skip legacy/Supabase code — don't test Supabase-specific code (trip services, old providers, LazyMigrationService). It's being removed in Phase 7. Focus test budget on Firestore-backed code.
- **D-03:** Exhaustive BalanceCalculator test coverage: all 4 scopes (global, subGroup, personal, custom) + cross-event aggregation + settlement optimization with multi-event data + edge cases (zero amounts, single-member groups, 50+ expenses stress test, mixed currencies, negative balances from over-settlement, concurrent event modifications). ~40+ test cases.
- **D-04:** Add Firestore round-trip tests for all models (Expense, Settlement, Group, Event, GearItem, etc.) — test toFirestore/fromFirestore serialization.
- **D-05:** Add dedicated provider tests for key providers in isolation (eventExpensesProvider, groupBalancesProvider, groupEventsProvider, etc.) with mock services. Catches stream composition bugs that widget tests miss.
- **D-06:** AppFormatters gets tests (money formatting with OMR precision is critical). Skip theme constants and page transition tests.
- **D-07:** Audit existing 39 test files for weak assertions, missing edge cases, and naming consistency. Then write new tests for gaps. Ensures 80% is meaningful coverage, not just line-touching.
- **D-08:** Mirror existing test structure: test/unit/ for services + logic, test/features/ for widget tests, test/integration/ for E2E. New files follow {source_file}_test.dart naming.
- **D-09:** Test critical error paths only: Firestore write failures for financial operations (expenses, settlements), malformed money fields, auth session expiry. Skip non-critical errors (gear save fails, activity log write fails).
- **D-10:** Skip Riverpod provider lifecycle testing (dispose, refresh, invalidate) — framework handles it. Focus on business logic in providers.

### Offline Scenario Testing
- **D-11:** SQLite-only verification approach: write expense via service -> verify it lands in SQLite via BalanceCacheRepository -> verify Firestore document also exists. Tests the side-write pipeline. No Firestore network simulation.
- **D-12:** 3 core offline scenarios: (1) Expense write -> SQLite side-write verified, (2) Settlement write -> SQLite + BalanceCalculator reads correct values, (3) Multiple writes -> all appear in SQLite in correct order.
- **D-13:** Offline tests live in test/integration/ — they test interaction between Firestore services and SQLite.

### Coverage Enforcement
- **D-14:** CI-only enforcement: GitHub Actions runs `flutter test --coverage` and fails the build if below 80%. No local pre-commit hook.
- **D-15:** Exclude from coverage: firebase_options.dart, *.g.dart, *.freezed.dart, main.dart, app.dart. Everything else counts — including screens, widgets, and models.
- **D-16:** Project-wide 80% threshold — single number for the whole codebase. No per-feature minimums.
- **D-17:** lcov + CI comment: generate lcov.info, CI posts summary comment on PRs showing total coverage and per-file deltas.

### Widget Test Depth
- **D-18:** Render + key interactions depth: verify screens render without errors, key data displays correctly, primary interactions work (tap settle-up, toggle balance view, submit event form). ~5-8 test cases per screen.
- **D-19:** Test 7 screens total: required (GroupDetailScreen, CreateEventScreen, balance toggle) + high-traffic (HomeScreen, GroupSettleUpScreen, LedgerScreen, EventCommandCenter).
- **D-20:** Skip dedicated shared widget tests — ModuleHeader, AppTabBar, EmptyStateView tested through screen tests.
- **D-21:** Navigation assertions verify tap triggers (assert Navigator.push called), skip destination screen rendering. Navigation target testing is that screen's own responsibility.

### Claude's Discretion
- Test grouping and ordering within test files
- Exact mock setup patterns for new provider tests
- Balance between test readability and DRY (shared test helpers vs inline setup)
- Which existing test files need the most audit attention
- CI workflow YAML structure for coverage enforcement
- lcov report formatting and PR comment template

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Testing requirements
- `.planning/REQUIREMENTS.md` lines 58-66 — TST-01 through TST-06 acceptance criteria
- `.planning/ROADMAP.md` Phase 6 section — success criteria (80%+ coverage, BalanceCalculator scenarios, widget tests, offline scenario test)

### Existing test infrastructure
- `test/unit/balance_calculations_test.dart` — Existing BalanceCalculator tests (audit + extend)
- `test/unit/settlement_optimization_test.dart` — Existing settlement tests (audit + extend)
- `test/unit/money_serializer_test.dart` — MoneySerializer tests (audit for edge cases)
- `test/unit/expense_service_test.dart` — ExpenseService test pattern with FakeFirebaseFirestore
- `test/unit/group_balance_provider_test.dart` — Provider test pattern with mock services
- `test/integration/firebase_money_roundtrip_test.dart` — Firestore money round-trip pattern

### Financial code under test
- `lib/features/ledger/providers/expense_provider.dart` — BalanceCalculator, expense/settlement providers
- `lib/core/services/money_serializer.dart` — Integer fils serialization
- `lib/core/services/balance_cache_repository.dart` — SQLite side-write (offline scenario target)
- `lib/features/groups/providers/group_balance_provider.dart` — Cross-event balance aggregation

### Widget test targets
- `lib/features/groups/screens/group_detail_screen.dart` — Group dashboard (TST-02)
- `lib/features/events/screens/create_event_screen.dart` — Event creation flow (TST-02)
- `lib/features/groups/screens/group_settle_up_screen.dart` — Cross-event settle-up
- `lib/features/home/screens/home_screen.dart` — Home screen
- `lib/features/ledger/screens/ledger_screen.dart` — Ledger with balance view
- `lib/features/events/screens/event_command_center.dart` — Event hub

### CI/CD
- `.github/workflows/release_android.yml` — Existing CI workflow (extend with coverage step)

### Phase 4/5 test patterns
- `.planning/phases/04-firestore-repository-layer/04-CONTEXT.md` — Layered test approach (D-05 base class, services use FakeFirebaseFirestore)
- `.planning/phases/05-cross-event-financials/05-CONTEXT.md` — D-40/D-41: deferred full coverage to Phase 6, layered test approach confirmed

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `FakeFirebaseFirestore` — In-memory Firestore for service tests. Already used in 12+ test files.
- `mocktail` — Mocking framework for non-Firestore dependencies. Used across all test files.
- `sqflite_common_ffi` — In-memory SQLite for database tests. Established in Phase 1.
- Existing test patterns for services, providers, and widgets that new tests can follow.
- `test/unit/balance_calculations_test.dart` — Base to extend with 40+ exhaustive test cases.

### Established Patterns
- Service tests: `ServiceName.withFirestore(fakeDb)` constructor for FakeFirebaseFirestore injection
- Provider tests: `ProviderContainer` with overridden providers, pump with `Future.delayed(Duration.zero)`
- Widget tests: `ProviderScope.overrides` with mock providers, `tester.pumpAndSettle()`
- Integration tests: Full provider chain with FakeFirebaseFirestore + in-memory SQLite

### Integration Points
- GitHub Actions workflow needs new coverage step added to existing release_android.yml
- lcov.info generation integrates with `flutter test --coverage` output
- Coverage exclusions need lcov filter configuration

</code_context>

<specifics>
## Specific Ideas

- Exhaustive BalanceCalculator tests are the crown jewel of this phase — financial precision is the app's core value proposition, and edge cases (over-settlement, zero amounts, single-member) are where real bugs hide.
- Existing test audit before writing new tests ensures the 80% number is meaningful — weak assertions that touch lines but don't verify behavior are worse than no tests.
- SQLite-only offline verification is pragmatic — true offline simulation requires Firebase Emulator integration tests that can't run in standard `flutter test`, and the side-write pipeline is the critical path to verify.

</specifics>

<deferred>
## Deferred Ideas

- Firebase Emulator integration tests with real offline/online transitions — requires emulator running, slower, separate CI job. Consider for v2.
- Per-feature coverage minimums (e.g., ledger/ must be 95%) — adds CI complexity. Revisit if coverage distribution becomes uneven.
- Visual regression testing for widget tests — screenshot comparison testing adds tooling complexity. Not needed for 80% coverage target.
- Performance benchmarks as tests (BalanceCalculator with 1000+ expenses) — useful but not a coverage concern.

</deferred>

---

*Phase: 06-testing-and-coverage*
*Context gathered: 2026-03-27*
