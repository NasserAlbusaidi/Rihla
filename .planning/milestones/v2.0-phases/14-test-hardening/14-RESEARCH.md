# Phase 14: Test Hardening - Research

**Researched:** 2026-03-28
**Domain:** Flutter widget testing — semantic Key identifiers, find.byKey() migration
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** Per-feature key classes in `lib/features/{feature}/keys/{feature}_keys.dart`, plus `lib/core/keys/shared_keys.dart` for shared widgets
- **D-02:** Key string values use `feature_widget_role` pattern (e.g., `'ledger_expense_list'`, `'home_balance_hero'`, `'gear_add_button'`)
- **D-03:** Classes are `abstract final class` with `static const Key` fields
- **D-04:** Parameterized keys for list items use factory methods returning `Key('feature_widget_$id')` (e.g., `LedgerKeys.expenseCard(String id)`)
- **D-05:** Convert structural `find.text()` calls to `find.byKey()` — calls that check navigation, screen presence, section headers, widget structure. Keep `find.text()` for genuine content assertions (formatted amounts, label text validation)
- **D-06:** Convert structural `find.byType()` calls to `find.byKey()` — calls like `find.byType(LedgerScreen)`. Keep `find.byType()` for genuine type checks (CircularProgressIndicator, SnackBar)
- **D-07:** Convert `tester.tap(find.text(...))` targets to `tester.tap(find.byKey(...))` — tap-by-text is the most fragile pattern and highest value to convert
- **D-08:** Estimated scope: ~180-200 of 257 `find.text()` conversions, plus structural subset of 90 `find.byType()` conversions
- **D-09:** Test-driven key placement — only add keys to widgets that tests actually reference. No speculative keys for untested widgets
- **D-10:** Exception: every screen widget gets a `.screen` key regardless of current test coverage (~25 screens). Screen keys are cheap and high-value for future navigation testing
- **D-11:** Feature-by-feature migration with green `flutter test` runs after each file conversion. Heaviest files first (widget_coverage_test 35 calls, create_join_group_test 30, etc.)
- **D-12:** One atomic commit per test file: keys added to widgets + test updated + green run. ~23 commits total
- **D-13:** Rename resilience verification: after full migration, temporarily rename one UI label (e.g., 'Ledger' to 'Treasury'), run full suite, confirm only content-validation tests fail, revert. Documents proof of success criterion #3
- **D-14:** Add CI warning check for new `find.text()` calls in PRs — grep-based, non-blocking warning (not hard fail since content tests still need find.text)

### Claude's Discretion

- Exact categorization of each find.text() call as structural vs content
- Migration order within the heaviest-first strategy
- Exact CI warning script implementation details
- Whether to group very small test files into a single commit

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope

</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| FOUND-05 | Test suite uses semantic Key identifiers instead of find.text() for structural assertions, preventing cascade failures during UI changes | Key class architecture pattern, structural vs content classification taxonomy, migration commit strategy, CI warning implementation |

</phase_requirements>

---

## Summary

Phase 14 is a pure test infrastructure refactor: create a semantic Key system for Flutter widgets, then migrate the test suite from brittle `find.text()` / structural `find.byType()` calls to stable `find.byKey()` calls. No user-visible behavior changes. No new features. The phase gates all subsequent v2.0 visual work by making the test suite rename-resilient.

The codebase has exactly 257 `find.text()` calls across 21 test files and 90 `find.byType()` calls. The Key system starts from scratch — only two locations currently use `Key()` at all (`vault_screen.dart` list items and `onboarding_screen.dart` animations), both irrelevant to this phase. There are 22 screen files across 13 features plus ~29 widget files in `lib/features/*/widgets/` and 7 in `lib/shared/widgets/` that will receive keys.

The classification challenge is the core intellectual work of this phase: deciding which `find.text()` calls are structural (asserting widget presence / navigation / section structure) versus content (asserting formatted data, validation messages, user-supplied text). The taxonomy established here guides every task in the plan.

