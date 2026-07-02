# #364 Persistent Add-expense FAB with flattened event picker — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.
> **Gate:** This spec MUST pass `/run-the-gate` (fresh-context Opus review) BEFORE Task 2.1 — the issue pins "Spec + Gate (routing surface) before implementation". Note the change adds NO route and NO write path; the routing surface is new `context.push` call sites into an existing route.

**Goal:** Logging a spend takes 3+ taps today (home → group → event → Ledger tab → add). A persistent FAB on the Groups/Activity tabs opens a one-sheet flattened picker of open events across all groups (ongoing-first); tapping a row pushes the existing `/group/:gid/event/:eid/ledger/add`. When exactly one open event exists anywhere, the sheet is skipped — true 1-tap add for the #245 new-user shape.

**Design sign-off:** user picked V4 (flattened sheet) + fast path on 2026-07-02; gallery updated at `docs/design/mockups/364-add-expense-fab-picker.html` (V4 = pick; V1/V2/V3 kept as record; edge-states block added).

**Gate record:** round 1 (fresh-context Opus, 2026-07-02) — **0 P1 / 1 P2 / 2 P3**; stop condition met. All findings folded in: D-4 gained the participation filter (`uid ∈ participantIds`, the identity/scope axis the author's own principle-7 pass missed); D-5 spells out the FAB-while-loading contract; D-4's `ledger_screen.dart` cite corrected to :422.

**Tech stack:** Flutter/Riverpod client only. No Firestore writes, no rules, no Functions, no router-table change, no money math.

---

## Decisions

| # | Decision | Choice | Why | Rejected |
|---|---|---|---|---|
| D-1 | Picker resolution | **V4 flattened events sheet** — one sheet, every open event across every group, home journey-strip priority order (ongoing → upcoming → recently ended → undated) | Likely target is row one; no new persistence; never silently files into the wrong event; data comes from streams the always-mounted home tab already holds live (zero new listeners) | V2 last-active quick add (needs a NEW SharedPrefs pointer — nothing tracks last-active today; stale pointer silently mis-files); V1 two-step-always (one tap slower every time); V3 speed-dial (scales badly, two flows to build) |
| D-2 | Fast path | **totalOpen == 1 → skip sheet, push add directly** | Add editor's existing `_WhereCard` shows event name + date (`expense_editor_body.dart:1504-1507`) — target is visible, no new UI. Counted over ALL open events (not the window-capped list) so the skip never hides a valid alternative. Gated on every group's event stream having resolved (see D-5) | Always show the sheet (one wasted tap for the single-event majority post-#245) |
| D-3 | FAB scope | **Groups + Activity tabs; hidden on Profile** (`_currentIndex != 2`) | Issue text. Profile is settings — a money CTA there is noise. The `/activity` top-level ROUTE entry (showBack) renders `CrossGroupActivityScreen` without the shell → no FAB there, which is correct (FAB is shell chrome) | FAB on all three tabs |
| D-4 | Open-event definition | **`!isDeleted && !isClosed && event.participantIds.contains(uid)`** | Closed: mirrors the existing add gates — `LedgerStickyCta` disables add on closed (`ledger_screen.dart:422`), and `AddExpenseScreen` hard-blocks closed with `_ErrorScaffold` (`add_expense_screen.dart:171-176`, #723). Participation (Gate rd-1 P2): `validExpenseCreate` requires `isEventParticipant` (`security/firestore.rules:718-720`) — a group member excluded from an event's roster (`create_event_screen.dart` subset picker) would submit into a clean `permission-denied`; the picker must only offer events the uid can actually write to. uid from `currentUserIdProvider` | Include closed/non-participant rows disabled (dead rows are clutter) |
| D-5 | Loading semantics | **Sheet is always safe to open; fast path requires `allResolved`** (every group's `groupEventsProvider` has a value). Unresolved group streams are swallowed from the list (same semantics as `activeJourneysProvider`). FAB tap while the provider is still `AsyncLoading` (groups unresolved) → open the sheet, which renders a loading body (Gate rd-1 P3: the cold-start `userGroupsProvider` false-empty race can briefly read `totalOpen==0`; the worst case is a transient empty/loading sheet — never a wrong fast-path push, since `sole` requires `allResolved` on real data) | A fast-path decision on partial data could skip the sheet while a second open event is still loading → mis-target. Sheet on partial data is harmless (browse-all covers anything missing) | Block the FAB until resolved (dead button on cold start) |
| D-6 | Empty states | **Zero groups → sheet explains + "Create a group" (`context.push('/create-group')`; #245 seeds a ledger event, so the next FAB tap hits the fast path). Groups but zero window-active open events → sheet opens directly on the browse-all group list** | Keeps the FAB always tappable and self-explanatory | Hide the FAB when empty (undiscoverable; inconsistent chrome) |
| D-7 | Browse-all fallback | **Footer row "Browse all groups ›" switches the sheet in place to: group list (with open-event counts) → tapped group's open events → push. A group with exactly ONE open event skips its event page** | Covers the long tail (open events outside the 60d/14d active window; many-group users) without burdening the common case | Uncapped flattened list only (an old undated-but-open event would be unreachable if we capped; an uncapped list with 30 events is unusable) |
| D-8 | Provider placement | **New `addExpenseTargetsProvider` colocated in `active_journeys_provider.dart`** | Reuses the private `_isActive` window + `_priority` sort in place — no export, no duplication, and the two flatten passes stay side by side so they can't drift | New file in ledger feature (would need to export/duplicate `_isActive`/`_priority`); reusing `activeJourneysProvider` itself (caps at 5 via `entries.take(5)`, carries balance `nets` the picker doesn't need, and `ActiveJourneyEntry` lacks `isClosed`/`groupName`) |
| D-9 | FAB form | **Circular icon FAB (`Icons`/Iconsax add), l10n tooltip** | Matches gallery; less chrome over content than an extended FAB. Theme already carries `FloatingActionButtonThemeData` (`app_theme.dart:147`) | Extended "＋ Expense" FAB |

## Verification notes (7 principles, run 2026-07-02 against `main`)

1. **Callsite classification:** everything new is INBOUND/display+navigation. The picker performs **zero writes**; the only write path touched by the user journey is the pre-existing `AddExpenseScreen._handleSubmit`, which is not modified and already bumps `ledgerRevisionProvider` (`add_expense_screen.dart:88`) — the CLAUDE.md "new expense write path must bump" rule is not triggered because no new write path is created.
2. **Claims verified against code:**
   - Target route exists and is built from path params only: `AppRoutes.eventLedgerAdd = '/group/:gid/event/:eid/ledger/add'` (`app_router.dart:55`), builder reads `state.pathParameters` (`app_router.dart:334-344`). No `state.extra` anywhere in this plan. Cold deep-link into that path already works today — unchanged.
   - No FAB exists anywhere in `lib/` (grep `FloatingActionButton` hits only the theme, `app_theme.dart:147`). `HomeKeys.createGroupFab` is a legacy-named Key on a `SectionHeader` action + empty-state `ElevatedButton` (`home_screen.dart:165,296`) — not a floating button; no collision.
   - `BottomNavShell` is a single `Scaffold` with Stack/AnimatedOpacity tabs and `_currentIndex` state (`bottom_nav_shell.dart:41-91`) — one `floatingActionButton:` slot serves all tabs; hide on index 2.
   - `activeJourneysProvider` flattens `userGroupsProvider` × `groupEventsProvider(gid)`, filters `!isDeleted && _isActive`, sorts by `_priority`, caps 5 (`active_journeys_provider.dart:154-213`) and does **not** filter `isClosed` — confirming the picker needs its own filter and its own provider (D-8).
   - `_isActive` window: ongoing; upcoming ≤60d; ended ≤14d; undated always (`active_journeys_provider.dart:67-99`).
   - Closed-add is blocked at the editor: `add_expense_screen.dart:161-176` watches `eventDetailProvider`, renders `_ErrorScaffold(editorEventClosedTitle)` when `isClosed` (#723). The FAB path lands on the same screen → same guard.
   - `Event` carries `isClosed` (`event_model.dart:98`, default false at `:126`, parsed `data['isClosed'] == true` at `:175`) and `isDeleted` (existing journey filter uses it).
   - `Group.name` exists (`group_model.dart:13`) for the row subtitle; `Event.name` for the row title (already used by `ActiveJourneyEntry.title`).
   - `/create-group` route exists (`AppRoutes.createGroup`, `app_router.dart:42,169`).
   - No existing "ongoing / in Xd" l10n strings (grep `app_en.arb`) → new keys required, en + ar.
3. **Read-path per write-path:** n/a — this change introduces no data write. The only writes are the two ARB files, whose read-path is the regenerated `AppLocalizations` (commit the generated files — #245 trap).
4. **Fields enumerated from the type:** `AddExpenseTarget` consumes from `Event` (`event_model.dart`): `id`, `name`, `startDate`, `endDate`, `createdAt`, `isDeleted`, `isClosed`; from `Group`: `id`, `name`. Nothing else — no balances, no currency (the sheet shows no amounts, keeping money math entirely out of scope).
5. **Data contracts spelled out:**
   ```dart
   class AddExpenseTarget {
     final String groupId;   // Group.id
     final String eventId;   // Event.id
     final String eventName; // Event.name
     final String groupName; // Group.name
     final DateTime? startDate;
     final DateTime? endDate;
     final DateTime createdAt;
   }
   class AddExpenseTargets {
     final List<AddExpenseTarget> active; // open (D-4: !deleted ∧ !closed ∧ uid ∈ participantIds) ∧ in _isActive window, _priority-sorted, UNCAPPED
     final int totalOpen;                 // ALL open (D-4) events across all resolved groups (ignores window)
     final AddExpenseTarget? sole;        // non-null iff totalOpen == 1 ∧ allResolved; may lie OUTSIDE the window
     final bool allResolved;              // every group's groupEventsProvider has a value
   }
   final addExpenseTargetsProvider = Provider<AsyncValue<AddExpenseTargets>>(...);
   ```
   Push target string: `'/group/${t.groupId}/event/${t.eventId}/ledger/add'` — identical shape to the two existing call sites (`ledger_screen.dart:425`, `event_command_center.dart:268`).
   FAB tap contract: `sole != null → context.push(addPath(sole))`; else `showModalBottomSheet(AddExpenseTargetSheet)`; sheet row tap = pop sheet + push.
6. **Arithmetic decomposition:** n/a — no money math anywhere in the diff.
7. **Orthogonal adversarial axis (time/lifecycle):** the fix is on the navigation axis; the adversarial example exercises the lifecycle axis — a group whose ONLY event was closed yesterday (#723). The flattened list hides it (D-4); `totalOpen` for that group is 0, so a user with one group and one closed event gets the browse-all group list showing "0 open events" → the row must be disabled/explained, NOT push into a dead event page. Second axis (time): an open undated event created 6 months ago in an otherwise-empty account — outside no window (undated = always active) so it appears; but an open DATED event that ended 20 days ago is outside the window: it must still be reachable via browse-all, and if it is the account's sole open event the fast path must target it (D-2's "counted over ALL open, not window").

**Back/deep-link invariants (issue box 3):** no route added/removed/reordered; `appRouteRedirect` untouched; no `PopScope` anywhere in the diff. `context.push` from the shell adds one page → system back pops to the shell (nested-route rule: `canPop()` true on pushed pages). The editor's success-dialog `Done` does `context.pop(true)` (`add_expense_screen.dart:120`) → lands back on the shell. Cold deep-links into `/group/:gid/event/:eid/ledger/add` behave exactly as today.

---

## Single PR — feat(home): persistent add-expense FAB with flattened event picker (Closes #364)

Branch: `feat/364-add-expense-fab` off `origin/main`. Client-only; Gate-category by path (`lib/core/router/**` NOT touched, but `/automerge` classifier may still route models/routing-adjacent diffs to review — fine).

### Task 1: RED — provider unit tests

**Files:** NEW `test/unit/add_expense_targets_provider_test.dart`

Cases (ProviderContainer with `userGroupsProvider`/`groupEventsProvider` overrides, same harness as existing journey/provider tests):
- filters `isClosed` and `isDeleted` events out of `active` AND out of `totalOpen`
- filters events where `!event.participantIds.contains(uid)` out of `active`, `totalOpen`, and `sole` (Gate rd-1 P2 — a non-participant's submit would `permission-denied` at `validExpenseCreate`)
- priority order: ongoing event sorts before upcoming before undated (reuse journey fixtures)
- `totalOpen` counts an open dated event that ended 20+ days ago (outside window) — `active` excludes it
- `sole` non-null iff `totalOpen == 1` and every group stream resolved; `sole` may be the outside-window event
- one group stream still loading → `allResolved == false`, `sole == null`, other groups' events still listed
- zero groups → `active` empty, `totalOpen == 0`, `allResolved == true`

### Task 2: GREEN — `addExpenseTargetsProvider`

**Files:** Modify `lib/features/home/providers/active_journeys_provider.dart`

Colocate `AddExpenseTarget`, `AddExpenseTargets`, provider. Reuse `_isActive`/`_priority` in place. Same error-swallow semantics as the journeys provider (a group stream error = that group contributes nothing, `allResolved` stays false).

### Task 3: RED — FAB + sheet widget tests

**Files:** NEW `test/features/home/add_expense_fab_test.dart`, NEW `test/features/home/add_expense_target_sheet_test.dart`

- Shell shows FAB on tab 0 and tab 1, hides it on tab 2 (Profile)
- FAB tap with `sole` set → router location becomes the add path, no sheet (pin with a test GoRouter, follow `*_navigation_test.dart` convention)
- FAB tap with 2+ targets → sheet opens; row tap → sheet dismissed, router at add path
- Browse-all: footer tap → group list with open-event counts → group tap → event list → push; single-open-event group skips its event page; zero-open-event group row disabled
- Zero groups → empty sheet, CTA pushes `/create-group`
- Closed event absent from rows (regression pin for D-4)
- RTL smoke: sheet renders under `Directionality.rtl` (chevrons via `DirectionalIcon`, `EdgeInsetsDirectional` only)
- Remember: `pumpRihlaApp` boot helper + `sharedPreferencesProvider` override; NO `pumpAndSettle` after helper; `EmptyStateView`-style tickers drained if used

### Task 4: GREEN — FAB widget, sheet widget, shell wiring

**Files:**
- NEW `lib/features/home/widgets/add_expense_fab.dart` — `ConsumerWidget`; reads `addExpenseTargetsProvider`; fast path vs sheet per contract (5)
- NEW `lib/features/home/widgets/add_expense_target_sheet.dart` — flattened list, in-place browse-all pages (internal page state, no nested Navigator), empty state; timing subtitle "group · ongoing / in Nd / —"
- Modify `lib/features/home/widgets/bottom_nav_shell.dart` — `floatingActionButton: _currentIndex == 2 ? null : const AddExpenseFab()`
- Modify `lib/features/home/keys/home_keys.dart` — `addExpenseFab`, sheet/row keys
- l10n `app_en.arb` + `app_ar.arb` (+ commit regenerated files): FAB tooltip, sheet title/subtitle, ongoing / in-days, browse-all, all-groups title, open-event count (plural), empty title/body. Create-group CTA reuses `homeCreateGroup`.

Styling: `context.colors|spacing`, no hardcoded colors (theme-purity: run `bash tool/check_theme_purity.sh` before pushing — new-widget copy-paste trap #615). FAB inherits `FloatingActionButtonThemeData`. Default `endFloat` location (RTL-aware).

### Task 5: Polish + verify

- Scroll clearance: bottom padding under the FAB on the Groups tab list and Activity feed so the last row's trailing content isn't occluded (check existing bottom padding first)
- `flutter analyze` clean; full `flutter test`
- Grep check: no `state.extra`, no `goNamed`, no `Navigator.push` introduced
- PR body: `Closes #364`, Spec line pointing here, RED evidence (failing-test output before GREEN)
