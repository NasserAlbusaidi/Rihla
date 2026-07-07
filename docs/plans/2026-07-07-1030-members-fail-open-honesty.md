# #1030 Members-Stream Fail-Open Honesty Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** A `groups/{gid}/members` stream hard error (`hasError && !hasValue`) can no longer silently re-shape the #249 balance universe into wrong money on any OUTBOUND basis (event settle-up, group settle-up, #773 revalidation, snapshot-at-close) or render false-clean nets on the hub header / recap / ledger surfaces.

**Architecture:** Mirror the #1028 shape exactly — the #1005 per-event-guard vocabulary (`hasError && !hasValue` = hard error → loud; stale-valued error → keep serving; `isLoading && !hasValue` = first-value window → skeleton/pending) applied to the members stream at each surface. No new providers, no universe-semantics change, no rules/server change.

**Tech Stack:** Flutter/Riverpod 2.x, `flutter_test` + FakeFirebaseFirestore overrides.

**Spec:** this document. **Issue:** #1030. **Gate:** mandatory (money surface).

---

## Why members is the worst fail-open class

`eventBalanceUniverse` (`lib/features/ledger/providers/expense_provider.dart:106-151`) folds departed split recipients via `splitRecipientKeys.intersection(allMemberIds).difference(liveMemberIds)`. With `members == []` both sets are empty → every departed recipient's owed is silently dropped AND tombstone/live distinction vanishes → the computed nets are **wrong money relative to the server oracle**, not merely incomplete. There is **no provably-safe degrade without members**: without `allMemberIds` you cannot distinguish a departed member (must fold, #249) from a never-member key (must drop, oracle parity #249/oracle contract) — any guess diverges from `recomputeNet`. Loud is the only honest option. Precedent: `groupBalancesOnceProvider` already made members failures loud on purpose (#997 D3, `group_balance_provider.dart:764-772` comment: "members=[] re-opens the #249 universe gap (WRONG money, not incomplete money)").

## Verification report (7 principles, run 2026-07-07 in worktree at `origin/main`)

