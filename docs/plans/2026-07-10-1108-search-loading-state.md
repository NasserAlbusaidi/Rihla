# #1108 Search Loading State Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep global search from showing “No matches” until auth, groups, and the watched group-event streams have delivered their first values.

**Architecture:** `SearchResults` keeps its existing groups-and-events-only fan-out. It resolves `firebaseUserProvider` before watching `userGroupsProvider`, which prevents the cold-auth false-empty branch from starting, records unresolved first snapshots from `groupEventsProvider`, and renders a small progress state only when unresolved data would otherwise collapse to `_NoMatches`. Existing group or event hits remain visible while unrelated event streams load.

**Tech Stack:** Flutter, Riverpod 2.x `AsyncValue`, Flutter widget tests.

## Global Constraints

- Preserve the Falaj PR-5b scope: group and event names only; never watch expenses or settlements.
- Do not touch `security/firestore.rules`, `functions/**`, or `**/models/**.dart`.
- Write and run the failing regression test before changing production code; preserve the exact RED output for the PR body.
- Use existing theme tokens and directional layout APIs. Run `bash tool/check_theme_purity.sh` after changing widget code.
- The final commit body must contain `Closes #1108`.

---

### Task 1: Pin both first-snapshot races

**Files:**
- Create: `test/features/search/search_loading_state_1108_test.dart`
- Reference: `test/features/search/search_navigation_test.dart`

**Interfaces:**
- Consumes: `firebaseUserProvider`, `userGroupsProvider`, `groupEventsProvider`, `SearchResults`, and `SearchKeys.emptyState`.
- Produces: two widget regressions that fail when unresolved search inputs render the confirmed-empty state.

- [ ] **Step 1: Add the focused widget harness and regression cases**

Build `SearchResults(query: 'Alps')` under `ProviderScope` and `MaterialApp` with `AppTheme.lightTheme` and the generated localization delegates. Use `StreamController<User?>` to hold auth in its first `AsyncLoading`, and `StreamController<List<Event>>` to hold one group’s event stream in its first `AsyncLoading`.

Add these tests:

```dart
testWidgets(
  'cold auth loading does not render confirmed no-matches state (#1108)',
  (tester) async {
    final auth = StreamController<User?>();
    addTearDown(auth.close);

    await _pumpResults(
      tester,
      overrides: [
        firebaseUserProvider.overrideWith((ref) => auth.stream),
      ],
    );

    expect(find.byKey(SearchKeys.emptyState), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  },
);
```

Leave the real `userGroupsProvider` active in this case. Its `uid == null` branch emits `Stream.value([])` while the overridden auth stream remains unresolved, reproducing the exact cold-start false-settled pair instead of merely constructing it in the test.

```dart
testWidgets(
  'unresolved event stream does not render confirmed no-matches state (#1108)',
  (tester) async {
    final events = StreamController<List<Event>>();
    addTearDown(events.close);
    final group = _group('g1', 'Desert Crew');

    await _pumpResults(
      tester,
      overrides: [
        firebaseUserProvider.overrideWith((ref) => Stream.value(null)),
        userGroupsProvider.overrideWith((ref) => Stream.value([group])),
        groupEventsProvider(group.id).overrideWith((ref) => events.stream),
      ],
    );

    expect(find.byKey(SearchKeys.emptyState), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  },
);
```

Pump bounded frames instead of `pumpAndSettle`; the post-fix progress indicator animates indefinitely while each controller remains unresolved.

- [ ] **Step 2: Run the test and capture genuine RED**

Run:

```bash
flutter test test/features/search/search_loading_state_1108_test.dart
```

Expected: both cases fail because `SearchKeys.emptyState` is present and no `CircularProgressIndicator` is rendered. Save the complete terminal output verbatim for the PR body.

- [ ] **Step 3: Commit the regression test and plan**

```bash
git add docs/plans/2026-07-10-1108-search-loading-state.md \
  test/features/search/search_loading_state_1108_test.dart
git commit -m "test(search): reproduce unresolved-stream false empty state"
```

