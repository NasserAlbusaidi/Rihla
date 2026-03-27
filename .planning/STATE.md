---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
status: Ready to execute
stopped_at: Completed 12-01-PLAN.md
last_updated: "2026-03-27T21:55:52.314Z"
progress:
  total_phases: 13
  completed_phases: 11
  total_plans: 42
  completed_plans: 41
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-26)

**Core value:** Groups persist across events and accumulate financial history — friends settle up across trips, not just within one.
**Current focus:** Phase 12 — expense-logistics-provider-rewiring

## Current Position

Phase: 12 (expense-logistics-provider-rewiring) — EXECUTING
Plan: 2 of 2

## Performance Metrics

**Velocity:**

- Total plans completed: 0
- Average duration: -
- Total execution time: 0 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| - | - | - | - |

**Recent Trend:**

- Last 5 plans: -
- Trend: -

*Updated after each plan completion*
| Phase 01 P01 | 6 | 3 tasks | 6 files |
| Phase 01-data-foundation P03 | 2 | 2 tasks | 7 files |
| Phase 01 P02 | 5 | 3 tasks | 6 files |
| Phase 02-groups P00 | 3min | 2 tasks | 6 files |
| Phase 02-groups P01 | 7 | 3 tasks | 9 files |
| Phase 02-groups P02 | 5 | 3 tasks | 8 files |
| Phase 02-groups P03 | 8 | 3 tasks | 4 files |
| Phase 03-events P00 | 4 | 2 tasks | 7 files |
| Phase 03-events P01 | 6 | 2 tasks | 6 files |
| Phase 03-events P02 | 5 | 2 tasks | 4 files |
| Phase 03-events P03 | 6 | 2 tasks | 4 files |
| Phase 03-events P04 | 7 | 2 tasks | 6 files |
| Phase 04-firestore-repository-layer P00 | 5 | 2 tasks | 18 files |
| Phase 04-firestore-repository-layer P01 | 8 | 2 tasks | 6 files |
| Phase 04-firestore-repository-layer P02 | 10 | 2 tasks | 11 files |
| Phase 04-firestore-repository-layer P03 | 9 | 2 tasks | 13 files |
| Phase 04 P04 | 90m | 2 tasks | 18 files |
| Phase 04-firestore-repository-layer P05 | 65 | 3 tasks | 25 files |
| Phase 05 P00 | 2 | 2 tasks | 6 files |
| Phase 05 P02 | 3 | 1 tasks | 1 files |
| Phase 05 P01 | 20 | 2 tasks | 6 files |
| Phase 05 P03 | 7 | 1 tasks | 2 files |
| Phase 05 P04 | 10 | 2 tasks | 5 files |
| Phase 05 P05 | 8 | 2 tasks | 5 files |
| Phase 05 P06 | 4 | 2 tasks | 3 files |
| Phase 06 P02 | 4 | 2 tasks | 2 files |
| Phase 06 P03 | 3 | 2 tasks | 3 files |
| Phase 06 P04 | 7 | 3 tasks | 5 files |
| Phase 06 P05 | 90 | 2 tasks | 18 files |
| Phase 07 P01 | 4 | 2 tasks | 11 files |
| Phase 07-data-migration-and-supabase-removal P02 | 15 | 2 tasks | 20 files |
| Phase 08-integration-correctness-fixes P02 | 6 | 2 tasks | 4 files |
| Phase 08-integration-correctness-fixes P01 | 15 | 2 tasks | 7 files |
| Phase 09-dead-code-cleanup P01 | 8 | 1 tasks | 3 files |
| Phase 10-full-codebase-review P01 | 10 | 2 tasks | 19 files |
| Phase 10-full-codebase-review P02 | 7 | 2 tasks | 9 files |
| Phase 10-full-codebase-review P03 | 9 | 2 tasks | 9 files |
| Phase 10-full-codebase-review P04 | 15 | 2 tasks | 8 files |
| Phase 11-gear-write-mutations P01 | 10 | 2 tasks | 4 files |
| Phase 12 P01 | 6 | 2 tasks | 5 files |

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- [Pre-Phase 1]: Store all OMR amounts as integer fils in Firestore (MoneySerializer boundary); no Firestore doubles for money
- [Pre-Phase 1]: Firestore SDK cache is the read authority; SQLite populated as side effect of listener events only — never write to SQLite as the primary write path
- [Pre-Phase 1]: Group membership stored as map field on group document (`members: { uid: role }`) to avoid cross-document get() calls in security rules (10-get limit)
- [Pre-Phase 1]: Riverpod stays on 2.x for this milestone — Riverpod 3.x migration is a separate future milestone
- [Pre-Phase 1]: SyncService is deleted, not ported — Firestore offline persistence replaces the polling sync queue
- [Pre-Phase 1]: Group-level balance computed client-side from per-event summaries in SQLite — no single aggregation document that would create a write hotspot
- [Phase 01]: firebase_messaging bumped to ^16.1.3 — firebase_messaging 15.x is incompatible with firebase_core 4.x (transitive firebase_core_platform_interface conflict)
- [Phase 01]: FirebaseConfig static class mirrors SupabaseConfig pattern — consistent dual-auth config across the app
- [Phase 01-data-foundation]: memberIds is an array on group document — rules use in operator for O(1) membership check, no cross-document get() for group itself (D-14)
- [Phase 01-data-foundation]: Group delete blocked unconditionally (allow delete: if false) — groups are persistent cross-event constructs
- [Phase 01-data-foundation]: inviteCodes collection is publicly readable for join flow — authenticated write only
- [Phase 01]: decimal v3 division returns Rational not Decimal -- call .toDecimal(scaleOnInfinitePrecision: 10) at the Firestore read boundary
- [Phase 01]: sqflite_common_ffi added as dev dependency to enable in-memory SQLite testing on macOS/Linux/Windows
- [Phase 02-groups]: memberIds stored as List<String> array in Firestore and JSON-encoded in SQLite per D-14
- [Phase 02-groups]: GroupMember role field is String not enum (CREATOR/MEMBER) for forward-compatible Firestore serialization
- [Phase 02-groups]: Home screen fully replaces trip-based layout — no legacy trip UI retained
- [Phase 02-groups]: group/:id detail route registered as scaffold placeholder until Plan 03
- [Phase 02-groups]: Firebase currentUser access wrapped in try-catch for test safety — allows widget tests without Firebase initialization
- [Phase 02-groups]: GoRouter nested routes used for /group/:id/settings — consistent with GoRouter patterns while Navigator.push used within-screen for settings from GroupDetailScreen
- [Phase 03-events]: EventModules constructor does not force ledger=true — preset types enforce via forType(), Custom toggles via copyWith per D-14
- [Phase 03-events]: bridgeTripId falls back to doc.id — Supabase bridge always has valid trip ID for incremental field adoption
- [Phase 03-events]: EventService.withFirestore test constructor sets _skipBridgeInTest=true so gear seeding can be verified without Supabase initialization
- [Phase 03-events]: Supabase isAuthenticated check wrapped in try-catch to handle uninitialized Supabase in test/Firebase-only environments
- [Phase 03-events]: pull-to-refresh uses ref.invalidate(userGroupsProvider) not ref.refresh — invalidate closes and reopens the Firestore stream subscription for fresh fetch
- [Phase 03-events]: Custom event module overrides require optional modules param on EventService.createEvent — service now accepts modules override; null falls back to EventModules.forType(type)
- [Phase 03-events]: EventCard is ConsumerWidget to watch tripExpensesProvider(bridgeTripId) for live financial totals
- [Phase 03-events]: GroupDetailScreen FAB always visible (unconditional) — creating events valid regardless of loading state
- [Phase 03-events]: Trip facade used in EventCommandCenter: event.bridgeTripId as Trip.id, event.modules.vault mapped to TripModules.docs
- [Phase 03-events]: EventModuleList checks event.modules.ledger (not hardcoded) to support Custom type ledger toggle per D-14
- [Phase 04-00]: Expense.currency is a computed getter defaulting to 'OMR' -- existing model has no currency field, avoids breaking change while enabling MoneySerializer
- [Phase 04-00]: Module subcollection security uses nested match /{module}/{docId} under match /events/{eventId} -- functionally equivalent to flat path, Firestore canonical syntax
- [Phase 04-00]: SubGroup.fromFirestore returns members: const [] -- members are in a separate subcollection, not inlined in the document
- [Phase 04-01]: asyncMap used over listen() for SQLite side-write: keeps stream pipeline intact, ensures SQLite writes complete before downstream subscribers receive data
- [Phase 04-01]: CacheService.cacheExpenses/cacheSettlements used as interim until BalanceCacheRepository created in 04-04
- [Phase 04-01]: tripExpensesProvider/tripSettlementsProvider kept as deprecated shims -- screen migration deferred to 04-05
- [Phase 04-02]: EventRef typedef created in plan 04-02 (parallel to 04-01) — both wave-2 plans define identical content; no conflict
- [Phase 04-02]: gear_screen.dart legacy mutations routed to OfflineRepository — screen still on SQLite path, EventRef migration deferred to future plan
- [Phase 04-02]: logistics_screen.dart write operations stubbed with debugPrint — SubGroupService now requires EventRef; screen update deferred to EventRef migration plan
- [Phase Phase 04-03]: Document.fileUrl maps to storagePath in Firestore — backward compat with existing screen code
- [Phase Phase 04-03]: tripDocumentsProvider and tripMemoriesProvider kept as deprecated shims — screen migration deferred to EventRef migration plan
- [Phase Phase 04-03]: LazyMigrationService catches SupabaseConfig.isAuthenticated in try-catch per Phase 03 pattern
- [Phase 04]: BalanceCacheRepository replaces OfflineRepository for balance query path — narrow SQLite wrapper, no stream subscriptions to manage
- [Phase 04]: Firestore Source.server ping replaces Supabase auth.refreshSession for connectivity detection
- [Phase 04]: FirestoreRepository.withFirestore uses @protected so subclasses can call super.withFirestore without lint warnings (MIG-05)
- [Phase 04]: Camping gear seeding is now unconditional (not gated on Supabase bridge success)
- [Phase 04-firestore-repository-layer]: Removed tripBalancesProvider entirely — its only consumers were tests for the deleted Trip-based CommandCenter widget
- [Phase 04-firestore-repository-layer]: expense_provider.dart re-exports event_ref.dart so screens get EventRef transitively without redundant imports
- [Phase 05]: D-06 confirmed: BalanceCalculator handles combined multi-event expense lists without code changes — expense list is scope-agnostic, tripId on Expense is irrelevant to balance math
- [Phase 05]: logGroupEvent returns void not Future<void> for fire-and-forget activity writes; errors caught silently via catchError/debugPrint
- [Phase 05]: Settlement.fromFirestore reads scope with default 'event' for backward compat with existing event settlements that lack a scope field
- [Phase 05]: eventId sentinel for group settlements set to groupId — group settlements have no eventId, avoids null dereference in fromFirestore (RESEARCH Pitfall 3)
- [Phase 05]: Provider.family (not StreamProvider.family) used for groupBalancesProvider — enables ref.watch inside loops for variable-length event list (RESEARCH Pitfall 2)
- [Phase 05]: Test pump uses Future.delayed(Duration.zero) x10 for cascaded stream providers in Provider.family — microtask pump insufficient for 3-layer dependency cascade
- [Phase 05]: GroupBalanceHero is StatelessWidget (not ConsumerWidget) — parent reads groupBalancesProvider and passes data down as constructor params
- [Phase 05]: AnimatedCrossFade keeps both children in widget tree simultaneously — test assertions check button presence/absence rather than text visibility
- [Phase 05]: GroupActivityTile uses Dart 3 switch expression for icon/color dispatch per activity type
- [Phase 05]: GroupDetailScreen converted to ConsumerStatefulWidget for accordion expand state (_expandedMemberId) tracking GroupMemberBalanceCard (D-13)
- [Phase 05]: hasExpensesData non-null local variable used instead of bool hasExpenses — Dart flow analysis requires direct null check pattern to narrow nullable type inside if blocks
- [Phase 05]: GroupSettleUpScreen uses ConsumerStatefulWidget for ScrollController to auto-scroll to preSelectedMemberId tile (D-22)
- [Phase 06]: BalanceCalculator does not filter is_deleted expenses — caller responsibility to pre-filter; documented via test
- [Phase 06]: Over-settlement (paying more than owed) correctly flips creditor/debtor roles — verified via sign-direction assertions in 06-02 tests
- [Phase 06]: Group.fromDoc(DocumentSnapshot) tested via FakeFirebaseFirestore; Group.fromMap/toMap tests the SQLite path — both serialization paths covered
- [Phase 06]: Direct map testing for fromFirestore/toFirestore (no FakeFirestore overhead) is faster and equally valid for models that take Map params
- [Phase 06]: BalanceCalculator.calculateBalances takes List<Participant> not Map -- used Participant constructor with tripId=eventId for integration tests
- [Phase 06]: eventUnifiedLedgerProvider is Provider.family returning AsyncValue not StreamProvider -- override with AsyncValue.data not Stream.value
- [Phase 06]: Extended lcov exclusion list covers legacy Supabase features — makes 80% achievable without testing Firebase-auth-dependent legacy code (D-02 resolution)
- [Phase 06]: SettingsNotifier tests extracted to dedicated settings_notifier_test.dart — provider_tests.dart tests were not discovered in combined flutter test runs
- [Phase 07]: LazyMigrationService deleted and Supabase data recovery descoped per D-01 — old trip data abandoned, no migration needed
- [Phase 07]: supabase_flutter removed from pubspec.yaml — app now boots on Firebase only with no Supabase initialization
- [Phase 07]: firebase_auth.User.uid used everywhere — User.id was Supabase, User.uid is Firebase; three latent bugs fixed in gear_screen, edit_expense_sheet, split_scope_selector
- [Phase 07]: CategoryProvider hardcoded to 6 defaults — expense_categories Supabase table has no Firestore equivalent; custom categories deferred
- [Phase 07]: TripService class deleted — only served legacy create/join trip screens deleted in Plan 01; no active consumers remain
- [Phase 08-integration-correctness-fixes]: groupEventsProvider watched in build() with valueOrNull for non-blocking event name resolution in GroupSettleUpScreen -- empty map on loading/error triggers fallback label
- [Phase 08-integration-correctness-fixes]: Record type used for eventNameMap values ({name, type, date}) -- avoids creating a new class for a single-method lookup structure in settle-up screen
- [Phase 08-integration-correctness-fixes]: Pass Event object (not eventId String) to SplitScopeSelector so provider swap works without inner Firestore fetch
- [Phase 09-dead-code-cleanup]: firebase_auth_provider.dart deleted entirely — file served no purpose; canonical Firebase auth in auth_provider.dart (D-03)
- [Phase 09-dead-code-cleanup]: trip_provider.dart import removed from expense_provider.dart — exclusively used by deleted tripBalancesProvider; trip_model.dart kept for Participant/UserBalance types in BalanceCalculator
- [Phase 10-full-codebase-review]: EventRef implicit cast: use typed variable declaration (final EventRef x = (...)) not as EventRef cast
- [Phase 10-full-codebase-review]: Non-nullable Future result: drop variable assignment and await directly instead of checking != null
- [Phase 10-full-codebase-review]: SpendingSummarySection uses StatefulWidget for _showByCategory toggle — local ephemeral state, not lifted to screen
- [Phase 10-full-codebase-review]: TransactionList receives onEditExpense/onAddExpense callbacks — decouples widget from Navigator and parent screen
- [Phase 10-full-codebase-review]: GroupSettlementTile.onRecord is nullable VoidCallback — no button rendered when null (avoids isYourAction/isCurrentUser logic in extracted widget)
- [Phase 10-full-codebase-review]: UnassignedPool is StatelessWidget receiving pre-computed unassigned list — screen computes list from provider, avoids nested ref.watch in widget
- [Phase Phase 10-full-codebase-review]: FirebaseException catch used (not generic catch) at Firestore/Storage boundaries — catches only Firebase errors, lets programming errors propagate uncaught
- [Phase 11-gear-write-mutations]: showButtonMenu() used in widget tests for PopupMenuButton — direct tap unreliable due to FAB z-ordering in test viewport
- [Phase 11-gear-write-mutations]: togglePacked uses fire-and-forget .catchError() — no await needed; all other write mutations are async/await for consistent error handling
- [Phase 12-01]: trip_model.dart kept in split_scope_selector and edit_expense_sheet because Participant type is used in _ParticipantTile/_buildCustomParticipantSelector — cannot remove without breaking compile
- [Phase 12-01]: currentParticipantProvider removed from split_scope_selector entirely — replaced with direct currentUid since participant IDs are Firebase UIDs matching currentUser.uid

### Pending Todos

None yet.

### Blockers/Concerns

- Firebase Emulator configuration does not yet exist in the repo (firebase.json, emulator port config) — must be created in Phase 1 before any security rules are written
- GoRouter 13.x to 17.x migration risk is MEDIUM confidence — validate against breaking changes before Phase 2 adds new group/event routes
- Group invite code format (length, collision strategy) needs a product decision before Phase 2 implementation begins
- Dual-cache conflict resolution for offline-written expenses not yet confirmed — needs explicit handling in Phase 4

## Session Continuity

Last session: 2026-03-27T21:55:52.311Z
Stopped at: Completed 12-01-PLAN.md
Resume file: None
