# Phase 13: Final Cleanup - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-03-28
**Phase:** 13-final-cleanup
**Areas discussed:** Documentation depth, Collateral cleanup, Consumer verification, Commit strategy, Empty file handling, CLAUDE.md table placement

---

## Documentation Depth

| Option | Description | Selected |
|--------|-------------|----------|
| Full mapping table | Table showing each remaining trip* provider, its event* equivalent, which screens still use it, and deprecation status | ✓ |
| Simple list | Just list the remaining trip* providers with a one-liner each | |
| Names only | Add provider names to existing conventions section with no extra detail | |

**User's choice:** Full mapping table
**Notes:** User confirmed the preview format with columns: trip* Provider, Delegates To, Used By, Status

---

## Collateral Cleanup

| Option | Description | Selected |
|--------|-------------|----------|
| Clean same-file only | If removing a provider leaves dead imports or orphaned comments in the same file, clean those too. Don't venture into other files | ✓ |
| Strict 4 items only | Touch exactly the 3 providers + 1 stale comment. Leave collateral mess | |
| Opportunistic sweep | Fix any dead code or stale comments found while working | |

**User's choice:** Clean same-file only
**Notes:** None

---

## Consumer Verification

| Option | Description | Selected |
|--------|-------------|----------|
| Grep + tests + analyze | Search all of lib/ AND test/ for references, then run flutter analyze after removal | ✓ |
| Grep lib/ only | Search lib/ for direct references only | |
| Just delete and see | Remove and let flutter analyze + flutter test catch breakage | |

**User's choice:** Grep + tests + analyze
**Notes:** None

---

## Commit Strategy

| Option | Description | Selected |
|--------|-------------|----------|
| Two commits | First: remove providers + stale comment + collateral. Second: update CLAUDE.md docs | ✓ |
| One atomic commit | All changes in a single commit | |
| Three commits | One per provider removal, then one for docs | |

**User's choice:** Two commits
**Notes:** Separates destructive changes from documentation

---

## Empty File Handling

| Option | Description | Selected |
|--------|-------------|----------|
| Delete if empty | If file has no remaining exports after removal, delete it. Move surviving providers first | ✓ |
| Keep as shell | Leave file even if mostly empty | |

**User's choice:** Delete if empty
**Notes:** None

---

## CLAUDE.md Table Placement

| Option | Description | Selected |
|--------|-------------|----------|
| Under Provider Naming | Add table below existing "Legacy shims" bullet in Provider Naming subsection | ✓ |
| New dedicated section | Create new "Legacy Provider Shims" section in Conventions | |

**User's choice:** Under Provider Naming
**Notes:** Keeps all provider guidance together in one place

---

## Claude's Discretion

- Order of provider removals within the first commit
- Exact wording of CLAUDE.md table entries
- Whether to relocate surviving providers from a deleted file
- Formatting adjustments to CLAUDE.md for readability

## Deferred Ideas

None — discussion stayed within phase scope
