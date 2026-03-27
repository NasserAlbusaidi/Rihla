# Phase 6: Testing and Coverage - Research

**Researched:** 2026-03-27
**Domain:** Flutter testing — unit, widget, integration, and CI coverage enforcement
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Coverage Gaps & Priorities**
- D-01: Financial logic first priority order: BalanceCalculator cross-event scenarios and edge cases, settlement optimization, MoneySerializer boundaries. Then services, then widget tests for key screens.
- D-02: Skip legacy/Supabase code — don't test Supabase-specific code (trip services, old providers, LazyMigrationService). It's being removed in Phase 7. Focus test budget on Firestore-backed code.
- D-03: Exhaustive BalanceCalculator test coverage: all 4 scopes (global, subGroup, personal, custom) + cross-event aggregation + settlement optimization with multi-event data + edge cases (zero amounts, single-member groups, 50+ expenses stress test, mixed currencies, negative balances from over-settlement, concurrent event modifications). ~40+ test cases.
- D-04: Add Firestore round-trip tests for all models (Expense, Settlement, Group, Event, GearItem, etc.) — test toFirestore/fromFirestore serialization.
- D-05: Add dedicated provider tests for key providers in isolation (eventExpensesProvider, groupBalancesProvider, groupEventsProvider, etc.) with mock services. Catches stream composition bugs that widget tests miss.
- D-06: AppFormatters gets tests (money formatting with OMR precision is critical). Skip theme constants and page transition tests.
- D-07: Audit existing 39 test files for weak assertions, missing edge cases, and naming consistency. Then write new tests for gaps. Ensures 80% is meaningful coverage, not just line-touching.
- D-08: Mirror existing test structure: test/unit/ for services + logic, test/features/ for widget tests, test/integration/ for E2E. New files follow {source_file}_test.dart naming.
- D-09: Test critical error paths only: Firestore write failures for financial operations (expenses, settlements), malformed money fields, auth session expiry. Skip non-critical errors (gear save fails, activity log write fails).
- D-10: Skip Riverpod provider lifecycle testing (dispose, refresh, invalidate) — framework handles it. Focus on business logic in providers.

**Offline Scenario Testing**
- D-11: SQLite-only verification approach: write expense via service -> verify it lands in SQLite via BalanceCacheRepository -> verify Firestore document also exists. Tests the side-write pipeline. No Firestore network simulation.
- D-12: 3 core offline scenarios: (1) Expense write -> SQLite side-write verified, (2) Settlement write -> SQLite + BalanceCalculator reads correct values, (3) Multiple writes -> all appear in SQLite in correct order.
- D-13: Offline tests live in test/integration/ — they test interaction between Firestore services and SQLite.

**Coverage Enforcement**
- D-14: CI-only enforcement: GitHub Actions runs `flutter test --coverage` and fails the build if below 80%. No local pre-commit hook.
- D-15: Exclude from coverage: firebase_options.dart, *.g.dart, *.freezed.dart, main.dart, app.dart. Everything else counts — including screens, widgets, and models.
- D-16: Project-wide 80% threshold — single number for the whole codebase. No per-feature minimums.
- D-17: lcov + CI comment: generate lcov.info, CI posts summary comment on PRs showing total coverage and per-file deltas.

**Widget Test Depth**
- D-18: Render + key interactions depth: verify screens render without errors, key data displays correctly, primary interactions work (tap settle-up, toggle balance view, submit event form). ~5-8 test cases per screen.
- D-19: Test 7 screens total: required (GroupDetailScreen, CreateEventScreen, balance toggle) + high-traffic (HomeScreen, GroupSettleUpScreen, LedgerScreen, EventCommandCenter).
- D-20: Skip dedicated shared widget tests — ModuleHeader, AppTabBar, EmptyStateView tested through screen tests.
- D-21: Navigation assertions verify tap triggers (assert Navigator.push called), skip destination screen rendering.

### Claude's Discretion
- Test grouping and ordering within test files
- Exact mock setup patterns for new provider tests
- Balance between test readability and DRY (shared test helpers vs inline setup)
- Which existing test files need the most audit attention
- CI workflow YAML structure for coverage enforcement
- lcov report formatting and PR comment template