**Primary recommendation:** Execute as a file-by-file migration in descending call-count order. Each "unit of work" is one test file: classify its calls, add keys to the corresponding widget files, update the test, run `flutter test`, commit. Never leave the suite red between commits.

---

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `flutter_test` | SDK-bundled (Flutter 3.41.5) | `find.byKey()`, `find.text()`, `testWidgets()` | Standard Flutter test framework — no additional dep |
| `flutter/material.dart` | SDK-bundled | `Key`, `ValueKey`, `GlobalKey` types | All Key types are in the Flutter SDK |

### Key API Facts (verified from Flutter SDK)

**`Key` constructor** — `const Key(String value)` — The base Key class. `const Key('ledger_expense_list')` is the correct pattern for static keys. Equality is value-based: two `Key('same')` instances are equal.

**`ValueKey<T>`** — Wraps any value. `ValueKey('ledger_expense_list')` is equivalent to `Key('ledger_expense_list')` for String values, but `ValueKey(expenseId)` works for typed IDs. The decisions use `Key(...)` directly, which is cleaner for string keys.

**`find.byKey(Key key)`** — The CommonFinders method in flutter_test. Accepts any `Key` subtype. `find.byKey(LedgerKeys.expenseList)` is the correct test invocation pattern.

**Widget `key` parameter** — Every Flutter widget has an optional `key` parameter on its constructor (inherited from `Widget`). Setting it: `SmartModuleCard(key: EventKeys.ledgerCard, ...)`.

### No New Dependencies

This phase requires zero new packages. `Key`, `ValueKey`, `find.byKey()` are all in the existing Flutter SDK and `flutter_test` bundle.

---

## Architecture Patterns

### Key Class Structure

```
lib/
├── core/
│   └── keys/
│       └── shared_keys.dart       # Keys for lib/shared/widgets/
└── features/
    ├── events/
    │   └── keys/
    │       └── event_keys.dart
    ├── groups/
    │   └── keys/
    │       └── group_keys.dart
    ├── home/
    │   └── keys/
    │       └── home_keys.dart
    ├── ledger/
    │   └── keys/
    │       └── ledger_keys.dart
    ├── logistics/
    │   └── keys/
    │       └── logistics_keys.dart
    ├── gear/
    │   └── keys/
    │       └── gear_keys.dart
    ├── settings/
    │   └── keys/
    │       └── settings_keys.dart
    └── (activity, auth, memories, onboarding, vault, trip — only if tests reference them)
```

### Pattern 1: Static Key Class

```dart
// lib/features/events/keys/event_keys.dart
abstract final class EventKeys {
  // Screen-level keys (D-10: every screen gets one unconditionally)
  static const screen = Key('event_command_center_screen');
  static const createEventScreen = Key('create_event_screen');
  static const eventTypePickerScreen = Key('event_type_picker_screen');

  // Section / structural keys (converted from find.text() structural calls)
  static const moduleList = Key('event_module_list');
  static const ledgerCard = Key('event_ledger_card');
  static const gearCard = Key('event_gear_card');
  static const logisticsCard = Key('event_logistics_card');
  static const vaultCard = Key('event_vault_card');
  static const memoriesCard = Key('event_memories_card');
  static const spendingHero = Key('event_spending_hero');

  // Action keys (converted from tester.tap(find.text()) calls)
  static const addExpenseFab = Key('event_add_expense_fab');
}
```

### Pattern 2: Parameterized Keys for List Items

```dart
// Factory method pattern (D-04)
abstract final class EventKeys {
  // ...static const fields above...

  // Parameterized: returns a new Key instance per ID
  static Key eventCard(String eventId) => Key('event_card_$eventId');
}

// Usage in widget:
EventCard(
  key: EventKeys.eventCard(event.id),
  event: event,
)

// Usage in test:
expect(find.byKey(EventKeys.eventCard('event123')), findsOneWidget);
```

