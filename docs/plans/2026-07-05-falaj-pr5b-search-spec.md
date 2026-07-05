# PR-5b — Global `/search` (split from PR-5 at Gate round 2)

**STATUS: NOT GATED.** This spec was split out of `2026-07-05-falaj-pr5-ia-spec.md` §5 when the R2 adversary found a [P1] in its data source. It must pass its own `/run-the-gate` (routing = Gate category) before any code. Refs #900.

**Problem (friction #3):** search exists only event-scoped (2 callsites: `ledger_screen.dart:281`, `event_command_center.dart:297`); the Activity tab filters only loaded pager pages. Finding an old expense = 4 taps + recalling group AND event.

## The R2 [P1] this spec must honor

The original design read `openByGroup` / journeys providers — both filter `!isClosed` (`active_journeys_provider.dart:226-228`), so a **concluded trip was unfindable**, contradicting the feature's purpose. **Data source is therefore `groupEventsProvider` (`event_provider.dart:33`)** — filters only `isDeleted == false`, keeps closed events — iterated per group from `userGroupsProvider`. Results label: "groups and events, including past events".

## Scope (v1)

- **Groups + events only** (open AND closed). Full expense search remains **Option C** — needs a server index (denormalized token field or external index); do NOT hand-roll a client full-scan and do NOT fan out live expense listeners (reopens #104). File the Option-C follow-up issue when this PR opens; the friction-#3 tap-table claim ("find old expense 4→2") belongs to Option C, not v1.
- Route: top-level `AppRoutes.search = '/search'`; builder → `SearchScreen(query: state.uri.queryParameters['q'])` — query in the QUERY param, never `extra`; `/search?q=alps` cold-linkable.
- Result taps: group → §2 smart-forward rule from the PR-5 spec; event → `/group/$gid/event/$eid` (works for closed events — the hub renders closed events with the Recap tab available).
- Back-guard: `/search` is TOP-LEVEL → cold link makes it the sole stack page (`canPop()==false`) → `_back` = `canPop() ? pop() : go('/home')`. No `PopScope(canPop:false)`.

## Open questions (for the Gate round)

- **Entry point placement [R2 P2]:** the home Groups `SectionHeader` already carries its single action ("New group" → create-or-join sheet, `home_screen.dart:180-185`), and PR-5 §fix-6 may split it into "New · Join". Options: (a) search icon in the home top bar (next to the bell), (b) third text action in the Groups header, (c) a search field atop the Activity tab. Pick ONE before gating; (a) recommended — doesn't crowd the header actions.
- Closed-event result rendering: show a `SETTLED`/ended badge on closed-event rows (existing badge idioms) so past results are visually distinct?
- l10n (all new keys land in BOTH `app_en.arb` + `app_ar.arb` same commit): `searchTitle`, `searchHint`, `searchEmpty`, `searchSectionGroups`, `searchSectionEvents` (+ badge key if used).

## Test plan (sketch — finalize at gating)

`test/features/search/search_navigation_test.dart`: cold `/search?q=…` renders + back→`/home`; a CLOSED event matching `q` appears in results (pins the P1 fix); group tap smart-forwards; event tap lands the hub; `?q=` round-trips; no expense rows + honest scope label (pins Option-B scope); renders without the bottom-nav shell.
