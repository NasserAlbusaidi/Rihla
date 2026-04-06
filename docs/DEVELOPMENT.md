<!-- generated-by: gsd-doc-writer -->

# Rihla Development Guide

Day-to-day reference for working in this codebase. See [ARCHITECTURE.md](./ARCHITECTURE.md) for the deeper system picture and [CONFIGURATION.md](./CONFIGURATION.md) for environment setup.

---

## 1. Development Workflow

### Running the app

```bash
# Requires config.json in the repo root with SUPABASE_URL, SUPABASE_ANON_KEY, SENTRY_DSN
flutter run --dart-define-from-file=config.json
```

Hot reload (`r`) and hot restart (`R`) work as usual. Full restart is needed when you change provider initialization, `main()`, or `firebase_options.dart`.

### Daily cycle

```bash
flutter pub get           # after pulling or changing pubspec.yaml
flutter analyze           # before committing — no warnings tolerated
flutter test              # full suite must stay green
flutter test test/unit/   # fast unit-only pass during active work
```

### Build

```bash
flutter build appbundle --release \
  --obfuscate \
  --split-debug-info=./build/app/outputs/symbols \
  --dart-define-from-file=config.json
```

CI runs this via `.github/workflows/release_android.yml` on `v*` tag push or manual dispatch.

---

## 2. Adding a New Feature

### Directory layout

Every feature lives under `lib/features/<name>/` and is self-contained:

```
lib/features/gear/
├── keys/          # GlobalKey / ValueKey constants
├── models/        # Plain Dart data classes (immutable)
├── providers/     # Riverpod providers
├── screens/       # ConsumerWidget / ConsumerStatefulWidget screens
├── services/      # Firestore service (extends FirestoreRepository)
└── widgets/       # Feature-local widgets
```

Not every folder is required. `trip/` has only `models/` and `providers/` — add subdirectories as the feature grows.

### Step-by-step

1. **Create the model** in `models/`. Make it immutable — all fields `final`, provide a `copyWith`. Firestore serialization goes on the model itself (`fromFirestore` / `toFirestore`).

2. **Create the service** in `services/`. Extend `FirestoreRepository` (`lib/core/services/firestore_repository.dart`) and call `eventSubcollection(groupId, eventId, 'your_module')` for the standard path `groups/{groupId}/events/{eventId}/your_module`.

3. **Wire up providers** in `providers/`. Use `StreamProvider.family<T, EventRef>` for Firestore real-time streams (see section 3 for patterns).

4. **Register the route** in `lib/core/router/app_router.dart` — add a constant to `AppRoutes` and a `GoRoute` entry (see section 4).

5. **Build the screen** in `screens/`. Screens receive IDs as constructor parameters (`groupId`, `eventId`) and fetch data via `ref.watch` inside `build`.

6. **Write tests first.** Unit test the model and service. Widget test the screen with mocked providers.

### Naming conventions

- Service class: `<Feature>Service` (e.g., `GearService`)
- Provider for stream: `event<Feature>Provider` for `EventRef`-scoped streams
- Provider for service: `<feature>ServiceProvider`
- Loading/error state: `<feature>LoadingProvider`, `<feature>ErrorProvider`

---

## 3. State Management Patterns

All providers are hand-written (no Riverpod code-gen). Key provider types in use:

### StreamProvider.family for Firestore real-time data

The primary pattern for all module data. The family parameter is `EventRef` — a named record `({String groupId, String eventId})`.

```dart
// lib/core/types/event_ref.dart
typedef EventRef = ({String groupId, String eventId});

// In a provider file
final eventGearItemsProvider =
    StreamProvider.family<List<GearItem>, EventRef>((ref, eventRef) {
  return ref
      .read(gearServiceProvider)
      .watchGearItems(eventRef.groupId, eventRef.eventId);
});
```

Usage in a screen:

```dart
final eventRef = (groupId: widget.groupId, eventId: widget.eventId);
final gearAsync = ref.watch(eventGearItemsProvider(eventRef));
```

### asyncMap side-write pattern (cache-on-success)

When a Firestore stream also needs to populate the SQLite cache (for `BalanceCalculator`), use `asyncMap` inside the `StreamProvider`:

```dart
final eventExpensesProvider = StreamProvider.family<List<Expense>, EventRef>((
  ref,
  eventRef,
) {
  final service = ref.read(expenseServiceProvider);
  final cache = ref.read(balanceCacheRepositoryProvider);
  return service.watchExpenses(eventRef.groupId, eventRef.eventId)
      .asyncMap((expenses) async {
        try {
          await cache.cacheExpenses(eventRef.eventId, expenses);
        } catch (e) {
          // SQLite cache is non-critical; Firestore is the source of truth
        }
        return expenses;
      });
});
```

This keeps the stream pipeline intact and guarantees SQLite is updated before downstream subscribers receive the data.

### Provider.family for derived state

Use when you need to combine two or more async sources without creating a new stream. Combine with `AsyncValue` operators:

```dart
final eventBalancesProvider = Provider.family<
    AsyncValue<List<UserBalance>>,
    ({EventRef eventRef, Event event})>((ref, params) {
  final expensesAsync = ref.watch(eventExpensesProvider(params.eventRef));
  final settlementsAsync = ref.watch(eventSettlementsProvider(params.eventRef));

  if (expensesAsync.isLoading || settlementsAsync.isLoading) {
    if (!expensesAsync.hasValue || !settlementsAsync.hasValue) {
      return const AsyncValue.loading();
    }
  }

  final expenses = expensesAsync.valueOrNull ?? [];
  final settlements = settlementsAsync.valueOrNull ?? [];

  return AsyncValue.data(BalanceCalculator.calculateBalances(
    expenses: expenses,
    settlements: settlements,
    participants: /* derived from params.event */,
  ));
});
```

### StateNotifierProvider for mutable state

Used for `settingsProvider` (persists to SharedPreferences) and the loading/error flag pairs:

```dart
final settingsProvider = StateNotifierProvider<SettingsNotifier, AppSettings>((ref) {
  final service = ref.watch(settingsServiceProvider);
  return SettingsNotifier(service);
});
```

The notifier calls `state = state.copyWith(...)` — never mutates the state object in place.

### StateProvider for simple flags

```dart
final gearLoadingProvider = StateProvider<bool>((ref) => false);
final gearErrorProvider = StateProvider<String?>((ref) => null);
```

### Rendering async state

The standard three-state pattern used in every screen:

```dart
gearAsync.when(
  loading: () => SkeletonLoader.gearList(),
  error: (e, _) => Center(child: Text('Error: $e')),
  data: (items) => /* real UI */,
);
```

---

## 4. Navigation

### Adding a new route

1. Add a constant to `AppRoutes` in `lib/core/router/app_router.dart`:

```dart
static const String myNewScreen = '/group/:gid/event/:eid/my-screen';
```

2. Add a `GoRoute` entry. Use `_slideRightTransition` for all module-level screens:

```dart
GoRoute(
  path: 'my-screen',
  pageBuilder: (context, state) => CustomTransitionPage(
    key: state.pageKey,
    child: MyNewScreen(
      groupId: state.pathParameters['gid']!,
      eventId: state.pathParameters['eid']!,
    ),
    transitionsBuilder: _slideRightTransition,
  ),
),
```

Nest it inside the appropriate parent `GoRoute` — event module routes go under `event/:eid`.

3. Navigate with `context.push('/group/$gid/event/$eid/my-screen')` or `context.go(...)` for root-level replacements.

### Transition rules

| Route type | Transition |
|---|---|
| Module screens (most routes) | `_slideRightTransition` — slide from right (Offset(1,0) → zero, `Curves.easeOutCubic`) |
| `/home`, `/onboarding` | `FadeTransition` |
| `/create-group`, `/join-group` | Slide-up (Offset(0,1) → zero) |