### Deferred Ideas (OUT OF SCOPE)
- Firebase Emulator integration tests with real offline/online transitions
- Per-feature coverage minimums (e.g., ledger/ must be 95%)
- Visual regression testing for widget tests
- Performance benchmarks as tests (BalanceCalculator with 1000+ expenses)
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| TST-01 | Unit tests for all financial calculations (balance, settlement optimization, cross-event aggregation) | BalanceCalculator (60.4% covered), settlement_optimization_test.dart and balance_calculations_test.dart exist but need expansion per D-03. MoneySerializer at 100%. gap is BalanceCalculator edge cases and model serialization. |
| TST-02 | Widget tests for group dashboard, event creation, balance toggle | GroupDetailScreen (76.5%), CreateEventScreen (64.9%), balance toggle in GroupDetailScreen — existing tests in group_screens_test.dart and create_event_test.dart. Gaps are the 7 D-19 screens needing deeper interaction coverage. |
| TST-05 | 80%+ code coverage enforced | Current baseline: 28.7% (2526/8816 lines). CRITICAL GAP — see Coverage Gap Analysis section. CI step must be added to release_android.yml with lcov filtering. |
| TST-06 | Offline scenario tests (write while offline, verify sync on reconnect) | BalanceCacheRepository (83.7% covered), integration pattern established in firebase_money_roundtrip_test.dart. D-11 defines SQLite-only approach. 3 scenarios needed per D-12. |
</phase_requirements>

---

## Summary

Phase 6 is a test-only phase: no new features, no refactoring. The codebase enters with 39 test files, 314 passing tests, and 9 failing tests caused by three distinct issues (Firebase not initialized in group_service_test.dart, missing CommandCenter import in command_center_test.dart, and a duplicate text widget assertion in group_detail_events_test.dart). The current line coverage is 28.7% — far below the 80% target.

The most important research finding is a **decision conflict**: D-15 says "everything else counts" (including legacy screens), while D-02 says "skip legacy/Supabase code." These decisions pull in opposite directions. The lcov exclusion list in D-15 only mentions firebase_options.dart, *.g.dart, *.freezed.dart, main.dart, and app.dart — which means the ~3,163 lines of legacy trip/logistics/gear/memories/vault/settings code ARE counted toward the 80% threshold. Testing legacy screens that are being deleted in Phase 7 contradicts D-02. The planner must resolve this by expanding the lcov exclusion list to include legacy paths, or the 80% target becomes unachievable without contradicting D-02.

The test infrastructure is well-established. FakeFirebaseFirestore, sqflite_common_ffi, mocktail, and firebase_auth_mocks are already installed and used in 12+ files. The established patterns (ServiceName.withFirestore(fakeDb), ProviderContainer with overrides, ProviderScope.overrides for widgets) are consistent across the codebase and should be followed exactly.

**Primary recommendation:** Fix the 9 failing tests first (wave 0), resolve the lcov exclusion scope to make 80% achievable, then write new tests in priority order: BalanceCalculator edge cases, model serialization round-trips, offline integration scenarios, and widget tests for the 7 D-19 screens.

---

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `flutter_test` | sdk: flutter (Flutter 3.41.5) | Unit + widget test runner | Built into Flutter SDK, no install needed |
| `fake_cloud_firestore` | `^4.1.0+1` | In-memory Firestore for service tests | Standard approach; already used in 12+ test files in this codebase |
| `mocktail` | `^1.0.4` | Mocking for non-Firestore dependencies | Already installed; used across all test files |
| `firebase_auth_mocks` | `^0.15.1` | Mock Firebase Auth | Already installed; provides MockFirebaseAuth |
| `sqflite_common_ffi` | `^2.3.4` | In-memory SQLite for database tests | Already installed; established in Phase 1 |

### CI Coverage Tooling
| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| `flutter test --coverage` | Built-in | Generates coverage/lcov.info | Run in CI before coverage check |
| `lcov` (ubuntu package) | system | Parse and filter lcov.info | GitHub Actions: `sudo apt-get install lcov` |
| `flutter_gen_coverage` action or manual lcov --remove | — | Filter exclusions from lcov.info | Remove firebase_options, generated files, legacy paths |
| `romeovs/lcov-reporter-action` | v0.4.0 | Post coverage comment on PRs | GitHub Action for D-17 PR comment |

**Installation (CI only — dev dependencies already installed):**
```bash
# No new pub dependencies needed for tests.
# lcov tool installed in CI:
sudo apt-get install -y lcov
```

---

## Architecture Patterns

### Test Directory Structure (Established — Do Not Change)
```
test/
├── unit/                        # Pure logic: services, models, providers
│   ├── balance_calculations_test.dart   # Extend per D-03
│   ├── settlement_optimization_test.dart # Extend (edge cases)
│   ├── money_serializer_test.dart        # Already complete
│   ├── expense_service_test.dart         # Pattern reference
│   ├── group_balance_provider_test.dart  # Pattern reference
│   └── {source_file}_test.dart          # New files follow this naming
├── features/                    # Widget tests per screen
│   ├── groups/group_screens_test.dart
│   ├── events/create_event_test.dart
│   ├── home/home_screen_groups_test.dart
│   └── {feature}/{screen}_test.dart     # New files follow this naming
└── integration/                 # Full provider chain E2E
    ├── happy_path_test.dart
    ├── firebase_money_roundtrip_test.dart
    └── {scenario}_test.dart             # New offline scenario files
```

