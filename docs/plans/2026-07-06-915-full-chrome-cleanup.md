# #915 — Delete the unrouted full-chrome event module screens

**Status:** DRAFT — pre-Gate.
**Issue:** #915 (Refs #900, the named follow-up from PR-5 §4's R2 revision).
**Parent spec:** `docs/plans/2026-07-05-falaj-pr5-ia-spec.md` §4 — "Full-chrome code is KEPT, just unrouted (R2 revision) … Their deletion + test migration is a named follow-up cleanup PR."
**Gate class:** GATE (touches `lib/core/router/app_router.dart` — subtractive only, but routing is unconditionally Gate-category).

## Problem

PR-5 §4 (#917) stopped routing to the full-chrome `LedgerScreen` / `ActivityFeedScreen` (route-level redirects into the hub's `?tab=`), but kept their `embedded:false` branches + the router pageBuilders alive because ~12 ledger test files + `activity_feed_screen_test.dart` construct them directly, and deleting the mode in PR-5 would have broken tree-green-per-commit. This PR deletes the dead mode and migrates/retires its tests.

`EventRecapScreen` and `SettleUpScreen` are REAL routed dual-mode screens — **not part of this cleanup**; their `embedded` flags stay.

## Verified mechanism facts (go_router 13.2.5, read from the installed package source 2026-07-06)

1. **Redirect-only `GoRoute` is legal:** `route.dart:216` — `assert(pageBuilder != null || builder != null || redirect != null)`.
2. **A builderless route contributes NO page:** `builder.dart` `_buildPageForGoRoute` returns `null` when the route has neither `pageBuilder` nor `builder`, and `_updatePages` skips null pages (`if (page == null) continue;`). Children of a builderless parent still build their own pages.
3. **Consequence — current live behavior being changed:** today a *declarative* navigation (cold deep link / `go`) to `…/ledger/add`, `…/ledger/edit/:expId`, or `…/ledger/settle-up` materializes the kept full-chrome `LedgerScreen` as an ancestor page in the stack (the redirect's null-for-children guard lets the chain through, and the ancestor has a pageBuilder). Back from a cold-linked editor therefore lands on the full-chrome ledger — the very chrome PR-5 removed from the IA. After this PR the ancestor contributes no page, so Back from a cold-linked editor lands on the **hub** (`event/:eid` ancestor, ONE instance — the PR-5 R1 double-hub P1 does not apply because the hub materializes only via the `event/:eid` ancestor, not a second time for `…/ledger`).
4. Warm in-app flows are unchanged: every producer `push`es (imperative — only the leaf page is added), so no full-chrome ancestor exists in warm stacks today either.

## Change inventory — lib (7 files)

1. **`lib/core/router/app_router.dart`** (subtractive only):
   - `GoRoute(path: 'ledger')`: delete the `pageBuilder:` (route becomes redirect-only; `redirect: eventLedgerModuleRedirect` and the three children `add` / `edit/:expId` / `settle-up` are UNTOUCHED). The `endsWith('/ledger')` null-for-children guard stays LOAD-BEARING (ancestor redirects still run for descendants).
   - `GoRoute(path: 'activity')`: delete the `pageBuilder:` (redirect-only; no children).
   - Drop the now-unused `LedgerScreen` / `ActivityFeedScreen` imports; rewrite the two "KEPT for its widget tests" comments to say redirect-only.
   - `appRouteRedirect` (global) UNTOUCHED — `test/unit/app_router_test.dart` continues to pin it, and its URL-resolution list stays green (redirect-only routes still match; `findMatch` never errors).
2. **`lib/features/ledger/screens/ledger_screen.dart`**: remove the `embedded` field/param (screen becomes the panel, period). Delete: the `Scaffold` wrapper (+ `LedgerKeys.screen`), `_CoverHeader` (back/search/activity/settings buttons), the `OfflineBanner` sliver, the `LedgerHeroStatement` sliver, the sticky-CTA `Column` branch, and the hero-only derivations (`heroKind`, `singleLine`, `heroLines`). KEEP: `isSettled` (feeds `rosterState` + the settled footer), the trip caption, the roster strip **with its per-person `…/ledger/settle-up?memberId=` push** (PR-5 §4: the only in-app preselect producer), category strip, day cards, empty states, end-of-ledger footer; FAB clearance becomes unconditional (`kEmbeddedEventPanelFabClearance`). Dead imports go (`cover_art`, `offline_banner`, `r_icon_button`, `haptic_service`, `ledger_sticky_cta`, `ledger_search_sheet`).
3. **`lib/features/activity/screens/activity_feed_screen.dart`**: remove `embedded`; delete the `Scaffold` + `CaptionTitleBar` branch (+ `ActivityKeys.screen`); list padding unconditionally uses the FAB clearance. `CaptionTitleBar` itself survives (`group_activity_screen.dart`).
4. **`lib/features/events/screens/event_command_center.dart`**: drop `embedded: true` from the `LedgerScreen` / `ActivityFeedScreen` constructions (param gone). `SettleUpScreen` / `EventRecapScreen` keep theirs.
5. **`lib/features/ledger/widgets/ledger_hero_block.dart`**: delete `LedgerHeroKind`, `LedgerHeroLine`, `LedgerHeroStatement`, `_ProseRow`, `_SettledRow`. **`LedgerTripCaption` stays** (embedded panel + `ledger_currency_display_test.dart` construct it).
6. **`lib/features/ledger/widgets/ledger_sticky_cta.dart`**: delete the file (sole producer was the deleted branch; hub owns add/settle affordances).
7. **Keys + l10n**: delete `LedgerKeys.screen`, `ActivityKeys.screen` (all other members of both keys files survive). Delete 11 provably-dead l10n keys (grep-verified 0 external users, EN+AR in the same commit + regen): `ledgerBackTooltip`, `ledgerActivityTooltip`, `ledgerSettleUp`, `ledgerAllSquare`, `ledgerHeroEmptyPrefix`, `ledgerHeroEmptyTail`, `ledgerHeroNegativePrefix`, `ledgerHeroNegativeTail`, `ledgerHeroPositivePrefix`, `ledgerHeroPositiveTail`, `ledgerSettledBadge`. Surviving near-misses, do NOT touch: `ledgerSearchExpensesTooltip` + `ledgerEventSettingsTooltip` (hub), `ledgerAddExpense` (cross-group activity CTA), `ledgerExpenseCount` / `ledgerSettledCount` / `ledgerTripTotal` (trip caption), `activityCaption` / `activityTitle` (group activity screen).

## Callsite classification (principle 1)

Everything deleted is INBOUND (display-only chrome). The one OUTBOUND producer inside the deleted region — `_CoverHeader`'s `onActivity` push of `…/activity` — is redundant chrome (the hub's Activity tab is the surface). The roster strip's OUTBOUND `settle-up?memberId=` push is explicitly retained (it sits outside the `!embedded` guard since PR-5 §4). No write path, no money math, no schema, no rules change.

## Deep-link inventory (byte-stable — nothing renamed, nothing 404s)

`…/ledger` → hub `?tab=expenses` (redirect, unchanged) · `…/activity` → hub `?tab=activity` (redirect, unchanged) · `…/ledger/add`, `…/ledger/edit/:expId`, `…/ledger/settle-up?memberId=` real screens (unchanged builders) · `…/recap` real (untouched) · `/join/:code`, `/recover` untouched. The ONLY behavior delta: Back from a **cold-linked** editor/settle-up now reveals the hub instead of the deleted full-chrome ledger (§Verified-facts 3).

## Back-guard / #243

Editors and settle-up stay nested; on any declarative nav their `canPop()` is still true (GroupDetail + Hub pages beneath). No `PopScope` added or removed anywhere. The deleted screens' own back affordances die with them.

## Test migration (appendix filled from the fresh inventory pass)

To be spliced from the `915-test-inventory` sweep: per-file MIGRATE / SPLIT / DELETE verdicts for the ~14 affected files, including `event_module_redirect_navigation_test.dart:284,306` (the `LedgerKeys.screen` / `ActivityKeys.screen` `findsNothing` lines — the keys die; the "exact `…/ledger` lands on hub" semantic stays pinned by the existing hub assertions) and the hero/sticky-CTA widget tests (surface deleted → tests retire with it).

New pin: one test asserting a **cold `…/ledger/edit/:expId` → Back lands on the hub** (the §Verified-facts-3 behavior change, so the builderless-ancestor mechanism can't silently regress).

## Non-goals

- No route renames, no redirect changes, no `appRouteRedirect` change.
- No `SettleUpScreen` / `EventRecapScreen` changes (real dual-mode screens).
- No l10n VALUE changes; key DELETIONS only, each grep-verified 0 external users.
- No BottomNavShell / StatefulShellRoute work.
- No new abstractions; subtractive PR.

## PR

One PR, `Closes #915`. Body carries `Spec:` line to this file + the deep-link inventory above. `/automerge` will classify GATE (router path) — expected.
