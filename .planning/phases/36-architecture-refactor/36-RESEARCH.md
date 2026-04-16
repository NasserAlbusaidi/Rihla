# Phase 36: Architecture Refactor — Research

**Researched:** 2026-04-16
**Domain:** Flutter/Dart + Riverpod + Firestore + SQLite architecture debt reduction
**Confidence:** HIGH (in-codebase evidence; no external library research needed)

## Summary

This phase pays down three interrelated architectural debts in Rihla with **zero user-facing change**: god screens that violate the 600-LOC ceiling, a home-dashboard provider graph that fans out O(G×E) Firestore listeners, and a 660-line all-static `CacheService` that duplicates writes with `BalanceCacheRepository`. The surface area is much smaller than it looks: the codebase has already moved to a Firestore-first model and the legacy Supabase-era `CacheService` has exactly **one** live caller in production (`tripLogisticsParticipantsProvider`), which simplifies the decomposition story dramatically.

The god screens all share one shape: a single `ConsumerStatefulWidget` with 5–10 private `_buildX()` helpers on the state class. Every extraction target already has clean seams — tabs in settle-up, steps in edit-expense, card/list/section blocks in gear/logistics, card blocks in create-event. The adjacent widget folders (`lib/features/*/widgets/`) already hold smaller siblings created in prior phases (Phase 10, Phase 17, Phase 29), providing a clear extraction template.

**Primary recommendation:** Split each god screen into widget-per-section siblings under `lib/features/<feature>/widgets/` or `lib/features/<feature>/widgets/sections/`; replace `weeklyGroupSpendingProvider`'s full-download pattern with a Firestore collection-group range query on the existing `createdAt` ISO-8601 string field (requires one new composite index); fold every `CacheService` method into domain repositories registered via Riverpod providers and delete `CacheService.dart` wholesale after migrating the single remaining caller.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Phase Boundary (in scope):**
- `group_settle_up_screen.dart` (990 LOC) — decompose
- `edit_expense_screen.dart` (799 LOC) — decompose
- `gear_screen.dart` (731 LOC) — decompose
- `logistics_screen.dart` (690 LOC) — decompose
- `create_event_screen.dart` (690 LOC) — decompose (already defensible; lighter touch)
- `home_screen.dart` provider fan-out
- `weeklyGroupSpendingProvider` query strategy
- `cache_service.dart` decomposition
- `balance_cache_repository.dart` overlap reconciliation

