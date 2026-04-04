# Phase 30: Group Settle Up & Activity - Research

**Researched:** 2026-04-04
**Domain:** Flutter widget redesign + balance bug investigation + activity logging audit
**Confidence:** HIGH

## Summary

Phase 30 is a visual overhaul and functional fix phase for two fully implemented screens: `GroupSettleUpScreen` and `GroupActivityScreen`. Both screens already have working data pipelines, providers, services, and Firestore backing. No new data architecture is needed — this phase is a UI transformation and targeted bug fix.

The settle-up screen needs its flat 3-section list replaced with a 4-tab `AppTabBar` (You Owe / Owed to You / Between Others / History), the activity screen needs date-grouped sections with filter chips and infinite scroll replacing the manual "Load more" button, and both need their custom headers replaced with `ModuleHeader`.

The balance sign bug (D-12) is a sign convention mismatch: `groupBalancesProvider` computes `netBalance = (totalPaid + settlementAdj) - totalOwed`, where positive = owed money (creditor). The `GroupDetailScreen` `GroupStatsGrid` likely displays this correctly at group level, but the event-level `LedgerScreen` may use a different display convention, causing the user to perceive a sign flip. The bug is in the rendering / labeling layer, not in the math itself — the `BalanceCalculator` is consistent.

The activity logging audit reveals that `logGroupEvent` is called in exactly one place in the entire codebase: `group_settle_up_screen.dart` for `group_settlement`. The four other action types (`event_created`, `event_deleted`, `member_joined`, `member_left`) are defined in the model and icon switch but have no callers. These logging calls must be added to `create_event_screen.dart`, the event delete path, `join_group_screen.dart`, and the group leave/remove flow.

**Primary recommendation:** Reuse existing `ModuleHeader`, `AppTabBar`, `EmptyStateView`, and the date-grouping pattern from `ActivityFeedScreen` — no new widgets needed. The settlement History tab reads from `groupSettlementsProvider` which already streams live data from Firestore.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Settle-up screen design**
- D-01: Replace custom header with ModuleHeader (dark gradient) for consistency with other v2.0 screens
- D-02: Replace 3-section layout (YOUR ACTIONS / WAITING FOR OTHERS / OTHERS SETTLING) with a tabbed view using AppTabBar — tabs: "You Owe" / "Owed to You" / "Between Others"
- D-03: Add a "History" tab showing completed/recorded settlements with dates, amounts, and participants
- D-04: Settlement tiles redesigned as card-style — rounded cards with avatar initials, prominent amount, collapsible per-event breakdown
- D-05: Record Settlement bottom sheet gets token polish — card-style input fields, consistent spacing, gradient CTA button. Same fields (amount + note), no new fields
- D-06: "All settled" empty state stays as-is — green checkmark circle, current copy is fine

**Activity feed design**
- D-07: Replace custom header with ModuleHeader (dark gradient), same as settle-up
- D-08: Switch from flat list to date-grouped sections with section headers ("Today", "Yesterday", "Mar 28") — match the pattern from event-level ActivityFeedScreen
- D-09: Rich activity tiles — avatar/initials circle, actor name, description text, relative timestamp, type-specific icon (money for settlements, calendar for events, people for member actions)
- D-10: Add horizontal scrollable filter chips below header: All, Settlements, Events, Members
- D-11: Replace manual "Load more" button with infinite scroll (auto-load next page when scrolling near bottom)

**Functional fixes**
- D-12: FIX: Balance sign flip bug — group-level balance shows user is owed X, but event-level shows user owes X. The group balance aggregation is inverting payer/recipient. Root cause investigation and fix required
- D-13: FIX: Settlement history — currently no way to view past/completed settlements. The History tab (D-03) addresses this
- D-14: FIX: Activity logging audit — some actions appear missing from the group activity feed. Audit all action types that should log (expense CRUD, settlement recording, event creation/deletion, member join/leave) and ensure each has a working logging call

**GroupDetail integration**
- D-15: Keep existing CTA entry points — gradient "Settle Up" button and "View All" on activity section. Ensure they navigate correctly to redesigned screens
- D-16: Keep 5-item activity preview on GroupDetailScreen. Update tile rendering to match new rich tile design from D-09

### Claude's Discretion
- Exact spacing and padding within new card-style settlement tiles
- Skeleton/loading state design for tabbed settle-up view
- Filter chip visual styling (colors, selected state)
- Date section header typography and spacing
- Infinite scroll threshold distance

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope
</user_constraints>