### Pattern 3: Shared Widget Keys

```dart
// lib/core/keys/shared_keys.dart
abstract final class SharedKeys {
  // ModuleHeader
  static const moduleHeaderBackButton = Key('shared_module_header_back_button');

  // OfflineBanner
  static const offlineBanner = Key('shared_offline_banner');

  // AppTabBar — parameterized by tab label since tabs vary per screen
  static Key appTabBarTab(String label) => Key('shared_tab_bar_tab_$label');

  // InviteCodeDisplay
  static const inviteCodeDisplay = Key('shared_invite_code_display');
  static const inviteCodeCopyButton = Key('shared_invite_code_copy_button');
  static const inviteCodeShareButton = Key('shared_invite_code_share_button');

  // GroupBalanceHero
  static const groupBalanceHero = Key('shared_group_balance_hero');
  static const groupBalanceSettleUpButton = Key('shared_group_balance_settle_up_button');

  // EmptyStateView
  static const emptyStateView = Key('shared_empty_state_view');
  static const emptyStateCtaButton = Key('shared_empty_state_cta_button');

  // LoadingButton
  static Key loadingButton(String label) => Key('shared_loading_button_$label');
}
```

### Pattern 4: Adding Key to Widget Build Method

```dart
// BEFORE (no key)
class EventCommandCenter extends ConsumerWidget {
  const EventCommandCenter({super.key, required this.event, required this.group});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      // ...
    );
  }
}

// AFTER (screen-level key on root widget)
import '../keys/event_keys.dart';

class EventCommandCenter extends ConsumerWidget {
  const EventCommandCenter({super.key, required this.event, required this.group});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      key: EventKeys.screen,
      // ...
    );
  }
}
```

### Pattern 5: Keying a SmartModuleCard for find.byKey()

The EventModuleList builds SmartModuleCard instances. Keys go on the SmartModuleCard itself:

```dart
// In event_module_list.dart:
SmartModuleCard(
  key: EventKeys.ledgerCard,
  icon: Iconsax.wallet_3,
  title: 'Ledger',
  // ...
)

// In test (replacing find.text('Ledger') for structural assertions):
expect(find.byKey(EventKeys.ledgerCard), findsOneWidget);   // structural: card is present
expect(find.byKey(EventKeys.gearCard), findsNothing);       // structural: card is absent
```

**Important:** `find.text('Ledger')` that validates the card's title text *as content* remains as-is. Only the structural "is this card present" assertions convert.

### Pattern 6: CI Warning Step

```yaml
# Add after "Run Tests with Coverage" step in release_android.yml
- name: Warn on new find.text() in structural test context
  run: |
    # Count find.text() calls that look structural (navigation/screen assertions)
    # This is a non-blocking warning only — content tests legitimately use find.text()
    COUNT=$(grep -r "find\.text(" test/ | wc -l | tr -d ' ')
    echo "Current find.text() call count: $COUNT"
    echo "::notice::find.text() calls in test suite: $COUNT (structural assertions should use find.byKey())"
```

A simpler variant stores a baseline count and warns if it increases:

```yaml
- name: find.text() regression warning
  run: |
    BASELINE=57  # Updated after Phase 14 completes (content-only calls remaining)
    CURRENT=$(grep -rn "find\.text(" test/ | wc -l | tr -d ' ')
    if [ "$CURRENT" -gt "$BASELINE" ]; then
      echo "::warning::find.text() calls increased from $BASELINE to $CURRENT. New structural assertions should use find.byKey() instead."
    fi
    echo "find.text() calls: $CURRENT (baseline: $BASELINE)"
```

The baseline count gets set after Phase 14 completes by counting remaining content-only `find.text()` calls.

### Anti-Patterns to Avoid

