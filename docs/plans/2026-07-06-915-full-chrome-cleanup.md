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
4. Warm in-app flows are unchanged — but NOT because "every producer pushes" (that premise is false: `settle_up_screen.dart:991`'s cold-entry back fallback does `context.go('…/ledger')`). The correct invariant: **no path can materialize the deleted ancestor**, because (a) any exact `…/ledger`/`…/activity` location — pushed, gone, or cold — always fires the route-level redirect before building, and (b) child paths (`add`/`edit`/`settle-up`) build the parent match builderless → no page. The `go('…/ledger')` producer lands on the hub via the redirect, one instance, unchanged by this PR.

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
7. **Keys + l10n**: delete `LedgerKeys.screen`, `ActivityKeys.screen` (all other members of both keys files survive). Delete 11 dead l10n keys (EN+AR in the same commit + regen): `ledgerBackTooltip`, `ledgerActivityTooltip`, `ledgerSettleUp`, `ledgerAllSquare`, `ledgerHeroEmptyPrefix`, `ledgerHeroEmptyTail`, `ledgerHeroNegativePrefix`, `ledgerHeroNegativeTail`, `ledgerHeroPositivePrefix`, `ledgerHeroPositiveTail`, `ledgerSettledBadge`. **Their "0 users" status holds for `lib/` only** — 10 of the 11 (all but `ledgerActivityTooltip`) are enumerated by `test/unit/generated_l10n_surface_test.dart` (`_pr2bCalls` lambdas at :99, :121–130, :184), which compiles against the generated getters; those lambda lines are pruned in the SAME commit as the key deletion or the whole suite breaks at compile (Gate R1 catch, both reviewers). Surviving near-misses, do NOT touch: `ledgerSearchExpensesTooltip` + `ledgerEventSettingsTooltip` (hub), `ledgerAddExpense` (cross-group activity CTA), `ledgerExpenseCount` / `ledgerSettledCount` / `ledgerTripTotal` (trip caption), `activityCaption` / `activityTitle` (group activity screen).

## Callsite classification (principle 1)

Everything deleted is INBOUND (display-only chrome). The one OUTBOUND producer inside the deleted region — `_CoverHeader`'s `onActivity` push of `…/activity` — is redundant chrome (the hub's Activity tab is the surface). The roster strip's OUTBOUND `settle-up?memberId=` push is explicitly retained (it sits outside the `!embedded` guard since PR-5 §4). No write path, no money math, no schema, no rules change.

## Deep-link inventory (byte-stable — nothing renamed, nothing 404s)

`…/ledger` → hub `?tab=expenses` (redirect, unchanged) · `…/activity` → hub `?tab=activity` (redirect, unchanged) · `…/ledger/add`, `…/ledger/edit/:expId`, `…/ledger/settle-up?memberId=` real screens (unchanged builders) · `…/recap` real (untouched) · `/join/:code`, `/recover` untouched. The ONLY behavior delta: Back from a **cold-linked** editor/settle-up now reveals the hub instead of the deleted full-chrome ledger (§Verified-facts 3).

## Back-guard / #243

Editors and settle-up stay nested; on any declarative nav their `canPop()` is still true (GroupDetail + Hub pages beneath). No `PopScope` added or removed anywhere. The deleted screens' own back affordances die with them.

## Test migration (from the fresh-context inventory sweep, spot-verified)

