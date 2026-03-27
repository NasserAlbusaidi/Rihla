# Phase 9: Dead Code Cleanup - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-03-27
**Phase:** 09-dead-code-cleanup
**Areas discussed:** Scope, Imports, Commits

---

## Scope

| Option | Description | Selected |
|--------|-------------|----------|
| Audit items only (Recommended) | Remove the 3 orphaned providers listed in the milestone audit. Fast, surgical, low risk. Phase 10 catches anything else. | ✓ |
| Audit items + quick scan | Remove the 3 providers, then run a quick grep for other unused providers/imports across lib/. | |
| Broad dead code sweep | Full dead code analysis across the codebase — unused providers, orphaned imports, unreferenced models. | |

**User's choice:** Audit items only
**Notes:** Clean separation with Phase 10 which handles broader codebase review.

---

## Imports

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, clean imports (Recommended) | After removing each provider, also remove any imports that become unused. | ✓ |
| You decide | Claude handles import cleanup at discretion. | |

**User's choice:** Yes, clean imports
**Notes:** None

---

## Commits

| Option | Description | Selected |
|--------|-------------|----------|
| One atomic commit (Recommended) | All 3 removals in a single commit. Small scope, all related. | ✓ |
| One commit per file | 3 separate commits — each provider removal isolated. | |

**User's choice:** One atomic commit
**Notes:** None

---

## Claude's Discretion

- Order of removals within the single commit
- Whether to remove associated comments/documentation alongside the providers
- Whether to remove helper functions only used by the deleted providers

## Deferred Ideas

None — discussion stayed within phase scope.