- **Key on the wrong level:** Putting `key: EventKeys.ledgerCard` on a child `Text` widget inside SmartModuleCard instead of on the SmartModuleCard itself — makes `find.byKey()` find an invisible inner widget, not the interactive card
- **Over-keying:** Adding keys to every widget in a `build()` method speculatively. D-09 is explicit: only key widgets that tests reference
- **`const Key()` on parameterized keys:** `const Key('event_card_${event.id}')` is NOT valid Dart (const requires compile-time constants). Factory methods `static Key eventCard(String id) => Key('event_card_$id')` are correct (non-const)
- **Importing key class in widget file unnecessarily:** Key classes are small. Import cost is negligible — don't avoid the import to "keep widget files clean"
- **Modifying the `key` named parameter in the constructor signature:** Screens already have `super.key` in their constructor. The screen-level key goes on the root `Scaffold` or root widget inside `build()`, NOT on the constructor's `super.key` parameter

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Unique key per list item | Custom UUID generator | `Key('feature_widget_${item.id}')` | item.id from Firestore is already globally unique |
| Key registry / map | Central key store with lookup | Per-feature `abstract final class` | Dart's `static const` provides compile-time constants and IDE autocomplete at zero runtime cost |
| Semantic testing framework | Custom test helpers | `find.byKey()` from flutter_test | Already in the SDK |
| Regex to find structural vs content calls | Automated classifier | Manual classification per test file | The distinction requires reading test intent, not just the string |

---

## Structural vs Content Classification Taxonomy

This is the most critical decision this phase makes. The planner must encode this taxonomy into tasks.

### Structural — CONVERT to find.byKey()

These calls assert widget presence/absence as a proxy for app structure, navigation success, or feature enablement. They break when labels rename.

| Pattern | Example | Why Structural |
|---------|---------|----------------|
| Module card presence/absence | `find.text('Ledger')`, `find.text('Gear')` in event_command_center_test and event_module_list_test | Tests whether a module IS rendered based on event.modules config — the label is incidental |
| Screen header / AppBar title | `find.text('New Group')`, `find.text('Join a Group')`, `find.text('Group Settings')` | Tests that the correct screen rendered after navigation |
| Section header | `find.text('Members & Balances')`, `find.text('Invite Code')`, `find.text('Events')`, `find.text('Modules')` | Tests that a UI section exists |
| Action button tap target | `tester.tap(find.text('Create Group'))`, `tester.tap(find.text('Create Event'))`, `tester.tap(find.text('Copy Code'))`, `tester.tap(find.text('Share'))`, `tester.tap(find.text('Settle Up'))` | The button exists and is tappable — the label is incidental |
| Navigation confirmation | `find.text('Create a Group')`, `find.text('Join a Group')` in home_screen_groups_test bottom sheet | Tests sheet opened after FAB tap — structural |
| Empty state label | `find.text('No groups yet')`, `find.text('No events yet')` | Tests that empty state widget rendered |

### Content — KEEP find.text()

These calls assert specific data content that the system must produce correctly. They should fail when the data or format changes.

| Pattern | Example | Why Content |
|---------|---------|-------------|
| Formatted amounts | `find.text('25.500 OMR')`, `find.text('0.000 OMR')` | Tests financial formatting — must fail if format breaks |
| User-supplied data | `find.text('Desert Crew')`, `find.text('Beach Trip')`, `find.text('Alice')`, `find.text('ABC123')` | Tests that actual data renders — name of a group/event/member in test fixture |
| Validation error messages | `find.text("Group name can't be empty.")`, `find.text('Enter your name so others know who you are.')`, `find.text("Event name can't be empty.")` | Tests that the correct error text appears |
| Count/summary text | `find.textContaining('2 expenses')`, `find.textContaining('1 expense')`, `find.textContaining('item still need')` | Tests computed summary content |
| State-specific status | `find.text('All balances settled')`, `find.text('All settled! No outstanding balances.')`, `find.text('YOU OWE')`, `find.text('YOU ARE OWED')` — these are conditional state labels | BORDERLINE: could go either way. Recommended: keep as content assertions since they validate a specific financial state string, not widget presence |

