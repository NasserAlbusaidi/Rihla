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

## Milestone: v2.0 — Major UI/UX Overhaul

**Shipped:** 2026-03-31
**Phases:** 9 | **Plans:** 28 | **Commits:** 190

### What Was Built
- ThemeExtension-based design token system with warm earthy palette (terracotta, sand, olive), WCAG AA verified, CI-enforced
- Single-scroll home dashboard with cross-group balance hero, quick-action tray, inline group cards, weekly spending chart
- Full GoRouter navigation restructuring — 22 Navigator.push calls replaced, all screens URL-addressable
- Complete screen redesign across all 6 module screens, forms, onboarding, and splash with card-based layouts
- M3 motion patterns (ContainerTransform, SharedAxis, FadeThrough), haptic feedback, grain textures, animated balance counters
- AppColors class deleted after migrating 1,375 references to the new token system

### What Worked
- **Token system before screens** — Phases 14-15 as non-negotiable prerequisites meant zero palette rework across Phases 18-22. Every screen phase pulled from one source of truth
- **Stitch-first design** — visual specs from Phase 16 gave each subsequent phase a target instead of designing-while-coding. Reduced back-and-forth
- **Semantic Key infrastructure** — Phase 14's find.byKey() migration meant 143 tests survived 9 phases of visual restructuring with zero false failures
- **Two-layer AppColors facade** — preserving the 895 call sites through Phase 15 then bulk-deleting in Phase 22 was the right sequencing. No intermediate breakage
- **OpenContainer URL desync acceptance** — deciding early (Phase 20 D-06) that ContainerTransform animation quality > URL correctness saved repeated debate in Phases 22-23
- **Wave-based parallel execution** — independent plans within phases (e.g., 21-01 through 21-06) ran in parallel subagents efficiently

### What Was Inefficient
- **SUMMARY one-liner extraction** — many SUMMARY.md files had malformed or missing one-liner fields, causing noisy auto-extraction at milestone completion. Summaries need stricter frontmatter enforcement
- **Hardcoded Color regression** — Phase 15 added CI lint, but Phases 21-22 introduced 16 new inline Color(0xFF...) violations in gradient decorations. The lint didn't catch these because they were in allowlisted patterns (gradient stops). Need tighter lint scope
- **Dead code accumulation** — StaggeredGrid (Phase 17), domain aliases (Phase 15), LogisticsHeroCard (Phase 21) were built but never adopted. Phase-level verification checked that deliverables existed but not that they were consumed downstream
- **Nyquist validation gaps** — only 3/9 phases fully compliant. Validation was treated as optional rather than mandatory
- **PLSH-02 checkbox drift** — REQUIREMENTS.md showed PLSH-02 unchecked despite implementation being verified. Manual checkbox updates drift from reality

### Patterns Established
- **AppColorTokens.light.* direct access** — all token references use the static instance directly, not Theme.of(context).extension. Simpler, grep-friendly, test-friendly
- **OpenContainer for navigation transitions** — M3 ContainerTransform replaces TapBounce+context.push at the widget level; URL desync is an accepted trade-off
- **Stack+AnimatedOpacity for tab switching** — replaces IndexedStack in BottomNavShell for true FadeThrough animation (renders all tabs simultaneously)
- **SharedAxisTransition for form steps** — PageTransitionSwitcher with vertical shared axis and directional _goingBack flag
- **HapticService for write actions** — centralized haptic feedback service called at point-of-success in expense/settlement/join-group flows
- **GrainOverlay widget** — reusable grain texture overlay via Stack wrapping, applied to hero cards and headers

### Key Lessons
1. **CI lint must be comprehensive** — the Phase 15 Color(0xFF...) lint caught direct widget colors but missed gradient stops. Lint rules need to cover all Color instantiation patterns, not just the obvious ones
2. **Build-then-verify is incomplete** — verifying "does it exist?" without verifying "is it used?" leads to dead code. Phase verification should check both creation and consumption
3. **Facade-then-delete is the right migration pattern** — for 1,000+ reference migrations, keeping the old API through the intermediate phases and deleting in a final pass avoids mid-milestone breakage
4. **4 days for 9 visual phases is possible** — with a token system, Stitch specs, and semantic tests as prerequisites, screen redesign is mostly mechanical. The 4-phase foundation (14-17) enabled the 5-phase execution (18-22) to move at speed
5. **Palette decisions compound** — the Phase 16 monochrome+teal pivot from the original terracotta/sand/olive rippled through every subsequent phase. Making this decision early (before any screen work) was critical

