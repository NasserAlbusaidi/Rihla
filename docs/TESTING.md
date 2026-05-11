
# Testing Guide

## Overview

### Philosophy

Tests in Rihla are behavior-first. The question every test answers is: "does this behavior hold?" — not "does this line run?". Unit tests cover pure logic in isolation. Widget tests verify screen behavior with provider overrides replacing real Firebase. Integration tests wire services together using in-memory fakes.

The most important constraint: **no test ever touches real Firebase**. All Firebase dependencies are replaced at the provider level (widget tests) or by injecting `FakeFirebaseFirestore` / `MockFirebaseAuth` directly into services (unit/integration tests).

### Coverage Target

80% minimum line coverage. Enforced in CI by `lcov`. Several large feature directories are currently excluded from the threshold calculation (see the CI section for the exact exclusion list) while they accumulate tests. The 80% gate applies to everything not excluded.

### Test Types

| Type | Location | What it covers |
|------|----------|----------------|
| Unit | `test/unit/` | Pure logic: calculators, formatters, services, providers, models |
| Widget | `test/features/`, `test/shared/`, `test/core/` | Screen rendering and interaction with mocked providers |
| Integration | `test/integration/` | Multi-layer flows: services + SQLite, Firestore round-trips, auth contracts |
| Helpers | `test/helpers/` | Shared test infrastructure (router, navigation) |

---

## Test Structure

```
test/
├── widget_test.dart                    # Smoke test — verifies Flutter test infra
├── unit/                               # Pure-Dart logic tests (no Flutter widgets)
│   ├── balance_calculations_test.dart  # BalanceCalculator (all 4 expense scopes)
│   ├── settlement_optimization_test.dart # calculateOptimalSettlements algorithm
│   ├── formatters_test.dart            # AppFormatters (OMR, currency, dates)
│   ├── money_serializer_test.dart      # MoneySerializer subunit conversion
│   ├── expense_service_test.dart       # ExpenseService with FakeFirebaseFirestore
│   ├── settlement_service_test.dart    # SettlementService with FakeFirebaseFirestore
│   ├── group_service_test.dart         # GroupService with FakeFirebaseFirestore
│   ├── group_join_test.dart            # Invite code lookup logic
│   ├── activity_service_test.dart      # ActivityService with FakeFirebaseFirestore
│   ├── android_manifest_test.dart      # Release manifest permissions
│   ├── local_database_migration_test.dart # SQLite schema migrations (sqflite_common_ffi)
│   ├── balance_cache_repository_test.dart # SQLite cache layer
│   ├── connectivity_provider_test.dart # ConnectivityNotifier state machine
│   ├── settings_notifier_test.dart     # SettingsNotifier (SharedPreferences)
│   ├── color_tokens_test.dart          # AppColorTokens exact hex values
│   ├── design_tokens_test.dart         # Spacing/theme token system
│   ├── provider_tests.dart             # Provider wiring and initial states
│   └── ...                             # Additional model and widget unit tests
├── features/                           # Widget tests for feature screens
│   ├── home/
│   │   ├── home_screen_dashboard_test.dart
│   │   ├── home_screen_groups_test.dart
│   │   ├── home_screen_quick_actions_test.dart
│   │   └── widgets_test.dart
│   ├── groups/
│   │   ├── group_screens_test.dart     # GroupDetailScreen, GroupSettingsScreen
│   │   ├── group_settle_up_screen_test.dart
│   │   ├── group_activity_screen_test.dart
│   │   └── create_join_group_test.dart
│   ├── events/
│   │   ├── event_command_center_test.dart
│   │   ├── event_module_list_test.dart
│   │   ├── group_detail_events_test.dart
│   │   └── create_event_test.dart
│   ├── ledger/
│   │   └── payer_currency_rewiring_test.dart
│   ├── profile/
│   │   └── profile_screen_test.dart
│   ├── ledger_test.dart                # LedgerScreen + SettleUpScreen
│   ├── gear_screen_mutations_test.dart
│   ├── logistics_screen_mutations_test.dart
│   ├── vault_screen_mutations_test.dart
│   └── memories_screen_mutations_test.dart
├── shared/
│   └── widgets/
│       ├── grain_overlay_test.dart
│       └── animated_currency_text_test.dart
├── core/
│   └── providers/
│       └── app_bootstrap_wiring_test.dart
├── integration/
│   ├── happy_path_test.dart            # Full widget tree E2E with GoRouter
│   ├── offline_scenario_test.dart      # SQLite side-write verification
│   ├── firebase_auth_test.dart         # Anonymous auth behavioral contract
│   └── firebase_money_roundtrip_test.dart # Decimal -> Firestore -> Decimal
└── helpers/
    ├── test_router.dart                # Shared GoRouter with stub routes
    └── navigation_test.dart            # Router navigation assertions
```