## Standard Stack

### Core (all already installed — no new packages needed)

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `flutter_riverpod` | `^2.x` | State management | Already in use — all providers exist |
| `go_router` | `^17.1.0` | Navigation | All routes defined and working |
| `flutter_animate` | `^4.5.0` | Entrance animations | Already installed, used in all v2.0 phases |
| `iconsax` | `^0.0.8` | Icons | Already installed throughout |
| `decimal` | existing | Money math | All settlement math already uses it |
| `intl` | existing | Date formatting | Used in ActivityFeedScreen for date labels |
| `timeago` | existing | Relative timestamps | Used in ActivityFeedScreen |

### Supporting Widgets (already in `lib/shared/widgets/`)

| Widget | File | Purpose |
|--------|------|---------|
| `ModuleHeader` | `module_header.dart` | Dark gradient header — drop-in for both screens |
| `AppTabBar` | `app_tab_bar.dart` | Gradient pill tabs — settle-up 4-tab layout |
| `EmptyStateView` | `empty_state_view.dart` | Per-tab empty states |
| `SkeletonLoader` | `skeleton_loader.dart` | Loading states for tabs |

**No new packages to install.** This phase is a pure widget transformation using existing infrastructure.

## Architecture Patterns

### Recommended Project Structure

No structural changes needed. All files stay in their current locations:

```
lib/features/groups/
├── screens/
│   ├── group_settle_up_screen.dart   # Full rewrite of _buildContent + _buildHeader
│   └── group_activity_screen.dart    # Full rewrite of _buildBody + _buildHeader
├── widgets/
│   ├── group_settlement_tile.dart    # Card-style redesign
│   └── group_activity_tile.dart     # Rich tile redesign (D-09)
└── services/
    ├── group_activity_service.dart   # No changes needed
    └── group_settlement_service.dart # No changes needed
```

### Pattern 1: TabBar with TabController (settle-up screen)

The screen converts from `ConsumerStatefulWidget` to `ConsumerStatefulWidget with SingleTickerProviderStateMixin` to host the `TabController`.

```dart
// Source: ActivityFeedScreen pattern + AppTabBar widget
class _GroupSettleUpScreenState extends ConsumerState<GroupSettleUpScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
}
```

AppTabBar usage:
```dart
AppTabBar(
  controller: _tabController,
  tabs: const ['You Owe', 'Owed to You', 'Between Others', 'History'],
)
```

Tab 0 (You Owe): `optimalSettlements.where((s) => s['fromUserId'] == currentUid)`
Tab 1 (Owed to You): `optimalSettlements.where((s) => s['toUserId'] == currentUid)`
Tab 2 (Between Others): neither uid
Tab 3 (History): `groupSettlementsProvider(groupId)` — existing stream, already in `group_balance_provider.dart`

### Pattern 2: Date-grouped list (activity screen)

Copied directly from `ActivityFeedScreen._buildGroupedTimeline()`. The `_groupByDate` logic is identical — only the model type changes from `ActivityLog` to `GroupActivityLog`.

```dart
// Source: lib/features/activity/screens/activity_feed_screen.dart:190-206
Map<String, List<GroupActivityLog>> _groupByDate(List<GroupActivityLog> logs) {
  final grouped = <String, List<GroupActivityLog>>{};
  final now = DateTime.now();
  for (final log in logs) {
    final label = _dateLabel(log.timestamp, now);  // GroupActivityLog uses .timestamp
    grouped.putIfAbsent(label, () => []).add(log);
  }
  return grouped;
}

String _dateLabel(DateTime date, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final logDate = DateTime(date.year, date.month, date.day);
  if (logDate == today) return 'TODAY';
  if (logDate == today.subtract(const Duration(days: 1))) return 'YESTERDAY';
  return DateFormat('MMM d').format(date);
}
```

Note: `ActivityLog.createdAt` vs `GroupActivityLog.timestamp` — different field names.

### Pattern 3: Infinite scroll (activity screen)

Replace the manual "Load more" button at index `_activities.length` with a `ScrollController` listener:

```dart
_scrollController.addListener(() {
  final pos = _scrollController.position;
  final threshold = pos.maxScrollExtent - 200; // 200px from bottom
  if (pos.pixels >= threshold && _hasMore && !_isLoadingMore) {
    _loadPage();
  }
});
```

