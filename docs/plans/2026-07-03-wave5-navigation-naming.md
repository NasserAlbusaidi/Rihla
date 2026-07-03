# Wave 5 — Navigation & Naming (#818) Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Ship the three signed-off Wave-5 items — 5.1 bottom-tab rename to "History", 5.2 the home bell selects the Activity tab instead of pushing `/activity`, 5.3 a standalone event settle-up entry point to the Trip Receipt export.

**Architecture:** Three independent PRs. 5.1 is a copy-only ARB value change plus one new l10n key for the tab's own screen header. 5.2 introduces an `InheritedWidget` tab-select channel on `BottomNavShell` (state stays private in the shell; both side effects centralized) and rewires the two home entry points; the `/activity` route is untouched. 5.3 adds an optional `footer` slot to the shared `SettleUpPageBody` and a nav-only CTA from the standalone event settle-up to the existing recap route.

**Tech Stack:** Flutter 3.x, Riverpod 2 (no codegen), GoRouter 13 declarative, gen-l10n with committed generated files.

**Sign-off:** All three items approved 2026-07-03 (product sign-off recorded in session). 5.2 is Gate-category (routing/back-behavior surface) — run `/run-the-gate` on §PR-3 before writing its code.

**PR packaging & order:**
- **PR-1 (5.1, EXEMPT-expected):** ARB rename + header key + fixtures. Ships this plan doc.
- **PR-2 (5.3, EXEMPT-expected):** settle-up → recap CTA. Parallel with PR-1 (disjoint lib files; ARB regions differ — rebase + `flutter gen-l10n` on conflict).
- **PR-3 (5.2, Gate):** bell → tab. **After PR-1 merges** (shared test fixtures tap the tab by label).

Every PR: `Refs #818` in the COMMIT body (partial delivery — squash inherits commit bodies, not PR bodies), RED evidence pasted in the PR body, `/automerge` classification.