---

## Running Tests

### All tests

```bash
flutter test
```

### With coverage

```bash
flutter test --coverage
```

### Specific file

```bash
flutter test test/unit/balance_calculations_test.dart
```

### Specific directory

```bash
flutter test test/unit/
flutter test test/features/
flutter test test/integration/
```

### Verbose output

```bash
flutter test --reporter expanded
```

### Single named test (by pattern match)

```bash
flutter test --name "Two people, one paid everything"
```

### Static analysis

```bash
flutter analyze
```

---

## Unit Tests

Unit tests live in `test/unit/` and have no Flutter widget dependencies. They import only Dart packages and the `safar` package itself.

### What is tested

**BalanceCalculator** (`test/unit/balance_calculations_test.dart`, `test/unit/settlement_optimization_test.dart`):
- All four expense scopes: `global`, `subGroup`, `personal`, `custom`
- `calculateOptimalSettlements` greedy algorithm (two-person, three-person, complex multi-debtor cases)
- Net balance computation across mixed expense types

**AppFormatters** (`test/unit/formatters_test.dart`):
- `formatOMR` — 3 decimal places, rounding, negatives, zero
- `formatCurrency` — symbol lookup, unknown currency fallback
- `formatRelativeDate` — Today/Yesterday/N days ago/dd/mm
- `formatShortMonthDay` — "Mar 15", no leading zero on day

**Service tests with FakeFirebaseFirestore** (`test/unit/expense_service_test.dart`, `settlement_service_test.dart`, etc.):
- Verify Firestore document path and field structure
- Verify `MoneySerializer.toSubunits` is used for amount storage (not raw Decimal/double)
- Verify soft-delete flags (`isDeleted: false` on create)

**Model tests** (`test/unit/firebase_model_roundtrip_test.dart`, `test/unit/group_model_test.dart`):
- `fromFirestore` / `toFirestore` round-trips
- Default field values

**SQLite migration** (`test/unit/local_database_migration_test.dart`):
- Uses `sqflite_common_ffi` with an in-memory database
- Verifies all expected columns exist after migration

### Writing a new unit test

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:decimal/decimal.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';