### Pattern 1: Service Tests with FakeFirebaseFirestore
**What:** Inject FakeFirebaseFirestore via named constructor, test Firestore reads/writes directly.
**When to use:** All service tests that touch Firestore collections.
```dart
// Source: test/unit/expense_service_test.dart (established pattern)
late FakeFirebaseFirestore fakeDb;
late ExpenseService service;

setUp(() {
  fakeDb = FakeFirebaseFirestore();
  service = ExpenseService.withFirestore(fakeDb);
});

test('writes expense with correct amountFils', () async {
  final expense = await service.addExpense(
    groupId: 'g1', eventId: 'e1',
    payerParticipantId: 'p1',
    amount: Decimal.parse('10.500'),
  );
  final snap = await fakeDb
    .collection('groups').doc('g1')
    .collection('events').doc('e1')
    .collection('expenses').doc(expense.id).get();
  expect(snap.data()!['amountFils'], equals(10500));
});
```

### Pattern 2: Provider Tests with ProviderContainer
**What:** Create ProviderContainer with stream overrides, pump async queue, read final state.
**When to use:** All provider-level tests (groupBalancesProvider, eventExpensesProvider, etc.)
```dart
// Source: test/unit/group_balance_provider_test.dart (established pattern)
Future<void> _pumpUntilData(ProviderContainer container, String groupId) async {
  container.listen(groupBalancesProvider(groupId), (_, __) {}, fireImmediately: true);
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

final container = ProviderContainer(overrides: [
  groupEventsProvider(groupId).overrideWith((_) => Stream.value([eventA])),
  eventExpensesProvider((groupId: groupId, eventId: 'event-a'))
    .overrideWith((_) => Stream.value(expenses)),
  // ... all dependent providers must be overridden
]);
addTearDown(container.dispose);
await _pumpUntilData(container, groupId);
final result = container.read(groupBalancesProvider(groupId));
expect(result, isA<AsyncData<GroupBalances>>());
```

**Critical:** Provider.family with cascaded StreamProvider dependencies requires 10 rounds of `Future.delayed(Duration.zero)` — not `Future.microtask`. Established in Phase 5 (STATE.md entry).

### Pattern 3: Widget Tests with ProviderScope Overrides
**What:** Wrap widget in ProviderScope with all touching providers overridden, pumpAndSettle.
**When to use:** All widget tests for screens.
```dart
// Source: test/features/groups/group_screens_test.dart (established pattern)
Widget _wrap(Widget child, SharedPreferences prefs) {
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      groupDetailProvider('group-1').overrideWith(
        (ref) => Stream.value(_testGroup),
      ),
      groupMembersProvider('group-1').overrideWith(
        (ref) => Stream.value(_testMembers),
      ),
      // ALL providers the widget reads must be overridden
    ],
    child: MaterialApp(home: child),
  );
}

testWidgets('shows group name in header', (tester) async {
  await tester.pumpWidget(_wrap(const GroupDetailScreen(groupId: 'group-1'), prefs));
  await tester.pumpAndSettle();
  expect(find.text('Adventure Crew'), findsWidgets);
});
```

**Critical:** SharedPreferences must be overridden for any screen that reads settings. Pattern: `SharedPreferences.setMockInitialValues({'device_name': 'Test User'})` in setUpAll.

### Pattern 4: SQLite Integration Tests
**What:** Initialize sqflite_common_ffi, clear DB between tests, test service + SQLite side-write pipeline.
**When to use:** Offline scenario tests in test/integration/.
```dart
// Source: test/unit/balance_cache_repository_test.dart (established pattern)
setUpAll(() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
});

setUp(() async {
  await LocalDatabase.clearAll();
});

tearDownAll(() async {
  await LocalDatabase.close();
});
```

### Anti-Patterns to Avoid
- **Reading `FirebaseFirestore.instance` directly in tests:** Always use `.withFirestore(fakeDb)` constructor. Services that call `FirebaseFirestore.instance` throw `[core/no-app] No Firebase App '[DEFAULT]'` in tests.
- **Missing provider overrides in widget tests:** If ANY provider the widget watches is not overridden, the test will try to initialize real Firebase and fail.
- **Using `Future.microtask` for Provider.family pump:** Insufficient for cascaded stream delivery. Use `Future.delayed(Duration.zero)` in a loop (10x established as sufficient).
- **`findsOneWidget` for text that appears in multiple places:** Many screens show the same value in multiple widgets (e.g., amount in a card header AND a summary row). Use `findsWidgets` or `findsNWidgets(2)` instead.
- **Not calling `addTearDown(container.dispose)`:** ProviderContainer must be disposed or test isolation breaks.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| In-memory Firestore for tests | Custom Firestore mock | `FakeFirebaseFirestore` | Firestore's internal API surface is too large; already used in 12+ files |
| In-memory SQLite for tests | Real file-backed SQLite | `sqflite_common_ffi` with `databaseFactoryFfi` | Test isolation requires fresh state per test; file-backed DBs bleed state |
| lcov coverage filtering | Custom script | `lcov --remove lcov.info 'patterns'` | Standard lcov CLI flag; works perfectly for excluding generated/legacy files |
| PR coverage comment | Manually writing comments | `romeovs/lcov-reporter-action` | Maintained GitHub Action that parses lcov.info and posts PR comments |
| Stream pump timing | Custom `Stream.asyncExpand` | `Future.delayed(Duration.zero)` loop (10x) | Established by Phase 5 work for Provider.family cascade timing |