**Verification-principles record (run while authoring, 2026-07-03):**
1. Callsite classification: no money/write path touched anywhere in Wave 5. The only write is 5.2's `activitySeenProvider.markSeenNow()` (SharedPreferences display-state; read back only by `activityUnreadProvider` — read-path named).
2. Every file:line below re-verified by fresh grep/Read in-session against `d25c2c90` (post-#834 main), not trusted from the mapper agents.
3. Read-path per write-path: seen-stamp → unread dot (above). No schema/field changes.
4. Contracts spelled exactly: `selectTab(int index)`, `footer: Widget?`, key names and ARB keys literal below.
5. Orthogonal axis: deep-link/direct-entry — `/activity` route stays (pinned by `test/unit/app_router_test.dart:95`), cold-entry back-guard behavior unchanged, `showBack:true` mode still exercised by `cross_group_activity_screen_test.dart`.

---

## PR-1 — 5.1 Tab rename "Activity" → "History"

The bottom tab label is driven solely by l10n key `homeBottomNavActivity` (sole lib consumer: `lib/features/home/widgets/bottom_nav_shell.dart:174`). Rename is **value-only — the key name stays** (renaming the key would touch `integration_test/golden_path_arabic_test.dart:124`, which finds by key and self-updates on a value change).

**Scope addition (flagged):** the tab's own landing screen header (`lib/features/home/screens/cross_group_activity_screen.dart:436`) currently reads shared key `activityTitle` ("Activity"). A "History" tab landing on an "Activity"-titled screen re-creates the confusion this item kills, and 5.2 sends more traffic there. Mint a **new** key `historyTabTitle` for that one header. **Never edit `activityTitle` itself** — it is the shared fallback title for `lib/features/activity/screens/activity_feed_screen.dart:136` (per-event) and `lib/features/groups/screens/group_activity_screen.dart:149` (per-group), which keep "Activity" per the sign-off.

**Out of scope — do not touch:** `activityTitle` values, `activityCaption` (feed eyebrow), `activitySubtitle` (cross-group subtitle stays), `groupActivity` (group overflow item), `eventTabActivity` (per-event tab), `homeQuickActivity` (dead key — leave; cleanup ticket with `profileAnonymousTraveller`), `test/helpers/test_router.dart:135` route-stub text, `test/features/group_detail_screen_test.dart:610`, `test/features/groups/group_detail_navigation_test.dart:204`.

**Files:**
- Modify: `lib/l10n/app_en.arb:1529` (`homeBottomNavActivity` value), new `historyTabTitle` entry
- Modify: `lib/l10n/app_ar.arb:556` (value), new `historyTabTitle` entry
- Modify: `lib/features/home/screens/cross_group_activity_screen.dart:436`
- Regenerate + commit: `lib/l10n/generated/app_localizations{,_en,_ar}.dart`
- Modify (fixtures): `test/features/home/widgets_test.dart:181-231`, `test/features/home/home_screen_dashboard_test.dart:474`, `test/features/home/home_screen_groups_test.dart:362-379`, `test/features/home/cross_group_activity_screen_test.dart:199,655`, `integration_test/golden_path_arabic_test.dart:136`
- Add: this plan doc (`docs/plans/2026-07-03-wave5-navigation-naming.md`)

### Task 1.1: RED — update fixtures to expect "History"

**Step 1:** Edit the five tab-label assertions to the new values:
- `widgets_test.dart:194` → `orderedEquals(['Groups', 'History', 'Profile'])`
- `widgets_test.dart:212` → `orderedEquals(['المجموعات', 'السجل', 'الملف'])`
- `widgets_test.dart:224` → `await tester.tap(find.text('History').last);`
- `home_screen_dashboard_test.dart:474` → `expect(find.text('History'), findsWidgets);`
- `home_screen_groups_test.dart:376` → `expect(find.text('History'), findsWidgets);`
Plus the two header assertions: `cross_group_activity_screen_test.dart:199` and `:655` → `find.text('History')`. Update test *names* mentioning the old label (`widgets_test.dart:181/:216`, `home_screen_groups_test.dart:362`) for honesty.
And `integration_test/golden_path_arabic_test.dart:136` → `find.text(ar.historyTabTitle)` (key-driven; compiles RED until the key exists).

**Step 2:** Run: `flutter test test/features/home/widgets_test.dart test/features/home/home_screen_dashboard_test.dart test/features/home/home_screen_groups_test.dart test/features/home/cross_group_activity_screen_test.dart`
Expected: FAIL — labels still "Activity"/"النشاط". Capture output for the PR body.

### Task 1.2: GREEN — flip the values

**Step 1:** `app_en.arb`: `"homeBottomNavActivity": "History"`; add `"historyTabTitle": "History"` (+ `@historyTabTitle` description "Header of the cross-group History tab screen"). `app_ar.arb`: `"homeBottomNavActivity": "السجل"`; add `"historyTabTitle": "السجل"`.

**Step 2:** `cross_group_activity_screen.dart:436` → `context.l10n.historyTabTitle`.

**Step 3:** Run `flutter gen-l10n`; commit the regenerated files (checked-in by convention — #245 trap).

**Step 4:** Re-run the Task-1.1 test set. Expected: PASS.

### Task 1.3: Verify + ship

**Step 1:** `flutter analyze` (clean) → `flutter test` (full) → `bash tool/check_theme_purity.sh` (PASS).
**Step 2:** Commit `fix(l10n): bottom tab Activity → History (#818 Wave 5.1)` with body naming the header-key scope addition + `Refs #818`. Push, PR with RED evidence, `/automerge`.

---

## PR-2 — 5.3 Settle-up entry to Trip Receipt export

**Scoping facts (verified):** the Trip Receipt is **event-scoped only** — `tripReceiptProvider = Provider.autoDispose.family<AsyncValue<TripReceipt>, EventRef>` (`lib/features/events/providers/trip_receipt_provider.dart:54-55`); zero group-receipt code exists in lib/ (grep `GroupReceipt|groupReceipt` = 0); #704 stays open for the group-scoped pack. Therefore:
- **Group settle-up screen gets NO entry point** (nothing to link to). Named non-goal.
- **Embedded event settle-up** (`SettleUpScreen(embedded: true)` inside the tabbed `EventCommandCenter`) gets NO entry point — the Recap tab sits in the same tab strip one tap away, and `_chrome` (settle_up_screen.dart:113-133) renders no top bar there anyway.
- **Standalone event settle-up** (route `/group/:gid/event/:eid/ledger/settle-up`, reachable from the #721 recap CTA and elsewhere) is the surface that gains the entry.

**Mechanism — nav-only, mirroring #721 in reverse:** push the existing recap route `'/group/$gid/event/$eid/recap'` (`app_router.dart:403-408`, nested under `/group/:gid` so back pops straight back to settle-up per #243 semantics). No direct `showRecapShareSheet` open (would drag `eventRecapProvider` + `ledgerViewProvider` watches into settle-up). Export stays owned by the recap screen. `tripReceiptProvider` stays autoDispose-fresh — no pre-warming.

**Copy trap (#359):** the shared body's payment history already renders a "Share receipt" TextButton (`settle_up_page_body.dart:1131-1166`, `GroupKeys.settleUpShareReceiptButton`) — a plain-text single-payment share. The new CTA must not say "receipt": copy is **"View recap & export"** / AR **"عرض الملخّص والتصدير"**, new key `settleUpViewRecapCta`.

**Files:**
- Modify: `lib/features/groups/widgets/settle_up_page_body.dart` — add `final Widget? footer;` ctor param (default null), rendered after `_PaymentHistorySection` and before the `bottomInset` spacer in the scroll column (layout order at :303-344)
- Modify: `lib/features/ledger/screens/settle_up_screen.dart` — build the footer CTA only when `!widget.embedded && expenses.isNotEmpty` (screen already watches `eventExpensesProvider`); handler = `HapticService.lightClick();` then `GoRouter.of(context).push('/group/${widget.groupId}/event/${widget.eventId}/recap')`
- Modify: `lib/features/ledger/keys/ledger_keys.dart` — add `settleUpRecapCta = Key('settle_up_recap_cta')`
- Modify: `lib/l10n/app_en.arb` + `app_ar.arb` — `settleUpViewRecapCta` (+ regenerated files)
- Test: `test/features/ledger/settle_up_screen_test.dart` (extend) — and one absent-assertion in `test/features/groups/group_settle_up_screen_test.dart`

Gate on `expenses.isNotEmpty` only — do NOT copy the command-center's `!event.isClosed` conjunct (`event_command_center.dart:194`); it hides `onRecap` there because the closed banner supplies its own recap entry. A closed event's standalone settle-up should still reach the recap/export.

### Task 2.1: RED — new tests first

**Step 1:** In `settle_up_screen_test.dart` add (using the file's existing standalone + embedded pump helpers):
- "standalone shows the recap CTA and navigates": pump standalone with a non-empty ledger, `expect(find.byKey(LedgerKeys.settleUpRecapCta), findsOneWidget)`; tap; assert the router landed on the recap route (the file's router harness pattern; recap route stub if needed).
- "embedded hides the recap CTA": pump embedded → `findsNothing`.
- "empty ledger hides the recap CTA": standalone, no expenses → `findsNothing`.
In `group_settle_up_screen_test.dart`: one assertion `find.byKey(LedgerKeys.settleUpRecapCta)` → `findsNothing` in the loaded-data test.

**Step 2:** Run: `flutter test test/features/ledger/settle_up_screen_test.dart` → FAIL (key not defined / CTA absent). Capture RED output. (Key compile error is acceptable RED for a new affordance.)

### Task 2.2: GREEN — implement

**Step 1:** Add `LedgerKeys.settleUpRecapCta`; ARB keys EN+AR; `flutter gen-l10n`, commit generated.
**Step 2:** `settle_up_page_body.dart`: add `footer` param; render `if (footer != null) footer!` after the payment-history section, inside the scroll, before the bottom-inset spacer. Use `EdgeInsetsDirectional` for any padding (RTL).
**Step 3:** `settle_up_screen.dart` data branch: pass `footer:` an `OutlinedButton.icon` (icon `Iconsax.document_text`, label `context.l10n.settleUpViewRecapCta`, key `LedgerKeys.settleUpRecapCta`) wrapped in padding, built only when `!widget.embedded && expenses.isNotEmpty`; handler as above (lightClick + push recap route). Group screen passes nothing (param defaults null).
**Step 4:** Re-run Task-2.1 tests → PASS.

### Task 2.3: Verify + ship

**Step 1:** `flutter analyze` → full `flutter test` → `bash tool/check_theme_purity.sh` (new styled widget — the copied-block justification trap).
**Step 2:** Commit `feat(ledger): recap & export entry from standalone settle-up (#818 Wave 5.3)`, body names the two non-goals (group scope — #704 open; embedded — Recap tab adjacent) + `Refs #818`. Push, PR with RED evidence, `/automerge`.

---

## PR-3 — 5.2 Bell selects the Activity tab (GATE — run `/run-the-gate` on this section first)

> **Gate record:** round 1 (fresh-context Opus, 2026-07-03, vs `d25c2c90`) — **0 P1 / 1 P2 / 1 P3**; stop condition met in one round. Both findings folded in below: the [P2] unread-dot test assertion (badge only exists on the inactive icon — back-to-Groups before reading) and the [P3] `getElementForInheritedWidgetOfExactType` idiom for callback-time lookups.

**Current state (verified):** the bell is `_IconCircle(icon: Iconsax.notification)` in `_TopBar`, key-less, handler `HapticService.lightClick(); context.push('/activity')` (`home_screen.dart:517-523`). A second entry, the journeys `SectionHeader` "View activity" action, also pushes `/activity` (`home_screen.dart:155-158`). Tab state is private to `_BottomNavShellState` (`int _currentIndex` / `Set<int> _visited`, `bottom_nav_shell.dart:45-47`); the ONLY switch path is `NavigationBar.onDestinationSelected` (`:131-145`) which also (a) fires `activitySeenProvider.notifier.markSeenNow()` when `i == 1` (dot clear, pinned by `test/features/home/activity_unread_test.dart:87-135`) and (b) `_visited.add(i)` (lazy-build mount, #113). The bell sits INSIDE the shell's tab-0 subtree (`HomeScreen.build → BottomNavShell(child: _DashboardContent())`, `home_screen.dart:52-61`), so it needs an upward channel — none exists.

**Design:**
1. **Channel = InheritedWidget, state stays in the shell.** New `BottomNavTabScope extends InheritedWidget` (in `bottom_nav_shell.dart`): field `final void Function(int index) selectTab;`, `static BottomNavTabScope? maybeOf(BuildContext c) => c.getElementForInheritedWidgetOfExactType<BottomNavTabScope>()?.widget as BottomNavTabScope?;` (Gate r1 [P3]: `getElement…` not `dependOn…` — the lookup happens inside `onTap` callbacks, not `build`, so no dependency should be registered), `updateShouldNotify => false`. `_BottomNavShellState` extracts a `void _selectTab(int i)` method centralizing BOTH side effects (`if (i == 1) markSeenNow; setState { _currentIndex = i; _visited.add(i); }`) — `onDestinationSelected` becomes haptic + `_selectTab(i)` — and wraps its built Scaffold in `BottomNavTabScope(selectTab: _selectTab, child: …)`. No provider: a lifted `StateProvider` would make tab state app-global (survives across home unmounts) and churn the four test files that construct `BottomNavShell` directly.
2. **Bell:** `onTap: () { HapticService.lightClick(); final scope = BottomNavTabScope.maybeOf(context); if (scope != null) { scope.selectTab(1); } else { context.push('/activity'); } }` — the push fallback keeps the bell functional if `_TopBar` is ever composed outside the shell.
3. **"View activity" journeys action converts identically** (same screen, same destination, same confusion class — one concern). After this, `/activity` has zero in-app callers; **the route STAYS** (deep-link/direct-entry, pinned by `test/unit/app_router_test.dart:95`; `showBack:true` mode still exercised by `cross_group_activity_screen_test.dart:144`).
4. **Keys:** `_IconCircle` gains an optional `Key? key` pass-through (it takes none today, `home_screen.dart:600-622`); new `HomeKeys.activityBell = Key('home_activity_bell')` (`home_keys.dart` — no bell key exists).
5. **Named UX delta (accepted):** bell now lands the TAB (no back affordance — `showBack` stays false; system back behaves like the other tabs, i.e. home/exit semantics) instead of a pushed route that popped back to home. This is the tab paradigm working as designed.
6. **#666 guard:** `CrossGroupActivityScreen` is dual-mode — do NOT touch its `showBack` wiring, do NOT add `PopScope`. No `app_router.dart` changes at all.
7. **Unread parity:** bell taps route through `_selectTab(1)` → `markSeenNow` fires → dot clears, same as a nav tap. (The screen's own `initState` markSeenNow only covers FIRST mount; the tab stays mounted after.)

**Files:**
- Modify: `lib/features/home/widgets/bottom_nav_shell.dart` (scope widget + `_selectTab` extraction)
- Modify: `lib/features/home/screens/home_screen.dart` (bell handler :517-523, journeys action :158, `_IconCircle` key param :600-622)
- Modify: `lib/features/home/keys/home_keys.dart` (`activityBell`)
- Test: `test/features/home/widgets_test.dart` or new `test/features/home/bell_tab_select_test.dart`; `test/features/home/activity_unread_test.dart` (extend)

No ARB changes (bell has no visible copy; semantics label out of scope).

### Task 3.0: Gate

Run `/run-the-gate` on this section (fresh-context Opus, zero session history). Apply P1s, re-run with a NEW subagent until 0 P1s. Only then code.

### Task 3.1: RED — new tests first

**Step 1:** New tests (home boot-helper contracts: override `sharedPreferencesProvider`, never `pumpAndSettle` after `pumpRihlaApp`, but DO settle/drain when landing on the Activity tab's `EmptyStateView` — `activity_unread_test.dart` shows the dance):
- "bell selects the Activity tab": pump `HomeScreen`, tap `HomeKeys.activityBell` → `NavigationBar.selectedIndex == 1`, `CrossGroupActivityScreen` visible, **no back affordance** (tab mode), router location unchanged (no `/activity` push).
- "bell tap clears the unread dot": seed unread state (pattern from `activity_unread_test.dart`), tap bell, **then switch back to the Groups tab before reading the badge** — while Activity is selected, `NavigationBar` renders `selectedIcon` (no `Badge`), so `find.byKey(HomeKeys.activityUnreadBadge)` finds 0 widgets and the naive assertion throws (Gate r1 [P2]; the existing pinning test does exactly this back-to-Groups dance at `activity_unread_test.dart:119-126`). Then assert `isLabelVisible == false`. (Alternative: assert `activityUnreadProvider` reads `false` via the container.)
- "journeys View-activity action selects the tab": same assertions via the section-header action.

**Step 2:** Run → FAIL (`HomeKeys.activityBell` undefined → compile RED). Capture output.

### Task 3.2: GREEN — implement

Steps: add key + `_IconCircle` key param → `BottomNavTabScope` + `_selectTab` in the shell → rewire both handlers → re-run new tests (PASS) → `flutter test test/features/home/ test/unit/app_router_test.dart` (no regressions, route still pinned).

### Task 3.3: Verify + ship

`flutter analyze` → full suite → theme purity. Commit `feat(home): bell and View-activity select the History tab (#818 Wave 5.2)` + body naming the UX delta + `Refs #818`. Push, PR with RED evidence + `Spec:` line pointing at this doc, `/automerge` (classifier decides; review rounds expected if gated).

---

## After all three merge

Fresh-context re-grade per `docs/plans/2026-07-03-a-plus-grade-sprint.md` (zero would-quit findings, every dimension ≥ B+).
