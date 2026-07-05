# PR-5 — IA / Friction Fixes (Falaj rebrand) — Gate-ready spec

**Gate-category** (routing / route tree / deep links / back guards). Run `/run-the-gate` on THIS spec before any code. Source: `docs/plans/2026-07-05-falaj-rebrand.md` §PR-5 + friction audit `scratchpad/wf-friction.json` (`routingConstraints` = the checklist, mapped in §8).

**App name stays Rihla** (Falaj = design system only). No money-math / `firestore.rules` / l10n-key changes in this PR. Five fixes, independently landable (see §7). Route-tree file throughout: `lib/core/router/app_router.dart` (route CONSTANTS at `AppRoutes.*`, e.g. `eventHub = '/group/:gid/event/:eid'`).

Classification legend: INBOUND = display/read only; OUTBOUND = feeds a write/nav target that must survive cold; BOTH = treat as OUTBOUND.

---

## 1. One-tap FAB + editor "change destination" affordance

**Problem (friction #1):** `AddExpenseFab` fires the picker sheet unless `AddExpenseTargets.sole != null`, and `sole` is non-null ONLY when `totalOpen == 1` across ALL groups. The #245 auto-seed gives every group one open event, so any 2+-group user always pays the sheet. A ranked default (`_priority` sort) already exists but is unused for the fast path.

**Provider contract change** (`lib/features/home/providers/active_journeys_provider.dart`):
- Add getter `AddExpenseTarget? get preferred` on `AddExpenseTargets`: **first line is the guard — `if (!allResolved) return null;`** (R2: the naive ternary would fast-path on partial data, defeating the same guard `sole` carries at `active_journeys_provider.dart:264`). Then: `active.isNotEmpty ? active.first : (sole ?? _firstAcrossOpenByGroup)`, where `active` is the window-filtered `_priority`-sorted list and the fallback flattens `openByGroup` values preserving priority order. Zero open targets → null.
- `sole` and `totalOpen` stay unchanged (other callers rely on them). `preferred` is PURELY a new getter; no field, no stream change.

**FAB change** (`lib/features/home/widgets/add_expense_fab.dart:34-39`): replace `final sole = …sole; if (sole != null) push` with `final target = …preferred; if (target != null) { context.push(addExpensePathFor(target)); return; } AddExpenseTargetSheet.show(context)`. Reuse existing `addExpensePathFor` (same file:14) → yields `/group/:gid/event/:eid/ledger/add`. No new route.

**Editor "change" affordance** — CORRECT ANCHOR: `lib/features/ledger/widgets/expense_editor_body.dart:1677` `_WhereCard` (NOT `add_expense_screen.dart`, which is a thin host; the editor body is SHARED by add AND edit). Render the trailing "Adding to <eventName> · change" button **only in add mode** (`!_isEdit` — today only `_DeleteCard` is mode-gated at :976; this adds the second gate). An existing expense is pinned to its event, so the affordance must never appear in edit mode. Tap behavior: if the form is dirty, run the EXISTING add-discard confirm (`editorDiscardAddTitle` flow) first; on confirm (or if pristine) call `AddExpenseTargetSheet.show(context, replaceCurrent: true)` — new optional param, exact contract `static Future<void> show(BuildContext context, {bool replaceCurrent = false})`; when true, `_pushTarget` (`add_expense_target_sheet.dart:50-55`) uses `context.pushReplacement(addExpensePathFor(target))` instead of `push`, so the abandoned add editor is REPLACED, never stacked (no ghost draft under Back). The FAB path keeps the default plain `push`. No `extra`; the target is path-encoded. **Wiring contract (R2):** `_WhereCard` is stateless and takes only `event` (`expense_editor_body.dart:1677-1678`) and renders in BOTH modes (`:965`); thread an optional `VoidCallback? onChangeDestination` from the ADD host only — `null` in edit mode hides the button (the null-check IS the mode gate).

**Callsite classification:** `preferred` is INBOUND for the label render; the pushed `addExpensePathFor(target)` is OUTBOUND (nav target, path-encoded — cold-safe). Sheet `push` unchanged (already OUTBOUND path-encoded).

**Back-guard / #243:** no route-tree change. FAB pushes `/…/ledger/add` (nested, `canPop()==true`) → bare pop reaches parent; unchanged. Sheet is a modal, not a route.

**Deep-link inventory:** byte-stable — `/group/:gid/event/:eid/ledger/add` and the sheet's push target are untouched.

**Test plan** — `test/features/home/add_expense_fab_navigation_test.dart` (extend existing FAB test): (a) two groups each with one open event → FAB pushes `/…ledger/add` for the `_priority`-first event (was: opened sheet) — assert pushed location, NOT a sheet; (b) `!allResolved` → FAB opens sheet (no false fast-path); (c) zero open targets → sheet; (d) editor "change" tap opens sheet and picking a second event pushes a fresh `/…ledger/add` for that eid. Add `_priority` ordering unit test in `active_journeys_provider_test.dart` (ongoing < upcoming < recently-ended).

## 2. Smart-forward group rows (1 open event → event hub)

**Problem (friction #2):** `GroupDetailScreen` shows balance/members/event-rows but zero expenses (group-wide ledger deferred #422). A one-open-event group forces Home → group → event before any ledger. Journeys strip bypasses it but only inside the active window.

**Change is CLIENT-SIDE at the home row only — NOT a router redirect.** The home groups-list row (`lib/features/home/screens/home_screen.dart:200`, currently `context.push('/group/${groups[index].id}')`) becomes: if that group has exactly one open event, push `/group/$gid/event/$eid` instead; else push `/group/$gid` unchanged.

**Provider contract:** reuse the already-watched data — the home tab holds `homeGroupBalanceProvider(gid)` live (`active_journeys_provider.dart:313`) and per-group open events via `openByGroup[gid]` on `AddExpenseTargets`. Decision rule: `final open = targets.openByGroup[gid]; final soleEvent = (targets.allResolved && open != null && open.length == 1) ? open.single : null;`. If `soleEvent != null` → `context.push('/group/$gid/event/${soleEvent.eventId}')`, else `context.push('/group/$gid')`. Never forward on unresolved streams (fail-safe to the overview). No new provider.

**Why the row, not a GoRouter redirect:** a `redirect` on `/group/:gid` would (a) break the multi-event and deep-link cases, (b) need the event stream resolved synchronously inside redirect (it isn't), and (c) fight the #243 top-level PopScope. Forwarding at the tap keeps `/group/:gid` a real, cold-linkable route.

**Callsite classification:** `openByGroup`/`allResolved` reads are INBOUND (decide-only). Both pushed locations are OUTBOUND, path-encoded, cold-safe.

**Back-guard / #243:** unchanged and load-bearing. Cold deep-link to `/group/:gid` still materializes it as sole top-level page → its `PopScope`→`/home` fallback still applies. Forwarding to `/group/:gid/event/:eid` (nested) means GoRouter materializes the `/group/:gid` ancestor, so `canPop()==true` at the hub and the hub's bare `if(canPop())pop()` reaches the group overview — the user CAN still reach the group screen (via hub back + header). Do NOT add any PopScope to the hub.

**Deep-link inventory:** byte-stable. `/group/:gid` and `/group/:gid/event/:eid` both already exist (`AppRoutes.groupDetail`, `AppRoutes.eventHub`); no URL added or renamed. External `/join/:code`, `/recover`, `/…/ledger/edit/:expId`, settle-up `?memberId=` untouched.

**Test plan** — `test/features/home/home_group_row_navigation_test.dart` (new, `*_navigation_test.dart` convention): (a) group with exactly 1 open event → row push == `/group/$gid/event/$eid`; (b) group with 2 open events → `/group/$gid`; (c) group with 0 open events → `/group/$gid`; (d) `!allResolved` → `/group/$gid` (fail-safe); (e) COLD deep-link straight to `/group/:gid` still renders overview + honors PopScope→/home (regression against forwarding leaking into the route layer).

## 3. Hero → per-group breakdown sheet → `settle-up?memberId=`

**Problem (friction #4):** `BalanceHeroCard` says "you are owed X / you owe Y" but its `onTap` only calls `_scrollToJourneys` (`home_screen.dart:141`). The money intent is discarded; acting on it is a 4-tap re-walk.

**Change** (`home_screen.dart:141`): replace `BalanceHeroCard(onTap: _scrollToJourneys)` with `BalanceHeroCard(onTap: () => GroupBalanceBreakdownSheet.show(context))`. `BalanceHeroCard` signature is unchanged (`onTap` is already an optional `VoidCallback`, `balance_hero_card.dart:29`).

**New widget** `lib/features/home/widgets/group_balance_breakdown_sheet.dart` (a `ConsumerWidget` modal, follows `AddExpenseTargetSheet` shape): one row per group the user has a non-zero net in, per-currency (never sum across currencies — read `ref.watch(homeGroupBalanceProvider(gid)).valueOrNull?.userNet`, the already-uid-sliced per-currency `Map<String, Decimal>` on the `HomeGroupBalance` record (`group_balance_provider.dart:806`) — exactly the `_GroupRow` pattern at `home_screen.dart:812-819`. There is NO `netFor` on this type; `netFor` lives on the different `GroupBalanceAggregate` — do not confuse them. Iterate `userGroupsProvider` like `active_journeys_provider.dart:313`). Each row shows group name + `RAmount` net + the owe/owed caption the groups list already renders (`home_screen.dart:829-835`, reusing existing `homeTheyOweYou`/`homeYouOwe`/`homeSettled` keys — no new l10n for this); tapping a row does `context.push('/group/$gid/settle-up')` — the router already reads `?memberId=` (`app_router.dart:269`). **Preselect:** the group-level hero net is not member-specific, so push WITHOUT `memberId` (the group settle-up screen already lists all pairwise transfers). Only append `?memberId=$id` if a future per-member hero row exists — do NOT fabricate a member id.

**Provider contract:** read-only. `homeGroupBalanceProvider(gid)` (facade in `group_balance_provider.dart`) → `AsyncValue<HomeGroupBalance>` → `.valueOrNull?.userNet` (per-currency, uid-sliced); `currentUserIdProvider` for uid; `userGroupsProvider` for the group list. No new provider, no write, no aggregate-doc change (the #366 aggregate is a DISPLAY cache — INBOUND only).

**Callsite classification:** all balance reads INBOUND (display). The row push to `/group/:gid/settle-up` is OUTBOUND, path-encoded, cold-safe. The `?memberId=` query is OUTBOUND when present.

**Back-guard / #243:** no route-tree change. Sheet is a modal. `/group/:gid/settle-up` is an existing nested route under `/group/:gid`; GoRouter materializes the ancestor so `canPop()==true` on the settle-up screen — its existing bare pop is correct, unchanged.

**Deep-link inventory:** byte-stable. `/group/:gid/settle-up?memberId=` preserved exactly (constant `AppRoutes.groupSettleUp`, query read at :269). No new URL.

**Honest tap-count correction (O3 closed):** without a member preselect, job 4 (record a group settlement) stays 4 taps (hero → row → Mark paid → confirm) — the earlier proposal table's "4→3" overclaimed by one. The fix's real value: the hero stops being a dead end, and the per-currency per-group breakdown is one tap away. Record this correction in the PR body.

**Test plan** — `test/features/home/hero_breakdown_navigation_test.dart` (new): (a) hero tap opens the breakdown sheet (was: scroll — assert sheet present, no scroll side-effect); (b) sheet renders one row per non-zero-net group, per-currency (two-currency group → two `RAmount`s, never summed); (c) tapping a row pushes `/group/$gid/settle-up` (no bogus `memberId`); (d) zero-net user → empty-state row / sheet still opens without crash. Keep an existing `home_screen` test asserting `_scrollToJourneys` is no longer the hero handler (grep-delete the stale assertion, don't patch).

## 4. Module-route consolidation — route-level redirects, NOT builder shims

**Problem (friction #7):** every event module exists twice — the `EventCommandCenter` tab panel AND a standalone full-chrome route. Two chromes per surface. Hub tab state is in-widget (`_EventTab`, `event_command_center.dart:92`).

**ROUND-1 GATE REVISIONS (why the original shim design was wrong):**
- Builder-shims double-materialize the hub: module routes are NESTED under `/event/:eid`, and GoRouter materializes ancestors — a cold link to `…/ledger` would build [GroupDetail, Hub(ancestor), Hub(leaf)]; first Back appears to no-op. Resolution: route-level REDIRECTS into the hub with a `?tab=` query — one hub instance, URLs still resolve.
- `…/recap` must stay a REAL screen: the hub's recap tab exists only when `event.isClosed` (`showRecap`, `event_command_center.dart:155-160`, open+`initialTab:recap` falls back to Expenses at :158). Open-event recap is a live surface (`_OpenRecapBanner` `event_command_center.dart:214`; settle-up "View recap & export" `settle_up_screen.dart:155-157`) and `EventRecapScreen` is the SOLE host of the #722 share card + #704 CSV export. A shim would strand open-event users on Expenses and sever the exports.
- `…/ledger/settle-up?memberId=` must stay a REAL screen (**O1 CLOSED**): the embedded settle panel takes no preselect (`event_command_center.dart:236-240`); only the standalone `SettleUpScreen` threads `preSelectedMemberId` (`settle_up_screen.dart:52,332`). A shim would drop the byte-stable param.

**Route-tree change** (`app_router.dart`):
- Hub gains an optional tab query: `AppRoutes.eventHub` builder → `EventCommandCenter(initialTab: EventTab.fromQuery(state.uri.queryParameters['tab']))`. `fromQuery` maps EXPLICITLY: `expenses`→expenses, `activity`→activity, `recap`→recap; **`settleUp`, absent, or unknown → expenses** (a cold `?tab=settleUp` must not fire the #204 settle-review sheet with no settle context); `tab=recap` on an open event falls back to Expenses via the existing :158 guard. **Seeding contract:** `_tab = widget.initialTab` in `initState` only — all producers `push` (imperative pageKey), so no `didUpdateWidget` path is needed; test (f) is the cold-landing proof. **Known + accepted:** warm in-app `push` of the hub URL with a different `?tab=` stacks a second hub instance — Back returns to the prior tab state; embedded rows don't self-navigate, so it's practically unreachable; documented, not guarded. Promote `_EventTab` → public `EventTab` (zero refs outside the file today — collision-free). Query param, never `extra` — cold-safe.
- `AppRoutes.eventLedger` (`…/ledger`): add route-level `redirect`: `(context, state) { final loc = state.uri.path; if (!loc.endsWith('/ledger')) return null; return '${loc.substring(0, loc.length - 7)}?tab=expenses'; }`. **The null-for-children guard is LOAD-BEARING**: GoRouter runs ancestor route-level redirects for descendant matches, so without it `…/ledger/add`, `…/ledger/edit/:expId`, `…/ledger/settle-up` would be hijacked. Children keep their real builders.
- `AppRoutes.eventActivity` (`…/activity`): same pattern → `?tab=activity` (no children to guard, keep the same endsWith shape for symmetry).
- `AppRoutes.eventRecap` (`…/recap`): **UNCHANGED real `EventRecapScreen`** (open + closed).
- `AppRoutes.eventLedgerSettleUp`: **UNCHANGED real `SettleUpScreen`** with `?memberId=` read at `app_router.dart:368-369`.
- `…/ledger/add` / `…/ledger/edit/:expId`: unchanged real editors.

**Roster-strip preselect producer survives:** the per-person chips (`ledger_screen.dart:327-330`) — today inside the full-chrome-only region — MOVE into the embedded expenses panel (lifted out of the `embedded:false` guard), so "tap a person → settle preselected" remains producible in-app; the chip keeps pushing `…/ledger/settle-up?memberId=X` (now the real screen).

**Full-chrome code is KEPT, just unrouted (R2 revision):** ~12 `test/features/ledger/*` files + `activity_feed_screen_test.dart` construct the widgets with default `embedded:false` and assert on cover/hero/roster/back-arrow — deleting the mode in this PR makes "each commit leaves the tree green" unachievable. PR-5 therefore only STOPS ROUTING to the full chrome (the redirects above); the `embedded:false` branches and their tests stay green but unreachable. Their deletion + test migration is a named follow-up cleanup PR (file at PR time). `EventRecapScreen` is untouched either way.

**`appRouteRedirect` constraint note:** constraint #1 pins the GLOBAL `appRouteRedirect` (only `/`→`/home`; `test/unit/app_router_test.dart`). The two additions here are ROUTE-LEVEL `redirect:` callbacks on `…/ledger` and `…/activity` — additive, per-route, and do not touch `appRouteRedirect`. Reviewer: confirm the pinned test asserts only the top-level redirect function.

**Callsite classification:** redirect targets and `?tab=` are OUTBOUND (cold-linkable locations); `initialTab` seeding is INBOUND UI state. `?memberId=` on the real settle-up screen is OUTBOUND and round-trips byte-for-byte.

**Back-guard / #243:** the redirect lands on `…/event/:eid?tab=…` (nested under `/group/:gid`) → ancestor materializes, `canPop()==true`, hub's bare pop reaches GroupDetail. ONE hub instance in the stack. No PopScope anywhere here (predictive-back intact).

**Deep-link inventory:** every module URL still RESOLVES (nothing 404s, nothing renamed): `…/ledger` → hub`?tab=expenses` (redirect), `…/activity` → hub`?tab=activity` (redirect), `…/recap` real, `…/ledger/settle-up?memberId=` real + param intact, `…/ledger/add` + `…/ledger/edit/:expId` real. In-app producers (`activity_nav.dart:35,43`, `notification_service.dart:330`) keep emitting the old URLs — the redirects absorb them; no producer churn required in this PR.

**Test plan** — `test/features/events/event_module_redirect_navigation_test.dart` (new): (a) cold `…/ledger` → exactly ONE `EventCommandCenter`, Expenses tab; one Back reaches GroupDetail (no duplicate-hub no-op); (b) cold `…/activity` → hub on Activity tab; (c) cold `…/ledger/add` and `…/ledger/edit/:expId` are NOT hijacked by the parent redirect (pins the load-bearing null-guard) → real editors render; (d) cold `…/ledger/settle-up?memberId=X` → real `SettleUpScreen` with preselect X; (e) cold `…/recap` on an OPEN event → `EventRecapScreen` with share/export affordances reachable; and on a CLOSED event → same; (f) activity-row landings: `activityRowTarget` expense_added (`…/ledger`) renders hub@Expenses, expense_deleted (`…/activity`) renders hub@Activity; (g) hub URL with `?tab=recap` + OPEN event → Expenses fallback, no crash; (h) `?tab=` absent/garbage → Expenses.

## 5. Global `/search` — SPLIT OUT (R2)

Removed from PR-5. The R2 adversary found a [P1]: the proposed data source (`openByGroup`/journeys providers) filters out CLOSED events (`active_journeys_provider.dart:226-228`), so a concluded trip would be unfindable — defeating the friction the route exists to fix. `/search` now lives in its own spec — `docs/plans/2026-07-05-falaj-pr5b-search-spec.md` — carrying the fix (source from `groupEventsProvider`, `event_provider.dart:33`, which keeps closed events) and its own open questions (entry-point placement). **PR-5b requires its own /run-the-gate before implementation.** Friction #3's tap-table claim moves wholly to PR-5b/Option-C.

## 6. Non-goals

- **No StatefulShellRoute / persistent-shell migration** (friction #5). Bottom nav stays `/home`-only; tabs stay the `AnimatedOpacity+IgnorePointer` stack. Deliberately deferred — a separate gated routing migration, not bundled here.
- **No `/search` at all in PR-5** — split to PR-5b (see §5); expense search remains Option-C beyond that.
- **No money-math / `MoneySerializer` / `firestore.rules` / Cloud Functions changes.** Zero write-path or balance changes; every provider read added here is INBOUND display. The #366 aggregate doc stays a display cache.
- **No l10n VALUE / key removals.** Additive keys ONLY — full inventory, each landing in BOTH `app_en.arb` AND `app_ar.arb` in the same commit (the #857 class): §1 editor affordance `editorAddingToEvent` ("Adding to {eventName}") + `editorChangeDestination` ("change"); §3 sheet `heroBreakdownTitle`, `heroBreakdownEmpty`; (search keys moved to PR-5b). No other copy changes.
- **No `state.extra`, no `goNamed`, no `Navigator.push`** anywhere (release-readiness greps all three).
- **No rename of `/join/:code`, `/recover`, ledger edit/add, or settle-up `?memberId=`** URLs.
- **Not touching the #245 auto-seed, the #243 back-guard matrix, or the #666 dual-mode `showBack` pattern** — all preserved as-is.
- Friction #6 (Join hidden under "New group" label) and friction #8 (dual-mode centralize helper) are small copy/refactor items — OPTIONAL add-ons, not required for PR-5; land separately if desired (out of the 5 core fixes).

## 7. Rollout order / PR split

Five INDEPENDENT commits; each leaves the tree green and is separately revertable. Recommended as ONE PR-5 (all Gate-category, one Gate run covers the route surface) OR split into 5 sub-PRs if reviewer prefers — order below minimizes route-tree churn overlap:

1. **§1 One-tap FAB** — no route-tree change; `active_journeys_provider` getter + FAB + editor button. Lowest risk, ships first (pure client, no URL). Can even land before PR-1–4.
2. **§2 Smart-forward group rows** — no route-tree change; home-row tap logic only. Independent of §1.
3. **§3 Hero breakdown sheet** — no route-tree change; new widget + `home_screen:141` handler swap. Independent.
4. **§4 Module-route consolidation** — BIGGEST route-tree change (2 route-level redirects + hub `?tab=` + promotes `EventTab` + deletes full-chrome; recap & settle-up stay real). Land LAST so a revert doesn't disturb the smaller wins. O1 is CLOSED (settle-up stays a real screen).

Each sub-PR body: `Spec:` line pointing to this file's section; `Closes #<friction-issue>` or `Refs`. §4 and §5 (route-tree touchers) MUST show the byte-stable deep-link inventory diff in the PR body. All five classify Gate-category in `/automerge` (router + provider-contract), so each gets the fresh-context Opus diff review + refuter.

## 8. Gate reviewer checklist — routingConstraints coverage

Every entry from `wf-friction.json` `routingConstraints[]`, mapped to the section that honors it:

1. **`appRouteRedirect` maps only `/`→`/home`, never add an onboarding gate.** → `appRouteRedirect` itself is UNTOUCHED. §2 forwards at the TAP. §4 adds two ROUTE-LEVEL `redirect:` callbacks (on `…/ledger`, `…/activity`) — a different mechanism from the pinned global redirect; reviewer must confirm `test/unit/app_router_test.dart` pins only the top-level function. §5 adds `/search` as a plain GoRoute. Satisfied by §2, §4 (with the note), §5.
2. **Top-level vs nested `canPop` asymmetry BY DESIGN (#243); no `else go('/home')` on nested; no `PopScope(canPop:false)` on nested.** → §2 (hub stays nested, no PopScope added), §4 (redirect targets nested, bare pop, no PopScope). (/search → PR-5b.) Each fix's "Back-guard / #243" paragraph addresses it explicitly.
3. **Dual-mode screens keep `showBack`-flag pattern; never `PopScope(canPop:false)` (#666).** → No fix modifies Profile/CrossGroupActivity dual-mode; no new dual-mode screen in PR-5 (/search → PR-5b). Satisfied by Non-goals.
4. **Nav data via path/query only — no `state.extra`, no `goNamed`, no `Navigator.push`.** → §1 (path-encoded add target), §2 (path pushes), §3 (`/group/:gid/settle-up` path push), §4 (tab via `?tab=` query, NOT extra). All four. No `goNamed`/`Navigator.push` introduced anywhere.
5. **Byte-stable URLs: `/join/:code`, `/recover`(+`/pending`), `…/ledger/edit/:expId`, `/group/:gid/settle-up?memberId=` + event `ledger/settle-up?memberId=`.** → §3 preserves `settle-up?memberId=`; §4 preserves `…/ledger/edit/:expId` (real), `…/ledger/settle-up?memberId=` (REAL screen — O1 closed, param intact), `…/activity` (redirect-resolves), `…/recap` (real); §1 preserves `…/ledger/add`. `/join`, `/recover` untouched by all. Each fix has a "Deep-link inventory" line.
6. **BottomNavShell tabs are opacity stack, not GoRouter; any persistent-shell migration must be deliberate + preserve `BottomNavTabScope.selectTab` side effects.** → Non-goals: NO StatefulShellRoute migration in PR-5. §5 `/search` is a pushed top-level route, not a tab, so it doesn't touch the shell or the seen-stamp. Satisfied by Non-goals + §5.
7. **Inbound deep links owned by `app_links`; `FlutterDeepLinkingEnabled` ABSENT from Info.plist (#369); `flutter_deeplinking_enabled=false` Android.** → No fix touches iOS `Info.plist` or `AndroidManifest`; no fix enables Flutter-native deep linking. All new routes are GoRouter builders reached via `context.push`. Satisfied by all (nothing changes the deep-link ownership). Reviewer: confirm no `Info.plist` diff.
8. **Back-guard tests follow `*_navigation_test.dart`; keep `restorationScopeId:'router'` (#362) + `RouteNotFoundScreen` errorBuilder (#823).** → Every §1–§5 test plan uses `*_navigation_test.dart`. No fix edits `restorationScopeId` or the `errorBuilder`. New routes fall under the existing errorBuilder unchanged. Satisfied by §1–§5 test plans.
9. **Route changes are Gate-category — `/run-the-gate` mandatory before code; `lib/core/router/**` PRs classify Gate in `/automerge`.** → Header + §7: this spec IS the pre-code Gate artifact; §4/§5 touch `app_router.dart` and are flagged Gate for both `/run-the-gate` and `/automerge`. Satisfied by header + §7.
10. **`EventCommandCenter` tab state is in-widget (`_EventTab`), not a route param today; tab must derive from path/query, not `extra`, and the standalone add/edit editor routes must not break.** → §4: promote `_EventTab`→public `EventTab`, seed via the hub's `?tab=` QUERY param (never `extra`); redirects carry the tab in the URL; add/edit/settle-up/recap stay REAL screens, protected by the load-bearing null-for-children redirect guard + test (c). Directly satisfied by §4.

**Round-1 resolutions (all former open questions CLOSED):**
- **O1 → CLOSED:** `…/ledger/settle-up?memberId=` stays a REAL `SettleUpScreen` (embedded panel takes no preselect, `event_command_center.dart:236-240`). (§4)
- **O2 → CLOSED:** §5 ships Option B (groups+events); friction-#3's tap-table claim moves to the named Option-C follow-up issue, filed at PR time. (§5)
- **O3 → CLOSED:** hero-sheet rows push without `memberId`; job-4 tap count honestly stays 4 (correction recorded in §3). (§3)

---
## §9 Gate log
- **Round 2 (2026-07-05): rubric 0 P1 / 2 P2 / 3 P3 · adversary 1 P1 / 1 P2 / 3 P3.** The sole P1 was confined to §5 (/search sourced from providers that exclude closed events). Resolution per the Gate's over-scope rule: §5 SPLIT Out to PR-5b (not gated); §1–§4 are same-round P1-clean from BOTH reviewers → **GATE CLEARED for §1–§4**. R2 P2/P3s folded in: `preferred` allResolved guard, full-chrome kept-but-unrouted (test blast radius), `_WhereCard` onChangeDestination contract, `fromQuery` explicit mapping + initState seeding pin, hero-row captions, warm-stack note. R2 rubric claimed the §4 mechanism held on "installed go_router 17.1.0" — that version claim was FABRICATED (the reviewer read a pub-cache copy from another project; `pubspec.lock` resolves **13.2.5**, CLAUDE.md's "GoRouter 13" is correct). Caught by the orchestrator's mechanical lockfile check before a doc "fix" merged. The two load-bearing semantics were then RE-VERIFIED against the real 13.2.5 sources: `_getRouteLevelRedirect` walks the full matched chain from index 0 (ancestor redirects fire for descendants → the null-for-children guard IS load-bearing), and `buildState` passes `uri: matches.uri` (full location → the `endsWith('/ledger')` guard sees child paths). §4's design holds on 13.2.5 exactly as written.
- **Round 1 (2026-07-05): 3 P1 / 5 P2 / 3 P3 across two reviewers — all applied.** P1s: (a) recap shim severed open-event recap + #722/#704 exports → recap stays real; (b) editor affordance mis-anchored to `add_expense_screen.dart` and leaked into edit mode → anchored to `expense_editor_body.dart:1677` `_WhereCard`, add-mode-gated, replaceCurrent semantics; (c) builder-shims double-materialize the hub on nested routes → route-level redirects + hub `?tab=` query, null-for-children guard. P2s: `netFor`→`userNet`; recap prose inversion fixed; roster-strip preselect producer moved into the embedded panel; l10n inventory enumerated with AR pairs; O1 closed to real screen. P3s: replace-not-push from the editor; friction-#3 claim moved to Option-C follow-up; activity-row landing assertions added to §4 tests.