**Out of scope:**
- UI redesign or visual changes (Phase 37 handles theming)
- New features of any kind
- Firestore schema migration
- Security/auth changes (Phase 38 handles storage rules)
- Test coverage for services without tests today (#33, deferred)

**Screen decomposition strategy (ARCH-01):**
- Target: No screen file > 600 LOC. Stretch: ≤ 400 LOC.
- Method: Extract sub-widgets into sibling files under the feature's `widgets/` directory. Apply the step-widget pattern from `AddExpenseScreen` consistently.
- State handling: Pure-presentational sub-widgets become `StatelessWidget`/`ConsumerWidget`. Stateful orchestration that belongs in state management moves into new `StateNotifier`s or derived providers.
- Tests: Each extracted widget gets at least one golden or widget test exercising its primary path. Screen-level tests continue to cover integration.

**Provider fan-out (ARCH-02, ARCH-03):**
- Home dashboard: Replace O(G×E) subscriptions with one per-group aggregate stream.
- Weekly spending: Use Firestore `where('occurredAt', >= startOfWeek)` plus a secondary `<= endOfWeek` bound, or a `weekKey` denormalized field, rather than downloading all expenses and filtering in Dart.
- Reactivity: Dashboard must remain live — use `Stream` providers, not `Future` snapshots.

**CacheService decomposition (ARCH-04):**
- Split into domain repositories: `ExpenseCacheRepository`, `GearCacheRepository`, `ParticipantCacheRepository`, `ActivityLogCacheRepository`, etc.
- Reconcile with `balance_cache_repository.dart`: either fold balance caching into the new structure (preferred) or keep `balance_cache_repository.dart` as the sole writer and have the new expense repository defer balance refresh to it. No silent double-writers.
- Instances, not static: Convert from all-static to injected instances registered via Riverpod providers.
- Back-compat: Remove `CacheService` only after all call sites migrate.

**Migration safety:**
- TDD required. Each decomposition step starts with a failing widget or unit test for the new surface.
- No behavior change. Balance calculations, settlement suggestions, and ledger totals must match pre-refactor values.
- Commit atomicity: Each `<plan>.md` lands in a single atomic commit.
- Provider-watch regression fence: A test asserts that `home_screen.dart` does not instantiate more than N providers for a group with K events.

### Claude's Discretion
- Exact widget extraction granularity per screen (how many sub-widgets per split)
- Whether to use `StatefulShellRoute` side-effects or leave routing untouched
- Naming of new repository classes
- Whether weekly spending uses a date-range query, a `weekKey` denormalization, or a Cloud Function trigger (pick based on research findings + Firestore cost/latency trade-offs)
- Folder placement of extracted widgets (sibling `widgets/` vs. screen-adjacent `sections/`)

### Deferred Ideas (OUT OF SCOPE)
- Dark theme widget migration (Phase 37)
- textMuted contrast fixes (Phase 37)
- Spacing token adoption (Phase 37)
- Storage Cloud Functions (Phase 38)
- Test coverage expansion for services without tests (#33 — TEST-01..04)
- `copyWith` sentinel pattern (#22)
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| ARCH-01 | No screen file exceeds 600 lines (split or extract widgets). Applies to `group_settle_up_screen.dart` (990), `edit_expense_screen.dart` (799), `gear_screen.dart` (731/measured 729), `logistics_screen.dart` (690), `create_event_screen.dart` (690/measured 689). | Screen extraction maps in §Architecture Patterns; sibling-folder conventions verified; existing widget folders already populated by prior refactors. |
| ARCH-02 | Home dashboard provider fan-out is bounded — per-group subscription replaces O(G×E) per-event listeners. | Dashboard fan-out analysis in §Architecture Patterns identifies `weeklyGroupSpendingProvider` as the sole O(G×E) source; `groupBalancesProvider` already aggregates at per-group granularity via the desired pattern. |
| ARCH-03 | `weeklyGroupSpendingProvider` uses a Firestore date-range query (or cached aggregate), not a full expenses download + client filter. | Expense.createdAt stored as ISO-8601 UTC string — lexicographically sortable. Firestore collection-group query supports string range comparisons. New composite index needed. |
| ARCH-04 | `CacheService` (660 lines, all static) split into focused repositories with cohesive write strategies. Deduplicate overlap with `balance_cache_repository.dart`. | Only ONE live call site of CacheService remains (`trip_provider.dart:21`). Full decomposition plus deletion is feasible within the phase. BalanceCacheRepository is the existing instance-based template. |
</phase_requirements>

## Project Constraints (from CLAUDE.md)

**Architectural (authoritative):**
- Feature-first structure: `lib/features/<feature>/{models,providers,screens,services,widgets}`.
- Riverpod 2.x without code-gen. `StreamProvider.family` for Firestore subscriptions; `Provider.family` for derived aggregates; `StateNotifierProvider` for complex state.
- GoRouter declarative routing. Screens receive `groupId`/`eventId` as string path params; no `state.extra`.
- `Decimal` package (not `double`) for all money; OMR is 3 decimal places.
- Offline-first: cache-on-success + fallback-to-cache-on-error.

**Coding (from global rules):**
- Immutability non-negotiable — create new objects, never mutate existing ones.
- Files 200-400 lines typical, 800 max. High cohesion, low coupling.
- TDD mandatory: RED → GREEN → REFACTOR, 80%+ coverage.
- No hardcoded secrets; validate all input at boundaries.
- All colors via `AppColorTokens` (CI blocks direct `Color(0xFF…)`).

**Testing:**
- `flutter test` for unit + widget tests.
- `fake_cloud_firestore ^4.1.0+1` for Firestore-backed tests.
- `sqflite_common_ffi ^2.3.4` for in-memory SQLite tests.
- `mocktail ^1.0.4` for mocking.

**Stale CLAUDE.md warning:** `CLAUDE.md` still describes the Supabase-era offline pipeline (`OfflineRepository`, `SyncService`, SQLite version 5). These do not reflect reality:
- `OfflineRepository` does not exist in `lib/`.
- SQLite schema version is **6**, not 5 (verified in `lib/core/services/local_database.dart:11`).
- Firestore is the authoritative data layer; SQLite is a thin side-cache driven by the `eventExpensesProvider`/`eventSettlementsProvider` asyncMap pipelines.

## Standard Stack

No new packages. This is a pure refactor using existing infrastructure.

### Core (in use, verified against `pubspec.yaml`)
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `flutter_riverpod` | `^2.5.1` (installed) | State management, provider graph | Already the entire app's state substrate. `Provider.family` is the right tool for per-group aggregation (see `groupBalancesProvider` for the working template). |
| `cloud_firestore` | `^4.17.5` (installed) | Primary data layer | Already used; supports range filters on string fields lexicographically — critical for ARCH-03. |
| `sqflite` | `^2.3.3+1` + `sqflite_common_ffi` (test) | Offline cache | Existing `safar_cache.db` (version 6) is the migration target for the new repositories. |
| `decimal` | `^2.3.3` (installed) | Money precision | Mandatory — do not change anything about money math during refactor. |
| `fake_cloud_firestore` | `^4.1.0+1` (dev) | Firestore unit tests | Pattern already established in `expense_service_test.dart`. Use for ARCH-03 query-shape assertions. |
| `mocktail` | `^1.0.4` (dev) | Mock services | Already used across the test suite. |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `go_router` | `^13.2.0` | Navigation | No change — do not touch routing in this phase. |
| `shared_preferences` | `^2.2.2` | Persisted settings | No change. |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Per-group `Provider.family` aggregation for dashboard | Cloud Function that maintains a single denormalized `groupSummary` doc per group | Denormalization adds write amplification on every expense/settlement and requires a Cloud Function deploy. Phase 38 is the Cloud Function phase. Keep client-side aggregation for this phase. |
| Firestore range query for weekly spending | Denormalize a `weekKey` (`YYYY-Www`) field on every expense | `weekKey` requires a backfill over all existing expenses and enforces write amplification. Range query on existing `createdAt` is zero-migration. |
| Per-domain cache repositories | Single refactored `CacheService` with instance methods | With only 1 live caller, domain repos cost nothing more than the refactor itself and give us the dependency-injection discipline we already use for `BalanceCacheRepository`. |

**Installation:** None. All packages already installed.

**Version verification skipped:** No new dependencies to verify.

## Architecture Patterns

### Recommended Project Structure (no change — confirms existing pattern)
```
lib/
├── features/
│   ├── groups/
│   │   ├── screens/
│   │   ├── widgets/               # target for settle-up tab extractions
│   │   └── providers/
│   ├── ledger/
│   │   ├── screens/
│   │   ├── widgets/               # target for edit-expense step extractions
│   │   └── providers/
│   ├── gear/
│   │   ├── screens/
│   │   └── widgets/               # currently only gear_hero_card.dart — expand
│   ├── logistics/
│   │   ├── screens/
│   │   └── widgets/               # currently only sub_group_card.dart — expand
│   ├── events/
│   │   ├── screens/
│   │   └── widgets/               # create-event card extractions
│   └── home/
│       ├── screens/               # home_screen.dart (505 LOC — already under ceiling, leave)
│       ├── widgets/
│       └── providers/
│           └── dashboard_providers.dart   # WHERE ARCH-02, ARCH-03 LAND
└── core/
    └── services/
        ├── cache_service.dart             # DELETE after migration
        ├── balance_cache_repository.dart  # RENAME or merge into new repo set
        └── <new>/                         # or expand this directory with domain caches
            ├── expense_cache_repository.dart
            ├── gear_cache_repository.dart
            ├── participant_cache_repository.dart
            ├── sub_group_cache_repository.dart
            ├── activity_log_cache_repository.dart
            └── category_cache_repository.dart
```

### Pattern 1: Screen Decomposition via Sibling Widget Files

**What:** Extract pure-presentational `_buildX()` methods on a stateful widget into top-level `StatelessWidget`/`ConsumerWidget` files in the feature's `widgets/` folder. Keep screen-scoped state (controllers, booleans) on the screen class; pass data down as constructor args and lift callbacks up.

**When to use:** Every `_buildX()` helper > 30 LOC that reads data plus returns a widget tree; every tab body in a TabBarView; every step body in a step-widget flow.

**Reference (already in codebase):** `lib/features/ledger/screens/add_expense_screen.dart` alongside `lib/features/ledger/widgets/` (12 extracted widgets including `category_selection_step.dart`, `split_scope_selector.dart`, `amount_input_section.dart`, `receipt_picker_section.dart`). The screen is still 672 LOC because step orchestration + validation lives there — below the 800 max but above the 600 soft ceiling. This phase can tighten that further but it is not a primary target.

**Example seam:**
```dart
// Source: lib/features/groups/widgets/group_settlement_tile.dart (existing)
class GroupSettlementTile extends StatelessWidget {
  final Settlement settlement;
  final String currency;
  final VoidCallback? onTap;

  const GroupSettlementTile({
    super.key,
    required this.settlement,
    required this.currency,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Presentational. No ref.watch. No setState.
    return ListTile(/* ... */);
  }
}
```

### Pattern 2: Per-Group Aggregation Provider (ARCH-02 template)

**What:** A `Provider.family<AsyncValue<T>, String groupId>` that watches all per-group streams, folds them, and returns a single `AsyncValue`. Consumers on the dashboard watch the aggregate (one provider per group) instead of the underlying streams.

**When to use:** Any UI that needs to show derived state aggregated from a variable-length list of child documents.

**Reference (already in codebase):** `lib/features/groups/providers/group_balance_provider.dart:109` — `groupBalancesProvider` is the exact template. It watches `groupEventsProvider` + `groupMembersProvider` + `groupSettlementsProvider`, loops over events calling `ref.watch(eventExpensesProvider(...))` + `ref.watch(eventSettlementsProvider(...))`, and returns a `GroupBalances` record.

**Critical Riverpod property:** `ref.watch()` inside a loop is **safe in Provider.family bodies** (it is not safe inside `StreamProvider` bodies — the pattern already caught this with the "RESEARCH Pitfall 2" comment in the file). Any new aggregate providers in this phase MUST be `Provider.family`, not `StreamProvider.family`.

**Example:**
```dart
// Source: lib/features/groups/providers/group_balance_provider.dart:109
final groupBalancesProvider =
    Provider.family<AsyncValue<GroupBalances>, String>((ref, groupId) {
  final eventsAsync = ref.watch(groupEventsProvider(groupId));
  // ... fold, loop over events watching child providers, return AsyncValue.data
});
```

### Pattern 3: Firestore Range Query on ISO-8601 String (ARCH-03 target)

**What:** Firestore range filters (`isGreaterThanOrEqualTo`, `isLessThanOrEqualTo`) on a `createdAt` field stored as an ISO-8601 UTC string. ISO-8601 is lexicographically sortable (e.g., `'2026-04-13T00:00:00.000Z' < '2026-04-14T...'`), so string comparison produces the correct date ordering.

**When to use:** Any per-date or per-week aggregation that currently pulls all documents and filters in Dart.

**Evidence in codebase:** `Expense.createdAt` is stored as `now.toIso8601String()` (lib/features/ledger/services/expense_service.dart:84). All Firestore reads deserialize via `DateTime.parse(data['createdAt'] as String)` (lib/features/ledger/models/expense_model.dart:161). No Firestore `Timestamp` type is used for `createdAt` — string comparison is valid.

**Index required:** Currently `firestore.indexes.json` has:
```json
{ "collectionGroup": "expenses", "queryScope": "COLLECTION",
  "fields": [
    { "fieldPath": "isDeleted", "order": "ASCENDING" },
    { "fieldPath": "createdAt", "order": "DESCENDING" }
  ]
}
```

The existing index supports `where('isDeleted', ==, false).orderBy('createdAt', descending: true)` which already includes the weekly range predicate structure — but for a **collection-group** query across all events of all the user's groups you must:

1. **Change queryScope** to `COLLECTION_GROUP` (currently `COLLECTION`). A collection-group query scans every subcollection named `expenses` anywhere in Firestore.
2. **Add `memberIds` or `groupId`** to the index if you need to pre-filter by group. The cheaper approach for Rihla: keep the per-group query pattern (one snapshot subscription per group) and do the date range inside each — this preserves the query shape of existing code and adds only the collection-group scope change **if you want a single query**. Practical recommendation: **stay per-group** (one `StreamProvider.family` listener per groupId) because groups already have a bounded listener (G listeners, not G×E), and the collection-group approach requires rewriting security rules to permit cross-group reads.

**Recommended query shape:**
```dart
Stream<List<Expense>> watchExpensesForDateRange({
  required String groupId,
  required String eventId,
  required DateTime startUtc,
  required DateTime endUtc,
}) {
  return eventSubcollection(groupId, eventId, 'expenses')
      .where('isDeleted', isEqualTo: false)
      .where('createdAt', isGreaterThanOrEqualTo: startUtc.toIso8601String())
      .where('createdAt', isLessThan: endUtc.toIso8601String())
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map(/* deserialize */);
}
```

**Composite index needed (add to `firestore.indexes.json`):** The existing `(isDeleted ASC, createdAt DESC)` index already covers this query exactly because Firestore range filters can be combined with equality filters on the same compound index. No new index is strictly required — **but** verify in manual testing that the query executes without a `FAILED_PRECONDITION: requires an index` error. If it does ask for an index, add the composite with the same fields + `__name__` as Firestore's error message requests.

### Pattern 4: Instance-Based Repository with Riverpod Provider

**What:** Replace static classes with classes that take a `Database` in their constructor (or lazily access `LocalDatabase.database`) and are exposed via a `Provider`. Tests override the provider with a fake DB.

**When to use:** Any SQLite access from production code. This is already the pattern for `BalanceCacheRepository`:

```dart
// Source: lib/core/services/balance_cache_repository.dart:11
final balanceCacheRepositoryProvider =
    Provider<BalanceCacheRepository>((ref) => BalanceCacheRepository());

class BalanceCacheRepository {
  Future<void> cacheExpenses(String eventId, List<Expense> expenses) async {
    final db = await LocalDatabase.database;
    // ...
  }
}
```

Consumers read via `ref.read(balanceCacheRepositoryProvider)`. The test pattern (`test/unit/balance_cache_repository_test.dart:1-30`) uses `sqflite_common_ffi` for in-memory SQLite without Riverpod overrides — just calls the repo methods directly with `LocalDatabase.clearAll()` between tests.

### Anti-Patterns to Avoid
- **Do not introduce a second cache writer.** Either fold `BalanceCacheRepository` into the new `ExpenseCacheRepository`/`SettlementCacheRepository` OR keep `BalanceCacheRepository` as-is and have the new repo classes delegate writes to it. Two writers → silent divergence.
- **Do not use `StreamProvider.family` for aggregate providers that watch child providers in a loop.** Use `Provider.family` returning `AsyncValue<T>`. Ref lookup inside a stream builder is not supported for variable-length lists.
- **Do not rename the SQLite `trip_id` column.** `BalanceCacheRepository` has explicit "NOTE: column stores eventId" comments (lib/core/services/balance_cache_repository.dart:73,110,143,181). A rename requires a schema migration AND a data backfill, which is out of scope per CONTEXT.
- **Do not introduce `StatefulShellRoute`.** Routing is explicitly out of scope. Existing `BottomNavShell` widget already handles the bottom-nav, and the app's routing is already under 500 LOC.
- **Do not decompose `home_screen.dart`.** At 505 LOC it is under the 600 ceiling; the god-screen list in CONTEXT does not include it. Touch only `_buildActivitySection` (which already calls the extracted `ActivityRow` widget — no refactor needed) and the `_handleGroupAction` / `_showFabBottomSheet` helpers **only if** you need to modify them for ARCH-02 wiring.

## Concrete Screen Decomposition Maps

Each map below was verified against the actual file (structure confirmed via grep of `_build*`, `class`, `Widget build` anchors). Extracted widgets land in `lib/features/<feature>/widgets/`.

### Map 1: `group_settle_up_screen.dart` (990 → target ≤ 400)

**Current structure** (from grep @ lib/features/groups/screens/group_settle_up_screen.dart):
- Line 36: `GroupSettleUpScreen extends ConsumerStatefulWidget`
- Line 53: `_GroupSettleUpScreenState`
- Line 76: `void _autoSelectTab(...)` — stays on screen (touches `_tabController`)
- Line 237: `Widget _buildTabLayout(...)` ~120 LOC
- Line 356: `Widget _buildSettlementTabContent(...)` ~74 LOC
- Line 430: `Widget _buildHistoryTab(...)` ~39 LOC
- Line 469: `Widget _buildHistoryTile(...)` ~83 LOC
- Line 552: `Widget _buildHistoryAvatar(...)` ~31 LOC
- Line 583: `Widget _buildAllSettledState(...)` ~73 LOC
- Line 656: `String _buildEventLabel(...)` — small helper, leave

**Proposed extraction:**
| New File | LOC (est.) | Contents |
|----------|-----------|----------|
| `widgets/settle_up_tab_layout.dart` | ~150 | Rewraps `_buildTabLayout` body — AppTabBar + TabBarView. Takes `balancesData`, `optimalSettlements`, `settlementsAsync`, `currentUid`, `controller`. Computes youOwe/owedToYou/betweenOthers splits and totalPending. |
| `widgets/settlement_tab_content.dart` | ~100 | `_buildSettlementTabContent` — list of settlement tiles + empty state. Takes `settlements`, `balancesData`, `eventNameMap`, `isYourAction`, `isCreditor`, `emptyIcon`, `emptyTitle`, `emptyMessage`. |
| `widgets/settle_up_history_tab.dart` | ~130 | `_buildHistoryTab` + `_buildHistoryTile` + `_buildHistoryAvatar` combined. Takes `settlementsAsync`, `currency`, `spacing`. |
| `widgets/all_settled_state.dart` | ~80 | `_buildAllSettledState` body. Pure visual. |

**Screen after:** ~400 LOC (initState, dispose, build, _autoSelectTab, small helpers, wiring). Stretch-target met.

**Risk:** `_autoSelectTab` mutates `_tabController.index` and reads `_tileKeys` — both are screen-scoped. Keep `_autoSelectTab` on the screen; call it before returning the extracted `SettleUpTabLayout`. Pass `tileKeys` down as a constructor arg.

### Map 2: `edit_expense_screen.dart` (799 → target ≤ 450)

**Current structure** (from grep):
- Line 28: `EditExpenseScreen extends ConsumerStatefulWidget`
- Line 44: `_EditExpenseScreenState`
- Line 69: `void _initializeControllers(Expense expense)` — stays on screen
- Line 206: `Widget _buildScopeSection()` ~85 LOC — mirrors `SplitScopeSelector`
- Line 291: `Widget _buildScopeTab(...)` ~38 LOC — internal to scope section
- Line 329: `Widget _buildCustomParticipantSelector(...)` ~32 LOC
- Line 361: `Widget _buildPayerSelector()` ~66 LOC
- Line 427: `Widget _buildForm(...)` (main form body) — large

**Proposed extraction:**
| New File | LOC (est.) | Contents |
|----------|-----------|----------|
| `widgets/edit_expense_scope_section.dart` | ~160 | `_buildScopeSection` + `_buildScopeTab` + `_buildCustomParticipantSelector`. Takes current scope, selected subgroup, participants list, `onScopeChanged`, `onSubGroupChanged`, `onCustomParticipantsChanged`. Reuse opportunity: compare against `lib/features/ledger/widgets/split_scope_selector.dart` (used by AddExpenseScreen) — **do they merge into one shared widget?** Check during planning; likely yes. |
| `widgets/edit_expense_payer_selector.dart` | ~70 | `_buildPayerSelector` body. |
| `widgets/edit_expense_form.dart` | ~220 | `_buildForm` — amount field, category picker (reuse `CategorySelectionStep`?), note field, submit button. Takes all controllers + callbacks. |

**Screen after:** ~380 LOC (controllers, init, validation, submit handler, build that composes the three widgets).

**Risk:** `_scope`, `_selectedSubGroupId`, `_customSplitParticipants`, `_selectedPayerId` are `setState`-managed. Pass down as constructor values + `onChanged` callbacks (immutable pattern). Check `AddExpenseScreen` for the same setState-vs-callback split — the extracted widgets there (`split_scope_selector.dart`, `category_selection_step.dart`) already use this pattern.

### Map 3: `gear_screen.dart` (729 → target ≤ 380)

**Current structure:**
- Line 28: `GearScreen extends ConsumerStatefulWidget`
- Line 42: `_GearScreenState`
- Line 130: `Widget _buildContent(...)` ~130 LOC (filters + list + empty state)
- Line 261: `Widget _buildGearItemCard(...)` ~155 LOC (LARGE — dominates)
- Line 419: `Widget _buildStatusChip(...)` ~25 LOC
- Line 445: `Widget _buildPriorityBadge()` ~25 LOC
- Line 471: `Widget _buildAddItemInput()` ~55 LOC
- Line 527: `Widget _buildFloatingAction()` ~17 LOC
- Line 545: `Widget _buildErrorState(...)` ~10 LOC
- Line 556: `void _focusAddField()` — stays
- Line 624: `void _confirmDelete(GearItem item)` — stays
- Line 669: `void _addItem()` — stays
- Line 708: `void _togglePacked(...)` — stays

**Proposed extraction:**
| New File | LOC (est.) | Contents |
|----------|-----------|----------|
| `widgets/gear_item_card.dart` | ~200 | `_buildGearItemCard` + `_buildStatusChip` + `_buildPriorityBadge`. Takes `item`, `currentUserId`, `onTogglePacked`, `onLongPress` (for delete). |
| `widgets/gear_add_input.dart` | ~75 | `_buildAddItemInput` + `_buildFloatingAction` (shared focus logic). Takes `controller`, `isHighPriority`, `onSubmit`, `onTogglePriority`. |
| `widgets/gear_list_view.dart` | ~130 | `_buildContent` body — filter bar + search + list + empty state. Takes `items`, `currentUserId`, `searchQuery`, `statusFilter`, `hideClaimed`, callbacks. |

**Screen after:** ~300 LOC (state, controllers, dialogs, handlers, build). Well under 400.

**Risk:** Many inline styles use `AppColorTokens.light.*` — do not change during this phase (Phase 37 migrates to `context.colors`).

### Map 4: `logistics_screen.dart` (690 → target ≤ 400)

**Current structure:**
- Line 29: `LogisticsScreen extends ConsumerStatefulWidget`
- Line 43: `_LogisticsScreenState`
- Line 147: `Widget _buildContent(...)` ~83 LOC (slivers + hero + list)
- Line 230: `Widget _buildHeroCard(...)` ~64 LOC
- Line 294: `void _showMemberPicker(SubGroup group)` ~168 LOC (bottom-sheet body — LARGE)
- Line 462: `void _confirmDeleteGroup(SubGroup group)` ~48 LOC (dialog)
- Line 510: `void _showCreateDialog({SubGroup? group})` ~80 LOC (dialog)

**Proposed extraction:**
| New File | LOC (est.) | Contents |
|----------|-----------|----------|
| `widgets/logistics_hero_card.dart` | ~80 | `_buildHeroCard`. Takes `groupCount`, `memberCount`, `unassignedCount`, `onCreateTapped`. |
| `widgets/logistics_member_picker_sheet.dart` | ~180 | Modal bottom sheet content from `_showMemberPicker`. Takes `subGroup`, `eventRef`, `onMemberSelected`. The `showModalBottomSheet` call stays on the screen; the `builder:` body becomes the widget. |
| `widgets/logistics_group_dialog.dart` | ~100 | `_showCreateDialog` content — name + capacity + type fields. Takes `initialGroup` (null for create), `onSubmit`. |
| `widgets/logistics_delete_confirmation.dart` | ~60 | `_confirmDeleteGroup` body. Or keep as a local function since dialogs are small — leave if extraction cost > value. |

**Screen after:** ~330 LOC.

**Risk:** `_showMemberPicker` reads `ref.read(eventDetailProvider(eventRef))` to get the event — inline. Pass the event data into the widget, not the eventRef, to keep the widget purely presentational.

### Map 5: `create_event_screen.dart` (689 → target ≤ 500)

CONTEXT already notes: "already defensible; lighter touch."

**Current structure:**
- Line 31: `CreateEventScreen extends ConsumerStatefulWidget`
- Line 45: `_CreateEventScreenState` with `_submitForm`, `_pickStartDate`, `_pickEndDate`
- Line 189: `Widget build(BuildContext context)` — large (~395 LOC because it inlines 4 card widgets)
- Line 574: `class _ParticipantRow extends StatelessWidget` (already extracted)
- Line 641: `class _ModuleToggleRow extends StatelessWidget` (already extracted)

**Proposed extraction (lighter):**
| New File | LOC (est.) | Contents |
|----------|-----------|----------|
| `widgets/event_type_badge.dart` | ~40 | `eventTypeBadge` inline Container from line ~225. Takes `typeConfig`. |
| `widgets/event_details_card.dart` | ~160 | `eventDetailsCard` inline Container from line ~253 (name field + dates row + pickers). Takes controllers + `startDate`/`endDate` + callbacks. |
| `widgets/event_participants_card.dart` | ~200 | `participantsCard` inline Container from line ~345. Uses existing `_ParticipantRow`. Takes `members`, `selectedIds`, `onToggle`. Move `_ParticipantRow` into this file. |
| `widgets/event_modules_card.dart` | ~100 | Module toggle rows for Custom events. Uses existing `_ModuleToggleRow`. Move into this file. |

**Screen after:** ~280–350 LOC (state, submit, pickers, build that composes the widgets).

**Risk:** This screen has complex mount-time initialization (`_participantsInitialized` + `addPostFrameCallback`). Keep that on the screen; pass fully-initialized `_selectedParticipantIds` into the participants card.

### Map 6: home_screen dashboard provider fan-out (ARCH-02)

**Current listener math for G groups, E events per group:**

| Provider | Listener Count | Location |
|----------|----------------|----------|
| `userGroupsProvider` | 1 | home_screen.dart:63 (dashboard) |
| `crossGroupBalanceProvider` | 1 | used by `BalanceHeroCard` (home/widgets/balance_hero_card.dart:27) |
| `crossGroupActivityProvider` | 1 | home_screen.dart:148 |
| `weeklyGroupSpendingProvider` | 1 | home/widgets/weekly_spending_card.dart:25 |
| `groupActivityProvider(groupId)` | **G** (via crossGroupActivityProvider loop) | dashboard_providers.dart:46 |
| `groupBalancesProvider(groupId)` | **G** (via crossGroupBalanceProvider loop + GroupCard loop) | dashboard uses shares via Riverpod's structural sharing |
| `groupEventsProvider(groupId)` | **G** (via groupBalancesProvider + weeklyGroupSpendingProvider + GroupCard) | |
| `groupMembersProvider(groupId)` | **G** (via groupBalancesProvider) | |
| `groupSettlementsProvider(groupId)` | **G** (via groupBalancesProvider) | |
| `eventExpensesProvider(eventRef)` | **G × E** (via groupBalancesProvider + **weeklyGroupSpendingProvider**) | the double-count |
| `eventSettlementsProvider(eventRef)` | **G × E** (via groupBalancesProvider only) | |

**The offender is `weeklyGroupSpendingProvider`.** It loops over groups AND events AND re-subscribes to every event's expenses just to filter by date client-side. That's the per-event fan-out that ARCH-02 targets.

**`crossGroupBalanceProvider` is innocent.** It only watches `groupBalancesProvider(groupId)` — O(G) subscriptions at the aggregate level. The G×E child subscriptions inside `groupBalancesProvider` are **necessary** for accurate per-event balance breakdown (feature requirement for settle-up screens). They cannot be removed without losing correctness.

**Fix strategy for ARCH-02:**

The correct framing is narrower than "replace G×E with G": the dashboard should not be the source of G×E subscriptions **when those subscriptions exist solely for weekly aggregation**. Fix `weeklyGroupSpendingProvider` to stop walking per-event expenses, and the dashboard fan-out problem resolves.

**Two viable approaches:**

**(a) Per-group range-filtered aggregate stream** (recommended):
- New `weeklyGroupExpensesProvider = StreamProvider.family<List<Expense>, String groupId>` that subscribes to `collectionGroup('expenses')` under `groups/{groupId}/events/*/expenses` with `where('createdAt', isGreaterThanOrEqualTo: startOfWeekIsoUtc).where('isDeleted', ==, false)`. Requires collection-group index (see ARCH-03).
- Rewire `weeklyGroupSpendingProvider` to `Provider<AsyncValue<List<DailySpending>>>` that watches `userGroupsProvider` then watches `weeklyGroupExpensesProvider(groupId)` for each group. Per-group subscription; no per-event subscription.
- Listener count: G per-group subs (not G×E). One Firestore query per group, server-side filtered.

**(b) Cached weekly aggregate in SQLite** (alternative, adds complexity):
- A `WeeklySpendingCacheRepository` that tracks `weekKey → totalByDay` per group. Updated via listener on expense writes. Harder to keep fresh; defers the real fix.

**Recommendation:** Approach (a). It is the direct answer to both ARCH-02 and ARCH-03 in one change. The Cloud Function path (approach b + trigger) is out of scope per CONTEXT.

**Verification approach for ARCH-02:** A test in `test/unit/dashboard_providers_test.dart` that sets up `userGroupsProvider.overrideWith([g1, g2])` and `groupEventsProvider(g1).overrideWith([e1,e2,e3])` etc., then uses `ProviderContainer` to listen to `weeklyGroupSpendingProvider`, then asserts `eventExpensesProvider(anything)` is **never** watched (check via `container.read` returning `AsyncValue` without triggering materialization, or by using a spy `StreamProvider` that counts subscriptions).

### Map 7: `CacheService` decomposition (ARCH-04)

**Call-site reality check:** Only ONE live caller of `CacheService` in `lib/` as of today:
```
lib/features/trip/providers/trip_provider.dart:21:  yield await CacheService.getCachedParticipants(tripId);
```

This is `tripLogisticsParticipantsProvider` — marked `@Deprecated('Will be migrated to Firestore stream in 04-05.')`. In tests: 0 references.

**This is a critical finding.** CONTEXT says "remove `CacheService` only after all call sites migrate. Acceptable to land in two steps within this phase." With only 1 live caller, the two-step plan is:

**Step A:** Migrate `tripLogisticsParticipantsProvider` to read from a new `ParticipantCacheRepository` instance. This is a ~3-line edit.
**Step B:** Delete `lib/core/services/cache_service.dart` wholesale.

Even if the planner decides to land 5 new repository files (one per domain), the domain repositories can be created **empty** and `CacheService` deleted in the same phase — because nothing else references it.

**Method inventory in `cache_service.dart` by domain** (verified against the file):

| Domain | Methods | SQLite tables touched |
|--------|---------|------------------------|
| **Trip** | `cacheTrip`, `getCachedTrips`, `deleteTrip` (cascade delete across 7 tables) | `trips`, `activity_logs`, `categories`, `expenses`, `settlements`, `gear_items`, `participants`, `sub_groups`, `sub_group_members` |
| **Expense** | `cacheExpenses`, `getCachedExpenses` | `expenses` (**overlap with BalanceCacheRepository.cacheExpenses**) |
| **Settlement** | `cacheSettlements`, `getCachedSettlements` | `settlements` (**overlap with BalanceCacheRepository.cacheSettlements**) |
| **Gear** | `cacheGearItems`, `cacheSingleGearItem`, `getCachedGearItems` | `gear_items` |
| **Participant** | `cacheParticipants`, `getCachedParticipants` | `participants` |
| **SubGroup** | `cacheSubGroups`, `getCachedSubGroups` | `sub_groups`, `sub_group_members` |
| **ActivityLog** | `cacheActivityLogs`, `getCachedActivityLogs` | `activity_logs` |
| **Category** | `cacheCategories`, `getCachedCategories` | `categories` |
| **Group** | `cacheGroup`, `getCachedGroups`, `cacheGroupMember`, `getCachedGroupMembers`, `deleteGroupCache` | `groups`, `group_members` |

**Proposed new repository set (instance-based, Riverpod-provided):**

| New File | Methods | Notes |
|----------|---------|-------|
| `lib/core/services/cache/trip_cache_repository.dart` | `cacheTrip`, `getCachedTrips`, `deleteTrip` | `deleteTrip` is the cross-table cascade — keep as a single transactional method. |
| `lib/core/services/cache/expense_cache_repository.dart` | `cacheExpenses`, `getCachedExpenses` | **Consolidate with `BalanceCacheRepository.cacheExpenses`** (see below). |
| `lib/core/services/cache/settlement_cache_repository.dart` | `cacheSettlements`, `getCachedSettlements` | Same as above — merge with BalanceCacheRepository. |
| `lib/core/services/cache/gear_cache_repository.dart` | `cacheGearItems`, `cacheSingleGearItem`, `getCachedGearItems` | |
| `lib/core/services/cache/participant_cache_repository.dart` | `cacheParticipants`, `getCachedParticipants` | Only repo with a production caller today. |
| `lib/core/services/cache/sub_group_cache_repository.dart` | `cacheSubGroups`, `getCachedSubGroups` | |
| `lib/core/services/cache/activity_log_cache_repository.dart` | `cacheActivityLogs`, `getCachedActivityLogs` | |
| `lib/core/services/cache/category_cache_repository.dart` | `cacheCategories`, `getCachedCategories` | |
| `lib/core/services/cache/group_cache_repository.dart` | `cacheGroup`, `getCachedGroups`, `cacheGroupMember`, `getCachedGroupMembers`, `deleteGroupCache` | |

**Folder placement decision:** Put new repos in `lib/core/services/cache/` subfolder (new directory). This keeps them colocated but distinct from single-instance services like `notification_service.dart`.

**Conflict strategy per repo (explicit):**

| Repo | Write strategy | Why |
|------|----------------|-----|
| Trip, Gear (single item), Participant, SubGroup, ActivityLog, Category, Group | `ConflictAlgorithm.replace` (existing) | Upsert by primary key; no deletion needed since source of truth is Firestore. |
| Expense, Settlement | **Delete-all-for-event then batch insert** (from BalanceCacheRepository pattern) | Prevents ghost rows from server-side deletes. Critical for balance correctness. This is the ONLY correct pattern for these two. CacheService.cacheExpenses (current) does a plain replace — **a latent ghost-row bug** until the stale-SQLite fix shipped in commit `8288da2`. |

**The BalanceCacheRepository / CacheService overlap resolution:**

CONTEXT says "either fold balance caching into the new structure (preferred) or keep `balance_cache_repository.dart` as the sole writer and have the new expense repository defer balance refresh to it."

**Recommended:** **Rename `BalanceCacheRepository` → `ExpenseCacheRepository` + `SettlementCacheRepository`** and move the methods into the new cache folder. `BalanceCacheRepository` becomes a fiction — the name no longer matches its actual responsibility (it is just SQLite I/O for expenses and settlements, not a "balance" cache per se).

- `ExpenseCacheRepository.cacheExpenses` ← from `BalanceCacheRepository.cacheExpenses` (the delete-then-insert version).
- `ExpenseCacheRepository.getExpenses` ← from `BalanceCacheRepository.getExpenses`.
- `ExpenseCacheRepository.watchExpenses` ← from `BalanceCacheRepository.watchExpenses` (deprecated; retain during migration, delete when nothing watches).
- `SettlementCacheRepository.cacheSettlements` + `.getSettlements` + `.watchSettlements` ← mirror from BalanceCacheRepository.

Then update `eventExpensesProvider` and `eventSettlementsProvider` (in `expense_provider.dart`) to read from the new providers:
```dart
// Was:
final cache = ref.read(balanceCacheRepositoryProvider);
await cache.cacheExpenses(eventRef.eventId, expenses);
// Becomes:
final cache = ref.read(expenseCacheRepositoryProvider);
await cache.cacheExpenses(eventRef.eventId, expenses);
```

**SQLite schema decisions:**
- **No version bump needed.** The refactor does not change schema; it only changes which Dart class writes to existing tables. `local_database.dart:11` stays at `_databaseVersion = 6`.
- **No column renames.** `trip_id` stays as the column name (already explicitly documented as "stores eventId" in 8 annotated comments).

**Deletion plan for `cache_service.dart`:**
1. Land all new repository files (empty of callers).
2. Migrate `trip_provider.dart:21` to `ref.read(participantCacheRepositoryProvider).getCachedParticipants(tripId)`.
3. Update `balance_cache_repository.dart` consumers to use new provider names (find-replace pair: `balanceCacheRepositoryProvider` → `expenseCacheRepositoryProvider` where cacheExpenses is called; same for settlement sites).
4. Run `flutter analyze` — confirm zero references to `CacheService` remain.
5. Delete `lib/core/services/cache_service.dart`.
6. Delete `lib/core/services/balance_cache_repository.dart`.
7. Update `lib/core/README.md` to remove `cache_service.dart` bullet.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Firestore query parameterization | Custom query builder classes | Use the existing `FirestoreRepository` base class (`lib/core/services/firestore_repository.dart`) | 51-line file already provides `eventSubcollection(groupId, eventId, name)` helpers and accepts an injectable `FirebaseFirestore` for tests. |
| In-memory SQLite for tests | Mocking `Database` with mocktail | `sqflite_common_ffi` — call `databaseFactory = databaseFactoryFfi` in `setUpAll`. Pattern already in `test/unit/balance_cache_repository_test.dart`. | Tests validate actual SQL behavior, not mock interactions. |
| Custom fake Firestore | Hand-rolled stream controllers | `fake_cloud_firestore ^4.1.0+1` (already a dev dep) | Standard for all Firestore query-shape tests in the codebase. |
| Provider listener counting in tests | Custom subscription tracking | Riverpod's `ProviderContainer.listen(provider, (_, __) {}, fireImmediately: true)` + overriding child providers with counting stubs. Existing dashboard_providers_test uses this pattern. | Exposes Riverpod's internal subscription semantics without mocking. |
| Cross-event balance math | Custom aggregator | `BalanceCalculator.calculateBalances(...)` (existing) — unchanged by this phase. | Already battle-tested via `test/unit/balance_calculations_test.dart`. |
| Date range boundaries (start/end of week) | Custom timezone logic | Existing `_emptyWeek(startOfWeek)` + `DateTime` Monday-arithmetic in `dashboard_providers.dart:111`. | Consistent with app-wide Monday-first week convention. |

**Key insight:** Every repository/provider/test pattern you need is already present in the codebase. This phase is translation work, not invention.

## Runtime State Inventory

Applies because this is a refactor that renames providers, moves files, and deletes one file outright.

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | SQLite `safar_cache.db` version 6 with 11 tables. All data is disposable — SQLite is a cache of Firestore (source of truth). No Firestore data migrations. No cached data needs transformation. | None. Schema unchanged. |
| Live service config | None. Firestore security rules don't reference `CacheService` (rules are server-side). No deployed Cloud Functions touched. | None. |
| OS-registered state | None — Flutter mobile app, no OS task scheduler or launchd entries. | None. |
| Secrets/env vars | None. Refactor does not touch `config.json`, FCM tokens, or any secret key. | None. |
| Build artifacts / installed packages | No code-generated files depend on renamed provider identifiers. Riverpod providers are manually declared (no `riverpod_generator`). No `.g.dart` files to regenerate. Pub cache is insensitive. | None. |

**Existing user-installed apps:** The Flutter app on user devices will still read SQLite `safar_cache.db` v6 after update. Tables stay the same. No in-place data migration needed. Re-downloaded data from Firestore overwrites existing rows via the new repository classes.

**The canonical question answered:** After every file in the repo is updated, the only runtime-state gap is: does an installed app on v2.3 correctly open the v6 SQLite DB with the new repository code? Yes — same schema, same column names, same table names.

## Common Pitfalls

### Pitfall 1: `ref.watch` inside `StreamProvider` body
**What goes wrong:** Calling `ref.watch(childProvider)` inside a `StreamProvider.family` body crashes at runtime because Riverpod cannot re-subscribe to variable-length dependencies in a stream context.
**Why it happens:** Aggregate providers that watch N child providers (where N is read from a prior watch) must return a derived value synchronously.
**How to avoid:** Aggregate providers are `Provider.family<AsyncValue<T>, ...>`. Stream-shaped data only when the aggregation is 1:1. See comment "RESEARCH Pitfall 2" in `group_balance_provider.dart:87` for the in-codebase acknowledgment.
**Warning signs:** Compile passes but `LateInitializationError` or `"Provider was modified during building"` at runtime.

### Pitfall 2: Double cache writers for the same table
**What goes wrong:** `CacheService.cacheExpenses` uses plain `ConflictAlgorithm.replace` which leaves ghost rows when Firestore deletes a record. `BalanceCacheRepository.cacheExpenses` uses delete-then-insert which does not. If both write to the same table, balances silently drift.
**Why it happens:** Historical split — `CacheService` predates the Firestore migration; `BalanceCacheRepository` was created later.
**How to avoid:** This refactor eliminates `CacheService.cacheExpenses` / `cacheSettlements` entirely. The new `ExpenseCacheRepository` inherits the delete-then-insert pattern.
**Warning signs:** A ghost-row regression test (already present: `balance_cache_repository_test.dart` exercises this) catches it.

### Pitfall 3: SQLite column `trip_id` rename temptation
**What goes wrong:** The column name is misleading — it stores `eventId` for Firestore-era events. A well-meaning rename breaks all read/write queries without a schema migration and silently returns zero rows.
**Why it happens:** Flutter tests don't test SQL strings; they test behavior. A renamed column with no data changes looks "correct" in compile + test but returns empty at runtime.
**How to avoid:** DO NOT rename. Respect the 8 annotated `// NOTE:` comments. If a rename is eventually desired, it requires a v7 schema migration AND a backfill. Out of scope.

### Pitfall 4: Extracting a widget that secretly reads `context` deep-scoped data
**What goes wrong:** A `_buildX` helper inside the state class has access to `context`, `ref`, and `widget.xxx`. Extracting to a separate file breaks the implicit `widget.xxx` capture, and you end up rewriting constructor signatures three times before the tests pass.
**Why it happens:** Hidden coupling via `this.widget.groupId`.
**How to avoid:** Audit every `widget.xxx` and `ref.watch()` call in the helper. Pass all of those as constructor args explicitly. Keep the widget `StatelessWidget` unless it genuinely needs state.
**Warning signs:** `undefined identifier widget` compile errors after extraction. Treat each as a required constructor arg.

### Pitfall 5: Firestore string range query without the equality prefix
**What goes wrong:** `where('createdAt', >=, iso).orderBy('createdAt')` works. But adding `where('isDeleted', ==, false)` without the index fails with `FAILED_PRECONDITION: requires an index`.
**Why it happens:** Firestore composite indexes must cover all filter fields.
**How to avoid:** The existing `(isDeleted ASC, createdAt DESC)` index already covers `where isDeleted==false AND where createdAt>=X`. Test in dev with emulator or real Firestore BEFORE shipping. If Firestore returns the "create this index" URL, follow it — don't try to guess.
**Warning signs:** `FAILED_PRECONDITION` error in test or dev logs with an index URL.

### Pitfall 6: `flutter test` unknowingly skips widgets that use `FirebaseConfig.currentUser`
**What goes wrong:** Screens read `FirebaseConfig.currentUser?.uid` directly. In tests, this throws if Firebase isn't initialized. The app uses `currentUserIdProvider` to make this mockable, but extracted widgets might inline the direct call.
**Why it happens:** Extraction might copy-paste the `FirebaseConfig.currentUser` access.
**How to avoid:** Any extracted widget that needs the current UID reads it via `ref.watch(currentUserIdProvider)` (defined in `group_balance_provider.dart:331`), not `FirebaseConfig.currentUser` directly.

## Code Examples

### Existing Pattern 1: Per-group aggregate provider (target pattern for ARCH-02)
```dart
// Source: lib/features/groups/providers/group_balance_provider.dart:109
final groupBalancesProvider =
    Provider.family<AsyncValue<GroupBalances>, String>((ref, groupId) {
  final eventsAsync = ref.watch(groupEventsProvider(groupId));
  if (eventsAsync.isLoading && !eventsAsync.hasValue) {
    return const AsyncValue.loading();
  }
  // ... fold + loop + return AsyncValue.data
});
```

### Existing Pattern 2: Firestore stream service with injectable test DB
```dart
// Source: lib/features/ledger/services/expense_service.dart:20
class ExpenseService extends FirestoreRepository {
  ExpenseService() : super();

  @visibleForTesting
  // ignore: invalid_use_of_visible_for_testing_member
  ExpenseService.withFirestore(super.db) : super.withFirestore();

  Stream<List<Expense>> watchExpenses(String groupId, String eventId) {
    return eventSubcollection(groupId, eventId, 'expenses')
        .where('isDeleted', isEqualTo: false)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(/* ... */);
  }
}
```

### Existing Pattern 3: Instance-based cache repository with Riverpod provider
```dart
// Source: lib/core/services/balance_cache_repository.dart:11
final balanceCacheRepositoryProvider =
    Provider<BalanceCacheRepository>((ref) => BalanceCacheRepository());

class BalanceCacheRepository {
  Future<void> cacheExpenses(String eventId, List<Expense> expenses) async {
    final db = await LocalDatabase.database;
    await db.delete('expenses', where: 'trip_id = ?', whereArgs: [eventId]);
    // ... batch insert
  }
}
```

### Existing Pattern 4: Widget extraction skeleton
```dart
// Source: lib/features/groups/widgets/group_settlement_tile.dart (pattern)
class SomeExtractedTile extends StatelessWidget {
  final DataModel data;
  final String currency;
  final VoidCallback? onTap;

  const SomeExtractedTile({
    super.key,
    required this.data,
    required this.currency,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Purely presentational — no ref.watch, no setState, no widget.xxx
    return InkWell(onTap: onTap, child: /* ... */);
  }
}
```

### Target pattern for ARCH-03 (new)
```dart
// NEW: lib/features/ledger/services/expense_service.dart (added method)
Stream<List<Expense>> watchExpensesInRange({
  required String groupId,
  required String eventId,
  required DateTime startUtc,
  required DateTime endExclusiveUtc,
}) {
  return eventSubcollection(groupId, eventId, 'expenses')
      .where('isDeleted', isEqualTo: false)
      .where('createdAt', isGreaterThanOrEqualTo: startUtc.toIso8601String())
      .where('createdAt', isLessThan: endExclusiveUtc.toIso8601String())
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((snap) => snap.docs.map(Expense.fromFirestore).toList());
}
```

### Target pattern for ARCH-02 dashboard fan-out (new)
```dart
// NEW: lib/features/home/providers/dashboard_providers.dart (rewritten weekly provider)
final weeklyGroupExpensesProvider =
    StreamProvider.family<List<Expense>, String>((ref, groupId) {
  // Compute start of current week (Monday 00:00:00 UTC) and start of next week
  final now = DateTime.now().toUtc();
  final today = DateTime.utc(now.year, now.month, now.day);
  final startOfWeek = today.subtract(Duration(days: today.weekday - 1));
  final startOfNextWeek = startOfWeek.add(const Duration(days: 7));

  // Per-group subscription — Firestore range-filters server-side
  return _watchAllEventsExpensesInRange(
    groupId: groupId,
    startUtc: startOfWeek,
    endExclusiveUtc: startOfNextWeek,
    ref: ref,
  );
});

final weeklyGroupSpendingProvider =
    Provider<AsyncValue<List<DailySpending>>>((ref) {
  final groupsAsync = ref.watch(userGroupsProvider);
  // ... loop over groups, watch weeklyGroupExpensesProvider(group.id) (G subs, not G×E)
  // Fold into 7-day DailySpending list.
});
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `CacheService.staticMethod(...)` | Instance-based repos via `ref.read(fooCacheRepositoryProvider)` | Established when `BalanceCacheRepository` was added (commit `8288da2` 2026-04-09) | Testability without static state hacking. |
| `OfflineRepository + SyncService` offline pipeline | Firestore stream + asyncMap side-write to SQLite | v1.0 Phase 7 (Supabase removal) | CLAUDE.md is stale; journal.md confirms the migration. |
| God screen with 10 `_buildX()` helpers | Screen + widget folder with per-section `StatelessWidget` files | Phases 10, 17, 29 (see git log) | Sustained pressure — the god screens regrew after their last split. |
| Per-event client-side filter for weekly aggregate | Per-group server-side range query | This phase (ARCH-03) | Reduces listener count from O(G×E) to O(G). |

**Deprecated/outdated:**
- `CacheService` class: 1 live caller, to be deleted this phase.
- `BalanceCacheRepository.watchExpenses` / `.watchSettlements`: explicitly marked `@Deprecated`, marked for removal in "Plan 04-05" (that plan already shipped — remove during ARCH-04).
- `tripLogisticsParticipantsProvider`: marked `@Deprecated` in `trip_provider.dart:18`. Not a deletion target in this phase.

## TDD Ordering (First Failing Tests Per Requirement)

**ARCH-01 (god screens):** First failing test is a file-size assertion, not a widget test.

```dart
// test/architecture/screen_size_test.dart (new file)
void main() {
  group('Screen LOC ceiling (ARCH-01)', () {
    test('no screen file exceeds 600 lines', () async {
      final dir = Directory('lib/features');
      final screens = await dir
          .list(recursive: true)
          .where((e) => e.path.contains('/screens/') && e.path.endsWith('.dart'))
          .cast<File>()
          .toList();

      final violations = <String>[];
      for (final f in screens) {
        final lines = (await f.readAsLines()).length;
        if (lines > 600) violations.add('${f.path}: $lines');
      }
      expect(violations, isEmpty, reason: 'Screens over 600 LOC: $violations');
    });
  });
}
```

Run before any extraction to confirm RED (5 violations). Run after each extraction plan to confirm progress. GREEN when violations is empty.

Per extracted widget, ALSO add a widget test exercising its primary render path (see existing `test/features/groups/group_settle_up_screen_test.dart` for the pattern).

**ARCH-02 (dashboard fan-out):** Listener count assertion.

```dart
// test/unit/dashboard_providers_test.dart (new test in existing file)
test('weeklyGroupSpendingProvider does not watch eventExpensesProvider', () async {
  var eventExpensesWatchCount = 0;
  final container = ProviderContainer(
    overrides: [
      userGroupsProvider.overrideWith((_) => Stream.value([g1])),
      groupEventsProvider('g1').overrideWith((_) => Stream.value([e1, e2, e3])),
      eventExpensesProvider((groupId: 'g1', eventId: 'e1')).overrideWith((_) {
        eventExpensesWatchCount++;
        return Stream.value(<Expense>[]);
      }),
      // Same for e2, e3.
    ],
  );
  addTearDown(container.dispose);

  container.listen(weeklyGroupSpendingProvider, (_, __) {}, fireImmediately: true);
  await _pump(container);

  expect(eventExpensesWatchCount, equals(0),
      reason: 'ARCH-02: weekly spending must not subscribe per-event');
});
```

**ARCH-03 (weekly query shape):** `fake_cloud_firestore` query-shape assertion.

```dart
// test/unit/expense_service_test.dart (new test)
test('watchExpensesInRange filters server-side by createdAt', () async {
  final fakeDb = FakeFirebaseFirestore();
  final service = ExpenseService.withFirestore(fakeDb);

  final startUtc = DateTime.utc(2026, 4, 13);       // Mon of this week
  final endUtc = DateTime.utc(2026, 4, 20);         // Mon of next week

  // Seed expenses INSIDE and OUTSIDE the range
  await service.addExpense(
    groupId: 'g1', eventId: 'e1',
    payerParticipantId: 'p1', amount: Decimal.parse('10.000'),
    // Force createdAt via test harness to 2026-04-01 (outside range)
    /* ... */
  );
  await service.addExpense(/* 2026-04-15, inside */);

  final stream = service.watchExpensesInRange(
    groupId: 'g1', eventId: 'e1',
    startUtc: startUtc, endExclusiveUtc: endUtc,
  );
  final result = await stream.first;

  expect(result.length, equals(1));
  expect(result.first.createdAt.isAfter(startUtc), isTrue);
});
```

**ARCH-04 (no CacheService calls remain):** Codebase assertion.

```dart
// test/architecture/no_cache_service_test.dart (new file)
void main() {
  test('no file in lib/ references CacheService', () async {
    final result = await Process.run('grep', ['-rn', 'CacheService', 'lib/']);
    expect(result.stdout.toString().trim(), isEmpty,
        reason: 'ARCH-04: CacheService must be fully removed');
  });
}
```

Run before any repository migration to confirm RED (1 match). Run after the deletion plan commits — GREEN when grep returns nothing.

## Risk & Dependency Map

**Cross-screen state dependencies flagged:**
- `edit_expense_screen.dart` reads `eventSubGroupsProvider` for the scope selector. `logistics_screen.dart` writes to the same collection. If the logistics refactor changes the sub_group service interface, edit-expense's scope selector must be tested together. **Mitigation:** Keep logistics and edit-expense plans in the same wave only if the sub_group_service signature is being changed (it is not in this phase).

- `gear_screen.dart` and `edit_expense_screen.dart` both read `eventDetailProvider(eventRef)` inline. Extracted widgets in both screens must respect the same pattern. Independent but parallel work.

- `dashboard_providers.dart` watches `groupActivityProvider` and `groupEventsProvider`. The CacheService refactor does NOT touch these — they are pure Firestore. **Low risk.**

- `home_screen.dart` `_buildActivitySection` renders `CrossGroupActivityEntry` records produced by `crossGroupActivityProvider` in dashboard_providers. The weekly-spending provider rewrite changes the provider file but not the activity provider; these two are independently safe to work on.

**Recommended execution order for plans:**

1. **Plan W0 — Wave 0 test scaffolding** (parallel-safe):
   - Add `test/architecture/screen_size_test.dart` and `test/architecture/no_cache_service_test.dart` (both RED).
   - Add provider-watch-count test stubs in `test/unit/dashboard_providers_test.dart` (RED).
   - Commit with all tests RED. Establishes the finish lines.

2. **Wave 1 — Screen decompositions** (fully parallel, 5 plans):
   - Plan A: `group_settle_up_screen.dart` split (largest, do first).
   - Plan B: `edit_expense_screen.dart` split.
   - Plan C: `gear_screen.dart` split.
   - Plan D: `logistics_screen.dart` split.
   - Plan E: `create_event_screen.dart` split (lightest touch).
   These 5 plans touch different files; no merge conflicts.

3. **Wave 2 — CacheService decomposition** (one plan, mostly mechanical):
   - Plan F: Create `lib/core/services/cache/` folder with 9 new repository files. Migrate `trip_provider.dart:21` to `participantCacheRepositoryProvider`. Rename `BalanceCacheRepository` methods into `ExpenseCacheRepository` + `SettlementCacheRepository`. Update `expense_provider.dart` asyncMap side-writes to use new providers. Delete `cache_service.dart` and `balance_cache_repository.dart`. Verify no-cache-service grep test passes.

4. **Wave 3 — Dashboard fan-out fix** (one plan, depends on Wave 2 for cleanliness but is strictly independent):
   - Plan G: Add `watchExpensesInRange` to `ExpenseService`. Add `weeklyGroupExpensesProvider` to `dashboard_providers.dart`. Rewrite `weeklyGroupSpendingProvider` to consume the new per-group stream. Update `test/unit/dashboard_providers_test.dart` — existing tests fed by `userGroupsProvider.overrideWith([])` still pass; new test asserts no per-event fan-out. Add Firestore index if needed (test with emulator).

**Wave 2 and Wave 3 can run in parallel** — they touch different folders. Wave 1 can run entirely in parallel with both because neither touches `lib/features/{groups,ledger,gear,logistics,events}/screens/`.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Flutter SDK | Build + test | ✓ | Whatever pubspec specifies | — |
| `flutter test` runner | All unit + widget tests | ✓ (stdlib) | — | — |
| `sqflite_common_ffi` | SQLite in-memory tests | ✓ dev dep | ^2.3.4 | — |
| `fake_cloud_firestore` | Firestore query-shape tests | ✓ dev dep | ^4.1.0+1 | — |
| `mocktail` | Mocks | ✓ dev dep | ^1.0.4 | — |
| Firestore composite indexes (existing) | ARCH-03 range query | ✓ `(isDeleted ASC, createdAt DESC)` already indexed | — | If Firestore demands a different index, the error URL gives the exact index to add. |
| Firestore emulator | Manual dev verification of ARCH-03 query | Likely ✓ (required for offline dev testing) | — | Test against production with a single group if emulator unavailable. |

**Missing dependencies with no fallback:** None.

**Missing dependencies with fallback:** None.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | `flutter_test` (Flutter SDK) + `test: ^1.24.9` |
| Config file | None (Flutter default); `analysis_options.yaml` for lints |
| Quick run command | `flutter test --plain-name '<test name>' test/<file>.dart` |
| Full suite command | `flutter test` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| ARCH-01 | No screen file > 600 LOC | unit (file I/O) | `flutter test test/architecture/screen_size_test.dart` | ❌ Wave 0 — add |
| ARCH-01 | Each extracted widget renders primary path | widget | `flutter test test/features/<feature>/<widget>_test.dart` | Partial — widget test files exist for many widgets in `test/features/home/widgets_test.dart`, `test/features/groups/*`, add per new widget |
| ARCH-02 | `weeklyGroupSpendingProvider` does not subscribe to `eventExpensesProvider` | unit (provider) | `flutter test test/unit/dashboard_providers_test.dart` | ✅ exists — extend with new test |
| ARCH-02 | `crossGroupBalanceProvider` listener count is O(G), not O(G×E) | unit (provider) | same file | ✅ existing file, add test |
| ARCH-03 | `watchExpensesInRange` filters server-side by `createdAt` | unit (fake_firestore) | `flutter test test/unit/expense_service_test.dart` | ✅ exists — add test |
| ARCH-03 | `weeklyGroupSpendingProvider` returns correct 7-day distribution with mixed in-range/out-of-range expenses | unit (provider) | `flutter test test/unit/dashboard_providers_test.dart` | ✅ extend |
| ARCH-04 | No production code references `CacheService` | unit (grep) | `flutter test test/architecture/no_cache_service_test.dart` | ❌ Wave 0 — add |
| ARCH-04 | `ExpenseCacheRepository.cacheExpenses` prevents ghost rows (delete-then-insert) | unit (SQLite) | `flutter test test/unit/expense_cache_repository_test.dart` | ❌ Wave 0 — rename from `balance_cache_repository_test.dart` |
| ARCH-04 | `eventExpensesProvider` asyncMap side-writes to new repo | unit (provider + SQLite) | `flutter test test/unit/expense_provider_test.dart` (if not existing, add to `expense_service_test.dart`) | Partial — verify |

### Sampling Rate
- **Per task commit:** `flutter test test/architecture/ test/unit/dashboard_providers_test.dart test/unit/expense_service_test.dart` (~5 sec)
- **Per wave merge:** `flutter test` (full suite — currently ~80 files)
- **Phase gate:** Full suite green before `/gsd-verify-work`

### Wave 0 Gaps
- [ ] `test/architecture/screen_size_test.dart` — covers ARCH-01
- [ ] `test/architecture/no_cache_service_test.dart` — covers ARCH-04
- [ ] Extend `test/unit/dashboard_providers_test.dart` with provider-watch-count tests for ARCH-02
- [ ] Extend `test/unit/expense_service_test.dart` with range-query test for ARCH-03
- [ ] `test/unit/expense_cache_repository_test.dart` — rename/replace `balance_cache_repository_test.dart` when the class is renamed (track in Wave 2)

No framework install needed. All tools already in `pubspec.yaml`.

## Security Domain

ARCH requirements are refactor-only; no new attack surface introduced. But two security-adjacent checks belong in planning:

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | No auth changes this phase. `currentUserIdProvider` already exists for the UID injection pattern. |
| V3 Session Management | no | — |
| V4 Access Control | yes (indirect) | Firestore security rules must still enforce `memberIds` check on new `watchExpensesInRange` query. The query uses the same subcollection path as the existing `watchExpenses`, so existing rules apply. Verify by running the query in dev with a non-member UID — it must return permission-denied. |
| V5 Input Validation | no | No new inputs. Range-query start/end are computed from device time, not user input. |
| V6 Cryptography | no | — |

### Known Threat Patterns for Flutter/Firestore

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Firestore query bypass via collection-group scan | Information Disclosure | Keep per-group subscription pattern; do not introduce `collectionGroup('expenses')` queries that scan across group boundaries without security rules support. |
| SQLite injection via unsanitized input | Tampering | All existing repos use parameterized queries (`whereArgs`). New repos MUST use the same pattern. No string concatenation into SQL. |
| Time-based race on `DateTime.now()` | Tampering | `weeklyGroupSpendingProvider` already uses local `DateTime.now()`. No trust boundary — display-only. No mitigation needed. |

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Rollback of `ConflictAlgorithm.replace` vs. delete-then-insert is safe because `BalanceCacheRepository` already survived a production ship via `8288da2`. | §Architecture Patterns, Pattern 4 | Low — commit shipped with tests. |
| A2 | The existing `(isDeleted ASC, createdAt DESC)` composite index covers the new range query without a new index definition. | ARCH-03 | Medium — verify in dev with Firestore emulator or real Firestore before shipping. If wrong, Firestore error message gives the exact index URL. |
| A3 | `StatefulShellRoute` is not needed for ARCH-02 because the dashboard fan-out fix is a provider change, not a routing change. | §Architecture Patterns, Anti-Patterns | Low — the existing `BottomNavShell` widget already solves persistent tab state. |
| A4 | `CacheService` has exactly 1 live caller as of 2026-04-16 based on grep. | §Architecture Patterns, Map 7 | Low — grep pattern `CacheService\.` found 1 match in `lib/`. Before deleting, re-run the grep. |
| A5 | SQLite schema version 6 in `local_database.dart:11` is accurate; CLAUDE.md saying "version 5" is stale. | §Project Constraints | Low — verified directly in source. |
| A6 | `Expense.createdAt` is ISO-8601 string in Firestore (not Timestamp). Firestore string range queries are lexicographically correct for ISO-8601. | ARCH-03 | Low — confirmed via `expense_service.dart:84` (`now.toIso8601String()`) and `expense_model.dart:161` (`DateTime.parse(data['createdAt'] as String)`). |
| A7 | `OfflineRepository` and `SyncService` described in CLAUDE.md do not exist in the current codebase (Supabase-era artifacts). | §Project Constraints | Low — grep returned zero matches in `lib/`. |

**Low risk:** 5/7 claims. Medium risk: A2 (Firestore index). Plan to verify A2 in a dev scratch task before the ARCH-03 implementation commit.

## Open Questions

1. **Should `BalanceCacheRepository` split into `ExpenseCacheRepository` and `SettlementCacheRepository`, or stay as one renamed class with both method sets?**
   - What we know: CONTEXT says "fold balance caching into the new structure (preferred)." The methods naturally partition by domain (expenses vs. settlements). Single-responsibility favors splitting.
   - What's unclear: Whether keeping one class named `BalanceCacheRepository` is more or less confusing than two classes split by domain.
   - Recommendation: Split into two. Delete `BalanceCacheRepository` filename wholesale; the name was never accurate.

2. **For `edit_expense_screen.dart`: can the extracted scope section reuse `lib/features/ledger/widgets/split_scope_selector.dart`?**
   - What we know: `split_scope_selector.dart` is already used by `AddExpenseScreen`. Both screens have similar scope-editing needs.
   - What's unclear: Whether edit-expense has special edit-mode behaviors (e.g., warning when changing scope on existing expenses) that split_scope_selector doesn't support.
   - Recommendation: Read `split_scope_selector.dart` during planning. If it accepts `initialScope` + `onChanged` callback, reuse. Otherwise document the difference and create a new widget.

3. **Should the per-group weekly provider be `Provider.family` (folded derived) or `StreamProvider.family` (direct stream)?**
   - What we know: The Firestore query returns a `Stream<List<Expense>>`, so `StreamProvider.family` is natural. But `weeklyGroupSpendingProvider` (the top-level UI provider) must fold multiple groups' streams.
   - What's unclear: Whether the top-level should be `Provider<AsyncValue<...>>` (folding N child streams) or something else.
   - Recommendation: Per-group provider is `StreamProvider.family<List<Expense>, String groupId>`. Top-level `weeklyGroupSpendingProvider` stays as `Provider<AsyncValue<List<DailySpending>>>`. The `Provider.family`-in-a-loop pattern handles the fold.

4. **Do extracted widgets need golden tests, or are widget tests sufficient?**
   - What we know: CONTEXT says "Each extracted widget gets at least one golden or widget test."
   - What's unclear: Whether goldens are already in use in the codebase.
   - Recommendation: Use widget tests by default; add goldens only if CI already runs golden comparison (check `test/features/**/*_test.dart` for `matchesGoldenFile`). Based on a quick glance at test files, widget tests are the norm.

## Sources

### Primary (HIGH confidence)
- `lib/features/groups/screens/group_settle_up_screen.dart` (990 LOC) — structural analysis via grep + spot-reads at lines 20-80, 230-360
- `lib/features/ledger/screens/edit_expense_screen.dart` (799 LOC) — spot-reads at 40-80, 200-330
- `lib/features/gear/screens/gear_screen.dart` (729 LOC) — spot-reads at 40-80, 125-300
- `lib/features/logistics/screens/logistics_screen.dart` (690 LOC) — spot-reads at 40-80, 140-300
- `lib/features/events/screens/create_event_screen.dart` (689 LOC) — spot-reads at 30-200, 190-400
- `lib/features/home/screens/home_screen.dart` (505 LOC) — full structural read including `ref.watch` grep
- `lib/core/services/cache_service.dart` (660 LOC) — full read
- `lib/core/services/balance_cache_repository.dart` (219 LOC) — full read
- `lib/core/services/local_database.dart` (528 LOC) — version + structure verification
- `lib/features/home/providers/dashboard_providers.dart` (166 LOC) — full read, identifies the weekly-spending fan-out
- `lib/features/groups/providers/group_balance_provider.dart` (365 LOC) — full read, the aggregation template
- `lib/features/ledger/services/expense_service.dart` — query-shape verification
- `lib/features/ledger/models/expense_model.dart` — `createdAt` ISO-8601 confirmation
- `firestore.indexes.json` — existing composite index verification
- `test/unit/dashboard_providers_test.dart` (195 LOC) — existing test pattern
- `test/unit/balance_cache_repository_test.dart` (304 LOC) — existing SQLite test pattern
- `test/unit/expense_service_test.dart` (246 LOC) — existing fake_firestore test pattern
- `test/features/home/home_screen_dashboard_test.dart` — existing widget test pattern

### Secondary (HIGH confidence, in-context)
- `.planning/phases/36-architecture-refactor/36-CONTEXT.md` — locked scope + decisions
- `.planning/milestones/v2.4-REQUIREMENTS.md` — ARCH-01..04 definitions
- `.planning/milestones/v2.4-ROADMAP.md` — phase success criteria
- `.planning/review/06-architecture-debt.md` — source issues #15, #16, #17, #18

### Tertiary (MEDIUM confidence)
- Git log analysis (`git log --oneline --grep="refactor"`) — confirms prior Phase 10, 17, 29 splits shipped and the god screens regrew since.

### External
- No web searches performed. All findings from in-codebase evidence. Firestore range-query behavior on ISO-8601 strings is a documented Firebase capability (cross-verified against general Firestore documentation knowledge — standard and stable across SDK versions 2021-2026).

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — no new packages; all decisions use existing dependencies.
- Architecture: HIGH — extraction maps verified against actual file structure; aggregate-provider pattern is already implemented in `groupBalancesProvider` (template).
- Cache decomposition: HIGH — call-site count verified (1 live caller). Method-to-domain mapping verified.
- Pitfalls: HIGH — all pitfalls cross-referenced with in-codebase comments or commit history.
- ARCH-03 query shape: MEDIUM-HIGH — confidence dips on Firestore index specifics (A2) which planner should verify before shipping.

**Research date:** 2026-04-16
**Valid until:** 30 days (stable domain — Flutter + Firestore + Riverpod 2.x; nothing external to stale).