void main() {
  group('BalanceCalculator — custom split', () {
    test('two participants, unequal custom split', () {
      final participants = [
        Participant(id: 'p1', tripId: 't1', role: ParticipantRole.member,
            joinedAt: DateTime(2026), displayName: 'Alice'),
        Participant(id: 'p2', tripId: 't1', role: ParticipantRole.member,
            joinedAt: DateTime(2026), displayName: 'Bob'),
      ];

      final expenses = [
        Expense(
          id: 'e1',
          tripId: 't1',
          payerParticipantId: 'p1',
          amount: Decimal.parse('30'),
          scope: ExpenseScope.custom,
          customSplitParticipants: ['p1'],  // only p1 owes
          createdAt: DateTime(2026),
        ),
      ];

      final result = BalanceCalculator.calculate(
        participants: participants,
        expenses: expenses,
        settlements: [],
        subGroups: [],
      );

      // p1 paid 30, owes 30 (custom only for p1) → net 0
      final p1 = result.firstWhere((b) => b.participantId == 'p1');
      expect(p1.netBalance, equals(Decimal.zero));
    });
  });
}
```

---

## Widget Tests

Widget tests live in `test/features/`, `test/shared/widgets/`, and `test/core/`. They use `testWidgets` and `ProviderScope` with overrides to replace all Firestore/Firebase providers with in-memory streams.

### Core pattern

```dart
testWidgets('screen renders group name', (tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        groupDetailProvider('group-1').overrideWith(
          (ref) => Stream.value(_testGroup),
        ),
        // ... other required overrides
      ],
      child: const MaterialApp(
        home: GroupDetailScreen(groupId: 'group-1'),
      ),
    ),
  );

  await tester.pumpAndSettle();

  expect(find.text('Adventure Crew'), findsOneWidget);
});
```

### Required provider overrides by screen

**Any screen that reads device name (HomeScreen, GroupDetailScreen, etc.):**
```dart
sharedPreferencesProvider.overrideWithValue(prefs),
// where prefs = await SharedPreferences.getInstance()
// and SharedPreferences.setMockInitialValues({'device_name': 'Test User'}) was called first
```

**HomeScreen** (requires all dashboard providers):
```dart
sharedPreferencesProvider.overrideWithValue(prefs),
authStateProvider.overrideWith((ref) => Stream.value(mockUser)),
currentUserProvider.overrideWithValue(mockUser),
currentUserIdProvider.overrideWithValue('user-1'),
userGroupsProvider.overrideWith((ref) => Stream.value([mockGroup])),
crossGroupBalanceProvider.overrideWith(
  (ref) => AsyncValue.data((net: Decimal.zero, groupCount: 1, isLoading: false)),
),
crossGroupActivityProvider.overrideWith(
  (ref) => const AsyncValue.data([]),
),
weeklyGroupSpendingProvider.overrideWith(
  (ref) => AsyncValue.data(List.generate(7, (i) => (
    date: DateTime(2026, 3, 24).add(Duration(days: i)),
    amount: Decimal.zero,
  ))),
),
groupBalancesProvider.overrideWith(
  (ref, groupId) => AsyncValue.data((
    balances: <UserBalance>[],
    totalSpent: Decimal.zero,
    eventCount: 0,
    perEventBreakdown: <String, Map<String, Decimal>>{},
    memberNames: <String, String>{},
  )),
),
```

**GroupDetailScreen**:
```dart
sharedPreferencesProvider.overrideWithValue(prefs),
currentUserIdProvider.overrideWithValue('uid-creator'),  // or null
groupDetailProvider('group-1').overrideWith((ref) => Stream.value(_testGroup)),
groupMembersProvider('group-1').overrideWith((ref) => Stream.value(_testMembers)),
groupEventsProvider('group-1').overrideWith((ref) => Stream.value(const [])),
groupBalancesProvider('group-1').overrideWith(
  (ref) => AsyncValue.data(_groupBalancesStub),
),
groupActivityProvider('group-1').overrideWith((ref) => Stream.value(const [])),
```

**EventCommandCenter**:
```dart
eventDetailProvider(eventRef).overrideWith((ref) => Stream.value(event)),
groupDetailProvider(eventRef.groupId).overrideWith((ref) => Stream.value(group)),
eventExpensesProvider(eventRef).overrideWith((ref) => Stream.value(expenses)),
eventSettlementsProvider(eventRef).overrideWith(
  (ref) => Stream.value(const <Settlement>[]),
),
eventSubGroupsProvider(eventRef).overrideWith(
  (ref) => Stream.value(const <SubGroup>[]),
),
```

**LedgerScreen**:
```dart
eventDetailProvider(_eventRef).overrideWith((ref) => Stream.value(event)),
eventExpensesProvider(_eventRef).overrideWith((ref) => Stream.value(expenses)),
eventSettlementsProvider(_eventRef).overrideWith((ref) => Stream.value(settlements)),
eventSubGroupsProvider(_eventRef).overrideWith((ref) => Stream.value(subGroups)),
eventUnifiedLedgerProvider(_eventRef).overrideWith(
  (ref) => const AsyncValue.data(<Transaction>[]),
),
```


### Using testRouter for navigation tests

When the screen under test calls `context.push(...)` or `context.go(...)`, wrap it in a GoRouter to prevent routing exceptions:

```dart
import 'package:test/helpers/test_router.dart';

final router = testRouter(initialLocation: '/group/g1');
await tester.pumpWidget(
  ProviderScope(
    overrides: [...],
    child: MaterialApp.router(routerConfig: router),
  ),
);
```

`testRouter` in `test/helpers/test_router.dart` registers stub routes for the full app route tree. Pass `extraRoutes` for routes not in the default set.

### pump vs pumpAndSettle

- `pumpAndSettle()` — waits for all animations and async operations to complete. Use for most tests.
- `pump(Duration)` — advance time by an exact amount. Use when testing animation states mid-flight or when `pumpAndSettle` would timeout due to infinite animations.
- Wrap animated widgets with `MediaQuery(data: const MediaQueryData(disableAnimations: true), ...)` to skip `flutter_animate` timers when the animation behavior itself is not under test.

### Asserting with keys

Prefer `find.byKey` over `find.text` for structural assertions. Keys are stable; text strings change with copy updates.

```dart
// Good
expect(find.byKey(HomeKeys.createGroupFab), findsOneWidget);
expect(find.byKey(GroupKeys.settleButton), findsOneWidget);

