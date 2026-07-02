# #758 Tabbed Event View Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make the event one screen — pinned collapsing balance header + segmented tabs **Expenses · Settle up · Activity (· Recap when closed)** — replacing the `EventCommandCenter` launchpad hub, with zero route / money / schema surface changes.

**Architecture:** The four existing screens gain an `embedded: true` mode that skips their own chrome (Scaffold / top bar / cover header / sticky CTA) and renders content-only; `EventCommandCenter` becomes the tabbed shell that hosts them in a lazily-built keep-alive `IndexedStack`. No logic moves: the settle write path (#282/#367/#773/#204), activity pagination, ledger filtering, and recap projection all stay in their current files. Standalone routes (`/ledger`, `/ledger/settle-up`, `/activity`, `/recap`) keep rendering the full-chrome versions for deep links. `app_router.dart` is untouched.

**Tech Stack:** Flutter, Riverpod 2.x (existing providers only), GoRouter 13 (untouched), design tokens via `context.colors|spacing|shadows`.

**Design source:** `docs/design/mockups/in-event-tabbed-A.html` (signed off). Decisions locked 2026-07-02: settle rows lead with **Mark received** (existing record sheet); **Recap tab in this PR**, visible only when `event.isClosed`; search **behind a header icon**, category chips inline (as today).

---

## Gate classification (checked against the operating contract)

- **Money math:** header reuses the hub's existing derivation verbatim — `ledgerViewProvider(eventRef).balances` → `myNetByCurrency` → `nonZeroNetsGccFirst` (`event_command_center.dart:124-141`). No `BalanceCalculator`/`MoneySerializer` edit.
- **Routing:** `app_router.dart` untouched — tabs are widget state; every existing route keeps its current builder. Verify at the end: `git diff main...HEAD -- lib/core/router/ | wc -l` must be 0.
- **Schema/rules/functions:** untouched.

→ **Gate-exempt** (UI re-layout). The `/automerge` classifier will still route this to review if any model/router file sneaks into the diff — keep them out.

**Verification-principles pass (run while writing this spec):**
1. *Callsite classification:* every new surface is INBOUND (display). The only OUTBOUND logic in scope (settle record/correct, `ledgerRevisionProvider` bumps at `settle_up_screen.dart:739`) is untouched by the embedded flag — the flag gates chrome only (verified: all write logic lives in `_SettleUpScreenState` methods, not the skipped `_SettleUpTopBar`/Scaffold).
2. *Claims vs code:* routes verified at `app_router.dart:48-62,311-375`; screen structures read in full (`ledger_screen.dart`, `settle_up_screen.dart`, `activity_feed_screen.dart:1-120`, `event_recap_screen.dart:43-120`, `event_command_center.dart:1-380`); `SettleUpPageBody` confirmed a `SingleChildScrollView` (`settle_up_page_body.dart:297`); `showLedgerSearchSheet` signature at `ledger_search_sheet.dart:21`.
3. *Read-path per write-path:* no new write paths; no new `ledgerRevisionProvider` bump obligations (per-event money writes still happen only in add/edit/settle screens, all of which already bump).
4. *Fields from types:* header consumes `view.balances`, `view.eventTotal`, `view.expensePayerDisplayNames`, `view.settlementDisplayNames`, `view.rosterDisplayNames` — all confirmed on `ledgerViewProvider`'s value by reading the hub + ledger callsites.
5. *Data contracts:* `embedded` is a `bool` constructor param, default `false`, on all four screens. Tab identity is a private enum in the shell.
6. *Arithmetic:* none new.
7. *Adversarial axes:* closed-event (FAB hidden, Recap tab appears, add frozen), multi-currency (header renders per-currency lines, never sums), empty-event (header "Nothing to settle yet", Expenses tab shows journal empty state), RTL (DirectionalIcon back, EdgeInsetsDirectional).

---

## Landmines (read before coding)

- **#204 review sheet timing improves for free:** `_maybeShowReviewSheet` fires when `SettleUpScreen`'s data callback first runs. With lazy tab building it fires on first **Settle tab activation**, not event open. This is the desired semantic — pin it with a test.
- **`EmptyStateView` ticker:** any widget test landing on an empty/error state must end with `pumpAndSettle()`.
- **`pumpRihlaApp` tests must NOT `pumpAndSettle` after the helper** (ConnectivityNotifier timer). Use targeted `pump`s; only `pumpAndSettle` when an EmptyStateView entrance is in play and the connectivity timer isn't (follow existing patterns in `event_command_center_test.dart`).
- **Theme purity is CI-only:** run `bash tool/check_theme_purity.sh` locally before pushing. Copying styled blocks into the new header/tab bar drops justification comments — re-add them.
- **`prefer_const_constructors` fails CI** — mark const-eligible literals.
- **Removed UI = grep the tests for its labels** and delete obsolete assertions, don't patch around them. Removed surfaces: day badge ("Day 3 of 7"), "Add the first expense" dashed CTA, ledger summary strip ("· 1 expense", "CAMPING TOTAL" strip form), hub breakdown rows ("owes you" rich text in hero), roster strip cards.
- **Keep `EventKeys.closedBanner` + `EventKeys.closedBannerViewReceipt`** (test-pinned, #708). "View receipt →" now switches to the Recap tab instead of pushing `/recap`.
- **`flutter_animate` / `AnimatedSize` in the collapsing header:** keep the animation driven by plain implicit animations with fixed durations so widget tests can `pump(duration)` deterministically.
- **RTL:** back arrow via `DirectionalIcon`/existing flip pattern; all new padding `EdgeInsetsDirectional`.

---

### Task 0: Branch

```bash
git fetch origin main
git checkout -b feat/758-tabbed-event-view origin/main
```

(Current checkout sits on `feat/204-departed-payer-review-trigger` — PR #786 is open; do not touch it.)

---

### Task 1: `ActivityFeedScreen` embedded mode

**Files:**
- Modify: `lib/features/activity/screens/activity_feed_screen.dart`
- Test: `test/features/activity/activity_feed_screen_test.dart` (add group)

**Step 1: Failing test** — pump `ActivityFeedScreen(groupId:…, eventId:…, embedded: true)` inside a bare `MaterialApp` host (mirror the file's existing harness): expect `find.byKey(ActivityKeys.screen)` (or the feed list) present and the top-bar title/back **absent** (`find.byType(Scaffold)` scoped-to-screen absent — assert no `_TopBar` by its visible text/tooltip).

**Step 2: Run** — fails (no `embedded` param).

**Step 3: Implement** — add `final bool embedded` (default false). In `build`: extract the current `Column` children below `_TopBar` into a local `feed` widget; return

```dart
if (widget.embedded) return feed;            // content only, host owns chrome
return Scaffold(... SafeArea(Column([_TopBar(...), Expanded(feed)])));
```

Keep the `ScrollController` + pagination untouched.

**Step 4: Run test group + the file's existing tests** — pass.

**Step 5: Commit** — `feat(events): activity feed gains embedded mode (#758)`

---

### Task 2: `SettleUpScreen` embedded mode

**Files:**
- Modify: `lib/features/ledger/screens/settle_up_screen.dart`
- Test: `test/features/ledger/settle_up_screen_test.dart` (add group)

**Step 1: Failing test** — pump embedded variant with the file's existing provider-override harness: expect `SettleUpPageBody` renders and `settleUpTitle` top bar absent.

**Step 2–3:** add `final bool embedded` (default false). Every `return Scaffold(...)` branch (loading / event-null / group-null / data) gets an embedded twin that returns just the inner content (loading skeleton / EmptyStateView / the `Column(OfflineBanner…Expanded(when))` **minus** `_SettleUpTopBar`, Scaffold, SafeArea — and minus `OfflineBanner` in embedded mode, the shell hosts one). Factor the four bodies into small `Widget _body(...)` helpers so route and embedded modes compose the same content — **do not move any `_recordSettlement`/`_showRecordPaymentSheet`/`_freshOutstandingForPair` logic.**

**Step 4:** run the whole settle test suite:
`flutter test test/features/ledger/settle_up_screen_test.dart test/features/ledger/settle_up_revalidation_test.dart test/features/ledger/settle_up_currency_test.dart test/features/ledger/settle_up_screen_same_name_test.dart` — green.

**Step 5: Commit** — `feat(events): settle-up screen gains embedded mode (#758)`

---

### Task 3: `LedgerScreen` embedded mode

**Files:**
- Modify: `lib/features/ledger/screens/ledger_screen.dart`
- Test: `test/features/ledger/ledger_screen_test.dart` (add group)

Embedded panel = **trip caption + category strip + day cards + end-of-ledger footer + empty states**. Omitted when embedded: `_CoverHeader`, `OfflineBanner` sliver, `LedgerHeroStatement`, `LedgerRosterStrip`, `LedgerStickyCta` (FAB + Settle tab replace them; balance lives in the shell header).

**Step 1: Failing test** — embedded variant shows a seeded expense row and does NOT show the hero statement / sticky CTA / cover header (assert by existing keys/labels used in `ledger_screen_test.dart`).

**Step 2–3:** thread `embedded` from `LedgerScreen` → `_Body`; wrap the omitted slivers in `if (!embedded)`; in embedded mode return the bare `CustomScrollView` (no `Column`+CTA). Category-filter state stays in `_LedgerScreenState`.

**Step 4:** run `flutter test test/features/ledger/` — green (standalone behavior byte-identical).

**Step 5: Commit** — `feat(events): ledger gains embedded mode (#758)`

---

### Task 4: `EventRecapScreen` embedded mode

**Files:**
- Modify: `lib/features/events/screens/event_recap_screen.dart`
- Test: `test/features/events/event_recap_screen_test.dart` (add group)

**Step 1: Failing test** — embedded variant renders recap content without the back button (`EventKeys.recapBackButton` absent) while the share affordance survives.

**Step 2–3:** add `embedded`; in `_wrap`, when embedded skip Scaffold/SafeArea and render the header `Row` with `Spacer()+trailing` only (no back button). Loading/empty/not-found branches reuse `_wrap` so they inherit the same treatment.

**Step 4:** recap tests green.

**Step 5: Commit** — `feat(events): recap gains embedded mode (#758)`

---

### Task 5: l10n keys

**Files:**
- Modify: `lib/l10n/app_en.arb`, `lib/l10n/app_ar.arb`

Add (names final at implementation, reuse existing keys where they exist — check first with grep):
- `eventTabExpenses` ("Expenses"), `eventTabSettle` ("Settle up" — reuse `settleUpTitle` if identical), `eventTabActivity` ("Activity" — reuse `activityTitle` if identical), `eventTabRecap` ("Recap")
- `eventHeaderYourBalance` ("YOUR BALANCE") — only if the hub's existing overline keys ("YOU ARE OWED"/"YOU OWE"/"All settled"/"Nothing to settle yet") don't already cover the header states; prefer reusing the hub's exact state copy so tests keep matching.

Run `flutter gen-l10n` (or build) to regenerate. Commit with Task 6.

---

### Task 6: The tabbed shell (`EventCommandCenter` rebuild)

**Files:**
- Modify: `lib/features/events/screens/event_command_center.dart` (rewrite `_Content` + delete dead widgets)
- Modify: `lib/features/events/keys/event_keys.dart` (add `tabBar`, `tabExpenses`, `tabSettle`, `tabActivity`, `tabRecap`, `addExpenseFab`, `balanceHeader` keys)
- Test: `test/features/events/event_command_center_test.dart` (rewrite), new `test/features/events/event_tabs_test.dart`

**Structure** (replaces `_Content`'s CustomScrollView):

```dart
class _Content extends ConsumerStatefulWidget { ... }   // needs tab + collapse state

// build():
Column(
  children: [
    _EventHeader(            // compact paper header — NO cover art (mockup)
      event: event,
      collapsed: _collapsed,
      myLines: myLines,      // same derivation as today: ledgerViewProvider → myNetByCurrency → nonZeroNetsGccFirst
      state: state,          // reuse _resolveState (KEEP it and myLines derivation; delete breakdown)
      onBack: ...,           // nested route: if (canPop) pop  (#243 — bare pop, no /home fallback)
      onSearch: ...,         // showLedgerSearchSheet(context, expenses:…, settlements:…, …maps from `view`)
      onSettings: () => push('/group/$gid/event/$eid/settings'),
    ),
    if (event.isClosed) _ClosedBanner(  // KEEP keys; onViewReceipt: switch to Recap tab
      onViewReceipt: expenses.isEmpty ? null : () => setState(() => _tab = _EventTab.recap)),
    const OfflineBanner(),
    _EventTabBar(tabs: [...3 or 4...], active: _tab, onSelect: ...),   // pill segmented bar per mockup
    Expanded(
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) { if (n.depth == 0 && n.metrics.axis == Axis.vertical) setCollapsed(n.metrics.pixels > 20); return false; },
        child: _LazyIndexedStack(   // builds a panel on first activation, keeps it alive after
          index: _tab.index,
          children: [
            LedgerScreen(groupId:…, eventId:…, embedded: true),
            SettleUpScreen(groupId:…, eventId:…, embedded: true),
            ActivityFeedScreen(groupId:…, eventId:…, embedded: true),
            if (event.isClosed) EventRecapScreen(groupId:…, eventId:…, embedded: true),
          ],
        ),
      ),
    ),
  ],
)
// Scaffold gains: floatingActionButton: event.isClosed ? null : FAB('+ Add expense') → push('.../ledger/add')
```

Details:
- `_EventHeader`: title row (back · eyebrow `TYPE · date-range` + event name · compact per-currency amount(s) shown only when collapsed · search icon · settings icon). Balance block below (overline state label + big `RAmount` per currency line), wrapped in `AnimatedSize`+`ClipRect` and hidden when `_collapsed`. Reuse hub state copy for empty/settled/owed/owe/mixed.
- `_LazyIndexedStack`: tiny local widget — `children` built as `_built[i] ? child : SizedBox.shrink()`, marking `_built[activeIndex] = true` on activation; wraps a plain `IndexedStack` so panel state (pagination, filters) survives switching. If `event.isClosed` flips false→true live, the recap child simply appears as a 4th entry (index math: keep `_EventTab.recap` last; if active tab is recap and event reopens, snap `_tab` back to expenses).
- **Delete** (now dead): `_BalanceHero`, `_BalanceWithBreakdown`, `_BalanceQuiet`, `_BreakdownRow`, `_breakdownFor`, `_BreakdownEntry`, `_LedgerSummaryStrip`, `_RecentExpensesSection`, `_RecentList`, `_RecentRow`, `_AddFirstExpenseCard`, `_DashedBorderBox`, `_DashedBorderPainter`, `_RosterStrip`, `_RosterPersonCard`, `_CoverHeader`, `_DayBadge`, and the `CoverArt`/`RAvatar` imports if unused. Keep `_ClosedBanner`, `_Overline` (if header reuses it), `_LoadingState`/`_ErrorState`/`_NotFoundState`, `_resolveState`, `_HubState`.
- Keys: attach `EventKeys.*` to tab bar buttons + FAB + header for tests.

**Step 1: Write the new tests first** (`event_tabs_test.dart`), red:
1. default tab = Expenses (a seeded expense row visible; `SettleUpPageBody` absent)
2. tap Settle tab → `SettleUpPageBody` appears; Expenses panel retained (IndexedStack) but hidden
3. tap Activity tab → feed renders
4. Recap tab absent when open event; present when `isClosed`
5. FAB present + routes to `/ledger/add` when open; **absent** when closed (#723)
6. closed banner "View receipt" switches to Recap tab (recap content appears, no route push)
7. #204 pin: with a review-worthy expense seeded, the review sheet does NOT appear on event open, DOES appear on first Settle tab activation
8. header balance: multi-currency event renders one line per currency (never a summed amount)

**Step 2:** run — all red (missing widgets/keys).

**Step 3:** implement shell + l10n (Task 5) until green.

**Step 4:** rewrite `event_command_center_test.dart`: drop day-badge/dashed-CTA/summary-strip/breakdown/roster assertions; keep & adapt: empty-state copy, settled copy, YOU ARE OWED/YOU OWE overlines (now in header), #261 currency rendering, #723 closed banner + frozen add (now: FAB absent), back-button behavior, event-type total caption test moves to embedded-ledger context if still relevant. Update `event_command_center_same_name_test.dart` + `recap_settle_cta_nav_test.dart` to the new surfaces.

**Step 5:** `flutter test test/features/events/ test/features/ledger/ test/features/activity/` — green.

**Step 6: Commit** — `feat(events): tabbed event view — Expenses · Settle up · Activity · Recap (#758)`

---

### Task 7: Collapse-on-scroll polish

Already wired structurally in Task 6 (NotificationListener + AnimatedSize). Here: tune threshold/durations, compact-amount fade-in, verify no jank with the ledger's `CustomScrollView` and settle's `SingleChildScrollView` both bubbling depth-0 notifications.

**Test:** widget test — drag the Expenses list up past threshold → big balance block gone, compact amount visible in title row; drag back → restored. Switching tabs resets scroll-collapse only if the new panel's offset says so (mockup resets to expanded — on tab switch set `_collapsed=false`).

**Commit** — `feat(events): balance header collapses on scroll (#758)`

---

### Task 8: Sweep + verify

- [ ] `grep -rn "Day .* of \|Add the first expense\|ledgerCard\|dayBadge" test/ lib/` — no orphaned assertions/keys; delete unused `EventKeys` entries
- [ ] `flutter analyze` — clean
- [ ] `flutter test` — full suite green
- [ ] `bash tool/check_theme_purity.sh` — clean
- [ ] `git diff main...HEAD --stat -- lib/core/router/ security/ functions/ lib/features/ledger/providers/ '**/models/'` — **empty** (Gate-exempt claim holds; embedded flags live in screens/, not models/)
- [ ] Run the app (`flutter run --dart-define-from-file=config.json`), walk: group → event → tabs, scroll collapse, settle record, closed event → Recap tab + receipt, deep link `/group/:gid/event/:eid/ledger` still lands on standalone ledger
- [ ] Security checklist: no secrets, no new inputs (display-only), no auth surface

### Task 9: PR

- Branch pushed with `-u`; PR body: `Closes #758`, spec line pointing at this plan, mockup link, decisions recorded (Mark received leads / Recap tab in-PR / search behind icon), note the #204 review-sheet timing change.
- Full-branch diff review (`git diff main...HEAD`), then `/automerge`.
