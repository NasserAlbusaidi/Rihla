# Phase 36: Architecture Refactor — Context

**Gathered:** 2026-04-16
**Status:** Ready for planning
**Source:** Derived from `.planning/review/06-architecture-debt.md` + `.planning/review/07-code-quality.md` + `.planning/review/README.md` scoreboard

<domain>
## Phase Boundary

This phase pays down three interrelated architectural debts flagged in the post-v2.3 project review:

1. **God screens (#15)** — Five screen files exceed 600 lines, conflating layout, state orchestration, and business logic in single widgets. Split them into focused child widgets and, where appropriate, extract stateful controllers into providers.
2. **Provider watch explosion (#16)** — The home dashboard creates O(G × E) Firestore listeners by watching every event in every group. `weeklyGroupSpendingProvider` downloads the entire expense history to filter for the current week client-side. Replace with bounded per-group aggregates or date-scoped queries.
3. **CacheService god class (#18)** — A 660-line all-static service handles every cache domain (trips, expenses, settlements, gear, participants, sub-groups, activity logs, categories). Overlap with `balance_cache_repository.dart` means two writers with divergent conflict strategies for overlapping data.

The phase ships **no user-facing feature changes**. Success is measured by line-count ceilings, listener counts, clean test runs, and no regressions in existing flows.

### In scope
- `group_settle_up_screen.dart` (990 LOC) — decompose
- `edit_expense_screen.dart` (799 LOC) — decompose
- `gear_screen.dart` (731 LOC) — decompose
- `logistics_screen.dart` (690 LOC) — decompose
- `create_event_screen.dart` (690 LOC) — decompose (already defensible; lighter touch)
- `home_screen.dart` provider fan-out
- `weeklyGroupSpendingProvider` query strategy
- `cache_service.dart` decomposition
- `balance_cache_repository.dart` overlap reconciliation

### Out of scope
- UI redesign or visual changes (Phase 37 handles theming)
- New features of any kind
- Firestore schema migration
- Security/auth changes (Phase 38 handles storage rules)
- Test coverage for services without tests today (#33, deferred)

</domain>

<decisions>
## Implementation Decisions

### Screen decomposition strategy (ARCH-01)
- **Target:** No screen file > 600 LOC after this phase. Stretch target: ≤ 400 LOC.
- **Method:** Extract sub-widgets into sibling files under the same feature's `widgets/` directory. Extract step/section widgets for multi-step flows (e.g., `AddExpenseScreen` already uses this pattern — apply consistently).
- **State handling:** Pure-presentational sub-widgets become `StatelessWidget`/`ConsumerWidget`. Stateful orchestration that belongs in state management moves into new `StateNotifier`s or derived providers, not a second stateful widget.
- **Tests:** Each extracted widget gets at least one golden or widget test exercising its primary path. Screen-level tests continue to cover integration; do not duplicate coverage.

### Provider fan-out (ARCH-02, ARCH-03)
- **Home dashboard:** Replace O(G×E) subscriptions with one per-group aggregate stream (or a single `groupDashboardSummaryProvider` family indexed by groupId). The per-event stream stays — but only inside the group detail screen, not on home.
- **Weekly spending:** Use Firestore `where('occurredAt', >= startOfWeek)` plus a secondary `<= endOfWeek` bound, or a `weekKey` denormalized field, rather than downloading all expenses and filtering in Dart.
- **If a denormalized aggregate is needed (writes on expense create/update/delete):** prefer a Cloud Function / Firestore trigger to keep `weeklyTotals` accurate. If that is out of reach for this phase, document the decision and use a client-side write on the same transaction that writes the expense.
- **Reactivity:** Dashboard must remain live — use `Stream` providers, not `Future` snapshots.

### CacheService decomposition (ARCH-04)
- **Split into domain repositories:** `ExpenseCacheRepository`, `GearCacheRepository`, `ParticipantCacheRepository`, `ActivityLogCacheRepository`, etc. Each owns its table(s) in `safar_cache.db` and has an explicit conflict strategy (replace vs. merge) documented at the top of the file.
- **Reconcile with `balance_cache_repository.dart`:** Either fold balance caching into the new structure (preferred) or keep `balance_cache_repository.dart` as the sole writer and have the new expense repository defer balance refresh to it. No silent double-writers.
- **Instances, not static:** Convert from all-static to injected instances registered via Riverpod providers. Preserves testability and lets tests swap in fake SQLite databases without reaching into static state.
- **Back-compat:** Remove `CacheService` only after all call sites migrate. Acceptable to land in two steps within this phase: (a) introduce new repos alongside; (b) migrate call sites and delete `CacheService`. Both steps committed atomically; no orphan code left on main between plans.

### Migration safety
- **TDD required.** Each decomposition step starts with a failing widget or unit test for the new surface, then implementation.
- **No behavior change.** Snapshot tests or golden tests confirm visual output unchanged where relevant. Balance calculations, settlement suggestions, and ledger totals must match pre-refactor values.
- **Commit atomicity:** Each `<plan>.md` lands in a single atomic commit; splitting a screen into three widgets does NOT land across three commits unless each commit individually passes `flutter analyze` + `flutter test`.
- **Provider-watch regression fence:** A test asserts that `home_screen.dart` does not instantiate more than N providers for a group with K events (where N is the new bounded number, not K-dependent).

### Claude's Discretion
- Exact widget extraction granularity per screen (how many sub-widgets per split)
- Whether to use `StatefulShellRoute` side-effects or leave routing untouched
- Naming of new repository classes
- Whether weekly spending uses a date-range query, a `weekKey` denormalization, or a Cloud Function trigger (pick based on research findings + Firestore cost/latency trade-offs)
- Folder placement of extracted widgets (sibling `widgets/` vs. screen-adjacent `sections/`)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Review source-of-truth
- `.planning/review/06-architecture-debt.md` — Issues #15, #16, #17, #18 with exact file + line info
- `.planning/review/07-code-quality.md` — Issues #31, #33 context (spacing tokens, test gaps)
- `.planning/review/README.md` — Scoreboard status (30 fixed / 4 open / 5 partial as of 2026-04-16)

### Roadmap + requirements
- `.planning/ROADMAP.md` — Phase 36 entry under v2.4
- `.planning/milestones/v2.4-REQUIREMENTS.md` — ARCH-01..04 locked requirements
- `.planning/milestones/v2.4-ROADMAP.md` — Phase goal + success criteria

### Project context
- `CLAUDE.md` — Architecture section (feature-first structure, Riverpod 2.x, GoRouter, offline-first sync pipeline, design tokens)
- `.planning/PROJECT.md` — Current project framing

### Target source files
- `lib/features/groups/screens/group_settle_up_screen.dart` (990 LOC)
- `lib/features/ledger/screens/edit_expense_screen.dart` (799 LOC)
- `lib/features/gear/screens/gear_screen.dart` (731 LOC)
- `lib/features/logistics/screens/logistics_screen.dart` (690 LOC)
- `lib/features/events/screens/create_event_screen.dart` (690 LOC)
- `lib/features/home/screens/home_screen.dart` (provider fan-out)
- `lib/core/services/cache_service.dart` (660 LOC)
- `lib/core/services/balance_cache_repository.dart` (overlap with CacheService)

### Sibling patterns to emulate
- `lib/features/ledger/screens/add_expense_screen.dart` — already uses step-widget extraction (CategorySelectionStep, SplitScopeSelector)
- `lib/features/home/providers/` — existing provider structure to preserve while rewiring
- `lib/core/db/local_database.dart` — SQLite migrations and table definitions

</canonical_refs>

<specifics>
## Specific Ideas

- Measure god screens before and after with `wc -l` and include the delta in each plan's verification.
- For `group_settle_up_screen.dart` (990 LOC): four tabs (You Owe / Owed to You / Between Others / History) make natural extraction boundaries. Each tab becomes its own widget.
- For `edit_expense_screen.dart` (799 LOC): mirror the step-widget pattern from `add_expense_screen.dart`.
- For `gear_screen.dart` and `logistics_screen.dart`: the list + detail structure suggests extracting an item-tile widget + an empty-state widget + a section-header widget.
- Home dashboard fan-out fix likely reuses the `group_balance_provider.dart` pattern (per-group subscription) that currently exists but is not adopted by the dashboard.

</specifics>

<deferred>
## Deferred Ideas

- Dark theme widget migration (Phase 37 — this phase touches many of the same widgets, but theming is a separate concern that should not be conflated with structural refactor)
- textMuted contrast fixes (Phase 37)
- Spacing token adoption (Phase 37)
- Storage Cloud Functions (Phase 38)
- Test coverage expansion for services without tests (#33 — tracked as TEST-01..04 future requirements)
- `copyWith` sentinel pattern (#22 — no active callers, deferred until one exists)

</deferred>

---

*Phase: 36-architecture-refactor*
*Context gathered: 2026-04-16 from review findings*
