# Phase 13: Final Cleanup - Research

**Researched:** 2026-03-28
**Domain:** Flutter/Dart dead code removal and documentation
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** Remove exactly 3 orphaned providers: `tripUnifiedLedgerProvider`, `tripSeedProvider`, `tripSubGroupsProvider`. No broader dead code sweep.
- **D-02:** Before each deletion, verify zero consumers by grepping both `lib/` and `test/` directories. Then run `flutter analyze` after all removals.
- **D-03:** Same-file collateral cleanup: if removing a provider leaves dead imports, orphaned comments, or unused helpers in the same file, clean those too. Do not venture into other files looking for extra cleanup.
- **D-04:** If removing a provider leaves its containing file empty (no remaining exports), delete the file entirely. Move any surviving providers to a more appropriate home first.
- **D-05:** Remove the stale comment at `auth_provider.dart:8` referencing deleted `firebase_auth_provider.dart`.
- **D-06:** Add a full mapping table of all remaining `trip*` legacy providers to CLAUDE.md, placed under the existing "Provider Naming" subsection in Conventions (below the "Legacy shims" bullet).
- **D-07:** Table columns: `trip* Provider`, `Delegates To` (event* equivalent), `Used By` (screens/files), `Status` (deprecated shim).
- **D-08:** Two commits: (1) Remove 3 providers + stale comment + same-file collateral. (2) Update CLAUDE.md with legacy provider mapping table.
- **D-09:** `flutter analyze` must report zero new warnings after all removals.
- **D-10:** `flutter test` must pass with zero failures after all removals.

### Claude's Discretion

- Order of provider removals within the first commit
- Exact wording of the CLAUDE.md table entries (provider descriptions, "Used By" detail level)
- Whether to relocate surviving providers from a deleted file or leave them if the file isn't fully empty
- Any formatting adjustments to CLAUDE.md for readability

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope
</user_constraints>

---

## Summary

Phase 13 is a pure tech debt closure phase with no new feature code. It closes 4 items from the v1.0 milestone audit: 3 orphaned Riverpod providers that survived earlier cleanup phases without consumers, 1 stale doc comment in auth_provider.dart referencing a deleted file, and undocumented legacy `trip*` shims in CLAUDE.md conventions.

All three orphaned providers exist only as definitions — confirmed by grep across `lib/` and `test/`. `tripUnifiedLedgerProvider` lives alone at the bottom of `ledger_provider.dart` (lines 44-77), `tripSeedProvider` is a no-op FutureProvider at the bottom of `trip_provider.dart` (lines 75-80), and `tripSubGroupsProvider` returns `Stream.value([])` in `sub_group_provider.dart` (lines 31-39). None have any `ref.watch` or `ref.read` consumers in active code. Same-file collateral in `trip_provider.dart` — `tripLoadingProvider`, `tripErrorProvider`, and `currentTripProvider` — also have zero consumers in `lib/` and are safe to remove under D-03.

The baseline is clean: `flutter analyze` shows 168 info-level issues (zero errors or warnings) and `flutter test` passes all 624 tests. The task is surgical deletion, one stale comment fix, and one documentation update.

**Primary recommendation:** Execute deletions in declaration order within each file, run `flutter analyze` after all removals in the same commit, then write the CLAUDE.md table as a second standalone commit.

---

## Standard Stack

### Core (No new dependencies)

This phase introduces no new packages. The existing toolchain handles all operations.

| Tool | Version | Purpose | Note |
|------|---------|---------|------|
| `flutter analyze` | SDK 3.x | Static analysis verification | Baseline: 168 info, 0 warnings, 0 errors |
| `flutter test` | SDK 3.x | Test suite verification | Baseline: 624 tests passing |

### Alternatives Considered

None applicable — this is a deletion and documentation phase.

---

## Architecture Patterns

### Provider File Structure After Removals

