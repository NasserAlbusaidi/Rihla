# Phase 10: Full Codebase Review - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-03-27
**Phase:** 10-full-codebase-review
**Areas discussed:** Audit depth vs fix scope, Large file strategy, Lint level threshold, Naming consistency target

---

## Audit Depth vs Fix Scope

| Option | Description | Selected |
|--------|-------------|----------|
| Audit and fix in one phase | Single phase does the review and applies all fixes. More plans, but no separate follow-up phase needed. Keeps milestone v1.0 closure tight. | ✓ |
| Audit only, fix in Phase 11 | Phase 10 produces a report. A new Phase 11 executes fixes. Cleaner separation but delays milestone close. | |
| Fix easy, report hard | Fix straightforward issues in this phase. Report complex issues for a follow-up. | |

**User's choice:** Audit and fix in one phase
**Notes:** None — clean selection.

---

## Error Handling Scope (follow-up to Audit Depth)

| Option | Description | Selected |
|--------|-------------|----------|
| Verify existing, add missing | Audit all Firestore/auth/storage calls. Where try/catch exists, verify it handles errors well. Where it's missing, add it. Don't wrap internal code that can't fail. | ✓ |
| Add try/catch everywhere | Wrap every Firestore, auth, and storage call in try/catch with user-friendly error messages. Maximum safety but adds boilerplate. | |
| Review only, fix critical gaps | Only add error handling where a crash is likely. Leave read-path errors to Riverpod's AsyncValue.error. | |

**User's choice:** Verify existing, add missing
**Notes:** None.

---

## Large File Strategy

| Option | Description | Selected |
|--------|-------------|----------|
| Split all 5 to under 800 | Extract widget methods into separate files, move dialogs/sheets into their own widgets. Aligns with success criteria. Biggest effort but cleanest result. | ✓ |
| Split the 3 over 1000 only | Focus on the worst offenders. Leave 800-900 range files alone. | |
| Extract shared patterns only | Don't split by line count — extract duplicated widget patterns. May or may not hit the 800 target. | |

**User's choice:** Split all 5 to under 800
**Notes:** None.

---

## Lint Level Threshold

| Option | Description | Selected |
|--------|-------------|----------|
| Zero warnings, ignore infos | Fix all 26 warnings (unused imports, unnecessary casts, null comparisons). Leave 172 infos alone — mostly test file style. | ✓ |
| Zero warnings + lib/ infos | Fix warnings plus info-level issues in lib/ only. | |
| Zero everything | Fix all 198 issues including test file cosmetics. | |

**User's choice:** Zero warnings, ignore infos
**Notes:** None.

---

## Naming Consistency Target

| Option | Description | Selected |
|--------|-------------|----------|
| Document conventions, fix violations | Establish the naming standard (event* for new, trip* only for legacy shims), audit for violations, and fix them. Adds a conventions section to CLAUDE.md. | ✓ |
| Rename all trip* to event* | Full rename of legacy shims. Higher risk — touches many files and tests. | |
| Document only, don't rename | Write down conventions. Don't change any names. | |

**User's choice:** Document conventions, fix violations
**Notes:** None.

---

## Claude's Discretion

- Security review depth (Claude determines based on what codebase exposes)
- Performance review approach (code pattern review, not benchmarking)
- Hardcoded values extraction threshold (Claude judges inline vs constant)

## Deferred Ideas

None — discussion stayed within phase scope.