### Borderline — Use Judgment

| Call | Decision | Rationale |
|------|----------|-----------|
| `find.text('GROUP BALANCES')` in GroupBalanceHero test | Keep (content) | Tests a label literal that lives in the widget — if the widget renders, this label appears |
| `find.text('Settle Up')` in group_settle_up_screen | Convert to byKey | This is a button tap target and screen section marker — structural |
| `find.text('Record Settlement')` | Convert to byKey | Button label used as tap target — structural |
| `find.text('Not Now')` | Convert to byKey | Dialog action used as tap target — structural |
| `find.text('SPENDING')` in EventExpenseHero | Keep (content) | Section label in the hero widget — validates the specific header string |
| `find.text('B')`, `find.text('Beta')` in tab tests | Convert to byKey for the tap target | These are tap targets verifying tab switching works — structural. But `find.text('Alpha')` / `find.text('Beta')` as existence checks in `renders tab labels` tests are content |

---

## Migration Scope (Actual Counts from Codebase)

### Test File Priority Order (by find.text() call count)

| Priority | Test File | find.text() Calls | Est. Structural | Est. Content |
|----------|-----------|-------------------|-----------------|--------------|
| 1 | `test/unit/widget_coverage_test.dart` | 35 | ~18 | ~17 |
| 2 | `test/features/groups/create_join_group_test.dart` | 30 | ~18 | ~12 |
| 3 | `test/features/events/event_command_center_test.dart` | 23 | ~20 | ~3 |
| 4 | `test/features/groups/group_settle_up_screen_test.dart` | 20 | ~15 | ~5 |
| 5 | `test/features/groups/group_screens_test.dart` | 19 | ~12 | ~7 |
| 6 | `test/features/events/create_event_test.dart` | 18 | ~14 | ~4 |
| 7 | `test/features/events/event_module_list_test.dart` | 15 | ~14 | ~1 |
| 8 | `test/features/events/group_detail_events_test.dart` | 14 | ~7 | ~7 |
| 9 | `test/features/logistics_screen_mutations_test.dart` | 12 | ~10 | ~2 |
| 10 | `test/features/group_settle_up_screen_test.dart` | 12 | ~9 | ~3 |
| 11 | `test/unit/shared_widgets_test.dart` | 11 | ~5 | ~6 |
| 12 | `test/features/group_detail_screen_test.dart` | 11 | ~8 | ~3 |
| 13 | `test/features/home/home_screen_groups_test.dart` | 8 | ~6 | ~2 |
| 14 | `test/features/group_balance_card_test.dart` | 7 | ~3 | ~4 |
| 15-21 | Remaining files (1-4 calls each) | ~25 | ~15 | ~10 |
| **Total** | | **257** | **~174** | **~83** |

Note: The 83 content calls represent the expected remaining `find.text()` count after migration. This becomes the CI baseline number.

### Widget Files That Will Receive Keys

Derived from test coverage + D-10 (every screen gets a key):

**Screens (D-10 mandates all):**
- events: `EventCommandCenter`, `CreateEventScreen`, `EventTypePickerScreen`
- groups: `GroupDetailScreen`, `CreateGroupScreen`, `JoinGroupScreen`, `GroupSettleUpScreen`, `GroupSettingsScreen`, `GroupActivityScreen`
- home: `HomeScreen`
- ledger: `LedgerScreen`, `AddExpenseScreen`, `EditExpenseSheet`, `SettleUpScreen`
- gear: `GearScreen`
- logistics: `LogisticsScreen`
- memories: `MemoriesScreen`
- onboarding: `OnboardingScreen`
- settings: `SettingsScreen`
- vault: `VaultScreen`
- activity: `ActivityFeedScreen`