The existing `_loadPage()` method already guards against concurrent calls (`_isLoadingMore` flag). The threshold distance (200px) is within Claude's discretion per CONTEXT.md.

### Pattern 4: Filter chips (activity screen)

Client-side filter applied after pagination. State: `String _activeFilter = 'All'` in the screen widget. Filter values: `'All'`, `'Settlements'`, `'Events'`, `'Members'`.

Type mapping:
- Settlements: `type == 'group_settlement'`
- Events: `type == 'event_created' || type == 'event_deleted'`
- Members: `type == 'member_joined' || type == 'member_left'`

Filter chips live in a `SingleChildScrollView(scrollDirection: Axis.horizontal)` row below the `ModuleHeader`.

### Pattern 5: Staggered entrance animations

Standard for all v2.0 screens:
```dart
// Source: all recent phases (27, 28, 29)
Widget.animate()
  .fadeIn(delay: Duration(milliseconds: index * 50))
  .slideY(begin: 0.1, curve: Curves.easeOutCubic)
```

Apply to settlement card tiles and activity group sections.

### Anti-Patterns to Avoid

- **Don't re-implement date grouping from scratch:** Copy `_groupByDate` / `_dateLabel` from `ActivityFeedScreen` — it's already tested.
- **Don't use `TabBarView` with `ListView.builder` inside a scroll:** `TabBarView` + `ListView` inside `NestedScrollView` creates nested scroll conflicts. Use `TabBarView` with `Column` + explicit list, or use `physics: NeverScrollableScrollPhysics()` on inner lists.
- **Don't call `groupSettlementsProvider` inside `_buildHistoryTab` without null-checking:** The provider returns `AsyncValue<List<Settlement>>` — always use `.when()`.
- **Don't add filter state to the `groupBalancesProvider` computation:** Filters are client-side display logic only. Provider computes unfiltered data; screen widget filters the list before rendering.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Tab indicator UI | Custom TabBar | `AppTabBar` | Already built with gradient pill, haptics, semantic keys |
| Date label generation | Custom logic | Copy from `ActivityFeedScreen._dateLabel` | Exact same logic, already in codebase |
| Relative timestamps | Custom formatter | `timeago` package (already installed) | Handles all edge cases, already imported in ActivityFeedScreen |
| Settlement history data | New Firestore query | `groupSettlementsProvider` | Already streams `groups/{gid}/settlements`, ordered by `settledAt` descending |
| Card shadows | Raw `BoxDecoration` | `AppShadowTokens.standard.raised` | Token consistency with rest of app |

## Balance Sign Bug Investigation (D-12)

### Root Cause Analysis (CONFIRMED HIGH confidence)

The `BalanceCalculator.calculateBalances()` formula is:
```
netBalance = (totalPaid + settlementAdj) - totalOwed
```

**Sign convention:** positive netBalance = creditor (is owed money), negative = debtor (owes money).

This is correct and consistent. `calculateOptimalSettlements` correctly identifies debtors as `netBalance < 0` (fromUserId) and creditors as `netBalance > 0` (toUserId).

The `GroupSettlementTile` colors the amount with `AppColorTokens.light.error` when `isYourAction == true` (you are the debtor, `fromUserId == currentUid`). This is correct.

The bug is NOT in the math. The sign flip the user reports is in the **display layer**:

1. `GroupDetailScreen._buildMembersBalancesSection` passes `balance.netBalance` to `GroupMemberBalanceCard`.
2. `GroupMemberBalanceCard` displays this as-is.
3. Event-level screens (`LedgerScreen`) use `eventBalancesProvider` which runs the same `BalanceCalculator` but for event-only participants.

**Likely bug location:** `GroupStatsGrid` — the "Your Balance" stat. Read `group_stats_grid.dart` to check whether it displays `userNetBalance` as-is or applies a sign inversion for display.

The `perEventBreakdown` used in `GroupMemberBalanceCard` and event cards comes from `_buildPerEventBreakdown` which computes separate `BalanceCalculator` runs per event. If the sign convention in this per-event breakdown is different from the aggregated group balance, the user sees a flip when comparing group-level to event-level.

**Investigation task:** Read `group_stats_grid.dart` and `group_member_balance_card.dart` fully. Check how `netBalance` is presented — specifically whether a positive netBalance is shown as "you are owed" or "you owe" at each display site.

### Fix Strategy