**Key insight:** The hardest part of this phase is not writing tests — it is getting the lcov exclusion configuration right so that the 80% threshold is measured against meaningful code.

---

## Critical Finding: Coverage Gap Analysis

This is the most important planning input for Phase 6.

### Current State (from coverage/lcov.info, last run before Phase 6)
| Metric | Value |
|--------|-------|
| Total .dart files in lib/ | 118 |
| Files instrumented in lcov.info | 102 |
| Files never touched by any test | 16 |
| Total instrumented lines | 8,821 |
| Lines currently covered | 2,526 |
| Current coverage (full codebase) | **28.7%** |

### Coverage by Category
| Category | Covered/Total | % | Notes |
|----------|--------------|---|-------|
| Financial/groups/events (priority) | 1,964/4,455 | 44.1% | Primary target |
| Shared/core | 365/1,545 | 23.6% | Some legacy |
| Legacy screens (trip, logistics, gear, memories, vault, settings) | 188/1,784 | 10.5% | D-02: SKIP |
| Supabase services (cache_service, lazy_migration) | 11/521 | 2.1% | D-02: SKIP |
| Legacy trip features | 4/848 | 0.5% | D-02: SKIP |

### The Decision Conflict: D-02 vs D-15
D-15 says "Everything else counts — including screens, widgets, and models."
D-02 says "Skip legacy/Supabase code."

These decisions are contradictory when applied to lcov measurement:

| Scenario | Effective Lines | Current Coverage | Lines Needed for 80% |
|----------|----------------|-----------------|----------------------|
| D-15 literal (all lines count) | 8,821 | 28.7% | **4,526 more lines** — requires testing legacy screens |
| D-15 + exclude legacy per D-02 spirit | 5,653 | 41.1% | **2,201 more lines** — still significant |
| Financial/groups/events only | 4,455 | 44.1% | **1,600 more lines** — most achievable |

**The planner must resolve this by specifying the exact `lcov --remove` patterns used in CI.** The recommended resolution: expand D-15 exclusions to include the legacy paths that D-02 says to skip. This makes 80% achievable without contradicting D-02.

**Recommended lcov exclusion list for CI:**
```bash
lcov --remove coverage/lcov.info \
  'lib/firebase_options.dart' \
  'lib/main.dart' \
  'lib/app.dart' \
  '*.g.dart' \
  '*.freezed.dart' \
  'lib/features/trip/*' \
  'lib/features/logistics/*' \
  'lib/features/gear/*' \
  'lib/features/memories/*' \
  'lib/features/vault/*' \
  'lib/features/settings/*' \
  'lib/core/services/cache_service.dart' \
  'lib/core/services/lazy_migration_service.dart' \
  'lib/core/services/sync_service.dart' \
  -o coverage/lcov_filtered.info
```

With this exclusion, the baseline is 41.1% of 5,653 lines, and 80% requires covering ~2,200 more lines — achievable through the D-19 widget tests plus unit test gaps.

### Highest-Value Uncovered Files (priority order)
| File | Lines | Current % | Uncovered Lines |
|------|-------|-----------|-----------------|
| features/ledger/screens/ledger_screen.dart | 365 | 60.8% | 143 |
| features/groups/screens/group_detail_screen.dart | 238 | 76.5% | 56 |
| features/groups/screens/group_settle_up_screen.dart | 281 | 63.9% | 101 |
| features/events/screens/create_event_screen.dart | 194 | 64.9% | 68 |
| features/ledger/providers/expense_provider.dart | 144 | 60.4% | 57 |
| features/groups/providers/group_provider.dart | 103 | 13.6% | 89 |
| features/events/providers/event_provider.dart | 43 | 20.9% | 34 |
| features/groups/screens/create_group_screen.dart | 106 | 0.9% | 105 |
| features/groups/screens/join_group_screen.dart | 66 | 1.5% | 65 |
| features/ledger/models/expense_model.dart | 110 | 41.8% | 64 |
| features/ledger/models/settlement_model.dart | 62 | 50.0% | 31 |

---

## Failing Tests That Must Be Fixed First (Wave 0)

There are currently **9 failing tests** across 3 files. These must be fixed before writing new tests or running coverage.

### Failure 1: command_center_test.dart (1 file fails to compile)
**Root cause:** Imports `lib/features/home/screens/command_center.dart` which no longer exists (was replaced with home_screen.dart during Phase 2/3 migration).
**Fix:** Delete `test/features/command_center_test.dart` (it tests a widget that no longer exists) or redirect to `home_screen.dart` if the tests still apply.

