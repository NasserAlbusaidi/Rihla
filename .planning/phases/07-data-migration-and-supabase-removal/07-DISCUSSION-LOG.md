# Phase 7: Data Migration and Supabase Removal - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-03-27
**Phase:** 07-data-migration-and-supabase-removal
**Areas discussed:** Data recovery flow

---

## Data Recovery Flow

### Discovery Method

| Option | Description | Selected |
|--------|-------------|----------|
| Invite code entry | Add 'Recover old trip' option. User enters invite code, app pulls Supabase data into Firestore event. | |
| Auto-detect on launch | Check for Supabase anonymous session on first launch after update, prompt to migrate. | |
| Skip recovery entirely | Old trip data abandoned. Phase 7 just removes Supabase code. Users start fresh. | ✓ |

**User's choice:** Skip recovery entirely
**Notes:** Simplifies Phase 7 to pure cleanup — no migration UI, no Supabase data pull needed.

### MIG-06 Disposition

| Option | Description | Selected |
|--------|-------------|----------|
| Descope MIG-06 | Mark as intentionally dropped. Phase 7 only delivers MIG-07. | ✓ |
| Reword to 'optional' | Keep as nice-to-have / v2 enhancement. | |

**User's choice:** Descope MIG-06
**Notes:** Old trip data is abandoned. No recovery flow will be built.

---

## Claude's Discretion

- Deletion scope (which files/directories to remove)
- Boot sequence changes (main.dart Supabase init removal)
- Migration testing approach (post-removal verification)
- ConnectivityNotifier refactoring
- Order and granularity of cleanup commits

## Deferred Ideas

None — discussion stayed within phase scope.