// Fragile — avoid for structural checks
expect(find.text('Create Group'), findsOneWidget);
```

---

## Integration Tests

Integration tests in `test/integration/` test cross-layer interactions without a real Firebase project.

### Happy path E2E (`test/integration/happy_path_test.dart`)

Renders the full app with `MaterialApp.router` and the real `routerProvider`. Exercises the splash → home redirect with mocked auth and group providers.

Key pattern: `SharedPreferences.setMockInitialValues` must be called before `SharedPreferences.getInstance()`:

```dart
SharedPreferences.setMockInitialValues({'device_name': 'Test User'});
final prefs = await SharedPreferences.getInstance();
```

### SQLite side-write verification (`test/integration/offline_scenario_test.dart`)

Tests the pipeline: `ExpenseService` → `FakeFirebaseFirestore` → manual cache → `SQLite` → read back.

Setup required:
```dart
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

### Firebase auth contract (`test/integration/firebase_auth_test.dart`)

Uses `firebase_auth_mocks` package (`MockFirebaseAuth`, `MockUser`). No emulator dependency.

```dart
final mockAuth = MockFirebaseAuth(signedIn: false);
await mockAuth.signInAnonymously();
expect(mockAuth.currentUser!.isAnonymous, isTrue);
```

### Firestore money round-trip (`test/integration/firebase_money_roundtrip_test.dart`)

End-to-end `Decimal` → `MoneySerializer.toSubunits` → `FakeFirebaseFirestore` → `MoneySerializer.fromSubunits` → `Decimal`. Validates no precision loss through the integer-subunit storage layer.

---

## Mocking Patterns

### mocktail

All mocks use `mocktail` (not `mockito`). No code generation required.

```dart
import 'package:mocktail/mocktail.dart';

class MockGroupService extends Mock implements GroupService {}
class MockNotificationService extends Mock implements NotificationService {}
class MockFirebaseUser extends Mock implements firebase_auth.User {}
```

Set up stubs in `setUp`:
```dart
setUp(() {
  mockGroupService = MockGroupService();
  when(
    () => mockGroupService.joinGroup(
      inviteCode: any(named: 'inviteCode'),
    ),
  ).thenAnswer((_) async => _testGroup);
});
```

Verify calls:
```dart
verify(() => mockNotificationService.initialize()).called(1);
verifyNever(() => mockNotificationService.removeToken());
```

### FakeFirebaseFirestore

Services that accept a `Firestore` parameter expose a `withFirestore` constructor for injection:

```dart
final fakeDb = FakeFirebaseFirestore();
final service = ExpenseService.withFirestore(fakeDb);
```

For provider-level injection:
```dart
groupServiceProvider.overrideWith(
  (ref) => GroupService.withFirestore(ref, fakeDb),
),
```

### firebase_auth_mocks

```dart
// Start signed out
final mockAuth = MockFirebaseAuth(signedIn: false);

// Start with an existing user
final existingUser = MockUser(uid: 'existing-uid-123', isAnonymous: true);
final mockAuth = MockFirebaseAuth(signedIn: true, mockUser: existingUser);
```

### ProviderContainer (non-widget tests)

For testing provider logic without a widget tree:

```dart
final container = ProviderContainer(
  overrides: [
    sharedPreferencesProvider.overrideWithValue(prefs),
  ],
);
addTearDown(container.dispose);

final value = container.read(someProvider);
```

### sqflite_common_ffi (SQLite in tests)

Required for any test that touches `LocalDatabase`:

```dart
setUpAll(() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
});
```

Without this, SQLite calls will throw on macOS/Linux test environments.

---

## Common Pitfalls

### Missing sharedPreferencesProvider override

Any screen that reads `settingsProvider` (which includes the device name) will throw if `sharedPreferencesProvider` is not overridden. The provider's default implementation throws intentionally.

**Fix:**
```dart
SharedPreferences.setMockInitialValues({'device_name': 'Test User'});
final prefs = await SharedPreferences.getInstance();
// then override:
sharedPreferencesProvider.overrideWithValue(prefs),
```

In tests that don't need a real device name, an empty values map works:
```dart
SharedPreferences.setMockInitialValues({});
```

### Infinite animation loops with pumpAndSettle

`flutter_animate` running looping animations will cause `pumpAndSettle` to time out. Wrap the widget under test with `disableAnimations: true`:

```dart
child: MediaQuery(
  data: const MediaQueryData(disableAnimations: true),
  child: WidgetUnderTest(),
),
```

### PopupMenuButton tap in widget tests

`PopupMenuButton` taps via `tester.tap(find.byType(PopupMenuButton))` are unreliable in small test viewports due to z-ordering with FABs and scroll views. Use the state directly:

```dart
final menuBtn = find.byType(PopupMenuButton<String>).first;
final PopupMenuButtonState<String> menuState = tester.state(menuBtn);
menuState.showButtonMenu();
await tester.pumpAndSettle();
```

### Label references

Use exact strings matching the current codebase. Two labels that have been renamed and are easy to get wrong:

| Wrong | Correct |
|-------|---------|
| `'TREASURY'` | `'SPENDING'` |
| `'Audit Log'` | `'Ledger'` |

### sqflite not initialized

SQLite tests on non-mobile platforms fail with an unsupported platform error unless `sqfliteFfiInit()` and `databaseFactory = databaseFactoryFfi` are called in `setUpAll`.

### FakeFirebaseFirestore does not enforce security rules

`fake_cloud_firestore` ignores Firestore security rules. Tests that pass with the fake may fail in production if RLS is misconfigured. Security rule correctness is not tested in this suite — validate rules separately using the Firebase emulator.

### async callbacks in ProviderContainer tests

Provider listeners fire asynchronously. After triggering a state change, advance the event loop before asserting:

```dart
container.read(settingsProvider.notifier).setPushNotificationsEnabled(true);
container.read(appBootstrapProvider);
await Future<void>.delayed(Duration.zero);  // let async listeners fire
verify(() => mockNotificationService.initialize()).called(1);
```

---

## CI Integration

Tests run in the `Android Release` GitHub Actions workflow (`.github/workflows/release_android.yml`). The workflow triggers on `workflow_dispatch` or any tag matching `v*`.

### Test step

```yaml
- name: Run Tests with Coverage
  run: |
    rm -f coverage/lcov.info
    flutter test --coverage
```

### Static analysis (runs before tests)

```yaml
- name: Static Analysis
  run: flutter analyze --no-fatal-infos
```

### Hardcoded color lint

A custom CI step rejects any `Color(0xFF...)` literal outside the token system files:

```yaml
- name: Hardcoded color lint
  run: |
    VIOLATIONS=$(grep -rn "Color(0x" lib/ \
      --include="*.dart" \
      | grep -v "lib/core/theme/app_theme.dart" \
      | grep -v "lib/core/theme/tokens/" \
      | grep -v "lib/features/ledger/models/expense_category_model.dart" \
      | wc -l | tr -d ' ')
    if [ "$VIOLATIONS" -gt "0" ]; then
      echo "::error::$VIOLATIONS hardcoded Color(0xFF...) literal(s) found outside the token system."
      exit 1
    fi
```

### find.text() regression warning

CI tracks the number of `find.text()` calls in the test suite against a baseline. New structural assertions should use `find.byKey()` instead. Exceeding the baseline emits a warning (not a failure):

```yaml
- name: find.text() regression warning
  run: |
    BASELINE=135
    CURRENT=$(grep -rn "find\.text(" test/ | wc -l | tr -d ' ')
    if [ "$CURRENT" -gt "$BASELINE" ]; then
      echo "::warning::find.text() calls increased from $BASELINE to $CURRENT."
    fi
```

### Coverage threshold

After running `flutter test --coverage`, CI filters the `lcov.info` file to remove generated, bootstrap, and in-progress feature files, then enforces the 80% threshold on the remainder:

```yaml
- name: Check Coverage Threshold (80%)
  run: |
    lcov --remove coverage/lcov.info \
      'lib/firebase_options.dart' \
      'lib/main.dart' \
      'lib/app.dart' \
      '*.g.dart' \
      '*.freezed.dart' \
      'lib/features/trip/*' \
      'lib/features/logistics/*' \
      ... \
      -o coverage/lcov_filtered.info
    COVERAGE=$(lcov --summary coverage/lcov_filtered.info 2>&1 \
      | grep -oP '\d+\.\d+(?=%)' | head -1)
    if (( $(echo "$COVERAGE < 80" | bc -l) )); then
      echo "::error::Coverage ${COVERAGE}% is below 80% threshold"
      exit 1
    fi
```

The excluded paths are temporary coverage exemptions for feature modules still under active development. As those modules stabilize, they should be removed from the exclusion list.

### Required CI secrets

| Secret | Purpose |
|--------|---------|
| `KEYSTORE_BASE64` | Android signing keystore (base64) |
| `KEY_PROPERTIES` | `key.properties` file content |
| `CONFIG_JSON` | Production `config.json` values such as `SENTRY_DSN` and `USE_FIREBASE_EMULATOR=false` |
| `GOOGLE_PLAY_JSON_KEY` | Google Play service account for upload |

No iOS CI — iOS builds are done manually.