### No `state.extra`

Screens never receive data objects through `state.extra`. They always accept string IDs and fetch data inside `build` via `ref.watch`. This ensures deep links work without pre-loaded objects.

### Query parameters

Optional parameters go in the URI query string:

```dart
context.push('/group/$gid/settle-up?memberId=$memberId');
// Read in the route:
state.uri.queryParameters['memberId']
```

---

## 5. Offline Support

### How offline works

Firestore's built-in offline persistence (`persistenceEnabled: true`, set in `FirebaseConfig.initialize()`) handles offline write replay automatically. No manual upload queue. Screens using `StreamProvider` continue to receive cached Firestore data while offline.

The SQLite cache (`safar_cache.db` via `LocalDatabase`) is a secondary layer used specifically by `BalanceCalculator`, which needs random-access queries across expenses and settlements. Firestore streams side-write to SQLite via `asyncMap` (see section 3).

### ConnectivityNotifier

Watches Firestore reachability every 60 seconds by attempting a server-only read. Screens show `OfflineBanner` when `connectivityProvider` is `ConnectivityStatus.offline`.

```dart
// In a screen that needs the offline banner
const OfflineBanner(),  // from lib/shared/widgets/offline_banner.dart
```

### Making a feature work offline

1. **Reads:** No extra work if your provider uses `StreamProvider` with Firestore — Firestore's offline cache returns the last snapshot automatically.

2. **Writes:** No extra work — Firestore queues writes locally when offline and replays on reconnect. Service methods (`addGearItem`, `createGroup`, etc.) can be called offline.

3. **Balance calculations:** If your feature feeds `BalanceCalculator`, add a `cacheExpenses` / `cacheSettlements` call via `asyncMap` in the stream provider (see expense provider pattern above).

4. **LocalDatabase schema:** If you need a new SQLite table for balance caching, add it in `LocalDatabase._onCreate` and `_onUpgrade`, and bump `_databaseVersion`. Current version is 6.

### LocalDatabase tables

```
trips, expenses, settlements, gear_items, participants,
sub_groups, sub_group_members, activity_logs, categories,
groups, group_members, group_ledger
```

All monetary amounts are stored as `TEXT` (Decimal string representation). Soft-delete columns (`is_deleted INTEGER`, `deleted_at TEXT`) on expenses, gear_items, and settlements.

---

## 6. Design System

### Accessing tokens

Tokens are `ThemeExtension` classes. The canonical instances are:

```dart
AppColorTokens.light    // lib/core/theme/tokens/color_tokens.dart
AppSpacingTokens.standard  // lib/core/theme/tokens/spacing_tokens.dart
AppShadowTokens.standard   // lib/core/theme/tokens/shadow_tokens.dart
```

These are accessed as static singletons — no `Theme.of(context).extension<>()` needed in practice, though the ThemeExtension infrastructure is there for future dark theme support.

### Color tokens

Key tokens for new screens:

| Token | Hex | Use |
|---|---|---|
| `primary` | `#0D7B74` | Buttons, FABs, focused inputs, ledger accent |
| `textPrimary` | `#111827` | Body text, headings |
| `textSecondary` | `#6B7280` | Supporting labels, secondary info |
| `textMuted` | `#9CA3AF` | Decorative only — never for functional text or amounts |
| `cardSurface` | `#F8F9FA` | Card backgrounds |
| `inputFill` | `#F3F4F6` | Text field fill |
| `border` | `#E5E7EB` | Dividers, borders |
| `error` / `errorText` | `#EF4444` / `#B91C1C` | Error states (use `errorText` for text) |
| `success` / `successText` | `#10B981` / `#047857` | Success states (use `successText` for text) |
| `warning` | `#F59E0B` | Warning badges, offline indicator |

