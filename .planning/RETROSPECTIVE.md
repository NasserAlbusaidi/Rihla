# Project Retrospective

*A living document updated after each milestone. Lessons feed forward into future planning.*

## Milestone: v1.0 — Groups, Events & Cross-Event Financials

**Shipped:** 2026-03-28
**Phases:** 13 | **Plans:** 43 | **Commits:** 411

### What Was Built
- Persistent groups with invite-code join flow and groups-first home screen
- Typed events (5 types) with template-driven modules and gear presets inside groups
- Cross-event financial tracking — group-level running balances, settle-up with optimization, spending stats
- Full Supabase → Firebase Firestore migration (9 services on FirestoreRepository base class)
- 624 tests with 80%+ CI-enforced coverage

### What Worked
- **Wave 0 test stubs** — writing test files with skip markers before implementation kept TDD honest and made coverage tracking clear
- **asyncMap side-write pattern** — Firestore snapshot → asyncMap → SQLite kept both data layers in sync without a separate sync process
- **Phase-level verification** — each phase had explicit success criteria checked before moving on; caught integration gaps early
- **Gap closure phases (8-13)** — the audit-then-fix cycle caught real bugs (payer-override, gear stubs, logistics no-ops) that would have shipped broken
- **Fire-and-forget activity logging** — `catchError/debugPrint` for non-critical writes kept the main path clean

### What Was Inefficient
- **Supabase bridge pattern** — the dual-backend bridge in Phase 3 was built then torn down in Phase 4-7. Could have gone Firebase-only from Phase 3 if the migration order had been different
- **Multiple cleanup phases** — Phases 9, 13 (dead code) were separate phases that could have been a single pass. The audit found new orphans each time because earlier phases created them
- **SUMMARY frontmatter gaps** — only 17/41 requirements had SUMMARY frontmatter entries. The tooling relied on it but the summaries didn't consistently fill the field
- **Stale ROADMAP status** — phases 2/5/6/7/8 showed "In Progress" long after completion. Status tracking drifted from reality

### Patterns Established
- **FirestoreRepository base class** — all Firestore access flows through `protected db getter` (MIG-05). New services extend this
- **EventRef typedef** — `({String groupId, String eventId})` is the canonical way to identify an event. All providers use it
- **Provider naming convention** — `event*` prefix for event-scoped, `group*` for group-scoped, `trip*` deprecated
- **MoneySerializer boundary** — integer fils in Firestore, Decimal in Dart, conversion only at the serialization boundary
- **BalanceCacheRepository** — narrow SQLite wrapper for balance queries, populated via asyncMap side-write from Firestore streams

### Key Lessons
1. **Audit early, not just at the end** — the first milestone audit found 6 integration gaps and 3 broken flows. Running it after Phase 7 instead of Phase 13 would have caught these sooner
2. **debugPrint stubs are bugs** — every `debugPrint("TODO")` in a callback became a real gap. Either wire it or throw `UnimplementedError`
3. **Bridge patterns have a shelf life** — the Supabase bridge was useful for incremental migration but created cleanup debt. Plan the teardown phase adjacent to the bridge phase
4. **Provider.family for variable-length aggregation** — `StreamProvider.family` can't watch a dynamic list of sub-providers; `Provider.family` with `ref.watch` inside loops is the pattern
5. **Test pump for cascaded streams** — `Future.delayed(Duration.zero)` x10 needed for 3-layer provider dependency cascades in widget tests; `pumpAndSettle` alone is insufficient

### Cost Observations
- Model mix: primarily Sonnet for execution, Opus for planning and audits
- Sessions: ~40+ sessions over 91 days
- Notable: wave-based parallelization in phases 4-5 was the most context-efficient pattern — independent plans executed by subagents in parallel

---

## Cross-Milestone Trends

### Process Evolution

| Milestone | Commits | Phases | Key Change |
|-----------|---------|--------|------------|
| v1.0 | 411 | 13 | GSD workflow with audit-fix cycle |

### Cumulative Quality

| Milestone | Tests | Coverage | LOC |
|-----------|-------|----------|-----|
| v1.0 | 624 | 80%+ | 24,895 |

### Top Lessons (Verified Across Milestones)

1. Audit-driven gap closure catches real bugs that code review misses
2. Wave 0 test stubs enforce TDD discipline at scale
3. Bridge patterns need adjacent teardown phases to avoid debt accumulation