**Widgets (test-referenced only per D-09):**
- `SmartModuleCard` — needs keys for each module card instance (ledger, gear, logistics, vault, memories)
- `GroupBalanceHero` — settle up button, balance label area
- `InviteCodeDisplay` — copy button, share button
- `AppTabBar` — tab items (parameterized)
- `GroupCard` (in groups feature)
- `GroupMemberBalanceCard`
- `EventCard` (parameterized by eventId)
- Various action buttons in logistics (CREATE GROUP, REMOVE, DELETE dialog)
- Settle Up / Record Settlement / Mark as Paid / Not Now buttons in group settle up

---

## Common Pitfalls

### Pitfall 1: Key Collision on Singleton vs Multi-Instance Widgets

**What goes wrong:** Two `SmartModuleCard` instances in the same tree both receive `key: EventKeys.ledgerCard`. Flutter throws a duplicate key error at runtime (and tests fail with confusing messages).

**Why it happens:** The ledger module card appears once, but if the key is placed incorrectly (e.g., in a wrapper that renders it twice), or if the same key constant is accidentally reused for two different cards.

**How to avoid:** Each module card has its own distinct key constant (`ledgerCard`, `gearCard`, etc.). Never reuse a key constant across two widgets that could appear simultaneously in the tree.

**Warning signs:** Test error "Duplicate keys found in widget tree" or "Multiple widgets used the same GlobalKey."

### Pitfall 2: `const Key()` on Parameterized Keys

**What goes wrong:** Writing `static const Key eventCard = Key('event_card_${event.id}')` — Dart compiler error because string interpolation is not a compile-time constant.

**Why it happens:** Trying to apply `const` to factory methods or interpolated strings.

**How to avoid:** Parameterized keys must be factory methods (non-const): `static Key eventCard(String id) => Key('event_card_$id')`. Static const fields are only valid for fixed string values.

**Warning signs:** Dart compile error "The value of the constant 'eventCard' must be constant."

### Pitfall 3: Structural Test Breaks on Key Addition

**What goes wrong:** Adding a key to a widget causes an existing test to fail — the test was checking widget identity by position (`byType().first`) and the key changes widget matching.

**Why it happens:** Rare but possible when tests use `.first` / `.last` selectors that depended on implicit widget ordering.

**How to avoid:** Run `flutter test` immediately after adding keys to each widget file, before modifying the test file. If a test breaks from key addition alone, investigate before proceeding.

**Warning signs:** Test failures in files you haven't touched yet in the migration.

### Pitfall 4: Key on Wrong Widget Layer

**What goes wrong:** `find.byKey(EventKeys.ledgerCard)` finds nothing in the test even though the key was added to the widget.

**Why it happens:** The key was placed on a private inner widget (`_CardBody`) rather than on the public `SmartModuleCard` widget that the test renders. The test's widget tree traversal finds the public widget, not the private child.

**How to avoid:** Always place keys on the outermost widget that maps to the test's semantic unit. For module cards, that's the `SmartModuleCard` call site in `event_module_list.dart`, not inside `smart_module_card.dart`.

**Warning signs:** `find.byKey()` returns `findsNothing` even though the widget is visually present.

### Pitfall 5: Missing Key Import in Test File

**What goes wrong:** Test file uses `EventKeys.ledgerCard` but doesn't import `event_keys.dart`. Dart compile error.

**Why it happens:** Each test file must explicitly import the key class file.

**How to avoid:** Per D-12, test update is part of the same atomic commit. Include the import statement as the first change to the test file.

**Warning signs:** "The getter 'EventKeys' isn't defined" compile error.

### Pitfall 6: Rename Verification Revert Forgotten

**What goes wrong:** D-13's rename verification ('Ledger' → 'Treasury') is done to confirm resilience, but the revert step is skipped. 'Treasury' ships in the codebase.