### Failure 2: group_service_test.dart (3 tests fail)
**Root cause:** Tests try to read `groupServiceProvider` via `ProviderContainer.read()` without Firebase initialized. Error: `[core/no-app] No Firebase App '[DEFAULT]' has been created`.
**Fix:** Use `MockFirebaseFirestore` or override the Firebase-dependent provider with a mock, same pattern as all other service tests.

### Failure 3: group_detail_events_test.dart (4 tests fail)
**Root cause 1 (3 tests):** EventCard tests fail because they reference a widget/provider that was renamed or changed in Phase 5 (EventCard financial display).
**Root cause 2 (1 test - "shows 0.000 OMR"):** `findsOneWidget` assertion fails because "0.000 OMR" text appears in MULTIPLE widgets (the card shows it in two Text widgets with different styles). Use `findsWidgets` instead.

### Failure 4: group_join_test.dart (1 test fails)
**Root cause:** Same Firebase not initialized issue as group_service_test.dart.

---

## Common Pitfalls

### Pitfall 1: Firebase Not Initialized in Tests
**What goes wrong:** Tests that use a `Provider` which internally calls `FirebaseFirestore.instance` throw `[core/no-app]` error even if the test doesn't explicitly use Firebase.
**Why it happens:** Riverpod providers can be lazy — when `ProviderContainer.read()` is called, it initializes the provider which calls the real Firebase SDK.
**How to avoid:** Every test that reads a Firebase-touching provider MUST either (a) override the provider with a mock, or (b) use the `.withFirestore(fakeDb)` constructor pattern. Never rely on provider defaults in tests.
**Warning signs:** `[core/no-app] No Firebase App '[DEFAULT]'` in test output.

### Pitfall 2: Missing Provider Overrides in Widget Tests
**What goes wrong:** Widget test crashes or produces incorrect state because a provider reads from real Firebase.
**Why it happens:** Screens often watch multiple providers; easy to miss one.
**How to avoid:** Before writing any widget test, read the screen's build() method and list every `ref.watch(...)` call. Override all of them.
**Warning signs:** Test passes in isolation but fails when run in full suite; errors about Firebase initialization.

### Pitfall 3: `findsOneWidget` vs `findsWidgets` for Repeated Text
**What goes wrong:** Test uses `findsOneWidget` but the text appears in multiple widget tree nodes (e.g., an amount shown in a summary row AND a detail card).
**Why it happens:** Many screens display the same data value in multiple places for design reasons.
**How to avoid:** Use `findsWidgets` as default for text assertions, use `findsOneWidget` only when you are certain the text appears exactly once (section headers, appbar titles).
**Warning signs:** "Expected: exactly one matching node; Actual: 2 nodes" in test output. Already hit in group_detail_events_test.dart.

### Pitfall 4: Provider.family Cascade Timing
**What goes wrong:** `groupBalancesProvider` reads `AsyncLoading` even after await because the cascaded stream providers haven't delivered values yet.
**Why it happens:** `Provider.family` that watches `StreamProvider.family` values needs multiple microtask + event loop rounds for each layer of the cascade.
**How to avoid:** Use the established `_pumpUntilData` helper (10x `Future.delayed(Duration.zero)` loop). Don't use `Future.microtask` — it only drains the microtask queue, not the event loop.
**Warning signs:** `result` is `AsyncLoading` when you expected `AsyncData`.

### Pitfall 5: BalanceCalculator personal/subGroup scope edge cases
**What goes wrong:** BalanceCalculator returns wrong net for personal expenses or subGroup expenses when participant sets differ.
**Why it happens:** Personal scope only creates a charge for the payer (no split). SubGroup scope requires `subGroups` parameter — if omitted or if `subGroupId` doesn't match, the expense falls through to zero split.
**How to avoid:** When testing `ExpenseScope.personal`, verify that totalOwed == totalPaid for the payer (net = 0, not paying for others). When testing `ExpenseScope.subGroup`, always pass the `subGroups` parameter.
**Warning signs:** Unexpected zero balances in subGroup tests when subGroups param is missing.

### Pitfall 6: lcov.info Stale from Prior Run
**What goes wrong:** CI reports wrong coverage because `coverage/lcov.info` is from a previous run with different test state.
**Why it happens:** `flutter test --coverage` appends to existing lcov.info by default in some environments.
**How to avoid:** Always delete `coverage/lcov.info` before running `flutter test --coverage` in CI. In CI step: `rm -f coverage/lcov.info && flutter test --coverage`.

---

## Code Examples