**MIGRATE — mechanical, no assertion dies (5):** `ledger_filter_recompute_test.dart`, `ledger_clear_filters_test.dart`, `ledger_screen_same_name_test.dart`, `ledger_category_filter_settlements_note_test.dart`, `list_scroll_restoration_test.dart`. All assert only surviving panel surfaces (day cards, category strip, roster, empty/clear-filters, #807 note, #106/#629 recompute counters, scroll restoration). Construction just drops `embedded:` (param gone). `list_scroll_restoration_test.dart` keeps `MaterialApp.router(restorationScopeId:)` so both `restorationId`s stay under a restoration scope.

**SPLIT (3):**
- `ledger_screen_test.dart` — embedded group (:147–248) survives with THREE compile-fixes (Gate R1 adversary catch — "untouched" was false): drop imports :18 (`ledger_hero_block.dart`) + :20 (`ledger_sticky_cta.dart`) (the file references no surviving symbol from either — verified `LedgerTripCaption` is not used), and drop the two dead-type negative asserts :221 `find.byType(LedgerHeroStatement)` + :222 `find.byType(LedgerStickyCta)` (:220 `CoverArt` and :223 `OfflineBanner` findsNothing stay — those types survive elsewhere in the app). DROP the full-chrome asserts: :272–284 hero "All square"/"You owe"/−USD + 'Settle up' tap→route, :340–345 per-currency hero, :371–377 CoverArt RepaintBoundary. Re-point the roster-chip asserts (:367–368) at the panel construction. The hero behaviors (settled-gate-spans-all-buckets, per-currency lines) are ALREADY pinned at their new home — `event_command_center_test.dart` covers `_BalanceBlock` settled/owed/owing/USD (:50–:150) — no relocation test needed.
- `ledger_screen_overflow_test.dart` — DROP the chrome asserts (:148 header buttons, :157 cover back, :169 search-btn→sheet, :180 settings, :192/:204 sticky CTAs, :259 search-result→edit, hero asserts in :288). The 2 surviving asserts (row-tap→`edit/:expId` :233, day-card subtitle :327) FOLD into `ledger_screen_test.dart`'s embedded group; delete the file (its RenderFlex-overflow purpose was the chrome).
- `activity_feed_screen_test.dart` — DROP :161–174 (CaptionTitleBar back tap) and :699–707 (PaperBackdrop findsOneWidget). All ~26 feed-body tests survive; the two embedded-mode tests (:625, :730) become the primary spec (their nested-Scaffold/PaperBackdrop ABSENT asserts stay valid — now unconditionally true).

**DELETE (2 + 3):** `ledger_activity_entry_test.dart` (pins the cover-header activity button; hub Activity tab covered by redirect test (b)); `ledger_back_arrow_rtl_test.dart` (pins the deleted cover-header arrow — see replacement below). Plus the 3 orphaned hero-widget tests, deleted WITH the widget: `ledger_hero_block_rtl_test.dart`, `ledger_hero_settled_stamp_test.dart`, `ledger_currency_display_test.dart` — **except** `ledger_currency_display_test.dart` also constructs `LedgerTripCaption` (:24, :39), which survives → keep that file, drop only its `LedgerHeroStatement` cases. `LedgerStickyCta` has no direct test (dies silently).

**KEEP with 2 compile-fixes:** `event_module_redirect_navigation_test.dart` — :284 / :306 reference `LedgerKeys.screen` / `ActivityKeys.screen`, which die; drop those two `findsNothing` lines (the "exact `…/ledger` lands on hub, one instance" semantic stays pinned by the file's hub assertions), and its :181–184 / :216–219 constructions drop `embedded:` if present.

**PRUNE (l10n compile coupling):** `test/unit/generated_l10n_surface_test.dart` — remove the 10 `_pr2bCalls` lambda entries for deleted keys (:99 `ledgerBackTooltip`; :121–130 the 8 hero keys incl. the `(1)`/`(3)` plural calls; :184 `ledgerSettleUp`) in the same commit as the ARB deletion + regen. All other entries stay.

**Unaffected (verified):** `test/unit/app_router_test.dart` (pure `findMatch`), `notification_service_test.dart` (nav strings via stub), `test/helpers/test_router.dart` (stub Text builders), goldens (GoldenHarness), `check_arb_completeness_test.dart` (synthetic fixtures). No test helper constructs these screens.

**NEW pins (2):**
1. Cold `go('…/ledger/edit/:expId')` → Back lands on the **hub** (pins §Verified-facts-3: builderless ancestor contributes no page). Lives in `event_module_redirect_navigation_test.dart`.
2. Hub back-arrow RTL mirror: the deleted `ledger_back_arrow_rtl_test.dart` was the only event-chrome RTL pin, and `test/features/events/` has ZERO RTL tests today; the hub has its own directional arrow (`event_command_center.dart:424-425`). Add an RTL case (pump hub in `TextDirection.rtl`, assert `Iconsax.arrow_right`) so the #126 invariant keeps a home.

**Inventory correction (refuted during verification):** the sweep claimed `showLedgerSearchSheet` loses its only in-app caller. WRONG — the hub owns a live search button (`EventKeys.searchButton`, `event_command_center.dart:467` → `_openSearch:326` → `showLedgerSearchSheet:344`). Search survives; `ledger_search_sheet.dart` is untouched; no product decision needed.

## Non-goals

- No route renames, no redirect changes, no `appRouteRedirect` change.
- No `SettleUpScreen` / `EventRecapScreen` changes (real dual-mode screens).
- No l10n VALUE changes; key DELETIONS only, each grep-verified 0 external users.
- No BottomNavShell / StatefulShellRoute work.
- No new abstractions; subtractive PR.

## PR

One PR, `Closes #915`. Body carries `Spec:` line to this file + the deep-link inventory above. `/automerge` will classify GATE (router path) — expected.