### Task 2: Gate only the confirmed-empty collapse

**Files:**
- Modify: `lib/features/search/widgets/search_results.dart`
- Test: `test/features/search/search_loading_state_1108_test.dart`

**Interfaces:**
- Consumes: the existing `AsyncValue<User?>`, `AsyncValue<List<Group>>`, and `AsyncValue<List<Event>>` providers.
- Produces: `_LoadingState`, a private display-only widget; no provider, route, persistence, or schema contract changes.

- [ ] **Step 1: Track initial auth and group loading before reading groups**

Resolve auth before starting the groups watch, then replace the eager `valueOrNull ?? []` read with the groups `AsyncValue`:

```dart
final userAsync = ref.watch(firebaseUserProvider);
if (userAsync.isLoading && !userAsync.hasValue) {
  return const _LoadingState();
}

final groupsAsync = ref.watch(userGroupsProvider);
if (groupsAsync.isLoading && !groupsAsync.hasValue) {
  return const _LoadingState();
}

final groups = groupsAsync.valueOrNull ?? const <Group>[];
```

The auth check must precede the groups watch. Otherwise `userGroupsProvider` can start while auth lacks its first value and emit the false `AsyncData([])` described in #1108.

- [ ] **Step 2: Track unresolved event streams without hiding partial matches**

Within the existing per-group loop, watch the full event `AsyncValue`, set `hasUnresolvedEvents` only for first-load/no-value state, and continue matching any delivered data:

```dart
var hasUnresolvedEvents = false;
for (final group in groups) {
  final eventsAsync = ref.watch(groupEventsProvider(group.id));
  if (eventsAsync.isLoading && !eventsAsync.hasValue) {
    hasUnresolvedEvents = true;
    continue;
  }
  final events = eventsAsync.valueOrNull ?? const <Event>[];
  // Existing deleted-event guard and name matching remain unchanged.
}
```

Gate only the empty collapse:

```dart
if (matchedGroups.isEmpty && eventHits.isEmpty) {
  if (hasUnresolvedEvents) return const _LoadingState();
  return const _NoMatches();
}
```

This placement preserves already-known group and event hits while another group’s first event snapshot is pending.

- [ ] **Step 3: Add the private lightweight loading widget**

```dart
class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}
```

- [ ] **Step 4: Run focused GREEN verification**

```bash
flutter test test/features/search/search_loading_state_1108_test.dart
flutter test test/features/search/
bash tool/check_theme_purity.sh
```

Expected: every command exits 0. The existing unresolved-event smart-forward test must still find and tap its matching group, proving partial results remain visible.

- [ ] **Step 5: Run repository verification**

```bash
flutter test
flutter analyze
git diff --check
```

Expected: every command exits 0 with no analyzer issues or whitespace errors.

- [ ] **Step 6: Commit the fix**

```bash
git add lib/features/search/widgets/search_results.dart
git commit -m "fix(search): distinguish loading from confirmed empty" \
  -m "Cold auth and first event snapshots no longer flash No matches." \
  -m "Closes #1108"
```

### Task 3: Review and publish

**Files:**
- Review: the complete `origin/main...HEAD` diff

**Interfaces:**
- Consumes: the two commits and saved RED output.
- Produces: one pushed branch and one GitHub PR that closes issue #1108.

- [ ] **Step 1: Review branch scope**

```bash
git status --short --branch
git diff --stat origin/main...HEAD
git diff origin/main...HEAD -- \
  docs/plans/2026-07-10-1108-search-loading-state.md \
  test/features/search/search_loading_state_1108_test.dart \
  lib/features/search/widgets/search_results.dart
```

Expected: only the plan, focused regression test, and search results widget changed.

- [ ] **Step 2: Push and open the PR**

```bash
git push -u origin fix/1108-search-loading-state
gh pr create --base main --head fix/1108-search-loading-state
```

The PR body must include a concise summary, `Closes #1108`, exact test commands and results, and the complete failing-before-fix output under `RED evidence`.