**`lib/features/ledger/providers/ledger_provider.dart`** — After removing `tripUnifiedLedgerProvider` (lines 44-77):
```
Retains:
  - eventUnifiedLedgerProvider (lines 1-42)
  - imports: flutter_riverpod, event_ref.dart, transaction_model.dart, expense_provider.dart
Note: expense_provider.dart import stays — eventUnifiedLedgerProvider uses
      eventExpensesProvider and eventSettlementsProvider from it.
```

**`lib/features/trip/providers/trip_provider.dart`** — After removing 4 providers:
```
Removes:
  - tripLoadingProvider (line 17) — zero consumers
  - tripErrorProvider (line 20) — zero consumers
  - currentTripProvider (line 23) — zero consumers
  - tripSeedProvider (lines 75-80) — zero consumers
Retains:
  - userGroupsForParticipantProvider (line 11)
  - tripLogisticsParticipantsProvider (line 28)
  - currentParticipantProvider (line 38)
  - All current imports (firebase_config, cache_service, event_provider, group_provider, trip_model)
Note: cache_service.dart import stays — tripLogisticsParticipantsProvider uses it.
      File is NOT empty after removals; do not delete.
```

**`lib/features/logistics/providers/sub_group_provider.dart`** — After removing `tripSubGroupsProvider` (lines 31-39):
```
Removes:
  - tripSubGroupsProvider definition and its @Deprecated doc comment
  - Also: update eventSubGroupsProvider doc comment to remove "Replaces [tripSubGroupsProvider]." line
Retains:
  - subGroupLoadingProvider, subGroupErrorProvider, subGroupServiceProvider
  - eventSubGroupsProvider, eventLogisticsParticipantsProvider
  - All imports (event_model.dart, trip_model.dart needed for List<Participant>)
```

**`lib/features/auth/providers/auth_provider.dart`** — Stale comment fix at line 8:
```
Current:
  /// Auth state provider — listens to Firebase auth changes.
  ///
  /// Re-exports from firebase_auth_provider.dart for backward compatibility.

Replace with:
  /// Auth state provider -- listens to Firebase auth changes.
```

### CLAUDE.md Mapping Table Placement

The table inserts immediately after the "Legacy shims" bullet at line 253, before the blank line at 254. The "Legacy shims" bullet itself must be updated to replace the inline provider list with a forward reference to the table.

```
Current bullet (line 253):
  - **Legacy shims**: `trip*` prefix providers (`tripExpensesProvider`, ...) are
    deprecated compatibility aliases. They delegate to the `event*` equivalents.
    Do NOT create new `trip*` providers. Do NOT remove existing shims while
    screens still reference them.

Updated bullet:
  - **Legacy shims**: `trip*` prefix providers are deprecated compatibility aliases.
    See the table below for the full mapping. Do NOT create new `trip*` providers.
    Do NOT remove existing shims while screens still reference them.
```

### Anti-Patterns to Avoid

- **Cascade deletion without grep verification first:** Each of the 3 target providers must be grepped in `lib/` and `test/` before touching code. The plan requires this as step 1.
- **Removing same-file imports prematurely:** Check that surviving providers in each file still need each import before removing it. `expense_provider.dart` stays in `ledger_provider.dart`; `cache_service.dart` stays in `trip_provider.dart`; `event_model.dart` and `trip_model.dart` stay in `sub_group_provider.dart`.
- **Treating `test/` comment references as consumers:** `test/features/home/home_screen_groups_test.dart:169` mentions `tripSeedProvider` in a comment inside a trivial `expect(true, isTrue)` test. This is not a consumer — the test does not call or override the provider. The comment can remain; it documents a historical check.
- **Adding new analyze warnings:** Removing providers that are `unused_element` would be caught by analyze as a fix, not a new warning. But orphaned imports after deletion would generate new warnings — verify each file's imports after edits.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Consumer verification | Custom script | `grep -r "providerName" lib/ test/ --include="*.dart"` | Ripgrep/grep is authoritative, zero false negatives |
| Analyze verification | Manual inspection | `flutter analyze --no-pub` | SDK analyzer catches issues grep cannot |
| Test verification | Manual run selection | `flutter test` (full suite) | 624 tests run in ~10 seconds; no reason to run subset |