Once the display site is identified:
- Standardize sign display: positive = "You're owed", negative = "You owe"
- If `GroupStatsGrid` inverts the sign before display, `GroupMemberBalanceCard` may not (or vice versa)
- Fix the inconsistent site — do not change `BalanceCalculator` math (it is correct per BalanceCalculator tests)

## Activity Logging Audit (D-14) — CONFIRMED GAPS

**Finding (HIGH confidence):** `logGroupEvent` is called from exactly one location in the entire codebase. All other action types are unimplemented.

| Action Type | Defined in Model | Caller Exists | Call Site |
|-------------|-----------------|----------------|-----------|
| `group_settlement` | Yes | **Yes** | `group_settle_up_screen.dart:723` |
| `event_created` | Yes | **No** | Missing — should be in `create_event_screen.dart` |
| `event_deleted` | Yes | **No** | Missing — should be in event delete path |
| `member_joined` | Yes | **No** | Missing — should be in `join_group_screen.dart` |
| `member_left` | Yes | **No** | Missing — should be in group leave/remove flow |

**Where to add the missing calls:**

1. `event_created` — `create_event_screen.dart` `_submitForm()`, after `EventService.createEvent()` succeeds. Actor = current user, metadata = `{'eventId': event.id, 'eventName': event.name}`.

2. `event_deleted` — Search for the event delete path. Likely in `group_settings_screen.dart` or an event options menu. Add after soft-delete confirmation.

3. `member_joined` — `join_group_screen.dart`, after successful `joinGroup()` call. Actor = joining user, metadata = `{'groupId': groupId}`.

4. `member_left` — `group_settings_screen.dart` or `group_danger_section.dart`, after confirmed leave. Actor = leaving user.

All calls use the fire-and-forget `logGroupEvent()` pattern (void, no await, errors silently caught by the service).

## Settlement History Tab (D-03)

**Data source:** `groupSettlementsProvider(groupId)` — already exists in `group_balance_provider.dart`. This provider streams `groups/{groupId}/settlements` filtered `isDeleted == false`, ordered `settledAt` descending.

**Settlement model fields available for history display:** `payerParticipantId`, `recipientParticipantId`, `payerName`, `recipientName`, `amount`, `currency`, `note`, `settledAt`, `scope`.

The `GroupSettlementService.watchGroupSettlements()` method returns `List<Settlement>` — use `payerName` and `recipientName` directly (they are stored on the record at creation time).

**History tile design:** Read `Settlement` model to confirm field names. Display: avatar pair (initials from payerName/recipientName), "X paid Y", formatted amount, formatted date from `settledAt`.

## Common Pitfalls

### Pitfall 1: TabView + Inner ListView Scroll Conflict

**What goes wrong:** Placing a `ListView` inside a `TabBarView` inside a `Column` causes layout overflow and broken scroll behavior.

**Why it happens:** `ListView` needs unconstrained height or a parent that provides height via `Expanded`/`SliverConstraints`.

**How to avoid:** Wrap the `TabBarView` in `Expanded` inside the outer `Column`. Each tab body should be a `ListView` directly, not wrapped in another `Column`.

```dart
// CORRECT
Expanded(
  child: TabBarView(
    controller: _tabController,
    children: [
      ListView.builder(...),  // tab 0
      ListView.builder(...),  // tab 1
    ],
  ),
)
```

### Pitfall 2: Infinite Scroll Double-Trigger

**What goes wrong:** `ScrollController.addListener` fires on every scroll event. Without the `_isLoadingMore` guard, `_loadPage()` gets called dozens of times before the first page returns.

**Why it happens:** The scroll listener fires synchronously on every pixel change.

**How to avoid:** The existing `_loadPage()` already has `if (_isLoadingMore || !_hasMore) return;`. The scroll listener must call `_loadPage()` — not `setState` that triggers a rebuild that triggers `_loadPage()`.

### Pitfall 3: Filter Chips Breaking Pagination

**What goes wrong:** Filter state causes the displayed list to show 0 items even when data has been loaded, making the user think more data needs to be loaded.

**Why it happens:** The filtered list can be empty even when `_activities` is non-empty. `_hasMore` looks at the raw list length, not the filtered list.

**How to avoid:** Always apply filters as a `final filtered = _activities.where(...)` derivation in `build()`. Never modify `_activities` based on filter state. The "Load more" trigger checks `_hasMore` (raw), not filtered list length.

### Pitfall 4: preSelectedMemberId Auto-Scroll with TabBar

**What goes wrong:** `_scrollToPreSelected()` calls `Scrollable.ensureVisible()` but in the tabbed layout, the settlement is not in the current scroll context.

