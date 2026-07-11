# #1106 — Settle-up RECORD guard during per-event stream convergence

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Refuse the group settle-up RECORD write while any event's expense/settlement stream is still delivering its FIRST snapshot (the `groupBalancesProvider` loading-skip window), so a cold-`push()` entry can never record an understated settlement — without touching the display side (#244's proceed-on-partial stays).

**Architecture:** One new derived provider (`groupConvergingEventIdsProvider`, the loading-skip mirror of the existing `groupFailedEventIdsProvider` error-skip mirror) + a two-point write-time gate inside `_showRecordPaymentSheet` in `group_settle_up_screen.dart` (refuse before opening the sheet; refuse again at the #719 pre-write revalidation). Client-only — no rules, Functions, or schema change; no deploy.

**Tech Stack:** Flutter/Riverpod 2.x, `fake_cloud_firestore`, `flutter_test`.

**Issue:** #1106 (P3, money, cluster:money-trust). PR must carry `Closes #1106`.

---

## Context (verified against worktree @ b566cd62, 2026-07-11)

`groupBalancesProvider` (`lib/features/groups/providers/group_balance_provider.dart:189-220`) deliberately **proceeds on partial data**: an event whose `eventExpensesProvider`/`eventSettlementsProvider` is `isLoading && !hasValue` is `continue`d (`:194-197`) and the provider still returns `AsyncValue.data(...)` (`:212`). That display decision is **closed** (#244 — returning loading deadlocks the balance card for new zero-expense events) and is out of scope here.

The exposure is that the **RECORD path trusts the same provider**:

- `group_settle_up_screen.dart:135` — `balancesAsync` feeds both display and `onRecord`/`onRecordStepped`.
- `group_settle_up_screen.dart:626-650` — the #719 pre-write revalidation `ref.read(groupBalancesProvider(...)).valueOrNull` re-reads the **same still-converging provider**, so a mid-convergence basis revalidates against an equally incomplete fresh read and passes.
- `groupFailedEventIdsProvider` (`:236-253`) tracks only **hard-errored** events ("Loading ≠ partial" is in its docstring, by design), and the #244 banner it drives is warn-not-block — `canRecord: true` is hardcoded (`:231`).

Reachable via the two `push()`-only cold entries that bypass `GroupDetailScreen`'s warm-up (an imperative `push` materializes only the leaf — #996):
- `lib/features/home/widgets/group_balance_breakdown_sheet.dart:56` — `router.push('/group/$groupId/settle-up')` (verified: `_openSettleUp`).
- `lib/features/activity/utils/activity_nav.dart:50` — `group_settlement` activity rows return `/group/$groupId/settle-up` (pushed).

In that window the screen shows an understated suggested amount with a live, unwarned Record CTA; a confirm inside the window writes understated money (and decomposes from an incomplete `perEventBreakdown`).

**Supporting precedent already in the codebase:** `groupPreSettleReviewProvider` (#204, `group_presettle_review_provider.dart:100-110`) already treats this exact signal (`isLoading && !hasValue` on any event stream) as "basis not resolved — the one-shot review sheet must never latch on a partial basis". The REVIEW sheet got a convergence guard; the RECORD write never did. This plan gives the write the same discipline.

## Hard constraints (from the issue's lineage block)

1. **Do NOT re-litigate #244's display decision.** The loading-skip `continue` + `AsyncValue.data` return in `groupBalancesProvider` stays byte-identical. `groupFailedEventIdsProvider` stays error-only. The #244 warning banner stays error-only.
2. Scope is the **write-time exposure only** in `group_settle_up_screen.dart`.
3. Distinct from #1093 (cross-device concurrency — shipped as deterministic dedup ids) and closed #719/#773 (sheet-open staleness — the fresh re-read). This fix composes with both; it changes neither.

## Design

### D1 — `groupConvergingEventIdsProvider` (new, in `group_balance_provider.dart`)

Loading-skip mirror of `groupFailedEventIdsProvider`: iterates the SAME `groupEventsProvider` list and the SAME per-event family instances the live balance provider watches (zero new Firestore listeners — the cached `StreamProvider.family` argument used by `groupTaggedEventSettlementsProvider:267-283`), flagging event ids where `(expenses.isLoading && !expenses.hasValue) || (settlements.isLoading && !settlements.hasValue)`.

Set (not bool) for symmetry with the failed-ids provider and testability.

### D2 — Two-point write gate in `_showRecordPaymentSheet`

Both record paths funnel through `_showRecordPaymentSheet` (`group_settle_up_screen.dart:536`): the single-tile path (`onRecord`, `:233-254`) and every step of the stepped walk (`_runSteppedSettle:459` loops it). Corrections (`_correctSettlement`, `_correctLogicalSettleUp`) are server-authoritative callables — not gated.

- **Entry gate** (top of the method, before `showRecordPaymentSheet` opens): converging non-empty → snackbar + `return _StepOutcome(_StepOutcomeKind.invalid)`. Kills the root exposure — a sheet opened in the window carries an understated suggestion that the #719 re-read can never catch (an understated `editedAmount` ≤ a later-converged higher outstanding **passes** #719 by design, since partial payments are legal).
- **Confirm gate** (inside the #719 block, before `ref.read(...)` of the fresh balance, `:627`): a convergence window can OPEN while the sheet is up (another device adds an event → its fresh family instances are loading here). Same refuse.

Block, not warn: the #719 precedent for write-time staleness is abort-with-snackbar ("review again"), and the window is sub-second and self-healing — a retry succeeds. The #244 warn-not-block precedent governs the *display* banner for *hard-errored* (permanently degraded) events; a *converging* basis is transient and cannot even be honestly warned about (the true number is unknown).

### D3 — New l10n key

`settleUpBalanceStillSyncing` — en: `"Balances are still syncing — try again in a moment."`, ar: `"لا تزال الأرصدة قيد المزامنة — حاول مرة أخرى بعد لحظات."`. Added beside `settleUpBalanceChangedReviewAgain` (`app_en.arb:825`, `app_ar.arb:317`); regenerate with `flutter gen-l10n` (config: `l10n.yaml`, output `lib/l10n/generated`).

### D4 — Explicitly unchanged

- `groupBalancesProvider` body: byte-identical.
- `groupFailedEventIdsProvider` + `settleUpIncompleteBalanceWarning` banner: error-only, unchanged.
- `canRecord: true` (`:231`): unchanged — the gate lives at the write funnel, not CTA visibility (CTA visibility is not a safety boundary — the #647/#648 lesson).
- Server/rules: nothing. The group-settlements-loading leg of the same window is ALREADY write-blocked by the #1093 dedup-basis guard (`:835-841` and `:1024-1031` throw `StateError` when `groupSettlementsProvider` has no value).

### D5 — Adjacent surfaces classified OUT of scope (with reasons)

- `group_danger_section.dart:186/:213/:295` and `group_members_section.dart:203` read the same provider for leave/remove/delete pre-gates, but each is commented "UX-only short-circuit … the SERVER decide[s]" — `leaveGroup`/`removeMember`/`deleteGroup` callables recompute balances server-side (`recomputeNet`). Client staleness there is UX, not money-wrong. No change.
- Event-level settle-up (`settle_up_screen.dart`): reads its own event's streams directly; a loading stream holds the whole screen in loading — no proceed-on-partial, no exposure.
- `groupBalancesOnceProvider`/home aggregate: display cache, never OUTBOUND (CLAUDE.md #366). No change.

### Alternatives considered (rejected)

- **Reuse `groupPreSettleReview.resolved` as the gate signal** — bundles #1058 watermark/suppression semantics tuned to the sheet's one-shot latch (e.g. members hard-error still resolves true); a dedicated provider keeps write-gate semantics explicit and independently testable.
- **Extend the #244 banner to loading events (warn-not-block)** — flashes on every cold entry for a sub-second window (noise), leaves the write exposure open, and contradicts the #244 docstring's deliberate "Loading ≠ partial" display stance.
- **Await convergence with timeout at confirm** — seamless but complex; a #997-style wedged listener would hang the confirm. Snackbar-retry is simpler and self-healing.
- **Warm the two `push()` entries (go-navigation / ancestor materialization)** — fixes only the two *known* entries and breaks the deliberate #996 push-leaf behavior; the write gate is entry-point-agnostic.

### Accepted trade-off (surfaced to Gate round 1; both reviewers accepted the direction)

The gate is deliberately COARSE: `.isNotEmpty` blocks recording for **every** pair while **any** event's streams are converging — including pairs whose own basis is fully resolved. In the normal (cold-entry) case that costs a sub-second retry; if an event's stream **never** emits (the #997 DNS-blackhole wedge: listener up, no snapshot, no error), the whole screen's RECORD stays blocked until it does. That is the fail-safe direction: a basis that never delivers is a basis money must not be written from (same fail-safe stance as `outgoingShellProvablyEmpty`'s timeout→block). Display, history, and all server-authoritative actions stay available. Offline is NOT this case: the SDK delivers an initial from-cache snapshot (even empty) for every listener (#50 — offline reads served by SDK persistence), so convergence completes offline and the gate adds no offline blocker; the residual "offline + never-cached event" case shows that event's money nowhere on screen either, so blocking its basis from being *written* is precisely #1106, not a regression.

---

## Verification principles (run against code, reported)

1. **Callsite classification of `groupBalancesProvider`** (grep `lib/`, 2026-07-11): OUTBOUND/BOTH — `group_settle_up_screen.dart:135` (display + feeds write), `:627` (#719 fresh re-read, feeds write). INBOUND — `group_detail_screen.dart:151`, `group_presettle_review_provider.dart:55`, `group_spending_summary_provider.dart:23`, `group_spending_summary_section.dart:37`, and the three danger/members pre-gates (server-authoritative callables revalidate; comments verified in-file). Retry `ref.invalidate` sites: `group_settle_up_screen.dart:363`, `group_detail_screen.dart:141` (neither). The fix gates the only client-direct money write on this basis.
2. **Concrete claims re-verified this session:** all line numbers above; `GroupKeys.settleUpRecordPaymentButton` (`group_keys.dart:85`), `GroupKeys.markAsPaidButton` (`:32`); `groupMembersProvider` (`group_provider.dart:654`); `eventExpensesProvider`/`eventSettlementsProvider` (`expense_provider.dart:67/:76`, `StreamProvider.family<…, EventRef>`); l10n keys at `app_en.arb:816-831`, `app_ar.arb:313-317`; `l10n.yaml` output `lib/l10n/generated`.
3. **Read-path per write-path:** the new provider is read by exactly two `ref.read` sites in `_showRecordPaymentSheet` (both gate a write; nothing persists it). The gated write paths (`stageDecomposedSettleUp` / `addGroupSettlement`) are unchanged when the gate passes — their readers (event ledgers, group history union, oracle) see identical documents.
4. **Fields enumerated from types:** no model/schema change. `GroupBalances` typedef untouched. New provider returns `Set<String>` of `Event.id`.
5. **Data contracts spelled out:** `groupConvergingEventIdsProvider: Provider.family<Set<String>, String>` keyed by groupId; non-empty ⇒ refuse with `_StepOutcomeKind.invalid` (the same outcome kind #719 uses, so the stepped walk stops on it — L3 semantics preserved). Snackbar key: `settleUpBalanceStillSyncing`.
6. **Arithmetic decomposition:** none added. The understated-basis claim was verified by reading the loading-skip fold (`:189-207`): a skipped event contributes zero expenses/settlements to `computeGroupBalances`, so nets omit its money.
7. **Adversarial pass on orthogonal axes:** (time axis) Test B exercises a window that OPENS mid-sheet, not the cold-entry window the issue describes; (settlement axis) provider test 4 pends the *settlement* stream while expenses emit (OR semantics); (offline axis) reasoned in the trade-off note — cache-first snapshots converge offline; (identity axis) gate is uid-agnostic, perspective (payer/recipient/on-behalf) unaffected.

---

## Tasks

### Task 1: Provider — `groupConvergingEventIdsProvider` (TDD)

**Files:**
- Test (create): `test/features/groups/providers/group_converging_event_ids_1106_test.dart`
- Modify: `lib/features/groups/providers/group_balance_provider.dart` (insert after `groupFailedEventIdsProvider`, i.e. after `:253`)

**Step 1.1: Write the failing test** (harness copied from `group_balance_provider_orphan_uid_test.dart` — `ProviderContainer` + family overrides):

```dart
import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/events/providers/event_provider.dart';
import 'package:safar/features/groups/models/group_member_model.dart';
import 'package:safar/features/groups/providers/group_balance_provider.dart';
import 'package:safar/features/groups/providers/group_provider.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/models/settlement_model.dart';
import 'package:safar/features/ledger/providers/expense_provider.dart';

const _groupId = 'group-1';

Event _event(String id) => Event(
  id: id,
  name: 'Event $id',
  type: EventType.trip,
  groupId: _groupId,
  createdBy: 'alice',
  participantIds: const ['alice', 'bob'],
  participantNames: const {'alice': 'Alice', 'bob': 'Bob'},
  modules: const EventModules(),
  createdAt: DateTime(2026, 7, 1),
);

GroupMember _member(String uid, String name) => GroupMember(
  id: uid,
  groupId: _groupId,
  userId: uid,
  displayName: name,
  role: 'MEMBER',
  joinedAt: DateTime(2026, 7, 1),
);

Expense _expense(String id, String eventId, String amount) => Expense(
  id: id,
  tripId: eventId,
  payerParticipantId: 'alice',
  amount: Decimal.parse(amount),
  scope: ExpenseScope.global,
  createdAt: DateTime(2026, 7, 1),
);

Future<void> _drainMicrotasks() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test(
    '#1106: an event whose expense stream has no first snapshot is converging; '
    'display still proceeds-on-partial (#244 pinned)',
    () async {
      final pendingExpenses = StreamController<List<Expense>>();
      addTearDown(pendingExpenses.close);
      final container = ProviderContainer(
        overrides: [
          groupEventsProvider(_groupId)
              .overrideWith((_) => Stream.value([_event('e1'), _event('e2')])),
          groupMembersProvider(_groupId).overrideWith(
            (_) => Stream.value([_member('alice', 'Alice'), _member('bob', 'Bob')]),
          ),
          groupSettlementsProvider(_groupId)
              .overrideWith((_) => Stream.value(const <Settlement>[])),
          eventExpensesProvider((groupId: _groupId, eventId: 'e1'))
              .overrideWith((_) => Stream.value([_expense('x1', 'e1', '20.000')])),
          eventSettlementsProvider((groupId: _groupId, eventId: 'e1'))
              .overrideWith((_) => Stream.value(const <Settlement>[])),
          eventExpensesProvider((groupId: _groupId, eventId: 'e2'))
              .overrideWith((_) => pendingExpenses.stream),
          eventSettlementsProvider((groupId: _groupId, eventId: 'e2'))
              .overrideWith((_) => Stream.value(const <Settlement>[])),
        ],
      );
      addTearDown(container.dispose);
      container.listen(groupConvergingEventIdsProvider(_groupId), (_, _) {},
          fireImmediately: true);
      container.listen(groupBalancesProvider(_groupId), (_, _) {},
          fireImmediately: true);
      await _drainMicrotasks();

      // e2's expense stream has not delivered a first snapshot → converging.
      expect(container.read(groupConvergingEventIdsProvider(_groupId)), {'e2'});
      // #244 display invariant PINNED: the balance provider still returns DATA
      // computed from e1 alone (proceed-on-partial is deliberately kept).
      final balances = container.read(groupBalancesProvider(_groupId));
      expect(balances.hasValue, isTrue);
      expect(
        balances.requireValue.balances['OMR']!
            .firstWhere((b) => b.participantId == 'bob')
            .netBalance,
        Decimal.parse('-10.000'),
      );

      // First snapshot arrives → the window closes.
      pendingExpenses.add(const <Expense>[]);
      await _drainMicrotasks();
      expect(
        container.read(groupConvergingEventIdsProvider(_groupId)),
        isEmpty,
      );
    },
  );

  test('#1106: a hard-errored stream is failed, NOT converging (orthogonal '
      'to groupFailedEventIdsProvider)', () async {
    final container = ProviderContainer(
      overrides: [
        groupEventsProvider(_groupId)
            .overrideWith((_) => Stream.value([_event('e1')])),
        groupMembersProvider(_groupId).overrideWith(
          (_) => Stream.value([_member('alice', 'Alice'), _member('bob', 'Bob')]),
        ),
        groupSettlementsProvider(_groupId)
            .overrideWith((_) => Stream.value(const <Settlement>[])),
        eventExpensesProvider((groupId: _groupId, eventId: 'e1')).overrideWith(
          (_) => Stream<List<Expense>>.error(Exception('permission-denied')),
        ),
        eventSettlementsProvider((groupId: _groupId, eventId: 'e1'))
            .overrideWith((_) => Stream.value(const <Settlement>[])),
      ],
    );
    addTearDown(container.dispose);
    container.listen(groupConvergingEventIdsProvider(_groupId), (_, _) {},
        fireImmediately: true);
    container.listen(groupFailedEventIdsProvider(_groupId), (_, _) {},
        fireImmediately: true);
    await _drainMicrotasks();

    expect(container.read(groupConvergingEventIdsProvider(_groupId)), isEmpty);
    expect(container.read(groupFailedEventIdsProvider(_groupId)), {'e1'});
  });

  test('#1106: a pending SETTLEMENT stream alone marks the event converging '
      '(OR semantics)', () async {
    final pendingSettlements = StreamController<List<Settlement>>();
    addTearDown(pendingSettlements.close);
    final container = ProviderContainer(
      overrides: [
        groupEventsProvider(_groupId)
            .overrideWith((_) => Stream.value([_event('e1')])),
        groupMembersProvider(_groupId).overrideWith(
          (_) => Stream.value([_member('alice', 'Alice'), _member('bob', 'Bob')]),
        ),
        groupSettlementsProvider(_groupId)
            .overrideWith((_) => Stream.value(const <Settlement>[])),
        eventExpensesProvider((groupId: _groupId, eventId: 'e1'))
            .overrideWith((_) => Stream.value(const <Expense>[])),
        eventSettlementsProvider((groupId: _groupId, eventId: 'e1'))
            .overrideWith((_) => pendingSettlements.stream),
      ],
    );
    addTearDown(container.dispose);
    container.listen(groupConvergingEventIdsProvider(_groupId), (_, _) {},
        fireImmediately: true);
    await _drainMicrotasks();

    expect(container.read(groupConvergingEventIdsProvider(_groupId)), {'e1'});
  });
}
```

**Step 1.2: Run — expect FAIL** (compile error: `groupConvergingEventIdsProvider` undefined):
`flutter test test/features/groups/providers/group_converging_event_ids_1106_test.dart`

**Step 1.3: Implement the provider** — insert into `lib/features/groups/providers/group_balance_provider.dart` directly after `groupFailedEventIdsProvider` (after line 253):

```dart
/// Event ids in [groupId] whose expense OR settlement stream has NOT delivered
/// a FIRST snapshot yet (`isLoading && !hasValue`) — the loading-skip window of
/// [groupBalancesProvider] (#1106). Mirrors [groupFailedEventIdsProvider]
/// (which mirrors the error-skip) for the OTHER silent skip, and iterates the
/// SAME events list and per-event family instances, so it adds no Firestore
/// listeners and can never disagree with the events the balance omitted.
///
/// DISPLAY deliberately stays proceed-on-partial (#244 — do not wire this into
/// the balance provider or its banner). The group settle-up RECORD path reads
/// this set to refuse writing money from a still-converging basis: the #719
/// fresh re-read cannot catch that window because it re-reads the SAME
/// still-converging provider.
final groupConvergingEventIdsProvider = Provider.family<Set<String>, String>((
  ref,
  groupId,
) {
  final events =
      ref.watch(groupEventsProvider(groupId)).valueOrNull ?? const <Event>[];
  final converging = <String>{};
  for (final event in events) {
    final eventRef = (groupId: groupId, eventId: event.id);
    final expensesAsync = ref.watch(eventExpensesProvider(eventRef));
    final settlementsAsync = ref.watch(eventSettlementsProvider(eventRef));
    if ((expensesAsync.isLoading && !expensesAsync.hasValue) ||
        (settlementsAsync.isLoading && !settlementsAsync.hasValue)) {
      converging.add(event.id);
    }
  }
  return converging;
});
```

**Step 1.4: Run — expect PASS** (same command).

**Step 1.5: Commit** — `fix(#1106): add groupConvergingEventIdsProvider — loading-skip mirror` (test + provider together; the provider alone changes no behavior).

### Task 2: l10n key

**Files:** `lib/l10n/app_en.arb` (after the `@settleUpBalanceChangedReviewAgain` block, ~`:830`), `lib/l10n/app_ar.arb` (after `settleUpBalanceChangedReviewAgain`, ~`:317`).

**Step 2.1:** en:
```json
  "settleUpBalanceStillSyncing": "Balances are still syncing — try again in a moment.",
```
ar:
```json
  "settleUpBalanceStillSyncing": "لا تزال الأرصدة قيد المزامنة — حاول مرة أخرى بعد لحظات.",
```

**Step 2.2:** `flutter gen-l10n` — expect regenerated files under `lib/l10n/generated/` to include `settleUpBalanceStillSyncing`. Commit rides with Task 3 (the key is dead until the gate lands; committing separately would trip the unused-key surface check).

### Task 3: Screen gate (TDD — the regression tests for the issue itself)

**Files:**
- Test (create): `test/features/groups/group_settle_up_convergence_1106_test.dart`
- Modify: `lib/features/groups/screens/group_settle_up_screen.dart` (`_showRecordPaymentSheet`, two insertions)

**Step 3.1: Write the failing tests** (harness copied from `group_settle_up_revalidation_test.dart`, but with the REAL `groupBalancesProvider` — the convergence window must be modeled honestly through per-event family overrides, per the `*_offline_412_test.dart` never-completing-stream discipline):

Shared fixtures: group `grp-1` (members alice+bob, OMR), `_event('event-1')`/`_event('event-2')` as in Task 1, event-1 expenses `[20.000 paid by alice, equal split]` → Bob owes Alice 10.000; real `SettlementService.withFirestore(fake)` + `GroupSettlementService.withFirestore(fake)` for write counting (`_eventSettlementCount`/`_groupSettlementCount` helpers as in the #719 test).

- **Test A — entry gate (the issue's cold-entry window):** events = `[event-1, event-2]`, event-2 expenses = never-emitting `StreamController`. Pump `GroupSettleUpScreen`, `pumpAndSettle`. Tile shows the understated 10.000 (from event-1 alone). Tap `GroupKeys.settleUpRecordPaymentButton`, pump. **Expect:** `find.byKey(GroupKeys.markAsPaidButton)` findsNothing (sheet refused), `find.textContaining('still syncing')` findsOneWidget, and 0 event + 0 group settlements written.
  *RED today:* the sheet OPENS (markAsPaidButton found) — and confirming it writes 1 understated event settlement.
- **Test B — confirm gate (window opens mid-sheet; proves the understated write lands today):** events override driven by a `StreamController<List<Event>>` seeded `[event-1]`; event-2's family overrides registered up-front (pending expense controller). `pumpAndSettle` (converged), tap record → sheet opens. NOW `eventsController.add([event-1, event-2])`, pump. Tap `GroupKeys.markAsPaidButton`, `pumpAndSettle`. **Expect:** 0 event + 0 group settlements written, `find.textContaining('still syncing')` findsOneWidget.
  *RED today:* the #719 fresh re-read returns the still-converging basis (event-2 silently omitted), passes, and 1 event settlement is written.
- **Test C — control (no false block):** events = `[event-1]` only, everything emitted. Tap record → confirm. **Expect:** 1 event settlement written (decomposed leg), no 'still syncing' text, `settleUpRecorded` copy shown. Pins that the gate cannot over-block a converged basis.

**Step 3.2: Run — expect FAIL** on A and B exactly as annotated (C passes — it must, before and after):
`flutter test test/features/groups/group_settle_up_convergence_1106_test.dart`
Paste the failing output into the PR (RED evidence, #329).

**Step 3.3: Implement the gate** — two insertions in `_showRecordPaymentSheet`:

(a) At the top of the method body (before the `fromDisplayName` line, `:555`):

```dart
    // Steps ≥2 of the stepped walk re-enter here in the async continuation
    // after the previous sheet closed — the context may be disposed (Gate R1).
    if (!context.mounted) {
      return const _StepOutcome(_StepOutcomeKind.cancelled);
    }
    // #1106: the live balance provider proceeds-on-partial while per-event
    // streams deliver their FIRST snapshot (the #244 loading-skip, deliberately
    // kept for display). A sheet opened inside that window carries an
    // understated suggestion the #719 re-read below can never catch (an
    // understated amount passes a later-converged higher outstanding). Refuse
    // to open — write-time only; the screen itself stays proceed-on-partial.
    if (ref
        .read(groupConvergingEventIdsProvider(widget.groupId))
        .isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.settleUpBalanceStillSyncing)),
      );
      return const _StepOutcome(_StepOutcomeKind.invalid);
    }
```

(Gate R1 union applied: the adversary's [P2] — the spec originally claimed gate (a) "runs synchronously from the tap", which is false for stepped-walk iterations ≥2; the mounted guard resolves it, returning `cancelled` so the walk stops quietly, mirroring the sheet-dismissed path.)

(b) Inside the #719 revalidation block, immediately before `var writeBalances = balancesData;` / `final fresh = ...` (`:626-627`):

```dart
    // #1106 (confirm-time twin of the entry gate): a convergence window can
    // OPEN while the sheet is up (another device adds an event — its streams
    // have no first snapshot here yet). The fresh re-read below would silently
    // omit that event's money and revalidate against itself — refuse instead.
    if (ref
        .read(groupConvergingEventIdsProvider(widget.groupId))
        .isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.settleUpBalanceStillSyncing)),
      );
      return const _StepOutcome(_StepOutcomeKind.invalid);
    }
```

(Mounted-ness: gate (a) carries its own guard above — the stepped walk re-enters this method after awaits; gate (b) sits after the existing `!context.mounted` early-return at `:577`.)

**Step 3.4: Run — expect PASS** (A, B, C green). Re-run Task 1's provider tests, the sibling suites `group_settle_up_revalidation_test.dart`, `group_settle_up_decompose_test.dart`, `group_settle_up_atomic_929_test.dart`, `group_settle_up_dedup_1093_test.dart`, `group_settle_up_screen_test.dart` — expect all green (the gate must not trip any converged-basis fixture; those suites override `groupBalancesProvider` and either override the per-event families with emitting streams or leave them erroring — errors are NOT converging, so no false block).

**Step 3.5: Commit** — `fix(#1106): refuse settle-up RECORD while balance basis is converging` (screen + l10n + generated files + tests).

### Task 4: Verify, document, ship

**Step 4.1:** `flutter analyze` — clean. `bash tool/check_theme_purity.sh` — clean (no new colors; snackbars use defaults).
**Step 4.2:** `flutter test` — full suite green.
**Step 4.3:** CLAUDE.md — append one line to the Key Invariants soft-delete/#244-adjacent area (the settle-up decomposition bullet): the RECORD path refuses a converging basis via `groupConvergingEventIdsProvider` (#1106); display stays proceed-on-partial (#244) — don't wire the converging set into the balance provider or the banner.
**Step 4.4:** PR: branch `fix/1106-settle-up-record-convergence-guard`, full-branch diff review (`git diff main...HEAD`), body = summary + test plan + RED output, `Closes #1106`, `Spec:` line pointing at this file. Then `/automerge` (Gate-category: money screen — fresh reviewer + refuter).

## Test plan (summary)

| Layer | File | Pins |
|---|---|---|
| Provider unit | `test/features/groups/providers/group_converging_event_ids_1106_test.dart` | converging set contents; window closes on first snapshot; error≠converging orthogonality; settlement-side OR; **#244 display invariant (data-while-converging)** |
| Widget regression | `test/features/groups/group_settle_up_convergence_1106_test.dart` | A: entry gate blocks sheet + zero writes (cold-entry window); B: confirm gate blocks mid-sheet window + zero writes; C: converged basis records exactly one leg (no false block) |
| Existing suites | `group_settle_up_*_test.dart`, `group_balance_provider_*` | no regressions; #719 both tests unchanged |

No deploy: client-only. No `pending_deploy.sh` interaction.