### Cost Observations
- Model mix: primarily Sonnet for execution, Opus for planning/audits/milestone-completion
- Sessions: ~15 sessions over 4 days
- Notable: the entire v2.0 milestone (9 phases, 28 plans, 190 commits) completed in 4 days — 10x faster than v1.0 (91 days). Foundation work (token system, test hardening, Stitch specs) was the multiplier

---

## Milestone: v2.1 — Home Screen Completion

**Shipped:** 2026-04-01
**Phases:** 2 | **Plans:** 3 | **Commits:** 30

### What Was Built
- Quick action fixes: Invite Friend → share sheet with invite code, Activity → CrossGroupActivityScreen, 0-groups edge case feedback
- GroupCard accent strip (hash-based earthy color per group) and event context line (last event name + relative timestamp)
- Weekly spending chart with "Weekly Spending (OMR)" title and per-bar amount labels
- Dashboard spacing tightened to 12dp, "Your Groups (N)" section header above group list

### What Worked
- **Tight scope** — 9 requirements across 2 phases, all clearly defined from the v2.0 audit. No scope creep
- **Same-day turnaround** — both phases planned, executed, and verified in a single day. Foundation work from v2.0 (token system, semantic tests) made this possible
- **Audit-first completion** — running `/gsd:audit-milestone` before completion caught the Nyquist gap on Phase 23 and documented tech debt items cleanly
- **TDD discipline held** — even for small visual changes (accent strip, chart labels), RED→GREEN→REFACTOR was followed with proper test commits

### What Was Inefficient
- **SUMMARY one-liner extraction still noisy** — Plan 24-01's one-liner was a bug description rather than an accomplishment. The extraction heuristic needs improvement
- **Phase 23 Nyquist validation missing** — skipped during execution, caught at audit. Should have been part of phase completion
- **Minimal scope overhead** — 2-phase milestone may not justify full milestone ceremony (archive, tag, retrospective). Consider a lighter "patch" workflow for sub-milestones

### Patterns Established
- **Hash-based accent colors** — `groupId.hashCode.abs() % N` for deterministic visual identity without user configuration
- **IntrinsicHeight + CrossAxisAlignment.stretch** — pattern for full-height decorative elements in variable-height cards

### Key Lessons
1. **Small milestones ship fast but have proportionally high ceremony cost** — 2 phases took ~4 hours of work but milestone completion takes almost as long as the work itself. For patch-level milestones, consider a lighter archival workflow
2. **Audit before complete is non-negotiable** — the audit caught 4 tech debt items and the Nyquist gap that would have been invisible otherwise
3. **v2.0 foundation compounds** — token system, semantic tests, and Stitch workflow meant v2.1 visual changes were entirely mechanical. The investment keeps paying off

### Cost Observations
- Model mix: Sonnet for execution, Opus for audit and milestone completion
- Sessions: 2 sessions over 1 day
- Notable: the entire milestone (2 phases, 3 plans, 30 commits) completed in a single day — foundation compound effect from v2.0

---

## Cross-Milestone Trends

### Process Evolution

| Milestone | Commits | Phases | Timeline | Key Change |
|-----------|---------|--------|----------|------------|
| v1.0 | 411 | 13 | 91 days | GSD workflow with audit-fix cycle |
| v2.0 | 190 | 9 | 4 days | Foundation-first visual overhaul with wave parallelism |
| v2.1 | 30 | 2 | 1 day | Focused fix+polish on existing foundation |

### Cumulative Quality

| Milestone | Tests | Coverage | LOC | Files Changed |
|-----------|-------|----------|-----|---------------|
| v1.0 | 624 | 80%+ | 24,895 | — |
| v2.0 | 767 | 80%+ | 29,489 | 254 |
| v2.1 | 789 | 80%+ | ~30,000 | 10 |

### Top Lessons (Verified Across Milestones)

1. Audit-driven gap closure catches real bugs that code review misses (v1.0, v2.0, v2.1)
2. Wave 0 test stubs enforce TDD discipline at scale (v1.0)
3. Facade-then-delete is the safest pattern for 1,000+ reference migrations (v1.0 Supabase, v2.0 AppColors)
4. Foundation phases (infrastructure before features) enable exponential execution speed in later phases (v2.0: 4 days, v2.1: 1 day — compound effect)
5. CI lint rules must cover all instantiation patterns, not just the obvious ones (v2.0 gradient Color regression)
6. Small milestones ship fast but have proportionally high ceremony cost — consider lighter workflows for patch-level work (v2.1)