**Why it happens:** The verification step modifies production code temporarily.

**How to avoid:** The rename verification task must include an explicit revert step as a sub-action. Commit the revert before closing the verification task. Never commit the temporary rename.

**Warning signs:** `git diff` shows label changes in `lib/` files after the verification task closes.

---

## Code Examples

### Declaring a Key Class

```dart
// lib/features/events/keys/event_keys.dart
import 'package:flutter/material.dart';

abstract final class EventKeys {
  // Screen keys (D-10: mandatory for all screens)
  static const screen = Key('event_command_center_screen');
  static const createEventScreen = Key('create_event_screen');
  static const eventTypePickerScreen = Key('event_type_picker_screen');

  // Module cards
  static const ledgerCard = Key('event_ledger_card');
  static const gearCard = Key('event_gear_card');
  static const logisticsCard = Key('event_logistics_card');
  static const vaultCard = Key('event_vault_card');
  static const memoriesCard = Key('event_memories_card');

  // Actions
  static const addExpenseFab = Key('event_add_expense_fab');

  // Parameterized (list items)
  static Key eventCard(String eventId) => Key('event_card_$eventId');
}
```

### Applying Key in Widget

```dart
// In event_module_list.dart — adding key to SmartModuleCard
import '../../events/keys/event_keys.dart';  // or relative path

SmartModuleCard(
  key: EventKeys.ledgerCard,   // <-- added
  icon: Iconsax.wallet_3,
  title: 'Ledger',
  description: 'Track expenses',
  // ...
)
```

### Applying Screen Key

```dart
// In event_command_center.dart
import '../keys/event_keys.dart';

@override
Widget build(BuildContext context, WidgetRef ref) {
  return Scaffold(
    key: EventKeys.screen,   // <-- added to root Scaffold
    floatingActionButton: FloatingActionButton(
      key: EventKeys.addExpenseFab,  // <-- if tests tap the FAB
      // ...
    ),
    // ...
  );
}
```

### Test After Migration

```dart
// BEFORE: structural find.text() calls
expect(find.text('Ledger'), findsOneWidget);   // module card present
expect(find.text('Gear'), findsNothing);        // module card absent
await tester.tap(find.text('Settle Up'));

// AFTER: find.byKey() for structural, find.text() kept for content
import 'package:safar/features/events/keys/event_keys.dart';
import 'package:safar/features/groups/keys/group_keys.dart';

expect(find.byKey(EventKeys.ledgerCard), findsOneWidget);
expect(find.byKey(EventKeys.gearCard), findsNothing);
await tester.tap(find.byKey(GroupKeys.settleUpButton));

// Content assertion stays unchanged:
expect(find.text('Alice'), findsOneWidget);           // user data
expect(find.text('25.500 OMR'), findsOneWidget);      // formatted amount
expect(find.text("Group name can't be empty."), findsOneWidget);  // validation
```

### Rename Resilience Verification Script