---

## Consumer Verification Results (Authoritative)

Verified by grep across `lib/` and `test/` directories:

| Provider | Defined In | Consumers in lib/ | Consumers in test/ | Safe to Delete |
|----------|-----------|------------------|-------------------|----------------|
| `tripUnifiedLedgerProvider` | `ledger_provider.dart:46` | None | None | YES |
| `tripSeedProvider` | `trip_provider.dart:78` | None | Comment only (line 169) | YES |
| `tripSubGroupsProvider` | `sub_group_provider.dart:34` | None (doc comment only) | None | YES |
| `tripLoadingProvider` | `trip_provider.dart:17` | None | None | YES (collateral) |
| `tripErrorProvider` | `trip_provider.dart:20` | None | None | YES (collateral) |
| `currentTripProvider` | `trip_provider.dart:23` | None | None | YES (collateral) |

**Remaining trip* providers (DO NOT delete — documented only):**

| Provider | File | Active Consumers |
|----------|------|-----------------|
| `tripExpensesProvider` | `expense_provider.dart:177` | `ledger_provider.dart:tripUnifiedLedgerProvider` (being deleted) |
| `tripSettlementsProvider` | `expense_provider.dart:186` | `ledger_provider.dart:tripUnifiedLedgerProvider` (being deleted) |
| `tripGearProvider` | `gear_provider.dart:31` | `gear_provider.dart:gearByStatusProvider` (line 44, internal use) |
| `tripDocumentsProvider` | `document_provider.dart:35` | No active consumers |
| `tripMemoriesProvider` | `memory_provider.dart:26` | No active consumers |
| `tripActivityProvider` | `activity_service.dart:38` | No active consumers |
| `tripTransactionActivityProvider` | `activity_service.dart:46` | No active consumers |
| `tripLogisticsParticipantsProvider` | `trip_provider.dart:28` | No active consumers in lib/ |
| `tripCategoriesProvider` | `category_provider.dart:15` | `add_expense_screen.dart:285`, `edit_expense_sheet.dart:420` — ACTIVE |

**Key finding:** `tripCategoriesProvider` is an active provider with live screen consumers, not a deprecated shim. It returns hardcoded default categories (Phase 7 decision). It must be documented as "Active (not a shim)" in the table, not "Deprecated shim".

---

## Common Pitfalls

### Pitfall 1: Mistaking Comment References for Active Consumers
**What goes wrong:** The test file `home_screen_groups_test.dart:169` contains `// or tripSeedProvider` in a code comment, not in executable code. A naive grep count would flag it.
**Why it happens:** Grep finds all occurrences including comments and doc strings.
**How to avoid:** Read the matching line context before concluding a file is a consumer. The test comment is documentation of a historical check, not a `ref.watch/read` call.
**Warning signs:** Grep match is inside a `// comment` or a doc string `///`.

### Pitfall 2: Import Chain Invalidation After Provider Removal
**What goes wrong:** Removing `tripUnifiedLedgerProvider` from `ledger_provider.dart` might tempt removal of `expense_provider.dart` import. But `eventUnifiedLedgerProvider` uses `eventExpensesProvider` and `eventSettlementsProvider` from the same import.
**Why it happens:** The deleted provider and the surviving provider use the same import.
**How to avoid:** Re-read the file after removal to verify each import still has a reference.
**Warning signs:** `flutter analyze` reports `unused_import` after removal.

### Pitfall 3: Leaving Orphaned Doc Comment References
**What goes wrong:** `sub_group_provider.dart` line 23 says `Replaces [tripSubGroupsProvider].` in `eventSubGroupsProvider`'s doc comment. If `tripSubGroupsProvider` is deleted without updating this comment, the doc reference becomes a broken link.
**Why it happens:** Doc comments referencing deleted symbols are not caught by `flutter analyze` as errors.
**How to avoid:** Search for `[tripSubGroupsProvider]` in the file and remove the reference when deleting the provider.
**Warning signs:** Any doc comment cross-referencing the deleted symbol.