**Why it happens:** The scroll context changes per tab. The current code scrolls in the root `ScrollController` but settlements are now in `TabBarView` child lists.

**How to avoid:** When `preSelectedMemberId` is provided, auto-switch to the correct tab (You Owe or Owed to You) first via `_tabController.animateTo(tabIndex)`, then run `Scrollable.ensureVisible()` in the next frame.

### Pitfall 5: Test Key Changes Breaking Existing Tests

**What goes wrong:** Existing tests find widgets by `GroupKeys.settleUpTitle` (text: 'Settle Up'). If `ModuleHeader` renders the title differently (different widget type or key), tests fail.

**Why it happens:** `ModuleHeader` uses its own internal Text widget; the test key `GroupKeys.settleUpTitle` was on the old custom header `Text`.

**How to avoid:** Add a `key` param to `ModuleHeader` calls OR update test finders to use `find.text('Settle Up')` across the widget tree. Audit all `GroupKeys.settleUpTitle` and `GroupKeys.activityScreenTitle` usages before changing headers.

### Pitfall 6: GroupActivityLog.timestamp vs ActivityLog.createdAt

**What goes wrong:** Copy-pasting `_dateLabel` from `ActivityFeedScreen` and using `.createdAt` instead of `.timestamp` causes a `NoSuchMethodError`.

**Why it happens:** The two models use different field names for the same concept.

**How to avoid:** `GroupActivityLog` uses `.timestamp` (DateTime). `ActivityLog` uses `.createdAt`. Always use `.timestamp` in group activity contexts.

## Code Examples

### Verified Existing Patterns

#### Settlement History tab data wiring
```dart
// Source: lib/features/groups/providers/group_balance_provider.dart:39-43
// groupSettlementsProvider already exists — just watch it in the History tab
final historicSettlementsAsync = ref.watch(groupSettlementsProvider(groupId));
historicSettlementsAsync.when(
  data: (settlements) => settlements.isEmpty
    ? EmptyStateView(icon: Iconsax.receipt_1, title: 'No settled payments yet', ...)
    : ListView.builder(itemCount: settlements.length, ...),
  loading: () => SkeletonLoader.cardList(),
  error: (e, _) => EmptyStateView(...),
)
```

#### Infinite scroll listener pattern
```dart
// Source: Phase 28/29 scroll patterns + existing _loadPage guard
@override
void initState() {
  super.initState();
  _scrollController = ScrollController();
  _scrollController.addListener(_onScroll);
  _loadPage();
}

void _onScroll() {
  final pos = _scrollController.position;
  if (pos.pixels >= pos.maxScrollExtent - 200) {
    _loadPage(); // guard: if (_isLoadingMore || !_hasMore) return;
  }
}
```

#### AppTabBar integration (4 tabs)
```dart
// Source: lib/shared/widgets/app_tab_bar.dart
// Requires SingleTickerProviderStateMixin
_tabController = TabController(length: 4, vsync: this);

AppTabBar(
  controller: _tabController,
  tabs: const ['You Owe', 'Owed to You', 'Between Others', 'History'],
)
```

#### Date section header (copy from ActivityFeedScreen)
```dart
// Source: lib/features/activity/screens/activity_feed_screen.dart:209-234
class _DateSectionHeader extends StatelessWidget {
  final String label;
  const _DateSectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: AppColorTokens.light.textMuted,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
```

## Open Questions

1. **GroupStatsGrid balance display convention**
   - What we know: `userNetBalance` is passed from `groupBalancesProvider` — positive = creditor
   - What's unclear: Does `GroupStatsGrid` display it directly or apply a sign inversion? Need to read `lib/features/groups/widgets/group_stats_grid.dart`
   - Recommendation: Read the file before writing the balance fix — it determines the exact line to change