### BalanceCalculator — Personal Scope Test
```dart
// Pattern for D-03 personal scope coverage
test('Personal scope: only payer is charged, others unaffected', () {
  final expense = Expense(
    id: 'e1', tripId: 't1',
    payerParticipantId: 'p1',
    amount: Decimal.parse('15.000'),
    scope: ExpenseScope.personal,
    createdAt: DateTime(2026),
  );
  final balances = BalanceCalculator.calculateBalances(
    expenses: [expense], participants: participants,
  );
  final b1 = balances.firstWhere((b) => b.participantId == 'p1');
  final b2 = balances.firstWhere((b) => b.participantId == 'p2');
  // Personal = payer pays for themselves only, net = 0
  expect(b1.netBalance, Decimal.zero);
  expect(b2.netBalance, Decimal.zero);
});
```

### BalanceCalculator — Negative Balance (Over-settlement) Edge Case
```dart
// D-03: negative balances from over-settlement
test('Over-settlement: settlement exceeds debt creates negative balance', () {
  final expenses = [
    Expense(
      id: 'e1', tripId: 't1', payerParticipantId: 'p1',
      amount: Decimal.parse('10.000'), scope: ExpenseScope.global,
      createdAt: DateTime(2026),
    ),
  ];
  // p2 owes p1 only 5.000, but settles 10.000 (over-payment)
  final settlements = [
    Settlement(
      id: 's1', tripId: 't1',
      payerParticipantId: 'p2', recipientParticipantId: 'p1',
      amount: Decimal.parse('10.000'), settledAt: DateTime(2026),
    ),
  ];
  final balances = BalanceCalculator.calculateBalances(
    expenses: expenses, participants: participants,
    settlements: settlements,
  );
  final b2 = balances.firstWhere((b) => b.participantId == 'p2');
  // p2 paid 10 as settlement but only owed 5 -> net = +5 (creditor now)
  expect(b2.netBalance, Decimal.parse('5.000'));
});
```

### Offline Scenario Integration Test (D-11 pattern)
```dart
// Source: test/integration/ — new file following firebase_money_roundtrip pattern
// Uses FakeFirebaseFirestore + sqflite_common_ffi
setUpAll(() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
});

setUp(() async { await LocalDatabase.clearAll(); });
tearDownAll(() async { await LocalDatabase.close(); });

test('Scenario 1: expense write lands in both Firestore and SQLite', () async {
  final fakeDb = FakeFirebaseFirestore();
  final expenseService = ExpenseService.withFirestore(fakeDb);
  final repo = BalanceCacheRepository();

  final expense = await expenseService.addExpense(
    groupId: 'g1', eventId: 'e1',
    payerParticipantId: 'p1',
    amount: Decimal.parse('10.500'),
  );

  // Verify Firestore write
  final snap = await fakeDb
    .collection('groups').doc('g1')
    .collection('events').doc('e1')
    .collection('expenses').doc(expense.id).get();
  expect(snap.exists, isTrue);
  expect(snap.data()!['amountFils'], equals(10500));

  // Simulate the SQLite side-write that the Firestore listener triggers
  await repo.cacheExpenses('e1', [expense]);

  // Verify SQLite read
  final cached = await repo.getExpenses('e1');
  expect(cached, hasLength(1));
  expect(cached.first.amount, equals(Decimal.parse('10.500')));

  repo.dispose();
});
```