### Pitfall 4: Adding Info-Level Warnings While Fixing Others
**What goes wrong:** Editing a file touches lines that were not in the analysis baseline, triggering new `prefer_const_constructors` or similar info warnings.
**Why it happens:** Info-level warnings are numerous (168 baseline) and easy to accidentally introduce.
**How to avoid:** D-09 says "zero new warnings" — the baseline has zero errors and zero warnings (info does not count). Focus verify on error/warning counts, not info counts.
**Warning signs:** `flutter analyze` count increasing in error or warning tier.

---

## Code Examples

### Pattern: Provider Removal in Dart File

```dart
// Source: Current codebase ledger_provider.dart

// BEFORE (lines 44-77 to remove):
/// LEGACY: Unifies Expenses and Settlements into a single chronologically sorted stream.
/// Returns an AsyncValue containing the list of merged transactions.
final tripUnifiedLedgerProvider = Provider.family<AsyncValue<List<Transaction>>, String>((ref, tripId) {
  // ... body ...
});

// AFTER: File ends at line 42 with eventUnifiedLedgerProvider closing });
```

### Pattern: Stale Comment Replacement

```dart
// Source: auth_provider.dart

// BEFORE:
/// Auth state provider — listens to Firebase auth changes.
///
/// Re-exports from firebase_auth_provider.dart for backward compatibility.
final authStateProvider = StreamProvider<firebase_auth.User?>((ref) {

// AFTER:
/// Auth state provider -- listens to Firebase auth changes.
final authStateProvider = StreamProvider<firebase_auth.User?>((ref) {
```

### Pattern: CLAUDE.md Table Insertion

The table goes at CLAUDE.md line 254 (after the "Legacy shims" bullet, before the blank line before "### Service Naming"):

```markdown
| trip* Provider | Delegates To | Used By | Status |
|----------------|-------------|---------|--------|
| `tripExpensesProvider` | `eventExpensesProvider` (via SQLite `BalanceCacheRepository`) | `tripUnifiedLedgerProvider` (deleted) | Deprecated shim |
| `tripSettlementsProvider` | `eventSettlementsProvider` (via SQLite `BalanceCacheRepository`) | `tripUnifiedLedgerProvider` (deleted) | Deprecated shim |
| `tripGearProvider` | Returns `Stream.value([])` | `gearByStatusProvider` | Deprecated shim |
| `tripDocumentsProvider` | Returns `Stream.empty()` | None (no active consumers) | Deprecated shim |
| `tripMemoriesProvider` | Returns `[]` | None (no active consumers) | Deprecated shim |
| `tripActivityProvider` | Returns `Stream.value([])` | None (no active consumers) | Deprecated shim |
| `tripTransactionActivityProvider` | Returns `Stream.value([])` | None (no active consumers) | Deprecated shim |
| `tripLogisticsParticipantsProvider` | SQLite `CacheService.getCachedParticipants` | None (no active consumers) | Deprecated shim |
| `tripCategoriesProvider` | Hardcoded 6 default categories | `add_expense_screen.dart`, `edit_expense_sheet.dart` | Active (not a shim) |
```

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| `flutter analyze` | D-09 verification | Yes | SDK 3.x | — |
| `flutter test` | D-10 verification | Yes | SDK 3.x (624 tests passing) | — |
| `grep` / ripgrep | D-02 consumer verification | Yes | System grep | — |

Step 2.6: No external services, databases, or CLI tools beyond the Flutter SDK are required by this phase. All operations are file edits + local flutter commands.

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Flutter test (built-in) |
| Config file | None (default test/ directory discovery) |
| Quick run command | `flutter test test/unit/` |
| Full suite command | `flutter test` |

### Phase Requirements to Test Map

This phase has no functional requirements (tech debt only). The validation is structural:

| Check | Behavior | Type | Command | Automated |
|-------|----------|------|---------|-----------|
| No orphaned providers | 3 targets deleted from lib/ | Static grep | `grep -r "tripUnifiedLedgerProvider\|tripSeedProvider\|tripSubGroupsProvider" lib/ --include="*.dart"` | Yes |
| No stale comment | `firebase_auth_provider.dart` ref removed | Static grep | `grep -n "firebase_auth_provider" lib/features/auth/providers/auth_provider.dart` | Yes |
| Analyze clean | Zero new warnings | Tool run | `flutter analyze --no-pub` | Yes |
| Tests pass | All 624 tests green | Tool run | `flutter test` | Yes |
| CLAUDE.md table present | Table header found | Static grep | `grep -c "trip\* Provider" CLAUDE.md` | Yes |

### Sampling Rate

- **Per task commit:** `flutter analyze --no-pub && flutter test`
- **Per wave merge:** `flutter test` (full suite)
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps

None — existing test infrastructure covers all phase requirements. No new test files needed.

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `tripSeedProvider` seeding SQLite from Supabase | No-op (Firestore offline persistence replaces sync queue) | Phase 4 | Provider body is empty; safe to delete |
| `tripSubGroupsProvider` returning real Supabase data | Returns `Stream.value([])` | Phase 4 | Provider is vestigial; safe to delete |
| `tripUnifiedLedgerProvider` combining trip expenses | `eventUnifiedLedgerProvider` (EventRef-based) | Phase 4-05 | Screens migrated; original has no consumers |

**Phase 9 context:** Phase 9 deleted `firebase_auth_provider.dart` but left a reference to it in `auth_provider.dart`'s doc comment. This was not caught at the time. Phase 13 closes it.

---

## Open Questions

None. All target files verified by read, all consumers verified by grep. The implementation path is fully deterministic.

---

## Project Constraints (from CLAUDE.md)

| Directive | Applies To Phase 13 |
|-----------|---------------------|
| Immutability (CRITICAL) | Not applicable — no new code written |
| Many small files over few large files | Files remain feature-organized; no new files created |
| Error handling at every level | Not applicable — no new code |
| TDD mandatory | Not applicable — no new functionality; structural deletions verified by grep + analyze |
| 80%+ test coverage | Not applicable — deletions only; no new paths introduced |
| No hardcoded values | Not applicable |
| No mutation | Not applicable |
| Two commits: deletions then docs | D-08 locked |
| `flutter analyze` zero new warnings | D-09 locked |
| `flutter test` zero failures | D-10 locked |

---

## Sources

### Primary (HIGH confidence)

- Direct file reads: `ledger_provider.dart`, `trip_provider.dart`, `sub_group_provider.dart`, `auth_provider.dart` — content confirmed at line level
- Direct grep: `lib/` and `test/` directories — consumer count confirmed at zero for all 6 deletion targets
- `flutter analyze --no-pub` run: 168 info, 0 warnings, 0 errors — baseline confirmed
- `flutter test` run: 624 tests passing — baseline confirmed
- `CLAUDE.md` read at line 249-253 — table insertion point confirmed

### Secondary (MEDIUM confidence)

- `.planning/phases/13-final-cleanup/13-CONTEXT.md` — user decisions and file/line references used as starting points, all verified by direct file read
- `.planning/v1.0-MILESTONE-AUDIT.md` — tech debt items confirmed accurate

### Tertiary (LOW confidence)

None.

---

## Metadata

**Confidence breakdown:**
- Deletion targets and consumers: HIGH — verified by direct grep and file reads
- Same-file collateral: HIGH — verified by grep on `tripLoadingProvider`, `tripErrorProvider`, `currentTripProvider`
- CLAUDE.md insertion point: HIGH — verified by line read
- Post-deletion analyze safety: HIGH — all removed providers are pure Riverpod declarations; no side effects on compile graph
- Test safety: HIGH — 624 tests pass with current code; removing unused providers cannot break tests

**Research date:** 2026-03-28
**Valid until:** Immediately — this research is a snapshot of file state. Any intervening edits to the 5 target files would require re-verification.