2. **Event delete call site**
   - What we know: Event deletion must exist somewhere (it's a declared action type)
   - What's unclear: Which screen/widget handles event deletion — not found in the files read so far
   - Recommendation: `grep -r "deleteEvent\|softDelete.*event\|event.*delete" lib/` before writing the logging fix

3. **preSelectedMemberId tab routing**
   - What we know: `preSelectedMemberId` currently triggers auto-scroll; the new tab layout changes the scroll context
   - What's unclear: Which tab (You Owe vs Owed to You) should be auto-selected based on who is payer vs recipient
   - Recommendation: Auto-select "You Owe" if `currentUid == fromUserId` in the settlement involving `preSelectedMemberId`, else "Owed to You"

## Environment Availability

Step 2.6: SKIPPED — no external dependencies. This phase is purely Flutter widget changes (UI transformation + bug fixes). All data infrastructure is Firebase/Firestore already in use.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | flutter_test (Flutter SDK built-in) |
| Config file | none — tests run via `flutter test` |
| Quick run command | `flutter test test/features/groups/ --no-pub` |
| Full suite command | `flutter test --no-pub` |

### Existing Tests (Passing Baseline — CONFIRMED)

Both test files pass before this phase begins:

- `test/features/groups/group_settle_up_screen_test.dart` — 15 tests, all passing
- `test/features/groups/group_activity_screen_test.dart` — 5 tests, all passing

### Phase Requirements → Test Map

| Behavior | Test Type | Automated Command | Notes |
|----------|-----------|-------------------|-------|
| Settle-up shows "You Owe" / "Owed to You" / "Between Others" / "History" tabs | Widget | `flutter test test/features/groups/group_settle_up_screen_test.dart` | Update existing test: `find.text('You Owe')` |
| Settle-up History tab shows past settlements | Widget | same | New test: `groupSettlementsProvider` override |
| Activity screen shows date section headers (TODAY, YESTERDAY) | Widget | `flutter test test/features/groups/group_activity_screen_test.dart` | New test: inject activities with known timestamps |
| Activity filter chips filter displayed list | Widget | same | New test: inject mixed-type activities, verify filter |
| Missing activity log types are now called | Unit | `flutter test test/unit/group_activity_service_test.dart` | Verify `event_created`, `member_joined` write to Firestore |
| Balance sign consistency (D-12) | Widget | `flutter test test/features/groups/group_settle_up_screen_test.dart` | Verify "You Owe" tab color for debtor |

### Sampling Rate
- **Per task commit:** `flutter test test/features/groups/ --no-pub`
- **Per wave merge:** `flutter test --no-pub`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps

The following new tests must be written in Wave 0 before implementation:

- [ ] `test/features/groups/group_settle_up_screen_test.dart` — add: tab bar renders with 4 tabs; "You Owe" tab is selected by default; History tab shows settlement list
- [ ] `test/features/groups/group_activity_screen_test.dart` — add: date section headers appear; filter chips render; "All" filter shows all activities; "Settlements" filter hides non-settlement entries

## Sources

### Primary (HIGH confidence)
- `lib/features/groups/screens/group_settle_up_screen.dart` — full implementation read
- `lib/features/groups/screens/group_activity_screen.dart` — full implementation read
- `lib/features/groups/providers/group_balance_provider.dart` — GroupBalances typedef, all provider definitions
- `lib/features/groups/services/group_settlement_service.dart` — Settlement CRUD, watchGroupSettlements
- `lib/features/groups/services/group_activity_service.dart` — logGroupEvent, fetchActivityPageRaw
- `lib/features/groups/models/group_activity_log_model.dart` — 5 action types, field names
- `lib/features/groups/widgets/group_settlement_tile.dart` — current tile structure
- `lib/features/groups/widgets/group_activity_tile.dart` — current tile + icon switch
- `lib/features/activity/screens/activity_feed_screen.dart` — date grouping pattern to replicate
- `lib/shared/widgets/app_tab_bar.dart` — AppTabBar API
- `lib/features/ledger/providers/expense_provider.dart` — BalanceCalculator sign convention
- `test/features/groups/group_settle_up_screen_test.dart` — 15 tests, confirmed passing
- `test/features/groups/group_activity_screen_test.dart` — 5 tests, confirmed passing
- `grep` audit of `logGroupEvent` across all lib/*.dart — 1 caller confirmed

### Secondary (MEDIUM confidence)
- `lib/features/groups/screens/group_detail_screen.dart` — activity section + balance display wiring
- `lib/features/groups/widgets/group_settlement_summary.dart` — summary card (keep as-is)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all packages already installed, confirmed in pubspec
- Architecture patterns: HIGH — read directly from existing implementations
- Bug root cause: MEDIUM — traced to display layer, but exact line requires reading `group_stats_grid.dart`
- Activity logging gaps: HIGH — grep audit of entire lib/ confirms 1 caller
- Pitfalls: HIGH — directly derived from code reading

**Research date:** 2026-04-04
**Valid until:** 2026-05-04 (stable stack)