Module accent colors: Ledger = `moduleLedger` (#0D7B74 teal). All other modules = `moduleGear` (#6B7280 gray).

`textMuted` fails WCAG AA at 2.86:1 on white — never use it for readable labels, amounts, or status text.

### Spacing tokens

```dart
AppSpacingTokens.standard.space4   // 4dp
AppSpacingTokens.standard.space8   // 8dp
AppSpacingTokens.standard.space12  // 12dp
AppSpacingTokens.standard.space16  // 16dp — base grid unit
AppSpacingTokens.standard.space20  // 20dp
AppSpacingTokens.standard.space24  // 24dp
AppSpacingTokens.standard.space32  // 32dp

// Border radii
AppSpacingTokens.standard.radiusSmall   // 8dp — chips, tags
AppSpacingTokens.standard.radiusMedium  // 12dp — buttons, inputs
AppSpacingTokens.standard.radiusLarge   // 16dp — cards, sheets

// Button
AppSpacingTokens.standard.buttonHeight  // 52dp
```

### Shared widgets

All live in `lib/shared/widgets/`. Use these before building custom equivalents.

**`ModuleHeader`** — standard header for module screens with back button, title, and optional subtitle/actions. Pass `useDarkTheme: true` for the dark gradient header variant (used by Gear, Vault, Memories).

```dart
ModuleHeader(
  title: 'Gear',
  subtitle: 'PACK LIST',
  useDarkTheme: true,
  actions: [/* icon buttons */],
  bottom: AppTabBar(...),  // optional tab bar below title
)
```

**`AppTabBar`** — pill-indicator tab bar. Requires a `TabController`.

```dart
AppTabBar(
  controller: _tabController,
  tabs: const ['Unpacked', 'Packed'],
  activeColor: AppColorTokens.light.moduleLedger,  // optional override
)
```

**`SkeletonLoader`** — named factory constructors for content-aware loading states. Use the variant that matches the screen layout:

```dart
SkeletonLoader.gearList()        // gear item rows
SkeletonLoader.expenseList()     // expense rows with trailing amount
SkeletonLoader.eventCard()       // event cards
SkeletonLoader.groupList()       // group rows with avatar
SkeletonLoader.dashboardHero()   // balance hero + stats
SkeletonLoader.photoGrid()       // 3-column photo grid
SkeletonLoader.generic()         // plain fallback
```

**`EmptyStateView`** — consistent empty states with optional CTA:

```dart
EmptyStateView(
  icon: Iconsax.box,
  title: 'No items yet',
  message: 'Add gear your group needs to pack.',
  actionLabel: 'Add Item',
  onAction: () { /* ... */ },
  accentGradient: LinearGradient(...),  // optional colored icon background
)
```

**`LoadingButton`** — 52dp button with loading spinner:

```dart
LoadingButton(
  label: 'Save',
  isLoading: ref.watch(gearLoadingProvider),
  onPressed: _handleSave,
  gradient: AppColorTokens.light.primaryGradient,  // optional
)
```

**`OfflineBanner`** — self-contained offline indicator, place at top of Scaffold body.

**`SearchFilterBar`** — expandable search input with optional filter chips.

**`SmartModuleCard`** — module card for EventCommandCenter with summary/empty/action states.

---

## 7. Financial Code

### Core rule

All money calculations use `package:decimal`. Never use `double` for amounts.

```dart
import 'package:decimal/decimal.dart';

final price = Decimal.parse('10.500');
final tax = Decimal.parse('0.050');
final total = price + tax;  // Decimal('10.550') — exact
```

### Firestore storage: MoneySerializer

Amounts are stored as integer subunits to avoid floating-point in Firestore documents. Call `MoneySerializer` only at the Firestore read/write boundary:

```dart
// Writing to Firestore
final subunits = MoneySerializer.toSubunits(amount, 'OMR');
// OMR 10.500 → 10500

// Reading from Firestore
final amount = MoneySerializer.fromSubunits(subunitsInt, 'OMR');
// 10500 → Decimal('10.500')
```

Supported currencies: OMR (1000 subunits), USD/EUR/GBP/SAR/AED/QAR (100), JPY/KWD/BHD (1/1000).

### Formatting

```dart
AppFormatters.formatOMR(amount)                  // "10.500 OMR"
AppFormatters.formatCurrency(amount, 'USD')      // "$ 10.00"
AppFormatters.formatRelativeDate(date)           // "2 days ago"
AppFormatters.formatShortMonthDay(date)          // "Mar 15"
```

### BalanceCalculator

`BalanceCalculator` in `lib/features/ledger/providers/expense_provider.dart` is a pure function — no side effects, no providers. It takes expenses, settlements, participants, and optional sub-groups and returns a list of `UserBalance` objects.

Expense scopes:
- `global` — split equally among all participants
- `subGroup` — split among members of a specific `subGroupId`
- `personal` — only the payer owes (no redistribution)
- `custom` — split among `customSplitParticipants` list

Settlement optimization uses a greedy min-transactions algorithm (`calculateOptimalSettlements`). Takes `List<UserBalance>` and returns a list of payment maps with `fromUserId`, `toUserId`, `amount`.

### Soft deletes

Expenses, gear items, and settlements use `isDeleted` + `deletedAt` flags. Queries must filter `isDeleted == false`. Hard deletes only on trips (cascade) and media documents.

---

## 8. Code Style

These rules are non-negotiable:

### Immutability

Never mutate an existing object. Always return a new copy:

```dart
// Wrong
expense.amount = newAmount;

// Correct
final updated = expense.copyWith(amount: newAmount);
```

All model classes must have a `copyWith` method.

### File size

- Typical: 200–400 lines
- Hard limit: 800 lines
- When a file approaches the limit, extract: utilities → `utils/`, sub-widgets → `widgets/`, services → `services/`

### Function size

Target under 50 lines per function. Extract helper methods aggressively.

### Error handling

Never swallow errors silently unless it is explicitly the pattern (e.g., the offline Firestore propagation in `SettingsNotifier.setDeviceName`). At the UI layer, show user-facing error messages. Service layer errors bubble up as exceptions.

```dart
// Wrong
try {
  await service.doSomething();
} catch (_) {}

// Correct (unless explicitly a fire-and-forget)
try {
  await service.doSomething();
} catch (e) {
  debugPrint('[Feature] error: $e');
  ref.read(featureErrorProvider.notifier).state = 'Something went wrong';
}
```

### No hardcoded colors

All colors via `AppColorTokens.light.*`. The CI pipeline flags hardcoded `Color(0xFF...)` literals.

### Naming

- Providers: `<scope><Entity>Provider` — e.g., `eventGearItemsProvider`, `groupEventsProvider`
- Services: `<Entity>Service` — e.g., `GearService`, `ExpenseService`
- Screens: `<Feature>Screen` — `ConsumerStatefulWidget` for screens with local state, `ConsumerWidget` for stateless
- Models: plain `<Entity>` — e.g., `GearItem`, `Expense`, `Group`

### Testing

Tests live in `test/`. Structure mirrors `lib/`:

```
test/unit/         — pure logic, model, service tests
test/features/     — widget tests organized by feature
test/integration/  — full app widget tests with mocked providers
```

Provider overrides in widget tests follow the `sharedPreferencesProvider` pattern:

```dart
ProviderScope(
  overrides: [
    sharedPreferencesProvider.overrideWithValue(mockPrefs),
    eventGearItemsProvider.overrideWith((ref, arg) => Stream.value(mockItems)),
  ],
  child: const MyScreen(...),
)
```

The `onboardingCompleteProvider` must be overridden in integration tests that hit the home screen:

```dart
onboardingCompleteProvider.overrideWith((ref) => true),
```

Minimum coverage: 80%.
