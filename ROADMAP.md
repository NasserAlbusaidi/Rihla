# Rihla Roadmap

Public roadmap for Rihla. Track progress on the [GitHub Project](https://github.com/nasseralbusaidi/Rihla/projects/3).

---

## Current: v1.5.1

**Status:** 6/12 issues open | [See milestone](https://github.com/nasseralbusaidi/Rihla/milestone/1)

Release hardening and external blockers before treating v1.5.0 as 1.0-ready. Critical path:

- **#469** (P1) — Account deletion deletes anon session, not durable account
- **#522** (P3) — Email recovery link never force-refreshes ID token
- **#519** (P2) — deleteGroup lock-reaper missing (write-lock stall)
- **#524** (P3) — Member doc keying inconsistency (uuid vs uid field)
- **#529** (P3) — deleteGroup concurrent caller can clear peer's lock

All blockers: [1.5.1 milestone](https://github.com/nasseralbusaidi/Rihla/milestone/1)

---

## Next: Post-launch hardening

**Status:** 6/42 issues open | [See milestone](https://github.com/nasseralbusaidi/Rihla/milestone/2)

Server trust-boundary hardening from the 2026-05-31 prelaunch audit. Deferred post-v1.3.0: #190 ships first (deleteGroup balance gate + cascade), the rest batched here.

**Theme:** Server rules layer is more permissive than the money invariants.

Key areas:
- **Schema debt** (#532 malformed doc handling)
- **Money trust** (#524 member duplication, #528 amountFils bounds)
- **Backend consistency** (#526 write-rate monitor, #525 soft-delete edge cases)
- **Localization** (#527 UTF-16 vs code-point lengths, #530 European number format)

All blockers: [Post-launch hardening milestone](https://github.com/nasseralbusaidi/Rihla/milestone/2)

---

## Later: Post-release features

**Status:** 21/23 issues | [See milestone](https://github.com/nasseralbusaidi/Rihla/milestone/3)

UI/UX improvements, design consolidation, performance optimization.

Highlights:
- **#486** — Stop restating balance 3 ways + remove double "New event"
- **#485** — Collapse 3-section split editor into one card
- **#489** — Fold event type-picker into create form (3 screens → 2)
- **#422** — Cursor-paginate expense ledger (evidence-gated)
- **#490** — Consolidate hand-rolled headers, avatars, rows onto shared primitives

All items: [Post-release features milestone](https://github.com/nasseralbusaidi/Rihla/milestone/3)

---

## Backlog

**Status:** 7/8 issues | [See milestone](https://github.com/nasseralbusaidi/Rihla/milestone/4)

Low-priority tech debt and enhancements. Triaged but not scheduled.

---

## How to read this

1. **Milestones** — group work into release phases
2. **GitHub Project** — shows live board (Backlog → Planned → In Progress → In Review → Done)
3. **Priority labels** — P0 (critical), P1 (high), P2 (medium), P3 (low)
4. **Cluster labels** — group related issues (`cluster:recovery-backend`, `cluster:money-trust`, etc.)

Filter by milestone or label on the [GitHub Project](https://github.com/nasseralbusaidi/Rihla/projects/3) for a focused view.

---

## Release schedule

- **v1.5.1** — current, ship pending RD-QA + external blockers
- **v1.5.2+** — Post-launch hardening batches (TBD)
- **v2.0** — Post-release features + design overhaul (TBD)

---

*Last updated: 2026-06-16*