### CI Coverage Step (GitHub Actions YAML)
```yaml
# Add BEFORE the build step in release_android.yml
- name: Run Tests with Coverage
  run: |
    rm -f coverage/lcov.info
    flutter test --coverage

- name: Filter Coverage (exclude generated and legacy files)
  run: |
    sudo apt-get install -y lcov
    lcov --remove coverage/lcov.info \
      'lib/firebase_options.dart' \
      'lib/main.dart' \
      'lib/app.dart' \
      '*.g.dart' \
      '*.freezed.dart' \
      'lib/features/trip/*' \
      'lib/features/logistics/*' \
      'lib/features/gear/*' \
      'lib/features/memories/*' \
      'lib/features/vault/*' \
      'lib/features/settings/*' \
      'lib/core/services/cache_service.dart' \
      'lib/core/services/lazy_migration_service.dart' \
      -o coverage/lcov_filtered.info

- name: Check Coverage Threshold (80%)
  run: |
    COVERAGE=$(lcov --summary coverage/lcov_filtered.info 2>&1 \
      | grep "lines" | grep -oP '\d+\.\d+(?=%)' | head -1)
    echo "Coverage: ${COVERAGE}%"
    if (( $(echo "$COVERAGE < 80" | bc -l) )); then
      echo "FAIL: Coverage ${COVERAGE}% is below 80% threshold"
      exit 1
    fi

- name: Post Coverage Comment on PR
  uses: romeovs/lcov-reporter-action@v0.4.0
  if: github.event_name == 'pull_request'
  with:
    lcov-file: coverage/lcov_filtered.info
    github-token: ${{ secrets.GITHUB_TOKEN }}
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `OfflineRepository` for all SQLite | `BalanceCacheRepository` (narrow wrapper) | Phase 4 | Tests use repo.cacheExpenses/getExpenses directly |
| `SyncService` polling for offline | Firestore offline persistence + SQLite side-write | Phase 4 | Offline tests verify SQLite side-write, not sync queue |
| Supabase anonymous auth in tests | `MockFirebaseAuth` from firebase_auth_mocks | Phase 1 | Tests import MockFirebaseAuth, not Supabase |
| `tripExpensesProvider/tripSettlementsProvider` | `eventExpensesProvider/eventSettlementsProvider` (EventRef) | Phase 4 | Old providers are deprecated shims — test new ones |

**Deprecated/outdated:**
- `tripBalancesProvider`: Removed entirely in Phase 4 (no tests reference it).
- `CommandCenter` widget at `lib/features/home/screens/command_center.dart`: No longer exists. `test/features/command_center_test.dart` needs deletion or replacement.
- `tripExpensesProvider` / `tripSettlementsProvider`: Kept as deprecated shims — new tests should use `eventExpensesProvider` / `eventSettlementsProvider` exclusively.

---

## Open Questions

1. **lcov Exclusion Scope**
   - What we know: D-15 says 5 exclusions; D-02 says skip legacy Supabase code.
   - What's unclear: Are legacy screens (trip/, logistics/, gear/, etc.) in or out of the 80% measurement?
   - Recommendation: Expand D-15 exclusions to include legacy paths (see recommended exclusion list in Coverage Gap Analysis). Without this, 80% is not achievable without contradicting D-02. The planner should make this explicit in the CI step definition.

2. **command_center_test.dart Disposition**
   - What we know: The file fails to compile because `CommandCenter` widget no longer exists.
   - What's unclear: Are any of the test cases in this file still relevant to the current HomeScreen?
   - Recommendation: Read the test file's test cases, check if they apply to `HomeScreen`, and either adapt or delete. Most likely delete — HomeScreen already has `home_screen_groups_test.dart`.

3. **group_service_test.dart Firebase Provider Tests**
   - What we know: 3 tests fail because they read `groupServiceProvider` directly.
   - What's unclear: Is `groupServiceProvider` being used in production code via Riverpod, or is it a provider-level integration test?
   - Recommendation: If `groupServiceProvider` is a real Riverpod provider in production, mock Firebase at the provider level using `container.overrides` with `MockFirebaseAuth`. If it's testing the provider registration mechanism, those tests can simply be deleted as they test Riverpod infrastructure, not business logic.

4. **group_detail_events_test.dart Interaction Tests**
   - What we know: 3 tests fail for reasons beyond the "finds too many" assertion bug. The EventCard test failures suggest the EventCard widget or tripExpensesProvider changed in Phase 5.
   - What's unclear: Exact nature of the 3 other failures (EventCard financial total, opacity, navigation).
   - Recommendation: Wave 0 must diagnose and fix these — they are the baseline for the existing test suite being green.

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Flutter SDK | All tests | Yes | 3.41.5 (stable) | — |
| Dart SDK | All tests | Yes | 3.11.3 | — |
| `fake_cloud_firestore` | Service tests | Yes (in pubspec.yaml) | ^4.1.0+1 | — |
| `mocktail` | Provider/service mocking | Yes (in pubspec.yaml) | ^1.0.4 | — |
| `sqflite_common_ffi` | SQLite integration tests | Yes (in pubspec.yaml) | ^2.3.4 | — |
| `firebase_auth_mocks` | Auth testing | Yes (in pubspec.yaml) | ^0.15.1 | — |
| `lcov` CLI | CI coverage filtering | No (not installed locally) | — | Install in CI: `sudo apt-get install lcov` |
| `genhtml` | HTML report (optional) | No | — | Skip HTML report; use lcov-reporter-action for PRs |

**Missing dependencies with fallback:**
- `lcov` CLI: Not installed on dev machine. Install in CI with `sudo apt-get install -y lcov`. Local development does not need lcov — use `flutter test --coverage` and inspect the raw lcov.info or use VS Code Flutter coverage extension.

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | flutter_test (Flutter 3.41.5 SDK) |
| Config file | None — standard `flutter test` discovery |
| Quick run command | `flutter test test/unit/balance_calculations_test.dart` |
| Full suite command | `flutter test` |
| Coverage command | `flutter test --coverage` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| TST-01 | BalanceCalculator: all 4 scopes + edge cases (~40 tests) | unit | `flutter test test/unit/balance_calculations_test.dart -x` | Exists, needs expansion |
| TST-01 | Settlement optimization: min-transactions algorithm, multi-event | unit | `flutter test test/unit/settlement_optimization_test.dart -x` | Exists, needs expansion |
| TST-01 | MoneySerializer: boundary values, unsupported currencies | unit | `flutter test test/unit/money_serializer_test.dart -x` | Exists, complete |
| TST-01 | Model Firestore round-trips: all models toFirestore/fromFirestore | unit | `flutter test test/unit/firebase_model_roundtrip_test.dart -x` | Needs creation |
| TST-01 | AppFormatters: OMR money formatting, edge cases | unit | `flutter test test/unit/formatters_test.dart -x` | Exists (verify coverage) |
| TST-02 | GroupDetailScreen: render, member count, balance display | widget | `flutter test test/features/groups/group_screens_test.dart -x` | Exists, needs expansion |
| TST-02 | CreateEventScreen: type picker, participant selection, submit | widget | `flutter test test/features/events/create_event_test.dart -x` | Exists, needs expansion |
| TST-02 | Balance toggle: per-event vs group view toggle interaction | widget | `flutter test test/features/groups/group_screens_test.dart -x` | Needs addition to group_screens_test.dart |
| TST-02 | HomeScreen: group list, FAB, navigation | widget | `flutter test test/features/home/home_screen_groups_test.dart -x` | Exists, verify coverage |
| TST-02 | GroupSettleUpScreen: member list, amounts, settle action | widget | `flutter test test/features/groups/group_settle_up_screen_test.dart -x` | Exists, needs expansion |
| TST-02 | LedgerScreen: expenses list, add expense, balance display | widget | `flutter test test/features/ledger_test.dart -x` | Exists, needs expansion |
| TST-02 | EventCommandCenter: module cards, navigation | widget | `flutter test test/features/events/event_command_center_test.dart -x` | Exists, needs expansion |
| TST-05 | 80%+ line coverage on filtered codebase | coverage | `flutter test --coverage && lcov --summary coverage/lcov_filtered.info` | CI step: needs creation |
| TST-06 | Expense write -> SQLite side-write verified | integration | `flutter test test/integration/offline_scenario_test.dart -x` | Needs creation |
| TST-06 | Settlement write -> SQLite + BalanceCalculator correct | integration | `flutter test test/integration/offline_scenario_test.dart -x` | Needs creation |
| TST-06 | Multiple writes -> correct order in SQLite | integration | `flutter test test/integration/offline_scenario_test.dart -x` | Needs creation |

### Sampling Rate
- **Per task commit:** `flutter test` (full suite, ~10 seconds)
- **Per wave merge:** `flutter test --coverage && lcov --summary coverage/lcov.info`
- **Phase gate:** Full suite green, filtered coverage >= 80% before `/gsd:verify-work`

### Wave 0 Gaps (Must exist before implementation begins)
- [ ] Fix `test/features/command_center_test.dart` — either delete or redirect to HomeScreen
- [ ] Fix `test/unit/group_service_test.dart` — override Firebase-touching providers with mocks
- [ ] Fix `test/features/events/group_detail_events_test.dart` — diagnose 4 failures, fix assertions
- [ ] Fix `test/unit/group_join_test.dart` — override Firebase provider
- [ ] Create `test/integration/offline_scenario_test.dart` — 3 offline scenarios per D-12
- [ ] Create `test/unit/firebase_model_roundtrip_test.dart` — all model toFirestore/fromFirestore (D-04)
- [ ] Add CI coverage step to `.github/workflows/release_android.yml` (D-14, D-17)
- [ ] Verify `lcov` is installable in CI runner: `sudo apt-get install -y lcov`

*(Existing test infrastructure (flutter_test, FakeFirebaseFirestore, sqflite_common_ffi) is complete — no new packages needed)*

---

## Sources

### Primary (HIGH confidence)
- `test/unit/expense_service_test.dart` — Service test pattern with FakeFirebaseFirestore injection
- `test/unit/group_balance_provider_test.dart` — Provider test pattern with `_pumpUntilData` helper
- `test/unit/balance_cache_repository_test.dart` — SQLite integration test pattern
- `test/features/groups/group_screens_test.dart` — Widget test pattern with ProviderScope overrides
- `coverage/lcov.info` — Current coverage data (28.7%, 2526/8821 lines)
- `.planning/phases/06-testing-and-coverage/06-CONTEXT.md` — All locked decisions D-01 through D-21
- `.planning/STATE.md` — Phase 5 decisions about Provider.family timing, cascaded streams

### Secondary (MEDIUM confidence)
- `flutter test --coverage` output — 314 passing, 9 failing tests confirmed
- `romeovs/lcov-reporter-action` — GitHub Action for PR coverage comments; widely used in Flutter community

### Tertiary (LOW confidence)
- lcov `--remove` flag behavior — documented in lcov man page; standard tool, behavior is well-known

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all libraries already installed and in use; versions verified from pubspec.yaml
- Architecture: HIGH — patterns verified from reading existing test files; no speculation
- Coverage gap analysis: HIGH — computed directly from coverage/lcov.info file
- Pitfalls: HIGH — derived from actual failing tests and error messages observed during research
- CI YAML pattern: MEDIUM — lcov-reporter-action is well-known but exact YAML syntax not verified against latest version

**Research date:** 2026-03-27
**Valid until:** 2026-04-27 (stable tooling, unlikely to change)
