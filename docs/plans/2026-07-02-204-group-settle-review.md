# Group-Level Settle-Up Pre-Settlement Review Trigger (#204 — final acceptance box)

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** When the group settle-up screen opens and the group's settle basis contains review-worthy expenses, show the existing non-blocking pre-settlement review sheet once — closing #204's last acceptance box with zero new Firestore listeners.

**Architecture:** A new zero-listener sibling provider (`groupPreSettleReviewProvider`, same pattern as `groupTaggedEventSettlementsProvider`/#180's `groupSpendingSummaryProvider`) re-watches the already-open `groupEventsProvider` + per-event `eventExpensesProvider` + `groupMembersProvider` streams, runs the existing pure `detectReviewWorthyExpenses` **once per event** with that event's active-participant set, and unions the flags. `GroupSettleUpScreen` fires the existing sheet one-shot when the basis is resolved and flags are non-empty. The sheet's "Review expenses" CTA becomes optional (hidden at group scope — there is no group ledger surface, #422 deferred).

**Tech Stack:** Flutter/Riverpod 2.x (`Provider.family` sibling), existing `pre_settlement_review.dart` detector (unchanged), existing `pre_settlement_review_sheet.dart` (one nullable param).

---

## Design decisions (with rejected alternatives)

### D-1: Data source = zero-listener sibling provider, NOT threading `allExpenses` through `GroupBalances`
The issue's slice-1 comment proposed threading `allExpenses` through the `GroupBalances` record. **Rejected** in favor of the sibling-provider pattern because:
- `GroupBalances` has two construction sites (`groupBalancesProvider` live path + `groupBalancesOnceProvider` home one-shot, `group_balance_provider.dart:130/715`) and many consumers; widening the record carries raw expenses into the home path where they are dead weight.
- The sibling pattern has shipped twice since that comment with the exact same zero-new-listener argument: `groupTaggedEventSettlementsProvider` (#752, `group_balance_provider.dart:237`) and `groupSpendingSummaryProvider` (#180, merged 9a80d846). `eventExpensesProvider` is a cached `StreamProvider.family` — re-watching re-uses the open streams.
- `group_balance_provider.dart` is already 1034 lines (>800 cap) — the new provider gets its own file.

### D-2: Detector runs PER EVENT with `event.participantIds ∩ liveMemberIds`; flags unioned
Two wrinkles dissolve at once:
- **Payer universe fidelity:** the event-level check (slice 1, `settle_up_screen.dart:205-208`) uses `event.participantIds.toSet().intersection(liveMemberIds)`. The server oracle's universe formula (`participantIds ∪ (payers+settlement parties \ live)`) implies a payer can exist outside `participantIds`, so a flat group-wide `liveMemberIds` set is NOT provably equivalent. Per-event invocation reproduces slice-1 semantics exactly.
- **`largeAmount` scope:** per-event invocation keeps the large-amount denominator event-local — the group sheet's flag set is exactly the union of what each event's own settle sheet would show. One semantic everywhere. **Rejected:** one group-wide detector call (would compute per-currency totals across the whole group — flags the user never saw at event level, and vice versa).
- Edge parity: an event whose entire roster departed yields an empty intersection → detector treats empty as "unknown" and skips the payer check — identical to event level.

### D-3: Resolution gate — one-shot must not latch on a partial basis
The sheet fires once per screen entry. Unlike #180's continuously-recomputing summary, a one-shot latch on partial data shows an incomplete sheet forever. The provider therefore reports `resolved`:
- `false` while `groupEventsProvider` has no value, `groupMembersProvider` is unsettled (no value AND no error), or ANY event's expense stream is still loading (`isLoading && !hasValue`).
- A hard-errored expense stream (`hasError && !hasValue`) is **dropped but does not block resolution** — mirrors the #244 OR-skip: that event's money is absent from the settle basis too, so review-basis == settle-basis.
- Members hard-error → resolved with an empty live set per event → payer check skipped, other reasons still fire (mirrors `settle_up_screen.dart:209-210` fallback).
- Settlement streams are NOT watched — detection classifies expenses only; watching settlements would only add spurious recomputes. **Caveat (Gate rd-1 P3):** this makes "review-basis == settle-basis" approximate, not literal — `groupBalancesProvider` OR-skips an event when EITHER money stream is unhealthy (`group_balance_provider.dart:164-173`), while the review basis drops it only on an unhealthy EXPENSE stream. An event with healthy expenses but an errored settlement stream is absent from the settle total yet still classified for review — a harmless extra non-blocking nudge, accepted.

### D-4: Closed events (#723) are INCLUDED
Their expenses feed the group net being settled (basis-match), and slice 1 set the precedent — the event-level sheet has no `isClosed` filter. Tapping a flagged frozen expense lands on the existing #723 guard (`edit_expense_screen.dart:70-77` shows the "event closed" scaffold) — explained, not a silent dead-end. A possible "exclude sealed events from the nudge" product decision is a follow-up, not built now.

### D-5: Sheet CTA — `onReviewAll` becomes nullable; hidden at group scope
There is no group-wide ledger surface (#422 deferred — don't re-propose). Pushing `/group/:gid` from settle-up would stack a duplicate group screen. So `showPreSettlementReviewSheet`'s `onReviewAll` becomes `VoidCallback?`; `null` hides the "Review expenses" button (row-tap deep-links remain). Event-level callers are unchanged (they keep passing a callback).

### D-6: Row tap deep-links via `expense.tripId`
`Expense.tripId` maps to Firestore `eventId` (`expense_model.dart:174,200,242`), so the group sheet routes each row to its OWN event's editor: `/group/{gid}/event/{e.tripId}/ledger/edit/{e.id}` — same route shape the event-level sheet already pushes.

### D-7: One-shot latch mirrors slice 1
`_reviewSheetShown` bool + post-frame callback, latched ONLY when the sheet actually shows (`resolved && flags.isNotEmpty`), so late-resolving data still gets its chance. Fired from inside `balancesAsync.when(data:)` so the sheet never appears over a skeleton.

## Verification principles report (run while writing, per Operating Contract)

1. **Callsite classification:** every new surface is INBOUND/display-only. `groupPreSettleReviewProvider` is consumed only by `GroupSettleUpScreen`; `ReviewFlag`s are never persisted; row tap pushes the existing editor route (no write). No OUTBOUND path exists.
2. **Concrete claims verified against code this session:**
   - `detectReviewWorthyExpenses(expenses, {largeFraction, activeParticipantIds})` — `lib/features/ledger/services/pre_settlement_review.dart:44-48`; empty active set = check skipped (`:74`).
   - Event-level wiring + fallback — `settle_up_screen.dart:83-108, 204-211`; `liveMemberIds` = non-tombstone `userId`s (`:187-190`).
   - Sibling precedent + OR-skip — `group_balance_provider.dart:237-253`, `group_spending_summary_provider.dart:18-49`.
   - Sheet signature — `pre_settlement_review_sheet.dart:22-27`; CTA row `:165-175`.
   - `Event.isClosed` — `event_model.dart:98`; editor closed-guard — `edit_expense_screen.dart:70-77`.
   - `claimShadow` re-keys `payerParticipantId` uuid→uid (`functions/src/callables/claimShadow.ts:247-248,293-294`) — claimed shadows cannot false-fire the payer check.
3. **Read-path per write-path:** no write path introduced.
4. **Fields enumerated from types:** `Expense.tripId/payerParticipantId/currency/amount/scope/splitMode/isDeleted` (expense_model.dart); `GroupMember.userId/isTombstone` (group_member_model.dart:12,18); `Event.participantIds` (event_model.dart:82).
5. **Data contracts spelled out:** provider returns `({List<ReviewFlag> flags, bool resolved})`; sheet param change `required VoidCallback onReviewAll` → `VoidCallback? onReviewAll` (named optional, existing callers compile unchanged).
6. **Arithmetic decomposition:** none persisted. The only aggregate (per-currency `largeAmount` denominator) stays event-scoped by construction (D-2).
7. **Adversarial pass, orthogonal axes:** identity axis — claimed shadows re-keyed (see 2); unclaimed shadows are live members (`isTombstone == false`) → no false fire. Time axis — closed events (D-4). Scope axis — expenses from event B must deep-link with event B's id (pinned by a cross-event navigation test, Task 3).

**Existing-test blast radius:** adding `ref.watch(groupPreSettleReviewProvider)` to the screen makes existing group-settle-up widget tests construct `groupMembersProvider`/`eventExpensesProvider` without overrides. Default harness (`_wrap`) overrides `groupEventsProvider` with `[]` → zero event loops; unoverridden `groupMembersProvider` throws `[core/no-app]` synchronously in the provider body → Riverpod catches → `AsyncError` → members settled, flags empty → no sheet. Tests that pass `events: [_testEvent]` hit unoverridden `eventExpensesProvider` → same `AsyncError` → event OR-dropped → flags empty → no sheet. Verified expectation: existing tests stay green with no edits; Task 4 runs the full group-settle suites to confirm.

---

## Tasks

### Task 1: `groupPreSettleReviewProvider` (pure wiring, unit-tested)

**Files:**
- Create: `lib/features/groups/providers/group_presettle_review_provider.dart`
- Test: `test/features/groups/providers/group_presettle_review_provider_test.dart`

**Step 1: Write the failing tests** (harness pattern copied from `group_spending_summary_provider_test.dart` — `ProviderContainer` + family overrides + `_pump`):

Test cases:
1. `flags union across events with per-event active sets` — two events; event-a has an exact-split expense (→ `exactSplit`), event-b has an expense paid by `uid-gone` who is in event-b's `participantIds` but whose member doc is tombstoned (→ `payerNotInParticipants`). Members stream = [alice(live), bob(live), gone(tombstone)]. **Gate rd-1 P2: event-b's `participantIds` MUST also contain a live member (e.g. alice)** — if it held only `uid-gone`, the `participantIds ∩ liveMemberIds` intersection would be empty and the detector SKIPS the payer check (`pre_settlement_review.dart:74`), silently never firing the asserted flag. Expect exactly those two flags, `resolved: true`.
2. `largeAmount denominator is event-local` — event-a: expenses 10 + 2 (the 10 is >0.5 of 12 → `largeAmount`); event-b: single expense 100 (lone expense in its event → never large, even though it dominates the group total). Expect exactly one `largeAmount` flag, on the 10.
3. `unresolved while any expense stream is loading` — event-b's expenses stream never emits (`Stream.empty()`... use a `StreamController` with no add) → `resolved: false`, `flags` empty.
4. `errored expense stream is OR-dropped but resolves` — event-b's expenses stream errors; event-a has an exact-split expense → `resolved: true`, only event-a's flag.
5. `members error → payer check skipped, other reasons still fire` — members stream errors; event-a has expense paid by an unknown uid AND an exact-split expense → only `exactSplit` flag, `resolved: true`.
6. `members loading → unresolved` — members stream never emits → `resolved: false`.

`GroupMember` construction: `GroupMember(id:…, groupId:…, userId:…, displayName:…, role:'MEMBER', isShadow:false, isTombstone:…, joinedAt:…)` — enumerate required params from `group_member_model.dart` when writing (role convention is `'MEMBER'`/`'CREATOR'`, though this provider never reads it).

**Step 2: Run — expect FAIL** (file/provider doesn't exist):
`flutter test test/features/groups/providers/group_presettle_review_provider_test.dart`

**Step 3: Implement** `lib/features/groups/providers/group_presettle_review_provider.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../events/models/event_model.dart';
import '../../events/providers/event_provider.dart';
import '../../ledger/models/expense_model.dart';
import '../../ledger/providers/expense_provider.dart';
import '../../ledger/services/pre_settlement_review.dart';
import 'group_provider.dart';

/// Result of the group-scope pre-settlement review basis (#204).
///
/// [resolved] is false while the basis is still assembling (events list or
/// members unsettled, or ANY event's expense stream still loading) — a
/// one-shot consumer (the review sheet) must never latch on a partial basis.
/// A hard-errored expense stream is dropped WITHOUT blocking resolution,
/// mirroring the #244 OR-skip so review-basis == settle-basis.
typedef GroupPreSettleReview = ({List<ReviewFlag> flags, bool resolved});

/// Review-worthy expenses across the whole group settle basis (#204, final
/// acceptance box). Display-only sibling of [groupBalancesProvider] — a
/// projection, never a money source.
///
/// Iterates the SAME [groupEventsProvider] list and the SAME per-event
/// [eventExpensesProvider] family instances the live balance provider
/// watches, so this adds NO new Firestore listeners (same argument as
/// [groupTaggedEventSettlementsProvider] / groupSpendingSummaryProvider).
///
/// The detector runs PER EVENT with that event's
/// `participantIds ∩ liveMemberIds` — reproducing the event-level sheet's
/// semantics exactly (payer universe AND event-local largeAmount denominator),
/// so the group sheet shows precisely the union of what each event's own
/// settle-up sheet would.
final groupPreSettleReviewProvider =
    Provider.family<GroupPreSettleReview, String>((ref, groupId) {
      final eventsAsync = ref.watch(groupEventsProvider(groupId));
      final membersAsync = ref.watch(groupMembersProvider(groupId));

      // Members error → run without the active set (payer check skipped,
      // other reasons still fire) — mirrors settle_up_screen's fallback.
      final membersSettled = membersAsync.hasValue || membersAsync.hasError;
      if (!eventsAsync.hasValue || !membersSettled) {
        return (flags: const <ReviewFlag>[], resolved: false);
      }

      final liveMemberIds = <String>{
        for (final m in membersAsync.valueOrNull ?? const [])
          if (!m.isTombstone) m.userId,
      };

      final flags = <ReviewFlag>[];
      var resolved = true;
      for (final event in eventsAsync.valueOrNull ?? const <Event>[]) {
        final eventRef = (groupId: groupId, eventId: event.id);
        final expensesAsync = ref.watch(eventExpensesProvider(eventRef));
        if (expensesAsync.isLoading && !expensesAsync.hasValue) {
          resolved = false;
          continue;
        }
        if (expensesAsync.hasError && !expensesAsync.hasValue) continue;
        flags.addAll(
          detectReviewWorthyExpenses(
            expensesAsync.valueOrNull ?? const <Expense>[],
            activeParticipantIds: event.participantIds
                .toSet()
                .intersection(liveMemberIds),
          ),
        );
      }
      if (!resolved) return (flags: const <ReviewFlag>[], resolved: false);
      return (flags: List.unmodifiable(flags), resolved: true);
    });
```

(Adjust the members-list typing to the real `groupMembersProvider` element type when writing; if events can error, `!eventsAsync.hasValue` on a hard error returns unresolved — acceptable: the screen shows the missing/error view and no sheet should fire.)

**Step 4: Run — expect PASS.** Also `flutter analyze` clean.

**Step 5: Commit** — `feat(groups): group-scope pre-settlement review basis provider (Refs #204)`

### Task 2: Nullable `onReviewAll` on the sheet

**Files:**
- Modify: `lib/features/ledger/widgets/pre_settlement_review_sheet.dart` (`:26` signature, `:38` pass-through, widget field, CTA row `:165-176`)
- Test: `test/features/ledger/pre_settlement_review_sheet_test.dart` (add one case)

**Step 1: Failing test** — pump the sheet with `onReviewAll: null`; expect `find.byKey(PreSettleReviewKeys.reviewButton)` → `findsNothing`, continue button still present. (Match the file's existing pump helper.)

**Step 2: Run — expect FAIL** (compile error: null not assignable to `VoidCallback`).

**Step 3: Implement** — `required VoidCallback onReviewAll` → `VoidCallback? onReviewAll` (drop `required`, keep named) in `showPreSettlementReviewSheet` and `_PreSettlementReviewSheet`; wrap the review `Expanded(TextButton…)` + trailing `SizedBox(width: spacing.space12)` in `if (onReviewAll != null) …` (collection-if inside the `Row`'s children), using `onReviewAll!()`. Doc comment: null hides the CTA (group scope has no all-expenses surface).

**Step 4: Run sheet test file — expect PASS** (all existing cases too — event-level behavior unchanged).

**Step 5: Commit** — `feat(ledger): pre-settlement review sheet CTA optional for group scope (Refs #204)`

### Task 3: Wire the sheet into `GroupSettleUpScreen`

**Files:**
- Modify: `lib/features/groups/screens/group_settle_up_screen.dart` (state class `:62-70`, `build` data branch `:151-152`)
- Test: `test/features/groups/group_settle_up_review_sheet_test.dart` (new; harness copied from `group_settle_up_screen_test.dart` `_wrap`, plus overrides for `groupMembersProvider` + per-event `eventExpensesProvider`)

**Step 1: Failing tests:**
1. `sheet fires once when any event has a review-worthy expense` — events [A, B]; B has an exact-split expense; members live. Pump → expect `find.byKey(PreSettleReviewKeys.sheet)` visible. Dismiss (tap continue), trigger a rebuild (emit on an overridden stream) → sheet does NOT reappear.
2. `no sheet when basis is clean` — plain equal-split expenses → `findsNothing`.
3. `no sheet while an expense stream never resolves` — event B's expense stream never emits → `findsNothing` (partial-basis guard).
4. `discriminating: departed payer flags at group level` — expense in event A paid by `uid-gone`, present in A's `participantIds`, tombstoned in members → sheet visible with the payer-left count line (`l10n.preSettleReviewPayerLeftCount(1)` text).
5. `review-all CTA hidden at group scope` — flags present → `PreSettleReviewKeys.reviewButton` → `findsNothing`.
6. `row tap deep-links to the expense's OWN event` — GoRouter harness (pattern: `group_detail_navigation_test.dart`): routes for the settle screen + a probe route at `/group/:gid/event/:eid/ledger/edit/:xid`; flagged expense lives in event-b → tap row → probe screen receives `eid == 'event-b'`, `xid == the expense id`.

**Step 2: Run — expect FAIL** (no sheet wired).

**Step 3: Implement** in `_GroupSettleUpScreenState`:

```dart
/// #204: the pre-settlement review sheet fires once per screen entry —
/// same one-shot contract as the event-level settle-up.
bool _reviewSheetShown = false;

void _maybeShowReviewSheet(
  BuildContext context,
  GroupPreSettleReview review,
) {
  if (_reviewSheetShown || !review.resolved || review.flags.isEmpty) return;
  _reviewSheetShown = true;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!mounted) return;
    showPreSettlementReviewSheet(
      context,
      flags: review.flags,
      // Group scope: each row deep-links to its OWN event's editor
      // (expense.tripId is the Firestore eventId). No review-all CTA —
      // there is no group-wide ledger surface (#422 deferred).
      onTapExpense: (e) => context.push(
        '/group/${widget.groupId}/event/${e.tripId}/ledger/edit/${e.id}',
      ),
    );
  });
}
```

In `build`, watch the provider next to the other siblings (`final review = ref.watch(groupPreSettleReviewProvider(widget.groupId));`) and call `_maybeShowReviewSheet(context, review);` as the first line of `balancesAsync.when(data: (balancesData) { … })`. Imports: the new provider + `pre_settlement_review_sheet.dart` (+ `go_router` already imported? verify — `context.push` needs it).

**Step 4: Run new test file — expect PASS.** Then run the neighboring suites to confirm zero blast radius:
`flutter test test/features/groups/ test/features/ledger/pre_settlement_review_sheet_test.dart test/unit/pre_settlement_review_test.dart`

**Step 5: Commit** — `feat(groups): pre-settlement review sheet on group settle-up (Refs #204)`

### Task 4: Full verification + PR

- [ ] `flutter analyze` — clean
- [ ] `flutter test` — full suite green (pins acceptance box #3: MVP behavior unchanged — `pre_settlement_review.dart` has ZERO edits in this diff)
- [ ] `bash tool/check_theme_purity.sh` — no new violations (no colors introduced, but the CI-only trap costs a round-trip if skipped)
- [ ] Security checklist: no secrets / no queries / display-only, no new write path / no rules change
- [ ] PR: branch `feat/204-group-settle-review`, body carries `Closes #204` (this is the LAST open acceptance box; boxes 2–3 already delivered/documented on the issue) — and `Closes #204` goes in the SQUASH COMMIT BODY too (the #447 trap)
- [ ] `/automerge` the PR (classifier will likely Gate it — models/ledger surface; the review IS the gate)
- [ ] After merge: issue #204 auto-closes; post a closeout comment mapping the three acceptance boxes to their PRs; update memory (`project_204_departed_payer_trigger.md`)

**No l10n changes** (sheet copy verified scope-neutral: `preSettleReviewTitle` "Before you settle", reason chips/counts carry no event wording). **No rules/schema/server changes.**
