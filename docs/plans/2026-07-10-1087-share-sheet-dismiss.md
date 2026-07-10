# #1087 — Post-create share sheet: every dismissal navigates to the created group

> **For Claude:** Delegated implementation (Codex executes; the delegating session re-verifies everything — Codex's sandbox cannot run `flutter test`, so no green/RED claim from Codex is trusted).

**Goal:** After a group is successfully created, dismissing the share sheet by ANY means (Done, drag-down, tap-outside, system back) lands on `/group/:gid` — never back on the stale creation form, whose re-enabled Create button mints a duplicate group.

**Architecture:** `_showSharePrompt` (`lib/features/groups/screens/create_group_screen.dart:238`) already `await`s `showModalBottomSheet`, which resolves on every dismissal path. Move the `pushReplacement` from the sheet's Done callback to after that await; Done becomes a plain `Navigator.pop`. One file, one test file.

**Tech stack:** Flutter widget tests, `mocktail`, GoRouter test router. Mirror the harness in `test/features/groups/create_group_offline_412_test.dart` (`_MockGroupService`, `stageGroup` stub, `GoRouter` with a stub `/group/:gid` route, `sharedPreferencesProvider` override — mandatory in every app-booting test).

**Constraints (project contract):**
- Bug fix ⇒ failing regression test FIRST. The delegating session regenerates genuine RED after the fact, but author the test before the fix and structure commits test-first anyway.
- `Closes #1087` goes in the COMMIT MESSAGE body (squash-merge auto-close reads the commit, not the PR body).
- No new comments unless the WHY is non-obvious (issue-number comments are house idiom).
- Don't touch `_close()` (pre-create cancel) or the `notificationPrompt.maybePrompt()` ordering.

---

### Task 1: Failing regression test

**Files:**
- Create: `test/features/groups/create_group_share_sheet_dismiss_1087_test.dart`
- Reference (read first, mirror its harness exactly): `test/features/groups/create_group_offline_412_test.dart`

**Step 1: Write the test file.** Three cases, one shared harness:

1. `'barrier-tap dismissal of the post-create share sheet lands on the group (#1087)'` — pump the create screen via the reference harness (stub `stageGroup` to return a staged group `g1` with an already-completed ack future = online/acked path; stub `addShadowMember` unused). Enter a group name + display name, tap Create, `pumpAndSettle` until the share sheet is visible (assert via the sheet's group-name `Text` or `InviteCodeDisplay`). Then tap the modal barrier: `await tester.tapAt(const Offset(10, 60)); await tester.pumpAndSettle();`. Assert the router landed on the stub group route (e.g. `expect(find.text('GroupDetail:g1'), findsOneWidget)` where the stub `/group/:gid` route renders `Text('GroupDetail:${id}')`), and the creation form is gone.
2. `'drag-down dismissal lands on the group (#1087)'` — same setup; dismiss with `await tester.drag(find.byType(BottomSheet), const Offset(0, 400)); await tester.pumpAndSettle();` then the same assertion.
3. `'Done keeps navigating (#1087 regression guard)'` — same setup; tap the Done `TextButton` (`context.l10n.commonDone` == the EN string used in the sheet — find it via `find.widgetWithText(TextButton, 'Done')`), `pumpAndSettle`, same assertion.

Notes for the harness:
- The offline_412 test's `wrap()` builds `MaterialApp.router` + `ProviderScope` with `sharedPreferencesProvider.overrideWithValue(prefs)` and a mocked `GroupService`. Reuse that shape verbatim; the router needs routes for the create screen AND a stub `/group/:groupId`.
- `settingsProvider.notifier.setDeviceName` runs before create — the offline_412 harness already handles it (check how; keep identical).
- If the screen lands on an `EmptyStateView`-bearing state, end with `pumpAndSettle()` (flutter_animate ticker teardown rule).

**Step 2: Run it — expect cases 1 and 2 to FAIL** (user remains on the creation form; `GroupDetail:g1` not found) and case 3 to PASS. If the sandbox cannot run `flutter test`, note that in the final report and rely on static review; the delegator regenerates RED.

**Step 3: Commit** — `test(groups): RED — share-sheet dismissal strands the creation form (#1087)`.

### Task 2: The fix

**Files:**
- Modify: `lib/features/groups/screens/create_group_screen.dart:238-256` (`_showSharePrompt`)

**Step 1:** Replace `_showSharePrompt` with:

```dart
  Future<void> _showSharePrompt(BuildContext context, Group group) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.colors.cardSurface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => _SharePrompt(
        group: group,
        onNavigate: () => Navigator.pop(sheetContext),
      ),
    );
    // #1087: the group already exists — every dismissal path (Done, drag,
    // barrier tap, system back) must leave the creation form, or its
    // re-enabled Create button mints a duplicate group.
    if (!mounted) return;
    context.pushReplacement('/group/${group.id}');
  }
```

(`mounted` is the `State.mounted` of the surrounding `ConsumerState`. The Done path is now pop → await resolves → same `pushReplacement`, so ordering relative to `notificationPrompt.maybePrompt()` in `_createGroup` is unchanged.)

**Step 2:** Run the new test file — all 3 cases green. Run the sibling suites: `flutter test test/features/groups/` (a comment in `create_join_group_test.dart:36` says those tests "never dismiss" the sheet — they should be unaffected; if one asserts post-Done behavior, it must still pass unmodified).

**Step 3:** `flutter analyze` clean.

**Step 4: Commit** — body must contain `Closes #1087`:

```
fix(groups): navigate to the created group on ANY share-sheet dismissal

Drag/barrier/system-back previously stranded the user on the stale
creation form; its re-enabled Create button minted a duplicate group.

Closes #1087
```

### Task 3: Report

Final message: list files changed, test names added, exact commands you ran (or could not run) and their output. Do NOT claim tests passed if you could not run them — say so plainly. If you could not commit via git (read-only worktree metadata), leave a `git bundle` at the worktree root and say so.
