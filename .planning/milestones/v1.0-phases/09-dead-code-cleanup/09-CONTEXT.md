# Phase 9: Dead Code Cleanup - Context

**Gathered:** 2026-03-27
**Status:** Ready for planning

<domain>
## Phase Boundary

Remove the 3 orphaned providers identified in the v1.0 milestone audit. No broader dead code sweep — Phase 10 (Full Codebase Review) handles that. After this phase, `flutter analyze` and `flutter test` pass with zero references to these dead providers.

</domain>

<decisions>
## Implementation Decisions

### Deletion Scope
- **D-01:** Scope limited to the 3 audit items only. No broader codebase sweep.
- **D-02:** `tripBalancesProvider` removed from `lib/features/ledger/providers/expense_provider.dart` (line ~204). Zero consumers confirmed.
- **D-03:** `firebaseAuthStateProvider` and `firebaseCurrentUserProvider` removed from `lib/features/auth/providers/firebase_auth_provider.dart` (lines ~10, ~18). `auth_provider.dart` is the canonical consumer — these Phase 1 exports are orphaned.
- **D-04:** `subGroupsByTypeProvider` removed from `lib/features/logistics/providers/sub_group_provider.dart` (line ~42). References `tripSubGroupsProvider` which always returns empty.

### Import Cleanup
- **D-05:** After removing each provider, also remove any imports that become unused in the same file. Keep files tidy.

### Commit Strategy
- **D-06:** All 3 removals in a single atomic commit. Small scope, all related, easier to review.

### Verification
- **D-07:** `flutter analyze` must report zero warnings after removals.
- **D-08:** `flutter test` must pass with zero failures after removals.

### Claude's Discretion
- Order of removals within the single commit
- Whether to remove associated comments/documentation alongside the providers
- Whether to remove helper functions only used by the deleted providers (if any exist)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Milestone Audit (Source of Truth)
- `.planning/v1.0-MILESTONE-AUDIT.md` — `tech_debt` section lists all 3 providers with file locations and rationale for removal

### Target Files
- `lib/features/ledger/providers/expense_provider.dart` — Contains `tripBalancesProvider` (dead since Phase 4)
- `lib/features/auth/providers/firebase_auth_provider.dart` — Contains `firebaseAuthStateProvider` + `firebaseCurrentUserProvider` (orphaned since Phase 7)
- `lib/features/logistics/providers/sub_group_provider.dart` — Contains `subGroupsByTypeProvider` (orphaned — references always-empty provider)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- None needed — this is pure deletion, no new code.

### Established Patterns
- Provider files contain multiple providers per file. Removing one provider from a file requires care to not break adjacent providers.
- Imports may become unused after provider removal (e.g., Riverpod types, model imports only used by the deleted provider).

### Integration Points
- `expense_provider.dart` still has active providers (`tripExpensesProvider`, `tripSettlementsProvider` shims, and Firestore-based providers). Only `tripBalancesProvider` is dead.
- `firebase_auth_provider.dart` may have no remaining active exports after removal — `auth_provider.dart` is the canonical auth provider file.
- `sub_group_provider.dart` still has active providers (`tripSubGroupsProvider`, `eventLogisticsParticipantsProvider`). Only `subGroupsByTypeProvider` is dead.

</code_context>

<specifics>
## Specific Ideas

No specific requirements — open to standard approaches. The audit defines exactly what to remove.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 09-dead-code-cleanup*
*Context gathered: 2026-03-27*