```bash
# D-13 verification protocol (run after full migration, revert after)
# 1. Temporarily rename the label in source
sed -i '' "s/title: 'Ledger'/title: 'Treasury'/g" lib/features/events/widgets/event_module_list.dart

# 2. Run full test suite
flutter test 2>&1 | tail -30

# 3. Verify only content tests fail (ones testing the label text itself)
# Expected failures: any test with find.text('Ledger') that wasn't converted (content-only)
# Unexpected failures: any find.byKey() test — means the key is on the wrong widget

# 4. Revert immediately
sed -i '' "s/title: 'Treasury'/title: 'Ledger'/g" lib/features/events/widgets/event_module_list.dart
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `find.text('Submit')` for button tap targets | `find.byKey(ScreenKeys.submitButton)` | This phase introduces | Label renames no longer cascade test failures |
| `find.byType(LedgerScreen)` for screen presence | `find.byKey(LedgerKeys.screen)` | This phase introduces | Screen class renames no longer break navigation tests |
| No semantic key system | Per-feature `abstract final class` with `static const Key` | This phase introduces | IDE-navigable, refactor-safe, zero runtime cost |

---

## Open Questions

1. **exact content vs structural classification for borderline calls (~15 calls)**
   - What we know: The taxonomy above handles 95% of cases clearly
   - What's unclear: Calls like `find.text('GROUP BALANCES')`, `find.text('SPENDING')` — header labels that are both structural markers AND content strings
   - Recommendation: Claude's discretion as defined in D-05. When in doubt, favor keeping as `find.text()` if the assertion is genuinely testing that the widget renders correct text (not just that it exists)

2. **whether very small test files (1-2 calls) should be grouped into a single commit**
   - What we know: D-12 says one commit per test file, D-12 also grants discretion to group small files
   - What's unclear: Whether files like `widget_test.dart` (1 call), `happy_path_test.dart` (1 call), `ledger_test.dart` (4 calls) warrant individual commits
   - Recommendation: Group files with ≤4 calls that test the same feature area into a single commit

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Flutter SDK | flutter test, Key types | Yes | 3.41.5 (stable) | — |
| Dart SDK | abstract final class, const Key | Yes | ^3.10.1 | — |
| flutter_test | find.byKey(), testWidgets | Yes | SDK-bundled | — |

No missing dependencies. This phase is purely code/test changes within the existing Flutter SDK.

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | flutter_test (SDK-bundled, Flutter 3.41.5) |
| Config file | none — standard `flutter test` |
| Quick run command | `flutter test test/unit/widget_coverage_test.dart` |
| Full suite command | `flutter test` |

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| FOUND-05 | All structural assertions use find.byKey() | Integration | `flutter test` (full suite passes) | Yes — existing suite |
| FOUND-05 | Rename 'Ledger' to 'Treasury' causes zero byKey() failures | Smoke | Manual rename + `flutter test` | Yes — D-13 protocol |
| FOUND-05 | 624 tests pass after key additions | Regression | `flutter test` | Yes |

### Sampling Rate
- **Per widget file keyed:** `flutter test` for the matching test file only
- **Per test file commit:** `flutter test` for that specific file (fast, < 30 seconds for a single file)
- **Per wave / after 5+ commits:** `flutter test` full suite
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
None — existing test infrastructure covers all phase requirements. Key class files (`lib/features/*/keys/*.dart`, `lib/core/keys/shared_keys.dart`) are source files, not test infrastructure.

---

## Sources

### Primary (HIGH confidence)
- Flutter SDK source — `Key`, `ValueKey`, `find.byKey()` API verified from Flutter 3.41.5 (stable, 2026-03-17)
- Direct codebase inspection — all counts (257 find.text(), 90 find.byType(), 22 screen files) verified by grep against actual test files
- `14-CONTEXT.md` — locked decisions D-01 through D-14

### Secondary (MEDIUM confidence)
- Flutter widget test documentation pattern — `abstract final class` with `static const Key` is the established Dart pattern for constant namespaces, confirmed by codebase usage of `abstract class FirestoreRepository`

### Tertiary (LOW confidence)
- Structural vs content classification estimates (~174 structural / ~83 content) — manual sampling of top files; exact numbers will vary during implementation

---

## Metadata

**Confidence breakdown:**
- Key class API: HIGH — verified from Flutter SDK (Key, ValueKey, find.byKey are stable APIs unchanged since Flutter 2.x)
- Architecture patterns: HIGH — derived directly from locked decisions in CONTEXT.md
- Structural vs content taxonomy: HIGH for clear cases, MEDIUM for borderline calls
- Call count estimates: HIGH — direct grep count from codebase (not estimates)
- CI warning script: MEDIUM — pattern is correct, exact baseline count requires completing migration first

**Research date:** 2026-03-28
**Valid until:** 2026-04-28 (30 days — Flutter test API is highly stable)
