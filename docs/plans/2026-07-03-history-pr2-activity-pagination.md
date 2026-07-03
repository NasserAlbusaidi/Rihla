# History PR2 — Activity tab pagination + expense rendering (#808 PR2)

> **For the implementing agent:** TDD per task (RED → GREEN). Work only in your assigned worktree.
> Re-verify every concrete claim below against live code before relying on it (grep/Read — the
> claims were verified 2026-07-03 against `main@7fdc1093` but you must re-confirm in your checkout).

**Goal:** The cross-group Activity tab becomes a real history surface: cursor-paginated across
groups (replacing the #804 30-item live window) and rendering the PR1 `expense_*` entries properly
(localized text, icon, amount, filter chip). Absorbs the #807-deferred polish: unread dot on the
Activity tab + empty-state CTA.

**Scope law:** Pure client. NO server/Functions/rules change, NO schema change, NO router change.
PR is `Refs #808` (PR2 of 3) — **in the COMMIT BODY too**, not just the PR body (squash-merge
auto-close trap, #447). Branch: `feat/808-pr2-activity-pagination`.

---

## Verified ground truth (2026-07-03, main@7fdc1093)

- Tab screen: `lib/features/home/screens/cross_group_activity_screen.dart` — watches
  `crossGroupActivityProvider`, filter chips `_Filter {all, settlements, events, members}`,
  day-grouped `ListView.builder`, row taps push `/group/{gid}`. Amount via private
  `_coerceAmount(log.metadata['amount'])` (legacy decimal-string/num key — expense entries do
  NOT use it).
- Window provider: `lib/features/home/providers/dashboard_providers.dart` —
  `crossGroupActivityProvider` merges `groupActivityProvider(gid)` (live, 15/group,
  `kCrossGroupActivityPerGroupLimit` in `group_balance_provider.dart`) and caps at
  `kCrossGroupActivityMergedCap = 30`. **The home RECENTLY section also reads this provider
  (slices take(3)) — it MUST keep working unchanged.**
- Pagination precedent: `lib/features/groups/services/group_activity_service.dart`
  `fetchActivityPageRaw(groupId, {startAfter, limit=50})` — cursor-then-limit already encoded
  (fake_cloud_firestore trap #183). `lib/features/groups/screens/group_activity_screen.dart`
  is the reference implementation (scroll-near-bottom prefetch, #488 failed-first-load error
  state, #634 filter memoization).
- PR1 data shape (`expenseAuditLogger.ts`, deployed): group activity docs with
  `type: expense_added|expense_edited|expense_deleted`, `actorId`, `actorName` (nullable),
  `description` (English verb phrase, may embed expense label + amount, e.g.
  `added Dinner (10.500 OMR)`), `timestamp` (ISO string), `metadata: {expenseId, eventId,
  eventName (may be ''), amountFils (int subunits), currency}`. **metadata has NO expense
  label and NO legacy `amount` key.**
- Rendering chokepoint: `lib/features/activity/utils/activity_display.dart`
  `localizedGroupActivityText` — `expense_*` currently falls to `_ => log.description`
  (pinned by a PR1 test in `test/unit/activity_display_test.dart` — that pin is
  **superseded by this PR**; update it deliberately, don't delete blindly).
- Three row surfaces render group activity:
  1. `cross_group_activity_screen.dart` `_ActivityRow` + `_CategoryIcon` (icon + amount)
  2. `group_activity_screen.dart` `_ActivityRow`-equivalent + `_CategoryIcon` at :611 (icon +
     amount) + `_matches` at :673 (filter)
  3. `lib/features/home/widgets/activity_row.dart` (home RECENTLY — avatar, text only; no icon
     map, no amount → only l10n text flows there, no widget change needed)
- Money display: `MoneySerializer.fromSubunits(int, currency) → Decimal`
  (`lib/core/services/money_serializer.dart:51`); currency validity via
  `MoneySerializer.supportedCurrencies` (used by `activityAmountCurrency`).
- Empty-state CTA target: `AddExpenseTargetSheet.show(context)` (static,
  `lib/features/home/widgets/add_expense_target_sheet.dart:26`). `EmptyStateView` already
  supports `onAction`/`actionLabel`.
- Nav shell: `lib/features/home/widgets/bottom_nav_shell.dart` — Activity destination icons at
  ~:154/:159 (`Iconsax.activity` / `.activity5`). Shell stacks tabs via
  `AnimatedOpacity`+`IgnorePointer`, NOT GoRouter.
- l10n: keys in `lib/l10n/app_en.arb` + `app_ar.arb`; follow `activityGroupEventCreated`
  (param + Generic fallback) pattern. Generated files under `lib/l10n/generated/` are
  committed — regenerate and commit them with any ARB change.

## Decisions already made (do not re-litigate)

- **D-PR2-1 — localized expense phrases are GENERIC (no expense label).** metadata carries no
  label; parsing it out of `description` is fragile. Render
  `added an expense in {eventName}` / `edited …` / `deleted …` (Generic variants when
  `eventName` empty), amount shown separately from `amountFils`. English loses the embedded
  label vs the PR1 interim description — accepted; a `metadata.label` server addendum is a
  possible follow-up issue, NOT this PR.
- **D-PR2-2 — "bell" is scoped to an unread dot on the Activity tab destination**, driven by
  the still-live `crossGroupActivityProvider` newest timestamp vs a persisted last-seen ISO
  string (SharedPreferences). No new bell icon anywhere else.
- **D-PR2-3 — the tab becomes one-shot + pull-to-refresh** (RefreshIndicator), mirroring the
  per-group screen's one-shot pattern. Live updates on the tab are given up on purpose; home
  RECENTLY and the unread dot stay live via the untouched `crossGroupActivityProvider`.
- **D-PR2-4 — frontier-clamped merge.** Never display an entry older than the oldest fetched
  entry of any non-exhausted group (otherwise later pages insert rows ABOVE the viewport).
  Formal invariant in Task 1.

---

## Task 1 — Pure merged paginator (TDD, table-driven)

**New file:** `lib/features/home/providers/merged_activity_paginator.dart` (pure Dart, no
Firestore imports). **Test:** `test/unit/merged_activity_paginator_test.dart`.

Model (immutable — return new state, never mutate):

```dart
class GroupPageState {        // per group
  final String groupId;
  final List<GroupActivityLog> buffer;  // fetched, not yet emitted, sorted desc
  final bool exhausted;                 // last fetch returned < pageSize
  final bool failed;                    // last fetch threw
}
class MergeResult {
  final List<GroupActivityLog EMITTED-with-group-context> emitted; // appended to visible list
  final Map<String, GroupPageState> next;
}
```

(Exact field/class names are the implementer's choice; the CONTRACT below is not.)

**Emission contract:**
1. An entry may be emitted only while **every non-exhausted, non-failed group has a non-empty
   buffer**. Emit the globally newest buffered entry, pop it, repeat until some non-exhausted
   non-failed group's buffer is empty.
2. Total order: timestamp desc, then `groupId` asc, then `log.id` asc (deterministic tiebreak;
   compare parsed `DateTime`, both write paths are UTC ISO-8601).
3. `hasMore` == any group is non-exhausted-non-failed, OR any buffer non-empty.
4. `needsFetch` == the set of non-exhausted, non-failed groups with empty buffers.
5. A `failed` group is excluded from the frontier (doesn't block emission) but is reported so
   the UI can offer retry; retry clears `failed` and re-fetches from that group's cursor.

**Table-driven tests (minimum):** two groups interleaved across page boundaries (frontier holds
back the tail); one group exhausted early (its whole buffer drains); equal timestamps tiebreak;
single group degenerates to plain pagination; all groups exhausted → hasMore false, buffers fully
drained; failed group doesn't block emission and appears in retry set; group with exactly
pageSize entries (exhausted only discovered on the empty next page).

## Task 2 — Paginated notifier + screen wiring (TDD)

**New:** `CrossGroupActivityPagerNotifier` (StateNotifierProvider — the project's pattern for
complex state) in `dashboard_providers.dart` or a sibling file. It:
- reads `userGroupsProvider` for the group list + names/currencies at load; pull-to-refresh
  re-reads and resets everything;
- fetches via the existing `groupActivityServiceProvider.fetchActivityPageRaw` (do NOT write a
  new Firestore query — the cursor-then-limit trap is already solved there), page size 50/group,
  keeping one `DocumentSnapshot` cursor per group;
- runs fetch results through the Task-1 paginator; state exposes
  `{entries (with groupName/groupId/currency context), isLoadingMore, hasMore, firstLoadFailed,
  partialFailure}`;
- `loadMore()` fetches ONLY `needsFetch` groups (parallel `Future.wait`, per-group try/catch —
  #244 OR-drop precedent: one failing group must not sink the page).

**Screen (`cross_group_activity_screen.dart`):**
- swap `crossGroupActivityProvider` → the pager; keep day-grouping, chips, row visuals;
- scroll-near-bottom prefetch (mirror `group_activity_screen.dart` :80-87) + a footer loading
  row while `isLoadingMore`;
- RefreshIndicator wrapping the list;
- first-load-all-failed → existing #488 error view (retry = full reload); partial failure →
  compact footer row "some activity couldn't load" + retry (l10n, both languages);
- filter memoization guard (#634 pattern) — the entries list is append-only, so cache by
  `(length, filter, query-less)` like the group screen does.
- **DO NOT touch `crossGroupActivityProvider` itself** — home RECENTLY + the Task-4 dot read it.

**Widget tests** (`test/features/home/cross_group_activity_screen_test.dart` + new):
pagination — seed >50 entries in one fake group, assert a page-2-only row **becomes findable
after scrolling** (small drag steps / `scrollUntilVisible`; never assert by counting rows under
virtualization; rows render in `Text.rich` → `find.textContaining(..., findRichText: true)`);
refresh resets; error/partial-failure paths.

## Task 3 — Render `expense_*` (TDD)

- `activity_display.dart` `localizedGroupActivityText`: add `expense_added|edited|deleted`
  arms using new l10n keys `activityGroupExpenseAdded(eventName)` = "added an expense in
  {eventName}" + `activityGroupExpenseAddedGeneric` = "added an expense" (same pair for
  Edited/Deleted; Arabic in `app_ar.arb`; regen + commit generated files). Update the PR1 pin
  test in `test/unit/activity_display_test.dart` to the new contract (conscious supersede).
- **New shared amount helper** in `activity_display.dart` (single chokepoint, replaces BOTH
  private `_coerceAmount` copies):

  ```dart
  ({Decimal value, String currency})? activityAmount(GroupActivityLog log, String fallbackCurrency)
  ```

  Contract: if `metadata['amountFils']` is `int` AND `metadata['currency']` is a supported
  currency string → `(MoneySerializer.fromSubunits(amountFils, currency), currency)`.
  **If `amountFils` is present but currency is missing/unsupported → return null** (converting
  with a guessed scale is a 10×/1000× lie). Else fall back to the legacy `metadata['amount']`
  num/string coercion with `activityAmountCurrency(log, fallbackCurrency)` as today.
  **`amountFils` must NEVER flow through the legacy decimal-units path** (10500 fils would
  render as 10,500 OMR). Table-driven unit tests: fils+currency; fils+missing currency → null;
  fils+unsupported currency → null; legacy string amount; legacy num; both keys present →
  fils wins; neither → null. This helper is money-display code — clean/warning/error cases all
  covered.
- Icon maps: add `expense_*` arms to `_CategoryIcon` in BOTH
  `cross_group_activity_screen.dart` and `group_activity_screen.dart:611` (suggest
  `Iconsax.receipt_2` family: added = `colors.saffronSoft`/`colors.primaryDark`, edited =
  `colors.cardSoft`/`colors.textSecondary` + `Iconsax.edit_2`… implementer picks within
  existing token palette — NO hardcoded colors, run `bash tool/check_theme_purity.sh` locally).
- Filter: add `expenses` bucket (label l10n `activityFilterExpenses` = "Expenses"/Arabic) to
  BOTH screens' chip strips; match = `type.startsWith('expense_')`.
- Home RECENTLY (`activity_row.dart`): text flows via the shared function — verify with a test,
  no widget change expected.

## Task 4 — Unread dot + empty-state CTA (TDD)

- Persist last-seen: SharedPreferences key (e.g. `activityLastSeenIso`), read through the
  existing `sharedPreferencesProvider` (override it in every app-booting test — it throws by
  default). Provider `activityUnreadProvider` = newest `crossGroupActivityProvider` entry
  timestamp > lastSeen (missing lastSeen + non-empty feed = unread true).
- Dot: wrap the Activity destination icons in `bottom_nav_shell.dart` with Material 3 `Badge`
  (`isLabelVisible: hasUnread`, `smallSize`, color from `context.colors` tokens). Mark seen
  (write now-UTC ISO) when the Activity tab becomes the active tab AND on tab-screen init for
  the routed `/activity` entry.
- Empty-state CTA (zero-activity state on the tab): if the user has ≥1 group →
  `actionLabel` "Add an expense" (new l10n key or reuse an existing add-expense label if one
  fits) → `AddExpenseTargetSheet.show(context)`. **Zero groups → NO CTA** (#807: never a
  duplicate create-group affordance; the FAB is hidden there too).
- Tests: dot appears with fresh activity, clears after visiting the tab (fake time via injected
  `DateTime`-free comparison — compare ISO strings); CTA visible with groups + absent with
  zero groups; `EmptyStateView` schedules a flutter_animate ticker → tests landing on
  empty/error states must drain it, BUT tests booting via `pumpRihlaApp` must NOT
  `pumpAndSettle` (ConnectivityNotifier timer) — follow the existing patterns in
  `cross_group_activity_screen_test.dart`.

## Task 5 — Verify & hand back (do NOT push yet)

- [ ] `flutter analyze` clean (`prefer_const_constructors` is CI-fatal)
- [ ] `bash tool/check_theme_purity.sh` clean (CI-only check — run it locally)
- [ ] `flutter test test/unit/ test/features/home/ test/features/groups/ test/features/activity/`
      then the FULL `flutter test`
- [ ] l10n generated files regenerated AND committed
- [ ] Conventional commits, each body `Refs #808`
- [ ] Report back (do not push, do not open a PR): worktree path, branch, commit list,
      RED evidence excerpts (failing-first output per task), full-suite result, and any spec
      deviations with reasons
