# Phase 13: Final Cleanup - Context

**Gathered:** 2026-03-28
**Status:** Ready for planning

<domain>
## Phase Boundary

Remove 3 orphaned providers (`tripUnifiedLedgerProvider`, `tripSeedProvider`, `tripSubGroupsProvider`), remove 1 stale comment in `auth_provider.dart`, and document all remaining `trip*` legacy providers in CLAUDE.md with a full mapping table. After this phase, `flutter analyze` and `flutter test` pass, and the codebase has no undocumented legacy shims.

</domain>

<decisions>
## Implementation Decisions

### Provider Deletion
- **D-01:** Remove exactly 3 orphaned providers: `tripUnifiedLedgerProvider`, `tripSeedProvider`, `tripSubGroupsProvider`. No broader dead code sweep.
- **D-02:** Before each deletion, verify zero consumers by grepping both `lib/` and `test/` directories. Then run `flutter analyze` after all removals.
- **D-03:** Same-file collateral cleanup: if removing a provider leaves dead imports, orphaned comments, or unused helpers in the same file, clean those too. Do not venture into other files looking for extra cleanup.
- **D-04:** If removing a provider leaves its containing file empty (no remaining exports), delete the file entirely. Move any surviving providers to a more appropriate home first.

### Stale Comment
- **D-05:** Remove the stale comment at `auth_provider.dart:8` referencing deleted `firebase_auth_provider.dart`.

### Documentation
- **D-06:** Add a full mapping table of all remaining `trip*` legacy providers to CLAUDE.md, placed under the existing "Provider Naming" subsection in Conventions (below the "Legacy shims" bullet).
- **D-07:** Table columns: `trip* Provider`, `Delegates To` (event* equivalent), `Used By` (screens/files), `Status` (deprecated shim).

### Commit Strategy
- **D-08:** Two commits: (1) Remove 3 providers + stale comment + same-file collateral. (2) Update CLAUDE.md with legacy provider mapping table.

### Verification
- **D-09:** `flutter analyze` must report zero new warnings after all removals.
- **D-10:** `flutter test` must pass with zero failures after all removals.

### Claude's Discretion
- Order of provider removals within the first commit
- Exact wording of the CLAUDE.md table entries (provider descriptions, "Used By" detail level)
- Whether to relocate surviving providers from a deleted file or leave them if the file isn't fully empty
- Any formatting adjustments to CLAUDE.md for readability

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Milestone Audit (Source of Truth)
- `.planning/v1.0-MILESTONE-AUDIT.md` — `tech_debt` section (phase 09, 10 items) lists the 3 orphaned providers and stale comment

### Target Files for Deletion
- `lib/features/ledger/providers/ledger_provider.dart` — Contains `tripUnifiedLedgerProvider` (line 46)
- `lib/features/trip/providers/trip_provider.dart` — Contains `tripSeedProvider` (line 78)
- `lib/features/logistics/providers/sub_group_provider.dart` — Contains `tripSubGroupsProvider` (line 34)

### Stale Comment Target
- `lib/features/auth/providers/auth_provider.dart` — Line 8, references deleted `firebase_auth_provider.dart`

### Documentation Target
- `CLAUDE.md` — "Conventions > Provider Naming" subsection, below "Legacy shims" bullet

### Prior Phase Context
- `.planning/phases/09-dead-code-cleanup/09-CONTEXT.md` — Phase 9 scope pattern (audit items only)
- `.planning/phases/10-full-codebase-review/10-CONTEXT.md` — Phase 10 naming conventions decisions
- `.planning/phases/12-expense-logistics-provider-rewiring/12-CONTEXT.md` — Phase 12 removed `userTripsProvider`

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- None needed — this phase is deletions + documentation only.

### Established Patterns
- Phase 9 used single atomic commit for all 3 provider deletions — this phase splits into 2 commits (deletions vs docs)
- CLAUDE.md already has "Provider Naming" section with event*/trip* convention and "Legacy shims" bullet — table goes directly below

### Integration Points
- `lib/features/ledger/providers/ledger_provider.dart` — `tripUnifiedLedgerProvider` may be imported by ledger screens (verify before deletion)
- `lib/features/trip/providers/trip_provider.dart` — `tripSeedProvider` used by `CommandCenter` seed flow (verify if still active)
- `lib/features/logistics/providers/sub_group_provider.dart` — `tripSubGroupsProvider` already has docstring saying "use eventSubGroupsProvider instead"

### Remaining trip* Providers (for documentation)
- `tripExpensesProvider` — `lib/features/ledger/providers/expense_provider.dart:177`
- `tripSettlementsProvider` — `lib/features/ledger/providers/expense_provider.dart:186`
- `tripGearProvider` — `lib/features/gear/providers/gear_provider.dart:31`
- `tripDocumentsProvider` — `lib/features/vault/providers/document_provider.dart:35`
- `tripMemoriesProvider` — `lib/features/memories/providers/memory_provider.dart:26`
- `tripActivityProvider` — `lib/features/activity/services/activity_service.dart:38`
- `tripTransactionActivityProvider` — `lib/features/activity/services/activity_service.dart:46`
- `tripLogisticsParticipantsProvider` — `lib/features/trip/providers/trip_provider.dart:28`
- `tripCategoriesProvider` — `lib/features/ledger/providers/category_provider.dart:15`
- `tripLoadingProvider` — `lib/features/trip/providers/trip_provider.dart:17`
- `tripErrorProvider` — `lib/features/trip/providers/trip_provider.dart:20`

</code_context>

<specifics>
## Specific Ideas

- Mapping table format explicitly chosen by user (preview confirmed): columns are `trip* Provider | Delegates To | Used By | Status`
- Table placement: under existing "Provider Naming" subsection, below "Legacy shims" bullet — not a new section

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 13-final-cleanup*
*Context gathered: 2026-03-28*