1. **Callsite classification — every `groupMembersProvider` consumer** (grep `groupMembersProvider(` in `lib/`, 14 hits):
   - `settle_up_screen.dart:213` build fold → **OUTBOUND** (universe → suggestions → settlement write) — Task 3.
   - `settle_up_screen.dart:559` `_freshOutstandingForPair` → **OUTBOUND** (#773 pre-write cap) — Task 4.
   - `group_balance_provider.dart:154` live group basis → **OUTBOUND** (group settle-up decompose reads it at `group_settle_up_screen.dart:627` and as `balancesData`) — Task 2.
   - `group_balance_provider.dart:749` once-provider → already loud (#997 D3) ✓ no change.
   - `ledger_view_provider.dart:69-71` fold → transitive, reaches: hub header (`event_command_center.dart:188`, Task 5), snapshot-at-close (`event_danger_section.dart:351`, **OUTBOUND write** — Task 6), recap (`event_recap_provider.dart:19` + `event_recap_screen.dart:70`, Task 7), ledger screen (`ledger_screen.dart:146`, Task 8), receipt (`trip_receipt_provider.dart:83` — **already gated**, see principle 2).
   - `group_presettle_review_provider.dart:46` — already error-aware (members error → empty active set, payer check skipped, other reasons fire; `membersSettled = hasValue || hasError`) ✓ no change.
   - `trip_receipt_provider.dart:59` — already gated: required-input check `for (a in [event, expenses, settlements, members]) if (a.hasError) return AsyncValue.error` + `isLoading` → loading (`trip_receipt_provider.dart:60-78`). **The issue's claim that this site "does NOT error-handle" is STALE** — Task 9 pins it with a test instead.
   - `create_event_screen.dart:264/292` — full `membersAsync.when` with real error state (#488) ✓ no change.
   - `expense_editor_body.dart:735`, `split_scope_selector.dart:42` — shadow-marker labels only, documented "purely additive, empty set renders no markers" → INBOUND-safe ✓ no change.
   - `group_detail_screen.dart:142/156` — display; watches members directly and surfaces its terminal error (`membersHasError`); #574 staging retry covers the denial window ✓ no change (but see "Out of scope" for the `_BalanceCard` sibling gap).
   - `group_settings_screen.dart:33` — member management display, not money ✓ no change.
2. **Concrete claims re-verified in-session:** universe fold `expense_provider.dart:106-151`; settle-up fold `settle_up_screen.dart:213-225`, sheet gate `:295-318`, `_balancesErrorView` `:424-450` (retry invalidates expenses+settlements only — extended in Task 3), revalidation fold `:558-559`, revalidation caller null-skip `:689-708`; group provider loading guard `:155-157`, fold `:158`, settlements loud gate `:168-173` (the template C3 mirrors); hub gates `event_command_center.dart:204-215`, `_HubState` `:374`; snapshot capture `event_danger_section.dart:338-357`, `SpendingSnapshot.from` `spending_snapshot.dart:55-82` (`owedByCurrency` ← `balances[].totalOwed`), null-snapshot degrade documented at `:343-345` ("recap stays live, recoverable by reopen+close"); receipt gate `trip_receipt_provider.dart:60-78`; recap screen watches only `eventDetailProvider` (`event_recap_screen.dart:52`); ledger screen gate `ledger_screen.dart:88-95` (bare `hasError`, expenses+settlements only); group settle-up consumes the provider via `.when` with an error branch (`group_settle_up_screen.dart:186`, error at `:340`) and null-skips revalidation (`:627-628`); `groupPreSettleReviewProvider` handles `balancesAsync.hasError` (`group_presettle_review_provider.dart:87-89`); l10n `settleUpCouldNotLoadBalances` (`app_en.arb:799`), `commonRetry` (`app_en.arb:466`).
3. **One read-path per write-path:** the event settlement write reads the on-screen suggestion basis (Task 3) and the #773 revalidation basis (Task 4); the group decompose write reads `groupBalancesProvider` (Task 2 makes it loud; `group_settle_up_screen.dart:627` `.valueOrNull` → null → documented skip); the `spendingSnapshot` write is read back by `EventRecap.fromSnapshot` on every closed-event recap open (Task 6).
4. **Fields enumerated from the type:** `GroupBalances` record (6 fields, `group_balance_provider.dart:104-111`) — a members-error basis corrupts `balances`, `perEventBreakdown` (participant-name resolution), `memberNames`, `memberRawNames` (OUTBOUND — feeds settlement writes). `SpendingSnapshot.from` consumes `recap` + `balances` only.
5. **Data contracts spelled out:** exact gate expressions, exact keys (`EventKeys.balanceHeaderUnavailable`/`balanceHeaderPending` — existing, reused), exact l10n keys (`recapDataUnavailable` new EN+AR; all others existing), exact test names — in the tasks below.
6. **Arithmetic decomposition:** unchanged — no allocator, oracle, or universe-semantics change anywhere in this plan. The fix is strictly "refuse to compute from a members-less basis", never "compute differently".
7. **Orthogonal-axis adversarial pass (self-run):** *identity axis* — a members error hides tombstone flags, so `liveMemberIds` inflation/deflation corrupts payer-left detection and #249 folds in BOTH directions (over- and under-count); *time axis* — the first-value loading window (`isLoading && !hasValue`) folds identically to the error case, so Tasks 3/5 gate it too (skeleton/pending), mirroring #1028's C2; *money-flow axis* — `memberRawNames` feeds the settlement write's name fields, so a members-less basis also writes wrong names, another reason loud-not-degrade; *scope axis* — group-level (Task 2) and event-level (Task 3) surfaces fail independently; the hub (Task 5) fails transitively through a different provider than the settle-up screen it sits above.

## Contract change (Gate attention): #204/#898 review-sheet fallback re-scoped

The pinned contract (`settle_up_screen_test.dart:377-405` — "member-provider errors do not suppress existing review reasons") was written when a members hard error still RENDERED the settle-up basis; the sheet's warnings compensated for what the basis couldn't know (payer-left). After Task 3 a members **hard** error (`hasError && !hasValue`) renders `_balancesErrorView` INSTEAD of the basis — there are no suggestions to warn about and **no settle write is reachable from the screen at all**, which strictly dominates "warn but allow". The fallback contract survives on the only leg where a basis still renders: a **stale-valued** members error (`hasError && hasValue`) keeps serving the stale members through the FULL detector (the existing `hasValue` branch — payer-left included). The `else if (groupMembersAsync.hasError)` reduced-detector branch (`settle_up_screen.dart:316-318`) becomes unreachable and is removed. The pinned test is re-scoped (hard error → loud view), and a NEW test pins the stale-valued leg (sheet still fires with warnings). `settle_up_review_suppression_test.dart` has no members-error cases (verified — only a settlements `Stream.error` at `:283`) → untouched.

## Out of scope (do not bundle)

- **Group detail `_BalanceCard` false-settled on an errored provider** (`group_detail_screen.dart:640-641`: `lines.isEmpty → groupAllSettled`, fed by `balancesAsync.valueOrNull` at `:181`): pre-existing for events/settlements hard errors since #1028 made the provider loud; members joins the SAME channel, no new class. File as a follow-up issue at close-out (same false-clean family as #1017/#1028; display-only, its settle CTA leads to the gated group settle-up screen).
- `groupSpendingSummaryProvider` (`group_spending_summary_provider.dart:23` folds `balances` null-safe) — display-only top-payer/top-consumer chips; a members error now yields a null balances fold (summary renders from expenses only). Same follow-up issue.
- Any `ledgerViewProvider` internal error-awareness refactor (returning `AsyncValue<LedgerView>`) — bigger surface, all 6 consumers churn; the per-screen gates here are the #1028-consistent shape.

---

### Task 1: RED — `groupBalancesProvider` members hard error must be loud

**Files:**
- Test: `test/unit/group_balance_provider_test.dart`

**Step 1: Write the failing test** (mirror the #1028 group-settlements loud test in the same file — same harness, same override style):

```dart
test(
  '#1030: members hard error → groupBalancesProvider errors, '
  'never an empty-members wrong basis',
  () async {
    // Harness identical to the #1028 settlements-error test in this file,
    // except groupMembersProvider is the errored stream:
    //   groupMembersProvider(gid).overrideWith(
    //     (_) => Stream<List<GroupMember>>.error(
    //       FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'),
    //     ),
    //   )
    // events / per-event expenses/settlements / group settlements all valued.
    final result = container.read(groupBalancesProvider(gid));
    expect(result, isA<AsyncError<GroupBalances>>());
  },
);
```

Also a sibling healthy-path pin if the existing #1028 test doesn't already cover it (it does — don't duplicate).

**Step 2: Run it, verify it fails for the right reason**

Run: `flutter test test/unit/group_balance_provider_test.dart --plain-name "1030"`
Expected: FAIL — result is `AsyncData` (the fold-to-`[]` bug).

### Task 2: GREEN — members loud gate in `groupBalancesProvider`

**Files:**
- Modify: `lib/features/groups/providers/group_balance_provider.dart:154-158`

**Step 1: Implementation.** Replace:

```dart
  final membersAsync = ref.watch(groupMembersProvider(groupId));
  if (membersAsync.isLoading && !membersAsync.hasValue) {
    return const AsyncValue.loading();
  }
  final members = membersAsync.valueOrNull ?? [];
```

with:

```dart
  final membersAsync = ref.watch(groupMembersProvider(groupId));
  if (membersAsync.isLoading && !membersAsync.hasValue) {
    return const AsyncValue.loading();
  }
  // #1030: a hard-errored members stream must be LOUD — members=[] re-shapes
  // the #249 universe (departed split recipients dropped) into WRONG money on
  // the OUTBOUND group settle-up basis, and memberRawNames feeds the
  // settlement write. Mirrors the once-provider's members-loud semantics
  // (#997 D3) and the group-settlements gate below. Stale-valued errors keep
  // serving (per-event-guard vocabulary).
  if (membersAsync.hasError && !membersAsync.hasValue) {
    return AsyncValue.error(membersAsync.error!, membersAsync.stackTrace!);
  }
  final members = membersAsync.valueOrNull ?? [];
```

**Step 2: Run the Task 1 test** — Expected: PASS.

**Step 3: Run the file + consumer suites**

Run: `flutter test test/unit/group_balance_provider_test.dart test/features/groups/`
Expected: PASS. Consumers verified in-session: `group_settle_up_screen.dart:186` `.when` error branch; `:627` revalidation `.valueOrNull` → null → documented captured-snapshot fallback; `group_presettle_review_provider.dart:87-89` `hasError` branch; `group_detail_screen.dart:171-173` `deniedBalances` staging; `group_danger_section.dart:186/:213/:295` + `group_members_section.dart:202` null-safe `.valueOrNull` server-authority fall-throughs (#1028-audited). **Stale comment fix (same commit):** `group_detail_screen.dart:152-155` says the provider "SWALLOWS a members error into empty data" — update the comment (direct members watch is still needed there for retry + the members-card terminal error).

**Step 4: Commit** — `fix(groups): #1030 members hard error makes groupBalancesProvider loud`

### Task 3: Event settle-up basis — loud members gate + #204 re-scope

**Files:**
- Modify: `lib/features/ledger/screens/settle_up_screen.dart` (`:213-225` fold, `:238-244` gate block, `:295-318` sheet, `:424-450` retry)
- Test: `test/features/ledger/settle_up_screen_test.dart`

**Step 1: RED — re-scope the pinned #204 test and add the stale-valued pin.** Replace the body of `'#204: member-provider errors do not suppress existing review reasons'` (`:377-405`) with the new contract and rename:

```dart
testWidgets(
  '#1030: members HARD error → loud balances error view, no basis, no sheet',
  (tester) async {
    final fakeDb = FakeFirebaseFirestore();
    await tester.pumpWidget(
      buildScreen(
        fakeDb,
        expensesStream: Stream.value([/* exact-split e1 as before */]),
        groupMembersStream:
            Stream<List<GroupMember>>.error(StateError('members failed')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text("Couldn't load balances."), findsOneWidget);
    expect(find.byKey(PreSettleReviewKeys.sheet), findsNothing);
  },
);

testWidgets(
  '#1030 (#204/#898 preserved): members STALE-VALUED error → basis renders, '
  'sheet still shows warnings',
  (tester) async {
    final fakeDb = FakeFirebaseFirestore();
    final members = StreamController<List<GroupMember>>();
    await tester.pumpWidget(
      buildScreen(
        fakeDb,
        expensesStream: Stream.value([/* exact-split e1 as before */]),
        groupMembersStream: members.stream,
      ),
    );
    members.add(const []); // value first…
    await tester.pump();
    members.addError(StateError('members failed')); // …then error → stale-valued
    await tester.pumpAndSettle();
    expect(find.byKey(PreSettleReviewKeys.sheet), findsOneWidget);
    expect(find.text('Exact split'), findsOneWidget);
    await members.close();
  },
);
```

(Adapt names/fixtures to the file's existing `buildScreen` harness — it already takes `groupMembersStream`, `:102-120`.)

**Step 2: Run** `flutter test test/features/ledger/settle_up_screen_test.dart --plain-name "1030"` — Expected: BOTH FAIL (hard error currently renders sheet; no loud view).

**Step 3: Implementation.**
1. After the #1028 settlements gates (`:238-243`), add inside the `data:` branch:

```dart
          // #1030: a hard-errored members stream must not fold to [] — the
          // #249 universe intersects split recipients with allMemberIds, so
          // empty members computes WRONG money on this OUTBOUND basis (and
          // userRawNames feeds the settlement write). Stale-valued errors
          // keep serving; the first-value window gets the same skeleton as
          // the settlements leg. The #204/#898 review-sheet fallback is
          // re-scoped to the stale-valued leg — under a hard error no settle
          // write is reachable at all, which dominates "warn but allow".
          if (groupMembersAsync.hasError && !groupMembersAsync.hasValue) {
            return _balancesErrorView(context, eventRef);
          }
          if (groupMembersAsync.isLoading && !groupMembersAsync.hasValue) {
            return SkeletonLoader.groupList();
          }
```

2. Delete the now-unreachable reduced-detector branch (`:316-318`, `else if (groupMembersAsync.hasError) { _maybeShowReviewSheet(context, expenses, outstandingCurrencies); }`) and its share of the `:295` comment; note the re-scope in the surviving comment. The `if (groupMembersAsync.hasValue)` wrapper also simplifies away (always true past the gates — keep or flatten, prefer flatten with a one-line comment).
3. `_balancesErrorView` (`:424`): add `ref.invalidate(groupMembersProvider(widget.groupId));` to the retry and extend its doc comment ("a members-triggered error could never heal off the money-stream invalidates").

**Step 4: Run** the two new tests → PASS; then the full file: `flutter test test/features/ledger/settle_up_screen_test.dart` — sweep for any other test relying on the members fold (grep `groupMembersStream` — fixture-fix, don't weaken).

**Step 5: Commit** — `fix(ledger): #1030 settle-up basis loud on members hard error, #204 fallback re-scoped to stale-valued leg`

### Task 4: #773 revalidation — skip on valueless members

**Files:**
- Modify: `lib/features/ledger/screens/settle_up_screen.dart:558-559`
- Test: `test/features/ledger/settle_up_revalidation_test.dart`

**Step 1: RED.** Mirror the file's existing #1028 settlements-skip test: members override that is valueless at revalidation time (e.g. `Stream<List<GroupMember>>.error(...)` swapped in before the record-sheet confirm, or a never-emitting stream via the harness's re-override pattern — reuse whatever mechanism the settlements-skip test uses) → the over-cap write is NOT blocked-by-wrong-cap / the revalidation is skipped exactly like the expenses/settlements legs. Name: `'#1030: valueless members read skips #773 revalidation like the money legs'`.

**Step 2: Run it** — Expected: FAIL (today members folds to `[]` and revalidation recomputes against a wrong universe).

**Step 3: Implementation.** Replace `:558-559`:

```dart
    final groupMembers =
        ref.read(groupMembersProvider(widget.groupId)).valueOrNull ?? const [];
```

with:

```dart
    // #1030: a valueless members read (loading or hard error) must SKIP
    // revalidation like the expenses/settlements legs — folding it to []
    // recomputes the cap against the wrong #249 universe. Stale values serve.
    final membersAsync = ref.read(groupMembersProvider(widget.groupId));
    if (!membersAsync.hasValue) return null;
    final groupMembers = membersAsync.requireValue;
```

**Step 4: Run** the new test + `flutter test test/features/ledger/settle_up_revalidation_test.dart` — PASS.

**Step 5: Commit** — `fix(ledger): #1030 #773 revalidation skips on valueless members read`

### Task 5: Hub header — members joins the unavailable/pending gates

**Files:**
- Modify: `lib/features/events/screens/event_command_center.dart:184-215`
- Test: `test/features/events/event_hub_balance_error_states_test.dart`

**Step 1: RED.** Two tests in the existing harness (it already overrides `groupMembersProvider`, `:143`):
- `'#1030: members-only hard error → hub header unavailable, never clean nets'` — members `Stream.error`, expenses/settlements valued with money that WOULD render nets → expect `EventKeys.balanceHeaderUnavailable`, and the #1028 assertion style for "no amount lines rendered".
- `'#1030: members first-value window → hub header pending'` — members stream never emits (`StreamController` without add) → expect `EventKeys.balanceHeaderPending`.

**Step 2: Run** — Expected: both FAIL (header renders computed-without-members nets as clean).

**Step 3: Implementation.** Add beside the existing stream watches (`:184-186`):

```dart
    final membersAsync = ref.watch(groupMembersProvider(widget.groupId));
```

Extend both gates (`:205-211`) — members added as a third leg to `balanceUnavailable` and `balancePending`, same vocabulary, and extend the #1028 comment (`:198-204`) with one line: `// #1030: members joins both gates — ledgerViewProvider folds it too, and a members-less universe is wrong nets, not fewer nets.`

**Step 4: Run** the file — `flutter test test/features/events/event_hub_balance_error_states_test.dart`, then the events suite `flutter test test/features/events/` (fixture-fix any hub test that never provides members and now lands in pending — provide the members override, don't weaken the gate).

**Step 5: Commit** — `fix(events): #1030 hub balance header covers the members-only error window`

### Task 6: Snapshot-at-close — never freeze a members-less basis

**Files:**
- Modify: `lib/features/events/widgets/event_danger_section.dart:338-357`
- Test: new `test/features/events/event_close_snapshot_1030_test.dart` (reuse the close-flow harness from `event_settings_screen_test.dart` — it drives `closeEvent`)

**Step 1: RED.** `'#1030: close under a members hard error captures NO spending snapshot'`: mock `eventServiceProvider`, members `Stream.error`, expenses/settlements valued with real money → drive the close confirm → capture the `closeEvent` invocation → expect `spendingSnapshot: null` (today it captures a wrong-universe snapshot). Sibling pin: healthy streams → `spendingSnapshot` non-null.

**Step 2: Run** — Expected: FAIL (snapshot captured non-null under the members error).

**Step 3: Implementation.** In `_executeClose`, after the existing bounded expenses await, before reading `recap`/`view`:

```dart
      // #1030: the snapshot is an OUTBOUND write (frozen spending served by
      // every future recap open). A valueless money/members stream means
      // ledgerViewProvider computed from a wrong #249 universe — capture NO
      // snapshot instead (recap stays live; recoverable by reopen+close,
      // the same degrade as the timeout above). Stale values serve.
      final basisHealthy =
          ref.read(eventExpensesProvider(eventRef)).hasValue &&
          ref.read(eventSettlementsProvider(eventRef)).hasValue &&
          ref.read(groupMembersProvider(groupId)).hasValue;
      final recap = ref.read(eventRecapProvider(eventRef));
      final view = ref.read(ledgerViewProvider(eventRef));
      final snapshot = (!basisHealthy || recap.isEmpty)
          ? null
          : SpendingSnapshot.from(recap: recap, balances: view.balances).toMap();
```

(Existing `recap`/`view`/`snapshot` lines replaced; everything else untouched.)

**Step 4: Run** new test file + `flutter test test/features/events/event_settings_screen_test.dart` — PASS.

**Step 5: Commit** — `fix(events): #1030 event close refuses to freeze a members-less spending snapshot`

### Task 7: Recap screen — gate the three source streams

**Files:**
- Modify: `lib/features/events/screens/event_recap_screen.dart` (data branch, `:64-82`)
- Modify: `lib/l10n/app_en.arb`, `lib/l10n/app_ar.arb` (new key `recapDataUnavailable`)
- Test: `test/features/events/event_recap_screen_test.dart`

**Step 1: RED.** `'#1030: members hard error → recap shows data-unavailable, never folded nets'` — members `Stream.error`, expenses/settlements valued → expect the unavailable view (new key text) and no participant-net rows. Sibling: same for an expenses hard error (the adversary's non-members leg — closed-event recap had NO gate at all).

**Step 2: Run** — Expected: FAIL.

**Step 3: Implementation.** Inside the `data:` branch after the `event == null` check:

```dart
        // #1030: recap + its share/export CTAs render ledgerViewProvider
        // folds — a hard-errored source stream means wrong nets (members:
        // wrong #249 universe), so gate all three. Stale values serve;
        // loading-no-value keeps the existing spinner.
        final expensesAsync = ref.watch(eventExpensesProvider(eventRef));
        final settlementsAsync = ref.watch(eventSettlementsProvider(eventRef));
        final membersAsync =
            ref.watch(groupMembersProvider(eventRef.groupId));
        final sources = [expensesAsync, settlementsAsync, membersAsync];
        if (sources.any((s) => s.hasError && !s.hasValue)) {
          return _dataUnavailable(context, eventRef);
        }
        if (sources.any((s) => s.isLoading && !s.hasValue)) {
          return _wrap(context, const [
            Center(
              child: Padding(
                padding: EdgeInsets.only(top: 48),
                child: CircularProgressIndicator(),
              ),
            ),
          ]);
        }
```

`_dataUnavailable` = `EmptyStateView` (icon `Iconsax.warning_2`, title `context.l10n.recapDataUnavailable`, action `commonRetry` → invalidate all three providers), `_wrap`-ped like `_notFound`. ARB: `"recapDataUnavailable": "Couldn't load recap data."` (EN) / `"recapDataUnavailable": "تعذّر تحميل بيانات الملخّص."` (AR — match the file's existing recap-section translations' register; verify neighboring recap keys in `app_ar.arb` before finalizing the string). Note `EmptyStateView` schedules a `flutter_animate` ticker — the test must `pumpAndSettle` (CLAUDE.md gotcha).

**Step 4: Run** `flutter test test/features/events/event_recap_screen_test.dart` + `flutter test test/unit/generated_l10n_surface_test.dart` (if key-surface pinning exists there) — PASS.

**Step 5: Commit** — `fix(events): #1030 recap gates expense/settlement/members stream health before rendering nets`

### Task 8: Ledger screen — members joins the data-error gate

**Files:**
- Modify: `lib/features/ledger/screens/ledger_screen.dart:76-95`
- Test: `test/features/ledger/` (the ledger screen test file — locate via `grep -rl _DataErrorState test/features/ledger/`)

**Step 1: RED.** `'#1030: members hard error → ledger data-error state, not a members-less roster'` — members `Stream.error`, expenses/settlements valued → expect the `_DataErrorState` retry view.

**Step 2: Run** — Expected: FAIL.

**Step 3: Implementation.** Match the file's local convention (bare `hasError` — stricter than #1005; changing the siblings is out of scope):

```dart
        final membersAsync = ref.watch(groupMembersProvider(widget.groupId));
        if (expensesAsync.hasError ||
            settlementsAsync.hasError ||
            membersAsync.hasError) {
          return _DataErrorState(
            onRetry: () {
              ref.invalidate(eventExpensesProvider(eventRef));
              ref.invalidate(eventSettlementsProvider(eventRef));
              ref.invalidate(groupMembersProvider(widget.groupId));
            },
          );
        }
```

(The members first-value loading window is accepted here: display-only surface, members resolves from SDK cache in the same frame batch as the money streams; the OUTBOUND surfaces (Tasks 3/4/6) and the hub (Task 5) do gate it.)

**Step 4: Run** the ledger screen tests — fixture-fix any test that never provided members.

**Step 5: Commit** — `fix(ledger): #1030 ledger screen data-error gate covers the members stream`

### Task 9: Pin the receipt's existing members gate

**Files:**
- Test: `test/features/events/trip_receipt_provider_test.dart`

**Step 1:** Check for an existing members-error case (`grep -n "members" test/features/events/trip_receipt_provider_test.dart`). If absent, add `'#1030 pin: members hard error → tripReceiptProvider is AsyncError (no members-less export)'` — members `Stream.error`, everything else valued → `AsyncError`. Should pass WITHOUT implementation change (the gate exists, `trip_receipt_provider.dart:72-78`); if it unexpectedly fails, STOP — the verification above was wrong, re-open the plan.

**Step 2: Run + commit** — `test(events): #1030 pin trip receipt members-error gate`

### Task 10: Full verification + PR

- `flutter analyze` — clean.
- `flutter test` — full suite green.
- `bash tool/check_theme_purity.sh` — new/changed widgets (recap `_dataUnavailable`) carry no violations.
- PR body: `Closes #1030`, spec line `Spec: docs/plans/2026-07-07-1030-members-fail-open-honesty.md`, RED evidence pasted per task (failing-before-fix output), note the #204/#898 contract re-scope explicitly, note the receipt-claim correction, and the follow-up issue for the group-detail `_BalanceCard` / spending-summary false-settled sibling (file it, link it).
- Submit via `/automerge` (Gate-category: money + `**/providers/**` balance surfaces).
