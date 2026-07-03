# #852 a1 — Shared activity-row deep-link target (Home RECENTLY + group activity rows)

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** One deep-link source of truth for activity-row taps: extract #840's `_historyRowTarget` + `_navMetadataString` into a shared util, reuse it from the home RECENTLY rows and the per-group activity timeline, making the raised-card cue truthful.

**Architecture:** Pure INBOUND/nav-only change. A new `lib/features/activity/utils/activity_nav.dart` hosts the per-type target table (moved byte-for-byte from `cross_group_activity_screen.dart`). Three callers: History tab (rewired, behavior unchanged, pinned by the existing #840 tests), home RECENTLY rows (new behavior: per-type push instead of bare group root), group activity rows (new behavior: `InkWell` + per-type push; self-referential targets stay inert). No write path, no schema, no rules, no server.

**Tech Stack:** Flutter, GoRouter 13 (path-string push), Riverpod overrides + `FakeFirebaseFirestore` in tests.

**Issue:** #852 (decision-labelled; user chose **a1** on 2026-07-03). Gate category: **routing** (deep-link paths built from client-forgeable `log.metadata`).

---

## Decision record

- **a1** (full consistency) chosen by user 2026-07-03 over a2 (Recently-only) and b (drop raised cue). Rationale: one deep-link source of truth; a2 leaves the raised-but-inert contradiction the re-grade will re-flag; b keeps the History-vs-group-rows asymmetry.
- **Util location/signature:** `lib/features/activity/utils/activity_nav.dart`, `String activityRowTarget({required String groupId, required GroupActivityLog log})`. Primitives, not `CrossGroupActivityEntry` — the group activity screen has no entry record and must not import home's `dashboard_providers.dart` typedef. The switch body and the `_navMetadataString` guard move **verbatim**; only the two locals (`final groupId = entry.groupId; final log = entry.log;`) become parameters. Verified parity: `CrossGroupActivityEntry` is `({log, groupName, groupId, currency})` (`dashboard_providers.dart:15-20`) built with `groupId: group.id` from fetch context (`:65-70`) — every field the table reads exists at all three callsites.
- **Gate round 1 (2026-07-03): rubric 0 P1/1 P2/2 P3, adversary 0 P1/0 P2/3 P3 — passed; all findings folded in.** Accepted trade-off from the adversary: a day card containing only member/event_deleted rows stays raised while fully inert — the "raised = actionable" cue is honored per-row, not per-card.
- **Group screen self-targets stay inert:** rows whose resolved target equals `/group/{gid}` (member_joined, member_left, event_deleted, unknown types, guard-degraded expense rows) get `onTap: null` — pushing a duplicate of the parent screen is itself a false affordance (the exact defect class #852 names). This requires resolving the target during **build**, so the util's totality becomes a documented contract. It is provably total today: `switch` over `String log.type`; metadata read via `is String && isNotEmpty`; `GroupActivityLog.metadata` is non-nullable with `const {}` default (`group_activity_log_model.dart:28,41,66`). The #840 docstring's "only from onTap" line is superseded by the sharper invariant it was protecting: **never throw, and never run inside list-wide match/filter passes** (`activityMatchesQuery`).
- **Home RECENTLY: uniform push** (identical to History tab) — group-root targets are meaningful when navigating from Home.
- **Out of scope:** the event-level feed `activity_feed_screen.dart` also has raised-but-inert day cards, but uses a different model (`ActivityLog`, MONEY/GEAR/DOCS × CREATE/UPDATE/DELETE) — the target table's type vocabulary does not apply. Separate follow-up decision; name it in the PR body. Also out of scope (per issue): BottomNavShell tab back-behavior.

## Read/write-path classification

All touched reads are **INBOUND (display/nav-only)**. `entry.groupId` / `widget.groupId` come from fetch context (dashboard enrichment `group.id`; the group screen's route param scoping the query), never `log.metadata['groupId']`. A forged `eventId` under the true groupId reaches a safe not-found on the target screen (established #840 contract). No OUTBOUND leg exists.

## Verification principles report (run 2026-07-03 against main @ 021f571e)

1. **Callsite classification:** all reads INBOUND/nav-only (above). No write surface.
2. **Claims vs code:** `home_screen.dart:238-239` bare `context.push('/group/${entry.groupId}')` — confirmed. `cross_group_activity_screen.dart:682` row push via `_historyRowTarget`; table at `:790-820`; guard at `:832-835` — confirmed (issue cited pre-drift `:787-817/:829-832`). `group_activity_screen.dart:471-476` raised day card; `_ActivityRow` `:494-589` plain `Padding`, no onTap — confirmed. `ActivityRow` widget takes `onTap` + `InkWell` (`lib/features/home/widgets/activity_row.dart:21,27,33-34`) — confirmed. Gate round-1 note: the new `InkWell` splash paints under the opaque `cardSurface` day-card fill — cosmetically invisible ripple, byte-for-byte parity with the shipped History tab row (`cross_group_activity_screen.dart:681`); accepted, no action.
3. **Read-path per write-path:** N/A — no write path.
4. **Fields from the type:** `CrossGroupActivityEntry = ({GroupActivityLog log, String groupName, String groupId, String currency})`; `GroupActivityLog = {id, type, actorId, actorName, description, metadata (non-null, default {}), timestamp}`. Table reads only `log.type`, `log.metadata['eventId']`, param `groupId`.
5. **Exact data contract:** `String activityRowTarget({required String groupId, required GroupActivityLog log})` → GoRouter location string. Targets: `expense_added|expense_edited` → `/group/$gid/event/$eid/ledger`; `expense_deleted` → `/group/$gid/event/$eid/activity`; `event_created` → `/group/$gid/event/$eid`; `group_settlement` → `/group/$gid/settle-up`; everything else / guard-degraded → `/group/$gid`.
6. **Arithmetic decomposition:** N/A — no money math.
7. **Adversarial orthogonal axis (identity/scope):** a log whose metadata carries a forged `groupId` for another group — nothing in this change reads `metadata['groupId']`; groupId is bound from fetch context at every callsite. Lifecycle axis: eventId pointing at a deleted/closed event — target screens already render safe not-found (#840 contract; `event_deleted` deliberately never targets the event). RTL axis: `InkWell` adds no directional layout.

---

### Task 1: Extract the shared util + rewire the History tab (pure refactor, pinned by #840 tests)

**Files:**
- Create: `lib/features/activity/utils/activity_nav.dart`
- Modify: `lib/features/home/screens/cross_group_activity_screen.dart` (delete `_historyRowTarget` `:779-820` + `_navMetadataString` `:822-835`; rewire `:682`)
- Test: existing `test/features/home/cross_group_activity_screen_test.dart` (NO changes — it pins the refactor)

**Step 1: Create `lib/features/activity/utils/activity_nav.dart`**

```dart
import '../../groups/models/group_activity_log_model.dart';

/// Deep-link target for an activity-feed row tap, resolved per activity type
/// (#840 PR-7; shared across surfaces by #852).
///
/// Callers: the History tab (`cross_group_activity_screen.dart`), the home
/// RECENTLY rows (`home_screen.dart`), and the per-group activity timeline
/// (`group_activity_screen.dart`).
///
/// CONTRACT — MUST stay total (never throw): the group activity screen
/// resolves this during build to decide row affordance, so a throwing
/// resolution would ErrorWidget every row in its day card (the #808 P1
/// class). Keep it out of list-wide match/filter passes
/// (`activityMatchesQuery` in `activity_display.dart`) for the same reason.
/// If you add a case, never target `/group/<gid>/activity` — the group
/// activity screen suppresses only the bare group root as a self-target, so
/// a target equal to its own route would push a duplicate of itself.
///
/// [groupId] must come ONLY from fetch context (`_enrich` in
/// `cross_group_activity_pager.dart`, the dashboard provider's `group.id`,
/// or the group screen's route param) — never `log.metadata['groupId']`.
/// That key is client-forgeable (e.g. on `member_joined`) and a forged
/// groupId would cross-group-navigate. A forged eventId under the TRUE
/// groupId only ever reaches a safe not-found state on the target screen.
String activityRowTarget({
  required String groupId,
  required GroupActivityLog log,
}) {
  switch (log.type) {
    case 'expense_added':
    case 'expense_edited':
      final eventId = _navMetadataString(log, 'eventId');
      return eventId == null
          ? '/group/$groupId'
          : '/group/$groupId/event/$eventId/ledger';
    case 'expense_deleted':
      // The audit feed is the only place a deleted expense is still visible.
      final eventId = _navMetadataString(log, 'eventId');
      return eventId == null
          ? '/group/$groupId'
          : '/group/$groupId/event/$eventId/activity';
    case 'event_created':
      final eventId = _navMetadataString(log, 'eventId');
      return eventId == null
          ? '/group/$groupId'
          : '/group/$groupId/event/$eventId';
    case 'group_settlement':
      // Metadata carries no eventId even for #752 decomposed settle-ups —
      // group settle-up is the only honest target. No `?memberId=` in v1.
      return '/group/$groupId/settle-up';
    // event_deleted (target is gone), member_joined, member_left, and any
    // unknown/default type all fall through to group detail (unchanged).
    default:
      return '/group/$groupId';
  }
}

/// Type+non-empty guard for a metadata value read for NAVIGATION.
///
/// `firestore.rules`' #814 value-domain floor types 11 named metadata keys
/// but leaves `eventId`/`expenseId` OPAQUE, and legacy pre-#814 docs have no
/// floor at all — the map is client-forgeable end to end. A non-String OR
/// empty value reads as absent so a forged/legacy row degrades to the group
/// detail fallback instead of building a malformed path (an empty segment,
/// e.g. `/group/g1/event//ledger`). Deliberately NOT a reuse of
/// `activity_display.dart`'s file-private `_metadataString` (which is
/// `is String` only, without the `.isNotEmpty` guard this callsite needs).
String? _navMetadataString(GroupActivityLog log, String key) {
  final value = log.metadata[key];
  return value is String && value.isNotEmpty ? value : null;
}
```

(The switch body and guard are byte-identical to the deleted originals; only the two entry-binding locals became parameters and the docstrings widened to name the new callers + totality contract.)

**Step 2: Rewire the History row**

In `cross_group_activity_screen.dart`:
- Add import `../../activity/utils/activity_nav.dart`.
- Replace `:682` with:

```dart
      onTap: () => GoRouter.of(context)
          .push(activityRowTarget(groupId: entry.groupId, log: entry.log)),
```

- Delete `_historyRowTarget` and `_navMetadataString` (including their docstrings and the `// #840 PR-7: per-type row deep-links` section header).
- Delete the now-unused `import '../../groups/models/group_activity_log_model.dart';` (`:14`) — `GroupActivityLog` was referenced in this file only inside the deleted `_navMetadataString`; leaving it turns Task 1's `flutter analyze` red with `unused_import` (Gate round-1 P2).

**Step 3: Run the pinning tests**

Run: `flutter test test/features/home/cross_group_activity_screen_test.dart`
Expected: ALL PASS (pure refactor — the #840 block `:683+` pins per-type behavior and forged-metadata degradation).

**Step 4: Analyze + commit**

Run: `flutter analyze` → clean.
```bash
git add lib/features/activity/utils/activity_nav.dart lib/features/home/screens/cross_group_activity_screen.dart
git commit -m "refactor(activity): extract shared activityRowTarget nav util (#852)"
```

### Task 2: Home RECENTLY rows deep-link per type (RED → GREEN)

**Files:**
- Create: `test/features/home/home_recently_deeplink_test.dart`
- Modify: `lib/features/home/screens/home_screen.dart:238-239`

**Step 1: Write the failing tests**

New file `test/features/home/home_recently_deeplink_test.dart`. Harness: copy `_buildTestApp` + `_loadedOverrides` shape from `home_screen_dashboard_test.dart` (same provider set — `sharedPreferencesProvider`, `linkedEmailProvider`, `isDurableUserProvider`, `groupBalancesOnceProvider` bridge, `userGroupsProvider`, `crossGroupHomeBalanceProvider`, `crossGroupActivityProvider`, `groupBalancesProvider`, `groupEventsProvider`, `currentUserIdProvider`), but replace the router's `/group/:id` subtree with the full #840 stub set from `cross_group_activity_screen_test.dart:153-200` (GroupDetail / GroupSettleUp+query echo / EventHub / EventLedger / EventActivity text stubs). Activity entries are injected directly via `crossGroupActivityProvider.overrideWith` — no Firestore seeding. Reuse the scroll-to-RECENTLY idiom from dashboard Test 4 (`tester.drag(find.byType(CustomScrollView), const Offset(0, -600))`), then tap via `find.textContaining(..., findRichText: true)`.

Mirror the #840 block (`cross_group_activity_screen_test.dart:683-986`) for RECENTLY (entries capped at 3 per test — seed ≤3):

1. `expense_added` (metadata `{'eventId': 'ev1', 'eventName': 'Beach Trip', 'amountFils': 500, 'currency': 'OMR'}`) → tap → `find.text('EventLedger:g1/ev1')`.
2. `expense_deleted` (eventId ev1) → tap → `EventActivity:g1/ev1`.
3. `event_created` (eventId ev1) → tap → `EventHub:g1/ev1`, and `GroupDetail:g1` absent.
4. `group_settlement` (metadata with `amount`, `fromUserId`, `toUserId`, `recipientId`) → tap → `GroupSettleUp:g1?` (no query params).
5. `member_joined` → tap → `GroupDetail:g1` (unchanged bare-root behavior).
6. Forged-eventId degradation, mirroring `:913-963`: `expense_added` with `eventId` as `42`, `''`, and absent → tap → `GroupDetail:g1` and `find.byType(ErrorWidget)` findsNothing.

**Step 2: Run to verify RED**

Run: `flutter test test/features/home/home_recently_deeplink_test.dart`
Expected: tests 1-4 + 6 FAIL (today every tap lands on `GroupDetail:g1`); test 5 passes. Paste the failing output into the PR body (RED evidence).

**Step 3: Implement**

`home_screen.dart` — add import `../../activity/utils/activity_nav.dart`; replace `:238-239`:

```dart
                            onTap: () => context.push(
                              activityRowTarget(
                                groupId: entry.groupId,
                                log: entry.log,
                              ),
                            ),
```

**Step 4: Run to verify GREEN**

Run: `flutter test test/features/home/home_recently_deeplink_test.dart test/features/home/home_screen_dashboard_test.dart`
Expected: ALL PASS.

**Step 5: Commit**

```bash
git add lib/features/home/screens/home_screen.dart test/features/home/home_recently_deeplink_test.dart
git commit -m "feat(home): RECENTLY rows deep-link per activity type (#852)"
```

### Task 3: Group activity rows — tappable, self-targets inert (RED → GREEN)

**Files:**
- Modify: `lib/features/groups/screens/group_activity_screen.dart` (`_buildBody` day-section construction `:252-257`, `_DaySection` `:436-491`, `_ActivityRow` `:494-589`)
- Test: `test/features/groups/group_activity_screen_test.dart` (extend `_buildActivityRoute`'s router `:156-172` with nested stubs; new test group)

**Step 1: Extend the test router + write the failing tests**

In `_buildActivityRoute`, add under the existing `/group/:gid` route (sibling of `activity`), mirroring the cross-group harness stubs:

```dart
          GoRoute(
            path: 'settle-up',
            builder: (context, state) => Scaffold(
              body: Text('GroupSettleUp:${state.pathParameters['gid']}'),
            ),
          ),
          GoRoute(
            path: 'event/:eid',
            builder: (context, state) => Scaffold(
              body: Text(
                'EventHub:${state.pathParameters['gid']}/'
                '${state.pathParameters['eid']}',
              ),
            ),
            routes: [
              GoRoute(
                path: 'ledger',
                builder: (context, state) => Scaffold(
                  body: Text(
                    'EventLedger:${state.pathParameters['gid']}/'
                    '${state.pathParameters['eid']}',
                  ),
                ),
              ),
              GoRoute(
                path: 'activity',
                builder: (context, state) => Scaffold(
                  body: Text(
                    'EventActivity:${state.pathParameters['gid']}/'
                    '${state.pathParameters['eid']}',
                  ),
                ),
              ),
            ],
          ),
```

New test group `'row deep-links (#852)'`, each seeding via the file's existing seed helper + pumping `_buildActivityRoute(groupId: 'grp-1', ...)`:

1. `expense_added` with eventId `ev1` → tap row (rich-text finder) → `EventLedger:grp-1/ev1`.
2. `group_settlement` → tap (`find.byIcon(Iconsax.wallet_3)`) → `GroupSettleUp:grp-1`.
3. `event_created` with eventId → tap → `EventHub:grp-1/ev1`.
4. **Inert self-target:** `member_joined` → tap → still on the activity screen (`GroupKeys.activityScreen` present, `GroupDetail:grp-1` absent).
5. **Inert guard-degraded:** `expense_added` with `metadata: {'eventId': 42}` → tap → still on the activity screen, `find.byType(ErrorWidget)` findsNothing.

**Step 2: Run to verify RED**

Run: `flutter test test/features/groups/group_activity_screen_test.dart`
Expected: new tests 1-3 FAIL (rows have no onTap — tap is a no-op, target screens never appear); 4-5 pass trivially; all pre-existing tests still pass. Paste failing output (RED evidence).

**Step 3: Implement**

`group_activity_screen.dart`:
- Add import `../../activity/utils/activity_nav.dart`.
- `_buildBody` `:252` passes `groupId: widget.groupId` to `_DaySection`.
- `_DaySection` gains `required this.groupId` (`final String groupId;`) and passes it to `_ActivityRow`.
- `_ActivityRow` gains `required this.groupId`; wrap its `Padding` in an `InkWell`:

```dart
    // #852: per-type deep-link shared with the History tab (activity_nav.dart).
    // A target resolving to this screen's own group root (member_*,
    // event_deleted, unknown types, or a guard-degraded eventId) stays inert —
    // pushing a duplicate of the parent screen is the false-affordance class
    // this issue removes, and a null onTap honestly drops the ripple.
    final target = activityRowTarget(groupId: groupId, log: log);
    final selfTarget = target == '/group/$groupId';
    return InkWell(
      onTap: selfTarget
          ? null
          : () => GoRouter.of(context).push(target),
      child: Padding(
        // ... existing body unchanged ...
```

**Step 4: Run to verify GREEN**

Run: `flutter test test/features/groups/group_activity_screen_test.dart test/features/groups/group_activity_filter_memo_test.dart`
Expected: ALL PASS (memo test guards the #634 filter cache against the new params).

**Step 5: Commit**

```bash
git add lib/features/groups/screens/group_activity_screen.dart test/features/groups/group_activity_screen_test.dart
git commit -m "feat(groups): activity rows deep-link per type; self-targets stay inert (#852)"
```

### Task 4: Full verify + PR

**Step 1:** `flutter analyze` → clean.
**Step 2:** `flutter test` → full suite green.
**Step 3:** `bash tool/check_theme_purity.sh` → clean (no new colors, but the InkWell wrap touches a styled file).
**Step 4:** PR: branch `feat/852-activity-row-deeplinks`; body carries `Closes #852`, `Spec: docs/plans/2026-07-03-852-activity-row-deeplinks.md`, the decision record (a1 + inert-self-target rationale + event-feed out-of-scope note), and the pasted RED evidence from Tasks 2-3. Route through `/automerge` (Gate category: routing).
